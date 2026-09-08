#!/usr/bin/env python3
"""Advance the validation-only R93 RHS, outer-confirmation, and quantile gates."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import shutil
from typing import Any

import numpy as np
import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, sha256_file


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
RHS_PREP = DATA / "authoritative/pricefm_stage_r93_ridge_closeout_rhs_prep_20260906"
RHS_GENERATED = DATA / "experiment_grids/pricefm_stage_r93_region_frozen_rhs_20260906"
R93_OUTPUT = DATA / "authoritative/pricefm_stage_r93_overnight_validation_ladder_20260906"
REFINE_GENERATED = DATA / "experiment_grids/pricefm_stage_r93_region_frozen_rhs_refinement_20260906"
REFINE_RUNS = DATA / "runs/pricefm_stage_r93_region_frozen_rhs_refinement_20260906"
OUTER_GENERATED = DATA / "experiment_grids/pricefm_stage_r93_region_frozen_outer_normal_20260906"
OUTER_RUNS = DATA / "runs/pricefm_stage_r93_region_frozen_outer_normal_20260906"
OUTER_PROCESSED = DATA / "processed_stage_r93_region_frozen_outer_20260906"
QUANTILE_RUNS = DATA / "runs/pricefm_stage_r93_region_frozen_quantile_validation_20260906"
R82_LIBRARY = DATA / "runtime_libraries/exdqlm_pricefm_r82_structured_init_repair"
R82_MANIFEST = R82_LIBRARY / "pricefm_stage_r82_structured_init_repair_manifest.json"
R82_SOURCE = DATA / "runtime_sources/exdqlm_pricefm_r82_structured_init_repair/exdqlm"
R93_NORMAL_MANIFEST = (
    DATA / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/"
    "pricefm_stage_r93_normal_runtime_manifest.json"
)
QUANTILE_RUNNER = Path(__file__).with_name("295_run_pricefm_stage_r93_quantile_ladder.R")
GRID_BLOCK = "pricefm_desn_experiment_grid"
RHS_METHOD = "normal_rhs_ns"
AL_METHOD = "qdesn_al_rhs_ns_r93_region_frozen"
EXAL_METHOD = "qdesn_exal_rhs_ns_r93_region_frozen_structured"
PAPER_QUANTILES = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]
WARM_ORDER = [0.50, 0.45, 0.25, 0.10, 0.55, 0.75, 0.90]
WARM_PARENT_BY_TAU = {
    "0.50": "outer_normal_rhs",
    "0.45": "0.50",
    "0.25": "0.45",
    "0.10": "0.25",
    "0.55": "0.50",
    "0.75": "0.55",
    "0.90": "0.75",
}
COARSE_TAU0 = [1e-4, 1e-3, 1e-2]
REFINEMENT_TAU0 = [5e-5, 5e-4, 2e-3]
EXPECTED_R82_VERSION = "1.1.1.9004"
EXPECTED_R82_REPAIR = (
    "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-"
    "plus-structured-plugin-init"
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "action",
        choices=("close-rhs", "close-refinement", "close-outer", "close-quantile"),
    )
    p.add_argument("--rhs-prep-dir", type=Path, default=RHS_PREP)
    p.add_argument("--rhs-generated-root", type=Path, default=RHS_GENERATED)
    p.add_argument("--output-root", type=Path, default=R93_OUTPUT)
    p.add_argument("--refinement-generated-root", type=Path, default=REFINE_GENERATED)
    p.add_argument("--refinement-run-root", type=Path, default=REFINE_RUNS)
    p.add_argument("--outer-generated-root", type=Path, default=OUTER_GENERATED)
    p.add_argument("--outer-run-root", type=Path, default=OUTER_RUNS)
    p.add_argument("--outer-processed-root", type=Path, default=OUTER_PROCESSED)
    p.add_argument("--quantile-run-root", type=Path, default=QUANTILE_RUNS)
    p.add_argument("--r82-library", type=Path, default=R82_LIBRARY)
    p.add_argument("--r82-manifest", type=Path, default=R82_MANIFEST)
    p.add_argument("--r82-source", type=Path, default=R82_SOURCE)
    p.add_argument("--r93-normal-manifest", type=Path, default=R93_NORMAL_MANIFEST)
    p.add_argument("--quantile-runner", type=Path, default=QUANTILE_RUNNER)
    p.add_argument("--target-region", default="SE_2")
    p.add_argument("--inner-folds", default="101,102,103")
    p.add_argument("--expected-coarse-arms", type=int, default=90)
    p.add_argument("--refinement-relative-gap", type=float, default=0.01)
    p.add_argument(
        "--accept-coarse-winner-without-refinement",
        type=parse_bool,
        default=False,
    )
    p.add_argument("--expected-coarse-winner-id", default="")
    p.add_argument("--expected-coarse-winner-tau0", type=float)
    p.add_argument("--force", type=parse_bool, default=False)
    p.add_argument("--allow-fixture-counts", action="store_true")
    return p


def load_yaml(path: Path) -> dict[str, Any]:
    payload = yaml.safe_load(path.read_text())
    if not isinstance(payload, dict):
        raise ValueError(f"YAML is not a mapping: {path}")
    return payload


def write_yaml(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(payload, sort_keys=False))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def write_csv(path: Path, frame: pd.DataFrame) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)


def boolish(value: Any) -> bool:
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def parse_ints(value: str) -> list[int]:
    values = [int(item.strip()) for item in value.split(",") if item.strip()]
    if not values or len(values) != len(set(values)):
        raise ValueError("folds must be a nonempty unique integer list")
    return values


def resolve_path(value: Any) -> Path:
    path = Path(str(value))
    return path if path.is_absolute() else repo_path(path)


def source_row(path: Path, role: str) -> dict[str, Any]:
    path = path.resolve()
    return {
        "role": role,
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def prepare_output(path: Path, force: bool) -> Path:
    path = path.resolve()
    if path.exists() and any(path.iterdir()):
        if not force:
            raise FileExistsError(f"output is nonempty: {path}")
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)
    return path


def tau_token(value: float) -> str:
    return f"{value:.0e}".replace("-", "m").replace("+", "p")


def complexity(row: pd.Series) -> tuple[int, int]:
    units = row.get("units", "[]")
    if isinstance(units, str):
        units = json.loads(units)
    return int(row.get("n_state_features", row.get("feature_dim", 0))), sum(map(int, units))


def read_grid_manifest(generated_root: Path) -> pd.DataFrame:
    path = generated_root.resolve() / "manifest.csv"
    if not path.is_file() or path.stat().st_size == 0:
        raise FileNotFoundError(path)
    manifest = pd.read_csv(path)
    if not {"id", "run_dir"}.issubset(manifest):
        raise RuntimeError(f"malformed generated manifest: {path}")
    if manifest.id.astype(str).duplicated().any():
        raise RuntimeError(f"duplicate generated IDs: {path}")
    return manifest


def collect_normal_results(
    arms: pd.DataFrame,
    generated_root: Path,
    folds: list[int],
    target_region: str,
) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    manifest = read_grid_manifest(generated_root)
    arm_ids = arms.experiment_id.astype(str)
    manifest_ids = manifest.id.astype(str)
    if arm_ids.duplicated().any() or set(arm_ids) != set(manifest_ids):
        raise RuntimeError("normal-arm and generated manifests do not match exactly")
    indexed = manifest.assign(id=manifest_ids).set_index("id")
    rows: list[dict[str, Any]] = []
    sources: list[dict[str, Any]] = []
    for arm in arms.itertuples(index=False):
        experiment_id = str(arm.experiment_id)
        run_dir = resolve_path(indexed.loc[experiment_id].run_dir)
        for fold in folds:
            model = run_dir / "cells" / f"region={target_region}" / f"fold={fold}" / "model"
            metric_path = model / "metric_summary.csv"
            method_path = model / "model_method_summary.csv"
            if not metric_path.is_file() or not method_path.is_file():
                raise RuntimeError(f"incomplete normal-RHS result: {model}")
            metrics = pd.read_csv(metric_path)
            methods = pd.read_csv(method_path)
            if metrics.split.astype(str).str.lower().eq("test").any():
                raise RuntimeError(f"test metrics are forbidden in R93 selection: {metric_path}")
            selected = metrics[
                metrics.method_id.astype(str).eq(RHS_METHOD)
                & metrics.split.astype(str).eq("val")
                & metrics.unit.astype(str).eq("original")
            ]
            method = methods[methods.method_id.astype(str).eq(RHS_METHOD)]
            if len(selected) != 1 or len(method) != 1:
                raise RuntimeError(f"expected one normal-RHS validation row: {model}")
            aql = float(pd.to_numeric(selected.iloc[0].AQL, errors="coerce"))
            n_features = int(pd.to_numeric(method.iloc[0].n_features, errors="coerce"))
            if not math.isfinite(aql) or aql < 0 or n_features <= 0:
                raise RuntimeError(f"invalid normal-RHS result: {model}")
            rows.append({
                "experiment_id": experiment_id,
                "region": target_region,
                "inner_fold": int(fold),
                "validation_AQL_original": aql,
                "converged": boolish(method.iloc[0].converged),
                "n_features": n_features,
                "metric_path": str(metric_path),
                "method_summary_path": str(method_path),
            })
            sources.extend([
                source_row(metric_path, "normal_rhs_validation_metric"),
                source_row(method_path, "normal_rhs_method_summary"),
            ])
    return pd.DataFrame(rows), sources


def rank_normal_arms(arms: pd.DataFrame, cells: pd.DataFrame) -> pd.DataFrame:
    aggregate = cells.groupby("experiment_id", as_index=False).agg(
        median_validation_AQL=("validation_AQL_original", "median"),
        max_validation_AQL=("validation_AQL_original", "max"),
        mean_validation_AQL=("validation_AQL_original", "mean"),
        n_inner_folds=("inner_fold", "nunique"),
        n_state_features=("n_features", "max"),
        all_converged=("converged", "all"),
    )
    wide = cells.pivot(
        index="experiment_id", columns="inner_fold", values="validation_AQL_original"
    ).rename(columns=lambda fold: f"fold_{int(fold)}_validation_AQL")
    ranked = aggregate.merge(wide.reset_index(), on="experiment_id", validate="one_to_one")
    ranked = ranked.merge(arms, on="experiment_id", validate="one_to_one")
    ranked["sum_units"] = ranked.apply(lambda row: complexity(row)[1], axis=1)
    ranked["selection_eligible"] = ranked.all_converged.map(bool)
    ranked = ranked.sort_values(
        ["selection_eligible", "median_validation_AQL", "max_validation_AQL",
         "n_state_features", "sum_units", "experiment_id"],
        ascending=[False, True, True, True, True, True],
        kind="stable",
    ).reset_index(drop=True)
    ranked.insert(0, "rhs_rank", range(1, len(ranked) + 1))
    ranked["test_metrics_loaded_or_used"] = False
    return ranked


def refinement_decision(
    ranked: pd.DataFrame,
    threshold: float,
    coarse_tau0: list[float] = COARSE_TAU0,
) -> dict[str, Any]:
    eligible = ranked[ranked.selection_eligible.map(bool)].copy()
    if eligible.empty:
        raise RuntimeError("no converged normal-RHS arm is selection-eligible")
    winner = eligible.iloc[0]
    structural_geometry = ranked[
        ranked.parent_ridge_candidate_id.astype(str).eq(
            str(winner.parent_ridge_candidate_id)
        )
    ].sort_values("median_validation_AQL")
    observed_tau0 = pd.to_numeric(
        structural_geometry.tau0, errors="coerce"
    ).tolist()
    structurally_complete = (
        len(structural_geometry) == len(coarse_tau0)
        and all(math.isfinite(value) for value in observed_tau0)
        and all(
            sum(math.isclose(value, expected) for value in observed_tau0) == 1
            for expected in coarse_tau0
        )
    )
    if not structurally_complete:
        raise RuntimeError("winning geometry lacks the complete coarse tau0 surface")

    geometry = structural_geometry[
        structural_geometry.selection_eligible.map(bool)
    ].sort_values("median_validation_AQL")
    best = float(winner.median_validation_AQL)
    if len(geometry) >= 2:
        second = float(geometry.iloc[1].median_validation_AQL)
        relative_gap = (second - best) / max(abs(best), np.finfo(float).eps)
        near_tie = relative_gap <= threshold
    else:
        relative_gap = None
        near_tie = False
    winning_tau0 = float(winner.tau0)
    boundary = math.isclose(winning_tau0, min(coarse_tau0)) or math.isclose(
        winning_tau0, max(coarse_tau0)
    )
    numerically_incomplete = len(geometry) != len(coarse_tau0)
    triggers = []
    if boundary:
        triggers.append("coarse_tau0_boundary")
    if near_tie:
        triggers.append("coarse_tau0_near_tie")
    if numerically_incomplete:
        triggers.append("coarse_tau0_numerically_incomplete")
    required = bool(triggers)
    return {
        "refinement_required": required,
        "reason": triggers[0] if triggers else "interior_tau0_with_clear_margin",
        "refinement_triggers": triggers,
        "winning_experiment_id": str(winner.experiment_id),
        "parent_ridge_candidate_id": str(winner.parent_ridge_candidate_id),
        "winning_tau0": winning_tau0,
        "winning_median_validation_AQL": best,
        "same_geometry_second_best_relative_gap": relative_gap,
        "relative_gap_threshold": float(threshold),
        "coarse_surface_structurally_complete": structurally_complete,
        "coarse_surface_arm_count": int(len(structural_geometry)),
        "coarse_surface_eligible_arm_count": int(len(geometry)),
        "coarse_surface_ineligible_experiment_ids": structural_geometry.loc[
            ~structural_geometry.selection_eligible.map(bool), "experiment_id"
        ].astype(str).tolist(),
    }


def apply_coarse_winner_acceptance(
    decision: dict[str, Any],
    *,
    accepted: bool,
    expected_winner_id: str,
    expected_winner_tau0: float | None,
) -> dict[str, Any]:
    if not accepted:
        return decision
    if not expected_winner_id or expected_winner_tau0 is None:
        raise RuntimeError(
            "coarse-winner acceptance requires the expected winner ID and tau0"
        )
    if str(decision["winning_experiment_id"]) != str(expected_winner_id):
        raise RuntimeError("coarse-winner acceptance ID does not match the selected arm")
    if not math.isclose(
        float(decision["winning_tau0"]),
        float(expected_winner_tau0),
        rel_tol=1e-12,
        abs_tol=0.0,
    ):
        raise RuntimeError("coarse-winner acceptance tau0 does not match the selected arm")

    amended = copy.deepcopy(decision)
    amended.update({
        "pre_registered_refinement_required": bool(
            decision["refinement_required"]
        ),
        "pre_registered_refinement_reason": str(decision["reason"]),
        "refinement_required": False,
        "reason": "explicit_coarse_winner_acceptance_without_refinement",
        "protocol_amendment": True,
        "protocol_amendment_scope": "normal_rhs_tau0_refinement_only",
        "protocol_amendment_rationale": (
            "accept the fully converged coarse validation winner; the planned "
            "refinement does not bracket the upper-boundary winner and would "
            "add normal-likelihood tuning before the target quantile fit"
        ),
        "selection_changed_by_amendment": False,
        "test_evidence_consulted": False,
    })
    return amended


def experiment_map(grid_payload: dict[str, Any]) -> dict[str, dict[str, Any]]:
    grid = grid_payload[GRID_BLOCK]
    return {str(item["id"]): item for item in grid["experiments"]}


def copy_base_configs(
    source_grid: dict[str, Any], output: Path, prefix: str
) -> tuple[Path, Path, dict[str, Any], dict[str, Any]]:
    block = source_grid[GRID_BLOCK]
    data = load_yaml(resolve_path(block["base"]["data_config"]))
    full = load_yaml(resolve_path(block["base"]["full_config"]))
    data_path = output / "configs/base" / f"{prefix}_data.yaml"
    full_path = output / "configs/base" / f"{prefix}_full.yaml"
    return data_path, full_path, data, full


def build_refinement_grid(
    coarse_grid: dict[str, Any], winner: pd.Series, output: Path,
    generated_root: Path, run_root: Path,
) -> tuple[Path, Path, pd.DataFrame]:
    source = experiment_map(coarse_grid)[str(winner.experiment_id)]
    data_path, full_path, data, full = copy_base_configs(
        coarse_grid, output, "pricefm_stage_r93_rhs_refinement"
    )
    full["pricefm_desn_full"]["data_config"] = str(data_path)
    write_yaml(data_path, data)
    write_yaml(full_path, full)
    experiments = []
    rows = []
    for tau0 in REFINEMENT_TAU0:
        item = copy.deepcopy(source)
        fingerprint = hashlib.sha256(
            f"{winner.parent_ridge_candidate_id}|rhs_refinement|{tau0:.17g}".encode()
        ).hexdigest()
        region_token = str(winner.region).lower().replace("_", "")
        experiment_id = f"r93_{region_token}_rhs_refine_t{tau_token(tau0)}_{fingerprint[:10]}"
        item.update({
            "id": experiment_id,
            "stage": "pricefm_stage_r93_normal_rhs_tau0_refinement",
            "tau0": float(tau0),
            "stage_r93_rhs_tau0_phase": "conditional_refinement",
            "stage_r93_semantic_fingerprint": fingerprint,
            "selection_is_validation_only": True,
            "test_metrics_role": "not_loaded_not_predicted_not_selected",
        })
        experiments.append(item)
        rows.append({
            "experiment_id": experiment_id,
            "parent_ridge_candidate_id": str(winner.parent_ridge_candidate_id),
            "ridge_rank": int(winner.ridge_rank),
            "region": str(winner.region),
            "feature_policy": str(winner.feature_policy),
            "lag_window": int(winner.lag_window),
            "depth": int(winner.depth),
            "units": winner.units,
            "feature_dim": int(winner.feature_dim),
            "alpha": float(winner.alpha),
            "rho": float(winner.rho),
            "input_scale": float(winner.input_scale),
            "state_output": str(winner.state_output),
            "seed": int(winner.seed),
            "tau0": float(tau0),
            "selection_split": "inner_validation",
            "selection_metric": "AQL",
            "test_access_authorized": False,
            "launch_authorized": False,
            "semantic_fingerprint": fingerprint,
        })
    payload = copy.deepcopy(coarse_grid)
    grid = payload[GRID_BLOCK]
    grid.update({
        "grid_id": "pricefm_stage_r93_region_frozen_rhs_refinement_20260906",
        "purpose": "Conditional tau0 refinement for the single coarse-RHS winning geometry.",
        "base": {
            "data_config": str(data_path), "full_config": str(full_path),
            "generated_root": str(generated_root.resolve()),
            "run_root": str(run_root.resolve()),
        },
        "experiments": experiments,
        "experiment_blocks": [],
        "launch": {"prepared_not_authorized": {
            "experiment_jobs": 3, "cell_jobs": 1, "build_windows": True,
            "resume": True, "force": False, "dry_run": False,
            "authorized": False,
            "note": "Overnight controller authorization is required.",
        }},
    })
    grid_path = output / "pricefm_stage_r93_rhs_refinement_grid.yaml"
    manifest_path = output / "pricefm_stage_r93_rhs_refinement_manifest.csv"
    write_yaml(grid_path, payload)
    write_csv(manifest_path, pd.DataFrame(rows))
    return grid_path, manifest_path, pd.DataFrame(rows)


def selected_contract(row: pd.Series, source_grid: Path) -> dict[str, Any]:
    fields = [
        "experiment_id", "parent_ridge_candidate_id", "ridge_rank", "region",
        "feature_policy", "lag_window", "depth", "units", "feature_dim", "alpha",
        "rho", "input_scale", "state_output", "seed", "tau0",
        "median_validation_AQL", "max_validation_AQL", "all_converged",
    ]
    result = {name: row[name] for name in fields if name in row.index}
    for name, value in list(result.items()):
        if isinstance(value, np.generic):
            result[name] = value.item()
    result.update({
        "source_grid": str(source_grid.resolve()),
        "source_grid_sha256": sha256_file(source_grid.resolve()),
        "selection_split": "three_inner_validation_windows_inside_original_fold1_train",
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    })
    return result


def build_outer_grid(
    source_grid_path: Path, contract: dict[str, Any], output: Path,
    generated_root: Path, run_root: Path, processed_root: Path,
) -> tuple[Path, Path, Path]:
    source_grid = load_yaml(source_grid_path)
    source = experiment_map(source_grid)[str(contract["experiment_id"])]
    data_path, full_path, data, full = copy_base_configs(
        source_grid, output, "pricefm_stage_r93_outer_normal"
    )
    data_block = data["pricefm"]
    data_block["processed_dir"] = str(processed_root.resolve())
    data_block["splits"] = [{
        "fold": 1,
        "train": ["2022-01-01", "2024-09-01"],
        "val": ["2024-09-01", "2025-01-01"],
    }]
    data_block["pilot"] = {"enabled": True, "region": contract["region"], "fold": 1}
    full_block = full["pricefm_desn_full"]
    full_block["data_config"] = str(data_path)
    full_block["scope"].update({
        "regions": [contract["region"]], "folds": [1],
        "splits": ["train", "val"], "quantiles": PAPER_QUANTILES,
    })
    full_block["normal"].update({
        "enabled": True, "prior_types": ["rhs_ns"],
        "predictive_quantile_mode": "analytic_normal",
    })
    full_block["qdesn_vb"]["enabled"] = False
    full_block["warm_start"] = {"enabled": False}
    write_yaml(data_path, data)
    write_yaml(full_path, full)
    item = copy.deepcopy(source)
    fingerprint = hashlib.sha256(
        f"{contract['parent_ridge_candidate_id']}|outer_normal|{contract['tau0']:.17g}".encode()
    ).hexdigest()
    item.update({
        "id": f"r93_se2_outer_normal_{fingerprint[:10]}",
        "stage": "pricefm_stage_r93_outer_normal_rhs_confirmation",
        "folds": [1], "quantiles": PAPER_QUANTILES,
        "tau0": float(contract["tau0"]),
        "stage_r93_rhs_tau0_phase": "frozen_after_inner_validation",
        "stage_r93_semantic_fingerprint": fingerprint,
        "selection_is_validation_only": True,
        "selected_on_split": "inner_validation",
        "test_metrics_role": "not_loaded_not_predicted",
    })
    payload = copy.deepcopy(source_grid)
    grid = payload[GRID_BLOCK]
    grid.update({
        "grid_id": "pricefm_stage_r93_region_frozen_outer_normal_20260906",
        "purpose": "Confirm the one inner-validation-selected normal-RHS specification on reserved Fold-1 validation.",
        "base": {
            "data_config": str(data_path), "full_config": str(full_path),
            "generated_root": str(generated_root.resolve()),
            "run_root": str(run_root.resolve()),
        },
        "scope": {
            **grid["scope"], "regions": [contract["region"]], "folds": [1],
            "splits": ["train", "val"], "quantiles": PAPER_QUANTILES,
            "ranking_split": "reserved_original_fold1_validation",
            "audit_split": "test_absent",
        },
        "experiments": [item], "experiment_blocks": [],
        "launch": {"prepared_not_authorized": {
            "experiment_jobs": 1, "cell_jobs": 1, "build_windows": True,
            "resume": True, "force": False, "dry_run": False,
            "authorized": False,
            "note": "Overnight controller authorization is required.",
        }},
    })
    grid_path = output / "pricefm_stage_r93_outer_normal_grid.yaml"
    contract_path = output / "pricefm_stage_r93_frozen_normal_contract.json"
    write_yaml(grid_path, payload)
    write_json(contract_path, contract)
    return grid_path, contract_path, data_path


def validate_runtime(args: argparse.Namespace) -> dict[str, Any]:
    manifest = json.loads(args.r82_manifest.read_text())
    if (
        manifest.get("status") != "installed_structured_initialization_repair_runtime"
        or manifest.get("version") != EXPECTED_R82_VERSION
        or manifest.get("repair") != EXPECTED_R82_REPAIR
        or manifest.get("base_tarball_sha256")
        != "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
    ):
        raise RuntimeError("R82 structured exAL runtime provenance changed")
    if not (args.r82_library / "exdqlm").is_dir() or not args.r82_source.is_dir():
        raise FileNotFoundError("R82 installed library or source tree is absent")
    if not args.quantile_runner.is_file():
        raise FileNotFoundError(args.quantile_runner)
    return manifest


def locate_single_model(generated_root: Path, region: str, fold: int) -> tuple[str, Path]:
    manifest = read_grid_manifest(generated_root)
    if len(manifest) != 1:
        raise RuntimeError("outer confirmation must contain exactly one experiment")
    row = manifest.iloc[0]
    model = resolve_path(row.run_dir) / "cells" / f"region={region}" / f"fold={fold}" / "model"
    return str(row.id), model


def build_quantile_task(
    args: argparse.Namespace, output: Path, contract: dict[str, Any],
    outer_experiment_id: str, outer_model: Path,
) -> tuple[Path, Path, dict[str, Any]]:
    outer_manifest = read_grid_manifest(args.outer_generated_root)
    full_config = resolve_path(outer_manifest.iloc[0].full_config)
    full = load_yaml(full_config)["pricefm_desn_full"]
    data_config = resolve_path(full["data_config"])
    if any("test" in split for split in load_yaml(data_config)["pricefm"]["splits"]):
        raise RuntimeError("outer data config contains a forbidden test interval")
    quantile_root = args.quantile_run_root.resolve() / "r93_se2_region_frozen"
    adapter_dir = quantile_root / "adapter"
    model_dir = quantile_root / "model"
    cell = {
        "pricefm_desn_smoke": {
            "data_config": str(data_config),
            "package_path": str(args.r82_source.resolve()),
            "region": str(contract["region"]), "fold": 1,
            "splits": ["train", "val"], "horizons": list(range(1, 97)),
            "quantiles": PAPER_QUANTILES,
            "feature_policy": full["scope"]["feature_policy"],
            "adapter": {**full["adapter"], "output_dir": str(adapter_dir)},
            "run": {**full["run"], "output_dir": str(model_dir)},
            "rhs_ns": {
                "tau0": float(contract["tau0"]), "init_tau": 1.0,
                "shrink_intercept": False,
                "freeze_tau_iters": 50, "freeze_tau_warmup_iters": 50,
            },
            "normal": {"enabled": False},
            "qdesn_vb": {
                "enabled": True, "likelihoods": ["al", "exal"],
                "max_iter": 150, "tol": 1e-4, "n_samp": 200,
                "n_samp_xi": 200, "prior_sigma": {"a": 1.0, "b": 1.0},
                "prior_gamma": {"mu0": 0.0, "s20": 10.0},
                "public_api": "exalStaticLDVB",
                "structured_sigmagam": {
                    "factorization": "structured", "structured_grid_size": 151,
                    "structured_span_sd": 6.0, "freeze_warmup_iters": 0,
                    "force_after_warmup": True, "postwarmup_damping": 0.2,
                    "postwarmup_damping_iters": 30, "min_postwarmup_updates": 35,
                },
            },
            "warm_start": {
                "enabled": True, "fallback_to_cold": False,
                "tau_order": WARM_ORDER,
                "chain": "outer_normal_rhs_to_al_adjacent_then_exal_same_tau",
            },
            "exact_equivalence": {"enabled": False},
            "training": {
                "train_origin_limit": 3000, "train_origin_selection": "tail",
                "selection_split": "reserved_original_fold1_validation",
                "test_metrics_role": "not_loaded_not_predicted_not_selected",
            },
            "artifact_hygiene": full.get("artifact_hygiene", {}),
        },
        "pricefm_stage_r93": {
            "stage": "R93", "role": "region_frozen_seven_quantile_validation",
            "outer_experiment_id": outer_experiment_id,
            "test_access_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "joint_model_authorized": False,
            "mcmc_authorized": False,
        },
    }
    config_path = output / "pricefm_stage_r93_quantile_cell_config.yaml"
    write_yaml(config_path, cell)
    beta_path = outer_model / "normal_beta_mean.csv"
    parameter_path = outer_model / "model_parameter_summary.csv"
    metric_path = outer_model / "metric_summary.csv"
    for path in (beta_path, parameter_path, metric_path):
        if not path.is_file() or path.stat().st_size == 0:
            raise FileNotFoundError(path)
    semantic = {
        "region": contract["region"], "fold": 1, "quantiles": PAPER_QUANTILES,
        "warm_order": WARM_ORDER, "tau0": float(contract["tau0"]),
        "feature_policy": contract["feature_policy"],
        "lag_window": int(contract["lag_window"]), "depth": int(contract["depth"]),
        "units": contract["units"], "alpha": float(contract["alpha"]),
        "rho": float(contract["rho"]), "input_scale": float(contract["input_scale"]),
        "state_output": contract["state_output"], "seed": int(contract["seed"]),
        "r82_manifest_sha256": sha256_file(args.r82_manifest),
        "normal_beta_sha256": sha256_file(beta_path),
        "normal_parameter_sha256": sha256_file(parameter_path),
        "config_sha256": sha256_file(config_path),
        "data_config_sha256": sha256_file(data_config),
        "warm_parent_by_tau": WARM_PARENT_BY_TAU,
    }
    semantic_hash = hashlib.sha256(
        json.dumps(semantic, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    adapter_scripts = [
        repo_path("application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R").resolve(),
        repo_path("application/scripts/pricefm/pricefm_stage_r72_repair_adapter.R").resolve(),
        repo_path("application/scripts/pricefm/pricefm_stage_r75_large_n_gig_adapter.R").resolve(),
    ]
    task = {
        "stage": "R93", "task_id": "r93_se2_region_frozen_quantile_validation",
        "semantic_contract": semantic, "semantic_contract_sha256": semantic_hash,
        "config": str(config_path), "config_sha256": sha256_file(config_path),
        "data_config": str(data_config), "data_config_sha256": sha256_file(data_config),
        "adapter_dir": str(adapter_dir), "output_dir": str(model_dir),
        "normal_beta_path": str(beta_path), "normal_beta_sha256": sha256_file(beta_path),
        "normal_parameter_path": str(parameter_path),
        "normal_parameter_sha256": sha256_file(parameter_path),
        "r_library": str(args.r82_library.resolve()),
        "runtime_manifest": str(args.r82_manifest.resolve()),
        "runtime_manifest_sha256": sha256_file(args.r82_manifest),
        "runner_script": str(args.quantile_runner.resolve()),
        "runner_script_sha256": sha256_file(args.quantile_runner),
        "adapter_scripts": [
            {"path": str(path), "sha256": sha256_file(path)}
            for path in adapter_scripts
        ],
        "code_root": str(repo_path(".").resolve()),
        "method_ids": {"al": AL_METHOD, "exal": EXAL_METHOD},
        "quantiles": PAPER_QUANTILES, "warm_order": WARM_ORDER,
        "warm_parent_by_tau": WARM_PARENT_BY_TAU,
        "rhs": cell["pricefm_desn_smoke"]["rhs_ns"],
        "qdesn_vb": cell["pricefm_desn_smoke"]["qdesn_vb"],
        "selection_split": "val", "test_access_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "joint_model_authorized": False, "mcmc_authorized": False,
        "launch_authorized": False,
    }
    task_path = output / "pricefm_stage_r93_quantile_task.json"
    write_json(task_path, task)
    return config_path, task_path, task


def action_close_rhs(args: argparse.Namespace) -> dict[str, Any]:
    if not args.allow_fixture_counts and (
        args.expected_coarse_arms != 90 or parse_ints(args.inner_folds) != [101, 102, 103]
    ):
        raise RuntimeError("production R93 requires 90 coarse arms on inner folds 101-103")
    stage = prepare_output(args.output_root / "rhs_coarse_closeout", bool(args.force))
    arms_path = args.rhs_prep_dir / "pricefm_stage_r93_rhs_coarse_launch_manifest.csv"
    grid_path = args.rhs_prep_dir / "pricefm_stage_r93_rhs_grid.yaml"
    arms = pd.read_csv(arms_path)
    if len(arms) != args.expected_coarse_arms:
        raise RuntimeError(f"expected {args.expected_coarse_arms} coarse RHS arms, found {len(arms)}")
    if arms.test_access_authorized.map(boolish).any():
        raise RuntimeError("coarse RHS manifest authorizes test access")
    folds = parse_ints(args.inner_folds)
    cells, sources = collect_normal_results(arms, args.rhs_generated_root, folds, args.target_region)
    ranked = rank_normal_arms(arms, cells)
    if len(cells) != len(arms) * len(folds):
        raise RuntimeError("coarse RHS cell surface is incomplete")
    decision = refinement_decision(ranked, args.refinement_relative_gap)
    decision = apply_coarse_winner_acceptance(
        decision,
        accepted=bool(args.accept_coarse_winner_without_refinement),
        expected_winner_id=str(args.expected_coarse_winner_id),
        expected_winner_tau0=args.expected_coarse_winner_tau0,
    )
    winner = ranked[ranked.selection_eligible.map(bool)].iloc[0]
    write_csv(stage / "pricefm_stage_r93_rhs_coarse_cell_metrics.csv", cells)
    write_csv(stage / "pricefm_stage_r93_rhs_coarse_ranking.csv", ranked)
    write_json(stage / "pricefm_stage_r93_rhs_refinement_decision.json", decision)
    next_grid = None
    final_contract = None
    if decision["refinement_required"]:
        next_grid, next_manifest, _ = build_refinement_grid(
            load_yaml(grid_path), winner, stage,
            args.refinement_generated_root, args.refinement_run_root,
        )
        next_action = "launch_refinement"
    else:
        final_contract = selected_contract(winner, grid_path)
        final_contract.update({
            "tau0_selection_resolution": str(decision["reason"]),
            "coarse_winner_acceptance_without_refinement": bool(
                args.accept_coarse_winner_without_refinement
            ),
            "pre_registered_refinement_required": bool(
                decision.get("pre_registered_refinement_required", False)
            ),
            "selection_changed_by_protocol_amendment": bool(
                decision.get("selection_changed_by_amendment", False)
            ),
        })
        next_grid, contract_path, _ = build_outer_grid(
            grid_path, final_contract, stage, args.outer_generated_root,
            args.outer_run_root, args.outer_processed_root,
        )
        next_manifest = contract_path
        next_action = "launch_outer_normal_confirmation"
    fixed_sources = [source_row(arms_path, "coarse_rhs_arm_manifest"), source_row(grid_path, "coarse_rhs_grid")]
    write_csv(stage / "source_manifest.csv", pd.DataFrame(fixed_sources + sources).drop_duplicates("path"))
    summary = {
        "stage": "pricefm_stage_r93_rhs_coarse_closeout",
        "status": "completed",
        "coarse_arms": len(ranked), "coarse_cells": len(cells),
        "eligible_arms": int(ranked.selection_eligible.map(bool).sum()),
        "winner": str(winner.experiment_id),
        "winner_tau0": float(winner.tau0),
        "winner_median_validation_AQL": float(winner.median_validation_AQL),
        "refinement": decision,
        "coarse_winner_acceptance_without_refinement": bool(
            args.accept_coarse_winner_without_refinement
        ),
        "next_action": next_action, "next_grid": str(next_grid),
        "next_manifest": str(next_manifest),
        "test_opened": False, "test_access_authorized": False,
        "registry_mutated": False, "article_mutated": False,
        "joint_or_mcmc_authorized": False,
    }
    write_json(stage / "summary.json", summary)
    return summary


def action_close_refinement(args: argparse.Namespace) -> dict[str, Any]:
    coarse_dir = args.output_root / "rhs_coarse_closeout"
    coarse_summary = json.loads((coarse_dir / "summary.json").read_text())
    if not coarse_summary["refinement"]["refinement_required"]:
        raise RuntimeError("coarse closeout did not request refinement")
    stage = prepare_output(args.output_root / "rhs_refinement_closeout", bool(args.force))
    refine_arms_path = coarse_dir / "pricefm_stage_r93_rhs_refinement_manifest.csv"
    refine_grid_path = coarse_dir / "pricefm_stage_r93_rhs_refinement_grid.yaml"
    refine_arms = pd.read_csv(refine_arms_path)
    folds = parse_ints(args.inner_folds)
    cells, sources = collect_normal_results(
        refine_arms, args.refinement_generated_root, folds, args.target_region
    )
    refined = rank_normal_arms(refine_arms, cells)
    coarse = pd.read_csv(coarse_dir / "pricefm_stage_r93_rhs_coarse_ranking.csv")
    parent = str(coarse_summary["refinement"]["parent_ridge_candidate_id"])
    coarse_same = coarse[coarse.parent_ridge_candidate_id.astype(str).eq(parent)].copy()
    combined = pd.concat([coarse_same, refined], ignore_index=True, sort=False)
    combined = combined[combined.selection_eligible.map(bool)].sort_values(
        ["median_validation_AQL", "max_validation_AQL", "n_state_features",
         "sum_units", "experiment_id"], kind="stable"
    ).reset_index(drop=True)
    if combined.empty or len(refined) != len(REFINEMENT_TAU0):
        raise RuntimeError("refinement surface is incomplete or has no eligible arm")
    combined.insert(0, "final_rhs_rank", range(1, len(combined) + 1))
    winner = combined.iloc[0]
    source_grid_path = refine_grid_path if str(winner.experiment_id) in set(refine_arms.experiment_id) else args.rhs_prep_dir / "pricefm_stage_r93_rhs_grid.yaml"
    contract = selected_contract(winner, source_grid_path)
    outer_grid, contract_path, _ = build_outer_grid(
        source_grid_path, contract, stage, args.outer_generated_root,
        args.outer_run_root, args.outer_processed_root,
    )
    write_csv(stage / "pricefm_stage_r93_rhs_refinement_cell_metrics.csv", cells)
    write_csv(stage / "pricefm_stage_r93_rhs_refinement_ranking.csv", refined)
    write_csv(stage / "pricefm_stage_r93_rhs_final_tau0_ranking.csv", combined)
    write_csv(stage / "source_manifest.csv", pd.DataFrame([
        source_row(refine_arms_path, "refinement_arm_manifest"),
        source_row(refine_grid_path, "refinement_grid"),
        *sources,
    ]).drop_duplicates("path"))
    summary = {
        "stage": "pricefm_stage_r93_rhs_refinement_closeout", "status": "completed",
        "refinement_arms": len(refined), "refinement_cells": len(cells),
        "winner": str(winner.experiment_id), "winner_tau0": float(winner.tau0),
        "winner_median_validation_AQL": float(winner.median_validation_AQL),
        "next_action": "launch_outer_normal_confirmation",
        "next_grid": str(outer_grid), "next_manifest": str(contract_path),
        "test_opened": False, "test_access_authorized": False,
        "registry_mutated": False, "article_mutated": False,
        "joint_or_mcmc_authorized": False,
    }
    write_json(stage / "summary.json", summary)
    return summary


def find_final_rhs_summary(output_root: Path) -> tuple[dict[str, Any], Path]:
    refine = output_root / "rhs_refinement_closeout/summary.json"
    coarse = output_root / "rhs_coarse_closeout/summary.json"
    path = refine if refine.is_file() else coarse
    summary = json.loads(path.read_text())
    if summary.get("next_action") != "launch_outer_normal_confirmation":
        raise RuntimeError("RHS closeout has not frozen an outer-confirmation candidate")
    return summary, Path(summary["next_manifest"])


def action_close_outer(args: argparse.Namespace) -> dict[str, Any]:
    validate_runtime(args)
    _, contract_path = find_final_rhs_summary(args.output_root)
    contract = json.loads(contract_path.read_text())
    stage = prepare_output(args.output_root / "outer_normal_closeout", bool(args.force))
    experiment_id, model = locate_single_model(args.outer_generated_root, contract["region"], 1)
    metrics = pd.read_csv(model / "metric_summary.csv")
    methods = pd.read_csv(model / "model_method_summary.csv")
    if metrics.split.astype(str).str.lower().eq("test").any():
        raise RuntimeError("outer normal confirmation contains test metrics")
    row = metrics[
        metrics.method_id.astype(str).eq(RHS_METHOD)
        & metrics.split.astype(str).eq("val")
        & metrics.unit.astype(str).eq("original")
    ]
    method = methods[methods.method_id.astype(str).eq(RHS_METHOD)]
    if len(row) != 1 or len(method) != 1 or not boolish(method.iloc[0].converged):
        raise RuntimeError("outer normal RHS confirmation is incomplete or nonconverged")
    aql = float(row.iloc[0].AQL)
    if not math.isfinite(aql) or aql < 0:
        raise RuntimeError("outer normal RHS AQL is invalid")
    config_path, task_path, task = build_quantile_task(
        args, stage, contract, experiment_id, model
    )
    gates = pd.DataFrame([
        {"gate": "outer_normal_complete_finite_converged", "passed": True, "observed": aql},
        {"gate": "outer_split_is_reserved_validation", "passed": True, "observed": "fold1 val"},
        {"gate": "seven_quantiles_exact", "passed": task["quantiles"] == PAPER_QUANTILES, "observed": json.dumps(task["quantiles"])},
        {"gate": "public_api_only", "passed": task["qdesn_vb"]["public_api"] == "exalStaticLDVB", "observed": task["qdesn_vb"]["public_api"]},
        {"gate": "structured_profile_explicit", "passed": task["qdesn_vb"]["structured_sigmagam"]["min_postwarmup_updates"] == 35, "observed": 35},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": not any(task[name] for name in ("test_access_authorized", "registry_mutation_authorized", "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized")), "observed": "blocked"},
    ])
    if not gates.passed.map(bool).all():
        raise RuntimeError("outer-to-quantile gates failed")
    write_csv(stage / "pricefm_stage_r93_outer_to_quantile_gates.csv", gates)
    write_csv(stage / "source_manifest.csv", pd.DataFrame([
        source_row(contract_path, "frozen_rhs_contract"),
        source_row(model / "metric_summary.csv", "outer_normal_metric"),
        source_row(model / "model_method_summary.csv", "outer_normal_method"),
        source_row(model / "normal_beta_mean.csv", "outer_normal_beta"),
        source_row(model / "model_parameter_summary.csv", "outer_normal_parameter"),
        source_row(args.r82_manifest, "r82_runtime_manifest"),
        source_row(args.quantile_runner, "r93_quantile_runner"),
        source_row(config_path, "quantile_cell_config"),
        source_row(resolve_path(task["data_config"]), "quantile_data_config"),
        source_row(task_path, "quantile_task"),
        *[
            source_row(Path(item["path"]), "quantile_public_api_adapter")
            for item in task["adapter_scripts"]
        ],
    ]))
    summary = {
        "stage": "pricefm_stage_r93_outer_normal_closeout_quantile_prep",
        "status": "completed_quantile_prepared_not_launched",
        "outer_experiment_id": experiment_id, "outer_validation_AQL": aql,
        "quantile_task": str(task_path), "quantile_config": str(config_path),
        "quantile_output_dir": task["output_dir"],
        "next_action": "launch_quantile_validation_ladder",
        "test_opened": False, "test_access_authorized": False,
        "registry_mutated": False, "article_mutated": False,
        "joint_or_mcmc_authorized": False,
    }
    write_json(stage / "summary.json", summary)
    return summary


def action_close_quantile(args: argparse.Namespace) -> dict[str, Any]:
    prep_dir = args.output_root / "outer_normal_closeout"
    prep = json.loads((prep_dir / "summary.json").read_text())
    task = json.loads(Path(prep["quantile_task"]).read_text())
    model = Path(task["output_dir"])
    stage = prepare_output(args.output_root / "quantile_validation_closeout", bool(args.force))
    metrics_path = model / "metric_summary.csv"
    methods_path = model / "model_method_summary.csv"
    run_summary_path = model / "pricefm_stage_r93_quantile_run_summary.json"
    for path in (metrics_path, methods_path, run_summary_path):
        if not path.is_file() or path.stat().st_size == 0:
            raise FileNotFoundError(path)
    metrics = pd.read_csv(metrics_path)
    methods = pd.read_csv(methods_path)
    run_summary = json.loads(run_summary_path.read_text())
    if metrics.split.astype(str).str.lower().eq("test").any() or run_summary.get("test_loaded") is not False:
        raise RuntimeError("quantile validation closeout found forbidden test evidence")
    rows = []
    for family, method_id in (("al", AL_METHOD), ("exal", EXAL_METHOD)):
        metric = metrics[
            metrics.method_id.astype(str).eq(method_id)
            & metrics.split.astype(str).eq("val")
            & metrics.unit.astype(str).eq("original")
        ]
        method = methods[methods.method_id.astype(str).eq(method_id)]
        complete = len(metric) == 1 and method.tau.nunique() == 7
        aql = float(metric.iloc[0].AQL) if len(metric) == 1 else math.nan
        numerically_eligible = bool(
            complete and math.isfinite(aql)
            and (family == "al" or run_summary.get("exal_surface_numerically_eligible") is True)
        )
        rows.append({
            "family": family, "method_id": method_id,
            "validation_AQL_original": aql,
            "quantiles_complete": int(method.tau.nunique()) if "tau" in method else 0,
            "formal_convergence_count": int(method.converged.map(boolish).sum()) if len(method) else 0,
            "numerically_eligible": numerically_eligible,
        })
    comparison = pd.DataFrame(rows)
    eligible = comparison[comparison.numerically_eligible]
    if not comparison.loc[comparison.family.eq("al"), "numerically_eligible"].iloc[0] or eligible.empty:
        raise RuntimeError("the complete finite AL fallback surface is absent")
    winner = eligible.sort_values(["validation_AQL_original", "family"], kind="stable").iloc[0]
    frozen = {
        "stage": "pricefm_stage_r93_region_frozen_quantile_validation_closeout",
        "status": "validation_family_frozen_awaiting_test_audit_authorization",
        "region": task["semantic_contract"]["region"],
        "geometry_and_tau0_contract": task["semantic_contract"],
        "selected_family": str(winner.family),
        "selected_method_id": str(winner.method_id),
        "selected_validation_AQL_original": float(winner.validation_AQL_original),
        "selection_rule": "complete_numerically_eligible_family_minimum_reserved_fold1_validation_AQL",
        "per_quantile_family_mixing": False,
        "test_opened": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
        "next_action": "stop_and_request_explicit_scoring_only_test_audit_authorization",
    }
    write_csv(stage / "pricefm_stage_r93_validation_family_comparison.csv", comparison)
    write_json(stage / "pricefm_stage_r93_frozen_validation_family.json", frozen)
    evidence = [
        source_row(Path(prep["quantile_task"]), "quantile_task"),
        source_row(metrics_path, "quantile_validation_metrics"),
        source_row(methods_path, "quantile_method_summary"),
        source_row(run_summary_path, "quantile_run_summary"),
    ]
    for name in (
        "model_predictions_scaled.csv", "metric_by_horizon.csv",
        "metric_by_horizon_group.csv", "model_parameter_summary.csv",
        "warm_start_diagnostics.csv", "exal_atom_status.csv",
    ):
        path = model / name
        if path.is_file():
            evidence.append(source_row(path, "quantile_validation_evidence"))
    write_csv(stage / "source_manifest.csv", pd.DataFrame(evidence))
    summary = {
        **frozen,
        "family_candidates": len(comparison),
        "eligible_families": int(comparison.numerically_eligible.sum()),
        "output_dir": str(stage),
    }
    write_json(stage / "summary.json", summary)
    report = (
        "# PriceFM Stage-R93 Validation Ladder Closeout\n\n"
        f"The region-frozen specification for `{frozen['region']}` selected "
        f"`{frozen['selected_family']}` on the reserved original Fold-1 validation window "
        f"with AQL {frozen['selected_validation_AQL_original']:.6f}. Test data remained sealed.\n\n"
        "The next admissible operation is a scoring-only all-fold test audit after explicit "
        "authorization. Registry, article, joint, and MCMC work remain blocked.\n"
    )
    (stage / "pricefm_stage_r93_validation_closeout_report.md").write_text(report)
    return summary


def run(args: argparse.Namespace) -> dict[str, Any]:
    actions = {
        "close-rhs": action_close_rhs,
        "close-refinement": action_close_refinement,
        "close-outer": action_close_outer,
        "close-quantile": action_close_quantile,
    }
    return actions[args.action](args)


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
