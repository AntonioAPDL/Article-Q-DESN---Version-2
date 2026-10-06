from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
from statistics import NormalDist

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
sys.path.insert(0, str(SCRIPTS))
import pricefm_r120_engine as OLD
import pricefm_r122_runtime as R122
import pricefm_r123_runtime as NEW

loader = importlib.util.spec_from_file_location("r123_tests_runner", SCRIPTS / "433_run_pricefm_stage_r123_connectivity.py")
RUN = importlib.util.module_from_spec(loader); loader.loader.exec_module(RUN)
PROTOCOL = json.loads(RUN.PROTOCOL.read_text())


def spec(**kwargs):
    return NEW.normalize_spec(dict(RUN.anchor(), seed=2026092501, **kwargs))


def tiny_arrays():
    rng = np.random.default_rng(123)
    return NEW.ExplicitArrays(rng.normal(size=(1, 3120)), rng.normal(size=(1, 3120, 3)),
        rng.normal(size=(1, 96, 3)), rng.normal(size=(1, 96)), np.array(["2022-02-04T00:00:00Z"]),
        ("load", "solar", "wind"), ())


def test_legacy_winner_hash_and_real_disconnection():
    value = spec()
    old, _, _ = R122.BASE.make_reservoir(value, 2022)
    new, _, audit = NEW.make_reservoir(value, 2022)
    assert old["sha256"] == new["sha256"] == "fe2d590be516872054e9efee5006716212f0ab36513d3fbbb67c2eef3dc26d49"
    assert audit["current_exogenous_row_degrees"] == [0, 0, 0, 1, 4, 0]
    assert OLD.SOURCE_WINDOW == 970 and R122.BASE.SOURCE_WINDOW == 3120
    assert NEW.BASE is not R122.BASE


@pytest.mark.parametrize("policy", ["coverage", "balanced"])
@pytest.mark.parametrize("mx", [0, 24, 96, 672])
@pytest.mark.parametrize("channels", [3, 6, 9])
def test_mandatory_current_and_lag_coverage_with_fixed_fan(policy, mx, channels):
    value = spec(input_policy=policy, m_x=mx)
    matrix = NEW.input_matrix(value, 2016 + (mx + 1) * channels)
    degrees = np.diff(matrix.indptr)
    assert np.all(degrees[NEW.mandatory_rows(value, matrix.shape[0])] > 0)
    assert np.all(degrees[2016:2016 + channels] > 0)
    assert np.all(np.diff(matrix.tocsc().indptr) == 8)
    assert np.array_equal(matrix.toarray(), NEW.input_matrix(value, matrix.shape[0]).toarray())


def test_recurrent_pairing_and_separate_interlayer_gain():
    control, _, _ = NEW.make_reservoir(spec(), 2022)
    changed, config, audit = NEW.make_reservoir(spec(input_policy="balanced", interlayer_gain=.5), 2022)
    for a, b in zip(control["layers"], changed["layers"]):
        assert (a["recurrent"] != b["recurrent"]).nnz == 0
    np.testing.assert_allclose(changed["layers"][1]["input"], control["layers"][1]["input"] * 10)
    assert config["input_scale"] == [.05, .5]
    assert changed["sha256"] != control["sha256"]
    assert audit["missing_current_exogenous_count"] == 0


def test_current_exogenous_row_order_matches_actual_engine_names():
    value = spec(m_x=24)
    names = NEW.input_names(value, ["load", "solar", "wind"])
    current = NEW.mandatory_rows(value, len(names))[-3:]
    assert [names[i] for i in current] == ["load::current", "solar::current", "wind::current"]


def test_candidate_counts_and_parameter_bounds():
    pilot = RUN.pilot_manifest()
    search = RUN.search_manifest(PROTOCOL, "balanced")
    assert len(pilot) == 24 and len(search) == 600
    assert search.candidate_id.nunique() == 600
    assert not set(search.candidate_id) & set(pilot.candidate_id)
    specs = [json.loads(row) for row in search.spec_json]
    assert sum(x["depth"] == 8 for x in specs) == 36
    assert sum(x["m_x"] in PROTOCOL["m_x_sentinels"] for x in specs) == 60
    assert max(search.readout_dimension) <= 577
    assert {x["feature_policy"] for x in specs} == set(OLD.POLICIES)
    assert {x["m_y"] for x in specs} == set(PROTOCOL["m_y"])
    assert max(x["m_x"] for x in specs) == 672
    assert all(x["readout"] == "pure_all_layers" for x in specs)
    assert RUN.search_manifest(PROTOCOL, "balanced").equals(search)


