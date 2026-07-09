#!/usr/bin/env python3
"""Prepare the Stage-ZC graph spread-summary smoke grid.

This planner is launchable only after the Stage-ZC diagnostics recommend the
`graph_neighbor_spread_summary` contract.  It writes one PL fold-3 smoke cell
with the current Stage-ZB geometry but a compact relative graph information set.
"""

from __future__ import annotations

import argparse
import copy
import json
import subprocess
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, sha256_file, write_json
from pricefm_graph import graph_hash, graph_scope_manifest_for_policy


GRID_BLOCK = "pricefm_desn_experiment_grid"
DEFAULT_STAGE_ZC_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_zc_graph_design_diagnostics_20260701"
)
DEFAULT_TEMPLATE_GRID = (
    "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_zc_graph_spread_smoke_20260701"
)
DEFAULT_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_zc_graph_spread_smoke_20260701.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_zc_graph_spread_smoke_20260701"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_zc_graph_spread_smoke_20260701"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-zc-dir", default=DEFAULT_STAGE_ZC_DIR)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE_GRID)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--grid-config", default=DEFAULT_GRID_CONFIG)
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--region", default="PL")
    p.add_argument("--fold", type=int, default=3)
    p.add_argument("--train-origin-limit", type=int, default=50)
    p.add_argument("--force", type=parse_bool, default=True)
    p.add_argument("--write-grid", type=parse_bool, default=True)
    return p


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


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def read_json_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required JSON: {}".format(label, path))
    with open(path, "r") as f:
        return json.load(f)


def read_yaml_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required YAML: {}".format(label, path))
    with open(path, "r") as f:
        return yaml.safe_load(f)


def write_yaml(path, payload):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def write_frame(path, frame):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)


def load_pricefm_regions(template_grid):
    grid = template_grid[GRID_BLOCK]
    data_path = repo_path(grid["base"]["data_config"])
    with open(data_path, "r") as f:
        data = yaml.safe_load(f)["pricefm"]
    return [str(x) for x in data["regions"]]


def validate_stage_zc(summary):
    if not bool(summary.get("diagnostic_only", False)):
        raise ValueError("Stage-ZC diagnostics must be diagnostic-only.")
    if bool(summary.get("fits_models", True)):
        raise ValueError("Stage-ZC diagnostics must not fit models.")
    if bool(summary.get("writes_launch_configs", True)):
        raise ValueError("Stage-ZC diagnostics must not write launch configs.")
    if summary.get("recommended_next_contract") != "graph_neighbor_spread_summary":
        raise ValueError("Stage-ZC diagnostics did not recommend graph_neighbor_spread_summary.")
    if not bool(summary.get("diagnostic_supports_revised_graph_contract", False)):
        raise ValueError("Stage-ZC diagnostics did not support a revised graph contract.")


def build_experiment(region, fold, graph, train_origin_limit):
    neighbors = list(graph["neighbor_regions"])
    return {
        "id": "stagezc_graph_spread_{}_f{}_l096_d1_n120_smoke_seed20260701".format(
            str(region).lower().replace("_", ""),
            int(fold),
        ),
        "stage": "stage_zc_graph_spread_smoke",
        "priority": 0,
        "regions": [str(region)],
        "folds": [int(fold)],
        "feature_policy": "graph_neighbor_spread_summary",
        "graph_degree": 1,
        "neighbor_regions": neighbors,
        "target_lag_features": ["price", "load", "solar", "wind"],
        "target_lead_features": ["load", "solar", "wind"],
        "neighbor_lag_features": ["price", "load"],
        "neighbor_lead_features": ["load", "wind"],
        "summary_stats": ["mean_diff", "sd", "min_diff", "max_diff"],
        "feature_map": "window_reservoir_v1",
        "lag_window": 96,
        "depth": 1,
        "units": [120],
        "alpha": 0.5,
        "rho": 0.9,
        "input_scale": 0.25,
        "projection_scale": 1.0,
        "state_output": "final_layer",
        "tau0": 1.0e-3,
        "seed": 20260701,
        "quantile": 0.5,
        "input_scope": "pricefm_graph_neighbor_spread_summary_degree1_n{}".format(len(neighbors)),
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "pricefm_neighbor_augmented_spread_summary",
        "graph_source": "PriceFM.graph_adj_matrix",
        "graph_hash": graph_hash(),
        "candidate_family": "stage_zc_graph_spread_smoke",
        "candidate_source": "stage_zc_graph_design_diagnostics_20260701",
        "selection_rule": "diagnostic_recommended_one_cell_smoke",
        "selection_is_validation_only": True,
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "test_metrics_role": "audit_only_after_selection",
        "target_label": "graph_spread_summary_smoke",
        "rationale": (
            "Diagnostic-approved compact relative graph smoke for PL fold 3. "
            "It keeps the Stage-ZB geometry but replaces raw direct neighbor "
            "columns with neighbor-minus-target spread summaries."
        ),
        "train_origin_limit_for_planner": int(train_origin_limit),
    }


