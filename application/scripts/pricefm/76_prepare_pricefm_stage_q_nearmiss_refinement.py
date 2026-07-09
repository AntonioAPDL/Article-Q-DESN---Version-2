#!/usr/bin/env python3
"""Prepare Stage-Q near-miss PriceFM Q-DESN median refinement.

Stage P confirmed Stage-N median candidates on the seven paper quantiles.
Only one row beat cached fold-aligned PriceFM, while two rows were close.
This script freezes that decision and prepares a new median-only refinement
grid for the close rows.  It does not mutate the current article decision
surface and does not promote median-only results.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, write_json
from pricefm_graph import graph_hash


GRID_BLOCK = "pricefm_desn_experiment_grid"

DEFAULT_TEMPLATE_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_p_stage_n_promotions_quantile_confirmation_20260626.yaml"
)
DEFAULT_STAGE_P_FLAGS = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_vs_stage_p_promotions_20260626/"
    "selected_competitiveness_flags.csv"
)
DEFAULT_STAGE_P_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_o_selection_promotion_hardening_20260626/"
    "stage_p_quantile_confirmation_registry.csv"
)
DEFAULT_CURRENT_SURFACE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624/"
    "current_decision_surface_table.csv"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_q_nearmiss_refinement_plan_20260626"
)
DEFAULT_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_q_nearmiss_refinement_20260626.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_q_nearmiss_refinement_20260626"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_q_nearmiss_refinement_20260626"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE_GRID_CONFIG)
    p.add_argument("--stage-p-flags-csv", default=DEFAULT_STAGE_P_FLAGS)
    p.add_argument("--stage-p-registry-csv", default=DEFAULT_STAGE_P_REGISTRY)
    p.add_argument("--current-decision-surface-csv", default=DEFAULT_CURRENT_SURFACE)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--stage-q-grid-config", default=DEFAULT_GRID_CONFIG)
    p.add_argument("--stage-q-grid-id", default="pricefm_stage_q_nearmiss_refinement_20260626")
    p.add_argument("--stage-q-generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--stage-q-run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--stage-name", default="stage_q_nearmiss_median_refinement")
    p.add_argument("--experiment-id-prefix", default="stageq")
    p.add_argument("--close-abs-delta", type=float, default=0.35)
    p.add_argument("--close-rel-delta", type=float, default=0.05)
    p.add_argument("--optional-abs-delta", type=float, default=0.55)
    p.add_argument("--optional-rel-delta", type=float, default=0.08)
    p.add_argument("--include-optional-modest-gaps", type=parse_bool, default=True)
    p.add_argument("--max-variants-priority0", type=int, default=42)
    p.add_argument("--max-variants-priority1", type=int, default=20)
    p.add_argument("--write-grid", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=True)
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


def normalize_keys(frame, label):
    require_columns(frame, ["region", "fold"], label)
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    return out


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


def clean_slug(value):
    text = str(value).lower().replace("_", "")
    return "".join(ch for ch in text if ch.isalnum()) or "x"


def value_tag(value):
    if isinstance(value, (list, tuple)):
        return "x".join(value_tag(x) for x in value)
    if isinstance(value, float):
        text = "{:.6g}".format(value)
    else:
        text = str(value)
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


def ordered_unique(values):
    out = []
    seen = set()
    for value in values:
        key = json.dumps(value, sort_keys=True) if isinstance(value, (list, dict)) else str(value)
        if key in seen:
            continue
        seen.add(key)
        out.append(value)
    return out


def classify_stage_p_rows(flags, registry, surface, args):
    required_flags = [
        "region", "fold", "method_id", "AQL", "pricefm_phase1_AQL",
        "delta_abs", "delta_rel", "decision_label",
    ]
    require_columns(flags, required_flags, "Stage-P selected flags")
    require_columns(registry, [
        "region", "fold", "experiment_id", "selected_method_id",
        "lag_window", "depth", "units", "alpha", "rho", "input_scale",
        "projection_scale", "tau0", "seed", "feature_policy",
    ], "Stage-P registry")
    flags = normalize_keys(flags, "Stage-P selected flags")
    registry = normalize_keys(registry, "Stage-P registry")
    surface = normalize_keys(surface, "current decision surface")

    merged = flags.merge(
        registry,
        on=["region", "fold"],
        how="left",
        suffixes=("_stagep", "_median"),
        validate="one_to_one",
    )
    if merged["experiment_id"].isna().any():
        missing = merged[merged["experiment_id"].isna()][["region", "fold"]]
        raise ValueError("Stage-P registry missing rows: {}".format(missing.to_dict("records")))
    merged["stage_p_method_id"] = merged.get(
        "method_id_stagep",
        merged.get("method_id", merged.get("selected_method_id", "")),
    )

    if "local_AQL" in surface.columns:
        current = surface[["region", "fold", "local_AQL", "pricefm_AQL", "best_local_method"]].copy()
        current = current.rename(columns={
            "local_AQL": "current_surface_local_AQL",
            "pricefm_AQL": "current_surface_pricefm_AQL",
            "best_local_method": "current_surface_method",
        })
        merged = merged.merge(current, on=["region", "fold"], how="left", validate="one_to_one")
        merged["stage_p_minus_current_local_AQL"] = (
            pd.to_numeric(merged["AQL"], errors="coerce")
            - pd.to_numeric(merged["current_surface_local_AQL"], errors="coerce")
        )
    else:
        merged["current_surface_local_AQL"] = float("nan")
        merged["current_surface_pricefm_AQL"] = float("nan")
        merged["current_surface_method"] = ""
        merged["stage_p_minus_current_local_AQL"] = float("nan")

    merged["stage_q_decision"] = "do_not_promote_yet"
    merged.loc[merged["decision_label"].astype(str).eq("local_beats_pricefm"), "stage_q_decision"] = (
        "promote_article_candidate"
    )
    close = (
        merged["decision_label"].astype(str).eq("local_close_to_pricefm")
        | pd.to_numeric(merged["delta_abs"], errors="coerce").le(float(args.close_abs_delta))
        | pd.to_numeric(merged["delta_rel"], errors="coerce").le(float(args.close_rel_delta))
    ) & ~merged["stage_q_decision"].eq("promote_article_candidate")
    merged.loc[close, "stage_q_decision"] = "near_miss_refine"

    optional = (
        bool(args.include_optional_modest_gaps)
        & ~merged["stage_q_decision"].isin(["promote_article_candidate", "near_miss_refine"])
        & (
            pd.to_numeric(merged["delta_abs"], errors="coerce").le(float(args.optional_abs_delta))
            | pd.to_numeric(merged["delta_rel"], errors="coerce").le(float(args.optional_rel_delta))
        )
    )
    merged.loc[optional, "stage_q_decision"] = "optional_modest_gap_refine"

    merged["stage_q_priority"] = 99
    merged.loc[merged["stage_q_decision"].eq("near_miss_refine"), "stage_q_priority"] = 0
    merged.loc[merged["stage_q_decision"].eq("optional_modest_gap_refine"), "stage_q_priority"] = 1
    merged.loc[merged["stage_q_decision"].eq("promote_article_candidate"), "stage_q_priority"] = 90
    merged["stage_q_action"] = merged["stage_q_decision"].map({
        "promote_article_candidate": "freeze_as_stage_p_win_no_stage_q_refit",
        "near_miss_refine": "launch_stage_q_priority0_median_refinement",
        "optional_modest_gap_refine": "prepare_stage_q_priority1_optional_refinement",
        "do_not_promote_yet": "hold_until_new_evidence",
    })
    return merged.sort_values(["stage_q_priority", "delta_abs", "region", "fold"]).reset_index(drop=True)


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


def local_metadata():
    return {
        "feature_policy": "target_only",
        "input_scope": "local_target_only",
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "local_only_not_pricefm_graph",
    }


def base_geometry(row):
    return {
        "lag_window": as_int(row["lag_window"], 96),
        "units": parse_units(row["units"]),
        "alpha": as_float(row["alpha"], 0.5),
        "rho": as_float(row["rho"], 0.9),
        "input_scale": as_float(row["input_scale"], 0.35),
        "projection_scale": as_float(row.get("projection_scale", 1.0), 1.0),
        "tau0": as_float(row["tau0"], 1.0e-3),
        "seed": as_int(row["seed"], 20260626),
        "feature_map": str(row.get("feature_map", "window_reservoir_v1")),
        "state_output": str(row.get("state_output", "final_layer")),
    }


def current_degree(row):
    value = row.get("graph_degree", "")
    if pd.isna(value) or str(value).strip() == "":
        return None
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None


def experiment_spec(row, args, tag, metadata, updates=None, family="nearmiss_refinement", factor="base"):
    updates = dict(updates or {})
    geom = base_geometry(row)
    geom.update(updates)
    geom["units"] = parse_units(geom["units"])
    geom["depth"] = len(geom["units"])
    priority = int(row["stage_q_priority"])
    region = str(row["region"])
    fold = int(row["fold"])
    stage_p_method_id = row.get("stage_p_method_id", row.get("selected_method_id", ""))
    exp_id = "{}_{}_f{}_{}".format(args.experiment_id_prefix, clean_slug(region), fold, tag)
    spec = {
        "id": exp_id,
        "stage": str(args.stage_name),
        "priority": priority,
        "regions": [region],
        "folds": [fold],
        "quantile": 0.50,
        "target_label": "stage_q_median_validation_nearmiss_refinement",
        "selection_rule": "median_validation_AQL_only",
        "selection_is_validation_only": True,
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "test_metrics_role": "audit_only",
        "candidate_source": "stage_q_nearmiss_refinement_20260626",
        "candidate_source_final": "stage_q_nearmiss_refinement_20260626",
        "candidate_family": str(family),
        "factor_changed": str(factor),
        "target_tier": str(row["stage_q_decision"]),
        "underperformance_delta_abs": as_float(row["delta_abs"]),
        "underperformance_delta_rel": as_float(row["delta_rel"]),
        "local_AQL": as_float(row["AQL"]),
        "pricefm_AQL": as_float(row["pricefm_phase1_AQL"]),
        "test_AQL": as_float(row["AQL"]),
        "test_MAE": as_float(row.get("MAE", float("nan"))),
        "test_RMSE": as_float(row.get("RMSE", float("nan"))),
        "rationale": (
            "Stage-Q median-only refinement around Stage-P {} row {}, fold {}. "
            "Stage-P AQL={:.6g}, PriceFM AQL={:.6g}, delta={:.6g}; "
            "candidate family={}, factor={}. Promotion still requires later "
            "seven-quantile confirmation."
        ).format(
            row["stage_q_decision"], region, fold, as_float(row["AQL"]),
            as_float(row["pricefm_phase1_AQL"]), as_float(row["delta_abs"]),
            family, factor,
        ),
        "median_registry": {
            "region": region,
            "fold": fold,
            "stage_p_experiment_id": str(row["experiment_id"]),
            "stage_p_method_id": str(stage_p_method_id),
            "stage_p_decision": str(row["decision_label"]),
            "stage_q_decision": str(row["stage_q_decision"]),
            "stage_p_AQL": as_float(row["AQL"]),
            "pricefm_AQL": as_float(row["pricefm_phase1_AQL"]),
            "current_surface_local_AQL": as_float(row.get("current_surface_local_AQL", float("nan"))),
        },
    }
    spec.update(geom)
    spec.update(metadata)
    return spec


def variant_key(spec):
    keep = [
        "feature_policy", "graph_degree", "lag_window", "units", "alpha",
        "rho", "input_scale", "projection_scale", "tau0", "seed",
        "state_output",
    ]
    return tuple(json.dumps(spec.get(key, ""), sort_keys=True) for key in keep)


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


def graph_degree_sequence(row):
    degree = current_degree(row)
    degrees = []
    if degree in (1, 2):
        degrees.append(degree)
    for item in [1, 2]:
        if item not in degrees:
            degrees.append(item)
    return degrees


def one_factor_graph_variants(row, args, degree):
    base = base_geometry(row)
    meta = graph_metadata(degree)
    prefix = "g{}".format(degree)
    specs = [
        experiment_spec(row, args, "{}_base".format(prefix), meta, family="graph_anchor", factor="base")
    ]

    alpha_values = ordered_unique([
        round_control(clamp(base["alpha"] - 0.10, 0.10, 0.95)),
        round_control(clamp(base["alpha"] - 0.05, 0.10, 0.95)),
        round_control(base["alpha"]),
        round_control(clamp(base["alpha"] + 0.05, 0.10, 0.95)),
        round_control(clamp(base["alpha"] + 0.10, 0.10, 0.95)),
    ])
    for value in alpha_values:
        if value != round_control(base["alpha"]):
            specs.append(experiment_spec(
                row, args, "{}_a{}".format(prefix, value_tag(value)), meta,
                {"alpha": value}, "reservoir_dynamics", "alpha",
            ))

    rho_values = ordered_unique([
        0.75, 0.85, round_control(base["rho"]), 0.95, 1.05,
    ])
    for value in rho_values:
        if value != round_control(base["rho"]):
            specs.append(experiment_spec(
                row, args, "{}_r{}".format(prefix, value_tag(value)), meta,
                {"rho": value}, "reservoir_dynamics", "rho",
            ))

    input_values = ordered_unique([
        round_control(clamp(base["input_scale"] * 0.65, 0.05, 1.00)),
        round_control(clamp(base["input_scale"] * 0.85, 0.05, 1.00)),
        round_control(base["input_scale"]),
        round_control(clamp(base["input_scale"] * 1.15, 0.05, 1.00)),
        round_control(clamp(base["input_scale"] * 1.35, 0.05, 1.00)),
        0.25, 0.35, 0.50,
    ])
    for value in input_values:
        if value != round_control(base["input_scale"]):
            specs.append(experiment_spec(
                row, args, "{}_in{}".format(prefix, value_tag(value)), meta,
                {"input_scale": value}, "input_scaling", "input_scale",
            ))

    for lag in [72, 96, 128, 144, 192]:
        if int(lag) != int(base["lag_window"]):
            specs.append(experiment_spec(
                row, args, "{}_l{}".format(prefix, lag), meta,
                {"lag_window": int(lag)}, "context_length", "lag_window",
            ))

    unit_candidates = [
        base["units"],
        [80], [120], [180], [240],
        [80, 80], [120, 120], [160, 160], [200, 200],
        [80, 80, 80], [100, 100, 100],
    ]
    for units in ordered_unique(unit_candidates):
        if parse_units(units) != parse_units(base["units"]):
            specs.append(experiment_spec(
                row, args, "{}_n{}".format(prefix, value_tag(units)), meta,
                {"units": parse_units(units)}, "capacity_depth", "units",
            ))

    interaction_specs = [
        ("lowin_alow", {
            "input_scale": round_control(clamp(base["input_scale"] * 0.75, 0.05, 1.00)),
            "alpha": round_control(clamp(base["alpha"] - 0.05, 0.10, 0.95)),
        }),
        ("lowin_rhi", {
            "input_scale": round_control(clamp(base["input_scale"] * 0.75, 0.05, 1.00)),
            "rho": round_control(clamp(base["rho"] + 0.05, 0.10, 1.20)),
        }),
        ("d2n160_inlow", {
            "units": [160, 160],
            "input_scale": round_control(clamp(base["input_scale"] * 0.85, 0.05, 1.00)),
        }),
        ("d3n80_inlow", {
            "units": [80, 80, 80],
            "input_scale": round_control(clamp(base["input_scale"] * 0.85, 0.05, 1.00)),
        }),
    ]
    for tag, updates in interaction_specs:
        specs.append(experiment_spec(
            row, args, "{}_{}".format(prefix, tag), meta, updates,
            "targeted_interaction", tag,
        ))

    return specs


def local_guardrail_variants(row, args):
    base = base_geometry(row)
    meta = local_metadata()
    specs = []
    for tag, updates in [
        ("local_d1n120", {"units": [120]}),
        ("local_d1n180", {"units": [180]}),
        ("local_d2n120", {"units": [120, 120]}),
        ("local_l72", {"lag_window": 72}),
        ("local_l144", {"lag_window": 144}),
        ("local_in{}".format(value_tag(base["input_scale"])), {"input_scale": base["input_scale"]}),
    ]:
        specs.append(experiment_spec(row, args, tag, meta, updates, "local_guardrail", tag))
    return specs


def build_variants(decisions, args):
    targets = decisions[decisions["stage_q_priority"].isin([0, 1])].copy()
    experiments = []
    manifest_rows = []
    for _, row in targets.iterrows():
        specs = []
        for degree in graph_degree_sequence(row):
            specs.extend(one_factor_graph_variants(row, args, degree))
        if int(row["stage_q_priority"]) == 1:
            specs.extend(local_guardrail_variants(row, args))
        specs = dedupe(specs)
        limit = (
            int(args.max_variants_priority0)
            if int(row["stage_q_priority"]) == 0
            else int(args.max_variants_priority1)
        )
        specs = specs[:limit]
        experiments.extend(specs)
        for spec in specs:
            manifest_rows.append({
                "region": row["region"],
                "fold": int(row["fold"]),
                "experiment_id": spec["id"],
                "priority": int(spec["priority"]),
                "stage_q_decision": row["stage_q_decision"],
                "candidate_family": spec["candidate_family"],
                "factor_changed": spec["factor_changed"],
                "lag_window": int(spec["lag_window"]),
                "units": json.dumps(spec["units"]),
                "alpha": float(spec["alpha"]),
                "rho": float(spec["rho"]),
                "input_scale": float(spec["input_scale"]),
                "graph_degree": spec.get("graph_degree", ""),
                "stage_p_AQL": as_float(row["AQL"]),
                "pricefm_AQL": as_float(row["pricefm_phase1_AQL"]),
                "stage_p_delta_abs": as_float(row["delta_abs"]),
            })
    return experiments, pd.DataFrame(manifest_rows)


def build_grid(template, decisions, experiments, args):
    if GRID_BLOCK not in template:
        raise ValueError("template grid missing {}".format(GRID_BLOCK))
    payload = copy.deepcopy(template)
    grid = payload[GRID_BLOCK]
    targets = decisions[decisions["stage_q_priority"].isin([0, 1])].copy()
    grid["grid_id"] = str(args.stage_q_grid_id)
    grid["purpose"] = (
        "Stage-Q median-only near-miss refinement after Stage-P seven-quantile "
        "confirmation. Targets are selected from fold-aligned PriceFM deltas; "
        "candidate selection remains validation AQL only. No article-surface "
        "promotion is implied by this grid."
    )
    grid["base"]["generated_root"] = str(args.stage_q_generated_root)
    grid["base"]["run_root"] = str(args.stage_q_run_root)
    grid["scope"]["regions"] = sorted(targets["region"].astype(str).unique().tolist())
    grid["scope"]["folds"] = sorted(int(x) for x in targets["fold"].unique())
    grid["scope"]["quantiles"] = [0.50]
    grid["experiments"] = experiments
    grid["experiment_blocks"] = []

    fixed = grid.setdefault("fixed", {})
    fixed["shrink_intercept"] = False
    fixed["qdesn_likelihoods"] = ["al", "exal"]
    hygiene = fixed.setdefault("artifact_hygiene", {})
    hygiene["enabled"] = True
    hygiene["clean_adapter_patterns"] = sorted(set(hygiene.get("clean_adapter_patterns", []) + ["X_*.csv"]))
    hygiene["clean_model_patterns"] = sorted(set(hygiene.get("clean_model_patterns", []) + [
        "*.rds", "*.rda", "*.RData", "*.rdata",
    ]))
    fixed["stage_q_stage_p_flags"] = config_path_value(args.stage_p_flags_csv)
    fixed["stage_q_stage_p_registry"] = config_path_value(args.stage_p_registry_csv)
    fixed["stage_q_current_decision_surface"] = config_path_value(args.current_decision_surface_csv)

    grid["launch"] = {
        "stage_q_dry_run_gate": {
            "priorities": [0],
            "experiment_jobs": 1,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Run with --dry-run true before any model launch.",
        },
        "stage_q_priority0_nearmiss": {
            "priorities": [0],
            "experiment_jobs": 12,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Near-miss refinement for NL fold 3 and RO fold 1.",
        },
        "stage_q_priority1_optional": {
            "priorities": [1],
            "experiment_jobs": 8,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Optional modest-gap refinement after priority 0 is inspected.",
        },
    }
    return payload


def markdown_table(frame, columns, max_rows=24):
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


def write_report(out_dir, summary, decisions, manifest):
    path = out_dir / "stage_q_nearmiss_refinement_plan_report.md"
    with open(path, "w") as f:
        f.write("# PriceFM Stage-Q Near-Miss Median Refinement Plan\n\n")
        f.write("Stage Q follows the Stage-P seven-quantile confirmation. It freezes ")
        f.write("the Stage-P promotion status, prepares median-only refinement for ")
        f.write("near-miss rows, and keeps article-surface promotion gated by a later ")
        f.write("seven-quantile comparison.\n\n")
        f.write("## Summary\n\n")
        for key in sorted(summary):
            f.write("- {}: `{}`\n".format(key, summary[key]))
        f.write("\n## Stage-P Closeout Decisions\n\n")
        f.write(markdown_table(
            decisions,
            [
                "region", "fold", "stage_p_method_id", "AQL", "pricefm_phase1_AQL",
                "delta_abs", "delta_rel", "decision_label", "stage_q_decision",
                "stage_q_action",
            ],
        ))
        f.write("\n\n## Stage-Q Median Refinement Manifest Preview\n\n")
        f.write(markdown_table(
            manifest,
            [
                "region", "fold", "experiment_id", "priority", "candidate_family",
                "factor_changed", "lag_window", "units", "alpha", "rho",
                "input_scale", "graph_degree",
            ],
        ))
        f.write("\n\n## Guardrails\n\n")
        f.write("- Selection remains validation AQL only.\n")
        f.write("- Test metrics remain audit-only.\n")
        f.write("- Current Stage-M article decision surface is not mutated.\n")
        f.write("- No Stage-Q candidate can be promoted without later paper-quantile confirmation.\n")
    return path


def prepare(args):
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and not bool(args.force):
        raise FileExistsError("{} exists; rerun with --force true".format(out_dir))
    out_dir.mkdir(parents=True, exist_ok=True)

    flags = read_csv_required(args.stage_p_flags_csv, "Stage-P selected flags")
    registry = read_csv_required(args.stage_p_registry_csv, "Stage-P registry")
    surface = read_csv_required(args.current_decision_surface_csv, "current decision surface")
    template = read_yaml_required(args.template_grid_config)

    decisions = classify_stage_p_rows(flags, registry, surface, args)
    experiments, manifest = build_variants(decisions, args)
    grid_payload = build_grid(template, decisions, experiments, args)

    if bool(args.write_grid):
        write_yaml(args.stage_q_grid_config, grid_payload)
        write_yaml(out_dir / "stage_q_nearmiss_refinement_grid.yaml", grid_payload)

    decisions.to_csv(out_dir / "stage_q_stage_p_closeout_decisions.csv", index=False)
    manifest.to_csv(out_dir / "stage_q_median_refinement_manifest.csv", index=False)
    decisions[decisions["stage_q_decision"].eq("promote_article_candidate")].to_csv(
        out_dir / "stage_q_promote_without_refit_candidates.csv", index=False
    )
    decisions[decisions["stage_q_priority"].eq(0)].to_csv(
        out_dir / "stage_q_priority0_targets.csv", index=False
    )
    decisions[decisions["stage_q_priority"].eq(1)].to_csv(
        out_dir / "stage_q_priority1_optional_targets.csv", index=False
    )

    counts = decisions["stage_q_decision"].value_counts().to_dict()
    summary = {
        "status": "completed",
        "output_dir": config_path_value(out_dir),
        "stage_q_grid_config": config_path_value(args.stage_q_grid_config),
        "stage_q_generated_root": config_path_value(args.stage_q_generated_root),
        "stage_q_run_root": config_path_value(args.stage_q_run_root),
        "n_stage_p_rows": int(len(decisions)),
        "n_promote_article_candidates": int(counts.get("promote_article_candidate", 0)),
        "n_priority0_nearmiss_targets": int((decisions["stage_q_priority"] == 0).sum()),
        "n_priority1_optional_targets": int((decisions["stage_q_priority"] == 1).sum()),
        "n_do_not_promote_yet": int(counts.get("do_not_promote_yet", 0)),
        "n_stage_q_experiments": int(len(experiments)),
        "n_stage_q_priority0_experiments": int((manifest["priority"] == 0).sum()) if not manifest.empty else 0,
        "n_stage_q_priority1_experiments": int((manifest["priority"] == 1).sum()) if not manifest.empty else 0,
        "stage_m_surface_changed": False,
        "selection_rule": "median_validation_AQL_only",
        "test_metrics_role": "audit_only",
    }
    report = write_report(out_dir, summary, decisions, manifest)
    summary["report"] = config_path_value(report)
    write_json(out_dir / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    print(json.dumps(prepare(args), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
