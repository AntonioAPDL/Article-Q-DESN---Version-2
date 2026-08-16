#!/usr/bin/env python3
"""Prepare the PriceFM Stage-R32 large-capacity/history launch grid."""

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
DEFAULT_STAGE_R29_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r29_horizon_block_readout_launch_prep_20260711"
)
DEFAULT_TEMPLATE_GRID = "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r32_large_capacity_history_launch_prep_20260714"
)
DEFAULT_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_r32_large_capacity_history_20260714.yaml"
)
DEFAULT_GRID_ID = "pricefm_stage_r32_large_capacity_history_20260714"
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_r32_large_capacity_history_20260714"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_r32_large_capacity_history_20260714"
)

R29_CASE_PLAN = "pricefm_stage_r29_case_plan.csv"
R29_GATES = "pricefm_stage_r29_launch_prep_gates.csv"
R29_LAUNCH_MANIFEST = "pricefm_stage_r29_stage_r30_launch_manifest.csv"

OUT_CASE_PLAN = "pricefm_stage_r32_case_plan.csv"
OUT_ARM_PLAN = "pricefm_stage_r32_arm_plan.csv"
OUT_LAUNCH_MANIFEST = "pricefm_stage_r32_large_capacity_launch_manifest.csv"
OUT_GATES = "pricefm_stage_r32_launch_prep_gates.csv"
OUT_ALPHA_TAU0 = "pricefm_stage_r32_alpha_tau0_reference.csv"
OUT_SOURCE = "source_manifest.csv"
OUT_GRID_COPY = "pricefm_stage_r32_large_capacity_history_grid.yaml"
OUT_REPORT = "pricefm_stage_r32_large_capacity_history_launch_prep_report.md"

SUPPORTED_FEATURE_POLICIES = {
    "target_only",
    "graph_khop",
    "graph_summary_mean_std",
    "graph_neighbor_spread_summary",
}
BINARY_SUFFIXES = {".rds", ".rda", ".RData", ".rdata"}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r29-dir", default=DEFAULT_STAGE_R29_DIR)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE_GRID)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--grid-config", default=DEFAULT_GRID_CONFIG)
    p.add_argument("--grid-id", default=DEFAULT_GRID_ID)
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--target-quantile", type=float, default=0.5)
    p.add_argument("--expected-cases", type=int, default=20)
    p.add_argument("--d-values", default="3,4")
    p.add_argument("--n-values", default="100,200,300")
    p.add_argument("--lag-windows", default="300,500")
    p.add_argument("--recommended-experiment-jobs", type=int, default=2)
    p.add_argument("--seed-base", type=int, default=2026073200)
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


def parse_int_list(value: str, name: str) -> list[int]:
    out = []
    for raw in str(value).split(","):
        raw = raw.strip()
        if not raw:
            continue
        out.append(int(raw))
    if not out:
        raise ValueError(f"{name} must contain at least one integer")
    if any(x <= 0 for x in out):
        raise ValueError(f"{name} entries must be positive")
    return out


def clean_slug(value: Any) -> str:
    out = "".join(ch for ch in str(value).lower().replace("_", "") if ch.isalnum())
    return out or "x"


def short_hash(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:8]


def read_csv_required(path: str | Path, label: str) -> pd.DataFrame:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required CSV: {full}")
    return pd.read_csv(full, low_memory=False)


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


