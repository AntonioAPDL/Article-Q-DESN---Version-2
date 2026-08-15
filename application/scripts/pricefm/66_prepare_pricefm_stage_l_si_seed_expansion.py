#!/usr/bin/env python3
"""Prepare the Stage-L SI fold-1 graph-summary seed expansion grid."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import copy

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, write_json


DEFAULT_SOURCE_GRID = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_k_regularized_graph_20260623.yaml"
)
DEFAULT_SOURCE_MANIFEST = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_k_regularized_graph_20260623/manifest.csv"
)
DEFAULT_OUTPUT_GRID = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_l_si_seed_expansion_20260624.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_l_si_seed_expansion_20260624"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_l_si_seed_expansion_20260624"
)
DEFAULT_SUMMARY_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_l_si_seed_expansion_plan_20260624"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-grid-config", default=DEFAULT_SOURCE_GRID)
    p.add_argument("--source-manifest-csv", default=DEFAULT_SOURCE_MANIFEST)
    p.add_argument("--output-grid-config", default=DEFAULT_OUTPUT_GRID)
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--summary-dir", default=DEFAULT_SUMMARY_DIR)
    p.add_argument("--grid-id", default="pricefm_stage_l_si_seed_expansion_20260624")
    p.add_argument("--source-experiment-id", default="stagek_si_f1_graphd2_summary_mean_seed20260624")
    p.add_argument("--existing-experiment-prefix", default="stagek_si_f1_graphd2_summary_mean_seed")
    p.add_argument("--new-seeds", default="20260627,20260628,20260629,20260630,20260631")
    p.add_argument("--existing-seeds", default="20260624,20260625,20260626")
    p.add_argument("--stage-name", default="stage_l_si_seed_expansion")
    p.add_argument("--candidate-source", default="stage_l_si_seed_expansion_20260624")
    p.add_argument("--experiment-prefix", default="stagel_si_f1_graphd2_summary_mean_seed")
    p.add_argument("--write", type=parse_bool, default=True)
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def parse_seeds(text):
    seeds = []
    for raw in str(text).split(","):
        raw = raw.strip()
        if raw:
            seeds.append(int(raw))
    if not seeds:
        raise ValueError("At least one seed is required.")
    if len(seeds) != len(set(seeds)):
        raise ValueError("Duplicate seeds are not allowed.")
    return seeds


def read_yaml(path):
    with open(repo_path(path), "r") as f:
        return yaml.safe_load(f)


def find_experiment(grid, experiment_id):
    experiments = grid["pricefm_desn_experiment_grid"].get("experiments", [])
    for exp in experiments:
        if str(exp.get("id")) == str(experiment_id):
            return exp
    raise ValueError("Source experiment not found: {}".format(experiment_id))


def new_experiment(source, seed, args):
    out = copy.deepcopy(source)
    exp_id = "{}{}".format(args.experiment_prefix, int(seed))
    out["id"] = exp_id
    out["stage"] = args.stage_name
    out["priority"] = 0
    out["seed"] = int(seed)
    out["candidate_source"] = args.candidate_source
    out["candidate_source_final"] = args.candidate_source
    out["target_label"] = "stage_l_si_seed_expansion_validation"
    out["rationale"] = (
        "stage_l_si_seed_expansion: SI fold 1 graph_summary_mean degree-2 "
        "expanded seed check; seed={}; source_stage_k_experiment={}."
    ).format(int(seed), args.source_experiment_id)
    median = dict(out.get("median_registry", {}))
    median["robustness_seed"] = int(seed)
    median["source_stage_l_parent_experiment_id"] = args.source_experiment_id
    median["source_stage_l_candidate_source"] = args.candidate_source
    out["median_registry"] = median
    return out


def existing_manifest_rows(source_manifest, args, existing_seeds):
    manifest = pd.read_csv(repo_path(source_manifest))
    ids = {"{}{}".format(args.existing_experiment_prefix, int(seed)) for seed in existing_seeds}
    rows = manifest[manifest["id"].astype(str).isin(ids)].copy()
    missing = sorted(ids - set(rows["id"].astype(str)))
    if missing:
        raise ValueError("Missing existing Stage-K manifest rows: {}".format(missing))
    return rows.sort_values("id")


def write_report(summary_dir, summary):
    report = summary_dir / "stage_l_si_seed_expansion_plan_report.md"
    with open(report, "w") as f:
        f.write("# PriceFM Stage-L SI Fold-1 Seed Expansion Plan\n\n")
        f.write("This plan prepares a narrow SI fold-1 median seed expansion for the ")
        f.write("Stage-K near-miss geometry. Selection remains validation-only; test ")
        f.write("metrics are audit-only.\n\n")
        f.write("## Summary\n\n")
        for key in sorted(summary):
            f.write("- {}: `{}`\n".format(key, summary[key]))
        f.write("\n## Launch\n\n")
        f.write("Dry-run first, then launch only if the generated count is expected.\n")
    return report


def prepare(args):
    source_grid = read_yaml(args.source_grid_config)
    block = copy.deepcopy(source_grid["pricefm_desn_experiment_grid"])
    source_exp = find_experiment(source_grid, args.source_experiment_id)
    new_seeds = parse_seeds(args.new_seeds)
    existing_seeds = parse_seeds(args.existing_seeds)

    block["grid_id"] = args.grid_id
    block["purpose"] = (
        "Stage-L narrow SI fold-1 graph-summary degree-2 expanded seed check. "
        "Median validation AQL controls selection; test metrics are audit-only."
    )
    block["base"]["generated_root"] = config_path_value(args.generated_root)
    block["base"]["run_root"] = config_path_value(args.run_root)
    block["scope"]["regions"] = ["SI"]
    block["scope"]["folds"] = [1]
    block["scope"]["quantiles"] = [0.5]
    block["fixed"]["stage_l_parent_grid"] = config_path_value(args.source_grid_config)
    block["fixed"]["stage_l_parent_manifest"] = config_path_value(args.source_manifest_csv)
    block["fixed"]["stage_l_selection_rule"] = "median validation AQL only; test metrics audit-only"
    block["launch"] = {
        "stage_l_si_seed_expansion": {
            "priorities": [0],
            "experiment_jobs": min(len(new_seeds), 8),
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Run after dry-run and current-decision-surface validation.",
        }
    }
    block["experiments"] = [new_experiment(source_exp, seed, args) for seed in new_seeds]

    out = {"pricefm_desn_experiment_grid": block}
    output_grid = repo_path(args.output_grid_config)
    summary_dir = repo_path(args.summary_dir)
    summary_dir.mkdir(parents=True, exist_ok=True)
    if bool(args.write):
        output_grid.parent.mkdir(parents=True, exist_ok=True)
        with open(output_grid, "w") as f:
            yaml.safe_dump(out, f, sort_keys=False)

    existing_rows = existing_manifest_rows(args.source_manifest_csv, args, existing_seeds)
    existing_manifest_path = summary_dir / "existing_stage_k_seed_manifest.csv"
    if bool(args.write):
        existing_rows.to_csv(existing_manifest_path, index=False)

    summary = {
        "grid_id": args.grid_id,
        "output_grid_config": config_path_value(output_grid),
        "generated_root": config_path_value(args.generated_root),
        "run_root": config_path_value(args.run_root),
        "summary_dir": config_path_value(summary_dir),
        "source_grid_config": config_path_value(args.source_grid_config),
        "source_manifest_csv": config_path_value(args.source_manifest_csv),
        "source_experiment_id": args.source_experiment_id,
        "n_existing_seed_rows": int(existing_rows.shape[0]),
        "existing_seeds": existing_seeds,
        "n_new_experiments": len(block["experiments"]),
        "new_seeds": new_seeds,
        "existing_manifest_csv": config_path_value(existing_manifest_path),
    }
    report = write_report(summary_dir, summary)
    summary["report"] = config_path_value(report)
    if bool(args.write):
        write_json(summary_dir / "prepare_summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    summary = prepare(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