def test_execution_identity_rejects_mutation():
    row = RUN.execution(RUN.pilot_manifest().head(1), [2026092501]).iloc[0].to_dict()
    RUN.validate_row(row)
    with pytest.raises(ValueError): RUN.validate_row(dict(row, reservoir_seed=123))
    with pytest.raises(ValueError): RUN.validate_row(dict(row, test_access_authorized=True))


@pytest.mark.parametrize("tail", ["clipped", "linear"])
def test_quantile_function_pointmass_scaling_and_monotonicity(tail):
    curves = np.full((100, 7), 3.)
    samples, audit = NEW.marginal_quantile_diagnostic(curves, np.linspace(.001, .999, 100), tail)
    assert np.all(samples == 3) and audit["selection_authorized"] is False
    curves = np.repeat(np.asarray(NEW.QUANTILES)[None, :], 100, axis=0)
    u = np.linspace(.001, .999, 100)
    values, _ = NEW.marginal_quantile_diagnostic(curves, u, tail)
    scaled, _ = NEW.marginal_quantile_diagnostic(curves * 2 + 5, u, tail)
    assert np.all(np.diff(values) >= 0)
    np.testing.assert_allclose(scaled, values * 2 + 5)


def test_two_component_mixture_not_average_conditional_quantiles():
    curves = np.r_[np.zeros((500, 7)), np.full((500, 7), 10)]
    values, _ = NEW.marginal_quantile_diagnostic(curves, np.full(1000, .5))
    assert np.mean(curves[:, -1]) == 5
    assert np.quantile(values, .9) == 10