def graph_fields(region: str, input_regions: list[str], feature_policy: str) -> dict[str, Any]:
    if feature_policy == "target_only":
        return {
            "input_scope": "local_target_only",
            "output_scope": "target_region_path",
            "lead_covariate_status": "realized_ex_post",
            "spatial_information_set": "local_only_not_pricefm_graph",
        }
    graph = graph_scope_manifest_for_policy(
        region,
        input_regions,
        feature_policy,
        spatial={"graph_degree": 1},
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
        "spatial": {"graph_degree": 1},
    }
    if feature_policy == "graph_khop":
        common.update(
            {
                "input_scope": f"pricefm_graph_khop_degree1_n{len(neighbors)}",
                "spatial_information_set": "pricefm_released_graph_khop_full_feature_concat",
            }
        )
    elif feature_policy == "graph_summary_mean_std":
        common.update(
            {
                "input_scope": f"pricefm_graph_summary_mean_std_degree1_n{len(neighbors)}",
                "spatial_information_set": "pricefm_released_graph_summary_mean_std",
                "target_lag_features": ["price", "load", "solar", "wind"],
                "target_lead_features": ["load", "solar", "wind"],
                "neighbor_lag_features": ["price", "load"],
                "neighbor_lead_features": ["load", "wind"],
                "summary_stats": ["neighbor_mean", "neighbor_sd"],
            }
        )
        common["spatial"].update(
            {
                "neighbor_regions": neighbors,
                "target_lag_features": common["target_lag_features"],
                "target_lead_features": common["target_lead_features"],
                "neighbor_lag_features": common["neighbor_lag_features"],
                "neighbor_lead_features": common["neighbor_lead_features"],
                "summary_stats": common["summary_stats"],
            }
        )
    elif feature_policy == "graph_neighbor_spread_summary":
        common.update(
            {
                "input_scope": f"pricefm_graph_neighbor_spread_summary_degree1_n{len(neighbors)}",
                "spatial_information_set": "pricefm_neighbor_augmented_spread_summary",
                "target_lag_features": ["price", "load", "solar", "wind"],
                "target_lead_features": ["load", "solar", "wind"],
                "neighbor_lag_features": ["price", "load"],
                "neighbor_lead_features": ["load", "wind"],
                "summary_stats": ["mean_diff", "sd", "min_diff", "max_diff"],
            }
        )
        common["spatial"].update(
            {
                "neighbor_regions": neighbors,
                "target_lag_features": common["target_lag_features"],
                "target_lead_features": common["target_lead_features"],
                "neighbor_lag_features": common["neighbor_lag_features"],
                "neighbor_lead_features": common["neighbor_lead_features"],
                "summary_stats": common["summary_stats"],
            }
        )
    else:
        raise ValueError(f"unsupported Stage-R32 feature policy: {feature_policy}")
    return common


def dynamics_profiles() -> list[dict[str, Any]]:
    return [
        {
            "stage_r32_profile": "balanced_final_layer",
            "state_output": "final_layer",
            "alpha": 0.40,
            "rho": 0.86,
            "input_scale": 0.30,
            "tau0": 0.001,
            "rationale": "Balanced dynamics near the historically used alpha/tau0 center.",
        },
        {
            "stage_r32_profile": "slow_memory_concat_regularized",
            "state_output": "concat_layers",
            "alpha": 0.25,
            "rho": 0.95,
            "input_scale": 0.20,
            "tau0": 0.0005,
            "rationale": "Long-memory, lower-input, more regularized readout exposing all layer states.",
        },
    ]


def load_inputs(args: argparse.Namespace) -> dict[str, Any]:
    r29 = Path(args.stage_r29_dir)
    return {
        "case_plan": read_csv_required(r29 / R29_CASE_PLAN, "Stage-R29 case plan"),
        "r29_gates": read_csv_required(r29 / R29_GATES, "Stage-R29 gates"),
        "r29_launch_manifest": read_csv_required(r29 / R29_LAUNCH_MANIFEST, "Stage-R29 launch manifest"),
        "template": read_yaml_required(args.template_grid_config, "template experiment grid"),
    }


