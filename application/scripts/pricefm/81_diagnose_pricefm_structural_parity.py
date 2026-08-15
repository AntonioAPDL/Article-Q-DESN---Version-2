#!/usr/bin/env python3
"""Diagnose PriceFM/Q-DESN structural parity before any new search.

Stage T is diagnostic-only.  It consumes the frozen Stage-M decision surface
and the Stage-R/S diagnostic closeouts, ranks likely structural failure modes,
and writes a mechanism checklist.  It never fits models, mutates Stage-M, or
writes launch grids.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, repo_path, sha256_file, write_json


DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_t_structural_diagnostics_20260629"
)
DEFAULT_STAGE_M_SURFACE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624/"
    "current_decision_surface_table.csv"
)
DEFAULT_STAGE_R_SUMMARY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r_selection_diagnostics_20260627/summary.json"
)
DEFAULT_STAGE_R_SCORECARD = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r_selection_diagnostics_20260627/stage_r_region_fold_scorecard.csv"
)
DEFAULT_STAGE_R_FAILURES = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r_selection_diagnostics_20260627/stage_r_failure_mode_assignments.csv"
)
DEFAULT_STAGE_R_INFOSET = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r_selection_diagnostics_20260627/stage_r_information_set_parity.csv"
)
DEFAULT_STAGE_R_TRANSFER = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r_selection_diagnostics_20260627/stage_r_selection_transfer_by_source.csv"
)
DEFAULT_STAGE_R_HORIZON = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r_selection_diagnostics_20260627/stage_r_horizon_block_diagnostics.csv"
)
DEFAULT_STAGE_S_SUMMARY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_s_targeted_rescue_closeout_20260629/summary.json"
)
DEFAULT_STAGE_S_SELECTION = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_s_targeted_rescue_closeout_20260629/stage_s_selection_summary_by_family.csv"
)
DEFAULT_STAGE_S_VALIDATION = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_s_targeted_rescue_closeout_20260629/stage_s_validation_selected_candidates.csv"
)
DEFAULT_STAGE_S_ORACLE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_s_targeted_rescue_closeout_20260629/stage_s_test_oracle_audit.csv"
)
DEFAULT_STAGE_S_VARIANTS = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_s_targeted_rescue_closeout_20260629/stage_s_variant_summary_by_factor.csv"
)
DEFAULT_PAPER_TEXT = (
    "application/data_local/pricefm/external/papers/"
    "pricefm_arxiv_2508.04875v4_20260508.txt"
)
DEFAULT_PIPELINE_REPORT = "PRICEFM_DATA_PIPELINE_REPORT.md"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-m-surface-csv", default=DEFAULT_STAGE_M_SURFACE)
    p.add_argument("--stage-r-summary-json", default=DEFAULT_STAGE_R_SUMMARY)
    p.add_argument("--stage-r-scorecard-csv", default=DEFAULT_STAGE_R_SCORECARD)
    p.add_argument("--stage-r-failures-csv", default=DEFAULT_STAGE_R_FAILURES)
    p.add_argument("--stage-r-infoset-csv", default=DEFAULT_STAGE_R_INFOSET)
    p.add_argument("--stage-r-transfer-csv", default=DEFAULT_STAGE_R_TRANSFER)
    p.add_argument("--stage-r-horizon-csv", default=DEFAULT_STAGE_R_HORIZON)
    p.add_argument("--stage-s-summary-json", default=DEFAULT_STAGE_S_SUMMARY)
    p.add_argument("--stage-s-selection-csv", default=DEFAULT_STAGE_S_SELECTION)
    p.add_argument("--stage-s-validation-csv", default=DEFAULT_STAGE_S_VALIDATION)
    p.add_argument("--stage-s-oracle-csv", default=DEFAULT_STAGE_S_ORACLE)
    p.add_argument("--stage-s-variants-csv", default=DEFAULT_STAGE_S_VARIANTS)
    p.add_argument("--paper-text", default=DEFAULT_PAPER_TEXT)
    p.add_argument("--pipeline-report", default=DEFAULT_PIPELINE_REPORT)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--expected-region-folds", type=int, default=42)
    p.add_argument("--force", type=parse_bool, default=True)
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def read_csv_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required CSV: {}".format(label, path))
    return pd.read_csv(path)


def read_json_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required JSON: {}".format(label, path))
    with open(path, "r") as f:
        return json.load(f)


def read_text_if_present(path):
    path = repo_path(path)
    if not path.exists():
        return ""
    with open(path, "r", errors="ignore") as f:
        return f.read()


def bool_value(value):
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in ("true", "1", "yes", "y")


def require_columns(frame, columns, label):
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError("{} missing required columns: {}".format(label, missing))


def numeric(frame, col, label=None, required=False):
    if col not in frame.columns:
        if required:
            raise ValueError("{} missing required numeric column {}".format(label, col))
        return pd.Series([float("nan")] * len(frame), index=frame.index)
    vals = pd.to_numeric(frame[col], errors="coerce")
    if required and vals.isna().any():
        raise ValueError("{} has non-finite {} values".format(label, col))
    return vals


def normalize_keys(frame, label, unique=False):
    require_columns(frame, ["region", "fold"], label)
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    if unique and out.duplicated(["region", "fold"]).any():
        dup = (
            out[out.duplicated(["region", "fold"], keep=False)][["region", "fold"]]
            .drop_duplicates()
            .sort_values(["region", "fold"])
            .to_dict("records")
        )
        raise ValueError("{} has duplicate region/fold keys: {}".format(label, dup))
    return out


def _first_json_list_value(value, label):
    if isinstance(value, (list, tuple)):
        vals = list(value)
    else:
        text = str(value)
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ValueError("{} has non-JSON list value: {}".format(label, value)) from exc
        vals = parsed if isinstance(parsed, list) else [parsed]
    if not vals:
        raise ValueError("{} has empty list value".format(label))
    return vals[0]


def normalize_region_fold_columns(frame, label, unique=False):
    """Normalize scalar `region`/`fold` or list-valued `regions`/`folds` keys."""
    if {"region", "fold"}.issubset(frame.columns):
        return normalize_keys(frame, label, unique=unique)
    if {"regions", "folds"}.issubset(frame.columns):
        out = frame.copy()
        out["region"] = [
            str(_first_json_list_value(value, "{} regions".format(label)))
            for value in out["regions"]
        ]
        out["fold"] = [
            int(_first_json_list_value(value, "{} folds".format(label)))
            for value in out["folds"]
        ]
        return normalize_keys(out, label, unique=unique)
    require_columns(frame, ["region", "fold"], label)
    return frame


def git_value(args):
    try:
        proc = subprocess.run(
            args,
            cwd=str(repo_path(".")),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            check=False,
        )
        if proc.returncode == 0:
            return proc.stdout.strip()
    except OSError:
        pass
    return ""


def repo_state():
    return {
        "repo_branch": git_value(["git", "branch", "--show-current"]),
        "repo_head": git_value(["git", "rev-parse", "--short", "HEAD"]),
        "repo_dirty": bool(git_value(["git", "status", "--short"])),
    }


def input_specs(args):
    return [
        ("stage_m_surface", args.stage_m_surface_csv, "csv", "frozen Stage-M decision surface"),
        ("stage_r_summary", args.stage_r_summary_json, "json", "Stage-R health and diagnostic-only status"),
        ("stage_r_scorecard", args.stage_r_scorecard_csv, "csv", "Stage-R row-level scorecard"),
        ("stage_r_failures", args.stage_r_failures_csv, "csv", "Stage-R failure-mode assignments"),
        ("stage_r_infoset", args.stage_r_infoset_csv, "csv", "Stage-R information-set parity"),
        ("stage_r_transfer", args.stage_r_transfer_csv, "csv", "Stage-R validation/test transfer"),
        ("stage_r_horizon", args.stage_r_horizon_csv, "csv", "Stage-R horizon diagnostics"),
        ("stage_s_summary", args.stage_s_summary_json, "json", "Stage-S closeout health"),
        ("stage_s_selection", args.stage_s_selection_csv, "csv", "Stage-S validation-selected family summary"),
        ("stage_s_validation", args.stage_s_validation_csv, "csv", "Stage-S validation-selected candidates"),
        ("stage_s_oracle", args.stage_s_oracle_csv, "csv", "Stage-S test-oracle audit"),
        ("stage_s_variants", args.stage_s_variants_csv, "csv", "Stage-S variant summary"),
        ("pricefm_paper_text", args.paper_text, "txt", "local PriceFM paper text"),
        ("pricefm_pipeline_report", args.pipeline_report, "md", "local PriceFM pipeline report"),
    ]


def build_input_manifest(args):
    rows = []
    for input_id, path, kind, role in input_specs(args):
        full = repo_path(path)
        if not full.exists() or full.stat().st_size == 0:
            raise FileNotFoundError("{} missing required input: {}".format(input_id, full))
        row = {
            "input_id": input_id,
            "kind": kind,
            "role": role,
            "path": config_path_value(full),
            "sha256": sha256_file(full),
            "size_bytes": int(full.stat().st_size),
        }
        if kind == "csv":
            frame = pd.read_csv(full)
            row["n_rows"] = int(frame.shape[0])
            row["n_columns"] = int(frame.shape[1])
        else:
            row["n_rows"] = ""
            row["n_columns"] = ""
        rows.append(row)
    return pd.DataFrame(rows)


def validate_stage_s_contract(summary, validation):
    if not bool_value(summary.get("run_clean", False)):
        raise ValueError("Stage-S summary is not clean.")
    if bool_value(summary.get("stage_m_surface_changed", True)):
        raise ValueError("Stage-S summary says Stage-M surface changed.")
    if bool_value(summary.get("promotion_recommended", True)):
        raise ValueError("Stage-S promoted a candidate; expected negative evidence.")
    if int(summary.get("validation_selected_beats_stage_m", -1)) != 0:
        raise ValueError("Stage-S validation-selected candidates beat Stage-M unexpectedly.")
    if int(summary.get("validation_selected_beats_pricefm", -1)) != 0:
        raise ValueError("Stage-S validation-selected candidates beat PriceFM unexpectedly.")
    if "selection_is_validation_only" in validation.columns:
        vals = validation["selection_is_validation_only"].astype(str).str.lower()
        if not vals.isin(["true", "1", "yes"]).all():
            raise ValueError("Stage-S validation candidates must be validation-only.")
    if "test_metrics_role" in validation.columns:
        vals = validation["test_metrics_role"].astype(str)
        if not vals.eq("audit_only").all():
            raise ValueError("Stage-S test metrics must be audit-only.")


def validate_inputs(data, expected_region_folds):
    surface = normalize_keys(data["surface"], "Stage-M surface", unique=True)
    require_columns(
        surface,
        [
            "local_AQL", "pricefm_AQL", "delta_abs", "delta_rel",
            "information_set", "feature_policy", "spatial_information_set",
        ],
        "Stage-M surface",
    )
    for col in ["local_AQL", "pricefm_AQL", "delta_abs", "delta_rel"]:
        numeric(surface, col, "Stage-M surface", required=True)
    if surface.shape[0] != int(expected_region_folds):
        raise ValueError(
            "Stage-M surface must have {} rows; got {}".format(
                int(expected_region_folds), surface.shape[0]
            )
        )

    r_summary = data["stage_r_summary"]
    if not bool_value(r_summary.get("diagnostic_only", False)):
        raise ValueError("Stage-R summary must be diagnostic_only.")
    if bool_value(r_summary.get("stage_m_surface_changed", True)):
        raise ValueError("Stage-R summary says Stage-M surface changed.")
    if int(r_summary.get("stage_m_rows", expected_region_folds)) != int(expected_region_folds):
        raise ValueError("Stage-R summary row count does not match expected region/folds.")

    failures = normalize_keys(data["stage_r_failures"], "Stage-R failures", unique=True)
    require_columns(
        failures,
        ["primary_failure_mode", "recommended_action", "current_delta_AQL"],
        "Stage-R failures",
    )
    numeric(failures, "current_delta_AQL", "Stage-R failures", required=True)

    for key, label in [
        ("stage_r_scorecard", "Stage-R scorecard"),
        ("stage_r_infoset", "Stage-R information-set parity"),
        ("stage_r_transfer", "Stage-R transfer"),
        ("stage_r_horizon", "Stage-R horizon"),
        ("stage_s_selection", "Stage-S selection summary"),
        ("stage_s_validation", "Stage-S validation candidates"),
        ("stage_s_oracle", "Stage-S oracle candidates"),
        ("stage_s_variants", "Stage-S variants"),
    ]:
        if data[key].empty:
            raise ValueError("{} is empty.".format(label))

    validate_stage_s_contract(data["stage_s_summary"], data["stage_s_validation"])


def load_inputs(args):
    data = {
        "surface": read_csv_required(args.stage_m_surface_csv, "Stage-M surface"),
        "stage_r_summary": read_json_required(args.stage_r_summary_json, "Stage-R summary"),
        "stage_r_scorecard": read_csv_required(args.stage_r_scorecard_csv, "Stage-R scorecard"),
        "stage_r_failures": read_csv_required(args.stage_r_failures_csv, "Stage-R failures"),
        "stage_r_infoset": read_csv_required(args.stage_r_infoset_csv, "Stage-R information-set parity"),
        "stage_r_transfer": read_csv_required(args.stage_r_transfer_csv, "Stage-R transfer"),
        "stage_r_horizon": read_csv_required(args.stage_r_horizon_csv, "Stage-R horizon"),
        "stage_s_summary": read_json_required(args.stage_s_summary_json, "Stage-S summary"),
        "stage_s_selection": read_csv_required(args.stage_s_selection_csv, "Stage-S selection summary"),
        "stage_s_validation": read_csv_required(args.stage_s_validation_csv, "Stage-S validation candidates"),
        "stage_s_oracle": read_csv_required(args.stage_s_oracle_csv, "Stage-S oracle candidates"),
        "stage_s_variants": read_csv_required(args.stage_s_variants_csv, "Stage-S variants"),
        "paper_text": read_text_if_present(args.paper_text),
        "pipeline_report": read_text_if_present(args.pipeline_report),
    }
    validate_inputs(data, args.expected_region_folds)
    return data


def structural_signal_from_row(row, stage_s_target_keys):
    key = (str(row["region"]), int(row["fold"]))
    delta = float(row["delta_abs"])
    info = str(row.get("information_set", ""))
    failure = str(row.get("primary_failure_mode", ""))
    if delta <= 0.0:
        return "current_stage_m_win"
    if key in stage_s_target_keys:
        return "stage_s_falsified_local_rescue_family"
    if failure == "pricefm_far_ahead":
        return "large_gap_needs_model_data_mismatch_audit"
    if failure == "selection_instability":
        return "validation_transfer_failure"
    if info == "target_only":
        return "input_parity_gap_unresolved"
    return "graph_input_row_still_underperforming"


def next_gate_for_signal(signal):
    mapping = {
        "current_stage_m_win": "keep_stage_m",
        "stage_s_falsified_local_rescue_family": "structural_diagnostics_before_search",
        "large_gap_needs_model_data_mismatch_audit": "pricefm_parity_and_target_transform_audit",
        "validation_transfer_failure": "multi_validation_or_horizon_selection_contract",
        "input_parity_gap_unresolved": "pricefm_input_parity_audit",
        "graph_input_row_still_underperforming": "horizon_and_model_class_audit",
    }
    return mapping.get(signal, "manual_review")


def build_structural_scorecard(data):
    surface = normalize_keys(data["surface"], "Stage-M surface", unique=True)
    failures = normalize_keys(data["stage_r_failures"], "Stage-R failures", unique=True)
    validation = normalize_region_fold_columns(data["stage_s_validation"], "Stage-S validation candidates")
    stage_s_target_keys = set(zip(validation["region"].astype(str), validation["fold"].astype(int)))

    work = surface.merge(
        failures,
        on=["region", "fold"],
        how="left",
        validate="one_to_one",
        suffixes=("", "_stage_r"),
    )
    work["stage_s_targeted"] = [
        (str(r), int(f)) in stage_s_target_keys
        for r, f in zip(work["region"], work["fold"])
    ]
    work["structural_signal"] = [
        structural_signal_from_row(row, stage_s_target_keys)
        for _, row in work.iterrows()
    ]
    work["next_gate"] = [next_gate_for_signal(x) for x in work["structural_signal"]]
    keep = [
        "region", "fold", "local_AQL", "pricefm_AQL", "delta_abs", "delta_rel",
        "information_set", "feature_policy", "spatial_information_set", "graph_degree",
        "primary_failure_mode", "recommended_action", "stage_s_targeted",
        "structural_signal", "next_gate", "experiment_id", "best_local_method",
    ]
    keep = [col for col in keep if col in work.columns]
    return work[keep].sort_values(["delta_abs", "region", "fold"], ascending=[False, True, True])


def build_surface_health(data, args, input_manifest):
    surface = normalize_keys(data["surface"], "Stage-M surface", unique=True)
    delta = numeric(surface, "delta_abs", "Stage-M surface", required=True)
    info = surface["information_set"].astype(str)
    stage_s = data["stage_s_summary"]
    rows = [
        {
            "check": "stage_m_row_count",
            "value": int(surface.shape[0]),
            "status": "pass" if surface.shape[0] == int(args.expected_region_folds) else "fail",
        },
        {
            "check": "stage_m_surface_sha256",
            "value": sha256_file(repo_path(args.stage_m_surface_csv)),
            "status": "info",
        },
        {
            "check": "stage_m_qdesn_wins",
            "value": int((delta < 0.0).sum()),
            "status": "info",
        },
        {
            "check": "stage_m_pricefm_wins",
            "value": int((delta >= 0.0).sum()),
            "status": "info",
        },
        {
            "check": "stage_m_mean_delta_aql",
            "value": float(delta.mean()),
            "status": "info",
        },
        {
            "check": "stage_m_median_delta_aql",
            "value": float(delta.median()),
            "status": "info",
        },
        {
            "check": "graph_input_rows",
            "value": int(info.eq("pricefm_graph_inputs").sum()),
            "status": "info",
        },
        {
            "check": "target_only_rows",
            "value": int(info.eq("target_only").sum()),
            "status": "info",
        },
        {
            "check": "stage_s_run_clean",
            "value": bool_value(stage_s.get("run_clean", False)),
            "status": "pass" if bool_value(stage_s.get("run_clean", False)) else "fail",
        },
        {
            "check": "stage_s_promotions",
            "value": bool_value(stage_s.get("promotion_recommended", True)),
            "status": "pass" if not bool_value(stage_s.get("promotion_recommended", True)) else "fail",
        },
        {
            "check": "stage_s_binary_artifacts",
            "value": int(stage_s.get("binary_artifacts", -1)),
            "status": "pass" if int(stage_s.get("binary_artifacts", -1)) == 0 else "fail",
        },
        {
            "check": "input_manifest_rows",
            "value": int(input_manifest.shape[0]),
            "status": "pass",
        },
    ]
    return pd.DataFrame(rows)


def build_horizon_selection_risk(data):
    horizon = data["stage_r_horizon"].copy()
    require_columns(horizon, ["region", "fold", "horizon_band"], "Stage-R horizon")
    for col in ["validation_selected_AQL", "test_oracle_AQL", "oracle_minus_validation_AQL"]:
        if col in horizon.columns:
            horizon[col] = pd.to_numeric(horizon[col], errors="coerce")
    rows = []
    for (region, fold), sub in horizon.groupby(["region", "fold"], dropna=False):
        late = sub[sub["horizon_band"].isin(["middle", "middle_late", "late"])]
        early = sub[sub["horizon_band"].eq("early")]
        val_mean = float(sub["validation_selected_AQL"].mean()) if "validation_selected_AQL" in sub.columns else float("nan")
        oracle_mean = float(sub["test_oracle_AQL"].mean()) if "test_oracle_AQL" in sub.columns else float("nan")
        late_mean = float(late["validation_selected_AQL"].mean()) if not late.empty and "validation_selected_AQL" in late.columns else float("nan")
        early_mean = float(early["validation_selected_AQL"].mean()) if not early.empty and "validation_selected_AQL" in early.columns else float("nan")
        rows.append({
            "region": str(region),
            "fold": int(fold),
            "n_horizon_rows": int(sub.shape[0]),
            "validation_selected_AQL_mean": val_mean,
            "test_oracle_AQL_mean": oracle_mean,
            "oracle_minus_validation_AQL_mean": oracle_mean - val_mean if math.isfinite(oracle_mean) and math.isfinite(val_mean) else float("nan"),
            "late_minus_early_validation_AQL": late_mean - early_mean if math.isfinite(late_mean) and math.isfinite(early_mean) else float("nan"),
            "horizon_selection_risk": "high" if math.isfinite(oracle_mean - val_mean) and oracle_mean < val_mean - 0.25 else "audit",
        })
    return pd.DataFrame(rows).sort_values(["horizon_selection_risk", "region", "fold"])


def paper_contract_signals(data):
    text = (data["paper_text"] + "\n" + data["pipeline_report"]).lower()
    checks = [
        ("paper_uses_price_load_solar_wind", ["price", "load", "solar", "wind"]),
        ("paper_uses_day_ahead_96_horizon", ["96", "day-ahead"]),
        ("paper_uses_graph_mask_or_topology", ["graph", "mask"]),
        ("paper_uses_rolling_evaluation", ["rolling", "fold"]),
        ("pipeline_records_generation_optional", ["generation", "optional"]),
        ("pipeline_records_robust_scaler", ["robustscaler"]),
    ]
    rows = []
    for signal, needles in checks:
        present = all(needle in text for needle in needles)
        rows.append({
            "signal": signal,
            "present_in_local_docs": bool(present),
            "role": "input_contract" if "paper" in signal or "pipeline" in signal else "audit",
        })
    return pd.DataFrame(rows)


def mechanism_rows(data):
    s = data["stage_s_summary"]
    best_oracle = float(s.get("best_test_oracle_vs_pricefm", float("nan")))
    median_vs_pricefm = float(s.get("median_validation_selected_vs_pricefm", float("nan")))
    return pd.DataFrame([
        {
            "rank": 1,
            "mechanism": "PriceFM information-set parity audit",
            "decision": "implement_next_diagnostic",
            "justification": "Stage-S graph-parity variants failed; verify exact covariates, scaling, graph scope, and lead semantics before more fitting.",
            "preserves_stage_m": True,
            "writes_launch_grid": False,
            "requires_model_fit": False,
            "success_gate": "complete row-level parity matrix with no unknown feature/window/scaling fields",
        },
        {
            "rank": 2,
            "mechanism": "Horizon-aware or multi-validation selection contract",
            "decision": "design_after_parity_audit",
            "justification": "Stage-R/S show weak validation/test transfer; new selection rules need a contract before any launch.",
            "preserves_stage_m": True,
            "writes_launch_grid": False,
            "requires_model_fit": False,
            "success_gate": "validation-only rule improves transfer on historical candidate rows without using test labels",
        },
        {
            "rank": 3,
            "mechanism": "Target scaling and transform audit",
            "decision": "implement_as_part_of_parity_audit",
            "justification": "Apples-to-apples comparison requires matching raw-unit scoring, RobustScaler use, and any target transforms.",
            "preserves_stage_m": True,
            "writes_launch_grid": False,
            "requires_model_fit": False,
            "success_gate": "documented transform/scoring parity for all 42 Stage-M rows",
        },
        {
            "rank": 4,
            "mechanism": "Calendar or market-feature adapter",
            "decision": "conditional",
            "justification": "May help if diagnostics show missing deterministic structure, but should not be added without forecast-time availability.",
            "preserves_stage_m": True,
            "writes_launch_grid": False,
            "requires_model_fit": False,
            "success_gate": "feature is exogenous at forecast origin and appears in a tracked manifest",
        },
        {
            "rank": 5,
            "mechanism": "Spatial or multi-output Q-DESN",
            "decision": "research_extension",
            "justification": "PriceFM is joint multi-region; this is scientifically plausible but larger than a screening patch.",
            "preserves_stage_m": True,
            "writes_launch_grid": False,
            "requires_model_fit": False,
            "success_gate": "mathematical contract and small synthetic tests before PriceFM runs",
        },
        {
            "rank": 6,
            "mechanism": "More Stage-S graph-parity/local capacity sweep",
            "decision": "reject_now",
            "justification": "Stage-S completed cleanly but selected 0 winners; best test-oracle row remained {:.3f} AQL worse than PriceFM.".format(best_oracle),
            "preserves_stage_m": True,
            "writes_launch_grid": False,
            "requires_model_fit": False,
            "success_gate": "not applicable",
        },
        {
            "rank": 7,
            "mechanism": "Seven-quantile confirmation of Stage-S candidates",
            "decision": "reject_now",
            "justification": "No median candidate earned confirmation; validation-selected median gap was {:.3f} AQL worse than PriceFM.".format(median_vs_pricefm),
            "preserves_stage_m": True,
            "writes_launch_grid": False,
            "requires_model_fit": False,
            "success_gate": "not applicable",
        },
    ])


def markdown_table(frame, columns=None, max_rows=None):
    if columns is not None:
        frame = frame[columns]
    if max_rows is not None:
        frame = frame.head(max_rows)
    if frame.empty:
        return "_No rows._\n"
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        vals = []
        for col in cols:
            val = row[col]
            if isinstance(val, float):
                vals.append("{:.4g}".format(val))
            else:
                vals.append(str(val).replace("|", "\\|"))
        lines.append("| " + " | ".join(vals) + " |")
    return "\n".join(lines) + "\n"


def write_report(out_dir, summary, surface_health, infoset, transfer, scorecard, mechanisms):
    report = out_dir / "stage_t_structural_diagnostics_report.md"
    unresolved = scorecard[scorecard["delta_abs"] > 0.0].copy()
    with open(report, "w") as f:
        f.write("# PriceFM Stage-T Structural Diagnostics\n\n")
        f.write("Stage T is diagnostic-only. It does not fit models, write launch grids, ")
        f.write("or mutate the Stage-M article decision surface.\n\n")
        f.write("## Summary\n\n")
        for key in [
            "stage_m_rows", "stage_m_qdesn_wins", "stage_m_pricefm_wins",
            "stage_s_run_clean", "stage_s_promotion_recommended",
            "recommended_next_stage",
        ]:
            f.write("- {}: `{}`\n".format(key, summary.get(key)))
        f.write("\n## Surface Health\n\n")
        f.write(markdown_table(surface_health, max_rows=20))
        f.write("\n## Information-Set Parity\n\n")
        f.write(markdown_table(infoset))
        f.write("\n## Selection Transfer\n\n")
        cols = [c for c in [
            "source_label", "n_rows", "n_region_folds", "test_win_rate",
            "pricefm_win_rate", "disagree_rate", "mean_test_delta_vs_pricefm",
            "mean_spearman_val_test_rank",
        ] if c in transfer.columns]
        f.write(markdown_table(transfer, columns=cols))
        f.write("\n## Largest Unresolved Rows\n\n")
        cols = [c for c in [
            "region", "fold", "delta_abs", "information_set",
            "primary_failure_mode", "stage_s_targeted", "structural_signal", "next_gate",
        ] if c in unresolved.columns]
        f.write(markdown_table(unresolved.sort_values("delta_abs", ascending=False), columns=cols, max_rows=17))
        f.write("\n## Mechanism Ranking\n\n")
        f.write(markdown_table(mechanisms[["rank", "mechanism", "decision", "success_gate"]]))
        f.write("\n## Decision\n\n")
        f.write("Do not launch another Stage-S-style graph-parity or local-capacity sweep. ")
        f.write("The next stage should implement an information-set/transform/horizon ")
        f.write("parity audit before any new model-fitting grid.\n")
    return report


def summarize(args):
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and not bool(args.force):
        raise FileExistsError("{} already exists; rerun with --force true".format(out_dir))
    out_dir.mkdir(parents=True, exist_ok=True)

    data = load_inputs(args)
    input_manifest = build_input_manifest(args)
    surface_health = build_surface_health(data, args, input_manifest)
    structural_scorecard = build_structural_scorecard(data)
    horizon_risk = build_horizon_selection_risk(data)
    mechanisms = mechanism_rows(data)
    paper_signals = paper_contract_signals(data)

    infoset = data["stage_r_infoset"].copy()
    transfer = data["stage_r_transfer"].copy()
    stage_s_selection = data["stage_s_selection"].copy()
    stage_s_variants = data["stage_s_variants"].copy()

    input_manifest.to_csv(out_dir / "stage_t_input_manifest.csv", index=False)
    surface_health.to_csv(out_dir / "stage_t_surface_health.csv", index=False)
    infoset.to_csv(out_dir / "stage_t_information_set_parity.csv", index=False)
    transfer.to_csv(out_dir / "stage_t_selection_transfer.csv", index=False)
    structural_scorecard.to_csv(out_dir / "stage_t_structural_scorecard.csv", index=False)
    horizon_risk.to_csv(out_dir / "stage_t_horizon_selection_risk.csv", index=False)
    mechanisms.to_csv(out_dir / "stage_t_mechanism_ranking.csv", index=False)
    paper_signals.to_csv(out_dir / "stage_t_paper_contract_signals.csv", index=False)
    stage_s_selection.to_csv(out_dir / "stage_t_stage_s_selection_summary.csv", index=False)
    stage_s_variants.to_csv(out_dir / "stage_t_stage_s_variant_summary.csv", index=False)

    delta = pd.to_numeric(data["surface"]["delta_abs"], errors="coerce")
    s_summary = data["stage_s_summary"]
    summary = {
        **repo_state(),
        "status": "completed",
        "diagnostic_only": True,
        "writes_launch_configs": False,
        "fits_models": False,
        "stage_m_rows": int(data["surface"].shape[0]),
        "stage_m_surface_csv": config_path_value(args.stage_m_surface_csv),
        "stage_m_surface_sha256": sha256_file(repo_path(args.stage_m_surface_csv)),
        "stage_m_qdesn_wins": int((delta < 0.0).sum()),
        "stage_m_pricefm_wins": int((delta >= 0.0).sum()),
        "stage_m_mean_delta_aql": float(delta.mean()),
        "stage_m_median_delta_aql": float(delta.median()),
        "stage_s_run_clean": bool_value(s_summary.get("run_clean", False)),
        "stage_s_promotion_recommended": bool_value(s_summary.get("promotion_recommended", True)),
        "stage_s_validation_selected_beats_pricefm": int(s_summary.get("validation_selected_beats_pricefm", -1)),
        "stage_s_test_oracle_beats_pricefm": int(s_summary.get("test_oracle_beats_pricefm", -1)),
        "stage_s_best_test_oracle_vs_pricefm": float(s_summary.get("best_test_oracle_vs_pricefm", float("nan"))),
        "n_structural_scorecard_rows": int(structural_scorecard.shape[0]),
        "n_unresolved_rows": int((structural_scorecard["delta_abs"] > 0.0).sum()),
        "n_stage_s_targeted_rows": int(structural_scorecard["stage_s_targeted"].sum()),
        "recommended_next_stage": "pricefm_information_set_transform_horizon_parity_audit",
        "output_dir": config_path_value(out_dir),
    }
    report = write_report(
        out_dir, summary, surface_health, infoset, transfer, structural_scorecard, mechanisms
    )
    summary["report"] = config_path_value(report)
    write_json(out_dir / "summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main(argv=None):
    args = parser().parse_args(argv)
    summarize(args)


if __name__ == "__main__":
    main()
