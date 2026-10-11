from dataclasses import replace
import json
import os
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'application/scripts/pricefm'
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(Path(os.environ['PRICEFM_R132_DEPENDENCY']) / 'application/scripts/pricefm'))

import pricefm_r123_runtime as RT
from pricefm_r132_calibration import (CANDIDATES, FORBIDDEN, validate_protocol,
    fit_calibration, calibration_terms, apply_calibration, normal_driver_paths,
    select_candidate, calibrated_receiver_replay, plot_report)


@pytest.fixture
def protocol():
    return json.loads((ROOT / 'application/config/pricefm_stage_r132_stochastic_driver_calibration_20261011.json').read_text())


@pytest.fixture(scope='module')
def toy():
    rng = np.random.default_rng(132); n = 2; lag = 3120
    arrays = RT.ExplicitArrays(rng.normal(size=(n, lag)), rng.normal(size=(n, lag, 3)),
        rng.normal(size=(n, 96, 3)), rng.normal(size=(n, 96)),
        np.array([v.isoformat() for v in pd.date_range('2024-01-01', periods=n, freq='D', tz='UTC')]),
        ('load', 'solar', 'wind'), ())
    spec = RT.normalize_spec(dict(region='BG', feature_policy='target_only', calendar='none',
        readout='pure_all_layers', m_y=3, m_x=2, units=[4, 3], alpha=.5, rho=.8,
        input_scale=.15, input_fan_in=2, recurrent_sparsity=.5, seed=17))
    mean = np.arange(8) * .01; covariance = np.eye(8) * .001
    normal = dict(beta_mean=mean, beta_cov=covariance, omega_shape=5., omega_rate=.5)
    quantiles = {float(q): dict(beta_mean=mean + q / 10, beta_cov=covariance)
                 for q in (.1, .25, .45, .5, .55, .75, .9)}
    identity = dict(mode='identity', global_bias=0., hour_effect=[0.] * 24,
        lead_block_effect=[0.] * 4, lead_block_scale=[1.] * 4,
        training_splits=[], observations=0, units='EUR/MWh',
        estimated_from_internal_driver_residuals_only=True)
    return arrays, spec, normal, quantiles, identity


@pytest.mark.parametrize('key', FORBIDDEN)
def test_forbidden_scope_fails_closed(protocol, key):
    protocol[key] = True
    with pytest.raises(ValueError): validate_protocol(protocol)


@pytest.mark.parametrize('key,value', [('paths', 100), ('horizon_steps', 95),
    ('maximum_workers', 31), ('forward_evaluation_splits', [1, 2, 3]),
    ('scale_bounds', [.1, 9.]), ('calibration_candidates', ['identity'])])
def test_frozen_geometry_rejected(protocol, key, value):
    protocol[key] = value
    with pytest.raises(ValueError): validate_protocol(protocol)


def packet(offset=0., scale=1.):
    n = 8; mean = np.zeros((n, 96)); sd = np.ones((n, 96)) * scale
    clock = np.arange(n) * 12 % 96
    lead = np.arange(96)[None, :]
    truth = mean + offset + .1 * np.sin(2 * np.pi * (clock[:, None] + lead) / 96)
    return dict(truth=truth, driver_mean=mean, driver_sd=sd, anchor_clock=clock)


def test_identity_map_is_exact_and_prior_free(protocol):
    value = fit_calibration([packet(3.)], 'identity', protocol, [1])
    assert value['global_bias'] == 0 and value['lead_block_scale'] == [1.] * 4
    x = np.array([1., 3., 9.])
    np.testing.assert_array_equal(apply_calibration(x, value, 0, 0), x)
    assert value['training_splits'] == [1]


def test_location_and_scale_are_shrunken_finite_and_bounded(protocol):
    location = fit_calibration([packet(4.)], 'location', protocol, [1])
    scale = fit_calibration([packet(4., .1)], 'location_scale', protocol, [1])
    assert location['global_bias'] == pytest.approx(4., abs=.02)
    assert np.isfinite(location['hour_effect']).all()
    assert all(protocol['scale_bounds'][0] <= v <= protocol['scale_bounds'][1]
               for v in scale['lead_block_scale'])
    bias, multiplier = calibration_terms(scale, 95, 95)
    assert np.isfinite(bias) and np.isfinite(multiplier)


def surface(identity=10., location=(9., 9.1), scale=(10.2, 9.9), combined=(9.5, 9.6)):
    values = dict(identity=(identity, identity), location=location, scale=scale,
        location_scale=combined)
    return [dict(candidate=candidate, split=split, AQL=values[candidate][split - 2])
            for candidate in CANDIDATES for split in (2, 3)]


