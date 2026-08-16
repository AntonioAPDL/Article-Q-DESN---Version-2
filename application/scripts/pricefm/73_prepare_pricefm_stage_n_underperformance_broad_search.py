#!/usr/bin/env python3
"""Prepare a Stage-N underperformance-focused PriceFM median search grid.

Stage N is a selected-panel rescue stage.  It targets current region/fold rows
where the selected Q-DESN registry underperforms cached fold-aligned PriceFM
Phase-I predictions.  Target selection uses the current paper-grid test
comparison only to decide where to spend compute.  Candidate selection remains
median validation AQL only.
"""

from __future__ import annotations

import argparse
import ast
import copy
import hashlib
import json
import subprocess
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, sha256_file, write_json
from pricefm_graph import graph_hash


GRID_BLOCK = "pricefm_desn_experiment_grid"

DEFAULT_TEMPLATE = "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
DEFAULT_DECISION_SURFACE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624/"
    "current_decision_surface_table.csv"
)
DEFAULT_MEDIAN_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_l_current_decision_surface_20260624/"
    "current_median_registry.csv"
)
DEFAULT_OUTPUT_GRID = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_n_underperformance_broad_20260625.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_n_underperformance_broad_20260625"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_n_underperformance_broad_20260625"
)
DEFAULT_SUMMARY_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_n_underperformance_plan_20260625"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE)
    p.add_argument("--decision-surface-csv", default=DEFAULT_DECISION_SURFACE)
    p.add_argument("--median-registry-csv", default=DEFAULT_MEDIAN_REGISTRY)
    p.add_argument("--output-grid-config", default=DEFAULT_OUTPUT_GRID)
    p.add_argument("--grid-id", default="pricefm_stage_n_underperformance_broad_20260625")
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--summary-dir", default=DEFAULT_SUMMARY_DIR)
    p.add_argument("--stage-name", default="stage_n_underperformance_broad_search")
    p.add_argument("--experiment-id-prefix", default="stagen")
    p.add_argument("--candidate-source", default="stage_n_underperformance_broad_search_20260625")
    p.add_argument("--target-label", default="stage_n_underperformance_median_validation")
    p.add_argument("--severe-delta", type=float, default=0.70)
    p.add_argument("--moderate-delta", type=float, default=0.25)
    p.add_argument("--near-win-delta", type=float, default=0.25)
    p.add_argument("--max-variants-priority0", type=int, default=72)
    p.add_argument("--max-variants-priority1", type=int, default=36)
    p.add_argument("--max-variants-priority2", type=int, default=8)
    p.add_argument("--include-slight", type=parse_bool, default=True)
    p.add_argument("--include-fragile-near-wins", type=parse_bool, default=False)
    p.add_argument("--include-d4-smoke", type=parse_bool, default=False)
    p.add_argument("--write", type=parse_bool, default=True)
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def read_yaml(path):
    with open(repo_path(path), "r") as f:
        return yaml.safe_load(f)


def write_yaml(path, payload):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def read_csv_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required CSV: {}".format(label, path))
    return pd.read_csv(path)


def parse_jsonish(value):
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return value
        if text.startswith("[") or text.startswith("{") or text.startswith('"'):
            try:
                return json.loads(text)
            except json.JSONDecodeError:
                return ast.literal_eval(text)
    return value


def finite_float(value, default=None):
    try:
        out = float(value)
    except (TypeError, ValueError):
        if default is None:
            raise
        return float(default)
    if not pd.notna(out):
        if default is None:
            raise ValueError("non-finite numeric value")
        return float(default)
    return out


def finite_int(value, default=None):
    try:
        out = int(float(value))
    except (TypeError, ValueError):
        if default is None:
            raise
        return int(default)
    return out


def units_list(value):
    value = parse_jsonish(value)
    if isinstance(value, (list, tuple)):
        return [int(float(x)) for x in value]
    return [int(float(value))]


def slug(value):
    text = str(value).lower().replace("_", "")
    out = []
    for ch in text:
        out.append(ch if ch.isalnum() else "")
    return "".join(out) or "x"


def value_tag(value):
    if isinstance(value, (list, tuple)):
        return "x".join(value_tag(x) for x in value)
    text = "{:.8g}".format(float(value)) if isinstance(value, float) else str(value)
    return text.replace("-", "m").replace(".", "p").replace("+", "").replace("[", "").replace("]", "").replace(",", "x").replace(" ", "")


