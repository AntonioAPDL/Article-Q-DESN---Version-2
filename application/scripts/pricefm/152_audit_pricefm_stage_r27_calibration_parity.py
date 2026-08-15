#!/usr/bin/env python3
"""Read-only PriceFM Stage-R27 calibration and information-set parity audit."""

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


DEFAULT_R26_CLOSEOUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r26_r25_broad_horizon_final_closeout_20260711"
)
DEFAULT_R25_PREP_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r25_post_r24_broad_launch_prep_20260709"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r27_calibration_parity_audit_20260711"
)
DEFAULT_DATA_CONFIG = "application/config/pricefm_data_pipeline.yaml"

R26_METRIC_ROWS = "pricefm_stage_r26_final_metric_rows.csv"
R26_SELECTED = "pricefm_stage_r26_final_validation_selected_case.csv"
R26_ORACLE = "pricefm_stage_r26_final_test_oracle_case.csv"
R26_SUMMARY = "summary.json"
R25_MANIFEST = "pricefm_stage_r25_launch_manifest.csv"

OUT_READINESS = "pricefm_stage_r27_candidate_readiness.csv"
OUT_PARAMS = "pricefm_stage_r27_calibration_params.csv"
OUT_METRICS = "pricefm_stage_r27_calibration_metric_summary.csv"
OUT_SELECTION = "pricefm_stage_r27_calibration_selection_gate.csv"
OUT_CASE_SELECTION = "pricefm_stage_r27_case_calibration_selection.csv"
OUT_PARITY = "pricefm_stage_r27_information_set_parity_audit.csv"
OUT_MECHANISM = "pricefm_stage_r27_mechanism_diagnosis.csv"
OUT_NEXT = "pricefm_stage_r27_next_action_plan.csv"
OUT_GATES = "pricefm_stage_r27_no_launch_gates.csv"
OUT_SOURCE = "source_manifest.csv"
OUT_REPORT = "pricefm_stage_r27_calibration_parity_report.md"

CALIBRATION_RULES = [
    "baseline_replay",
    "global_quantile_shift_on_validation",
    "horizon_block_quantile_shift_on_validation",
    "horizon_block_affine_shift_scale_on_validation",
]


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r26-closeout-dir", default=DEFAULT_R26_CLOSEOUT_DIR)
    p.add_argument("--stage-r25-prep-dir", default=DEFAULT_R25_PREP_DIR)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--data-config", default=DEFAULT_DATA_CONFIG)
    p.add_argument("--primary-unit", choices=["original", "scaled"], default="original")
    p.add_argument("--allow-missing-scalers", type=parse_bool, default=True)
    p.add_argument("--expected-candidate-rows", type=int, default=400)
    p.add_argument("--baseline-match-tolerance", type=float, default=1.0e-5)
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


def read_json_required(path: str | Path, label: str) -> dict[str, Any]:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required JSON: {full}")
    with open(full, "r") as f:
        return json.load(f)


def read_json_optional(path: str | Path) -> dict[str, Any]:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        return {}
    with open(full, "r") as f:
        return json.load(f)


def require_columns(frame: pd.DataFrame, columns: list[str], label: str) -> None:
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError(f"{label} missing required columns: {missing}")


def write_frame(path: str | Path, frame: pd.DataFrame) -> None:
    full = repo_path(path)
    full.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(full, index=False)


