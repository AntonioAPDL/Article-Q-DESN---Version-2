#!/usr/bin/env python3
"""Prepare the Stage-ZB full-budget graph-direct PL fold-3 candidate.

Stage ZB is deliberately one cell: it preserves the current PL fold-3
target-only selected geometry and changes only the feature information set to
``graph_neighbor_direct``.  The generated grid is launchable after Stage-ZA
adapter/model smoke passed.
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
DEFAULT_STAGE_Z_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_z_design_contracts_20260630"
)
DEFAULT_TEMPLATE_GRID = (
    "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_zb_graph_direct_fullbudget_pl_f3_20260701"
)
DEFAULT_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_zb_graph_direct_fullbudget_pl_f3_20260701.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_zb_graph_direct_fullbudget_pl_f3_20260701"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_zb_graph_direct_fullbudget_pl_f3_20260701"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-z-dir", default=DEFAULT_STAGE_Z_DIR)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE_GRID)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--grid-config", default=DEFAULT_GRID_CONFIG)
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--region", default="PL")
    p.add_argument("--fold", type=int, default=3)
    p.add_argument("--train-origin-limit", type=int, default=3000)
    p.add_argument("--force", type=parse_bool, default=True)
    p.add_argument("--write-grid", type=parse_bool, default=True)
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def bool_value(value):
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in ("true", "1", "yes", "y")


def read_json_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required JSON: {}".format(label, path))
    with open(path, "r") as f:
        return json.load(f)


def read_csv_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required CSV: {}".format(label, path))
    return pd.read_csv(path)


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


def stage_z_path(stage_z_dir, filename):
    return repo_path(Path(stage_z_dir) / filename)


def validate_stage_z(summary, graph_contract, gates):
    if not bool_value(summary.get("diagnostic_only", False)):
        raise ValueError("Stage-Z must be diagnostic-only.")
    if bool_value(summary.get("fits_models", True)):
        raise ValueError("Stage-Z must not fit models.")
    if bool_value(summary.get("writes_launch_configs", True)):
        raise ValueError("Stage-Z must not write launch configs.")
    if int(summary.get("launch_ready_rows", 0)) != 0:
        raise ValueError("Stage-Z must have zero launch-ready rows.")
    if graph_contract.empty:
        raise ValueError("Stage-Z graph contract has no rows.")
    if graph_contract["launch_ready"].map(bool_value).any():
        raise ValueError("Stage-Z graph rows must not be launch-ready.")
    if "passed" in gates.columns and not gates["passed"].map(bool_value).all():
        raise ValueError("Stage-Z decision gates are not all passing.")


def load_pricefm_regions(template_grid):
    grid = template_grid[GRID_BLOCK]
    data_path = repo_path(grid["base"]["data_config"])
    with open(data_path, "r") as f:
        data = yaml.safe_load(f)["pricefm"]
    return [str(x) for x in data["regions"]]


def select_contract_row(graph_contract, region, fold):
    sub = graph_contract[
        graph_contract["region"].astype(str).eq(str(region)) &
        graph_contract["fold"].astype(int).eq(int(fold))
    ].copy()
    if sub.empty:
        raise ValueError("No Stage-Z graph contract row for region={} fold={}.".format(region, fold))
    return sub.iloc[0].to_dict()


def graph_for_region(region, template_grid):
    regions = load_pricefm_regions(template_grid)
    return graph_scope_manifest_for_policy(
        region,
        regions,
        "graph_neighbor_direct",
        spatial={"graph_degree": 1},
    )


def build_experiment(row, graph):
    region = str(row["region"])
    fold = int(row["fold"])
    neighbors = list(graph["neighbor_regions"])
    return {
        "id": "stagezb_graph_direct_{}_f{}_l096_d1_n120_anchor_seed20260603".format(
            region.lower().replace("_", ""),
            fold,
        ),
        "stage": "stage_zb_graph_direct_fullbudget",
        "priority": 0,
        "regions": [region],
        "folds": [fold],
        "feature_policy": "graph_neighbor_direct",
        "graph_degree": 1,
        "neighbor_regions": neighbors,
        "target_lag_features": ["price", "load", "solar", "wind"],
        "target_lead_features": ["load", "solar", "wind"],
        "neighbor_lag_features": ["price", "load"],
        "neighbor_lead_features": ["load", "wind"],
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
        "seed": 20260603,
        "quantile": 0.5,
        "input_scope": "pricefm_graph_neighbor_direct_degree1_n{}".format(len(neighbors)),
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "pricefm_neighbor_augmented_direct",
        "graph_source": "PriceFM.graph_adj_matrix",
        "graph_hash": graph_hash(),
        "candidate_family": "stage_zb_graph_direct_fullbudget",
        "candidate_source": "stage_zb_graph_direct_fullbudget_pl_f3_20260701",
        "selection_rule": "single_approved_fullbudget_graph_direct_probe",
        "selection_is_validation_only": True,
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "test_metrics_role": "audit_only_after_selection",
        "local_AQL": float(row["current_AQL"]),
        "pricefm_AQL": float(row["pricefm_AQL"]),
        "underperformance_delta_abs": float(row["current_delta_vs_pricefm"]),
        "rationale": (
            "Full-budget one-cell graph-direct probe for PL fold 3. It keeps "
            "the current target-only selected geometry and changes only the "
            "neighbor-direct information set."
        ),
    }


def build_grid(template_grid, experiment, args):
    payload = copy.deepcopy(template_grid)
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = "pricefm_stage_zb_graph_direct_fullbudget_pl_f3_20260701"
    grid["purpose"] = (
        "One-cell full-training-budget median probe for PL fold 3 using "
        "graph_neighbor_direct inputs and the current selected target-only "
        "geometry."
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
    grid["fixed"]["qdesn_likelihoods"] = ["al", "exal"]
    grid["launch"] = {
        "fullbudget_probe": {
            "priorities": [0],
            "experiment_jobs": 1,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "One approved PL fold-3 graph-direct full-budget probe only.",
        }
    }
    grid["experiments"] = [experiment]
    grid["experiment_blocks"] = []
    return payload


def markdown_table(frame):
    if frame is None or frame.empty:
        return "_No rows._"
    headers = list(frame.columns)
    lines = ["| {} |".format(" | ".join(headers))]
    lines.append("| {} |".format(" | ".join(["---"] * len(headers))))
    for _, row in frame.iterrows():
        lines.append("| {} |".format(" | ".join(str(row[col]) for col in headers)))
    return "\n".join(lines)


def write_report(path, summary, probe_manifest, gates):
    lines = []
    lines.append("# PriceFM Stage-ZB Graph-Direct Full-Budget Probe")
    lines.append("")
    lines.append("Stage ZB writes one launchable full-training-budget graph-direct candidate for `PL` fold 3.")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append(markdown_table(pd.DataFrame([summary]).T.reset_index().rename(columns={"index": "field", 0: "value"})))
    lines.append("")
    lines.append("## Probe Manifest")
    lines.append("")
    lines.append(markdown_table(probe_manifest))
    lines.append("")
    lines.append("## Decision Gates")
    lines.append("")
    lines.append(markdown_table(gates))
    lines.append("")
    lines.append("## Launch Command")
    lines.append("")
    lines.append("```sh")
    lines.append("application/data_local/pricefm/venv/bin/python application/scripts/pricefm/13_run_desn_experiment_grid.py \\")
    lines.append("  --grid-config {} \\".format(summary["grid_config"]))
    lines.append("  --priorities 0 --experiment-jobs 1 --cell-jobs 1 \\")
    lines.append("  --build-windows true --dry-run false --resume true --force true")
    lines.append("```")
    repo_path(path).write_text("\n".join(lines))


def input_manifest(args):
    specs = [
        ("stage_z_summary", stage_z_path(args.stage_z_dir, "summary.json"), "json"),
        ("stage_z_graph_contract", stage_z_path(args.stage_z_dir, "stage_z_graph_adapter_contract.csv"), "csv"),
        ("stage_z_decision_gates", stage_z_path(args.stage_z_dir, "stage_z_decision_gates.csv"), "csv"),
        ("template_grid", args.template_grid_config, "yaml"),
    ]
    rows = []
    for input_id, path, kind in specs:
        full = repo_path(path)
        row = {
            "input_id": input_id,
            "kind": kind,
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


def prepare(args):
    output_dir = repo_path(args.output_dir)
    if output_dir.exists() and any(output_dir.iterdir()) and not args.force:
        raise FileExistsError("{} already exists; re-run with --force true".format(output_dir))
    output_dir.mkdir(parents=True, exist_ok=True)

    stage_z_summary = read_json_required(stage_z_path(args.stage_z_dir, "summary.json"), "Stage-Z summary")
    graph_contract = read_csv_required(
        stage_z_path(args.stage_z_dir, "stage_z_graph_adapter_contract.csv"),
        "Stage-Z graph adapter contract",
    )
    gates = read_csv_required(stage_z_path(args.stage_z_dir, "stage_z_decision_gates.csv"), "Stage-Z gates")
    validate_stage_z(stage_z_summary, graph_contract, gates)
    template = read_yaml_required(args.template_grid_config, "template grid")

    selected = select_contract_row(graph_contract, args.region, args.fold)
    graph = graph_for_region(selected["region"], template)
    experiment = build_experiment(selected, graph)
    grid_payload = build_grid(template, experiment, args)
    if args.write_grid:
        write_yaml(args.grid_config, grid_payload)

    probe_manifest = pd.DataFrame([{
        "experiment_id": experiment["id"],
        "region": selected["region"],
        "fold": int(selected["fold"]),
        "feature_policy": experiment["feature_policy"],
        "neighbor_regions": json.dumps(experiment["neighbor_regions"]),
        "train_origin_limit": int(args.train_origin_limit),
        "geometry_anchor": "stage_c_target_only_selected_pl_f3",
        "input_scale": experiment["input_scale"],
        "seed": experiment["seed"],
        "current_target_only_AQL": float(selected["current_AQL"]),
        "pricefm_AQL": float(selected["pricefm_AQL"]),
        "launch_ready": True,
        "grid_config": config_path_value(args.grid_config),
        "generated_root": config_path_value(args.generated_root),
        "run_root": config_path_value(args.run_root),
    }])
    decision_gates = pd.DataFrame([
        {
            "gate_id": "one_cell_only",
            "passed": len(probe_manifest) == 1,
            "decision": "{} probe experiment(s)".format(len(probe_manifest)),
        },
        {
            "gate_id": "fullbudget_limit",
            "passed": int(args.train_origin_limit) == 3000,
            "decision": "train_origin_limit={}".format(int(args.train_origin_limit)),
        },
        {
            "gate_id": "graph_direct_policy",
            "passed": experiment["feature_policy"] == "graph_neighbor_direct",
            "decision": experiment["feature_policy"],
        },
        {
            "gate_id": "anchor_geometry_preserved",
            "passed": (
                experiment["lag_window"] == 96 and
                experiment["units"] == [120] and
                experiment["input_scale"] == 0.25 and
                experiment["seed"] == 20260603
            ),
            "decision": "L96 D1 n120 input_scale0.25 seed20260603",
        },
    ])
    if not decision_gates["passed"].map(bool_value).all():
        raise ValueError("Stage-ZB gates failed.")

    state = repo_state()
    summary = {
        "status": "prepared",
        "output_dir": config_path_value(output_dir),
        "fits_models": False,
        "writes_launch_config": bool(args.write_grid),
        "launch_ready_rows": int(probe_manifest["launch_ready"].map(bool_value).sum()),
        "probe_experiments": int(len(probe_manifest)),
        "selected_region": str(selected["region"]),
        "selected_fold": int(selected["fold"]),
        "grid_config": config_path_value(args.grid_config),
        "repo_branch": state["repo_branch"],
        "repo_head": state["repo_head"],
        "repo_dirty": state["repo_dirty"],
    }
    inputs = input_manifest(args)
    write_frame(output_dir / "stage_zb_input_manifest.csv", inputs)
    write_frame(output_dir / "stage_zb_probe_manifest.csv", probe_manifest)
    write_frame(output_dir / "stage_zb_decision_gates.csv", decision_gates)
    write_report(output_dir / "stage_zb_report.md", summary, probe_manifest, decision_gates)
    summary["outputs"] = {
        "input_manifest_csv": config_path_value(output_dir / "stage_zb_input_manifest.csv"),
        "probe_manifest_csv": config_path_value(output_dir / "stage_zb_probe_manifest.csv"),
        "decision_gates_csv": config_path_value(output_dir / "stage_zb_decision_gates.csv"),
        "report_md": config_path_value(output_dir / "stage_zb_report.md"),
    }
    write_json(output_dir / "summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main():
    return prepare(parser().parse_args())


if __name__ == "__main__":
    main()
