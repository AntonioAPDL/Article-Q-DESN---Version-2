#!/usr/bin/env python3
"""Prepare a Stage-F graph-khop median rescue grid.

Stage F starts from the authoritative seven-quantile decision registry after
Stage E. It does not fit models. It prepares a validation-clean median-only
graph-khop rescue grid for region/folds where the local target-only DESN/Q-DESN
candidate is either close to PriceFM or still falls back to PriceFM.
"""

from __future__ import annotations

import argparse
import copy
import json
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
    "pricefm_authoritative_quantile_decisions_stage_e_20260619/"
    "authoritative_quantile_decision_registry.csv"
)
DEFAULT_OUTPUT_GRID = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_f_graph_median_rescue_20260620.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_f_graph_median_rescue_20260620"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_f_graph_median_rescue_20260620"
)
DEFAULT_SUMMARY_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_f_graph_median_rescue_plan_20260620"
)
TARGET_DECISIONS = {
    "stage_c_local_close_to_pricefm",
    "stage_c_pricefm_fallback",
}


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE)
    p.add_argument("--median-registry-csv", default=DEFAULT_MEDIAN_REGISTRY)
    p.add_argument("--authoritative-decision-registry-csv", default=DEFAULT_DECISION_REGISTRY)
    p.add_argument("--output-grid-config", default=DEFAULT_OUTPUT_GRID)
    p.add_argument("--grid-id", default="pricefm_stage_f_graph_median_rescue_20260620")
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--summary-dir", default=DEFAULT_SUMMARY_DIR)
    p.add_argument("--include-graph-rows", type=parse_bool, default=False)
    p.add_argument("--include-close", type=parse_bool, default=True)
    p.add_argument("--include-fallback", type=parse_bool, default=True)
    p.add_argument("--max-variants-per-row", type=int, default=12)
    p.add_argument("--candidate-source", default="stage_f_graph_median_rescue_20260620")
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
    return float(row_value(row, key, default))


def as_int(row, key, default):
    return int(row_value(row, key, default))


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


def expand_units(units, factor=1.5, step=20, cap=300):
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
        "seed": as_int(row, "seed", 20260620),
    }


def graph_metadata(graph_degree):
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


def require_columns(frame, columns, context):
    missing = set(columns) - set(frame.columns)
    if missing:
        raise ValueError("{} missing columns: {}".format(context, sorted(missing)))


def normalize_keys(frame):
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    return out


def read_median_registry(path):
    frame = pd.read_csv(repo_path(path))
    required = {
        "region", "fold", "experiment_id", "selected_method_id",
        "selected_on_split", "selected_on_unit", "selection_metric",
        "selection_metric_value", "selection_AQL", "test_AQL",
        "feature_map", "lag_window", "depth", "units", "alpha", "rho",
        "input_scale", "projection_scale", "tau0", "seed",
    }
    require_columns(frame, required, "median registry")
    frame = normalize_keys(frame)
    if frame.duplicated(["region", "fold"]).any():
        dup = frame[frame.duplicated(["region", "fold"], keep=False)]
        raise ValueError("median registry duplicate region/fold rows: {}".format(
            dup[["region", "fold"]].drop_duplicates().to_dict("records")
        ))
    return frame


def read_decision_registry(path):
    frame = pd.read_csv(repo_path(path))
    required = {
        "region", "fold", "stage_c_quantile_decision", "local_AQL",
        "pricefm_AQL", "delta_abs", "delta_rel", "feature_policy",
    }
    require_columns(frame, required, "authoritative decision registry")
    frame = normalize_keys(frame)
    if frame.duplicated(["region", "fold"]).any():
        dup = frame[frame.duplicated(["region", "fold"], keep=False)]
        raise ValueError("decision registry duplicate region/fold rows: {}".format(
            dup[["region", "fold"]].drop_duplicates().to_dict("records")
        ))
    return frame


def priority_for_row(row):
    decision = str(row_value(row, "stage_c_quantile_decision", ""))
    delta_rel = abs(as_float(row, "delta_rel", 0.0))
    if decision == "stage_c_local_close_to_pricefm":
        return 0
    if delta_rel >= 0.25:
        return 0
    if delta_rel >= 0.10:
        return 1
    return 2


def rescue_reason(row):
    decision = str(row_value(row, "stage_c_quantile_decision", ""))
    if decision == "stage_c_local_close_to_pricefm":
        return "close_local_loss"
    if decision == "stage_c_pricefm_fallback":
        delta_rel = abs(as_float(row, "delta_rel", 0.0))
        if delta_rel >= 0.25:
            return "severe_pricefm_fallback"
        if delta_rel >= 0.10:
            return "moderate_pricefm_fallback"
        return "mild_pricefm_fallback"
    return decision


