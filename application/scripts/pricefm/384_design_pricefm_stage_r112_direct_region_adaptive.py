#!/usr/bin/env python3
"""Design the read-only R112 direct region-adaptive PriceFM campaign."""

from __future__ import annotations

import argparse
import ast
import csv
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import tempfile
from typing import Any

import pandas as pd


STAGE = "R112"
TAG = "pricefm_stage_r112_direct_region_adaptive_design_20260922"
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
OUTPUT = DATA / "authoritative" / TAG
R98 = DATA / "authoritative/pricefm_stage_r98_validity_first_authority_closeout_20260913"
R97 = DATA / "campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908"
R100_PREP = DATA / "launch_prep/pricefm_stage_r100_targeted_normal_recovery_20260913"
R100 = DATA / "campaigns/pricefm_stage_r100_targeted_normal_recovery_20260913"
R111C = DATA / "authoritative/pricefm_stage_r111c_bg_residual_decomposition_20260922"
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
FOLDS = (1, 2, 3)
RIDGE_CANDIDATES = 240
RIDGE_TOP_K = 30
RHS_TAU_MULTIPLIERS = (0.25, 1.0, 4.0)
INNER_FOLDS = 3
SPEC_COLUMNS = (
    "selected_family", "rhs_tau0", "lag_window", "depth", "units", "alpha",
    "rho", "input_scale", "feature_policy", "state_output",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True, default=str) + "\n")


def artifact(role: str, path: Path, **extra: Any) -> dict[str, Any]:
    path = path.resolve()
    if not path.is_file():
        raise FileNotFoundError(path)
    return {
        "role": role,
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
        **extra,
    }


def as_bool(series: pd.Series) -> pd.Series:
    return series.map(lambda value: str(value).strip().lower() == "true")


def units_tuple(value: Any) -> tuple[int, ...]:
    if isinstance(value, (list, tuple)):
        parsed = value
    else:
        parsed = ast.literal_eval(str(value))
    return tuple(int(item) for item in parsed)


def same_number(left: pd.Series, right: float) -> pd.Series:
    return pd.to_numeric(left).round(12).eq(round(float(right), 12))


def validate_r98() -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    summary_path = R98 / "summary.json"
    registry_path = R98 / "pricefm_stage_r98_authoritative_registry.csv"
    summary = json.loads(summary_path.read_text())
    if (
        summary.get("stage") != "R98"
        or summary.get("status") != "completed_validity_first_authority_package_ready_for_coordinator"
        or summary.get("R98_rows_selected_as_authority") != 114
        or summary.get("selection_changes_after_test") != 0
        or summary.get("test_driven_case_mixing_used") is not False
        or summary.get("model_refits_during_scoring") != 0
        or summary.get("registry_mutated") is not False
        or summary.get("article_mutated") is not False
    ):
        raise RuntimeError("R112 R98 authority contract changed")
    registry = pd.read_csv(registry_path, low_memory=False)
    if (
        len(registry) != 114
        or registry.region.nunique() != 38
        or set(registry.fold.astype(int)) != set(FOLDS)
        or as_bool(registry.test_driven_case_mixing_used).any()
        or as_bool(registry.R92_case_fallback_used).any()
        or not as_bool(registry.selection_is_validation_only).all()
        or not as_bool(registry.same_desn_tau0_all_folds_within_region).all()
        or not as_bool(registry.same_likelihood_family_all_folds_within_region).all()
    ):
        raise RuntimeError("R112 R98 registry violates the complete-surface contract")
    for _, rows in registry.groupby("region"):
        if len(rows) != 3 or any(rows[column].nunique(dropna=False) != 1 for column in SPEC_COLUMNS):
            raise RuntimeError(f"R112 R98 region contract changed: {rows.iloc[0].region}")
    evidence = [artifact("r98_summary", summary_path), artifact("r98_registry", registry_path)]
    selected = registry[["region", "selected_atom_manifest_path", "selected_atom_manifest_sha256"]].drop_duplicates()
    if len(selected) != 38:
        raise RuntimeError("R112 expected one R98 selected-atom manifest per region")
    for row in selected.itertuples(index=False):
        selected_path = Path(row.selected_atom_manifest_path)
        if not selected_path.is_file() or sha256_file(selected_path) != row.selected_atom_manifest_sha256:
            raise RuntimeError(f"R112 changed R98 selected-atom manifest: {row.region}")
        evidence.append(artifact("r98_selected_atom_manifest", selected_path, region=row.region))
    return registry, evidence