def round_control(value):
    return float("{:.6g}".format(float(value)))


def clamp(value, low, high):
    return max(float(low), min(float(high), float(value)))


def require_columns(frame, columns, label):
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError("{} missing required columns: {}".format(label, missing))


def normalize_keys(frame):
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    return out


def validate_surface(surface, args):
    required = [
        "region", "fold", "local_AQL", "pricefm_AQL", "delta_abs",
        "delta_rel", "stage_c_quantile_decision", "experiment_id",
        "feature_policy", "information_set",
    ]
    require_columns(surface, required, "decision surface")
    out = normalize_keys(surface)
    if out.duplicated(["region", "fold"]).any():
        dup = out[out.duplicated(["region", "fold"], keep=False)][["region", "fold"]]
        raise ValueError("decision surface duplicate keys: {}".format(
            dup.drop_duplicates().to_dict("records")
        ))
    for col in ["local_AQL", "pricefm_AQL", "delta_abs", "delta_rel"]:
        out[col] = pd.to_numeric(out[col], errors="coerce")
        if out[col].isna().any():
            bad = out[out[col].isna()][["region", "fold"]].to_dict("records")
            raise ValueError("decision surface has non-finite {} rows: {}".format(col, bad))
    out["target_tier"] = "win_or_nonloss"
    out.loc[out["delta_abs"].gt(0.0) & out["delta_abs"].lt(float(args.moderate_delta)), "target_tier"] = "slight"
    out.loc[out["delta_abs"].ge(float(args.moderate_delta)) & out["delta_abs"].lt(float(args.severe_delta)), "target_tier"] = "moderate"
    out.loc[out["delta_abs"].ge(float(args.severe_delta)), "target_tier"] = "severe"
    out["stage_n_priority"] = out["target_tier"].map({"severe": 0, "moderate": 1, "slight": 2}).fillna(999).astype(int)
    out["stage_n_rescue_reason"] = out.apply(rescue_reason, axis=1)
    return out.sort_values(["stage_n_priority", "delta_abs", "region", "fold"], ascending=[True, False, True, True])


def validate_median_registry(median):
    required = [
        "region", "fold", "experiment_id", "selected_method_id",
        "selected_on_split", "selected_on_unit", "selection_metric",
        "selection_AQL", "test_AQL", "feature_map", "lag_window",
        "depth", "units", "alpha", "rho", "input_scale",
        "projection_scale", "tau0", "seed", "feature_policy",
        "input_scope", "spatial_information_set",
    ]
    require_columns(median, required, "median registry")
    out = normalize_keys(median)
    if out.duplicated(["region", "fold"]).any():
        dup = out[out.duplicated(["region", "fold"], keep=False)][["region", "fold"]]
        raise ValueError("median registry duplicate keys: {}".format(
            dup.drop_duplicates().to_dict("records")
        ))
    bad = out[
        ~out["selected_on_split"].astype(str).eq("val")
        | ~out["selected_on_unit"].astype(str).eq("original")
        | ~out["selection_metric"].astype(str).eq("AQL")
    ]
    if not bad.empty:
        raise ValueError("median registry must be validation/original/AQL selected.")
    for col in ["selection_AQL", "test_AQL"]:
        vals = pd.to_numeric(out[col], errors="coerce")
        if vals.isna().any():
            rows = out[vals.isna()][["region", "fold"]].to_dict("records")
            raise ValueError("median registry has non-finite {} rows: {}".format(col, rows))
        out[col] = vals
    return out


def rescue_reason(row):
    if float(row["delta_abs"]) <= 0.0:
        return "fragile_near_win_monitor"
    feature_policy = str(row.get("feature_policy", ""))
    tier = str(row.get("target_tier", ""))
    if feature_policy == "target_only":
        return "{}_target_only_graph_conversion".format(tier)
    return "{}_graph_geometry_refinement".format(tier)