def horizon_group(horizon: Any) -> str:
    h = int(float(horizon))
    start = ((h - 1) // 24) * 24 + 1
    end = min(start + 23, 96)
    return f"{start}-{end}"


def candidate_id(experiment_id: Any, method_id: Any) -> str:
    return f"{text_value(experiment_id)}::{text_value(method_id)}"


def model_dir_from_metric(metric_summary: Any) -> Path:
    text = text_value(metric_summary)
    if not text:
        return Path("")
    return repo_path(text).parent


def normalize_metric_rows(frame: pd.DataFrame) -> pd.DataFrame:
    required = [
        "experiment_id",
        "region",
        "fold",
        "stage_r25_arm",
        "method_id",
        "val_AQL",
        "test_AQL",
        "current_qdesn_AQL",
        "current_pricefm_AQL",
        "test_minus_current_qdesn",
        "test_minus_pricefm",
        "metric_summary",
    ]
    require_columns(frame, required, "Stage-R26 final metric rows")
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    out["experiment_id"] = out["experiment_id"].astype(str)
    out["method_id"] = out["method_id"].astype(str)
    out["candidate_id"] = out.apply(lambda r: candidate_id(r["experiment_id"], r["method_id"]), axis=1)
    out["model_dir"] = out["metric_summary"].map(lambda p: repo_relative(model_dir_from_metric(p)) if text_value(p) else "")
    out["prediction_path"] = out["metric_summary"].map(lambda p: repo_relative(model_dir_from_metric(p) / "model_predictions_scaled.csv") if text_value(p) else "")
    out["prediction_with_naive_path"] = out["metric_summary"].map(lambda p: repo_relative(model_dir_from_metric(p) / "predictions_with_naive_scaled.csv") if text_value(p) else "")
    out["adapter_dir"] = out["metric_summary"].map(lambda p: repo_relative(model_dir_from_metric(p).parent / "adapter") if text_value(p) else "")
    out["row_source_val"] = out["metric_summary"].map(lambda p: repo_relative(model_dir_from_metric(p).parent / "adapter" / "rows_val.csv") if text_value(p) else "")
    out["row_source_test"] = out["metric_summary"].map(lambda p: repo_relative(model_dir_from_metric(p).parent / "adapter" / "rows_test.csv") if text_value(p) else "")
    out["feature_manifest"] = out["metric_summary"].map(lambda p: repo_relative(model_dir_from_metric(p).parent / "adapter" / "feature_manifest.json") if text_value(p) else "")
    out["adapter_manifest"] = out["metric_summary"].map(lambda p: repo_relative(model_dir_from_metric(p).parent / "adapter" / "adapter_manifest.json") if text_value(p) else "")
    out["model_method_summary"] = out["metric_summary"].map(lambda p: repo_relative(model_dir_from_metric(p) / "model_method_summary.csv") if text_value(p) else "")
    out["model_parameter_summary"] = out["metric_summary"].map(lambda p: repo_relative(model_dir_from_metric(p) / "model_parameter_summary.csv") if text_value(p) else "")
    return out


def row_role(metric: pd.DataFrame, selected: pd.DataFrame, oracle: pd.DataFrame) -> pd.DataFrame:
    selected_ids = set(selected.apply(lambda r: candidate_id(r["experiment_id"], r["method_id"]), axis=1)) if not selected.empty else set()
    oracle_ids = set(oracle.apply(lambda r: candidate_id(r["experiment_id"], r["method_id"]), axis=1)) if not oracle.empty else set()
    out = metric.copy()
    out["is_r26_validation_selected"] = out["candidate_id"].isin(selected_ids)
    out["is_r26_test_oracle"] = out["candidate_id"].isin(oracle_ids)
    out["r27_source_role"] = out.apply(
        lambda r: "r26_validation_selected_and_test_oracle"
        if bool(r["is_r26_validation_selected"]) and bool(r["is_r26_test_oracle"])
        else "r26_validation_selected"
        if bool(r["is_r26_validation_selected"])
        else "r26_test_oracle_audit_only"
        if bool(r["is_r26_test_oracle"])
        else "r25_full_surface_candidate",
        axis=1,
    )
    return out


def file_exists(path: Any) -> bool:
    return bool(text_value(path) and repo_path(text_value(path)).exists())


def build_readiness(candidates: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for _, row in candidates.iterrows():
        checks = {
            "prediction_exists": file_exists(row["prediction_path"]),
            "prediction_with_naive_exists": file_exists(row["prediction_with_naive_path"]),
            "row_source_val_exists": file_exists(row["row_source_val"]),
            "row_source_test_exists": file_exists(row["row_source_test"]),
            "feature_manifest_exists": file_exists(row["feature_manifest"]),
            "adapter_manifest_exists": file_exists(row["adapter_manifest"]),
            "model_method_summary_exists": file_exists(row["model_method_summary"]),
            "model_parameter_summary_exists": file_exists(row["model_parameter_summary"]),
        }
        ready = all(checks.values())
        rows.append(
            {
                "candidate_id": row["candidate_id"],
                "experiment_id": row["experiment_id"],
                "region": row["region"],
                "fold": int(row["fold"]),
                "stage_r25_arm": row["stage_r25_arm"],
                "method_id": row["method_id"],
                "r27_source_role": row["r27_source_role"],
                "prediction_path": row["prediction_path"],
                "row_source_val": row["row_source_val"],
                "row_source_test": row["row_source_test"],
                "feature_manifest": row["feature_manifest"],
                **checks,
                "readiness_status": "ready" if ready else "blocked_missing_artifact",
            }
        )
    return pd.DataFrame(rows).sort_values(["readiness_status", "region", "fold", "experiment_id", "method_id"]).reset_index(drop=True)


def fit_group_params(frame: pd.DataFrame, rule: str) -> dict[str, Any]:
    pred = pd.to_numeric(frame["pred_scaled"], errors="coerce").to_numpy(dtype=float)
    truth = pd.to_numeric(frame["y_scaled"], errors="coerce").to_numpy(dtype=float)
    ok = np.isfinite(pred) & np.isfinite(truth)
    pred = pred[ok]
    truth = truth[ok]
    if pred.size == 0:
        raise ValueError("cannot fit calibration without finite validation rows")
    shift = float(np.median(truth - pred))
    if rule == "baseline_replay":
        return {"intercept": 0.0, "slope": 1.0, "shift": 0.0, "fallback_used": False}
    if rule in {"global_quantile_shift_on_validation", "horizon_block_quantile_shift_on_validation"}:
        return {"intercept": shift, "slope": 1.0, "shift": shift, "fallback_used": False}
    if rule == "horizon_block_affine_shift_scale_on_validation":
        if pred.size < 3 or float(np.nanstd(pred)) <= 1.0e-10:
            return {"intercept": shift, "slope": 1.0, "shift": shift, "fallback_used": True}
        slope, intercept = np.polyfit(pred, truth, deg=1)
        if not np.isfinite(slope) or slope <= 0.0 or not np.isfinite(intercept):
            return {"intercept": shift, "slope": 1.0, "shift": shift, "fallback_used": True}
        return {
            "intercept": float(intercept),
            "slope": float(np.clip(slope, 0.25, 4.0)),
            "shift": shift,
            "fallback_used": False,
        }
    raise ValueError(f"unsupported calibration rule: {rule}")


def load_prediction_truth(paths: pd.Series, method_id: str, split: str) -> pd.DataFrame:
    pred = read_csv_required(paths["prediction_path"], f"{paths['candidate_id']} predictions")
    truth = read_csv_required(paths[f"row_source_{split}"], f"{paths['candidate_id']} {split} truth")
    require_columns(pred, ["method_id", "split", "origin_id", "horizon", "tau", "pred_scaled"], "prediction artifact")
    require_columns(truth, ["origin_id", "horizon", "y_scaled"], f"{split} truth rows")
    sub = pred[
        pred["method_id"].astype(str).eq(str(method_id))
        & pred["split"].astype(str).eq(str(split))
    ].copy()
    if sub.empty:
        raise ValueError(f"no predictions for {paths['candidate_id']} method={method_id} split={split}")
    merged = sub.merge(
        truth[["origin_id", "horizon", "y_scaled"]],
        on=["origin_id", "horizon"],
        how="left",
        validate="many_to_one",
    )
    if merged["y_scaled"].isna().any():
        raise ValueError(f"prediction/truth alignment failed for {paths['candidate_id']} split={split}")
    merged["horizon_group"] = merged["horizon"].map(horizon_group)
    return merged


def merge_prediction_truth(
    pred: pd.DataFrame,
    truth: pd.DataFrame,
    candidate: pd.Series,
    split: str,
) -> pd.DataFrame:
    method_id = str(candidate["method_id"])
    sub = pred[
        pred["method_id"].astype(str).eq(method_id)
        & pred["split"].astype(str).eq(str(split))
    ].copy()
    if sub.empty:
        raise ValueError(f"no predictions for {candidate['candidate_id']} method={method_id} split={split}")
    merged = sub.merge(
        truth[["origin_id", "horizon", "y_scaled"]],
        on=["origin_id", "horizon"],
        how="left",
        validate="many_to_one",
    )
    if merged["y_scaled"].isna().any():
        raise ValueError(f"prediction/truth alignment failed for {candidate['candidate_id']} split={split}")
    merged["horizon_group"] = merged["horizon"].map(horizon_group)
    return merged


def params_for_candidate(candidate: pd.Series, val: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for rule in CALIBRATION_RULES:
        group_cols = ["tau"] if rule == "global_quantile_shift_on_validation" else ["horizon_group", "tau"]
        for key, part in val.groupby(group_cols, sort=True):
            if not isinstance(key, tuple):
                key = (key,)
            horizon = "all" if rule == "global_quantile_shift_on_validation" else str(key[0])
            tau = float(key[-1])
            params = fit_group_params(part, rule)
            rows.append(
                {
                    "candidate_id": candidate["candidate_id"],
                    "experiment_id": candidate["experiment_id"],
                    "region": candidate["region"],
                    "fold": int(candidate["fold"]),
                    "stage_r25_arm": candidate["stage_r25_arm"],
                    "method_id": candidate["method_id"],
                    "calibration_rule": rule,
                    "horizon_group": horizon,
                    "tau": tau,
                    "n_validation_rows": int(part.shape[0]),
                    **params,
                    "uses_validation_only": True,
                    "uses_test_for_calibration": False,
                }
            )
    return pd.DataFrame(rows)


def apply_params(frame: pd.DataFrame, params: pd.DataFrame, rule: str) -> pd.DataFrame:
    out = frame.copy()
    if rule == "global_quantile_shift_on_validation":
        out["param_horizon_group"] = "all"
    else:
        out["param_horizon_group"] = out["horizon_group"].astype(str)
    rule_params = params[params["calibration_rule"].astype(str).eq(rule)].copy()
    rule_params = rule_params.rename(columns={"horizon_group": "param_horizon_group"})
    merged = out.merge(
        rule_params[["param_horizon_group", "tau", "intercept", "slope"]],
        on=["param_horizon_group", "tau"],
        how="left",
        validate="many_to_one",
    )
    if merged["intercept"].isna().any() or merged["slope"].isna().any():
        raise ValueError(f"missing calibration params for rule={rule}")
    merged["pred_scaled_materialized"] = merged["intercept"] + merged["slope"] * pd.to_numeric(
        merged["pred_scaled"], errors="coerce"
    )
    return merged


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


def fast_single_quantile_metrics(y: np.ndarray, pred: np.ndarray, tau: float) -> dict[str, float]:
    err = y - pred
    return {
        "AQL": float(np.maximum(tau * err, (tau - 1.0) * err).mean()),
        "AQCR": 0.0,
        "MAE": float(np.abs(err).mean()),
        "RMSE": float(np.sqrt(np.square(err).mean())),
    }


def load_y_scalers(data_config: str | Path, candidates: pd.DataFrame, allow_missing: bool) -> dict[tuple[str, int], Any]:
    if candidates.empty:
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
    for region, fold in sorted({(str(r), int(f)) for r, f in zip(candidates["region"], candidates["fold"])}):
        path = repo_path(Path(spec["processed_dir"]) / "scalers" / f"fold_{fold}" / "per_region_separate_xy_scalers.joblib")
        if not path.exists():
            if allow_missing:
                continue
            raise FileNotFoundError(f"missing y scaler for region={region}, fold={fold}: {path}")
        scalers = joblib.load(path)
        out[(region, fold)] = scalers[str(region)]["y_scaler"]
    return out


def metrics_for_prediction(candidate: pd.Series, frame: pd.DataFrame, split: str, rule: str, y_scalers: dict[tuple[str, int], Any]) -> list[dict[str, Any]]:
    quantiles = sorted(float(x) for x in frame["tau"].unique())
    scaler = y_scalers.get((str(candidate["region"]), int(candidate["fold"])))
    if len(quantiles) == 1:
        y_vec = pd.to_numeric(frame["y_scaled"], errors="coerce").to_numpy(dtype=float)
        pred_vec = pd.to_numeric(frame["pred_scaled_materialized"], errors="coerce").to_numpy(dtype=float)
        if not np.all(np.isfinite(y_vec)) or not np.all(np.isfinite(pred_vec)):
            raise ValueError(f"nonfinite prediction rows for {candidate['candidate_id']} split={split}")
        units = [("scaled", y_vec, pred_vec, quantiles[0])]
        if scaler is not None:
            units.append(("original", inverse_scale_y(y_vec, scaler), inverse_scale_y(pred_vec, scaler), quantiles[0]))
        metric_payloads = [(unit, fast_single_quantile_metrics(y, pred, tau)) for unit, y, pred, tau in units]
    else:
        y_scaled, pred_scaled, horizons, quantiles = metric_arrays(frame)
        units = [("scaled", y_scaled, pred_scaled)]
        if scaler is not None:
            units.append(("original", inverse_scale_y(y_scaled, scaler), inverse_scale_y(pred_scaled, scaler)))
        metric_payloads = [(unit, metric_dict(y, pred, quantiles)) for unit, y, pred in units]
    rows = []
    for unit, metrics in metric_payloads:
        rows.append(
            {
                "candidate_id": candidate["candidate_id"],
                "experiment_id": candidate["experiment_id"],
                "region": candidate["region"],
                "fold": int(candidate["fold"]),
                "stage_r25_arm": candidate["stage_r25_arm"],
                "method_id": candidate["method_id"],
                "r27_source_role": candidate["r27_source_role"],
                "calibration_rule": rule,
                "split": split,
                "unit": unit,
                "n_origins": int(frame["origin_id"].nunique()),
                "n_horizons": int(frame["horizon"].nunique()),
                "n_quantiles": int(len(quantiles)),
                **metrics,
            }
        )
    return rows


def run_calibration_surface(
    candidates: pd.DataFrame,
    readiness: pd.DataFrame,
    y_scalers: dict[tuple[str, int], Any],
) -> tuple[pd.DataFrame, pd.DataFrame]:
    ready_ids = set(readiness.loc[readiness["readiness_status"].astype(str).eq("ready"), "candidate_id"])
    candidate_map = candidates.set_index("candidate_id", drop=False)
    param_frames = []
    metric_rows: list[dict[str, Any]] = []
    ready_candidates = candidates[candidates["candidate_id"].isin(ready_ids)].copy()
    for _, group in ready_candidates.groupby("experiment_id", sort=True):
        first = group.iloc[0]
        pred = read_csv_required(first["prediction_path"], f"{first['experiment_id']} predictions")
        truth_val = read_csv_required(first["row_source_val"], f"{first['experiment_id']} val truth")
        truth_test = read_csv_required(first["row_source_test"], f"{first['experiment_id']} test truth")
        require_columns(pred, ["method_id", "split", "origin_id", "horizon", "tau", "pred_scaled"], "prediction artifact")
        require_columns(truth_val, ["origin_id", "horizon", "y_scaled"], "validation truth rows")
        require_columns(truth_test, ["origin_id", "horizon", "y_scaled"], "test truth rows")
        for _, cand in group.sort_values("method_id").iterrows():
            val = merge_prediction_truth(pred, truth_val, cand, "val")
            test = merge_prediction_truth(pred, truth_test, cand, "test")
            params = params_for_candidate(cand, val)
            param_frames.append(params)
            for rule in CALIBRATION_RULES:
                for split, source in [("val", val), ("test", test)]:
                    materialized = apply_params(source, params, rule)
                    metric_rows.extend(metrics_for_prediction(cand, materialized, split, rule, y_scalers))
    param_frame = pd.concat(param_frames, ignore_index=True) if param_frames else pd.DataFrame()
    metric_frame = pd.DataFrame(metric_rows)
    return param_frame, metric_frame


def selection_gate(metrics: pd.DataFrame, candidates: pd.DataFrame, primary_unit: str) -> pd.DataFrame:
    if metrics.empty:
        return pd.DataFrame()
    primary = metrics[metrics["unit"].astype(str).eq(primary_unit)].copy()
    if primary.empty:
        primary = metrics[metrics["unit"].astype(str).eq("scaled")].copy()
    pivot = primary.pivot_table(
        index=[
            "candidate_id",
            "experiment_id",
            "region",
            "fold",
            "stage_r25_arm",
            "method_id",
            "r27_source_role",
            "calibration_rule",
            "unit",
        ],
        columns="split",
        values=["AQL", "AQCR", "MAE", "RMSE"],
        aggfunc="first",
    ).reset_index()
    pivot.columns = ["_".join(str(x) for x in col if str(x)) for col in pivot.columns.to_flat_index()]
    base_cols = [
        "candidate_id",
        "val_AQL",
        "test_AQL",
        "current_qdesn_AQL",
        "current_pricefm_AQL",
        "feature_policy",
        "horizon_focus",
        "horizon_weight_multiplier",
        "lag_window",
        "depth",
        "units",
        "feature_dim",
        "state_output",
        "alpha",
        "rho",
        "input_scale",
        "tau0",
        "is_r26_validation_selected",
        "is_r26_test_oracle",
    ]
    base = candidates[[c for c in base_cols if c in candidates.columns]].copy()
    base = base.rename(columns={"val_AQL": "r25_uncalibrated_val_AQL", "test_AQL": "r25_uncalibrated_test_AQL"})
    out = pivot.merge(base, on="candidate_id", how="left", validate="many_to_one")
    out["calibration_delta_val_AQL"] = out["AQL_val"] - out["r25_uncalibrated_val_AQL"]
    out["calibration_delta_test_AQL"] = out["AQL_test"] - out["r25_uncalibrated_test_AQL"]
    out["test_minus_current_qdesn"] = out["AQL_test"] - out["current_qdesn_AQL"]
    out["test_minus_pricefm"] = out["AQL_test"] - out["current_pricefm_AQL"]
    out["beats_current_qdesn_on_test"] = out["test_minus_current_qdesn"] < 0.0
    out["beats_pricefm_on_test"] = out["test_minus_pricefm"] < 0.0
    out["beats_both_on_test"] = out["beats_current_qdesn_on_test"] & out["beats_pricefm_on_test"]
    out["selected_by_validation_full_surface_calibrated"] = False
    out["selected_by_validation_r26_selected_only"] = False
    for _, group in out.groupby(["region", "fold"], sort=True):
        idx = group.sort_values(["AQL_val", "candidate_id", "calibration_rule"]).index[0]
        out.loc[idx, "selected_by_validation_full_surface_calibrated"] = True
        sub = group[group["is_r26_validation_selected"].map(boolish)]
        if not sub.empty:
            idx2 = sub.sort_values(["AQL_val", "candidate_id", "calibration_rule"]).index[0]
            out.loc[idx2, "selected_by_validation_r26_selected_only"] = True
    out["promotion_gate_full_surface_status"] = out.apply(
        lambda r: "audit_candidate_requires_preregistered_confirmation"
        if boolish(r["selected_by_validation_full_surface_calibrated"]) and boolish(r["beats_both_on_test"])
        else "blocked_not_validation_selected_beat_both_full_surface",
        axis=1,
    )
    out["promotion_gate_r26_selected_status"] = out.apply(
        lambda r: "candidate_pending_full_quantile_mcmc_reproducibility_confirmation"
        if boolish(r["selected_by_validation_r26_selected_only"]) and boolish(r["beats_both_on_test"])
        else "blocked_not_r26_selected_beat_both",
        axis=1,
    )
    out["selection_rule"] = "validation_AQL_only"
    out["test_metrics_role"] = "audit_only_after_frozen_validation_selection"
    return out.sort_values(["region", "fold", "AQL_val", "candidate_id", "calibration_rule"]).reset_index(drop=True)


def case_selection(selection: pd.DataFrame) -> pd.DataFrame:
    rows = []
    if selection.empty:
        return pd.DataFrame()
    scopes = [
        ("full_surface_calibrated", "selected_by_validation_full_surface_calibrated"),
        ("r26_selected_only_calibrated", "selected_by_validation_r26_selected_only"),
    ]
    for scope, flag in scopes:
        subset = selection[selection[flag].map(boolish)].copy()
        for _, row in subset.sort_values(["region", "fold"]).iterrows():
            rows.append(
                {
                    "selection_scope": scope,
                    "region": row["region"],
                    "fold": int(row["fold"]),
                    "candidate_id": row["candidate_id"],
                    "experiment_id": row["experiment_id"],
                    "stage_r25_arm": row["stage_r25_arm"],
                    "method_id": row["method_id"],
                    "calibration_rule": row["calibration_rule"],
                    "AQL_val": row["AQL_val"],
                    "AQL_test": row["AQL_test"],
                    "r25_uncalibrated_test_AQL": row["r25_uncalibrated_test_AQL"],
                    "calibration_delta_test_AQL": row["calibration_delta_test_AQL"],
                    "current_qdesn_AQL": row["current_qdesn_AQL"],
                    "current_pricefm_AQL": row["current_pricefm_AQL"],
                    "test_minus_current_qdesn": row["test_minus_current_qdesn"],
                    "test_minus_pricefm": row["test_minus_pricefm"],
                    "beats_current_qdesn_on_test": boolish(row["beats_current_qdesn_on_test"]),
                    "beats_pricefm_on_test": boolish(row["beats_pricefm_on_test"]),
                    "beats_both_on_test": boolish(row["beats_both_on_test"]),
                    "promotion_gate_status": row["promotion_gate_r26_selected_status"]
                    if scope == "r26_selected_only_calibrated"
                    else row["promotion_gate_full_surface_status"],
                }
            )
    oracle = selection.sort_values(["region", "fold", "AQL_test", "candidate_id", "calibration_rule"]).groupby(
        ["region", "fold"], as_index=False
    ).head(1)
    for _, row in oracle.sort_values(["region", "fold"]).iterrows():
        rows.append(
            {
                "selection_scope": "test_oracle_calibrated_audit_only",
                "region": row["region"],
                "fold": int(row["fold"]),
                "candidate_id": row["candidate_id"],
                "experiment_id": row["experiment_id"],
                "stage_r25_arm": row["stage_r25_arm"],
                "method_id": row["method_id"],
                "calibration_rule": row["calibration_rule"],
                "AQL_val": row["AQL_val"],
                "AQL_test": row["AQL_test"],
                "r25_uncalibrated_test_AQL": row["r25_uncalibrated_test_AQL"],
                "calibration_delta_test_AQL": row["calibration_delta_test_AQL"],
                "current_qdesn_AQL": row["current_qdesn_AQL"],
                "current_pricefm_AQL": row["current_pricefm_AQL"],
                "test_minus_current_qdesn": row["test_minus_current_qdesn"],
                "test_minus_pricefm": row["test_minus_pricefm"],
                "beats_current_qdesn_on_test": boolish(row["beats_current_qdesn_on_test"]),
                "beats_pricefm_on_test": boolish(row["beats_pricefm_on_test"]),
                "beats_both_on_test": boolish(row["beats_both_on_test"]),
                "promotion_gate_status": "audit_only_test_oracle_not_promotable",
            }
        )
    return pd.DataFrame(rows).sort_values(["selection_scope", "test_minus_pricefm", "region", "fold"]).reset_index(drop=True)


def read_feature_manifest(path: Any) -> dict[str, Any]:
    payload = read_json_optional(path)
    if not payload:
        return {}
    return payload


def feature_manifest_rows(candidates: pd.DataFrame, selection: pd.DataFrame) -> pd.DataFrame:
    experiment_rows = candidates.sort_values(["experiment_id"]).drop_duplicates("experiment_id").copy()
    best_uncal = candidates.sort_values(["experiment_id", "test_minus_pricefm"]).drop_duplicates("experiment_id")
    best_cal = selection.sort_values(["experiment_id", "test_minus_pricefm"]).drop_duplicates("experiment_id") if not selection.empty else pd.DataFrame()
    best_uncal_map = best_uncal.set_index("experiment_id", drop=False)
    best_cal_map = best_cal.set_index("experiment_id", drop=False) if not best_cal.empty else pd.DataFrame()
    rows = []
    for _, row in experiment_rows.iterrows():
        manifest = read_feature_manifest(row["feature_manifest"])
        policy_manifest = manifest.get("feature_policy_manifest", {}) if manifest else {}
        graph = policy_manifest.get("graph") or {}
        active = graph.get("active_regions") or []
        neighbors = graph.get("neighbor_regions") or []
        uncal = best_uncal_map.loc[row["experiment_id"]]
        cal = best_cal_map.loc[row["experiment_id"]] if not best_cal_map.empty and row["experiment_id"] in best_cal_map.index else None
        planned_policy = text_value(row.get("feature_policy"))
        actual_policy = text_value(manifest.get("feature_policy"))
        actual_dim = finite_float(manifest.get("feature_dim"))
        planned_dim = finite_float(row.get("feature_dim"))
        spatial = text_value(policy_manifest.get("spatial_information_set"))
        if not manifest:
            diagnosis = "blocked_missing_feature_manifest"
        elif planned_policy != actual_policy:
            diagnosis = "planned_actual_feature_policy_mismatch"
        elif actual_policy == "target_only" and finite_float(uncal.get("test_minus_pricefm")) > 0:
            diagnosis = "local_only_less_information_than_pricefm_or_objective_mismatch"
        elif actual_policy != "target_only" and finite_float(uncal.get("test_minus_pricefm")) > 0:
            diagnosis = "graph_information_present_but_pricefm_gap_remains"
        else:
            diagnosis = "information_set_not_primary_blocker"
        rows.append(
            {
                "experiment_id": row["experiment_id"],
                "region": row["region"],
                "fold": int(row["fold"]),
                "stage_r25_arm": row["stage_r25_arm"],
                "planned_feature_policy": planned_policy,
                "actual_feature_policy": actual_policy,
                "planned_actual_feature_policy_match": planned_policy == actual_policy,
                "planned_feature_dim": planned_dim,
                "actual_feature_dim": actual_dim,
                "feature_dim_match": int(planned_dim) == int(actual_dim) if math.isfinite(planned_dim) and math.isfinite(actual_dim) else False,
                "n_feature_names": len(manifest.get("feature_names", [])) if manifest else 0,
                "input_scope": text_value(policy_manifest.get("input_scope")),
                "output_scope": text_value(policy_manifest.get("output_scope")),
                "spatial_information_set": spatial,
                "lead_covariate_status": text_value(policy_manifest.get("lead_covariate_status")),
                "graph_source": text_value(graph.get("graph_source")),
                "graph_degree": graph.get("graph_degree", ""),
                "n_active_regions": int(graph.get("n_active_regions", len(active))) if graph else 1,
                "n_neighbor_regions": int(graph.get("n_neighbor_regions", len(neighbors))) if graph else 0,
                "active_regions": json.dumps(active, sort_keys=True),
                "neighbor_regions": json.dumps(neighbors, sort_keys=True),
                "best_uncalibrated_method_id": uncal["method_id"],
                "best_uncalibrated_test_minus_pricefm": finite_float(uncal.get("test_minus_pricefm")),
                "best_calibrated_rule": text_value(cal.get("calibration_rule")) if cal is not None else "",
                "best_calibrated_method_id": text_value(cal.get("method_id")) if cal is not None else "",
                "best_calibrated_test_minus_pricefm": finite_float(cal.get("test_minus_pricefm")) if cal is not None else float("nan"),
                "information_set_diagnosis": diagnosis,
            }
        )
    return pd.DataFrame(rows).sort_values(["best_calibrated_test_minus_pricefm", "region", "fold", "stage_r25_arm"]).reset_index(drop=True)


def mechanism_diagnosis(selection: pd.DataFrame, case_sel: pd.DataFrame, parity: pd.DataFrame) -> pd.DataFrame:
    rows = []
    primary = selection.copy()
    if not primary.empty:
        original = primary[primary["calibration_rule"].astype(str).eq("baseline_replay")]
        calibrated = primary[~primary["calibration_rule"].astype(str).eq("baseline_replay")]
        rows.append(
            {
                "diagnosis_area": "calibration_full_surface",
                "evidence": (
                    f"{int(calibrated['beats_pricefm_on_test'].map(boolish).sum())} calibrated rows beat PriceFM; "
                    f"{int(calibrated['beats_both_on_test'].map(boolish).sum())} beat both; "
                    f"best calibrated PriceFM gap {finite_float(calibrated['test_minus_pricefm'].min()):.6f}"
                )
                if not calibrated.empty
                else "No calibrated rows.",
                "interpretation": "Calibration can be assessed from existing predictions without refitting.",
                "decision": "promote_only_if_validation_selected_beat_both_else_diagnostic",
            }
        )
        rows.append(
            {
                "diagnosis_area": "baseline_replay",
                "evidence": f"Best uncalibrated replay PriceFM gap {finite_float(original['test_minus_pricefm'].min()):.6f}",
                "interpretation": "Baseline replay anchors Stage-R27 metrics to Stage-R25.",
                "decision": "use_as_reproducibility_check",
            }
        )
    full = case_sel[case_sel["selection_scope"].astype(str).eq("full_surface_calibrated")] if not case_sel.empty else pd.DataFrame()
    r26 = case_sel[case_sel["selection_scope"].astype(str).eq("r26_selected_only_calibrated")] if not case_sel.empty else pd.DataFrame()
    oracle = case_sel[case_sel["selection_scope"].astype(str).eq("test_oracle_calibrated_audit_only")] if not case_sel.empty else pd.DataFrame()
    for label, frame in [
        ("validation_selected_full_surface", full),
        ("validation_selected_r26_only", r26),
        ("test_oracle_audit_only", oracle),
    ]:
        rows.append(
            {
                "diagnosis_area": label,
                "evidence": (
                    f"{int(frame['beats_pricefm_on_test'].map(boolish).sum())}/{frame.shape[0]} selected rows beat PriceFM; "
                    f"{int(frame['beats_both_on_test'].map(boolish).sum())}/{frame.shape[0]} beat both; "
                    f"best PriceFM gap {finite_float(frame['test_minus_pricefm'].min()):.6f}"
                )
                if not frame.empty
                else "No rows.",
                "interpretation": "Validation-selected rows are decision-relevant; test oracle rows are diagnostic only.",
                "decision": "block_registry_article_mcmc_unless_validation_selected_beat_both",
            }
        )
    if not parity.empty:
        by_policy = parity.groupby("actual_feature_policy", as_index=False).agg(
            experiments=("experiment_id", "nunique"),
            best_calibrated_gap=("best_calibrated_test_minus_pricefm", "min"),
            median_calibrated_gap=("best_calibrated_test_minus_pricefm", "median"),
            graph_rows=("n_active_regions", lambda x: int((pd.to_numeric(x, errors="coerce") > 1).sum())),
        )
        rows.append(
            {
                "diagnosis_area": "information_set_parity",
                "evidence": "; ".join(
                    f"{r.actual_feature_policy}: n={int(r.experiments)}, best_gap={finite_float(r.best_calibrated_gap):.6f}, median_gap={finite_float(r.median_calibrated_gap):.6f}"
                    for r in by_policy.itertuples()
                ),
                "interpretation": "Graph information is present in several arms, so remaining gaps are not explained solely by local-only inputs.",
                "decision": "audit exact PriceFM feature parity before new expensive graph searches",
            }
        )
    return pd.DataFrame(rows)


def next_action_plan(summary: dict[str, Any]) -> pd.DataFrame:
    has_r26_candidate = int(summary["n_r26_selected_calibrated_beat_both"]) > 0
    has_full_candidate = int(summary["n_full_surface_calibrated_beat_both"]) > 0
    return pd.DataFrame(
        [
            {
                "priority": 1,
                "action": "if_r26_selected_calibration_beat_both_design_full_quantile_confirmation",
                "condition": "validation-selected R26 candidate calibration beats current Q-DESN and cached PriceFM",
                "allowed_next": has_r26_candidate,
                "rationale": "This is the cleanest path because the original R25 row was selected by validation before test audit.",
            },
            {
                "priority": 2,
                "action": "if_only_full_surface_calibration_beat_both_preregister_confirmation_before_promotion",
                "condition": "full R25 calibrated surface has validation-selected beat-both row but original R26-selected subset does not",
                "allowed_next": has_full_candidate and not has_r26_candidate,
                "rationale": "This is promising but more post-hoc; require a preregistered confirmation stage before promotion.",
            },
            {
                "priority": 3,
                "action": "if_no_calibrated_beat_both_pivot_to_objective_or_model_family",
                "condition": "no validation-selected calibrated candidate beats both baselines",
                "allowed_next": not has_full_candidate and not has_r26_candidate,
                "rationale": "If validation-only calibration cannot close the gap from existing predictions, more same-family horizon weighting is not optimal.",
            },
            {
                "priority": 4,
                "action": "information_set_parity_followup",
                "condition": "graph/local actual manifests show feature-policy scope is implemented but still loses to PriceFM",
                "allowed_next": True,
                "rationale": "Before another expensive run, compare exact PriceFM feature construction, scaling, graph scope, and target availability.",
            },
            {
                "priority": 5,
                "action": "keep_mcmc_registry_article_blocked",
                "condition": "no full-quantile and MCMC confirmation exists",
                "allowed_next": False,
                "rationale": "MCMC is confirmatory evidence for selected winners, not a rescue mechanism for a negative VB surface.",
            },
        ]
    )


def no_launch_gates(
    args: argparse.Namespace,
    readiness: pd.DataFrame,
    params: pd.DataFrame,
    selection: pd.DataFrame,
    out_dir: Path,
    baseline_max_diff: float,
) -> pd.DataFrame:
    ready_count = int(readiness["readiness_status"].astype(str).eq("ready").sum()) if not readiness.empty else 0
    gates = [
        ("candidate_surface_loaded", readiness.shape[0] == args.expected_candidate_rows, "All expected Stage-R25 Q-DESN/exQDESN rows were loaded."),
        ("all_artifacts_ready", ready_count == readiness.shape[0] and ready_count > 0, "All candidate prediction/truth/manifest artifacts are present."),
        ("validation_only_calibration_params", params.empty or params["uses_validation_only"].map(boolish).all(), "Calibration parameters are fit on validation only."),
        ("test_not_used_for_calibration", params.empty or (~params["uses_test_for_calibration"].map(boolish)).all(), "Test rows are not used to estimate calibration parameters."),
        ("baseline_replay_matches_r25", baseline_max_diff <= args.baseline_match_tolerance, f"Baseline replay max absolute AQL difference is {baseline_max_diff:.6g}."),
        ("selection_test_audit_only", selection.empty or selection["test_metrics_role"].astype(str).eq("audit_only_after_frozen_validation_selection").all(), "Test metrics remain audit-only."),
        ("no_launch_yaml_written", not any(out_dir.glob("*.yaml")) and not any(out_dir.glob("*.yml")), "No launch YAML was written."),
        ("no_registry_manuscript_article_mutation", True, "Registry, manuscript, and article mutation remain blocked."),
    ]
    return pd.DataFrame([{"gate": gate, "passed": bool(passed), "detail": detail} for gate, passed, detail in gates])


def baseline_replay_diff(selection: pd.DataFrame) -> float:
    if selection.empty:
        return float("inf")
    base = selection[selection["calibration_rule"].astype(str).eq("baseline_replay")].copy()
    if base.empty:
        return float("inf")
    diffs = pd.concat(
        [
            (base["AQL_val"] - base["r25_uncalibrated_val_AQL"]).abs(),
            (base["AQL_test"] - base["r25_uncalibrated_test_AQL"]).abs(),
        ],
        ignore_index=True,
    )
    return finite_float(diffs.max(), default=float("inf"))


def source_manifest(args: argparse.Namespace) -> pd.DataFrame:
    specs = [
        ("stage_r26_summary", Path(args.stage_r26_closeout_dir) / R26_SUMMARY, "json"),
        ("stage_r26_metric_rows", Path(args.stage_r26_closeout_dir) / R26_METRIC_ROWS, "csv"),
        ("stage_r26_validation_selected", Path(args.stage_r26_closeout_dir) / R26_SELECTED, "csv"),
        ("stage_r26_test_oracle", Path(args.stage_r26_closeout_dir) / R26_ORACLE, "csv"),
        ("stage_r25_launch_manifest", Path(args.stage_r25_prep_dir) / R25_MANIFEST, "csv"),
        ("data_config", Path(args.data_config), "yaml"),
    ]
    rows = []
    for label, path, kind in specs:
        full = repo_path(path)
        rows.append(
            {
                "label": label,
                "kind": kind,
                "path": repo_relative(full),
                "exists": full.exists(),
                "size_bytes": int(full.stat().st_size) if full.exists() and full.is_file() else 0,
                "sha256": sha256_file_or_blank(full) if full.exists() and full.is_file() else "",
            }
        )
    return pd.DataFrame(rows)


def markdown_table(frame: pd.DataFrame, max_rows: int = 20) -> str:
    if frame.empty:
        return "_No rows._"
    work = frame.head(max_rows).copy()
    cols = list(work.columns)
    lines = ["| " + " | ".join(cols) + " |", "| " + " | ".join(["---"] * len(cols)) + " |"]
    for _, row in work.iterrows():
        vals = []
        for col in cols:
            value = row[col]
            text = "" if isinstance(value, float) and math.isnan(value) else str(value)
            vals.append(text.replace("|", "\\|").replace("\n", " "))
        lines.append("| " + " | ".join(vals) + " |")
    if frame.shape[0] > work.shape[0]:
        lines.extend(["", f"_Showing {work.shape[0]} of {frame.shape[0]} rows._"])
    return "\n".join(lines)


def build_report(summary: dict[str, Any], case_sel: pd.DataFrame, mechanism: pd.DataFrame, next_plan: pd.DataFrame, gates: pd.DataFrame) -> str:
    display_cols = [
        "selection_scope",
        "region",
        "fold",
        "stage_r25_arm",
        "method_id",
        "calibration_rule",
        "AQL_val",
        "AQL_test",
        "calibration_delta_test_AQL",
        "test_minus_pricefm",
        "beats_both_on_test",
        "promotion_gate_status",
    ]
    return "\n".join(
        [
            "# PriceFM Stage-R27 Calibration and Information-Set Parity Audit",
            "",
            "## Executive Summary",
            "",
            f"- Status: `{summary['status']}`.",
            f"- Candidate rows audited: {summary['n_candidate_rows']}.",
            f"- Calibration metric rows: {summary['n_calibration_metric_rows']}.",
            f"- Full-surface validation-selected calibrated rows beating both: {summary['n_full_surface_calibrated_beat_both']}.",
            f"- R26-selected-only calibrated rows beating both: {summary['n_r26_selected_calibrated_beat_both']}.",
            f"- Best full-surface calibrated PriceFM gap: {summary['best_full_surface_selected_test_minus_pricefm']}.",
            f"- Best R26-selected calibrated PriceFM gap: {summary['best_r26_selected_test_minus_pricefm']}.",
            "",
            "This is a read-only audit. It estimates postfit calibration parameters on validation rows only and uses test rows only after frozen validation selection.",
            "",
            "## Case Selection",
            "",
            markdown_table(case_sel[[c for c in display_cols if c in case_sel.columns]], 35),
            "",
            "## Mechanism Diagnosis",
            "",
            markdown_table(mechanism, 20),
            "",
            "## Next Action Plan",
            "",
            markdown_table(next_plan, 10),
            "",
            "## Gates",
            "",
            markdown_table(gates, 20),
            "",
            "## Do Not Do Yet",
            "",
            "- Do not launch new PriceFM jobs from this stage.",
            "- Do not run MCMC unless a future full-quantile confirmation gate exists.",
            "- Do not mutate the registry, manuscript, or article.",
            "- Do not promote test-oracle rows.",
            "",
        ]
    )


def run(args: argparse.Namespace) -> dict[str, Any]:
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and any(out_dir.iterdir()) and not bool(args.force):
        raise FileExistsError(f"{out_dir} exists; rerun with --force true")
    out_dir.mkdir(parents=True, exist_ok=True)

    closeout = Path(args.stage_r26_closeout_dir)
    prep = Path(args.stage_r25_prep_dir)
    r26_summary = read_json_required(closeout / R26_SUMMARY, "Stage-R26 final summary")
    metric = normalize_metric_rows(read_csv_required(closeout / R26_METRIC_ROWS, "Stage-R26 metric rows"))
    selected = read_csv_required(closeout / R26_SELECTED, "Stage-R26 validation-selected rows")
    oracle = read_csv_required(closeout / R26_ORACLE, "Stage-R26 test oracle rows")
    manifest = read_csv_required(prep / R25_MANIFEST, "Stage-R25 launch manifest")

    candidates = row_role(metric, selected, oracle)
    manifest_cols = [c for c in manifest.columns if c not in candidates.columns or c == "experiment_id"]
    candidates = candidates.merge(manifest[manifest_cols], on="experiment_id", how="left", validate="many_to_one", suffixes=("", "_manifest"))
    readiness = build_readiness(candidates)
    y_scalers = load_y_scalers(args.data_config, candidates, bool(args.allow_missing_scalers))
    params, metrics = run_calibration_surface(candidates, readiness, y_scalers)
    selection = selection_gate(metrics, candidates, args.primary_unit)
    case_sel = case_selection(selection)
    parity = feature_manifest_rows(candidates, selection)
    mechanism = mechanism_diagnosis(selection, case_sel, parity)

    full_sel = case_sel[case_sel["selection_scope"].astype(str).eq("full_surface_calibrated")] if not case_sel.empty else pd.DataFrame()
    r26_sel = case_sel[case_sel["selection_scope"].astype(str).eq("r26_selected_only_calibrated")] if not case_sel.empty else pd.DataFrame()
    baseline_diff = baseline_replay_diff(selection)
    summary = {
        "stage": "pricefm_stage_r27_calibration_parity_audit",
        "status": "completed_read_only_calibration_parity_audit",
        "source_stage_r26_status": r26_summary.get("status", ""),
        "n_candidate_rows": int(candidates.shape[0]),
        "n_ready_candidate_rows": int(readiness["readiness_status"].astype(str).eq("ready").sum()) if not readiness.empty else 0,
        "n_calibration_param_rows": int(params.shape[0]),
        "n_calibration_metric_rows": int(metrics.shape[0]),
        "n_selection_gate_rows": int(selection.shape[0]),
        "n_case_selection_rows": int(case_sel.shape[0]),
        "n_full_surface_calibrated_beat_both": int(full_sel["beats_both_on_test"].map(boolish).sum()) if not full_sel.empty else 0,
        "n_r26_selected_calibrated_beat_both": int(r26_sel["beats_both_on_test"].map(boolish).sum()) if not r26_sel.empty else 0,
        "n_full_surface_calibrated_pricefm_wins": int(full_sel["beats_pricefm_on_test"].map(boolish).sum()) if not full_sel.empty else 0,
        "n_r26_selected_calibrated_pricefm_wins": int(r26_sel["beats_pricefm_on_test"].map(boolish).sum()) if not r26_sel.empty else 0,
        "best_full_surface_selected_test_minus_pricefm": best_or_blank(full_sel, "test_minus_pricefm"),
        "best_r26_selected_test_minus_pricefm": best_or_blank(r26_sel, "test_minus_pricefm"),
        "best_any_calibrated_test_minus_pricefm": best_or_blank(selection[selection["calibration_rule"].astype(str).ne("baseline_replay")] if not selection.empty else selection, "test_minus_pricefm"),
        "baseline_replay_max_abs_AQL_diff": baseline_diff,
        "launches_models": False,
        "fits_models": False,
        "writes_launch_yaml": False,
        "registry_mutation_authorized": False,
        "manuscript_mutation_authorized": False,
        "article_update_justified": False,
    }
    next_plan = next_action_plan(summary)
    gates = no_launch_gates(args, readiness, params, selection, out_dir, baseline_diff)
    if not gates["passed"].map(boolish).all():
        failed = gates.loc[~gates["passed"].map(boolish), "gate"].tolist()
        raise RuntimeError(f"Stage-R27 no-launch gates failed: {failed}")

    outputs = {
        "candidate_readiness": out_dir / OUT_READINESS,
        "calibration_params": out_dir / OUT_PARAMS,
        "calibration_metrics": out_dir / OUT_METRICS,
        "selection_gate": out_dir / OUT_SELECTION,
        "case_selection": out_dir / OUT_CASE_SELECTION,
        "information_set_parity": out_dir / OUT_PARITY,
        "mechanism_diagnosis": out_dir / OUT_MECHANISM,
        "next_action_plan": out_dir / OUT_NEXT,
        "gates": out_dir / OUT_GATES,
        "source_manifest": out_dir / OUT_SOURCE,
        "report": out_dir / OUT_REPORT,
        "summary_json": out_dir / "summary.json",
    }
    write_frame(outputs["candidate_readiness"], readiness)
    write_frame(outputs["calibration_params"], params)
    write_frame(outputs["calibration_metrics"], metrics)
    write_frame(outputs["selection_gate"], selection)
    write_frame(outputs["case_selection"], case_sel)
    write_frame(outputs["information_set_parity"], parity)
    write_frame(outputs["mechanism_diagnosis"], mechanism)
    write_frame(outputs["next_action_plan"], next_plan)
    write_frame(outputs["gates"], gates)
    write_frame(outputs["source_manifest"], source_manifest(args))
    summary["outputs"] = {key: repo_relative(path) for key, path in outputs.items()}
    write_json(outputs["summary_json"], summary)
    outputs["report"].write_text(build_report(summary, case_sel, mechanism, next_plan, gates))
    return summary


def best_or_blank(frame: pd.DataFrame, col: str) -> float | str:
    if frame.empty or col not in frame.columns:
        return ""
    return finite_float(pd.to_numeric(frame[col], errors="coerce").min())


def main() -> None:
    args = parser().parse_args()
    print(json.dumps(run(args), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
