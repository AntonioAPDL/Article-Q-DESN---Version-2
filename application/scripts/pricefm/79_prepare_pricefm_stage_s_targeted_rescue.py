#!/usr/bin/env python3
"""Prepare a manifest-first PriceFM Stage-S targeted rescue grid.

Stage S consumes the Stage-R failure-mode diagnostics and prepares a bounded
median-only candidate manifest.  By default it does not write a launch grid and
never launches model fits.  Use ``--write-grid true`` only after reviewing the
manifest outputs.
"""

from __future__ import annotations

import argparse
import copy
import json
import subprocess

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, sha256_file, write_json
from pricefm_graph import graph_hash


GRID_BLOCK = "pricefm_desn_experiment_grid"

DEFAULT_STAGE_R_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r_selection_diagnostics_20260627"
)
DEFAULT_STAGE_R_RECOMMENDATIONS = DEFAULT_STAGE_R_DIR + "/stage_r_next_grid_recommendations.csv"
DEFAULT_STAGE_R_SCORECARD = DEFAULT_STAGE_R_DIR + "/stage_r_region_fold_scorecard.csv"
DEFAULT_STAGE_R_HORIZON = DEFAULT_STAGE_R_DIR + "/stage_r_horizon_block_diagnostics.csv"
DEFAULT_STAGE_M_SURFACE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624/"
    "current_decision_surface_table.csv"
)
DEFAULT_TEMPLATE_GRID = "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_s_targeted_rescue_plan_20260628"
)
DEFAULT_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_s_targeted_rescue_20260628.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_s_targeted_rescue_20260628"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_s_targeted_rescue_20260628"
)

GRAPH_PARITY_ACTION = "graph_parity_targeted_grid"
HORIZON_ACTION = "horizon_block_selection_pilot"
STAGE_S_PRIORITY = "candidate_priority0_after_stage_r_review"
BLOCKED_REGIONS = {("RO", 1), ("NL", 3), ("HU", 2), ("SK", 3)}


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r-recommendations-csv", default=DEFAULT_STAGE_R_RECOMMENDATIONS)
    p.add_argument("--stage-r-scorecard-csv", default=DEFAULT_STAGE_R_SCORECARD)
    p.add_argument("--stage-r-horizon-csv", default=DEFAULT_STAGE_R_HORIZON)
    p.add_argument("--stage-m-surface-csv", default=DEFAULT_STAGE_M_SURFACE)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE_GRID)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--stage-s-grid-config", default=DEFAULT_GRID_CONFIG)
    p.add_argument("--stage-s-grid-id", default="pricefm_stage_s_targeted_rescue_20260628")
    p.add_argument("--stage-s-generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--stage-s-run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--stage-name", default="stage_s_targeted_rescue")
    p.add_argument("--experiment-id-prefix", default="stages")
    p.add_argument("--write-grid", type=parse_bool, default=False)
    p.add_argument("--force", type=parse_bool, default=True)
    p.add_argument("--max-graph-variants-per-row", type=int, default=12)
    p.add_argument("--max-horizon-variants-per-row", type=int, default=6)
    p.add_argument("--max-total-experiments", type=int, default=150)
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


