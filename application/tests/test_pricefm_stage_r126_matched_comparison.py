from __future__ import annotations

from dataclasses import replace
import importlib.util
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / 'application/scripts/pricefm'
sys.path.insert(0, str(SCRIPTS))
from pricefm_r126_contract import (choose, digest, immutable, read, seal, verified,
    market_ns, official_origins, training_origins, loss, inverse_price, transform, training_valid, LEVELS, OPERATORS)
from pricefm_r126_compare import long_prediction
from pricefm_r126_replay import forecast
from pricefm_r125_cdf import forecast_diagnostic
from pricefm_r124_covariance import GaussianSampler
import pricefm_r123_runtime as RT

PROTOCOL = read(ROOT / 'application/config/pricefm_stage_r126_matched_comparison_protocol_20261007.json')


@pytest.mark.parametrize('fold,count', [(1, 120), (2, 123), (3, 122)])
def test_official_clock_and_half_open_support(fold, count):
    origins = official_origins(PROTOCOL, fold)
    assert len(origins) == count
    assert origins[-1] < pd.Timestamp(PROTOCOL['test_intervals_market'][fold - 1][1], tz='UTC')
    assert np.all(np.diff(market_ns(origins)) == 24 * 3600 * 10**9)
    physical = origins - pd.Timedelta(hours=1)
    np.testing.assert_array_equal(market_ns(origins) - market_ns(physical), np.full(count, 3600 * 10**9))


def test_timestamp_precision_is_normalized():
    idx = pd.date_range('2025-01-01', periods=3, tz='UTC', freq='D')
    np.testing.assert_array_equal(market_ns(idx.as_unit('us')), market_ns(idx.as_unit('ns')))


def test_two_stage_scaler_inversion():
    x = np.arange(5.)
    np.testing.assert_array_equal(inverse_price(x, dict(price_scale=3, price_mean=2),
                                              dict(y_scale=7, y_center=10)), (3 * x + 2) * 7 + 10)


def test_metric_has_no_extra_factor_and_requires_H96():
    y = np.ones((2, 96)); p = np.zeros((2, 96, 7))
    assert loss(y, p).mean() == pytest.approx(LEVELS.mean())
    with pytest.raises(ValueError): loss(y[:, :95], p[:, :95])
    with pytest.raises(ValueError): loss(y, p[:, :, :6])
    p[0, 0, 0] = np.nan
    with pytest.raises(ValueError): loss(y, p)


def cells():
    return [dict(candidate_id=c, split=s, origins=[125, 135, 174][s - 1],
        AQL=.1 if c == PROTOCOL['diagnostic_candidates'][0] else .2 + .01 * s,
        formal_certified=c in PROTOCOL['eligible_candidates'])
        for c in PROTOCOL['eligible_candidates'] + PROTOCOL['diagnostic_candidates'] for s in (1, 2, 3)]


def test_uncertified_low_score_cannot_determine_deployment():
    winner, scores = choose(cells(), PROTOCOL)
    assert winner in PROTOCOL['eligible_candidates']
    assert scores[PROTOCOL['diagnostic_candidates'][0]] < scores[winner]


@pytest.mark.parametrize('problem', ['missing', 'duplicate', 'uncertified', 'nonfinite'])
def test_selection_fails_closed(problem):
    rows = cells()
    if problem == 'missing': rows.pop()
    if problem == 'duplicate': rows.append(rows[0])
    if problem == 'uncertified': rows[0]['formal_certified'] = False
    if problem == 'nonfinite': rows[0]['AQL'] = np.nan
    with pytest.raises(ValueError): choose(rows, PROTOCOL)


def test_split_equal_mean_not_origin_weighted():
    rows = cells(); c = PROTOCOL['eligible_candidates'][0]
    for row in rows:
        if row['candidate_id'] == c: row['AQL'] = row['split']
    _, scores = choose(rows, PROTOCOL)
    assert scores[c] == 2


def valid_training():
    return dict(fold=1, train_end_market='2024-09-01',
        first_origin_market=PROTOCOL['new_model_first_train_origin_market'],
        full_training_window=True, test_opened=False, raw_sha256=PROTOCOL['raw_sha256'],
        response_sha256='a' * 64, scaler_sha256='b' * 64)


