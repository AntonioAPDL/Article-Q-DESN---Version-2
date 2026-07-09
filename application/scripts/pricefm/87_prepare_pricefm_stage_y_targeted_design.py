#!/usr/bin/env python3
"""Prepare the Stage-Y PriceFM targeted design manifest.

Stage Y is a planning gate after Stage X.  It converts Stage-X failure labels
into explicit design lanes, estimates the cost of possible future work, and
records which rows are blocked or eligible for manual review.  It does not fit
models, write launch grids, mutate Stage-M, or start background jobs.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, repo_path, sha256_file, write_json


DEFAULT_STAGE_X_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_x_selection_failure_contract_20260630"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_y_targeted_design_20260630"
)


LANE_CONTRACTS = [
    {
        "stage_y_lane": "exclude_falsified_stage_w_family",
        "failure_modes": ["candidate_family_falsified"],
        "launch_ready": False,
        "requires_new_code": False,
        "requires_manual_approval": False,
        "future_experiments_per_row_if_approved": 0,
        "role": "Do not relaunch Stage-W graph/input/geometry family for this row.",
    },
    {
        "stage_y_lane": "defer_model_class_change",
        "failure_modes": ["pricefm_far_ahead"],
        "launch_ready": False,
        "requires_new_code": True,
        "requires_manual_approval": True,
        "future_experiments_per_row_if_approved": 0,
        "role": "Defer until a model-class or data-information change is justified.",
    },
    {
        "stage_y_lane": "graph_adapter_contract_design",
        "failure_modes": ["graph_information_gap"],
        "launch_ready": False,
        "requires_new_code": True,
        "requires_manual_approval": True,
        "future_experiments_per_row_if_approved": 12,
        "role": "Design a genuinely new graph adapter; current graph_khop/summary variants are insufficient.",
    },
    {
        "stage_y_lane": "horizon_targeted_design",
        "failure_modes": ["late_horizon_failure"],
        "launch_ready": False,
        "requires_new_code": False,
        "requires_manual_approval": True,
        "future_experiments_per_row_if_approved": 8,
        "role": "Design a narrow future grid around late-horizon weakness and validation-only horizon selection.",
    },
    {
        "stage_y_lane": "monitor_no_large_launch",
        "failure_modes": ["minor_underperformance"],
        "launch_ready": False,
        "requires_new_code": False,
        "requires_manual_approval": True,
        "future_experiments_per_row_if_approved": 0,
        "role": "Monitor or include only if a broader approved mechanism directly covers the row.",
    },
    {
        "stage_y_lane": "no_action_current_qdesn_wins",
        "failure_modes": ["current_qdesn_wins"],
        "launch_ready": False,
        "requires_new_code": False,
        "requires_manual_approval": False,
        "future_experiments_per_row_if_approved": 0,
        "role": "Current Q-DESN already beats cached PriceFM; keep unchanged.",
    },
]


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-x-dir", default=DEFAULT_STAGE_X_DIR)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--force", type=parse_bool, default=True)
    p.add_argument("--max-proposed-future-experiments", type=int, default=120)
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


def stage_x_path(stage_x_dir, filename):
    return repo_path(Path(stage_x_dir) / filename)


def input_specs(args):
    sx = args.stage_x_dir
    return [
        ("stage_x_summary", stage_x_path(sx, "summary.json"), "json", "Stage-X summary"),
        ("stage_x_input_manifest", stage_x_path(sx, "stage_x_input_manifest.csv"), "csv", "Stage-X input hashes"),
        ("stage_x_failure_modes", stage_x_path(sx, "stage_x_region_fold_failure_modes.csv"), "csv", "Stage-X row labels"),
        ("stage_x_rule_audit", stage_x_path(sx, "stage_x_selection_rule_audit.csv"), "csv", "Stage-X validation-only rule audit"),
        ("stage_x_recommended_actions", stage_x_path(sx, "stage_x_recommended_actions.csv"), "csv", "Stage-X recommendations"),
        ("stage_x_horizon_audit", stage_x_path(sx, "stage_x_horizon_failure_audit.csv"), "csv", "Stage-X horizon audit"),
        ("stage_x_candidate_evidence", stage_x_path(sx, "stage_x_candidate_evidence.csv"), "csv", "Stage-X candidate evidence"),
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


def validate_stage_x(summary, rule_audit, recommendations):
    if not bool_value(summary.get("diagnostic_only", False)):
        raise ValueError("Stage-X must be diagnostic-only.")
    if bool_value(summary.get("fits_models", True)):
        raise ValueError("Stage-X must not fit models.")
    if bool_value(summary.get("writes_launch_configs", True)):
        raise ValueError("Stage-X must not write launch configs.")
    if bool_value(summary.get("stage_m_surface_changed", True)):
        raise ValueError("Stage-X must not mutate Stage-M.")
    if bool_value(summary.get("selection_uses_test_metrics_any", True)):
        raise ValueError("Stage-X selection rules must be validation-only.")
    if bool_value(summary.get("launch_new_fits_now", True)):
        raise ValueError("Stage-X must not recommend immediate new fits.")
    if "selection_uses_test_metrics" in rule_audit.columns and rule_audit["selection_uses_test_metrics"].map(bool_value).any():
        raise ValueError("Stage-X rule audit includes a test-using rule.")
    launch = recommendations[recommendations["action"].astype(str).eq("launch_new_model_fits_now")]
    if not launch.empty and launch["decision"].map(bool_value).any():
        raise ValueError("Stage-X recommendations permit immediate new model fits.")


def lane_contract_frame():
    rows = []
    for contract in LANE_CONTRACTS:
        row = contract.copy()
        row["failure_modes"] = ",".join(contract["failure_modes"])
        rows.append(row)
    return pd.DataFrame(rows)


def lane_lookup():
    out = {}
    for contract in LANE_CONTRACTS:
        for mode in contract["failure_modes"]:
            out[mode] = contract
    return out


def build_design_manifest(failure_modes, horizon_audit):
    require_columns(
        failure_modes,
        ["region", "fold", "primary_failure_mode", "recommended_action", "current_delta_vs_pricefm"],
        "Stage-X failure modes",
    )
    lookup = lane_lookup()
    horizon_rank = build_horizon_rank(horizon_audit)
    rows = []
    for _, row in failure_modes.iterrows():
        mode = str(row["primary_failure_mode"])
        contract = lookup.get(mode, {
            "stage_y_lane": "manual_review",
            "launch_ready": False,
            "requires_new_code": True,
            "requires_manual_approval": True,
            "future_experiments_per_row_if_approved": 0,
            "role": "Unrecognized failure mode; manual review required.",
        })
        region = str(row["region"])
        fold = int(row["fold"])
        hkey = "{}::{}".format(region, fold)
        future_experiments = int(contract["future_experiments_per_row_if_approved"])
        priority = stage_y_priority(mode, as_float(row.get("current_delta_vs_pricefm")), as_float(row.get("horizon_AQL_range")))
        rows.append({
            "region": region,
            "fold": fold,
            "stage_x_failure_mode": mode,
            "stage_x_recommended_action": row.get("recommended_action", ""),
            "stage_y_lane": contract["stage_y_lane"],
            "stage_y_priority": priority,
            "launch_ready": bool(contract["launch_ready"]),
            "fits_models_now": False,
            "writes_launch_config_now": False,
            "requires_new_code": bool(contract["requires_new_code"]),
            "requires_manual_approval": bool(contract["requires_manual_approval"]),
            "future_experiments_per_row_if_approved": future_experiments,
            "future_experiment_budget_if_approved": future_experiments,
            "current_AQL": as_float(row.get("current_AQL")),
            "pricefm_AQL": as_float(row.get("pricefm_AQL")),
            "current_delta_vs_pricefm": as_float(row.get("current_delta_vs_pricefm")),
            "information_set": row.get("information_set", ""),
            "worst_horizon_group": row.get("worst_horizon_group", ""),
            "horizon_AQL_range": as_float(row.get("horizon_AQL_range")),
            "horizon_rank": horizon_rank.get(hkey, ""),
            "blocked_by": blocked_by(mode),
            "rationale": contract["role"],
        })
    return pd.DataFrame(rows).sort_values(
        ["stage_y_priority", "current_delta_vs_pricefm", "region", "fold"],
        ascending=[True, False, True, True],
        na_position="last",
    )


def stage_y_priority(mode, delta, horizon_range):
    if mode == "late_horizon_failure":
        return 0
    if mode == "graph_information_gap":
        return 1
    if mode == "minor_underperformance":
        return 2
    if mode == "candidate_family_falsified":
        return 3
    if mode == "pricefm_far_ahead":
        return 4
    if mode == "current_qdesn_wins":
        return 9
    return 8


def blocked_by(mode):
    if mode == "candidate_family_falsified":
        return "Stage-W family failed both validation-selected and test-oracle PriceFM gates."
    if mode == "pricefm_far_ahead":
        return "Requires model-class or information-set change, not another local sweep."
    if mode == "graph_information_gap":
        return "Requires new graph adapter contract before any launch grid is valid."
    if mode == "late_horizon_failure":
        return "Requires manual approval of a narrow horizon-targeted candidate design."
    if mode == "minor_underperformance":
        return "Insufficient benefit for a large launch."
    if mode == "current_qdesn_wins":
        return "No action because current Q-DESN beats cached PriceFM."
    return "Manual review required."


def build_horizon_rank(horizon_audit):
    if horizon_audit.empty or "horizon_AQL_range" not in horizon_audit.columns:
        return {}
    surf = horizon_audit[horizon_audit["source"].astype(str).eq("stage_u_surface")].copy()
    if surf.empty:
        return {}
    surf["horizon_AQL_range"] = numeric(surf, "horizon_AQL_range")
    surf = surf.sort_values(["horizon_AQL_range", "region", "fold"], ascending=[False, True, True])
    out = {}
    for i, (_, row) in enumerate(surf.iterrows(), start=1):
        out["{}::{}".format(row["region"], int(row["fold"]))] = i
    return out


def build_cost_estimate(design):
    rows = []
    for lane, sub in design.groupby("stage_y_lane", sort=True):
        rows.append({
            "stage_y_lane": lane,
            "n_rows": int(len(sub)),
            "launch_ready_rows": int(sub["launch_ready"].map(bool_value).sum()),
            "future_experiment_budget_if_approved": int(sub["future_experiment_budget_if_approved"].sum()),
            "requires_new_code_rows": int(sub["requires_new_code"].map(bool_value).sum()),
            "requires_manual_approval_rows": int(sub["requires_manual_approval"].map(bool_value).sum()),
        })
    total = {
        "stage_y_lane": "TOTAL",
        "n_rows": int(len(design)),
        "launch_ready_rows": int(design["launch_ready"].map(bool_value).sum()),
        "future_experiment_budget_if_approved": int(design["future_experiment_budget_if_approved"].sum()),
        "requires_new_code_rows": int(design["requires_new_code"].map(bool_value).sum()),
        "requires_manual_approval_rows": int(design["requires_manual_approval"].map(bool_value).sum()),
    }
    rows.append(total)
    return pd.DataFrame(rows)


def build_stage_y_decision(design, cost, max_proposed_future_experiments):
    total = cost[cost["stage_y_lane"].eq("TOTAL")].iloc[0]
    future_budget = int(total["future_experiment_budget_if_approved"])
    launch_ready_rows = int(total["launch_ready_rows"])
    return pd.DataFrame([
        {
            "decision_id": "no_immediate_launch",
            "decision": True,
            "reason": "Stage-X forbids immediate new fits and Stage-Y has zero launch-ready rows.",
        },
        {
            "decision_id": "do_not_relaunch_stage_w_family",
            "decision": bool((design["stage_y_lane"] == "exclude_falsified_stage_w_family").any()),
            "reason": "Rows marked candidate_family_falsified are explicitly excluded.",
        },
        {
            "decision_id": "future_budget_requires_manual_review",
            "decision": future_budget > 0,
            "reason": "Future hypothetical budget is {} experiments; cap is {}.".format(
                future_budget, max_proposed_future_experiments
            ),
        },
        {
            "decision_id": "future_budget_within_cap_if_approved",
            "decision": future_budget <= max_proposed_future_experiments,
            "reason": "Hypothetical future budget is an estimate, not a launch authorization.",
        },
        {
            "decision_id": "launch_ready_rows",
            "decision": launch_ready_rows > 0,
            "reason": "{} rows are currently launch-ready.".format(launch_ready_rows),
        },
    ])


def build_analysis_by_point(design, rule_audit):
    rows = []
    best_rule = rule_audit.sort_values(
        ["test_improved_vs_pricefm_rows", "test_improved_vs_current_rows", "mean_test_delta_vs_pricefm"],
        ascending=[False, False, True],
    ).head(1)
    rows.append({
        "point": "selection_contract",
        "diagnosis": "Best historical validation-only rule is {}.".format(best_rule["rule_id"].iloc[0] if not best_rule.empty else "unavailable"),
        "decision": "Use for audit and future narrowing only; not enough to launch.",
    })
    for lane, sub in design.groupby("stage_y_lane", sort=True):
        rows.append({
            "point": lane,
            "diagnosis": "{} row(s); future budget {}.".format(len(sub), int(sub["future_experiment_budget_if_approved"].sum())),
            "decision": lane_decision(lane),
        })
    return pd.DataFrame(rows)


def lane_decision(lane):
    return {
        "exclude_falsified_stage_w_family": "Block same-family relaunch.",
        "defer_model_class_change": "Defer until a new model/information contract exists.",
        "graph_adapter_contract_design": "Plan adapter contract; no grid until code/data contract exists.",
        "horizon_targeted_design": "Potential narrow Stage-Y candidate after manual review.",
        "monitor_no_large_launch": "No large launch.",
        "no_action_current_qdesn_wins": "Keep current row.",
    }.get(lane, "Manual review.")


def write_report(path, summary, design, cost, decisions, analysis):
    lines = []
    lines.append("# PriceFM Stage-Y Targeted Design")
    lines.append("")
    lines.append("Stage Y is a non-launch planning gate. It translates Stage-X failure labels into design lanes, estimates hypothetical future work, and blocks families that have already failed.")
    lines.append("")
    lines.append("## Health")
    lines.append("")
    health_cols = {
        "diagnostic_only": summary["diagnostic_only"],
        "fits_models": summary["fits_models"],
        "writes_launch_configs": summary["writes_launch_configs"],
        "stage_m_surface_changed": summary["stage_m_surface_changed"],
        "launch_ready_rows": summary["launch_ready_rows"],
        "future_experiment_budget_if_approved": summary["future_experiment_budget_if_approved"],
        "repo_head": summary["repo_head"],
        "repo_dirty": summary["repo_dirty"],
    }
    lines.append(markdown_table(pd.DataFrame([health_cols]).T.reset_index().rename(columns={"index": "field", 0: "value"})))
    lines.append("")
    lines.append("## Lane Cost Estimate")
    lines.append("")
    lines.append(markdown_table(cost))
    lines.append("")
    lines.append("## Design Manifest")
    lines.append("")
    lines.append(markdown_table(
        design,
        [
            "region", "fold", "stage_x_failure_mode", "stage_y_lane",
            "stage_y_priority", "launch_ready", "future_experiment_budget_if_approved",
            "current_delta_vs_pricefm", "worst_horizon_group", "blocked_by",
        ],
        max_rows=42,
    ))
    lines.append("")
    lines.append("## Decisions")
    lines.append("")
    lines.append(markdown_table(decisions))
    lines.append("")
    lines.append("## Analysis By Point")
    lines.append("")
    lines.append(markdown_table(analysis))
    lines.append("")
    lines.append("## Next Step")
    lines.append("")
    lines.append("Review this design manifest manually. If a future launch is authorized, start with a narrow horizon-targeted design or a new graph-adapter contract; do not relaunch the Stage-W family.")
    lines.append("")
    repo_path(path).write_text("\n".join(lines))


def prepare(args):
    output_dir = repo_path(args.output_dir)
    if output_dir.exists() and any(output_dir.iterdir()) and not args.force:
        raise FileExistsError("{} already exists; re-run with --force true".format(output_dir))
    output_dir.mkdir(parents=True, exist_ok=True)

    stage_x_summary = read_json_required(stage_x_path(args.stage_x_dir, "summary.json"), "Stage-X summary")
    failure_modes = read_csv_required(stage_x_path(args.stage_x_dir, "stage_x_region_fold_failure_modes.csv"), "Stage-X failure modes")
    rule_audit = read_csv_required(stage_x_path(args.stage_x_dir, "stage_x_selection_rule_audit.csv"), "Stage-X rule audit")
    recommended = read_csv_required(stage_x_path(args.stage_x_dir, "stage_x_recommended_actions.csv"), "Stage-X recommended actions")
    horizon_audit = read_csv_required(stage_x_path(args.stage_x_dir, "stage_x_horizon_failure_audit.csv"), "Stage-X horizon audit")
    candidate_evidence = read_csv_required(stage_x_path(args.stage_x_dir, "stage_x_candidate_evidence.csv"), "Stage-X candidate evidence")
    validate_stage_x(stage_x_summary, rule_audit, recommended)

    input_manifest = build_input_manifest(args)
    lane_contract = lane_contract_frame()
    design = build_design_manifest(failure_modes, horizon_audit)
    cost = build_cost_estimate(design)
    decisions = build_stage_y_decision(design, cost, args.max_proposed_future_experiments)
    analysis = build_analysis_by_point(design, rule_audit)
    state = repo_state()
    total = cost[cost["stage_y_lane"].eq("TOTAL")].iloc[0]
    launch_ready_rows = int(total["launch_ready_rows"])
    future_budget = int(total["future_experiment_budget_if_approved"])
    summary = {
        "status": "completed",
        "output_dir": config_path_value(output_dir),
        "diagnostic_only": True,
        "fits_models": False,
        "writes_launch_configs": False,
        "stage_m_surface_changed": False,
        "launch_ready_rows": launch_ready_rows,
        "launch_new_fits_now": False,
        "future_experiment_budget_if_approved": future_budget,
        "future_budget_within_cap_if_approved": future_budget <= args.max_proposed_future_experiments,
        "design_rows": int(len(design)),
        "candidate_evidence_rows_read": int(len(candidate_evidence)),
        "recommended_next_stage": "manual_review_stage_y_then_authorize_narrow_stage_z_or_stop",
        "repo_branch": state["repo_branch"],
        "repo_head": state["repo_head"],
        "repo_dirty": state["repo_dirty"],
    }

    write_frame(output_dir / "stage_y_input_manifest.csv", input_manifest)
    write_frame(output_dir / "stage_y_lane_contract.csv", lane_contract)
    write_frame(output_dir / "stage_y_design_manifest.csv", design)
    write_frame(output_dir / "stage_y_cost_estimate.csv", cost)
    write_frame(output_dir / "stage_y_decisions.csv", decisions)
    write_frame(output_dir / "stage_y_analysis_by_point.csv", analysis)
    write_report(output_dir / "stage_y_report.md", summary, design, cost, decisions, analysis)
    summary["outputs"] = {
        "input_manifest_csv": config_path_value(output_dir / "stage_y_input_manifest.csv"),
        "lane_contract_csv": config_path_value(output_dir / "stage_y_lane_contract.csv"),
        "design_manifest_csv": config_path_value(output_dir / "stage_y_design_manifest.csv"),
        "cost_estimate_csv": config_path_value(output_dir / "stage_y_cost_estimate.csv"),
        "decisions_csv": config_path_value(output_dir / "stage_y_decisions.csv"),
        "analysis_by_point_csv": config_path_value(output_dir / "stage_y_analysis_by_point.csv"),
        "report_md": config_path_value(output_dir / "stage_y_report.md"),
    }
    write_json(output_dir / "summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main():
    return prepare(parser().parse_args())


if __name__ == "__main__":
    main()