def validate_inputs(inputs: dict[str, Any], args: argparse.Namespace) -> None:
    if not inputs["r29_gates"]["passed"].map(boolish).all():
        failed = inputs["r29_gates"].loc[~inputs["r29_gates"]["passed"].map(boolish), "gate"].tolist()
        raise ValueError(f"Stage-R29 gates failed: {failed}")
    require_columns(
        inputs["case_plan"],
        [
            "region",
            "fold",
            "stage_r22b_case_id",
            "horizon_focus",
            "feature_policy",
            "current_pricefm_AQL",
            "current_qdesn_AQL",
            "alpha",
            "rho",
            "input_scale",
            "tau0",
            "horizon_weight_multiplier",
            "stage_r29_case_status",
        ],
        "Stage-R29 case plan",
    )
    included = inputs["case_plan"][
        inputs["case_plan"]["stage_r29_case_status"].astype(str).eq("included_in_horizon_block_readout_main_launch")
    ]
    n_cases = int(included[["region", "fold"]].drop_duplicates().shape[0])
    if n_cases != int(args.expected_cases):
        raise ValueError(f"Expected {args.expected_cases} Stage-R32 target cases, found {n_cases}")
    policies = set(included["feature_policy"].astype(str))
    unsupported = sorted(policies - SUPPORTED_FEATURE_POLICIES)
    if unsupported:
        raise ValueError(f"Stage-R32 unsupported feature policies: {unsupported}")


def build_case_plan(case_plan: pd.DataFrame) -> pd.DataFrame:
    out = case_plan[
        case_plan["stage_r29_case_status"].astype(str).eq("included_in_horizon_block_readout_main_launch")
    ].copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    out["stage_r32_case_status"] = "included_in_large_capacity_history_launch"
    return out.sort_values(["region", "fold"]).reset_index(drop=True)


def build_alpha_tau0_reference(inputs: dict[str, Any]) -> pd.DataFrame:
    rows = []
    for label, frame in [
        ("stage_r29_case_plan", inputs["case_plan"]),
        ("stage_r29_stage_r30_launch_manifest", inputs["r29_launch_manifest"]),
    ]:
        for col in ["alpha", "rho", "input_scale", "tau0", "horizon_weight_multiplier"]:
            if col not in frame.columns:
                continue
            values = pd.to_numeric(frame[col], errors="coerce").dropna()
            if values.empty:
                continue
            rows.append(
                {
                    "source": label,
                    "parameter": col,
                    "min": float(values.min()),
                    "max": float(values.max()),
                    "unique_values": json.dumps(sorted(float(x) for x in values.drop_duplicates())),
                    "n_unique": int(values.nunique()),
                }
            )
    for profile in dynamics_profiles():
        for col in ["alpha", "rho", "input_scale", "tau0"]:
            rows.append(
                {
                    "source": f"stage_r32_profile:{profile['stage_r32_profile']}",
                    "parameter": col,
                    "min": float(profile[col]),
                    "max": float(profile[col]),
                    "unique_values": json.dumps([float(profile[col])]),
                    "n_unique": 1,
                }
            )
    return pd.DataFrame(rows)


