#!/usr/bin/env python3
"""Prepare the PriceFM Stage-R25 post-R24 broad horizon-weighted launch."""

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
DEFAULT_R22D_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r22d_case_specific_screening_closeout_20260709"
)
DEFAULT_R23_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r23_mechanism_capability_audit_20260709"
)
DEFAULT_R24_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r24_postfit_calibration_materialized_20260709"
)
DEFAULT_TEMPLATE_GRID = "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r25_post_r24_broad_launch_prep_20260709"
)
DEFAULT_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_r25_post_r24_broad_20260709.yaml"
)
DEFAULT_GRID_ID = "pricefm_stage_r25_post_r24_broad_horizon_weighted_20260709"
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_r25_post_r24_broad_horizon_weighted_20260709"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_r25_post_r24_broad_horizon_weighted_20260709"
)

R22D_CASE_SUMMARY = "pricefm_stage_r22d_case_summary.csv"
R22D_METRIC_ROWS = "pricefm_stage_r22d_metric_rows.csv"
R22D_PROMOTION_QUEUE = "pricefm_stage_r22d_promotion_queue.csv"
R22D_VALIDATION_SELECTED = "pricefm_stage_r22d_validation_selected_case.csv"
R23_CAPABILITY = "pricefm_stage_r23_runner_capability_matrix.csv"
R23_BOUNDS = "pricefm_stage_r23_expensive_path_bounds_recommendation.csv"
R24_GATES = "pricefm_stage_r24_no_launch_gates.csv"

OUT_CASE_PLAN = "pricefm_stage_r25_case_plan.csv"
OUT_ARM_PLAN = "pricefm_stage_r25_arm_plan.csv"
OUT_LAUNCH_MANIFEST = "pricefm_stage_r25_launch_manifest.csv"
OUT_GATES = "pricefm_stage_r25_launch_prep_gates.csv"
OUT_SOURCE = "source_manifest.csv"
OUT_GRID_COPY = "pricefm_stage_r25_post_r24_broad_grid.yaml"
OUT_REPORT = "pricefm_stage_r25_post_r24_broad_launch_prep_report.md"

SUPPORTED_FEATURE_POLICIES = {
    "target_only",
    "graph_khop",
    "graph_summary_mean",
    "graph_summary_mean_std",
    "graph_neighbor_spread_summary",
}
BINARY_SUFFIXES = {".rds", ".rda", ".RData", ".rdata"}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r22d-dir", default=DEFAULT_R22D_DIR)
    p.add_argument("--r23-dir", default=DEFAULT_R23_DIR)
    p.add_argument("--r24-dir", default=DEFAULT_R24_DIR)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE_GRID)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--grid-config", default=DEFAULT_GRID_CONFIG)
    p.add_argument("--grid-id", default=DEFAULT_GRID_ID)
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--target-quantile", type=float, default=0.5)
    p.add_argument("--expected-cases", type=int, default=20)
    p.add_argument("--arms-per-case", type=int, default=10)
    p.add_argument("--recommended-experiment-jobs", type=int, default=6)
    p.add_argument("--seed-base", type=int, default=202607250)
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
        raise ValueError("empty units")
    parsed = json.loads(text)
    if isinstance(parsed, int):
        return [int(parsed)]
    return [int(x) for x in parsed]


def feature_dim(units: list[int], state_output: str) -> int:
    if str(state_output) == "concat_layers":
        return int(sum(units))
    return int(units[-1])


def larger_units(units: list[int]) -> list[int]:
    if len(units) == 1:
        return [max(128, int(round(units[0] * 1.5)))]
    return [min(256, max(96, int(round(x * 4 / 3)))) for x in units]


def deeper_units(units: list[int]) -> list[int]:
    if len(units) >= 3:
        return [max(96, units[0]), max(96, units[1]), max(64, units[-1])]
    first = max(96, units[0])
    last = max(64, units[-1])
    return [first, max(80, int(round((first + last) / 2))), last]


def concat_units(units: list[int]) -> list[int]:
    if len(units) >= 3:
        return [max(96, units[0]), max(96, units[1]), max(64, units[-1])]
    return [max(96, units[0]), max(96, units[0]), max(64, units[-1])]


