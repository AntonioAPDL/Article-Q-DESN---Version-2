from __future__ import annotations

from dataclasses import replace
import hashlib
import importlib.util
from pathlib import Path
import sys
from types import SimpleNamespace

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / 'application/scripts/pricefm'
sys.path.insert(0, str(SCRIPTS))
from pricefm_r125_cdf import LEVELS, curve_support, pooled_cdf, pooled_quantiles, origin_positions, forecast_diagnostic
from pricefm_r125_comparison import matched_comparison, METHODS
from pricefm_r124_covariance import GaussianSampler, POLICY
import pricefm_r120_engine as ENGINE
import pricefm_r123_runtime as RUNTIME

loader = importlib.util.spec_from_file_location('r125_test', SCRIPTS / '446_run_pricefm_stage_r125_forecast_estimand.py')
RUN = importlib.util.module_from_spec(loader); loader.loader.exec_module(RUN)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


@pytest.mark.parametrize('tails', ['clipped', 'linear'])
def test_normalized_monotone_cdf_and_inverse(tails):
    curves = np.vstack((LEVELS, LEVELS + 2, LEVELS + 4))
    x = np.linspace(-1, 6, 401); cdf = pooled_cdf(x, curves, tails)
    assert cdf[0] == 0 and cdf[-1] == 1
    assert np.all(np.diff(cdf) >= -1e-15)
    quantiles, audit = pooled_quantiles(curves, tails)
    assert np.all(np.diff(quantiles) >= 0)
    np.testing.assert_allclose(pooled_cdf(quantiles, curves, tails), LEVELS, atol=1e-11)
    assert audit['diagnostic_only'] and not audit['distribution_identified_by_seven_quantiles']
    assert audit['maximum_inversion_bracket_width'] < 1e-11


@pytest.mark.parametrize('tails', ['clipped', 'linear'])
def test_single_curve_reproduces_knots_and_affine_units(tails):
    curves = np.array([[-2., -1., .2, .5, .8, 2., 4.]])
    q, _ = pooled_quantiles(curves, tails)
    np.testing.assert_allclose(q, curves[0], atol=1e-11)
    transformed, _ = pooled_quantiles(curves * 3 + 7, tails)
    np.testing.assert_allclose(transformed, q * 3 + 7, atol=3e-11)


@pytest.mark.parametrize('tails', ['clipped', 'linear'])
def test_degenerate_curves_and_repeated_knots_are_atoms(tails):
    curves = np.vstack((np.zeros(7), np.ones(7) * 10))
    np.testing.assert_array_equal(pooled_cdf([-1, 0, 5, 10, 11], curves, tails), [0, .5, .5, 1, 1])
    q, _ = pooled_quantiles(curves, tails)
    np.testing.assert_allclose(q, [0, 0, 0, 0, 10, 10, 10], atol=1e-11)
    repeated = np.array([[0, 0, 1, 1, 1, 2, 2.]])
    cdf = pooled_cdf([-.1, 0, .5, 1, 1.5, 2], repeated, tails)
    assert np.all(np.diff(cdf) >= 0) and cdf[-1] == 1


def test_mixture_quantiles_are_not_average_conditional_quantiles():
    curves = np.vstack((LEVELS - 4, LEVELS + 4))
    mixed, _ = pooled_quantiles(curves, 'linear')
    assert mixed[-1] > curves[:, -1].mean() + 3
    assert mixed[0] < curves[:, 0].mean() - 3


def test_tail_conventions_are_distinct_and_sort_is_explicit():
    curves = np.array([[3, 0, 1, 2, 4, 5, 6.]])
    knots, levels = curve_support(curves, 'clipped')
    np.testing.assert_array_equal(knots[0], np.arange(7))
    np.testing.assert_array_equal(levels, LEVELS)
    assert pooled_cdf([-.1], curves, 'clipped')[0] == 0
    assert pooled_cdf([-.1], curves, 'linear')[0] > 0
    _, audit = pooled_quantiles(curves, 'linear')
    assert audit['crossed_draw_curve_fraction'] == 1
    assert audit['crossing_treatment'] == 'explicit_unweighted_knot_sort'
    assert not audit['uses_AL_working_density']


