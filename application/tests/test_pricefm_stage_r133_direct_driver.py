import importlib.util
import json
import os
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'application/scripts/pricefm/pricefm_r133_direct_driver.py'
RUNNER = ROOT / 'application/scripts/pricefm/463_run_pricefm_stage_r133_direct_driver.py'
CONFIG = ROOT / 'application/config/pricefm_stage_r133_direct_multihorizon_driver_20261011.json'

spec = importlib.util.spec_from_file_location('pricefm_r133_direct_driver_tested', SCRIPT)
M = importlib.util.module_from_spec(spec); spec.loader.exec_module(M)


def protocol():
    return json.loads(CONFIG.read_text())


def packet(seed=1, n=8, exog=3):
    rng = np.random.default_rng(seed)
    mean = rng.normal(size=(n, 96)); sd = rng.uniform(.3, 1.2, size=(n, 96))
    offsets = np.array([-1.2, -.6, -.1, 0, .1, .6, 1.2])
    prediction = mean[..., None] + sd[..., None] * offsets
    truth = mean + .15 * np.sin(np.arange(96)[None, :] / 8) + rng.normal(scale=.1, size=(n, 96))
    return dict(truth=truth, driver_mean=mean, driver_sd=sd, prediction=prediction,
        anchor_clock=np.arange(n) * 7 % 96, history_lags=rng.normal(size=(n, 5)),
        exog_future=rng.normal(size=(n, 96, exog)))


def test_protocol_is_exact_and_bounded():
    value = protocol(); M.validate_protocol(value)
    assert value['regions'] == ['HR', 'DK_1']
    assert value['maximum_workers'] == 30
    assert value['paths'] == 500 and value['horizon_steps'] == 96
    assert value['first_horizon_replay_tolerance_EUR_MWh'] == 5e-8
    assert not value['promotion_authorized'] and not value['all_region_launch_authorized']


@pytest.mark.parametrize('key', M.FORBIDDEN)
def test_forbidden_expansion_fails_closed(key):
    value = protocol(); value[key] = True
    with pytest.raises(ValueError): M.validate_protocol(value)


def test_candidate_surface_is_frozen():
    assert M.FAMILIES == ('identity', 'compact_location', 'compact_location_scale',
        'known_exog_location', 'known_exog_location_scale')
    assert protocol()['ridge_penalties'] == [.1, 1., 10., 100.]


def test_feature_geometry_and_exogenous_increment():
    value = packet()
    compact = M.feature_matrix(value, 'compact_location')
    expanded = M.feature_matrix(value, 'known_exog_location')
    assert compact.shape[0] == len(value['truth']) * 96
    assert expanded.shape[1] == compact.shape[1] + value['exog_future'].shape[-1]


def test_truth_is_not_a_predictor():
    first = packet(); second = {key: value.copy() for key, value in first.items()}
    second['truth'] += 1e6
    np.testing.assert_array_equal(M.feature_matrix(first, 'known_exog_location'),
                                  M.feature_matrix(second, 'known_exog_location'))


def test_augment_uses_history_and_known_exog_only():
    p = packet(); arrays = SimpleNamespace(response=p['truth'].copy(),
        price_history=np.arange(len(p['truth']) * 800, dtype=float).reshape(len(p['truth']), 800),
        exog_future=p['exog_future'].copy())
    base = {key: p[key] for key in ('truth', 'driver_mean', 'driver_sd', 'prediction', 'anchor_clock')}
    answer = M.augment_packet(arrays, base)
    arrays.response[:] = -999
    second = M.augment_packet(arrays, base)
    np.testing.assert_array_equal(answer['history_lags'], second['history_lags'])
    np.testing.assert_array_equal(answer['exog_future'], second['exog_future'])


@pytest.mark.parametrize('family', M.FAMILIES)
def test_map_fit_is_finite_and_declared(family):
    value = packet(); penalty = None if family == 'identity' else 1.
    fit = M.fit_direct_map([value], family, penalty, protocol(), [1])
    assert fit['family'] == family
    assert np.isfinite(np.asarray(fit['scale'])).all()
    if family != 'identity':
        assert len(fit['beta']) == fit['feature_dimension'] + 1


def test_identity_is_exact():
    value = packet(); fit = M.fit_direct_map([value], 'identity', None, protocol(), [1])
    np.testing.assert_array_equal(M.direct_quantiles(value, fit), value['prediction'])
    paths = np.repeat(value['driver_mean'][..., None], 5, axis=2)
    np.testing.assert_array_equal(M.direct_paths(value, paths, fit), paths)


def test_direct_path_is_decoupled_affine_transform():
    value = packet(); fit = M.fit_direct_map([value], 'compact_location_scale', 1., protocol(), [1])
    offsets = np.linspace(-1, 1, 11)
    paths = value['driver_mean'][..., None] + value['driver_sd'][..., None] * offsets
    transformed = M.direct_paths(value, paths, fit)
    np.testing.assert_allclose(transformed.mean(axis=2), M.direct_location(value, fit), atol=1e-12)
    assert not np.shares_memory(paths, transformed)


def _rows(candidate_scores):
    rows = []
    for candidate, scores in candidate_scores.items():
        family = 'identity' if candidate == 'identity' else 'compact_location'
        for split, score in zip((2, 3), scores):
            rows.append(dict(candidate_id=candidate, split=split, AQL=score, family=family,
                ridge_penalty=np.nan if candidate == 'identity' else 1.,
                feature_dimension=0 if candidate == 'identity' else 20,
                scale_enabled=False))
    return rows


def test_selection_accepts_only_forward_transfer():
    decision = M.select_candidate(_rows({'identity': (10., 10.), 'good': (9.8, 9.8)}), protocol())
    assert decision['selected'] == 'good'


def test_selection_rejects_single_split_harm():
    decision = M.select_candidate(_rows({'identity': (10., 10.), 'unstable': (8., 10.1)}), protocol())
    assert decision['selected'] == 'identity'


def test_selection_rejects_subthreshold_gain():
    decision = M.select_candidate(_rows({'identity': (10., 10.), 'tiny': (9.95, 9.95)}), protocol())
    assert decision['selected'] == 'identity'


def test_selection_is_strict_json_serializable():
    decision = M.select_candidate(_rows({'identity': (10., 10.), 'good': (9., 9.)}), protocol())
    assert json.dumps(decision, allow_nan=False)
    identity = next(row for row in decision['ranking'] if row['candidate_id'] == 'identity')
    assert identity['ridge_penalty'] is None


def test_runner_orders_baseline_before_direct_receiver():
    text = SCRIPT.read_text()
    assert text.index("baseline = np.empty") < text.index("corrected = direct_paths")
    assert text.index("corrected = direct_paths") < text.index("output = np.empty")
    assert 'baseline_generator_feedback=False' in text


def test_runner_enforces_first_horizon_identity_and_source_gate():
    text = RUNNER.read_text()
    assert "first > tolerance" in text
    assert "work/pricefm-r133-" in text
    assert "official_test_reforecast=False" in text
    assert "normal_or_quantile_refits=0" in text
    assert "release retry namespace exhausted" in text


def test_paths_are_runtime_excluded():
    ignore = (ROOT / '.gitignore').read_text()
    assert 'application/data_local/' in ignore
    assert 'local_trackers/' in ignore


def test_note_declares_nonpromotion_boundary():
    note = (ROOT / 'application/notes/pricefm_stage_r133_direct_multihorizon_driver_20261011.md').read_text()
    assert 'no all-region launch' in note
    assert 'excluded from fitting and selection' in note