def test_forward_selection_uses_complete_surface_and_gate(protocol):
    answer = select_candidate(surface(), protocol)
    assert answer['selected'] == 'location'
    assert answer['selection_uses_only_forward_internal_splits']
    answer = select_candidate(surface(location=(9., 10.2), scale=(10.2, 10.1),
        combined=(10.3, 10.2)), protocol)
    assert answer['selected'] == 'identity'
    with pytest.raises(ValueError): select_candidate(surface()[:-1], protocol)


def test_normal_driver_ignores_future_truth_and_is_chunk_invariant(toy):
    arrays, spec, normal, _, identity = toy
    first, audit = normal_driver_paths(RT, arrays, spec, normal, [7, 11], 19, identity)
    poisoned, _ = normal_driver_paths(RT, replace(arrays, response=np.full_like(arrays.response, 1e20)),
        spec, normal, [7, 11], 19, identity)
    for key in ('prediction', 'driver_mean', 'driver_sd'):
        np.testing.assert_array_equal(first[key], poisoned[key])
    chunks = [normal_driver_paths(RT, RT.subset_arrays(arrays, [i]), spec, normal, [p], 19,
        identity)[0] for i, p in enumerate((7, 11))]
    for key in ('prediction', 'driver_mean', 'driver_sd'):
        np.testing.assert_array_equal(first[key], np.concatenate([v[key] for v in chunks]))
    assert audit['future_target_access'] is False and audit['parameters_fixed_within_path']


def test_receiver_calibration_changes_recursion_only_after_first_step(toy):
    arrays, spec, normal, quantiles, identity = toy
    location = dict(identity, mode='location', global_bias=2.)
    first, _ = calibrated_receiver_replay(RT, arrays, spec, quantiles, normal,
        [7, 11], 23, identity, 1.)
    second, audit = calibrated_receiver_replay(RT, arrays, spec, quantiles, normal,
        [7, 11], 23, location, 1.)
    np.testing.assert_array_equal(first['calibrated'][:, 0], second['calibrated'][:, 0])
    assert not np.allclose(first['calibrated'][:, 1:], second['calibrated'][:, 1:])
    assert audit['future_target_access'] is False and not audit['receiver_fit_changed']


def test_receiver_replay_ignores_future_truth(toy):
    arrays, spec, normal, quantiles, identity = toy
    first, _ = calibrated_receiver_replay(RT, arrays, spec, quantiles, normal,
        [7, 11], 29, identity, 1.)
    second, _ = calibrated_receiver_replay(RT,
        replace(arrays, response=np.full_like(arrays.response, -1e20)), spec,
        quantiles, normal, [7, 11], 29, identity, 1.)
    np.testing.assert_array_equal(first['calibrated'], second['calibrated'])


def test_report_renders(tmp_path):
    internal = pd.DataFrame([dict(region=r, split=s, candidate=c, AQL=8 + .1 * i,
        median_MAE=10., coverage_80=.75, width_80=30.)
        for r in ('HR', 'DK_1') for s in (2, 3) for i, c in enumerate(CANDIDATES)])
    heldout = pd.DataFrame([dict(region=r, fold=f, offset_steps=o, operator=m,
        AQL=8. if m == 'stochastic' else 7.8, median_MAE=10., coverage_80=.75, width_80=30.)
        for r in ('HR', 'DK_1') for f in (1, 2, 3) for o in (0, 24, 48, 72)
        for m in ('stochastic', 'calibrated')])
    driver = pd.DataFrame([dict(region=r, fold=f, operator=m, lead_step=h,
        bias=0., MAE=10 + h / 96, RMSE=12.) for r in ('HR', 'DK_1') for f in (1, 2, 3)
        for m in ('stochastic', 'calibrated') for h in range(1, 97)])
    decisions = {r: dict(selected='location') for r in ('HR', 'DK_1')}
    path = tmp_path / 'report.pdf'; plot_report(path, internal, heldout, driver, decisions)
    assert path.stat().st_size > 10000 and path.read_bytes().startswith(b'%PDF-')


def test_source_declares_no_fit_or_promotion(protocol):
    validate_protocol(protocol)
    script = (HERE / '462_run_pricefm_stage_r132_calibration.py').read_text()
    assert 'new_fits=0' in script and 'official_test_reforecast=False' in script
    assert 'exalStaticLDVB(' not in script and 'run_r(' not in script
    assert 'git push' not in script and 'git merge' not in script
    assert "r128_out / 'blocked.json'" in script
    assert "r128_out / 'terminal.json'" not in script
    assert protocol['selection_uses_r130_or_r131'] is False
    assert protocol['oracle_used_for_calibration'] is False
