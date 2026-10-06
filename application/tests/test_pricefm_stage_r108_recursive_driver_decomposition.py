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

import pricefm_recursive_driver_diagnostics as diagnostics  # noqa: E402
import pricefm_recursive_normal as normal  # noqa: E402
import pricefm_recursive_quantile as quantile  # noqa: E402
from pricefm_recursive_quantile_marginal import stratified_uniforms  # noqa: E402


def load_script(name: str):
    path = SCRIPTS / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


AUDIT = load_script("364_audit_pricefm_stage_r108_recursive_driver_decomposition.py")


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
        "anchors": np.asarray(window["anchors"], dtype=str),
        "reservoir": fitted["reservoir"],
        "reservoir_config": fitted["reservoir_config"],
    }
    context["initial_states"] = normal.precompute_initial_states(context)
    return context, int(fitted["p"])


def beta_draws(p: int, n_paths: int = 20) -> dict[float, np.ndarray]:
    values = {}
    for index, tau in enumerate(quantile.QUANTILES):
        beta = np.full((n_paths, p), 0.02 * (index + 1), dtype=float)
        beta[:, 1:3] = np.asarray([0.8, -0.5])
        values[float(tau)] = beta
    return values


def test_oracle_bridge_endpoints_and_validation() -> None:
    truth = np.asarray([1.0, 2.0, 3.0])
    generated = np.asarray([4.0, 5.0, 6.0])
    np.testing.assert_array_equal(diagnostics.oracle_bridge(truth, generated, 0), truth)
    np.testing.assert_array_equal(diagnostics.oracle_bridge(truth, generated, 1), generated)
    np.testing.assert_allclose(
        diagnostics.oracle_bridge(truth, generated, 0.25),
        truth + 0.25 * (generated - truth),
    )


def test_pricefm_pseudo_paths_are_reproducible_monotone_and_bounded() -> None:
    curves = np.column_stack([
        np.linspace(index, index + 1, 96) for index in range(7)
    ])
    uniforms = stratified_uniforms(30, 96, 2026)
    first = diagnostics.quantile_curve_driver_paths(curves, 30, 1, uniforms=uniforms)
    second = diagnostics.quantile_curve_driver_paths(curves, 30, 999, uniforms=uniforms)
    np.testing.assert_array_equal(first["paths"], second["paths"])
    assert np.all(first["paths"] >= curves[:, 0][None, :])
    assert np.all(first["paths"] <= curves[:, -1][None, :])
    assert first["tail_rule"] == "winsorize_uniforms_to_fitted_0p10_0p90_grid"


def test_state_support_and_summary_detect_out_of_support_states() -> None:
    training = np.asarray([[-1.0, -1.0], [0.0, 0.0], [1.0, 1.0]])
    support = diagnostics.state_support(training)
    summary = diagnostics.summarize_state(np.asarray([[10.0, 10.0]]), support)
    assert summary["state_outside_training_envelope_rate"] == 1
    assert summary["state_robust_distance_mean"] > 1


def test_recursive_driver_is_strictly_causal_and_lambda_one_equals_self() -> None:
    context, p = toy_context()
    beta = beta_draws(p)
    uniforms = stratified_uniforms(20, 96, 44)
    self_result = diagnostics.recursive_quantile_driver_forecast(
        context,
        external_panel={},
        origin_index=0,
        beta_draws=beta,
        seed=1,
        target_mode="self",
        uniforms=uniforms,
    )
    truth_a = np.zeros(96)
    truth_b = truth_a.copy()
    truth_b[0] = 1000.0
    oracle_a = diagnostics.recursive_quantile_driver_forecast(
        context,
        external_panel={},
        origin_index=0,
        beta_draws=beta,
        seed=1,
        target_mode="oracle_bridge",
        target_truth=truth_a,
        oracle_lambda=0,
        uniforms=uniforms,
    )
    oracle_b = diagnostics.recursive_quantile_driver_forecast(
        context,
        external_panel={},
        origin_index=0,
        beta_draws=beta,
        seed=1,
        target_mode="oracle_bridge",
        target_truth=truth_b,
        oracle_lambda=0,
        uniforms=uniforms,
    )
    np.testing.assert_array_equal(oracle_a["samples"][:, 0], oracle_b["samples"][:, 0])
    assert not np.array_equal(oracle_a["samples"][:, 1], oracle_b["samples"][:, 1])
    lambda_one = diagnostics.recursive_quantile_driver_forecast(
        context,
        external_panel={},
        origin_index=0,
        beta_draws=beta,
        seed=1,
        target_mode="oracle_bridge",
        target_truth=truth_b,
        oracle_lambda=1,
        uniforms=uniforms,
    )
    np.testing.assert_allclose(lambda_one["samples"], self_result["samples"])
    np.testing.assert_allclose(lambda_one["target_driver"], self_result["target_driver"])


def test_external_target_driver_is_used_only_after_current_prediction() -> None:
    context, p = toy_context()
    beta = beta_draws(p)
    uniforms = stratified_uniforms(20, 96, 55)
    first_driver = np.zeros((20, 96))
    second_driver = first_driver.copy()
    second_driver[:, 0] = 500.0
    first = diagnostics.recursive_quantile_driver_forecast(
        context, {}, 0, beta, 1, target_mode="external",
        target_external=first_driver, uniforms=uniforms,
    )
    second = diagnostics.recursive_quantile_driver_forecast(
        context, {}, 0, beta, 1, target_mode="external",
        target_external=second_driver, uniforms=uniforms,
    )
    np.testing.assert_array_equal(first["samples"][:, 0], second["samples"][:, 0])
    assert not np.array_equal(first["samples"][:, 1], second["samples"][:, 1])


def test_r108_contract_is_no_refit_validation_only_and_blocks_mutation() -> None:
    helper = (SCRIPTS / "pricefm_recursive_driver_diagnostics.py").read_text()
    cache = (SCRIPTS / "363_prepare_pricefm_stage_r108_pricefm_driver_cache.py").read_text()
    runner = (SCRIPTS / "364_audit_pricefm_stage_r108_recursive_driver_decomposition.py").read_text()
    assert ".fit(" not in helper + cache + runner
    assert '"split": "validation_only"' in cache
    assert '"selection_split": "validation_only"' in runner
    assert '"model_fit_started": False' in cache
    assert '"model_fit_started": False' in runner
    assert '"registry_mutated": False' in runner
    assert '"article_mutated": False' in runner
    assert '"launch_yaml_written": False' in runner
    assert "subprocess.Popen" not in runner
    assert AUDIT.POLICIES[-1] == "pricefm_quantile_paths_all_active"


def test_external_references_are_complete_and_split_separated(tmp_path: Path) -> None:
    rows = []
    for region in AUDIT.COMPLETE_REGIONS:
        for fold in (1, 2, 3):
            rows.append({
                "region": region,
                "fold": fold,
                "qdesn_AQL": 7.0 + fold,
                "pricefm_AQL": 6.5 + fold,
                "test_metrics_role": "audit_and_reporting_only",
                "selection_is_validation_only": True,
                "test_driven_case_mixing_used": False,
            })
    path = tmp_path / "r98_registry.csv"
    pd.DataFrame(rows).to_csv(path, index=False)
    references = AUDIT.load_external_test_references(path)
    assert len(references) == 27
    assert set(references.reference_split) == {"outer_test"}
    assert set(references.comparison_role) == {
        "context_only_not_ranked_with_r108_validation"
    }
    assert references.current_authoritative_qdesn_AQL.notna().all()
    assert references.cached_pricefm_AQL.notna().all()
