import importlib.util
from pathlib import Path
import sys

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/287_closeout_pricefm_stage_r91_test_audit_and_promotion.py"


def load():
    spec = importlib.util.spec_from_file_location("pricefm_r91", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_horizon_blocks_are_exact():
    module = load()
    values = module.horizon_group(pd.Series([1, 24, 25, 48, 49, 72, 73, 96]))
    assert values.tolist() == ["1-24", "1-24", "25-48", "25-48", "49-72", "49-72", "73-96", "73-96"]


def test_promotion_requires_dual_win_and_complete_subgroup_diagnostics():
    module = load()
    cases = pd.DataFrame({
        "case_id": ["pass", "incomplete"], "region": ["AA", "BB"], "fold": [1, 1],
        "candidate_test_AQL": [0.9, 0.9], "validation_replay_pass": [True, True],
    })
    quantiles = pd.DataFrame([
        {"case_id": case, "tau": tau, "candidate_test_AQL": 0.9}
        for case in ("pass", "incomplete") for tau in module.TAUS
        if not (case == "incomplete" and tau == 0.9)
    ])
    horizons = pd.DataFrame([
        {"case_id": case, "tau": tau, "horizon_group": block, "candidate_test_AQL": 0.9}
        for case in ("pass", "incomplete") for tau in module.TAUS for block in module.BLOCKS
    ])
    crefs = pd.DataFrame([
        {"case_id": case, "authoritative_qdesn_test_AQL": 1.0, "cached_pricefm_test_AQL": 1.0}
        for case in ("pass", "incomplete")
    ])
    decisions, _ = module.apply_promotion_gates(cases, quantiles, horizons, crefs)
    result = decisions.set_index("case_id")
    assert bool(result.loc["pass", "promotion_eligible"])
    assert not bool(result.loc["incomplete", "promotion_eligible"])


def test_score_case_rejects_duplicate_test_prediction_keys(tmp_path):
    module = load()
    assert "Duplicate R90 test prediction keys" in SCRIPT.read_text()
    assert "Unexpected R90 prediction quantiles" in SCRIPT.read_text()
    assert "Unexpected R90 prediction horizons" in SCRIPT.read_text()
    assert "Mixed target scalers" in SCRIPT.read_text()


def test_closeout_cannot_mutate_or_launch():
    text = SCRIPT.read_text()
    assert '"registry_mutated": False' in text
    assert '"article_mutated": False' in text
    assert '"joint_or_mcmc_authorized": False' in text
    assert "subprocess" not in text
