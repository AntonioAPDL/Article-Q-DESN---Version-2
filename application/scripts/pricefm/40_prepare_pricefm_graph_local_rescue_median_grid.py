#!/usr/bin/env python3
"""Prepare a targeted graph/local median rescue grid for weak PriceFM folds."""

from __future__ import annotations

import argparse
import copy
import json

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path
from pricefm_graph import graph_hash


GRID_BLOCK = "pricefm_desn_experiment_grid"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--template-grid-config", required=True)
    p.add_argument("--registry-csv", required=True)
    p.add_argument("--rescue-scope-csv", required=True)
    p.add_argument("--output-grid-config", required=True)
    p.add_argument("--grid-id", required=True)
    p.add_argument("--generated-root", required=True)
    p.add_argument("--run-root", required=True)
    p.add_argument("--priority-offset", type=int, default=0)
    p.add_argument("--include-close", type=parse_bool, default=True)
    p.add_argument("--max-variants-per-row", type=int, default=10)
    p.add_argument("--candidate-source", default="graph_local_rescue_20260615")
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


def as_float(row, key, default):
    value = row_value(row, key, default)
    return float(value)


def as_int(row, key, default):
    value = row_value(row, key, default)
    return int(value)


def units_list(row):
    units = row_value(row, "units")
    if isinstance(units, (list, tuple)):
        return [int(x) for x in units]
    if units is None:
        return [80, 80]
    return [int(units)]


def round_control(value):
    return float("{:.6g}".format(float(value)))


def clamp(value, low, high):
    return max(float(low), min(float(high), float(value)))


def expand_units(units, factor=1.5, step=20, cap=240):
    return [int(min(cap, max(step, round(int(u) * factor / step) * step))) for u in units]


def shrink_units(units, factor=0.75, step=20, floor=40):
    return [int(max(floor, round(int(u) * factor / step) * step)) for u in units]


def slug_region(region):
    return str(region).lower().replace("_", "")


def base_geometry(row):
    return {
        "feature_map": str(row_value(row, "feature_map", "window_reservoir_v1")),
        "lag_window": as_int(row, "lag_window", 96),
        "depth": as_int(row, "depth", len(units_list(row))),
        "units": units_list(row),
        "alpha": as_float(row, "alpha", 0.4),
        "rho": as_float(row, "rho", 0.9),
        "input_scale": as_float(row, "input_scale", 0.25),
        "projection_scale": as_float(row, "projection_scale", 1.0),
        "tau0": as_float(row, "tau0", 1.0e-3),
        "seed": as_int(row, "seed", 20260615),
    }


def spatial_metadata(feature_policy, graph_degree=None):
    if feature_policy == "graph_khop":
        degree = int(graph_degree if graph_degree is not None else 1)
        return {
            "feature_policy": "graph_khop",
            "graph_degree": degree,
            "graph_source": "PriceFM.graph_adj_matrix",
            "graph_hash": graph_hash(),
            "input_scope": "pricefm_graph_khop_degree{}".format(degree),
            "output_scope": "target_region_path",
            "lead_covariate_status": "realized_ex_post",
            "spatial_information_set": "pricefm_released_graph_khop",
        }
    return {
        "feature_policy": "target_only",
        "input_scope": "local_target_only",
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "local_only_not_pricefm_graph",
    }