def cap_concat_units(units: list[int], cap: int = 384) -> list[int]:
    out = [int(x) for x in units]
    while sum(out) > int(cap):
        idx = max(range(len(out)), key=lambda i: out[i])
        floor = 96 if idx < len(out) - 1 else 64
        if out[idx] <= floor:
            break
        out[idx] -= min(out[idx] - floor, sum(out) - int(cap))
    return out


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def alternate_policy(policy: str) -> str:
    if policy != "target_only":
        return "target_only"
    return "graph_summary_mean_std"


def load_pricefm_regions(template: dict[str, Any]) -> list[str]:
    data_path = repo_path(template[GRID_BLOCK]["base"]["data_config"])
    with open(data_path, "r") as f:
        return [str(x) for x in yaml.safe_load(f)["pricefm"]["regions"]]


def graph_fields(region: str, input_regions: list[str], feature_policy: str, graph_degree: int | None) -> dict[str, Any]:
    if feature_policy == "target_only":
        return {
            "input_scope": "local_target_only",
            "output_scope": "target_region_path",
            "lead_covariate_status": "realized_ex_post",
            "spatial_information_set": "local_only_not_pricefm_graph",
        }
    degree = int(graph_degree if graph_degree is not None else 1)
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
    if feature_policy == "graph_khop":
        common.update(
            {
                "input_scope": f"pricefm_graph_khop_degree{degree}",
                "spatial_information_set": "pricefm_released_graph_khop",
                "neighbor_lag_features": [],
                "neighbor_lead_features": [],
                "summary_stats": [],
            }
        )
    elif feature_policy == "graph_summary_mean":
        common.update(
            {
                "input_scope": f"pricefm_graph_summary_mean_degree{degree}",
                "spatial_information_set": "pricefm_released_graph_summary",
                "neighbor_lag_features": ["price", "load", "solar", "wind"],
                "neighbor_lead_features": ["load", "solar", "wind"],
                "summary_stats": ["neighbor_mean"],
            }
        )
    elif feature_policy == "graph_summary_mean_std":
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
        raise ValueError(f"unsupported Stage-R25 feature policy: {feature_policy}")
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
    r22d = Path(args.r22d_dir)
    r23 = Path(args.r23_dir)
    r24 = Path(args.r24_dir)
    return {
        "r22d_summary": read_json_required(r22d / "summary.json", "Stage-R22D summary"),
        "case_summary": read_csv_required(r22d / R22D_CASE_SUMMARY, "Stage-R22D case summary"),
        "metric_rows": read_csv_required(r22d / R22D_METRIC_ROWS, "Stage-R22D metric rows"),
        "promotion_queue": read_csv_required(r22d / R22D_PROMOTION_QUEUE, "Stage-R22D promotion queue"),
        "validation_selected": read_csv_required(r22d / R22D_VALIDATION_SELECTED, "Stage-R22D validation-selected rows"),
        "r23_summary": read_json_required(r23 / "summary.json", "Stage-R23 summary"),
        "r23_capability": read_csv_required(r23 / R23_CAPABILITY, "Stage-R23 capability matrix"),
        "r23_bounds": read_csv_required(r23 / R23_BOUNDS, "Stage-R23 expensive bounds"),
        "r24_summary": read_json_required(r24 / "summary.json", "Stage-R24 summary"),
        "r24_gates": read_csv_required(r24 / R24_GATES, "Stage-R24 gates"),
        "template": read_yaml_required(args.template_grid_config, "template experiment grid"),
    }


def source_mechanism_audit() -> dict[str, bool]:
    runner = repo_path("application/scripts/pricefm/08_run_desn_model_smoke.R").read_text()
    prep = repo_path("application/scripts/pricefm/12_prepare_desn_experiment_grid.py").read_text()
    postfit = repo_path("application/scripts/pricefm/148_materialize_pricefm_stage_r24_postfit_calibration.py")
    return {
        "prep_writes_horizon_weighting": "training[\"horizon_weighting\"]" in prep,
        "runner_builds_horizon_weighting": "build_horizon_weighting" in runner,
        "runner_uses_integer_replication": "integer_frequency_replication" in runner and "train_index_qdesn" in runner,
        "runner_writes_weight_summary": "training_weight_summary.csv" in runner,
        "runner_honors_likelihood_list": "qdesn_likelihoods" in runner and 'if ("exal" %in% qdesn_likelihoods)' in runner,
        "postfit_materializer_exists": postfit.exists(),
    }


