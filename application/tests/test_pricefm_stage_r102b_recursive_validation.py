"""Focused tests for PriceFM Stage-R102B recursive validation."""

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

import pricefm_recursive_normal as recursive  # noqa: E402


def load(name: str):
    path = SCRIPTS / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PREP = load("339_prepare_pricefm_stage_r102b_recursive_validation.py")
CLOSEOUT = load("341_closeout_pricefm_stage_r102b_recursive_validation.py")
ORCHESTRATOR = load("342_orchestrate_pricefm_stage_r102b_recursive_validation.py")


def target_spec(region: str) -> dict:
    return {
        "region": region,
        "feature_policy": "target_only",
        "lag_window": 3,
        "depth": 1,
        "units": [2],
        "alpha": 0.5,
        "rho": 0.8,
        "input_scale": 0.2,
        "state_output": "final_layer",
        "seed": 7,
        "spatial": {"graph_degree": 0},
        "tau0": 0.01,
    }


def toy_context(region: str, offset: float = 0.0) -> dict:
    rng = np.random.default_rng(int(100 + offset))
    n_origins = 2
    initial_lag = rng.normal(size=(n_origins, 3, 4))
    raw_lead = rng.normal(size=(n_origins, 96, 3))
    config = {
        "depth": 1,
        "units": [2],
        "alpha": [0.5],
        "rho": [0.8],
        "input_scale": [0.2],
        "recurrent_sparsity": [1.0],
        "bias_scale": [0.0],
        "reservoir_activation": "tanh",
        "state_output": "final_layer",
    }
    reservoir = {"layers": [{
        "input": np.asarray([[0.2, 0.1], [0.1, -0.1], [0.05, 0.03], [-0.02, 0.04]]),
        "recurrent": np.asarray([[0.3, 0.1], [-0.1, 0.2]]),
        "bias": np.zeros(2),
    }]}
    p = 1 + 2 + 3 + 99
    beta = np.zeros((4, p))
    beta[:, 0] = 0.2 + offset
    beta[:, 1] = 0.7
    context = {
        "region": region,
        "spec": target_spec(region),
        "active_regions": [region],
        "input_regions": ["AT", "BE"],
        "initial_lag": initial_lag,
        "lead_features": raw_lead,
        "raw_lead": {region: raw_lead},
        "lag_columns": {region: [f"{region}-price", f"{region}-load", f"{region}-solar", f"{region}-wind"]},
        "lead_columns": {region: [f"{region}-load", f"{region}-solar", f"{region}-wind"]},
        "truth": rng.normal(size=(n_origins, 96)),
        "reservoir": reservoir,
        "reservoir_config": config,
        "posterior_draws": {"beta": beta, "omega2": np.zeros(4), "contract": "toy"},
    }
    context["initial_states"] = recursive.precompute_initial_states(context)
    return context


def test_exact_ridge_and_rhs_draw_contracts_are_deterministic() -> None:
    mean = np.asarray([0.2, -0.1])
    covariance = np.asarray([[0.4, 0.05], [0.05, 0.3]])
    precision_inverse = np.asarray([[0.2, 0.01], [0.01, 0.15]])
    first = recursive.draw_normal_posterior(
        mean, covariance, 10.0, 4.0, 200, 81, "scaled_ridge", precision_inverse
    )
    second = recursive.draw_normal_posterior(
        mean, covariance, 10.0, 4.0, 200, 81, "scaled_ridge", precision_inverse
    )
    np.testing.assert_array_equal(first["beta"], second["beta"])
    np.testing.assert_array_equal(first["omega2"], second["omega2"])
    assert first["contract"] == "exact_normal_inverse_gamma_conditional"
    rhs = recursive.draw_normal_posterior(mean, covariance, 10.0, 4.0, 200, 81, "rhs_ns")
    assert rhs["contract"] == "mean_field_q_beta_times_q_omega2"
    assert rhs["beta"].shape == (200, 2)
    assert np.all(rhs["omega2"] > 0)


def test_recursive_transition_uses_generated_price_and_known_exogenous() -> None:
    price = np.asarray([1.0, 2.0, 3.0])
    exogenous = np.asarray([10.0, 20.0, 30.0])
    value = recursive.recursive_transition_features(
        "AT",
        target_spec("AT"),
        {"AT": price},
        {"AT": exogenous},
        {"AT": ["AT-price", "AT-load", "AT-solar", "AT-wind"]},
        {"AT": ["AT-load", "AT-solar", "AT-wind"]},
        ["AT"],
    )
    np.testing.assert_allclose(value[:, 0], price)
    np.testing.assert_allclose(value[:, 1:], np.repeat(exogenous[None, :], 3, axis=0))


def test_recursive_panel_is_order_invariant_and_never_reads_truth() -> None:
    contexts = {"AT": toy_context("AT", 0), "BE": toy_context("BE", 1)}
    first = recursive.recursive_panel_origin(contexts, 0, 4, 1, 91, ["AT", "BE"])
    second = recursive.recursive_panel_origin(contexts, 0, 4, 1, 91, ["BE", "AT"])
    np.testing.assert_allclose(first, second)
    contexts["AT"]["truth"][:] = 1e12
    contexts["BE"]["truth"][:] = -1e12
    third = recursive.recursive_panel_origin(contexts, 0, 4, 1, 91, ["AT", "BE"])
    np.testing.assert_allclose(first, third)
    assert first.shape == (4, 96, 2)


def test_r102b_prep_is_complete_validation_only_and_blocks_later_surfaces() -> None:
    args = PREP.parser().parse_args([])
    bundle = PREP.build(args)
    assert len(bundle["tasks"]) == 12
    assert set(bundle["tasks"].panel) == {"r98_control", "r100_primary"}
    assert set(bundle["tasks"].prior_type) == {"scaled_ridge", "rhs_ns"}
    assert set(bundle["tasks"].fold.astype(int)) == {1, 2, 3}
    assert bundle["tasks"].selection_split.eq("validation_only").all()
    assert bundle["tasks"].test_access_authorized.eq(False).all()
    assert bundle["summary"]["quantile_fit_authorized"] is False
    assert bundle["summary"]["article_mutation_authorized"] is False


def test_complete_panel_selection_uses_weighted_aql_then_worst_fold() -> None:
    rows = []
    for panel, values in {
        "r98_control": [2.0, 2.0, 2.0],
        "r100_primary": [1.0, 2.0, 3.0],
    }.items():
        for fold, value in enumerate(values, start=1):
            rows.append({
                "panel": panel,
                "prior_type": "rhs_ns",
                "fold": fold,
                "validation_AQL_original": value,
                "validation_AQCR": 0.0,
                "n_loss_atoms": 10,
            })
    surfaces = CLOSEOUT.aggregate_surfaces(pd.DataFrame(rows))
    selected = CLOSEOUT.select_rhs(surfaces)
    assert selected.panel == "r98_control"


def test_orchestrator_requires_clean_pushed_source_and_explicit_approval() -> None:
    assert ORCHESTRATOR.parse_cpus("17-19,24") == [17, 18, 19, 24]
    source = (SCRIPTS / "342_orchestrate_pricefm_stage_r102b_recursive_validation.py").read_text()
    assert "RUN_PRICEFM_R102B_RECURSIVE_VALIDATION" in source
    assert 'identity["head"] == identity["upstream_head"]' in source
    assert 'identity["branch"].startswith("work/pricefm-")' in source
    assert "quantile_fit_started" in source
    assert "test_opened" in source
