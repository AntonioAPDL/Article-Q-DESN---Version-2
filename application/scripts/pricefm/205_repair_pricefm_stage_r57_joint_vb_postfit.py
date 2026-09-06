#!/usr/bin/env python3
"""Repair artifact-complete Stage-R57 cases without refitting any model."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys

import joblib
import numpy as np
import pandas as pd
import yaml

from pricefm_common import load_config, parse_bool, pricefm_block, write_json
from pricefm_metrics import inverse_scale_y, metric_dict


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
GRID = DATA / "experiment_grids/pricefm_stage_r57_joint_vb_20260824"
OUTPUT = DATA / "authoritative/pricefm_stage_r57_joint_vb_postfit_repair_20260824"
HEAVY_NAMES = {
    "X_train.csv", "X_val.csv", "y_train.csv", "y_val.csv",
    "rows_train.csv", "rows_val.csv", "rows_all.csv",
}
FIT_ARTIFACTS = {
    "model_predictions_scaled.csv", "model_trace_summary.csv",
    "model_parameter_summary.csv", "crossing_diagnostics.csv",
    "joint_vb_initialization.rds",
}
GENERIC_METRIC_ARTIFACTS = {
    "metric_summary.csv", "metric_by_horizon.csv", "metric_by_horizon_group.csv",
    "predictions_with_naive_scaled.csv",
}
CHANGE_COLUMNS = (
    "max_beta_change", "max_gamma_change", "max_sigma_change", "max_qhat_change",
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=GRID / "launch_manifest.csv")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--python-bin", type=Path, default=Path(sys.executable))
    p.add_argument(
        "--summarizer", type=Path,
        default=Path(__file__).with_name("09_summarize_desn_model_smoke.py"),
    )
    p.add_argument("--case-ids", default="", help="Optional comma-separated case IDs")
    p.add_argument("--skip-summarizer", type=parse_bool, default=False)
    p.add_argument("--cleanup-heavy", type=parse_bool, default=False)
    p.add_argument("--require-original-metrics", type=parse_bool, default=True)
    p.add_argument("--workers", type=int, default=1)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def atomic_csv(frame: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    frame.to_csv(tmp, index=False)
    tmp.replace(path)


def atomic_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")
    tmp.replace(path)


def pava(values: np.ndarray) -> np.ndarray:
    """Equal-weight PAVA, matching stats::isoreg on an ordered tau grid."""
    y = np.asarray(values, dtype=float)
    if y.ndim != 1 or not np.isfinite(y).all():
        raise ValueError("PAVA requires one finite vector")
    levels: list[float] = []
    weights: list[int] = []
    for value in y:
        levels.append(float(value))
        weights.append(1)
        while len(levels) > 1 and levels[-2] > levels[-1]:
            weight = weights[-2] + weights[-1]
            level = (weights[-2] * levels[-2] + weights[-1] * levels[-1]) / weight
            levels[-2:] = [level]
            weights[-2:] = [weight]
    return np.asarray([level for level, weight in zip(levels, weights) for _ in range(weight)])


def pava_rows(values: np.ndarray) -> np.ndarray:
    """Vectorized equal-weight isotonic regression across many short rows."""
    y = np.asarray(values, dtype=float)
    if y.ndim != 2 or y.shape[1] < 1 or not np.isfinite(y).all():
        raise ValueError("Row-wise PAVA requires one finite matrix")
    prefix = np.concatenate([np.zeros((len(y), 1)), np.cumsum(y, axis=1)], axis=1)
    width = y.shape[1]
    interval_means = {
        (start, end): (prefix[:, end + 1] - prefix[:, start]) / (end - start + 1)
        for start in range(width) for end in range(start, width)
    }
    fitted = np.empty_like(y)
    for index in range(width):
        lower_envelopes = []
        for start in range(index + 1):
            upper = np.column_stack([
                interval_means[(start, end)] for end in range(index, width)
            ])
            lower_envelopes.append(upper.min(axis=1))
        fitted[:, index] = np.column_stack(lower_envelopes).max(axis=1)
    return fitted


def runtime_config(path: Path) -> dict:
    payload = yaml.safe_load(path.read_text())
    cfg = None
    if isinstance(payload, dict):
        cfg = payload.get("pricefm_stage_r57_joint_vb") or payload.get("pricefm_stage_r61_joint_mechanism")
    if not isinstance(cfg, dict):
        raise RuntimeError(f"Invalid joint runtime config: {path}")
    return cfg


def rhs_scale_metadata(cfg: dict) -> dict:
    """Normalize legacy scalar and split joint-RHS scale contracts."""
    rhs_control = cfg.get("rhs_control")
    if isinstance(rhs_control, dict):
        required = {"anchor_tau0", "innovation_tau0"}
        missing = sorted(required - set(rhs_control))
        if missing:
            raise RuntimeError(f"Joint RHS control lacks fields: {missing}")
        anchor_tau0 = float(rhs_control["anchor_tau0"])
        innovation_tau0 = float(rhs_control["innovation_tau0"])
        normalized_control = dict(rhs_control)
    elif "tau0" in cfg:
        anchor_tau0 = innovation_tau0 = float(cfg["tau0"])
        normalized_control = {
            "anchor_tau0": anchor_tau0,
            "innovation_tau0": innovation_tau0,
        }
    else:
        raise RuntimeError("Joint runtime config lacks scalar or split RHS tau0 controls")
    if not all(math.isfinite(value) and value > 0 for value in (anchor_tau0, innovation_tau0)):
        raise RuntimeError("Joint RHS tau0 controls must be finite and positive")
    return {
        # Retain the scalar alias for legacy readers while preserving the split contract.
        "tau0": anchor_tau0,
        "anchor_tau0": anchor_tau0,
        "innovation_tau0": innovation_tau0,
        "rhs_control": normalized_control,
    }


def trace_health(path: Path, tol: float) -> dict:
    trace = pd.read_csv(path)
    columns = [name for name in CHANGE_COLUMNS if name in trace.columns]
    if trace.empty or not columns:
        raise RuntimeError(f"Trace lacks convergence columns: {path}")
    values = trace[columns].apply(pd.to_numeric, errors="coerce")
    if not np.isfinite(values.to_numpy()).all():
        raise RuntimeError(f"Trace contains nonfinite convergence values: {path}")
    row_max = values.max(axis=1)
    final = float(row_max.iloc[-1])
    slope = float((row_max.iloc[-1] - row_max.iloc[-5]) / 4) if len(row_max) >= 5 else math.nan
    return {
        "iterations": int(len(trace)), "final_max_change": final,
        "last5_change_slope": slope, "converged": bool(final < float(tol)),
    }


def crossing_health(path: Path) -> dict:
    frame = pd.read_csv(path)
    pairs = pd.to_numeric(frame.n_crossing_pairs, errors="raise").astype(int)
    magnitude = pd.to_numeric(frame.max_crossing_magnitude, errors="raise")
    return {
        "rows": int(len(frame)), "crossing_rows": int((pairs > 0).sum()),
        "crossing_pairs": int(pairs.sum()),
        "max_crossing_magnitude": float(magnitude.max()) if len(frame) else 0.0,
    }


def count_csv_rows(path: Path, header: bool) -> int:
    with path.open("rb") as handle:
        count = sum(1 for _ in handle)
    return max(0, count - int(header))


def csv_columns(path: Path) -> int:
    with path.open() as handle:
        return len(handle.readline().rstrip("\n").split(","))


def existing_summary(path: Path) -> dict:
    try:
        return json.loads(path.read_text()) if path.is_file() else {}
    except (OSError, json.JSONDecodeError):
        return {}


def preserved_fit_metadata(model: Path, cfg: dict, summary: dict) -> dict:
    """Retain or reconstruct compact fit dimensions after adapter cleanup."""
    method = pd.read_csv(model / "model_method_summary.csv")
    method_row = method.iloc[0] if len(method) else pd.Series(dtype=object)

    def finite_value(value):
        try:
            numeric = float(value)
        except (TypeError, ValueError):
            return None
        return numeric if math.isfinite(numeric) else None

    n_train = finite_value(summary.get("n_train"))
    if n_train is None:
        n_train = finite_value(method_row.get("n_train"))
    n_slopes = finite_value(summary.get("n_slopes"))
    if n_slopes is None:
        n_slopes = finite_value(method_row.get("n_features"))
    n_validation = finite_value(summary.get("n_validation"))
    if n_validation is None:
        raw = pd.read_csv(
            model / "model_predictions_scaled.csv", usecols=["origin_id", "horizon"],
        )
        n_validation = float(len(raw.drop_duplicates(["origin_id", "horizon"])))
    joint_dimension = finite_value(summary.get("joint_dimension"))
    if joint_dimension is None and n_slopes is not None:
        joint_dimension = n_slopes * len(cfg["quantiles"])
    elapsed = finite_value(summary.get("elapsed_seconds"))
    if elapsed is None:
        elapsed = finite_value(method_row.get("train_seconds"))
    values = {
        "n_train": n_train, "n_validation": n_validation, "n_slopes": n_slopes,
        "joint_dimension": joint_dimension, "elapsed_seconds": elapsed,
    }
    return {
        key: int(value) if key != "elapsed_seconds" else float(value)
        for key, value in values.items() if value is not None
    }


def method_summary(cfg: dict, model: Path, adapter: Path, health: dict) -> pd.DataFrame:
    old = existing_summary(model / "job_summary.json")
    initialization_mode = str(cfg.get("initialization", {}).get("mode", "cold"))
    n_train = old.get("n_train")
    n_features = old.get("n_slopes")
    if n_train is None and (adapter / "y_train.csv").is_file():
        n_train = count_csv_rows(adapter / "y_train.csv", header=False)
    if n_features is None and (adapter / "X_train.csv").is_file():
        n_features = csv_columns(adapter / "X_train.csv") - 1
    elapsed = old.get("elapsed_seconds")
    elapsed_source = "runner"
    if elapsed is None and (adapter / "adapter_manifest.json").is_file():
        elapsed = max(
            0.0,
            (model / "joint_vb_initialization.rds").stat().st_mtime
            - (adapter / "adapter_manifest.json").stat().st_mtime,
        )
        elapsed_source = "artifact_mtime_approximation"
    return pd.DataFrame([{
        "method_id": cfg["method_id"], "model_family": "joint_qdesn_readout",
        "likelihood_family": cfg["likelihood_family"], "prior_family": "rhs_ns",
        "target_label": "joint_seven_quantile_validation",
        "preserves_full_data_target": True, "approximate": True,
        "chunking_mode": "joint_vb_dense", "converged": health["converged"],
        "iter": health["iterations"], "train_seconds": elapsed,
        "train_seconds_source": elapsed_source, "n_train": n_train,
        "n_features": n_features, "warm_start_enabled": initialization_mode != "cold",
        "warm_start_strategy": initialization_mode,
    }])


def contract_predictions(model: Path, cfg: dict) -> tuple[pd.DataFrame, pd.DataFrame, dict]:
    raw = pd.read_csv(model / "model_predictions_scaled.csv")
    required = {"method_id", "split", "origin_id", "horizon", "tau", "pred_scaled"}
    if required - set(raw.columns):
        raise RuntimeError(f"Raw predictions lack columns: {sorted(required - set(raw.columns))}")
    if set(raw.split.astype(str)) != {"val"}:
        raise RuntimeError("R57 postfit repair refuses predictions outside validation")
    taus = np.asarray(cfg["quantiles"], dtype=float)
    if raw.duplicated(["origin_id", "horizon", "tau"]).any():
        raise RuntimeError("Raw predictions contain duplicate origin/horizon/tau rows")
    wide = raw.pivot(index=["origin_id", "horizon"], columns="tau", values="pred_scaled")
    observed = np.asarray(wide.columns, dtype=float)
    if len(observed) != len(taus) or not np.allclose(observed, taus, atol=1e-12, rtol=0):
        raise RuntimeError("Raw predictions do not contain the declared quantile grid")
    wide = wide.reindex(columns=list(taus))
    if wide.isna().any().any() or len(raw) != len(wide) * len(taus):
        raise RuntimeError("Raw predictions do not form a rectangular quantile grid")
    raw_values = wide.to_numpy(dtype=float)
    fitted = pava_rows(raw_values)
    adjustment = fitted - raw_values
    raw_diff = np.diff(raw_values, axis=1)
    contract_diff = np.diff(fitted, axis=1)
    origins = wide.index.get_level_values("origin_id").to_numpy()
    horizons = wide.index.get_level_values("horizon").to_numpy(dtype=int)
    method_ids = raw.method_id.astype(str).unique()
    if len(method_ids) != 1:
        raise RuntimeError("R57 repair requires one joint method per case")
    contract = pd.DataFrame({
        "method_id": np.repeat(method_ids[0], len(wide) * len(taus)),
        "prediction_role": np.repeat("monotone_contract", len(wide) * len(taus)),
        "split": np.repeat("val", len(wide) * len(taus)),
        "origin_id": np.repeat(origins, len(taus)),
        "horizon": np.repeat(horizons, len(taus)),
        "tau": np.tile(taus, len(wide)),
        "pred_scaled_raw": raw_values.ravel(),
        "pred_scaled": fitted.ravel(),
        "contract_adjustment": adjustment.ravel(),
    })
    diag = pd.DataFrame({
        "origin_id": origins, "horizon": horizons,
        "raw_crossing_pairs": (raw_diff < -1e-10).sum(axis=1).astype(int),
        "contract_crossing_pairs": (contract_diff < -1e-10).sum(axis=1).astype(int),
        "adjusted_quantiles": (np.abs(adjustment) > 1e-10).sum(axis=1).astype(int),
        "max_abs_adjustment": np.max(np.abs(adjustment), axis=1),
        "mean_abs_adjustment": np.mean(np.abs(adjustment), axis=1),
    })
    summary = {
        "validation_rows": int(len(diag)),
        "raw_crossing_rows": int((diag.raw_crossing_pairs > 0).sum()),
        "raw_crossing_pairs": int(diag.raw_crossing_pairs.sum()),
        "contract_crossing_rows": int((diag.contract_crossing_pairs > 0).sum()),
        "contract_crossing_pairs": int(diag.contract_crossing_pairs.sum()),
        "adjusted_rows": int((diag.adjusted_quantiles > 0).sum()),
        "adjusted_quantiles": int(diag.adjusted_quantiles.sum()),
        "max_abs_adjustment": float(diag.max_abs_adjustment.max()),
        "mean_abs_adjustment": float(np.average(diag.mean_abs_adjustment)),
    }
    return contract, diag, summary


def prediction_cube(pred: pd.DataFrame, rows: pd.DataFrame, taus: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    rows = rows.sort_values(["origin_id", "horizon"])
    truth = rows.pivot(index="origin_id", columns="horizon", values="y_scaled")
    pivot = pred.pivot_table(
        index="origin_id", columns=["horizon", "tau"], values="pred_scaled", aggfunc="first",
    )
    origins = truth.index
    horizons = list(truth.columns)
    blocks = []
    for horizon in horizons:
        block = pivot.xs(horizon, axis=1, level="horizon").reindex(
            index=origins, columns=list(taus),
        )
        if block.isna().any().any():
            raise RuntimeError(f"Prediction grid is incomplete for horizon {horizon}")
        blocks.append(block.to_numpy(dtype=float))
    return truth.to_numpy(dtype=float), np.stack(blocks, axis=1)


def load_scaler(smoke: dict):
    data_cfg = load_config(smoke["data_config"])
    spec = pricefm_block(data_cfg)
    processed = Path(spec["processed_dir"])
    if not processed.is_absolute():
        processed = ARTIFACT_REPO / processed
    path = processed / "scalers" / f"fold_{int(smoke['fold'])}" / "per_region_separate_xy_scalers.joblib"
    return joblib.load(path)[smoke["region"]]["y_scaler"]


def contract_metrics(
    model: Path, adapter: Path, cfg: dict, smoke: dict,
    raw: pd.DataFrame, contract: pd.DataFrame, require_original: bool,
) -> pd.DataFrame:
    rows = pd.read_csv(adapter / "rows_val.csv")
    taus = np.asarray(cfg["quantiles"], dtype=float)
    truth, raw_cube = prediction_cube(raw, rows, taus)
    _, contract_cube = prediction_cube(contract, rows, taus)
    payload = []
    for role, cube in (("raw_joint", raw_cube), ("monotone_contract", contract_cube)):
        payload.append({
            "method_id": cfg["method_id"], "prediction_role": role,
            "split": "val", "unit": "scaled", **metric_dict(truth, cube, taus),
        })
    try:
        scaler = load_scaler(smoke)
    except Exception:
        if require_original:
            raise
    else:
        truth_orig = inverse_scale_y(truth, scaler)
        for role, cube in (("raw_joint", raw_cube), ("monotone_contract", contract_cube)):
            payload.append({
                "method_id": cfg["method_id"], "prediction_role": role,
                "split": "val", "unit": "original",
                **metric_dict(truth_orig, inverse_scale_y(cube, scaler), taus),
            })
    return pd.DataFrame(payload)


def source_manifest(paths: dict[str, Path]) -> pd.DataFrame:
    rows = []
    for label, path in paths.items():
        if path.is_file():
            rows.append({
                "label": label, "path": str(path.resolve()), "sha256": sha256(path),
                "bytes": int(path.stat().st_size),
            })
    return pd.DataFrame(rows)


def cleanup_adapter(adapter: Path) -> list[str]:
    removed = []
    if not adapter.is_dir():
        return removed
    for path in sorted(adapter.iterdir()):
        if path.name in HEAVY_NAMES and path.is_file():
            path.unlink()
            removed.append(path.name)
    return removed


def adapter_cleanup_complete(adapter: Path) -> bool:
    return not any((adapter / name).is_file() for name in HEAVY_NAMES)


def reusable_generic_metrics(model: Path, method_id: str) -> bool:
    if not all((model / name).is_file() for name in GENERIC_METRIC_ARTIFACTS):
        return False
    try:
        for name in GENERIC_METRIC_ARTIFACTS:
            if pd.read_csv(model / name, nrows=1).empty:
                return False
        frame = pd.read_csv(model / "metric_summary.csv")
    except Exception:
        return False
    rows = frame[
        frame.method_id.astype(str).eq(str(method_id))
        & frame.split.astype(str).eq("val")
        & frame.unit.astype(str).eq("original")
    ]
    return len(rows) == 1 and math.isfinite(float(rows.iloc[0].AQL))


def fit_is_terminal(model: Path) -> bool:
    """Reject a case while its runner can still be writing postfit artifacts."""
    summary_path = model / "job_summary.json"
    summary = existing_summary(summary_path)
    if summary.get("status") not in {"completed", "failed"}:
        return False
    artifacts = [model / name for name in FIT_ARTIFACTS]
    if not all(path.is_file() for path in artifacts):
        return False
    newest_fit_artifact = max(path.stat().st_mtime for path in artifacts)
    return summary_path.stat().st_mtime >= newest_fit_artifact


def already_repaired(model: Path) -> bool:
    summary = existing_summary(model / "job_summary.json")
    required = {
        "model_predictions_contract_scaled.csv", "contract_crossing_diagnostics.csv",
        "raw_contract_metric_summary.csv", "model_method_summary.csv", "source_manifest.csv",
    }
    return (
        summary.get("status") == "completed"
        and summary.get("postfit_repaired") is True
        and all((model / name).is_file() for name in required)
    )


def repair_case(row: pd.Series, args: argparse.Namespace) -> dict:
    case_id = str(row.case_id)
    model = Path(row.output_dir)
    config_path = Path(row.config)
    cfg = runtime_config(config_path)
    adapter = Path(cfg["adapter_dir"])
    if already_repaired(model) and not args.force:
        payload = existing_summary(model / "job_summary.json")
        payload.update(preserved_fit_metadata(model, cfg, payload))
        removed = cleanup_adapter(adapter) if args.cleanup_heavy else []
        previous = list(payload.get("adapter_heavy_files_removed", []))
        payload["adapter_heavy_files_removed"] = sorted(set(previous + removed))
        payload["adapter_cleanup_completed"] = adapter_cleanup_complete(adapter)
        payload["last_repair_code_sha256"] = sha256(Path(__file__).resolve())
        atomic_json(model / "job_summary.json", payload)
        return {
            "case_id": case_id, "region": cfg["region"], "fold": int(cfg["fold"]),
            "status": "already_repaired", "cleanup_files_removed": len(removed),
        }
    missing = sorted(name for name in FIT_ARTIFACTS if not (model / name).is_file())
    if missing:
        return {"case_id": case_id, "status": "not_fit_complete", "missing": ";".join(missing)}
    if not fit_is_terminal(model):
        return {"case_id": case_id, "status": "fit_postprocess_active"}
    fit_summary = existing_summary(model / "job_summary.json")
    smoke_payload = yaml.safe_load(Path(cfg["smoke_config"]).read_text())
    smoke = smoke_payload["pricefm_desn_smoke"]
    if list(smoke.get("splits", [])) != ["train", "val"]:
        raise RuntimeError(f"{case_id}: split firewall is not train/val")
    raw = pd.read_csv(model / "model_predictions_scaled.csv")
    if set(raw.split.astype(str)) != {"val"}:
        raise RuntimeError(f"{case_id}: prediction artifact contains a non-validation split")

    trace = trace_health(model / "model_trace_summary.csv", float(cfg["tol"]))
    raw_crossing = crossing_health(model / "crossing_diagnostics.csv")
    method_path = model / "model_method_summary.csv"
    atomic_csv(method_summary(cfg, model, adapter, trace), method_path)

    if args.skip_summarizer:
        generic_summary_mode = "explicit_test_skip"
    elif reusable_generic_metrics(model, cfg["method_id"]):
        generic_summary_mode = "reused_and_replay_verified"
    else:
        env = os.environ.copy()
        for name in (
            "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
            "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS",
        ):
            env[name] = "1"
        result = subprocess.run(
            [str(args.python_bin), str(args.summarizer), "--smoke-config", str(cfg["smoke_config"]),
             "--run-dir", str(model)],
            text=True, capture_output=True, check=False, env=env,
        )
        (model / "postfit_validation_summary.log").write_text(result.stdout + result.stderr)
        if result.returncode != 0:
            raise RuntimeError(f"{case_id}: validation summarizer exited {result.returncode}")
        generic_summary_mode = "rerun_after_method_metadata_repair"
    if not (model / "metric_summary.csv").is_file():
        raise RuntimeError(f"{case_id}: validation metric summary is absent")

    contract, contract_diag, contract_summary = contract_predictions(model, cfg)
    contract_path = model / "model_predictions_contract_scaled.csv"
    contract_diag_path = model / "contract_crossing_diagnostics.csv"
    atomic_csv(contract, contract_path)
    atomic_csv(contract_diag, contract_diag_path)
    metrics = contract_metrics(
        model, adapter, cfg, smoke, raw, contract, args.require_original_metrics,
    )
    contract_metric_path = model / "raw_contract_metric_summary.csv"
    atomic_csv(metrics, contract_metric_path)

    original = metrics[(metrics.prediction_role == "raw_joint") & (metrics.unit == "original")]
    if args.require_original_metrics and len(original) != 1:
        raise RuntimeError(f"{case_id}: original-scale raw validation metric is not unique")
    generic = pd.read_csv(model / "metric_summary.csv")
    generic_raw = generic[
        generic.method_id.astype(str).eq(str(cfg["method_id"]))
        & generic.split.astype(str).eq("val") & generic.unit.astype(str).eq("original")
    ]
    if args.require_original_metrics:
        if len(generic_raw) != 1 or not math.isclose(
            float(generic_raw.iloc[0].AQL), float(original.iloc[0].AQL), rel_tol=0, abs_tol=1e-9,
        ):
            raise RuntimeError(f"{case_id}: raw metric replay does not match the generic summary")

    checkpoint = model / "joint_vb_initialization.rds"
    manifest_path = model / "source_manifest.csv"
    manifest_sources = {
        "runtime_config": config_path, "source_config": Path(cfg["source_config"]),
        "adapter_manifest": adapter / "adapter_manifest.json",
        "feature_manifest": adapter / "feature_manifest.json",
        "vb_initialization": checkpoint,
        "raw_predictions": model / "model_predictions_scaled.csv",
        "contract_predictions": contract_path,
        "raw_metrics": model / "metric_summary.csv",
        "raw_contract_metrics": contract_metric_path,
        "trace": model / "model_trace_summary.csv",
        "method_summary": method_path,
        "repair_script": Path(__file__).resolve(),
    }
    initialization_cfg = cfg.get("initialization", {})
    if initialization_cfg.get("checkpoint"):
        manifest_sources["initialization_checkpoint"] = Path(initialization_cfg["checkpoint"])
    manifest = source_manifest(manifest_sources)
    atomic_csv(manifest, manifest_path)
    payload = {
        "status": "completed", "fit_completed": True, "postfit_repaired": True,
        "case_id": case_id, "region": cfg["region"], "fold": int(cfg["fold"]),
        "likelihood_family": cfg["likelihood_family"], "method_id": cfg["method_id"],
        "vb_method_id": cfg["vb_method_id"], "quantiles": list(map(float, cfg["quantiles"])),
        **rhs_scale_metadata(cfg), "converged": trace["converged"],
        "stage": cfg.get("stage", "R57"),
        "source_case_id": cfg.get("source_case_id", case_id),
        "initialization_mode": fit_summary.get(
            "initialization_mode", initialization_cfg.get("mode", "cold")
        ),
        "initialization_checkpoint": fit_summary.get(
            "initialization_checkpoint", initialization_cfg.get("checkpoint", "")
        ),
        "initialization_checkpoint_sha256": fit_summary.get(
            "initialization_checkpoint_sha256", initialization_cfg.get("checkpoint_sha256", "")
        ),
        "output_checkpoint_format": fit_summary.get(
            "output_checkpoint_format",
            "pricefm_joint_vb_checkpoint_v2"
            if cfg.get("stage") == "R60"
            else "pricefm_stage_r57_joint_vb_initialization_v1",
        ),
        "iterations": trace["iterations"], "final_max_change": trace["final_max_change"],
        "last5_change_slope": trace["last5_change_slope"],
        "validation_crossing_rows": raw_crossing["crossing_rows"],
        "validation_crossing_pairs": raw_crossing["crossing_pairs"],
        "contract_crossing_rows": contract_summary["contract_crossing_rows"],
        "contract_crossing_pairs": contract_summary["contract_crossing_pairs"],
        "contract_adjusted_rows": contract_summary["adjusted_rows"],
        "contract_max_abs_adjustment": contract_summary["max_abs_adjustment"],
        "contract_mean_abs_adjustment": contract_summary["mean_abs_adjustment"],
        "checkpoint": str(checkpoint), "checkpoint_sha256": sha256(checkpoint),
        "source_manifest": str(manifest_path), "source_manifest_sha256": sha256(manifest_path),
        "repair_execution_script_sha256": sha256(Path(__file__).resolve()),
        "generic_summary_mode": generic_summary_mode,
        "adapter_heavy_files_removed": [],
        "adapter_cleanup_completed": adapter_cleanup_complete(adapter),
        "split_firewall": "train_validation_only", "test_accessed": False,
        "selection_role": "validation_only", "mcmc_launch_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
    }
    payload.update(preserved_fit_metadata(model, cfg, fit_summary))
    # A completed summary is durable before cleanup, so interruption cannot strand
    # a validated case after its reconstructible adapter rows are removed.
    atomic_json(model / "job_summary.json", payload)
    removed = cleanup_adapter(adapter) if args.cleanup_heavy else []
    payload["adapter_heavy_files_removed"] = removed
    payload["adapter_cleanup_completed"] = adapter_cleanup_complete(adapter)
    atomic_json(model / "job_summary.json", payload)
    return {
        "case_id": case_id, "region": cfg["region"], "fold": int(cfg["fold"]),
        "status": "repaired", "converged": trace["converged"],
        "raw_crossing_rows": raw_crossing["crossing_rows"],
        "contract_crossing_rows": contract_summary["contract_crossing_rows"],
        "cleanup_files_removed": len(removed),
    }


def run(args: argparse.Namespace) -> dict:
    manifest = pd.read_csv(args.manifest)
    required = {"case_id", "config", "output_dir"}
    if required - set(manifest.columns):
        raise RuntimeError(f"Manifest lacks columns: {sorted(required - set(manifest.columns))}")
    selected = {value.strip() for value in args.case_ids.split(",") if value.strip()}
    if selected:
        manifest = manifest[manifest.case_id.astype(str).isin(selected)]
    if args.workers < 1:
        raise ValueError("--workers must be positive")

    def guarded(row) -> dict:
        try:
            return repair_case(pd.Series(row._asdict()), args)
        except Exception as error:
            return {"case_id": row.case_id, "status": "repair_failed", "error": str(error)}

    manifest_rows = list(manifest.sort_values(["region", "fold"]).itertuples(index=False))
    if args.workers == 1:
        rows = [guarded(row) for row in manifest_rows]
    else:
        with ThreadPoolExecutor(max_workers=min(args.workers, len(manifest_rows))) as pool:
            rows = list(pool.map(guarded, manifest_rows))
    frame = pd.DataFrame(rows).sort_values("case_id").reset_index(drop=True)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    atomic_csv(frame, args.output_dir / "pricefm_stage_r57_postfit_repair_status.csv")
    counts = frame.status.value_counts().to_dict() if not frame.empty else {}
    summary = {
        "status": "completed_postfit_repair_pass",
        "manifest_cases": int(len(manifest)), "status_counts": {str(k): int(v) for k, v in counts.items()},
        "postfit_complete": int(frame.status.isin(["repaired", "already_repaired"]).sum()),
        "fit_postprocess_active": int(frame.status.eq("fit_postprocess_active").sum()),
        "not_fit_complete": int(frame.status.eq("not_fit_complete").sum()),
        "repair_failures": int(frame.status.eq("repair_failed").sum()),
        "cleanup_heavy": bool(args.cleanup_heavy), "workers": int(args.workers),
        "models_refit": 0,
        "test_opened": False, "mcmc_launch_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
    }
    if summary["repair_failures"]:
        summary["status"] = "completed_postfit_repair_with_failures"
    write_json(args.output_dir / "summary.json", summary)
    return summary


def command_exit_code(summary: dict) -> int:
    """Expose scientific repair failures to shell orchestration."""
    return 1 if int(summary.get("repair_failures", 0)) else 0


if __name__ == "__main__":
    result = run(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    raise SystemExit(command_exit_code(result))
