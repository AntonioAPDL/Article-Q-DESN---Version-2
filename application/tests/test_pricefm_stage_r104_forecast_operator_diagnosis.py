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


def load_script():
    path = SCRIPTS / "350_audit_pricefm_stage_r104_forecast_operator.py"
    spec = importlib.util.spec_from_file_location(path.stem, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


AUDIT = load_script()


def test_selected_family_uses_fold1_and_whole_family_eligibility() -> None:
    rows = []
    for fold in (1, 2, 3):
        rows.extend([
            {
                "fold": fold,
                "family": "al",
                "validation_AQL_original": 2.0,
                "numerically_eligible": True,
            },
            {
                "fold": fold,
                "family": "exal",
                "validation_AQL_original": 1.0 if fold == 1 else 9.0,
                "numerically_eligible": True,
            },
        ])
    frame = pd.DataFrame(rows)
    assert AUDIT.selected_family(frame) == "exal"
    frame.loc[(frame.family == "exal") & (frame.fold == 3), "numerically_eligible"] = False
    assert AUDIT.selected_family(frame) == "al"


def test_surface_score_recovers_perfect_ordered_forecast() -> None:
    truth = np.asarray([[1.0, 2.0], [3.0, 4.0]])
    offsets = np.asarray([-2.0, -1.0, -0.1, 0.0, 0.1, 1.0, 2.0])
    prediction = truth[None, :, :] + offsets[:, None, None]
    result = AUDIT.score_surface(truth, prediction)
    assert result["AQCR"] == 0
    assert result["coverage_10_90"] == 1
    assert result["median_MAE"] == 0
    assert result["mean_width_10_90"] == 4


def test_horizon_metrics_keep_complete_geometry() -> None:
    truth = np.zeros((3, 96), dtype=float)
    prediction = np.zeros((7, 3, 96), dtype=float)
    result = AUDIT.horizon_metrics("BG", 1, "al", "candidate", truth, prediction)
    assert len(result) == 96
    assert result.horizon.tolist() == list(range(1, 97))
    assert result.AQL.eq(0).all()


def test_aggregate_operator_metrics_keeps_policy_fixed_across_folds() -> None:
    rows = []
    for fold, current, candidate_a, candidate_b in (
        (1, 10.0, 5.0, 7.0),
        (2, 10.0, 8.0, 4.0),
        (3, 10.0, 6.0, 9.0),
    ):
        for policy, aql in (
            ("normal_rhs_mean_conditional", current),
            ("quantile_curve_self_rhs_neighbors", candidate_a),
            ("quantile_curve_self_ridge_neighbors", candidate_b),
        ):
            rows.append({
                "region": "BE",
                "fold": fold,
                "family": "exal",
                "policy": policy,
                "AQL": aql,
                "AQCR": 0.0,
                "coverage_10_90": 0.5,
                "mean_width_10_90": 2.0,
                "mean_width_25_75": 1.0,
                "median_MAE": aql,
                "median_RMSE": aql,
                "pre_rearrangement_crossing_rate": 0.0,
                "rearrangement_mean_abs_scaled": 0.0,
                "rearrangement_max_abs_scaled": 0.0,
                "n_origins": 1,
                "n_loss_atoms": 7,
            })
    result = AUDIT.aggregate_operator_metrics(pd.DataFrame(rows))
    assert len(result) == 3
    assert result.folds.eq(3).all()
    assert result[result.policy.eq("quantile_curve_self_rhs_neighbors")].AQL.item() == 19 / 3
    assert result[result.policy.eq("quantile_curve_self_ridge_neighbors")].AQL.item() == 20 / 3


def test_r104_is_read_only_and_broad_launch_is_not_authorized() -> None:
    source = (SCRIPTS / "350_audit_pricefm_stage_r104_forecast_operator.py").read_text()
    marginal = (SCRIPTS / "pricefm_recursive_quantile_marginal.py").read_text()
    assert "subprocess" not in source
    assert '"broad_relaunch_authorized": False' in source
    assert '"test_opened": False' in source
    assert "context[\"truth\"]" not in marginal
    assert "winsorize_uniforms_to_fitted_0p10_0p90_grid" in marginal