def build_arm_plan(case_plan: pd.DataFrame, args: argparse.Namespace) -> pd.DataFrame:
    depths = parse_int_list(args.d_values, "d-values")
    widths = parse_int_list(args.n_values, "n-values")
    lag_windows = parse_int_list(args.lag_windows, "lag-windows")
    if any(d not in {3, 4} for d in depths):
        raise ValueError("Stage-R32 intentionally supports D values 3 and 4 only")
    if any(n not in {100, 200, 300} for n in widths):
        raise ValueError("Stage-R32 intentionally supports n values 100, 200, and 300 only")
    if any(m not in {300, 500} for m in lag_windows):
        raise ValueError("Stage-R32 intentionally supports lag windows 300 and 500 only")
    rows = []
    for _, case in case_plan.iterrows():
        multiplier = min(4.0, max(1.5, finite_float(case["horizon_weight_multiplier"], 2.0)))
        for lag_window in lag_windows:
            for depth in depths:
                for width in widths:
                    for profile in dynamics_profiles():
                        units = [int(width)] * int(depth)
                        arm = (
                            f"cap_l{lag_window}_d{depth}_n{width}_"
                            f"{profile['stage_r32_profile']}"
                        )
                        rows.append(
                            {
                                "region": case["region"],
                                "fold": int(case["fold"]),
                                "stage_r22b_case_id": case["stage_r22b_case_id"],
                                "horizon_focus": case["horizon_focus"],
                                "feature_policy": case["feature_policy"],
                                "current_pricefm_AQL": finite_float(case["current_pricefm_AQL"]),
                                "current_qdesn_AQL": finite_float(case["current_qdesn_AQL"]),
                                "stage_r32_arm": arm,
                                "stage_r32_profile": profile["stage_r32_profile"],
                                "stage_r32_profile_rationale": profile["rationale"],
                                "lag_window": int(lag_window),
                                "depth": int(depth),
                                "n_per_layer": int(width),
                                "units": json.dumps(units),
                                "feature_dim": int(width),
                                "state_output": profile["state_output"],
                                "readout_interaction": "horizon_block",
                                "horizon_block_size": 24,
                                "readout_interaction_basis": "state_lead",
                                "alpha": float(profile["alpha"]),
                                "rho": float(profile["rho"]),
                                "input_scale": float(profile["input_scale"]),
                                "tau0": float(profile["tau0"]),
                                "horizon_weight_multiplier": float(multiplier),
                                "horizon_weighting_mode": "integer_frequency_replication",
                                "selection_rule": "validation_AQL_only_within_case",
                                "selection_is_validation_only": True,
                                "test_metrics_role": "audit_only_after_frozen_validation_selection",
                                "mutates_registry": False,
                                "mutates_manuscript": False,
                                "requires_stage_r33_closeout_gate": True,
                                "requires_full_quantile_gate": True,
                                "requires_mcmc_confirmation_gate": True,
                                "case_specific_spec_key": short_hash(
                                    "|".join(
                                        [
                                            text_value(case["stage_r22b_case_id"]),
                                            text_value(case["region"]),
                                            str(int(case["fold"])),
                                            arm,
                                        ]
                                    )
                                ),
                            }
                        )
    return pd.DataFrame(rows).sort_values(["region", "fold", "lag_window", "depth", "n_per_layer", "stage_r32_profile"]).reset_index(drop=True)


def experiment_from_arm(row: pd.Series, input_regions: list[str], args: argparse.Namespace, ordinal: int) -> dict[str, Any]:
    region = text_value(row["region"])
    fold = int(row["fold"])
    feature_policy = text_value(row["feature_policy"])
    graph = graph_fields(region, input_regions, feature_policy)
    arm = text_value(row["stage_r32_arm"])
    exp_id = f"r32_{clean_slug(region)}_f{fold}_{clean_slug(arm)}_{row['case_specific_spec_key']}"
    metadata = {
        "stage": "pricefm_stage_r32_large_capacity_history_launch_prep",
        "region": region,
        "fold": fold,
        "stage_r22b_case_id": text_value(row["stage_r22b_case_id"]),
        "stage_r32_arm": arm,
        "stage_r32_profile": text_value(row["stage_r32_profile"]),
        "lag_window": int(row["lag_window"]),
        "depth": int(row["depth"]),
        "n_per_layer": int(row["n_per_layer"]),
        "horizon_focus": text_value(row["horizon_focus"]),
        "launch_authorized_by_user": True,
        "launcher_invoked_by_prep": False,
        "registry_mutation_authorized": False,
        "manuscript_mutation_authorized": False,
    }
    return {
        "id": exp_id,
        "stage": "stage_r32_large_capacity_history_screening",
        "priority": 0,
        "regions": [region],
        "folds": [fold],
        "quantile": float(args.target_quantile),
        "target_label": "stage_r32_large_capacity_history_median_screen",
        "feature_map": "window_reservoir_v1",
        "feature_policy": feature_policy,
        "projection_scale": 1.0,
        "lag_window": int(row["lag_window"]),
        "depth": int(row["depth"]),
        "units": json.loads(row["units"]),
        "feature_dim": int(row["feature_dim"]),
        "alpha": float(row["alpha"]),
        "rho": float(row["rho"]),
        "input_scale": float(row["input_scale"]),
        "recurrent_sparsity": 0.05,
        "reservoir_activation": "tanh",
        "state_output": text_value(row["state_output"]),
        "readout_interaction": "horizon_block",
        "horizon_block_size": 24,
        "readout_interaction_basis": "state_lead",
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
            f"Stage-R32 large capacity/history test for {region} fold {fold}; "
            f"lag_window={row['lag_window']}; depth={row['depth']}; "
            f"units={row['units']}; profile={row['stage_r32_profile']}."
        ),
        **graph,
        "final_decision": "future_stage_r32_candidate_not_registry_promotion",
        "candidate_source_final": "pricefm_stage_r32_large_capacity_history_launch_prep_20260714",
        "candidate_source": "pricefm_stage_r32_large_capacity_history_launch_prep_20260714",
        "candidate_family": f"stage_r32_large_capacity_history_{feature_policy}",
        "factor_changed": f"stage_r32_{clean_slug(arm)}_{row['case_specific_spec_key']}",
        "target_tier": "large_capacity_history_rescue",
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
        "stage_r32_arm": arm,
        "stage_r32_profile": text_value(row["stage_r32_profile"]),
        "stage_r32_profile_rationale": text_value(row["stage_r32_profile_rationale"]),
        "stage_r32_horizon_focus": text_value(row["horizon_focus"]),
        "stage_r32_horizon_weight_multiplier": float(row["horizon_weight_multiplier"]),
        "stage_r32_case_specific_spec_key": text_value(row["case_specific_spec_key"]),
        "implemented_feature_policy": True,
        "launch_authorized_by_user": True,
        "launcher_invoked_by_prep": False,
        "fits_models_when_launched": True,
        "writes_launch_yaml_now": True,
        "mutates_registry": False,
        "mutates_manuscript": False,
        "requires_stage_r33_closeout_gate": True,
        "requires_full_quantile_gate": True,
        "requires_mcmc_confirmation_gate": True,
        "horizon_weighting_enabled": True,
        "horizon_weighting_mode": "integer_frequency_replication",
        "horizon_focus": text_value(row["horizon_focus"]),
        "horizon_weight_multiplier": float(row["horizon_weight_multiplier"]),
        "current_pricefm_AQL": float(row["current_pricefm_AQL"]),
        "current_qdesn_AQL": float(row["current_qdesn_AQL"]),
        "n_per_layer": int(row["n_per_layer"]),
    }


