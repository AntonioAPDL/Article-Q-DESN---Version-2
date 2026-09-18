from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))


def load(name: str):
    path = SCRIPTS / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CLOSEOUT = load("362_closeout_pricefm_stage_r107_exact500_focus_comparison.py")
ORCHESTRATOR = load("363_orchestrate_pricefm_stage_r106_focus_comparison.py")


def metric_rows(aql_multiplier: float = 1.0) -> tuple[pd.DataFrame, pd.DataFrame]:
    exact_rows = []
    early_rows = []
    for _, region, fold, family, policy in CLOSEOUT.FOCUS_CASES:
        early = 10.0 + fold
        common = {
            "region": region, "fold": fold, "family": family, "policy": policy,
            "AQCR": 0.0, "coverage_10_90": 0.6,
            "mean_width_10_90": 40.0, "mean_width_25_75": 20.0,
            "median_MAE": 15.0, "median_RMSE": 20.0,
        }
        early_rows.append({**common, "AQL": early})
        exact_rows.append({
            "region": region, "fold": fold, "family": family, "policy": policy,
            "validation_AQL_original": early * aql_multiplier,
            "validation_AQCR": 0.0, "coverage_10_90": 0.6,
            "mean_width_10_90": 40.0, "mean_width_25_75": 20.0,
            "median_MAE": 15.0, "median_RMSE": 20.0,
        })
    return pd.DataFrame(exact_rows), pd.DataFrame(early_rows)


def test_exact500_equivalence_gate_stops_broad_campaign() -> None:
    exact, early = metric_rows(1.005)
    comparison = CLOSEOUT.matched_comparison(exact, early)
    decision = CLOSEOUT.decision_from_comparison(comparison)
    assert comparison.practically_equivalent.all()
    assert decision["recommended_action"] == "stop_broad_exact500_no_practical_change"
    assert decision["broad_resume_supported"] is False


def test_consistent_material_improvement_can_support_resume() -> None:
    exact, early = metric_rows(0.95)
    comparison = CLOSEOUT.matched_comparison(exact, early)
    decision = CLOSEOUT.decision_from_comparison(comparison)
    assert comparison.materially_better.all()
    assert decision["recommended_action"] == "resume_broad_exact500_after_resource_review"
    assert decision["broad_resume_supported"] is True


def test_crossing_harm_blocks_apparent_aql_gain() -> None:
    exact, early = metric_rows(0.95)
    exact.loc[0, "validation_AQCR"] = 0.05
    comparison = CLOSEOUT.matched_comparison(exact, early)
    decision = CLOSEOUT.decision_from_comparison(comparison)
    assert comparison.crossing_harm.any()
    assert decision["recommended_action"] == "hold_broad_exact500_mixed_forecast_effect"


def test_focus_contract_is_bounded_and_validation_only() -> None:
    assert ORCHESTRATOR.FOCUS_CASES == (
        "r106_bg_f1", "r106_be_f1", "r106_be_f2", "r106_be_f3"
    )
    assert ORCHESTRATOR.APPROVAL == "RUN_PRICEFM_R106_FOCUS_COMPARISON"
    source = (SCRIPTS / "363_orchestrate_pricefm_stage_r106_focus_comparison.py").read_text()
    assert "361_orchestrate_pricefm_stage_r106_exact500_recursive_quantile.py" in source
    assert 'int(args.workers) != 4' in source
    assert "362_closeout_pricefm_stage_r107_exact500_focus_comparison.py" in source
    assert "article" not in ORCHESTRATOR.FOCUS_CASES


def test_horizon_contract_has_seven_rows_times_96() -> None:
    assert len(CLOSEOUT.FOCUS_CASES) == 7
    assert len(CLOSEOUT.FOCUS_CASE_IDS) == 4
    expected = len(CLOSEOUT.FOCUS_CASES) * np.arange(1, 97).size
    assert expected == 672