def split_targets(surface, args):
    under = surface[surface["delta_abs"].gt(0.0)].copy()
    if not bool(args.include_slight):
        under = under[~under["target_tier"].eq("slight")].copy()
    monitor = surface[
        surface["delta_abs"].lt(0.0)
        & surface["delta_abs"].abs().le(float(args.near_win_delta))
    ].copy()
    if bool(args.include_fragile_near_wins):
        extra = monitor.copy()
        extra["target_tier"] = "fragile_near_win"
        extra["stage_n_priority"] = 2
        extra["stage_n_rescue_reason"] = "fragile_near_win_monitor"
        under = pd.concat([under, extra], ignore_index=True)
    return (
        under.sort_values(["stage_n_priority", "delta_abs", "region", "fold"], ascending=[True, False, True, True]),
        monitor.sort_values(["delta_abs", "region", "fold"]),
    )


def merge_targets(targets, median):
    merged = targets.merge(
        median,
        on=["region", "fold"],
        how="left",
        suffixes=("_surface", "_median"),
        validate="one_to_one",
    )
    if merged["experiment_id_median"].isna().any():
        missing = merged[merged["experiment_id_median"].isna()][["region", "fold"]]
        raise ValueError("median registry missing Stage-N target rows: {}".format(
            missing.to_dict("records")
        ))
    return merged


def row_value(row, key, default=None):
    if key not in row.index:
        return default
    value = row[key]
    if pd.isna(value):
        return default
    return parse_jsonish(value)


def base_geometry(row):
    units = units_list(row_value(row, "units", row_value(row, "units_median", [120])))
    return {
        "feature_map": str(row_value(row, "feature_map", row_value(row, "feature_map_median", "window_reservoir_v1"))),
        "lag_window": finite_int(row_value(row, "lag_window", row_value(row, "lag_window_median", 96)), 96),
        "units": units,
        "depth": len(units),
        "alpha": finite_float(row_value(row, "alpha", row_value(row, "alpha_median", 0.5)), 0.5),
        "rho": finite_float(row_value(row, "rho", row_value(row, "rho_median", 0.9)), 0.9),
        "input_scale": finite_float(row_value(row, "input_scale", row_value(row, "input_scale_median", 0.35)), 0.35),
        "projection_scale": finite_float(row_value(row, "projection_scale", row_value(row, "projection_scale_median", 1.0)), 1.0),
        "tau0": finite_float(row_value(row, "tau0", row_value(row, "tau0_median", 1.0e-3)), 1.0e-3),
        "seed": finite_int(row_value(row, "seed", row_value(row, "seed_median", 20260625)), 20260625),
    }


def local_metadata():
    return {
        "feature_policy": "target_only",
        "input_scope": "local_target_only",
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "local_only_not_pricefm_graph",
    }


def graph_metadata(degree):
    degree = int(degree)
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


def d1_units(units, size):
    return [int(size)]


def d2_units(size):
    return [int(size), int(size)]


def d3_units(size):
    return [int(size), int(size), int(size)]


def current_graph_degree(row):
    value = row_value(row, "graph_degree", row_value(row, "graph_degree_median", None))
    if value in (None, ""):
        return None
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None


def priority_limit(priority, args):
    return {
        0: int(args.max_variants_priority0),
        1: int(args.max_variants_priority1),
        2: int(args.max_variants_priority2),
    }.get(int(priority), int(args.max_variants_priority2))


def variant_key(spec):
    return tuple(json.dumps(spec.get(k, ""), sort_keys=True) for k in [
        "feature_policy", "graph_degree", "lag_window", "units", "alpha",
        "rho", "input_scale", "projection_scale", "tau0", "seed",
        "state_output",
    ])


def dedupe_variants(variants):
    out = []
    seen = set()
    for item in variants:
        key = variant_key(item)
        if key in seen:
            continue
        seen.add(key)
        out.append(item)
    return out


