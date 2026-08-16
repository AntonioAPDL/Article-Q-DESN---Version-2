#!/usr/bin/env python3
"""Prepare seed-robustness grids for queued graph/local median rescues."""

from __future__ import annotations

import argparse
import copy
import json

import pandas as pd
import yaml

from pricefm_common import repo_path, write_json


GRID_BLOCK = "pricefm_desn_experiment_grid"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-grid-config", required=True)
    p.add_argument("--seed-plan-csv", required=True)
    p.add_argument("--output-grid-config", required=True)
    p.add_argument("--grid-id", required=True)
    p.add_argument("--generated-root", required=True)
    p.add_argument("--run-root", required=True)
    p.add_argument("--summary-output", default=None)
    p.add_argument("--priority", type=int, default=0)
    p.add_argument("--candidate-source", default="graph_local_rescue_seed_robustness_20260616")
    return p


def read_yaml(path):
    with open(repo_path(path), "r") as f:
        return yaml.safe_load(f)


def write_yaml(path, payload):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def seed_slug(seed):
    return str(int(seed))


def source_experiment_index(source_grid):
    experiments = source_grid.get(GRID_BLOCK, {}).get("experiments", [])
    out = {}
    for exp in experiments:
        exp_id = str(exp.get("id", ""))
        if not exp_id:
            raise ValueError("Source grid contains an experiment without id.")
        if exp_id in out:
            raise ValueError("Source grid contains duplicate experiment id: {}".format(exp_id))
        out[exp_id] = exp
    return out


def required_seed_plan(seed_plan):
    required = {"region", "fold", "source_experiment_id", "robustness_seed"}
    missing = required - set(seed_plan.columns)
    if missing:
        raise ValueError("Seed plan missing required columns: {}".format(sorted(missing)))
    out = seed_plan.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = out["fold"].astype(int)
    out["robustness_seed"] = out["robustness_seed"].astype(int)
    if out.duplicated(["region", "fold", "source_experiment_id", "robustness_seed"]).any():
        dup = out[out.duplicated(["region", "fold", "source_experiment_id", "robustness_seed"], keep=False)]
        raise ValueError("Seed plan contains duplicate rows: {}".format(
            dup[["region", "fold", "source_experiment_id", "robustness_seed"]].to_dict("records")
        ))
    return out.sort_values(["region", "fold", "source_experiment_id", "robustness_seed"]).reset_index(drop=True)


def robustness_experiment(source_exp, plan_row, priority, candidate_source):
    exp = copy.deepcopy(source_exp)
    source_id = str(plan_row["source_experiment_id"])
    seed = int(plan_row["robustness_seed"])
    exp["id"] = "{}_seedrob{}".format(source_id, seed_slug(seed))
    exp["stage"] = "graph_local_median_rescue_seed_robustness"
    exp["priority"] = int(priority)
    exp["seed"] = seed
    exp["regions"] = [str(plan_row["region"])]
    exp["folds"] = [int(plan_row["fold"])]
    exp["quantile"] = 0.50
    exp["selection_is_validation_only"] = True
    exp["candidate_source"] = str(candidate_source)
    exp["candidate_source_final"] = str(candidate_source)
    exp["source_rescue_experiment_id"] = source_id
    exp["robustness_seed"] = seed
    exp["rationale"] = (
        "Seed-robustness rerun for queued graph/local median rescue: "
        "source_experiment={}, region={}, fold={}, seed={}."
    ).format(source_id, str(plan_row["region"]), int(plan_row["fold"]), seed)
    median_registry = copy.deepcopy(exp.get("median_registry", {}))
    median_registry["source_rescue_experiment_id"] = source_id
    median_registry["robustness_seed"] = seed
    median_registry["robustness_stage"] = "graph_local_median_rescue_seed_robustness"
    exp["median_registry"] = median_registry
    return exp


def build_grid(source_grid, seed_plan, args):
    if GRID_BLOCK not in source_grid:
        raise ValueError("Source grid missing {}".format(GRID_BLOCK))
    exp_idx = source_experiment_index(source_grid)
    payload = copy.deepcopy(source_grid)
    grid = payload[GRID_BLOCK]
    experiments = []
    missing = sorted(set(seed_plan["source_experiment_id"].astype(str)) - set(exp_idx))
    if missing:
        raise ValueError("Seed plan references unknown source experiments: {}".format(missing))
    for _, row in seed_plan.iterrows():
        source_exp = exp_idx[str(row["source_experiment_id"])]
        candidate_source = getattr(args, "candidate_source", "graph_local_rescue_seed_robustness_20260616")
        experiments.append(robustness_experiment(source_exp, row, int(args.priority), candidate_source))
    ids = [str(exp["id"]) for exp in experiments]
    if len(ids) != len(set(ids)):
        raise ValueError("Generated duplicate experiment ids.")
    grid["grid_id"] = str(args.grid_id)
    grid["purpose"] = (
        "Seed-robustness grid for graph/local median rescue candidates. "
        "This grid preserves the queued rescue geometry and changes only the "
        "random seed, experiment identity, stage, priority, and output roots."
    )
    grid["base"]["generated_root"] = str(args.generated_root)
    grid["base"]["run_root"] = str(args.run_root)
    grid["scope"]["regions"] = sorted(seed_plan["region"].astype(str).unique().tolist())
    grid["scope"]["folds"] = sorted(int(x) for x in seed_plan["fold"].unique())
    grid["scope"]["quantiles"] = [0.50]
    grid["experiments"] = experiments
    grid["experiment_blocks"] = []
    grid.setdefault("launch", {})
    grid["launch"]["rescue_seed_robustness"] = {
        "priorities": [int(args.priority)],
        "experiment_jobs": min(3, max(1, len(experiments))),
        "cell_jobs": 1,
        "build_windows": True,
        "note": "Run dry first; launch only after verifying one queued rescue fold.",
    }
    return payload


def main():
    args = parser().parse_args()
    source_grid = read_yaml(args.source_grid_config)
    seed_plan = required_seed_plan(pd.read_csv(repo_path(args.seed_plan_csv)))
    payload = build_grid(source_grid, seed_plan, args)
    write_yaml(args.output_grid_config, payload)
    summary = {
        "output_grid_config": config_path_value(args.output_grid_config),
        "grid_id": str(args.grid_id),
        "generated_root": config_path_value(args.generated_root),
        "run_root": config_path_value(args.run_root),
        "n_seed_plan_rows": int(seed_plan.shape[0]),
        "n_experiments": len(payload[GRID_BLOCK]["experiments"]),
        "regions": sorted(seed_plan["region"].astype(str).unique().tolist()),
        "folds": sorted(int(x) for x in seed_plan["fold"].unique()),
        "seeds": sorted(int(x) for x in seed_plan["robustness_seed"].unique()),
    }
    if args.summary_output:
        write_json(args.summary_output, summary)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
