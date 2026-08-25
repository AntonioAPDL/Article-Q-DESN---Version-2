#!/usr/bin/env python3
"""Read-only PriceFM Stage-R24 postfit calibration materializer."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from pricefm_common import load_config, parse_bool, pricefm_block, repo_path, write_json
from pricefm_full_surface import repo_relative, sha256_file_or_blank
from pricefm_metrics import inverse_scale_y, metric_dict


DEFAULT_CANDIDATE_MANIFEST = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r22c_case_specific_screening_launch_prep_20260709/"
    "pricefm_stage_r22c_postfit_deferred_manifest.csv"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r24_postfit_calibration_materialized_20260709"
)

OUT_READINESS = "pricefm_stage_r24_postfit_readiness.csv"
OUT_PARAMS = "pricefm_stage_r24_postfit_calibration_params.csv"
OUT_PREDICTIONS = "pricefm_stage_r24_postfit_materialized_predictions.csv"
OUT_METRICS = "pricefm_stage_r24_postfit_metric_summary.csv"
OUT_GROUP_METRICS = "pricefm_stage_r24_postfit_metric_by_horizon_group.csv"
OUT_GATE = "pricefm_stage_r24_postfit_candidate_gate.csv"
OUT_NO_LAUNCH_GATES = "pricefm_stage_r24_no_launch_gates.csv"
OUT_SOURCE = "source_manifest.csv"
OUT_REPORT = "pricefm_stage_r24_postfit_calibration_report.md"

SUPPORTED_RULES = {
    "none",
    "baseline_replay",
    "horizon_block_quantile_shift_on_validation",
    "horizon_block_affine_shift_scale_on_validation",
}
QDESN_DEFAULT_METHOD = "qdesn_exal_rhs_ns_exact_chunked"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--candidate-manifest", default=DEFAULT_CANDIDATE_MANIFEST)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--data-config", default="application/config/pricefm_data_pipeline.yaml")
    p.add_argument("--default-method-id", default=QDESN_DEFAULT_METHOD)
    p.add_argument("--primary-unit", choices=["original", "scaled"], default="original")
    p.add_argument("--allow-missing-scalers", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def boolish(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y", "passed", "completed"}


def text_value(value: Any) -> str:
    if value is None:
        return ""
    try:
        if pd.isna(value):
            return ""
    except (TypeError, ValueError):
        pass
    return str(value).strip()


def finite_float(value: Any, default: float = float("nan")) -> float:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return float(default)
    return out if math.isfinite(out) else float(default)


def read_csv_required(path: str | Path, label: str) -> pd.DataFrame:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required CSV: {full}")
    return pd.read_csv(full, low_memory=False)


def require_columns(frame: pd.DataFrame, columns: list[str], label: str) -> None:
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError(f"{label} missing required columns: {missing}")


def write_frame(path: str | Path, frame: pd.DataFrame) -> None:
    full = repo_path(path)
    full.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(full, index=False)


def first_nonblank(row: pd.Series, names: list[str], default: str = "") -> str:
    for name in names:
        if name in row.index and text_value(row.get(name)):
            return text_value(row.get(name))
    return default


def horizon_group(horizon: Any) -> str:
    h = int(float(horizon))
    start = ((h - 1) // 24) * 24 + 1
    end = min(start + 23, 96)
    return f"{start}-{end}"


def normalize_manifest(frame: pd.DataFrame, default_method_id: str) -> pd.DataFrame:
    require_columns(
        frame,
        [
            "region",
            "fold",
            "screening_arm",
            "candidate_family",
            "calibration_rule",
            "uses_existing_predictions",
            "requires_new_fit",
        ],
        "Stage-R24 candidate manifest",
    )
    out = frame.copy()
    if "stage_r22b_candidate_id" not in out.columns:
        out["stage_r22b_candidate_id"] = [f"postfit_candidate_{i+1:04d}" for i in range(out.shape[0])]
    if "stage_r22b_case_id" not in out.columns:
        out["stage_r22b_case_id"] = out.apply(lambda r: f"case_{r['region']}_f{int(r['fold'])}", axis=1)
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    out["candidate_id"] = out["stage_r22b_candidate_id"].astype(str)
    out["source_method_id"] = out.apply(
        lambda row: first_nonblank(row, ["source_method_id", "method_id", "existing_method_id"], default_method_id),
        axis=1,
    )
    for col in ["existing_prediction_path", "existing_metric_summary_path", "row_source_val", "row_source_test"]:
        if col not in out.columns:
            out[col] = ""
    return out


def infer_row_path(row: pd.Series, split: str) -> str:
    explicit = first_nonblank(row, [f"row_source_{split}", "row_source"])
    if explicit:
        return explicit
    metric = text_value(row.get("existing_metric_summary_path"))
    pred = text_value(row.get("existing_prediction_path"))
    if metric:
        return repo_relative(repo_path(metric).parent.parent / "adapter" / f"rows_{split}.csv")
    if pred:
        return repo_relative(repo_path(pred).parent.parent / "adapter" / f"rows_{split}.csv")
    return ""


def readiness(manifest: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for _, row in manifest.iterrows():
        pred_path = text_value(row.get("existing_prediction_path"))
        metric_path = text_value(row.get("existing_metric_summary_path"))
        val_rows = infer_row_path(row, "val")
        test_rows = infer_row_path(row, "test")
        rule = text_value(row.get("calibration_rule"))
        pred_exists = bool(pred_path and repo_path(pred_path).exists())
        metric_exists = bool(metric_path and repo_path(metric_path).exists())
        val_rows_exists = bool(val_rows and repo_path(val_rows).exists())
        test_rows_exists = bool(test_rows and repo_path(test_rows).exists())
        uses_existing = boolish(row.get("uses_existing_predictions"))
        requires_new_fit = boolish(row.get("requires_new_fit"))
        if rule not in SUPPORTED_RULES:
            status = "blocked_unsupported_calibration_rule"
        elif not uses_existing or requires_new_fit:
            status = "blocked_not_existing_prediction_postfit"
        elif pred_exists and val_rows_exists and test_rows_exists:
            status = "ready"
        elif not pred_path and not metric_path:
            status = "blocked_missing_existing_prediction_and_metric_paths"
        else:
            status = "blocked_missing_prediction_or_row_artifacts"
        rows.append(
            {
                "candidate_id": row["candidate_id"],
                "stage_r22b_case_id": row["stage_r22b_case_id"],
                "region": row["region"],
                "fold": int(row["fold"]),
                "source_method_id": row["source_method_id"],
                "candidate_family": row["candidate_family"],
                "calibration_rule": rule,
                "uses_existing_predictions": uses_existing,
                "requires_new_fit": requires_new_fit,
                "existing_prediction_path": pred_path,
                "existing_prediction_exists": pred_exists,
                "existing_metric_summary_path": metric_path,
                "existing_metric_summary_exists": metric_exists,
                "row_source_val": val_rows,
                "row_source_val_exists": val_rows_exists,
                "row_source_test": test_rows,
                "row_source_test_exists": test_rows_exists,
                "readiness_status": status,
            }
        )
    return pd.DataFrame(rows).sort_values(["readiness_status", "region", "fold", "candidate_id"]).reset_index(drop=True)


def load_prediction_truth(row: pd.Series, ready: pd.Series, split: str) -> pd.DataFrame:
    pred = read_csv_required(ready["existing_prediction_path"], f"{row['candidate_id']} predictions")
    truth = read_csv_required(ready[f"row_source_{split}"], f"{row['candidate_id']} rows {split}")
    require_columns(pred, ["method_id", "split", "origin_id", "horizon", "tau", "pred_scaled"], "predictions")
    require_columns(truth, ["origin_id", "horizon", "y_scaled"], "row truth")
    sub = pred[
        pred["method_id"].astype(str).eq(str(row["source_method_id"]))
        & pred["split"].astype(str).eq(str(split))
    ].copy()
    if sub.empty:
        raise ValueError(f"no prediction rows for {row['candidate_id']} method={row['source_method_id']} split={split}")
    merged = sub.merge(
        truth[["origin_id", "horizon", "y_scaled"]],
        on=["origin_id", "horizon"],
        how="left",
        validate="many_to_one",
    )
    if merged["y_scaled"].isna().any():
        raise ValueError(f"prediction/truth alignment failed for {row['candidate_id']} split={split}")
    merged["horizon_group"] = merged["horizon"].map(horizon_group)
    return merged


def fit_group_params(frame: pd.DataFrame, rule: str) -> dict[str, float]:
    pred = pd.to_numeric(frame["pred_scaled"], errors="coerce").to_numpy(dtype=float)
    truth = pd.to_numeric(frame["y_scaled"], errors="coerce").to_numpy(dtype=float)
    ok = np.isfinite(pred) & np.isfinite(truth)
    pred = pred[ok]
    truth = truth[ok]
    if pred.size == 0:
        raise ValueError("cannot fit postfit calibration with no finite validation rows")
    if rule in {"none", "baseline_replay"}:
        return {"intercept": 0.0, "slope": 1.0, "shift": 0.0, "fallback_used": False}
    shift = float(np.median(truth - pred))
    if rule == "horizon_block_quantile_shift_on_validation":
        return {"intercept": shift, "slope": 1.0, "shift": shift, "fallback_used": False}
    if rule == "horizon_block_affine_shift_scale_on_validation":
        if pred.size < 3 or float(np.nanstd(pred)) <= 1.0e-10:
            return {"intercept": shift, "slope": 1.0, "shift": shift, "fallback_used": True}
        slope, intercept = np.polyfit(pred, truth, deg=1)
        if not np.isfinite(slope) or slope <= 0.0 or not np.isfinite(intercept):
            return {"intercept": shift, "slope": 1.0, "shift": shift, "fallback_used": True}
        slope = float(np.clip(slope, 0.25, 4.0))
        return {"intercept": float(intercept), "slope": slope, "shift": shift, "fallback_used": False}
    raise ValueError(f"unsupported calibration rule: {rule}")


def build_params(manifest: pd.DataFrame, ready: pd.DataFrame) -> pd.DataFrame:
    ready_map = ready.set_index("candidate_id", drop=False)
    rows = []
    for _, cand in manifest.iterrows():
        if cand["candidate_id"] not in ready_map.index:
            continue
        status = ready_map.loc[cand["candidate_id"]]
        if str(status["readiness_status"]) != "ready":
            continue
        val = load_prediction_truth(cand, status, "val")
        rule = text_value(cand["calibration_rule"])
        for (group, tau), part in val.groupby(["horizon_group", "tau"], sort=True):
            params = fit_group_params(part, rule)
            rows.append(
                {
                    "candidate_id": cand["candidate_id"],
                    "stage_r22b_case_id": cand["stage_r22b_case_id"],
                    "region": cand["region"],
                    "fold": int(cand["fold"]),
                    "source_method_id": cand["source_method_id"],
                    "calibration_rule": rule,
                    "horizon_group": group,
                    "tau": float(tau),
                    "n_validation_rows": int(part.shape[0]),
                    **params,
                    "uses_validation_only": True,
                    "uses_test_for_calibration": False,
                }
            )
    cols = [
        "candidate_id",
        "stage_r22b_case_id",
        "region",
        "fold",
        "source_method_id",
        "calibration_rule",
        "horizon_group",
        "tau",
        "n_validation_rows",
        "intercept",
        "slope",
        "shift",
        "fallback_used",
        "uses_validation_only",
        "uses_test_for_calibration",
    ]
    if not rows:
        return pd.DataFrame(columns=cols)
    return pd.DataFrame(rows)[cols].sort_values(["region", "fold", "candidate_id", "horizon_group", "tau"]).reset_index(drop=True)


def materialize_predictions(manifest: pd.DataFrame, ready: pd.DataFrame, params: pd.DataFrame) -> pd.DataFrame:
    cols = [
        "candidate_id",
        "stage_r22b_case_id",
        "region",
        "fold",
        "source_method_id",
        "calibration_rule",
        "split",
        "origin_id",
        "horizon",
        "horizon_group",
        "tau",
        "pred_scaled",
        "postfit_intercept",
        "postfit_slope",
        "pred_scaled_materialized",
        "y_scaled",
    ]
    if params.empty:
        return pd.DataFrame(columns=cols)
    ready_map = ready.set_index("candidate_id", drop=False)
    param_map = params.set_index(["candidate_id", "horizon_group", "tau"], drop=False)
    pieces = []
    for _, cand in manifest.iterrows():
        cid = cand["candidate_id"]
        if cid not in ready_map.index:
            continue
        status = ready_map.loc[cid]
        if str(status["readiness_status"]) != "ready":
            continue
        for split in ["val", "test"]:
            pred = load_prediction_truth(cand, status, split)
            pred["candidate_id"] = cid
            pred["stage_r22b_case_id"] = cand["stage_r22b_case_id"]
            pred["region"] = cand["region"]
            pred["fold"] = int(cand["fold"])
            pred["source_method_id"] = cand["source_method_id"]
            pred["calibration_rule"] = cand["calibration_rule"]
            intercepts = []
            slopes = []
            for _, row in pred.iterrows():
                key = (cid, row["horizon_group"], float(row["tau"]))
                if key not in param_map.index:
                    raise ValueError(f"missing calibration params for {key}")
                p = param_map.loc[key]
                intercepts.append(float(p["intercept"]))
                slopes.append(float(p["slope"]))
            pred["postfit_intercept"] = intercepts
            pred["postfit_slope"] = slopes
            pred["pred_scaled_materialized"] = pred["postfit_intercept"] + pred["postfit_slope"] * pd.to_numeric(
                pred["pred_scaled"], errors="coerce"
            )
            pieces.append(
                pred[
                    [
                        "candidate_id",
                        "stage_r22b_case_id",
                        "region",
                        "fold",
                        "source_method_id",
                        "calibration_rule",
                        "split",
                        "origin_id",
                        "horizon",
                        "horizon_group",
                        "tau",
                        "pred_scaled",
                        "postfit_intercept",
                        "postfit_slope",
                        "pred_scaled_materialized",
                        "y_scaled",
                    ]
                ]
            )
    return pd.concat(pieces, ignore_index=True)[cols] if pieces else pd.DataFrame(columns=cols)


def metric_arrays(frame: pd.DataFrame) -> tuple[np.ndarray, np.ndarray, list[int], list[float]]:
    quantiles = sorted(float(x) for x in frame["tau"].unique())
    truth = frame.drop_duplicates(["origin_id", "horizon"]).pivot(
        index="origin_id", columns="horizon", values="y_scaled"
    )
    pred = frame.pivot_table(
        index="origin_id",
        columns=["horizon", "tau"],
        values="pred_scaled_materialized",
        aggfunc="first",
    )
    origins = sorted(truth.index)
    horizons = sorted(int(h) for h in frame["horizon"].unique())
    y = truth.loc[origins, horizons].to_numpy()
    blocks = [pred[h].loc[origins, quantiles].to_numpy() for h in horizons]
    return y, np.stack(blocks, axis=1), horizons, quantiles


def load_y_scalers(data_config: str, manifest: pd.DataFrame, allow_missing: bool) -> dict[tuple[str, int], Any]:
    if manifest.empty:
        return {}
    try:
        import joblib
    except Exception:
        if allow_missing:
            return {}
        raise
    cfg = load_config(data_config)
    spec = pricefm_block(cfg)
    out: dict[tuple[str, int], Any] = {}
    for region, fold in sorted({(str(r), int(f)) for r, f in zip(manifest["region"], manifest["fold"])}):
        path = repo_path(Path(spec["processed_dir"]) / "scalers" / f"fold_{fold}" / "per_region_separate_xy_scalers.joblib")
        if not path.exists():
            if allow_missing:
                continue
            raise FileNotFoundError(f"missing y scaler for region={region}, fold={fold}: {path}")
        scalers = joblib.load(path)
        out[(region, fold)] = scalers[str(region)]["y_scaler"]
    return out


def compute_metrics(predictions: pd.DataFrame, y_scalers: dict[tuple[str, int], Any]) -> tuple[pd.DataFrame, pd.DataFrame]:
    if predictions.empty:
        return pd.DataFrame(), pd.DataFrame()
    rows = []
    group_rows = []
    for (candidate_id, split), df in predictions.groupby(["candidate_id", "split"], sort=True):
        first = df.iloc[0]
        y_scaled, pred_scaled, horizons, quantiles = metric_arrays(df)
        units = [("scaled", y_scaled, pred_scaled)]
        scaler = y_scalers.get((str(first["region"]), int(first["fold"])))
        if scaler is not None:
            units.append(("original", inverse_scale_y(y_scaled, scaler), inverse_scale_y(pred_scaled, scaler)))
        for unit, y, pred in units:
            rows.append(
                {
                    "candidate_id": candidate_id,
                    "stage_r22b_case_id": first["stage_r22b_case_id"],
                    "region": first["region"],
                    "fold": int(first["fold"]),
                    "source_method_id": first["source_method_id"],
                    "calibration_rule": first["calibration_rule"],
                    "split": split,
                    "unit": unit,
                    "n_origins": int(df["origin_id"].nunique()),
                    "n_horizons": int(df["horizon"].nunique()),
                    **metric_dict(y, pred, quantiles),
                }
            )
            for group in sorted(df["horizon_group"].unique()):
                idx = [i for i, h in enumerate(horizons) if horizon_group(h) == group]
                group_rows.append(
                    {
                        "candidate_id": candidate_id,
                        "stage_r22b_case_id": first["stage_r22b_case_id"],
                        "region": first["region"],
                        "fold": int(first["fold"]),
                        "source_method_id": first["source_method_id"],
                        "calibration_rule": first["calibration_rule"],
                        "split": split,
                        "unit": unit,
                        "horizon_group": group,
                        "n_horizons": int(len(idx)),
                        **metric_dict(y[:, idx], pred[:, idx, :], quantiles),
                    }
                )
    return pd.DataFrame(rows), pd.DataFrame(group_rows)


def candidate_gate(metrics: pd.DataFrame, primary_unit: str) -> pd.DataFrame:
    if metrics.empty:
        return pd.DataFrame()
    primary = metrics[metrics["unit"].astype(str).eq(primary_unit)].copy()
    if primary.empty:
        primary = metrics[metrics["unit"].astype(str).eq("scaled")].copy()
    pivot = primary.pivot_table(
        index=["candidate_id", "stage_r22b_case_id", "region", "fold", "source_method_id", "calibration_rule", "unit"],
        columns="split",
        values=["AQL", "MAE", "RMSE"],
        aggfunc="first",
    ).reset_index()
    pivot.columns = ["_".join(str(x) for x in col if str(x)) for col in pivot.columns.to_flat_index()]
    pivot["selected_by_validation_AQL_within_case"] = False
    for _, sub in pivot.groupby("stage_r22b_case_id", sort=True):
        idx = sub.sort_values(["AQL_val", "candidate_id"]).index[0]
        pivot.loc[idx, "selected_by_validation_AQL_within_case"] = True
    pivot["selection_rule"] = "validation_AQL_only_within_case"
    pivot["test_metrics_role"] = "audit_only_after_validation_selection"
    pivot["launch_authorized_now"] = False
    pivot["fits_models_now"] = False
    pivot["mutates_registry"] = False
    pivot["mutates_manuscript"] = False
    return pivot


def no_launch_gates(readiness_frame: pd.DataFrame, params: pd.DataFrame, predictions: pd.DataFrame, output_dir: Path) -> pd.DataFrame:
    ready_count = int(readiness_frame["readiness_status"].astype(str).eq("ready").sum()) if not readiness_frame.empty else 0
    gates = [
        ("candidate_manifest_loaded", not readiness_frame.empty, "Candidate manifest was loaded."),
        ("unsupported_rules_blocked", not readiness_frame["readiness_status"].astype(str).eq("blocked_unsupported_calibration_rule").any() if not readiness_frame.empty else True, "All calibration rules are supported or rows are otherwise blocked."),
        ("validation_only_params", params.empty or params["uses_validation_only"].map(boolish).all(), "Calibration parameters are learned from validation only."),
        ("test_not_used_for_calibration", params.empty or (~params["uses_test_for_calibration"].map(boolish)).all(), "Test rows are not used to estimate calibration parameters."),
        ("ready_rows_materialized", ready_count == 0 or not predictions.empty, "Ready candidates were materialized."),
        ("no_launch_yaml_written", not any(output_dir.glob("*.yaml")) and not any(output_dir.glob("*.yml")), "No launch YAML was written."),
        ("no_registry_or_manuscript_mutation", True, "Registry and manuscript mutation remain blocked."),
    ]
    return pd.DataFrame([{"gate": name, "passed": bool(passed), "detail": detail} for name, passed, detail in gates])


def source_manifest(args: argparse.Namespace) -> pd.DataFrame:
    specs = [("candidate_manifest", Path(args.candidate_manifest), "csv")]
    rows = []
    for label, path, kind in specs:
        full = repo_path(path)
        rows.append(
            {
                "label": label,
                "kind": kind,
                "path": repo_relative(full),
                "exists": full.exists(),
                "bytes": int(full.stat().st_size) if full.exists() and full.is_file() else 0,
                "sha256": sha256_file_or_blank(full) if full.exists() and full.is_file() else "",
            }
        )
    return pd.DataFrame(rows)


def markdown_table(frame: pd.DataFrame, max_rows: int = 30) -> str:
    if frame.empty:
        return "_No rows._"
    work = frame.head(max_rows).copy()
    headers = list(work.columns)
    lines = ["| {} |".format(" | ".join(headers))]
    lines.append("| {} |".format(" | ".join(["---"] * len(headers))))
    for _, row in work.iterrows():
        vals = []
        for col in headers:
            value = row[col]
            if isinstance(value, float):
                vals.append("" if math.isnan(value) else "{:.6g}".format(value))
            else:
                vals.append(str(value).replace("|", "\\|"))
        lines.append("| {} |".format(" | ".join(vals)))
    if len(frame) > len(work):
        lines.extend(["", f"_Showing {len(work)} of {len(frame)} rows._"])
    return "\n".join(lines)


def write_report(path: str | Path, summary: dict[str, Any], readiness_frame: pd.DataFrame, gate: pd.DataFrame, no_launch: pd.DataFrame) -> None:
    lines = [
        "# PriceFM Stage-R24 Postfit Calibration Materialization",
        "",
        "Stage-R24 implements a reusable validation-only postfit calibration path. It reads existing predictions, estimates calibration parameters on validation rows only, applies them to validation/test predictions, and writes audit metrics. It does not launch or fit models.",
        "",
        "## Executive Summary",
        "",
        f"- Status: `{summary['status']}`",
        f"- Candidate rows: `{summary['n_candidate_rows']}`",
        f"- Ready rows: `{summary['n_ready_rows']}`",
        f"- Blocked rows: `{summary['n_blocked_rows']}`",
        f"- Materialized prediction rows: `{summary['n_materialized_prediction_rows']}`",
        f"- Recommended next action: `{summary['recommended_next_action']}`",
        "",
        "## Readiness",
        "",
        markdown_table(readiness_frame, max_rows=40),
        "",
        "## Candidate Gate",
        "",
        markdown_table(gate, max_rows=40),
        "",
        "## No-Launch Gates",
        "",
        markdown_table(no_launch, max_rows=40),
        "",
    ]
    repo_path(path).write_text("\n".join(lines))


def run(args: argparse.Namespace) -> dict[str, Any]:
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and any(out_dir.iterdir()) and not bool(args.force):
        raise FileExistsError(f"{out_dir} exists; rerun with --force true")
    out_dir.mkdir(parents=True, exist_ok=True)

    manifest = normalize_manifest(read_csv_required(args.candidate_manifest, "Stage-R24 candidate manifest"), args.default_method_id)
    ready = readiness(manifest)
    params = build_params(manifest, ready)
    predictions = materialize_predictions(manifest, ready, params)
    y_scalers = load_y_scalers(args.data_config, manifest, bool(args.allow_missing_scalers))
    metrics, group_metrics = compute_metrics(predictions, y_scalers)
    gate = candidate_gate(metrics, args.primary_unit)
    no_launch = no_launch_gates(ready, params, predictions, out_dir)
    source = source_manifest(args)

    ready_count = int(ready["readiness_status"].astype(str).eq("ready").sum())
    blocked_count = int(ready.shape[0] - ready_count)
    status = "completed_with_materialized_postfit_candidates" if ready_count > 0 else "completed_no_ready_postfit_candidates"
    summary = {
        "stage": "pricefm_stage_r24_postfit_calibration_materialization",
        "status": status,
        "n_candidate_rows": int(manifest.shape[0]),
        "n_ready_rows": ready_count,
        "n_blocked_rows": blocked_count,
        "n_calibration_param_rows": int(params.shape[0]),
        "n_materialized_prediction_rows": int(predictions.shape[0]),
        "n_metric_rows": int(metrics.shape[0]),
        "launches_models": False,
        "fits_models": False,
        "writes_launch_yaml": False,
        "registry_mutation_authorized": False,
        "manuscript_mutation_authorized": False,
        "recommended_next_action": (
            "use_postfit_gate_outputs_in_expensive_launch_closeout"
            if ready_count > 0
            else "supply_existing_prediction_paths_or_use_new_expensive_runs_before_postfit_calibration"
        ),
    }

    outputs = {
        "readiness": out_dir / OUT_READINESS,
        "calibration_params": out_dir / OUT_PARAMS,
        "materialized_predictions": out_dir / OUT_PREDICTIONS,
        "metric_summary": out_dir / OUT_METRICS,
        "metric_by_horizon_group": out_dir / OUT_GROUP_METRICS,
        "candidate_gate": out_dir / OUT_GATE,
        "no_launch_gates": out_dir / OUT_NO_LAUNCH_GATES,
        "source_manifest": out_dir / OUT_SOURCE,
        "report": out_dir / OUT_REPORT,
        "summary_json": out_dir / "summary.json",
    }
    write_frame(outputs["readiness"], ready)
    write_frame(outputs["calibration_params"], params)
    write_frame(outputs["materialized_predictions"], predictions)
    write_frame(outputs["metric_summary"], metrics)
    write_frame(outputs["metric_by_horizon_group"], group_metrics)
    write_frame(outputs["candidate_gate"], gate)
    write_frame(outputs["no_launch_gates"], no_launch)
    write_frame(outputs["source_manifest"], source)
    summary["outputs"] = {key: repo_relative(path) for key, path in outputs.items()}
    write_report(outputs["report"], summary, ready, gate, no_launch)
    write_json(outputs["summary_json"], summary)

    if not no_launch["passed"].map(boolish).all():
        failed = no_launch.loc[~no_launch["passed"].map(boolish), "gate"].tolist()
        raise RuntimeError(f"Stage-R24 postfit no-launch gates failed: {failed}")
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    run(parser().parse_args())


if __name__ == "__main__":
    main()
