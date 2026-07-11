#!/usr/bin/env python3
"""Prepare non-launching PriceFM DESN experiment-grid configs."""

from __future__ import annotations

import argparse
import copy
import csv
import itertools
import json
from pathlib import Path

import yaml

from pricefm_common import repo_path, write_json
from pricefm_full_run import load_full_config


GRID_BLOCK = "pricefm_desn_experiment_grid"
EXPERIMENT_METADATA_FIELDS = [
    "feature_policy",
    "input_scope",
    "output_scope",
    "lead_covariate_status",
    "spatial_information_set",
    "graph_degree",
    "graph_source",
    "graph_hash",
    "neighbor_regions",
    "max_neighbor_regions",
    "target_lag_features",
    "target_lead_features",
    "neighbor_lag_features",
    "neighbor_lead_features",
    "summary_stats",
    "final_decision",
    "candidate_source_final",
    "candidate_source",
    "candidate_family",
    "factor_changed",
    "target_tier",
    "underperformance_delta_abs",
    "underperformance_delta_rel",
    "stage_n_rescue_reason",
    "selection_rule",
    "selection_is_validation_only",
    "selected_on_split",
    "selected_on_unit",
    "selection_metric",
    "test_metrics_role",
    "local_AQL",
    "pricefm_AQL",
    "test_AQL",
    "test_MAE",
    "test_RMSE",
    "horizon_focus",
    "horizon_weight_multiplier",
    "horizon_weighting_mode",
    "horizon_weighting_enabled",
    "readout_interaction",
    "horizon_block_size",
    "readout_interaction_basis",
]


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--grid-config",
        default="application/config/pricefm_desn_experiment_grid_median_de_lu_refine_20260601.yaml",
    )
    p.add_argument("--write", action="store_true", help="Write generated configs under the ignored grid root.")
    p.add_argument("--output-root", default=None, help="Override generated_root from the grid spec.")
    return p


def read_yaml(path):
    with open(repo_path(path), "r") as f:
        return yaml.safe_load(f)


def write_yaml(path, payload):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def require_keys(obj, keys, context):
    missing = [key for key in keys if key not in obj]
    if missing:
        raise ValueError("{} missing required keys: {}".format(context, ", ".join(missing)))


def slug_value(value):
    if isinstance(value, (list, tuple)):
        return "x".join(slug_value(x) for x in value)
    if isinstance(value, float):
        text = "{:.8g}".format(value)
    else:
        text = str(value)
    return text.replace("-", "m").replace(".", "p").replace("+", "").replace("e", "e")


def json_cell(value):
    if value is None:
        return ""
    if isinstance(value, (list, tuple, dict)):
        return json.dumps(value, sort_keys=True)
    return value


def infer_feature_dim(exp):
    if "feature_dim" in exp:
        return int(exp["feature_dim"])
    units = exp.get("units")
    if isinstance(units, (list, tuple)) and units:
        if str(exp.get("state_output", "final_layer")) == "concat_layers":
            return int(sum(int(x) for x in units))
        return int(units[-1])
    if units is not None:
        return int(units)
    raise ValueError("experiment {} needs feature_dim or units".format(exp.get("id", "")))


def experiment_quantiles(grid, exp):
    if "quantiles" in exp:
        qs = [float(x) for x in exp["quantiles"]]
    elif "quantile" in exp:
        qs = [float(exp["quantile"])]
    else:
        qs = [float(x) for x in grid["scope"]["quantiles"]]
    if not qs or qs != sorted(qs) or any(q <= 0.0 or q >= 1.0 for q in qs):
        raise ValueError(
            "experiment {} quantiles must be an increasing list in (0, 1)".format(exp.get("id", ""))
        )
    return qs


def experiment_regions(grid, exp):
    value = exp.get("regions", grid["scope"]["regions"])
    regions = [str(x) for x in value] if isinstance(value, (list, tuple)) else [str(value)]
    if not regions or any(not x for x in regions):
        raise ValueError("experiment {} regions must be nonempty".format(exp.get("id", "")))
    return regions


def experiment_folds(grid, exp):
    value = exp.get("folds", grid["scope"]["folds"])
    folds = [int(x) for x in value] if isinstance(value, (list, tuple)) else [int(value)]
    if not folds:
        raise ValueError("experiment {} folds must be nonempty".format(exp.get("id", "")))
    return folds


def experiment_feature_policy(grid, exp):
    fixed = grid.get("fixed", {})
    scope = grid.get("scope", {})
    return str(exp.get("feature_policy", fixed.get("feature_policy", scope.get("feature_policy", "target_only"))))


