#!/usr/bin/env python3
"""Partial-stop closeout and guarded cache cleanup for PriceFM Stage-R32."""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json
from pricefm_full_surface import BINARY_SUFFIXES, QDESN_PREFIX, repo_relative, sha256_file_or_blank


DEFAULT_PREP_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r32_large_capacity_history_launch_prep_20260714"
)
DEFAULT_MANIFEST = f"{DEFAULT_PREP_DIR}/pricefm_stage_r32_large_capacity_launch_manifest.csv"
DEFAULT_CASE_PLAN = f"{DEFAULT_PREP_DIR}/pricefm_stage_r32_case_plan.csv"
DEFAULT_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_r32_large_capacity_history_20260714.yaml"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_r32_large_capacity_history_20260714"
)
DEFAULT_LOG_ROOT = "application/data_local/pricefm/logs"
DEFAULT_RUN_TAG = "pricefm_stage_r32_large_capacity_history_20260714"
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r32_partial_stop_closeout_20260721"
)

OUT_STATUS = "pricefm_stage_r32_partial_run_status.csv"
OUT_METRICS = "pricefm_stage_r32_partial_metric_rows.csv"
OUT_VALIDATION_SELECTED = "pricefm_stage_r32_partial_validation_selected_case.csv"
OUT_TEST_ORACLE = "pricefm_stage_r32_partial_test_oracle_case.csv"
OUT_CAPACITY = "pricefm_stage_r32_partial_capacity_diagnostics.csv"
OUT_FAILURES = "pricefm_stage_r32_partial_failure_summary.csv"
OUT_GATES = "pricefm_stage_r32_partial_closeout_gates.csv"
OUT_NEXT_DESIGN = "pricefm_stage_r32_partial_next_design_recommendations.csv"
OUT_CLEANUP_MANIFEST = "pricefm_stage_r32_partial_cleanup_manifest.csv"
OUT_CLEANUP_SUMMARY = "pricefm_stage_r32_partial_cleanup_summary.json"
OUT_STOP_EVIDENCE = "pricefm_stage_r32_manual_stop_evidence.json"
OUT_SOURCE = "source_manifest.csv"
OUT_REPORT = "pricefm_stage_r32_partial_stop_closeout_report.md"

HEAVY_BASENAMES = {
    "X_train.csv",
    "X_val.csv",
    "X_test.csv",
    "rows_train.csv",
    "rows_val.csv",
    "rows_test.csv",
    "rows_all.csv",
    "y_train.csv",
    "y_val.csv",
    "y_test.csv",
    "feature_map_matrix.npy",
    "feature_map_matrix.npz",
    "model_predictions_scaled.csv",
    "predictions_with_naive_scaled.csv",
    "exact_equivalence.csv",
}
HEAVY_SUFFIXES = set(BINARY_SUFFIXES) | {".rds", ".rda", ".RData", ".rdata"}
PRESERVED_BASENAMES = {
    "cell_status.csv",
    "config.yaml",
    "metric_summary.csv",
    "metric_by_horizon.csv",
    "metric_by_horizon_group.csv",
    "model_method_summary.csv",
    "model_parameter_summary.csv",
    "model_trace_summary.csv",
    "training_weight_summary.csv",
    "warm_start_diagnostics.csv",
    "report.md",
    "run_manifest.json",
    "repo_state.json",
    "feature_manifest.json",
    "feature_provenance.csv",
    "adapter_manifest.json",
}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", default=DEFAULT_MANIFEST)
    p.add_argument("--case-plan", default=DEFAULT_CASE_PLAN)
    p.add_argument("--grid-config", default=DEFAULT_GRID_CONFIG)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--log-root", default=DEFAULT_LOG_ROOT)
    p.add_argument("--run-tag", default=DEFAULT_RUN_TAG)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--expected-experiments", type=int, default=480)
    p.add_argument("--expected-cases", type=int, default=20)
    p.add_argument("--near-miss-pricefm-margin", type=float, default=0.15)
    p.add_argument("--skip-process-check", type=parse_bool, default=False)
    p.add_argument("--write-cleanup-manifest", type=parse_bool, default=True)
    p.add_argument("--execute-cleanup", type=parse_bool, default=False)
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