def build_grid(template_grid, experiment, args):
    payload = copy.deepcopy(template_grid)
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = "pricefm_stage_zc_graph_spread_smoke_20260701"
    grid["purpose"] = (
        "One-cell smoke grid for the diagnostic-approved "
        "graph_neighbor_spread_summary adapter."
    )
    grid["base"]["generated_root"] = config_path_value(args.generated_root)
    grid["base"]["run_root"] = config_path_value(args.run_root)
    grid["scope"]["regions"] = list(experiment["regions"])
    grid["scope"]["folds"] = list(experiment["folds"])
    grid["scope"]["quantiles"] = [0.5]
    grid["scope"]["horizons"] = "all"
    grid["fixed"]["feature_policy"] = "target_only"
    grid["fixed"]["train_origin_limit"] = int(args.train_origin_limit)
    grid["fixed"]["train_origin_selection"] = "tail"
    grid["fixed"]["row_chunk_size"] = 512
    grid["fixed"]["projection_scale"] = 1.0
    grid["fixed"]["qdesn_likelihoods"] = ["al", "exal"]
    grid["launch"] = {
        "writes_launch_configs": True,
        "launch_ready": True,
        "note": "One diagnostic-approved graph spread-summary smoke only.",
    }
    grid["experiment_blocks"] = []
    grid["experiments"] = [experiment]
    return payload


def report_lines(summary, experiment):
    lines = []
    lines.append("# PriceFM Stage-ZC Graph Spread-Summary Smoke")
    lines.append("")
    lines.append("Stage ZC writes one launchable smoke grid for `graph_neighbor_spread_summary`.")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append("| Field | Value |")
    lines.append("|---|---|")
    for key in [
        "status", "selected_region", "selected_fold", "feature_policy",
        "train_origin_limit", "launch_ready_rows", "grid_config",
    ]:
        lines.append("| `{}` | `{}` |".format(key, summary.get(key, "")))
    lines.append("")
    lines.append("## Experiment")
    lines.append("")
    lines.append("| Field | Value |")
    lines.append("|---|---|")
    for key in [
        "id", "feature_policy", "neighbor_regions", "summary_stats",
        "lag_window", "units", "alpha", "rho", "input_scale", "seed",
    ]:
        lines.append("| `{}` | `{}` |".format(key, experiment.get(key, "")))
    return "\n".join(lines) + "\n"


def prepare(args):
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and not args.force:
        raise FileExistsError("{} exists; rerun with --force true".format(out_dir))
    out_dir.mkdir(parents=True, exist_ok=True)

    stage_zc = read_json_required(Path(args.stage_zc_dir) / "summary.json", "Stage-ZC summary")
    validate_stage_zc(stage_zc)
    template = read_yaml_required(args.template_grid_config, "template grid")
    regions = load_pricefm_regions(template)
    graph = graph_scope_manifest_for_policy(
        args.region,
        regions,
        "graph_neighbor_spread_summary",
        spatial={"graph_degree": 1},
    )
    experiment = build_experiment(args.region, args.fold, graph, args.train_origin_limit)
    payload = build_grid(template, experiment, args)
    if args.write_grid:
        write_yaml(args.grid_config, payload)

    manifest = pd.DataFrame([{
        "region": args.region,
        "fold": int(args.fold),
        "feature_policy": experiment["feature_policy"],
        "neighbor_regions": json.dumps(experiment["neighbor_regions"]),
        "summary_stats": json.dumps(experiment["summary_stats"]),
        "train_origin_limit": int(args.train_origin_limit),
        "launch_ready": True,
        "grid_config": config_path_value(args.grid_config),
    }])
    gates = pd.DataFrame([
        {
            "gate_id": "stage_zc_diagnostic_recommendation",
            "passed": True,
            "decision": stage_zc["recommended_next_contract"],
        },
        {
            "gate_id": "one_cell_only",
            "passed": True,
            "decision": "1 smoke experiment",
        },
        {
            "gate_id": "bounded_train_origin_limit",
            "passed": int(args.train_origin_limit) <= 50,
            "decision": "train_origin_limit={}".format(int(args.train_origin_limit)),
        },
        {
            "gate_id": "spread_summary_policy",
            "passed": experiment["feature_policy"] == "graph_neighbor_spread_summary",
            "decision": experiment["feature_policy"],
        },
    ])
    if not gates["passed"].astype(bool).all():
        raise ValueError("Stage-ZC smoke gates failed.")

    summary = {
        "status": "prepared",
        "selected_region": args.region,
        "selected_fold": int(args.fold),
        "feature_policy": experiment["feature_policy"],
        "train_origin_limit": int(args.train_origin_limit),
        "launch_ready_rows": 1,
        "writes_launch_config": bool(args.write_grid),
        "grid_config": config_path_value(args.grid_config),
        "generated_root": config_path_value(args.generated_root),
        "run_root": config_path_value(args.run_root),
        "output_dir": config_path_value(args.output_dir),
        "stage_zc_summary": config_path_value(Path(args.stage_zc_dir) / "summary.json"),
        "grid_config_sha256": sha256_file(repo_path(args.grid_config)) if args.write_grid else "",
    }
    summary.update(repo_state())
    write_frame(out_dir / "stage_zc_smoke_manifest.csv", manifest)
    write_frame(out_dir / "stage_zc_smoke_decision_gates.csv", gates)
    write_json(out_dir / "summary.json", summary)
    (out_dir / "stage_zc_smoke_report.md").write_text(report_lines(summary, experiment))
    return summary


def main():
    args = parser().parse_args()
    summary = prepare(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
