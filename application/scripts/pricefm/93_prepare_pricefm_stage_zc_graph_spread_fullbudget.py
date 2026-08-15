#!/usr/bin/env python3
"""Prepare the Stage-ZC full-budget graph spread-summary PL fold-3 probe.

This planner is gated by two earlier artifacts:

1. Stage-ZC diagnostics must recommend `graph_neighbor_spread_summary`.
2. The one-cell Stage-ZC smoke run must complete cleanly and produce finite
   metrics without binary fit-state artifacts.

The generated grid is still deliberately one cell.  It changes only the graph
information set relative to the current PL fold-3 anchor geometry.
"""

from __future__ import annotations

import argparse
import copy
import json
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, sha256_file, write_json
from pricefm_graph import graph_hash, graph_scope_manifest_for_policy


GRID_BLOCK = "pricefm_desn_experiment_grid"
DEFAULT_STAGE_ZC_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_zc_graph_design_diagnostics_20260701"
)
DEFAULT_SMOKE_GRID_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_zc_graph_spread_smoke_20260701"
)
DEFAULT_SMOKE_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_zc_graph_spread_smoke_20260701"
)
DEFAULT_TEMPLATE_GRID = (
    "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_zc_graph_spread_fullbudget_pl_f3_20260701"
)
DEFAULT_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_zc_graph_spread_fullbudget_pl_f3_20260701.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_zc_graph_spread_fullbudget_pl_f3_20260701"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_zc_graph_spread_fullbudget_pl_f3_20260701"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-zc-dir", default=DEFAULT_STAGE_ZC_DIR)
    p.add_argument("--smoke-grid-root", default=DEFAULT_SMOKE_GRID_ROOT)
    p.add_argument("--smoke-run-root", default=DEFAULT_SMOKE_RUN_ROOT)
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


def smoke_metric_paths(smoke_run_root, region, fold):
    root = repo_path(smoke_run_root)
    pattern = "*/cells/region={}/fold={}/model/metric_summary.csv".format(region, int(fold))
    return sorted(root.glob(pattern))


def smoke_adapter_paths(smoke_run_root, region, fold):
    root = repo_path(smoke_run_root)
    pattern = "*/cells/region={}/fold={}/adapter".format(region, int(fold))
    return sorted(root.glob(pattern))


def validate_smoke(smoke_grid_root, smoke_run_root, region, fold):
    launch_status = read_csv_required(
        Path(smoke_grid_root) / "launch_status.csv",
        "Stage-ZC smoke launch status",
    )
    if launch_status.empty:
        raise ValueError("Stage-ZC smoke launch status has no rows.")
    if not launch_status["status"].astype(str).eq("completed").all():
        raise ValueError("Stage-ZC smoke did not complete all launch rows.")
    if not launch_status["return_code"].astype(int).eq(0).all():
        raise ValueError("Stage-ZC smoke has nonzero return codes.")

    binaries = []
    for suffix in ("*.rds", "*.rda", "*.RData", "*.rdata"):
        binaries.extend(repo_path(smoke_run_root).glob("**/{}".format(suffix)))
    if binaries:
        raise ValueError("Stage-ZC smoke left binary fit artifacts.")

    metrics_paths = smoke_metric_paths(smoke_run_root, region, fold)
    if len(metrics_paths) != 1:
        raise ValueError("Expected exactly one Stage-ZC smoke metric summary, found {}.".format(
            len(metrics_paths)
        ))
    metrics = pd.read_csv(metrics_paths[0])
    if metrics.empty or "AQL" not in metrics.columns:
        raise ValueError("Stage-ZC smoke metrics are missing AQL.")
    if not np.isfinite(metrics["AQL"].astype(float).to_numpy()).all():
        raise ValueError("Stage-ZC smoke metrics contain non-finite AQL.")

    adapter_dirs = smoke_adapter_paths(smoke_run_root, region, fold)
    if len(adapter_dirs) != 1:
        raise ValueError("Expected exactly one Stage-ZC smoke adapter directory, found {}.".format(
            len(adapter_dirs)
        ))
    feature_manifest = read_json_required(adapter_dirs[0] / "feature_manifest.json", "feature manifest")
    provenance = read_csv_required(adapter_dirs[0] / "feature_provenance.csv", "feature provenance")
    if feature_manifest.get("feature_policy") != "graph_neighbor_spread_summary":
        raise ValueError("Stage-ZC smoke feature manifest has the wrong feature policy.")
    roles = set(provenance["source_role"].astype(str))
    if "target" not in roles or "neighbor_summary" not in roles:
        raise ValueError("Stage-ZC smoke provenance lacks target or neighbor_summary roles.")

    return {
        "launch_status": launch_status,
        "metrics": metrics,
        "metrics_path": metrics_paths[0],
        "adapter_dir": adapter_dirs[0],
        "feature_manifest": feature_manifest,
        "feature_provenance": provenance,
    }