def variant_spec(row, args, tag, metadata, updates=None, family="base", factor="base"):
    updates = dict(updates or {})
    geom = base_geometry(row)
    geom.update(updates)
    geom["depth"] = len(units_list(geom["units"]))
    region = str(row["region"])
    fold = int(row["fold"])
    tier = str(row["target_tier"])
    priority = int(row["stage_n_priority"])
    spec = {
        "id": "{}_{}_f{}_{}".format(str(args.experiment_id_prefix), slug(region), fold, tag),
        "stage": str(args.stage_name),
        "priority": priority,
        "regions": [region],
        "folds": [fold],
        "quantile": 0.50,
        "target_label": str(args.target_label),
        "selection_is_validation_only": True,
        "selection_rule": "median_validation_AQL_only",
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "test_metrics_role": "audit_only",
        "candidate_source": str(args.candidate_source),
        "candidate_source_final": str(args.candidate_source),
        "candidate_family": str(family),
        "factor_changed": str(factor),
        "target_tier": tier,
        "stage_n_rescue_reason": str(row["stage_n_rescue_reason"]),
        "stage_c_quantile_decision": str(row["stage_c_quantile_decision"]),
        "underperformance_delta_abs": float(row["delta_abs"]),
        "underperformance_delta_rel": float(row["delta_rel"]),
        "local_AQL": float(row["local_AQL"]),
        "pricefm_AQL": float(row["pricefm_AQL"]),
        "test_AQL": float(row["median_test_AQL"] if "median_test_AQL" in row.index else row["test_AQL"]),
        "rationale": (
            "Stage-N {} candidate for region={}, fold={}, tier={}, tag={}; "
            "current paper-grid delta={:.6g}; current median experiment={}."
        ).format(family, region, fold, tier, tag, float(row["delta_abs"]), row["experiment_id_median"]),
        "median_registry": {
            "region": region,
            "fold": fold,
            "source_experiment_id": str(row["experiment_id_median"]),
            "source_selected_method_id": str(row["selected_method_id"]),
            "source_selection_AQL": float(row["selection_AQL"]),
            "source_test_AQL": float(row["test_AQL"]),
            "surface_experiment_id": str(row["experiment_id_surface"]),
            "stage_c_quantile_decision": str(row["stage_c_quantile_decision"]),
        },
    }
    spec.update(geom)
    spec.update(metadata)
    return spec


def graph_degrees(row, priority):
    current = current_graph_degree(row)
    degrees = []
    if current in (1, 2):
        degrees.append(current)
    for degree in [1, 2]:
        if degree not in degrees:
            degrees.append(degree)
    if int(priority) > 1:
        return degrees[:1]
    return degrees


def add_graph_family(row, args, variants, degrees, severe=False):
    geom = base_geometry(row)
    input_scale = geom["input_scale"]
    alpha = geom["alpha"]
    rho = geom["rho"]
    lag = int(geom["lag_window"])
    base_units = geom["units"]
    for degree in degrees:
        meta = graph_metadata(degree)
        prefix = "g{}".format(degree)
        variants.append(variant_spec(row, args, "{}_base".format(prefix), meta, family="graph_geometry", factor="base"))
        variants.append(variant_spec(row, args, "{}_inlow".format(prefix), meta, {"input_scale": round_control(clamp(input_scale * 0.70, 0.05, 1.0))}, "graph_geometry", "input_scale_low"))
        variants.append(variant_spec(row, args, "{}_inhi".format(prefix), meta, {"input_scale": round_control(clamp(input_scale * 1.25, 0.05, 1.0))}, "graph_geometry", "input_scale_high"))
        variants.append(variant_spec(row, args, "{}_alow".format(prefix), meta, {"alpha": round_control(clamp(alpha - 0.15, 0.10, 0.95))}, "graph_geometry", "alpha_low"))
        variants.append(variant_spec(row, args, "{}_ahi".format(prefix), meta, {"alpha": round_control(clamp(alpha + 0.15, 0.10, 0.95))}, "graph_geometry", "alpha_high"))
        variants.append(variant_spec(row, args, "{}_rlow".format(prefix), meta, {"rho": round_control(clamp(rho - 0.15, 0.10, 1.25))}, "graph_geometry", "rho_low"))
        variants.append(variant_spec(row, args, "{}_rhi".format(prefix), meta, {"rho": round_control(clamp(rho + 0.07, 0.10, 1.25))}, "graph_geometry", "rho_high"))
        for candidate_lag in ([72, 144] + ([192] if severe else [])):
            if int(candidate_lag) != lag:
                variants.append(variant_spec(row, args, "{}_l{}".format(prefix, candidate_lag), meta, {"lag_window": int(candidate_lag)}, "graph_geometry", "lag_window"))
        variants.append(variant_spec(row, args, "{}_d1n180".format(prefix), meta, {"units": d1_units(base_units, 180)}, "capacity", "d1_180"))
        variants.append(variant_spec(row, args, "{}_d1n240".format(prefix), meta, {"units": d1_units(base_units, 240)}, "capacity", "d1_240"))
        variants.append(variant_spec(row, args, "{}_d2n120".format(prefix), meta, {"units": d2_units(120)}, "capacity", "d2_120"))
        if severe:
            variants.append(variant_spec(row, args, "{}_d2n160".format(prefix), meta, {"units": d2_units(160)}, "capacity", "d2_160"))
            variants.append(variant_spec(row, args, "{}_d3n60".format(prefix), meta, {"units": d3_units(60)}, "capacity", "d3_60"))
            variants.append(variant_spec(row, args, "{}_d3n100".format(prefix), meta, {"units": d3_units(100)}, "capacity", "d3_100"))
            variants.append(variant_spec(row, args, "{}_tau0lo".format(prefix), meta, {"tau0": 1.0e-4}, "prior_minimal", "tau0_low"))
            variants.append(variant_spec(row, args, "{}_tau0hi".format(prefix), meta, {"tau0": 1.0e-2}, "prior_minimal", "tau0_high"))