def validate_r100() -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    prep_summary_path = R100_PREP / "summary.json"
    terminal_path = R100 / "campaign_terminal.json"
    winner_path = R100 / "pricefm_stage_r100_frozen_normal_winners.csv"
    prep = json.loads(prep_summary_path.read_text())
    terminal = json.loads(terminal_path.read_text())
    if (
        prep.get("stage") != "R100_launch_prep"
        or prep.get("status") != "completed_launch_ready"
        or prep.get("selection_uses_test") is not False
        or terminal.get("stage") != "R100"
        or terminal.get("status") != "completed_normal_winners_frozen"
        or terminal.get("regions_complete") != 17
        or terminal.get("regions_failed") != []
        or terminal.get("test_opened") is not False
        or terminal.get("quantile_fit_started") is not False
        or terminal.get("registry_mutated") is not False
        or terminal.get("article_mutated") is not False
    ):
        raise RuntimeError("R112 R100 reuse contract changed")
    winners = pd.read_csv(winner_path)
    if len(winners) != 17 or winners.region.nunique() != 17:
        raise RuntimeError("R112 expected 17 unique frozen R100 Normal winners")
    evidence = [
        artifact("r100_prep_summary", prep_summary_path),
        artifact("r100_campaign_terminal", terminal_path),
        artifact("r100_frozen_normal_winners", winner_path),
    ]
    for row in winners.itertuples(index=False):
        contract_path = Path(row.contract)
        contract = json.loads(contract_path.read_text())
        if (
            contract.get("region") != row.region
            or contract.get("status") != "provisional_normal_winner_frozen"
            or contract.get("converged") is not True
            or contract.get("eligible") is not True
            or contract.get("selection_uses_test") is not False
            or contract.get("test_access_authorized") is not False
            or contract.get("test_scoring_authorized") is not False
            or contract.get("quantile_fit_authorized") is not False
        ):
            raise RuntimeError(f"R112 invalid R100 winner contract: {row.region}")
        compact_path = R100 / f"regions/{row.region}/rhs_runs/{row.experiment_id}/r100_compaction_terminal.json"
        compact = json.loads(compact_path.read_text())
        if (
            compact.get("status") != "completed_compacted"
            or compact.get("region") != row.region
            or compact.get("experiment_id") != row.experiment_id
            or compact.get("binary_model_artifacts_retained") is not False
            or compact.get("test_opened") is not False
        ):
            raise RuntimeError(f"R112 invalid R100 compaction contract: {row.region}")
        for retained in compact.get("retained", []):
            retained_path = Path(retained["path"])
            if not retained_path.is_file() or sha256_file(retained_path) != retained["sha256"]:
                raise RuntimeError(f"R112 changed R100 retained artifact: {retained_path}")
        evidence.append(artifact("r100_frozen_normal_contract", contract_path, region=row.region))
        evidence.append(artifact("r100_compaction_terminal", compact_path, region=row.region))
    return winners, evidence


def candidate_manifest(region: str, reusable_regions: set[str]) -> tuple[str, Path]:
    if region in reusable_regions:
        return "R100_expanded_train_only", R100_PREP / f"regions/{region}/ridge_prep/pricefm_stage_r100_ridge_candidate_manifest.csv"
    return "R97_region_frozen_baseline", R97 / f"regions/{region}/ridge_prep/pricefm_stage_r93_ridge_candidate_manifest.csv"


