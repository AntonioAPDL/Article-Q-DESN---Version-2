import importlib.util
import sys
from pathlib import Path

import numpy as np
import pandas as pd


SCRIPTS = Path(__file__).parents[1] / "scripts/pricefm"
R55 = SCRIPTS / "187_audit_pricefm_stage_r55_functional_convergence.py"
sys.path.insert(0, str(SCRIPTS))


def load_module():
    spec = importlib.util.spec_from_file_location("pricefm_stage_r55", R55)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_modern_diagnostics_distinguish_iid_and_shifted_chains():
    mod = load_module()
    rng = np.random.default_rng(20260820)
    iid = rng.normal(size=(4, 2000))
    healthy = mod.modern_diagnostics(iid)
    assert healthy["combined_rhat"] < 1.01
    assert healthy["bulk_ess"] > 1000
    assert healthy["tail_ess"] > 500

    shifted = iid.copy()
    shifted[0] += 2.5
    unhealthy = mod.modern_diagnostics(shifted)
    assert unhealthy["combined_rhat"] > 1.1
    assert unhealthy["bulk_ess"] < healthy["bulk_ess"]


def test_confirmation_target_requires_validation_harm_replay_and_both_references():
    mod = load_module()
    rows = pd.DataFrame([
        {
            "case_id": "ee", "region": "EE", "fold": 1,
            "validation_selected": True, "validation_harm_guard_pass": True,
            "authority_replay_pass": True, "beats_authoritative_qdesn": True,
            "beats_cached_pricefm": True,
        },
        {
            "case_id": "harm", "region": "AA", "fold": 1,
            "validation_selected": True, "validation_harm_guard_pass": False,
            "authority_replay_pass": True, "beats_authoritative_qdesn": True,
            "beats_cached_pricefm": True,
        },
        {
            "case_id": "test_only", "region": "BB", "fold": 1,
            "validation_selected": False, "validation_harm_guard_pass": True,
            "authority_replay_pass": True, "beats_authoritative_qdesn": True,
            "beats_cached_pricefm": True,
        },
    ])
    targets = mod.confirmation_candidates(rows)
    assert targets.case_id.tolist() == ["ee"]
    comparison = mod.diagnostic_comparison_cases(rows)
    assert comparison.case_id.tolist() == ["ee", "harm"]


def test_case_triage_never_authorizes_launch_or_mutation():
    mod = load_module()
    decisions = pd.DataFrame([{
        "case_id": "ee", "region": "EE", "fold": 1,
        "validation_selected": True, "validation_harm_guard_pass": True,
        "authority_replay_pass": True, "beats_authoritative_qdesn": True,
        "beats_cached_pricefm": True,
    }])
    modern = pd.DataFrame([{
        "case_id": "ee", "modern_diagnostic_pass": False,
        "combined_rhat": 1.2, "bulk_ess": 50.0, "tail_ess": 40.0,
    }])
    functional = pd.DataFrame([{
        "case_id": "ee", "functional_stability_pass": False,
        "path_group_nrmse": 0.02, "chain_relative_spread": 0.01,
    }])
    triage = mod.build_case_triage(decisions, modern, functional)
    assert triage.iloc[0].bounded_confirmation_target
    assert not triage.iloc[0].confirmation_launch_authorized
    assert triage.iloc[0].recommended_action == "design_case_specific_full_budget_confirmation"


def test_script_contract_is_read_only_and_writes_no_launch_yaml():
    text = R55.read_text()
    assert "rank_folded_rhat" in text
    assert "bulk_ess" in text and "tail_ess" in text
    assert "validation_selected+harm_guard+authority_replay" in text
    assert '"confirmation_launch_authorized": False' in text
    assert '"cleanup_authorized": False' in text
    assert '"registry_mutation_authorized": False' in text
    assert '"article_mutation_authorized": False' in text
    assert "launch.yaml" not in text