def read_yaml_required(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("missing required YAML: {}".format(path))
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


def numeric(frame, col, label, required=False):
    if col not in frame.columns:
        if required:
            raise ValueError("{} missing required numeric column {}".format(label, col))
        return pd.Series([float("nan")] * len(frame), index=frame.index)
    vals = pd.to_numeric(frame[col], errors="coerce")
    if required and vals.isna().any():
        bad = frame[vals.isna()][["region", "fold"]].to_dict("records")
        raise ValueError("{} has non-finite {} rows: {}".format(label, col, bad))
    return vals


def as_float(value, default=float("nan")):
    try:
        out = float(value)
    except (TypeError, ValueError):
        return default
    return out if pd.notna(out) else default


def as_int(value, default=0):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return int(default)


def parse_units(value):
    if isinstance(value, (list, tuple)):
        return [int(float(x)) for x in value]
    text = str(value).strip()
    if text.startswith("["):
        return [int(float(x)) for x in json.loads(text)]
    return [int(float(text))]


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


def clean_slug(value):
    text = str(value).lower().replace("_", "")
    return "".join(ch for ch in text if ch.isalnum()) or "x"


def round_control(value):
    return float("{:.6g}".format(float(value)))


def clamp(value, low, high):
    return max(float(low), min(float(high), float(value)))


def input_specs(args):
    return [
        ("stage_r_recommendations", args.stage_r_recommendations_csv, "csv", "Stage-R next-grid recommendations"),
        ("stage_r_scorecard", args.stage_r_scorecard_csv, "csv", "Stage-R region/fold scorecard"),
        ("stage_r_horizon", args.stage_r_horizon_csv, "csv", "Stage-R horizon-block diagnostics"),
        ("stage_m_surface", args.stage_m_surface_csv, "csv", "current Stage-M decision surface"),
        ("template_grid", args.template_grid_config, "yaml", "known-safe grid template"),
    ]


def input_manifest(args):
    rows = []
    for label, path, file_type, role in input_specs(args):
        full = repo_path(path)
        if not full.exists() or full.stat().st_size == 0:
            raise FileNotFoundError("{} missing required input: {}".format(label, full))
        row = {
            "label": label,
            "role": role,
            "file_type": file_type,
            "path": config_path_value(full),
            "sha256": sha256_file(full),
            "size_bytes": int(full.stat().st_size),
        }
        if file_type == "csv":
            df = pd.read_csv(full)
            row["n_rows"] = int(len(df))
            row["n_cols"] = int(len(df.columns))
        else:
            row["n_rows"] = ""
            row["n_cols"] = ""
        rows.append(row)
    return pd.DataFrame(rows)


def git_state():
    def run(cmd):
        proc = subprocess.run(
            cmd, cwd=str(repo_path(".")), stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, universal_newlines=True, check=False,
        )
        return proc.stdout.strip() if proc.returncode == 0 else ""

    status = run(["git", "status", "--short"])
    return {
        "repo_branch": run(["git", "branch", "--show-current"]),
        "repo_head": run(["git", "rev-parse", "--short", "HEAD"]),
        "repo_dirty": bool(status),
    }


def validate_stage_r_inputs(recommendations, scorecard, horizon, surface):
    require_columns(recommendations, [
        "region", "fold", "primary_failure_mode", "recommended_action",
        "stage_s_priority", "writes_launch_config",
    ], "Stage-R recommendations")
    require_columns(scorecard, [
        "region", "fold", "information_set", "feature_policy", "local_AQL",
        "pricefm_AQL", "delta_abs", "delta_rel", "lag_window", "depth",
        "units", "seed", "current_validation_AQL", "current_median_test_AQL",
    ], "Stage-R scorecard")
    require_columns(horizon, [
        "source_label", "region", "fold", "horizon_group", "horizon_band",
        "validation_selected_AQL", "test_oracle_AQL",
        "oracle_minus_validation_AQL", "oracle_better",
    ], "Stage-R horizon diagnostics")
    require_columns(surface, ["region", "fold", "local_AQL", "pricefm_AQL"], "Stage-M surface")

    recommendations = normalize_keys(recommendations, "Stage-R recommendations", unique=True)
    scorecard = normalize_keys(scorecard, "Stage-R scorecard", unique=True)
    surface = normalize_keys(surface, "Stage-M surface", unique=True)
    horizon = normalize_keys(horizon, "Stage-R horizon diagnostics", unique=False)

    if len(surface) != 42:
        raise ValueError("Stage-M surface row count must be 42, observed {}".format(len(surface)))
    if recommendations["writes_launch_config"].astype(str).str.lower().isin(["true", "1", "yes"]).any():
        raise ValueError("Stage-R recommendations unexpectedly contain writes_launch_config=true")
    for label, df in [
        ("Stage-R scorecard", scorecard),
        ("Stage-M surface", surface),
    ]:
        for col in ["local_AQL", "pricefm_AQL", "delta_abs"]:
            if col in df.columns:
                numeric(df, col, label, required=True)
    return recommendations, scorecard, horizon, surface


def graph_metadata(policy, degree):
    degree = int(degree)
    source = "PriceFM.graph_adj_matrix"
    ghash = graph_hash()
    if policy == "graph_khop":
        input_scope = "pricefm_graph_khop_degree{}".format(degree)
        spatial_set = "pricefm_released_graph_khop"
    elif policy in ("graph_summary_mean", "graph_summary_mean_std"):
        input_scope = "pricefm_{}_degree{}".format(policy, degree)
        spatial_set = "pricefm_released_graph_summary"
    else:
        raise ValueError("Unsupported Stage-S graph policy: {}".format(policy))
    return {
        "feature_policy": policy,
        "graph_degree": degree,
        "graph_source": source,
        "graph_hash": ghash,
        "input_scope": input_scope,
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": spatial_set,
        "spatial": {
            "graph_degree": degree,
            "graph_source": source,
            "graph_hash": ghash,
        },
    }


def anchor_geometries():
    return [
        {
            "tag": "anchor_d1_main",
            "lag_window": 96,
            "units": [120],
            "depth": 1,
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.5,
            "seed": 20260601,
            "geometry_role": "stage_c_graph_anchor",
        },
        {
            "tag": "anchor_d1_lowinput",
            "lag_window": 96,
            "units": [120],
            "depth": 1,
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.25,
            "seed": 20260603,
            "geometry_role": "lower_input_scale_anchor",
        },
        {
            "tag": "anchor_d2_compact",
            "lag_window": 96,
            "units": [80, 80],
            "depth": 2,
            "alpha": 0.4,
            "rho": 0.9,
            "input_scale": 0.35,
            "seed": 20260603,
            "geometry_role": "compact_d2_anchor",
        },
    ]


def current_geometry(row):
    units = parse_units(row.get("units", "[120]"))
    return {
        "lag_window": as_int(row.get("lag_window", 96), 96),
        "units": units,
        "depth": as_int(row.get("depth", len(units)), len(units)),
        "alpha": as_float(row.get("alpha", 0.5), 0.5),
        "rho": as_float(row.get("rho", 0.9), 0.9),
        "input_scale": as_float(row.get("input_scale", 0.35), 0.35),
        "seed": as_int(row.get("seed", 20260628), 20260628),
        "geometry_role": "current_stage_m_anchor",
    }


def base_experiment(row, args, tag, family, factor, metadata, geom, priority=0):
    region = str(row["region"])
    fold = int(row["fold"])
    units = parse_units(geom["units"])
    exp_id = "{}_{}_f{}_{}".format(args.experiment_id_prefix, clean_slug(region), fold, tag)
    spec = {
        "id": exp_id,
        "stage": str(args.stage_name),
        "priority": int(priority),
        "regions": [region],
        "folds": [fold],
        "quantile": 0.5,
        "target_label": "stage_s_median_validation_targeted_rescue",
        "selection_rule": "median_validation_AQL_only",
        "selection_rule_family": str(row.get("recommended_action", "")),
        "selection_is_validation_only": True,
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "test_metrics_role": "audit_only",
        "candidate_source": "stage_r_selection_diagnostics_20260627",
        "candidate_source_final": "stage_s_targeted_rescue_20260628",
        "candidate_family": str(family),
        "factor_changed": str(factor),
        "target_tier": str(row.get("primary_failure_mode", "")),
        "underperformance_delta_abs": as_float(row.get("delta_abs")),
        "underperformance_delta_rel": as_float(row.get("delta_rel")),
        "local_AQL": as_float(row.get("local_AQL")),
        "pricefm_AQL": as_float(row.get("pricefm_AQL")),
        "test_AQL": as_float(row.get("local_AQL")),
        "test_MAE": as_float(row.get("MAE")),
        "test_RMSE": as_float(row.get("RMSE")),
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
            "Stage-S {} for {}, fold {} from Stage-R failure mode {}. "
            "Current AQL={:.6g}, PriceFM AQL={:.6g}, delta={:.6g}. "
            "Selection is validation-only; test metrics remain audit-only."
        ).format(
            family, region, fold, row.get("primary_failure_mode", ""),
            as_float(row.get("local_AQL")), as_float(row.get("pricefm_AQL")),
            as_float(row.get("delta_abs")),
        ),
        "median_registry": {
            "region": region,
            "fold": fold,
            "stage_r_failure_mode": str(row.get("primary_failure_mode", "")),
            "stage_r_action": str(row.get("recommended_action", "")),
            "current_experiment_id": str(row.get("experiment_id", "")),
            "current_method_id": str(row.get("best_local_method", "")),
            "current_AQL": as_float(row.get("local_AQL")),
            "pricefm_AQL": as_float(row.get("pricefm_AQL")),
        },
    }
    spec.update(metadata)
    return spec