def experiment_training_config(grid, exp):
    fixed = grid.get("fixed", {})
    training = {
        "train_origin_limit": int(fixed["train_origin_limit"]),
        "train_origin_selection": str(fixed.get("train_origin_selection", "tail")),
    }
    if "training" in fixed:
        training.update(copy.deepcopy(fixed["training"]))
    if "training" in exp:
        training.update(copy.deepcopy(exp["training"]))

    enabled = exp.get("horizon_weighting_enabled", None)
    has_explicit = "horizon_weighting" in exp or "horizon_weight_multiplier" in exp
    if enabled is not None or has_explicit:
        current = copy.deepcopy(training.get("horizon_weighting", {}))
        if "horizon_weighting" in exp:
            current.update(copy.deepcopy(exp["horizon_weighting"]))
        if enabled is not None:
            current["enabled"] = bool(enabled)
        elif "enabled" not in current:
            current["enabled"] = False
        if "horizon_focus" in exp:
            current["focus"] = copy.deepcopy(exp["horizon_focus"])
        if "horizon_weight_multiplier" in exp:
            current["multiplier"] = float(exp["horizon_weight_multiplier"])
        if "horizon_weighting_mode" in exp:
            current["mode"] = str(exp["horizon_weighting_mode"])
        current.setdefault("mode", "integer_frequency_replication")
        current.setdefault("scope", "horizon_group")
        current.setdefault("apply_to", ["qdesn"])
        training["horizon_weighting"] = current
    return training


def experiment_spatial_config(grid, exp):
    fixed = grid.get("fixed", {})
    spatial = copy.deepcopy(fixed.get("spatial", {}))
    spatial.update(copy.deepcopy(exp.get("spatial", {})))
    if "graph_degree" in exp:
        spatial["graph_degree"] = int(exp["graph_degree"])
    elif "graph_degree" in fixed:
        spatial["graph_degree"] = int(fixed["graph_degree"])
    for key in [
        "neighbor_regions",
        "max_neighbor_regions",
        "target_lag_features",
        "target_lead_features",
        "neighbor_lag_features",
        "neighbor_lead_features",
        "summary_stats",
    ]:
        if key in exp:
            spatial[key] = copy.deepcopy(exp[key])
    return spatial


def expand_experiment_blocks(grid):
    experiments = [copy.deepcopy(exp) for exp in grid.get("experiments", [])]
    for block in grid.get("experiment_blocks", []):
        require_keys(block, ["id_prefix", "stage", "priority", "base", "factors"], "experiment block")
        base = copy.deepcopy(block["base"])
        factors = block["factors"]
        keys = list(factors.keys())
        values = [list(factors[key]) for key in keys]
        for combo in itertools.product(*values):
            exp = copy.deepcopy(base)
            suffix = []
            for key, value in zip(keys, combo):
                exp[key] = value
                suffix.append("{}{}".format(key, slug_value(value)))
            exp["id"] = "{}_{}".format(block["id_prefix"], "_".join(suffix))
            exp["stage"] = block["stage"]
            exp["priority"] = int(block["priority"])
            exp["feature_dim"] = infer_feature_dim(exp)
            if "rationale" in block and "rationale" not in exp:
                exp["rationale"] = block["rationale"]
            experiments.append(exp)
    return experiments


def load_grid(path):
    payload = read_yaml(path)
    if not isinstance(payload, dict) or GRID_BLOCK not in payload:
        raise ValueError("Grid config must contain top-level '{}'.".format(GRID_BLOCK))
    grid = payload[GRID_BLOCK]
    require_keys(grid, ["grid_id", "base", "scope", "fixed"], GRID_BLOCK)
    grid = copy.deepcopy(grid)
    grid["experiments"] = expand_experiment_blocks(grid)
    ids = [str(exp.get("id", "")) for exp in grid["experiments"]]
    if not ids or any(not x for x in ids):
        raise ValueError("Every experiment must have a nonempty id.")
    dup = sorted({x for x in ids if ids.count(x) > 1})
    if dup:
        raise ValueError("Duplicate experiment ids: {}".format(", ".join(dup)))
    for exp in grid["experiments"]:
        exp["feature_dim"] = infer_feature_dim(exp)
        require_keys(exp, ["id", "lag_window", "feature_dim", "tau0", "seed"], "experiment {}".format(exp.get("id")))
        experiment_quantiles(grid, exp)
        experiment_regions(grid, exp)
        experiment_folds(grid, exp)
        if "projection_scale" in exp and float(exp["projection_scale"]) <= 0.0:
            raise ValueError("experiment {} projection_scale must be positive".format(exp.get("id")))
    return grid


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def experiment_paths(grid, exp, generated_root):
    grid_id = str(grid["grid_id"])
    exp_id = str(exp["id"])
    root = repo_path(generated_root)
    cfg_dir = root / "configs"
    run_root = repo_path(grid["base"]["run_root"])
    return {
        "data_config": cfg_dir / "data" / "{}.yaml".format(exp_id),
        "full_config": cfg_dir / "full" / "{}.yaml".format(exp_id),
        "run_dir": run_root / exp_id,
        "adapter_root": run_root / exp_id / "cells",
        "manifest": root / "manifest.csv",
        "summary": root / "grid_summary.json",
    }