def rescue_scope(decisions, args):
    targets = set()
    if bool(args.include_close):
        targets.add("stage_c_local_close_to_pricefm")
    if bool(args.include_fallback):
        targets.add("stage_c_pricefm_fallback")
    if not targets:
        raise ValueError("At least one of include-close/include-fallback must be true.")
    out = decisions[decisions["stage_c_quantile_decision"].astype(str).isin(targets)].copy()
    if not bool(args.include_graph_rows):
        out = out[~out["feature_policy"].astype(str).eq("graph_khop")].copy()
    if out.empty:
        raise ValueError("No Stage-F rescue rows remain after filtering.")
    out["stage_f_rescue_reason"] = out.apply(rescue_reason, axis=1)
    out["stage_f_rescue_priority"] = out.apply(priority_for_row, axis=1)
    out["selection_rule"] = "validation_AQL_median_only_test_pricefm_audit"
    out["test_metrics_role"] = "audit_only"
    return out.sort_values(["stage_f_rescue_priority", "region", "fold"]).reset_index(drop=True)


def merge_median(decisions, median):
    out = decisions.merge(
        median,
        on=["region", "fold"],
        how="left",
        suffixes=("_decision", ""),
        validate="one_to_one",
    )
    missing = out[out["experiment_id"].isna()][["region", "fold"]]
    if not missing.empty:
        raise ValueError("median registry missing Stage-F rows: {}".format(
            missing.to_dict("records")
        ))
    return out.sort_values(["stage_f_rescue_priority", "region", "fold"]).reset_index(drop=True)


def variant_spec(row, tag, graph_degree, updates, candidate_source):
    region = str(row["region"])
    fold = int(row["fold"])
    geom = base_geometry(row)
    geom.update(updates or {})
    geom["depth"] = int(len(geom["units"]))
    spec = {
        "id": "stagef_{}_f{}_{}".format(slug(region), fold, tag),
        "stage": "stage_f_graph_median_rescue",
        "priority": int(row["stage_f_rescue_priority"]),
        "regions": [region],
        "folds": [fold],
        "quantile": 0.50,
        "target_label": "stage_f_graph_median_rescue_validation",
        "selection_is_validation_only": True,
        "test_metrics_role": "audit_only",
        "candidate_source": str(candidate_source),
        "candidate_source_final": str(candidate_source),
        "stage_c_quantile_decision": str(row["stage_c_quantile_decision"]),
        "stage_f_rescue_reason": str(row["stage_f_rescue_reason"]),
        "authoritative_local_AQL": float(row["local_AQL"]),
        "authoritative_pricefm_AQL": float(row["pricefm_AQL"]),
        "authoritative_delta_abs": float(row["delta_abs"]),
        "authoritative_delta_rel": float(row["delta_rel"]),
        "rationale": (
            "Stage-F graph-informed median rescue: region={}, fold={}, tag={}, "
            "source_median_experiment={}, authoritative decision={}."
        ).format(region, fold, tag, row["experiment_id"], row["stage_c_quantile_decision"]),
        "median_registry": {
            "region": region,
            "fold": fold,
            "source_experiment_id": str(row["experiment_id"]),
            "source_selected_method_id": str(row["selected_method_id"]),
            "source_selection_AQL": float(row["selection_AQL"]),
            "source_test_AQL": float(row["test_AQL"]),
            "stage_c_quantile_decision": str(row["stage_c_quantile_decision"]),
            "stage_f_rescue_reason": str(row["stage_f_rescue_reason"]),
        },
    }
    spec.update(geom)
    spec.update(graph_metadata(graph_degree))
    for key in ["recurrent_sparsity", "state_output"]:
        value = row_value(row, key)
        if value not in (None, ""):
            spec[key] = value
    return spec