def variant_key(spec):
    keep = [
        "region", "fold", "feature_policy", "graph_degree", "lag_window",
        "units", "alpha", "rho", "input_scale", "seed", "candidate_family",
        "selection_rule",
    ]
    vals = []
    for key in keep:
        if key in ("region", "fold"):
            value = spec["regions"][0] if key == "region" else spec["folds"][0]
        else:
            value = spec.get(key, "")
        vals.append(json.dumps(value, sort_keys=True))
    return tuple(vals)


def dedupe(specs):
    out = []
    seen = set()
    for spec in specs:
        key = variant_key(spec)
        if key in seen:
            continue
        seen.add(key)
        out.append(spec)
    return out


def graph_parity_specs(row, args):
    specs = []
    feature_degrees = [
        ("graph_khop", 1),
        ("graph_khop", 2),
        ("graph_summary_mean", 1),
        ("graph_summary_mean", 2),
    ]
    for policy, degree in feature_degrees:
        meta = graph_metadata(policy, degree)
        for geom in anchor_geometries():
            tag = "{}_g{}_{}".format(policy.replace("graph_", ""), degree, geom["tag"])
            specs.append(base_experiment(
                row, args, tag, "graph_parity_rescue", geom["geometry_role"],
                meta, geom,
            ))
    specs = dedupe(specs)
    return specs[: int(args.max_graph_variants_per_row)]


