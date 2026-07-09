#!/usr/bin/env python3
"""Prepare region/fold-specific PriceFM Q-DESN screening.

Stage W is a mechanism-aware planner after Stage-V.  It uses the frozen
Stage-M decision surface to decide where to spend compute, but candidate
selection remains validation-only.  The planner writes an ignored manifest and,
when requested, a launch-ready grid config.  It never launches model fits and
never mutates the Stage-M decision surface.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import subprocess

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, sha256_file, write_json
from pricefm_graph import graph_hash


GRID_BLOCK = "pricefm_desn_experiment_grid"

DEFAULT_STAGE_M_SURFACE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624/"
    "current_decision_surface_table.csv"
)
DEFAULT_STAGE_V_SUMMARY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_v_horizon_selection_contract_20260629/summary.json"
)
DEFAULT_STAGE_V_RULE_MATRIX = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_v_horizon_selection_contract_20260629/"
    "stage_v_region_fold_rule_matrix.csv"
)
DEFAULT_TEMPLATE_GRID = (
    "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_w_region_fold_screening_plan_20260629"
)
DEFAULT_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_w_region_fold_screening_20260629.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_w_region_fold_screening_20260629"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_w_region_fold_screening_20260629"
)

DEFAULT_GRID_ID = "pricefm_stage_w_region_fold_screening_20260629"
DEFAULT_STAGE_NAME = "stage_w_region_fold_specific_screening"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-m-surface-csv", default=DEFAULT_STAGE_M_SURFACE)
    p.add_argument("--stage-v-summary-json", default=DEFAULT_STAGE_V_SUMMARY)
    p.add_argument("--stage-v-rule-matrix-csv", default=DEFAULT_STAGE_V_RULE_MATRIX)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE_GRID)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--grid-config", default=DEFAULT_GRID_CONFIG)
    p.add_argument("--grid-id", default=DEFAULT_GRID_ID)
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--stage-name", default=DEFAULT_STAGE_NAME)
    p.add_argument("--experiment-id-prefix", default="stagew")
    p.add_argument("--severe-loss-threshold", type=float, default=0.75)
    p.add_argument("--moderate-loss-threshold", type=float, default=0.25)
    p.add_argument("--near-win-threshold", type=float, default=-0.35)
    p.add_argument("--include-near-wins", type=parse_bool, default=True)
    p.add_argument("--write-grid", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=True)
    p.add_argument("--max-variants-severe", type=int, default=16)
    p.add_argument("--max-variants-moderate", type=int, default=12)
    p.add_argument("--max-variants-slight", type=int, default=8)
    p.add_argument("--max-variants-near-win", type=int, default=4)
    p.add_argument("--max-total-experiments", type=int, default=360)
    p.add_argument("--recommended-experiment-jobs", type=int, default=20)
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def read_csv_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required CSV: {}".format(label, path))
    return pd.read_csv(path)


def read_json_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required JSON: {}".format(label, path))
    with open(path, "r") as f:
        return json.load(f)


def read_yaml_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required YAML: {}".format(label, path))
    with open(path, "r") as f:
        return yaml.safe_load(f)


def write_yaml(path, payload):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def require_columns(frame, columns, label):
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError("{} missing required columns: {}".format(label, missing))


def numeric(frame, col, label, required=False):
    if col not in frame.columns:
        if required:
            raise ValueError("{} missing required numeric column {}".format(label, col))
        return pd.Series([float("nan")] * len(frame), index=frame.index)
    out = pd.to_numeric(frame[col], errors="coerce")
    if required and out.isna().any():
        bad = frame[out.isna()][["region", "fold"]].to_dict("records")
        raise ValueError("{} has non-finite {} rows: {}".format(label, col, bad))
    return out


def normalize_keys(frame, label, unique=False):
    require_columns(frame, ["region", "fold"], label)
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    if unique and out.duplicated(["region", "fold"]).any():
        dup = (
            out[out.duplicated(["region", "fold"], keep=False)][["region", "fold"]]
            .drop_duplicates()
            .sort_values(["region", "fold"])
            .to_dict("records")
        )
        raise ValueError("{} has duplicate region/fold keys: {}".format(label, dup))
    return out


def bool_value(value):
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in ("true", "1", "yes", "y")


def git_state():
    def run(cmd):
        proc = subprocess.run(
            cmd,
            cwd=str(repo_path(".")),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            check=False,
        )
        return proc.stdout.strip() if proc.returncode == 0 else ""

    return {
        "repo_branch": run(["git", "branch", "--show-current"]),
        "repo_head": run(["git", "rev-parse", "--short", "HEAD"]),
        "repo_dirty": bool(run(["git", "status", "--short"])),
    }


def as_float(value, default=float("nan")):
    try:
        out = float(value)
    except (TypeError, ValueError):
        return default
    return out if math.isfinite(out) else default


def as_int(value, default=0):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return int(default)


def parse_units(value):
    if isinstance(value, (list, tuple)):
        return [int(float(x)) for x in value]
    text = str(value).strip()
    if not text:
        return [120]
    if text.startswith("["):
        return [int(float(x)) for x in json.loads(text)]
    return [int(float(text))]


def clean_slug(value):
    text = str(value).lower().replace("_", "")
    return "".join(ch for ch in text if ch.isalnum()) or "x"


def value_tag(value):
    if isinstance(value, (list, tuple)):
        return "x".join(value_tag(x) for x in value)
    text = "{:.6g}".format(float(value)) if isinstance(value, float) else str(value)
    return (
        text.replace("-", "m")
        .replace(".", "p")
        .replace("+", "")
        .replace("[", "")
        .replace("]", "")
        .replace(",", "x")
        .replace(" ", "")
    )


def round_control(value):
    return float("{:.6g}".format(float(value)))


def clamp(value, low, high):
    return max(float(low), min(float(high), float(value)))


def input_manifest(args):
    specs = [
        ("stage_m_surface", args.stage_m_surface_csv, "csv", "frozen Stage-M decision surface"),
        ("stage_v_summary", args.stage_v_summary_json, "json", "Stage-V no-launch gate"),
        ("stage_v_rule_matrix", args.stage_v_rule_matrix_csv, "csv", "Stage-V rule selections"),
        ("template_grid", args.template_grid_config, "yaml", "known-safe grid template"),
    ]
    rows = []
    for label, path, kind, role in specs:
        full = repo_path(path)
        if not full.exists() or full.stat().st_size == 0:
            raise FileNotFoundError("{} missing required input: {}".format(label, full))
        row = {
            "label": label,
            "role": role,
            "file_type": kind,
            "path": config_path_value(full),
            "sha256": sha256_file(full),
            "size_bytes": int(full.stat().st_size),
            "n_rows": "",
            "n_cols": "",
        }
        if kind == "csv":
            frame = pd.read_csv(full)
            row["n_rows"] = int(frame.shape[0])
            row["n_cols"] = int(frame.shape[1])
        rows.append(row)
    return pd.DataFrame(rows)


def validate_stage_v(summary):
    if not bool_value(summary.get("diagnostic_only", False)):
        raise ValueError("Stage-V summary must be diagnostic_only.")
    if bool_value(summary.get("fits_models", True)):
        raise ValueError("Stage-V summary unexpectedly fits models.")
    if bool_value(summary.get("writes_launch_configs", True)):
        raise ValueError("Stage-V summary unexpectedly writes launch configs.")
    if bool_value(summary.get("stage_m_surface_changed", True)):
        raise ValueError("Stage-V summary says Stage-M surface changed.")
    if bool_value(summary.get("selection_uses_test_metrics_any", True)):
        raise ValueError("Stage-V selected using test metrics; refusing Stage-W.")
    expected = "do_not_launch_more_capacity_until_selection_or_graph_model_changes"
    if str(summary.get("recommended_next_stage", "")) != expected:
        raise ValueError(
            "Stage-V recommended_next_stage must be {}; got {}".format(
                expected, summary.get("recommended_next_stage")
            )
        )


def validate_surface(surface):
    required = [
        "region", "fold", "best_local_method", "model_family",
        "information_set", "local_AQL", "pricefm_AQL", "delta_abs",
        "delta_rel", "feature_policy", "lag_window", "depth", "units",
        "seed", "run_dir", "experiment_id",
    ]
    require_columns(surface, required, "Stage-M surface")
    out = normalize_keys(surface, "Stage-M surface", unique=True)
    if len(out) != 42:
        raise ValueError("Stage-M surface row count must be 42, got {}".format(len(out)))
    for col in ["local_AQL", "pricefm_AQL", "delta_abs", "delta_rel"]:
        out[col] = numeric(out, col, "Stage-M surface", required=True)
    return out


def validate_stage_v_matrix(matrix):
    required = [
        "region", "fold", "rule_id", "source_label", "experiment_id",
        "method_id", "val_AQL", "test_AQL", "test_delta_vs_current_median",
        "test_delta_vs_pricefm",
    ]
    require_columns(matrix, required, "Stage-V rule matrix")
    out = normalize_keys(matrix, "Stage-V rule matrix", unique=False)
    for col in [
        "val_AQL", "test_AQL", "test_delta_vs_current_median",
        "test_delta_vs_pricefm",
    ]:
        out[col] = numeric(out, col, "Stage-V rule matrix", required=True)
    return out


def load_inputs(args):
    surface = validate_surface(read_csv_required(args.stage_m_surface_csv, "Stage-M surface"))
    stage_v = read_json_required(args.stage_v_summary_json, "Stage-V summary")
    validate_stage_v(stage_v)
    matrix = validate_stage_v_matrix(
        read_csv_required(args.stage_v_rule_matrix_csv, "Stage-V rule matrix")
    )
    template = read_yaml_required(args.template_grid_config, "template grid")
    return surface, stage_v, matrix, template


def loss_tier(delta, args):
    delta = float(delta)
    if delta >= float(args.severe_loss_threshold):
        return "severe_loss"
    if delta >= float(args.moderate_loss_threshold):
        return "moderate_loss"
    if delta > 0.0:
        return "slight_loss"
    if delta > float(args.near_win_threshold):
        return "near_win"
    return "solid_win"


def priority_for_tier(tier):
    return {
        "severe_loss": 0,
        "moderate_loss": 1,
        "slight_loss": 2,
        "near_win": 3,
        "solid_win": 9,
    }[tier]


def screening_family(row, tier):
    feature_policy = str(row.get("feature_policy", ""))
    if tier == "solid_win":
        return "defer_strong_current_win"
    if tier == "near_win":
        return "local_stability_guard"
    if feature_policy == "target_only":
        return "graph_information_conversion"
    if feature_policy == "graph_khop":
        return "graph_geometry_refinement"
    return "region_fold_geometry_refinement"


def build_region_fold_audit(surface, matrix, args):
    best_rule = matrix[matrix["rule_id"].astype(str).eq("horizon_max_aql_min")].copy()
    if best_rule.empty:
        best_rule = matrix.sort_values(["region", "fold", "rule_id"]).drop_duplicates(["region", "fold"])
    best_rule = best_rule.sort_values(["region", "fold"]).drop_duplicates(["region", "fold"])
    best_rule = best_rule[[
        "region", "fold", "rule_id", "source_label", "experiment_id",
        "method_id", "val_AQL", "test_AQL", "test_delta_vs_current_median",
        "test_delta_vs_pricefm",
    ]].rename(columns={
        "rule_id": "stage_v_rule_id",
        "source_label": "stage_v_source_label",
        "experiment_id": "stage_v_experiment_id",
        "method_id": "stage_v_method_id",
        "val_AQL": "stage_v_val_AQL",
        "test_AQL": "stage_v_test_AQL",
        "test_delta_vs_current_median": "stage_v_test_delta_vs_current_median",
        "test_delta_vs_pricefm": "stage_v_test_delta_vs_pricefm",
    })
    out = surface.merge(best_rule, on=["region", "fold"], how="left", validate="one_to_one")
    out["loss_tier"] = [loss_tier(x, args) for x in out["delta_abs"]]
    out["screening_priority"] = out["loss_tier"].map(priority_for_tier).astype(int)
    out["screening_family"] = [screening_family(row, row["loss_tier"]) for _, row in out.iterrows()]
    out["include_in_stage_w"] = (
        out["delta_abs"].gt(0.0)
        | (bool(args.include_near_wins) & out["loss_tier"].eq("near_win"))
    )
    out["stage_w_role"] = "defer"
    out.loc[out["include_in_stage_w"], "stage_w_role"] = "screen_region_fold"
    out["stage_w_rationale"] = out.apply(stage_w_rationale, axis=1)
    return out.sort_values(["screening_priority", "delta_abs", "region", "fold"], ascending=[True, False, True, True])


def stage_w_rationale(row):
    tier = row["loss_tier"]
    family = row["screening_family"]
    if family == "graph_information_conversion":
        return "Current selected row is target-only; graph-neighbor information is the highest-value mechanism to test."
    if family == "graph_geometry_refinement":
        return "Current selected row already uses graph inputs; refine graph degree/summary geometry and reservoir controls."
    if family == "local_stability_guard":
        return "Current row is a near win; run seed/geometry stability checks before treating it as robust."
    if tier == "solid_win":
        return "Current row already has a comfortable Q-DESN win; do not spend screening compute here now."
    return "Region/fold-specific geometry refinement."


def graph_metadata(policy, degree):
    degree = int(degree)
    ghash = graph_hash()
    if policy == "target_only":
        return {
            "feature_policy": "target_only",
            "graph_source": "",
            "graph_hash": "",
            "input_scope": "local_target_only",
            "output_scope": "target_region_path",
            "lead_covariate_status": "realized_ex_post",
            "spatial_information_set": "local_only_not_pricefm_graph",
        }
    if policy == "graph_khop":
        input_scope = "pricefm_graph_khop_degree{}".format(degree)
        spatial = "pricefm_released_graph_khop"
    elif policy in ["graph_summary_mean", "graph_summary_mean_std"]:
        input_scope = "pricefm_{}_degree{}".format(policy, degree)
        spatial = "pricefm_released_graph_summary"
    else:
        raise ValueError("unsupported graph policy: {}".format(policy))
    return {
        "feature_policy": policy,
        "graph_degree": degree,
        "graph_source": "PriceFM.graph_adj_matrix",
        "graph_hash": ghash,
        "input_scope": input_scope,
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": spatial,
        "spatial": {
            "graph_degree": degree,
            "graph_source": "PriceFM.graph_adj_matrix",
            "graph_hash": ghash,
        },
    }


def current_geometry(row):
    units = parse_units(row.get("units", "[120]"))
    return {
        "tag": "current_anchor",
        "lag_window": as_int(row.get("lag_window", 96), 96),
        "units": units,
        "depth": as_int(row.get("depth", len(units)), len(units)),
        "alpha": as_float(row.get("alpha", 0.5), 0.5),
        "rho": as_float(row.get("rho", 0.9), 0.9),
        "input_scale": as_float(row.get("input_scale", 0.35), 0.35),
        "seed": as_int(row.get("seed", 20260629), 20260629),
        "geometry_role": "current_stage_m_anchor",
    }


def geometry_library(row):
    base = current_geometry(row)
    return [
        base,
        {
            "tag": "d1_main",
            "lag_window": 96,
            "units": [120],
            "depth": 1,
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.5,
            "seed": 20260601,
            "geometry_role": "stage_c_core_anchor",
        },
        {
            "tag": "d1_lowinput",
            "lag_window": 96,
            "units": [120],
            "depth": 1,
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.25,
            "seed": 20260603,
            "geometry_role": "low_input_anchor",
        },
        {
            "tag": "d2_compact",
            "lag_window": 96,
            "units": [80, 80],
            "depth": 2,
            "alpha": 0.4,
            "rho": 0.9,
            "input_scale": 0.35,
            "seed": 20260603,
            "geometry_role": "compact_depth2_anchor",
        },
        {
            "tag": "d3_compact",
            "lag_window": 96,
            "units": [60, 60, 60],
            "depth": 3,
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.25,
            "seed": 20260617,
            "geometry_role": "compact_depth3_anchor",
        },
    ]


def max_variants(row, args):
    tier = row["loss_tier"]
    if tier == "severe_loss":
        return int(args.max_variants_severe)
    if tier == "moderate_loss":
        return int(args.max_variants_moderate)
    if tier == "slight_loss":
        return int(args.max_variants_slight)
    if tier == "near_win":
        return int(args.max_variants_near_win)
    return 0


def experiment_id(args, row, tag):
    return "{}_{}_f{}_{}".format(
        args.experiment_id_prefix,
        clean_slug(row["region"]),
        int(row["fold"]),
        tag,
    )


def base_experiment(args, row, tag, candidate_family, factor_changed, meta, geom):
    units = parse_units(geom["units"])
    spec = {
        "id": experiment_id(args, row, tag),
        "stage": str(args.stage_name),
        "priority": int(row["screening_priority"]),
        "regions": [str(row["region"])],
        "folds": [int(row["fold"])],
        "quantile": 0.5,
        "target_label": "stage_w_region_fold_specific_median_validation",
        "selection_rule": "region_fold_validation_aql_horizon_stability",
        "selection_rule_family": "validation_only_region_fold_specific",
        "selection_is_validation_only": True,
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "test_metrics_role": "audit_only",
        "candidate_source": "stage_w_region_fold_screening_20260629",
        "candidate_source_final": "stage_w_region_fold_screening_20260629",
        "candidate_family": candidate_family,
        "factor_changed": factor_changed,
        "screening_family": str(row["screening_family"]),
        "loss_tier": str(row["loss_tier"]),
        "underperformance_delta_abs": as_float(row["delta_abs"]),
        "underperformance_delta_rel": as_float(row["delta_rel"]),
        "local_AQL": as_float(row["local_AQL"]),
        "pricefm_AQL": as_float(row["pricefm_AQL"]),
        "stage_m_experiment_id": str(row.get("experiment_id", "")),
        "stage_m_method_id": str(row.get("best_local_method", "")),
        "stage_v_rule_id": str(row.get("stage_v_rule_id", "")),
        "stage_v_test_delta_vs_current_median": as_float(row.get("stage_v_test_delta_vs_current_median")),
        "stage_v_test_delta_vs_pricefm": as_float(row.get("stage_v_test_delta_vs_pricefm")),
        "lag_window": int(geom["lag_window"]),
        "units": units,
        "depth": int(geom.get("depth", len(units))),
        "alpha": round_control(geom["alpha"]),
        "rho": round_control(geom["rho"]),
        "input_scale": round_control(geom["input_scale"]),
        "projection_scale": 1.0,
        "tau0": 1.0e-3,
        "seed": int(geom["seed"]),
        "feature_map": "window_reservoir_v1",
        "state_output": "final_layer",
        "rationale": (
            "Stage-W region/fold-specific screen for {region}, fold {fold}. "
            "Family={family}; tier={tier}; current delta AQL={delta:.6g}. "
            "Selection remains validation-only; test metrics remain audit-only."
        ).format(
            region=row["region"],
            fold=int(row["fold"]),
            family=row["screening_family"],
            tier=row["loss_tier"],
            delta=as_float(row["delta_abs"]),
        ),
        "median_registry": {
            "region": str(row["region"]),
            "fold": int(row["fold"]),
            "stage_w_family": str(row["screening_family"]),
            "stage_w_loss_tier": str(row["loss_tier"]),
            "current_experiment_id": str(row.get("experiment_id", "")),
            "current_method_id": str(row.get("best_local_method", "")),
            "current_AQL": as_float(row.get("local_AQL")),
            "pricefm_AQL": as_float(row.get("pricefm_AQL")),
        },
    }
    spec.update(meta)
    return spec


def variant_key(spec):
    return tuple(json.dumps(spec.get(k, ""), sort_keys=True) for k in [
        "regions", "folds", "feature_policy", "graph_degree", "lag_window",
        "units", "alpha", "rho", "input_scale", "seed", "candidate_family",
    ])


def dedupe(specs):
    seen = set()
    out = []
    for spec in specs:
        key = variant_key(spec)
        if key in seen:
            continue
        seen.add(key)
        out.append(spec)
    return out


def graph_conversion_specs(args, row):
    specs = []
    policies = [
        ("graph_khop", 1),
        ("graph_khop", 2),
        ("graph_summary_mean", 1),
        ("graph_summary_mean", 2),
    ]
    for policy, degree in policies:
        meta = graph_metadata(policy, degree)
        for geom in geometry_library(row):
            tag = "{}_g{}_{}".format(policy.replace("graph_", ""), degree, geom["tag"])
            specs.append(base_experiment(
                args, row, tag, "graph_information_conversion",
                "{}_{}".format(policy, geom["geometry_role"]), meta, geom,
            ))
    return dedupe(specs)[: max_variants(row, args)]


def graph_refinement_specs(args, row):
    specs = []
    current_degree = as_int(row.get("graph_degree", 1), 1)
    degrees = sorted(set([1, 2, current_degree]))
    policies = []
    for degree in degrees:
        if degree in (1, 2):
            policies.append(("graph_khop", degree))
            policies.append(("graph_summary_mean", degree))
    for policy, degree in policies:
        meta = graph_metadata(policy, degree)
        for geom in geometry_library(row):
            tag = "{}_g{}_{}".format(policy.replace("graph_", ""), degree, geom["tag"])
            specs.append(base_experiment(
                args, row, tag, "graph_geometry_refinement",
                "{}_{}".format(policy, geom["geometry_role"]), meta, geom,
            ))
    return dedupe(specs)[: max_variants(row, args)]


def stability_specs(args, row):
    specs = []
    policy = str(row.get("feature_policy", "target_only"))
    degree = as_int(row.get("graph_degree", 1), 1)
    if policy not in ["target_only", "graph_khop", "graph_summary_mean", "graph_summary_mean_std"]:
        policy = "target_only"
    if policy == "target_only":
        meta = graph_metadata("target_only", 0)
    else:
        meta = graph_metadata(policy, degree if degree in (1, 2) else 1)
    geom = current_geometry(row)
    for seed in [20260629, 20260630, 20260701, as_int(row.get("seed", 20260629), 20260629)]:
        g = dict(geom)
        g["seed"] = seed
        g["tag"] = "stability_seed{}".format(seed)
        tag = "{}_{}".format(policy.replace("graph_", ""), g["tag"])
        specs.append(base_experiment(
            args, row, tag, "near_win_stability_guard", "seed_stability", meta, g,
        ))
    return dedupe(specs)[: max_variants(row, args)]


def build_experiments(targets, args):
    specs = []
    manifest = []
    for _, row in targets.iterrows():
        family = str(row["screening_family"])
        if family == "graph_information_conversion":
            row_specs = graph_conversion_specs(args, row)
        elif family == "graph_geometry_refinement":
            row_specs = graph_refinement_specs(args, row)
        elif family == "local_stability_guard":
            row_specs = stability_specs(args, row)
        else:
            row_specs = []
        specs.extend(row_specs)
        for spec in row_specs:
            manifest.append({
                "region": spec["regions"][0],
                "fold": int(spec["folds"][0]),
                "experiment_id": spec["id"],
                "priority": int(spec["priority"]),
                "loss_tier": spec["loss_tier"],
                "screening_family": spec["screening_family"],
                "candidate_family": spec["candidate_family"],
                "factor_changed": spec["factor_changed"],
                "selection_rule": spec["selection_rule"],
                "selection_is_validation_only": bool(spec["selection_is_validation_only"]),
                "test_metrics_role": spec["test_metrics_role"],
                "feature_policy": spec["feature_policy"],
                "graph_degree": spec.get("graph_degree", ""),
                "graph_hash": spec.get("graph_hash", ""),
                "input_scope": spec.get("input_scope", ""),
                "spatial_information_set": spec.get("spatial_information_set", ""),
                "lag_window": int(spec["lag_window"]),
                "units": json.dumps(spec["units"]),
                "depth": int(spec["depth"]),
                "alpha": float(spec["alpha"]),
                "rho": float(spec["rho"]),
                "input_scale": float(spec["input_scale"]),
                "tau0": float(spec["tau0"]),
                "seed": int(spec["seed"]),
                "local_AQL": spec["local_AQL"],
                "pricefm_AQL": spec["pricefm_AQL"],
                "delta_abs": spec["underperformance_delta_abs"],
                "stage_m_experiment_id": spec["stage_m_experiment_id"],
                "stage_m_method_id": spec["stage_m_method_id"],
                "stage_v_rule_id": spec["stage_v_rule_id"],
            })
    manifest = pd.DataFrame(manifest)
    if len(specs) > int(args.max_total_experiments):
        raise ValueError(
            "Stage-W experiment count {} exceeds cap {}".format(
                len(specs), int(args.max_total_experiments)
            )
        )
    if not manifest.empty:
        if manifest["experiment_id"].duplicated().any():
            dup = manifest[manifest["experiment_id"].duplicated()]["experiment_id"].tolist()
            raise ValueError("duplicate Stage-W experiment ids: {}".format(dup))
        if not manifest["selection_is_validation_only"].astype(bool).all():
            raise ValueError("Stage-W manifest contains non-validation selection rows")
        if not manifest["test_metrics_role"].astype(str).eq("audit_only").all():
            raise ValueError("Stage-W manifest contains non-audit test metrics rows")
    return specs, manifest


def target_rows(audit):
    targets = audit[audit["include_in_stage_w"].astype(bool)].copy()
    return targets.sort_values(["screening_priority", "delta_abs", "region", "fold"], ascending=[True, False, True, True])


def deferred_rows(audit):
    return audit[~audit["include_in_stage_w"].astype(bool)].copy().sort_values(
        ["screening_priority", "delta_abs", "region", "fold"],
        ascending=[True, False, True, True],
    )


def build_expected_cost(manifest, args):
    rows = []
    if manifest.empty:
        return pd.DataFrame(rows)
    for (priority, family), sub in manifest.groupby(["priority", "screening_family"]):
        rows.append({
            "priority": int(priority),
            "screening_family": family,
            "n_experiments": int(len(sub)),
            "n_region_folds": int(sub[["region", "fold"]].drop_duplicates().shape[0]),
            "recommended_experiment_jobs": min(int(args.recommended_experiment_jobs), max(1, int(len(sub)))),
            "cell_jobs": 1,
            "launch_status": "requires_explicit_authorization",
        })
    rows.append({
        "priority": "all",
        "screening_family": "all",
        "n_experiments": int(len(manifest)),
        "n_region_folds": int(manifest[["region", "fold"]].drop_duplicates().shape[0]),
        "recommended_experiment_jobs": int(args.recommended_experiment_jobs),
        "cell_jobs": 1,
        "launch_status": "requires_explicit_authorization",
    })
    return pd.DataFrame(rows).sort_values(["priority", "screening_family"]).reset_index(drop=True)


def build_selection_contract():
    return pd.DataFrame([
        {
            "rank": 1,
            "contract_item": "region_fold_local_selection",
            "requirement": "Select a winning candidate independently within each region/fold.",
            "rationale": "Stage-M and Stage-V show no single global DESN spec should be treated as authoritative.",
        },
        {
            "rank": 2,
            "contract_item": "validation_only_ranking",
            "requirement": "Rank by validation metrics only; test metrics are audit-only.",
            "rationale": "Avoid Stage-Q/S validation-test leakage and overfitting.",
        },
        {
            "rank": 3,
            "contract_item": "horizon_stability_tiebreaker",
            "requirement": "Use horizon-block validation summaries as secondary stability diagnostics.",
            "rationale": "Stage-U/V found mid/late horizon instability in several rows.",
        },
        {
            "rank": 4,
            "contract_item": "graph_information_priority",
            "requirement": "For target-only losses, test PriceFM graph-neighbor input policies before more local capacity.",
            "rationale": "Graph-input Q-DESN wins 20/27 rows, while target-only wins 5/15.",
        },
        {
            "rank": 5,
            "contract_item": "artifact_hygiene",
            "requirement": "Preserve metrics, manifests, traces, and figures; remove binary fit artifacts after summaries.",
            "rationale": "Large screenings must stay reproducible without accumulating .rds/.rda artifacts.",
        },
    ])


def build_grid(template, experiments, manifest, args):
    if GRID_BLOCK not in template:
        raise ValueError("template grid missing {}".format(GRID_BLOCK))
    payload = copy.deepcopy(template)
    grid = payload[GRID_BLOCK]
    regions = sorted(manifest["region"].astype(str).unique().tolist()) if not manifest.empty else []
    folds = sorted(pd.to_numeric(manifest["fold"], errors="raise").astype(int).unique().tolist()) if not manifest.empty else []
    grid["grid_id"] = str(args.grid_id)
    grid["purpose"] = (
        "Stage-W region/fold-specific median screening. Targets Stage-M losses "
        "and near wins with graph-information conversion, graph-geometry "
        "refinement, and stability guards. Selection remains validation-only; "
        "test metrics remain audit-only."
    )
    grid["base"]["generated_root"] = str(args.generated_root)
    grid["base"]["run_root"] = str(args.run_root)
    grid["scope"]["regions"] = regions
    grid["scope"]["folds"] = folds
    grid["scope"]["quantiles"] = [0.5]
    grid["scope"]["horizons"] = "all"
    grid["experiments"] = experiments
    grid["experiment_blocks"] = []
    fixed = grid.setdefault("fixed", {})
    fixed["shrink_intercept"] = False
    fixed["qdesn_likelihoods"] = ["al", "exal"]
    fixed["stage_m_decision_surface"] = config_path_value(args.stage_m_surface_csv)
    fixed["stage_v_summary"] = config_path_value(args.stage_v_summary_json)
    fixed["stage_v_rule_matrix"] = config_path_value(args.stage_v_rule_matrix_csv)
    hygiene = fixed.setdefault("artifact_hygiene", {})
    hygiene["enabled"] = True
    hygiene["clean_adapter_patterns"] = sorted(set(hygiene.get("clean_adapter_patterns", []) + ["X_*.csv"]))
    hygiene["clean_model_patterns"] = sorted(set(hygiene.get("clean_model_patterns", []) + [
        "*.rds", "*.rda", "*.RData", "*.rdata",
    ]))
    hygiene["preserve_patterns"] = sorted(set(hygiene.get("preserve_patterns", []) + [
        "metric_summary.csv", "metric_by_horizon.csv", "metric_by_horizon_group.csv",
        "model_method_summary.csv", "model_parameter_summary.csv",
        "model_trace_summary.csv", "predictions_with_naive_scaled.csv",
        "model_predictions_scaled.csv", "exact_equivalence.csv",
        "warm_start_diagnostics.csv", "report.md", "*.png", "*.pdf", "*.json", "*.log",
    ]))
    grid["launch"] = {
        "stage_w_dry_run_gate": {
            "priorities": [0, 1, 2, 3],
            "experiment_jobs": 1,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Dry-run/materialization only before any model launch.",
        },
        "stage_w_priority0_severe_losses": {
            "priorities": [0],
            "experiment_jobs": int(args.recommended_experiment_jobs),
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Launch first after reviewing Stage-W manifest.",
        },
        "stage_w_priority1_moderate_losses": {
            "priorities": [1],
            "experiment_jobs": int(args.recommended_experiment_jobs),
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Launch after priority 0 health/closeout.",
        },
        "stage_w_priority2_slight_losses": {
            "priorities": [2],
            "experiment_jobs": min(12, int(args.recommended_experiment_jobs)),
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Optional after higher-priority rows.",
        },
        "stage_w_priority3_near_win_stability": {
            "priorities": [3],
            "experiment_jobs": min(12, int(args.recommended_experiment_jobs)),
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Stability-only guard for near wins.",
        },
    }
    return payload


def markdown_table(frame, columns, max_rows=40):
    if frame.empty:
        return "_No rows._"
    work = frame[[c for c in columns if c in frame.columns]].head(max_rows).copy()
    lines = ["| " + " | ".join(work.columns) + " |"]
    lines.append("|" + "|".join(["---"] * len(work.columns)) + "|")
    for _, row in work.iterrows():
        vals = []
        for col in work.columns:
            value = row[col]
            if isinstance(value, float):
                vals.append("{:.6g}".format(value))
            else:
                vals.append(str(value).replace("|", "\\|"))
        lines.append("| " + " | ".join(vals) + " |")
    if len(frame) > max_rows:
        lines.append("| ... | " + " | ".join([""] * (len(work.columns) - 1)) + " |")
    return "\n".join(lines)


def write_report(path, summary, audit, targets, deferred, manifest, cost, contract):
    with open(repo_path(path), "w") as f:
        f.write("# PriceFM Stage-W Region/Fold Screening Plan\n\n")
        f.write("Stage W is a manifest-first planner for region/fold-specific Q-DESN screening. ")
        f.write("It writes no model fits and does not mutate the Stage-M decision surface.\n\n")
        f.write("## Summary\n\n")
        for key in sorted(summary):
            if key == "outputs":
                continue
            f.write("- {}: `{}`\n".format(key, summary[key]))
        f.write("\n## Target Rows\n\n")
        f.write(markdown_table(
            targets,
            [
                "region", "fold", "loss_tier", "screening_priority",
                "screening_family", "delta_abs", "information_set",
                "feature_policy", "stage_w_rationale",
            ],
            max_rows=60,
        ))
        f.write("\n\n## Experiment Manifest Preview\n\n")
        f.write(markdown_table(
            manifest,
            [
                "region", "fold", "experiment_id", "priority",
                "screening_family", "candidate_family", "feature_policy",
                "graph_degree", "lag_window", "units", "alpha", "rho",
                "input_scale", "seed",
            ],
            max_rows=40,
        ))
        f.write("\n\n## Expected Cost\n\n")
        f.write(markdown_table(
            cost,
            [
                "priority", "screening_family", "n_experiments",
                "n_region_folds", "recommended_experiment_jobs",
                "cell_jobs", "launch_status",
            ],
            max_rows=20,
        ))
        f.write("\n\n## Selection Contract\n\n")
        f.write(markdown_table(
            contract,
            ["rank", "contract_item", "requirement", "rationale"],
            max_rows=20,
        ))
        f.write("\n\n## Deferred Rows\n\n")
        f.write(markdown_table(
            deferred,
            ["region", "fold", "loss_tier", "delta_abs", "screening_family", "stage_w_rationale"],
            max_rows=40,
        ))
        f.write("\n\n## Guardrails\n\n")
        f.write("- Model fitting requires explicit authorization and a dry-run gate.\n")
        f.write("- Each region/fold is selected locally; no global spec is promoted.\n")
        f.write("- Selection remains validation-only.\n")
        f.write("- Test metrics remain audit-only.\n")
        f.write("- Artifact hygiene removes binary fit artifacts after summaries are written.\n")
        f.write("- Stage-M is unchanged by this plan.\n\n")
        f.write("## Output Manifest\n\n")
        for key, value in sorted(summary["outputs"].items()):
            f.write("- `{}`: `{}`\n".format(key, value))


def write_frame(path, frame):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)


def prepare(args):
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and not bool(args.force):
        raise FileExistsError("{} exists; rerun with --force true".format(out_dir))
    out_dir.mkdir(parents=True, exist_ok=True)

    surface, stage_v, matrix, template = load_inputs(args)
    inputs = input_manifest(args)
    audit = build_region_fold_audit(surface, matrix, args)
    targets = target_rows(audit)
    deferred = deferred_rows(audit)
    experiments, manifest = build_experiments(targets, args)
    cost = build_expected_cost(manifest, args)
    contract = build_selection_contract()
    grid_payload = build_grid(template, experiments, manifest, args)

    outputs = {
        "input_manifest_csv": out_dir / "stage_w_input_manifest.csv",
        "region_fold_audit_csv": out_dir / "stage_w_region_fold_audit.csv",
        "target_rows_csv": out_dir / "stage_w_target_rows.csv",
        "deferred_rows_csv": out_dir / "stage_w_deferred_rows.csv",
        "experiment_manifest_csv": out_dir / "stage_w_experiment_manifest.csv",
        "expected_cost_csv": out_dir / "stage_w_expected_cost.csv",
        "selection_contract_csv": out_dir / "stage_w_selection_contract.csv",
        "summary_md": out_dir / "stage_w_region_fold_screening_plan.md",
        "summary_json": out_dir / "summary.json",
    }
    if bool(args.write_grid):
        outputs["grid_config_yaml"] = repo_path(args.grid_config)
        outputs["grid_copy_yaml"] = out_dir / "stage_w_region_fold_screening_grid.yaml"

    if bool(args.write_grid):
        write_yaml(args.grid_config, grid_payload)
        write_yaml(out_dir / "stage_w_region_fold_screening_grid.yaml", grid_payload)

    write_frame(outputs["input_manifest_csv"], inputs)
    write_frame(outputs["region_fold_audit_csv"], audit)
    write_frame(outputs["target_rows_csv"], targets)
    write_frame(outputs["deferred_rows_csv"], deferred)
    write_frame(outputs["experiment_manifest_csv"], manifest)
    write_frame(outputs["expected_cost_csv"], cost)
    write_frame(outputs["selection_contract_csv"], contract)

    target_counts = targets["loss_tier"].value_counts().to_dict() if not targets.empty else {}
    family_counts = manifest["screening_family"].value_counts().to_dict() if not manifest.empty else {}
    summary = {
        "status": "completed",
        "diagnostic_manifest_only": not bool(args.write_grid),
        "write_grid": bool(args.write_grid),
        "writes_launch_configs": bool(args.write_grid),
        "launches_models": False,
        "stage_m_surface_changed": False,
        "selection_is_region_fold_specific": True,
        "selection_is_validation_only": True,
        "test_metrics_role": "audit_only",
        "stage_m_rows": int(len(surface)),
        "n_target_rows": int(len(targets)),
        "n_deferred_rows": int(len(deferred)),
        "n_experiments": int(len(manifest)),
        "target_counts_by_tier": json.dumps(target_counts, sort_keys=True),
        "experiment_counts_by_family": json.dumps(family_counts, sort_keys=True),
        "grid_config": config_path_value(args.grid_config) if bool(args.write_grid) else "",
        "output_dir": config_path_value(out_dir),
        "stage_v_recommended_next_stage": str(stage_v.get("recommended_next_stage", "")),
        "graph_hash": graph_hash(),
        "recommended_next_action": "review_stage_w_manifest_then_dry_run_priority0",
    }
    summary.update(git_state())
    summary["outputs"] = {key: config_path_value(value) for key, value in outputs.items()}

    write_report(outputs["summary_md"], summary, audit, targets, deferred, manifest, cost, contract)
    write_json(outputs["summary_json"], summary)
    return summary


def main():
    args = parser().parse_args()
    summary = prepare(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
