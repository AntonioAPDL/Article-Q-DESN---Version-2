import importlib.util
import sys
from pathlib import Path

import pandas as pd


SCRIPT = Path(__file__).parents[1] / "scripts/pricefm/171_prepare_pricefm_stage_r45_full_quantile_confirmation.py"
if str(SCRIPT.parent) not in sys.path:
    sys.path.insert(0, str(SCRIPT.parent))


def module():
    spec = importlib.util.spec_from_file_location("r45", SCRIPT)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def source_grid():
    return {"pricefm_desn_experiment_grid": {
        "grid_id": "r43", "purpose": "old",
        "base": {},
        "scope": {"regions": ["NO_3"], "folds": [2, 3], "splits": ["train", "val"], "quantiles": [0.5]},
        "fixed": {
            "qdesn_likelihoods": ["al", "exal"], "normal": {"enabled": True},
            "warm_start": {}, "nested_validation": {"enabled": True},
            "qdesn_vb": {"readout_modes": ["shared_static", "separate_horizon_block"], "horizon_readout": {"partial_pooling": {"enabled": True}}},
        },
        "launch": {},
        "experiments": [
            {"id": "r43_a", "regions": ["NO_3"], "folds": [2], "quantile": .5},
            {"id": "r43_b", "regions": ["NO_3"], "folds": [3], "quantile": .5},
            {"id": "r43_c", "regions": ["NO_5"], "folds": [3], "quantile": .5},
        ],
    }}


def queue():
    return pd.DataFrame([
        {"experiment_id": "r43_a", "region": "NO_3", "fold": 2, "weight_1_24": .75, "weight_25_48": 0, "weight_49_72": 0, "weight_73_96": 0},
        {"experiment_id": "r43_b", "region": "NO_3", "fold": 3, "weight_1_24": .25, "weight_25_48": 0, "weight_49_72": 0, "weight_73_96": 0},
    ])


def test_grid_is_two_case_full_quantile_and_disables_reselection():
    mod = module()
    payload = mod.build_grid(source_grid(), queue(), Path("out"), Path("grid"), Path("runs"), [40, 41], True)
    grid = payload["pricefm_desn_experiment_grid"]
    assert len(grid["experiments"]) == 2
    assert grid["scope"]["quantiles"] == mod.PAPER_QUANTILES
    assert grid["scope"]["splits"] == ["train", "val"]
    assert grid["fixed"]["nested_validation"]["enabled"] is False
    assert grid["fixed"]["qdesn_vb"]["horizon_readout"]["partial_pooling"]["enabled"] is False
    assert grid["fixed"]["warm_start"]["fallback_to_cold"] is False
    assert grid["experiments"][0]["frozen_horizon_pooling_weights"]["1-24"] == .75
    assert "quantile" not in grid["experiments"][0]


def test_capability_audit_passes_real_runner():
    mod = module()
    runner = Path(__file__).parents[1] / "scripts/pricefm/08_run_desn_model_smoke.R"
    assert mod.capability_audit(runner)["passed"].all()


def test_launch_prep_never_launches_and_keeps_test_and_mutations_blocked():
    source = SCRIPT.read_text()
    assert "subprocess" not in source
    assert "rows_test.csv" not in source
    assert '"test_inspected": False' in source
    assert '"mcmc_authorized": False' in source
    assert '"--authorize-launch", type=parse_bool, default=False' in source
    assert "PAPER_QUANTILES = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]" in source