def build_experiment(region, fold, graph, train_origin_limit):
    neighbors = list(graph["neighbor_regions"])
    return {
        "id": "stagezc_graph_spread_{}_f{}_l096_d1_n120_fullbudget_seed20260701".format(
            str(region).lower().replace("_", ""),
            int(fold),
        ),
        "stage": "stage_zc_graph_spread_fullbudget",
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
        "candidate_family": "stage_zc_graph_spread_fullbudget",
        "candidate_source": "stage_zc_graph_spread_fullbudget_pl_f3_20260701",
        "selection_rule": "single_smoke_approved_fullbudget_graph_spread_probe",
        "selection_is_validation_only": True,
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "test_metrics_role": "audit_only_after_selection",
        "target_label": "graph_spread_summary_fullbudget",
        "rationale": (
            "Full-budget PL fold-3 probe for the diagnostic- and smoke-approved "
            "graph_neighbor_spread_summary information set.  It preserves the "
            "Stage-ZB anchor geometry and replaces raw direct neighbor columns "
            "with compact neighbor-minus-target spread summaries."
        ),
        "train_origin_limit_for_planner": int(train_origin_limit),
    }


def build_grid(template_grid, experiment, args):
    payload = copy.deepcopy(template_grid)
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = "pricefm_stage_zc_graph_spread_fullbudget_pl_f3_20260701"
    grid["purpose"] = (
        "One-cell full-training-budget median probe for PL fold 3 using "
        "graph_neighbor_spread_summary inputs and the current selected "
        "target-only geometry."
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
        "fullbudget_probe": {
            "priorities": [0],
            "experiment_jobs": 1,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "One smoke-approved PL fold-3 graph spread-summary full-budget probe only.",
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


def report_lines(summary, probe_manifest, gates, smoke_metrics):
    lines = []
    lines.append("# PriceFM Stage-ZC Graph Spread-Summary Full-Budget Probe")
    lines.append("")
    lines.append(
        "This artifact prepares one launchable full-budget PL fold-3 probe after "
        "the diagnostic and smoke gates both passed."
    )
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append(markdown_table(pd.DataFrame([summary]).T.reset_index().rename(
        columns={"index": "field", 0: "value"}
    )))
    lines.append("")
    lines.append("## Probe Manifest")
    lines.append("")
    lines.append(markdown_table(probe_manifest))
    lines.append("")
    lines.append("## Decision Gates")
    lines.append("")
    lines.append(markdown_table(gates))
    lines.append("")
    lines.append("## Smoke Metrics")
    lines.append("")
    show = smoke_metrics.loc[
        smoke_metrics["split"].astype(str).eq("test") &
        smoke_metrics["unit"].astype(str).eq("original"),
        ["method_id", "AQL", "MAE", "RMSE"],
    ].copy()
    lines.append(markdown_table(show))
    lines.append("")
    lines.append("## Launch Command")
    lines.append("")
    lines.append("```sh")
    lines.append("application/data_local/pricefm/venv/bin/python application/scripts/pricefm/13_run_desn_experiment_grid.py \\")
    lines.append("  --grid-config {} \\".format(summary["grid_config"]))
    lines.append("  --priorities 0 --experiment-jobs 1 --cell-jobs 1 \\")
    lines.append("  --build-windows true --dry-run false --resume true --force true")
    lines.append("```")
    return "\n".join(lines) + "\n"


def input_manifest(args, smoke):
    specs = [
        ("stage_zc_summary", Path(args.stage_zc_dir) / "summary.json", "json"),
        ("smoke_launch_status", Path(args.smoke_grid_root) / "launch_status.csv", "csv"),
        ("smoke_metric_summary", smoke["metrics_path"], "csv"),
        ("smoke_feature_manifest", smoke["adapter_dir"] / "feature_manifest.json", "json"),
        ("smoke_feature_provenance", smoke["adapter_dir"] / "feature_provenance.csv", "csv"),
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
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and any(out_dir.iterdir()) and not args.force:
        raise FileExistsError("{} exists; rerun with --force true".format(out_dir))
    out_dir.mkdir(parents=True, exist_ok=True)

    stage_zc = read_json_required(Path(args.stage_zc_dir) / "summary.json", "Stage-ZC summary")
    validate_stage_zc(stage_zc)
    smoke = validate_smoke(args.smoke_grid_root, args.smoke_run_root, args.region, args.fold)
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

    probe_manifest = pd.DataFrame([{
        "experiment_id": experiment["id"],
        "region": args.region,
        "fold": int(args.fold),
        "feature_policy": experiment["feature_policy"],
        "neighbor_regions": json.dumps(experiment["neighbor_regions"]),
        "summary_stats": json.dumps(experiment["summary_stats"]),
        "train_origin_limit": int(args.train_origin_limit),
        "geometry_anchor": "stage_zb_anchor_pl_f3_l096_d1_n120",
        "input_scale": experiment["input_scale"],
        "seed": experiment["seed"],
        "launch_ready": True,
        "grid_config": config_path_value(args.grid_config),
        "generated_root": config_path_value(args.generated_root),
        "run_root": config_path_value(args.run_root),
    }])
    gates = pd.DataFrame([
        {
            "gate_id": "stage_zc_diagnostic_recommendation",
            "passed": True,
            "decision": stage_zc["recommended_next_contract"],
        },
        {
            "gate_id": "stage_zc_smoke_completed",
            "passed": True,
            "decision": "completed with finite metrics",
        },
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
            "gate_id": "spread_summary_policy",
            "passed": experiment["feature_policy"] == "graph_neighbor_spread_summary",
            "decision": experiment["feature_policy"],
        },
    ])
    if not gates["passed"].map(bool_value).all():
        raise ValueError("Stage-ZC full-budget gates failed.")

    summary = {
        "status": "prepared",
        "selected_region": args.region,
        "selected_fold": int(args.fold),
        "feature_policy": experiment["feature_policy"],
        "train_origin_limit": int(args.train_origin_limit),
        "launch_ready_rows": 1,
        "writes_launch_config": bool(args.write_grid),
        "grid_config": config_path_value(args.grid_config),
        "grid_config_sha256": sha256_file(repo_path(args.grid_config)) if args.write_grid else "",
        "generated_root": config_path_value(args.generated_root),
        "run_root": config_path_value(args.run_root),
        "output_dir": config_path_value(args.output_dir),
        "stage_zc_summary": config_path_value(Path(args.stage_zc_dir) / "summary.json"),
        "smoke_metric_summary": config_path_value(smoke["metrics_path"]),
        "smoke_adapter_dir": config_path_value(smoke["adapter_dir"]),
    }
    summary.update(repo_state())
    inputs = input_manifest(args, smoke)
    write_frame(out_dir / "stage_zc_fullbudget_input_manifest.csv", inputs)
    write_frame(out_dir / "stage_zc_fullbudget_probe_manifest.csv", probe_manifest)
    write_frame(out_dir / "stage_zc_fullbudget_decision_gates.csv", gates)
    write_json(out_dir / "summary.json", summary)
    (out_dir / "stage_zc_fullbudget_report.md").write_text(
        report_lines(summary, probe_manifest, gates, smoke["metrics"])
    )
    return summary


def main():
    args = parser().parse_args()
    summary = prepare(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
