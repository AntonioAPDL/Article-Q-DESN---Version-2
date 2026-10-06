from __future__ import annotations

from pathlib import Path
import sys

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import pricefm_recursive_normal as normal  # noqa: E402
import pricefm_recursive_quantile as quantile  # noqa: E402
import pricefm_recursive_quantile_marginal as marginal  # noqa: E402


def target_spec() -> dict:
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


def toy_context() -> tuple[dict, int]:
    rng = np.random.default_rng(91)
    window = {
        "X_lag": rng.normal(size=(2, 3, 4)),
        "X_lead": rng.normal(size=(2, 96, 3)),
        "Y": rng.normal(size=(2, 96)),
        "anchors": np.asarray(["a", "b"]),
        "lag_cols": ["AT-price", "AT-load", "AT-solar", "AT-wind"],
        "lead_cols": ["AT-load", "AT-solar", "AT-wind"],
    }
    fitted = quantile.causal_teacher_forced_design({"AT": window}, target_spec(), ["AT"])
    context = {
        "region": "AT",
        "spec": target_spec(),
        "active_regions": ["AT"],
        "input_regions": ["AT"],
        "initial_lag": np.asarray(window["X_lag"], dtype=float),
        "lead_features": np.asarray(window["X_lead"], dtype=float),
        "raw_lead": {"AT": np.asarray(window["X_lead"], dtype=float)},
        "lag_columns": {"AT": list(window["lag_cols"])},
        "lead_columns": {"AT": list(window["lead_cols"])},
        "truth": np.asarray(window["Y"], dtype=float),
        "reservoir": fitted["reservoir"],
        "reservoir_config": fitted["reservoir_config"],
    }
    context["initial_states"] = normal.precompute_initial_states(context)
    return context, int(fitted["p"])


def test_curve_rearrangement_and_interpolation_are_bounded() -> None:
    raw = np.asarray([[3.0, 1.0, 2.0], [-2.0, 0.0, 4.0]])
    ordered, diagnostics = marginal.rearrange_quantile_curves(raw)
    np.testing.assert_array_equal(ordered, [[1.0, 2.0, 3.0], [-2.0, 0.0, 4.0]])
    assert diagnostics["pre_rearrangement_crossing_rate"] > 0
    sampled = marginal.interpolate_quantile_curves(
        ordered,
        [0.1, 0.5, 0.9],
        np.asarray([0.01, 0.99]),
    )
    np.testing.assert_array_equal(sampled, [1.0, 4.0])


def test_stratified_uniforms_are_reproducible_and_balanced() -> None:
    first = marginal.stratified_uniforms(20, 4, 81)
    second = marginal.stratified_uniforms(20, 4, 81)
    third = marginal.stratified_uniforms(20, 4, 82)
    np.testing.assert_array_equal(first, second)
    assert not np.array_equal(first, third)
    np.testing.assert_allclose(np.sort(first[:, 0]), (np.arange(20) + 0.5) / 20)


def test_conditional_quantile_paths_keep_path_identity() -> None:
    design = np.asarray([[1.0, 2.0], [3.0, 4.0]])
    beta = {
        0.1: np.asarray([[1.0, 0.0], [2.0, 0.0]]),
        0.9: np.asarray([[0.0, 1.0], [0.0, 2.0]]),
    }
    result = marginal.conditional_quantile_paths(design, beta, [0.1, 0.9])
    np.testing.assert_array_equal(result, [[1.0, 2.0], [6.0, 8.0]])


def test_target_only_recursion_ignores_external_target_paths_and_truth() -> None:
    context, p = toy_context()
    n_paths = 40
    rng = np.random.default_rng(419)
    beta = {
        float(tau): rng.normal(scale=0.03, size=(n_paths, p)) + float(tau)
        for tau in quantile.QUANTILES
    }
    first_driver = np.zeros((n_paths, 96, 1), dtype=float)
    second_driver = np.full((n_paths, 96, 1), 1e6, dtype=float)
    first = marginal.recursive_quantile_curve_forecast(
        context, first_driver, 0, ["AT"], beta, seed=717
    )
    context["truth"][:] = -1e12
    second = marginal.recursive_quantile_curve_forecast(
        context, second_driver, 0, ["AT"], beta, seed=717
    )
    np.testing.assert_array_equal(first["prediction"], second["prediction"])
    np.testing.assert_array_equal(first["samples"], second["samples"])
    assert first["prediction"].shape == (7, 96)
    assert first["samples"].shape == (n_paths, 96)
    assert first["test_opened"] is False
    assert np.all(first["prediction"][:-1] <= first["prediction"][1:])


def test_recursive_curve_rejects_missing_active_region() -> None:
    context, p = toy_context()
    beta = {
        float(tau): np.ones((10, p), dtype=float)
        for tau in quantile.QUANTILES
    }
    try:
        marginal.recursive_quantile_curve_forecast(
            context,
            np.zeros((10, 96, 1), dtype=float),
            0,
            ["BE"],
            beta,
            seed=1,
        )
    except ValueError as error:
        assert "omits an active" in str(error)
    else:
        raise AssertionError("a missing active region must fail")