def validate_candidate_bank(region: str, path: Path, authority: pd.Series) -> dict[str, Any]:
    candidates = pd.read_csv(path, low_memory=False)
    if (
        len(candidates) != RIDGE_CANDIDATES
        or set(candidates.region.astype(str)) != {region}
        or not as_bool(candidates.selection_eligible).all()
        or set(candidates.selection_split.astype(str)) != {"fold1_train_internal_temporal_validation"}
        or set(candidates.selection_metric.astype(str)) != {"median_inner_validation_AQL_original"}
        or as_bool(candidates.test_access_authorized).any()
        or set(candidates.state_output.astype(str)) != {"final_layer"}
    ):
        raise RuntimeError(f"R112 candidate firewall failed: {region}")
    target_units = units_tuple(authority.units)
    anchor = (
        candidates.feature_policy.astype(str).eq(str(authority.feature_policy))
        & pd.to_numeric(candidates.lag_window).eq(int(authority.lag_window))
        & pd.to_numeric(candidates.depth).eq(int(authority.depth))
        & candidates.units.map(lambda value: units_tuple(value) == target_units)
        & same_number(candidates.alpha, authority.alpha)
        & same_number(candidates.rho, authority.rho)
        & same_number(candidates.input_scale, authority.input_scale)
        & candidates.state_output.astype(str).eq(str(authority.state_output))
    )
    if not anchor.any():
        raise RuntimeError(f"R112 candidate bank omits R98 geometry: {region}")
    units = sorted({json.dumps(list(units_tuple(value))) for value in candidates.units})
    return {
        "region": region,
        "candidate_count": len(candidates),
        "authority_geometry_present": True,
        "feature_policies": "|".join(sorted(candidates.feature_policy.astype(str).unique())),
        "lag_windows": "|".join(map(str, sorted(pd.to_numeric(candidates.lag_window).unique()))),
        "depths": "|".join(map(str, sorted(pd.to_numeric(candidates.depth).unique()))),
        "unit_geometries": "|".join(units),
        "alphas": "|".join(map(str, sorted(pd.to_numeric(candidates.alpha).unique()))),
        "rhos": "|".join(map(str, sorted(pd.to_numeric(candidates.rho).unique()))),
        "input_scales": "|".join(map(str, sorted(pd.to_numeric(candidates.input_scale).unique()))),
        "selection_split": "fold1_train_internal_temporal_validation",
        "selection_metric": "median_inner_validation_AQL_original",
        "test_access_authorized": False,
        "manifest_path": str(path.resolve()),
        "manifest_sha256": sha256_file(path),
    }


def assigned_hosts(regions: list[str], jerez_count: int) -> dict[str, str]:
    ranked = sorted(regions, key=lambda region: hashlib.sha256(region.encode()).hexdigest())
    return {region: ("jerez" if index < jerez_count else "muscat") for index, region in enumerate(ranked)}