def candidate_variants(row, max_variants, candidate_source):
    geom = base_geometry(row)
    alpha = float(geom["alpha"])
    rho = float(geom["rho"])
    input_scale = float(geom["input_scale"])
    units = list(geom["units"])
    severe = str(row["stage_f_rescue_reason"]).startswith("severe")
    variants = []

    def add(tag, degree, updates=None):
        variants.append(variant_spec(row, tag, degree, updates or {}, candidate_source))

    for degree in [1, 2]:
        prefix = "graphd{}".format(degree)
        add("{}_base".format(prefix), degree)
        add("{}_input_lo".format(prefix), degree, {
            "input_scale": round_control(clamp(input_scale * 0.75, 0.05, 1.00)),
        })
        add("{}_input_hi".format(prefix), degree, {
            "input_scale": round_control(clamp(input_scale * 1.35, 0.05, 1.00)),
        })
        add("{}_alpha_lo".format(prefix), degree, {
            "alpha": round_control(clamp(alpha - 0.10, 0.10, 0.90)),
        })
        add("{}_alpha_hi".format(prefix), degree, {
            "alpha": round_control(clamp(alpha + 0.10, 0.10, 0.90)),
        })
        add("{}_rho_lo".format(prefix), degree, {
            "rho": round_control(clamp(rho - 0.08, 0.10, 1.25)),
        })
        add("{}_rho_hi".format(prefix), degree, {
            "rho": round_control(clamp(rho + 0.08, 0.10, 1.25)),
        })
        if severe:
            add("{}_units_hi".format(prefix), degree, {"units": expand_units(units)})

    deduped = []
    seen = set()
    for spec in variants:
        signature = json.dumps({
            "degree": spec["graph_degree"],
            "alpha": spec["alpha"],
            "rho": spec["rho"],
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
        "Stage-F graph-informed median rescue generated from the authoritative "
        "Stage-E seven-quantile decision registry. Selection is median "
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
    grid["launch"]["stage_f_graph_median_rescue"] = {
        "priorities": priorities,
        "experiment_jobs": min(12, max(1, len(grid["experiments"]))),
        "cell_jobs": 1,
        "build_windows": True,
        "note": (
            "Run dry first. Priority 0 contains close rows and severe "
            "fallbacks; later priorities broaden the graph rescue search."
        ),
    }
    return payload


def write_summary(summary_dir, args, scope, merged, payload):
    out = repo_path(summary_dir)
    out.mkdir(parents=True, exist_ok=True)
    scope.to_csv(out / "stage_f_graph_rescue_scope.csv", index=False)
    merged.to_csv(out / "stage_f_graph_rescue_source_rows.csv", index=False)
    exps = pd.DataFrame(payload[GRID_BLOCK]["experiments"])
    manifest_cols = [
        "id", "stage", "priority", "regions", "folds", "feature_policy",
        "graph_degree", "input_scope", "spatial_information_set",
        "stage_c_quantile_decision", "stage_f_rescue_reason",
        "lag_window", "depth", "units", "alpha", "rho", "input_scale",
        "tau0", "seed",
    ]
    exps[[c for c in manifest_cols if c in exps.columns]].to_csv(
        out / "stage_f_graph_rescue_experiment_manifest.csv",
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
        "by_graph_degree": {
            str(k): int(v)
            for k, v in exps["graph_degree"].value_counts().sort_index().to_dict().items()
        },
        "by_rescue_reason": {
            str(k): int(v)
            for k, v in scope["stage_f_rescue_reason"].value_counts().to_dict().items()
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
        "include_graph_rows": bool(args.include_graph_rows),
        "counts": counts,
        "selection_rule": "median validation AQL only; test and PriceFM metrics are audit only",
        "recommended_launch": (
            "application/data_local/pricefm/venv/bin/python "
            "application/scripts/pricefm/13_run_desn_experiment_grid.py "
            "--grid-config {} --experiment-jobs 10 --cell-jobs 1 "
            "--build-windows true --dry-run false --resume true"
        ).format(config_path_value(args.output_grid_config)),
    }
    write_json(out / "summary.json", summary)
    with open(out / "stage_f_graph_rescue_plan_report.md", "w") as f:
        f.write("# PriceFM Stage-F Graph Median Rescue Plan\n\n")
        f.write("This generated plan targets authoritative Stage-E close/fallback rows with graph-khop median candidates.\n\n")
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
        f.write("- Test and PriceFM metrics are audit fields only.\n")
        f.write("- Seven-quantile promotion waits until median rescue and seed robustness pass.\n")
        f.write("- Prior graph-khop rows are excluded by default to avoid re-auditing Stage-D rows.\n")
        f.write("- All generated candidates use `feature_policy = graph_khop`.\n")
    return summary


def prepare(args):
    if int(args.max_variants_per_row) < 1:
        raise ValueError("max-variants-per-row must be positive.")
    template = read_yaml(args.template_grid_config)
    median = read_median_registry(args.median_registry_csv)
    decisions = read_decision_registry(args.authoritative_decision_registry_csv)
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