def validate_inputs(inputs: dict[str, Any], args: argparse.Namespace) -> dict[str, bool]:
    r22d_summary = inputs["r22d_summary"]
    if r22d_summary.get("status") != "completed_no_promotions":
        raise ValueError(f"Stage-R25 expects negative R22D closeout, got {r22d_summary.get('status')}")
    require_columns(
        inputs["case_summary"],
        [
            "stage_r22b_case_id",
            "region",
            "fold",
            "horizon_focus",
            "validation_selected_minus_current_qdesn",
            "validation_selected_minus_pricefm",
            "current_qdesn_AQL",
            "current_pricefm_AQL",
        ],
        "Stage-R22D case summary",
    )
    require_columns(
        inputs["validation_selected"],
        [
            "experiment_id",
            "region",
            "fold",
            "stage_r22b_case_id",
            "screening_arm",
            "feature_policy",
            "lag_window",
            "depth",
            "units",
            "state_output",
            "alpha",
            "rho",
            "input_scale",
            "tau0",
            "horizon_focus",
            "horizon_weight_multiplier",
            "case_specific_spec_key",
        ],
        "Stage-R22D validation-selected case rows",
    )
    if not inputs["promotion_queue"].empty:
        raise ValueError("Stage-R25 refuses to launch while Stage-R22D has promotable rows")
    if int(inputs["case_summary"][["region", "fold"]].drop_duplicates().shape[0]) != int(args.expected_cases):
        raise ValueError("Stage-R22D case summary does not match expected case count")
    if int(inputs["validation_selected"][["region", "fold"]].drop_duplicates().shape[0]) != int(args.expected_cases):
        raise ValueError("Stage-R22D validation-selected rows do not match expected case count")
    require_columns(inputs["r24_gates"], ["gate", "passed"], "Stage-R24 no-launch gates")
    if not inputs["r24_gates"]["passed"].map(boolish).all():
        failed = inputs["r24_gates"].loc[~inputs["r24_gates"]["passed"].map(boolish), "gate"].tolist()
        raise ValueError(f"Stage-R24 gates failed: {failed}")
    source_audit = source_mechanism_audit()
    if not all(source_audit.values()):
        failed = [key for key, passed in source_audit.items() if not passed]
        raise ValueError(f"Stage-R25 source mechanism audit failed: {failed}")
    return source_audit


def case_gap_tier(gap_to_pricefm: float) -> str:
    if gap_to_pricefm <= 1.0:
        return "near_gap_le_1"
    if gap_to_pricefm <= 1.75:
        return "moderate_gap_le_1p75"
    return "far_gap_gt_1p75"


def build_case_plan(inputs: dict[str, Any]) -> pd.DataFrame:
    case = inputs["case_summary"].copy()
    selected = inputs["validation_selected"].copy()
    selected = selected.add_prefix("selected_")
    selected = selected.rename(
        columns={
            "selected_stage_r22b_case_id": "stage_r22b_case_id",
            "selected_region": "region",
            "selected_fold": "fold",
        }
    )
    out = case.merge(selected, on=["stage_r22b_case_id", "region", "fold"], how="left", validate="one_to_one")
    if out["selected_experiment_id"].isna().any():
        raise ValueError("case plan could not align every case to a validation-selected Stage-R22D row")
    out["pricefm_gap_tier"] = out["validation_selected_minus_pricefm"].map(case_gap_tier)
    out["stage_r25_case_status"] = "eligible_post_r24_true_horizon_weighting"
    out["stage_r25_design_basis"] = (
        "Stage-R22D validation-selected spec plus R23/R24 mechanism audit; "
        "test metrics used only for failure diagnosis, not promotion."
    )
    return out.sort_values(["validation_selected_minus_pricefm", "region", "fold"]).reset_index(drop=True)