def ensure_artifact_hygiene(grid: dict[str, Any]) -> None:
    fixed = grid.setdefault("fixed", {})
    hygiene = fixed.setdefault("artifact_hygiene", {})
    hygiene["enabled"] = True
    hygiene["clean_adapter_patterns"] = sorted(set(hygiene.get("clean_adapter_patterns", []) + ["X_*.csv"]))
    hygiene["clean_model_patterns"] = sorted(
        set(hygiene.get("clean_model_patterns", []) + ["*.rds", "*.rda", "*.RData", "*.rdata"])
    )
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
        "Stage-R32 PriceFM large-capacity/history launch prep. This explicitly tests "
        "whether deeper same-width reservoirs and longer lag windows close the PriceFM gap."
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
    grid["fixed"]["lead_window"] = 96
    grid["fixed"]["feature_map"] = "window_reservoir_v1"
    grid["fixed"]["qdesn_likelihoods"] = ["al", "exal"]
    grid["fixed"]["train_origin_limit"] = int(grid["fixed"].get("train_origin_limit", 3000))
    grid["fixed"]["train_origin_selection"] = str(grid["fixed"].get("train_origin_selection", "tail"))
    grid["fixed"]["row_chunk_size"] = int(grid["fixed"].get("row_chunk_size", 512))
    ensure_artifact_hygiene(grid)
    grid["launch"] = {
        "stage_r32_full_background_launch_authorized_by_user": {
            "priorities": [0],
            "experiment_jobs": int(args.recommended_experiment_jobs),
            "cell_jobs": 1,
            "build_windows": True,
            "dry_run": False,
            "resume": True,
            "force": False,
            "note": "Actual expensive launch when explicitly invoked; prep itself does not launch.",
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
                "stage_r32_arm": exp["stage_r32_arm"],
                "stage_r32_profile": exp["stage_r32_profile"],
                "horizon_focus": exp["stage_r32_horizon_focus"],
                "horizon_weighting_enabled": bool(exp["horizon_weighting_enabled"]),
                "horizon_weighting_mode": exp["horizon_weighting_mode"],
                "horizon_weight_multiplier": float(exp["horizon_weight_multiplier"]),
                "feature_policy": exp["feature_policy"],
                "implemented_feature_policy": bool(exp["implemented_feature_policy"]),
                "lag_window": int(exp["lag_window"]),
                "depth": int(exp["depth"]),
                "n_per_layer": int(exp["n_per_layer"]),
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
                "current_pricefm_AQL": float(exp["current_pricefm_AQL"]),
                "current_qdesn_AQL": float(exp["current_qdesn_AQL"]),
                "selection_is_validation_only": bool(exp["selection_is_validation_only"]),
                "selection_rule": exp["selection_rule"],
                "test_metrics_role": exp["test_metrics_role"],
                "launch_authorized_by_user": bool(exp["launch_authorized_by_user"]),
                "launcher_invoked_by_prep": bool(exp["launcher_invoked_by_prep"]),
                "fits_models_when_launched": bool(exp["fits_models_when_launched"]),
                "mutates_registry": bool(exp["mutates_registry"]),
                "mutates_manuscript": bool(exp["mutates_manuscript"]),
                "requires_stage_r33_closeout_gate": bool(exp["requires_stage_r33_closeout_gate"]),
                "requires_full_quantile_gate": bool(exp["requires_full_quantile_gate"]),
                "requires_mcmc_confirmation_gate": bool(exp["requires_mcmc_confirmation_gate"]),
                "case_specific_spec_key": exp["stage_r32_case_specific_spec_key"],
            }
        )
    return pd.DataFrame(rows).sort_values(["region", "fold", "lag_window", "depth", "n_per_layer", "stage_r32_profile"]).reset_index(drop=True)