def horizon_pilot_specs(row, args):
    specs = []
    base = current_geometry(row)
    degree = as_int(row.get("graph_degree", 1), 1)
    if degree not in (1, 2):
        degree = 1
    meta = graph_metadata("graph_khop", degree)
    variants = [
        ("base", {}, "current_graph_anchor"),
        ("alpha_down", {"alpha": clamp(base["alpha"] - 0.05, 0.1, 0.95)}, "alpha"),
        ("alpha_up", {"alpha": clamp(base["alpha"] + 0.05, 0.1, 0.95)}, "alpha"),
        ("input_down", {"input_scale": clamp(base["input_scale"] * 0.8, 0.05, 1.5)}, "input_scale"),
        ("input_up", {"input_scale": clamp(base["input_scale"] * 1.2, 0.05, 1.5)}, "input_scale"),
        ("d1_main_anchor", anchor_geometries()[0], "known_safe_anchor"),
    ]
    for tag, updates, factor in variants:
        geom = dict(base)
        geom.update(updates)
        spec = base_experiment(
            row, args, "horizon_{}".format(tag), "horizon_block_pilot",
            factor, meta, geom,
        )
        spec["selection_rule"] = "horizon_block_validation_audit"
        spec["horizon_selection_rules"] = [
            "global_validation_AQL",
            "mean_horizon_block_validation_AQL",
            "max_horizon_block_validation_AQL",
            "late_weighted_validation_AQL",
        ]
        specs.append(spec)
    specs = dedupe(specs)
    return specs[: int(args.max_horizon_variants_per_row)]