def arm_specs(case_row: pd.Series) -> list[dict[str, Any]]:
    base_units = parse_units(case_row["selected_units"])
    base_policy = text_value(case_row["selected_feature_policy"])
    if base_policy not in SUPPORTED_FEATURE_POLICIES:
        raise ValueError(f"unsupported selected feature policy: {base_policy}")
    base_multiplier = clamp(finite_float(case_row["selected_horizon_weight_multiplier"], 2.0), 1.5, 4.0)
    light_multiplier = 1.5 if base_multiplier > 1.5 else 2.0
    heavy_multiplier = clamp(max(3.0, base_multiplier + 1.0), 2.0, 4.0)
    base = {
        "feature_policy": base_policy,
        "lag_window": int(finite_float(case_row["selected_lag_window"], 96)),
        "depth": int(finite_float(case_row["selected_depth"], len(base_units))),
        "units": base_units,
        "state_output": text_value(case_row["selected_state_output"]) or "final_layer",
        "alpha": finite_float(case_row["selected_alpha"], 0.35),
        "rho": finite_float(case_row["selected_rho"], 0.82),
        "input_scale": finite_float(case_row["selected_input_scale"], 0.30),
        "tau0": finite_float(case_row["selected_tau0"], 0.001),
    }
    arms = [
        ("true_weight_base", "base selected geometry, true R24 horizon weighting", {}),
        ("true_weight_light", "lighter focus multiplier tests over-weighting harm", {"horizon_weight_multiplier": light_multiplier}),
        ("true_weight_heavy", "heavier focus multiplier tests stronger horizon repair", {"horizon_weight_multiplier": heavy_multiplier}),
        ("short_lag_weighted", "shorter lag window probes training-window mismatch", {"lag_window": 48}),
        ("long_lag_weighted", "longer lag window probes memory insufficiency", {"lag_window": 192}),
        ("larger_units_weighted", "larger reservoir tests under-capacity", {"units": larger_units(base_units)}),
        ("deeper_units_weighted", "deeper reservoir tests non-linear state capacity", {"units": deeper_units(base_units)}),
        (
            "concat_block_weighted",
            "concat readout plus true weighting tests horizon-block readout capacity",
            {"units": concat_units(base_units), "state_output": "concat_layers"},
        ),
        (
            "alt_information_set_weighted",
            "alternate information set tests graph/local feature mismatch",
            {"feature_policy": alternate_policy(base_policy)},
        ),
        (
            "high_memory_low_input_weighted",
            "high memory with lower input scale tests dynamics mismatch",
            {"alpha": 0.5, "rho": 0.95, "input_scale": 0.2, "tau0": 0.0005},
        ),
    ]
    out = []
    for ordinal, (arm, rationale, updates) in enumerate(arms, start=1):
        spec = copy.deepcopy(base)
        spec.update(copy.deepcopy(updates))
        spec["depth"] = len(spec["units"])
        if spec["state_output"] == "concat_layers":
            spec["units"] = cap_concat_units(spec["units"])
        spec["feature_dim"] = feature_dim(spec["units"], spec["state_output"])
        spec["horizon_weight_multiplier"] = updates.get("horizon_weight_multiplier", base_multiplier)
        spec["arm_ordinal"] = ordinal
        spec["arm"] = arm
        spec["arm_rationale"] = rationale
        out.append(spec)
    return out


