#!/usr/bin/env python3
"""Prepare a Stage-K compact graph-summary PriceFM median grid.

Stage K is a regularized information-set follow-up to Stage J.  It avoids
another broad raw graph-khop sweep and instead tests compact graph summaries
under multiple seeds before any promotion decision.
"""

from __future__ import annotations

import argparse
import copy
import importlib.util
import json
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, write_json
from pricefm_graph import graph_scope_manifest


SCRIPT_DIR = Path(__file__).resolve().parent
STAGE_J_SCRIPT = SCRIPT_DIR / "61_prepare_pricefm_stage_j_information_set_rescue.py"
GRID_BLOCK = "pricefm_desn_experiment_grid"

DEFAULT_TEMPLATE = "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
DEFAULT_SOURCE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_k_instability_diagnostics_20260623/stage_j_candidate_flat.csv"
)
DEFAULT_OUTPUT_GRID = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_k_regularized_graph_20260623.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_k_regularized_graph_20260623"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_k_regularized_graph_20260623"
)
DEFAULT_SUMMARY_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_k_regularized_graph_plan_20260623"
)


def load_stage_j():
    spec = importlib.util.spec_from_file_location("pricefm_stage_j", STAGE_J_SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


STAGE_J = load_stage_j()
STAGE_H = STAGE_J.STAGE_H
STAGE_G = STAGE_J.STAGE_G


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE)
    p.add_argument("--source-csv", default=DEFAULT_SOURCE)
    p.add_argument("--output-grid-config", default=DEFAULT_OUTPUT_GRID)
    p.add_argument("--grid-id", default="pricefm_stage_k_regularized_graph_20260623")
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--summary-dir", default=DEFAULT_SUMMARY_DIR)
    p.add_argument("--seeds", default="20260624,20260625,20260626")
    p.add_argument(
        "--actions",
        default=(
            "try_regularized_graph_summary_multiseed,"
            "prefer_compact_summary_or_target_only,"
            "defer_or_reduce_graph_width"
        ),
    )
    p.add_argument("--max-rows", type=int, default=40)
    p.add_argument("--max-variants-per-row", type=int, default=4)
    p.add_argument("--candidate-source", default="stage_k_regularized_graph_20260623")
    p.add_argument("--stage-name", default="stage_k_regularized_graph")
    p.add_argument("--experiment-id-prefix", default="stagek")
    p.add_argument("--target-label", default="stage_k_regularized_graph_validation")
    p.add_argument("--launch-key", default="stage_k_regularized_graph")
    p.add_argument("--summary-prefix", default="stage_k_regularized_graph")
    p.add_argument("--write", type=parse_bool, default=True)
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
    return STAGE_J.config_path_value(path)


def row_value(row, key, default=None):
    return STAGE_J.row_value(row, key, default)


def parse_seeds(value):
    seeds = [int(x.strip()) for x in str(value).split(",") if x.strip()]
    if not seeds:
        raise ValueError("At least one seed is required.")
    return seeds


def parse_actions(value):
    actions = {x.strip() for x in str(value).split(",") if x.strip()}
    if not actions:
        raise ValueError("At least one Stage-K action is required.")
    return actions


def summary_metadata(region, input_regions, degree, statistic_set):
    degree = int(degree)
    graph = graph_scope_manifest(region, input_regions, degree)
    policy = "graph_summary_{}".format(statistic_set)
    return {
        "feature_policy": policy,
        "input_scope": "pricefm_{}_degree{}".format(policy, degree),
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "pricefm_released_graph_summary",
        "graph_degree": degree,
        "graph_source": "PriceFM.graph_adj_matrix",
        "graph_hash": graph["graph_hash"],
    }


def local_metadata():
    return STAGE_J.local_metadata()


def base_geometry(row):
    geom = STAGE_J.base_geometry(row)
    if "feature_dim" in row and row_value(row, "feature_dim") not in (None, ""):
        try:
            geom["feature_dim"] = int(float(row_value(row, "feature_dim")))
        except (TypeError, ValueError):
            pass
    return geom


def candidate_rows(source, args):
    if source.empty:
        raise ValueError("Stage-K source CSV has no rows.")
    actions = parse_actions(args.actions)
    out = source[source["stage_k_next_action"].astype(str).isin(actions)].copy()
    if out.empty:
        raise ValueError("No Stage-K rows match requested actions: {}".format(sorted(actions)))
    out["rank_key"] = pd.to_numeric(out.get("val_delta_vs_current", 0.0), errors="coerce").fillna(0.0)
    out = out.sort_values(["rank_key", "region", "fold"]).reset_index(drop=True)
    return out.head(int(args.max_rows))


