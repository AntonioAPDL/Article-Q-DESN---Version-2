#!/usr/bin/env python3
"""Prepare the bounded PriceFM Stage-R36 nested horizon-readout launch."""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
import shutil
from pathlib import Path
from typing import Any

import pandas as pd
import yaml

from pricefm_common import load_config, parse_bool, repo_path, write_json
from pricefm_full_run import load_full_config, missing_window_files


DEFAULT_R35_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r35_failure_decomposition_20260804"
)
DEFAULT_R34_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r34_lean_capacity_history_closeout_20260728"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r36_nested_horizon_readout_launch_prep_20260804"
)
DEFAULT_GRID_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_r36_nested_horizon_readout_20260804"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_r36_nested_horizon_readout_20260804"
)

R35_QUEUE = "pricefm_stage_r35_case_specific_next_queue.csv"
R34_SELECTED = "pricefm_stage_r34_validation_selected_cases.csv"
OUT_CASES = "pricefm_stage_r36_case_plan.csv"
OUT_ARMS = "pricefm_stage_r36_mechanism_arm_plan.csv"
OUT_MANIFEST = "pricefm_stage_r36_launch_manifest.csv"
OUT_PROTOCOL = "pricefm_stage_r36_selection_protocol.csv"
OUT_GATES = "pricefm_stage_r36_launch_prep_gates.csv"
OUT_GRID = "pricefm_stage_r36_nested_horizon_readout_grid.yaml"
OUT_BASE_DATA = "pricefm_stage_r36_base_data_config.yaml"
OUT_BASE_FULL = "pricefm_stage_r36_base_full_config.yaml"
OUT_SOURCE = "source_manifest.csv"
OUT_SUMMARY = "summary.json"
OUT_REPORT = "pricefm_stage_r36_nested_horizon_readout_launch_prep_report.md"
OUT_COMMAND = "pricefm_stage_r36_launch_command.txt"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r35-dir", default=DEFAULT_R35_DIR)
    p.add_argument("--stage-r34-dir", default=DEFAULT_R34_DIR)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--grid-generated-root", default=DEFAULT_GRID_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--artifact-repo-root", default=str(repo_path(".")))
    p.add_argument("--base-data-config", default="application/config/pricefm_data_pipeline.yaml")
    p.add_argument(
        "--base-full-config",
        default=(
            "application/config/"
            "pricefm_desn_model_median_de_lu_fold1_authoritative_reservoir_corrected_20260602.yaml"
        ),
    )
    p.add_argument(
        "--package-path",
        default="/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0",
    )
    p.add_argument("--rscript-bin", default="/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
    p.add_argument(
        "--python-bin",
        default="application/data_local/pricefm/venv/bin/python",
    )
    p.add_argument("--source-model-runner", default="application/scripts/pricefm/08_run_desn_model_smoke.R")
    p.add_argument(
        "--source-horizon-helper",
        default="application/scripts/pricefm/pricefm_horizon_readout.R",
    )
    p.add_argument(
        "--source-full-orchestrator",
        default="application/scripts/pricefm/pricefm_full_run.py",
    )
    p.add_argument(
        "--source-grid-materializer",
        default="application/scripts/pricefm/12_prepare_desn_experiment_grid.py",
    )
    p.add_argument(
        "--source-grid-launcher",
        default="application/scripts/pricefm/13_run_desn_experiment_grid.py",
    )
    p.add_argument(
        "--source-summarizer",
        default="application/scripts/pricefm/09_summarize_desn_model_smoke.py",
    )
    p.add_argument("--expected-targets", type=int, default=11)
    p.add_argument("--expected-harm-guards", type=int, default=2)
    p.add_argument("--experiment-jobs", type=int, default=11)
    p.add_argument("--cell-jobs", type=int, default=1)
    p.add_argument("--cpu-list", default="16-26")
    p.add_argument("--authorize-launch", type=parse_bool, default=False)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def read_json(path: Path) -> dict[str, Any]:
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError(path)
    payload = json.loads(path.read_text())
    if not isinstance(payload, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return payload


def read_csv(path: Path) -> pd.DataFrame:
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError(path)
    return pd.read_csv(path, low_memory=False)


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
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def finite_float(value: Any, default: float = float("nan")) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return float(default)
    return result if math.isfinite(result) else float(default)


def list_value(value: Any) -> list[Any]:
    if isinstance(value, list):
        return value
    if isinstance(value, tuple):
        return list(value)
    if value is None:
        return []
    try:
        if pd.isna(value):
            return []
    except (TypeError, ValueError):
        pass
    text = str(value).strip()
    if not text:
        return []
    parsed = json.loads(text)
    if not isinstance(parsed, list):
        raise ValueError(f"Expected list-valued field, got: {value}")
    return parsed


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_yaml(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(payload, sort_keys=False))


def config_hash(payload: dict[str, Any]) -> str:
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()[:8]


def slug_region(region: str) -> str:
    return str(region).lower().replace("_", "")


def cpu_list_value(value: str) -> list[int]:
    cpus: list[int] = []
    for part in str(value).split(","):
        token = part.strip()
        if not token:
            continue
        if "-" in token:
            start_text, end_text = token.split("-", 1)
            start, end = int(start_text), int(end_text)
            if start < 0 or end < start:
                raise ValueError(f"Invalid CPU range: {token}")
            cpus.extend(range(start, end + 1))
        else:
            cpus.append(int(token))
    if any(cpu < 0 for cpu in cpus) or len(cpus) != len(set(cpus)):
        raise ValueError("CPU list must contain unique nonnegative identifiers")
    return cpus


def absolutize_data_paths(data: dict[str, Any], artifact_root: Path) -> None:
    for key in ["raw_dir", "interim_dir", "processed_dir", "external_repo_dir", "log_dir"]:
        value = data.get(key)
        if value and not Path(str(value)).is_absolute():
            data[key] = str((artifact_root / str(value)).resolve())


def spatial_payload(row: pd.Series) -> dict[str, Any]:
    result: dict[str, Any] = {}
    graph_degree = finite_float(row.get("graph_degree"))
    if math.isfinite(graph_degree):
        result["graph_degree"] = int(graph_degree)
    for key in [
        "neighbor_regions",
        "target_lag_features",
        "target_lead_features",
        "neighbor_lag_features",
        "neighbor_lead_features",
        "summary_stats",
    ]:
        values = list_value(row.get(key))
        if values:
            result[key] = values
    max_neighbors = finite_float(row.get("max_neighbor_regions"))
    if math.isfinite(max_neighbors):
        result["max_neighbor_regions"] = int(max_neighbors)
    for key in ["graph_source", "graph_hash"]:
        value = str(row.get(key, "")).strip()
        if value and value.lower() != "nan":
            result[key] = value
    return result


def make_experiment(queue_row: pd.Series, selected_row: pd.Series) -> dict[str, Any]:
    units = [int(x) for x in list_value(selected_row["units"])]
    if not units:
        units = [int(selected_row["n_per_layer"])] * int(selected_row["depth"])
    spec_key = {
        "region": str(queue_row["region"]),
        "fold": int(queue_row["fold"]),
        "source_experiment": str(selected_row["experiment_id"]),
        "lag_window": int(selected_row["lag_window"]),
        "depth": int(selected_row["depth"]),
        "units": units,
        "tau0": float(selected_row["tau0"]),
        "seed": int(selected_row["seed"]),
    }
    suffix = config_hash(spec_key)
    experiment_id = (
        f"r36_{slug_region(queue_row['region'])}_f{int(queue_row['fold'])}_"
        f"nestedhorizonsep_{suffix}"
    )
    spatial = spatial_payload(selected_row)
    exp: dict[str, Any] = {
        "id": experiment_id,
        "stage": "stage_r36_nested_horizon_readout_qualification",
        "priority": int(queue_row["stage_r35_priority"]),
        "regions": [str(queue_row["region"])],
        "folds": [int(queue_row["fold"])],
        "quantile": 0.5,
        "target_label": "stage_r36_nested_horizon_readout_median_qualification",
        "feature_map": "window_reservoir_v1",
        "feature_policy": str(selected_row["feature_policy"]),
        "projection_scale": 1.0,
        "lag_window": int(selected_row["lag_window"]),
        "depth": int(selected_row["depth"]),
        "units": units,
        "feature_dim": int(selected_row["feature_dim"]),
        "alpha": float(selected_row["alpha"]),
        "rho": float(selected_row["rho"]),
        "input_scale": float(selected_row["input_scale"]),
        "recurrent_sparsity": 0.05,
        "reservoir_activation": "tanh",
        "state_output": str(selected_row["state_output"]),
        "readout_interaction": "none",
        "horizon_block_size": 24,
        "tau0": float(selected_row["tau0"]),
        "seed": int(selected_row["seed"]),
        "training": {
            "horizon_weighting": {
                "enabled": boolish(selected_row["horizon_weighting_enabled"]),
                "mode": str(selected_row["horizon_weighting_mode"]),
                "scope": "horizon_group",
                "focus": str(selected_row["horizon_focus"]),
                "multiplier": float(selected_row["horizon_weight_multiplier"]),
                "integer_scale": 4,
                "max_expansion_factor": 8,
                "apply_to": ["qdesn"],
            }
        },
        "rationale": (
            "Case-specific R34 validation-selected reservoir anchor with a paired shared-versus-"
            "separate horizon-block AL/RHS-NS readout and embargoed nested temporal validation."
        ),
        "stage_r35_queue": str(queue_row["stage_r35_queue"]),
        "protect_current_qdesn": boolish(queue_row["protect_current_qdesn"]),
        "source_r34_experiment_id": str(selected_row["experiment_id"]),
        "source_r34_selected_method": str(selected_row["method_id"]),
        "readout_modes": ["shared_static", "separate_horizon_block"],
        "nested_validation_rule": "median_inner_fold_AQL_scaled_with_worst_fold_harm_guard",
        "existing_test_role": "not_loaded_not_predicted_not_selected",
        "mechanism_qualification_only": True,
        "fresh_confirmation_required": True,
        "selection_rule": "nested_temporal_validation_AQL_only_within_case",
        "selection_is_validation_only": True,
        "selected_on_split": "inner_validation",
        "selected_on_unit": "scaled_within_case",
        "selection_metric": "AQL",
        "test_metrics_role": "quarantined_not_loaded",
        "final_decision": "stage_r36_mechanism_qualification_not_promotion",
        "candidate_source_final": "pricefm_stage_r36_nested_horizon_readout_launch_prep_20260804",
        "candidate_source": "pricefm_stage_r34_validation_selected_cases",
        "candidate_family": "fully_separate_horizon_block_al_rhs_ns",
        "factor_changed": "shared_fit_to_independent_24_horizon_block_fits",
        "target_tier": "priority0_harm_guard" if boolish(queue_row["protect_current_qdesn"]) else "priority1_near_gap",
        "output_scope": str(selected_row.get("output_scope", "target_region_path")),
        "lead_covariate_status": str(selected_row.get("lead_covariate_status", "realized_ex_post")),
        "spatial_information_set": str(selected_row.get("spatial_information_set", "")),
        "input_scope": str(selected_row.get("input_scope", "")),
    }
    if spatial:
        exp["spatial"] = spatial
        exp.update(copy.deepcopy(spatial))
    return exp


def grid_module(path: Path):
    spec = importlib.util.spec_from_file_location("pricefm_r36_grid_materializer", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run(args: argparse.Namespace) -> dict[str, Any]:
    r35_dir = repo_path(args.stage_r35_dir)
    r34_dir = repo_path(args.stage_r34_dir)
    output_dir = repo_path(args.output_dir)
    grid_root = repo_path(args.grid_generated_root)
    run_root = repo_path(args.run_root)
    artifact_root = Path(args.artifact_repo_root).resolve()
    cpu_ids = cpu_list_value(args.cpu_list)
    if output_dir.exists():
        if not args.force:
            raise FileExistsError(f"{output_dir} exists; rerun with --force true")
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    r35_summary = read_json(r35_dir / "summary.json")
    r35_queue = read_csv(r35_dir / R35_QUEUE)
    r34_summary = read_json(r34_dir / "summary.json")
    r34_selected = read_csv(r34_dir / R34_SELECTED)
    targets = r35_queue[r35_queue["stage_r35_priority"].astype(int).isin([0, 1])].copy()
    targets = targets.sort_values(["stage_r35_priority", "region", "fold"]).reset_index(drop=True)
    if len(targets) != int(args.expected_targets):
        raise ValueError(f"Expected {args.expected_targets} R36 targets, found {len(targets)}")
    if targets.duplicated(["region", "fold"]).any():
        raise ValueError("R35 R36-target queue contains duplicate region/fold rows")
    if len(r34_selected) != int(r35_summary.get("r34_cases", 20)):
        raise ValueError("R34 validation-selected table does not cover the R35 case surface")
    if not r34_selected["selection_is_validation_only"].map(boolish).all():
        raise ValueError("R34 source specifications were not selected validation-only")

    selected = targets.merge(r34_selected, on=["region", "fold"], how="left", validate="one_to_one")
    if selected["experiment_id"].isna().any():
        raise ValueError("At least one R36 target lacks an R34 validation-selected anchor")
    experiments = [make_experiment(row, row) for _, row in selected.iterrows()]

    source_data_path = repo_path(args.base_data_config)
    source_full_path = repo_path(args.base_full_config)
    base_data_payload = yaml.safe_load(source_data_path.read_text())
    base_full_payload = yaml.safe_load(source_full_path.read_text())
    absolutize_data_paths(base_data_payload["pricefm"], artifact_root)
    base_data_payload["pricefm"]["allow_absolute_local_paths"] = True
    python_bin = Path(args.python_bin)
    if not python_bin.is_absolute():
        python_bin = (artifact_root / python_bin).resolve()
    base_data_path = output_dir / OUT_BASE_DATA
    base_full_path = output_dir / OUT_BASE_FULL
    base_full = base_full_payload["pricefm_desn_full"]
    base_full["data_config"] = str(base_data_path)
    base_full["package_path"] = str(Path(args.package_path).resolve())
    base_full["rscript_bin"] = str(Path(args.rscript_bin).resolve())
    base_full["python_bin"] = str(python_bin)
    write_yaml(base_data_path, base_data_payload)
    write_yaml(base_full_path, base_full_payload)

    preserve = [
        "*.json", "*.log", "*.pdf", "*.png", "adapter_manifest.json",
        "feature_manifest.json", "feature_provenance.csv", "metric_by_horizon.csv",
        "metric_by_horizon_group.csv", "metric_summary.csv", "model_method_summary.csv",
        "model_parameter_summary.csv", "model_predictions_scaled.csv", "model_trace_summary.csv",
        "nested_validation_folds.csv", "nested_validation_manifest.json",
        "nested_validation_metrics.csv", "predictions_with_naive_scaled.csv", "report.md",
        "rows_*.csv", "rows_all.csv", "training_weight_summary.csv", "warm_start_diagnostics.csv",
        "y_*.csv",
    ]
    grid_payload = {
        "pricefm_desn_experiment_grid": {
            "grid_id": "pricefm_stage_r36_nested_horizon_readout_20260804",
            "purpose": (
                "Case-specific Stage-R36 qualification of a genuinely consumed independent 24-horizon-"
                "block AL/RHS-NS readout under embargoed nested temporal validation."
            ),
            "base": {
                "data_config": str(base_data_path),
                "full_config": str(base_full_path),
                "generated_root": str(grid_root),
                "run_root": str(run_root),
            },
            "scope": {
                "regions": sorted(targets["region"].astype(str).unique().tolist()),
                "folds": sorted(targets["fold"].astype(int).unique().tolist()),
                "splits": ["train", "val"],
                "quantiles": [0.5],
                "horizons": "all",
                "ranking_split": "nested_inner_validation",
                "audit_split": "outer_validation_only_existing_test_quarantined",
                "ranking_unit": "scaled_within_case",
                "ranking_metric": "AQL",
            },
            "fixed": {
                "lead_window": 96,
                "feature_map": "window_reservoir_v1",
                "include_intercept": True,
                "shrink_intercept": False,
                "train_origin_limit": 3000,
                "train_origin_selection": "tail",
                "row_chunk_size": 512,
                "projection_scale": 1.0,
                "recurrent_sparsity": 0.05,
                "reservoir_activation": "tanh",
                "state_output": "final_layer",
                "default_jobs": 1,
                "qdesn_likelihoods": ["al"],
                "normal": {"enabled": False},
                "warm_start": {"enabled": False, "record_diagnostics": True, "fallback_to_cold": False},
                "exact_equivalence": {"enabled": False},
                "qdesn_vb": {
                    "readout_modes": ["shared_static", "separate_horizon_block"],
                    "horizon_readout": {
                        "block_size": 24,
                        "warm_start_components": ["beta", "beta_state", "sigma"],
                    },
                },
                "nested_validation": {
                    "enabled": True,
                    "n_folds": 3,
                    "initial_train_fraction": 0.55,
                    "validation_fraction": 0.15,
                    "min_train_origins": 180,
                    "min_validation_origins": 60,
                    "selection_rule": "median_inner_fold_AQL_scaled_with_worst_fold_harm_guard",
                    "existing_test_role": "not_loaded_not_predicted_not_selected",
                },
                "artifact_hygiene": {
                    "enabled": True,
                    "clean_adapter_patterns": ["X_*.csv"],
                    "clean_model_patterns": ["*.RData", "*.rda", "*.rdata", "*.rds"],
                    "preserve_patterns": preserve,
                },
            },
            "launch": {
                "stage_r36_full_background_launch": {
                    "priorities": [0, 1],
                    "experiment_jobs": int(args.experiment_jobs),
                    "cell_jobs": int(args.cell_jobs),
                    "cpu_ids": cpu_ids,
                    "build_windows": False,
                    "dry_run": False,
                    "resume": True,
                    "force": False,
                    "authorized_now": bool(args.authorize_launch),
                }
            },
            "experiments": experiments,
        }
    }
    grid_path = output_dir / OUT_GRID
    write_yaml(grid_path, grid_payload)

    materializer_path = repo_path(args.source_grid_materializer)
    materializer = grid_module(materializer_path)
    grid = materializer.load_grid(str(grid_path))
    generated_rows = materializer.prepare_grid(grid, str(grid_root), write=True)
    generated = pd.DataFrame(generated_rows)
    generated_by_id = {str(row["id"]): row for row in generated_rows}

    manifest_rows = []
    missing_windows: list[str] = []
    full_contracts = []
    for experiment in experiments:
        generated_row = generated_by_id[experiment["id"]]
        full_cfg = load_full_config(generated_row["full_config"])
        data_cfg = load_config(full_cfg["data_config"])
        missing_windows.extend(
            missing_window_files(
                full_cfg,
                data_cfg,
                experiment["regions"][0],
                experiment["folds"][0],
            )
        )
        full_contracts.append(full_cfg)
        manifest_rows.append({
            "experiment_id": experiment["id"],
            "region": experiment["regions"][0],
            "fold": experiment["folds"][0],
            "priority": experiment["priority"],
            "stage_r35_queue": experiment["stage_r35_queue"],
            "protect_current_qdesn": experiment["protect_current_qdesn"],
            "source_r34_experiment_id": experiment["source_r34_experiment_id"],
            "source_r34_selected_method": experiment["source_r34_selected_method"],
            "feature_policy": experiment["feature_policy"],
            "lag_window": experiment["lag_window"],
            "depth": experiment["depth"],
            "units": json.dumps(experiment["units"]),
            "feature_dim": experiment["feature_dim"],
            "alpha": experiment["alpha"],
            "rho": experiment["rho"],
            "input_scale": experiment["input_scale"],
            "tau0": experiment["tau0"],
            "seed": experiment["seed"],
            "horizon_focus": experiment["training"]["horizon_weighting"]["focus"],
            "horizon_weight_multiplier": experiment["training"]["horizon_weighting"]["multiplier"],
            "readout_modes": json.dumps(experiment["readout_modes"]),
            "nested_validation_folds": 3,
            "configured_splits": json.dumps(["train", "val"]),
            "existing_test_role": experiment["existing_test_role"],
            "selection_rule": experiment["selection_rule"],
            "mechanism_qualification_only": True,
            "fresh_confirmation_required": True,
            "launch_authorized_by_user": bool(args.authorize_launch),
            "mutates_registry": False,
            "mutates_manuscript": False,
            "full_config": generated_row["full_config"],
            "run_dir": generated_row["run_dir"],
        })

    case_plan = targets.copy()
    case_plan["r36_role"] = case_plan["protect_current_qdesn"].map(boolish).map(
        {True: "harm_guard", False: "new_mechanism_qualification"}
    )
    case_plan["source_spec_rule"] = "R34_validation_selected_reservoir_anchor_only"
    case_plan["existing_test_role"] = "quarantined_not_loaded"
    arm_plan = pd.DataFrame([
        {
            "arm": "shared_static",
            "fit_contract": "one_AL_RHS_NS_fit_across_all_horizons",
            "role": "paired_control",
            "independent_coefficients_by_block": False,
            "independent_rhs_state_by_block": False,
        },
        {
            "arm": "separate_horizon_block",
            "fit_contract": "four_independent_AL_RHS_NS_fits_for_1_24_25_48_49_72_73_96",
            "role": "new_consumed_mechanism",
            "independent_coefficients_by_block": True,
            "independent_rhs_state_by_block": True,
        },
    ])
    protocol = pd.DataFrame([
        {"order": 1, "gate": "inner_selection", "rule": "minimum median inner-fold scaled AQL within region/fold"},
        {"order": 2, "gate": "stability", "rule": "separate readout cannot lose materially in the worst inner fold"},
        {"order": 3, "gate": "outer_validation", "rule": "frozen inner winner evaluated on outer validation only"},
        {"order": 4, "gate": "harm_guard", "rule": "NO_4 fold 1 and HU fold 2 preserve authoritative QDESN fallback"},
        {"order": 5, "gate": "existing_test", "rule": "not loaded, predicted, ranked, or inspected during R36"},
        {"order": 6, "gate": "promotion", "rule": "blocked pending fresh confirmation and dual-reference win"},
        {"order": 7, "gate": "MCMC_article_registry", "rule": "blocked pending full-quantile confirmation"},
    ])

    model_text = repo_path(args.source_model_runner).read_text()
    helper_text = repo_path(args.source_horizon_helper).read_text()
    weighting_factors = []
    for experiment in experiments:
        weighting = experiment["training"]["horizon_weighting"]
        scale = int(weighting["integer_scale"])
        multiplier = float(weighting["multiplier"])
        weighting_factors.append((3 * scale + round(multiplier * scale)) / 4.0)
    gates = [
        ("r35_complete", r35_summary.get("status") == "completed_read_only_new_mechanism_required", "R35 is complete."),
        ("r34_complete", str(r34_summary.get("status", "")).startswith("completed"), "R34 is complete."),
        ("target_count", len(manifest_rows) == int(args.expected_targets), "Exactly the bounded priority-0/1 target set is prepared."),
        ("harm_guard_count", sum(boolish(x["protect_current_qdesn"]) for x in manifest_rows) == int(args.expected_harm_guards), "The expected current-QDESN cases are harm guards."),
        ("validation_anchor_only", r34_selected["selection_is_validation_only"].map(boolish).all(), "Reservoir anchors come from R34 validation selection."),
        ("al_only", all(cfg["qdesn_vb"]["likelihoods"] == ["al"] for cfg in full_contracts), "R36 does not repeat the flat AL/exAL axis."),
        ("separate_fits_consumed", "pricefm_fit_horizon_block_models" in model_text and "separate_horizon_block" in model_text, "Runner executes independent block fits."),
        ("nested_selector_consumed", "pricefm_build_nested_temporal_folds" in model_text and "nested_validation_metrics.csv" in model_text, "Runner executes rolling inner folds."),
        ("helper_has_embargo", "response-time embargo" in helper_text, "Nested folds embargo overlapping responses."),
        ("test_quarantined", all(cfg["scope"]["splits"] == ["train", "val"] for cfg in full_contracts), "Generated configs omit test from the runner scope."),
        ("no_adapter_interaction_reuse", all(cfg["adapter"].get("readout_interaction") == "none" for cfg in full_contracts), "R4/R19-style shared interaction rescue is excluded."),
        ("normal_disabled", all(cfg["normal"].get("enabled") is False for cfg in full_contracts), "Normal fits are omitted from the mechanism screen."),
        ("nested_three_fold", all(cfg["nested_validation"].get("n_folds") == 3 for cfg in full_contracts), "Each case uses three inner folds."),
        ("weighting_expansion_bounded", all(factor <= 8.0 for factor in weighting_factors), "Every inherited horizon weighting is representable within the 8x replication ceiling."),
        ("windows_present", not missing_windows, "All pre-existing train/validation windows required by the bounded grid exist."),
        ("package_present", Path(args.package_path).exists(), "The pinned exdqlm package worktree exists."),
        ("rscript_present", Path(args.rscript_bin).exists(), "The configured Rscript exists."),
        ("python_present", python_bin.exists(), "The configured PriceFM Python environment exists."),
        ("one_cpu_per_experiment", len(cpu_ids) >= min(len(manifest_rows), int(args.experiment_jobs)), "Every concurrent experiment has a dedicated CPU affinity."),
        ("registry_manuscript_blocked", not any(x["mutates_registry"] or x["mutates_manuscript"] for x in manifest_rows), "No downstream mutation is enabled."),
    ]
    gate_frame = pd.DataFrame([{"gate": name, "passed": bool(passed), "detail": detail} for name, passed, detail in gates])
    if not gate_frame["passed"].all():
        gate_frame.to_csv(output_dir / OUT_GATES, index=False)
        failures = gate_frame.loc[~gate_frame["passed"], "gate"].tolist()
        raise ValueError(f"Stage-R36 launch prep gates failed: {failures}")

    case_plan.to_csv(output_dir / OUT_CASES, index=False)
    arm_plan.to_csv(output_dir / OUT_ARMS, index=False)
    pd.DataFrame(manifest_rows).to_csv(output_dir / OUT_MANIFEST, index=False)
    protocol.to_csv(output_dir / OUT_PROTOCOL, index=False)
    gate_frame.to_csv(output_dir / OUT_GATES, index=False)
    command = (
        f"{python_bin} {repo_path(args.source_grid_launcher)} --grid-config {grid_path} "
        f"--priorities 0,1 --experiment-jobs {int(args.experiment_jobs)} "
        f"--cell-jobs {int(args.cell_jobs)} --build-windows false --resume true "
        f"--force false --dry-run false --cpu-list {args.cpu_list}"
    )
    (output_dir / OUT_COMMAND).write_text(command + "\n")

    source_paths = [
        Path(__file__).resolve(), r35_dir / "summary.json", r35_dir / R35_QUEUE,
        r34_dir / "summary.json", r34_dir / R34_SELECTED, source_data_path, source_full_path,
        repo_path(args.source_model_runner), repo_path(args.source_horizon_helper),
        repo_path(args.source_full_orchestrator), materializer_path,
        repo_path(args.source_grid_launcher), repo_path(args.source_summarizer),
        base_data_path, base_full_path, grid_path, grid_root / "manifest.csv",
        grid_root / "grid_summary.json",
    ]
    source_paths.extend(Path(row["full_config"]) for row in generated_rows)
    source_paths.extend(Path(row["data_config"]) for row in generated_rows)
    source_rows = []
    for path in sorted(set(path.resolve() for path in source_paths), key=str):
        source_rows.append({
            "path": str(path),
            "exists": path.exists(),
            "bytes": path.stat().st_size if path.exists() else 0,
            "sha256": sha256_file(path) if path.exists() else "",
        })
    pd.DataFrame(source_rows).to_csv(output_dir / OUT_SOURCE, index=False)

    summary = {
        "stage": "pricefm_stage_r36_nested_horizon_readout_launch_prep",
        "status": "completed_launch_ready" if args.authorize_launch else "completed_waiting_for_launch_authorization",
        "n_cases": len(manifest_rows),
        "n_harm_guards": sum(boolish(x["protect_current_qdesn"]) for x in manifest_rows),
        "n_new_mechanism_targets": sum(not boolish(x["protect_current_qdesn"]) for x in manifest_rows),
        "n_experiments": len(generated),
        "readout_modes": ["shared_static", "separate_horizon_block"],
        "likelihoods": ["al"],
        "nested_validation_folds": 3,
        "configured_splits": ["train", "val"],
        "existing_test_loaded": False,
        "writes_launch_yaml": True,
        "launch_authorized_by_user": bool(args.authorize_launch),
        "launch_ready": bool(args.authorize_launch),
        "experiment_jobs": int(args.experiment_jobs),
        "cell_jobs": int(args.cell_jobs),
        "cpu_ids": cpu_ids,
        "mutates_registry": False,
        "mutates_manuscript": False,
        "mcmc_authorized": False,
        "grid_config": str(grid_path),
        "generated_root": str(grid_root),
        "run_root": str(run_root),
        "launch_command": command,
    }
    write_json(output_dir / OUT_SUMMARY, summary)
    report = [
        "# PriceFM Stage-R36 Nested Horizon-Readout Launch Prep",
        "",
        f"- Cases: `{summary['n_cases']}` (`{summary['n_harm_guards']}` harm guards, `{summary['n_new_mechanism_targets']}` qualification targets)",
        "- Mechanism: paired shared AL/RHS-NS control versus four independently fitted 24-horizon-block AL/RHS-NS readouts",
        "- Selection: three embargoed rolling inner folds, case-specific only",
        "- Evaluation scope: `train,val`; the existing test split is not loaded or predicted",
        "- Same-family interaction rescue reuse: excluded",
        f"- Launch authorized: `{summary['launch_authorized_by_user']}`",
        "- Registry, manuscript, MCMC, and article mutation: blocked",
        "",
        "## Scientific Contract",
        "",
        "Each case reuses only its R34 validation-selected reservoir anchor. The paired control and new",
        "mechanism therefore share the same reservoir states, weighting policy, shrinkage, seed, and data",
        "scope. The new arm differs by fitting independent coefficient, scale, and RHS shrinkage states",
        "for horizons 1-24, 25-48, 49-72, and 73-96.",
        "",
        "R36 is mechanism qualification, not promotion evidence. Any promising result still requires",
        "fresh confirmation, full-quantile evaluation, dual-reference wins, and only then MCMC.",
        "",
        "## Launch Command",
        "",
        f"`{command}`",
        "",
    ]
    (output_dir / OUT_REPORT).write_text("\n".join(report))
    return summary


def main() -> None:
    summary = run(parser().parse_args())
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