def variant_row(row, rescue_row, tag, feature_policy, graph_degree, updates, priority, candidate_source):
    region = str(row["region"])
    fold = int(row["fold"])
    geom = base_geometry(row)
    geom.update(updates)
    geom["depth"] = int(len(geom["units"]))
    exp_id = "rescue_{}_f{}_{}".format(slug_region(region), fold, tag)
    spec = {
        "id": exp_id,
        "stage": "graph_local_median_rescue",
        "priority": int(priority),
        "regions": [region],
        "folds": [fold],
        "quantile": 0.50,
        "target_label": "graph_local_median_rescue_validation",
        "selection_is_validation_only": True,
        "candidate_source": str(candidate_source),
        "candidate_source_final": str(candidate_source),
        "rescue_action": str(row_value(rescue_row, "recommended_action", "")),
        "rescue_reason": str(row_value(rescue_row, "decision_label", "")),
        "pricefm_delta_rel_reference": as_float(rescue_row, "delta_rel", 0.0),
        "rationale": (
            "Targeted median rescue candidate for region={}, fold={}, tag={}; "
            "selection remains validation-only."
        ).format(region, fold, tag),
        "median_registry": {
            "region": region,
            "fold": fold,
            "source_experiment_id": str(row_value(row, "experiment_id", "")),
            "source_selected_method_id": str(row_value(row, "selected_method_id", row_value(row, "method_id", ""))),
            "source_selected_source": str(row_value(row, "selected_source", "")),
            "rescue_action": str(row_value(rescue_row, "recommended_action", "")),
        },
    }
    spec.update(geom)
    spec.update(spatial_metadata(feature_policy, graph_degree=graph_degree))
    if row_value(row, "recurrent_sparsity", None) not in (None, ""):
        spec["recurrent_sparsity"] = row_value(row, "recurrent_sparsity")
    if row_value(row, "state_output", None) not in (None, ""):
        spec["state_output"] = str(row_value(row, "state_output"))
    return spec


def candidate_variants(row, rescue_row, max_variants, candidate_source):
    selected_source = str(row_value(row, "selected_source", "local"))
    action = str(row_value(rescue_row, "recommended_action", ""))
    priority = int(row_value(rescue_row, "rescue_priority", 1))
    geom = base_geometry(row)
    alpha = float(geom["alpha"])
    input_scale = float(geom["input_scale"])
    units = list(geom["units"])
    variants = []

    def add(tag, feature_policy, degree, updates=None, bump=0):
        variants.append(
            variant_row(
                row,
                rescue_row,
                tag,
                feature_policy,
                degree,
                updates or {},
                priority + int(bump),
                candidate_source,
            )
        )

    # Always try the two graph scopes; degree 2 is the main apples-to-apples
    # expansion beyond the first graph-neighbor pass.
    add("graphd1_base", "graph_khop", 1)
    add("graphd2_base", "graph_khop", 2)
    add("graphd1_alpha_lo", "graph_khop", 1, {"alpha": round_control(clamp(alpha - 0.10, 0.10, 0.80))})
    add("graphd1_alpha_hi", "graph_khop", 1, {"alpha": round_control(clamp(alpha + 0.10, 0.10, 0.80))})
    add("graphd1_input_lo", "graph_khop", 1, {"input_scale": round_control(clamp(input_scale * 0.75, 0.05, 1.00))})
    add("graphd1_input_hi", "graph_khop", 1, {"input_scale": round_control(clamp(input_scale * 1.35, 0.05, 1.00))})
    add("graphd2_input_lo", "graph_khop", 2, {"input_scale": round_control(clamp(input_scale * 0.75, 0.05, 1.00))})
    add("graphd2_input_hi", "graph_khop", 2, {"input_scale": round_control(clamp(input_scale * 1.35, 0.05, 1.00))})

    if selected_source == "local" or "local" in action:
        add("local_alpha_lo", "target_only", None, {"alpha": round_control(clamp(alpha - 0.10, 0.10, 0.80))}, bump=1)
        add("local_input_hi", "target_only", None, {"input_scale": round_control(clamp(input_scale * 1.35, 0.05, 1.00))}, bump=1)

    if float(row_value(rescue_row, "delta_rel", 0.0)) >= 0.10:
        add("graphd1_units_hi", "graph_khop", 1, {"units": expand_units(units)}, bump=1)
        add("graphd2_units_hi", "graph_khop", 2, {"units": expand_units(units)}, bump=1)
        if str(row["region"]) == "NO_4":
            add("local_units_hi", "target_only", None, {"units": expand_units(units)}, bump=1)
            add("local_units_lo", "target_only", None, {"units": shrink_units(units)}, bump=2)

    # Preserve order while removing accidental duplicate ids/tags after clipping.
    deduped = []
    seen = set()
    for spec in variants:
        signature = json.dumps({
            "feature_policy": spec["feature_policy"],
            "graph_degree": spec.get("graph_degree", ""),
            "alpha": spec["alpha"],
            "input_scale": spec["input_scale"],
            "units": spec["units"],
        }, sort_keys=True)
        if signature in seen:
            continue
        seen.add(signature)
        deduped.append(spec)
    return deduped[:int(max_variants)]


