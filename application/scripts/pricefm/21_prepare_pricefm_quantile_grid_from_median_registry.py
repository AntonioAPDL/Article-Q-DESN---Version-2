#!/usr/bin/env python3
"""Prepare a paper-quantile grid from selected median region/fold specs."""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import repo_path


GRID_BLOCK = "pricefm_desn_experiment_grid"
DEFAULT_QUANTILES = "0.10,0.25,0.45,0.50,0.55,0.75,0.90"
PROMOTION_METADATA_COLUMNS = [
    "feature_policy",
    "input_scope",
    "output_scope",
    "lead_covariate_status",
    "spatial_information_set",
    "graph_degree",
    "graph_source",
    "graph_hash",
    "final_decision",
    "candidate_source_final",
    "candidate_source",
    "selected_source",
    "changed_from_local",
    "selection_decision_rule",
    "selection_is_validation_only",
    "selected_on_split",
    "selected_on_unit",
    "selection_metric",
    "test_AQL",
    "test_MAE",
    "test_RMSE",
]


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--template-grid-config", required=True)
    p.add_argument("--registry-csv", required=True)
    p.add_argument("--output-grid-config", required=True)
    p.add_argument("--grid-id", required=True)
    p.add_argument("--generated-root", required=True)
    p.add_argument("--run-root", required=True)
    p.add_argument("--quantiles", default=DEFAULT_QUANTILES)
    p.add_argument("--priority", type=int, default=0)
    return p


def parse_quantiles(value):
    qs = [float(x.strip()) for x in str(value).split(",") if x.strip()]
    if not qs or qs != sorted(qs) or any(q <= 0.0 or q >= 1.0 for q in qs):
        raise ValueError("Quantiles must be sorted values in (0, 1).")
    return qs


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


def tau_slug(tau):
    return ("{:.4g}".format(float(tau))).replace(".", "p")


def row_value(row, key, default=""):
    if key not in row.index:
        return default
    value = row[key]
    if pd.isna(value):
        return default
    value = parse_jsonish(value)
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return value


def should_copy_metadata(value):
    if value is None:
        return False
    if isinstance(value, str) and value.strip() == "":
        return False
    return True


def spec_experiment(row, tau, priority):
    region = str(row["region"])
    fold = int(row["fold"])
    exp_id = "{}_fold{}_{}_tau{}".format(
        str(row["experiment_id"]),
        fold,
        region.lower().replace("_", ""),
        tau_slug(tau),
    )
    spec = {
        "id": exp_id,
        "stage": "paper_quantile_promoted",
        "priority": int(priority),
        "regions": [region],
        "folds": [fold],
        "feature_map": str(row["feature_map"]),
        "lag_window": int(row["lag_window"]),
        "depth": int(parse_jsonish(row["depth"])),
        "units": parse_jsonish(row["units"]),
        "alpha": float(parse_jsonish(row["alpha"])),
        "rho": float(parse_jsonish(row["rho"])),
        "input_scale": float(parse_jsonish(row["input_scale"])),
        "projection_scale": float(row["projection_scale"]),
        "tau0": float(row["tau0"]),
        "seed": int(row["seed"]),
        "quantile": float(tau),
        "rationale": (
            "Promoted from median validation registry: region={}, fold={}, "
            "median_experiment={}, selected_method={}, val_metric={}"
        ).format(
            region,
            fold,
            row["experiment_id"],
            row["selected_method_id"],
            row["selection_metric_value"],
        ),
    }
    spec["median_registry"] = {
        "region": region,
        "fold": fold,
        "median_experiment_id": str(row["experiment_id"]),
        "selected_method_id": str(row["selected_method_id"]),
        "selection_metric_value": float(row["selection_metric_value"]),
    }
    for key in PROMOTION_METADATA_COLUMNS:
        if key in row.index:
            value = row_value(row, key)
            if not should_copy_metadata(value):
                continue
            spec[key] = value
            spec["median_registry"][key] = spec[key]
    return spec


def build_grid(template_payload, registry, grid_id, generated_root, run_root,
               quantiles, priority):
    payload = copy.deepcopy(template_payload)
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = str(grid_id)
    grid["purpose"] = (
        "Paper-quantile promotion grid generated from the region-fold median "
        "selection registry. Each experiment is scoped to one selected "
        "region/fold/tau combination."
    )
    grid["base"]["generated_root"] = str(generated_root)
    grid["base"]["run_root"] = str(run_root)
    grid["scope"]["regions"] = sorted(registry["region"].astype(str).unique().tolist())
    grid["scope"]["folds"] = sorted(int(x) for x in registry["fold"].unique())
    grid["scope"]["quantiles"] = [float(x) for x in quantiles]
    grid["experiments"] = []
    grid["experiment_blocks"] = []
    for _, row in registry.sort_values(["region", "fold"]).iterrows():
        for tau in quantiles:
            grid["experiments"].append(spec_experiment(row, tau, priority))
    grid.setdefault("launch", {})
    grid["launch"]["paper_quantile_cells"] = {
        "priorities": [int(priority)],
        "experiment_jobs": min(8, max(1, len(grid["experiments"]))),
        "cell_jobs": 1,
        "build_windows": True,
        "note": (
            "Generated promotion grid. Launch with the grid runner; each "
            "experiment has a region/fold override from the median registry."
        ),
    }
    return payload


def main():
    args = parser().parse_args()
    template = read_yaml(args.template_grid_config)
    if GRID_BLOCK not in template:
        raise ValueError("Template grid must contain {}".format(GRID_BLOCK))
    registry = pd.read_csv(repo_path(args.registry_csv))
    required = {
        "region", "fold", "experiment_id", "selected_method_id",
        "selection_metric_value", "feature_map", "lag_window", "depth",
        "units", "alpha", "rho", "input_scale", "projection_scale",
        "tau0", "seed",
    }
    missing = required - set(registry.columns)
    if missing:
        raise ValueError("Registry missing required columns: {}".format(sorted(missing)))
    quantiles = parse_quantiles(args.quantiles)
    payload = build_grid(
        template,
        registry,
        args.grid_id,
        args.generated_root,
        args.run_root,
        quantiles,
        int(args.priority),
    )
    write_yaml(args.output_grid_config, payload)
    print(json.dumps({
        "output_grid_config": str(repo_path(args.output_grid_config)),
        "grid_id": args.grid_id,
        "n_registry_rows": int(registry.shape[0]),
        "n_quantiles": len(quantiles),
        "n_experiments": len(payload[GRID_BLOCK]["experiments"]),
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
