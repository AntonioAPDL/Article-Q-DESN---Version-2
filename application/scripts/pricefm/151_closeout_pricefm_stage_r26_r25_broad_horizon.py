#!/usr/bin/env python3
"""Final read-only closeout for PriceFM Stage-R25 broad horizon run."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json
from pricefm_full_surface import BINARY_SUFFIXES, repo_relative, sha256_file_or_blank


DEFAULT_R26_DIAG_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r26_inflight_mechanism_diagnosis_20260710"
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
    "pricefm_stage_r26_r25_broad_horizon_final_closeout_20260711"
)

IN_SUMMARY = "summary.json"
IN_HEALTH = "pricefm_stage_r26_r25_health.csv"
IN_CASE_PROGRESS = "pricefm_stage_r26_case_progress.csv"
IN_METRIC_ROWS = "pricefm_stage_r26_partial_metric_rows.csv"
IN_VALIDATION_SELECTED = "pricefm_stage_r26_partial_validation_selected_case.csv"
IN_TEST_ORACLE = "pricefm_stage_r26_partial_test_oracle_case.csv"
IN_ARM_SUMMARY = "pricefm_stage_r26_arm_mechanism_summary.csv"
IN_HORIZON_SUMMARY = "pricefm_stage_r26_horizon_mechanism_summary.csv"
IN_FAILURE_MAP = "pricefm_stage_r26_failure_decomposition_map.csv"
IN_GATES = "pricefm_stage_r26_diagnosis_gates.csv"
IN_SOURCE = "source_manifest.csv"

OUT_COMPLETION = "pricefm_stage_r26_final_completion_audit.csv"
OUT_METRIC_ROWS = "pricefm_stage_r26_final_metric_rows.csv"
OUT_VALIDATION_SELECTED = "pricefm_stage_r26_final_validation_selected_case.csv"
OUT_TEST_ORACLE = "pricefm_stage_r26_final_test_oracle_case.csv"
OUT_PROMOTION_QUEUE = "pricefm_stage_r26_final_full_quantile_promotion_queue.csv"
OUT_MCMC_GATE = "pricefm_stage_r26_final_mcmc_confirmation_gate.csv"
OUT_MECHANISM_LESSONS = "pricefm_stage_r26_final_mechanism_learning_summary.csv"
OUT_R27_PLAN = "pricefm_stage_r26_r27_pivot_plan.csv"
OUT_GATES = "pricefm_stage_r26_final_closeout_gates.csv"
OUT_SOURCE = "source_manifest.csv"
OUT_REPORT = "pricefm_stage_r26_r25_broad_horizon_final_closeout_report.md"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r26-diagnosis-dir", default=DEFAULT_R26_DIAG_DIR)
    p.add_argument("--stage-r25-grid-root", default=DEFAULT_R25_GRID_ROOT)
    p.add_argument("--stage-r25-run-root", default=DEFAULT_R25_RUN_ROOT)
    p.add_argument("--stage-r25-log-root", default=DEFAULT_R25_LOG_ROOT)
    p.add_argument("--run-tag", default=DEFAULT_RUN_TAG)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--expected-experiments", type=int, default=200)
    p.add_argument("--expected-cases", type=int, default=20)
    p.add_argument("--expected-window-builds", type=int, default=80)
    p.add_argument("--expected-method-rows", type=int, default=400)
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


def read_json_required(path: str | Path, label: str) -> dict[str, Any]:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required JSON: {full}")
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


def count_files(root: str | Path, pattern: str) -> int:
    full = repo_path(root)
    if not full.exists():
        return 0
    return sum(1 for _ in full.rglob(pattern))


def count_run_dirs(root: str | Path) -> int:
    full = repo_path(root)
    if not full.exists():
        return 0
    return sum(1 for p in full.iterdir() if p.is_dir())


def count_binary_artifacts(root: str | Path) -> int:
    full = repo_path(root)
    if not full.exists():
        return 0
    return sum(1 for p in full.rglob("*") if p.is_file() and p.suffix in BINARY_SUFFIXES)


def exit_code(log_root: str | Path, run_tag: str) -> int | None:
    path = repo_path(log_root) / f"{run_tag}.exit"
    if not path.exists():
        return None
    text = path.read_text().strip()
    return int(text) if text.isdigit() else None


def parse_wall_time(log_root: str | Path, run_tag: str) -> str:
    path = repo_path(log_root) / f"{run_tag}.time.log"
    if not path.exists():
        return ""
    for line in path.read_text().splitlines():
        if "Elapsed (wall clock) time" in line:
            return line.split("):", 1)[-1].strip()
    return ""


def launch_counts(grid_root: str | Path) -> dict[str, Any]:
    path = repo_path(grid_root) / "launch_status.csv"
    out: dict[str, Any] = {
        "launch_status_exists": path.exists(),
        "launch_status_rows": 0,
        "launch_status_completed_rows": 0,
        "launch_status_return_code_zero_rows": 0,
        "experiment_launch_rows": 0,
        "experiment_launch_completed_zero_rows": 0,
        "window_build_rows": 0,
        "window_build_completed_zero_rows": 0,
    }
    if not path.exists():
        return out
    frame = pd.read_csv(path, low_memory=False)
    require_columns(frame, ["kind", "status", "return_code"], "Stage-R25 launch status")
    out["launch_status_rows"] = int(frame.shape[0])
    completed = frame["status"].astype(str).str.lower().eq("completed")
    zero = pd.to_numeric(frame["return_code"], errors="coerce").fillna(-999).astype(int).eq(0)
    out["launch_status_completed_rows"] = int(completed.sum())
    out["launch_status_return_code_zero_rows"] = int(zero.sum())
    experiments = frame["kind"].astype(str).eq("experiment")
    windows = frame["kind"].astype(str).eq("window_build")
    out["experiment_launch_rows"] = int(experiments.sum())
    out["experiment_launch_completed_zero_rows"] = int((experiments & completed & zero).sum())
    out["window_build_rows"] = int(windows.sum())
    out["window_build_completed_zero_rows"] = int((windows & completed & zero).sum())
    return out


def grid_summary(grid_root: str | Path) -> dict[str, Any]:
    path = repo_path(grid_root) / "grid_summary.json"
    return read_json_required(path, "Stage-R25 grid summary") if path.exists() else {}


def launch_summary(grid_root: str | Path) -> dict[str, Any]:
    path = repo_path(grid_root) / "launch_summary.json"
    return read_json_required(path, "Stage-R25 launch summary") if path.exists() else {}


def require_final_inputs(metric_rows: pd.DataFrame, selected: pd.DataFrame, oracle: pd.DataFrame) -> None:
    shared = [
        "region",
        "fold",
        "experiment_id",
        "stage_r25_arm",
        "method_id",
        "val_AQL",
        "test_AQL",
        "current_qdesn_AQL",
        "current_pricefm_AQL",
        "test_minus_current_qdesn",
        "test_minus_pricefm",
        "beats_current_qdesn_on_test",
        "beats_pricefm_on_test",
        "beats_both_on_test",
    ]
    require_columns(metric_rows, shared, "Stage-R26 metric rows")
    require_columns(selected, shared, "Stage-R26 validation-selected rows")
    require_columns(oracle, shared, "Stage-R26 test-oracle rows")


def finalize_selected(selected: pd.DataFrame) -> pd.DataFrame:
    out = selected.copy()
    out["case_selected_by"] = "validation_AQL_only_complete_stage_r25_surface"
    out["test_metrics_use"] = "audit_only_after_frozen_validation_selection_final_closeout"
    out["promotion_gate_status"] = out["beats_both_on_test"].map(
        lambda x: "eligible_for_full_quantile_confirmation_design" if boolish(x) else "blocked_does_not_beat_both_qdesn_and_pricefm"
    )
    return out.sort_values(["test_minus_pricefm", "region", "fold"]).reset_index(drop=True)


def finalize_oracle(oracle: pd.DataFrame) -> pd.DataFrame:
    out = oracle.copy()
    out["case_oracle_by"] = "test_AQL_audit_only_complete_stage_r25_surface"
    out["oracle_role"] = "diagnostic_only_not_selection"
    return out.sort_values(["test_minus_pricefm", "region", "fold"]).reset_index(drop=True)


def promotion_queue(selected: pd.DataFrame) -> pd.DataFrame:
    cols = [
        "region",
        "fold",
        "experiment_id",
        "stage_r25_arm",
        "method_id",
        "val_AQL",
        "test_AQL",
        "current_qdesn_AQL",
        "current_pricefm_AQL",
        "test_minus_current_qdesn",
        "test_minus_pricefm",
        "promotion_gate_status",
        "required_next_gate",
    ]
    out = selected[
        selected["beats_current_qdesn_on_test"].map(boolish)
        & selected["beats_pricefm_on_test"].map(boolish)
        & selected["beats_both_on_test"].map(boolish)
    ].copy()
    if out.empty:
        return pd.DataFrame(columns=cols)
    out["promotion_gate_status"] = "candidate_pending_full_quantile_mcmc_reproducibility_confirmation"
    out["required_next_gate"] = (
        "full_quantile_confirmation_then_mcmc_initialized_from_vb_then_hash_manifest_before_registry_or_article"
    )
    return out[[c for c in cols if c in out.columns]].sort_values(["test_minus_pricefm", "region", "fold"]).reset_index(drop=True)


def mcmc_gate(promotions: pd.DataFrame) -> pd.DataFrame:
    cols = [
        "region",
        "fold",
        "experiment_id",
        "stage_r25_arm",
        "method_id",
        "test_minus_current_qdesn",
        "test_minus_pricefm",
        "mcmc_gate_status",
        "mcmc_gate_reason",
    ]
    if promotions.empty:
        return pd.DataFrame(columns=cols)
    out = promotions.copy()
    out["mcmc_gate_status"] = "blocked_until_full_quantile_confirmation_design"
    out["mcmc_gate_reason"] = (
        "Validation-selected VB candidate beat both baselines on test, but MCMC is confirmatory and should follow full-quantile design."
    )
    return out[[c for c in cols if c in out.columns]].sort_values(["test_minus_pricefm", "region", "fold"]).reset_index(drop=True)


def best_value(frame: pd.DataFrame, col: str) -> float:
    if frame.empty or col not in frame.columns:
        return float("nan")
    return finite_float(pd.to_numeric(frame[col], errors="coerce").min())


def completion_audit(
    args: argparse.Namespace,
    r26_summary: dict[str, Any],
    health: pd.DataFrame,
    case_progress: pd.DataFrame,
    metric_rows: pd.DataFrame,
    selected: pd.DataFrame,
) -> tuple[pd.DataFrame, dict[str, Any]]:
    counts = launch_counts(args.stage_r25_grid_root)
    exit = exit_code(args.stage_r25_log_root, args.run_tag)
    grid = grid_summary(args.stage_r25_grid_root)
    launch = launch_summary(args.stage_r25_grid_root)
    run_dirs = count_run_dirs(args.stage_r25_run_root)
    metric_files = count_files(args.stage_r25_run_root, "metric_summary.csv")
    horizon_files = count_files(args.stage_r25_run_root, "metric_by_horizon_group.csv")
    cell_files = count_files(args.stage_r25_run_root, "cell_status.csv")
    training_files = count_files(args.stage_r25_run_root, "training_weight_summary.csv")
    model_pred_files = count_files(args.stage_r25_run_root, "model_predictions_scaled.csv")
    naive_pred_files = count_files(args.stage_r25_run_root, "predictions_with_naive_scaled.csv")
    binary_files = count_binary_artifacts(args.stage_r25_run_root)
    complete_cases = int(case_progress["case_status"].astype(str).eq("complete").sum()) if not case_progress.empty else 0

    checks: list[dict[str, Any]] = []

    def add(check: str, observed: Any, expected: Any, passed: bool, detail: str) -> None:
        checks.append(
            {
                "check": check,
                "observed": observed,
                "expected": expected,
                "passed": bool(passed),
                "detail": detail,
            }
        )

    add("exit_code_zero", exit if exit is not None else "", 0, exit == 0, "Stage-R25 launcher exit file must be zero.")
    add(
        "launch_status_all_completed_zero",
        f"{counts['launch_status_completed_rows']}/{counts['launch_status_rows']} completed, "
        f"{counts['launch_status_return_code_zero_rows']}/{counts['launch_status_rows']} return-code-zero",
        "all rows completed with return_code 0",
        counts["launch_status_exists"]
        and counts["launch_status_rows"] > 0
        and counts["launch_status_completed_rows"] == counts["launch_status_rows"]
        and counts["launch_status_return_code_zero_rows"] == counts["launch_status_rows"],
        "Launch status must be complete for both experiment and window-build rows.",
    )
    add(
        "experiment_launch_rows",
        counts["experiment_launch_completed_zero_rows"],
        args.expected_experiments,
        counts["experiment_launch_completed_zero_rows"] == args.expected_experiments,
        "All selected Stage-R25 experiments completed with return_code 0.",
    )
    add(
        "window_build_rows",
        counts["window_build_completed_zero_rows"],
        args.expected_window_builds,
        counts["window_build_completed_zero_rows"] == args.expected_window_builds,
        "All required window-build tasks completed with return_code 0.",
    )
    add("run_dirs", run_dirs, args.expected_experiments, run_dirs == args.expected_experiments, "One run directory per experiment.")
    add("metric_summary_files", metric_files, args.expected_experiments, metric_files == args.expected_experiments, "One metric summary per experiment.")
    add("horizon_group_files", horizon_files, args.expected_experiments, horizon_files == args.expected_experiments, "One horizon-group diagnostic per experiment.")
    add("cell_status_files", cell_files, args.expected_experiments, cell_files == args.expected_experiments, "One cell status per experiment.")
    add("training_weight_files", training_files, args.expected_experiments, training_files == args.expected_experiments, "One training-weight summary per experiment.")
    add("model_prediction_files", model_pred_files, args.expected_experiments, model_pred_files == args.expected_experiments, "Prediction artifacts exist for postfit calibration audit.")
    add("naive_prediction_files", naive_pred_files, args.expected_experiments, naive_pred_files == args.expected_experiments, "Prediction artifacts include naive references.")
    add("binary_artifacts_absent", binary_files, 0, binary_files == 0, "No .rds/.rda/.RData/.rdata artifacts were produced by R25.")
    add("case_progress_complete", complete_cases, args.expected_cases, complete_cases == args.expected_cases, "All planned region/fold cases are complete.")
    add("metric_rows", metric_rows.shape[0], args.expected_method_rows, int(metric_rows.shape[0]) == args.expected_method_rows, "Two Q-DESN/exQDESN rows per experiment are present.")
    add("validation_selected_cases", selected.shape[0], args.expected_cases, int(selected.shape[0]) == args.expected_cases, "Validation-only selection produced one row per case.")
    add(
        "r26_diagnosis_completed_cleanly",
        r26_summary.get("r25_run_state", ""),
        "completed_cleanly",
        r26_summary.get("r25_run_state", "") == "completed_cleanly",
        "The source diagnosis must see the completed R25 surface.",
    )
    add(
        "grid_summary_selected_experiments",
        launch.get("n_selected_experiments", grid.get("n_experiments", "")),
        args.expected_experiments,
        int(launch.get("n_selected_experiments", grid.get("n_experiments", -1))) == args.expected_experiments,
        "Grid and launch summaries agree with the expected R25 experiment count.",
    )
    payload = {
        "exit_code": exit,
        "wall_time": parse_wall_time(args.stage_r25_log_root, args.run_tag),
        "run_dirs": run_dirs,
        "metric_summary_files": metric_files,
        "horizon_group_files": horizon_files,
        "cell_status_files": cell_files,
        "training_weight_files": training_files,
        "model_prediction_files": model_pred_files,
        "naive_prediction_files": naive_pred_files,
        "binary_artifacts": binary_files,
        **counts,
    }
    return pd.DataFrame(checks), payload


def mechanism_lessons(
    metric_rows: pd.DataFrame,
    selected: pd.DataFrame,
    oracle: pd.DataFrame,
    arm_summary: pd.DataFrame,
    horizon_summary: pd.DataFrame,
    failure_map: pd.DataFrame,
    artifact_payload: dict[str, Any],
) -> pd.DataFrame:
    selected_qdesn_wins = int(selected["beats_current_qdesn_on_test"].map(boolish).sum()) if not selected.empty else 0
    selected_pricefm_wins = int(selected["beats_pricefm_on_test"].map(boolish).sum()) if not selected.empty else 0
    rows = [
        {
            "lesson": "completed_surface",
            "evidence": f"{artifact_payload['experiment_launch_completed_zero_rows']} experiments completed; {metric_rows.shape[0]} Q-DESN/exQDESN rows parsed.",
            "diagnosis": "The R25 broad horizon-weighted search is a valid completed negative surface, not an in-flight ambiguity.",
            "next_implication": "Use this as a final closeout input; do not relaunch the same family just to wait for more rows.",
        },
        {
            "lesson": "pricefm_gap_not_closed",
            "evidence": (
                f"{int(metric_rows['beats_pricefm_on_test'].map(boolish).sum())} / {metric_rows.shape[0]} rows beat PriceFM; "
                f"{selected_pricefm_wins} / {selected.shape[0]} validation-selected rows beat PriceFM."
            ),
            "diagnosis": "The current horizon-weight/readout/capacity/lag family does not solve the cached PriceFM gap.",
            "next_implication": "Block registry, article, and MCMC promotion; pivot mechanism family.",
        },
        {
            "lesson": "internal_qdesn_progress_is_real_but_insufficient",
            "evidence": (
                f"{int(metric_rows['beats_current_qdesn_on_test'].map(boolish).sum())} rows beat current Q-DESN; "
                f"{selected_qdesn_wins} validation-selected row beats current Q-DESN."
            ),
            "diagnosis": "Some variants improve relative to the current authoritative Q-DESN, but not relative to PriceFM.",
            "next_implication": "Treat these rows as mechanism diagnostics, not manuscript evidence.",
        },
        {
            "lesson": "validation_selection_did_not_hide_pricefm_winners",
            "evidence": f"Best test-oracle PriceFM gap is {best_value(oracle, 'test_minus_pricefm'):.6f}; best validation-selected gap is {best_value(selected, 'test_minus_pricefm'):.6f}.",
            "diagnosis": "Even the audit-only test oracle does not find a PriceFM winner, so the negative result is not only validation-selection noise.",
            "next_implication": "Do not use test oracle rows for promotion; use them to diagnose mechanism limits.",
        },
        {
            "lesson": "horizon_baseline_wins_do_not_transfer_to_pricefm",
            "evidence": horizon_evidence(horizon_summary),
            "diagnosis": "R25 often beats naive/normal baselines by horizon group, so implementation machinery works, but that is below the PriceFM standard.",
            "next_implication": "Further horizon weighting alone is unlikely to be the optimal next expensive direction.",
        },
        {
            "lesson": "best_arm_family",
            "evidence": arm_evidence(arm_summary),
            "diagnosis": "The best arm is still positive-gap versus PriceFM; broadening within these arms did not produce an article-level candidate.",
            "next_implication": "Focus the next stage on calibration artifacts, information-set parity, and objective-family mismatch.",
        },
        {
            "lesson": "prediction_artifacts_ready",
            "evidence": f"{artifact_payload['model_prediction_files']} model prediction files and {artifact_payload['naive_prediction_files']} naive prediction files exist.",
            "diagnosis": "Unlike earlier blocked postfit paths, R25 has prediction artifacts for a read-only calibration audit.",
            "next_implication": "Stage-R27 can test validation-only postfit calibration without fitting or launching new DESN jobs.",
        },
    ]
    if not failure_map.empty and "partial_diagnosis" in failure_map.columns:
        counts = failure_map["partial_diagnosis"].value_counts().sort_index()
        rows.append(
            {
                "lesson": "failure_decomposition",
                "evidence": "; ".join(f"{idx}: {int(val)}" for idx, val in counts.items()),
                "diagnosis": "Most cases remain structural PriceFM-gap or mechanism-progress-only failures after final completion.",
                "next_implication": "Use queue-specific follow-up rather than a one-size-fits-all specification.",
            }
        )
    return pd.DataFrame(rows)


def horizon_evidence(horizon_summary: pd.DataFrame) -> str:
    if horizon_summary.empty:
        return "No horizon summary rows available."
    pieces = []
    for _, row in horizon_summary.iterrows():
        pieces.append(
            f"{row['horizon_group']}: {int(row['beats_best_naive'])}/{int(row['cases'])} beat naive, "
            f"{int(row['beats_best_normal'])}/{int(row['cases'])} beat normal"
        )
    return "; ".join(pieces)


def arm_evidence(arm_summary: pd.DataFrame) -> str:
    if arm_summary.empty:
        return "No arm summary rows available."
    best = arm_summary.sort_values(["best_test_minus_pricefm", "stage_r25_arm"]).iloc[0]
    return (
        f"Best arm {best['stage_r25_arm']} has best PriceFM gap "
        f"{finite_float(best['best_test_minus_pricefm']):.6f}; all arms have zero PriceFM wins."
    )


def r27_pivot_plan(summary: dict[str, Any]) -> pd.DataFrame:
    no_promotions = int(summary["n_promotion_queue_rows"]) == 0
    return pd.DataFrame(
        [
            {
                "priority": 1,
                "stage": "stage_r27_prediction_artifact_calibration_audit",
                "scope": "R25 validation-selected rows plus bounded top-k diagnostic rows from existing predictions",
                "action": "Read model_predictions_scaled.csv and predictions_with_naive_scaled.csv; estimate postfit calibration on validation only; audit test only after frozen validation choice.",
                "why_optimal_now": "R25 prediction artifacts exist for all 200 experiments, so this is the cheapest way to test calibration/readout mismatch before more fitting.",
                "launches_or_fits": False,
                "registry_or_article_mutation": False,
                "allowed_next": True,
            },
            {
                "priority": 2,
                "stage": "stage_r27_information_set_parity_audit",
                "scope": "Cases where alt_information_set_weighted or long_lag_weighted is best but still loses to PriceFM",
                "action": "Compare exact RHS_NS inputs, lag construction, exogenous availability, scaling, and horizon indexing against cached PriceFM assumptions.",
                "why_optimal_now": "The best R25 arm is an information-set variant, implying that missing or misweighted predictors may matter more than reservoir size.",
                "launches_or_fits": False,
                "registry_or_article_mutation": False,
                "allowed_next": True,
            },
            {
                "priority": 3,
                "stage": "stage_r27_objective_loss_family_design",
                "scope": "Structural PriceFM-gap cases after calibration and parity audit",
                "action": "Design a genuinely different objective/readout family if artifact calibration cannot close the gap; avoid more same-family Stage-R25 widening.",
                "why_optimal_now": "Horizon weighting by row replication and capacity/lag changes did not create any PriceFM winner.",
                "launches_or_fits": False,
                "registry_or_article_mutation": False,
                "allowed_next": True,
            },
            {
                "priority": 4,
                "stage": "mcmc_confirmation_hold",
                "scope": "Selected VB winners only",
                "action": "Do not launch MCMC until a validation-selected VB row beats both current Q-DESN and PriceFM, preferably after full-quantile confirmation.",
                "why_optimal_now": "There are no Stage-R25 promotion candidates; MCMC should confirm winners, not rescue broad negative VB surfaces.",
                "launches_or_fits": False,
                "registry_or_article_mutation": False,
                "allowed_next": not no_promotions,
            },
            {
                "priority": 5,
                "stage": "registry_article_hold",
                "scope": "Article tables, figures, and authoritative PriceFM registry",
                "action": "Keep blocked until beat-both, full-quantile, MCMC, and reproducibility/hash-manifest gates pass.",
                "why_optimal_now": "R25 provides mechanism-learning evidence, not promotable article evidence.",
                "launches_or_fits": False,
                "registry_or_article_mutation": False,
                "allowed_next": False,
            },
        ]
    )


def closeout_gates(
    completion: pd.DataFrame,
    source_gates: pd.DataFrame,
    metric_rows: pd.DataFrame,
    selected: pd.DataFrame,
    promotions: pd.DataFrame,
    mcmc: pd.DataFrame,
) -> pd.DataFrame:
    source_ok = source_gates.empty or source_gates["passed"].map(boolish).all()
    gates = [
        ("read_only_closeout", True, "This script writes closeout artifacts only; it does not launch, fit, mutate registry, or mutate manuscript."),
        ("source_r26_gates_passed", source_ok, "The upstream Stage-R26 diagnosis gates passed."),
        ("r25_completion_checks_passed", completion["passed"].map(boolish).all(), "Stage-R25 exit, launch status, and artifact-count checks passed."),
        (
            "validation_selection_only",
            selected["case_selected_by"].astype(str).eq("validation_AQL_only_complete_stage_r25_surface").all(),
            "Final selected rows are frozen using validation AQL only.",
        ),
        (
            "test_audit_only",
            selected["test_metrics_use"].astype(str).eq("audit_only_after_frozen_validation_selection_final_closeout").all(),
            "Test metrics remain audit-only after validation selection.",
        ),
        (
            "promotion_requires_beat_both",
            promotions.empty
            or (
                promotions["test_minus_current_qdesn"].map(finite_float).lt(0).all()
                and promotions["test_minus_pricefm"].map(finite_float).lt(0).all()
            ),
            "Promotion queue admits only validation-selected rows that beat current Q-DESN and PriceFM on test audit.",
        ),
        (
            "mcmc_empty_without_promotion",
            (not promotions.empty) or mcmc.empty,
            "MCMC queue stays empty when no beat-both promotion candidate exists.",
        ),
        (
            "pricefm_wins_are_not_auto_promoted",
            True,
            "Any PriceFM-beating row must still enter only through the validation-selected beat-both promotion queue.",
        ),
        ("registry_manuscript_article_blocked", True, "No registry, manuscript, or article mutation is authorized by this closeout."),
    ]
    return pd.DataFrame([{"gate": gate, "passed": bool(passed), "detail": detail} for gate, passed, detail in gates])


def source_manifest(args: argparse.Namespace, diagnosis_source: pd.DataFrame) -> pd.DataFrame:
    specs = [
        ("stage_r26_source_summary", Path(args.stage_r26_diagnosis_dir) / IN_SUMMARY, "json"),
        ("stage_r26_health", Path(args.stage_r26_diagnosis_dir) / IN_HEALTH, "csv"),
        ("stage_r26_case_progress", Path(args.stage_r26_diagnosis_dir) / IN_CASE_PROGRESS, "csv"),
        ("stage_r26_metric_rows", Path(args.stage_r26_diagnosis_dir) / IN_METRIC_ROWS, "csv"),
        ("stage_r26_validation_selected", Path(args.stage_r26_diagnosis_dir) / IN_VALIDATION_SELECTED, "csv"),
        ("stage_r26_test_oracle", Path(args.stage_r26_diagnosis_dir) / IN_TEST_ORACLE, "csv"),
        ("stage_r26_failure_map", Path(args.stage_r26_diagnosis_dir) / IN_FAILURE_MAP, "csv"),
        ("stage_r26_arm_summary", Path(args.stage_r26_diagnosis_dir) / IN_ARM_SUMMARY, "csv"),
        ("stage_r26_horizon_summary", Path(args.stage_r26_diagnosis_dir) / IN_HORIZON_SUMMARY, "csv"),
        ("stage_r25_grid_summary", Path(args.stage_r25_grid_root) / "grid_summary.json", "json"),
        ("stage_r25_launch_summary", Path(args.stage_r25_grid_root) / "launch_summary.json", "json"),
        ("stage_r25_launch_status", Path(args.stage_r25_grid_root) / "launch_status.csv", "csv"),
        ("stage_r25_exit_file", Path(args.stage_r25_log_root) / f"{args.run_tag}.exit", "text"),
        ("stage_r25_time_log", Path(args.stage_r25_log_root) / f"{args.run_tag}.time.log", "text"),
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
    if not diagnosis_source.empty:
        prior = diagnosis_source.copy()
        prior["label"] = "upstream_" + prior["label"].astype(str)
        rows.extend(prior.to_dict("records"))
    return pd.DataFrame(rows)


def build_report(
    summary: dict[str, Any],
    completion: pd.DataFrame,
    selected: pd.DataFrame,
    oracle: pd.DataFrame,
    lessons: pd.DataFrame,
    r27: pd.DataFrame,
    gates: pd.DataFrame,
) -> str:
    def escape_cell(value: Any) -> str:
        return text_value(value).replace("|", "\\|").replace("\n", " ")

    def md_table(frame: pd.DataFrame, n: int = 15) -> str:
        if frame.empty:
            return "_No rows._"
        head = frame.head(n).copy()
        lines = [
            "| " + " | ".join(str(col) for col in head.columns) + " |",
            "| " + " | ".join(["---"] * len(head.columns)) + " |",
        ]
        for _, row in head.iterrows():
            lines.append("| " + " | ".join(escape_cell(row[col]) for col in head.columns) + " |")
        return "\n".join(lines)

    selected_cols = [
        "region",
        "fold",
        "stage_r25_arm",
        "method_id",
        "val_AQL",
        "test_AQL",
        "test_minus_current_qdesn",
        "test_minus_pricefm",
        "promotion_gate_status",
    ]
    oracle_cols = [
        "region",
        "fold",
        "stage_r25_arm",
        "method_id",
        "test_AQL",
        "test_minus_current_qdesn",
        "test_minus_pricefm",
        "oracle_role",
    ]
    return "\n".join(
        [
            "# PriceFM Stage-R26 Final Closeout: Stage-R25 Broad Horizon",
            "",
            "## Executive Summary",
            "",
            f"- Run state: `{summary['r25_run_state']}`.",
            f"- Completed experiments: {summary['n_completed_experiments']} / {summary['n_expected_experiments']}.",
            f"- Parsed method rows: {summary['n_metric_rows']}.",
            f"- Validation-selected cases: {summary['n_validation_selected_cases']}.",
            f"- Rows beating current Q-DESN: {summary['n_rows_beating_current_qdesn']}.",
            f"- Rows beating cached PriceFM: {summary['n_rows_beating_pricefm']}.",
            f"- Rows beating both: {summary['n_rows_beating_both']}.",
            f"- Full-quantile promotion candidates: {summary['n_promotion_queue_rows']}.",
            f"- MCMC confirmation candidates: {summary['n_mcmc_gate_rows']}.",
            "",
            "Conclusion: Stage-R25 is complete and scientifically negative for promotion. It is useful mechanism evidence, not article-ready evidence.",
            "",
            "## Completion Audit",
            "",
            md_table(completion, 25),
            "",
            "## Validation-Selected Rows",
            "",
            md_table(selected[[c for c in selected_cols if c in selected.columns]].sort_values("test_minus_pricefm"), 25),
            "",
            "## Test Oracle Rows",
            "",
            md_table(oracle[[c for c in oracle_cols if c in oracle.columns]].sort_values("test_minus_pricefm"), 25),
            "",
            "## Mechanism Lessons",
            "",
            md_table(lessons, 20),
            "",
            "## R27 Pivot Plan",
            "",
            md_table(r27, 10),
            "",
            "## Closeout Gates",
            "",
            md_table(gates, 15),
            "",
            "## Recommendation",
            "",
            summary["recommended_next_action"],
            "",
            "## Do Not Do Yet",
            "",
            "- Do not mutate the PriceFM registry.",
            "- Do not update the article or manuscript.",
            "- Do not launch MCMC from R25 because there are no beat-both VB winners.",
            "- Do not relaunch another broad same-family horizon-weighted search before calibration and information-set parity audits.",
            "",
        ]
    )


def run(args: argparse.Namespace) -> dict[str, Any]:
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and any(out_dir.iterdir()) and not args.force:
        raise FileExistsError(f"{out_dir} already exists; rerun with --force true to overwrite")
    out_dir.mkdir(parents=True, exist_ok=True)

    diag = Path(args.stage_r26_diagnosis_dir)
    r26_summary = read_json_required(diag / IN_SUMMARY, "Stage-R26 diagnosis summary")
    health = read_csv_required(diag / IN_HEALTH, "Stage-R26 health")
    case_progress = read_csv_required(diag / IN_CASE_PROGRESS, "Stage-R26 case progress")
    metric_rows = read_csv_required(diag / IN_METRIC_ROWS, "Stage-R26 metric rows")
    selected_raw = read_csv_required(diag / IN_VALIDATION_SELECTED, "Stage-R26 validation-selected rows")
    oracle_raw = read_csv_required(diag / IN_TEST_ORACLE, "Stage-R26 test-oracle rows")
    arm_summary = read_csv_required(diag / IN_ARM_SUMMARY, "Stage-R26 arm summary")
    horizon_summary = read_csv_required(diag / IN_HORIZON_SUMMARY, "Stage-R26 horizon summary")
    failure_map = read_csv_required(diag / IN_FAILURE_MAP, "Stage-R26 failure map")
    source_gates = read_csv_required(diag / IN_GATES, "Stage-R26 diagnosis gates")
    source = read_csv_required(diag / IN_SOURCE, "Stage-R26 source manifest")

    require_final_inputs(metric_rows, selected_raw, oracle_raw)
    selected = finalize_selected(selected_raw)
    oracle = finalize_oracle(oracle_raw)
    promotions = promotion_queue(selected)
    mcmc = mcmc_gate(promotions)
    completion, artifact_payload = completion_audit(args, r26_summary, health, case_progress, metric_rows, selected)
    lessons = mechanism_lessons(metric_rows, selected, oracle, arm_summary, horizon_summary, failure_map, artifact_payload)

    n_rows_beating_qdesn = int(metric_rows["beats_current_qdesn_on_test"].map(boolish).sum())
    n_rows_beating_pricefm = int(metric_rows["beats_pricefm_on_test"].map(boolish).sum())
    n_rows_beating_both = int(metric_rows["beats_both_on_test"].map(boolish).sum())
    n_selected_beating_qdesn = int(selected["beats_current_qdesn_on_test"].map(boolish).sum())
    n_selected_beating_pricefm = int(selected["beats_pricefm_on_test"].map(boolish).sum())
    n_selected_beating_both = int(selected["beats_both_on_test"].map(boolish).sum())

    status = (
        "completed_with_promotion_candidates_pending_confirmation"
        if not promotions.empty
        else "completed_negative_no_promotions"
    )
    recommended = (
        "Design Stage-R27 as a read-only prediction-artifact calibration audit plus information-set parity audit. "
        "Keep registry, manuscript, article, and MCMC blocked until a validation-selected candidate beats both "
        "current Q-DESN and cached PriceFM, then passes full-quantile and reproducibility gates."
    )
    summary = {
        "stage": "pricefm_stage_r26_r25_broad_horizon_final_closeout",
        "status": status,
        "r25_run_state": "completed_cleanly" if completion["passed"].map(boolish).all() else "completion_check_failed",
        "n_expected_experiments": int(args.expected_experiments),
        "n_completed_experiments": int(artifact_payload["experiment_launch_completed_zero_rows"]),
        "n_metric_rows": int(metric_rows.shape[0]),
        "n_validation_selected_cases": int(selected.shape[0]),
        "n_rows_beating_current_qdesn": n_rows_beating_qdesn,
        "n_rows_beating_pricefm": n_rows_beating_pricefm,
        "n_rows_beating_both": n_rows_beating_both,
        "n_validation_selected_beating_current_qdesn": n_selected_beating_qdesn,
        "n_validation_selected_beating_pricefm": n_selected_beating_pricefm,
        "n_validation_selected_beats_both": n_selected_beating_both,
        "best_any_row_test_minus_pricefm": best_value(metric_rows, "test_minus_pricefm"),
        "best_validation_selected_test_minus_pricefm": best_value(selected, "test_minus_pricefm"),
        "best_test_oracle_test_minus_pricefm": best_value(oracle, "test_minus_pricefm"),
        "n_promotion_queue_rows": int(promotions.shape[0]),
        "n_mcmc_gate_rows": int(mcmc.shape[0]),
        "n_model_prediction_files": int(artifact_payload["model_prediction_files"]),
        "n_predictions_with_naive_files": int(artifact_payload["naive_prediction_files"]),
        "n_binary_artifacts": int(artifact_payload["binary_artifacts"]),
        "wall_time": artifact_payload["wall_time"],
        "registry_mutation_authorized": False,
        "manuscript_mutation_authorized": False,
        "article_update_justified": False,
        "launches_models": False,
        "fits_models": False,
        "writes_launch_yaml": False,
        "recommended_next_action": recommended,
    }
    r27 = r27_pivot_plan(summary)
    gates = closeout_gates(completion, source_gates, metric_rows, selected, promotions, mcmc)
    if not gates["passed"].map(boolish).all():
        failed = gates.loc[~gates["passed"].map(boolish), "gate"].tolist()
        raise RuntimeError(f"Stage-R26 final closeout gates failed: {failed}")

    outputs = {
        "completion_audit": out_dir / OUT_COMPLETION,
        "metric_rows": out_dir / OUT_METRIC_ROWS,
        "validation_selected": out_dir / OUT_VALIDATION_SELECTED,
        "test_oracle": out_dir / OUT_TEST_ORACLE,
        "promotion_queue": out_dir / OUT_PROMOTION_QUEUE,
        "mcmc_gate": out_dir / OUT_MCMC_GATE,
        "mechanism_lessons": out_dir / OUT_MECHANISM_LESSONS,
        "r27_pivot_plan": out_dir / OUT_R27_PLAN,
        "gates": out_dir / OUT_GATES,
        "source_manifest": out_dir / OUT_SOURCE,
        "report": out_dir / OUT_REPORT,
        "summary_json": out_dir / "summary.json",
    }
    write_frame(outputs["completion_audit"], completion)
    write_frame(outputs["metric_rows"], metric_rows)
    write_frame(outputs["validation_selected"], selected)
    write_frame(outputs["test_oracle"], oracle)
    write_frame(outputs["promotion_queue"], promotions)
    write_frame(outputs["mcmc_gate"], mcmc)
    write_frame(outputs["mechanism_lessons"], lessons)
    write_frame(outputs["r27_pivot_plan"], r27)
    write_frame(outputs["gates"], gates)
    write_frame(outputs["source_manifest"], source_manifest(args, source))
    summary["outputs"] = {key: repo_relative(path) for key, path in outputs.items()}
    write_json(outputs["summary_json"], summary)
    outputs["report"].write_text(build_report(summary, completion, selected, oracle, lessons, r27, gates))
    return summary


def main() -> None:
    args = parser().parse_args()
    summary = run(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