def build_arm_plan(case_plan: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for _, case_row in case_plan.iterrows():
        for spec in arm_specs(case_row):
            rows.append(
                {
                    "stage_r22b_case_id": case_row["stage_r22b_case_id"],
                    "region": case_row["region"],
                    "fold": int(case_row["fold"]),
                    "pricefm_gap_tier": case_row["pricefm_gap_tier"],
                    "horizon_focus": case_row["horizon_focus"],
                    "current_qdesn_AQL": finite_float(case_row["current_qdesn_AQL"]),
                    "current_pricefm_AQL": finite_float(case_row["current_pricefm_AQL"]),
                    "validation_selected_minus_current_qdesn": finite_float(
                        case_row["validation_selected_minus_current_qdesn"]
                    ),
                    "validation_selected_minus_pricefm": finite_float(case_row["validation_selected_minus_pricefm"]),
                    "selected_stage_r22c_experiment_id": case_row["selected_experiment_id"],
                    "selected_stage_r22c_screening_arm": case_row["selected_screening_arm"],
                    "stage_r25_arm": spec["arm"],
                    "stage_r25_arm_ordinal": int(spec["arm_ordinal"]),
                    "stage_r25_arm_rationale": spec["arm_rationale"],
                    "feature_policy": spec["feature_policy"],
                    "lag_window": int(spec["lag_window"]),
                    "depth": int(spec["depth"]),
                    "units": json.dumps(spec["units"]),
                    "feature_dim": int(spec["feature_dim"]),
                    "state_output": spec["state_output"],
                    "alpha": float(spec["alpha"]),
                    "rho": float(spec["rho"]),
                    "input_scale": float(spec["input_scale"]),
                    "tau0": float(spec["tau0"]),
                    "horizon_weighting_enabled": True,
                    "horizon_weighting_mode": "integer_frequency_replication",
                    "horizon_weighting_scope": "horizon_group",
                    "horizon_weight_multiplier": float(spec["horizon_weight_multiplier"]),
                    "horizon_weight_integer_scale": 2,
                    "horizon_weight_max_expansion_factor": 6,
                    "stage_r25_selection_rule": "validation_AQL_only_within_case",
                    "stage_r25_test_metrics_role": "audit_only_after_frozen_validation_selection",
                    "mutates_registry": False,
                    "mutates_manuscript": False,
                    "requires_stage_r26_closeout_gate": True,
                    "requires_postfit_calibration_gate": True,
                    "requires_full_quantile_gate": True,
                    "case_specific_spec_key": short_hash(
                        f"{case_row['stage_r22b_case_id']}|{spec['arm']}|{json.dumps(spec, sort_keys=True)}"
                    ),
                }
            )
    return pd.DataFrame(rows).sort_values(["region", "fold", "stage_r25_arm_ordinal"]).reset_index(drop=True)


def experiment_from_arm(row: pd.Series, input_regions: list[str], args: argparse.Namespace, ordinal: int) -> dict[str, Any]:
    region = text_value(row["region"])
    if region not in input_regions:
        raise ValueError(f"unknown PriceFM region in Stage-R25 design: {region}")
    fold = int(row["fold"])
    feature_policy = text_value(row["feature_policy"])
    graph = graph_fields(region, input_regions, feature_policy, 1 if feature_policy != "target_only" else None)
    units = parse_units(row["units"])
    state_output = text_value(row["state_output"]) or "final_layer"
    arm = text_value(row["stage_r25_arm"])
    case_id = text_value(row["stage_r22b_case_id"])
    exp_id = f"r25_{clean_slug(region)}_f{fold}_{clean_slug(arm)}_{row['case_specific_spec_key']}"
    metadata = {
        "stage": "pricefm_stage_r25_post_r24_broad_launch_prep",
        "stage_r22b_case_id": case_id,
        "selected_stage_r22c_experiment_id": text_value(row["selected_stage_r22c_experiment_id"]),
        "region": region,
        "fold": fold,
        "horizon_focus": text_value(row["horizon_focus"]),
        "stage_r25_arm": arm,
        "current_qdesn_AQL": finite_float(row["current_qdesn_AQL"]),
        "current_pricefm_AQL": finite_float(row["current_pricefm_AQL"]),
        "validation_selected_minus_pricefm": finite_float(row["validation_selected_minus_pricefm"]),
        "pricefm_gap_tier": text_value(row["pricefm_gap_tier"]),
        "launch_authorized_by_user": True,
        "launcher_invoked_by_prep": False,
        "registry_mutation_authorized": False,
        "manuscript_mutation_authorized": False,
    }
    return {
        "id": exp_id,
        "stage": "stage_r25_post_r24_broad_horizon_weighted_screening",
        "priority": 0,
        "regions": [region],
        "folds": [fold],
        "quantile": float(args.target_quantile),
        "target_label": "stage_r25_post_r24_broad_median_screen",
        "feature_map": "window_reservoir_v1",
        "feature_policy": feature_policy,
        "projection_scale": 1.0,
        "state_output": state_output,
        "lag_window": int(row["lag_window"]),
        "depth": int(row["depth"]),
        "units": units,
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
                "integer_scale": int(row["horizon_weight_integer_scale"]),
                "max_expansion_factor": int(row["horizon_weight_max_expansion_factor"]),
                "apply_to": ["qdesn"],
            }
        },
        "rationale": (
            f"Stage-R25 post-R24 broad true-horizon-weighted screen for {region} fold {fold}; "
            f"case={case_id}; arm={arm}; focus={row['horizon_focus']}; "
            f"previous validation-selected PriceFM gap={finite_float(row['validation_selected_minus_pricefm']):.6g}."
        ),
        **graph,
        "final_decision": "future_stage_r25_candidate_not_registry_promotion",
        "candidate_source_final": "pricefm_stage_r25_post_r24_broad_launch_prep_20260709",
        "candidate_source": "pricefm_stage_r25_post_r24_broad_launch_prep_20260709",
        "candidate_family": f"stage_r25_{clean_slug(arm)}_{feature_policy}",
        "factor_changed": f"stage_r25_{clean_slug(arm)}_{row['case_specific_spec_key']}",
        "target_tier": text_value(row["pricefm_gap_tier"]),
        "selection_rule": text_value(row["stage_r25_selection_rule"]),
        "selection_is_validation_only": True,
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "test_metrics_role": text_value(row["stage_r25_test_metrics_role"]),
        "local_AQL": "",
        "pricefm_AQL": "",
        "test_AQL": "",
        "test_MAE": "",
        "test_RMSE": "",
        "median_registry": json.dumps(metadata, sort_keys=True),
        "stage_r22b_case_id": case_id,
        "stage_r25_arm": arm,
        "stage_r25_arm_rationale": text_value(row["stage_r25_arm_rationale"]),
        "stage_r25_horizon_focus": text_value(row["horizon_focus"]),
        "stage_r25_horizon_weight_multiplier": float(row["horizon_weight_multiplier"]),
        "stage_r25_pricefm_gap_tier": text_value(row["pricefm_gap_tier"]),
        "stage_r25_case_specific_spec_key": text_value(row["case_specific_spec_key"]),
        "implemented_feature_policy": True,
        "launch_authorized_by_user": True,
        "launcher_invoked_by_prep": False,
        "fits_models_when_launched": True,
        "writes_launch_yaml_now": True,
        "mutates_registry": False,
        "mutates_manuscript": False,
        "requires_stage_r26_closeout_gate": True,
        "requires_postfit_calibration_gate": True,
        "requires_full_quantile_gate": True,
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
        "Stage-R25 post-R24 broad PriceFM DESN launch. This is the first broad "
        "screen after true horizon weighting was wired into the runner. It keeps "
        "selection validation-only and blocks registry/manuscript mutation."
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
        "stage_r25_full_background_launch_authorized_by_user": {
            "priorities": [0],
            "experiment_jobs": int(args.recommended_experiment_jobs),
            "cell_jobs": 1,
            "build_windows": True,
            "dry_run": False,
            "resume": True,
            "force": False,
            "note": (
                "Actual broad launch command. No dry/smoke run is required after prep gates pass; "
                "registry and manuscript mutation remain blocked."
            ),
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
                "stage_r25_arm": exp["stage_r25_arm"],
                "stage_r25_arm_rationale": exp["stage_r25_arm_rationale"],
                "pricefm_gap_tier": exp["stage_r25_pricefm_gap_tier"],
                "horizon_focus": exp["stage_r25_horizon_focus"],
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
                "requires_stage_r26_closeout_gate": bool(exp["requires_stage_r26_closeout_gate"]),
                "requires_postfit_calibration_gate": bool(exp["requires_postfit_calibration_gate"]),
                "requires_full_quantile_gate": bool(exp["requires_full_quantile_gate"]),
                "case_specific_spec_key": exp["stage_r25_case_specific_spec_key"],
            }
        )
    return pd.DataFrame(rows).sort_values(["region", "fold", "stage_r25_arm"]).reset_index(drop=True)


