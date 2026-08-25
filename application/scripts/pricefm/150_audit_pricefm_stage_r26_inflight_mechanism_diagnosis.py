#!/usr/bin/env python3
"""Read-only PriceFM Stage-R26 in-flight mechanism diagnosis for Stage-R25."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json
from pricefm_full_surface import BINARY_SUFFIXES, QDESN_PREFIX, repo_relative, sha256_file_or_blank


DEFAULT_R21_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r21_failure_atlas_20260709"
)
DEFAULT_R22D_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r22d_case_specific_screening_closeout_20260709"
)
DEFAULT_R23_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r23_mechanism_capability_audit_20260709"
)
DEFAULT_R24_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r24_postfit_calibration_materialized_20260709"
)
DEFAULT_R25_PREP_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r25_post_r24_broad_launch_prep_20260709"
)
DEFAULT_R25_GRID_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_r25_post_r24_broad_horizon_weighted_20260709"
)
DEFAULT_R25_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_r25_post_r24_broad_horizon_weighted_20260709"
)
DEFAULT_R25_LOG_ROOT = "application/data_local/pricefm/logs"
DEFAULT_RUN_TAG = "pricefm_stage_r25_post_r24_broad_horizon_weighted_20260709"
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r26_inflight_mechanism_diagnosis_20260710"
)

R21_ATLAS = "pricefm_stage_r21_failure_atlas.csv"
R22D_CASE_SUMMARY = "pricefm_stage_r22d_case_summary.csv"
R22D_METRIC_ROWS = "pricefm_stage_r22d_metric_rows.csv"
R22D_HORIZON = "pricefm_stage_r22d_horizon_group_diagnostics.csv"
R23_CAPABILITY = "pricefm_stage_r23_runner_capability_matrix.csv"
R23_QUEUE = "pricefm_stage_r23_case_next_mechanism_queue.csv"
R23_BOUNDS = "pricefm_stage_r23_expensive_path_bounds_recommendation.csv"
R24_READINESS = "pricefm_stage_r24_postfit_readiness.csv"
R24_GATE = "pricefm_stage_r24_postfit_candidate_gate.csv"
R25_MANIFEST = "pricefm_stage_r25_launch_manifest.csv"
R25_ARM_PLAN = "pricefm_stage_r25_arm_plan.csv"
R25_CASE_PLAN = "pricefm_stage_r25_case_plan.csv"

OUT_HEALTH = "pricefm_stage_r26_r25_health.csv"
OUT_CASE_PROGRESS = "pricefm_stage_r26_case_progress.csv"
OUT_METRIC_ROWS = "pricefm_stage_r26_partial_metric_rows.csv"
OUT_VALIDATION_SELECTED = "pricefm_stage_r26_partial_validation_selected_case.csv"
OUT_TEST_ORACLE = "pricefm_stage_r26_partial_test_oracle_case.csv"
OUT_ARM_SUMMARY = "pricefm_stage_r26_arm_mechanism_summary.csv"
OUT_HORIZON_SUMMARY = "pricefm_stage_r26_horizon_mechanism_summary.csv"
OUT_FAILURE_MAP = "pricefm_stage_r26_failure_decomposition_map.csv"
OUT_MCMC_GATE = "pricefm_stage_r26_mcmc_confirmation_gate.csv"
OUT_NEXT_ACTION = "pricefm_stage_r26_next_action_plan.csv"
OUT_GATES = "pricefm_stage_r26_diagnosis_gates.csv"
OUT_SOURCE = "source_manifest.csv"
OUT_REPORT = "pricefm_stage_r26_inflight_mechanism_diagnosis_report.md"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r21-dir", default=DEFAULT_R21_DIR)
    p.add_argument("--stage-r22d-dir", default=DEFAULT_R22D_DIR)
    p.add_argument("--stage-r23-dir", default=DEFAULT_R23_DIR)
    p.add_argument("--stage-r24-dir", default=DEFAULT_R24_DIR)
    p.add_argument("--stage-r25-prep-dir", default=DEFAULT_R25_PREP_DIR)
    p.add_argument("--stage-r25-grid-root", default=DEFAULT_R25_GRID_ROOT)
    p.add_argument("--stage-r25-run-root", default=DEFAULT_R25_RUN_ROOT)
    p.add_argument("--stage-r25-log-root", default=DEFAULT_R25_LOG_ROOT)
    p.add_argument("--run-tag", default=DEFAULT_RUN_TAG)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--expected-experiments", type=int, default=200)
    p.add_argument("--expected-cases", type=int, default=20)
    p.add_argument("--arms-per-case", type=int, default=10)
    p.add_argument("--near-miss-pricefm-margin", type=float, default=0.15)
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
        return default
    return out if math.isfinite(out) else default


def read_csv_required(path: str | Path, label: str) -> pd.DataFrame:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required CSV: {full}")
    return pd.read_csv(full, low_memory=False)


def read_csv_optional(path: str | Path) -> pd.DataFrame:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        return pd.DataFrame()
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


def normalize_keys(frame: pd.DataFrame, label: str) -> pd.DataFrame:
    require_columns(frame, ["region", "fold"], label)
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    return out


def normalize_manifest(frame: pd.DataFrame) -> pd.DataFrame:
    require_columns(
        frame,
        [
            "experiment_id",
            "region",
            "fold",
            "stage_r22b_case_id",
            "stage_r25_arm",
            "pricefm_gap_tier",
            "horizon_focus",
            "horizon_weighting_enabled",
            "horizon_weight_multiplier",
            "feature_policy",
            "lag_window",
            "depth",
            "units",
            "feature_dim",
            "state_output",
            "alpha",
            "rho",
            "input_scale",
            "tau0",
            "selection_is_validation_only",
            "test_metrics_role",
            "mutates_registry",
            "mutates_manuscript",
        ],
        "Stage-R25 launch manifest",
    )
    out = normalize_keys(frame, "Stage-R25 launch manifest")
    out["experiment_id"] = out["experiment_id"].astype(str)
    out["stage_r22b_case_id"] = out["stage_r22b_case_id"].astype(str)
    out["stage_r25_arm"] = out["stage_r25_arm"].astype(str)
    return out


def metric_paths(run_dir: Path) -> dict[str, Path | None]:
    return {
        "metric_summary": next(iter(sorted(run_dir.rglob("metric_summary.csv"))), None),
        "horizon_group": next(iter(sorted(run_dir.rglob("metric_by_horizon_group.csv"))), None),
        "training_weight_summary": next(iter(sorted(run_dir.rglob("training_weight_summary.csv"))), None),
        "cell_status": run_dir / "cell_status.csv" if (run_dir / "cell_status.csv").exists() else None,
    }


def read_cell_status(run_dir: Path) -> dict[str, Any]:
    path = run_dir / "cell_status.csv"
    if not path.exists() or path.stat().st_size == 0:
        return {"status": "missing_cell_status"}
    frame = pd.read_csv(path)
    if frame.empty:
        return {"status": "empty_cell_status"}
    return frame.iloc[0].to_dict()


def best_by_prefix(frame: pd.DataFrame, prefix: str) -> pd.Series:
    subset = frame[frame["method_id"].astype(str).str.startswith(prefix)].copy()
    if subset.empty:
        return pd.Series(dtype=object)
    subset["AQL_num"] = pd.to_numeric(subset["AQL"], errors="coerce")
    return subset.sort_values(["AQL_num", "method_id"]).iloc[0]


def metric_summary_rows(metric_path: Path) -> list[dict[str, Any]]:
    frame = pd.read_csv(metric_path)
    require_columns(frame, ["method_id", "split", "unit", "AQL", "MAE", "RMSE"], "metric summary")
    frame = frame[frame["unit"].astype(str).eq("original")].copy()
    frame = frame[frame["method_id"].astype(str).str.startswith(QDESN_PREFIX)].copy()
    rows: list[dict[str, Any]] = []
    for method_id, group in frame.groupby("method_id", sort=True):
        row: dict[str, Any] = {"method_id": method_id}
        for _, part in group.iterrows():
            split = str(part["split"])
            row[f"{split}_AQL"] = finite_float(part.get("AQL"))
            row[f"{split}_MAE"] = finite_float(part.get("MAE"))
            row[f"{split}_RMSE"] = finite_float(part.get("RMSE"))
        rows.append(row)
    return rows


def build_r25_run_tables(
    manifest: pd.DataFrame,
    arm_plan: pd.DataFrame,
    run_root: str | Path,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    root = repo_path(run_root)
    base = normalize_keys(arm_plan, "Stage-R25 arm plan").set_index(["region", "fold", "stage_r25_arm"], drop=False)
    metric_rows: list[dict[str, Any]] = []
    status_rows: list[dict[str, Any]] = []
    horizon_frames: list[pd.DataFrame] = []
    for _, prep in manifest.iterrows():
        exp_id = str(prep["experiment_id"])
        run_dir = root / exp_id
        paths = metric_paths(run_dir) if run_dir.exists() else {
            "metric_summary": None,
            "horizon_group": None,
            "training_weight_summary": None,
            "cell_status": None,
        }
        cell_status = read_cell_status(run_dir) if run_dir.exists() else {"status": "missing_run_dir"}
        metric_path = paths["metric_summary"]
        horizon_path = paths["horizon_group"]
        metric_status = "completed" if metric_path is not None and str(cell_status.get("status", "")).lower() == "completed" else "missing_or_incomplete"
        status_rows.append(
            {
                "experiment_id": exp_id,
                "region": prep["region"],
                "fold": int(prep["fold"]),
                "stage_r25_arm": prep["stage_r25_arm"],
                "horizon_focus": prep["horizon_focus"],
                "pricefm_gap_tier": prep["pricefm_gap_tier"],
                "feature_policy": prep["feature_policy"],
                "cell_status": cell_status.get("status", "missing"),
                "metric_status": metric_status,
                "cell_elapsed_seconds": finite_float(cell_status.get("elapsed_seconds")),
                "run_dir": repo_relative(run_dir),
                "metric_summary": repo_relative(metric_path) if metric_path is not None else "",
                "horizon_group": repo_relative(horizon_path) if horizon_path is not None else "",
                "training_weight_summary": repo_relative(paths["training_weight_summary"]) if paths["training_weight_summary"] is not None else "",
            }
        )
        if metric_path is None:
            continue
        key = (prep["region"], int(prep["fold"]), prep["stage_r25_arm"])
        if key not in base.index:
            raise ValueError(f"Stage-R25 arm plan missing baseline for {key}")
        b = base.loc[key]
        metric_frame = pd.read_csv(metric_path)
        test_original = metric_frame[
            metric_frame["split"].astype(str).eq("test") & metric_frame["unit"].astype(str).eq("original")
        ]
        naive = best_by_prefix(test_original, "naive")
        normal = best_by_prefix(test_original, "normal")
        best_naive_aql = finite_float(naive.get("AQL")) if not naive.empty else float("nan")
        best_normal_aql = finite_float(normal.get("AQL")) if not normal.empty else float("nan")
        for metric in metric_summary_rows(metric_path):
            row = {
                **prep.to_dict(),
                "method_id": metric["method_id"],
                "val_AQL": finite_float(metric.get("val_AQL")),
                "val_MAE": finite_float(metric.get("val_MAE")),
                "val_RMSE": finite_float(metric.get("val_RMSE")),
                "test_AQL": finite_float(metric.get("test_AQL")),
                "test_MAE": finite_float(metric.get("test_MAE")),
                "test_RMSE": finite_float(metric.get("test_RMSE")),
                "current_qdesn_AQL": finite_float(b["current_qdesn_AQL"]),
                "current_pricefm_AQL": finite_float(b["current_pricefm_AQL"]),
                "r22d_validation_selected_minus_current_qdesn": finite_float(b.get("validation_selected_minus_current_qdesn")),
                "r22d_validation_selected_minus_pricefm": finite_float(b.get("validation_selected_minus_pricefm")),
                "best_naive_AQL": best_naive_aql,
                "best_normal_AQL": best_normal_aql,
                "metric_summary": repo_relative(metric_path),
            }
            row["test_minus_current_qdesn"] = row["test_AQL"] - row["current_qdesn_AQL"]
            row["test_minus_pricefm"] = row["test_AQL"] - row["current_pricefm_AQL"]
            row["test_minus_r22d_validation_selected"] = row["test_minus_pricefm"] - row["r22d_validation_selected_minus_pricefm"]
            row["test_minus_best_reference"] = row["test_AQL"] - min(row["current_qdesn_AQL"], row["current_pricefm_AQL"])
            row["test_minus_best_naive"] = row["test_AQL"] - row["best_naive_AQL"]
            row["test_minus_best_normal"] = row["test_AQL"] - row["best_normal_AQL"]
            row["beats_current_qdesn_on_test"] = row["test_minus_current_qdesn"] < 0.0
            row["beats_pricefm_on_test"] = row["test_minus_pricefm"] < 0.0
            row["beats_both_on_test"] = row["beats_current_qdesn_on_test"] and row["beats_pricefm_on_test"]
            row["improves_over_r22d_validation_selected"] = row["test_minus_r22d_validation_selected"] < 0.0
            row["beats_best_naive_on_test"] = row["test_minus_best_naive"] < 0.0
            row["beats_best_normal_on_test"] = row["test_minus_best_normal"] < 0.0
            metric_rows.append(row)
        if horizon_path is not None:
            horizon = pd.read_csv(horizon_path)
            horizon["experiment_id"] = exp_id
            horizon["region"] = prep["region"]
            horizon["fold"] = int(prep["fold"])
            horizon["stage_r25_arm"] = prep["stage_r25_arm"]
            horizon["horizon_focus"] = prep["horizon_focus"]
            horizon["feature_policy"] = prep["feature_policy"]
            horizon_frames.append(horizon)
    return (
        pd.DataFrame(metric_rows),
        pd.DataFrame(status_rows),
        pd.concat(horizon_frames, ignore_index=True) if horizon_frames else pd.DataFrame(),
    )


def selected_by_validation(metric_rows: pd.DataFrame) -> pd.DataFrame:
    if metric_rows.empty:
        return metric_rows.copy()
    valid = metric_rows[metric_rows["val_AQL"].map(lambda x: math.isfinite(finite_float(x)))].copy()
    rows = []
    for _, group in valid.groupby(["region", "fold"], sort=True):
        row = group.sort_values(["val_AQL", "test_AQL", "experiment_id", "method_id"]).iloc[0].to_dict()
        row["case_selected_by"] = "validation_AQL_only_across_completed_stage_r25_candidates"
        row["test_metrics_use"] = "audit_only_partial_until_r25_completion"
        rows.append(row)
    return pd.DataFrame(rows).sort_values(["region", "fold"]).reset_index(drop=True)


def case_test_oracle(metric_rows: pd.DataFrame) -> pd.DataFrame:
    if metric_rows.empty:
        return metric_rows.copy()
    rows = []
    for _, group in metric_rows.groupby(["region", "fold"], sort=True):
        row = group.sort_values(["test_AQL", "val_AQL", "experiment_id", "method_id"]).iloc[0].to_dict()
        row["case_oracle_by"] = "test_AQL_audit_only_across_completed_stage_r25_candidates"
        rows.append(row)
    return pd.DataFrame(rows).sort_values(["test_minus_pricefm", "region", "fold"]).reset_index(drop=True)


def summary_by(frame: pd.DataFrame, by: str) -> pd.DataFrame:
    if frame.empty:
        return pd.DataFrame()
    return (
        frame.groupby(by, as_index=False)
        .agg(
            rows=("experiment_id", "size"),
            cases=("stage_r22b_case_id", "nunique"),
            beats_current_qdesn=("beats_current_qdesn_on_test", "sum"),
            beats_pricefm=("beats_pricefm_on_test", "sum"),
            beats_both=("beats_both_on_test", "sum"),
            improves_over_r22d=("improves_over_r22d_validation_selected", "sum"),
            best_test_minus_pricefm=("test_minus_pricefm", "min"),
            median_test_minus_pricefm=("test_minus_pricefm", "median"),
            best_test_minus_current_qdesn=("test_minus_current_qdesn", "min"),
            median_test_minus_current_qdesn=("test_minus_current_qdesn", "median"),
            best_test_minus_r22d_validation_selected=("test_minus_r22d_validation_selected", "min"),
            median_test_minus_r22d_validation_selected=("test_minus_r22d_validation_selected", "median"),
            median_test_minus_best_naive=("test_minus_best_naive", "median"),
            median_test_minus_best_normal=("test_minus_best_normal", "median"),
        )
        .sort_values(["best_test_minus_pricefm", by])
        .reset_index(drop=True)
    )


def horizon_summary(horizon: pd.DataFrame, selected: pd.DataFrame) -> pd.DataFrame:
    if horizon.empty or selected.empty:
        return pd.DataFrame()
    require_columns(horizon, ["experiment_id", "method_id", "split", "unit", "horizon_group", "AQL"], "Stage-R25 horizon diagnostics")
    selected_index = selected.set_index("experiment_id", drop=False)
    rows: list[dict[str, Any]] = []
    test = horizon[horizon["split"].astype(str).eq("test") & horizon["unit"].astype(str).eq("original")].copy()
    for exp_id, group in test.groupby("experiment_id", sort=True):
        if exp_id not in selected_index.index:
            continue
        sel = selected_index.loc[exp_id]
        method = str(sel["method_id"])
        q = group[group["method_id"].astype(str).eq(method)]
        for horizon_group, hgroup in group.groupby("horizon_group", sort=True):
            qh = q[q["horizon_group"].astype(str).eq(str(horizon_group))]
            if qh.empty:
                continue
            naive = best_by_prefix(hgroup, "naive")
            normal = best_by_prefix(hgroup, "normal")
            q_aql = finite_float(qh.iloc[0]["AQL"])
            naive_aql = finite_float(naive.get("AQL")) if not naive.empty else float("nan")
            normal_aql = finite_float(normal.get("AQL")) if not normal.empty else float("nan")
            rows.append(
                {
                    "experiment_id": exp_id,
                    "region": sel["region"],
                    "fold": int(sel["fold"]),
                    "stage_r25_arm": sel["stage_r25_arm"],
                    "method_id": method,
                    "horizon_focus": sel["horizon_focus"],
                    "horizon_group": horizon_group,
                    "is_primary_horizon": str(horizon_group) == str(sel["horizon_focus"]),
                    "qdesn_AQL": q_aql,
                    "best_naive_AQL": naive_aql,
                    "qdesn_minus_best_naive_AQL": q_aql - naive_aql,
                    "beats_best_naive": q_aql < naive_aql,
                    "best_normal_AQL": normal_aql,
                    "qdesn_minus_best_normal_AQL": q_aql - normal_aql,
                    "beats_best_normal": q_aql < normal_aql,
                }
            )
    diag = pd.DataFrame(rows)
    if diag.empty:
        return diag
    return (
        diag.groupby("horizon_group", as_index=False)
        .agg(
            rows=("experiment_id", "size"),
            cases=("experiment_id", "nunique"),
            primary_rows=("is_primary_horizon", "sum"),
            beats_best_naive=("beats_best_naive", "sum"),
            beats_best_normal=("beats_best_normal", "sum"),
            median_minus_best_naive=("qdesn_minus_best_naive_AQL", "median"),
            median_minus_best_normal=("qdesn_minus_best_normal_AQL", "median"),
            best_minus_best_naive=("qdesn_minus_best_naive_AQL", "min"),
            best_minus_best_normal=("qdesn_minus_best_normal_AQL", "min"),
        )
        .sort_values(["horizon_group"])
        .reset_index(drop=True)
    )


def case_progress(manifest: pd.DataFrame, status: pd.DataFrame) -> pd.DataFrame:
    planned = manifest.groupby(["region", "fold"], as_index=False).agg(planned_experiments=("experiment_id", "size"))
    started = status[status["cell_status"].astype(str).ne("missing_run_dir")].groupby(["region", "fold"], as_index=False).agg(started_experiments=("experiment_id", "size"))
    completed = status[status["metric_status"].astype(str).eq("completed")].groupby(["region", "fold"], as_index=False).agg(completed_experiments=("experiment_id", "size"))
    out = planned.merge(started, on=["region", "fold"], how="left").merge(completed, on=["region", "fold"], how="left")
    out[["started_experiments", "completed_experiments"]] = out[["started_experiments", "completed_experiments"]].fillna(0).astype(int)
    out["remaining_experiments"] = out["planned_experiments"] - out["completed_experiments"]
    out["case_status"] = out.apply(
        lambda r: "complete" if int(r["completed_experiments"]) == int(r["planned_experiments"])
        else "not_started" if int(r["started_experiments"]) == 0
        else "in_progress",
        axis=1,
    )
    return out.sort_values(["case_status", "region", "fold"]).reset_index(drop=True)


def classify_failure(row: pd.Series, near_margin: float) -> str:
    if boolish(row.get("beats_both_on_test")):
        return "promotion_candidate"
    if boolish(row.get("beats_current_qdesn_on_test")) and finite_float(row.get("test_minus_pricefm")) <= near_margin:
        return "mcmc_near_miss_consider_only_after_r25_completion"
    if boolish(row.get("beats_current_qdesn_on_test")):
        return "internal_qdesn_improvement_but_pricefm_gap_remains"
    if boolish(row.get("improves_over_r22d_validation_selected")):
        return "mechanism_progress_but_not_registry_ready"
    if finite_float(row.get("test_minus_pricefm")) > 1.0:
        return "structural_pricefm_gap_persists"
    return "nearer_gap_but_not_promotable"


def failure_decomposition(
    selected: pd.DataFrame,
    oracle: pd.DataFrame,
    r21: pd.DataFrame,
    r22d_case: pd.DataFrame,
    r23_queue: pd.DataFrame,
    near_margin: float,
) -> pd.DataFrame:
    if selected.empty:
        return pd.DataFrame()
    out = selected.copy()
    r21_cols = [
        "region",
        "fold",
        "stage_r21_primary_failure_pattern",
        "stage_r21_recommended_mechanism",
        "failure_mode",
        "worst_horizon_group_r21",
        "early_1_24_delta_AQL_qdesn_minus_pricefm",
        "best_overall_gap_bucket",
    ]
    r22_cols = [
        "region",
        "fold",
        "validation_selected_minus_pricefm",
        "test_oracle_minus_pricefm",
        "validation_selected_beats_both",
        "test_oracle_beats_both",
    ]
    r23_cols = [
        "region",
        "fold",
        "recommended_stage_r23_queue",
        "expensive_launch_readiness",
        "ready_postfit_candidates",
        "blocked_postfit_candidates",
    ]
    out = out.merge(normalize_keys(r21[r21_cols], "Stage-R21 atlas"), on=["region", "fold"], how="left")
    out = out.merge(normalize_keys(r22d_case[r22_cols], "Stage-R22D case summary"), on=["region", "fold"], how="left", suffixes=("", "_r22d_case"))
    out = out.merge(normalize_keys(r23_queue[r23_cols], "Stage-R23 queue"), on=["region", "fold"], how="left")
    oracle_cols = [
        "region",
        "fold",
        "experiment_id",
        "stage_r25_arm",
        "method_id",
        "test_AQL",
        "test_minus_current_qdesn",
        "test_minus_pricefm",
        "beats_both_on_test",
    ]
    if not oracle.empty:
        renamed = oracle[oracle_cols].rename(
            columns={
                "experiment_id": "test_oracle_experiment_id",
                "stage_r25_arm": "test_oracle_stage_r25_arm",
                "method_id": "test_oracle_method_id",
                "test_AQL": "test_oracle_AQL",
                "test_minus_current_qdesn": "test_oracle_minus_current_qdesn",
                "test_minus_pricefm": "test_oracle_minus_pricefm",
                "beats_both_on_test": "test_oracle_beats_both_on_test",
            }
        )
        out = out.merge(renamed, on=["region", "fold"], how="left")
    out["partial_diagnosis"] = out.apply(lambda r: classify_failure(r, near_margin), axis=1)
    out["mcmc_gate_status"] = out.apply(
        lambda r: "eligible_after_final_closeout" if boolish(r.get("beats_both_on_test"))
        else "near_miss_discuss_after_final_closeout" if (
            boolish(r.get("beats_current_qdesn_on_test")) and finite_float(r.get("test_minus_pricefm")) <= near_margin
        )
        else "blocked_no_pricefm_or_beat_both_signal",
        axis=1,
    )
    out["registry_article_gate_status"] = out["beats_both_on_test"].map(
        lambda x: "blocked_until_full_quantile_and_mcmc_confirmation" if boolish(x) else "blocked_no_beat_both_candidate"
    )
    cols = [
        "region",
        "fold",
        "stage_r22b_case_id",
        "stage_r25_arm",
        "method_id",
        "val_AQL",
        "test_AQL",
        "current_qdesn_AQL",
        "current_pricefm_AQL",
        "test_minus_current_qdesn",
        "test_minus_pricefm",
        "test_minus_r22d_validation_selected",
        "beats_current_qdesn_on_test",
        "beats_pricefm_on_test",
        "beats_both_on_test",
        "improves_over_r22d_validation_selected",
        "stage_r21_primary_failure_pattern",
        "stage_r21_recommended_mechanism",
        "failure_mode",
        "worst_horizon_group_r21",
        "early_1_24_delta_AQL_qdesn_minus_pricefm",
        "best_overall_gap_bucket",
        "validation_selected_minus_pricefm",
        "test_oracle_minus_pricefm",
        "recommended_stage_r23_queue",
        "expensive_launch_readiness",
        "ready_postfit_candidates",
        "blocked_postfit_candidates",
        "test_oracle_experiment_id",
        "test_oracle_stage_r25_arm",
        "test_oracle_method_id",
        "test_oracle_AQL",
        "test_oracle_minus_current_qdesn",
        "test_oracle_minus_pricefm",
        "test_oracle_beats_both_on_test",
        "partial_diagnosis",
        "mcmc_gate_status",
        "registry_article_gate_status",
    ]
    return out[[c for c in cols if c in out.columns]].sort_values(["test_minus_pricefm", "region", "fold"]).reset_index(drop=True)


def mcmc_gate(failure_map: pd.DataFrame, near_margin: float) -> pd.DataFrame:
    if failure_map.empty:
        return pd.DataFrame()
    out = failure_map[
        failure_map["mcmc_gate_status"].isin(["eligible_after_final_closeout", "near_miss_discuss_after_final_closeout"])
    ].copy()
    if out.empty:
        return pd.DataFrame(
            columns=[
                "region",
                "fold",
                "stage_r25_arm",
                "method_id",
                "test_minus_current_qdesn",
                "test_minus_pricefm",
                "mcmc_gate_status",
                "mcmc_gate_reason",
            ]
        )
    out["mcmc_gate_reason"] = out["mcmc_gate_status"].map(
        {
            "eligible_after_final_closeout": "validation-selected row beats current Q-DESN and PriceFM; MCMC can confirm after R25 final closeout.",
            "near_miss_discuss_after_final_closeout": f"validation-selected row beats current Q-DESN and is within {near_margin:g} AQL of PriceFM; discuss before MCMC.",
        }
    )
    return out.sort_values(["mcmc_gate_status", "test_minus_pricefm", "region", "fold"]).reset_index(drop=True)


def next_action_plan(summary: dict[str, Any], failure_map: pd.DataFrame) -> pd.DataFrame:
    rows = [
        {
            "priority": 1,
            "action": "wait_for_r25_completion",
            "condition": "launcher_exit_file_missing_or_incomplete_metric_count",
            "rationale": "R25 is still running; partial evidence is diagnostic but not final for promotion.",
            "allowed_now": summary["r25_run_state"] != "completed_cleanly",
        },
        {
            "priority": 2,
            "action": "run_final_stage_r26_closeout_after_exit_zero",
            "condition": "exit_code_zero_and_all_200_metric_summaries_present",
            "rationale": "Final winner selection must use frozen validation-only selection on the complete R25 surface.",
            "allowed_now": summary["r25_run_state"] == "completed_cleanly",
        },
        {
            "priority": 3,
            "action": "do_not_promote_internal_improvements",
            "condition": "candidate_beats_qdesn_but_not_pricefm",
            "rationale": "Internal Q-DESN improvements are mechanism evidence, not article/registry wins against PriceFM.",
            "allowed_now": True,
        },
        {
            "priority": 4,
            "action": "mcmc_only_after_beat_both_or_declared_near_miss",
            "condition": "validation_selected_candidate_beats_both_or_beats_qdesn_and_near_pricefm",
            "rationale": "MCMC should confirm selected VB candidates; it should not be used as a broad rescue for weak VB rows.",
            "allowed_now": False,
        },
        {
            "priority": 5,
            "action": "if_no_pricefm_winner_pivot_mechanism_family",
            "condition": "final_r25_no_validation_selected_pricefm_or_beat_both_rows",
            "rationale": "A negative R25 means true horizon weighting/readout breadth is insufficient; next search should target information-set, calibration-artifact, or objective-family mechanisms.",
            "allowed_now": summary["n_validation_selected_beats_both"] == 0,
        },
    ]
    if not failure_map.empty and int(failure_map["beats_both_on_test"].map(boolish).sum()) > 0:
        rows.append(
            {
                "priority": 0,
                "action": "freeze_candidate_for_full_quantile_confirmation_design",
                "condition": "partial_validation_selected_beat_both_observed",
                "rationale": "A beat-both row would need final R25 confirmation before any promotion queue.",
                "allowed_now": False,
            }
        )
    return pd.DataFrame(rows).sort_values(["priority", "action"]).reset_index(drop=True)


def health_table(
    manifest: pd.DataFrame,
    status: pd.DataFrame,
    grid_root: str | Path,
    log_root: str | Path,
    run_tag: str,
    args: argparse.Namespace,
) -> tuple[pd.DataFrame, dict[str, Any]]:
    grid = repo_path(grid_root)
    logs = repo_path(log_root)
    exit_path = logs / f"{run_tag}.exit"
    launch_status_path = grid / "launch_status.csv"
    launch_summary_csv_path = grid / "launch_summary.csv"
    launch_summary_json_path = grid / "launch_summary.json"
    completed = int(status["metric_status"].astype(str).eq("completed").sum()) if not status.empty else 0
    started = int(status["cell_status"].astype(str).ne("missing_run_dir").sum()) if not status.empty else 0
    total = int(manifest.shape[0])
    exit_text = exit_path.read_text().strip() if exit_path.exists() else ""
    exit_code = int(exit_text) if exit_text.isdigit() else None
    state = "completed_cleanly" if exit_code == 0 and completed == total else "completed_with_incomplete_artifacts" if exit_code == 0 else "still_running_or_waiting_for_exit"
    payload = {
        "planned_experiments": total,
        "started_experiments": started,
        "completed_metric_experiments": completed,
        "remaining_to_metric_completion": max(total - completed, 0),
        "not_started_experiments": max(total - started, 0),
        "started_not_completed_experiments": max(started - completed, 0),
        "percent_complete_metric": round(100.0 * completed / total, 3) if total else 0.0,
        "exit_file_exists": exit_path.exists(),
        "exit_code": exit_code if exit_code is not None else "",
        "launch_status_exists": launch_status_path.exists(),
        "launch_summary_exists": launch_summary_csv_path.exists() or launch_summary_json_path.exists(),
        "r25_run_state": state,
    }
    rows = [{"check": key, "value": value} for key, value in payload.items()]
    return pd.DataFrame(rows), payload


def diagnosis_gates(
    manifest: pd.DataFrame,
    metric_rows: pd.DataFrame,
    status: pd.DataFrame,
    failure_map: pd.DataFrame,
    health: dict[str, Any],
) -> pd.DataFrame:
    completed_count = int(health.get("completed_metric_experiments", health.get("n_completed_experiments", 0)))
    planned_count = int(health.get("planned_experiments", health.get("n_expected_experiments", 0)))
    gates = [
        ("read_only_diagnosis", True, "The script writes audit artifacts only; it does not launch, fit, mutate registry, or mutate manuscript."),
        ("manifest_selection_validation_only", manifest["selection_is_validation_only"].map(boolish).all(), "All Stage-R25 rows preserve validation-only selection."),
        ("manifest_test_metrics_audit_only", manifest["test_metrics_role"].astype(str).eq("audit_only_after_frozen_validation_selection").all(), "All Stage-R25 rows keep test metrics audit-only."),
        ("registry_manuscript_blocked", not manifest["mutates_registry"].map(boolish).any() and not manifest["mutates_manuscript"].map(boolish).any(), "R25 manifest blocks registry and manuscript mutation."),
        ("partial_evidence_labeled", health["r25_run_state"] != "completed_cleanly" or completed_count == planned_count, "Incomplete runs are explicitly labeled as in-flight evidence."),
        ("metric_rows_joined_to_baselines", metric_rows.empty or metric_rows[["current_qdesn_AQL", "current_pricefm_AQL"]].notna().all().all(), "Parsed metric rows join to current Q-DESN and PriceFM baselines."),
        ("no_article_promotion_gate_open", failure_map.empty or not failure_map["registry_article_gate_status"].astype(str).eq("blocked_until_full_quantile_and_mcmc_confirmation").any(), "No article or registry promotion is authorized by this diagnostic stage."),
        ("all_completed_cells_ok", status.empty or status.loc[status["metric_status"].astype(str).eq("completed"), "cell_status"].astype(str).eq("completed").all(), "Every completed metric row has a completed cell status."),
    ]
    return pd.DataFrame([{"gate": gate, "passed": bool(passed), "detail": detail} for gate, passed, detail in gates])


def source_manifest(args: argparse.Namespace) -> pd.DataFrame:
    specs = [
        ("stage_r21_failure_atlas", Path(args.stage_r21_dir) / R21_ATLAS, "csv"),
        ("stage_r22d_case_summary", Path(args.stage_r22d_dir) / R22D_CASE_SUMMARY, "csv"),
        ("stage_r22d_metric_rows", Path(args.stage_r22d_dir) / R22D_METRIC_ROWS, "csv"),
        ("stage_r22d_horizon_diagnostics", Path(args.stage_r22d_dir) / R22D_HORIZON, "csv"),
        ("stage_r23_capability", Path(args.stage_r23_dir) / R23_CAPABILITY, "csv"),
        ("stage_r23_queue", Path(args.stage_r23_dir) / R23_QUEUE, "csv"),
        ("stage_r23_bounds", Path(args.stage_r23_dir) / R23_BOUNDS, "csv"),
        ("stage_r24_readiness", Path(args.stage_r24_dir) / R24_READINESS, "csv"),
        ("stage_r24_candidate_gate", Path(args.stage_r24_dir) / R24_GATE, "csv"),
        ("stage_r25_prep_summary", Path(args.stage_r25_prep_dir) / "summary.json", "json"),
        ("stage_r25_manifest", Path(args.stage_r25_prep_dir) / R25_MANIFEST, "csv"),
        ("stage_r25_arm_plan", Path(args.stage_r25_prep_dir) / R25_ARM_PLAN, "csv"),
        ("stage_r25_case_plan", Path(args.stage_r25_prep_dir) / R25_CASE_PLAN, "csv"),
        ("stage_r25_grid_root", Path(args.stage_r25_grid_root), "directory"),
        ("stage_r25_run_root", Path(args.stage_r25_run_root), "directory"),
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
                "size_bytes": full.stat().st_size if full.exists() and full.is_file() else "",
                "sha256": sha256_file_or_blank(full) if full.exists() and full.is_file() else "",
            }
        )
    return pd.DataFrame(rows)


def count_binary_artifacts(path: str | Path) -> int:
    root = repo_path(path)
    if not root.exists():
        return 0
    return sum(1 for p in root.rglob("*") if p.is_file() and p.suffix in BINARY_SUFFIXES)


def build_report(
    summary: dict[str, Any],
    health: pd.DataFrame,
    case_progress_frame: pd.DataFrame,
    validation_selected: pd.DataFrame,
    failure_map: pd.DataFrame,
    mcmc: pd.DataFrame,
    next_plan: pd.DataFrame,
) -> str:
    def escape_cell(value: Any) -> str:
        text = text_value(value)
        return text.replace("|", "\\|").replace("\n", " ")

    def md_table(frame: pd.DataFrame, n: int = 12) -> str:
        if frame.empty:
            return "_No rows._"
        head = frame.head(n).copy()
        columns = [str(col) for col in head.columns]
        lines = [
            "| " + " | ".join(columns) + " |",
            "| " + " | ".join(["---"] * len(columns)) + " |",
        ]
        for _, row in head.iterrows():
            lines.append("| " + " | ".join(escape_cell(row[col]) for col in head.columns) + " |")
        return "\n".join(lines)

    compact_health = health.copy()
    cases = case_progress_frame[["region", "fold", "planned_experiments", "started_experiments", "completed_experiments", "remaining_experiments", "case_status"]]
    selected_cols = [
        "region",
        "fold",
        "stage_r25_arm",
        "method_id",
        "val_AQL",
        "test_AQL",
        "test_minus_current_qdesn",
        "test_minus_pricefm",
        "beats_both_on_test",
    ]
    failure_cols = [
        "region",
        "fold",
        "partial_diagnosis",
        "test_minus_pricefm",
        "test_minus_current_qdesn",
        "stage_r21_primary_failure_pattern",
        "mcmc_gate_status",
    ]
    return "\n".join(
        [
            "# PriceFM Stage-R26 In-Flight Mechanism Diagnosis",
            "",
            "## Executive Summary",
            "",
            f"- Run state: `{summary['r25_run_state']}`.",
            f"- Completed experiments: {summary['n_completed_experiments']} / {summary['n_expected_experiments']} ({summary['percent_complete_metric']}%).",
            f"- Remaining experiments: {summary['n_remaining_experiments']}.",
            f"- Completed Q-DESN/exQDESN rows: {summary['n_metric_rows']}.",
            f"- Rows beating current Q-DESN: {summary['n_rows_beating_current_qdesn']}.",
            f"- Rows beating PriceFM: {summary['n_rows_beating_pricefm']}.",
            f"- Rows beating both: {summary['n_rows_beating_both']}.",
            f"- Validation-selected rows beating both: {summary['n_validation_selected_beats_both']}.",
            f"- MCMC confirmation candidates now: {summary['n_mcmc_gate_rows']}.",
            "",
            "This is a read-only, in-flight diagnosis. If R25 is incomplete, test evidence is useful for mechanism learning but not final promotion.",
            "",
            "## Health",
            "",
            md_table(compact_health, 20),
            "",
            "## Case Progress",
            "",
            md_table(cases, 25),
            "",
            "## Validation-Selected Partial Rows",
            "",
            md_table(validation_selected[[c for c in selected_cols if c in validation_selected.columns]].sort_values("test_minus_pricefm") if not validation_selected.empty else validation_selected, 20),
            "",
            "## Failure Decomposition",
            "",
            md_table(failure_map[[c for c in failure_cols if c in failure_map.columns]], 20),
            "",
            "## MCMC Gate",
            "",
            md_table(mcmc, 20),
            "",
            "## Next Action Plan",
            "",
            md_table(next_plan, 10),
            "",
            "## Interpretation",
            "",
            summary["interpretation"],
            "",
            "## Do Not Do Yet",
            "",
            "- Do not mutate the registry.",
            "- Do not update the manuscript or article repo.",
            "- Do not promote rows that only beat current Q-DESN but still lose to PriceFM.",
            "- Do not launch MCMC until final R25 closeout confirms a beat-both or explicitly approved near-miss candidate.",
            "",
        ]
    )


def run(args: argparse.Namespace) -> dict[str, Any]:
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and any(out_dir.iterdir()) and not args.force:
        raise FileExistsError(f"{out_dir} already exists; rerun with --force true to overwrite")
    out_dir.mkdir(parents=True, exist_ok=True)

    r21 = normalize_keys(read_csv_required(Path(args.stage_r21_dir) / R21_ATLAS, "Stage-R21 failure atlas"), "Stage-R21 failure atlas")
    r22d_case = normalize_keys(read_csv_required(Path(args.stage_r22d_dir) / R22D_CASE_SUMMARY, "Stage-R22D case summary"), "Stage-R22D case summary")
    r23_queue = normalize_keys(read_csv_required(Path(args.stage_r23_dir) / R23_QUEUE, "Stage-R23 case queue"), "Stage-R23 case queue")
    r25_summary = read_json_required(Path(args.stage_r25_prep_dir) / "summary.json", "Stage-R25 prep summary")
    manifest = normalize_manifest(read_csv_required(Path(args.stage_r25_prep_dir) / R25_MANIFEST, "Stage-R25 launch manifest"))
    arm_plan = read_csv_required(Path(args.stage_r25_prep_dir) / R25_ARM_PLAN, "Stage-R25 arm plan")
    r23_capability = read_csv_optional(Path(args.stage_r23_dir) / R23_CAPABILITY)
    r24_readiness = read_csv_optional(Path(args.stage_r24_dir) / R24_READINESS)

    if int(manifest.shape[0]) != int(args.expected_experiments):
        raise ValueError(f"expected {args.expected_experiments} Stage-R25 experiments, observed {manifest.shape[0]}")
    if int(manifest[["region", "fold"]].drop_duplicates().shape[0]) != int(args.expected_cases):
        raise ValueError(f"expected {args.expected_cases} Stage-R25 cases")

    metric_rows, status, horizon = build_r25_run_tables(manifest, arm_plan, args.stage_r25_run_root)
    selected = selected_by_validation(metric_rows)
    oracle = case_test_oracle(metric_rows)
    arm_summary = summary_by(metric_rows, "stage_r25_arm")
    horizon_diag = horizon_summary(horizon, selected)
    progress = case_progress(manifest, status)
    health, health_payload = health_table(manifest, status, args.stage_r25_grid_root, args.stage_r25_log_root, args.run_tag, args)
    failure_map = failure_decomposition(selected, oracle, r21, r22d_case, r23_queue, args.near_miss_pricefm_margin)
    mcmc = mcmc_gate(failure_map, args.near_miss_pricefm_margin)

    n_rows_beating_qdesn = int(metric_rows["beats_current_qdesn_on_test"].map(boolish).sum()) if not metric_rows.empty else 0
    n_rows_beating_pricefm = int(metric_rows["beats_pricefm_on_test"].map(boolish).sum()) if not metric_rows.empty else 0
    n_rows_beating_both = int(metric_rows["beats_both_on_test"].map(boolish).sum()) if not metric_rows.empty else 0
    n_selected_beating_both = int(selected["beats_both_on_test"].map(boolish).sum()) if not selected.empty else 0
    n_selected_beating_qdesn = int(selected["beats_current_qdesn_on_test"].map(boolish).sum()) if not selected.empty else 0
    n_selected_beating_pricefm = int(selected["beats_pricefm_on_test"].map(boolish).sum()) if not selected.empty else 0
    best_gap = finite_float(metric_rows["test_minus_pricefm"].min()) if not metric_rows.empty else float("nan")
    best_selected_gap = finite_float(selected["test_minus_pricefm"].min()) if not selected.empty else float("nan")
    interpretation = (
        "R25 is still in flight; partial evidence is negative for promotion and should be used only for mechanism diagnosis."
        if health_payload["r25_run_state"] != "completed_cleanly"
        else "R25 appears complete; use this diagnosis as a pre-closeout check, then run the final Stage-R26 closeout gate."
    )
    if n_rows_beating_pricefm == 0:
        interpretation += " Completed rows do not yet beat PriceFM, which points away from more horizon-weight/readout breadth as the sole rescue mechanism."
    elif n_selected_beating_both == 0:
        interpretation += " Some rows may beat PriceFM, but validation-selected rows do not yet pass the beat-both promotion gate."

    summary = {
        "stage": "pricefm_stage_r26_inflight_mechanism_diagnosis",
        "status": "completed_read_only_inflight_diagnosis",
        "r25_run_state": health_payload["r25_run_state"],
        "n_expected_experiments": int(args.expected_experiments),
        "n_started_experiments": int(health_payload["started_experiments"]),
        "n_completed_experiments": int(health_payload["completed_metric_experiments"]),
        "n_remaining_experiments": int(health_payload["remaining_to_metric_completion"]),
        "percent_complete_metric": float(health_payload["percent_complete_metric"]),
        "n_metric_rows": int(metric_rows.shape[0]),
        "n_rows_beating_current_qdesn": n_rows_beating_qdesn,
        "n_rows_beating_pricefm": n_rows_beating_pricefm,
        "n_rows_beating_both": n_rows_beating_both,
        "n_validation_selected_cases": int(selected.shape[0]),
        "n_validation_selected_beating_current_qdesn": n_selected_beating_qdesn,
        "n_validation_selected_beating_pricefm": n_selected_beating_pricefm,
        "n_validation_selected_beats_both": n_selected_beating_both,
        "best_any_row_test_minus_pricefm": best_gap,
        "best_validation_selected_test_minus_pricefm": best_selected_gap,
        "n_mcmc_gate_rows": int(mcmc.shape[0]),
        "n_binary_artifacts": int(count_binary_artifacts(args.stage_r25_run_root)),
        "r25_prep_grid_id": r25_summary.get("grid_id", ""),
        "r23_mechanisms_ready_for_expensive_launch": int(r23_capability["effective_status"].astype(str).str.contains("ready", case=False, na=False).sum()) if not r23_capability.empty and "effective_status" in r23_capability.columns else "",
        "r24_ready_postfit_rows": int(r24_readiness["readiness_status"].astype(str).str.contains("ready", case=False, na=False).sum()) if not r24_readiness.empty and "readiness_status" in r24_readiness.columns else 0,
        "registry_mutation_authorized": False,
        "manuscript_mutation_authorized": False,
        "launches_models": False,
        "fits_models": False,
        "writes_launch_yaml": False,
        "article_update_justified": False,
        "recommended_next_action": "wait_for_r25_completion_then_run_final_stage_r26_closeout",
        "interpretation": interpretation,
    }
    gates = diagnosis_gates(manifest, metric_rows, status, failure_map, summary)
    if not gates["passed"].map(boolish).all():
        failed = gates.loc[~gates["passed"].map(boolish), "gate"].tolist()
        raise RuntimeError(f"Stage-R26 in-flight diagnosis gates failed: {failed}")
    next_plan = next_action_plan(summary, failure_map)

    outputs = {
        "health": out_dir / OUT_HEALTH,
        "case_progress": out_dir / OUT_CASE_PROGRESS,
        "metric_rows": out_dir / OUT_METRIC_ROWS,
        "validation_selected": out_dir / OUT_VALIDATION_SELECTED,
        "test_oracle": out_dir / OUT_TEST_ORACLE,
        "arm_summary": out_dir / OUT_ARM_SUMMARY,
        "horizon_summary": out_dir / OUT_HORIZON_SUMMARY,
        "failure_map": out_dir / OUT_FAILURE_MAP,
        "mcmc_gate": out_dir / OUT_MCMC_GATE,
        "next_action": out_dir / OUT_NEXT_ACTION,
        "gates": out_dir / OUT_GATES,
        "source_manifest": out_dir / OUT_SOURCE,
        "report": out_dir / OUT_REPORT,
        "summary_json": out_dir / "summary.json",
    }
    write_frame(outputs["health"], health)
    write_frame(outputs["case_progress"], progress)
    write_frame(outputs["metric_rows"], metric_rows)
    write_frame(outputs["validation_selected"], selected)
    write_frame(outputs["test_oracle"], oracle)
    write_frame(outputs["arm_summary"], arm_summary)
    write_frame(outputs["horizon_summary"], horizon_diag)
    write_frame(outputs["failure_map"], failure_map)
    write_frame(outputs["mcmc_gate"], mcmc)
    write_frame(outputs["next_action"], next_plan)
    write_frame(outputs["gates"], gates)
    write_frame(outputs["source_manifest"], source_manifest(args))
    summary["outputs"] = {key: repo_relative(path) for key, path in outputs.items()}
    write_json(outputs["summary_json"], summary)
    outputs["report"].write_text(build_report(summary, health, progress, selected, failure_map, mcmc, next_plan))
    return summary


def main() -> None:
    args = parser().parse_args()
    summary = run(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