def candidate_variants(row, args):
    priority = int(row["stage_n_priority"])
    tier = str(row["target_tier"])
    severe = tier == "severe"
    feature_policy = str(row_value(row, "feature_policy_surface", row_value(row, "feature_policy", "")))
    variants = []

    if feature_policy == "graph_khop":
        variants.append(variant_spec(row, args, "local_base", local_metadata(), family="target_only_guardrail", factor="base"))
        if severe:
            variants.append(variant_spec(row, args, "local_l72", local_metadata(), {"lag_window": 72}, "target_only_guardrail", "lag_short"))
            variants.append(variant_spec(row, args, "local_l144", local_metadata(), {"lag_window": 144}, "target_only_guardrail", "lag_long"))
        add_graph_family(row, args, variants, graph_degrees(row, priority), severe=severe)
    else:
        add_graph_family(row, args, variants, graph_degrees(row, priority), severe=severe)
        if severe:
            variants.append(variant_spec(row, args, "local_d1n240", local_metadata(), {"units": d1_units(base_geometry(row)["units"], 240)}, "local_capacity_guardrail", "d1_240"))
            variants.append(variant_spec(row, args, "local_d2n120", local_metadata(), {"units": d2_units(120)}, "local_capacity_guardrail", "d2_120"))

    if severe and bool(args.include_d4_smoke):
        variants.append(variant_spec(row, args, "d4smoke", graph_metadata(1), {"units": [80, 80, 80, 80]}, "capacity_smoke", "d4_80"))

    return dedupe_variants(variants)[:priority_limit(priority, args)]


def build_grid(template_payload, targets, args):
    payload = copy.deepcopy(template_payload)
    if GRID_BLOCK not in payload:
        raise ValueError("Template grid must contain {}".format(GRID_BLOCK))
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = str(args.grid_id)
    grid["purpose"] = (
        "Stage-N selected-panel underperformance search. Targets are chosen "
        "from current Q-DESN minus PriceFM paper-grid deltas; candidates are "
        "median validation AQL only."
    )
    grid["base"]["generated_root"] = str(args.generated_root)
    grid["base"]["run_root"] = str(args.run_root)
    grid["scope"]["regions"] = sorted(targets["region"].astype(str).unique().tolist())
    grid["scope"]["folds"] = sorted(int(x) for x in targets["fold"].unique())
    grid["scope"]["quantiles"] = [0.50]
    grid["experiments"] = []
    grid["experiment_blocks"] = []

    for _, row in targets.iterrows():
        grid["experiments"].extend(candidate_variants(row, args))

    fixed = grid.setdefault("fixed", {})
    hygiene = fixed.setdefault("artifact_hygiene", {})
    hygiene["enabled"] = True
    hygiene["clean_adapter_patterns"] = sorted(set(hygiene.get("clean_adapter_patterns", []) + ["X_*.csv"]))
    hygiene["clean_model_patterns"] = sorted(set(hygiene.get("clean_model_patterns", []) + [
        "*.rds", "*.rda", "*.RData", "*.rdata",
    ]))
    fixed["stage_n_decision_surface"] = config_path_value(args.decision_surface_csv)
    fixed["stage_n_median_registry"] = config_path_value(args.median_registry_csv)
    fixed["shrink_intercept"] = False
    fixed["qdesn_likelihoods"] = ["al", "exal"]

    grid["launch"] = {}
    grid["launch"]["stage_n_dry_run_gate"] = {
        "priorities": [0],
        "experiment_jobs": 1,
        "cell_jobs": 1,
        "build_windows": True,
        "note": "Run with --dry-run true before any model launch.",
    }
    grid["launch"]["stage_n_smoke"] = {
        "ids": smoke_ids(grid["experiments"]),
        "experiment_jobs": 3,
        "cell_jobs": 1,
        "build_windows": True,
        "note": "Run these explicit IDs after dry-run manifest audit passes.",
    }
    grid["launch"]["stage_n_priority0"] = {
        "priorities": [0],
        "experiment_jobs": 12,
        "cell_jobs": 1,
        "build_windows": True,
        "note": "Increase experiment_jobs toward 20 only after smoke confirms memory and cleanup.",
    }
    return payload