def stage_s_targets(recommendations, scorecard):
    target_keys = recommendations[
        recommendations["stage_s_priority"].eq(STAGE_S_PRIORITY)
        & recommendations["recommended_action"].isin([GRAPH_PARITY_ACTION, HORIZON_ACTION])
    ][["region", "fold", "primary_failure_mode", "recommended_action"]].copy()
    rows = scorecard.merge(
        target_keys,
        on=["region", "fold"],
        how="inner",
        suffixes=("", "_stage_r"),
    )
    if "primary_failure_mode_stage_r" in rows.columns:
        rows["primary_failure_mode"] = rows["primary_failure_mode_stage_r"]
    if rows.duplicated(["region", "fold"]).any():
        raise ValueError("Stage-S target rows contain duplicates")
    blocked = rows[rows[["region", "fold"]].apply(lambda x: (str(x["region"]), int(x["fold"])) in BLOCKED_REGIONS, axis=1)]
    if not blocked.empty:
        raise ValueError("Blocked rows appeared in Stage-S target manifest: {}".format(
            blocked[["region", "fold"]].to_dict("records")
        ))
    rows["stage_s_target_family"] = rows["recommended_action"].map({
        GRAPH_PARITY_ACTION: "graph_parity_targeted_grid",
        HORIZON_ACTION: "horizon_block_selection_pilot",
    })
    return rows.sort_values(["recommended_action", "delta_abs"], ascending=[True, False]).reset_index(drop=True)


def blocked_rows(recommendations, scorecard):
    rows = scorecard.merge(
        recommendations[["region", "fold", "primary_failure_mode", "recommended_action", "stage_s_priority"]],
        on=["region", "fold"],
        how="left",
        suffixes=("", "_stage_r"),
    )
    if "primary_failure_mode_stage_r" in rows.columns:
        rows["primary_failure_mode"] = rows["primary_failure_mode_stage_r"]
    out = rows[~rows["stage_s_priority"].eq(STAGE_S_PRIORITY)].copy()
    out["blocked_reason"] = out["recommended_action"].fillna("not_recommended")
    return out.sort_values(["stage_s_priority", "recommended_action", "delta_abs"], ascending=[True, True, False])


def build_experiments(targets, args):
    experiments = []
    manifest = []
    for _, row in targets.iterrows():
        if row["recommended_action"] == GRAPH_PARITY_ACTION:
            specs = graph_parity_specs(row, args)
        elif row["recommended_action"] == HORIZON_ACTION:
            specs = horizon_pilot_specs(row, args)
        else:
            specs = []
        experiments.extend(specs)
        for spec in specs:
            manifest.append({
                "region": spec["regions"][0],
                "fold": int(spec["folds"][0]),
                "experiment_id": spec["id"],
                "priority": int(spec["priority"]),
                "recommended_action": row["recommended_action"],
                "failure_mode": row["primary_failure_mode"],
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
            })
    manifest = pd.DataFrame(manifest)
    if len(experiments) > int(args.max_total_experiments):
        raise ValueError("Stage-S experiment count {} exceeds cap {}".format(
            len(experiments), int(args.max_total_experiments)
        ))
    if manifest["experiment_id"].duplicated().any():
        dup = manifest[manifest["experiment_id"].duplicated()]["experiment_id"].tolist()
        raise ValueError("duplicate Stage-S experiment ids: {}".format(dup))
    if not manifest["selection_is_validation_only"].all():
        raise ValueError("Stage-S manifest contains non-validation selection rows")
    if not manifest["test_metrics_role"].eq("audit_only").all():
        raise ValueError("Stage-S manifest contains non-audit test metrics rows")
    return experiments, manifest


def build_expected_cost(manifest):
    rows = []
    if manifest.empty:
        return pd.DataFrame(rows)
    for (action, family), group in manifest.groupby(["recommended_action", "candidate_family"]):
        rows.append({
            "recommended_action": action,
            "candidate_family": family,
            "n_experiments": int(len(group)),
            "n_region_folds": int(group[["region", "fold"]].drop_duplicates().shape[0]),
            "recommended_experiment_jobs": 12 if len(group) < 100 else 16,
            "cell_jobs": 1,
            "launch_status": "requires_explicit_authorization",
        })
    rows.append({
        "recommended_action": "all_priority0",
        "candidate_family": "all",
        "n_experiments": int(len(manifest)),
        "n_region_folds": int(manifest[["region", "fold"]].drop_duplicates().shape[0]),
        "recommended_experiment_jobs": 16 if len(manifest) <= 150 else 20,
        "cell_jobs": 1,
        "launch_status": "requires_explicit_authorization",
    })
    return pd.DataFrame(rows)