def build_design(registry: pd.DataFrame, winners: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, list[dict[str, Any]]]:
    reusable = set(winners.region.astype(str))
    regions = sorted(registry.region.astype(str).unique())
    pending = [region for region in regions if region not in reusable]
    screen_hosts = assigned_hosts(pending, math.ceil(len(pending) * 2 / 3))
    quantile_hosts = assigned_hosts(regions, math.ceil(len(regions) * 2 / 3))
    winner_index = winners.set_index("region")
    inventory_rows = []
    candidate_rows = []
    execution_rows = []
    evidence = []
    for region in regions:
        rows = registry[registry.region.eq(region)].sort_values("fold")
        authority = rows.iloc[0]
        source_class, manifest_path = candidate_manifest(region, reusable)
        audit = validate_candidate_bank(region, manifest_path, authority)
        audit["candidate_source_class"] = source_class
        candidate_rows.append(audit)
        evidence.append(artifact("regional_candidate_manifest", manifest_path, region=region, source_class=source_class))
        reusable_winner = region in reusable
        winner_contract = str(winner_index.loc[region, "contract"]) if reusable_winner else ""
        inventory_rows.append({
            "region": region,
            "folds": "1|2|3",
            "authority_rows": 3,
            "r98_mean_AQL": float(rows.AQL.mean()),
            "pricefm_mean_AQL": float(rows.cached_pricefm_AQL.mean()),
            "r98_selected_family": str(authority.selected_family),
            "r98_tau0": float(authority.rhs_tau0),
            "r98_lag_window": int(authority.lag_window),
            "r98_depth": int(authority.depth),
            "r98_units": json.dumps(list(units_tuple(authority.units))),
            "r98_alpha": float(authority.alpha),
            "r98_rho": float(authority.rho),
            "r98_input_scale": float(authority.input_scale),
            "r98_feature_policy": str(authority.feature_policy),
            "r98_state_output": str(authority.state_output),
            "expanded_normal_screen_status": "reuse_completed_R100" if reusable_winner else "requires_R112_extension",
            "normal_screen_fit_required": not reusable_winner,
            "normal_winner_specification_reusable": reusable_winner,
            "normal_posterior_object_reusable": False,
            "outer_normal_refit_required": True,
            "frozen_normal_contract": winner_contract,
            "candidate_manifest": str(manifest_path.resolve()),
            "candidate_manifest_sha256": audit["manifest_sha256"],
        })
        execution_rows.append({
            "region": region,
            "normal_screen_host": "reuse" if reusable_winner else screen_hosts[region],
            "quantile_host": quantile_hosts[region],
            "ridge_candidates_to_fit": 0 if reusable_winner else RIDGE_CANDIDATES,
            "ridge_inner_fit_cells": 0 if reusable_winner else RIDGE_CANDIDATES * INNER_FOLDS,
            "rhs_candidates_to_fit_max": 0 if reusable_winner else RIDGE_TOP_K * len(RHS_TAU_MULTIPLIERS),
            "rhs_inner_fit_cells_max": 0 if reusable_winner else RIDGE_TOP_K * len(RHS_TAU_MULTIPLIERS) * INNER_FOLDS,
            "normal_outer_fit_cells": len(FOLDS),
            "quantile_family_selection_fit_cells_max": len(QUANTILES) * 2 * INNER_FOLDS,
            "quantile_outer_fit_cells_max": len(QUANTILES) * len(FOLDS),
            "recursive_forecast_authorized": False,
            "joint_fit_authorized": False,
            "mcmc_authorized": False,
        })
    return (
        pd.DataFrame(inventory_rows).sort_values("region"),
        pd.DataFrame(candidate_rows).sort_values("region"),
        pd.DataFrame(execution_rows).sort_values("region"),
        evidence,
    )


