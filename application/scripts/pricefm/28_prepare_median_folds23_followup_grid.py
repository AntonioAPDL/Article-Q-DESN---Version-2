#!/usr/bin/env python3
"""Prepare the PriceFM DE_LU fold 2/3 median follow-up seed grid."""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import repo_path, write_json


GRID_BLOCK = "pricefm_desn_experiment_grid"
DEFAULT_TEMPLATE = "application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_deep_targeted_20260603.yaml"
DEFAULT_P2_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_median_de_lu_folds23_p2_registry_20260603/"
    "median_selection_registry.csv"
)
DEFAULT_OUTPUT = "application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE)
    p.add_argument("--p2-registry-csv", default=DEFAULT_P2_REGISTRY)
    p.add_argument("--output-grid-config", default=DEFAULT_OUTPUT)
    p.add_argument("--summary-output", default=None)
    p.add_argument("--grid-id", default="pricefm_median_de_lu_folds23_followup_20260605")
    p.add_argument(
        "--generated-root",
        default="application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_folds23_followup_20260605",
    )
    p.add_argument(
        "--run-root",
        default="application/data_local/pricefm/runs/pricefm_median_de_lu_folds23_followup_20260605",
    )
    p.add_argument("--region", default="DE_LU")
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


def feature_dim_for(units, state_output="final_layer"):
    units = [int(x) for x in units]
    if str(state_output) == "concat_layers":
        return int(sum(units))
    return int(units[-1])


def geometry_key(row):
    return (
        str(row["region"]),
        int(row["fold"]),
        str(row["feature_map"]),
        int(row["lag_window"]),
        int(row["depth"]),
        tuple(int(x) for x in row["units"]),
        float(row["alpha"]),
        float(row["rho"]),
        float(row["input_scale"]),
        float(row["projection_scale"]),
        float(row["tau0"]),
        str(row["state_output"]),
    )


def registry_geometry(row):
    units = parse_jsonish(row["units"])
    units = units if isinstance(units, list) else [int(units)]
    state_output = str(row.get("state_output", "final_layer"))
    return {
        "source_role": "prior_p2_retest",
        "source_experiment_id": str(row["experiment_id"]),
        "source_method_id": str(row["selected_method_id"]),
        "region": str(row["region"]),
        "fold": int(row["fold"]),
        "feature_map": str(row["feature_map"]),
        "lag_window": int(row["lag_window"]),
        "depth": int(float(parse_jsonish(row["depth"]))),
        "units": [int(x) for x in units],
        "alpha": float(parse_jsonish(row["alpha"])),
        "rho": float(parse_jsonish(row["rho"])),
        "input_scale": float(parse_jsonish(row["input_scale"])),
        "projection_scale": float(row.get("projection_scale", 1.0)),
        "tau0": float(row["tau0"]),
        "feature_dim": feature_dim_for(units, state_output=state_output),
        "state_output": state_output,
    }


def fold3_refinement_geometries(region):
    rows = []
    for depth, units in [(1, [80]), (2, [80, 80])]:
        for input_scale in [0.25, 0.35, 0.50]:
            for rho in [0.90, 0.97]:
                for alpha in [0.40, 0.50]:
                    rows.append({
                        "source_role": "fold3_local_refine",
                        "source_experiment_id": "fold3_l96_n80_local_surface",
                        "source_method_id": "qdesn_exal_rhs_ns_exact_chunked",
                        "region": str(region),
                        "fold": 3,
                        "feature_map": "window_reservoir_v1",
                        "lag_window": 96,
                        "depth": int(depth),
                        "units": [int(x) for x in units],
                        "alpha": float(alpha),
                        "rho": float(rho),
                        "input_scale": float(input_scale),
                        "projection_scale": 1.0,
                        "tau0": 1.0e-3,
                        "feature_dim": feature_dim_for(units),
                        "state_output": "final_layer",
                    })
    return rows