def require_columns(frame: pd.DataFrame, columns: list[str], label: str) -> None:
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError(f"{label} missing required columns: {missing}")


def write_frame(path: str | Path, frame: pd.DataFrame) -> None:
    full = repo_path(path)
    full.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(full, index=False)


def normalize_manifest(frame: pd.DataFrame) -> pd.DataFrame:
    require_columns(
        frame,
        [
            "experiment_id",
            "region",
            "fold",
            "stage_r22b_case_id",
            "stage_r32_arm",
            "stage_r32_profile",
            "horizon_focus",
            "feature_policy",
            "lag_window",
            "depth",
            "n_per_layer",
            "units",
            "feature_dim",
            "state_output",
            "alpha",
            "rho",
            "input_scale",
            "tau0",
            "current_pricefm_AQL",
            "current_qdesn_AQL",
            "selection_is_validation_only",
            "selection_rule",
            "test_metrics_role",
            "mutates_registry",
            "mutates_manuscript",
        ],
        "Stage-R32 launch manifest",
    )
    out = frame.copy()
    out["experiment_id"] = out["experiment_id"].astype(str)
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    for col in ["lag_window", "depth", "n_per_layer"]:
        out[col] = pd.to_numeric(out[col], errors="raise").astype(int)
    for col in ["alpha", "rho", "input_scale", "tau0", "current_pricefm_AQL", "current_qdesn_AQL"]:
        out[col] = pd.to_numeric(out[col], errors="coerce")
    return out


def output_path(output_dir: str | Path, name: str) -> Path:
    return repo_path(output_dir) / name


def safe_unlink(path: Path, root: Path) -> None:
    resolved = path.resolve()
    root_resolved = root.resolve()
    try:
        resolved.relative_to(root_resolved)
    except ValueError as exc:
        raise ValueError(f"Refusing cleanup outside run root: {resolved}") from exc
    resolved.unlink()


