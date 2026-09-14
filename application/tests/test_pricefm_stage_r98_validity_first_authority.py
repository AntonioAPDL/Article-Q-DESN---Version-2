"""Focused tests for the PriceFM R98 validity-first authority transition."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
from types import SimpleNamespace

import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from pricefm_r97_distributed_contract import sealed_payload, write_sealed  # noqa: E402
from pricefm_region_frozen_contract import (  # noqa: E402
    PAPER_QUANTILES,
    atomic_write_json,
    canonical_sha256,
    file_record,
    sha256_file,
)


def load(filename: str):
    spec = importlib.util.spec_from_file_location(Path(filename).stem, SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


PREP = load("329_prepare_pricefm_stage_r98_validity_first_authority.py")
CLOSE = load("330_closeout_pricefm_stage_r98_validity_first_authority.py")


class FakeGit:
    branch = "work/pricefm-fixture"
    head = "a" * 40
    upstream = "origin/work/pricefm-fixture"
    upstream_head = head
    clean = True

    def to_dict(self):
        return {
            "worktree": "/fixture", "branch": self.branch, "head": self.head,
            "upstream": self.upstream, "upstream_head": self.upstream_head,
            "clean": self.clean,
        }


def regions() -> list[str]:
    return ["SE_2", *[f"R{index:02d}" for index in range(1, 38)]]


def make_prep_fixture(tmp_path: Path, monkeypatch) -> SimpleNamespace:
    names = regions()
    r92 = tmp_path / "r92.csv"
    pd.DataFrame([
        {
            "region": region, "fold": fold, "source_class": f"source_{fold}",
            "qdesn_method_id": "old_qdesn", "experiment_id": f"old_{region}_f{fold}",
            "feature_policy": "target_only", "qdesn_AQL": 5.0, "pricefm_AQL": 6.0,
        }
        for region in names for fold in (1, 2, 3)
    ]).to_csv(r92, index=False)
    se2 = tmp_path / "se2.csv"
    pd.DataFrame([
        {
            "region": "SE_2", "fold": fold, "selected_family": "exal",
            "selection_is_validation_only": True, "model_refitted": False,
            "selection_changed_after_test": False, "quantile_rows": 7,
            "full_quantile_confirmation_pass": True, "full_horizon_confirmation_pass": True,
            "candidate_test_AQL": 8.0, "authoritative_qdesn_test_AQL": 5.0,
            "cached_pricefm_test_AQL": 6.0,
        }
        for fold in (1, 2, 3)
    ]).to_csv(se2, index=False)
    se2_surface = tmp_path / "r95_surface.json"
    atomic_write_json(se2_surface, {
        "status": "allfold_validation_surface_frozen_awaiting_test_authorization",
        "region": "SE_2", "validation_selected_family_from_R94": "exal",
        "test_opened": False, "test_access_authorized": False,
        "whole_region_AL_fallback_used": False, "rhs_tau0": 0.01,
        "frozen_desn": {
            "lag_window": 96, "depth": 2, "units": "[64,64]", "alpha": 0.5,
            "rho": 0.95, "input_scale": 0.2, "feature_policy": "target_only",
            "state_output": "final_layer", "tau0": 0.01,
        },
    })
    closeouts = tmp_path / "closeouts"
    for region in names[1:]:
        root = closeouts / region
        root.mkdir(parents=True)
        evidence_files = {}
        for role in ("beta", "prediction", "terminal", "source_case_config", "feature_manifest", "x_val", "rows_val", "scaler"):
            path = root / f"{role}.txt"
            path.write_text(f"{region}-{role}\n")
            evidence_files[role] = path
        selected_path = root / "pricefm_stage_r97_selected_atom_manifest.csv"
        selected_rows = []
        for fold in (1, 2, 3):
            for tau in PAPER_QUANTILES:
                row = {"region": region, "fold": fold, "tau": tau, "selected_family": "al"}
                for role, path in evidence_files.items():
                    row[f"{role}_path"] = str(path)
                    row[f"{role}_sha256"] = sha256_file(path)
                selected_rows.append(row)
        pd.DataFrame(selected_rows).to_csv(selected_path, index=False)
        metrics_path = root / "pricefm_stage_r97_family_fold_validation_metrics.csv"
        pd.DataFrame([{"fold": fold, "family": "al", "AQL": 1.0} for fold in (1, 2, 3)]).to_csv(metrics_path, index=False)
        pipeline_path = root / "pipeline.json"
        atomic_write_json(pipeline_path, {"stage": "R97"})
        surface_path = root / "pricefm_stage_r97_frozen_region_surface.json"
        atomic_write_json(surface_path, {
            "status": "region_validation_surface_frozen", "region": region,
            "selected_family": "al", "test_opened": False, "test_access_authorized": False,
            "per_fold_or_quantile_family_mixing": False, "rhs_tau0": 0.01,
            "frozen_desn": {
                "lag_window": 96, "depth": 2, "units": "[64,64]", "alpha": 0.5,
                "rho": 0.95, "input_scale": 0.2, "feature_policy": "target_only",
                "state_output": "final_layer",
            },
            "selected_atom_manifest": file_record(selected_path, "selected"),
            "validation_metrics": file_record(metrics_path, "metrics"),
            "pipeline_contract": file_record(pipeline_path, "pipeline"),
        })
        atomic_write_json(root / "summary.json", {
            "status": "completed_region_validation_surface_frozen", "region": region,
        })
    campaign = {
        "schema_version": 1, "stage": "R97", "status": "campaign_frozen_not_launched",
        "case_count": 114, "regions": names, "regions_to_fit": names[1:],
        "reused_region": "SE_2", "campaign_root": str(tmp_path / "campaign"),
        "authority_registry": file_record(r92, "R92"),
        "se2_reuse": file_record(se2, "SE2"),
        "final_decision": {
            "aggregation": "unweighted_arithmetic_mean_over_exactly_114_region_fold_cases",
            "promotion_gate": "candidate_mean_AQL_strictly_below_current_R92_mean_AQL",
            "per_case_dual_comparator_veto": False,
        },
    }
    campaign["campaign_contract_sha256"] = canonical_sha256(campaign)
    campaign_path = tmp_path / "campaign.json"
    atomic_write_json(campaign_path, campaign)
    validation_evidence = tmp_path / "validation.csv"
    validation_evidence.write_text("region\nR01\n")
    reconciliation = sealed_payload({
        "status": "completed_37_region_validation_reconciliation_test_still_sealed",
        "region_count": 37, "regions": names[1:],
        "validation_evidence": file_record(validation_evidence, "validation"),
        "test_opened": False, "test_access_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "joint_model_authorized": False, "mcmc_authorized": False,
    }, "reconciliation_sha256")
    reconciliation_path = tmp_path / "reconciliation.json"
    atomic_write_json(reconciliation_path, reconciliation)
    monkeypatch.setattr(PREP, "git_identity", lambda _: FakeGit())
    return SimpleNamespace(
        reconciliation_terminal=reconciliation_path, campaign_contract=campaign_path,
        r92_authority=r92, region_closeout_root=closeouts, se2_comparison=se2,
        se2_validation_surface=se2_surface, code_root=ROOT, output_dir=tmp_path / "output",
        quarantine_root=None, quarantine_existing=False,
    )


def test_r98_prep_seals_complete_validity_first_transition(tmp_path: Path, monkeypatch) -> None:
    args = make_prep_fixture(tmp_path, monkeypatch)
    summary = PREP.run(args)
    assert summary["status"] == "completed_validity_first_scoring_authorization_test_not_opened"
    assert summary["r98_complete_surface_replacement_required"] is True
    assert summary["r92_protocol_incompatible_regions"] == 38
    authorization = json.loads(Path(summary["scoring_authorization"]).read_text())
    assert authorization["test_access_authorized"] is True
    assert authorization["test_opened"] is False
    assert all(authorization[name] is False for name in PREP.BLOCKED)
    assert authorization["authority_transition_policy"]["case_specific_R92_fallback_authorized"] is False
    assert len(pd.read_csv(args.output_dir / "pricefm_stage_r98_frozen_region_specifications.csv")) == 38


def test_r98_prep_rejects_mixed_region_family(tmp_path: Path, monkeypatch) -> None:
    args = make_prep_fixture(tmp_path, monkeypatch)
    selected = args.region_closeout_root / "R01/pricefm_stage_r97_selected_atom_manifest.csv"
    frame = pd.read_csv(selected)
    frame.loc[0, "selected_family"] = "exal"
    frame.to_csv(selected, index=False)
    surface_path = args.region_closeout_root / "R01/pricefm_stage_r97_frozen_region_surface.json"
    surface = json.loads(surface_path.read_text())
    surface["selected_atom_manifest"] = file_record(selected, "selected")
    atomic_write_json(surface_path, surface)
    with pytest.raises(RuntimeError, match="incomplete or mixed"):
        PREP.run(args)


def make_closeout_authorization(tmp_path: Path, r92: Path, se2: Path, se2_surface: Path) -> Path:
    records = {}
    for name in ("reconciliation_terminal", "campaign_contract", "region_specifications"):
        path = tmp_path / f"{name}.txt"
        path.write_text(name)
        records[name] = file_record(path, name)
    policy = {
        "r98_authority_rule": "replace_all_114_R92_rows_with_the_complete_R97_surface_regardless_of_test_performance",
        "case_specific_R92_fallback_authorized": False,
        "performance_is_reported_not_used_to_choose_authority": True,
        "authority_basis": "prospective_region_frozen_validation_only_protocol",
    }
    policy_path = tmp_path / "policy.json"
    atomic_write_json(policy_path, policy)
    authorization = {
        "stage": "R98", "status": "authorized_once_for_frozen_R97_test_scoring",
        "test_access_authorized": True, "test_opened": False,
        **{name: False for name in CLOSE.BLOCKED},
        **records, "r92_authority": file_record(r92, "r92"),
        "se2_comparison": file_record(se2, "se2"),
        "se2_validation_surface": file_record(se2_surface, "se2_surface"),
        "authority_transition_policy": policy,
        "authority_transition_policy_file": file_record(policy_path, "policy"),
        "scoring_code": [],
    }
    path = tmp_path / "authorization.json"
    write_sealed(path, authorization, "scoring_authorization_sha256")
    return path


def test_r98_closeout_replaces_every_row_even_when_candidate_is_worse(tmp_path: Path, monkeypatch) -> None:
    names = regions()
    r92 = tmp_path / "r92.csv"
    pd.DataFrame([
        {
            "region": region, "fold": fold, "qdesn_method_id": "old",
            "qdesn_AQL": 5.0, "source_class": "historical",
            "experiment_id": f"old_{region}_{fold}", "feature_policy": "target_only",
        }
        for region in names for fold in (1, 2, 3)
    ]).to_csv(r92, index=False)
    se2 = tmp_path / "se2.csv"
    pd.DataFrame([
        {
            "fold": fold, "candidate_test_AQL": 8.0, "candidate_test_MAE": 9.0,
            "candidate_test_RMSE": 10.0, "adjacent_crossing_rate": 0.01,
        }
        for fold in (1, 2, 3)
    ]).to_csv(se2, index=False)
    se2_surface = tmp_path / "se2_surface.json"
    atomic_write_json(se2_surface, {"fixture": True})
    authorization_path = make_closeout_authorization(tmp_path, r92, se2, se2_surface)
    terminal_path = tmp_path / "global_terminal.json"
    write_sealed(terminal_path, {
        "status": "completed_global_scoring_closeout", "cases": 114,
        "model_refit_during_test_scoring": False,
        "selection_changed_during_test_scoring": False,
        "scoring_authorization": file_record(authorization_path, "authorization"),
        "global_closeout": {"candidate_mean_AQL": 8.0},
    }, "global_scoring_terminal_sha256")
    closeout = tmp_path / "r97_closeout"
    closeout.mkdir()
    selected_family = ["exal" if region == "SE_2" else "al" for region in names for _ in (1, 2, 3)]
    surface = pd.DataFrame([
        {
            "region": region, "fold": fold, "selected_family": family,
            "AQL": 8.0, "AQCR": 0.01, "MAE": 9.0, "RMSE": 10.0,
            "current_authoritative_qdesn_AQL": 5.0, "cached_pricefm_AQL": 6.0,
        }
        for (region, fold), family in zip(
            [(region, fold) for region in names for fold in (1, 2, 3)], selected_family
        )
    ])
    surface.to_csv(closeout / "pricefm_stage_r97_complete_surface.csv", index=False)
    pd.DataFrame([{"region": "fixture"}]).to_csv(closeout / "pricefm_stage_r97_region_diagnostics.csv", index=False)
    pd.DataFrame([{"surface": "fixture"}]).to_csv(closeout / "pricefm_stage_r97_global_mean_decision.csv", index=False)
    pd.DataFrame([{"path": "fixture"}]).to_csv(closeout / "source_manifest.csv", index=False)
    atomic_write_json(closeout / "summary.json", {
        "status": "completed_global_surface_closeout", "stage": "R97",
        "cases": 114, "regions": 38, "folds": 3,
        "per_case_dual_comparator_veto_used": False,
        "test_driven_case_mixing_used": False,
        "candidate_mean_AQL": 8.0,
        "complete_surface_promotion_gate_passed": False,
    })
    specifications = pd.DataFrame([
        {
            "region": region, "selected_family": "exal" if region == "SE_2" else "al",
            "rhs_tau0": 0.01, "lag_window": 96, "depth": 2, "units": "[64,64]",
            "alpha": 0.5, "rho": 0.95, "input_scale": 0.2,
            "feature_policy": "target_only", "state_output": "final_layer",
            "selection_source_stage": "fixture", "selected_atom_manifest_path": "fixture",
            "selected_atom_manifest_sha256": "a" * 64,
        }
        for region in names
    ])
    validation = pd.DataFrame([
        {
            "region": region, "fold": fold, "selected_validation_AQL": 4.0,
            "selected_validation_AQCR": 0.0, "selected_validation_MAE": 5.0,
            "selected_validation_RMSE": 6.0,
        }
        for region in names for fold in (1, 2, 3)
    ])
    score_evidence = pd.DataFrame([
        {"region": region, "fold": fold, "test_evidence_path": "fixture", "test_evidence_sha256": "b" * 64}
        for region in names for fold in (1, 2, 3)
    ])
    monkeypatch.setattr(CLOSE, "specification_and_validation_rows", lambda *_: (specifications, validation, []))
    monkeypatch.setattr(CLOSE, "scoring_evidence", lambda *_: (score_evidence, []))
    monkeypatch.setattr(CLOSE, "write_region_figure", lambda png, pdf, _frame: (png.write_bytes(b"png"), pdf.write_bytes(b"pdf")))
    args = SimpleNamespace(
        scoring_authorization=authorization_path, global_scoring_terminal=terminal_path,
        r97_closeout_dir=closeout, scoring_manifest=tmp_path / "unused.csv",
        r92_authority=r92, region_closeout_root=tmp_path,
        se2_comparison=se2, se2_validation_surface=se2_surface,
        output_dir=tmp_path / "output", quarantine_root=None, quarantine_existing=False,
    )
    summary = CLOSE.run(args)
    registry = pd.read_csv(args.output_dir / "pricefm_stage_r98_authoritative_registry.csv")
    assert summary["status"] == "completed_validity_first_authority_package_ready_for_coordinator"
    assert summary["R98_rows_selected_as_authority"] == 114
    assert summary["R92_rows_retained_as_fallback"] == 0
    assert summary["R97_preregistered_performance_gate_passed"] is False
    assert registry.qdesn_AQL.eq(8.0).all()
    assert registry.deprecated_R92_AQL.eq(5.0).all()
    assert not registry.R92_case_fallback_used.astype(bool).any()


def test_distributed_finalizer_requires_r98_authorization() -> None:
    source = (SCRIPTS / "326_finalize_pricefm_stage_r97_distributed_campaign.py").read_text()
    assert 'score.add_argument("--scoring-authorization", type=Path, required=True)' in source
    assert "authorized_once_for_frozen_R97_test_scoring" in source
    assert "already has a terminal and cannot be reopened" in source
