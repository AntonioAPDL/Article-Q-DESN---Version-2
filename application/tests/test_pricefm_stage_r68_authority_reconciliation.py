import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/235_audit_pricefm_stage_r68_authority_reconciliation.py"


def load_module():
    sys.path.insert(0, str(SCRIPT.parent))
    spec = importlib.util.spec_from_file_location("pricefm_r68", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload))
    return path


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)
    return path


def fixture_inputs(tmp_path):
    rows = [
        ("AA", 1, "al", 5.0, 5.6, 5.4, "near_loss_le_1pct"),
        ("BB", 1, "exal", 5.1, 5.8, 5.0, "near_loss_le_1pct"),
        ("CC", 1, "exal", 6.2, 5.5, 5.0, "severe_loss_gt_5pct"),
        ("DD", 1, "al", 4.9, 5.2, 4.75, "moderate_loss_1_to_5pct"),
    ]
    r62 = write_csv(tmp_path / "r62.csv", [
        {
            "case_id": f"pricefm_joint_{region.lower()}_f{fold}",
            "region": region,
            "fold": fold,
            "selected_seven_quantile_family": family,
            "selected_method_id": f"qdesn_{family}_rhs_ns_exact_chunked",
            "selected_seven_quantile_validation_AQL": qdesn + 0.5,
            "selected_panel_dir": f"/panel/{region}",
            "selected_base_id": f"base_{region}",
            "scientific_contract_sha256": "a" * 64,
            "feature_semantics_sha256": "b" * 64,
            "selection_split": "val",
            "selection_metric": "AQL",
            "test_opened": False,
        }
        for region, fold, family, qdesn, _cached_pf, _op_pf, _queue in rows
    ])
    queues = write_csv(tmp_path / "queues.csv", [
        {
            "region": region,
            "fold": fold,
            "mechanism_queue": queue,
            "joint_contract_validation_AQL": qdesn + 0.1,
            "delta_joint_minus_independent": 0.1,
        }
        for region, fold, _family, qdesn, _cached_pf, _op_pf, queue in rows
    ])
    cached = write_csv(tmp_path / "cached.csv", [
        {
            "region": region,
            "fold": fold,
            "qdesn_method_id": f"qdesn_{family}_rhs_ns_exact_chunked",
            "qdesn_AQL": qdesn,
            "pricefm_method_id": "pricefm_phase1_pretraining",
            "pricefm_AQL": cached_pf,
            "decision_label": "qdesn_wins" if qdesn < cached_pf else "pricefm_wins",
            "feature_policy": "target_only",
            "input_scope": "local_target_only",
            "spatial_information_set": "local_only_not_pricefm_graph",
            "experiment_id": f"exp_{region}",
            "evidence_path": f"evidence/{region}.csv",
            "evidence_sha256": "c" * 64,
        }
        for region, fold, family, qdesn, cached_pf, _op_pf, _queue in rows
    ])
    op = write_csv(tmp_path / "operational.csv", [
        {
            "surface_id": "op",
            "proposed_comparator_method_id": "pricefm_operational_public_architecture_validation_selected",
            "region": region,
            "fold": fold,
            "candidate_id": "graph_degree_1",
            "phase": "phase2",
            "canonical_degree": 1,
            "validation_AQL": op_pf + 0.2,
            "test_AQL": op_pf,
            "current_qdesn_method_id": f"qdesn_{family}_rhs_ns_exact_chunked",
            "current_qdesn_AQL": qdesn,
            "cached_pricefm_method_id": "pricefm_phase1_pretraining",
            "cached_pricefm_AQL": cached_pf,
            "comparison_outcome": "operational_below_both" if op_pf < min(qdesn, cached_pf) else "mixed",
            "selector_evidence_tier": "tier_a_both_selectors_dual_reference",
            "selected_on_split": "validation",
            "test_role": "one_time_audit_after_winner_freeze",
            "whole_surface_included": True,
            "individual_test_win_required_for_inclusion": False,
            "individual_row_promotion_authorized": False,
            "proposal_status": "frozen_candidate_pending_independent_integration_review",
            "paper_table_ii_equivalence_claimed": False,
            "cached_replay_replacement_claimed": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        }
        for region, fold, family, qdesn, cached_pf, op_pf, _queue in rows
    ])
    r48 = write_csv(tmp_path / "r48.csv", [{
        "region": "BB", "fold": 1, "pooled_test_AQL": 4.95,
        "authoritative_qdesn_AQL": 5.1, "cached_pricefm_AQL": 5.8,
        "beats_authoritative_qdesn": True, "beats_cached_pricefm": True,
        "mcmc_confirmation_eligible": True, "decision": "queued",
    }])
    r50 = write_csv(tmp_path / "r50.csv", [{
        "region": "BB", "fold": 1, "mcmc_pooled_test_AQL": 5.05,
        "beats_authoritative_qdesn": True, "beats_cached_pricefm": True,
        "hard_convergence_pass": False, "promotion_eligible": False,
        "decision": "blocked_r50_mcmc_confirmation_gate",
    }])
    r54 = write_csv(tmp_path / "r54.csv", [
        {
            "region": "BB", "fold": 1, "m0_validation_AQL": 5.3, "m0_test_AQL": 5.4,
            "validation_selected": True, "diagnostics_pass": False,
            "beats_authoritative_qdesn": False, "beats_cached_pricefm": True,
            "internal_registry_promotion_candidate": False,
            "article_pricefm_promotion_candidate": False,
            "decision": "no_promotion",
        }
    ])
    summaries = {
        "r62": write_json(tmp_path / "r62_summary.json", {"matched_cells": 4, "test_opened": False}),
        "r48": write_json(tmp_path / "r48_summary.json", {"status": "completed_frozen_test_audit"}),
        "r50": write_json(tmp_path / "r50_summary.json", {"promotion_candidates": 0}),
        "r54": write_json(tmp_path / "r54_summary.json", {"article_promotion_candidates": 0}),
        "r65": write_json(tmp_path / "r65_summary.json", {"status": "scientifically_stopped_mechanism_failure"}),
        "r66": write_json(tmp_path / "r66_summary.json", {"status": "prepared_corrected_r66_not_launched"}),
        "r67": write_json(tmp_path / "r67_summary.json", {
            "new_fit_package_authority": "exact_CRAN_exdqlm_1.1.1_public_API",
            "historical_custom_engine_may_be_relabelled_as_cran111": False,
        }),
        "cached": write_json(tmp_path / "cached_summary.json", {"status": "completed"}),
        "operational": write_json(tmp_path / "operational_summary.json", {"status": "completed_read_only_postcloseout_audit"}),
        "article": write_json(tmp_path / "article_summary.json", {"status": "completed"}),
        "article_manifest": write_json(tmp_path / "article_manifest.json", {"files": []}),
    }
    return {
        "r62_csv": r62,
        "queues": queues,
        "cached": cached,
        "operational": op,
        "r48": r48,
        "r50": r50,
        "r54": r54,
        "r62_summary": summaries["r62"],
        "r48_summary": summaries["r48"],
        "r50_summary": summaries["r50"],
        "r54_summary": summaries["r54"],
        "r65_summary": summaries["r65"],
        "r66_summary": summaries["r66"],
        "r67_summary": summaries["r67"],
        "cached_summary": summaries["cached"],
        "operational_summary": summaries["operational"],
        "article_summary": summaries["article"],
        "article_manifest": summaries["article_manifest"],
    }


