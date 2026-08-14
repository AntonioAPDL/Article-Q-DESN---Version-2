#!/usr/bin/env python3
"""Prepare a PriceFM median seed-robustness grid from retained and block winners."""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import repo_path, write_json


GRID_BLOCK = "pricefm_desn_experiment_grid"
DEFAULT_BASELINE_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_median_de_lu_folds23_selection_registry_20260602/"
    "median_selection_registry.csv"
)
DEFAULT_HORIZON_SELECTION = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_de_lu_folds23_horizon_block_selection_20260604/"
    "horizon_block_selection.csv"
)
DEFAULT_TEMPLATE = "application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_deep_targeted_20260603.yaml"
DEFAULT_OUTPUT = "application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_seed_robustness_20260604.yaml"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE)
    p.add_argument("--baseline-registry-csv", default=DEFAULT_BASELINE_REGISTRY)
    p.add_argument("--horizon-selection-csv", default=DEFAULT_HORIZON_SELECTION)
    p.add_argument("--output-grid-config", default=DEFAULT_OUTPUT)
    p.add_argument("--summary-output", default=None)
    p.add_argument("--grid-id", default="pricefm_median_de_lu_folds23_seed_robustness_20260604")
    p.add_argument(
        "--generated-root",
        default="application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_seed_robustness_20260604",
    )
    p.add_argument(
        "--run-root",
        default="application/data_local/pricefm/runs/pricefm_median_de_lu_folds23_seed_robustness_20260604",
    )
    p.add_argument("--region", default="DE_LU")
    p.add_argument("--folds", default="2,3")
    p.add_argument("--seeds", default="20260601,20260602,20260603,20260604,20260605")
    return p


def parse_csv(value, cast=str):
    if value is None or str(value).strip() == "":
        return []
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def read_yaml(path):
    with open(repo_path(path), "r") as f:
        return yaml.safe_load(f)


def write_yaml(path, payload):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def read_csv_required(path, context):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required CSV: {}".format(context, path))
    return pd.read_csv(path)


def parse_jsonish(value):
    if isinstance(value, str):
        text = value.strip()
        if text.startswith("[") or text.startswith("{") or text.startswith('"'):
            return json.loads(text)
    return value


def slug_value(value):
    if isinstance(value, (list, tuple)):
        return "x".join(slug_value(x) for x in value)
    text = "{:.8g}".format(float(value)) if isinstance(value, float) else str(value)
    return text.replace("-", "m").replace(".", "p").replace("+", "")


def geometry_from_row(row, source_role, horizon_group=None):
    units = parse_jsonish(row["units"])
    alpha = parse_jsonish(row["alpha"])
    rho = parse_jsonish(row["rho"])
    input_scale = parse_jsonish(row["input_scale"])
    depth = int(float(parse_jsonish(row["depth"])))
    return {
        "source_role": source_role,
        "source_horizon_group": horizon_group or "",
        "source_experiment_id": str(row["experiment_id"]),
        "source_method_id": str(row.get("selected_method_id", row.get("method_id", ""))),
        "region": str(row["region"]),
        "fold": int(row["fold"]),
        "feature_map": str(row["feature_map"]),
        "lag_window": int(row["lag_window"]),
        "depth": depth,
        "units": units if isinstance(units, list) else [int(units)],
        "alpha": float(alpha),
        "rho": float(rho),
        "input_scale": float(input_scale),
        "projection_scale": float(row.get("projection_scale", 1.0)),
        "tau0": float(row["tau0"]),
        "feature_dim": int(float(row["feature_dim"])),
    }


def geometry_key(row):
    return (
        row["region"], int(row["fold"]), row["feature_map"], int(row["lag_window"]),
        int(row["depth"]), tuple(int(x) for x in row["units"]), float(row["alpha"]),
        float(row["rho"]), float(row["input_scale"]), float(row["projection_scale"]),
        float(row["tau0"]),
    )


def collect_geometries(baseline, horizon_selection, region, folds):
    out = []
    baseline = baseline[
        baseline["region"].astype(str).eq(str(region))
        & baseline["fold"].astype(int).isin(set(folds))
    ].copy()
    horizon_selection = horizon_selection[
        horizon_selection["region"].astype(str).eq(str(region))
        & horizon_selection["fold"].astype(int).isin(set(folds))
    ].copy()
    for _, row in baseline.iterrows():
        out.append(geometry_from_row(row, "retained_global", "all"))
    for _, row in horizon_selection.iterrows():
        out.append(geometry_from_row(row, "horizon_block", str(row["horizon_group"])))
    dedup = {}
    for row in out:
        key = geometry_key(row)
        if key not in dedup:
            dedup[key] = row
            continue
        prev = dedup[key]
        prev["source_role"] = "+".join(sorted(set(str(prev["source_role"]).split("+") + [row["source_role"]])))
        groups = sorted(set(str(prev["source_horizon_group"]).split(",") + [str(row["source_horizon_group"])]))
        prev["source_horizon_group"] = ",".join(x for x in groups if x)
    return sorted(dedup.values(), key=lambda x: (x["fold"], x["source_role"], x["lag_window"], x["feature_dim"], x["rho"]))


