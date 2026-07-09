#!/usr/bin/env python3
"""Diagnose PriceFM Q-DESN validation/test transfer before new searches.

Stage R is diagnostic-only.  It consumes the existing Stage-M/N/O/P/Q
artifacts, assigns region/fold failure modes, and writes next-action
recommendations.  It never fits models, mutates the Stage-M surface, or writes
launch grids.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess

import pandas as pd

from pricefm_common import parse_bool, repo_path, sha256_file, write_json


DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r_selection_diagnostics_20260627"
)
DEFAULT_STAGE_M_SURFACE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624/"
    "current_decision_surface_table.csv"
)
DEFAULT_STAGE_M_CURRENT_VT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_validation_test_alignment_20260624/"
    "current_median_validation_test.csv"
)
DEFAULT_STAGE_M_ALIGNMENT_ROWS = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_validation_test_alignment_20260624/"
    "diagnostic_validation_test_rows.csv"
)
DEFAULT_STAGE_M_SPLIT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_split_diagnostics_20260624/"
    "split_response_contrasts.csv"
)
DEFAULT_STAGE_N_SELECTED = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_n_underperformance_closeout_20260625/"
    "validation_selected_closeout.csv"
)
DEFAULT_STAGE_N_INSTABILITY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_n_underperformance_closeout_20260625/"
    "selection_instability_audit.csv"
)
DEFAULT_STAGE_N_HORIZON = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_n_underperformance_closeout_20260625/"
    "horizon_gap_summary.csv"
)
DEFAULT_STAGE_O_RULE_AUDIT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_o_selection_promotion_hardening_20260626/"
    "stage_o_selection_rule_audit.csv"
)
DEFAULT_STAGE_O_RULE_SELECTED = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_o_selection_promotion_hardening_20260626/"
    "stage_o_selection_rule_selected_rows.csv"
)
DEFAULT_STAGE_P_FLAGS = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_vs_stage_p_promotions_20260626/"
    "selected_competitiveness_flags.csv"
)
DEFAULT_STAGE_Q_SUMMARY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_q_nearmiss_refinement_closeout_20260626/"
    "summary.json"
)
DEFAULT_STAGE_Q_TRANSFER = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_q_nearmiss_refinement_closeout_20260626/"
    "stage_q_selection_transfer_diagnostics.csv"
)
DEFAULT_STAGE_Q_VALIDATION = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_q_nearmiss_refinement_closeout_20260626/"
    "stage_q_target_best_by_validation.csv"
)
DEFAULT_STAGE_Q_ORACLE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_q_nearmiss_refinement_closeout_20260626/"
    "stage_q_target_best_by_test_audit.csv"
)
DEFAULT_STAGE_Q_HORIZON = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_q_nearmiss_refinement_closeout_20260626/"
    "stage_q_selected_horizon_group_diagnostics.csv"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-m-surface-csv", default=DEFAULT_STAGE_M_SURFACE)
    p.add_argument("--stage-m-current-vt-csv", default=DEFAULT_STAGE_M_CURRENT_VT)
    p.add_argument("--stage-m-alignment-rows-csv", default=DEFAULT_STAGE_M_ALIGNMENT_ROWS)
    p.add_argument("--stage-m-split-csv", default=DEFAULT_STAGE_M_SPLIT)
    p.add_argument("--stage-n-selected-csv", default=DEFAULT_STAGE_N_SELECTED)
    p.add_argument("--stage-n-instability-csv", default=DEFAULT_STAGE_N_INSTABILITY)
    p.add_argument("--stage-n-horizon-csv", default=DEFAULT_STAGE_N_HORIZON)
    p.add_argument("--stage-o-rule-audit-csv", default=DEFAULT_STAGE_O_RULE_AUDIT)
    p.add_argument("--stage-o-rule-selected-csv", default=DEFAULT_STAGE_O_RULE_SELECTED)
    p.add_argument("--stage-p-flags-csv", default=DEFAULT_STAGE_P_FLAGS)
    p.add_argument("--stage-q-summary-json", default=DEFAULT_STAGE_Q_SUMMARY)
    p.add_argument("--stage-q-transfer-csv", default=DEFAULT_STAGE_Q_TRANSFER)
    p.add_argument("--stage-q-validation-csv", default=DEFAULT_STAGE_Q_VALIDATION)
    p.add_argument("--stage-q-oracle-csv", default=DEFAULT_STAGE_Q_ORACLE)
    p.add_argument("--stage-q-horizon-csv", default=DEFAULT_STAGE_Q_HORIZON)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
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


def finite_check(frame, cols, label):
    for col in cols:
        vals = numeric(frame, col, label, required=True)
        if vals.isna().any():
            raise ValueError("{} has non-finite {} values".format(label, col))


def bool_value(value):
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    return text in ("true", "1", "yes", "y")


def bool_series(frame, col, fallback):
    if col not in frame.columns:
        return fallback.astype(bool)
    text = frame[col].astype(str).str.lower()
    true = text.isin(["true", "1", "yes", "y"])
    false = text.isin(["false", "0", "no", "n"])
    return true.where(~false, False).astype(bool)


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


def input_specs(args):
    return [
        ("stage_m_surface", args.stage_m_surface_csv, "csv", "current Stage-M decision surface"),
        ("stage_m_current_vt", args.stage_m_current_vt_csv, "csv", "current validation/test gaps"),
        ("stage_m_alignment_rows", args.stage_m_alignment_rows_csv, "csv", "Stage J/K/L validation/test rows"),
        ("stage_m_split", args.stage_m_split_csv, "csv", "split-shift diagnostics"),
        ("stage_n_selected", args.stage_n_selected_csv, "csv", "Stage-N validation-selected rows"),
        ("stage_n_instability", args.stage_n_instability_csv, "csv", "Stage-N selection instability"),
        ("stage_n_horizon", args.stage_n_horizon_csv, "csv", "Stage-N horizon-block diagnostics"),
        ("stage_o_rule_audit", args.stage_o_rule_audit_csv, "csv", "Stage-O selection-rule audit"),
        ("stage_o_rule_selected", args.stage_o_rule_selected_csv, "csv", "Stage-O selected rows by rule"),
        ("stage_p_flags", args.stage_p_flags_csv, "csv", "Stage-P seven-quantile flags"),
        ("stage_q_summary", args.stage_q_summary_json, "json", "Stage-Q summary and health"),
        ("stage_q_transfer", args.stage_q_transfer_csv, "csv", "Stage-Q transfer diagnostics"),
        ("stage_q_validation", args.stage_q_validation_csv, "csv", "Stage-Q validation-selected rows"),
        ("stage_q_oracle", args.stage_q_oracle_csv, "csv", "Stage-Q test-oracle rows"),
        ("stage_q_horizon", args.stage_q_horizon_csv, "csv", "Stage-Q horizon-block diagnostics"),
    ]


def build_input_manifest(args):
    rows = []
    for name, path, kind, role in input_specs(args):
        full = repo_path(path)
        if not full.exists() or full.stat().st_size == 0:
            raise FileNotFoundError("{} missing required {}: {}".format(name, kind, full))
        row = {
            "input_id": name,
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


def validate_stage_q_summary(summary):
    if not bool_value(summary.get("run_clean", False)):
        raise ValueError("Stage-Q summary is not clean.")
    if bool_value(summary.get("stage_m_surface_changed", True)):
        raise ValueError("Stage-Q summary says Stage-M surface changed.")
    if bool_value(summary.get("priority1_launch_recommended", True)):
        raise ValueError("Stage-Q priority 1 is still recommended; expected false.")
    if not bool_value(summary.get("no_stage_q_promotions_recommended", False)):
        raise ValueError("Stage-Q summary has promotions recommended; expected none.")


def load_inputs(args):
    data = {
        "surface": read_csv_required(args.stage_m_surface_csv, "Stage-M surface"),
        "current_vt": read_csv_required(args.stage_m_current_vt_csv, "Stage-M current validation/test"),
        "alignment_rows": read_csv_required(args.stage_m_alignment_rows_csv, "Stage-M alignment rows"),
        "split": read_csv_required(args.stage_m_split_csv, "Stage-M split diagnostics"),
        "stage_n_selected": read_csv_required(args.stage_n_selected_csv, "Stage-N selected"),
        "stage_n_instability": read_csv_required(args.stage_n_instability_csv, "Stage-N instability"),
        "stage_n_horizon": read_csv_required(args.stage_n_horizon_csv, "Stage-N horizon"),
        "stage_o_rule_audit": read_csv_required(args.stage_o_rule_audit_csv, "Stage-O rule audit"),
        "stage_o_rule_selected": read_csv_required(args.stage_o_rule_selected_csv, "Stage-O rule selected"),
        "stage_p_flags": read_csv_required(args.stage_p_flags_csv, "Stage-P flags"),
        "stage_q_transfer": read_csv_required(args.stage_q_transfer_csv, "Stage-Q transfer"),
        "stage_q_validation": read_csv_required(args.stage_q_validation_csv, "Stage-Q validation"),
        "stage_q_oracle": read_csv_required(args.stage_q_oracle_csv, "Stage-Q oracle"),
        "stage_q_horizon": read_csv_required(args.stage_q_horizon_csv, "Stage-Q horizon"),
        "stage_q_summary": read_json_required(args.stage_q_summary_json, "Stage-Q summary"),
    }
    validate_stage_q_summary(data["stage_q_summary"])
    validate_inputs(data)
    return data


def validate_inputs(data):
    surface = normalize_keys(data["surface"], "Stage-M surface", unique=True)
    require_columns(
        surface,
        [
            "local_AQL", "pricefm_AQL", "delta_abs", "delta_rel",
            "decision_label", "information_set", "feature_policy",
        ],
        "Stage-M surface",
    )
    finite_check(surface, ["local_AQL", "pricefm_AQL", "delta_abs", "delta_rel"], "Stage-M surface")
    if surface.shape[0] != 42:
        raise ValueError("Stage-M surface must have 42 rows; got {}".format(surface.shape[0]))

    current_vt = normalize_keys(data["current_vt"], "Stage-M current validation/test")
    require_columns(current_vt, ["selection_AQL", "test_AQL"], "Stage-M current validation/test")
    finite_check(current_vt, ["selection_AQL", "test_AQL"], "Stage-M current validation/test")

    align = normalize_keys(data["alignment_rows"], "Stage-M alignment rows")
    require_columns(align, ["source_label", "selection_AQL", "test_AQL"], "Stage-M alignment rows")
    finite_check(align, ["selection_AQL", "test_AQL"], "Stage-M alignment rows")

    split = normalize_keys(data["split"], "Stage-M split diagnostics")
    require_columns(split, ["contrast", "mean_delta", "sd_ratio", "median_delta"], "Stage-M split diagnostics")
    finite_check(split, ["mean_delta", "sd_ratio", "median_delta"], "Stage-M split diagnostics")

    for key, label in [
        ("stage_n_selected", "Stage-N selected"),
        ("stage_o_rule_selected", "Stage-O selected rows"),
    ]:
        frame = normalize_keys(data[key], label)
        require_columns(frame, ["method_id"], label)

    n_inst = normalize_keys(data["stage_n_instability"], "Stage-N instability")
    require_columns(n_inst, ["validation_selected_test_AQL", "test_oracle_test_AQL"], "Stage-N instability")
    finite_check(n_inst, ["validation_selected_test_AQL", "test_oracle_test_AQL"], "Stage-N instability")

    n_horizon = normalize_keys(data["stage_n_horizon"], "Stage-N horizon")
    require_columns(n_horizon, ["horizon_group"], "Stage-N horizon")

    require_columns(data["stage_o_rule_audit"], ["rule_id", "selection_uses_test_metrics"], "Stage-O rule audit")

    p_flags = normalize_keys(data["stage_p_flags"], "Stage-P flags")
    require_columns(p_flags, ["AQL", "pricefm_phase1_AQL", "delta_abs", "decision_label"], "Stage-P flags")
    finite_check(p_flags, ["AQL", "pricefm_phase1_AQL", "delta_abs"], "Stage-P flags")

    q_transfer = normalize_keys(data["stage_q_transfer"], "Stage-Q transfer")
    require_columns(q_transfer, ["spearman_val_test_rank", "validation_selected_test_regret"], "Stage-Q transfer")
    finite_check(q_transfer, ["spearman_val_test_rank", "validation_selected_test_regret"], "Stage-Q transfer")

    for key, label in [
        ("stage_q_validation", "Stage-Q validation"),
        ("stage_q_oracle", "Stage-Q oracle"),
        ("stage_q_horizon", "Stage-Q horizon"),
    ]:
        normalize_keys(data[key], label)


def method_family(method_id):
    text = str(method_id)
    if text.startswith("qdesn_exal"):
        return "qdesn_exal"
    if text.startswith("qdesn_al"):
        return "qdesn_al"
    if text.startswith("normal"):
        return "normal_desn"
    if text.startswith("naive"):
        return "naive"
    return "other"


def col_or_blank(frame, col):
    if col in frame.columns:
        return frame[col]
    return pd.Series([""] * len(frame), index=frame.index)


def col_or_nan(frame, col):
    if col in frame.columns:
        return pd.to_numeric(frame[col], errors="coerce")
    return pd.Series([float("nan")] * len(frame), index=frame.index)


def base_candidate_frame(frame, source_label, selection_view):
    frame = normalize_keys(frame, source_label)
    out = pd.DataFrame({
        "source_label": source_label,
        "region": frame["region"],
        "fold": frame["fold"],
        "experiment_id": col_or_blank(frame, "experiment_id").where(
            col_or_blank(frame, "experiment_id").astype(str).ne(""),
            col_or_blank(frame, "id"),
        ),
        "method_id": col_or_blank(frame, "method_id").where(
            col_or_blank(frame, "method_id").astype(str).ne(""),
            col_or_blank(frame, "selected_method_id"),
        ),
        "selection_view": selection_view,
        "feature_policy": col_or_blank(frame, "feature_policy"),
        "information_set": col_or_blank(frame, "information_set"),
        "graph_degree": col_or_blank(frame, "graph_degree"),
        "validation_AQL": col_or_nan(frame, "selection_AQL"),
        "test_AQL": col_or_nan(frame, "test_AQL"),
        "current_validation_AQL": col_or_nan(frame, "current_selection_AQL"),
        "current_test_AQL": col_or_nan(frame, "current_test_AQL"),
        "pricefm_AQL": col_or_nan(frame, "pricefm_AQL"),
        "validation_delta": col_or_nan(frame, "val_delta_vs_current"),
        "test_delta": col_or_nan(frame, "test_delta_vs_current"),
        "test_delta_vs_pricefm": col_or_nan(frame, "delta_test_vs_pricefm"),
        "candidate_family": col_or_blank(frame, "candidate_family"),
        "selection_rule": col_or_blank(frame, "selection_rule"),
        "test_metrics_role": col_or_blank(frame, "test_metrics_role"),
        "rule_id": col_or_blank(frame, "rule_id"),
    })
    if out["validation_AQL"].isna().all() and "val_AQL" in frame.columns:
        out["validation_AQL"] = col_or_nan(frame, "val_AQL")
    if out["test_delta_vs_pricefm"].isna().all() and out["pricefm_AQL"].notna().any():
        out["test_delta_vs_pricefm"] = out["test_AQL"] - out["pricefm_AQL"]
    if out["validation_delta"].isna().all() and out["current_validation_AQL"].notna().any():
        out["validation_delta"] = out["validation_AQL"] - out["current_validation_AQL"]
    if out["test_delta"].isna().all() and out["current_test_AQL"].notna().any():
        out["test_delta"] = out["test_AQL"] - out["current_test_AQL"]
    if out["selection_rule"].astype(str).eq("").all():
        out["selection_rule"] = "median_validation_AQL_only"
    if out["test_metrics_role"].astype(str).eq("").all():
        out["test_metrics_role"] = "audit_only"
    out["model_family"] = [method_family(x) for x in out["method_id"]]
    out["validation_improved"] = out["validation_delta"] < 0.0
    out["test_improved"] = out["test_delta"] < 0.0
    out["beats_pricefm"] = out["test_delta_vs_pricefm"] < 0.0
    out["selection_test_disagree"] = out["validation_improved"] != out["test_improved"]
    return out


def normalize_stage_m_alignment(frame):
    return base_candidate_frame(frame, "stage_m_alignment", "diagnostic_candidate")


def normalize_stage_n_selected(frame):
    out = base_candidate_frame(frame, "stage_n_validation_selected", "validation_selected")
    if "promotion_decision" in frame.columns:
        out["promotion_decision"] = frame["promotion_decision"].astype(str)
    return out


def normalize_stage_n_oracle(frame):
    rows = []
    frame = normalize_keys(frame, "Stage-N instability")
    for _, row in frame.iterrows():
        rows.append({
            "source_label": "stage_n_test_oracle_audit",
            "region": row["region"],
            "fold": int(row["fold"]),
            "experiment_id": row.get("test_oracle_id", ""),
            "method_id": row.get("test_oracle_method", ""),
            "selection_view": "test_oracle_audit_only",
            "feature_policy": "",
            "information_set": "",
            "graph_degree": "",
            "validation_AQL": row.get("test_oracle_val_AQL", float("nan")),
            "test_AQL": row.get("test_oracle_test_AQL", float("nan")),
            "current_validation_AQL": float("nan"),
            "current_test_AQL": float("nan"),
            "pricefm_AQL": float("nan"),
            "validation_delta": float("nan"),
            "test_delta": row.get("test_oracle_delta_vs_current", float("nan")),
            "test_delta_vs_pricefm": row.get("test_oracle_delta_vs_pricefm", float("nan")),
            "candidate_family": "",
            "selection_rule": "test_oracle_audit_only",
            "test_metrics_role": "audit_only",
            "rule_id": "",
            "model_family": method_family(row.get("test_oracle_method", "")),
            "validation_improved": False,
            "test_improved": pd.to_numeric(pd.Series([row.get("test_oracle_delta_vs_current", float("nan"))]), errors="coerce").iloc[0] < 0.0,
            "beats_pricefm": pd.to_numeric(pd.Series([row.get("test_oracle_delta_vs_pricefm", float("nan"))]), errors="coerce").iloc[0] < 0.0,
            "selection_test_disagree": False,
            "promotion_decision": "test_oracle_audit_only",
        })
    return pd.DataFrame(rows)


def normalize_stage_o_selected(frame):
    return base_candidate_frame(frame, "stage_o_selection_rule", "validation_rule_selected")


def normalize_stage_q_rows(validation, oracle):
    frames = []
    val = validation.copy()
    if "val_AQL" in val.columns and "selection_AQL" not in val.columns:
        val["selection_AQL"] = val["val_AQL"]
    frames.append(base_candidate_frame(val, "stage_q_validation_selected", "validation_selected"))
    test = oracle.copy()
    if "val_AQL" in test.columns and "selection_AQL" not in test.columns:
        test["selection_AQL"] = test["val_AQL"]
    frames.append(base_candidate_frame(test, "stage_q_test_oracle_audit", "test_oracle_audit_only"))
    return pd.concat(frames, ignore_index=True, sort=False)


def build_candidate_transfer_rows(data):
    frames = [
        normalize_stage_m_alignment(data["alignment_rows"]),
        normalize_stage_n_selected(data["stage_n_selected"]),
        normalize_stage_n_oracle(data["stage_n_instability"]),
        normalize_stage_o_selected(data["stage_o_rule_selected"]),
        normalize_stage_q_rows(data["stage_q_validation"], data["stage_q_oracle"]),
    ]
    out = pd.concat(frames, ignore_index=True, sort=False)
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    for col in [
        "validation_AQL", "test_AQL", "current_validation_AQL",
        "current_test_AQL", "pricefm_AQL", "validation_delta",
        "test_delta", "test_delta_vs_pricefm",
    ]:
        out[col] = pd.to_numeric(out[col], errors="coerce")
    out["test_metrics_role"] = out["test_metrics_role"].replace("", "audit_only")
    return out.sort_values(["source_label", "region", "fold", "selection_view", "experiment_id", "method_id"]).reset_index(drop=True)


def spearman_for_group(frame):
    work = frame[["validation_AQL", "test_AQL"]].dropna()
    if work.shape[0] < 3:
        return float("nan")
    val_rank = work["validation_AQL"].rank(method="average")
    test_rank = work["test_AQL"].rank(method="average")
    if val_rank.nunique() < 2 or test_rank.nunique() < 2:
        return float("nan")
    return val_rank.corr(test_rank)


def build_selection_transfer_by_source(candidates):
    if candidates.empty:
        return pd.DataFrame()
    grouped = candidates.groupby("source_label", dropna=False)
    rows = []
    for source, sub in grouped:
        spears = []
        for _, key_sub in sub.groupby(["region", "fold"], dropna=False):
            val = spearman_for_group(key_sub)
            if pd.notna(val):
                spears.append(float(val))
        rows.append({
            "source_label": source,
            "n_rows": int(sub.shape[0]),
            "n_region_folds": int(sub[["region", "fold"]].drop_duplicates().shape[0]),
            "validation_win_rate": float(sub["validation_improved"].mean()) if sub.shape[0] else float("nan"),
            "test_win_rate": float(sub["test_improved"].mean()) if sub.shape[0] else float("nan"),
            "pricefm_win_rate": float(sub["beats_pricefm"].mean()) if sub.shape[0] else float("nan"),
            "disagree_rate": float(sub["selection_test_disagree"].mean()) if sub.shape[0] else float("nan"),
            "mean_validation_delta": float(sub["validation_delta"].mean()),
            "mean_test_delta": float(sub["test_delta"].mean()),
            "mean_test_delta_vs_pricefm": float(sub["test_delta_vs_pricefm"].mean()),
            "mean_spearman_val_test_rank": float(pd.Series(spears).mean()) if spears else float("nan"),
            "n_spearman_groups": int(len(spears)),
        })
    return pd.DataFrame(rows).sort_values("source_label").reset_index(drop=True)


def build_split_pivot(split):
    split = normalize_keys(split, "split diagnostics")
    keep = split[["region", "fold", "contrast", "mean_delta", "sd_ratio", "median_delta"]].copy()
    pivot = keep.pivot_table(
        index=["region", "fold"],
        columns="contrast",
        values=["mean_delta", "sd_ratio", "median_delta"],
        aggfunc="first",
    )
    pivot.columns = ["{}_{}".format(a, b).replace("-", "_") for a, b in pivot.columns]
    return pivot.reset_index()


def build_information_set_parity(surface):
    surface = normalize_keys(surface, "Stage-M surface")
    out = surface.groupby(["information_set", "feature_policy"], dropna=False).agg(
        rows=("region", "size"),
        wins=("local_wins", lambda x: int(pd.Series(x).astype(bool).sum()) if "local_wins" in surface.columns else 0),
        mean_delta_AQL=("delta_abs", "mean"),
        median_delta_AQL=("delta_abs", "median"),
        mean_qdesn_AQL=("local_AQL", "mean"),
        mean_pricefm_AQL=("pricefm_AQL", "mean"),
    ).reset_index()
    out["win_rate"] = out["wins"] / out["rows"].clip(lower=1)
    return out.sort_values(["information_set", "feature_policy"]).reset_index(drop=True)


def horizon_band(value):
    text = str(value)
    if text.startswith("1-24"):
        return "early"
    if text.startswith("25-48"):
        return "middle"
    if text.startswith("49-72"):
        return "middle_late"
    if text.startswith("73-96"):
        return "late"
    return "other"


def build_horizon_block_diagnostics(data):
    rows = []
    n_h = normalize_keys(data["stage_n_horizon"], "Stage-N horizon")
    for _, row in n_h.iterrows():
        rows.append({
            "source_label": "stage_n",
            "region": row["region"],
            "fold": int(row["fold"]),
            "horizon_group": row.get("horizon_group", ""),
            "horizon_band": horizon_band(row.get("horizon_group", "")),
            "validation_selected_experiment_id": row.get("validation_selected_id", ""),
            "test_oracle_experiment_id": row.get("test_oracle_id", ""),
            "validation_selected_AQL": row.get("validation_selected_test_AQL", float("nan")),
            "test_oracle_AQL": row.get("test_oracle_test_AQL", float("nan")),
            "oracle_minus_validation_AQL": row.get("oracle_minus_validation_test_AQL", float("nan")),
            "oracle_better": row.get("oracle_better_on_test_group", ""),
            "selection_view": "validation_vs_oracle",
            "method_id": row.get("validation_selected_method", ""),
        })
    q_h = normalize_keys(data["stage_q_horizon"], "Stage-Q horizon")
    for _, row in q_h.iterrows():
        rows.append({
            "source_label": "stage_q",
            "region": row["region"],
            "fold": int(row["fold"]),
            "horizon_group": row.get("horizon_group", ""),
            "horizon_band": horizon_band(row.get("horizon_group", "")),
            "validation_selected_experiment_id": row.get("experiment_id", "")
            if str(row.get("selection_view", "")) == "validation_selected" else "",
            "test_oracle_experiment_id": row.get("experiment_id", "")
            if str(row.get("selection_view", "")) == "test_oracle_audit_only" else "",
            "validation_selected_AQL": row.get("AQL", float("nan"))
            if str(row.get("selection_view", "")) == "validation_selected" else float("nan"),
            "test_oracle_AQL": row.get("AQL", float("nan"))
            if str(row.get("selection_view", "")) == "test_oracle_audit_only" else float("nan"),
            "oracle_minus_validation_AQL": float("nan"),
            "oracle_better": "",
            "selection_view": row.get("selection_view", ""),
            "method_id": row.get("method_id", ""),
        })
    out = pd.DataFrame(rows)
    for col in ["validation_selected_AQL", "test_oracle_AQL", "oracle_minus_validation_AQL"]:
        out[col] = pd.to_numeric(out[col], errors="coerce")
    return out.sort_values(["source_label", "region", "fold", "horizon_group", "selection_view"]).reset_index(drop=True)


def build_region_fold_scorecard(data):
    surface = normalize_keys(data["surface"], "Stage-M surface", unique=True)
    current_vt = normalize_keys(data["current_vt"], "Stage-M current validation/test")
    split_pivot = build_split_pivot(data["split"])
    stage_p = normalize_keys(data["stage_p_flags"], "Stage-P flags")
    q_transfer = normalize_keys(data["stage_q_transfer"], "Stage-Q transfer")

    out = surface.merge(
        current_vt[[
            "region", "fold", "selection_AQL", "test_AQL",
            "test_minus_validation_AQL", "abs_test_minus_validation_AQL",
        ]].rename(columns={
            "selection_AQL": "current_validation_AQL",
            "test_AQL": "current_median_test_AQL",
        }),
        on=["region", "fold"],
        how="left",
        validate="one_to_one",
    )
    out = out.merge(split_pivot, on=["region", "fold"], how="left", validate="one_to_one")
    stage_p_small = stage_p[["region", "fold", "AQL", "pricefm_phase1_AQL", "delta_abs", "delta_rel", "decision_label"]].rename(columns={
        "AQL": "stage_p_AQL",
        "pricefm_phase1_AQL": "stage_p_pricefm_AQL",
        "delta_abs": "stage_p_delta_abs",
        "delta_rel": "stage_p_delta_rel",
        "decision_label": "stage_p_decision_label",
    })
    out = out.merge(stage_p_small, on=["region", "fold"], how="left", validate="one_to_one")
    q_small = q_transfer[[
        "region", "fold", "spearman_val_test_rank",
        "validation_selected_test_regret", "selected_delta_test_vs_pricefm",
        "oracle_delta_test_vs_pricefm",
    ]].rename(columns={
        "spearman_val_test_rank": "stage_q_spearman_val_test_rank",
        "validation_selected_test_regret": "stage_q_validation_selected_test_regret",
        "selected_delta_test_vs_pricefm": "stage_q_selected_delta_vs_pricefm",
        "oracle_delta_test_vs_pricefm": "stage_q_oracle_delta_vs_pricefm",
    })
    out = out.merge(q_small, on=["region", "fold"], how="left", validate="one_to_one")
    out["unresolved_tier"] = "local_win"
    out.loc[out["delta_abs"].gt(0.0) & out["delta_abs"].le(0.35), "unresolved_tier"] = "near"
    out.loc[out["delta_abs"].gt(0.35) & out["delta_abs"].le(0.75), "unresolved_tier"] = "moderate"
    out.loc[out["delta_abs"].gt(0.75), "unresolved_tier"] = "large"
    return out


def row_has_late_horizon_gap(horizon, region, fold):
    sub = horizon[(horizon["region"].astype(str).eq(str(region))) & (horizon["fold"].astype(int).eq(int(fold)))]
    if sub.empty:
        return False
    late = sub[sub["horizon_band"].isin(["middle", "middle_late", "late"])]
    vals = pd.to_numeric(late["validation_selected_AQL"].fillna(late["test_oracle_AQL"]), errors="coerce")
    early = sub[sub["horizon_band"].eq("early")]
    early_vals = pd.to_numeric(early["validation_selected_AQL"].fillna(early["test_oracle_AQL"]), errors="coerce")
    if vals.dropna().empty or early_vals.dropna().empty:
        return False
    return bool(vals.mean() > early_vals.mean() + 1.0)


def assign_failure_modes(scorecard, horizon):
    rows = []
    for _, row in scorecard.iterrows():
        delta = float(row.get("delta_abs", float("nan")))
        info = str(row.get("information_set", ""))
        feature = str(row.get("feature_policy", ""))
        q_spear = row.get("stage_q_spearman_val_test_rank", float("nan"))
        has_q = pd.notna(q_spear)
        late_gap = row_has_late_horizon_gap(horizon, row["region"], row["fold"])
        secondary = []
        if late_gap:
            secondary.append("late_horizon_gap")
        if delta <= 0.0:
            primary = "no_action"
            action = "no_launch"
            rationale = "Current selected row already beats cached PriceFM."
        elif has_q and abs(float(q_spear)) < 0.2:
            primary = "selection_instability"
            action = "no_launch"
            rationale = "Stage-Q near-miss search had near-zero validation/test rank transfer."
        elif info == "target_only" or feature == "target_only":
            primary = "graph_parity_gap"
            action = "graph_parity_targeted_grid"
            rationale = "Current underperforming row is target-only while graph-input rows perform better on average."
        elif delta >= 1.0:
            primary = "pricefm_far_ahead"
            action = "defer_as_pricefm_far_ahead"
            rationale = "PriceFM gap is large and existing rescue stages have not closed comparable gaps."
        elif late_gap:
            primary = "late_horizon_gap"
            action = "horizon_block_selection_pilot"
            rationale = "Middle/late horizon blocks dominate the available loss diagnostics."
        elif delta <= 0.35:
            primary = "stable_promising"
            action = "stable_seed_recheck"
            rationale = "The row is close enough to justify a small stability check if selection transfer is credible."
        else:
            primary = "graph_geometry_gap"
            action = "graph_geometry_diagnostic_only"
            rationale = "Graph inputs exist, but geometry/selection diagnostics are needed before more fitting."
        rows.append({
            "region": row["region"],
            "fold": int(row["fold"]),
            "primary_failure_mode": primary,
            "secondary_failure_modes": ";".join([x for x in secondary if x != primary]),
            "recommended_action": action,
            "diagnostic_rationale": rationale,
            "current_delta_AQL": delta,
            "current_information_set": info,
            "stage_q_transfer_available": bool(has_q),
            "late_horizon_gap_available": bool(late_gap),
        })
    return pd.DataFrame(rows).sort_values(["recommended_action", "current_delta_AQL", "region", "fold"], ascending=[True, False, True, True])


def build_next_grid_recommendations(failures):
    out = failures.copy()
    out["writes_launch_config"] = False
    out["requires_authorization_before_launch"] = True
    out["stage_s_priority"] = ""
    eligible = out["recommended_action"].isin([
        "graph_parity_targeted_grid", "horizon_block_selection_pilot",
        "stable_seed_recheck",
    ])
    out.loc[eligible, "stage_s_priority"] = "candidate_priority0_after_stage_r_review"
    out.loc[out["recommended_action"].isin(["no_launch", "defer_as_pricefm_far_ahead"]), "stage_s_priority"] = "not_eligible"
    return out[[
        "region", "fold", "primary_failure_mode", "secondary_failure_modes",
        "recommended_action", "stage_s_priority", "writes_launch_config",
        "requires_authorization_before_launch", "diagnostic_rationale",
        "current_delta_AQL", "current_information_set",
    ]].sort_values(["stage_s_priority", "recommended_action", "current_delta_AQL"], ascending=[True, True, False])


def write_frame(path, frame):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)


def markdown_table(frame, columns=None, max_rows=20):
    if frame is None or frame.empty:
        return "_No rows._"
    work = frame.copy()
    if columns is not None:
        work = work[[col for col in columns if col in work.columns]]
    if max_rows is not None:
        work = work.head(max_rows)
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
    return "\n".join(lines)


def write_report(path, summary, scorecard, transfer, parity, failures, recommendations):
    lines = [
        "# PriceFM Stage-R selection diagnostics",
        "",
        "Stage R is diagnostic-only.  It consumes existing Stage-M/N/O/P/Q "
        "artifacts and does not fit models, mutate the Stage-M surface, or "
        "write launch grids.",
        "",
        "## Health",
        "",
        "- Diagnostic only: `{}`".format(summary["diagnostic_only"]),
        "- Stage-M rows: `{}`".format(summary["stage_m_rows"]),
        "- Stage-M surface changed: `{}`".format(summary["stage_m_surface_changed"]),
        "- Stage-Q run clean: `{}`".format(summary["stage_q_run_clean"]),
        "- Stage-Q priority-1 launch recommended: `{}`".format(summary["stage_q_priority1_launch_recommended"]),
        "- Writes launch configs: `{}`".format(summary["writes_launch_configs"]),
        "",
        "## Selection Transfer By Source",
        "",
        markdown_table(transfer, [
            "source_label", "n_rows", "n_region_folds", "validation_win_rate",
            "test_win_rate", "pricefm_win_rate", "disagree_rate",
            "mean_test_delta_vs_pricefm", "mean_spearman_val_test_rank",
        ]),
        "",
        "## Information-Set Parity",
        "",
        markdown_table(parity, [
            "information_set", "feature_policy", "rows", "wins", "win_rate",
            "mean_delta_AQL", "median_delta_AQL",
        ]),
        "",
        "## Failure Modes",
        "",
        markdown_table(failures, [
            "region", "fold", "primary_failure_mode", "secondary_failure_modes",
            "recommended_action", "current_delta_AQL", "current_information_set",
        ], max_rows=50),
        "",
        "## Next Recommendations",
        "",
        markdown_table(recommendations, [
            "region", "fold", "recommended_action", "stage_s_priority",
            "writes_launch_config", "diagnostic_rationale",
        ], max_rows=50),
        "",
        "## Interpretation",
        "",
        "- Stage-Q priority 1 remains blocked.",
        "- A future Stage-S grid should be generated only after reviewing the "
        "row-level failure modes and recommendations in this directory.",
        "- Test metrics remain audit-only and are not used to promote rows.",
        "",
        "## Output Manifest",
        "",
    ]
    for key, value in sorted(summary["outputs"].items()):
        lines.append("- `{}`: `{}`".format(key, value))
    repo_path(path).write_text("\n".join(lines) + "\n")


def diagnose(args):
    output_dir = repo_path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    input_manifest = build_input_manifest(args)
    data = load_inputs(args)
    candidate_rows = build_candidate_transfer_rows(data)
    transfer_by_source = build_selection_transfer_by_source(candidate_rows)
    scorecard = build_region_fold_scorecard(data)
    horizon = build_horizon_block_diagnostics(data)
    parity = build_information_set_parity(data["surface"])
    failures = assign_failure_modes(scorecard, horizon)
    recommendations = build_next_grid_recommendations(failures)

    summary = {
        "status": "completed",
        "diagnostic_only": True,
        "writes_launch_configs": False,
        "stage_m_surface_changed": False,
        "stage_q_run_clean": True,
        "stage_q_priority1_launch_recommended": False,
        "stage_m_rows": int(scorecard.shape[0]),
        "candidate_transfer_rows": int(candidate_rows.shape[0]),
        "n_recommendation_rows": int(recommendations.shape[0]),
        "repo_branch": git_value(["git", "branch", "--show-current"]),
        "repo_head": git_value(["git", "rev-parse", "--short", "HEAD"]),
        "repo_dirty": bool(git_value(["git", "status", "--short"])),
        "output_dir": config_path_value(output_dir),
    }

    outputs = {
        "input_manifest_csv": output_dir / "stage_r_input_manifest.csv",
        "region_fold_scorecard_csv": output_dir / "stage_r_region_fold_scorecard.csv",
        "selection_transfer_by_source_csv": output_dir / "stage_r_selection_transfer_by_source.csv",
        "candidate_transfer_rows_csv": output_dir / "stage_r_candidate_transfer_rows.csv",
        "horizon_block_diagnostics_csv": output_dir / "stage_r_horizon_block_diagnostics.csv",
        "information_set_parity_csv": output_dir / "stage_r_information_set_parity.csv",
        "failure_mode_assignments_csv": output_dir / "stage_r_failure_mode_assignments.csv",
        "next_grid_recommendations_csv": output_dir / "stage_r_next_grid_recommendations.csv",
        "summary_md": output_dir / "stage_r_summary.md",
        "summary_json": output_dir / "summary.json",
    }
    summary["outputs"] = {key: config_path_value(value) for key, value in outputs.items()}

    write_frame(outputs["input_manifest_csv"], input_manifest)
    write_frame(outputs["region_fold_scorecard_csv"], scorecard)
    write_frame(outputs["selection_transfer_by_source_csv"], transfer_by_source)
    write_frame(outputs["candidate_transfer_rows_csv"], candidate_rows)
    write_frame(outputs["horizon_block_diagnostics_csv"], horizon)
    write_frame(outputs["information_set_parity_csv"], parity)
    write_frame(outputs["failure_mode_assignments_csv"], failures)
    write_frame(outputs["next_grid_recommendations_csv"], recommendations)
    write_json(outputs["summary_json"], summary)
    write_report(outputs["summary_md"], summary, scorecard, transfer_by_source, parity, failures, recommendations)

    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main():
    args = parser().parse_args()
    diagnose(args)


if __name__ == "__main__":
    main()