def build_experiment_config(grid, exp, generated_root):
    base_data = read_yaml(grid["base"]["data_config"])
    base_full = { "pricefm_desn_full": load_full_config(grid["base"]["full_config"]) }
    data_payload = copy.deepcopy(base_data)
    full_payload = copy.deepcopy(base_full)
    data = data_payload["pricefm"]
    full = full_payload["pricefm_desn_full"]
    fixed = grid["fixed"]
    scope = grid["scope"]
    paths = experiment_paths(grid, exp, generated_root)
    regions = experiment_regions(grid, exp)
    folds = experiment_folds(grid, exp)

    data["windows"]["lag_window"] = int(exp["lag_window"])
    data["windows"]["lead_window"] = int(fixed.get("lead_window", 96))
    data["pilot"]["region"] = str(regions[0])
    data["pilot"]["fold"] = int(folds[0])

    full["data_config"] = config_path_value(paths["data_config"])
    full["scope"]["regions"] = regions
    full["scope"]["folds"] = folds
    quantiles = experiment_quantiles(grid, exp)
    full["scope"]["quantiles"] = quantiles
    full["scope"]["horizons"] = scope.get("horizons", "all")
    feature_policy = experiment_feature_policy(grid, exp)
    full["scope"]["feature_policy"] = feature_policy
    full["training"] = experiment_training_config(grid, exp)
    full["adapter"]["output_root"] = config_path_value(paths["adapter_root"])
    full["adapter"]["feature_map"] = str(exp.get("feature_map", fixed.get("feature_map", "window_desn_v1")))
    full["adapter"]["feature_dim"] = int(exp["feature_dim"])
    full["adapter"]["seed"] = int(exp["seed"])
    full["adapter"]["include_intercept"] = bool(fixed.get("include_intercept", True))
    full["adapter"]["row_chunk_size"] = int(fixed.get("row_chunk_size", 512))
    full["adapter"]["projection_scale"] = float(exp.get("projection_scale", fixed.get("projection_scale", 1.0)))
    full["adapter"]["keep_matrices_after_success"] = False
    spatial = experiment_spatial_config(grid, exp)
    if spatial:
        full["adapter"]["spatial"] = spatial
    for key in [
        "depth", "units", "alpha", "rho", "input_scale",
        "recurrent_sparsity", "recurrent_density", "bias_scale",
        "reservoir_activation", "state_output", "readout_interaction",
        "horizon_block_size", "readout_interaction_basis",
    ]:
        if key in exp:
            full["adapter"][key] = copy.deepcopy(exp[key])
        elif key in fixed:
            full["adapter"][key] = copy.deepcopy(fixed[key])
    if "artifact_hygiene" in fixed:
        full["artifact_hygiene"] = copy.deepcopy(fixed["artifact_hygiene"])
    full["run"]["output_dir"] = config_path_value(paths["run_dir"])
    full["run"]["seed"] = int(exp["seed"])
    if "default_jobs" in fixed:
        full["run"]["default_jobs"] = int(fixed["default_jobs"])
    full["rhs_ns"]["tau0"] = float(exp["tau0"])
    full["rhs_ns"]["shrink_intercept"] = bool(fixed.get("shrink_intercept", False))
    full["qdesn_vb"]["likelihoods"] = list(fixed.get("qdesn_likelihoods", ["al", "exal"]))
    full["exact_equivalence"]["train_rows"] = int(fixed.get("exact_equivalence_train_rows", 1000))
    if len(quantiles) == 1:
        full["exact_equivalence"]["quantile"] = float(quantiles[0])
    metadata = {
        "grid_id": str(grid["grid_id"]),
        "experiment_id": str(exp["id"]),
        "stage": str(exp.get("stage", "")),
        "priority": int(exp.get("priority", 999)),
        "target_label": str(exp.get("target_label", "paper_quantile_from_median_registry")),
        "feature_policy": feature_policy,
    }
    if spatial:
        for key, value in spatial.items():
            metadata[key] = copy.deepcopy(value)
    for key in EXPERIMENT_METADATA_FIELDS:
        if key in exp:
            metadata[key] = copy.deepcopy(exp[key])
    if "median_registry" in exp:
        metadata["median_registry"] = copy.deepcopy(exp["median_registry"])
    full["comparison_metadata"] = metadata

    return paths, data_payload, full_payload