@pytest.mark.parametrize('tails', ['clipped', 'linear'])
def test_exact_pool_agrees_with_direct_inverse_quantile_sampling(tails):
    rng = np.random.default_rng(87)
    curves = np.vstack((LEVELS * 2, LEVELS + 3, LEVELS * 3 - 4))
    knots, probabilities = curve_support(curves, tails)
    sample = np.concatenate([np.interp(rng.uniform(size=50000), probabilities, k) for k in knots])
    exact, _ = pooled_quantiles(curves, tails)
    np.testing.assert_allclose(np.quantile(sample, LEVELS), exact, atol=.035)


@pytest.mark.parametrize('curves,tails', [(np.zeros(7), 'linear'), (np.zeros((0, 7)), 'clipped'),
    (np.zeros((2, 6)), 'linear'), (np.full((1, 7), np.nan), 'linear'), (np.zeros((1, 7)), 'unknown')])
def test_invalid_curves_fail_closed(curves, tails):
    with pytest.raises(ValueError): pooled_quantiles(curves, tails)


@pytest.mark.parametrize('levels,iterations', [([0], 44), ([1], 44), ([np.nan], 44), ([[.5]], 44), ([.5], 19), ([.5], 61)])
def test_invalid_inverse_requests(levels, iterations):
    with pytest.raises(ValueError): pooled_quantiles(np.zeros((1, 7)), 'linear', levels, iterations)


@pytest.mark.parametrize('count', [125, 135, 174])
def test_origins_are_predeclared_and_cover_complete_support(count):
    positions = origin_positions(count)
    np.testing.assert_array_equal(positions, np.linspace(0, count - 1, 12, dtype=int))
    assert positions[0] == 0 and positions[-1] == count - 1 and len(set(positions)) == 12


@pytest.mark.parametrize('count,requested', [(11, 12), (100, 13), (100, 1)])
def test_origin_budget_is_bounded(count, requested):
    with pytest.raises(ValueError): origin_positions(count, requested)


def tiny_arrays():
    rng = np.random.default_rng(3); n = 1
    window = dict(X_lag=rng.normal(size=(n, RUNTIME.BASE.SOURCE_WINDOW, 4)),
        X_lead=rng.normal(size=(n, 96, 3)), Y=rng.normal(size=(n, 96)), anchors=np.array(['a']),
        lag_cols=['BG-price', 'BG-load', 'BG-solar', 'BG-wind'],
        lead_cols=['BG-load', 'BG-solar', 'BG-wind'], path='/BG', sha256='test',
        manifest_path='/BG.json', manifest_sha256='test')
    spec = RUNTIME.normalize_spec(dict(region='BG', feature_policy='target_only', calendar='none',
        readout='pure_all_layers', m_y=3, m_x=2, units=[4, 3], alpha=.5, rho=.8,
        input_scale=.15, input_fan_in=2, recurrent_sparsity=.5, seed=17))
    return RUNTIME.explicit_arrays({'BG': window}, spec), spec


@pytest.fixture(scope='module')
def toy_forecast():
    arrays, spec = tiny_arrays(); p = 8
    mean = np.zeros(p); mean[0] = .1; cov = np.eye(p) * .001
    normal = dict(beta_mean=mean, beta_cov=cov, omega_shape=5., omega_rate=.5)
    quantiles = {float(q): dict(beta_mean=mean + q / 10, beta_cov=cov) for q in LEVELS}
    values, audit = forecast_diagnostic(RUNTIME, arrays, spec, normal, quantiles, [7], 4, GaussianSampler())
    return arrays, spec, normal, quantiles, values, audit