@pytest.mark.parametrize('key,value', [('fold', 2), ('train_end_market', '2025-01-01'),
    ('full_training_window', False), ('test_opened', True), ('raw_sha256', 'c' * 64),
    ('response_sha256', 'missing'), ('scaler_sha256', 'missing'),
    ('first_origin_market', '2022-01-04T00:00:00+00:00')])
def test_partial_fit_or_wrong_training_identity_rejected(key, value):
    contract = valid_training(); contract[key] = value
    with pytest.raises(ValueError): training_valid(contract, PROTOCOL, 1)


def test_training_contract_accepts_complete_identity():
    assert training_valid(valid_training(), PROTOCOL, 1)['full_training_window']


def test_immutable_files_and_sealed_artifacts(tmp_path):
    folder = tmp_path / 'cell'; folder.mkdir()
    immutable(folder / 'value.json', {'v': 1}); immutable(folder / 'value.json', {'v': 1})
    with pytest.raises(RuntimeError): immutable(folder / 'value.json', {'v': 2})
    seal(folder, {'done': True}); assert verified(folder)['done']
    (folder / 'value.json').write_text('{}')
    with pytest.raises(RuntimeError): verified(folder)


def test_reference_rows_complete_no_duplicates():
    frame = pd.DataFrame([dict(origin_id=0, horizon=h, tau=q, pred=h + q)
                          for h in range(1, 97) for q in LEVELS])
    assert long_prediction(frame, 1, 'pred').shape == (1, 96, 7)
    with pytest.raises(ValueError): long_prediction(frame.iloc[:-1], 1, 'pred')
    with pytest.raises(ValueError): long_prediction(pd.concat([frame, frame.iloc[:1]]), 1, 'pred')


@pytest.fixture(scope='module')
def toy():
    rng = np.random.default_rng(6)
    window = dict(X_lag=rng.normal(size=(2, 3120, 4)), X_lead=rng.normal(size=(2, 96, 3)),
        Y=rng.normal(size=(2, 96)), anchors=np.array(['a', 'b']),
        lag_cols=['BG-price', 'BG-load', 'BG-solar', 'BG-wind'],
        lead_cols=['BG-load', 'BG-solar', 'BG-wind'], path='/BG', sha256='toy',
        manifest_path='/BG.json', manifest_sha256='toy')
    spec = RT.normalize_spec(dict(region='BG', feature_policy='target_only', calendar='none',
        readout='pure_all_layers', m_y=3, m_x=2, units=[4, 3], alpha=.5, rho=.8,
        input_scale=.15, input_fan_in=2, recurrent_sparsity=.5, seed=17))
    arrays = RT.explicit_arrays({'BG': window}, spec); p = 8
    mean = np.zeros(p); mean[0] = .1; cov = np.eye(p) * .001
    normal = dict(beta_mean=mean, beta_cov=cov, omega_shape=5., omega_rate=.5)
    qs = {float(q): dict(beta_mean=mean + q / 10, beta_cov=cov) for q in LEVELS}
    values, audit = forecast(RT, arrays, spec, normal, qs, [7, 13], 4)
    return arrays, spec, normal, qs, values


def test_causal_replay_matches_R125_and_chunking(toy):
    arrays, spec, normal, qs, values = toy
    original, _ = forecast_diagnostic(RT, arrays, spec, normal, qs, [7, 13], 4, GaussianSampler())
    for key in OPERATORS: np.testing.assert_array_equal(values[key], original[key])
    chunk, _ = forecast(RT, RT.subset_arrays(arrays, [1]), spec, normal, qs, [13], 4)
    for key in OPERATORS: np.testing.assert_array_equal(values[key][1:], chunk[key])


def test_future_truth_poison_does_not_change_any_forecast(toy):
    arrays, spec, normal, qs, values = toy
    changed, _ = forecast(RT, replace(arrays, response=arrays.response + 1e6), spec, normal, qs, [7, 13], 4)
    for key in OPERATORS: np.testing.assert_array_equal(values[key], changed[key])


def test_same_training_transform_applies_to_forecast_arrays(toy):
    arrays = toy[0]
    scaler = dict(price_mean=2, price_scale=3, exog_mean=[1, 2, 3], exog_scale=[4, 5, 6])
    result = transform(arrays, scaler, RT.BASE.ExplicitArrays)
    np.testing.assert_allclose(result.price_history, (arrays.price_history - 2) / 3)
    np.testing.assert_allclose(result.exog_future, (arrays.exog_future - [1, 2, 3]) / [4, 5, 6])


