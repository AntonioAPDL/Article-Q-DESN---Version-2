#!/usr/bin/env python3
"""Repair artifact-complete Stage-R57 cases without refitting any model."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
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


def runtime_config(path: Path) -> dict:
    payload = yaml.safe_load(path.read_text())
    cfg = payload.get("pricefm_stage_r57_joint_vb") if isinstance(payload, dict) else None
    if not isinstance(cfg, dict):
        raise RuntimeError(f"Invalid R57 runtime config: {path}")
    return cfg


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


def method_summary(cfg: dict, model: Path, adapter: Path, health: dict) -> pd.DataFrame:
    old = existing_summary(model / "job_summary.json")
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
        "n_features": n_features, "warm_start_enabled": False,
        "warm_start_strategy": "joint_initialization",
    }])


def contract_predictions(model: Path, cfg: dict) -> tuple[pd.DataFrame, pd.DataFrame, dict]:
    raw = pd.read_csv(model / "model_predictions_scaled.csv")
    required = {"method_id", "split", "origin_id", "horizon", "tau", "pred_scaled"}
    if required - set(raw.columns):
        raise RuntimeError(f"Raw predictions lack columns: {sorted(required - set(raw.columns))}")
    if set(raw.split.astype(str)) != {"val"}:
        raise RuntimeError("R57 postfit repair refuses predictions outside validation")
    taus = np.asarray(cfg["quantiles"], dtype=float)
    pieces = []
    diagnostics = []
    for (origin, horizon), block in raw.groupby(["origin_id", "horizon"], sort=True):
        block = block.sort_values("tau").copy()
        observed = block.tau.to_numpy(dtype=float)
        if len(block) != len(taus) or not np.allclose(observed, taus, atol=1e-12, rtol=0):
            raise RuntimeError(f"Nonrectangular quantile grid for {origin}/{horizon}")
        raw_values = block.pred_scaled.to_numpy(dtype=float)
        fitted = pava(raw_values)
        adjustment = fitted - raw_values
        block["pred_scaled_raw"] = raw_values
        block["pred_scaled"] = fitted
        block["contract_adjustment"] = adjustment
        pieces.append(block)
        raw_diff = np.diff(raw_values)
        contract_diff = np.diff(fitted)
        diagnostics.append({
            "origin_id": origin, "horizon": int(horizon),
            "raw_crossing_pairs": int((raw_diff < -1e-10).sum()),
            "contract_crossing_pairs": int((contract_diff < -1e-10).sum()),
            "adjusted_quantiles": int((np.abs(adjustment) > 1e-10).sum()),
            "max_abs_adjustment": float(np.max(np.abs(adjustment))),
            "mean_abs_adjustment": float(np.mean(np.abs(adjustment))),
        })
    contract = pd.concat(pieces, ignore_index=True)
    diag = pd.DataFrame(diagnostics)
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
        removed = cleanup_adapter(adapter) if args.cleanup_heavy else []
        return {
            "case_id": case_id, "region": cfg["region"], "fold": int(cfg["fold"]),
            "status": "already_repaired", "cleanup_files_removed": len(removed),
        }
    missing = sorted(name for name in FIT_ARTIFACTS if not (model / name).is_file())
    if missing:
        return {"case_id": case_id, "status": "not_fit_complete", "missing": ";".join(missing)}
    if not fit_is_terminal(model):
        return {"case_id": case_id, "status": "fit_postprocess_active"}
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

    if not args.skip_summarizer:
        result = subprocess.run(
            [str(args.python_bin), str(args.summarizer), "--smoke-config", str(cfg["smoke_config"]),
             "--run-dir", str(model)],
            text=True, capture_output=True, check=False,
        )
        (model / "validation_summary.log").write_text(result.stdout + result.stderr)
        if result.returncode != 0:
            raise RuntimeError(f"{case_id}: validation summarizer exited {result.returncode}")
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
    manifest = source_manifest({
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
    })
    atomic_csv(manifest, manifest_path)
    removed = cleanup_adapter(adapter) if args.cleanup_heavy else []

    payload = {
        "status": "completed", "fit_completed": True, "postfit_repaired": True,
        "case_id": case_id, "region": cfg["region"], "fold": int(cfg["fold"]),
        "likelihood_family": cfg["likelihood_family"], "method_id": cfg["method_id"],
        "vb_method_id": cfg["vb_method_id"], "quantiles": list(map(float, cfg["quantiles"])),
        "tau0": float(cfg["tau0"]), "converged": trace["converged"],
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
        "adapter_heavy_files_removed": removed,
        "split_firewall": "train_validation_only", "test_accessed": False,
        "selection_role": "validation_only", "mcmc_launch_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
    }
    write_json(model / "job_summary.json", payload)
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


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