def test_causal_forecasts_ignore_future_truth_and_oracle_is_separate(toy_forecast):
    arrays, spec, normal, quantiles, values, audit = toy_forecast
    poisoned = replace(arrays, response=arrays.response + 1000)
    other, _ = forecast_diagnostic(RUNTIME, poisoned, spec, normal, quantiles, [7], 4, GaussianSampler())
    for operator in RUN.OPERATORS:
        if not operator.startswith('oracle_'):
            np.testing.assert_array_equal(other[operator], values[operator])
    assert not np.array_equal(other['oracle_mean_feature'], values['oracle_mean_feature'])
    assert audit['model_refitted'] is False and audit['oracle_diagnostic_only']
    assert audit['sigma_posterior_used_for_quantile_pooling'] is False
    assert quantiles[.5]['beta_cov'][0, 0] == .001


def test_controls_match_original_engine_at_original_seed_position(toy_forecast, monkeypatch):
    arrays, spec, normal, quantiles, values, _ = toy_forecast
    engine = RUNTIME.BASE
    original_seed = engine.deterministic_seed
    def mapped_seed(*args):
        if len(args) > 1 and args[1] == 'innovation':
            args = (*args[:2], 7, *args[3:])
        return original_seed(*args)
    monkeypatch.setattr(engine, 'deterministic_seed', mapped_seed)
    monkeypatch.setattr(engine, '_draw_gaussian', GaussianSampler())
    reference = engine.recursive_quantile_forecast(arrays, spec, normal, quantiles, 500, 4)
    for operator in ('mean_feature', 'path_specific', 'normal_driver'):
        np.testing.assert_allclose(values[operator], reference[operator], atol=1e-12, rtol=1e-12)


def jobs():
    return [dict(tag=RUN.TAG, job_id=f'{candidate}_s{split}', candidate_id=candidate, split=split,
        tau0=1e-4, posterior_paths=500, sampler=POLICY, official_test_opened=False,
        official_validation_opened=False, fitting_authorized=False, diagnostic_only=True,
        oracle_publishable=False, complete_origin_count={1:125, 2:135, 3:174}[split],
        origin_positions=origin_positions({1:125, 2:135, 3:174}[split]).tolist(), operators=list(RUN.OPERATORS))
        for candidate in RUN.read(RUN.PROTOCOL)['candidates'] for split in (1, 2, 3)]


def test_protocol_and_manifest_firewall():
    protocol = RUN.read(RUN.PROTOCOL); RUN.protocol_valid(protocol); RUN.validate_jobs(jobs())
    for field in ('fitting_authorized', 'official_test_authorized', 'all_region_launch_authorized'):
        with pytest.raises(ValueError): RUN.protocol_valid(dict(protocol, **{field: True}))


@pytest.mark.parametrize('field,value', [('origin_positions', list(range(12))), ('operators', ['mean_feature']),
    ('diagnostic_only', False), ('oracle_publishable', True), ('posterior_paths', 100), ('fitting_authorized', True)])
def test_job_drift_rejected(field, value):
    current = jobs(); current[0][field] = value
    with pytest.raises(ValueError): RUN.validate_jobs(current)


@pytest.mark.parametrize('smoke', [False, True])
def test_atomic_cell_metadata_and_hash_verified_reuse(tmp_path, monkeypatch, smoke):
    job = dict(jobs()[0], input_sha256={}, fit_labels=[], output_dir=str(tmp_path / 'cells/one'))
    config = tmp_path / 'job.json'; RUN.write(config, job)
    args = SimpleNamespace(output=tmp_path, config=config)
    m = SimpleNamespace(REC=SimpleNamespace(digest=digest, verify_evidence=lambda v: None))
    prep = dict(configurations={str(config): digest(config)}, source={'head': 'test'})
    monkeypatch.setattr(RUN.V, 'owner', lambda a: (m, {}))
    monkeypatch.setattr(RUN.V, 'verify_preparation', lambda a, b: (prep, [job]))
    calls = []
    def forecast(owner, control, value, maximum_origins, observe):
        calls.append(maximum_origins); n = 2 if smoke else 12
        predictions = dict(truth=np.zeros((n, 96)), **{name: np.zeros((n, 96, 7)) for name in RUN.OPERATORS})
        return predictions, {}, dict(posterior_paths=500, scored_origins=n, operators=list(RUN.OPERATORS),
            diagnostic_only=True, oracle_publishable=False, sampler_audit=[{}] * 8)
    monkeypatch.setattr(RUN, 'forecast', forecast)
    first = RUN.cell(args, smoke=smoke); second = RUN.cell(args, smoke=smoke)
    assert first == second and calls == ([2] if smoke else [None])
    assert first['posterior_paths'] == 500 and first['model_refits'] == 0
    output = tmp_path / 'smoke' / job['job_id'] if smoke else Path(job['output_dir'])
    (output / 'metrics.json').write_text('tampered')
    with pytest.raises(RuntimeError, match='hash'): RUN.verified_cell(output, job, digest, smoke=smoke)