def contracts(execution: pd.DataFrame) -> tuple[dict[str, Any], dict[str, Any], pd.DataFrame, pd.DataFrame]:
    search = {
        "stage": STAGE,
        "status": "design_only_not_launchable",
        "scientific_estimand": "complete_38_region_3_fold_direct_seven_quantile_surface",
        "region_selection_unit": "one_specification_per_region_frozen_across_outer_folds",
        "normal_selection_split": "fold1_training_only_three_embargoed_temporal_pseudo_folds",
        "normal_selection_metric": "median_inner_validation_AQL_original",
        "candidate_count_per_region": RIDGE_CANDIDATES,
        "ridge_top_k_per_region": RIDGE_TOP_K,
        "rhs_tau_multipliers": list(RHS_TAU_MULTIPLIERS),
        "rhs_tau_formula": "r98_tau0 * sqrt(r98_readout_features / candidate_readout_features) * multiplier",
        "r100_completed_winners_reused": 17,
        "r100_reuse_scope": "winner_specification_only_binary_posteriors_were_compacted",
        "r112_extension_regions": 21,
        "test_or_outer_fold_metrics_may_select": False,
        "row_level_fallback_authorized": False,
        "launch_authorized": False,
    }
    quantile = {
        "stage": STAGE,
        "status": "design_only_not_launchable",
        "forecast_operator": "direct_96_horizon_no_recursive_target_lags",
        "quantiles": list(QUANTILES),
        "families": ["AL_RHS_VB", "exAL_RHS_VB_structured_M0"],
        "family_selection_split": "training_only_embargoed_temporal_pseudo_folds",
        "family_selection_metric": "pooled_inner_AQL_with_convergence_eligibility",
        "family_frozen_across_outer_folds": True,
        "same_desn_tau0_all_quantiles": True,
        "normal_rhs_initializes_quantile_vb_only": True,
        "normal_rhs_outer_refit_cells": 114,
        "initialization_changes_prior": False,
        "exact_existing_fit_reuse": "only_if_model_data_prior_and_source_hashes_match",
        "joint_fit_authorized": False,
        "mcmc_authorized": False,
        "test_or_outer_fold_metrics_may_select": False,
        "launch_authorized": False,
    }
    gates = pd.DataFrame([
        ("complete_surface", "candidate_rows == 114", "authority_gate"),
        ("all_regions", "candidate_regions == 38", "authority_gate"),
        ("all_folds", "each_region_has_folds_1_2_3", "authority_gate"),
        ("one_region_specification", "same_DESN_tau0_family_across_folds", "authority_gate"),
        ("selection_firewall", "no_outer_validation_or_test_metric_ranks_candidates", "authority_gate"),
        ("no_case_mixing", "zero_row_level_R98_fallbacks_after_scoring", "authority_gate"),
        ("complete_provenance", "all_source_and_output_hashes_validate", "authority_gate"),
        ("authority_improvement", "candidate_complete_surface_mean_AQL < R98_mean_AQL", "authority_replacement"),
        ("pricefm_superiority", "candidate_complete_surface_mean_AQL < cached_PriceFM_mean_AQL", "article_claim"),
        ("article_registry", "coordinator_approval_after_all_prior_gates", "publication_gate"),
    ], columns=["gate", "rule", "role"])
    stages = pd.DataFrame([
        ("R112", "design", "complete", "read_only_design_and_source_audit"),
        ("R112A", "normal_extension_prep", "blocked", "materialize_21_region_R100_equivalent_manifests"),
        ("R112B", "normal_extension_run", "blocked", "fit_only_21_missing_region_screens"),
        ("R112C", "quantile_family_selection", "blocked", "training_only_AL_exAL_selection_for_38_regions"),
        ("R112D", "direct_quantile_surface", "blocked", "fit_or_exactly_reuse_114_outer_cases"),
        ("R112E", "global_closeout", "blocked", "apply_complete_surface_aggregate_gates"),
        ("integration", "coordinator", "blocked", "registry_article_only_after_R112E"),
    ], columns=["stage", "phase", "status", "purpose"])
    return search, quantile, gates, stages