def build_grid(template_payload, registry, rescue_scope, args):
    payload = copy.deepcopy(template_payload)
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = str(args.grid_id)
    grid["purpose"] = (
        "Targeted median rescue grid for graph/local PriceFM folds that lag or "
        "are close to PriceFM Phase-I after the graph/local seven-quantile pass."
    )
    grid["base"]["generated_root"] = str(args.generated_root)
    grid["base"]["run_root"] = str(args.run_root)
    grid["scope"]["regions"] = sorted(rescue_scope["region"].astype(str).unique().tolist())
    grid["scope"]["folds"] = sorted(int(x) for x in rescue_scope["fold"].unique())
    grid["scope"]["quantiles"] = [0.50]
    grid["experiments"] = []
    grid["experiment_blocks"] = []
    reg_idx = {
        (str(row["region"]), int(row["fold"])): row
        for _, row in registry.iterrows()
    }
    for _, rescue_row in rescue_scope.sort_values(["rescue_priority", "region", "fold"]).iterrows():
        key = (str(rescue_row["region"]), int(rescue_row["fold"]))
        row = reg_idx[key]
        variants = candidate_variants(row, rescue_row, args.max_variants_per_row, args.candidate_source)
        for spec in variants:
            spec["priority"] = int(args.priority_offset) + int(spec["priority"])
            grid["experiments"].append(spec)
    grid.setdefault("fixed", {})
    grid["fixed"]["feature_policy"] = "target_only"
    grid.setdefault("launch", {})
    grid["launch"]["targeted_rescue_median"] = {
        "priorities": sorted({int(exp["priority"]) for exp in grid["experiments"]}),
        "experiment_jobs": min(10, max(1, len(grid["experiments"]))),
        "cell_jobs": 1,
        "build_windows": True,
        "note": "Targeted median rescue. Run dry first; launch priority 0 before broadening.",
    }
    return payload


def filter_rescue_scope(scope, include_close):
    out = scope.copy()
    if not bool(include_close) and "decision_label" in out.columns:
        out = out[~out["decision_label"].astype(str).str.endswith("close_to_pricefm")]
    if out.empty:
        raise ValueError("Rescue scope is empty after filtering.")
    out["region"] = out["region"].astype(str)
    out["fold"] = out["fold"].astype(int)
    return out.sort_values(["rescue_priority", "region", "fold"]).reset_index(drop=True)


def main():
    args = parser().parse_args()
    template = read_yaml(args.template_grid_config)
    if GRID_BLOCK not in template:
        raise ValueError("Template grid must contain {}".format(GRID_BLOCK))
    registry = pd.read_csv(repo_path(args.registry_csv))
    rescue_scope = pd.read_csv(repo_path(args.rescue_scope_csv))
    required = {"region", "fold", "rescue_priority", "recommended_action", "delta_rel"}
    missing = required - set(rescue_scope.columns)
    if missing:
        raise ValueError("Rescue scope missing columns: {}".format(sorted(missing)))
    rescue_scope = filter_rescue_scope(rescue_scope, args.include_close)
    registry["region"] = registry["region"].astype(str)
    registry["fold"] = registry["fold"].astype(int)
    keys = set(zip(registry["region"], registry["fold"]))
    missing_keys = sorted(set(zip(rescue_scope["region"], rescue_scope["fold"])) - keys)
    if missing_keys:
        raise ValueError("Registry missing rescue rows: {}".format(missing_keys))
    payload = build_grid(template, registry, rescue_scope, args)
    write_yaml(args.output_grid_config, payload)
    print(json.dumps({
        "output_grid_config": str(repo_path(args.output_grid_config)),
        "grid_id": args.grid_id,
        "n_rescue_rows": int(rescue_scope.shape[0]),
        "n_experiments": len(payload[GRID_BLOCK]["experiments"]),
        "priorities": sorted({int(exp["priority"]) for exp in payload[GRID_BLOCK]["experiments"]}),
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