def test_partial_output_is_never_overwritten(tmp_path):
    (tmp_path / 'partial').mkdir()
    with pytest.raises(RuntimeError, match='partial'): RUN.verified_cell(tmp_path / 'partial', jobs()[0], digest)


def comparison_records():
    records = []
    for fold in (1, 2, 3):
        for method in METHODS:
            records.append(dict(region='BG', fold=fold, method=method, split='test', units='EUR/MWh',
                horizon_steps=96, step_minutes=15, quantiles=LEVELS, origin_utc=['2025-01-01T00:00:00Z'],
                truth=np.zeros((1, 96)), prediction=np.full((1, 96, 7), {'candidate':1., 'current_authority':2., 'pricefm':.5}[method]),
                specification_sha256='a' * 64, selection_uses_test=False, operator_frozen_before_scoring=True,
                oracle_inputs=False, full_training_fit=True))
    return records


def test_matched_comparison_is_cohort_mean_not_per_case_dual_gate():
    records = comparison_records(); records[0]['prediction'] = np.full((1, 96, 7), 3.)
    result = matched_comparison(records, ['BG'], {'BG':'a' * 64})
    assert result['candidate_mean_better_than_authority']
    assert not result['candidate_mean_better_than_pricefm']
    assert not result['promotion_authorized'] and not result['all_region_launch_authorized']
    assert result['mean_AQL']['candidate'] == pytest.approx(5 / 6)


@pytest.mark.parametrize('field,value', [('units','scaled'), ('split','val'), ('horizon_steps',24),
    ('step_minutes',60), ('quantiles',[.1,.2,.3,.5,.7,.8,.9]), ('origin_utc',['different']),
    ('truth',np.ones((1,96))), ('prediction',np.zeros((1,96,6))), ('specification_sha256','b'*64),
    ('selection_uses_test',True), ('operator_frozen_before_scoring',False), ('oracle_inputs',True), ('full_training_fit',False)])
def test_mismatched_comparison_is_rejected(field, value):
    records = comparison_records(); records[0][field] = value
    with pytest.raises(ValueError): matched_comparison(records, ['BG'], {'BG':'a'*64})


def test_comparison_requires_complete_unique_frozen_cohort():
    records = comparison_records()
    for bad in (records[:-1], records + [records[0]], []):
        with pytest.raises(ValueError): matched_comparison(bad, ['BG'], {'BG':'a'*64})
    for regions, hashes in (([], {}), (['BG','BG'], {'BG':'a'*64}), (['BG'], {'BG':'bad'})):
        with pytest.raises(ValueError): matched_comparison(records, regions, hashes)


def test_r125_source_hash_contract_covers_comparison_and_diagnostics():
    source = Path(RUN.__file__).read_text()
    assert "HERE / 'pricefm_r125_comparison.py'" in source
    assert 'UNRESOLVED_NO_MATCHED_NEW_OFFICIAL_FORECASTS' in source
    assert 'background_full_fit_auto_launch=False' in source
    assert not RUN.read(RUN.PROTOCOL)['all_region_launch_authorized']