def test_two_normal_mixture_reference_and_identical_distribution():
    levels = np.asarray(NEW.QUANTILES)
    knots = np.array([NormalDist().inv_cdf(q) for q in levels])
    n = 10000
    curves = np.tile(knots, (n, 1)); curves[n // 2:] += 10
    rng = np.random.default_rng(22)
    samples, _ = NEW.marginal_quantile_diagnostic(curves, rng.uniform(size=n), "linear")
    q90 = np.quantile(samples, .9)
    true_cdf = .5 * NormalDist().cdf(q90) + .5 * NormalDist(10, 1).cdf(q90)
    assert abs(true_cdf - .9) < .02
    assert q90 > np.mean(curves[:, -1]) + 4
    same = np.tile(knots, (n, 1))
    samples, _ = NEW.marginal_quantile_diagnostic(same, (np.arange(n) + .5) / n, "linear")
    np.testing.assert_allclose(np.quantile(samples, levels), knots, atol=.002)


def test_guarded_design_detects_binary_corruption(tmp_path):
    design = np.eye(3); response = np.ones(3)
    RUN.guarded_design(tmp_path / "design", design, response, {})
    (tmp_path / "design/X.bin").write_bytes(b"corrupted")
    with pytest.raises(RuntimeError, match="differs"): RUN.guarded_design(tmp_path / "design", design, response, {})


def test_crossing_repair_is_explicit_not_hidden():
    curves = np.array([[7, 6, 5, 4, 3, 2, 1.]])
    _, audit = NEW.marginal_quantile_diagnostic(curves, np.array([.5]))
    assert audit["crossed_curve_fraction"] == 1
    with pytest.raises(ValueError): NEW.marginal_quantile_diagnostic(curves, np.array([1.]))
    with pytest.raises(ValueError): NEW.marginal_quantile_diagnostic(curves, np.array([.5]), "unspecified")


def test_pure_model_and_capacity_fail_closed():
    with pytest.raises(ValueError): spec(readout="extended_all_layers")
    with pytest.raises(ValueError): spec(units=[200] * 4, depth=4)
    with pytest.raises(ValueError): spec(interlayer_gain=float("nan"))


def test_completed_ridge_corruption_is_not_reused(tmp_path):
    (tmp_path / "terminal.json").write_text(json.dumps(dict(status="completed_r123_ridge_cell", test_opened=False,
        fit_sha256="abc", output_sha256={"file.bin": "missing"})))
    assert not RUN.valid_ridge(tmp_path, "abc")


def test_protocol_keeps_official_windows_and_new_families_blocked():
    for key in ("official_validation_authorized", "official_test_authorized", "mcmc_authorized", "exal_authorized",
                "joint_authorized", "article_mutation_authorized", "registry_mutation_authorized"):
        assert PROTOCOL[key] is False
    assert NEW.internal_splits(940)[-1]["validation"].tolist() == list(range(766, 940))
    assert PROTOCOL["posterior_paths"] == 500


def test_recursive_diagnostic_matches_old_operator_and_cannot_read_future_prices():
    value = spec(units=[4, 4], feature_policy="target_only", m_y=96)
    data = tiny_arrays(); p = 9
    normal = dict(beta_mean=np.linspace(0, .05, p), beta_cov=np.eye(p) * .001,
                  omega_shape=10., omega_rate=.5)
    quantiles = {q: dict(beta_mean=np.linspace(q / 10, q / 10 + .05, p), beta_cov=np.eye(p) * .001)
                 for q in NEW.QUANTILES}
    old = NEW.recursive_quantile_forecast(data, value, normal, quantiles, 500, 123)
    new, interpretation = NEW.recursive_operator_diagnostic(data, value, normal, quantiles, 500, 123)
    for name in ("mean_feature", "path_specific", "normal_driver"):
        np.testing.assert_allclose(new[name], old[name], atol=1e-14)
    changed = NEW.ExplicitArrays(data.price_history, data.exog_history, data.exog_future,
        np.full_like(data.response, 1e9), data.anchors, data.exog_names, data.source_manifest)
    replay, _ = NEW.recursive_operator_diagnostic(changed, value, normal, quantiles, 500, 123)
    for name in new:
        if name != "truth": np.testing.assert_array_equal(new[name], replay[name])
    assert interpretation["selection_authorized"] is False


def test_input_clock_uses_current_exogenous_but_only_preceding_prices():
    value = spec(units=[8, 8], feature_policy="target_only", m_y=96, m_x=4)
    data = tiny_arrays()
    first = NEW.BASE.explicit_input(data, value, [0], 0, np.empty((1, 0)))
    assert first[0, 0] == data.price_history[0, -1]
    np.testing.assert_array_equal(first[0, 96:99], data.exog_future[0, 0])
    second = NEW.BASE.explicit_input(data, value, [0], 1, np.array([[12.]]))
    assert second[0, 0] == 12
    np.testing.assert_array_equal(second[0, 96:99], data.exog_future[0, 1])
    assert second[0, 1] == data.price_history[0, -1]


def test_washout_check_is_explicit_and_score_blind():
    value = spec(units=[8, 8], feature_policy="target_only", m_y=96, rho=0, alpha=1)
    audit = NEW.washout_audit(tiny_arrays(), value, [0])
    assert audit["passed"] and audit["maximum_absolute_state_difference"] == 0


def test_completed_normal_wrong_target_is_rejected_without_relaunch(tmp_path):
    root = tmp_path / "center/fits/example"
    root.mkdir(parents=True); (tmp_path / "center/contracts").mkdir()
    (root / "terminal.json").write_text(json.dumps(dict(status="completed_recursive_normal_fit", converged=True,
        test_opened=False, posterior_target_sha256="old", artifacts=[])))
    (tmp_path / "center/contracts/example.json").write_text(json.dumps(dict(posterior_target_sha256="new")))
    with pytest.raises(RuntimeError, match="target differs"): RUN.guarded_normal_valid(root)


def test_immutable_contract_rejects_changed_prior(tmp_path):
    RUN.immutable_json(tmp_path / "contract.json", {"tau0": .001})
    RUN.immutable_json(tmp_path / "contract.json", {"tau0": .001})
    with pytest.raises(RuntimeError): RUN.immutable_json(tmp_path / "contract.json", {"tau0": .002})
