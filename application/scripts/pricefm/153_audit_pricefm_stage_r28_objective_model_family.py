#!/usr/bin/env python3
"""PriceFM Stage-R28 read-only objective/model-family design audit."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json
from pricefm_full_surface import repo_relative, sha256_file_or_blank


DEFAULT_R26_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r26_r25_broad_horizon_final_closeout_20260711"
)
DEFAULT_R27_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r27_calibration_parity_audit_20260711"
)
DEFAULT_R25_PREP_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r25_post_r24_broad_launch_prep_20260709"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r28_objective_model_family_audit_20260711"
)

R26_SELECTED = "pricefm_stage_r26_final_validation_selected_case.csv"
R26_METRICS = "pricefm_stage_r26_final_metric_rows.csv"
R27_CASE_SELECTION = "pricefm_stage_r27_case_calibration_selection.csv"
R27_NEXT = "pricefm_stage_r27_next_action_plan.csv"
R27_PARITY = "pricefm_stage_r27_information_set_parity_audit.csv"
R25_MANIFEST = "pricefm_stage_r25_launch_manifest.csv"

OUT_CAPABILITY = "pricefm_stage_r28_objective_model_capability_matrix.csv"
OUT_FAMILY_TRANSFER = "pricefm_stage_r28_likelihood_family_transfer.csv"
OUT_CASE_QUEUE = "pricefm_stage_r28_case_target_queue.csv"
OUT_FAILURE_ATLAS = "pricefm_stage_r28_objective_failure_atlas.csv"
OUT_RECOMMENDATIONS = "pricefm_stage_r28_main_launch_recommendations.csv"
OUT_GATES = "pricefm_stage_r28_design_gates.csv"
OUT_SOURCE = "source_manifest.csv"
OUT_REPORT = "pricefm_stage_r28_objective_model_family_audit_report.md"

SOURCE_DEFAULTS = {
    "adapter_builder": "application/scripts/pricefm/pricefm_desn_adapter.py",
    "full_run_orchestrator": "application/scripts/pricefm/pricefm_full_run.py",
    "grid_materializer": "application/scripts/pricefm/12_prepare_desn_experiment_grid.py",
    "model_runner": "application/scripts/pricefm/08_run_desn_model_smoke.R",
    "grid_launcher": "application/scripts/pricefm/13_run_desn_experiment_grid.py",
}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r26-dir", default=DEFAULT_R26_DIR)
    p.add_argument("--stage-r27-dir", default=DEFAULT_R27_DIR)
    p.add_argument("--stage-r25-prep-dir", default=DEFAULT_R25_PREP_DIR)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    for label, default in SOURCE_DEFAULTS.items():
        p.add_argument(f"--source-{label.replace('_', '-')}", default=default)
    p.add_argument("--expected-cases", type=int, default=20)
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


def require_columns(frame: pd.DataFrame, columns: list[str], label: str) -> None:
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError(f"{label} missing required columns: {missing}")


def write_frame(path: str | Path, frame: pd.DataFrame) -> None:
    full = repo_path(path)
    full.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(full, index=False)


def source_paths(args: argparse.Namespace) -> dict[str, Path]:
    return {label: repo_path(getattr(args, f"source_{label}")) for label in SOURCE_DEFAULTS}


def read_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(errors="replace")


def source_manifest(args: argparse.Namespace, paths: dict[str, Path]) -> pd.DataFrame:
    specs = [
        ("stage_r26_summary", Path(args.stage_r26_dir) / "summary.json", "json"),
        ("stage_r26_selected", Path(args.stage_r26_dir) / R26_SELECTED, "csv"),
        ("stage_r26_metric_rows", Path(args.stage_r26_dir) / R26_METRICS, "csv"),
        ("stage_r27_summary", Path(args.stage_r27_dir) / "summary.json", "json"),
        ("stage_r27_case_selection", Path(args.stage_r27_dir) / R27_CASE_SELECTION, "csv"),
        ("stage_r27_next_action", Path(args.stage_r27_dir) / R27_NEXT, "csv"),
        ("stage_r27_information_set_parity", Path(args.stage_r27_dir) / R27_PARITY, "csv"),
        ("stage_r25_launch_manifest", Path(args.stage_r25_prep_dir) / R25_MANIFEST, "csv"),
    ]
    specs.extend((label, path, "source") for label, path in paths.items())
    rows = []
    for label, path, kind in specs:
        full = repo_path(path)
        rows.append(
            {
                "label": label,
                "kind": kind,
                "path": repo_relative(full) if str(full).startswith(str(repo_path("."))) else str(full),
                "exists": full.exists(),
                "bytes": int(full.stat().st_size) if full.exists() and full.is_file() else 0,
                "sha256": sha256_file_or_blank(full) if full.exists() and full.is_file() else "",
            }
        )
    return pd.DataFrame(rows)


def capability_matrix(paths: dict[str, Path]) -> pd.DataFrame:
    adapter = read_text(paths["adapter_builder"])
    full_run = read_text(paths["full_run_orchestrator"])
    grid = read_text(paths["grid_materializer"])
    runner = read_text(paths["model_runner"])
    rows = [
        {
            "mechanism": "new_likelihood_or_loss_family",
            "current_support": "blocked_al_exal_only",
            "runner_consumes_it": False,
            "evidence": "PriceFM runner fits AL and exAL; no separate likelihood/loss family is exposed.",
            "launch_implication": "Do not launch a fake new likelihood family from YAML.",
        },
        {
            "mechanism": "horizon_weighted_training",
            "current_support": "implemented_as_integer_frequency_replication",
            "runner_consumes_it": "horizon_weighting" in runner and "rep(seq_len(nrow(X_train))" in runner,
            "evidence": "R24/R25 runner expands selected training rows before Q-DESN fitting.",
            "launch_implication": "May be retained, but R25 showed this alone is insufficient.",
        },
        {
            "mechanism": "postfit_calibration",
            "current_support": "read_only_existing_prediction_audit",
            "runner_consumes_it": False,
            "evidence": "R27 applies validation-fit calibration to existing prediction artifacts only.",
            "launch_implication": "Use only after prediction artifacts exist; do not count it as a launch-time model family.",
        },
        {
            "mechanism": "horizon_block_readout_interaction",
            "current_support": (
                "implemented_design_matrix_axis"
                if all(
                    term in adapter + full_run + grid
                    for term in ["readout_interaction", "horizon_block", "horizon_block_size"]
                )
                else "not_supported"
            ),
            "runner_consumes_it": (
                "readout_interaction" in full_run
                and "readout_interaction" in grid
                and "append_readout_interactions" in adapter
            ),
            "evidence": "Adapter can append horizon-block interactions as ordinary design-matrix columns consumed by AL/exAL.",
            "launch_implication": "This is the supported non-R25-style main-launch mechanism.",
        },
        {
            "mechanism": "graph_information_set",
            "current_support": "implemented_but_not_sufficient_in_r25_r27",
            "runner_consumes_it": "feature_policy" in full_run and "feature_policy" in adapter,
            "evidence": "R27 manifests show graph policies were present while PriceFM gaps remained.",
            "launch_implication": "Keep graph/local arms for parity and harm guards, but not as the sole mechanism.",
        },
        {
            "mechanism": "mcmc_confirmation",
            "current_support": "blocked_until_vb_winner_exists",
            "runner_consumes_it": False,
            "evidence": "R26/R27 produced no validation-selected beat-both VB winner.",
            "launch_implication": "MCMC remains confirmatory, not a rescue stage.",
        },
    ]
    return pd.DataFrame(rows)


def likelihood_family_transfer(metrics: pd.DataFrame) -> pd.DataFrame:
    require_columns(metrics, ["method_id", "stage_r25_arm", "feature_policy", "test_minus_pricefm", "test_minus_current_qdesn"], "R26 metric rows")
    rows = []
    for keys, group in metrics.groupby(["method_id", "stage_r25_arm", "feature_policy"], dropna=False):
        method, arm, policy = keys
        rows.append(
            {
                "method_id": method,
                "stage_r25_arm": arm,
                "feature_policy": policy,
                "rows": int(group.shape[0]),
                "best_test_minus_pricefm": float(pd.to_numeric(group["test_minus_pricefm"], errors="coerce").min()),
                "median_test_minus_pricefm": float(pd.to_numeric(group["test_minus_pricefm"], errors="coerce").median()),
                "rows_beating_pricefm": int(group["test_minus_pricefm"].lt(0).sum()),
                "rows_beating_current_qdesn": int(group["test_minus_current_qdesn"].lt(0).sum()),
            }
        )
    return pd.DataFrame(rows).sort_values(["best_test_minus_pricefm", "method_id"]).reset_index(drop=True)


def build_case_queue(selected: pd.DataFrame, r27_case: pd.DataFrame) -> pd.DataFrame:
    require_columns(
        selected,
        [
            "region",
            "fold",
            "stage_r22b_case_id",
            "horizon_focus",
            "feature_policy",
            "stage_r25_arm",
            "method_id",
            "test_minus_pricefm",
            "test_minus_current_qdesn",
            "current_pricefm_AQL",
            "current_qdesn_AQL",
            "lag_window",
            "depth",
            "units",
            "feature_dim",
            "state_output",
            "alpha",
            "rho",
            "input_scale",
            "tau0",
            "horizon_weight_multiplier",
        ],
        "R26 validation-selected rows",
    )
    selected = selected.copy()
    selected["region"] = selected["region"].astype(str)
    selected["fold"] = pd.to_numeric(selected["fold"], errors="raise").astype(int)
    scopes = {}
    for scope in ["full_surface_calibrated", "r26_selected_only_calibrated", "test_oracle_calibrated_audit_only"]:
        sub = r27_case[r27_case["selection_scope"].astype(str).eq(scope)].copy()
        if not sub.empty:
            scopes[scope] = sub[["region", "fold", "test_minus_pricefm", "test_minus_current_qdesn", "calibration_rule"]].rename(
                columns={
                    "test_minus_pricefm": f"{scope}_test_minus_pricefm",
                    "test_minus_current_qdesn": f"{scope}_test_minus_current_qdesn",
                    "calibration_rule": f"{scope}_calibration_rule",
                }
            )
    out = selected.copy()
    for sub in scopes.values():
        out = out.merge(sub, on=["region", "fold"], how="left")
    best_gap_cols = [
        "test_minus_pricefm",
        "full_surface_calibrated_test_minus_pricefm",
        "r26_selected_only_calibrated_test_minus_pricefm",
        "test_oracle_calibrated_audit_only_test_minus_pricefm",
    ]
    present = [col for col in best_gap_cols if col in out.columns]
    out["best_observed_stage_r25_r27_test_minus_pricefm"] = out[present].apply(
        lambda row: min(finite_float(x) for x in row if math.isfinite(finite_float(x))),
        axis=1,
    )
    out["r28_queue"] = out["best_observed_stage_r25_r27_test_minus_pricefm"].map(
        lambda gap: "near_gap_horizon_block_readout"
        if gap <= 0.75
        else "moderate_gap_horizon_block_readout"
        if gap <= 1.5
        else "far_gap_horizon_block_readout_diagnostic"
    )
    out["include_in_stage_r29_main_launch"] = True
    out["selection_rule_for_next_launch"] = "validation_AQL_only_within_case"
    out["test_metrics_role_next_launch"] = "audit_only_after_frozen_validation_selection"
    keep = [
        "region",
        "fold",
        "stage_r22b_case_id",
        "horizon_focus",
        "feature_policy",
        "stage_r25_arm",
        "method_id",
        "test_minus_pricefm",
        "test_minus_current_qdesn",
        "best_observed_stage_r25_r27_test_minus_pricefm",
        "r28_queue",
        "include_in_stage_r29_main_launch",
        "current_pricefm_AQL",
        "current_qdesn_AQL",
        "lag_window",
        "depth",
        "units",
        "feature_dim",
        "state_output",
        "alpha",
        "rho",
        "input_scale",
        "tau0",
        "horizon_weight_multiplier",
        "selection_rule_for_next_launch",
        "test_metrics_role_next_launch",
    ]
    return out[[col for col in keep if col in out.columns]].sort_values(["r28_queue", "region", "fold"]).reset_index(drop=True)


def failure_atlas(case_queue: pd.DataFrame, parity: pd.DataFrame) -> pd.DataFrame:
    parity_diag = (
        parity.groupby(["region", "fold"], as_index=False)
        .agg(
            n_information_set_rows=("experiment_id", "size"),
            best_information_set_test_minus_pricefm=("best_calibrated_test_minus_pricefm", "min"),
            information_set_diagnoses=("information_set_diagnosis", lambda x: "; ".join(sorted(set(map(str, x))))),
        )
        if not parity.empty
        else pd.DataFrame(columns=["region", "fold"])
    )
    out = case_queue.merge(parity_diag, on=["region", "fold"], how="left")
    out["primary_failure_mode"] = "static_readout_objective_family_gap"
    out["diagnosis"] = (
        "R25 horizon weighting and R27 calibration/information-set parity did not beat PriceFM; "
        "next evidence should test a real horizon-block readout design matrix."
    )
    out["blocked_actions"] = "registry_mutation;manuscript_update;mcmc_confirmation_without_vb_winner"
    return out


def launch_recommendations(capability: pd.DataFrame, case_queue: pd.DataFrame) -> pd.DataFrame:
    cap = capability.set_index("mechanism")
    supported = (
        "horizon_block_readout_interaction" in cap.index
        and str(cap.loc["horizon_block_readout_interaction", "current_support"]) == "implemented_design_matrix_axis"
        and boolish(cap.loc["horizon_block_readout_interaction", "runner_consumes_it"])
    )
    rows = [
        {
            "recommendation": "stage_r29_prepare_stage_r30_horizon_block_readout_main_launch",
            "allowed": supported,
            "n_target_cases": int(case_queue["include_in_stage_r29_main_launch"].map(boolish).sum()),
            "recommended_arms_per_case": 4,
            "recommended_experiments": int(case_queue["include_in_stage_r29_main_launch"].map(boolish).sum()) * 4,
            "why": (
                "R25/R27 exhausted same-family horizon weighting/calibration without PriceFM wins; "
                "horizon-block readout interactions are now a consumed adapter axis."
            ),
            "scientific_gate_after_run": (
                "Validation-selected winners must beat both current authoritative Q-DESN and cached PriceFM on test, "
                "then pass full-quantile and MCMC confirmation before article or registry mutation."
            ),
        },
        {
            "recommendation": "do_not_launch_new_likelihood_yaml_only",
            "allowed": False,
            "n_target_cases": 0,
            "recommended_arms_per_case": 0,
            "recommended_experiments": 0,
            "why": "The R runner exposes AL/exAL only; YAML-only likelihood labels would be metadata.",
            "scientific_gate_after_run": "not_applicable",
        },
    ]
    return pd.DataFrame(rows)


def gates(
    r26_summary: dict[str, Any],
    r27_summary: dict[str, Any],
    selected: pd.DataFrame,
    next_plan: pd.DataFrame,
    capability: pd.DataFrame,
    recommendations: pd.DataFrame,
    output_dir: Path,
    expected_cases: int,
) -> pd.DataFrame:
    cap = capability.set_index("mechanism")
    rec = recommendations.set_index("recommendation")
    pivot_allowed = (
        not next_plan.empty
        and next_plan["action"].astype(str).eq("if_no_calibrated_beat_both_pivot_to_objective_or_model_family").any()
        and next_plan.loc[
            next_plan["action"].astype(str).eq("if_no_calibrated_beat_both_pivot_to_objective_or_model_family"),
            "allowed_next",
        ].map(boolish).any()
    )
    rows = [
        ("r26_negative_closeout_loaded", r26_summary.get("status") == "completed_negative_no_promotions", "R26 confirms R25 completed with no promotable rows."),
        ("r27_read_only_negative_loaded", r27_summary.get("status") == "completed_read_only_calibration_parity_audit", "R27 calibration/parity audit loaded."),
        ("expected_validation_selected_cases", int(selected[["region", "fold"]].drop_duplicates().shape[0]) == int(expected_cases), "All R25 failed target cases remain visible."),
        ("no_existing_pricefm_wins", int(r26_summary.get("n_rows_beating_pricefm", -1)) == 0 and int(r27_summary.get("n_full_surface_calibrated_pricefm_wins", -1)) == 0, "No existing R25/R27 row beat PriceFM."),
        ("objective_family_pivot_allowed", pivot_allowed, "R27 explicitly allows pivoting to objective/model-family design."),
        ("horizon_block_readout_supported", str(cap.loc["horizon_block_readout_interaction", "current_support"]) == "implemented_design_matrix_axis", "Adapter/readout mechanism is supported by code, not metadata only."),
        ("main_launch_recommendation_allowed", boolish(rec.loc["stage_r29_prepare_stage_r30_horizon_block_readout_main_launch", "allowed"]), "R28 recommends a bounded main-launch prep."),
        ("no_launch_yaml_written_by_r28", not any(output_dir.glob("*.yaml")) and not any(output_dir.glob("*.yml")), "R28 remains read-only and writes no launch YAML."),
        ("registry_manuscript_mcmc_blocked", True, "R28 blocks registry, manuscript, article, and MCMC until a VB winner passes gates."),
    ]
    return pd.DataFrame([{"gate": name, "passed": bool(passed), "detail": detail} for name, passed, detail in rows])


def markdown_table(frame: pd.DataFrame, max_rows: int = 30) -> str:
    if frame.empty:
        return "_No rows._"
    sub = frame.head(max_rows).copy()
    cols = list(sub.columns)
    lines = ["| " + " | ".join(cols) + " |", "| " + " | ".join(["---"] * len(cols)) + " |"]
    for _, row in sub.iterrows():
        vals = []
        for col in cols:
            value = row[col]
            if isinstance(value, float):
                vals.append("{:.6g}".format(value))
            else:
                vals.append(str(value).replace("|", "\\|"))
        lines.append("| " + " | ".join(vals) + " |")
    if len(frame) > len(sub):
        lines.extend(["", f"_Showing {len(sub)} of {len(frame)} rows._"])
    return "\n".join(lines)


def write_report(path: Path, summary: dict[str, Any], capability: pd.DataFrame, case_queue: pd.DataFrame, recommendations: pd.DataFrame, gate_rows: pd.DataFrame) -> None:
    lines = [
        "# PriceFM Stage-R28 Objective/Model-Family Audit",
        "",
        "Stage-R28 is read-only. It diagnoses why the R25/R27 path failed and decides whether a new consumed model-family axis is justified before another expensive launch.",
        "",
        "## Executive Summary",
        "",
        f"- Status: `{summary['status']}`",
        f"- Target cases: `{summary['n_target_cases']}`",
        f"- R25/R27 PriceFM wins: `{summary['existing_pricefm_wins']}`",
        f"- Recommended main-launch experiments: `{summary['recommended_stage_r30_experiments']}`",
        f"- Recommended next action: `{summary['recommended_next_action']}`",
        "",
        "## Capability",
        "",
        markdown_table(capability, max_rows=20),
        "",
        "## Case Queue",
        "",
        markdown_table(case_queue[["region", "fold", "r28_queue", "best_observed_stage_r25_r27_test_minus_pricefm", "horizon_focus"]], max_rows=40),
        "",
        "## Recommendations",
        "",
        markdown_table(recommendations, max_rows=10),
        "",
        "## Gates",
        "",
        markdown_table(gate_rows, max_rows=20),
        "",
        "## Decision",
        "",
        "The optimal next launch is not another plain R25-style capacity grid. The next expensive stage should test horizon-block readout interactions as real design-matrix columns, still using VB AL/exAL for fast screening and keeping test metrics audit-only.",
        "",
    ]
    repo_path(path).write_text("\n".join(lines))


def run(args: argparse.Namespace) -> dict[str, Any]:
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and any(out_dir.iterdir()) and not bool(args.force):
        raise FileExistsError(f"{out_dir} exists; rerun with --force true")
    out_dir.mkdir(parents=True, exist_ok=True)

    r26_dir = Path(args.stage_r26_dir)
    r27_dir = Path(args.stage_r27_dir)
    r25_dir = Path(args.stage_r25_prep_dir)
    r26_summary = read_json_required(r26_dir / "summary.json", "Stage-R26 summary")
    r27_summary = read_json_required(r27_dir / "summary.json", "Stage-R27 summary")
    selected = read_csv_required(r26_dir / R26_SELECTED, "Stage-R26 validation-selected rows")
    metrics = read_csv_required(r26_dir / R26_METRICS, "Stage-R26 metric rows")
    r27_case = read_csv_required(r27_dir / R27_CASE_SELECTION, "Stage-R27 case selection")
    next_plan = read_csv_required(r27_dir / R27_NEXT, "Stage-R27 next-action plan")
    parity = read_csv_required(r27_dir / R27_PARITY, "Stage-R27 information-set parity")
    _ = read_csv_required(r25_dir / R25_MANIFEST, "Stage-R25 launch manifest")

    paths = source_paths(args)
    capability = capability_matrix(paths)
    family = likelihood_family_transfer(metrics)
    case_queue = build_case_queue(selected, r27_case)
    atlas = failure_atlas(case_queue, parity)
    recommendations = launch_recommendations(capability, case_queue)
    gate_rows = gates(
        r26_summary,
        r27_summary,
        selected,
        next_plan,
        capability,
        recommendations,
        out_dir,
        int(args.expected_cases),
    )
    if not gate_rows["passed"].map(boolish).all():
        failed = gate_rows.loc[~gate_rows["passed"].map(boolish), "gate"].tolist()
        raise ValueError(f"Stage-R28 design gates failed: {failed}")

    source = source_manifest(args, paths)
    rec = recommendations.set_index("recommendation")
    allowed = boolish(rec.loc["stage_r29_prepare_stage_r30_horizon_block_readout_main_launch", "allowed"])
    summary = {
        "stage": "pricefm_stage_r28_objective_model_family_audit",
        "status": "completed_main_launch_path_ready" if allowed else "completed_main_launch_blocked",
        "n_target_cases": int(case_queue.shape[0]),
        "existing_pricefm_wins": int(r26_summary.get("n_rows_beating_pricefm", 0)) + int(r27_summary.get("n_full_surface_calibrated_pricefm_wins", 0)),
        "best_r26_test_minus_pricefm": float(r26_summary.get("best_validation_selected_test_minus_pricefm", float("nan"))),
        "best_r27_test_minus_pricefm": float(r27_summary.get("best_any_calibrated_test_minus_pricefm", float("nan"))),
        "recommended_stage_r30_experiments": int(rec.loc["stage_r29_prepare_stage_r30_horizon_block_readout_main_launch", "recommended_experiments"]),
        "writes_launch_yaml": False,
        "launches_models": False,
        "fits_models": False,
        "registry_mutation_authorized": False,
        "manuscript_mutation_authorized": False,
        "mcmc_confirmation_authorized": False,
        "recommended_next_action": "prepare_stage_r29_then_launch_stage_r30_horizon_block_readout_main" if allowed else "stop_until_supported_mechanism_exists",
    }
    outputs = {
        "capability": out_dir / OUT_CAPABILITY,
        "likelihood_family_transfer": out_dir / OUT_FAMILY_TRANSFER,
        "case_target_queue": out_dir / OUT_CASE_QUEUE,
        "failure_atlas": out_dir / OUT_FAILURE_ATLAS,
        "recommendations": out_dir / OUT_RECOMMENDATIONS,
        "gates": out_dir / OUT_GATES,
        "source_manifest": out_dir / OUT_SOURCE,
        "report": out_dir / OUT_REPORT,
        "summary_json": out_dir / "summary.json",
    }
    write_frame(outputs["capability"], capability)
    write_frame(outputs["likelihood_family_transfer"], family)
    write_frame(outputs["case_target_queue"], case_queue)
    write_frame(outputs["failure_atlas"], atlas)
    write_frame(outputs["recommendations"], recommendations)
    write_frame(outputs["gates"], gate_rows)
    write_frame(outputs["source_manifest"], source)
    summary["outputs"] = {key: repo_relative(path) for key, path in outputs.items()}
    write_report(outputs["report"], summary, capability, case_queue, recommendations, gate_rows)
    write_json(outputs["summary_json"], summary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    run(parser().parse_args())


if __name__ == "__main__":
    main()