def parse_args(module, inputs, output):
    return module.parser().parse_args([
        "--artifact-repo", str(output.parent),
        "--article-repo", str(output.parent),
        "--r62-authority", str(inputs["r62_csv"]),
        "--r62-queues", str(inputs["queues"]),
        "--r62-summary", str(inputs["r62_summary"]),
        "--r48-closeout", str(inputs["r48"]),
        "--r48-summary", str(inputs["r48_summary"]),
        "--r50-decision", str(inputs["r50"]),
        "--r50-summary", str(inputs["r50_summary"]),
        "--r54-decisions", str(inputs["r54"]),
        "--r54-summary", str(inputs["r54_summary"]),
        "--r65-summary", str(inputs["r65_summary"]),
        "--r66-summary", str(inputs["r66_summary"]),
        "--r67-summary", str(inputs["r67_summary"]),
        "--cached-registry", str(inputs["cached"]),
        "--cached-summary", str(inputs["cached_summary"]),
        "--operational-proposal", str(inputs["operational"]),
        "--operational-summary", str(inputs["operational_summary"]),
        "--article-summary", str(inputs["article_summary"]),
        "--article-manifest", str(inputs["article_manifest"]),
        "--output-dir", str(output),
        "--expected-cells", "4",
    ])


def test_r68_reconciles_comparators_and_builds_bounded_refit_queue(tmp_path, monkeypatch):
    module = load_module()
    inputs = fixture_inputs(tmp_path)
    output = tmp_path / "out"
    args = parse_args(module, inputs, output)
    monkeypatch.setattr(module, "git_head", lambda _path: "d" * 40)

    summary = module.run(args)
    recon = pd.read_csv(output / "pricefm_stage_r68_case_authority_reconciliation.csv")
    queue = pd.read_csv(output / "pricefm_stage_r68_refit_target_queue.csv")
    policy = pd.read_csv(output / "pricefm_stage_r68_comparator_policy.csv")
    gates = pd.read_csv(output / "pricefm_stage_r68_global_gates.csv")

    assert summary["status"] == "completed_read_only_authority_reconciliation"
    assert summary["qdesn_beats_operational_pricefm"] == 1
    assert summary["targeted_refit_candidates"] == 2
    assert set(queue.region) == {"BB", "DD"}
    assert recon.loc[recon.region.eq("AA"), "refit_priority"].iloc[0] == "harm_guard_keep_current"
    assert recon.loc[recon.region.eq("CC"), "refit_priority"].iloc[0] == "hold_far_gap"
    assert policy.loc[
        policy.comparator.eq("operational_pricefm_public_architecture_replay"),
        "role",
    ].iloc[0] == "controlling_pricefm_refit_target"
    assert gates.loc[gates.required, "passed"].all()
    assert summary["launch_authorized"] is False
    assert not list(output.rglob("*.yaml"))
    assert not list(output.rglob("*.yml"))


def test_r68_rejects_non_validation_r62_authority(tmp_path):
    module = load_module()
    inputs = fixture_inputs(tmp_path)
    r62 = pd.read_csv(inputs["r62_csv"])
    r62.loc[0, "selection_split"] = "test"
    r62.to_csv(inputs["r62_csv"], index=False)
    args = parse_args(module, inputs, tmp_path / "out")

    with pytest.raises(RuntimeError, match="validation selected"):
        module.run(args)


def test_r68_rejects_historical_engine_relabelling(tmp_path):
    module = load_module()
    inputs = fixture_inputs(tmp_path)
    inputs["r67_summary"].write_text(json.dumps({
        "new_fit_package_authority": "exact_CRAN_exdqlm_1.1.1_public_API",
        "historical_custom_engine_may_be_relabelled_as_cran111": True,
    }))
    args = parse_args(module, inputs, tmp_path / "out")

    with pytest.raises(RuntimeError, match="relabelling"):
        module.run(args)