def test_protocol_excludes_unauthorized_campaigns_and_promotions():
    for key in ('mcmc_authorized', 'joint_authorized', 'exal_authorized', 'oracle_authorized',
                'promotion_authorized', 'all_region_launch_authorized', 'new_screening_authorized',
                'registry_mutation_authorized', 'article_mutation_authorized', 'selection_uses_test'):
        assert PROTOCOL[key] is False
    assert PROTOCOL['workers'] == 15 and PROTOCOL['posterior_paths'] == 500


def test_AL_runner_fixed_prior_and_public_API():
    code = (SCRIPTS / '448_fit_pricefm_stage_r126_al.R').read_text()
    assert 'r67_fit_quantile(' in code and 'r67_assert_cran_package(' in code
    assert 'prior_sigma = list(a = 1, b = 1)' in code
    assert 'init = list(beta = beta0, sigma = sigma0)' in code
    assert 'freeze_tau_iters = 0L' in code
    assert "saveRDS(fit" in code and "!dir.exists(c$output_dir)" in code
    assert 'unlink(output' not in code


def test_muscat_comparison_is_automatic_and_not_promotion():
    code = (SCRIPTS / '449_closeout_pricefm_stage_r126_matched_comparison.py').read_text()
    assert 'wait_and_compare' in code and "filter='data'" in code
    assert 'git merge' not in code and 'git push' not in code


def test_complete_fold_training_counts_are_not_internal_splits():
    counts = [len(training_origins(PROTOCOL, fold)) for fold in (1, 2, 3)]
    assert counts == [940, 1062, 1182]


def test_missing_origin_partition_reuses_exact_R125_subset():
    from pricefm_r125_cdf import origin_positions
    totals = []
    for count in (125, 135, 174):
        reused = set(origin_positions(count)); missing = sorted(set(range(count)) - reused)
        assert len(reused) == 12 and not reused.intersection(missing)
        assert set(missing).union(reused) == set(range(count))
        totals.append(len(missing))
    assert 3 * sum(totals) == 1194


def test_AL_runner_isolated_public_API_packet(tmp_path):
    import os
    import subprocess
    from pricefm_r126_contract import write
    data = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
    design = tmp_path / 'design'; design.mkdir()
    parent = tmp_path / 'parent'; parent.mkdir()
    rng = np.random.default_rng(82); X = np.column_stack((np.ones(32), rng.normal(size=32)))
    y = .2 + X[:, 1] * .5 + rng.normal(scale=.2, size=32)
    X.astype('<f8').tofile(design / 'X.bin'); y.astype('<f8').tofile(design / 'y.bin')
    write(design / 'design.json', dict(n=32, p=2, depth=1, feature_names=['intercept', 'layer1::1']))
    write(design / 'terminal.json', dict(status='completed_r126_quantile_design', test_opened=False,
        files={n: digest(design / n) for n in ('X.bin', 'y.bin', 'design.json')}))
    np.zeros(2, dtype='<f8').tofile(parent / 'beta_mean.bin')
    write(parent / 'terminal.json', dict(full_variational_certified=True, omega_shape=4, omega_rate=.2))
    library = data / 'runtime_libraries/exdqlm_cran_1p1p1'
    manifest = library / 'pricefm_r67_cran111_install_manifest.json'
    adapter = SCRIPTS / 'pricefm_stage_r67_cran111_adapter.R'
    contract = dict(stage='R126_full_outer', family='al', test_opened=False,
        prior_center_from_initializer=False, max_iter=1000, tol=1e-5, tau=.5, tau0=.01,
        n_samp=20, n_samp_xi=20, seed=17, fold=1, output_dir=str(tmp_path / 'fit'),
        design_dir=str(design), design_terminal_sha256=digest(design / 'terminal.json'),
        parent_dir=str(parent), parent_terminal_sha256=digest(parent / 'terminal.json'), parent_type='normal_rhs',
        cran_adapter=str(adapter), cran_adapter_sha256=digest(adapter), cran_manifest=str(manifest),
        cran_manifest_sha256=digest(manifest), cran_library=str(library), posterior_target_sha256='toy_fixed_target')
    write(tmp_path / 'config.json', contract)
    env = dict(os.environ)
    env['LD_LIBRARY_PATH'] = '/data/jaguir26/local/opt/R/4.6.0/lib64/R/lib:' + env.get('LD_LIBRARY_PATH', '')
    command = ['/data/jaguir26/local/opt/R/4.6.0/bin/Rscript', str(SCRIPTS / '448_fit_pricefm_stage_r126_al.R'),
               '--config', str(tmp_path / 'config.json')]
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, result.stderr
    fit = read(tmp_path / 'fit/terminal.json')
    assert fit['finite_core'] and fit['initialization_only'] and not fit['prior_center_from_initializer']
    assert (tmp_path / 'fit/fit.rds').is_file() and (tmp_path / 'fit/vb_trace.csv').is_file()
    second = subprocess.run(command, env=env, capture_output=True, text=True, timeout=120)
    assert second.returncode != 0