def report(
    inventory: pd.DataFrame,
    candidates: pd.DataFrame,
    execution: pd.DataFrame,
    gates: pd.DataFrame,
    stages: pd.DataFrame,
) -> str:
    pending = inventory[inventory.normal_screen_fit_required]
    reuse = inventory[~inventory.normal_screen_fit_required]
    totals = execution.select_dtypes(include="number").sum()
    policy_counts = {}
    for value in candidates.feature_policies:
        for policy in value.split("|"):
            policy_counts[policy] = policy_counts.get(policy, 0) + 1
    region_table = inventory[[
        "region", "r98_mean_AQL", "pricefm_mean_AQL", "r98_selected_family",
        "r98_feature_policy", "expanded_normal_screen_status",
    ]]
    lines = [
        "# PriceFM Stage-R112 direct region-adaptive campaign design", "",
        "R112 is a read-only design and provenance audit. It fits nothing, writes no launch",
        "YAML, opens no test split, and changes no registry or article file.", "",
        "## Decision", "",
        "The R101--R111 recursive branch is closed. The next admissible performance study",
        "uses the direct 96-horizon operator and evaluates one complete 38-region surface.",
        "Selections are region-specific but frozen across folds and are made only on temporal",
        "pseudo-folds contained inside fold-1 training.", "",
        "## Reuse result", "",
        f"- completed expanded R100 Normal winners reused: {len(reuse)} regions;",
        f"- missing all-region extension screens: {len(pending)} regions;",
        f"- candidate banks audited: {len(candidates)} x {RIDGE_CANDIDATES} = {len(candidates) * RIDGE_CANDIDATES};",
        f"- new Ridge inner fit cells, maximum: {int(totals.ridge_inner_fit_cells)};",
        f"- new RHS inner fit cells, maximum: {int(totals.rhs_inner_fit_cells_max)};",
        f"- final outer Normal-RHS refits required: {int(totals.normal_outer_fit_cells)};",
        f"- quantile family-selection fit cells, maximum: {int(totals.quantile_family_selection_fit_cells_max)};",
        f"- outer direct quantile fit cells, maximum: {int(totals.quantile_outer_fit_cells_max)}.", "",
        "The 17 R100 searches are not rerun. Their winner specifications are reusable, but",
        "their binary posteriors were compacted, so all 114 outer region-fold Normal-RHS fits",
        "must be refitted to initialize the quantile models. The 21 remaining regions receive",
        "the same expanded search before any final Normal or quantile fit is permitted.", "",
        "## Candidate-space audit", "",
        f"Every regional bank contains the current R98 geometry. Policy coverage by number of",
        f"regional banks is: {json.dumps(policy_counts, sort_keys=True)}.", "",
        "## Region inventory", "", region_table.to_markdown(index=False), "",
        "## Distributed execution", "",
        "Normal extension work is deterministically split 14 regions to Jerez and 7 to Muscat.",
        "The later 38-region quantile phase is split 26 to Jerez and 12 to Muscat. Runtime",
        "preflight must determine actual idle CPUs; this design does not pin stale CPU IDs.",
        "Each fit remains single-threaded and each region stays on one host through dependent",
        "phases to avoid partial cross-host provenance.", "",
        "## Promotion gates", "", gates.to_markdown(index=False), "",
        "Authority replacement and a PriceFM-superiority article claim are separate decisions.",
        "No favorable row may be mixed into R98 after outer scoring.", "",
        "## Stage order", "", stages.to_markdown(index=False), "",
        "Each blocked stage requires its own tested preparation and explicit review. R112 itself",
        "does not authorize R112A or any model process.",
    ]
    return "\n".join(lines) + "\n"


