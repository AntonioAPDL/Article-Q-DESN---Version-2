#!/usr/bin/env python3
"""Audit R92/R97 protocol validity and seal one frozen R97 test authorization."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

import numpy as np
import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_r97_distributed_contract import verify_seal, write_sealed
from pricefm_region_frozen_contract import (
    PAPER_QUANTILES,
    atomic_write_json,
    canonical_sha256,
    file_record,
    git_identity,
    prepare_empty_directory,
    sha256_file,
    verify_file_record,
)


REQUIRED_DESN = (
    "lag_window", "depth", "units", "alpha", "rho", "input_scale",
    "feature_policy", "state_output",
)
BLOCKED = (
    "model_refit_authorized", "selection_change_authorized",
    "registry_mutation_authorized", "article_mutation_authorized",
    "joint_model_authorized", "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--reconciliation-terminal", type=Path, required=True)
    value.add_argument("--campaign-contract", type=Path, required=True)
    value.add_argument("--r92-authority", type=Path, required=True)
    value.add_argument("--region-closeout-root", type=Path, required=True)
    value.add_argument("--se2-comparison", type=Path, required=True)
    value.add_argument("--se2-validation-surface", type=Path, required=True)
    value.add_argument("--code-root", type=Path, required=True)
    value.add_argument("--output-dir", type=Path, required=True)
    value.add_argument("--quarantine-root", type=Path, default=None)
    value.add_argument("--quarantine-existing", action="store_true")
    return value


def verify_campaign(path: Path) -> dict[str, Any]:
    campaign = json.loads(path.read_text())
    unhashed = {key: value for key, value in campaign.items() if key != "campaign_contract_sha256"}
    if canonical_sha256(unhashed) != campaign.get("campaign_contract_sha256"):
        raise RuntimeError("R97 campaign contract hash changed")
    decision = campaign.get("final_decision") or {}
    if (
        campaign.get("stage") != "R97"
        or campaign.get("case_count") != 114
        or len(campaign.get("regions") or []) != 38
        or len(campaign.get("regions_to_fit") or []) != 37
        or campaign.get("reused_region") != "SE_2"
        or decision.get("aggregation") != "unweighted_arithmetic_mean_over_exactly_114_region_fold_cases"
        or decision.get("promotion_gate") != "candidate_mean_AQL_strictly_below_current_R92_mean_AQL"
        or decision.get("per_case_dual_comparator_veto") is not False
    ):
        raise RuntimeError("R97 campaign is not the frozen complete-surface protocol")
    return campaign


def verify_reconciliation(path: Path, campaign: dict[str, Any]) -> dict[str, Any]:
    reconciliation = json.loads(path.read_text())
    verify_seal(reconciliation, "reconciliation_sha256", label="R97 reconciliation")
    expected_false = (
        "test_opened", "test_access_authorized", "registry_mutation_authorized",
        "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
    )
    if (
        reconciliation.get("status")
        != "completed_37_region_validation_reconciliation_test_still_sealed"
        or reconciliation.get("region_count") != 37
        or sorted(reconciliation.get("regions") or []) != sorted(campaign["regions_to_fit"])
        or any(reconciliation.get(name) is not False for name in expected_false)
    ):
        raise RuntimeError("R97 reconciliation is incomplete or its firewall is open")
    verify_file_record(reconciliation["validation_evidence"], label="R97 validation evidence")
    return reconciliation


def verify_se2(comparison_path: Path, surface_path: Path, campaign: dict[str, Any]) -> tuple[pd.DataFrame, dict[str, Any]]:
    if sha256_file(comparison_path) != campaign["se2_reuse"]["sha256"]:
        raise RuntimeError("R96 SE_2 comparison differs from the frozen R97 campaign source")
    comparison = pd.read_csv(comparison_path)
    required = {
        "region", "fold", "selected_family", "selection_is_validation_only",
        "model_refitted", "selection_changed_after_test", "quantile_rows",
        "full_quantile_confirmation_pass", "full_horizon_confirmation_pass",
        "candidate_test_AQL", "authoritative_qdesn_test_AQL", "cached_pricefm_test_AQL",
    }
    if (
        not required.issubset(comparison.columns)
        or len(comparison) != 3
        or set(comparison.region.astype(str)) != {"SE_2"}
        or sorted(comparison.fold.astype(int)) != [1, 2, 3]
        or set(comparison.selected_family.astype(str)) != {"exal"}
        or not comparison.selection_is_validation_only.astype(bool).all()
        or comparison.model_refitted.astype(bool).any()
        or comparison.selection_changed_after_test.astype(bool).any()
        or not comparison.full_quantile_confirmation_pass.astype(bool).all()
        or not comparison.full_horizon_confirmation_pass.astype(bool).all()
        or not comparison.quantile_rows.astype(int).eq(7).all()
    ):
        raise RuntimeError("R96 SE_2 reuse is not a complete validation-frozen surface")
    surface = json.loads(surface_path.read_text())
    if (
        surface.get("status") != "allfold_validation_surface_frozen_awaiting_test_authorization"
        or surface.get("region") != "SE_2"
        or surface.get("validation_selected_family_from_R94") != "exal"
        or surface.get("test_opened") is not False
        or surface.get("test_access_authorized") is not False
        or surface.get("whole_region_AL_fallback_used") is not False
    ):
        raise RuntimeError("R95 SE_2 validation surface is incompatible with R98")
    spec = surface.get("frozen_desn") or {}
    if any(name not in spec for name in REQUIRED_DESN) or float(surface.get("rhs_tau0")) != float(spec["tau0"]):
        raise RuntimeError("R95 SE_2 does not contain one complete frozen DESN/tau0 specification")
    return comparison, surface


def verify_regions(root: Path, campaign: dict[str, Any]) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    rows: list[dict[str, Any]] = []
    evidence: list[dict[str, Any]] = []
    for region in campaign["regions_to_fit"]:
        closeout = root / region
        summary_path = closeout / "summary.json"
        surface_path = closeout / "pricefm_stage_r97_frozen_region_surface.json"
        summary = json.loads(summary_path.read_text())
        surface = json.loads(surface_path.read_text())
        if (
            summary.get("status") != "completed_region_validation_surface_frozen"
            or summary.get("region") != region
            or surface.get("status") != "region_validation_surface_frozen"
            or surface.get("region") != region
            or surface.get("test_opened") is not False
            or surface.get("test_access_authorized") is not False
            or surface.get("per_fold_or_quantile_family_mixing") is not False
            or surface.get("selected_family") not in {"al", "exal"}
        ):
            raise RuntimeError(f"R97 region is not validation-frozen: {region}")
        spec = surface.get("frozen_desn") or {}
        if any(name not in spec for name in REQUIRED_DESN):
            raise RuntimeError(f"R97 region omits a frozen DESN field: {region}")
        if not np.isfinite(float(surface.get("rhs_tau0"))):
            raise RuntimeError(f"R97 region omits its frozen tau0: {region}")
        selected_path = verify_file_record(surface["selected_atom_manifest"], label=f"R97 {region} selected surface")
        verify_file_record(surface["validation_metrics"], label=f"R97 {region} validation metrics")
        verify_file_record(surface["pipeline_contract"], label=f"R97 {region} pipeline")
        selected = pd.read_csv(selected_path)
        if (
            len(selected) != 21
            or set(selected.region.astype(str)) != {region}
            or sorted(selected.fold.astype(int).unique()) != [1, 2, 3]
            or not np.allclose(sorted(selected.tau.astype(float).unique()), PAPER_QUANTILES)
            or selected.groupby("fold").size().to_dict() != {1: 7, 2: 7, 3: 7}
            or set(selected.selected_family.astype(str)) != {surface["selected_family"]}
        ):
            raise RuntimeError(f"R97 region selected surface is incomplete or mixed: {region}")
        for atom in selected.itertuples(index=False):
            for name in ("beta", "prediction", "terminal", "source_case_config", "feature_manifest", "x_val", "rows_val", "scaler"):
                path = Path(getattr(atom, f"{name}_path"))
                if not path.is_file() or sha256_file(path) != str(getattr(atom, f"{name}_sha256")):
                    raise RuntimeError(f"R97 selected atom evidence changed: {region} {name}")
        rows.append({
            "region": region, "fold_count": 3, "quantile_atoms": 21,
            "selected_family": surface["selected_family"], "rhs_tau0": float(surface["rhs_tau0"]),
            **{name: spec[name] for name in REQUIRED_DESN},
            "one_desn_tau0_per_region": True, "one_family_per_region": True,
            "test_opened_during_selection": False,
        })
        evidence.extend([
            file_record(summary_path, f"{region}_summary"),
            file_record(surface_path, f"{region}_frozen_surface"),
            surface["selected_atom_manifest"], surface["validation_metrics"], surface["pipeline_contract"],
        ])
    frame = pd.DataFrame(rows).sort_values("region")
    if len(frame) != 37:
        raise RuntimeError("R98 requires exactly 37 newly fitted frozen regions")
    return frame, evidence


def r92_protocol_audit(authority: pd.DataFrame) -> pd.DataFrame:
    required = {"region", "fold", "source_class", "qdesn_method_id", "experiment_id", "feature_policy"}
    if not required.issubset(authority.columns) or len(authority) != 114 or authority.duplicated(["region", "fold"]).any():
        raise RuntimeError("R92 authority is not an exact 114-case surface")
    rows = []
    optional = [name for name in ("input_scope", "spatial_information_set", "evidence_path") if name in authority]
    for region, frame in authority.groupby(authority.region.astype(str), sort=True):
        row: dict[str, Any] = {
            "region": region, "folds": int(frame.fold.nunique()),
            "source_class_count": int(frame.source_class.nunique()),
            "experiment_id_count": int(frame.experiment_id.nunique()),
            "method_count": int(frame.qdesn_method_id.nunique()),
            "feature_policy_count": int(frame.feature_policy.nunique()),
        }
        for name in optional:
            row[f"{name}_count"] = int(frame[name].astype(str).nunique())
        row["compatible_with_prospective_region_frozen_protocol"] = bool(
            row["folds"] == 3
            and row["source_class_count"] == 1
            and row["experiment_id_count"] == 1
            and row["method_count"] == 1
            and row["feature_policy_count"] == 1
        )
        row["audit_interpretation"] = (
            "structurally_single_region_surface"
            if row["compatible_with_prospective_region_frozen_protocol"]
            else "retrospective_multi_source_or_fold_specific_surface"
        )
        rows.append(row)
    result = pd.DataFrame(rows)
    if len(result) != 38 or not result.folds.eq(3).all():
        raise RuntimeError("R92 protocol audit did not recover 38 complete regions")
    return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    campaign = verify_campaign(args.campaign_contract)
    reconciliation = verify_reconciliation(args.reconciliation_terminal, campaign)
    if sha256_file(args.r92_authority) != campaign["authority_registry"]["sha256"]:
        raise RuntimeError("R92 authority differs from the frozen R97 comparator")
    authority = pd.read_csv(args.r92_authority)
    r92_audit = r92_protocol_audit(authority)
    se2, se2_surface = verify_se2(args.se2_comparison, args.se2_validation_surface, campaign)
    region_specs, region_evidence = verify_regions(args.region_closeout_root, campaign)
    identity = git_identity(args.code_root)
    if (
        not identity.clean
        or identity.head != identity.upstream_head
        or not identity.branch.startswith("work/pricefm-")
    ):
        raise RuntimeError("R98 authorization requires a clean synchronized PriceFM task branch")

    output, quarantined = prepare_empty_directory(
        args.output_dir,
        quarantine_root=args.quarantine_root or args.output_dir.parent / "quarantine",
        reason="replaced_R98_validity_first_prep",
        allow_quarantine=args.quarantine_existing,
    )
    r92_path = output / "pricefm_stage_r98_r92_protocol_audit.csv"
    specs_path = output / "pricefm_stage_r98_frozen_region_specifications.csv"
    r92_audit.to_csv(r92_path, index=False)
    se2_spec = {
        "region": "SE_2", "fold_count": 3, "quantile_atoms": 21,
        "selected_family": "exal", "rhs_tau0": float(se2_surface["rhs_tau0"]),
        **{name: se2_surface["frozen_desn"][name] for name in REQUIRED_DESN},
        "one_desn_tau0_per_region": True, "one_family_per_region": True,
        "test_opened_during_selection": False,
    }
    all_specs = pd.concat([region_specs, pd.DataFrame([se2_spec])], ignore_index=True).sort_values("region")
    if len(all_specs) != 38 or all_specs.region.nunique() != 38:
        raise RuntimeError("R98 does not have one frozen specification for every region")
    all_specs.to_csv(specs_path, index=False)

    policy = {
        "schema_version": 1,
        "stage": "R98",
        "status": "validity_first_authority_transition_frozen_before_test",
        "authority_basis": "prospective_region_frozen_validation_only_protocol",
        "scientific_reason": (
            "R92 remains a valuable historical sensitivity surface, but its retrospective multi-stage, "
            "region-fold-specific construction is not the intended prospective region-frozen protocol."
        ),
        "r92_direct_test_reselection_claimed": False,
        "r92_status_after_transition": "deprecated_historical_sensitivity_only",
        "r97_preregistered_performance_gate_preserved": campaign["final_decision"],
        "r98_authority_rule": "replace_all_114_R92_rows_with_the_complete_R97_surface_regardless_of_test_performance",
        "performance_is_reported_not_used_to_choose_authority": True,
        "case_specific_R92_fallback_authorized": False,
        "test_driven_case_mixing_authorized": False,
        "selection_change_after_test_authorized": False,
        "poor_test_score_authorizes_retuning": False,
        "scoring_failure_repair_scope": "mechanical_scoring_or_evidence_repair_only_no_scientific_change",
        "external_comparator": "cached_PriceFM",
        "final_aggregation": "unweighted_arithmetic_mean_over_exactly_114_region_fold_cases",
        "regions": 38, "folds": 3, "cases": 114, "paper_quantiles": list(PAPER_QUANTILES),
        "joint_model_authorized": False, "mcmc_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
    }
    policy_path = output / "pricefm_stage_r98_validity_first_transition_policy.json"
    atomic_write_json(policy_path, policy)

    scoring_code = [
        file_record(SCRIPT_DIR / name, f"R98_{Path(name).stem}")
        for name in (
            "319_orchestrate_pricefm_stage_r97_global_campaign.py",
            "320_score_pricefm_stage_r97_frozen_case.py",
            "321_prepare_pricefm_stage_r97_global_scoring.py",
            "322_closeout_pricefm_stage_r97_global_surface.py",
            "326_finalize_pricefm_stage_r97_distributed_campaign.py",
            "329_prepare_pricefm_stage_r98_validity_first_authority.py",
            "330_closeout_pricefm_stage_r98_validity_first_authority.py",
        )
    ]
    authorization = {
        "schema_version": 1, "stage": "R98",
        "status": "authorized_once_for_frozen_R97_test_scoring",
        "campaign_root": str(Path(campaign["campaign_root"]).resolve()),
        "reconciliation_terminal": file_record(args.reconciliation_terminal, "R97_validation_reconciliation"),
        "campaign_contract": file_record(args.campaign_contract, "R97_campaign_contract"),
        "r92_authority": file_record(args.r92_authority, "R92_deprecated_comparator"),
        "se2_comparison": file_record(args.se2_comparison, "R96_SE_2_frozen_test_surface"),
        "se2_validation_surface": file_record(args.se2_validation_surface, "R95_SE_2_frozen_validation_surface"),
        "region_specifications": file_record(specs_path, "38_region_frozen_specifications"),
        "authority_transition_policy": policy,
        "authority_transition_policy_file": file_record(policy_path, "R98_transition_policy"),
        "code_git_identity": identity.to_dict(), "scoring_code": scoring_code,
        "test_access_authorized": True, "test_opened": False,
        **{name: False for name in BLOCKED},
    }
    authorization_path = output / "pricefm_stage_r98_scoring_authorization.json"
    write_sealed(authorization_path, authorization, "scoring_authorization_sha256")

    sources = [
        file_record(args.reconciliation_terminal, "R97_validation_reconciliation"),
        file_record(args.campaign_contract, "R97_campaign_contract"),
        file_record(args.r92_authority, "R92_deprecated_comparator"),
        file_record(args.se2_comparison, "R96_SE_2_frozen_test_surface"),
        file_record(args.se2_validation_surface, "R95_SE_2_frozen_validation_surface"),
        *region_evidence, *scoring_code,
    ]
    source_path = output / "source_manifest.csv"
    pd.DataFrame(sources).drop_duplicates(["path", "sha256"]).to_csv(source_path, index=False)
    gates = pd.DataFrame([
        {"gate": "R97_validation_reconciled", "passed": True, "detail": "37/37 newly fitted regions"},
        {"gate": "SE_2_compatible_reuse", "passed": True, "detail": "3/3 frozen scoring-only folds"},
        {"gate": "complete_region_frozen_surface", "passed": True, "detail": "38 regions, 114 cases"},
        {"gate": "R97_original_gate_preserved", "passed": True, "detail": campaign["final_decision"]["promotion_gate"]},
        {"gate": "R98_no_case_fallback", "passed": True, "detail": "all 114 R97 rows replace R92 together"},
        {"gate": "code_clean_and_synchronized", "passed": True, "detail": identity.head},
    ])
    gates_path = output / "pricefm_stage_r98_authorization_gates.csv"
    gates.to_csv(gates_path, index=False)
    report_path = output / "pricefm_stage_r98_validity_first_authority_plan.md"
    incompatible = int((~r92_audit.compatible_with_prospective_region_frozen_protocol).sum())
    report_path.write_text(
        "# PriceFM Stage-R98 validity-first authority transition\n\n"
        "## Decision\n\n"
        "R98 will score the already frozen R97 surface once and will replace the complete R92 "
        "114-case surface as the protocol-valid authority regardless of whether its mean test AQL is better or worse. "
        "The original R97 performance gate remains recorded and will be reported independently.\n\n"
        "## Evidence\n\n"
        f"- R97 validation reconciliation: 37/37 newly fitted regions, with test still sealed.\n"
        f"- Compatible frozen SE_2 reuse: 3/3 folds.\n"
        f"- Complete target surface: 38 regions, 3 folds, 7 quantiles, 114 cases.\n"
        f"- R92 regions not structurally equivalent to one prospective region-frozen source: {incompatible}/38.\n"
        "- This is a protocol-compatibility judgment, not a claim that R92's final closeout directly reselected on test.\n\n"
        "## Firewalls\n\n"
        "No fitting, reselection, per-case fallback, registry mutation, article mutation, joint model, or MCMC is authorized. "
        "A scoring failure may only trigger a mechanical scorer or evidence repair.\n"
    )
    summary = {
        "schema_version": 1, "stage": "R98",
        "status": "completed_validity_first_scoring_authorization_test_not_opened",
        "regions": 38, "new_regions": 37, "reused_regions": 1, "cases": 114,
        "r92_protocol_incompatible_regions": incompatible,
        "r97_original_performance_gate_preserved": True,
        "r98_complete_surface_replacement_required": True,
        "test_opened": False, "test_access_authorized": True,
        "model_refit_authorized": False, "selection_change_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "joint_model_authorized": False, "mcmc_authorized": False,
        "scoring_authorization": str(authorization_path),
        "scoring_authorization_sha256": sha256_file(authorization_path),
        "quarantined_previous_output": str(quarantined) if quarantined else None,
        "outputs": {
            "r92_protocol_audit": str(r92_path), "region_specifications": str(specs_path),
            "transition_policy": str(policy_path), "authorization_gates": str(gates_path),
            "source_manifest": str(source_path), "report": str(report_path),
        },
    }
    atomic_write_json(output / "summary.json", summary)
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