def launch_gates(
    case_plan: pd.DataFrame,
    arm_plan: pd.DataFrame,
    launch_manifest: pd.DataFrame,
    source_audit: dict[str, bool],
    grid_written: bool,
    args: argparse.Namespace,
) -> pd.DataFrame:
    expected_rows = int(args.expected_cases) * int(args.arms_per_case)
    gates = [
        ("r22d_completed_negative_closeout", True, "R22D completed with no promotable rows."),
        (
            "expected_case_coverage",
            int(case_plan[["region", "fold"]].drop_duplicates().shape[0]) == int(args.expected_cases),
            "Every Stage-R22B/R22D case enters Stage-R25.",
        ),
        (
            "expected_arm_count",
            int(launch_manifest.shape[0]) == expected_rows,
            "Stage-R25 launches the accepted broad arm count per case.",
        ),
        (
            "case_specific_specs",
            launch_manifest["case_specific_spec_key"].astype(str).nunique() == int(launch_manifest.shape[0]),
            "Every row has a distinct case-specific specification key.",
        ),
        (
            "true_horizon_weighting_enabled",
            launch_manifest["horizon_weighting_enabled"].map(boolish).all()
            and launch_manifest["horizon_weighting_mode"].astype(str).eq("integer_frequency_replication").all(),
            "All rows request the R24 true horizon-weighted training path.",
        ),
        (
            "no_same_family_stage_r4_r19_rescue_reuse",
            not launch_manifest["stage_r25_arm"].astype(str).str.contains("r4|r19", case=False, regex=True).any(),
            "R25 uses new post-R24 mechanism arms, not same-family Stage-R4/R19 rescue reuse.",
        ),
        (
            "validation_selection_only",
            launch_manifest["selection_is_validation_only"].map(boolish).all()
            and launch_manifest["selection_rule"].astype(str).eq("validation_AQL_only_within_case").all(),
            "Future selection is validation-only within each case.",
        ),
        (
            "test_metrics_audit_only",
            launch_manifest["test_metrics_role"].astype(str).eq("audit_only_after_frozen_validation_selection").all(),
            "Test metrics remain audit-only after frozen validation selection.",
        ),
        (
            "registry_manuscript_blocked",
            not launch_manifest["mutates_registry"].map(boolish).any()
            and not launch_manifest["mutates_manuscript"].map(boolish).any(),
            "Registry and manuscript mutation remain blocked.",
        ),
        (
            "prep_does_not_invoke_launcher",
            not launch_manifest["launcher_invoked_by_prep"].map(boolish).any(),
            "Prep materializes launch inputs but does not invoke the launcher.",
        ),
        (
            "full_closeout_gates_required",
            launch_manifest["requires_stage_r26_closeout_gate"].map(boolish).all()
            and launch_manifest["requires_postfit_calibration_gate"].map(boolish).all()
            and launch_manifest["requires_full_quantile_gate"].map(boolish).all(),
            "Promotion is blocked until R26 closeout, optional postfit, and full-quantile gates pass.",
        ),
        (
            "implemented_feature_policies_only",
            set(launch_manifest["feature_policy"].astype(str)).issubset(SUPPORTED_FEATURE_POLICIES),
            "All feature policies are supported by the local adapter.",
        ),
        (
            "bounded_expensive_axes",
            arm_plan["lag_window"].between(48, 192).all()
            and arm_plan["depth"].between(1, 4).all()
            and arm_plan["feature_dim"].between(32, 384).all()
            and arm_plan["alpha"].between(0.2, 0.7).all()
            and arm_plan["rho"].between(0.6, 0.99).all()
            and arm_plan["input_scale"].between(0.15, 0.7).all()
            and arm_plan["tau0"].between(0.0001, 0.02).all(),
            "The expensive path is broad but bounded over n/D/lag/dynamics/prior axes.",
        ),
        (
            "source_mechanisms_are_real",
            all(source_audit.values()),
            "Current R24 source hooks are present for horizon weighting, likelihoods, and postfit materialization.",
        ),
        (
            "grid_yaml_written",
            bool(grid_written),
            "Launch-ready YAML is materialized when requested.",
        ),
    ]
    return pd.DataFrame([{"gate": name, "passed": bool(passed), "detail": detail} for name, passed, detail in gates])