def run(code_root: Path, output: Path, force: bool = False) -> dict[str, Any]:
    code_root = code_root.resolve()
    output = output.resolve()
    summary_path = output / "summary.json"
    if summary_path.is_file() and not force:
        existing = json.loads(summary_path.read_text())
        if existing.get("status") == "completed_direct_region_adaptive_design":
            return existing
    if output.exists() and any(output.iterdir()) and not force:
        raise RuntimeError(f"R112 output exists but is not reusable: {output}")
    registry, evidence = validate_r98()
    winners, r100_evidence = validate_r100()
    evidence.extend(r100_evidence)
    r111c_path = R111C / "summary.json"
    r111c = json.loads(r111c_path.read_text())
    if (
        r111c.get("status") != "completed_bg_residual_decomposition"
        or r111c.get("recommended_action") != "stop_recursive_redesign_retain_R97"
        or r111c.get("unfinished_fit_tasks") != 0
        or r111c.get("test_opened") is not False
    ):
        raise RuntimeError("R112 requires the completed R111C stop decision")
    evidence.append(artifact("r111c_summary", r111c_path))
    inventory, candidates, execution, candidate_evidence = build_design(registry, winners)
    evidence.extend(candidate_evidence)
    search, quantile, gates, stages = contracts(execution)
    if (
        len(inventory) != 38
        or inventory.normal_screen_fit_required.sum() != 21
        or (~inventory.normal_screen_fit_required).sum() != 17
        or len(candidates) != 38
        or not candidates.authority_geometry_present.all()
        or execution.ridge_inner_fit_cells.sum() != 15120
        or execution.rhs_inner_fit_cells_max.sum() != 5670
        or execution.normal_outer_fit_cells.sum() != 114
        or execution.quantile_family_selection_fit_cells_max.sum() != 1596
        or execution.quantile_outer_fit_cells_max.sum() != 798
        or (execution.normal_screen_host == "jerez").sum() != 14
        or (execution.normal_screen_host == "muscat").sum() != 7
        or (execution.quantile_host == "jerez").sum() != 26
        or (execution.quantile_host == "muscat").sum() != 12
    ):
        raise RuntimeError("R112 design cardinality changed")
    script_path = Path(__file__).resolve()
    evidence.append(artifact("executed_source", script_path))
    evidence.append(artifact(
        "r100_candidate_generator_source",
        code_root / "application/scripts/pricefm/332_prepare_pricefm_stage_r100_targeted_normal_screen.py",
    ))
    evidence_frame = pd.DataFrame(evidence).drop_duplicates(["path", "sha256"]).sort_values(["role", "path"])

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        inventory.to_csv(temporary / "pricefm_stage_r112_region_inventory.csv", index=False)
        candidates.to_csv(temporary / "pricefm_stage_r112_candidate_bank_audit.csv", index=False, quoting=csv.QUOTE_MINIMAL)
        execution.to_csv(temporary / "pricefm_stage_r112_execution_partition.csv", index=False)
        gates.to_csv(temporary / "pricefm_stage_r112_promotion_gates.csv", index=False)
        stages.to_csv(temporary / "pricefm_stage_r112_stage_plan.csv", index=False)
        evidence_frame.to_csv(temporary / "source_manifest.csv", index=False, quoting=csv.QUOTE_MINIMAL)
        write_json(temporary / "pricefm_stage_r112_normal_search_contract.json", search)
        write_json(temporary / "pricefm_stage_r112_quantile_contract.json", quantile)
        (temporary / "pricefm_stage_r112_direct_region_adaptive_design.md").write_text(
            report(inventory, candidates, execution, gates, stages)
        )
        outputs = [{
            "path": str((output / path.name).resolve()),
            "bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        } for path in sorted(temporary.iterdir())]
        head = subprocess.check_output(["git", "-C", str(code_root), "rev-parse", "HEAD"], text=True).strip()
        summary = {
            "stage": STAGE,
            "status": "completed_direct_region_adaptive_design",
            "tag": TAG,
            "head": head,
            "regions": 38,
            "folds": 3,
            "complete_surface_cases": 114,
            "r100_normal_winners_reused": 17,
            "r112_normal_extension_regions": 21,
            "new_ridge_inner_fit_cells_max": 15120,
            "new_rhs_inner_fit_cells_max": 5670,
            "normal_outer_refit_cells": 114,
            "quantile_family_selection_fit_cells_max": 1596,
            "quantile_outer_fit_cells_max": 798,
            "forecast_operator": "direct_96_horizon_no_recursive_target_lags",
            "selection_uses_outer_validation": False,
            "selection_uses_test": False,
            "row_level_fallback_authorized": False,
            "model_fit_started": False,
            "launch_started": False,
            "launch_yaml_written": False,
            "joint_fit_authorized": False,
            "mcmc_authorized": False,
            "registry_mutated": False,
            "article_mutated": False,
            "next_stage": "R112A_normal_extension_launch_prep_after_explicit_review",
            "outputs": outputs,
        }
        write_json(temporary / "summary.json", summary)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
        return summary
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--code-root", type=Path, default=Path.cwd())
    parser.add_argument("--output-dir", type=Path, default=OUTPUT)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    print(json.dumps(run(args.code_root, args.output_dir, args.force), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