def build_grid(template, experiments, args):
    if GRID_BLOCK not in template:
        raise ValueError("template grid missing {}".format(GRID_BLOCK))
    payload = copy.deepcopy(template)
    grid = payload[GRID_BLOCK]
    target_regions = sorted({region for exp in experiments for region in exp["regions"]})
    target_folds = sorted({int(fold) for exp in experiments for fold in exp["folds"]})
    grid["grid_id"] = str(args.stage_s_grid_id)
    grid["purpose"] = (
        "Stage-S median-only targeted rescue from Stage-R diagnostics. "
        "The grid is manifest-gated: graph-parity target-only rescue plus a "
        "small horizon-block pilot. Selection remains validation-only and "
        "test metrics remain audit-only."
    )
    grid["base"]["generated_root"] = str(args.stage_s_generated_root)
    grid["base"]["run_root"] = str(args.stage_s_run_root)
    grid["scope"]["regions"] = target_regions
    grid["scope"]["folds"] = target_folds
    grid["scope"]["quantiles"] = [0.5]
    grid["scope"]["horizons"] = "all"
    grid["experiments"] = experiments
    grid["experiment_blocks"] = []
    fixed = grid.setdefault("fixed", {})
    fixed["shrink_intercept"] = False
    fixed["qdesn_likelihoods"] = ["al", "exal"]
    fixed["stage_r_recommendations"] = config_path_value(args.stage_r_recommendations_csv)
    fixed["stage_r_scorecard"] = config_path_value(args.stage_r_scorecard_csv)
    fixed["stage_r_horizon"] = config_path_value(args.stage_r_horizon_csv)
    fixed["stage_m_decision_surface"] = config_path_value(args.stage_m_surface_csv)
    hygiene = fixed.setdefault("artifact_hygiene", {})
    hygiene["enabled"] = True
    hygiene["clean_adapter_patterns"] = sorted(set(hygiene.get("clean_adapter_patterns", []) + ["X_*.csv"]))
    hygiene["clean_model_patterns"] = sorted(set(hygiene.get("clean_model_patterns", []) + [
        "*.rds", "*.rda", "*.RData", "*.rdata",
    ]))
    hygiene["preserve_patterns"] = sorted(set(hygiene.get("preserve_patterns", []) + [
        "metric_by_horizon_group.csv", "model_trace_summary.csv",
        "model_parameter_summary.csv", "exact_equivalence.csv",
    ]))
    grid["launch"] = {
        "stage_s_dry_run_gate": {
            "priorities": [0],
            "experiment_jobs": 1,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Dry-run/materialization only before any model launch.",
        },
        "stage_s_priority0_targeted_rescue": {
            "priorities": [0],
            "experiment_jobs": 16,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Launch only after reviewing the manifest and generated-grid validation.",
        },
    }
    return payload


def markdown_table(frame, columns, max_rows=40):
    if frame.empty:
        return "_No rows._"
    show = frame[columns].head(max_rows).copy()
    lines = ["| " + " | ".join(show.columns) + " |"]
    lines.append("|" + "|".join(["---"] * len(show.columns)) + "|")
    for _, row in show.iterrows():
        vals = []
        for col in show.columns:
            value = row[col]
            if isinstance(value, float):
                vals.append("{:.6g}".format(value))
            else:
                vals.append(str(value).replace("|", "\\|"))
        lines.append("| " + " | ".join(vals) + " |")
    if len(frame) > max_rows:
        lines.append("| ... | " + " | ".join([""] * (len(columns) - 1)) + " |")
    return "\n".join(lines)