def ps_lines() -> list[str]:
    result = subprocess.run(
        ["ps", "axww", "-o", "pid=,pgid=,stat=,args="],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.stdout.splitlines()


def r32_process_lines() -> list[str]:
    current_pid = str(os.getpid())
    lines: list[str] = []
    for line in ps_lines():
        parts = line.strip().split(maxsplit=3)
        if not parts or parts[0] == current_pid:
            continue
        if "/tmp/pricefm_stage_r32" in line:
            lines.append(line)
        elif "13_run_desn_experiment_grid.py" in line and "stage_r32" in line:
            lines.append(line)
        elif "10_run_desn_model_full.py" in line and "/r32_" in line:
            lines.append(line)
        elif "08_run_desn_model_smoke.R" in line and "/r32_" in line:
            lines.append(line)
    return lines


def tmux_sessions() -> list[str]:
    result = subprocess.run(["tmux", "ls"], text=True, capture_output=True, check=False)
    if result.returncode != 0:
        return []
    return result.stdout.splitlines()


def process_state(skip_process_check: bool) -> dict[str, Any]:
    if skip_process_check:
        return {
            "process_check_skipped": True,
            "r32_process_count": 0,
            "r32_process_sample": [],
            "r30_tmux_alive": False,
            "r32_tmux_alive": False,
        }
    sessions = tmux_sessions()
    r32 = r32_process_lines()
    return {
        "process_check_skipped": False,
        "r32_process_count": len(r32),
        "r32_process_sample": r32[:20],
        "r30_tmux_alive": any("pricefm_stage_r30" in line for line in sessions),
        "r32_tmux_alive": any("pricefm_stage_r32" in line for line in sessions),
    }


def metric_paths(run_dir: Path) -> dict[str, Path | None]:
    if not run_dir.exists():
        return {"metric_summary": None, "horizon_group": None, "training_weight_summary": None}
    return {
        "metric_summary": next(iter(sorted(run_dir.rglob("metric_summary.csv"))), None),
        "horizon_group": next(iter(sorted(run_dir.rglob("metric_by_horizon_group.csv"))), None),
        "training_weight_summary": next(iter(sorted(run_dir.rglob("training_weight_summary.csv"))), None),
    }


def read_cell_status(run_dir: Path) -> dict[str, Any]:
    path = run_dir / "cell_status.csv"
    if not path.exists() or path.stat().st_size == 0:
        return {"status": "missing_cell_status", "message": ""}
    frame = pd.read_csv(path)
    if frame.empty:
        return {"status": "empty_cell_status", "message": ""}
    return frame.iloc[0].to_dict()


def classify_run(run_dir: Path, metric_path: Path | None, cell_status: dict[str, Any]) -> str:
    status = text_value(cell_status.get("status")).lower()
    message = text_value(cell_status.get("message")).lower()
    if metric_path is not None:
        return "completed_with_metrics"
    if "failed" in status or "return code" in message:
        return "failed_without_metrics"
    if run_dir.exists():
        return "manual_stopped_no_metric"
    return "queued_not_started"


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


def build_status_and_metrics(manifest: pd.DataFrame, run_root: str | Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    root = repo_path(run_root)
    status_rows: list[dict[str, Any]] = []
    metric_rows: list[dict[str, Any]] = []
    for _, prep in manifest.iterrows():
        exp_id = str(prep["experiment_id"])
        run_dir = root / exp_id
        paths = metric_paths(run_dir)
        cell = read_cell_status(run_dir) if run_dir.exists() else {"status": "missing_run_dir", "message": ""}
        closeout_status = classify_run(run_dir, paths["metric_summary"], cell)
        status_rows.append(
            {
                "experiment_id": exp_id,
                "region": prep["region"],
                "fold": int(prep["fold"]),
                "stage_r22b_case_id": prep["stage_r22b_case_id"],
                "stage_r32_arm": prep["stage_r32_arm"],
                "stage_r32_profile": prep["stage_r32_profile"],
                "lag_window": int(prep["lag_window"]),
                "depth": int(prep["depth"]),
                "n_per_layer": int(prep["n_per_layer"]),
                "feature_policy": prep["feature_policy"],
                "cell_status": cell.get("status", "missing"),
                "cell_message": cell.get("message", ""),
                "cell_elapsed_seconds": finite_float(cell.get("elapsed_seconds")),
                "closeout_status": closeout_status,
                "metric_exists": paths["metric_summary"] is not None,
                "run_dir_exists": run_dir.exists(),
                "run_dir": repo_relative(run_dir),
                "metric_summary": repo_relative(paths["metric_summary"]) if paths["metric_summary"] else "",
                "horizon_group": repo_relative(paths["horizon_group"]) if paths["horizon_group"] else "",
                "training_weight_summary": repo_relative(paths["training_weight_summary"]) if paths["training_weight_summary"] else "",
            }
        )
        if paths["metric_summary"] is None:
            continue
        metric_frame = pd.read_csv(paths["metric_summary"])
        original_test = metric_frame[
            metric_frame["split"].astype(str).eq("test") & metric_frame["unit"].astype(str).eq("original")
        ]
        naive = best_by_prefix(original_test, "naive")
        normal = best_by_prefix(original_test, "normal")
        best_naive_aql = finite_float(naive.get("AQL")) if not naive.empty else float("nan")
        best_normal_aql = finite_float(normal.get("AQL")) if not normal.empty else float("nan")
        for metric in metric_summary_rows(paths["metric_summary"]):
            row = {
                **prep.to_dict(),
                "method_id": metric["method_id"],
                "val_AQL": finite_float(metric.get("val_AQL")),
                "val_MAE": finite_float(metric.get("val_MAE")),
                "val_RMSE": finite_float(metric.get("val_RMSE")),
                "test_AQL": finite_float(metric.get("test_AQL")),
                "test_MAE": finite_float(metric.get("test_MAE")),
                "test_RMSE": finite_float(metric.get("test_RMSE")),
                "best_naive_AQL": best_naive_aql,
                "best_normal_AQL": best_normal_aql,
                "metric_summary": repo_relative(paths["metric_summary"]),
            }
            row["test_minus_current_qdesn"] = row["test_AQL"] - finite_float(row["current_qdesn_AQL"])
            row["test_minus_pricefm"] = row["test_AQL"] - finite_float(row["current_pricefm_AQL"])
            row["test_minus_best_reference"] = row["test_AQL"] - min(
                finite_float(row["current_qdesn_AQL"]),
                finite_float(row["current_pricefm_AQL"]),
            )
            row["test_minus_best_naive"] = row["test_AQL"] - best_naive_aql
            row["test_minus_best_normal"] = row["test_AQL"] - best_normal_aql
            row["beats_current_qdesn_on_test"] = row["test_minus_current_qdesn"] < 0.0
            row["beats_pricefm_on_test"] = row["test_minus_pricefm"] < 0.0
            row["beats_both_on_test"] = row["beats_current_qdesn_on_test"] and row["beats_pricefm_on_test"]
            row["near_miss_pricefm_015"] = 0.0 <= row["test_minus_pricefm"] <= 0.15
            metric_rows.append(row)
    return pd.DataFrame(status_rows), pd.DataFrame(metric_rows)


def selected_by_validation(metric_rows: pd.DataFrame) -> pd.DataFrame:
    if metric_rows.empty:
        return pd.DataFrame()
    valid = metric_rows[metric_rows["val_AQL"].map(lambda x: math.isfinite(finite_float(x)))].copy()
    rows = []
    for _, group in valid.groupby(["region", "fold"], sort=True):
        row = group.sort_values(["val_AQL", "test_AQL", "experiment_id", "method_id"]).iloc[0].to_dict()
        row["case_selected_by"] = "validation_AQL_only_across_completed_stage_r32_candidates"
        row["test_metrics_use"] = "audit_only_partial_manual_stop"
        rows.append(row)
    return pd.DataFrame(rows).sort_values(["region", "fold"]).reset_index(drop=True)


def test_oracle(metric_rows: pd.DataFrame) -> pd.DataFrame:
    if metric_rows.empty:
        return pd.DataFrame()
    rows = []
    for _, group in metric_rows.groupby(["region", "fold"], sort=True):
        row = group.sort_values(["test_AQL", "val_AQL", "experiment_id", "method_id"]).iloc[0].to_dict()
        row["case_oracle_by"] = "test_AQL_audit_only_across_completed_stage_r32_candidates"
        rows.append(row)
    return pd.DataFrame(rows).sort_values(["test_minus_pricefm", "region", "fold"]).reset_index(drop=True)


def status_count(status: pd.DataFrame, value: str) -> int:
    if status.empty:
        return 0
    return int(status["closeout_status"].astype(str).eq(value).sum())


def capacity_diagnostics(status: pd.DataFrame, metrics: pd.DataFrame) -> pd.DataFrame:
    if status.empty:
        return pd.DataFrame()
    counts = (
        status.groupby(["stage_r32_profile", "lag_window", "depth", "n_per_layer"], as_index=False)
        .agg(
            planned_rows=("experiment_id", "size"),
            completed_rows=("closeout_status", lambda s: int((s == "completed_with_metrics").sum())),
            failed_rows=("closeout_status", lambda s: int((s == "failed_without_metrics").sum())),
            manual_stopped_rows=("closeout_status", lambda s: int((s == "manual_stopped_no_metric").sum())),
            queued_rows=("closeout_status", lambda s: int((s == "queued_not_started").sum())),
            median_elapsed_seconds=("cell_elapsed_seconds", "median"),
        )
    )
    if not metrics.empty:
        metric_summary = (
            metrics.groupby(["stage_r32_profile", "lag_window", "depth", "n_per_layer"], as_index=False)
            .agg(
                metric_rows=("experiment_id", "size"),
                best_test_minus_pricefm=("test_minus_pricefm", "min"),
                median_test_minus_pricefm=("test_minus_pricefm", "median"),
                best_test_minus_current_qdesn=("test_minus_current_qdesn", "min"),
                median_test_minus_current_qdesn=("test_minus_current_qdesn", "median"),
                beats_current_qdesn=("beats_current_qdesn_on_test", "sum"),
                beats_pricefm=("beats_pricefm_on_test", "sum"),
                beats_both=("beats_both_on_test", "sum"),
            )
        )
        counts = counts.merge(
            metric_summary,
            on=["stage_r32_profile", "lag_window", "depth", "n_per_layer"],
            how="left",
        )
    return counts.sort_values(["best_test_minus_pricefm", "failed_rows", "manual_stopped_rows"], na_position="last").reset_index(drop=True)


def failure_summary(status: pd.DataFrame, metrics: pd.DataFrame) -> pd.DataFrame:
    by_status = (
        status.groupby("closeout_status", as_index=False)
        .agg(rows=("experiment_id", "size"), cases=("stage_r22b_case_id", "nunique"))
        .rename(columns={"closeout_status": "failure_axis"})
    )
    by_status["axis_type"] = "run_status"
    by_profile = (
        status.groupby("stage_r32_profile", as_index=False)
        .agg(
            rows=("experiment_id", "size"),
            failed_rows=("closeout_status", lambda s: int((s == "failed_without_metrics").sum())),
            manual_stopped_rows=("closeout_status", lambda s: int((s == "manual_stopped_no_metric").sum())),
            completed_rows=("closeout_status", lambda s: int((s == "completed_with_metrics").sum())),
        )
        .rename(columns={"stage_r32_profile": "failure_axis"})
    )
    by_profile["cases"] = ""
    by_profile["axis_type"] = "stage_r32_profile"
    frames = [by_status, by_profile]
    if not metrics.empty:
        by_quality = pd.DataFrame(
            [
                {
                    "failure_axis": "completed_metric_rows_beating_current_qdesn",
                    "rows": int(metrics["beats_current_qdesn_on_test"].sum()),
                    "cases": int(metrics.loc[metrics["beats_current_qdesn_on_test"], "stage_r22b_case_id"].nunique()),
                    "axis_type": "test_gate",
                },
                {
                    "failure_axis": "completed_metric_rows_beating_pricefm",
                    "rows": int(metrics["beats_pricefm_on_test"].sum()),
                    "cases": int(metrics.loc[metrics["beats_pricefm_on_test"], "stage_r22b_case_id"].nunique()),
                    "axis_type": "test_gate",
                },
                {
                    "failure_axis": "completed_metric_rows_beating_both",
                    "rows": int(metrics["beats_both_on_test"].sum()),
                    "cases": int(metrics.loc[metrics["beats_both_on_test"], "stage_r22b_case_id"].nunique()),
                    "axis_type": "test_gate",
                },
            ]
        )
        frames.append(by_quality)
    return pd.concat(frames, ignore_index=True, sort=False)


def gate_rows(
    status: pd.DataFrame,
    metrics: pd.DataFrame,
    selected: pd.DataFrame,
    proc: dict[str, Any],
    expected_experiments: int,
    expected_cases: int,
) -> pd.DataFrame:
    planned = int(status.shape[0])
    completed = status_count(status, "completed_with_metrics")
    failed = status_count(status, "failed_without_metrics")
    manual_stopped = status_count(status, "manual_stopped_no_metric")
    queued = status_count(status, "queued_not_started")
    promotion_candidates = int(metrics["beats_both_on_test"].sum()) if not metrics.empty else 0
    selected_promotions = int(selected["beats_both_on_test"].sum()) if not selected.empty else 0
    rows = [
        ("expected_manifest_size", planned == expected_experiments, f"planned={planned}, expected={expected_experiments}"),
        ("expected_case_count", int(status[["region", "fold"]].drop_duplicates().shape[0]) == expected_cases, f"cases={status[['region','fold']].drop_duplicates().shape[0]}, expected={expected_cases}"),
        ("r32_processes_stopped", int(proc["r32_process_count"]) == 0, f"r32_process_count={proc['r32_process_count']}"),
        ("r32_tmux_session_absent", not boolish(proc["r32_tmux_alive"]), f"r32_tmux_alive={proc['r32_tmux_alive']}"),
        ("r30_not_interrupted", boolish(proc["r30_tmux_alive"]) or boolish(proc["process_check_skipped"]), f"r30_tmux_alive={proc['r30_tmux_alive']}"),
        ("partial_manual_stop_recorded", manual_stopped > 0 or queued > 0, f"completed={completed}, failed={failed}, manual_stopped={manual_stopped}, queued={queued}"),
        ("promotion_gate_open", promotion_candidates > 0 and selected_promotions > 0, f"completed_metric_promotions={promotion_candidates}, validation_selected_promotions={selected_promotions}"),
        ("registry_mutation_allowed", False, "blocked: Stage-R32 is a partial negative closeout"),
        ("manuscript_mutation_allowed", False, "blocked: no validation-selected candidate beat both current Q-DESN and PriceFM"),
        ("mcmc_confirmation_allowed", False, "blocked until a validation-selected VB winner beats both references"),
        ("r32_relaunch_same_design_allowed", False, "blocked: large n/D/m design is inefficient and non-promotable in partial evidence"),
        ("lean_redesign_recommended", True, "recommended: lower n, lower lag, final-layer-first bounded design after R30 closeout"),
    ]
    return pd.DataFrame([{"gate": g, "passed": bool(p), "detail": d} for g, p, d in rows])


def next_design_recommendations(metrics: pd.DataFrame) -> pd.DataFrame:
    best_gap = float("nan") if metrics.empty else finite_float(metrics["test_minus_pricefm"].min())
    return pd.DataFrame(
        [
            {
                "recommendation": "do_not_resume_r32_same_design",
                "value": "true",
                "rationale": f"Partial R32 best test-minus-PriceFM is {best_gap:.6g}; completed rows do not beat PriceFM and active rows consumed large memory.",
                "launch_allowed_now": False,
            },
            {
                "recommendation": "n_per_layer_bounds",
                "value": "48,64,96 with 128 only for a tiny audited subset",
                "rationale": "R32 n=200/300 arms increased memory sharply and did not improve the completed PriceFM gap.",
                "launch_allowed_now": False,
            },
            {
                "recommendation": "depth_bounds",
                "value": "2,3",
                "rationale": "D=4 rows were expensive and showed failures or no clear test benefit; keep D=4 out of the next default grid.",
                "launch_allowed_now": False,
            },
            {
                "recommendation": "lag_window_bounds",
                "value": "96,168,240; avoid 500 by default",
                "rationale": "m=300/500 materially inflated adapter size; the next search should test history length at lower memory first.",
                "launch_allowed_now": False,
            },
            {
                "recommendation": "state_output_priority",
                "value": "final_layer first; concat only when n<=64 and D<=3",
                "rationale": "slow-memory concat arms were the largest memory users and provided no promotable evidence.",
                "launch_allowed_now": False,
            },
            {
                "recommendation": "regularization_grid",
                "value": "alpha 0.35-0.50, rho 0.82-0.90, input_scale 0.20-0.35, tau0 0.001-0.002",
                "rationale": "Keep R30/R32 regimes but shift toward stronger shrinkage for smaller reservoirs.",
                "launch_allowed_now": False,
            },
            {
                "recommendation": "targeting_rule",
                "value": "wait for R30 closeout; select cases by validation-only failures and memory-normalized near misses",
                "rationale": "R30 is still active; next expensive work should be case-specific rather than another full 480-row sweep.",
                "launch_allowed_now": False,
            },
        ]
    )


def is_heavy_artifact(path: Path) -> bool:
    if path.name in HEAVY_BASENAMES:
        return True
    if path.suffix in HEAVY_SUFFIXES:
        return True
    if path.suffix.lower() == ".png":
        return True
    return False


def cleanup_manifest(status: pd.DataFrame, metrics: pd.DataFrame, run_root: str | Path) -> pd.DataFrame:
    root = repo_path(run_root)
    if not root.exists():
        return pd.DataFrame()
    winner_ids: set[str] = set()
    if not metrics.empty:
        winner_ids = set(metrics.loc[metrics["beats_both_on_test"], "experiment_id"].astype(str))
    status_index = status.set_index("experiment_id", drop=False)
    rows: list[dict[str, Any]] = []
    for exp_id, row in status_index.iterrows():
        exp_id = str(exp_id)
        run_dir = root / exp_id
        if exp_id in winner_ids or not run_dir.exists():
            continue
        for path in sorted(run_dir.rglob("*")):
            if not path.is_file() or not is_heavy_artifact(path) or path.name in PRESERVED_BASENAMES:
                continue
            size = path.stat().st_size
            rows.append(
                {
                    "experiment_id": exp_id,
                    "closeout_status": row["closeout_status"],
                    "path": repo_relative(path),
                    "size_bytes": int(size),
                    "size_mib": size / 1024 / 1024,
                    "cleanup_reason": "stage_r32_partial_stop_nonwinner_reconstructable_heavy_cache",
                    "winner_preserved": False,
                }
            )
    return pd.DataFrame(rows)


def execute_cleanup(manifest: pd.DataFrame, run_root: str | Path) -> dict[str, Any]:
    root = repo_path(run_root)
    deleted = 0
    deleted_bytes = 0
    errors: list[dict[str, str]] = []
    for _, row in manifest.iterrows():
        path = repo_path(row["path"])
        if not path.exists():
            continue
        try:
            size = path.stat().st_size
            safe_unlink(path, root)
            deleted += 1
            deleted_bytes += size
        except Exception as exc:  # pragma: no cover - surfaced in JSON/report
            errors.append({"path": str(path), "error": str(exc)})
    return {"deleted_files": deleted, "deleted_bytes": deleted_bytes, "errors": errors}


def source_manifest(args: argparse.Namespace) -> pd.DataFrame:
    paths = [
        ("stage_r32_launch_manifest", args.manifest),
        ("stage_r32_case_plan", args.case_plan),
        ("stage_r32_grid_config", args.grid_config),
        ("stage_r32_tmux_log", repo_path(args.log_root) / "pricefm_stage_r32_window12_resume16_20260717.tmux.log"),
        ("stage_r32_fit_time_log", repo_path(args.log_root) / "pricefm_stage_r32_window12_resume16_20260717.fit.time.log"),
    ]
    rows = []
    for label, path in paths:
        full = repo_path(path)
        rows.append(
            {
                "source_label": label,
                "path": repo_relative(full),
                "exists": full.exists(),
                "sha256": sha256_file_or_blank(full),
            }
        )
    return pd.DataFrame(rows)


def write_report(
    path: str | Path,
    summary: dict[str, Any],
    gates: pd.DataFrame,
    capacity: pd.DataFrame,
    next_design: pd.DataFrame,
) -> None:
    top_capacity = capacity.head(6).to_dict(orient="records") if not capacity.empty else []
    lines = [
        "# PriceFM Stage-R32 partial-stop closeout",
        "",
        "Stage-R32 was manually stopped and closed as partial negative evidence. This report is read-only with respect to registries and manuscript files.",
        "",
        "## Health",
        "",
        f"- Planned experiments: {summary['planned_experiments']}",
        f"- Completed with metrics: {summary['completed_with_metrics']}",
        f"- Failed without metrics: {summary['failed_without_metrics']}",
        f"- Manual-stopped run dirs without metrics: {summary['manual_stopped_no_metric']}",
        f"- Queued/not started: {summary['queued_not_started']}",
        f"- Metric rows: {summary['metric_rows']}",
        f"- Completed metric rows beating both current Q-DESN and PriceFM: {summary['metric_rows_beating_both']}",
        f"- Cleanup executed: {summary['cleanup_executed']}",
        f"- Cleanup bytes removed: {summary['cleanup_deleted_bytes']}",
        "",
        "## Gates",
        "",
        frame_to_markdown(gates),
        "",
        "## Capacity diagnosis",
        "",
        "The large-history design is not an efficient next default: n=200/300, D=4, m=500, and concat-style readouts produced high memory pressure without promotable completed evidence.",
        "",
        "Top observed capacity rows:",
        "",
        "```json",
        json.dumps(top_capacity, indent=2, sort_keys=True),
        "```",
        "",
        "## Next design",
        "",
        frame_to_markdown(next_design),
        "",
        "## Blocked actions",
        "",
        "- Do not resume the same R32 grid.",
        "- Do not mutate the PriceFM registry.",
        "- Do not update manuscript or article assets from R32.",
        "- Do not launch the next grid until R30 is closed out and the lean target set is frozen.",
        "",
    ]
    full = repo_path(path)
    full.parent.mkdir(parents=True, exist_ok=True)
    full.write_text("\n".join(lines))


def frame_to_markdown(frame: pd.DataFrame) -> str:
    if frame.empty:
        return "_No rows._"
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        values = []
        for col in cols:
            text = text_value(row.get(col)).replace("|", "\\|").replace("\n", " ")
            values.append(text)
        lines.append("| " + " | ".join(values) + " |")
    return "\n".join(lines)


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = normalize_manifest(read_csv_required(args.manifest, "Stage-R32 launch manifest"))
    case_plan = read_csv_required(args.case_plan, "Stage-R32 case plan")
    status, metrics = build_status_and_metrics(manifest, args.run_root)
    selected = selected_by_validation(metrics)
    oracle = test_oracle(metrics)
    capacity = capacity_diagnostics(status, metrics)
    failures = failure_summary(status, metrics)
    proc = process_state(args.skip_process_check)
    if args.execute_cleanup and proc["r32_process_count"] != 0:
        raise RuntimeError("Refusing cleanup while R32 processes are still running")
    gates = gate_rows(status, metrics, selected, proc, args.expected_experiments, args.expected_cases)
    next_design = next_design_recommendations(metrics)
    cleanup = cleanup_manifest(status, metrics, args.run_root) if args.write_cleanup_manifest else pd.DataFrame()
    cleanup_result = {"deleted_files": 0, "deleted_bytes": 0, "errors": []}
    if args.execute_cleanup and not cleanup.empty:
        cleanup_result = execute_cleanup(cleanup, args.run_root)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    write_frame(out_dir / OUT_STATUS, status)
    write_frame(out_dir / OUT_METRICS, metrics)
    write_frame(out_dir / OUT_VALIDATION_SELECTED, selected)
    write_frame(out_dir / OUT_TEST_ORACLE, oracle)
    write_frame(out_dir / OUT_CAPACITY, capacity)
    write_frame(out_dir / OUT_FAILURES, failures)
    write_frame(out_dir / OUT_GATES, gates)
    write_frame(out_dir / OUT_NEXT_DESIGN, next_design)
    write_frame(out_dir / OUT_SOURCE, source_manifest(args))
    if args.write_cleanup_manifest:
        write_frame(out_dir / OUT_CLEANUP_MANIFEST, cleanup)
    stop_evidence = {
        "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
        "run_tag": args.run_tag,
        "process_state": proc,
        "manual_stop_status": "r32_stopped" if proc["r32_process_count"] == 0 else "r32_processes_still_present",
    }
    write_json(out_dir / OUT_STOP_EVIDENCE, stop_evidence)
    write_json(out_dir / OUT_CLEANUP_SUMMARY, cleanup_result)
    summary = {
        "status": "completed",
        "stage": "stage_r32_partial_stop_closeout",
        "planned_experiments": int(status.shape[0]),
        "expected_experiments": int(args.expected_experiments),
        "case_count": int(status[["region", "fold"]].drop_duplicates().shape[0]) if not status.empty else 0,
        "expected_cases": int(args.expected_cases),
        "completed_with_metrics": status_count(status, "completed_with_metrics"),
        "failed_without_metrics": status_count(status, "failed_without_metrics"),
        "manual_stopped_no_metric": status_count(status, "manual_stopped_no_metric"),
        "queued_not_started": status_count(status, "queued_not_started"),
        "metric_rows": int(metrics.shape[0]),
        "metric_rows_beating_current_qdesn": int(metrics["beats_current_qdesn_on_test"].sum()) if not metrics.empty else 0,
        "metric_rows_beating_pricefm": int(metrics["beats_pricefm_on_test"].sum()) if not metrics.empty else 0,
        "metric_rows_beating_both": int(metrics["beats_both_on_test"].sum()) if not metrics.empty else 0,
        "validation_selected_cases": int(selected.shape[0]),
        "validation_selected_beating_both": int(selected["beats_both_on_test"].sum()) if not selected.empty else 0,
        "process_state": proc,
        "cleanup_manifest_rows": int(cleanup.shape[0]) if not cleanup.empty else 0,
        "cleanup_manifest_bytes": int(cleanup["size_bytes"].sum()) if not cleanup.empty else 0,
        "cleanup_executed": bool(args.execute_cleanup),
        "cleanup_deleted_files": int(cleanup_result["deleted_files"]),
        "cleanup_deleted_bytes": int(cleanup_result["deleted_bytes"]),
        "cleanup_errors": cleanup_result["errors"],
        "registry_mutation_allowed": False,
        "manuscript_mutation_allowed": False,
        "next_design_recommendation": "lean_case_specific_redesign_after_r30_closeout",
    }
    write_json(out_dir / "summary.json", summary)
    write_report(out_dir / OUT_REPORT, summary, gates, capacity, next_design)
    # Touch case_plan after output writes so missing columns are caught by read_csv_required but no unused import noise.
    _ = case_plan.shape
    return summary


def main() -> None:
    args = parser().parse_args()
    summary = run(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