def prepare_grid(grid, generated_root, write=False):
    rows = []
    for exp in sorted(grid["experiments"], key=lambda x: (int(x.get("priority", 999)), str(x["id"]))):
        paths, data_payload, full_payload = build_experiment_config(grid, exp, generated_root)
        if write:
            write_yaml(paths["data_config"], data_payload)
            write_yaml(paths["full_config"], full_payload)
        row = {
            "id": str(exp["id"]),
            "stage": str(exp.get("stage", "")),
            "priority": int(exp.get("priority", 999)),
            "lag_window": int(exp["lag_window"]),
            "feature_map": str(exp.get("feature_map", grid["fixed"].get("feature_map", "window_desn_v1"))),
            "feature_policy": experiment_feature_policy(grid, exp),
            "feature_dim": int(exp["feature_dim"]),
            "projection_scale": float(exp.get("projection_scale", grid["fixed"].get("projection_scale", 1.0))),
            "depth": exp.get("depth", grid["fixed"].get("depth", "")),
            "units": json.dumps(exp.get("units", grid["fixed"].get("units", ""))),
            "alpha": json.dumps(exp.get("alpha", grid["fixed"].get("alpha", ""))),
            "rho": json.dumps(exp.get("rho", grid["fixed"].get("rho", ""))),
            "input_scale": json.dumps(exp.get("input_scale", grid["fixed"].get("input_scale", ""))),
            "recurrent_sparsity": json.dumps(exp.get(
                "recurrent_sparsity",
                exp.get("recurrent_density", grid["fixed"].get("recurrent_sparsity", "")),
            )),
            "state_output": str(exp.get("state_output", grid["fixed"].get("state_output", ""))),
            "readout_interaction": str(exp.get("readout_interaction", grid["fixed"].get("readout_interaction", "none"))),
            "horizon_block_size": exp.get("horizon_block_size", grid["fixed"].get("horizon_block_size", "")),
            "readout_interaction_basis": str(exp.get("readout_interaction_basis", grid["fixed"].get("readout_interaction_basis", ""))),
            "quantiles": json.dumps(experiment_quantiles(grid, exp)),
            "regions": json.dumps(experiment_regions(grid, exp)),
            "folds": json.dumps(experiment_folds(grid, exp)),
            "tau0": float(exp["tau0"]),
            "seed": int(exp["seed"]),
            "data_config": config_path_value(paths["data_config"]),
            "full_config": config_path_value(paths["full_config"]),
            "run_dir": config_path_value(paths["run_dir"]),
            "rationale": str(exp.get("rationale", "")),
        }
        training = experiment_training_config(grid, exp)
        horizon_weighting = training.get("horizon_weighting", {})
        row["horizon_weighting_enabled"] = bool(horizon_weighting.get("enabled", False))
        row["horizon_weighting_mode"] = str(horizon_weighting.get("mode", ""))
        row["horizon_focus"] = json_cell(horizon_weighting.get("focus", exp.get("horizon_focus", "")))
        row["horizon_weight_multiplier"] = json_cell(
            horizon_weighting.get("multiplier", exp.get("horizon_weight_multiplier", ""))
        )
        spatial = experiment_spatial_config(grid, exp)
        row["graph_degree"] = spatial.get("graph_degree", "")
        row["graph_source"] = spatial.get("graph_source", "")
        row["graph_hash"] = spatial.get("graph_hash", "")
        for key in EXPERIMENT_METADATA_FIELDS:
            if key in exp:
                row[key] = json_cell(exp[key])
            elif key not in row:
                row[key] = ""
        row["median_registry"] = json_cell(exp.get("median_registry", ""))
        rows.append(row)
    if write:
        manifest = repo_path(generated_root) / "manifest.csv"
        manifest.parent.mkdir(parents=True, exist_ok=True)
        with open(manifest, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)
        write_json(repo_path(generated_root) / "grid_summary.json", {
            "grid_id": grid["grid_id"],
            "n_experiments": len(rows),
            "manifest": config_path_value(manifest),
            "ranking": {
                "split": grid["scope"]["ranking_split"],
                "unit": grid["scope"]["ranking_unit"],
                "metric": grid["scope"]["ranking_metric"],
            },
        })
    return rows


def main():
    args = parser().parse_args()
    grid = load_grid(args.grid_config)
    generated_root = args.output_root or grid["base"]["generated_root"]
    rows = prepare_grid(grid, generated_root, write=bool(args.write))
    print(json.dumps({
        "grid_id": grid["grid_id"],
        "write": bool(args.write),
        "generated_root": config_path_value(generated_root),
        "n_experiments": len(rows),
        "experiments": rows,
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