def launch_gates(
    case_plan: pd.DataFrame,
    arm_plan: pd.DataFrame,
    launch_manifest: pd.DataFrame,
    grid_written: bool,
    args: argparse.Namespace,
) -> pd.DataFrame:
    depths = parse_int_list(args.d_values, "d-values")
    widths = parse_int_list(args.n_values, "n-values")
    lag_windows = parse_int_list(args.lag_windows, "lag-windows")
    profiles = [x["stage_r32_profile"] for x in dynamics_profiles()]
    expected_rows = int(args.expected_cases) * len(depths) * len(widths) * len(lag_windows) * len(profiles)
    units_same_width = launch_manifest.apply(
        lambda r: json.loads(r["units"]) == [int(r["n_per_layer"])] * int(r["depth"]),
        axis=1,
    ).all()
    no_r30_path_collision = (
        "pricefm_stage_r30_horizon_block_readout_main_20260711" not in str(args.grid_config)
        and "pricefm_stage_r30_horizon_block_readout_main_20260711" not in str(args.generated_root)
        and "pricefm_stage_r30_horizon_block_readout_main_20260711" not in str(args.run_root)
    )
    rows = [
        ("expected_case_coverage", int(case_plan[["region", "fold"]].drop_duplicates().shape[0]) == int(args.expected_cases), "Every current Stage-R30 target case enters Stage-R32."),
        ("expected_experiment_count", int(launch_manifest.shape[0]) == expected_rows, "Stage-R32 covers all requested D/n/m/profile combinations per case."),
        ("large_depth_axis", set(launch_manifest["depth"].astype(int)) == set(depths) and set(depths).issubset({3, 4}), "Only D=3 and D=4 are used."),
        ("same_width_units_axis", units_same_width and set(launch_manifest["n_per_layer"].astype(int)) == set(widths), "Each row uses same-width layers with n in the requested set."),
        ("large_lag_axis", set(launch_manifest["lag_window"].astype(int)) == set(lag_windows) and set(lag_windows).issubset({300, 500}), "Only m=300 and m=500 lag windows are used."),
        ("explicit_alpha_tau0_profiles", set(launch_manifest["stage_r32_profile"].astype(str)) == set(profiles), "The grid explicitly varies alpha/rho/input_scale/tau0 profiles."),
        ("real_horizon_block_readout", launch_manifest["readout_interaction"].astype(str).eq("horizon_block").all(), "All rows keep consumed horizon-block readout interactions."),
        ("true_horizon_weighting_enabled", launch_manifest["horizon_weighting_enabled"].map(boolish).all() and launch_manifest["horizon_weighting_mode"].astype(str).eq("integer_frequency_replication").all(), "All rows retain implemented horizon weighting."),
        ("validation_selection_only", launch_manifest["selection_is_validation_only"].map(boolish).all() and launch_manifest["selection_rule"].astype(str).eq("validation_AQL_only_within_case").all(), "Future selection is validation-only within each case."),
        ("test_metrics_audit_only", launch_manifest["test_metrics_role"].astype(str).eq("audit_only_after_frozen_validation_selection").all(), "Test metrics remain audit-only after frozen validation selection."),
        ("registry_manuscript_blocked", not launch_manifest["mutates_registry"].map(boolish).any() and not launch_manifest["mutates_manuscript"].map(boolish).any(), "Registry and manuscript mutation remain blocked."),
        ("prep_does_not_invoke_launcher", not launch_manifest["launcher_invoked_by_prep"].map(boolish).any(), "Prep materializes launch inputs but does not invoke launcher."),
        ("implemented_feature_policies_only", set(launch_manifest["feature_policy"].astype(str)).issubset(SUPPORTED_FEATURE_POLICIES), "All feature policies are supported by the adapter."),
        ("bounded_expensive_axis_values", launch_manifest["alpha"].between(0.2, 0.45).all() and launch_manifest["rho"].between(0.85, 0.96).all() and launch_manifest["input_scale"].between(0.18, 0.35).all() and launch_manifest["tau0"].between(0.0005, 0.001).all(), "The expensive grid has explicit alpha/rho/input/tau bounds."),
        ("no_active_r30_path_collision", no_r30_path_collision, "Stage-R32 paths do not collide with the active Stage-R30 run."),
        ("grid_yaml_written", bool(grid_written), "Launch-ready YAML is materialized when requested."),
    ]
    return pd.DataFrame([{"gate": name, "passed": bool(passed), "detail": detail} for name, passed, detail in rows])