def source_manifest(args: argparse.Namespace) -> pd.DataFrame:
    specs = [
        ("stage_r22d_summary", Path(args.r22d_dir) / "summary.json", "json"),
        ("stage_r22d_case_summary", Path(args.r22d_dir) / R22D_CASE_SUMMARY, "csv"),
        ("stage_r22d_metric_rows", Path(args.r22d_dir) / R22D_METRIC_ROWS, "csv"),
        ("stage_r22d_promotion_queue", Path(args.r22d_dir) / R22D_PROMOTION_QUEUE, "csv"),
        ("stage_r22d_validation_selected", Path(args.r22d_dir) / R22D_VALIDATION_SELECTED, "csv"),
        ("stage_r23_summary", Path(args.r23_dir) / "summary.json", "json"),
        ("stage_r23_capability", Path(args.r23_dir) / R23_CAPABILITY, "csv"),
        ("stage_r23_expensive_bounds", Path(args.r23_dir) / R23_BOUNDS, "csv"),
        ("stage_r24_summary", Path(args.r24_dir) / "summary.json", "json"),
        ("stage_r24_gates", Path(args.r24_dir) / R24_GATES, "csv"),
        ("template_grid_config", Path(args.template_grid_config), "yaml"),
        ("r24_runner_source", Path("application/scripts/pricefm/08_run_desn_model_smoke.R"), "source"),
        ("grid_prep_source", Path("application/scripts/pricefm/12_prepare_desn_experiment_grid.py"), "source"),
        ("r24_postfit_source", Path("application/scripts/pricefm/148_materialize_pricefm_stage_r24_postfit_calibration.py"), "source"),
    ]
    rows = []
    for label, path, kind in specs:
        full = repo_path(path)
        rows.append(
            {
                "label": label,
                "kind": kind,
                "path": repo_relative(full),
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
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in sub.iterrows():
        vals = []
        for col in cols:
            value = row[col]
            if isinstance(value, float):
                vals.append("{:.6g}".format(value))
            else:
                vals.append(str(value))
        lines.append("| " + " | ".join(vals) + " |")
    if len(frame) > len(sub):
        lines.append("")
        lines.append(f"_Showing {len(sub)} of {len(frame)} rows._")
    return "\n".join(lines)


def build_report(summary: dict[str, Any], gates: pd.DataFrame, case_plan: pd.DataFrame, arm_plan: pd.DataFrame) -> str:
    case_cols = [
        "region",
        "fold",
        "horizon_focus",
        "pricefm_gap_tier",
        "validation_selected_minus_pricefm",
        "stage_r25_case_status",
    ]
    arm_cols = [
        "stage_r25_arm",
        "lag_window",
        "depth",
        "units",
        "feature_policy",
        "state_output",
        "horizon_weight_multiplier",
    ]
    return "\n".join(
        [
            "# PriceFM Stage-R25 Post-R24 Broad Launch Prep",
            "",
            "Stage-R25 is the first broad PriceFM launch prepared after Stage-R24 made horizon weighting real in the runner.",
            "It intentionally targets all Stage-R22D failed cases with case-specific specifications, not a single global DESN recipe.",
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
            "## Diagnosis",
            "",
            "R22C/R22D completed with no promotable candidates: the screen beat simple naive baselines in many rows, but did not beat PriceFM.",
            "R23 diagnosed that the intended horizon-weighting and postfit calibration mechanisms were not real launch-time fitting paths.",
            "R24 implemented true Q-DESN horizon weighting and a postfit calibration materializer, so R25 can now spend the expensive budget on the actual mechanism.",
            "",
            "## Case Plan",
            "",
            markdown_table(case_plan[case_cols], max_rows=30),
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
            "The command is an actual background-launch command, not a dry run. Registry and manuscript mutation remain blocked.",
            "",
        ]
    )


def run(args: argparse.Namespace) -> dict[str, Any]:
    inputs = load_inputs(args)
    source_audit = validate_inputs(inputs, args)
    case_plan = build_case_plan(inputs)
    arm_plan = build_arm_plan(case_plan)
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
    summary = {
        "stage": "pricefm_stage_r25_post_r24_broad_launch_prep",
        "status": "completed",
        "r22d_dir": config_path_value(args.r22d_dir),
        "r23_dir": config_path_value(args.r23_dir),
        "r24_dir": config_path_value(args.r24_dir),
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
        "source_mechanism_audit": source_audit,
        "r25_scientific_gate": (
            "Future Stage-R26 validation-selected candidates must beat both current authoritative "
            "Q-DESN and PriceFM on frozen test audit, then pass a full-quantile confirmation gate "
            "before any registry or manuscript mutation."
        ),
        "postfit_calibration_next_gate": (
            "Stage-R24 postfit calibration should be applied after Stage-R25 prediction artifacts exist."
        ),
        "recommended_next_action": "launch_stage_r25_background_then_close_out_with_stage_r26_validation_selected_test_audit",
    }
    gates = launch_gates(case_plan, arm_plan, launch_manifest, source_audit, grid_written, args)
    if not gates["passed"].map(boolish).all():
        failed = gates.loc[~gates["passed"].map(boolish), "gate"].tolist()
        raise ValueError(f"Stage-R25 launch prep gates failed: {failed}")

    out_dir.mkdir(parents=True, exist_ok=True)
    write_frame(out_dir / OUT_CASE_PLAN, case_plan)
    write_frame(out_dir / OUT_ARM_PLAN, arm_plan)
    write_frame(out_dir / OUT_LAUNCH_MANIFEST, launch_manifest)
    write_frame(out_dir / OUT_GATES, gates)
    write_frame(out_dir / OUT_SOURCE, source_manifest(args))
    if grid_written:
        write_yaml(out_dir / OUT_GRID_COPY, grid_payload)
        summary["grid_sha256"] = sha256_file(grid_config)
    summary["output_dir_binary_artifact_count"] = binary_artifact_count(out_dir)
    write_json(out_dir / "summary.json", summary)
    (out_dir / OUT_REPORT).write_text(build_report(summary, gates, case_plan, arm_plan))
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    run(parser().parse_args())


if __name__ == "__main__":
    main()
