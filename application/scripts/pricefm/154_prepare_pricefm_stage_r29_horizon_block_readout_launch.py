#!/usr/bin/env python3
"""Prepare the PriceFM Stage-R30 horizon-block readout main launch."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
from typing import Any

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, sha256_file, write_json
from pricefm_full_surface import repo_relative, sha256_file_or_blank
from pricefm_graph import graph_scope_manifest_for_policy


GRID_BLOCK = "pricefm_desn_experiment_grid"
DEFAULT_R28_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r28_objective_model_family_audit_20260711"
)
DEFAULT_TEMPLATE_GRID = "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r29_horizon_block_readout_launch_prep_20260711"
)
DEFAULT_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_r30_horizon_block_readout_main_20260711.yaml"
)
DEFAULT_GRID_ID = "pricefm_stage_r30_horizon_block_readout_main_20260711"
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_r30_horizon_block_readout_main_20260711"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_r30_horizon_block_readout_main_20260711"
)

R28_QUEUE = "pricefm_stage_r28_case_target_queue.csv"
R28_RECOMMENDATIONS = "pricefm_stage_r28_main_launch_recommendations.csv"
R28_CAPABILITY = "pricefm_stage_r28_objective_model_capability_matrix.csv"
R28_GATES = "pricefm_stage_r28_design_gates.csv"

OUT_CASE_PLAN = "pricefm_stage_r29_case_plan.csv"
OUT_ARM_PLAN = "pricefm_stage_r29_arm_plan.csv"
OUT_LAUNCH_MANIFEST = "pricefm_stage_r29_stage_r30_launch_manifest.csv"
OUT_GATES = "pricefm_stage_r29_launch_prep_gates.csv"
OUT_SOURCE = "source_manifest.csv"
OUT_GRID_COPY = "pricefm_stage_r30_horizon_block_readout_grid.yaml"
OUT_REPORT = "pricefm_stage_r29_horizon_block_readout_launch_prep_report.md"

SUPPORTED_FEATURE_POLICIES = {
    "target_only",
    "graph_summary_mean_std",
    "graph_neighbor_spread_summary",
}
BINARY_SUFFIXES = {".rds", ".rda", ".RData", ".rdata"}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r28-dir", default=DEFAULT_R28_DIR)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE_GRID)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--grid-config", default=DEFAULT_GRID_CONFIG)
    p.add_argument("--grid-id", default=DEFAULT_GRID_ID)
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--target-quantile", type=float, default=0.5)
    p.add_argument("--expected-cases", type=int, default=20)
    p.add_argument("--arms-per-case", type=int, default=4)
    p.add_argument("--recommended-experiment-jobs", type=int, default=6)
    p.add_argument("--seed-base", type=int, default=202607300)
    p.add_argument("--write-grid", type=parse_bool, default=False)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def boolish(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y", "passed", "completed"}


def text_value(value: Any) -> str:
    if value is None:
        return ""
    try:
        if pd.isna(value):
            return ""
    except (TypeError, ValueError):
        pass
    return str(value).strip()


def finite_float(value: Any, default: float = float("nan")) -> float:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return float(default)
    return out if math.isfinite(out) else float(default)


def clean_slug(value: Any) -> str:
    out = "".join(ch for ch in str(value).lower().replace("_", "") if ch.isalnum())
    return out or "x"


def short_hash(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:8]


def parse_units(value: Any) -> list[int]:
    if isinstance(value, list):
        return [int(x) for x in value]
    text = text_value(value)
    if not text:
        return [96]
    parsed = json.loads(text)
    if isinstance(parsed, int):
        return [int(parsed)]
    return [int(x) for x in parsed]


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def read_csv_required(path: str | Path, label: str) -> pd.DataFrame:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required CSV: {full}")
    return pd.read_csv(full, low_memory=False)


def read_json_required(path: str | Path, label: str) -> dict[str, Any]:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required JSON: {full}")
    with open(full, "r") as f:
        return json.load(f)


def read_yaml_required(path: str | Path, label: str) -> dict[str, Any]:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required YAML: {full}")
    with open(full, "r") as f:
        payload = yaml.safe_load(f)
    if not isinstance(payload, dict):
        raise ValueError(f"{label} did not parse to a mapping: {full}")
    return payload


def require_columns(frame: pd.DataFrame, columns: list[str], label: str) -> None:
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError(f"{label} missing required columns: {missing}")


def write_frame(path: str | Path, frame: pd.DataFrame) -> None:
    full = repo_path(path)
    full.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(full, index=False)


def write_yaml(path: str | Path, payload: dict[str, Any]) -> None:
    full = repo_path(path)
    full.parent.mkdir(parents=True, exist_ok=True)
    with open(full, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def config_path_value(path: str | Path) -> str:
    full = repo_path(path)
    root = repo_path(".")
    try:
        return str(full.relative_to(root))
    except ValueError:
        return str(full)


def load_pricefm_regions(template: dict[str, Any]) -> list[str]:
    data_path = repo_path(template[GRID_BLOCK]["base"]["data_config"])
    with open(data_path, "r") as f:
        return [str(x) for x in yaml.safe_load(f)["pricefm"]["regions"]]


def graph_fields(region: str, input_regions: list[str], feature_policy: str, graph_degree: int | None = 1) -> dict[str, Any]:
    if feature_policy == "target_only":
        return {
            "input_scope": "local_target_only",
            "output_scope": "target_region_path",
            "lead_covariate_status": "realized_ex_post",
            "spatial_information_set": "local_only_not_pricefm_graph",
        }
    degree = int(graph_degree or 1)
    graph = graph_scope_manifest_for_policy(
        region,
        input_regions,
        feature_policy,
        spatial={"graph_degree": degree},
    )
    neighbors = list(graph.get("neighbor_regions", []))
    common = {
        "graph_degree": int(graph["graph_degree"]),
        "graph_source": graph["graph_source"],
        "graph_hash": graph["graph_hash"],
        "neighbor_regions": neighbors,
        "max_neighbor_regions": len(neighbors),
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "target_lag_features": ["price", "load", "solar", "wind"],
        "target_lead_features": ["load", "solar", "wind"],
    }
    if feature_policy == "graph_summary_mean_std":
        common.update(
            {
                "input_scope": f"pricefm_graph_summary_mean_std_degree{degree}_n{len(neighbors)}",
                "spatial_information_set": "pricefm_released_graph_summary_mean_std",
                "neighbor_lag_features": ["price", "load"],
                "neighbor_lead_features": ["load", "wind"],
                "summary_stats": ["neighbor_mean", "neighbor_sd"],
            }
        )
    elif feature_policy == "graph_neighbor_spread_summary":
        common.update(
            {
                "input_scope": f"pricefm_graph_neighbor_spread_summary_degree{degree}_n{len(neighbors)}",
                "spatial_information_set": "pricefm_neighbor_augmented_spread_summary",
                "neighbor_lag_features": ["price", "load"],
                "neighbor_lead_features": ["load", "wind"],
                "summary_stats": ["mean_diff", "sd", "min_diff", "max_diff"],
            }
        )
    else:
        raise ValueError(f"unsupported Stage-R29 feature policy: {feature_policy}")
    common["spatial"] = {
        "graph_degree": degree,
        "neighbor_regions": neighbors,
        "target_lag_features": common["target_lag_features"],
        "target_lead_features": common["target_lead_features"],
        "neighbor_lag_features": common["neighbor_lag_features"],
        "neighbor_lead_features": common["neighbor_lead_features"],
        "summary_stats": common["summary_stats"],
    }
    return common


def load_inputs(args: argparse.Namespace) -> dict[str, Any]:
    r28 = Path(args.stage_r28_dir)
    return {
        "r28_summary": read_json_required(r28 / "summary.json", "Stage-R28 summary"),
        "r28_queue": read_csv_required(r28 / R28_QUEUE, "Stage-R28 case target queue"),
        "r28_recommendations": read_csv_required(r28 / R28_RECOMMENDATIONS, "Stage-R28 recommendations"),
        "r28_capability": read_csv_required(r28 / R28_CAPABILITY, "Stage-R28 capability matrix"),
        "r28_gates": read_csv_required(r28 / R28_GATES, "Stage-R28 gates"),
        "template": read_yaml_required(args.template_grid_config, "template experiment grid"),
    }


def validate_inputs(inputs: dict[str, Any], args: argparse.Namespace) -> None:
    summary = inputs["r28_summary"]
    if summary.get("status") != "completed_main_launch_path_ready":
        raise ValueError(f"Stage-R28 is not launch-ready: {summary.get('status')}")
    if not inputs["r28_gates"]["passed"].map(boolish).all():
        failed = inputs["r28_gates"].loc[~inputs["r28_gates"]["passed"].map(boolish), "gate"].tolist()
        raise ValueError(f"Stage-R28 gates failed: {failed}")
    rec = inputs["r28_recommendations"].set_index("recommendation")
    if not boolish(rec.loc["stage_r29_prepare_stage_r30_horizon_block_readout_main_launch", "allowed"]):
        raise ValueError("Stage-R28 did not allow the Stage-R29/Stage-R30 launch path.")
    cap = inputs["r28_capability"].set_index("mechanism")
    if str(cap.loc["horizon_block_readout_interaction", "current_support"]) != "implemented_design_matrix_axis":
        raise ValueError("horizon-block readout interaction is not implemented.")
    queue = inputs["r28_queue"]
    require_columns(
        queue,
        [
            "region",
            "fold",
            "stage_r22b_case_id",
            "horizon_focus",
            "include_in_stage_r29_main_launch",
            "lag_window",
            "units",
            "alpha",
            "rho",
            "input_scale",
            "tau0",
            "horizon_weight_multiplier",
        ],
        "Stage-R28 case queue",
    )
    included = queue[queue["include_in_stage_r29_main_launch"].map(boolish)]
    if int(included[["region", "fold"]].drop_duplicates().shape[0]) != int(args.expected_cases):
        raise ValueError("Stage-R29 expected all Stage-R28 cases to be included.")


def build_case_plan(queue: pd.DataFrame) -> pd.DataFrame:
    out = queue[queue["include_in_stage_r29_main_launch"].map(boolish)].copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    out["stage_r29_case_status"] = "included_in_horizon_block_readout_main_launch"
    return out.sort_values(["region", "fold"]).reset_index(drop=True)


def arm_specs(case_row: pd.Series) -> list[dict[str, Any]]:
    base_units = parse_units(case_row["units"])
    base_final = max(64, min(128, int(base_units[-1]) if base_units else 96))
    alpha = clamp(finite_float(case_row["alpha"], 0.4), 0.25, 0.6)
    rho = clamp(finite_float(case_row["rho"], 0.85), 0.7, 0.97)
    input_scale = clamp(finite_float(case_row["input_scale"], 0.3), 0.18, 0.45)
    multiplier = clamp(finite_float(case_row["horizon_weight_multiplier"], 2.0), 1.5, 3.0)
    return [
        {
            "stage_r30_arm": "hb_local_selected_dynamics",
            "arm_ordinal": 1,
            "feature_policy": "target_only",
            "units": [base_final],
            "alpha": alpha,
            "rho": rho,
            "input_scale": input_scale,
            "horizon_weight_multiplier": multiplier,
            "rationale": "local-only parity arm with horizon-block readout interactions",
        },
        {
            "stage_r30_arm": "hb_graph_summary_stable",
            "arm_ordinal": 2,
            "feature_policy": "graph_summary_mean_std",
            "units": [96],
            "alpha": 0.45,
            "rho": 0.82,
            "input_scale": 0.30,
            "horizon_weight_multiplier": multiplier,
            "rationale": "graph summary information set plus stable horizon-block readout",
        },
        {
            "stage_r30_arm": "hb_neighbor_spread_memory",
            "arm_ordinal": 3,
            "feature_policy": "graph_neighbor_spread_summary",
            "units": [128],
            "alpha": 0.30,
            "rho": 0.92,
            "input_scale": 0.25,
            "horizon_weight_multiplier": clamp(multiplier + 0.25, 1.5, 3.0),
            "rationale": "neighbor-spread information set with higher-memory horizon-block readout",
        },
        {
            "stage_r30_arm": "hb_graph_summary_high_memory",
            "arm_ordinal": 4,
            "feature_policy": "graph_summary_mean_std",
            "units": [128],
            "alpha": 0.25,
            "rho": 0.95,
            "input_scale": 0.20,
            "horizon_weight_multiplier": multiplier,
            "rationale": "high-memory graph-summary horizon-block readout",
        },
    ]


def build_arm_plan(case_plan: pd.DataFrame, args: argparse.Namespace) -> pd.DataFrame:
    rows = []
    for _, case_row in case_plan.iterrows():
        for spec in arm_specs(case_row):
            lag_window = int(clamp(finite_float(case_row["lag_window"], 96), 48, 192))
            units = [int(x) for x in spec["units"]]
            rows.append(
                {
                    "region": case_row["region"],
                    "fold": int(case_row["fold"]),
                    "stage_r22b_case_id": case_row["stage_r22b_case_id"],
                    "r28_queue": case_row.get("r28_queue", ""),
                    "horizon_focus": case_row["horizon_focus"],
                    "stage_r30_arm": spec["stage_r30_arm"],
                    "stage_r30_arm_ordinal": int(spec["arm_ordinal"]),
                    "stage_r30_arm_rationale": spec["rationale"],
                    "feature_policy": spec["feature_policy"],
                    "lag_window": lag_window,
                    "depth": 1,
                    "units": json.dumps(units),
                    "feature_dim": int(units[-1]),
                    "state_output": "final_layer",
                    "readout_interaction": "horizon_block",
                    "horizon_block_size": 24,
                    "readout_interaction_basis": "state_lead",
                    "alpha": float(spec["alpha"]),
                    "rho": float(spec["rho"]),
                    "input_scale": float(spec["input_scale"]),
                    "tau0": clamp(finite_float(case_row["tau0"], 0.001), 0.0005, 0.01),
                    "horizon_weight_multiplier": float(spec["horizon_weight_multiplier"]),
                    "horizon_weighting_mode": "integer_frequency_replication",
                    "selection_rule": "validation_AQL_only_within_case",
                    "selection_is_validation_only": True,
                    "test_metrics_role": "audit_only_after_frozen_validation_selection",
                    "mutates_registry": False,
                    "mutates_manuscript": False,
                    "requires_stage_r31_closeout_gate": True,
                    "requires_full_quantile_gate": True,
                    "requires_mcmc_confirmation_gate": True,
                    "case_specific_spec_key": short_hash(
                        "|".join([
                            text_value(case_row["stage_r22b_case_id"]),
                            text_value(spec["stage_r30_arm"]),
                            text_value(case_row["horizon_focus"]),
                            json.dumps(spec, sort_keys=True),
                        ])
                    ),
                }
            )
    out = pd.DataFrame(rows)
    return out.sort_values(["region", "fold", "stage_r30_arm_ordinal"]).reset_index(drop=True)


def experiment_from_arm(row: pd.Series, input_regions: list[str], args: argparse.Namespace, ordinal: int) -> dict[str, Any]:
    region = text_value(row["region"])
    fold = int(row["fold"])
    feature_policy = text_value(row["feature_policy"])
    if feature_policy not in SUPPORTED_FEATURE_POLICIES:
        raise ValueError(f"unsupported Stage-R29 feature policy: {feature_policy}")
    graph = graph_fields(region, input_regions, feature_policy, 1 if feature_policy != "target_only" else None)
    arm = text_value(row["stage_r30_arm"])
    exp_id = f"r30_{clean_slug(region)}_f{fold}_{clean_slug(arm)}_{row['case_specific_spec_key']}"
    metadata = {
        "stage": "pricefm_stage_r29_horizon_block_readout_launch_prep",
        "region": region,
        "fold": fold,
        "stage_r22b_case_id": text_value(row["stage_r22b_case_id"]),
        "stage_r30_arm": arm,
        "horizon_focus": text_value(row["horizon_focus"]),
        "launch_authorized_by_user": True,
        "launcher_invoked_by_prep": False,
        "registry_mutation_authorized": False,
        "manuscript_mutation_authorized": False,
    }
    return {
        "id": exp_id,
        "stage": "stage_r30_horizon_block_readout_main_screening",
        "priority": 0,
        "regions": [region],
        "folds": [fold],
        "quantile": float(args.target_quantile),
        "target_label": "stage_r30_horizon_block_readout_median_screen",
        "feature_map": "window_reservoir_v1",
        "feature_policy": feature_policy,
        "projection_scale": 1.0,
        "state_output": "final_layer",
        "readout_interaction": "horizon_block",
        "horizon_block_size": 24,
        "readout_interaction_basis": "state_lead",
        "lag_window": int(row["lag_window"]),
        "depth": int(row["depth"]),
        "units": parse_units(row["units"]),
        "feature_dim": int(row["feature_dim"]),
        "alpha": float(row["alpha"]),
        "rho": float(row["rho"]),
        "input_scale": float(row["input_scale"]),
        "recurrent_sparsity": 0.05,
        "tau0": float(row["tau0"]),
        "seed": int(args.seed_base) + int(ordinal),
        "training": {
            "horizon_weighting": {
                "enabled": True,
                "mode": "integer_frequency_replication",
                "scope": "horizon_group",
                "focus": text_value(row["horizon_focus"]),
                "multiplier": float(row["horizon_weight_multiplier"]),
                "integer_scale": 4,
                "max_expansion_factor": 6,
                "apply_to": ["qdesn"],
            }
        },
        "rationale": (
            f"Stage-R30 horizon-block readout main launch for {region} fold {fold}; "
            f"arm={arm}; focus={row['horizon_focus']}."
        ),
        **graph,
        "final_decision": "future_stage_r30_candidate_not_registry_promotion",
        "candidate_source_final": "pricefm_stage_r29_horizon_block_readout_launch_prep_20260711",
        "candidate_source": "pricefm_stage_r29_horizon_block_readout_launch_prep_20260711",
        "candidate_family": f"stage_r30_horizon_block_readout_{feature_policy}",
        "factor_changed": f"stage_r30_{clean_slug(arm)}_{row['case_specific_spec_key']}",
        "target_tier": text_value(row.get("r28_queue", "")),
        "selection_rule": text_value(row["selection_rule"]),
        "selection_is_validation_only": True,
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "test_metrics_role": text_value(row["test_metrics_role"]),
        "local_AQL": "",
        "pricefm_AQL": "",
        "test_AQL": "",
        "test_MAE": "",
        "test_RMSE": "",
        "median_registry": json.dumps(metadata, sort_keys=True),
        "stage_r22b_case_id": text_value(row["stage_r22b_case_id"]),
        "stage_r30_arm": arm,
        "stage_r30_arm_rationale": text_value(row["stage_r30_arm_rationale"]),
        "stage_r30_horizon_focus": text_value(row["horizon_focus"]),
        "stage_r30_horizon_weight_multiplier": float(row["horizon_weight_multiplier"]),
        "stage_r30_case_specific_spec_key": text_value(row["case_specific_spec_key"]),
        "implemented_feature_policy": True,
        "launch_authorized_by_user": True,
        "launcher_invoked_by_prep": False,
        "fits_models_when_launched": True,
        "writes_launch_yaml_now": True,
        "mutates_registry": False,
        "mutates_manuscript": False,
        "requires_stage_r31_closeout_gate": True,
        "requires_full_quantile_gate": True,
        "requires_mcmc_confirmation_gate": True,
        "horizon_weighting_enabled": True,
        "horizon_weighting_mode": "integer_frequency_replication",
        "horizon_focus": text_value(row["horizon_focus"]),
        "horizon_weight_multiplier": float(row["horizon_weight_multiplier"]),
    }


def ensure_artifact_hygiene(grid: dict[str, Any]) -> None:
    fixed = grid.setdefault("fixed", {})
    hygiene = fixed.setdefault("artifact_hygiene", {})
    hygiene["enabled"] = True
    hygiene["clean_adapter_patterns"] = sorted(set(hygiene.get("clean_adapter_patterns", []) + ["X_*.csv"]))
    hygiene["clean_model_patterns"] = sorted(set(hygiene.get("clean_model_patterns", []) + ["*.rds", "*.rda", "*.RData", "*.rdata"]))
    hygiene["preserve_patterns"] = sorted(
        set(
            hygiene.get("preserve_patterns", [])
            + [
                "adapter_manifest.json",
                "feature_manifest.json",
                "rows_*.csv",
                "rows_all.csv",
                "y_*.csv",
                "metric_summary.csv",
                "metric_by_horizon.csv",
                "metric_by_horizon_group.csv",
                "model_method_summary.csv",
                "model_parameter_summary.csv",
                "model_trace_summary.csv",
                "predictions_with_naive_scaled.csv",
                "model_predictions_scaled.csv",
                "training_weight_summary.csv",
                "exact_equivalence.csv",
                "warm_start_diagnostics.csv",
                "report.md",
                "*.png",
                "*.pdf",
                "*.json",
                "*.log",
            ]
        )
    )


def build_grid(template: dict[str, Any], experiments: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    payload = copy.deepcopy(template)
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = str(args.grid_id)
    grid["purpose"] = (
        "Stage-R30 PriceFM horizon-block readout main launch. This tests a real "
        "adapter/readout design-matrix mechanism after R25/R27 failed to beat PriceFM."
    )
    grid["base"]["generated_root"] = config_path_value(args.generated_root)
    grid["base"]["run_root"] = config_path_value(args.run_root)
    grid["scope"]["regions"] = sorted({exp["regions"][0] for exp in experiments})
    grid["scope"]["folds"] = sorted({int(exp["folds"][0]) for exp in experiments})
    grid["scope"]["quantiles"] = [float(args.target_quantile)]
    grid["scope"]["horizons"] = "all"
    grid["scope"]["ranking_split"] = "val"
    grid["scope"]["audit_split"] = "test"
    grid["scope"]["ranking_unit"] = "original"
    grid["scope"]["ranking_metric"] = "AQL"
    grid["fixed"]["qdesn_likelihoods"] = ["al", "exal"]
    ensure_artifact_hygiene(grid)
    grid["launch"] = {
        "stage_r30_full_background_launch_authorized_by_user": {
            "priorities": [0],
            "experiment_jobs": int(args.recommended_experiment_jobs),
            "cell_jobs": 1,
            "build_windows": True,
            "dry_run": False,
            "resume": True,
            "force": False,
            "note": "Actual main launch; no dry/smoke run; registry/manuscript mutation remains blocked.",
        }
    }
    grid["experiments"] = experiments
    grid["experiment_blocks"] = []
    return payload


def launch_manifest_from_experiments(experiments: list[dict[str, Any]]) -> pd.DataFrame:
    rows = []
    for exp in experiments:
        rows.append(
            {
                "experiment_id": exp["id"],
                "region": exp["regions"][0],
                "fold": int(exp["folds"][0]),
                "priority": int(exp["priority"]),
                "target_quantile": float(exp["quantile"]),
                "stage": exp["stage"],
                "stage_r22b_case_id": exp["stage_r22b_case_id"],
                "stage_r30_arm": exp["stage_r30_arm"],
                "stage_r30_arm_rationale": exp["stage_r30_arm_rationale"],
                "horizon_focus": exp["stage_r30_horizon_focus"],
                "horizon_weighting_enabled": bool(exp["horizon_weighting_enabled"]),
                "horizon_weighting_mode": exp["horizon_weighting_mode"],
                "horizon_weight_multiplier": float(exp["horizon_weight_multiplier"]),
                "feature_policy": exp["feature_policy"],
                "implemented_feature_policy": bool(exp["implemented_feature_policy"]),
                "lag_window": int(exp["lag_window"]),
                "depth": int(exp["depth"]),
                "units": json.dumps(exp["units"]),
                "feature_dim": int(exp["feature_dim"]),
                "state_output": exp["state_output"],
                "readout_interaction": exp["readout_interaction"],
                "horizon_block_size": int(exp["horizon_block_size"]),
                "readout_interaction_basis": exp["readout_interaction_basis"],
                "alpha": float(exp["alpha"]),
                "rho": float(exp["rho"]),
                "input_scale": float(exp["input_scale"]),
                "tau0": float(exp["tau0"]),
                "seed": int(exp["seed"]),
                "graph_degree": exp.get("graph_degree", ""),
                "selection_is_validation_only": bool(exp["selection_is_validation_only"]),
                "selection_rule": exp["selection_rule"],
                "test_metrics_role": exp["test_metrics_role"],
                "launch_authorized_by_user": bool(exp["launch_authorized_by_user"]),
                "launcher_invoked_by_prep": bool(exp["launcher_invoked_by_prep"]),
                "fits_models_when_launched": bool(exp["fits_models_when_launched"]),
                "mutates_registry": bool(exp["mutates_registry"]),
                "mutates_manuscript": bool(exp["mutates_manuscript"]),
                "requires_stage_r31_closeout_gate": bool(exp["requires_stage_r31_closeout_gate"]),
                "requires_full_quantile_gate": bool(exp["requires_full_quantile_gate"]),
                "requires_mcmc_confirmation_gate": bool(exp["requires_mcmc_confirmation_gate"]),
                "case_specific_spec_key": exp["stage_r30_case_specific_spec_key"],
            }
        )
    return pd.DataFrame(rows).sort_values(["region", "fold", "stage_r30_arm"]).reset_index(drop=True)


def launch_gates(
    case_plan: pd.DataFrame,
    arm_plan: pd.DataFrame,
    launch_manifest: pd.DataFrame,
    grid_written: bool,
    args: argparse.Namespace,
) -> pd.DataFrame:
    expected_rows = int(args.expected_cases) * int(args.arms_per_case)
    rows = [
        ("expected_case_coverage", int(case_plan[["region", "fold"]].drop_duplicates().shape[0]) == int(args.expected_cases), "Every Stage-R28 target case enters Stage-R30."),
        ("expected_arm_count", int(launch_manifest.shape[0]) == expected_rows, "Stage-R30 launches exactly the accepted arm count per case."),
        ("case_specific_specs", launch_manifest["case_specific_spec_key"].astype(str).nunique() == int(launch_manifest.shape[0]), "Every row has a distinct case-specific specification key."),
        ("real_horizon_block_readout", launch_manifest["readout_interaction"].astype(str).eq("horizon_block").all(), "All rows use adapter-consumed horizon-block readout interactions."),
        ("horizon_block_size_24", pd.to_numeric(launch_manifest["horizon_block_size"], errors="coerce").eq(24).all(), "All rows use 24-step horizon blocks."),
        ("true_horizon_weighting_enabled", launch_manifest["horizon_weighting_enabled"].map(boolish).all() and launch_manifest["horizon_weighting_mode"].astype(str).eq("integer_frequency_replication").all(), "All rows retain implemented horizon weighting."),
        ("no_same_family_stage_r4_r19_rescue_reuse", not launch_manifest["stage_r30_arm"].astype(str).str.contains("r4|r19", case=False, regex=True).any(), "Stage-R30 does not reuse Stage-R4/R19 same-family rescue labels."),
        ("validation_selection_only", launch_manifest["selection_is_validation_only"].map(boolish).all() and launch_manifest["selection_rule"].astype(str).eq("validation_AQL_only_within_case").all(), "Future selection is validation-only within each case."),
        ("test_metrics_audit_only", launch_manifest["test_metrics_role"].astype(str).eq("audit_only_after_frozen_validation_selection").all(), "Test metrics remain audit-only after frozen validation selection."),
        ("registry_manuscript_blocked", not launch_manifest["mutates_registry"].map(boolish).any() and not launch_manifest["mutates_manuscript"].map(boolish).any(), "Registry and manuscript mutation remain blocked."),
        ("prep_does_not_invoke_launcher", not launch_manifest["launcher_invoked_by_prep"].map(boolish).any(), "Prep materializes launch inputs but does not invoke launcher."),
        ("confirmation_gates_required", launch_manifest["requires_stage_r31_closeout_gate"].map(boolish).all() and launch_manifest["requires_full_quantile_gate"].map(boolish).all() and launch_manifest["requires_mcmc_confirmation_gate"].map(boolish).all(), "Promotion remains blocked until closeout/full-quantile/MCMC gates."),
        ("implemented_feature_policies_only", set(launch_manifest["feature_policy"].astype(str)).issubset(SUPPORTED_FEATURE_POLICIES), "All feature policies are supported by the adapter."),
        ("bounded_main_launch_axes", arm_plan["lag_window"].between(48, 192).all() and arm_plan["depth"].eq(1).all() and arm_plan["feature_dim"].between(64, 128).all() and arm_plan["alpha"].between(0.2, 0.6).all() and arm_plan["rho"].between(0.7, 0.97).all() and arm_plan["input_scale"].between(0.18, 0.45).all() and arm_plan["tau0"].between(0.0005, 0.01).all(), "The main launch is broad over cases but bounded over fit axes."),
        ("grid_yaml_written", bool(grid_written), "Launch-ready YAML is materialized when requested."),
    ]
    return pd.DataFrame([{"gate": name, "passed": bool(passed), "detail": detail} for name, passed, detail in rows])


def source_manifest(args: argparse.Namespace) -> pd.DataFrame:
    specs = [
        ("stage_r28_summary", Path(args.stage_r28_dir) / "summary.json", "json"),
        ("stage_r28_case_queue", Path(args.stage_r28_dir) / R28_QUEUE, "csv"),
        ("stage_r28_recommendations", Path(args.stage_r28_dir) / R28_RECOMMENDATIONS, "csv"),
        ("stage_r28_capability", Path(args.stage_r28_dir) / R28_CAPABILITY, "csv"),
        ("stage_r28_gates", Path(args.stage_r28_dir) / R28_GATES, "csv"),
        ("template_grid_config", Path(args.template_grid_config), "yaml"),
        ("adapter_builder_source", Path("application/scripts/pricefm/pricefm_desn_adapter.py"), "source"),
        ("grid_materializer_source", Path("application/scripts/pricefm/12_prepare_desn_experiment_grid.py"), "source"),
        ("full_run_source", Path("application/scripts/pricefm/pricefm_full_run.py"), "source"),
        ("model_runner_source", Path("application/scripts/pricefm/08_run_desn_model_smoke.R"), "source"),
    ]
    rows = []
    for label, path, kind in specs:
        full = repo_path(path)
        rows.append(
            {
                "label": label,
                "kind": kind,
                "path": repo_relative(full) if str(full).startswith(str(repo_path("."))) else str(full),
                "exists": full.exists(),
                "bytes": int(full.stat().st_size) if full.exists() and full.is_file() else 0,
                "sha256": sha256_file_or_blank(full) if full.exists() and full.is_file() else "",
            }
        )
    return pd.DataFrame(rows)


def binary_artifact_count(output_dir: str | Path) -> int:
    root = repo_path(output_dir)
    if not root.exists():
        return 0
    return sum(1 for p in root.rglob("*") if p.is_file() and p.suffix in BINARY_SUFFIXES)


def markdown_table(frame: pd.DataFrame, max_rows: int = 25) -> str:
    if frame.empty:
        return "_No rows._"
    sub = frame.head(max_rows).copy()
    cols = list(sub.columns)
    lines = ["| " + " | ".join(cols) + " |", "| " + " | ".join(["---"] * len(cols)) + " |"]
    for _, row in sub.iterrows():
        vals = []
        for col in cols:
            value = row[col]
            if isinstance(value, float):
                vals.append("{:.6g}".format(value))
            else:
                vals.append(str(value).replace("|", "\\|"))
        lines.append("| " + " | ".join(vals) + " |")
    if len(frame) > len(sub):
        lines.extend(["", f"_Showing {len(sub)} of {len(frame)} rows._"])
    return "\n".join(lines)


def build_report(summary: dict[str, Any], gates: pd.DataFrame, case_plan: pd.DataFrame, arm_plan: pd.DataFrame) -> str:
    case_cols = ["region", "fold", "r28_queue", "horizon_focus", "stage_r29_case_status"]
    arm_cols = [
        "stage_r30_arm",
        "feature_policy",
        "lag_window",
        "units",
        "readout_interaction",
        "horizon_block_size",
        "alpha",
        "rho",
        "input_scale",
        "horizon_weight_multiplier",
    ]
    return "\n".join(
        [
            "# PriceFM Stage-R29 Horizon-Block Readout Launch Prep",
            "",
            "Stage-R29 materializes the Stage-R30 main launch after Stage-R28 verified that a consumed horizon-block readout mechanism exists.",
            "",
            "## Summary",
            "",
            f"- Status: `{summary['status']}`",
            f"- Launch experiments: `{summary['n_launch_experiments']}`",
            f"- Cases: `{summary['n_cases']}`",
            f"- Arms per case: `{summary['arms_per_case']}`",
            f"- Grid config: `{summary['grid_config']}`",
            f"- Generated root: `{summary['generated_root']}`",
            f"- Run root: `{summary['run_root']}`",
            f"- Registry mutation authorized: `{summary['registry_mutation_authorized']}`",
            f"- Manuscript mutation authorized: `{summary['manuscript_mutation_authorized']}`",
            "",
            "## Case Plan",
            "",
            markdown_table(case_plan[[col for col in case_cols if col in case_plan.columns]], max_rows=40),
            "",
            "## Arm Families",
            "",
            markdown_table(arm_plan[arm_cols].drop_duplicates(), max_rows=60),
            "",
            "## Gates",
            "",
            markdown_table(gates, max_rows=60),
            "",
            "## Launch Command",
            "",
            "```bash",
            summary["launch_command"],
            "```",
            "",
            "This command is an actual main launch. It is not a dry run or smoke run. Registry, manuscript, article, and MCMC remain blocked until the closeout gates pass.",
            "",
        ]
    )


def run(args: argparse.Namespace) -> dict[str, Any]:
    inputs = load_inputs(args)
    validate_inputs(inputs, args)
    case_plan = build_case_plan(inputs["r28_queue"])
    arm_plan = build_arm_plan(case_plan, args)
    input_regions = load_pricefm_regions(inputs["template"])
    experiments = [
        experiment_from_arm(row, input_regions, args, ordinal)
        for ordinal, (_, row) in enumerate(arm_plan.iterrows(), start=1)
    ]
    grid_payload = build_grid(inputs["template"], experiments, args)
    launch_manifest = launch_manifest_from_experiments(experiments)
    out_dir = repo_path(args.output_dir)
    grid_config = repo_path(args.grid_config)

    if bool(args.write_grid) and grid_config.exists() and not bool(args.force):
        raise FileExistsError(f"{grid_config} already exists; rerun with --force true")
    grid_written = bool(args.write_grid)
    if grid_written:
        write_yaml(grid_config, grid_payload)

    launch_command = (
        "application/data_local/pricefm/venv/bin/python "
        "application/scripts/pricefm/13_run_desn_experiment_grid.py "
        f"--grid-config {config_path_value(grid_config)} "
        f"--priorities 0 --experiment-jobs {int(args.recommended_experiment_jobs)} --cell-jobs 1 "
        "--build-windows true --dry-run false --resume true --force false"
    )
    gates = launch_gates(case_plan, arm_plan, launch_manifest, grid_written, args)
    if not gates["passed"].map(boolish).all():
        failed = gates.loc[~gates["passed"].map(boolish), "gate"].tolist()
        raise ValueError(f"Stage-R29 launch prep gates failed: {failed}")

    out_dir.mkdir(parents=True, exist_ok=True)
    write_frame(out_dir / OUT_CASE_PLAN, case_plan)
    write_frame(out_dir / OUT_ARM_PLAN, arm_plan)
    write_frame(out_dir / OUT_LAUNCH_MANIFEST, launch_manifest)
    write_frame(out_dir / OUT_GATES, gates)
    write_frame(out_dir / OUT_SOURCE, source_manifest(args))
    if grid_written:
        write_yaml(out_dir / OUT_GRID_COPY, grid_payload)

    summary = {
        "stage": "pricefm_stage_r29_horizon_block_readout_launch_prep",
        "status": "completed",
        "stage_r28_dir": config_path_value(args.stage_r28_dir),
        "n_cases": int(case_plan[["region", "fold"]].drop_duplicates().shape[0]),
        "arms_per_case": int(args.arms_per_case),
        "n_launch_experiments": int(launch_manifest.shape[0]),
        "target_quantile": float(args.target_quantile),
        "grid_id": str(args.grid_id),
        "grid_config": config_path_value(grid_config),
        "grid_written": bool(grid_written),
        "writes_launch_yaml": bool(grid_written),
        "launch_command": launch_command,
        "generated_root": config_path_value(args.generated_root),
        "run_root": config_path_value(args.run_root),
        "recommended_experiment_jobs": int(args.recommended_experiment_jobs),
        "cell_jobs": 1,
        "build_windows": True,
        "dry_run": False,
        "resume": True,
        "force": False,
        "prep_invoked_launcher": False,
        "launch_authorized_by_user": True,
        "registry_mutation_authorized": False,
        "manuscript_mutation_authorized": False,
        "article_update_justified_now": False,
        "mcmc_confirmation_authorized": False,
        "promotion_gate": (
            "Future Stage-R31 validation-selected candidates must beat both current authoritative "
            "Q-DESN and cached PriceFM on frozen test audit, then pass full-quantile and MCMC "
            "confirmation before registry/manuscript/article mutation."
        ),
        "recommended_next_action": "launch_stage_r30_background_then_close_out_with_stage_r31_validation_selected_test_audit",
    }
    if grid_written:
        summary["grid_sha256"] = sha256_file(grid_config)
    summary["output_dir_binary_artifact_count"] = binary_artifact_count(out_dir)
    outputs = {
        "case_plan": out_dir / OUT_CASE_PLAN,
        "arm_plan": out_dir / OUT_ARM_PLAN,
        "launch_manifest": out_dir / OUT_LAUNCH_MANIFEST,
        "gates": out_dir / OUT_GATES,
        "source_manifest": out_dir / OUT_SOURCE,
        "report": out_dir / OUT_REPORT,
        "summary_json": out_dir / "summary.json",
    }
    if grid_written:
        outputs["grid_copy"] = out_dir / OUT_GRID_COPY
    summary["outputs"] = {key: repo_relative(path) for key, path in outputs.items()}
    write_json(out_dir / "summary.json", summary)
    (out_dir / OUT_REPORT).write_text(build_report(summary, gates, case_plan, arm_plan))
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    run(parser().parse_args())


if __name__ == "__main__":
    main()
