#!/usr/bin/env python3
"""Prepare Stage-Z PriceFM design contracts.

Stage Z is a diagnostic contract pass after Stage Y. It performs the manual
review mechanically: it separates the one horizon-targeted row from the graph
adapter rows, records why the other rows should not launch, and keeps every
launch gate closed. It does not fit models, write launch grids, mutate the
Stage-M surface, or start background jobs.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, repo_path, sha256_file, write_json


DEFAULT_STAGE_Y_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_y_targeted_design_20260630"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_z_design_contracts_20260630"
)

HORIZON_LANE = "horizon_targeted_design"
GRAPH_LANE = "graph_adapter_contract_design"
BLOCKED_LANES = {
    "exclude_falsified_stage_w_family": "blocked_stage_w_family",
    "defer_model_class_change": "blocked_model_class_change",
    "no_action_current_qdesn_wins": "blocked_current_qdesn_wins",
}
MONITOR_LANE = "monitor_no_large_launch"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-y-dir", default=DEFAULT_STAGE_Y_DIR)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--force", type=parse_bool, default=True)
    p.add_argument("--max-horizon-contract-rows", type=int, default=1)
    p.add_argument("--max-graph-contract-rows", type=int, default=12)
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def stage_y_path(stage_y_dir, filename):
    return repo_path(Path(stage_y_dir) / filename)


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
    sy = args.stage_y_dir
    return [
        ("stage_y_summary", stage_y_path(sy, "summary.json"), "json", "Stage-Y summary"),
        ("stage_y_input_manifest", stage_y_path(sy, "stage_y_input_manifest.csv"), "csv", "Stage-Y input hashes"),
        ("stage_y_lane_contract", stage_y_path(sy, "stage_y_lane_contract.csv"), "csv", "Stage-Y lane contracts"),
        ("stage_y_design_manifest", stage_y_path(sy, "stage_y_design_manifest.csv"), "csv", "Stage-Y row design manifest"),
        ("stage_y_cost_estimate", stage_y_path(sy, "stage_y_cost_estimate.csv"), "csv", "Stage-Y cost estimate"),
        ("stage_y_decisions", stage_y_path(sy, "stage_y_decisions.csv"), "csv", "Stage-Y decisions"),
        ("stage_y_analysis_by_point", stage_y_path(sy, "stage_y_analysis_by_point.csv"), "csv", "Stage-Y analysis by lane"),
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


def validate_stage_y(summary, design, decisions):
    if not bool_value(summary.get("diagnostic_only", False)):
        raise ValueError("Stage-Y must be diagnostic-only.")
    if bool_value(summary.get("fits_models", True)):
        raise ValueError("Stage-Y must not fit models.")
    if bool_value(summary.get("writes_launch_configs", True)):
        raise ValueError("Stage-Y must not write launch configs.")
    if bool_value(summary.get("stage_m_surface_changed", True)):
        raise ValueError("Stage-Y must not mutate Stage-M.")
    if bool_value(summary.get("launch_new_fits_now", True)):
        raise ValueError("Stage-Y must not recommend immediate fits.")
    if int(summary.get("launch_ready_rows", 0)) != 0:
        raise ValueError("Stage-Y must have zero launch-ready rows.")

    require_columns(
        design,
        [
            "region", "fold", "stage_x_failure_mode", "stage_y_lane",
            "launch_ready", "fits_models_now", "writes_launch_config_now",
            "future_experiment_budget_if_approved", "current_delta_vs_pricefm",
        ],
        "Stage-Y design manifest",
    )
    for col in ("launch_ready", "fits_models_now", "writes_launch_config_now"):
        if design[col].map(bool_value).any():
            raise ValueError("Stage-Y design contains true values in {}.".format(col))

    if "decision_id" in decisions.columns and "decision" in decisions.columns:
        launch = decisions[decisions["decision_id"].astype(str).eq("launch_ready_rows")]
        if not launch.empty and launch["decision"].map(bool_value).any():
            raise ValueError("Stage-Y decisions report launch-ready rows.")


def build_track_contract(design):
    rows = []
    track_specs = [
        {
            "track_id": "horizon_targeted_contract",
            "lane": HORIZON_LANE,
            "track_status": "eligible_for_manual_approval_only",
            "preserves_current_code": True,
            "requires_new_code": False,
            "launch_ready": False,
            "role": "Define a narrow horizon-aware design for the one late-horizon row.",
        },
        {
            "track_id": "graph_adapter_contract",
            "lane": GRAPH_LANE,
            "track_status": "requires_adapter_contract_before_launch",
            "preserves_current_code": False,
            "requires_new_code": True,
            "launch_ready": False,
            "role": "Define a new information-set adapter before any graph launch.",
        },
        {
            "track_id": "blocked_stage_w_family",
            "lane": "exclude_falsified_stage_w_family",
            "track_status": "blocked",
            "preserves_current_code": True,
            "requires_new_code": False,
            "launch_ready": False,
            "role": "Do not relaunch the falsified Stage-W candidate family.",
        },
        {
            "track_id": "blocked_model_class_change",
            "lane": "defer_model_class_change",
            "track_status": "blocked_until_new_model_class",
            "preserves_current_code": False,
            "requires_new_code": True,
            "launch_ready": False,
            "role": "Do not run another local sweep for PriceFM-far-ahead rows.",
        },
        {
            "track_id": "monitor_no_large_launch",
            "lane": MONITOR_LANE,
            "track_status": "monitor",
            "preserves_current_code": True,
            "requires_new_code": False,
            "launch_ready": False,
            "role": "Track minor underperformance; do not spend a large launch.",
        },
        {
            "track_id": "blocked_current_qdesn_wins",
            "lane": "no_action_current_qdesn_wins",
            "track_status": "blocked_no_action_needed",
            "preserves_current_code": True,
            "requires_new_code": False,
            "launch_ready": False,
            "role": "Current Q-DESN already beats cached PriceFM.",
        },
    ]
    for spec in track_specs:
        sub = design[design["stage_y_lane"].astype(str).eq(spec["lane"])]
        rows.append({
            "track_id": spec["track_id"],
            "stage_y_lane": spec["lane"],
            "n_rows": int(len(sub)),
            "future_experiment_budget_if_approved": int(pd.to_numeric(
                sub.get("future_experiment_budget_if_approved", pd.Series(dtype=float)),
                errors="coerce",
            ).fillna(0).sum()),
            "track_status": spec["track_status"],
            "launch_ready": spec["launch_ready"],
            "fits_models_now": False,
            "writes_launch_config_now": False,
            "preserves_current_code": spec["preserves_current_code"],
            "requires_new_code": spec["requires_new_code"],
            "requires_manual_approval": spec["track_id"] in (
                "horizon_targeted_contract",
                "graph_adapter_contract",
            ),
            "role": spec["role"],
        })
    return pd.DataFrame(rows)


def common_contract_row(row):
    return {
        "region": str(row["region"]),
        "fold": int(row["fold"]),
        "stage_x_failure_mode": str(row["stage_x_failure_mode"]),
        "stage_y_lane": str(row["stage_y_lane"]),
        "current_AQL": as_float(row.get("current_AQL")),
        "pricefm_AQL": as_float(row.get("pricefm_AQL")),
        "current_delta_vs_pricefm": as_float(row.get("current_delta_vs_pricefm")),
        "worst_horizon_group": row.get("worst_horizon_group", ""),
        "horizon_AQL_range": as_float(row.get("horizon_AQL_range")),
        "information_set": row.get("information_set", ""),
        "future_experiment_budget_if_approved": int(as_float(row.get("future_experiment_budget_if_approved"), 0)),
        "launch_ready": False,
        "fits_models_now": False,
        "writes_launch_config_now": False,
    }


def build_horizon_contract(design):
    sub = design[design["stage_y_lane"].astype(str).eq(HORIZON_LANE)].copy()
    rows = []
    for _, row in sub.iterrows():
        out = common_contract_row(row)
        out.update({
            "contract_id": "{}_fold{}_horizon_targeted".format(out["region"], out["fold"]),
            "targeted_horizon_group": row.get("worst_horizon_group", ""),
            "selection_rule_family": "validation_only_horizon_aware",
            "primary_selection_rule": "val_max_horizon_min",
            "test_metrics_role": "audit_only_after_fit",
            "candidate_family": "horizon_targeted_qdesn_design",
            "allowed_future_scope": "narrow_ro_fold3_only",
            "requires_new_code": False,
            "requires_manual_approval": True,
            "guardrail": "Use validation-only horizon criteria; compare test metrics only after selection.",
        })
        rows.append(out)
    cols = [
        "contract_id", "region", "fold", "stage_x_failure_mode", "stage_y_lane",
        "current_AQL", "pricefm_AQL", "current_delta_vs_pricefm",
        "targeted_horizon_group", "horizon_AQL_range", "information_set",
        "selection_rule_family", "primary_selection_rule", "test_metrics_role",
        "candidate_family", "allowed_future_scope",
        "future_experiment_budget_if_approved", "requires_new_code",
        "requires_manual_approval", "launch_ready", "fits_models_now",
        "writes_launch_config_now", "guardrail",
    ]
    return pd.DataFrame(rows, columns=cols)


def build_graph_contract(design):
    sub = design[design["stage_y_lane"].astype(str).eq(GRAPH_LANE)].copy()
    rows = []
    for _, row in sub.iterrows():
        out = common_contract_row(row)
        out.update({
            "contract_id": "{}_fold{}_graph_adapter".format(out["region"], out["fold"]),
            "adapter_status": "contract_required_before_launch",
            "required_information_set": "neighbor_augmented_inputs",
            "current_adapter_is_sufficient": False,
            "must_differ_from": "graph_khop,graph_summary_only",
            "requires_new_code": True,
            "requires_manual_approval": True,
            "allowed_future_scope": "adapter_contract_then_small_smoke_before_grid",
            "guardrail": "Do not launch graph rows until the adapter has leakage tests and feature provenance manifests.",
        })
        rows.append(out)
    cols = [
        "contract_id", "region", "fold", "stage_x_failure_mode", "stage_y_lane",
        "current_AQL", "pricefm_AQL", "current_delta_vs_pricefm",
        "worst_horizon_group", "horizon_AQL_range", "information_set",
        "adapter_status", "required_information_set",
        "current_adapter_is_sufficient", "must_differ_from",
        "future_experiment_budget_if_approved", "requires_new_code",
        "requires_manual_approval", "launch_ready", "fits_models_now",
        "writes_launch_config_now", "allowed_future_scope", "guardrail",
    ]
    return pd.DataFrame(rows, columns=cols)


def build_blocked_rows(design):
    rows = []
    for _, row in design.iterrows():
        lane = str(row["stage_y_lane"])
        if lane in (HORIZON_LANE, GRAPH_LANE):
            continue
        out = common_contract_row(row)
        if lane == MONITOR_LANE:
            status = "monitor_not_launch_ready"
            reason = "Minor underperformance does not justify a dedicated broad launch."
        else:
            status = BLOCKED_LANES.get(lane, "blocked_manual_review")
            reason = row.get("blocked_by", "")
        out.update({
            "row_status": status,
            "blocked_or_monitor_reason": reason,
            "same_family_relaunch_allowed": False if lane == "exclude_falsified_stage_w_family" else "",
            "requires_new_code_before_reconsideration": lane == "defer_model_class_change",
        })
        rows.append(out)
    cols = [
        "region", "fold", "stage_x_failure_mode", "stage_y_lane",
        "row_status", "current_AQL", "pricefm_AQL", "current_delta_vs_pricefm",
        "worst_horizon_group", "horizon_AQL_range", "information_set",
        "future_experiment_budget_if_approved", "launch_ready", "fits_models_now",
        "writes_launch_config_now", "same_family_relaunch_allowed",
        "requires_new_code_before_reconsideration", "blocked_or_monitor_reason",
    ]
    return pd.DataFrame(rows, columns=cols)


def build_decision_gates(design, track, horizon, graph, blocked):
    launch_ready_rows = int(design["launch_ready"].map(bool_value).sum())
    future_budget = int(pd.to_numeric(
        design["future_experiment_budget_if_approved"],
        errors="coerce",
    ).fillna(0).sum())
    rows = [
        {
            "gate_id": "no_immediate_launch",
            "passed": True,
            "decision": "do_not_launch_now",
            "reason": "Stage Y and Stage Z are diagnostic/contract passes with zero launch-ready rows.",
        },
        {
            "gate_id": "zero_launch_ready_rows",
            "passed": launch_ready_rows == 0,
            "decision": "{} launch-ready rows".format(launch_ready_rows),
            "reason": "Any positive value would require stopping before Stage Z.",
        },
        {
            "gate_id": "choose_one_track_before_launch",
            "passed": True,
            "decision": "manual_choice_required",
            "reason": "Do not launch the horizon and graph tracks together.",
        },
        {
            "gate_id": "horizon_track_available",
            "passed": len(horizon) == 1,
            "decision": "{} horizon contract row(s)".format(len(horizon)),
            "reason": "The only narrow current-code track is RO fold 3.",
        },
        {
            "gate_id": "graph_track_requires_new_adapter",
            "passed": len(graph) > 0 and graph["requires_new_code"].map(bool_value).all(),
            "decision": "{} graph contract row(s)".format(len(graph)),
            "reason": "Graph rows require adapter design, leakage tests, and provenance before fitting.",
        },
        {
            "gate_id": "stage_w_family_relaunch_blocked",
            "passed": bool((blocked["stage_y_lane"] == "exclude_falsified_stage_w_family").any()),
            "decision": "blocked",
            "reason": "Stage-W Priority 0 falsified the same family for those rows.",
        },
        {
            "gate_id": "future_budget_is_not_authorization",
            "passed": future_budget >= 0,
            "decision": "{} hypothetical experiments".format(future_budget),
            "reason": "Budget is a planning estimate only; no grid is written.",
        },
    ]
    if track["launch_ready"].map(bool_value).any():
        raise ValueError("Stage-Z track contract unexpectedly includes launch-ready rows.")
    return pd.DataFrame(rows)


def write_report(path, summary, track, horizon, graph, blocked, gates):
    lines = []
    lines.append("# PriceFM Stage-Z Design Contracts")
    lines.append("")
    lines.append("Stage Z is a non-launch contract pass. It turns Stage-Y's manual-review lanes into explicit launch gates and keeps all model-fitting switches closed.")
    lines.append("")
    lines.append("## Health")
    lines.append("")
    health = {
        "diagnostic_only": summary["diagnostic_only"],
        "fits_models": summary["fits_models"],
        "writes_launch_configs": summary["writes_launch_configs"],
        "stage_m_surface_changed": summary["stage_m_surface_changed"],
        "launch_ready_rows": summary["launch_ready_rows"],
        "horizon_contract_rows": summary["horizon_contract_rows"],
        "graph_adapter_contract_rows": summary["graph_adapter_contract_rows"],
        "blocked_or_monitor_rows": summary["blocked_or_monitor_rows"],
        "repo_head": summary["repo_head"],
        "repo_dirty": summary["repo_dirty"],
    }
    lines.append(markdown_table(pd.DataFrame([health]).T.reset_index().rename(columns={"index": "field", 0: "value"})))
    lines.append("")
    lines.append("## Track Contract")
    lines.append("")
    lines.append(markdown_table(
        track,
        [
            "track_id", "n_rows", "future_experiment_budget_if_approved",
            "track_status", "requires_new_code", "launch_ready", "role",
        ],
    ))
    lines.append("")
    lines.append("## Horizon Contract")
    lines.append("")
    lines.append(markdown_table(
        horizon,
        [
            "contract_id", "region", "fold", "current_delta_vs_pricefm",
            "targeted_horizon_group", "primary_selection_rule",
            "future_experiment_budget_if_approved", "launch_ready", "guardrail",
        ],
    ))
    lines.append("")
    lines.append("## Graph Adapter Contract")
    lines.append("")
    lines.append(markdown_table(
        graph,
        [
            "contract_id", "region", "fold", "current_delta_vs_pricefm",
            "worst_horizon_group", "required_information_set",
            "must_differ_from", "requires_new_code", "launch_ready",
        ],
    ))
    lines.append("")
    lines.append("## Blocked Or Monitor Rows")
    lines.append("")
    lines.append(markdown_table(
        blocked,
        [
            "region", "fold", "stage_x_failure_mode", "stage_y_lane",
            "row_status", "current_delta_vs_pricefm", "blocked_or_monitor_reason",
        ],
        max_rows=40,
    ))
    lines.append("")
    lines.append("## Decision Gates")
    lines.append("")
    lines.append(markdown_table(gates))
    lines.append("")
    lines.append("## Recommended Next Move")
    lines.append("")
    lines.append("Choose exactly one future direction before any launch: a narrow horizon-targeted pilot for RO fold 3, or a graph-adapter implementation contract for the six graph-information-gap rows. Do not relaunch Stage-W Priority 1 and do not start a broad grid from this state.")
    lines.append("")
    repo_path(path).write_text("\n".join(lines))


def prepare(args):
    output_dir = repo_path(args.output_dir)
    if output_dir.exists() and any(output_dir.iterdir()) and not args.force:
        raise FileExistsError("{} already exists; re-run with --force true".format(output_dir))
    output_dir.mkdir(parents=True, exist_ok=True)

    stage_y_summary = read_json_required(stage_y_path(args.stage_y_dir, "summary.json"), "Stage-Y summary")
    design = read_csv_required(stage_y_path(args.stage_y_dir, "stage_y_design_manifest.csv"), "Stage-Y design manifest")
    decisions = read_csv_required(stage_y_path(args.stage_y_dir, "stage_y_decisions.csv"), "Stage-Y decisions")
    validate_stage_y(stage_y_summary, design, decisions)

    input_manifest = build_input_manifest(args)
    track = build_track_contract(design)
    horizon = build_horizon_contract(design)
    graph = build_graph_contract(design)
    blocked = build_blocked_rows(design)

    if len(horizon) > int(args.max_horizon_contract_rows):
        raise ValueError("Too many horizon contract rows: {}".format(len(horizon)))
    if len(graph) > int(args.max_graph_contract_rows):
        raise ValueError("Too many graph contract rows: {}".format(len(graph)))
    if not horizon.empty and horizon["launch_ready"].map(bool_value).any():
        raise ValueError("Horizon contract must not be launch-ready.")
    if not graph.empty and graph["launch_ready"].map(bool_value).any():
        raise ValueError("Graph contract must not be launch-ready.")

    gates = build_decision_gates(design, track, horizon, graph, blocked)
    if not gates["passed"].map(bool_value).all():
        failing = gates[~gates["passed"].map(bool_value)]["gate_id"].tolist()
        raise ValueError("Stage-Z gates failed: {}".format(failing))

    state = repo_state()
    future_budget = int(pd.to_numeric(
        design["future_experiment_budget_if_approved"],
        errors="coerce",
    ).fillna(0).sum())
    summary = {
        "status": "completed",
        "output_dir": config_path_value(output_dir),
        "diagnostic_only": True,
        "fits_models": False,
        "writes_launch_configs": False,
        "stage_m_surface_changed": False,
        "launch_ready_rows": 0,
        "launch_new_fits_now": False,
        "design_rows_read": int(len(design)),
        "track_rows": int(len(track)),
        "horizon_contract_rows": int(len(horizon)),
        "graph_adapter_contract_rows": int(len(graph)),
        "blocked_or_monitor_rows": int(len(blocked)),
        "future_experiment_budget_if_approved": future_budget,
        "recommended_next_stage": "choose_one_stage_z_track_before_any_launch",
        "repo_branch": state["repo_branch"],
        "repo_head": state["repo_head"],
        "repo_dirty": state["repo_dirty"],
    }

    write_frame(output_dir / "stage_z_input_manifest.csv", input_manifest)
    write_frame(output_dir / "stage_z_track_contract.csv", track)
    write_frame(output_dir / "stage_z_horizon_contract.csv", horizon)
    write_frame(output_dir / "stage_z_graph_adapter_contract.csv", graph)
    write_frame(output_dir / "stage_z_blocked_rows.csv", blocked)
    write_frame(output_dir / "stage_z_decision_gates.csv", gates)
    write_report(output_dir / "stage_z_report.md", summary, track, horizon, graph, blocked, gates)
    summary["outputs"] = {
        "input_manifest_csv": config_path_value(output_dir / "stage_z_input_manifest.csv"),
        "track_contract_csv": config_path_value(output_dir / "stage_z_track_contract.csv"),
        "horizon_contract_csv": config_path_value(output_dir / "stage_z_horizon_contract.csv"),
        "graph_adapter_contract_csv": config_path_value(output_dir / "stage_z_graph_adapter_contract.csv"),
        "blocked_rows_csv": config_path_value(output_dir / "stage_z_blocked_rows.csv"),
        "decision_gates_csv": config_path_value(output_dir / "stage_z_decision_gates.csv"),
        "report_md": config_path_value(output_dir / "stage_z_report.md"),
    }
    write_json(output_dir / "summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main():
    return prepare(parser().parse_args())


if __name__ == "__main__":
    main()