def policy_variants(row, input_regions, args):
    region = str(row["region"])
    degree_raw = row_value(row, "graph_degree", 1)
    try:
        degree = max(1, int(float(degree_raw)))
    except (TypeError, ValueError):
        degree = 1
    degrees = [1]
    if degree >= 2:
        degrees.append(2)
    variants = []
    variants.append(("targetonly_guardrail", local_metadata()))
    for graph_degree in degrees:
        variants.append((
            "graphd{}_summary_mean".format(graph_degree),
            summary_metadata(region, input_regions, graph_degree, "mean"),
        ))
        variants.append((
            "graphd{}_summary_meanstd".format(graph_degree),
            summary_metadata(region, input_regions, graph_degree, "mean_std"),
        ))
    return variants[:int(args.max_variants_per_row)]


def variant_spec(row, tag, metadata, seed, args):
    region = str(row["region"])
    fold = int(row["fold"])
    geom = base_geometry(row)
    geom["seed"] = int(seed)
    geom["depth"] = int(len(geom["units"]))
    source_experiment = str(row_value(row, "experiment_id", row_value(row, "source_rescue_experiment_id", "")))
    spec = {
        "id": "{}_{}_f{}_{}_seed{}".format(
            str(args.experiment_id_prefix),
            STAGE_G.slug(region),
            fold,
            tag,
            int(seed),
        ),
        "stage": str(args.stage_name),
        "priority": 0,
        "regions": [region],
        "folds": [fold],
        "quantile": 0.50,
        "target_label": str(args.target_label),
        "selection_is_validation_only": True,
        "test_metrics_role": "audit_only",
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "candidate_source": str(args.candidate_source),
        "candidate_source_final": str(args.candidate_source),
        "source_stage_j_experiment_id": source_experiment,
        "stage_k_failure_class": str(row_value(row, "stage_k_failure_class", "")),
        "stage_k_next_action": str(row_value(row, "stage_k_next_action", "")),
        "rationale": (
            "{}: compact graph-summary median screen; region={}, fold={}, "
            "tag={}, seed={}, source_stage_j_experiment={}."
        ).format(str(args.stage_name), region, fold, tag, int(seed), source_experiment),
        "median_registry": {
            "region": region,
            "fold": fold,
            "source_experiment_id": source_experiment,
            "source_stage_k_failure_class": str(row_value(row, "stage_k_failure_class", "")),
            "source_stage_k_next_action": str(row_value(row, "stage_k_next_action", "")),
            "robustness_seed": int(seed),
        },
    }
    spec.update(geom)
    spec.update(metadata)
    for key in ["recurrent_sparsity", "state_output"]:
        value = row_value(row, key)
        if value not in (None, ""):
            spec[key] = value
    return spec


def data_config_regions(template_payload):
    data_config = template_payload[GRID_BLOCK]["base"]["data_config"]
    data = read_yaml(data_config)["pricefm"]
    return [str(x) for x in data["regions"]]


def build_grid(template_payload, rows, args):
    payload = copy.deepcopy(template_payload)
    if GRID_BLOCK not in payload:
        raise ValueError("Template grid must contain {}".format(GRID_BLOCK))
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = str(args.grid_id)
    grid["purpose"] = (
        "Stage-K compact graph-summary median screen generated from Stage-J "
        "instability diagnostics. Selection is median validation AQL only; "
        "test and PriceFM metrics remain audit fields."
    )
    grid["base"]["generated_root"] = str(args.generated_root)
    grid["base"]["run_root"] = str(args.run_root)
    grid["scope"]["regions"] = sorted(rows["region"].astype(str).unique().tolist())
    grid["scope"]["folds"] = sorted(int(x) for x in rows["fold"].unique())
    grid["scope"]["quantiles"] = [0.50]
    grid["experiments"] = []
    grid["experiment_blocks"] = []
    input_regions = data_config_regions(template_payload)
    seeds = parse_seeds(args.seeds)
    for _, row in rows.iterrows():
        for tag, metadata in policy_variants(row, input_regions, args):
            for seed in seeds:
                grid["experiments"].append(variant_spec(row, tag, metadata, seed, args))
    grid.setdefault("fixed", {})
    grid["fixed"]["stage_k_source_csv"] = config_path_value(args.source_csv)
    grid["fixed"]["stage_k_selection_rule"] = "median validation AQL only; test metrics audit-only"
    grid.setdefault("launch", {})
    grid["launch"][str(args.launch_key)] = {
        "priorities": [0],
        "experiment_jobs": 18,
        "cell_jobs": 1,
        "build_windows": True,
        "note": (
            "Run the generated grid through 13_run_desn_experiment_grid.py, then "
            "summarize with 62_summarize_pricefm_multiseed_median_screen.py."
        ),
    }
    return payload


