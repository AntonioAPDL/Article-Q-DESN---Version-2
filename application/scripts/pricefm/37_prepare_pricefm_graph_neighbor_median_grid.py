#!/usr/bin/env python3
"""Prepare a graph-neighbor PriceFM median grid from a median registry."""

from __future__ import annotations

import argparse
import copy
import json

import pandas as pd
import yaml

from pricefm_common import repo_path
from pricefm_graph import graph_hash


GRID_BLOCK = "pricefm_desn_experiment_grid"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--template-grid-config", required=True)
    p.add_argument("--registry-csv", required=True)
    p.add_argument("--output-grid-config", required=True)
    p.add_argument("--grid-id", required=True)
    p.add_argument("--generated-root", required=True)
    p.add_argument("--run-root", required=True)
    p.add_argument("--graph-degree", type=int, default=1)
    p.add_argument("--priority", type=int, default=0)
    p.add_argument("--candidate-source", default="graph_khop_degree1_20260614")
    return p


def read_yaml(path):
    with open(repo_path(path), "r") as f:
        return yaml.safe_load(f)


def write_yaml(path, payload):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def parse_jsonish(value):
    if isinstance(value, str):
        text = value.strip()
        if text.startswith("[") or text.startswith("{") or text.startswith('"'):
            return json.loads(text)
    return value


def parse_control(value):
    value = parse_jsonish(value)
    if isinstance(value, str):
        text = value.strip()
        try:
            return float(text)
        except ValueError:
            return value
    return value


def row_value(row, key, default=None):
    if key not in row.index:
        return default
    value = row[key]
    if pd.isna(value):
        return default
    value = parse_jsonish(value)
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return value


def slug_region(region):
    return str(region).lower().replace("_", "")


def graph_experiment(row, graph_degree, priority, candidate_source):
    region = str(row["region"])
    fold = int(row["fold"])
    source_exp = str(row["experiment_id"])
    exp_id = "{}_graphd{}_fold{}_{}".format(
        source_exp,
        int(graph_degree),
        fold,
        slug_region(region),
    )
    method = str(row.get("selected_method_id", row.get("method_id", "")))
    rationale = (
        "Graph-neighbor A/B candidate cloned from local-only median registry "
        "row: region={}, fold={}, source_experiment={}, source_method={}."
    ).format(region, fold, source_exp, method)
    spec = {
        "id": exp_id,
        "stage": "graph_neighbor_median_ab",
        "priority": int(priority),
        "regions": [region],
        "folds": [fold],
        "feature_policy": "graph_khop",
        "graph_degree": int(graph_degree),
        "graph_source": "PriceFM.graph_adj_matrix",
        "graph_hash": graph_hash(),
        "input_scope": "pricefm_graph_khop_degree{}".format(int(graph_degree)),
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "pricefm_released_graph_khop",
        "candidate_source": str(candidate_source),
        "candidate_source_final": str(candidate_source),
        "selection_is_validation_only": True,
        "target_label": "graph_neighbor_phase2_inspired_median_validation",
        "feature_map": str(row["feature_map"]),
        "lag_window": int(row["lag_window"]),
        "depth": int(parse_jsonish(row["depth"])),
        "units": parse_jsonish(row["units"]),
        "alpha": parse_control(row["alpha"]),
        "rho": parse_control(row["rho"]),
        "input_scale": parse_control(row["input_scale"]),
        "projection_scale": float(row["projection_scale"]),
        "tau0": float(row["tau0"]),
        "seed": int(row["seed"]),
        "quantile": 0.50,
        "rationale": rationale,
        "median_registry": {
            "region": region,
            "fold": fold,
            "median_experiment_id": source_exp,
            "selected_method_id": method,
            "selection_metric": row_value(row, "selection_metric", "AQL"),
            "selection_metric_value": float(row_value(row, "selection_metric_value", row_value(row, "selection_AQL", 0.0))),
            "candidate_source": row_value(row, "candidate_source_final", row_value(row, "candidate_source", "")),
        },
    }
    for key in ["recurrent_sparsity", "state_output"]:
        value = row_value(row, key)
        if value not in (None, ""):
            spec[key] = parse_control(value)
    return spec


def build_grid(template_payload, registry, grid_id, generated_root, run_root,
               graph_degree, priority, candidate_source):
    payload = copy.deepcopy(template_payload)
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = str(grid_id)
    grid["purpose"] = (
        "Median graph-neighbor A/B grid generated from the current local-only "
        "region/fold registry. Each experiment keeps the selected local DESN "
        "geometry and changes only the adapter feature policy to graph_khop."
    )
    grid["base"]["generated_root"] = str(generated_root)
    grid["base"]["run_root"] = str(run_root)
    grid["scope"]["regions"] = sorted(registry["region"].astype(str).unique().tolist())
    grid["scope"]["folds"] = sorted(int(x) for x in registry["fold"].unique())
    grid["scope"]["quantiles"] = [0.50]
    grid.setdefault("fixed", {})
    grid["fixed"]["feature_policy"] = "graph_khop"
    grid["fixed"]["spatial"] = {
        "graph_degree": int(graph_degree),
        "graph_source": "PriceFM.graph_adj_matrix",
        "graph_hash": graph_hash(),
    }
    grid["experiments"] = [
        graph_experiment(row, graph_degree, priority, candidate_source)
        for _, row in registry.sort_values(["region", "fold"]).iterrows()
    ]
    grid["experiment_blocks"] = []
    grid.setdefault("launch", {})
    grid["launch"]["graph_neighbor_ab"] = {
        "priorities": [int(priority)],
        "experiment_jobs": min(10, max(1, len(grid["experiments"]))),
        "cell_jobs": 1,
        "build_windows": True,
        "note": "Generated graph-neighbor median A/B grid. Run dry first, then launch in background.",
    }
    return payload


def main():
    args = parser().parse_args()
    if int(args.graph_degree) < 0:
        raise ValueError("graph-degree must be >= 0")
    template = read_yaml(args.template_grid_config)
    if GRID_BLOCK not in template:
        raise ValueError("Template grid must contain {}".format(GRID_BLOCK))
    registry = pd.read_csv(repo_path(args.registry_csv))
    required = {
        "region", "fold", "experiment_id", "feature_map", "lag_window",
        "depth", "units", "alpha", "rho", "input_scale",
        "projection_scale", "tau0", "seed",
    }
    missing = required - set(registry.columns)
    if missing:
        raise ValueError("Registry missing required columns: {}".format(sorted(missing)))
    payload = build_grid(
        template,
        registry,
        args.grid_id,
        args.generated_root,
        args.run_root,
        int(args.graph_degree),
        int(args.priority),
        args.candidate_source,
    )
    write_yaml(args.output_grid_config, payload)
    print(json.dumps({
        "output_grid_config": str(repo_path(args.output_grid_config)),
        "grid_id": args.grid_id,
        "graph_degree": int(args.graph_degree),
        "n_registry_rows": int(registry.shape[0]),
        "n_experiments": len(payload[GRID_BLOCK]["experiments"]),
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