def smoke_ids(experiments):
    by_reason = {}
    for exp in experiments:
        reason = str(exp.get("stage_n_rescue_reason", ""))
        if reason not in by_reason:
            by_reason[reason] = exp["id"]
    ordered = []
    for key in [
        "severe_target_only_graph_conversion",
        "severe_graph_geometry_refinement",
        "moderate_graph_geometry_refinement",
        "moderate_target_only_graph_conversion",
    ]:
        if key in by_reason and by_reason[key] not in ordered:
            ordered.append(by_reason[key])
    return ordered[:3]


def repo_state():
    root = repo_path(".")
    def run(args):
        proc = subprocess.run(args, cwd=str(root), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        return proc.stdout.strip() if proc.returncode == 0 else proc.stderr.strip()
    return {
        "branch": run(["git", "branch", "--show-current"]),
        "head": run(["git", "rev-parse", "HEAD"]),
        "status_short": run(["git", "status", "--short"]),
        "remote": run(["git", "remote", "-v"]),
    }


def frame_hash(frame):
    csv_text = frame.to_csv(index=False)
    return hashlib.sha256(csv_text.encode("utf-8")).hexdigest()


def write_report(summary_dir, summary, tiers, family_matrix):
    path = repo_path(summary_dir) / "stage_n_underperformance_plan_report.md"
    with open(path, "w") as f:
        f.write("# PriceFM Stage-N Underperformance Broad Search Plan\n\n")
        f.write("This generated plan targets current selected-panel Q-DESN underperformance rows.\n\n")
        f.write("## Summary\n\n")
        for key in sorted(summary):
            if isinstance(summary[key], (dict, list)):
                continue
            f.write("- {}: `{}`\n".format(key, summary[key]))
        f.write("\n## Target Tiers\n\n")
        f.write("| tier | rows |\n|---|---:|\n")
        for tier, n in tiers["target_tier"].value_counts().sort_index().items():
            f.write("| {} | {} |\n".format(tier, int(n)))
        f.write("\n## Candidate Families\n\n")
        if family_matrix.empty:
            f.write("_No candidate families._\n")
        else:
            f.write("| priority | tier | family | rows |\n|---:|---|---|---:|\n")
            grouped = family_matrix.groupby(["priority", "target_tier", "candidate_family"]).size().reset_index(name="rows")
            for _, row in grouped.sort_values(["priority", "target_tier", "candidate_family"]).iterrows():
                f.write("| {} | {} | {} | {} |\n".format(
                    int(row["priority"]), row["target_tier"], row["candidate_family"], int(row["rows"])
                ))
        f.write("\n## Discipline\n\n")
        f.write("- Target rows are chosen from current paper-grid underperformance.\n")
        f.write("- Candidate selection remains median validation AQL only.\n")
        f.write("- Test and PriceFM metrics are audit fields until seven-quantile promotion.\n")
        f.write("- Smoke and priority-0 closeout must pass before lower priorities launch.\n")
        f.write("- Cleanup must remove `.rds`, `.rda`, `.RData`, and `.rdata` artifacts.\n")
    return path


def write_outputs(args, surface, median, targets, monitor, payload):
    out = repo_path(args.summary_dir)
    out.mkdir(parents=True, exist_ok=True)
    surface.to_csv(out / "current_surface_audit.csv", index=False)
    targets.to_csv(out / "underperformance_manifest.csv", index=False)
    targets[[
        "region", "fold", "target_tier", "stage_n_priority", "stage_n_rescue_reason",
        "delta_abs", "delta_rel", "local_AQL", "pricefm_AQL", "information_set",
        "feature_policy_surface", "experiment_id_surface",
    ]].to_csv(out / "target_tiers.csv", index=False)
    monitor.to_csv(out / "fragile_near_wins.csv", index=False)

    experiments = pd.DataFrame(payload[GRID_BLOCK]["experiments"])
    experiments.to_csv(out / "candidate_family_matrix.csv", index=False)
    if bool(args.write):
        write_yaml(args.output_grid_config, payload)

    input_hashes = {
        "decision_surface_csv": config_path_value(args.decision_surface_csv),
        "decision_surface_sha256": sha256_file(repo_path(args.decision_surface_csv)),
        "median_registry_csv": config_path_value(args.median_registry_csv),
        "median_registry_sha256": sha256_file(repo_path(args.median_registry_csv)),
        "template_grid_config": config_path_value(args.template_grid_config),
        "template_grid_sha256": sha256_file(repo_path(args.template_grid_config)),
        "surface_frame_sha256": frame_hash(surface),
        "targets_frame_sha256": frame_hash(targets),
    }
    write_json(out / "input_hashes.json", input_hashes)
    write_json(out / "repo_state.json", repo_state())

    summary = {
        "status": "completed",
        "grid_id": str(args.grid_id),
        "output_grid_config": config_path_value(args.output_grid_config),
        "generated_root": config_path_value(args.generated_root),
        "run_root": config_path_value(args.run_root),
        "summary_dir": config_path_value(out),
        "n_surface_rows": int(surface.shape[0]),
        "n_underperformance_rows": int(targets.shape[0]),
        "n_fragile_near_wins": int(monitor.shape[0]),
        "n_experiments": int(experiments.shape[0]),
        "tier_counts": {str(k): int(v) for k, v in targets["target_tier"].value_counts().to_dict().items()},
        "priority_counts": {str(k): int(v) for k, v in experiments["priority"].value_counts().sort_index().to_dict().items()},
        "smoke_ids": smoke_ids(payload[GRID_BLOCK]["experiments"]),
        "selection_rule": "target rows from current underperformance; candidate selection is median validation AQL only",
        "recommended_dry_run": (
            "application/data_local/pricefm/venv/bin/python "
            "application/scripts/pricefm/13_run_desn_experiment_grid.py "
            "--grid-config {} --priorities 0 --experiment-jobs 1 --cell-jobs 1 "
            "--build-windows true --resume true --dry-run true"
        ).format(config_path_value(args.output_grid_config)),
        "recommended_smoke_ids": ",".join(smoke_ids(payload[GRID_BLOCK]["experiments"])),
        "recommended_priority0_launch": (
            "application/data_local/pricefm/venv/bin/python "
            "application/scripts/pricefm/13_run_desn_experiment_grid.py "
            "--grid-config {} --priorities 0 --experiment-jobs 12 --cell-jobs 1 "
            "--build-windows true --resume true --dry-run false"
        ).format(config_path_value(args.output_grid_config)),
        "recommended_closeout_model_methods": (
            "qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked"
        ),
    }
    write_json(out / "summary.json", summary)
    report_path = write_report(out, summary, targets, experiments)
    summary["report"] = config_path_value(report_path)
    write_json(out / "summary.json", summary)
    return summary


def prepare(args):
    if float(args.severe_delta) <= float(args.moderate_delta):
        raise ValueError("--severe-delta must be larger than --moderate-delta")
    for name in ["max_variants_priority0", "max_variants_priority1", "max_variants_priority2"]:
        if int(getattr(args, name)) < 1:
            raise ValueError("{} must be positive".format(name.replace("_", "-")))
    template = read_yaml(args.template_grid_config)
    surface = validate_surface(read_csv_required(args.decision_surface_csv, "decision surface"), args)
    median = validate_median_registry(read_csv_required(args.median_registry_csv, "median registry"))
    targets, monitor = split_targets(surface, args)
    merged = merge_targets(targets, median)
    payload = build_grid(template, merged, args)
    return write_outputs(args, surface, median, merged, monitor, payload)


def main():
    args = parser().parse_args()
    summary = prepare(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