def write_report(path, summary, targets, blocked, manifest, expected_cost):
    with open(path, "w") as f:
        f.write("# PriceFM Stage-S Targeted Rescue Plan Output\n\n")
        f.write("Stage S is manifest-first.  This output does not launch fits and ")
        f.write("does not mutate the Stage-M decision surface.\n\n")
        f.write("## Summary\n\n")
        for key in sorted(summary):
            f.write("- {}: `{}`\n".format(key, summary[key]))
        f.write("\n## Target Rows\n\n")
        f.write(markdown_table(
            targets,
            ["region", "fold", "recommended_action", "primary_failure_mode", "information_set", "delta_abs"],
        ))
        f.write("\n\n## Experiment Manifest Preview\n\n")
        f.write(markdown_table(
            manifest,
            [
                "region", "fold", "experiment_id", "candidate_family",
                "feature_policy", "graph_degree", "lag_window", "units",
                "alpha", "rho", "input_scale",
            ],
            max_rows=30,
        ))
        f.write("\n\n## Expected Cost\n\n")
        f.write(markdown_table(
            expected_cost,
            [
                "recommended_action", "candidate_family", "n_experiments",
                "n_region_folds", "recommended_experiment_jobs", "cell_jobs",
                "launch_status",
            ],
        ))
        f.write("\n\n## Blocked Rows\n\n")
        f.write(markdown_table(
            blocked,
            ["region", "fold", "primary_failure_mode", "recommended_action", "stage_s_priority", "delta_abs"],
            max_rows=30,
        ))
        f.write("\n\n## Guardrails\n\n")
        f.write("- Selection remains validation-only.\n")
        f.write("- Test metrics remain audit-only.\n")
        f.write("- Stage-Q priority-1 rows are not revived.\n")
        f.write("- Stage-M is unchanged.\n")
        f.write("- Model fitting requires explicit authorization after grid validation.\n")


def prepare(args):
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and not bool(args.force):
        raise FileExistsError("{} exists; rerun with --force true".format(out_dir))
    out_dir.mkdir(parents=True, exist_ok=True)

    recommendations = read_csv_required(args.stage_r_recommendations_csv, "Stage-R recommendations")
    scorecard = read_csv_required(args.stage_r_scorecard_csv, "Stage-R scorecard")
    horizon = read_csv_required(args.stage_r_horizon_csv, "Stage-R horizon diagnostics")
    surface = read_csv_required(args.stage_m_surface_csv, "Stage-M surface")
    template = read_yaml_required(args.template_grid_config)
    recommendations, scorecard, horizon, surface = validate_stage_r_inputs(
        recommendations, scorecard, horizon, surface
    )

    inputs = input_manifest(args)
    targets = stage_s_targets(recommendations, scorecard)
    blocked = blocked_rows(recommendations, scorecard)
    experiments, manifest = build_experiments(targets, args)
    expected_cost = build_expected_cost(manifest)
    grid_payload = build_grid(template, experiments, args)

    inputs.to_csv(out_dir / "stage_s_input_manifest.csv", index=False)
    targets.to_csv(out_dir / "stage_s_target_rows.csv", index=False)
    blocked.to_csv(out_dir / "stage_s_blocked_rows.csv", index=False)
    manifest.to_csv(out_dir / "stage_s_experiment_manifest.csv", index=False)
    expected_cost.to_csv(out_dir / "stage_s_expected_cost.csv", index=False)
    horizon.to_csv(out_dir / "stage_s_horizon_source_rows.csv", index=False)
    if bool(args.write_grid):
        write_yaml(args.stage_s_grid_config, grid_payload)
        write_yaml(out_dir / "stage_s_targeted_rescue_grid.yaml", grid_payload)

    summary = {
        "status": "completed",
        "diagnostic_manifest_only": not bool(args.write_grid),
        "write_grid": bool(args.write_grid),
        "writes_launch_configs": bool(args.write_grid),
        "launches_models": False,
        "stage_m_surface_changed": False,
        "n_target_rows": int(len(targets)),
        "n_graph_parity_rows": int((targets["recommended_action"] == GRAPH_PARITY_ACTION).sum()),
        "n_horizon_pilot_rows": int((targets["recommended_action"] == HORIZON_ACTION).sum()),
        "n_blocked_rows": int(len(blocked)),
        "n_experiments": int(len(manifest)),
        "grid_config": config_path_value(args.stage_s_grid_config) if bool(args.write_grid) else "",
        "output_dir": config_path_value(out_dir),
        "graph_hash": graph_hash(),
    }
    summary.update(git_state())
    write_report(out_dir / "stage_s_plan_summary.md", summary, targets, blocked, manifest, expected_cost)
    write_json(out_dir / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    summary = prepare(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