def source_manifest(args: argparse.Namespace) -> pd.DataFrame:
    specs = [
        ("stage_r29_case_plan", Path(args.stage_r29_dir) / R29_CASE_PLAN, "csv"),
        ("stage_r29_gates", Path(args.stage_r29_dir) / R29_GATES, "csv"),
        ("stage_r29_launch_manifest", Path(args.stage_r29_dir) / R29_LAUNCH_MANIFEST, "csv"),
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


def build_report(
    summary: dict[str, Any],
    gates: pd.DataFrame,
    case_plan: pd.DataFrame,
    arm_plan: pd.DataFrame,
    alpha_tau0: pd.DataFrame,
) -> str:
    case_cols = ["region", "fold", "horizon_focus", "feature_policy", "stage_r32_case_status"]
    arm_cols = [
        "lag_window",
        "depth",
        "n_per_layer",
        "units",
        "state_output",
        "alpha",
        "rho",
        "input_scale",
        "tau0",
        "stage_r32_profile",
    ]
    return "\n".join(
        [
            "# PriceFM Stage-R32 Large-Capacity/History Launch Prep",
            "",
            "Stage-R32 prepares an explicit capacity/history test for the current PriceFM problem cases.",
            "",
            "## Summary",
            "",
            f"- Status: `{summary['status']}`",
            f"- Launch experiments: `{summary['n_launch_experiments']}`",
            f"- Cases: `{summary['n_cases']}`",
            f"- Arms per case: `{summary['arms_per_case']}`",
            f"- Lag windows: `{summary['lag_windows']}`",
            f"- Depths: `{summary['depths']}`",
            f"- Widths: `{summary['n_values']}`",
            f"- Dynamics profiles: `{summary['dynamics_profiles']}`",
            f"- Grid config: `{summary['grid_config']}`",
            f"- Generated root: `{summary['generated_root']}`",
            f"- Run root: `{summary['run_root']}`",
            "",
            "## Current Alpha/Tau0 Reference",
            "",
            markdown_table(alpha_tau0, max_rows=40),
            "",
            "## Cases",
            "",
            markdown_table(case_plan[[col for col in case_cols if col in case_plan.columns]], max_rows=40),
            "",
            "## Arm Axes",
            "",
            markdown_table(arm_plan[arm_cols].drop_duplicates(), max_rows=80),
            "",
            "## Gates",
            "",
            markdown_table(gates, max_rows=80),
            "",
            "## Launch Command",
            "",
            "```bash",
            summary["launch_command"],
            "```",
            "",
            "The command is an actual expensive launch command for later explicit invocation. "
            "This prep stage does not invoke it, and registry/manuscript/article/MCMC mutation remain blocked.",
            "",
        ]
    )


def run(args: argparse.Namespace) -> dict[str, Any]:
    inputs = load_inputs(args)
    validate_inputs(inputs, args)
    case_plan = build_case_plan(inputs["case_plan"])
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
        raise ValueError(f"Stage-R32 launch prep gates failed: {failed}")
    alpha_tau0 = build_alpha_tau0_reference(inputs)

    out_dir.mkdir(parents=True, exist_ok=True)
    write_frame(out_dir / OUT_CASE_PLAN, case_plan)
    write_frame(out_dir / OUT_ARM_PLAN, arm_plan)
    write_frame(out_dir / OUT_LAUNCH_MANIFEST, launch_manifest)
    write_frame(out_dir / OUT_GATES, gates)
    write_frame(out_dir / OUT_ALPHA_TAU0, alpha_tau0)
    write_frame(out_dir / OUT_SOURCE, source_manifest(args))
    if grid_written:
        write_yaml(out_dir / OUT_GRID_COPY, grid_payload)

    depths = parse_int_list(args.d_values, "d-values")
    widths = parse_int_list(args.n_values, "n-values")
    lag_windows = parse_int_list(args.lag_windows, "lag-windows")
    summary = {
        "stage": "pricefm_stage_r32_large_capacity_history_launch_prep",
        "status": "completed",
        "stage_r29_dir": config_path_value(args.stage_r29_dir),
        "n_cases": int(case_plan[["region", "fold"]].drop_duplicates().shape[0]),
        "arms_per_case": int(len(depths) * len(widths) * len(lag_windows) * len(dynamics_profiles())),
        "n_launch_experiments": int(launch_manifest.shape[0]),
        "target_quantile": float(args.target_quantile),
        "depths": depths,
        "n_values": widths,
        "lag_windows": lag_windows,
        "lead_window": 96,
        "dynamics_profiles": [x["stage_r32_profile"] for x in dynamics_profiles()],
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
            "Future Stage-R33 validation-selected candidates must beat both current authoritative "
            "Q-DESN and cached PriceFM on frozen test audit, then pass full-quantile and MCMC "
            "confirmation before registry/manuscript/article mutation."
        ),
        "recommended_next_action": "explicitly_launch_stage_r32_background_when_current_r30_policy_is_resolved",
    }
    if grid_written:
        summary["grid_sha256"] = sha256_file(grid_config)
    summary["output_dir_binary_artifact_count"] = binary_artifact_count(out_dir)
    outputs = {
        "case_plan": out_dir / OUT_CASE_PLAN,
        "arm_plan": out_dir / OUT_ARM_PLAN,
        "launch_manifest": out_dir / OUT_LAUNCH_MANIFEST,
        "gates": out_dir / OUT_GATES,
        "alpha_tau0_reference": out_dir / OUT_ALPHA_TAU0,
        "source_manifest": out_dir / OUT_SOURCE,
        "report": out_dir / OUT_REPORT,
        "summary_json": out_dir / "summary.json",
    }
    if grid_written:
        outputs["grid_copy"] = out_dir / OUT_GRID_COPY
    summary["outputs"] = {key: repo_relative(path) for key, path in outputs.items()}
    write_json(out_dir / "summary.json", summary)
    (out_dir / OUT_REPORT).write_text(build_report(summary, gates, case_plan, arm_plan, alpha_tau0))
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    run(parser().parse_args())


if __name__ == "__main__":
    main()