def collect_geometries(registry, region):
    registry = registry[
        registry["region"].astype(str).eq(str(region))
        & registry["fold"].astype(int).isin({2, 3})
    ].copy()
    if registry.empty:
        raise ValueError("No P2 registry rows for region {} folds 2/3.".format(region))
    rows = [registry_geometry(row) for _, row in registry.iterrows()]
    rows.extend(fold3_refinement_geometries(region))
    dedup = {}
    for row in rows:
        key = geometry_key(row)
        if key not in dedup:
            dedup[key] = row
            continue
        prev = dedup[key]
        prev["source_role"] = "+".join(sorted(set(prev["source_role"].split("+") + row["source_role"].split("+"))))
        prev["source_experiment_id"] = "+".join(sorted(set(prev["source_experiment_id"].split("+") + row["source_experiment_id"].split("+"))))
    return sorted(
        dedup.values(),
        key=lambda x: (int(x["fold"]), str(x["source_role"]), int(x["depth"]), int(x["lag_window"]),
                       tuple(int(u) for u in x["units"]), float(x["alpha"]), float(x["rho"]), float(x["input_scale"])),
    )


def experiment_id(row, seed):
    role = str(row["source_role"]).replace("+", "plus").replace("_", "")
    return "fup_f{}_{}_l{}_d{}_n{}_a{}_r{}_in{}_seed{}".format(
        int(row["fold"]),
        role,
        int(row["lag_window"]),
        int(row["depth"]),
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
                "stage": "followup_seed_refine",
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
                "state_output": geom["state_output"],
                "rationale": (
                    "Fold {} follow-up seed/refinement geometry from role {}; source experiment {}; source method {}."
                ).format(
                    int(geom["fold"]),
                    geom["source_role"],
                    geom["source_experiment_id"],
                    geom["source_method_id"],
                ),
            }
            if exp["id"] in seen:
                raise ValueError("Duplicate generated experiment id: {}".format(exp["id"]))
            seen.add(exp["id"])
            rows.append(exp)
    return rows


def build_grid(template, grid_id, generated_root, run_root, region, experiments):
    payload = copy.deepcopy(template)
    if GRID_BLOCK not in payload:
        raise ValueError("Template missing {}".format(GRID_BLOCK))
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = str(grid_id)
    grid["purpose"] = (
        "Median follow-up grid for DE_LU folds 2/3: exact seed retests of prior "
        "P2 winners plus a fold-3 local L=96 n=80 refinement surface."
    )
    grid["base"]["generated_root"] = str(generated_root)
    grid["base"]["run_root"] = str(run_root)
    grid["scope"]["regions"] = [str(region)]
    grid["scope"]["folds"] = [2, 3]
    grid["scope"]["quantiles"] = [0.50]
    grid["experiments"] = experiments
    grid["experiment_blocks"] = []
    grid["launch"] = {
        "followup_seed_refine": {
            "priorities": [0],
            "experiment_jobs": 10,
            "cell_jobs": 1,
            "build_windows": True,
            "note": (
                "Launch only after dry-run validation. Selection uses validation metrics; "
                "test metrics remain audit-only."
            ),
        }
    }
    return payload


def main():
    args = parser().parse_args()
    seeds = parse_csv(args.seeds, int)
    template = read_yaml(args.template_grid_config)
    registry = read_csv_required(args.p2_registry_csv, "P2 registry")
    geometries = collect_geometries(registry, args.region)
    experiments = build_experiments(geometries, seeds)
    payload = build_grid(
        template,
        args.grid_id,
        args.generated_root,
        args.run_root,
        args.region,
        experiments,
    )
    write_yaml(args.output_grid_config, payload)
    summary = {
        "output_grid_config": str(repo_path(args.output_grid_config)),
        "grid_id": args.grid_id,
        "region": str(args.region),
        "seeds": seeds,
        "n_geometries": len(geometries),
        "n_experiments": len(experiments),
        "fold_counts": {
            str(fold): int(sum(1 for exp in experiments if int(exp["folds"][0]) == fold))
            for fold in [2, 3]
        },
    }
    if args.summary_output:
        write_json(args.summary_output, summary)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
