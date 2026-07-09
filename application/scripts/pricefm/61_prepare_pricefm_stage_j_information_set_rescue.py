#!/usr/bin/env python3
"""Prepare a Stage-J information-set PriceFM median rescue grid.

Stage J starts from the Stage-I authoritative quantile decision registry.  It
does not repeat the Stage-I unresolved sweep.  Instead, it builds a
validation-clean median-only grid focused on rows where a changed input
information set, especially PriceFM graph-neighbor inputs, is the most
plausible remaining lever.

Priority convention:

* priority 0: close local losses and near PriceFM fallbacks;
* priority 1: medium fallbacks where graph/input changes are still plausible;
* priority 2: hard fallbacks kept as optional diagnostics.

Test and cached PriceFM metrics are copied only as audit metadata.  Median
selection remains validation AQL only.
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
STAGE_H_SCRIPT = SCRIPT_DIR / "60_prepare_pricefm_stage_h_targeted_rescue.py"
GRID_BLOCK = "pricefm_desn_experiment_grid"

DEFAULT_TEMPLATE = "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
DEFAULT_MEDIAN_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_i_unresolved_seedrob_patched_registry_20260623/"
    "patched_selection_registry.csv"
)
DEFAULT_DECISION_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_authoritative_quantile_decisions_stage_i_unresolved_20260623/"
    "authoritative_quantile_decision_registry.csv"
)
DEFAULT_OUTPUT_GRID = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_j_information_set_rescue_20260623.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_j_information_set_rescue_20260623"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_j_information_set_rescue_20260623"
)
DEFAULT_SUMMARY_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_j_information_set_rescue_plan_20260623"
)


def load_stage_h():
    spec = importlib.util.spec_from_file_location("pricefm_stage_h_rescue", STAGE_H_SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


STAGE_H = load_stage_h()
STAGE_G = STAGE_H.STAGE_G


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE)
    p.add_argument("--median-registry-csv", default=DEFAULT_MEDIAN_REGISTRY)
    p.add_argument("--authoritative-decision-registry-csv", default=DEFAULT_DECISION_REGISTRY)
    p.add_argument("--output-grid-config", default=DEFAULT_OUTPUT_GRID)
    p.add_argument("--grid-id", default="pricefm_stage_j_information_set_rescue_20260623")
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--summary-dir", default=DEFAULT_SUMMARY_DIR)
    p.add_argument("--include-close", type=parse_bool, default=True)
    p.add_argument("--include-fallback", type=parse_bool, default=True)
    p.add_argument("--near-fallback-rel", type=float, default=0.06)
    p.add_argument("--hard-fallback-rel", type=float, default=0.18)
    p.add_argument("--max-variants-priority0", type=int, default=12)
    p.add_argument("--max-variants-priority1", type=int, default=8)
    p.add_argument("--max-variants-priority2", type=int, default=4)
    p.add_argument("--candidate-source", default="stage_j_information_set_rescue_20260623")
    p.add_argument("--stage-name", default="stage_j_information_set_rescue")
    p.add_argument("--experiment-id-prefix", default="stagej")
    p.add_argument("--target-label", default="stage_j_information_set_rescue_validation")
    p.add_argument("--launch-key", default="stage_j_information_set_rescue")
    p.add_argument("--summary-prefix", default="stage_j_information_set_rescue")
    p.add_argument("--write", type=parse_bool, default=True)
    return p


def config_path_value(path):
    return STAGE_H.config_path_value(path)


def read_yaml(path):
    with open(repo_path(path), "r") as f:
        return yaml.safe_load(f)


def write_yaml(path, payload):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def row_value(row, key, default=None):
    return STAGE_H.row_value(row, key, default)


def as_float(row, key, default):
    return STAGE_H.as_float(row, key, default)


def base_geometry(row):
    return STAGE_H.base_geometry(row)


def local_metadata():
    return STAGE_H.local_metadata()


def graph_metadata(degree):
    return STAGE_H.graph_metadata(degree)


def stage_j_reason(row):
    decision = str(row_value(row, "stage_c_quantile_decision", ""))
    feature_policy = str(row_value(row, "feature_policy", ""))
    if decision == "stage_c_local_close_to_pricefm":
        if feature_policy == "graph_khop":
            return "close_graph_geometry_refinement"
        return "close_target_only_graph_conversion"
    if feature_policy == "graph_khop":
        return "fallback_graph_geometry_refinement"
    return "fallback_target_only_graph_conversion"


def stage_j_priority(row, args):
    decision = str(row_value(row, "stage_c_quantile_decision", ""))
    delta_rel = as_float(row, "delta_rel", 0.0)
    if decision == "stage_c_local_close_to_pricefm":
        return 0
    if delta_rel <= float(args.near_fallback_rel):
        return 0
    if delta_rel >= float(args.hard_fallback_rel):
        return 2
    return 1


def rescue_scope(decisions, args):
    targets = set()
    if bool(args.include_close):
        targets.add("stage_c_local_close_to_pricefm")
    if bool(args.include_fallback):
        targets.add("stage_c_pricefm_fallback")
    if not targets:
        raise ValueError("At least one of include-close/include-fallback must be true.")
    out = decisions[decisions["stage_c_quantile_decision"].astype(str).isin(targets)].copy()
    if out.empty:
        raise ValueError("No Stage-J rescue rows remain after decision filtering.")
    out["stage_j_rescue_reason"] = out.apply(stage_j_reason, axis=1)
    out["stage_j_rescue_priority"] = out.apply(lambda row: stage_j_priority(row, args), axis=1)
    out["selection_rule"] = "validation_AQL_median_only_test_pricefm_audit"
    out["test_metrics_role"] = "audit_only"
    out["stage_j_information_set_action"] = out["stage_j_rescue_reason"].map({
        "close_target_only_graph_conversion": "add_pricefm_graph_inputs",
        "close_graph_geometry_refinement": "refine_existing_graph_geometry",
        "fallback_target_only_graph_conversion": "add_pricefm_graph_inputs",
        "fallback_graph_geometry_refinement": "refine_existing_graph_geometry",
    })
    return out.sort_values(
        ["stage_j_rescue_priority", "delta_rel", "region", "fold"],
        ascending=[True, True, True, True],
    ).reset_index(drop=True)


def merge_median(scope, median):
    out = scope.merge(
        median,
        on=["region", "fold"],
        how="left",
        suffixes=("_decision", ""),
        validate="one_to_one",
    )
    missing = out[out["experiment_id"].isna()][["region", "fold"]]
    if not missing.empty:
        raise ValueError("median registry missing Stage-J rows: {}".format(
            missing.to_dict("records")
        ))
    return out.sort_values(
        ["stage_j_rescue_priority", "delta_rel", "region", "fold"],
        ascending=[True, True, True, True],
    ).reset_index(drop=True)


def current_graph_degree(row):
    value = row_value(row, "graph_degree", None)
    if value in (None, ""):
        return None
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None


def unique(values):
    out = []
    for value in values:
        if value is None:
            continue
        value = int(value)
        if value not in out:
            out.append(value)
    return out


def graph_degrees_for_row(row):
    current = current_graph_degree(row)
    decision = str(row_value(row, "stage_c_quantile_decision", ""))
    feature_policy = str(row_value(row, "feature_policy", ""))
    if feature_policy == "graph_khop":
        degrees = [current, 1, 2]
    else:
        degrees = [1, 2]
    # Keep degree 2 optional for larger fallbacks, but never jump to degree 3
    # in this stage.  Stage J is an information-set rescue, not a feature-width
    # stress test.
    if decision == "stage_c_pricefm_fallback" and as_float(row, "delta_rel", 0.0) > 0.12:
        degrees = [1, current, 2]
    return unique(degrees)


def units_d1(units, cap=240):
    base = int(units[-1] if units else 120)
    return [int(min(cap, max(80, round(base * 1.35 / 20) * 20)))]


def units_d2(units):
    total = max(160, int(sum(units) if units else 180))
    each = int(max(60, min(140, round(total / 2 / 20) * 20)))
    return [each, each]


def units_d3(units):
    total = max(180, int(sum(units) if units else 240))
    each = int(max(40, min(120, round(total / 3 / 20) * 20)))
    return [each, each, each]


def variant_spec(row, tag, metadata, updates, args):
    region = str(row["region"])
    fold = int(row["fold"])
    geom = base_geometry(row)
    geom.update(updates or {})
    geom["depth"] = int(len(geom["units"]))
    spec = {
        "id": "{}_{}_f{}_{}".format(
            str(args.experiment_id_prefix),
            STAGE_G.slug(region),
            fold,
            tag,
        ),
        "stage": str(args.stage_name),
        "priority": int(row["stage_j_rescue_priority"]),
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
        "stage_c_quantile_decision": str(row["stage_c_quantile_decision"]),
        "stage_j_rescue_reason": str(row["stage_j_rescue_reason"]),
        "stage_j_information_set_action": str(row["stage_j_information_set_action"]),
        "authoritative_local_AQL": float(row["local_AQL"]),
        "authoritative_pricefm_AQL": float(row["pricefm_AQL"]),
        "authoritative_delta_abs": float(row["delta_abs"]),
        "authoritative_delta_rel": float(row["delta_rel"]),
        "rationale": (
            "{}: region={}, fold={}, tag={}, action={}, source_median_experiment={}, "
            "authoritative decision={}."
        ).format(
            str(args.stage_name),
            region,
            fold,
            tag,
            str(row["stage_j_information_set_action"]),
            row["experiment_id"],
            row["stage_c_quantile_decision"],
        ),
        "median_registry": {
            "region": region,
            "fold": fold,
            "source_experiment_id": str(row["experiment_id"]),
            "source_selected_method_id": str(row["selected_method_id"]),
            "source_selection_AQL": float(row["selection_AQL"]),
            "source_test_AQL": float(row["test_AQL"]),
            "stage_c_quantile_decision": str(row["stage_c_quantile_decision"]),
            "stage_j_rescue_reason": str(row["stage_j_rescue_reason"]),
            "stage_j_information_set_action": str(row["stage_j_information_set_action"]),
        },
    }
    spec.update(geom)
    spec.update(metadata)
    for key in ["recurrent_sparsity", "state_output"]:
        value = row_value(row, key)
        if value not in (None, ""):
            spec[key] = value
    return spec


def dedupe_variants(variants):
    return STAGE_H.dedupe_variants(variants)


def candidate_variants(row, args):
    geom = base_geometry(row)
    alpha = float(geom["alpha"])
    input_scale = float(geom["input_scale"])
    units = list(geom["units"])
    priority = int(row["stage_j_rescue_priority"])
    feature_policy = str(row_value(row, "feature_policy", ""))
    max_variants = {
        0: int(args.max_variants_priority0),
        1: int(args.max_variants_priority1),
        2: int(args.max_variants_priority2),
    }.get(priority, int(args.max_variants_priority2))
    variants = []

    def add(tag, metadata, updates=None):
        variants.append(variant_spec(row, tag, metadata, updates or {}, args))

    if feature_policy == "graph_khop":
        add("targetonly_guardrail", local_metadata())

    for degree in graph_degrees_for_row(row):
        meta = graph_metadata(degree)
        prefix = "graphd{}".format(degree)
        add("{}_base".format(prefix), meta)
        add("{}_input_low".format(prefix), meta, {
            "input_scale": STAGE_G.round_control(STAGE_G.clamp(input_scale * 0.70, 0.05, 1.0)),
        })
        add("{}_input_high".format(prefix), meta, {
            "input_scale": STAGE_G.round_control(STAGE_G.clamp(input_scale * 1.35, 0.05, 1.0)),
        })
        add("{}_alpha_low".format(prefix), meta, {
            "alpha": STAGE_G.round_control(STAGE_G.clamp(alpha - 0.10, 0.10, 0.90)),
        })
        add("{}_alpha_high".format(prefix), meta, {
            "alpha": STAGE_G.round_control(STAGE_G.clamp(alpha + 0.10, 0.10, 0.90)),
        })

    if priority == 0:
        # Add compact capacity variants only after the information-set variants.
        # These remain bounded and inherit whichever graph degree is most local
        # to the current row.
        degree = graph_degrees_for_row(row)[0]
        meta = graph_metadata(degree)
        add("graphd{}_d1_capacity".format(degree), meta, {"units": units_d1(units)})
        add("graphd{}_d2_compact".format(degree), meta, {"units": units_d2(units)})
        if feature_policy == "graph_khop":
            add("graphd{}_d3_compact".format(degree), meta, {"units": units_d3(units)})

    return dedupe_variants(variants)[:max_variants]


def attach_graph_scope_counts(scope, input_regions):
    out = scope.copy()
    n1 = []
    n2 = []
    for _, row in out.iterrows():
        region = str(row["region"])
        n1.append(graph_scope_manifest(region, input_regions, 1)["n_active_regions"])
        n2.append(graph_scope_manifest(region, input_regions, 2)["n_active_regions"])
    out["graph_degree1_active_regions"] = n1
    out["graph_degree2_active_regions"] = n2
    return out


def build_grid(template_payload, merged, args):
    payload = copy.deepcopy(template_payload)
    if GRID_BLOCK not in payload:
        raise ValueError("Template grid must contain {}".format(GRID_BLOCK))
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = str(args.grid_id)
    grid["purpose"] = (
        "Stage-J information-set median rescue generated from the Stage-I "
        "authoritative seven-quantile decision registry. Selection is median "
        "validation AQL only; test and PriceFM metrics are audit fields."
    )
    grid["base"]["generated_root"] = str(args.generated_root)
    grid["base"]["run_root"] = str(args.run_root)
    grid["scope"]["regions"] = sorted(merged["region"].astype(str).unique().tolist())
    grid["scope"]["folds"] = sorted(int(x) for x in merged["fold"].unique())
    grid["scope"]["quantiles"] = [0.50]
    grid["experiments"] = []
    grid["experiment_blocks"] = []
    for _, row in merged.iterrows():
        grid["experiments"].extend(candidate_variants(row, args))
    grid.setdefault("fixed", {})
    grid["fixed"]["stage_j_baseline_decision_registry"] = config_path_value(
        args.authoritative_decision_registry_csv
    )
    grid["fixed"]["stage_j_baseline_median_registry"] = config_path_value(
        args.median_registry_csv
    )
    grid.setdefault("launch", {})
    priorities = sorted({int(exp["priority"]) for exp in grid["experiments"]})
    grid["launch"][str(args.launch_key)] = {
        "priorities": priorities,
        "experiment_jobs": 18,
        "cell_jobs": 1,
        "build_windows": True,
        "note": (
            "Run --dry-run true first. Priority 0 contains close losses and "
            "near fallbacks; lower priorities should wait for priority-0 closeout."
        ),
    }
    return payload


def write_summary(summary_dir, args, scope, merged, payload):
    out = repo_path(summary_dir)
    out.mkdir(parents=True, exist_ok=True)
    prefix = str(args.summary_prefix)
    scope.to_csv(out / "{}_scope.csv".format(prefix), index=False)
    merged.to_csv(out / "{}_source_rows.csv".format(prefix), index=False)
    exps = pd.DataFrame(payload[GRID_BLOCK]["experiments"])
    manifest_cols = [
        "id", "stage", "priority", "regions", "folds", "feature_policy",
        "graph_degree", "input_scope", "spatial_information_set",
        "stage_c_quantile_decision", "stage_j_rescue_reason",
        "stage_j_information_set_action", "lag_window", "depth", "units",
        "alpha", "rho", "input_scale", "tau0", "seed",
    ]
    exps[[c for c in manifest_cols if c in exps.columns]].to_csv(
        out / "{}_experiment_manifest.csv".format(prefix),
        index=False,
    )
    counts = {
        "by_decision": {
            str(k): int(v)
            for k, v in scope["stage_c_quantile_decision"].value_counts().to_dict().items()
        },
        "by_priority": {
            str(k): int(v)
            for k, v in exps["priority"].value_counts().sort_index().to_dict().items()
        },
        "by_feature_policy": {
            str(k): int(v)
            for k, v in exps["feature_policy"].value_counts().sort_index().to_dict().items()
        },
        "by_rescue_reason": {
            str(k): int(v)
            for k, v in scope["stage_j_rescue_reason"].value_counts().to_dict().items()
        },
    }
    summary = {
        "status": "completed",
        "grid_id": str(args.grid_id),
        "output_grid_config": config_path_value(args.output_grid_config),
        "generated_root": config_path_value(args.generated_root),
        "run_root": config_path_value(args.run_root),
        "summary_dir": config_path_value(out),
        "n_rescue_rows": int(scope.shape[0]),
        "n_experiments": int(exps.shape[0]),
        "counts": counts,
        "selection_rule": "median validation AQL only; test and PriceFM metrics are audit only",
        "recommended_priority0_launch": (
            "application/data_local/pricefm/venv/bin/python "
            "application/scripts/pricefm/13_run_desn_experiment_grid.py "
            "--grid-config {} --priorities 0 --experiment-jobs 18 --cell-jobs 1 "
            "--build-windows true --resume true --dry-run false"
        ).format(config_path_value(args.output_grid_config)),
    }
    write_json(out / "summary.json", summary)
    with open(out / "{}_plan_report.md".format(prefix), "w") as f:
        f.write("# PriceFM Stage-J Information-Set Rescue Plan Artifacts\n\n")
        f.write("Grid config: `{}`\n\n".format(config_path_value(args.output_grid_config)))
        f.write("Run root: `{}`\n\n".format(config_path_value(args.run_root)))
        f.write("Rescue rows: `{}`. Experiments: `{}`.\n\n".format(
            int(scope.shape[0]), int(exps.shape[0])
        ))
        f.write("## Counts\n\n")
        for label, values in counts.items():
            f.write("### {}\n\n".format(label))
            f.write("| key | n |\n|---|---:|\n")
            for key, value in values.items():
                f.write("| {} | {} |\n".format(key, int(value)))
            f.write("\n")
        f.write("## Discipline\n\n")
        f.write("- Selection uses median validation AQL only.\n")
        f.write("- Test and cached PriceFM metrics remain audit fields only.\n")
        f.write("- Priority 0 contains close losses and near fallbacks.\n")
        f.write("- Seed robustness is required before any seven-quantile promotion.\n")
        f.write("- Generated candidates use existing PriceFM DESN grid APIs.\n")
        f.write("- Large fit binaries should not be retained after successful metric extraction.\n")
    return summary


def data_config_regions(template_payload):
    data_config = template_payload[GRID_BLOCK]["base"]["data_config"]
    data = read_yaml(data_config)["pricefm"]
    return [str(x) for x in data["regions"]]


def prepare(args):
    for name in ["max_variants_priority0", "max_variants_priority1", "max_variants_priority2"]:
        if int(getattr(args, name)) < 1:
            raise ValueError("{} must be positive.".format(name.replace("_", "-")))
    if float(args.near_fallback_rel) < 0.0 or float(args.hard_fallback_rel) < 0.0:
        raise ValueError("near/hard fallback thresholds must be non-negative.")
    if float(args.near_fallback_rel) >= float(args.hard_fallback_rel):
        raise ValueError("near-fallback-rel must be smaller than hard-fallback-rel.")
    template = read_yaml(args.template_grid_config)
    median = STAGE_G.read_median_registry(args.median_registry_csv)
    decisions = STAGE_G.read_decision_registry(args.authoritative_decision_registry_csv)
    scope = rescue_scope(decisions, args)
    scope = attach_graph_scope_counts(scope, data_config_regions(template))
    merged = merge_median(scope, median)
    payload = build_grid(template, merged, args)
    if bool(args.write):
        write_yaml(args.output_grid_config, payload)
        return write_summary(args.summary_dir, args, scope, merged, payload)
    return {
        "status": "planned",
        "n_rescue_rows": int(scope.shape[0]),
        "n_experiments": len(payload[GRID_BLOCK]["experiments"]),
    }


def main():
    args = parser().parse_args()
    summary = prepare(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
