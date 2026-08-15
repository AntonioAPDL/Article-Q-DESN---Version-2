#!/usr/bin/env python3
"""Prepare the Stage-ZA PriceFM graph-adapter smoke grid.

Stage ZA is the first graph-adapter implementation gate after Stage Z. It
chooses one graph-information-gap row, writes a bounded median-only smoke grid
using the new ``graph_neighbor_direct`` feature policy, and records the
provenance and launch guards. It does not launch model fits.
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
    "pricefm_stage_za_graph_adapter_smoke_20260630"
)
DEFAULT_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_za_graph_adapter_smoke_20260630.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_za_graph_adapter_smoke_20260630"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_za_graph_adapter_smoke_20260630"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-z-dir", default=DEFAULT_STAGE_Z_DIR)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE_GRID)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--grid-config", default=DEFAULT_GRID_CONFIG)
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--force", type=parse_bool, default=True)
    p.add_argument("--write-grid", type=parse_bool, default=True)
    p.add_argument("--smoke-train-origin-limit", type=int, default=50)
    p.add_argument("--max-smoke-experiments", type=int, default=1)
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


def bool_value(value):
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in ("true", "1", "yes", "y")


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


def input_manifest(args):
    specs = [
        ("stage_z_summary", stage_z_path(args.stage_z_dir, "summary.json"), "json", "Stage-Z summary"),
        ("stage_z_graph_contract", stage_z_path(args.stage_z_dir, "stage_z_graph_adapter_contract.csv"), "csv", "Stage-Z graph rows"),
        ("stage_z_decision_gates", stage_z_path(args.stage_z_dir, "stage_z_decision_gates.csv"), "csv", "Stage-Z decision gates"),
        ("template_grid", args.template_grid_config, "yaml", "known-safe grid template"),
    ]
    rows = []
    for input_id, path, kind, role in specs:
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
    if "requires_new_code" in graph_contract.columns and not graph_contract["requires_new_code"].map(bool_value).all():
        raise ValueError("Stage-Z graph rows must require new adapter code.")
    if "passed" in gates.columns and not gates["passed"].map(bool_value).all():
        raise ValueError("Stage-Z decision gates are not all passing.")


def load_pricefm_regions(template_grid):
    grid = template_grid[GRID_BLOCK]
    data_path = repo_path(grid["base"]["data_config"])
    with open(data_path, "r") as f:
        data = yaml.safe_load(f)["pricefm"]
    return [str(x) for x in data["regions"]]


def select_smoke_row(graph_contract):
    work = graph_contract.copy()
    work["current_delta_vs_pricefm"] = pd.to_numeric(work["current_delta_vs_pricefm"], errors="coerce")
    work = work.sort_values(
        ["current_delta_vs_pricefm", "region", "fold"],
        ascending=[False, True, True],
    )
    return work.iloc[0].to_dict()


def graph_neighbors(region, template_grid):
    regions = load_pricefm_regions(template_grid)
    spatial = {"graph_degree": 1}
    graph = graph_scope_manifest_for_policy(
        region,
        regions,
        "graph_neighbor_direct",
        spatial=spatial,
    )
    return graph


def build_smoke_experiment(row, graph, args):
    region = str(row["region"])
    fold = int(row["fold"])
    neighbors = list(graph["neighbor_regions"])
    return {
        "id": "stageza_graph_direct_{}_f{}_l096_d1_n120_seed20260630".format(
            region.lower().replace("_", ""),
            fold,
        ),
        "stage": "stage_za_graph_adapter_smoke",
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
        "input_scale": 0.5,
        "projection_scale": 1.0,
        "state_output": "final_layer",
        "tau0": 1.0e-3,
        "seed": 20260630,
        "quantile": 0.5,
        "input_scope": "pricefm_graph_neighbor_direct_degree1_n{}".format(len(neighbors)),
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "pricefm_neighbor_augmented_direct",
        "graph_source": "PriceFM.graph_adj_matrix",
        "graph_hash": graph_hash(),
        "candidate_family": "stage_za_graph_neighbor_direct_smoke",
        "candidate_source": "stage_za_graph_adapter_smoke_20260630",
        "selection_rule": "validation_AQL_median_only_test_audit",
        "selection_is_validation_only": True,
        "test_metrics_role": "audit_only_after_selection",
        "rationale": "Top Stage-Z graph-information-gap row with direct neighbor covariates and bounded train origins.",
    }


def build_grid(template_grid, experiment, args):
    payload = copy.deepcopy(template_grid)
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = "pricefm_stage_za_graph_adapter_smoke_20260630"
    grid["purpose"] = (
        "One-cell median-only smoke grid for the graph_neighbor_direct adapter. "
        "This grid is launchable only after explicit approval."
    )
    grid["base"]["generated_root"] = config_path_value(args.generated_root)
    grid["base"]["run_root"] = config_path_value(args.run_root)
    grid["scope"]["regions"] = list(experiment["regions"])
    grid["scope"]["folds"] = list(experiment["folds"])
    grid["scope"]["quantiles"] = [0.5]
    grid["scope"]["horizons"] = "all"
    grid["fixed"]["feature_policy"] = "target_only"
    grid["fixed"]["train_origin_limit"] = int(args.smoke_train_origin_limit)
    grid["fixed"]["train_origin_selection"] = "tail"
    grid["fixed"]["row_chunk_size"] = 512
    grid["fixed"]["qdesn_likelihoods"] = ["al", "exal"]
    grid["launch"] = {
        "dry_run_gate": {
            "priorities": [0],
            "experiment_jobs": 1,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Dry-run first; do not launch a broad graph grid from this smoke config.",
        },
        "smoke_if_approved": {
            "priorities": [0],
            "experiment_jobs": 1,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Only one PL fold-3 median smoke cell.",
        },
    }
    grid["experiments"] = [experiment]
    grid["experiment_blocks"] = []
    return payload


def write_report(path, summary, smoke, candidates, gates):
    lines = []
    lines.append("# PriceFM Stage-ZA Graph Adapter Smoke")
    lines.append("")
    lines.append("Stage ZA implements the first graph-adapter launch artifact after Stage Z. It writes a one-cell smoke grid using `graph_neighbor_direct` and does not launch model fits.")
    lines.append("")
    lines.append("## Health")
    lines.append("")
    health = pd.DataFrame([{
        "diagnostic_only": summary["diagnostic_only"],
        "fits_models": summary["fits_models"],
        "writes_launch_config": summary["writes_launch_config"],
        "launches_models": summary["launches_models"],
        "smoke_experiments": summary["smoke_experiments"],
        "graph_contract_rows_read": summary["graph_contract_rows_read"],
        "repo_head": summary["repo_head"],
        "repo_dirty": summary["repo_dirty"],
    }]).T.reset_index().rename(columns={"index": "field", 0: "value"})
    lines.append(markdown_table(health))
    lines.append("")
    lines.append("## Smoke Experiment")
    lines.append("")
    lines.append(markdown_table(smoke))
    lines.append("")
    lines.append("## Candidate Rows")
    lines.append("")
    lines.append(markdown_table(candidates, max_rows=10))
    lines.append("")
    lines.append("## Decision Gates")
    lines.append("")
    lines.append(markdown_table(gates))
    lines.append("")
    lines.append("## Next Step")
    lines.append("")
    lines.append("Run the dry-run gate, inspect the generated cell config and adapter provenance, then launch only this one-cell smoke if approved. Do not run the six-row graph grid until the smoke improves validation behavior and passes leakage/provenance checks.")
    repo_path(path).write_text("\n".join(lines))


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
            vals.append(str(row[col]))
        lines.append("| {} |".format(" | ".join(vals)))
    return "\n".join(lines)


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

    selected = select_smoke_row(graph_contract)
    graph = graph_neighbors(selected["region"], template)
    experiment = build_smoke_experiment(selected, graph, args)
    grid_payload = build_grid(template, experiment, args)
    if args.write_grid:
        write_yaml(args.grid_config, grid_payload)

    smoke_manifest = pd.DataFrame([{
        "experiment_id": experiment["id"],
        "region": selected["region"],
        "fold": int(selected["fold"]),
        "feature_policy": experiment["feature_policy"],
        "neighbor_regions": json.dumps(experiment["neighbor_regions"]),
        "neighbor_lag_features": json.dumps(experiment["neighbor_lag_features"]),
        "neighbor_lead_features": json.dumps(experiment["neighbor_lead_features"]),
        "train_origin_limit": int(args.smoke_train_origin_limit),
        "selection_rule": experiment["selection_rule"],
        "test_metrics_role": experiment["test_metrics_role"],
        "grid_config": config_path_value(args.grid_config),
        "generated_root": config_path_value(args.generated_root),
        "run_root": config_path_value(args.run_root),
        "launch_ready": False,
    }])
    candidates = graph_contract.copy()
    candidates["stage_za_role"] = candidates.apply(
        lambda row: "selected_smoke" if str(row["region"]) == str(selected["region"]) and int(row["fold"]) == int(selected["fold"]) else "held_for_after_smoke",
        axis=1,
    )
    decision_gates = pd.DataFrame([
        {
            "gate_id": "one_cell_smoke_only",
            "passed": len(smoke_manifest) == 1,
            "decision": "{} smoke experiment(s)".format(len(smoke_manifest)),
        },
        {
            "gate_id": "validation_only_selection",
            "passed": experiment["selection_is_validation_only"] is True,
            "decision": experiment["selection_rule"],
        },
        {
            "gate_id": "graph_direct_policy",
            "passed": experiment["feature_policy"] == "graph_neighbor_direct",
            "decision": experiment["feature_policy"],
        },
        {
            "gate_id": "no_model_launch",
            "passed": True,
            "decision": "planner_only",
        },
    ])
    if not decision_gates["passed"].map(bool_value).all():
        raise ValueError("Stage-ZA gates failed.")

    inputs = input_manifest(args)
    state = repo_state()
    summary = {
        "status": "completed",
        "output_dir": config_path_value(output_dir),
        "diagnostic_only": False,
        "fits_models": False,
        "writes_launch_config": bool(args.write_grid),
        "launches_models": False,
        "stage_m_surface_changed": False,
        "graph_contract_rows_read": int(len(graph_contract)),
        "smoke_experiments": int(len(smoke_manifest)),
        "selected_region": str(selected["region"]),
        "selected_fold": int(selected["fold"]),
        "grid_config": config_path_value(args.grid_config),
        "recommended_next_stage": "dry_run_stage_za_then_optional_one_cell_smoke",
        "repo_branch": state["repo_branch"],
        "repo_head": state["repo_head"],
        "repo_dirty": state["repo_dirty"],
    }

    write_frame(output_dir / "stage_za_input_manifest.csv", inputs)
    write_frame(output_dir / "stage_za_graph_candidate_rows.csv", candidates)
    write_frame(output_dir / "stage_za_smoke_manifest.csv", smoke_manifest)
    write_frame(output_dir / "stage_za_decision_gates.csv", decision_gates)
    write_report(output_dir / "stage_za_report.md", summary, smoke_manifest, candidates, decision_gates)
    summary["outputs"] = {
        "input_manifest_csv": config_path_value(output_dir / "stage_za_input_manifest.csv"),
        "graph_candidate_rows_csv": config_path_value(output_dir / "stage_za_graph_candidate_rows.csv"),
        "smoke_manifest_csv": config_path_value(output_dir / "stage_za_smoke_manifest.csv"),
        "decision_gates_csv": config_path_value(output_dir / "stage_za_decision_gates.csv"),
        "report_md": config_path_value(output_dir / "stage_za_report.md"),
    }
    write_json(output_dir / "summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main():
    return prepare(parser().parse_args())


if __name__ == "__main__":
    main()
