#!/usr/bin/env python3
"""Prepare a Stage-D graph-informed median rescue grid from Stage-C decisions.

Stage D is a validation-clean median-only rescue pass. It starts from the
Stage-C Priority-1 green seven-quantile decisions, targets close/fallback rows,
and clones the corresponding Stage-C median geometry while changing only the
input policy to graph-khop variants plus small local control perturbations.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import re

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, write_json
from pricefm_graph import graph_hash


GRID_BLOCK = "pricefm_desn_experiment_grid"
DEFAULT_TEMPLATE = "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
DEFAULT_MEDIAN_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_c_all_median_selection_20260618/median_selection_registry.csv"
)
DEFAULT_DECISION_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_c_priority1_green_quantile_decisions_20260618/"
    "stage_c_quantile_decision_registry.csv"
)
DEFAULT_OUTPUT_GRID = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_d_graph_median_rescue_20260619.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_d_graph_median_rescue_20260619"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_d_graph_median_rescue_20260619"
)
DEFAULT_SUMMARY_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_d_graph_median_rescue_plan_20260619"
)
TARGET_DECISIONS = {
    "stage_c_local_close_to_pricefm",
    "stage_c_pricefm_fallback",
}


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE)
    p.add_argument("--median-registry-csv", default=DEFAULT_MEDIAN_REGISTRY)
    p.add_argument("--stage-c-decision-registry-csv", default=DEFAULT_DECISION_REGISTRY)
    p.add_argument("--output-grid-config", default=DEFAULT_OUTPUT_GRID)
    p.add_argument("--grid-id", default="pricefm_stage_d_graph_median_rescue_20260619")
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--summary-dir", default=DEFAULT_SUMMARY_DIR)
    p.add_argument("--include-wins", type=parse_bool, default=False)
    p.add_argument("--max-variants-per-row", type=int, default=8)
    p.add_argument("--candidate-source", default="stage_d_graph_median_rescue_20260619")
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
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


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
    value = row_value(row, "units", [120])
    if isinstance(value, (list, tuple)):
        return [int(x) for x in value]
    return [int(value)]


def slug(value):
    text = str(value).strip().lower().replace("_", "")
    text = re.sub(r"[^a-z0-9]+", "", text)
    return text or "x"


def round_control(value):
    return float("{:.6g}".format(float(value)))


def clamp(value, low, high):
    return max(float(low), min(float(high), float(value)))


def expand_units(units, factor=1.5, step=20, cap=240):
    return [int(min(cap, max(step, round(int(u) * factor / step) * step))) for u in units]


def base_geometry(row):
    return {
        "feature_map": str(row_value(row, "feature_map", "window_reservoir_v1")),
        "lag_window": as_int(row, "lag_window", 96),
        "depth": as_int(row, "depth", len(units_list(row))),
        "units": units_list(row),
        "alpha": as_float(row, "alpha", 0.5),
        "rho": as_float(row, "rho", 0.9),
        "input_scale": as_float(row, "input_scale", 0.25),
        "projection_scale": as_float(row, "projection_scale", 1.0),
        "tau0": as_float(row, "tau0", 1.0e-3),
        "seed": as_int(row, "seed", 20260619),
    }


def spatial_metadata(graph_degree):
    degree = int(graph_degree)
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


def priority_for_decision(decision_row):
    decision = str(row_value(decision_row, "stage_c_quantile_decision", ""))
    delta_rel = abs(as_float(decision_row, "delta_rel", 0.0))
    if decision == "stage_c_local_close_to_pricefm":
        return 0
    if delta_rel <= 0.15:
        return 1
    return 2


def rescue_reason(decision_row):
    decision = str(row_value(decision_row, "stage_c_quantile_decision", ""))
    if decision == "stage_c_local_close_to_pricefm":
        return "close_local_loss"
    if decision == "stage_c_pricefm_fallback":
        return "pricefm_fallback"
    return decision


def rescue_scope_from_decisions(decisions, include_wins=False):
    required = {
        "region", "fold", "stage_c_quantile_decision", "local_AQL",
        "pricefm_AQL", "delta_abs", "delta_rel",
    }
    missing = required - set(decisions.columns)
    if missing:
        raise ValueError("Stage-C decision registry missing columns: {}".format(sorted(missing)))
    out = decisions.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = out["fold"].astype(int)
    targets = set(TARGET_DECISIONS)
    if bool(include_wins):
        targets.add("stage_c_confirmed_local_win")
    out = out[out["stage_c_quantile_decision"].astype(str).isin(targets)].copy()
    if out.empty:
        raise ValueError("No Stage-D rescue rows remain after decision filtering.")
    out["stage_d_rescue_reason"] = out.apply(rescue_reason, axis=1)
    out["stage_d_rescue_priority"] = out.apply(priority_for_decision, axis=1)
    out["selection_rule"] = "validation_AQL_median_only_test_audit"
    out["test_metrics_role"] = "audit_only"
    return out.sort_values(["stage_d_rescue_priority", "region", "fold"]).reset_index(drop=True)


def read_registry(path, label):
    frame = pd.read_csv(repo_path(path))
    required = {
        "region", "fold", "experiment_id", "selected_method_id",
        "selected_on_split", "selected_on_unit", "selection_metric",
        "selection_metric_value", "selection_AQL", "test_AQL",
        "feature_map", "lag_window", "depth", "units", "alpha", "rho",
        "input_scale", "projection_scale", "tau0", "seed",
    }
    missing = required - set(frame.columns)
    if missing:
        raise ValueError("{} missing columns: {}".format(label, sorted(missing)))
    frame = frame.copy()
    frame["region"] = frame["region"].astype(str)
    frame["fold"] = frame["fold"].astype(int)
    bad = frame[
        ~frame["selected_on_split"].astype(str).eq("val")
        | ~frame["selected_on_unit"].astype(str).eq("original")
        | ~frame["selection_metric"].astype(str).eq("AQL")
    ]
    if not bad.empty:
        raise ValueError("{} must be validation/original/AQL selected.".format(label))
    if frame.duplicated(["region", "fold"]).any():
        dup = frame[frame.duplicated(["region", "fold"], keep=False)]
        raise ValueError("{} has duplicate region/fold rows: {}".format(
            label, dup[["region", "fold"]].drop_duplicates().to_dict("records")
        ))
    return frame


def merged_rows(median_registry, rescue_scope):
    out = rescue_scope.merge(
        median_registry,
        on=["region", "fold"],
        how="left",
        validate="one_to_one",
        suffixes=("_decision", ""),
    )
    missing = out[out["experiment_id"].isna()][["region", "fold"]]
    if not missing.empty:
        raise ValueError("Median registry missing Stage-D rows: {}".format(
            missing.to_dict("records")
        ))
    return out.sort_values(["stage_d_rescue_priority", "region", "fold"]).reset_index(drop=True)


def variant_spec(row, tag, graph_degree, updates, candidate_source):
    region = str(row["region"])
    fold = int(row["fold"])
    geom = base_geometry(row)
    geom.update(updates or {})
    geom["depth"] = int(len(geom["units"]))
    exp_id = "staged_{}_f{}_{}".format(slug(region), fold, tag)
    spec = {
        "id": exp_id,
        "stage": "stage_d_graph_median_rescue",
        "priority": int(row["stage_d_rescue_priority"]),
        "regions": [region],
        "folds": [fold],
        "quantile": 0.50,
        "target_label": "stage_d_graph_median_rescue_validation",
        "selection_is_validation_only": True,
        "test_metrics_role": "audit_only",
        "candidate_source": str(candidate_source),
        "candidate_source_final": str(candidate_source),
        "stage_c_quantile_decision": str(row["stage_c_quantile_decision"]),
        "stage_d_rescue_reason": str(row["stage_d_rescue_reason"]),
        "stage_c_local_AQL": float(row["local_AQL"]),
        "stage_c_pricefm_AQL": float(row["pricefm_AQL"]),
        "stage_c_quantile_delta_abs": float(row["delta_abs"]),
        "stage_c_quantile_delta_rel": float(row["delta_rel"]),
        "rationale": (
            "Stage-D graph-informed median rescue: region={}, fold={}, tag={}, "
            "source_median_experiment={}, Stage-C decision={}."
        ).format(region, fold, tag, row["experiment_id"], row["stage_c_quantile_decision"]),
        "median_registry": {
            "region": region,
            "fold": fold,
            "source_experiment_id": str(row["experiment_id"]),
            "source_selected_method_id": str(row["selected_method_id"]),
            "source_selection_AQL": float(row["selection_AQL"]),
            "source_test_AQL": float(row["test_AQL"]),
            "stage_c_quantile_decision": str(row["stage_c_quantile_decision"]),
            "stage_d_rescue_reason": str(row["stage_d_rescue_reason"]),
        },
    }
    spec.update(geom)
    spec.update(spatial_metadata(graph_degree))
    for key in ["recurrent_sparsity", "state_output"]:
        value = row_value(row, key)
        if value not in (None, ""):
            spec[key] = value
    return spec


def candidate_variants(row, max_variants, candidate_source):
    geom = base_geometry(row)
    alpha = float(geom["alpha"])
    input_scale = float(geom["input_scale"])
    units = list(geom["units"])
    variants = []

    def add(tag, degree, updates=None):
        variants.append(variant_spec(row, tag, degree, updates or {}, candidate_source))

    add("graphd1_base", 1)
    add("graphd1_input_lo", 1, {"input_scale": round_control(clamp(input_scale * 0.75, 0.05, 1.00))})
    add("graphd1_input_hi", 1, {"input_scale": round_control(clamp(input_scale * 1.35, 0.05, 1.00))})
    add("graphd1_alpha_lo", 1, {"alpha": round_control(clamp(alpha - 0.10, 0.10, 0.80))})
    add("graphd1_alpha_hi", 1, {"alpha": round_control(clamp(alpha + 0.10, 0.10, 0.80))})
    add("graphd2_base", 2)
    add("graphd2_input_lo", 2, {"input_scale": round_control(clamp(input_scale * 0.75, 0.05, 1.00))})
    add("graphd2_input_hi", 2, {"input_scale": round_control(clamp(input_scale * 1.35, 0.05, 1.00))})
    if abs(float(row["delta_rel"])) >= 0.10:
        add("graphd1_units_hi", 1, {"units": expand_units(units)})
        add("graphd2_units_hi", 2, {"units": expand_units(units)})

    deduped = []
    seen = set()
    for spec in variants:
        signature = json.dumps({
            "degree": spec["graph_degree"],
            "alpha": spec["alpha"],
            "input_scale": spec["input_scale"],
            "units": spec["units"],
        }, sort_keys=True)
        if signature in seen:
            continue
        seen.add(signature)
        deduped.append(spec)
    return deduped[:int(max_variants)]


def build_grid(template_payload, merged, args):
    payload = copy.deepcopy(template_payload)
    if GRID_BLOCK not in payload:
        raise ValueError("Template grid must contain {}".format(GRID_BLOCK))
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = str(args.grid_id)
    grid["purpose"] = (
        "Stage-D graph-informed median rescue grid generated from Stage-C "
        "Priority-1 green quantile decisions. Selection remains validation-only; "
        "PriceFM and test metrics are audit fields."
    )
    grid["base"]["generated_root"] = str(args.generated_root)
    grid["base"]["run_root"] = str(args.run_root)
    grid["scope"]["regions"] = sorted(merged["region"].astype(str).unique().tolist())
    grid["scope"]["folds"] = sorted(int(x) for x in merged["fold"].unique())
    grid["scope"]["quantiles"] = [0.50]
    grid["experiments"] = []
    grid["experiment_blocks"] = []
    for _, row in merged.iterrows():
        grid["experiments"].extend(
            candidate_variants(row, args.max_variants_per_row, args.candidate_source)
        )
    grid.setdefault("fixed", {})
    grid["fixed"]["feature_policy"] = "graph_khop"
    grid["fixed"]["spatial"] = {
        "graph_source": "PriceFM.graph_adj_matrix",
        "graph_hash": graph_hash(),
    }
    grid.setdefault("launch", {})
    priorities = sorted({int(exp["priority"]) for exp in grid["experiments"]})
    grid["launch"]["stage_d_graph_median_rescue"] = {
        "priorities": priorities,
        "experiment_jobs": min(10, max(1, len(grid["experiments"]))),
        "cell_jobs": 1,
        "build_windows": True,
        "note": (
            "Run dry first. Launch priority 0 first if a narrow close-loss "
            "probe is desired; launch all priorities for the full median graph rescue."
        ),
    }
    return payload


def write_summary(summary_dir, args, rescue_scope, merged, payload):
    out = repo_path(summary_dir)
    out.mkdir(parents=True, exist_ok=True)
    rescue_scope.to_csv(out / "stage_d_graph_rescue_scope.csv", index=False)
    merged.to_csv(out / "stage_d_graph_rescue_source_rows.csv", index=False)
    exps = pd.DataFrame(payload[GRID_BLOCK]["experiments"])
    manifest_cols = [
        "id", "stage", "priority", "regions", "folds", "feature_policy",
        "graph_degree", "input_scope", "spatial_information_set",
        "stage_c_quantile_decision", "stage_d_rescue_reason",
        "lag_window", "depth", "units", "alpha", "rho", "input_scale",
        "tau0", "seed",
    ]
    exps[[c for c in manifest_cols if c in exps.columns]].to_csv(
        out / "stage_d_graph_rescue_experiment_manifest.csv",
        index=False,
    )
    counts = {
        "by_decision": {
            str(k): int(v)
            for k, v in rescue_scope["stage_c_quantile_decision"].value_counts().to_dict().items()
        },
        "by_priority": {
            str(k): int(v)
            for k, v in exps["priority"].value_counts().sort_index().to_dict().items()
        },
        "by_graph_degree": {
            str(k): int(v)
            for k, v in exps["graph_degree"].value_counts().sort_index().to_dict().items()
        },
    }
    summary = {
        "status": "completed",
        "grid_id": str(args.grid_id),
        "output_grid_config": config_path_value(args.output_grid_config),
        "generated_root": config_path_value(args.generated_root),
        "run_root": config_path_value(args.run_root),
        "summary_dir": config_path_value(out),
        "n_rescue_rows": int(rescue_scope.shape[0]),
        "n_experiments": int(exps.shape[0]),
        "counts": counts,
        "selection_rule": "median validation AQL only; test and PriceFM metrics are audit only",
        "recommended_launch": (
            "application/data_local/pricefm/venv/bin/python "
            "application/scripts/pricefm/13_run_desn_experiment_grid.py "
            "--grid-config {} --experiment-jobs 8 --cell-jobs 1 "
            "--build-windows true --dry-run false --resume true"
        ).format(config_path_value(args.output_grid_config)),
    }
    write_json(out / "summary.json", summary)
    with open(out / "stage_d_graph_rescue_plan_report.md", "w") as f:
        f.write("# PriceFM Stage-D Graph Median Rescue Plan\n\n")
        f.write("This generated plan targets Stage-C close/fallback rows with graph-khop median candidates.\n\n")
        f.write("Grid config: `{}`\n\n".format(config_path_value(args.output_grid_config)))
        f.write("Run root: `{}`\n\n".format(config_path_value(args.run_root)))
        f.write("Rescue rows: `{}`. Experiments: `{}`.\n\n".format(
            int(rescue_scope.shape[0]), int(exps.shape[0])
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
        f.write("- Test and PriceFM metrics are audit fields only.\n")
        f.write("- Seven-quantile promotion waits until median rescue and seed robustness pass.\n")
        f.write("- All candidates use `feature_policy = graph_khop`.\n")
    return summary


def prepare(args):
    template = read_yaml(args.template_grid_config)
    median = read_registry(args.median_registry_csv, "Stage-C median registry")
    decisions = pd.read_csv(repo_path(args.stage_c_decision_registry_csv))
    rescue_scope = rescue_scope_from_decisions(decisions, include_wins=args.include_wins)
    merged = merged_rows(median, rescue_scope)
    payload = build_grid(template, merged, args)
    if bool(args.write):
        write_yaml(args.output_grid_config, payload)
        return write_summary(args.summary_dir, args, rescue_scope, merged, payload)
    return {
        "status": "planned",
        "n_rescue_rows": int(rescue_scope.shape[0]),
        "n_experiments": len(payload[GRID_BLOCK]["experiments"]),
    }


def main():
    args = parser().parse_args()
    if int(args.max_variants_per_row) < 1:
        raise ValueError("max-variants-per-row must be positive.")
    summary = prepare(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