def experiment_id(row, seed):
    role = str(row["source_role"]).replace("+", "plus").replace("_", "")
    group = str(row["source_horizon_group"]).replace("-", "to").replace(",", "_").replace("all", "all")
    return "seedrob_f{}_{}_h{}_l{}_n{}_a{}_r{}_in{}_seed{}".format(
        int(row["fold"]),
        role,
        group,
        int(row["lag_window"]),
        slug_value(row["units"]),
        slug_value(float(row["alpha"])),
        slug_value(float(row["rho"])),
        slug_value(float(row["input_scale"])),
        int(seed),
    )


def build_experiments(geometries, seeds):
    rows = []
    seen = set()
    for geom in geometries:
        for seed in seeds:
            exp = {
                "id": experiment_id(geom, seed),
                "stage": "seed_robustness",
                "priority": 0,
                "regions": [geom["region"]],
                "folds": [int(geom["fold"])],
                "feature_map": geom["feature_map"],
                "lag_window": int(geom["lag_window"]),
                "depth": int(geom["depth"]),
                "units": [int(x) for x in geom["units"]],
                "alpha": float(geom["alpha"]),
                "rho": float(geom["rho"]),
                "input_scale": float(geom["input_scale"]),
                "projection_scale": float(geom["projection_scale"]),
                "tau0": float(geom["tau0"]),
                "seed": int(seed),
                "quantile": 0.50,
                "rationale": (
                    "Seed robustness for {}, fold {}, horizon group {}, source experiment {}, source method {}."
                ).format(
                    geom["source_role"],
                    geom["fold"],
                    geom["source_horizon_group"],
                    geom["source_experiment_id"],
                    geom["source_method_id"],
                ),
            }
            if exp["id"] in seen:
                raise ValueError("Duplicate generated experiment id: {}".format(exp["id"]))
            seen.add(exp["id"])
            rows.append(exp)
    return rows


def build_grid(template, grid_id, generated_root, run_root, region, folds, experiments):
    payload = copy.deepcopy(template)
    if GRID_BLOCK not in payload:
        raise ValueError("Template missing {}".format(GRID_BLOCK))
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = str(grid_id)
    grid["purpose"] = (
        "Median seed-robustness grid for retained fold winners and validation-selected "
        "horizon-block specialists. This config is prepared for dry-run validation before launch."
    )
    grid["base"]["generated_root"] = str(generated_root)
    grid["base"]["run_root"] = str(run_root)
    grid["scope"]["regions"] = [str(region)]
    grid["scope"]["folds"] = [int(x) for x in folds]
    grid["scope"]["quantiles"] = [0.50]
    grid["experiments"] = experiments
    grid["experiment_blocks"] = []
    grid["launch"] = {
        "seed_robustness": {
            "priorities": [0],
            "experiment_jobs": 10,
            "cell_jobs": 1,
            "build_windows": True,
            "note": (
                "Prepared only. Launch after inspecting generated configs and confirming storage/CPU budget."
            ),
        }
    }
    return payload


def main():
    args = parser().parse_args()
    region = str(args.region)
    folds = parse_csv(args.folds, int)
    seeds = parse_csv(args.seeds, int)
    template = read_yaml(args.template_grid_config)
    baseline = read_csv_required(args.baseline_registry_csv, "baseline registry")
    horizon_selection = read_csv_required(args.horizon_selection_csv, "horizon selection")
    geometries = collect_geometries(baseline, horizon_selection, region, folds)
    experiments = build_experiments(geometries, seeds)
    payload = build_grid(
        template,
        args.grid_id,
        args.generated_root,
        args.run_root,
        region,
        folds,
        experiments,
    )
    write_yaml(args.output_grid_config, payload)
    summary = {
        "output_grid_config": str(repo_path(args.output_grid_config)),
        "grid_id": args.grid_id,
        "region": region,
        "folds": folds,
        "seeds": seeds,
        "n_geometries": len(geometries),
        "n_experiments": len(experiments),
    }
    if args.summary_output:
        write_json(args.summary_output, summary)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
