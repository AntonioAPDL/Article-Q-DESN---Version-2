from __future__ import annotations

from pathlib import Path
import sys

import numpy as np
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import pricefm_recursive_normal as normal  # noqa: E402
import pricefm_recursive_quantile as quantile  # noqa: E402
import pricefm_recursive_quantile_marginal as marginal  # noqa: E402
import pricefm_recursive_readout as readout  # noqa: E402


def spec() -> dict:
    return {
        "region": "AT",
        "feature_policy": "target_only",
        "lag_window": 3,
        "depth": 1,
        "units": [2],
        "alpha": 0.5,
        "rho": 0.8,
        "input_scale": 0.2,
        "state_output": "final_layer",
        "seed": 17,
        "spatial": {"graph_degree": 0},
        "tau0": 0.01,
    }


def window() -> dict:
    rng = np.random.default_rng(113)
    return {
        "X_lag": rng.normal(size=(3, 3, 4)),
        "X_lead": rng.normal(size=(3, 96, 3)),
        "Y": rng.normal(size=(3, 96)),
        "anchors": np.asarray(["a", "b", "c"]),
        "lag_cols": ["AT-price", "AT-load", "AT-solar", "AT-wind"],
        "lead_cols": ["AT-load", "AT-solar", "AT-wind"],
    }


def context(source: dict) -> dict:
    fitted = quantile.causal_teacher_forced_design({"AT": source}, spec(), ["AT"])
    value = {
        "region": "AT",
        "spec": spec(),
        "active_regions": ["AT"],
        "input_regions": ["AT"],
        "initial_lag": np.asarray(source["X_lag"], dtype=float),
        "lead_features": np.asarray(source["X_lead"], dtype=float),
        "raw_lead": {"AT": np.asarray(source["X_lead"], dtype=float)},
        "lag_columns": {"AT": list(source["lag_cols"])},
        "lead_columns": {"AT": list(source["lead_cols"])},
        "reservoir": fitted["reservoir"],
        "reservoir_config": fitted["reservoir_config"],
    }
    value["initial_states"] = normal.precompute_initial_states(value)
    return value


@pytest.mark.parametrize(
    ("mode", "dimension"),
    [("state_lead_horizon", 105), ("state_horizon", 102), ("state_only", 3)],
)
def test_readout_modes_have_exact_dimensions_and_feature_order(mode: str, dimension: int) -> None:
    result = quantile.causal_teacher_forced_design(
        {"AT": window()}, spec(), ["AT"], readout_mode=mode
    )
    assert result["p"] == dimension
    assert result["X"].shape == (3 * 96, dimension)
    assert result["readout_mode"] == mode
    assert result["feature_names"][0] == "intercept"
    assert sum(name.startswith("state_") for name in result["feature_names"]) == 2
    assert any(name.startswith("lead::") for name in result["feature_names"]) == (
        mode == "state_lead_horizon"
    )
    assert any(name.startswith("horizon_") for name in result["feature_names"]) == (
        mode != "state_only"
    )
    assert result["horizon_one_parity_max_abs"] <= 1e-12


def test_no_bypass_still_uses_future_exogenous_values_in_state_transition() -> None:
    source = window()
    base_context = context(source)
    driver = np.zeros((8, 96, 1), dtype=float)
    first = quantile.recursive_quantile_design(
        base_context, driver, 0, ["AT"], readout_mode="state_only"
    )
    changed_source = dict(source)
    changed_source["X_lead"] = np.asarray(source["X_lead"]).copy()
    changed_source["X_lead"][0, 0, 0] += 50.0
    changed_context = context(changed_source)
    second = quantile.recursive_quantile_design(
        changed_context, driver, 0, ["AT"], readout_mode="state_only"
    )
    np.testing.assert_array_equal(first[:, 0], second[:, 0])
    assert not np.allclose(first[:, 1], second[:, 1])


def test_generated_price_affects_only_the_next_horizon_for_every_readout() -> None:
    value = context(window())
    baseline = np.zeros((8, 96, 1), dtype=float)
    changed = baseline.copy()
    changed[:, 0, 0] = np.arange(8, dtype=float) + 1
    for mode in readout.READOUT_MODES:
        first = quantile.recursive_quantile_design(value, baseline, 0, ["AT"], mode)
        second = quantile.recursive_quantile_design(value, changed, 0, ["AT"], mode)
        np.testing.assert_array_equal(first[:, 0], second[:, 0])
        assert not np.allclose(first[:, 1], second[:, 1])


def test_independent_policy_is_byte_identical_to_legacy_operator() -> None:
    legacy = marginal.stratified_uniforms(500, 96, 20260922)
    dispatched = marginal.forecast_uniforms(
        "independent_stratified", 500, 96, 20260922
    )
    np.testing.assert_array_equal(legacy, dispatched)


def test_training_block_ranks_are_reproducible_and_horizon_stratified() -> None:
    rng = np.random.default_rng(114)
    ranks = rng.uniform(0.001, 0.999, size=(40, 144))
    first = marginal.training_block_rank_uniforms(ranks, 500, 96, 12, 99)
    second = marginal.training_block_rank_uniforms(ranks, 500, 96, 12, 99)
    third = marginal.training_block_rank_uniforms(ranks, 500, 96, 24, 99)
    np.testing.assert_array_equal(first, second)
    assert not np.array_equal(first, third)
    expected = (np.arange(500, dtype=float) + 0.5) / 500
    for horizon in range(96):
        np.testing.assert_array_equal(np.sort(first[:, horizon]), expected)


def test_training_block_ranks_fail_closed_on_nontraining_like_inputs() -> None:
    with pytest.raises(ValueError, match="strictly inside"):
        marginal.training_block_rank_uniforms(
            np.asarray([[0.0] * 24, [0.5] * 24]), 10, 96, 12, 1
        )
    with pytest.raises(ValueError, match="controls"):
        marginal.training_block_rank_uniforms(
            np.full((3, 96), 0.5), 10, 96, 8, 1
        )
