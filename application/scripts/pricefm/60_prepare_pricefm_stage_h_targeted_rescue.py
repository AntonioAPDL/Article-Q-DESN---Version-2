#!/usr/bin/env python3
"""Prepare a Stage-H targeted PriceFM median rescue grid.

Stage H starts from the Stage-G seed-robust authoritative quantile registry.
It does not choose models from test metrics. It prepares a median-only,
validation-clean rescue grid for the remaining rows where the local
DESN/Q-DESN panel is close to, or worse than, the cached fold-aligned
PriceFM Phase-I benchmark.

The stage is deliberately narrower than a global search:

* priority 0: severe PriceFM fallbacks;
* priority 1: remaining PriceFM fallbacks;
* priority 2: close-to-PriceFM rows.

The generated candidates emphasize graph-khop information because the current
registry shows graph-khop rows convert substantially more often than
target-only rows. Test and PriceFM metrics are copied as audit metadata only.
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


SCRIPT_DIR = Path(__file__).resolve().parent
STAGE_G_SCRIPT = SCRIPT_DIR / "59_prepare_pricefm_stage_g_targeted_rescue.py"
GRID_BLOCK = "pricefm_desn_experiment_grid"

DEFAULT_TEMPLATE = "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
DEFAULT_MEDIAN_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_g_seedrob_patched_registry_20260622/"
    "patched_selection_registry.csv"
)
DEFAULT_DECISION_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_authoritative_quantile_decisions_stage_g_seedrob_20260622/"
    "authoritative_quantile_decision_registry.csv"
)
DEFAULT_OUTPUT_GRID = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_h_targeted_median_rescue_20260622.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_h_targeted_median_rescue_20260622"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_h_targeted_median_rescue_20260622"
)
DEFAULT_SUMMARY_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_h_targeted_median_rescue_plan_20260622"
)


def load_stage_g():
    spec = importlib.util.spec_from_file_location("pricefm_stage_g_rescue", STAGE_G_SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


STAGE_G = load_stage_g()


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE)
    p.add_argument("--median-registry-csv", default=DEFAULT_MEDIAN_REGISTRY)
    p.add_argument("--authoritative-decision-registry-csv", default=DEFAULT_DECISION_REGISTRY)
    p.add_argument("--output-grid-config", default=DEFAULT_OUTPUT_GRID)
    p.add_argument("--grid-id", default="pricefm_stage_h_targeted_median_rescue_20260622")
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--summary-dir", default=DEFAULT_SUMMARY_DIR)
    p.add_argument("--include-close", type=parse_bool, default=True)
    p.add_argument("--include-fallback", type=parse_bool, default=True)
    p.add_argument("--priority0-delta-abs", type=float, default=1.0)
    p.add_argument("--priority1-delta-abs", type=float, default=0.25)
    p.add_argument("--max-variants-priority0", type=int, default=24)
    p.add_argument("--max-variants-priority1", type=int, default=14)
    p.add_argument("--max-variants-priority2", type=int, default=8)
    p.add_argument("--candidate-source", default="stage_h_targeted_median_rescue_20260622")
    p.add_argument("--stage-name", default="stage_h_targeted_median_rescue")
    p.add_argument("--experiment-id-prefix", default="stageh")
    p.add_argument("--target-label", default="stage_h_targeted_median_rescue_validation")
    p.add_argument("--launch-key", default="stage_h_targeted_median_rescue")
    p.add_argument("--summary-prefix", default="stage_h_targeted_rescue")
    p.add_argument("--write", type=parse_bool, default=True)
    return p


def arg_value(args, name, default):
    return getattr(args, name, default)


def config_path_value(path):
    return STAGE_G.config_path_value(path)


def read_yaml(path):
    with open(repo_path(path), "r") as f:
        return yaml.safe_load(f)


def write_yaml(path, payload):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def as_float(row, key, default):
    return STAGE_G.as_float(row, key, default)


def as_int(row, key, default):
    return STAGE_G.as_int(row, key, default)


def row_value(row, key, default=None):
    return STAGE_G.row_value(row, key, default)


def base_geometry(row):
    return STAGE_G.base_geometry(row)


def local_metadata():
    return STAGE_G.local_metadata()


def graph_metadata(degree):
    return STAGE_G.graph_metadata(degree)


def stage_h_priority(row, args):
    decision = str(row_value(row, "stage_c_quantile_decision", ""))
    delta_abs = abs(as_float(row, "delta_abs", 0.0))
    if decision == "stage_c_local_close_to_pricefm":
        return 2
    if delta_abs >= float(args.priority0_delta_abs):
        return 0
    if delta_abs >= float(args.priority1_delta_abs):
        return 1
    return 1


def rescue_reason(row, args):
    decision = str(row_value(row, "stage_c_quantile_decision", ""))
    delta_abs = abs(as_float(row, "delta_abs", 0.0))
    if decision == "stage_c_local_close_to_pricefm":
        return "close_local_loss"
    if delta_abs >= float(args.priority0_delta_abs):
        return "severe_pricefm_fallback"
    return "moderate_pricefm_fallback"


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
        raise ValueError("No Stage-H rescue rows remain after decision filtering.")
    out["stage_h_rescue_reason"] = out.apply(lambda row: rescue_reason(row, args), axis=1)
    out["stage_h_rescue_priority"] = out.apply(lambda row: stage_h_priority(row, args), axis=1)
    out["selection_rule"] = "validation_AQL_median_only_test_pricefm_audit"
    out["test_metrics_role"] = "audit_only"
    return out.sort_values(
        ["stage_h_rescue_priority", "delta_abs", "region", "fold"],
        ascending=[True, False, True, True],
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
        raise ValueError("median registry missing Stage-H rows: {}".format(
            missing.to_dict("records")
        ))
    return out.sort_values(
        ["stage_h_rescue_priority", "delta_abs", "region", "fold"],
        ascending=[True, False, True, True],
    ).reset_index(drop=True)


def d1_units(units, factor=1.5, cap=280):
    base = int(units[-1] if units else 120)
    return [int(min(cap, max(80, round(base * factor / 20) * 20)))]


def d2_units(units):
    total = max(160, int(sum(units) if units else 180))
    each = int(max(60, min(160, round(total / 2 / 20) * 20)))
    return [each, each]


def d3_units(units):
    total = max(180, int(sum(units) if units else 240))
    each = int(max(40, min(140, round(total / 3 / 20) * 20)))
    return [each, each, each]


def variant_spec(row, tag, metadata, updates, args):
    region = str(row["region"])
    fold = int(row["fold"])
    geom = base_geometry(row)
    geom.update(updates or {})
    geom["depth"] = int(len(geom["units"]))
    spec = {
        "id": "{}_{}_f{}_{}".format(
            str(arg_value(args, "experiment_id_prefix", "stageh")),
            STAGE_G.slug(region),
            fold,
            tag,
        ),
        "stage": str(arg_value(args, "stage_name", "stage_h_targeted_median_rescue")),
        "priority": int(row["stage_h_rescue_priority"]),
        "regions": [region],
        "folds": [fold],
        "quantile": 0.50,
        "target_label": str(arg_value(args, "target_label", "stage_h_targeted_median_rescue_validation")),
        "selection_is_validation_only": True,
        "test_metrics_role": "audit_only",
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "candidate_source": str(args.candidate_source),
        "candidate_source_final": str(args.candidate_source),
        "stage_c_quantile_decision": str(row["stage_c_quantile_decision"]),
        "stage_h_rescue_reason": str(row["stage_h_rescue_reason"]),
        "authoritative_local_AQL": float(row["local_AQL"]),
        "authoritative_pricefm_AQL": float(row["pricefm_AQL"]),
        "authoritative_delta_abs": float(row["delta_abs"]),
        "authoritative_delta_rel": float(row["delta_rel"]),
        "rationale": (
            "{}: region={}, fold={}, tag={}, source_median_experiment={}, "
            "authoritative decision={}."
        ).format(
            str(arg_value(args, "stage_name", "stage_h_targeted_median_rescue")),
            region,
            fold,
            tag,
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
            "stage_h_rescue_reason": str(row["stage_h_rescue_reason"]),
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
    return STAGE_G.dedupe_variants(variants)


def graph_degrees_for_row(row, priority):
    feature_policy = str(row_value(row, "feature_policy", ""))
    current_degree = row_value(row, "graph_degree", None)
    degrees = [1, 2]
    if priority == 0:
        degrees.append(3)
    if feature_policy == "graph_khop" and current_degree not in (None, ""):
        try:
            degrees.insert(0, int(float(current_degree)))
        except (TypeError, ValueError):
            pass
    out = []
    for degree in degrees:
        if degree not in out:
            out.append(degree)
    return out


def candidate_variants(row, args):
    geom = base_geometry(row)
    alpha = float(geom["alpha"])
    rho = float(geom["rho"])
    input_scale = float(geom["input_scale"])
    lag = int(geom["lag_window"])
    units = list(geom["units"])
    priority = int(row["stage_h_rescue_priority"])
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
        add("targetonly_base", local_metadata())
        if priority == 0:
            add("targetonly_lag72", local_metadata(), {"lag_window": 72})
            add("targetonly_lag144", local_metadata(), {"lag_window": 144})

    for degree in graph_degrees_for_row(row, priority):
        meta = graph_metadata(degree)
        prefix = "graphd{}".format(degree)
        add("{}_base".format(prefix), meta)
        add("{}_input_low".format(prefix), meta, {"input_scale": STAGE_G.round_control(STAGE_G.clamp(input_scale * 0.70, 0.05, 1.0))})
        add("{}_input_mid".format(prefix), meta, {"input_scale": STAGE_G.round_control(STAGE_G.clamp(input_scale * 1.10, 0.05, 1.0))})
        add("{}_input_high".format(prefix), meta, {"input_scale": STAGE_G.round_control(STAGE_G.clamp(input_scale * 1.45, 0.05, 1.0))})
        add("{}_alpha_low".format(prefix), meta, {"alpha": STAGE_G.round_control(STAGE_G.clamp(alpha - 0.10, 0.10, 0.90))})
        add("{}_alpha_high".format(prefix), meta, {"alpha": STAGE_G.round_control(STAGE_G.clamp(alpha + 0.10, 0.10, 0.90))})
        add("{}_rho_low".format(prefix), meta, {"rho": STAGE_G.round_control(STAGE_G.clamp(rho - 0.08, 0.10, 1.25))})
        add("{}_rho_high".format(prefix), meta, {"rho": STAGE_G.round_control(STAGE_G.clamp(rho + 0.08, 0.10, 1.25))})
        if priority == 0:
            for candidate_lag in [48, 72, 96, 144, 192]:
                if int(candidate_lag) != lag:
                    add("{}_lag{}".format(prefix, candidate_lag), meta, {"lag_window": int(candidate_lag)})
            add("{}_d1_capacity".format(prefix), meta, {"units": d1_units(units)})
            add("{}_d2_compact".format(prefix), meta, {"units": d2_units(units)})
            add("{}_d3_compact".format(prefix), meta, {"units": d3_units(units)})

    # Close rows are cheap to include but should not crowd out severe
    # fallback work. A local anchor helps distinguish graph benefit from
    # ordinary reservoir perturbation on close cases.
    if priority == 2 and feature_policy != "graph_khop":
        add("targetonly_input_low", local_metadata(), {"input_scale": STAGE_G.round_control(STAGE_G.clamp(input_scale * 0.75, 0.05, 1.0))})
        add("targetonly_input_high", local_metadata(), {"input_scale": STAGE_G.round_control(STAGE_G.clamp(input_scale * 1.35, 0.05, 1.0))})

    return dedupe_variants(variants)[:max_variants]


def build_grid(template_payload, merged, args):
    payload = copy.deepcopy(template_payload)
    if GRID_BLOCK not in payload:
        raise ValueError("Template grid must contain {}".format(GRID_BLOCK))
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = str(args.grid_id)
    grid["purpose"] = (
        "{} generated from an authoritative seven-quantile decision registry. "
        "Selection is median validation AQL only; test and PriceFM metrics are "
        "audit fields."
    ).format(str(arg_value(args, "stage_name", "stage_h_targeted_median_rescue")))
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
    fixed_prefix = str(arg_value(args, "summary_prefix", "stage_h_targeted_rescue"))
    grid["fixed"]["{}_target_registry".format(fixed_prefix)] = config_path_value(args.authoritative_decision_registry_csv)
    grid["fixed"]["{}_median_registry".format(fixed_prefix)] = config_path_value(args.median_registry_csv)
    grid.setdefault("launch", {})
    priorities = sorted({int(exp["priority"]) for exp in grid["experiments"]})
    grid["launch"][str(arg_value(args, "launch_key", "stage_h_targeted_median_rescue"))] = {
        "priorities": priorities,
        "experiment_jobs": 20,
        "cell_jobs": 1,
        "build_windows": True,
        "note": (
            "Run --dry-run true first. Priority 0 contains severe fallbacks; "
            "priority 1 covers remaining fallbacks; priority 2 covers close rows."
        ),
    }
    return payload


def write_summary(summary_dir, args, scope, merged, payload):
    out = repo_path(summary_dir)
    out.mkdir(parents=True, exist_ok=True)
    prefix = str(arg_value(args, "summary_prefix", "stage_h_targeted_rescue"))
    scope.to_csv(out / "{}_scope.csv".format(prefix), index=False)
    merged.to_csv(out / "{}_source_rows.csv".format(prefix), index=False)
    exps = pd.DataFrame(payload[GRID_BLOCK]["experiments"])
    manifest_cols = [
        "id", "stage", "priority", "regions", "folds", "feature_policy",
        "graph_degree", "input_scope", "spatial_information_set",
        "stage_c_quantile_decision", "stage_h_rescue_reason",
        "lag_window", "depth", "units", "alpha", "rho", "input_scale",
        "tau0", "seed",
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
            for k, v in scope["stage_h_rescue_reason"].value_counts().to_dict().items()
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
            "--grid-config {} --priorities 0 --experiment-jobs 20 --cell-jobs 1 "
            "--build-windows true --resume true --dry-run false"
        ).format(config_path_value(args.output_grid_config)),
    }
    write_json(out / "summary.json", summary)
    with open(out / "{}_plan_report.md".format(prefix), "w") as f:
        f.write("# PriceFM {} Plan\n\n".format(
            str(arg_value(args, "stage_name", "stage_h_targeted_median_rescue")).replace("_", " ").title()
        ))
        f.write("This generated plan targets authoritative close/fallback rows.\n\n")
        f.write("Grid config: `{}`\n\n".format(config_path_value(args.output_grid_config)))
        f.write("Run root: `{}`\n\n".format(config_path_value(args.run_root)))
        f.write("Rescue rows: `{}`. Experiments: `{}`.\n\n".format(int(scope.shape[0]), int(exps.shape[0])))
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
        f.write("- Priority 0 severe fallback candidates run before lower-priority rows.\n")
        f.write("- Seed robustness is required before any seven-quantile promotion.\n")
        f.write("- Generated candidates use existing PriceFM DESN grid APIs.\n")
        f.write("- Large fit binaries should not be retained after successful metric extraction.\n")
    return summary


def prepare(args):
    for name in ["max_variants_priority0", "max_variants_priority1", "max_variants_priority2"]:
        if int(getattr(args, name)) < 1:
            raise ValueError("{} must be positive.".format(name.replace("_", "-")))
    template = read_yaml(args.template_grid_config)
    median = STAGE_G.read_median_registry(args.median_registry_csv)
    decisions = STAGE_G.read_decision_registry(args.authoritative_decision_registry_csv)
    scope = rescue_scope(decisions, args)
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
