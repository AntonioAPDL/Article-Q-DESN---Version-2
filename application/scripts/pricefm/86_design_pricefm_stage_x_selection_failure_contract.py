#!/usr/bin/env python3
"""Design the Stage-X PriceFM selection-failure contract.

Stage X is diagnostic-only.  It consolidates the Stage-M decision surface,
Stage-U parity audit, Stage-V horizon-aware rule audit, and Stage-W Priority-0
closeout.  It evaluates validation-only selection rules and uses test metrics
only as audit evidence.  It does not fit models, write launch grids, or mutate
the Stage-M decision surface.
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
    "pricefm_stage_x_selection_failure_contract_20260630"
)
DEFAULT_STAGE_M_SURFACE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624/"
    "current_decision_surface_table.csv"
)
DEFAULT_STAGE_U_SUMMARY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_u_parity_audit_20260629/summary.json"
)
DEFAULT_STAGE_U_ROW_PARITY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_u_parity_audit_20260629/stage_u_row_parity_matrix.csv"
)
DEFAULT_STAGE_U_HORIZON = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_u_parity_audit_20260629/stage_u_horizon_gap_by_row.csv"
)
DEFAULT_STAGE_V_SUMMARY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_v_horizon_selection_contract_20260629/summary.json"
)
DEFAULT_STAGE_V_CANDIDATES = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_v_horizon_selection_contract_20260629/"
    "stage_v_candidate_universe.csv"
)
DEFAULT_STAGE_V_RULE_AUDIT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_v_horizon_selection_contract_20260629/stage_v_rule_audit.csv"
)
DEFAULT_STAGE_W_SUMMARY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_w_priority0_closeout_20260630/summary.json"
)
DEFAULT_STAGE_W_QDESN = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_w_priority0_closeout_20260630/"
    "stage_w_priority0_qdesn_method_metrics.csv"
)
DEFAULT_STAGE_W_TRANSFER = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_w_priority0_closeout_20260630/"
    "stage_w_priority0_validation_transfer.csv"
)
DEFAULT_STAGE_W_ORACLE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_w_priority0_closeout_20260630/"
    "stage_w_priority0_test_oracle_audit.csv"
)
DEFAULT_STAGE_W_HORIZON = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_w_priority0_closeout_20260630/"
    "stage_w_priority0_horizon_gap_summary.csv"
)

HORIZON_GROUPS = ["1_24", "25_48", "49_72", "73_96"]
TEST_AUDIT_COLUMNS = {
    "test_AQL",
    "test_MAE",
    "test_RMSE",
    "test_delta_vs_current_median",
    "test_delta_vs_stage_m_surface",
    "test_delta_vs_pricefm",
    "test_horizon_mean_AQL",
    "test_horizon_max_AQL",
    "test_horizon_min_AQL",
    "test_horizon_range_AQL",
    "test_horizon_early_AQL",
    "test_horizon_midlate_mean_AQL",
}


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-m-surface-csv", default=DEFAULT_STAGE_M_SURFACE)
    p.add_argument("--stage-u-summary-json", default=DEFAULT_STAGE_U_SUMMARY)
    p.add_argument("--stage-u-row-parity-csv", default=DEFAULT_STAGE_U_ROW_PARITY)
    p.add_argument("--stage-u-horizon-csv", default=DEFAULT_STAGE_U_HORIZON)
    p.add_argument("--stage-v-summary-json", default=DEFAULT_STAGE_V_SUMMARY)
    p.add_argument("--stage-v-candidate-universe-csv", default=DEFAULT_STAGE_V_CANDIDATES)
    p.add_argument("--stage-v-rule-audit-csv", default=DEFAULT_STAGE_V_RULE_AUDIT)
    p.add_argument("--stage-w-summary-json", default=DEFAULT_STAGE_W_SUMMARY)
    p.add_argument("--stage-w-qdesn-metrics-csv", default=DEFAULT_STAGE_W_QDESN)
    p.add_argument("--stage-w-validation-transfer-csv", default=DEFAULT_STAGE_W_TRANSFER)
    p.add_argument("--stage-w-test-oracle-csv", default=DEFAULT_STAGE_W_ORACLE)
    p.add_argument("--stage-w-horizon-gap-csv", default=DEFAULT_STAGE_W_HORIZON)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--expected-stage-m-rows", type=int, default=42)
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


def numeric(frame, col, default=float("nan")):
    if col not in frame.columns:
        return pd.Series([default] * len(frame), index=frame.index)
    return pd.to_numeric(frame[col], errors="coerce")


def bool_value(value):
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in ("true", "1", "yes", "y")


def as_float(value, default=float("nan")):
    try:
        out = float(value)
    except (TypeError, ValueError):
        return default
    return out if math.isfinite(out) else default


def write_frame(path, frame):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)


def markdown_table(frame, columns=None, max_rows=None):
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
                vals.append(str(value))
        lines.append("| {} |".format(" | ".join(vals)))
    return "\n".join(lines)


def git_value(args):
    proc = subprocess.run(
        args,
        cwd=str(repo_path(".")),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        check=False,
    )
    return proc.stdout.strip() if proc.returncode == 0 else ""


def repo_state():
    return {
        "repo_branch": git_value(["git", "branch", "--show-current"]),
        "repo_head": git_value(["git", "rev-parse", "--short", "HEAD"]),
        "repo_dirty": bool(git_value(["git", "status", "--short"])),
    }


def input_specs(args):
    return [
        ("stage_m_surface", args.stage_m_surface_csv, "csv", "frozen Stage-M decision surface"),
        ("stage_u_summary", args.stage_u_summary_json, "json", "Stage-U parity summary"),
        ("stage_u_row_parity", args.stage_u_row_parity_csv, "csv", "Stage-U row parity matrix"),
        ("stage_u_horizon", args.stage_u_horizon_csv, "csv", "Stage-U horizon gap table"),
        ("stage_v_summary", args.stage_v_summary_json, "json", "Stage-V horizon contract summary"),
        ("stage_v_candidate_universe", args.stage_v_candidate_universe_csv, "csv", "Stage-V candidate universe"),
        ("stage_v_rule_audit", args.stage_v_rule_audit_csv, "csv", "Stage-V validation-rule audit"),
        ("stage_w_summary", args.stage_w_summary_json, "json", "Stage-W Priority-0 closeout summary"),
        ("stage_w_qdesn_metrics", args.stage_w_qdesn_metrics_csv, "csv", "Stage-W Q-DESN candidate metrics"),
        ("stage_w_validation_transfer", args.stage_w_validation_transfer_csv, "csv", "Stage-W validation/test transfer"),
        ("stage_w_test_oracle", args.stage_w_test_oracle_csv, "csv", "Stage-W test-oracle audit"),
        ("stage_w_horizon_gap", args.stage_w_horizon_gap_csv, "csv", "Stage-W horizon regret audit"),
    ]


def build_input_manifest(args):
    rows = []
    for input_id, path, kind, role in input_specs(args):
        full = repo_path(path)
        if not full.exists():
            raise FileNotFoundError("{} missing required input: {}".format(input_id, full))
        row = {
            "input_id": input_id,
            "kind": kind,
            "role": role,
            "path": config_path_value(full),
            "size_bytes": int(full.stat().st_size),
            "sha256": sha256_file(full),
            "n_rows": "",
            "n_columns": "",
        }
        if kind == "csv":
            frame = pd.read_csv(full)
            row["n_rows"] = int(frame.shape[0])
            row["n_columns"] = int(frame.shape[1])
        rows.append(row)
    return pd.DataFrame(rows)


def validate_upstream(args, stage_m, stage_u_summary, stage_v_summary, stage_w_summary):
    require_columns(stage_m, ["region", "fold", "local_AQL", "pricefm_AQL", "delta_abs"], "Stage-M surface")
    if len(stage_m) != args.expected_stage_m_rows:
        raise ValueError("Stage-M surface has {} rows; expected {}".format(len(stage_m), args.expected_stage_m_rows))
    if int(stage_u_summary.get("hard_parity_failures", -1)) != 0:
        raise ValueError("Stage-U hard parity failures must be zero.")
    if str(stage_u_summary.get("recommended_next_stage", "")) != "horizon_aware_validation_contract_after_parity":
        raise ValueError("Stage-U must recommend horizon-aware validation contract.")
    if bool_value(stage_v_summary.get("fits_models", True)):
        raise ValueError("Stage-V summary unexpectedly fits models.")
    if bool_value(stage_v_summary.get("writes_launch_configs", True)):
        raise ValueError("Stage-V summary unexpectedly writes launch configs.")
    if bool_value(stage_v_summary.get("selection_uses_test_metrics_any", True)):
        raise ValueError("Stage-V selection rules must not use test metrics.")
    if not bool_value(stage_w_summary.get("run_clean", False)):
        raise ValueError("Stage-W closeout must be clean.")
    if bool_value(stage_w_summary.get("stage_m_surface_changed", True)):
        raise ValueError("Stage-W must not mutate Stage-M surface.")


def normalize_stage_v_candidates(candidates):
    require_columns(
        candidates,
        [
            "source_label", "experiment_id", "region", "fold", "method_id",
            "val_AQL", "test_AQL", "pricefm_AQL", "current_median_test_AQL",
            "test_delta_vs_pricefm",
        ],
        "Stage-V candidate universe",
    )
    out = candidates.copy()
    out["evidence_source"] = "stage_v_candidate_universe"
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    out["current_AQL"] = numeric(out, "current_median_test_AQL")
    out["stage_m_surface_AQL"] = numeric(out, "stage_m_surface_AQL")
    out["pricefm_AQL"] = numeric(out, "pricefm_AQL")
    out["val_AQL"] = numeric(out, "val_AQL")
    out["test_AQL"] = numeric(out, "test_AQL")
    out["selection_rule_eligible"] = out.get("horizon_rule_eligible", False).map(bool_value)
    out["test_metrics_role"] = "audit_only"
    out["candidate_key"] = (
        out["region"].astype(str)
        + "::"
        + out["fold"].astype(str)
        + "::"
        + out["experiment_id"].astype(str)
        + "::"
        + out["method_id"].astype(str)
    )
    return out


def normalize_stage_w_candidates(stage_w):
    require_columns(
        stage_w,
        ["region", "fold", "experiment_id", "method_id", "val_AQL", "test_AQL", "local_AQL", "pricefm_AQL"],
        "Stage-W Q-DESN metrics",
    )
    out = stage_w.copy()
    out["evidence_source"] = "stage_w_priority0"
    out["source_label"] = "stage_w_priority0"
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    out["current_AQL"] = numeric(out, "local_AQL")
    out["stage_m_surface_AQL"] = out["current_AQL"]
    out["pricefm_AQL"] = numeric(out, "pricefm_AQL")
    out["val_AQL"] = numeric(out, "val_AQL")
    out["test_AQL"] = numeric(out, "test_AQL")
    out["test_delta_vs_current_median"] = out["test_AQL"] - out["current_AQL"]
    out["test_delta_vs_stage_m_surface"] = out["test_delta_vs_current_median"]
    out["test_delta_vs_pricefm"] = out["test_AQL"] - out["pricefm_AQL"]
    out["validation_metrics_complete"] = out["val_AQL"].notna()
    out["test_metrics_complete"] = out["test_AQL"].notna()
    out["val_horizon_groups_complete"] = False
    out["selection_rule_eligible"] = False
    out["test_metrics_role"] = "audit_only"
    out["candidate_key"] = (
        out["region"].astype(str)
        + "::"
        + out["fold"].astype(str)
        + "::"
        + out["experiment_id"].astype(str)
        + "::"
        + out["method_id"].astype(str)
    )
    return out


def build_candidate_evidence(stage_v, stage_w):
    v = normalize_stage_v_candidates(stage_v)
    w = normalize_stage_w_candidates(stage_w)
    all_cols = sorted(set(v.columns).union(set(w.columns)))
    out = pd.concat([v.reindex(columns=all_cols), w.reindex(columns=all_cols)], ignore_index=True)
    out["test_beats_current"] = out["test_AQL"] < out["current_AQL"]
    out["test_beats_pricefm"] = out["test_AQL"] < out["pricefm_AQL"]
    return out


def validation_rule_definitions():
    return pd.DataFrame([
        {
            "rule_id": "val_mean_min",
            "selection_uses_test_metrics": False,
            "requires_complete_val_horizon": False,
            "description": "Minimize validation mean AQL.",
        },
        {
            "rule_id": "val_max_horizon_min",
            "selection_uses_test_metrics": False,
            "requires_complete_val_horizon": True,
            "description": "Minimize worst validation horizon-block AQL.",
        },
        {
            "rule_id": "val_cvar2_horizon_min",
            "selection_uses_test_metrics": False,
            "requires_complete_val_horizon": True,
            "description": "Minimize average of the two worst validation horizon-block AQLs.",
        },
        {
            "rule_id": "val_stability_penalty_min",
            "selection_uses_test_metrics": False,
            "requires_complete_val_horizon": True,
            "description": "Minimize validation mean AQL plus 0.25 times validation horizon range.",
        },
        {
            "rule_id": "val_midlate_min",
            "selection_uses_test_metrics": False,
            "requires_complete_val_horizon": True,
            "description": "Minimize mean validation AQL on horizons 25-96.",
        },
        {
            "rule_id": "val_family_guarded_stability_min",
            "selection_uses_test_metrics": False,
            "requires_complete_val_horizon": True,
            "description": "Stability rule with a small penalty for candidates from historically unstable source labels.",
        },
    ])


def assert_rules_are_validation_only(definitions):
    leaked = definitions[definitions["selection_uses_test_metrics"].map(bool_value)]
    if not leaked.empty:
        raise ValueError("Stage-X rules must be validation-only: {}".format(leaked["rule_id"].tolist()))


def cvar2(row, prefix):
    vals = []
    for group in HORIZON_GROUPS:
        vals.append(as_float(row.get("{}_hg_{}_AQL".format(prefix, group), float("nan"))))
    vals = sorted([v for v in vals if math.isfinite(v)], reverse=True)
    if len(vals) < 2:
        return float("nan")
    return sum(vals[:2]) / 2.0


def add_rule_scores(candidates):
    out = candidates.copy()
    out["score_val_mean_min"] = numeric(out, "val_AQL")
    out["score_val_max_horizon_min"] = numeric(out, "val_horizon_max_AQL")
    out["score_val_cvar2_horizon_min"] = out.apply(lambda row: cvar2(row, "val"), axis=1)
    out["score_val_stability_penalty_min"] = numeric(out, "val_AQL") + 0.25 * numeric(out, "val_horizon_range_AQL")
    out["score_val_midlate_min"] = numeric(out, "val_horizon_midlate_mean_AQL")
    unstable_source_penalty = out["source_label"].astype(str).isin(["stage_q_candidate_root"]).astype(float) * 0.25
    out["score_val_family_guarded_stability_min"] = out["score_val_stability_penalty_min"] + unstable_source_penalty
    return out


def select_by_rule(candidates, definitions):
    scored = add_rule_scores(candidates)
    rows = []
    for _, rule in definitions.iterrows():
        rule_id = rule["rule_id"]
        score_col = "score_{}".format(rule_id)
        eligible = scored.copy()
        if bool_value(rule["requires_complete_val_horizon"]):
            eligible = eligible[eligible.get("val_horizon_groups_complete", False).map(bool_value)].copy()
        eligible = eligible[pd.to_numeric(eligible[score_col], errors="coerce").notna()].copy()
        for (region, fold), sub in eligible.groupby(["region", "fold"], sort=True):
            ordered = sub.sort_values(
                [score_col, "val_AQL", "experiment_id", "method_id"],
                kind="mergesort",
            )
            selected = ordered.iloc[0].to_dict()
            selected["rule_id"] = rule_id
            selected["rule_score"] = selected[score_col]
            selected["selection_uses_test_metrics"] = False
            selected["test_metrics_role"] = "audit_only"
            rows.append(selected)
    return pd.DataFrame(rows)


def build_rule_audit(selected):
    if selected.empty:
        return pd.DataFrame()
    rows = []
    for rule_id, sub in selected.groupby("rule_id", sort=True):
        rows.append({
            "rule_id": rule_id,
            "n_region_folds": int(sub[["region", "fold"]].drop_duplicates().shape[0]),
            "selection_uses_test_metrics": False,
            "mean_val_AQL": sub["val_AQL"].mean(),
            "mean_test_AQL": sub["test_AQL"].mean(),
            "mean_test_delta_vs_current": sub["test_delta_vs_current_median"].mean(),
            "mean_test_delta_vs_pricefm": sub["test_delta_vs_pricefm"].mean(),
            "test_improved_vs_current_rows": int((sub["test_delta_vs_current_median"] < 0).sum()),
            "test_improved_vs_pricefm_rows": int((sub["test_delta_vs_pricefm"] < 0).sum()),
            "median_test_regret_vs_best_rule": float("nan"),
        })
    audit = pd.DataFrame(rows)
    best_by_rf = selected.groupby(["region", "fold"])["test_AQL"].min().rename("best_rule_test_AQL").reset_index()
    regrets = selected.merge(best_by_rf, on=["region", "fold"], how="left")
    regrets["test_regret_vs_best_rule"] = regrets["test_AQL"] - regrets["best_rule_test_AQL"]
    med = regrets.groupby("rule_id")["test_regret_vs_best_rule"].median().rename("median_test_regret_vs_best_rule").reset_index()
    audit = audit.drop(columns=["median_test_regret_vs_best_rule"]).merge(med, on="rule_id", how="left")
    return audit.sort_values(
        ["test_improved_vs_pricefm_rows", "test_improved_vs_current_rows", "mean_test_delta_vs_pricefm"],
        ascending=[False, False, True],
    )


def build_horizon_failure_audit(stage_u_horizon, stage_w_horizon):
    rows = []
    u = stage_u_horizon.copy()
    if not u.empty:
        require_columns(u, ["region", "fold", "worst_horizon_group", "horizon_AQL_range"], "Stage-U horizon")
        for _, row in u.iterrows():
            rows.append({
                "region": str(row["region"]),
                "fold": int(row["fold"]),
                "source": "stage_u_surface",
                "worst_horizon_group": row.get("worst_horizon_group", ""),
                "horizon_AQL_range": as_float(row.get("horizon_AQL_range")),
                "validation_test_regret_vs_oracle": float("nan"),
            })
    w = stage_w_horizon.copy()
    if not w.empty:
        require_columns(w, ["region", "fold", "horizon_group", "validation_test_regret_vs_oracle"], "Stage-W horizon")
        agg = (
            w.sort_values(["region", "fold", "validation_test_regret_vs_oracle"], ascending=[True, True, False])
            .groupby(["region", "fold"], sort=True)
            .head(1)
        )
        for _, row in agg.iterrows():
            rows.append({
                "region": str(row["region"]),
                "fold": int(row["fold"]),
                "source": "stage_w_priority0",
                "worst_horizon_group": row.get("horizon_group", ""),
                "horizon_AQL_range": float("nan"),
                "validation_test_regret_vs_oracle": as_float(row.get("validation_test_regret_vs_oracle")),
            })
    return pd.DataFrame(rows)


def build_failure_modes(stage_m, stage_u_parity, stage_u_horizon, stage_w_transfer, stage_w_oracle):
    base = stage_m.copy()
    base["region"] = base["region"].astype(str)
    base["fold"] = pd.to_numeric(base["fold"], errors="raise").astype(int)
    base["current_AQL"] = numeric(base, "local_AQL")
    base["pricefm_AQL"] = numeric(base, "pricefm_AQL")
    base["current_delta_vs_pricefm"] = numeric(base, "delta_abs")
    parity_cols = ["region", "fold", "parity_status", "spatial_information_set", "n_active_regions"]
    parity = stage_u_parity[[col for col in parity_cols if col in stage_u_parity.columns]].copy()
    if not parity.empty:
        parity["region"] = parity["region"].astype(str)
        parity["fold"] = pd.to_numeric(parity["fold"], errors="raise").astype(int)
        base = base.merge(parity, on=["region", "fold"], how="left", suffixes=("", "_stage_u"))
    horizon_cols = ["region", "fold", "worst_horizon_group", "horizon_AQL_range"]
    horizon = stage_u_horizon[[col for col in horizon_cols if col in stage_u_horizon.columns]].copy()
    if not horizon.empty:
        horizon["region"] = horizon["region"].astype(str)
        horizon["fold"] = pd.to_numeric(horizon["fold"], errors="raise").astype(int)
        base = base.merge(horizon, on=["region", "fold"], how="left")

    transfer = stage_w_transfer.copy()
    if not transfer.empty:
        transfer["region"] = transfer["region"].astype(str)
        transfer["fold"] = pd.to_numeric(transfer["fold"], errors="raise").astype(int)
        base = base.merge(
            transfer[[
                "region", "fold", "test_regret_vs_oracle", "validation_test_spearman",
                "validation_selected_test_AQL", "test_oracle_test_AQL",
            ]],
            on=["region", "fold"],
            how="left",
        )
    oracle = stage_w_oracle.copy()
    if not oracle.empty:
        oracle["region"] = oracle["region"].astype(str)
        oracle["fold"] = pd.to_numeric(oracle["fold"], errors="raise").astype(int)
        oracle = oracle[["region", "fold", "test_AQL", "delta_vs_current_AQL", "delta_vs_pricefm_AQL"]].rename(
            columns={
                "test_AQL": "stage_w_oracle_test_AQL",
                "delta_vs_current_AQL": "stage_w_oracle_delta_vs_current",
                "delta_vs_pricefm_AQL": "stage_w_oracle_delta_vs_pricefm",
            }
        )
        base = base.merge(oracle, on=["region", "fold"], how="left")

    def label(row):
        delta = as_float(row.get("current_delta_vs_pricefm"))
        stage_w_oracle_delta = as_float(row.get("stage_w_oracle_delta_vs_current"))
        regret = as_float(row.get("test_regret_vs_oracle"))
        spearman = as_float(row.get("validation_test_spearman"))
        information = str(row.get("information_set", ""))
        horizon_range = as_float(row.get("horizon_AQL_range"))
        if math.isfinite(stage_w_oracle_delta) and stage_w_oracle_delta >= 0.0:
            return "candidate_family_falsified"
        if (math.isfinite(regret) and regret >= 1.0) or (math.isfinite(spearman) and spearman < 0.2):
            return "validation_transfer_failure"
        if delta > 0.0 and information == "target_only":
            return "graph_information_gap"
        if delta > 0.0 and math.isfinite(horizon_range) and horizon_range >= 7.0:
            return "late_horizon_failure"
        if delta > 1.0:
            return "pricefm_far_ahead"
        if delta > 0.0:
            return "minor_underperformance"
        return "current_qdesn_wins"

    def action(mode):
        return {
            "candidate_family_falsified": "do_not_relaunch_same_family",
            "validation_transfer_failure": "selection_contract_before_new_fits",
            "graph_information_gap": "consider_new_graph_adapter_after_selection_contract",
            "late_horizon_failure": "horizon_aware_rule_or_horizon_targeted_candidates",
            "pricefm_far_ahead": "defer_until_model_class_change",
            "minor_underperformance": "monitor_no_large_launch",
            "current_qdesn_wins": "no_action",
        }.get(mode, "review")

    base["primary_failure_mode"] = base.apply(label, axis=1)
    base["recommended_action"] = base["primary_failure_mode"].map(action)
    return base[[
        "region", "fold", "best_local_method", "information_set", "current_AQL",
        "pricefm_AQL", "current_delta_vs_pricefm", "worst_horizon_group",
        "horizon_AQL_range", "test_regret_vs_oracle", "validation_test_spearman",
        "stage_w_oracle_delta_vs_current", "stage_w_oracle_delta_vs_pricefm",
        "primary_failure_mode", "recommended_action",
    ]]


def build_recommended_actions(failure_modes, rule_audit, stage_w_summary):
    any_pricefm_rule = bool((rule_audit["test_improved_vs_pricefm_rows"] > 0).any()) if not rule_audit.empty else False
    stage_w_positive = int(stage_w_summary.get("test_oracle_beats_pricefm", 0)) > 0
    rows = []
    rows.append({
        "rank": 1,
        "action": "do_not_launch_stage_w_priority1",
        "decision": True,
        "justification": "Stage-W Priority 0 has zero validation-selected PriceFM wins and zero test-oracle PriceFM wins.",
    })
    rows.append({
        "rank": 2,
        "action": "freeze_stage_w_as_negative_evidence",
        "decision": True,
        "justification": "The run is clean, exact-equivalence checks passed, and the family failed scientifically.",
    })
    rows.append({
        "rank": 3,
        "action": "use_validation_only_horizon_stability_rule_for_next_design",
        "decision": not any_pricefm_rule,
        "justification": "Historical rules still do not beat PriceFM enough; use rules only to diagnose and narrow future searches.",
    })
    rows.append({
        "rank": 4,
        "action": "launch_new_model_fits_now",
        "decision": False,
        "justification": "No validation-only rule or Stage-W family currently justifies a new broad launch.",
    })
    rows.append({
        "rank": 5,
        "action": "design_stage_y_only_after_failure_mode_review",
        "decision": True,
        "justification": "New fits should target labeled failure modes rather than repeat graph/capacity sweeps.",
    })
    out = pd.DataFrame(rows)
    out["stage_w_has_pricefm_test_oracle_win"] = stage_w_positive
    out["n_candidate_family_falsified"] = int((failure_modes["primary_failure_mode"] == "candidate_family_falsified").sum())
    out["n_validation_transfer_failure"] = int((failure_modes["primary_failure_mode"] == "validation_transfer_failure").sum())
    return out


def write_report(path, summary, health, rule_audit, failure_modes, recommended, stage_w_transfer):
    lines = []
    lines.append("# PriceFM Stage-X Selection Failure Contract")
    lines.append("")
    lines.append("Stage X is diagnostic-only. It consolidates Stage-M/U/V/W evidence, evaluates validation-only rules, and uses test metrics only as audit evidence. It does not fit models, write launch grids, or mutate the Stage-M surface.")
    lines.append("")
    lines.append("## Health")
    lines.append("")
    lines.append(markdown_table(pd.DataFrame([health]).T.reset_index().rename(columns={"index": "field", 0: "value"})))
    lines.append("")
    lines.append("## Rule Audit")
    lines.append("")
    lines.append(markdown_table(
        rule_audit,
        [
            "rule_id", "n_region_folds", "selection_uses_test_metrics",
            "mean_test_delta_vs_current", "mean_test_delta_vs_pricefm",
            "test_improved_vs_current_rows", "test_improved_vs_pricefm_rows",
            "median_test_regret_vs_best_rule",
        ],
    ))
    lines.append("")
    lines.append("## Stage-W Transfer Reminder")
    lines.append("")
    lines.append(markdown_table(
        stage_w_transfer,
        [
            "region", "fold", "validation_selected_test_AQL", "test_oracle_test_AQL",
            "test_regret_vs_oracle", "validation_test_spearman",
        ],
    ))
    lines.append("")
    lines.append("## Failure Modes")
    lines.append("")
    lines.append(markdown_table(
        failure_modes.sort_values(["current_delta_vs_pricefm"], ascending=False),
        [
            "region", "fold", "information_set", "current_delta_vs_pricefm",
            "worst_horizon_group", "horizon_AQL_range", "test_regret_vs_oracle",
            "validation_test_spearman", "primary_failure_mode", "recommended_action",
        ],
        max_rows=42,
    ))
    lines.append("")
    lines.append("## Recommended Actions")
    lines.append("")
    lines.append(markdown_table(recommended, ["rank", "action", "decision", "justification"]))
    lines.append("")
    lines.append("## Decision")
    lines.append("")
    if summary["launch_new_fits_now"]:
        lines.append("A new fit launch may be considered only after manually reviewing the validation-only rule behavior.")
    else:
        lines.append("Do not launch new model fits from this stage. Freeze Stage-W as negative evidence, keep Stage-M unchanged, and design any Stage-Y launch only after reviewing the failure-mode labels.")
    lines.append("")
    repo_path(path).write_text("\n".join(lines) + "\n")


def build_health(input_manifest, stage_m, evidence, rule_audit, failure_modes, stage_w_summary):
    state = repo_state()
    return {
        "diagnostic_only": True,
        "fits_models": False,
        "writes_launch_configs": False,
        "stage_m_surface_changed": False,
        "selection_uses_test_metrics_any": bool(rule_audit["selection_uses_test_metrics"].map(bool_value).any()) if not rule_audit.empty else False,
        "stage_m_rows": int(len(stage_m)),
        "candidate_evidence_rows": int(len(evidence)),
        "rule_rows": int(len(rule_audit)),
        "failure_mode_rows": int(len(failure_modes)),
        "stage_w_run_clean": bool(stage_w_summary.get("run_clean", False)),
        "stage_w_priority1_recommended": bool(stage_w_summary.get("priority1_recommended", True)),
        "repo_branch": state["repo_branch"],
        "repo_head": state["repo_head"],
        "repo_dirty": state["repo_dirty"],
        "input_manifest_rows": int(len(input_manifest)),
    }


def design(args):
    output_dir = repo_path(args.output_dir)
    if output_dir.exists() and any(output_dir.iterdir()) and not args.force:
        raise FileExistsError("{} already exists; re-run with --force true".format(output_dir))
    output_dir.mkdir(parents=True, exist_ok=True)

    stage_m = read_csv_required(args.stage_m_surface_csv, "Stage-M surface")
    stage_u_summary = read_json_required(args.stage_u_summary_json, "Stage-U summary")
    stage_u_parity = read_csv_required(args.stage_u_row_parity_csv, "Stage-U row parity")
    stage_u_horizon = read_csv_required(args.stage_u_horizon_csv, "Stage-U horizon")
    stage_v_summary = read_json_required(args.stage_v_summary_json, "Stage-V summary")
    stage_v_candidates = read_csv_required(args.stage_v_candidate_universe_csv, "Stage-V candidate universe")
    stage_v_rule_audit = read_csv_required(args.stage_v_rule_audit_csv, "Stage-V rule audit")
    stage_w_summary = read_json_required(args.stage_w_summary_json, "Stage-W summary")
    stage_w_qdesn = read_csv_required(args.stage_w_qdesn_metrics_csv, "Stage-W Q-DESN metrics")
    stage_w_transfer = read_csv_required(args.stage_w_validation_transfer_csv, "Stage-W validation transfer")
    stage_w_oracle = read_csv_required(args.stage_w_test_oracle_csv, "Stage-W test oracle")
    stage_w_horizon = read_csv_required(args.stage_w_horizon_gap_csv, "Stage-W horizon")
    validate_upstream(args, stage_m, stage_u_summary, stage_v_summary, stage_w_summary)

    input_manifest = build_input_manifest(args)
    evidence = build_candidate_evidence(stage_v_candidates, stage_w_qdesn)
    definitions = validation_rule_definitions()
    assert_rules_are_validation_only(definitions)
    selected_rows = select_by_rule(evidence[evidence["evidence_source"].eq("stage_v_candidate_universe")].copy(), definitions)
    rule_audit = build_rule_audit(selected_rows)
    if "selection_uses_test_metrics" in stage_v_rule_audit.columns and stage_v_rule_audit["selection_uses_test_metrics"].map(bool_value).any():
        raise ValueError("Stage-V rule audit contains test-using rules.")
    horizon_audit = build_horizon_failure_audit(stage_u_horizon, stage_w_horizon)
    failure_modes = build_failure_modes(stage_m, stage_u_parity, stage_u_horizon, stage_w_transfer, stage_w_oracle)
    recommended = build_recommended_actions(failure_modes, rule_audit, stage_w_summary)
    health = build_health(input_manifest, stage_m, evidence, rule_audit, failure_modes, stage_w_summary)
    if health["selection_uses_test_metrics_any"]:
        raise ValueError("Stage-X produced a test-using selection rule.")

    summary = {
        "status": "completed",
        "output_dir": config_path_value(output_dir),
        "diagnostic_only": True,
        "fits_models": False,
        "writes_launch_configs": False,
        "stage_m_surface_changed": False,
        "selection_uses_test_metrics_any": False,
        "candidate_evidence_rows": int(len(evidence)),
        "rule_audit_rows": int(len(rule_audit)),
        "failure_mode_rows": int(len(failure_modes)),
        "stage_w_priority1_recommended": False,
        "launch_new_fits_now": False,
        "recommended_next_stage": "manual_review_stage_x_then_design_narrow_stage_y_if_needed",
    }

    write_frame(output_dir / "stage_x_input_manifest.csv", input_manifest)
    write_frame(output_dir / "stage_x_candidate_evidence.csv", evidence)
    write_frame(output_dir / "stage_x_selection_rule_definitions.csv", definitions)
    write_frame(output_dir / "stage_x_rule_selected_rows.csv", selected_rows)
    write_frame(output_dir / "stage_x_selection_rule_audit.csv", rule_audit)
    write_frame(output_dir / "stage_x_region_fold_failure_modes.csv", failure_modes)
    write_frame(output_dir / "stage_x_horizon_failure_audit.csv", horizon_audit)
    write_frame(output_dir / "stage_x_recommended_actions.csv", recommended)
    write_report(
        output_dir / "stage_x_report.md",
        summary,
        health,
        rule_audit,
        failure_modes,
        recommended,
        stage_w_transfer,
    )
    summary["outputs"] = {
        "input_manifest_csv": config_path_value(output_dir / "stage_x_input_manifest.csv"),
        "candidate_evidence_csv": config_path_value(output_dir / "stage_x_candidate_evidence.csv"),
        "selection_rule_definitions_csv": config_path_value(output_dir / "stage_x_selection_rule_definitions.csv"),
        "rule_selected_rows_csv": config_path_value(output_dir / "stage_x_rule_selected_rows.csv"),
        "selection_rule_audit_csv": config_path_value(output_dir / "stage_x_selection_rule_audit.csv"),
        "region_fold_failure_modes_csv": config_path_value(output_dir / "stage_x_region_fold_failure_modes.csv"),
        "horizon_failure_audit_csv": config_path_value(output_dir / "stage_x_horizon_failure_audit.csv"),
        "recommended_actions_csv": config_path_value(output_dir / "stage_x_recommended_actions.csv"),
        "report_md": config_path_value(output_dir / "stage_x_report.md"),
    }
    write_json(output_dir / "summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main():
    return design(parser().parse_args())


if __name__ == "__main__":
    main()