def test_full_fold_design_packet_and_train_only_scalers(tmp_path, monkeypatch, toy):
    import pricefm_r126_fullfold as full
    rng = np.random.default_rng(12)
    index = pd.date_range('2022-01-01', '2022-02-09', inclusive='left', tz='UTC', freq='15min')
    raw = pd.DataFrame(rng.normal(size=(len(index), 4)), index=index,
                       columns=['BG-price', 'BG-load', 'BG-solar', 'BG-wind'])
    monkeypatch.setattr(full, 'raw_frame', lambda data, end: raw[raw.index < pd.Timestamp(end, tz='UTC')])
    protocol = dict(PROTOCOL, train_end_market=['2022-02-06', '2022-02-07', '2022-02-08'])
    choice = dict(spec=toy[1], tau0=.01, candidate_id='toy', specification_sha256='a' * 64)
    for fold, count in ((1, 2), (2, 3), (3, 4)):
        folder = tmp_path / str(fold)
        contract = full.full_design(RT, tmp_path, folder, choice, protocol, fold)
        assert contract['origin_count'] == count and contract['response_rows'] == count * 96
        p = read(folder / 'design.json')['p']
        X = np.fromfile(folder / 'X.bin', dtype='<f8').reshape(count * 96, p)
        y = np.fromfile(folder / 'y.bin', dtype='<f8')
        np.testing.assert_array_equal(X[:, 0], np.ones(len(y)))
        XtX = np.fromfile(folder / 'stats/XtX.bin', dtype='<f8').reshape(p, p)
        np.testing.assert_allclose(XtX, X.T @ X)
        assert verified(folder)['fold'] == fold
        assert full.full_design(RT, tmp_path, folder, choice, protocol, fold) == contract


def test_historical_regression_input_is_pinned_and_not_overwritten(tmp_path, monkeypatch):
    import pricefm_r126_release as release
    source = tmp_path / 'source.md'; source.write_text('isolated fixture')
    monkeypatch.setattr(release, 'ROOT', tmp_path / 'worktree')
    monkeypatch.setattr(release, 'HISTORY_SHA256', digest(source))
    target = release.historical_input(source)
    assert target.read_bytes() == source.read_bytes()
    assert release.historical_input(source) == target
    target.write_text('external change')
    with pytest.raises(ValueError): release.historical_input(source)


def test_dependency_scheduler_waits_for_parent_and_drains_own_children(tmp_path, monkeypatch):
    loader = importlib.util.spec_from_file_location('r126_scheduler_test',
        SCRIPTS / '447_run_pricefm_stage_r126_matched_comparison.py')
    runner = importlib.util.module_from_spec(loader); loader.loader.exec_module(runner)
    monkeypatch.setattr(runner, 'OUT', tmp_path)
    monkeypatch.setattr(runner, 'reserves', lambda p: None)
    monkeypatch.setattr(runner.time, 'sleep', lambda t: None)
    from pricefm_r126_contract import write
    parent = tmp_path / 'parent.json'; child = tmp_path / 'child.json'
    write(parent, dict(dependencies=[])); write(child, dict(dependencies=['parent']))
    order = []
    class Process:
        returncode = 0
        pid = 999
        def __init__(self, command, **kwargs):
            self.name = Path(command[command.index('--task') + 1]).stem
            order.append(self.name)
        def poll(self):
            folder = tmp_path / 'tasks_done' / self.name
            if not folder.exists():
                folder.mkdir(parents=True); write(folder / 'result.json', dict(done=True)); seal(folder, dict(done=True))
            return 0
    monkeypatch.setattr(runner.subprocess, 'Popen', Process)
    runner.batch([child, parent], [1, 2], {})
    assert order == ['parent', 'child']