def write_summary(summary_dir, args, rows, payload):
    out = repo_path(summary_dir)
    out.mkdir(parents=True, exist_ok=True)
    prefix = str(args.summary_prefix)
    rows.to_csv(out / "{}_source_rows.csv".format(prefix), index=False)
    exps = pd.DataFrame(payload[GRID_BLOCK]["experiments"])
    manifest_cols = [
        "id", "stage", "priority", "regions", "folds", "feature_policy",
        "graph_degree", "input_scope", "spatial_information_set",
        "source_stage_j_experiment_id", "stage_k_failure_class",
        "stage_k_next_action", "lag_window", "depth", "units", "alpha",
        "rho", "input_scale", "tau0", "seed", "run_dir", "full_config",
        "data_config",
    ]
    exps[[c for c in manifest_cols if c in exps.columns]].to_csv(
        out / "{}_experiment_manifest.csv".format(prefix),
        index=False,
    )
    exps_count = exps.copy()
    exps_count["region_key"] = exps_count["regions"].apply(lambda x: str(x[0]))
    exps_count["fold_key"] = exps_count["folds"].apply(lambda x: int(x[0]))
    counts = {
        "by_feature_policy": {
            str(k): int(v)
            for k, v in exps["feature_policy"].value_counts().sort_index().to_dict().items()
        },
        "by_region_fold": {
            "{}_fold{}".format(k[0], int(k[1])): int(v)
            for k, v in exps_count.groupby(["region_key", "fold_key"]).size().to_dict().items()
        },
        "by_failure_class": {
            str(k): int(v)
            for k, v in rows["stage_k_failure_class"].value_counts().sort_index().to_dict().items()
        },
    }
    summary = {
        "status": "completed",
        "grid_id": str(args.grid_id),
        "output_grid_config": config_path_value(args.output_grid_config),
        "generated_root": config_path_value(args.generated_root),
        "run_root": config_path_value(args.run_root),
        "summary_dir": config_path_value(out),
        "n_source_rows": int(rows.shape[0]),
        "n_experiments": int(exps.shape[0]),
        "counts": counts,
        "recommended_launch": (
            "application/data_local/pricefm/venv/bin/python "
            "application/scripts/pricefm/13_run_desn_experiment_grid.py "
            "--grid-config {} --priorities 0 --experiment-jobs 18 --cell-jobs 1 "
            "--build-windows true --resume true --dry-run false"
        ).format(config_path_value(args.output_grid_config)),
        "recommended_summary": (
            "application/data_local/pricefm/venv/bin/python "
            "application/scripts/pricefm/62_summarize_pricefm_multiseed_median_screen.py "
            "--manifest-csv {} --current-registry-csv <current_authoritative_registry.csv> "
            "--output-dir <stage_k_multiseed_summary_dir>"
        ).format(config_path_value(repo_path(args.generated_root) / "manifest.csv")),
    }
    write_json(out / "summary.json", summary)
    with open(out / "{}_plan_report.md".format(prefix), "w") as f:
        f.write("# PriceFM Stage-K Regularized Graph Plan\n\n")
        f.write("Grid config: `{}`\n\n".format(config_path_value(args.output_grid_config)))
        f.write("Experiments: `{}` across `{}` source rows.\n\n".format(
            int(exps.shape[0]), int(rows.shape[0])
        ))
        f.write("## Counts\n\n")
        for label, values in counts.items():
            f.write("### {}\n\n".format(label))
            f.write("| key | n |\n|---|---:|\n")
            for key, value in values.items():
                f.write("| {} | {} |\n".format(key, int(value)))
            f.write("\n")
        f.write("## Discipline\n\n")
        f.write("- This grid uses compact graph summaries, not raw graph-khop expansion.\n")
        f.write("- Every candidate is multi-seed by construction.\n")
        f.write("- Selection remains validation-only; test metrics are audit-only.\n")
        f.write("- Fit binaries should be cleaned after metrics/figures are materialized.\n")
    return summary


def prepare(args):
    if int(args.max_rows) < 1:
        raise ValueError("max-rows must be positive.")
    if int(args.max_variants_per_row) < 1:
        raise ValueError("max-variants-per-row must be positive.")
    template = read_yaml(args.template_grid_config)
    source = pd.read_csv(repo_path(args.source_csv))
    rows = candidate_rows(source, args)
    payload = build_grid(template, rows, args)
    if bool(args.write):
        write_yaml(args.output_grid_config, payload)
        return write_summary(args.summary_dir, args, rows, payload)
    return {
        "status": "planned",
        "n_source_rows": int(rows.shape[0]),
        "n_experiments": len(payload[GRID_BLOCK]["experiments"]),
    }


def main():
    args = parser().parse_args()
    summary = prepare(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
