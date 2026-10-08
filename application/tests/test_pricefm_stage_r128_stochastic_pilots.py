"""Small numerical tests against the exact frozen PriceFM dependency."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

for name in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS', 'BLIS_NUM_THREADS'):
    os.environ[name] = '1'

import numpy as np
import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'application/scripts/pricefm'
sys.path.insert(0, str(HERE))
import pricefm_r128_core as core

if 'PRICEFM_R128_DEPENDENCY' not in os.environ:
    pytest.skip('R128 integration tests require the pinned PriceFM dependency worktree', allow_module_level=True)
DEPENDENCY = Path(os.environ['PRICEFM_R128_DEPENDENCY'])
RT = core.dependencies(DEPENDENCY)
CTL = core.module('r128_test_controller', HERE / '456_run_pricefm_stage_r128_stochastic_pilots.py')
CTL.setup(DEPENDENCY)
PROTOCOL = json.loads((ROOT / 'application/config/pricefm_stage_r128_stochastic_regional_pilots_20261008.json').read_text())


def spec(region='BG'):
    return RT.normalize_spec(dict(region=region, feature_policy='target_only', calendar='none',
        readout='pure_all_layers', m_y=8, m_x=2, source_window=3120, warmup_steps=240,
        depth=2, units=[16, 16], alpha=.2, rho=.55, input_scale=.1,
        input_fan_in=8, recurrent_sparsity=.1, seed=2026092501,
        input_policy='coverage', interlayer_gain=.2))


def arrays(n=2):
    rng = np.random.default_rng(7)
    return RT.ExplicitArrays(rng.normal(size=(n, 3120)), rng.normal(size=(n, 3120, 3)),
        rng.normal(size=(n, 96, 3)), rng.normal(size=(n, 96)),
        np.array([str(t) for t in pd.date_range('2023-01-01', periods=n, tz='UTC')]),
        ('BG::load', 'BG::solar', 'BG::wind'), ())


def normal(kind='rhs_ns'):
    rng = np.random.default_rng(8)
    return dict(beta_mean=rng.normal(0, .05, 33), beta_cov=np.eye(33) * .001,
        omega_shape=100., omega_rate=3., omega_mean=3 / 99, prior_type=kind)


@pytest.mark.parametrize('field', ['mcmc_authorized', 'joint_authorized', 'exal_authorized',
    'registry_mutation_authorized', 'article_mutation_authorized', 'promotion_authorized',
    'all_region_launch_authorized', 'priors_from_initializers'])
def test_forbidden_expansion(field):
    CTL.validate_protocol(PROTOCOL)
    with pytest.raises(ValueError): CTL.validate_protocol(dict(PROTOCOL, **{field: True}))


@pytest.mark.parametrize('kind', ['rhs_ns', 'scaled_ridge'])
def test_forecast_future_price_poison_and_chunk_invariance(kind):
    from dataclasses import replace
    a = arrays(); fit = normal(kind)
    result, audit = core.normal_predictions(RT, a, spec(), fit, [10, 20], 987, paths=500)
    poisoned, _ = core.normal_predictions(RT, replace(a, response=np.full_like(a.response, 1e20)),
        spec(), fit, [10, 20], 987, paths=500)
    np.testing.assert_array_equal(result, poisoned)
    chunks = [core.normal_predictions(RT, RT.subset_arrays(a, [i]), spec(), fit, [p], 987, paths=500)[0]
              for i, p in enumerate((10, 20))]
    np.testing.assert_array_equal(result, np.concatenate(chunks))
    assert audit['ridge_beta_omega_coupling'] == (kind == 'scaled_ridge')
    assert audit['future_target_access'] is False


def test_generated_lag_and_current_exogenous_timing():
    a = arrays(); s = spec()
    u0 = RT.BASE.explicit_input(a, s, [0], 0, np.empty((1, 0)))
    assert u0[0, 0] == a.price_history[0, -1]
    np.testing.assert_array_equal(u0[0, s['m_y']:s['m_y'] + 3], a.exog_future[0, 0])
    u1 = RT.BASE.explicit_input(a, s, [0], 1, np.array([[123.]]))
    assert u1[0, 0] == 123.
    assert u1[0, 1] == a.price_history[0, -1]


def test_fresh_origin_teacher_forces_observed_history():
    from dataclasses import replace
    a = arrays(); fit = normal()
    baseline, _ = core.normal_predictions(RT, a, spec(), fit, [0, 1], 31, paths=80)
    changed = a.price_history.copy(); changed[1, -240:] += 5
    result, _ = core.normal_predictions(RT, replace(a, price_history=changed), spec(), fit, [0, 1], 31, paths=80)
    np.testing.assert_array_equal(result[0], baseline[0])
    assert not np.allclose(result[1], baseline[1])


def test_graph_uses_no_neighbor_prices():
    s = dict(spec('HR'), feature_policy='graph_summary_mean_std')
    regions = RT.active_regions(s); index = pd.date_range('2022-01-01', periods=3400, freq='15min', tz='UTC')
    rng = np.random.default_rng(4)
    frame = pd.DataFrame(rng.normal(size=(3400, len(regions) * 4)), index=index,
        columns=[f'{r}-{v}' for r in regions for v in ('price', 'load', 'solar', 'wind')])
    origins = index[[3120, 3216]]
    first = core.regional_arrays(RT, frame, origins, s)
    for region in regions[1:]: frame[region + '-price'] = 1e25
    second = core.regional_arrays(RT, frame, origins, s)
    for name in ('price_history', 'exog_history', 'exog_future', 'response'):
        np.testing.assert_array_equal(getattr(first, name), getattr(second, name))
    assert len(first.exog_names) == 9


def test_train_file_omits_future_values(tmp_path):
    n = 300; time = pd.date_range('2024-08-31', periods=n, freq='15min', tz='UTC')
    frame = pd.DataFrame({'time_utc': time.astype(str), **{f'HR-{v}': np.arange(n, dtype=float)
        for v in ('price', 'load', 'solar', 'wind')}})
    path = tmp_path / 'raw.csv'; frame.to_csv(path, index=False)
    first = core.read_frame(path, ['HR'], '2024-09-01')
    frame.loc[92:, 'HR-price'] = 1e20; frame.to_csv(path, index=False)
    second = core.read_frame(path, ['HR'], '2024-09-01')
    pd.testing.assert_frame_equal(first, second)
    assert first.index.max() < pd.Timestamp('2024-09-01', tz='UTC')


def test_rank_requires_three_certified_splits_and_no_duplicates():
    rows = [dict(candidate_id='a', split=s, AQL=3., certified=True) for s in (1, 2, 3)]
    rows += [dict(candidate_id='b', split=s, AQL=1., certified=s != 2) for s in (1, 2, 3)]
    ranking, excluded = core.rank_groups(rows, ['candidate_id'])
    assert ranking[0]['candidate_id'] == 'a' and len(excluded) == 1
    with pytest.raises(ValueError): core.rank_groups([*rows, rows[0]], ['candidate_id'])


def test_tau_reference_scales_with_dimension_and_sample_size():
    assert core.tau_center(513, 4 * 48576) == pytest.approx(core.tau_center(513, 48576) / 2)
    with pytest.raises(ValueError): core.tau_center(5, 100)


def test_candidate_graph_and_connectivity_controls_preserve_architecture():
    registry = pd.read_csv(DEPENDENCY / 'tables/pricefm_r98_authoritative_registry.csv')
    candidates, protected, tau0 = core.regional_candidates(RT, [spec('BG')], registry, 'DK_1')
    assert len(candidates) == 8 and protected in {v['candidate_id'] for v in candidates}
    assert tau0 == .01
    assert all(v['spec']['readout'] == 'pure_all_layers' for v in candidates)
    assert {v['spec']['feature_policy'] for v in candidates} == {'target_only', 'graph_summary_mean_std'}


def test_nested_schedule_budget_and_dependencies():
    old = json.loads((DEPENDENCY / 'application/config/pricefm_stage_r126_matched_comparison_protocol_20261007.json').read_text())
    choice = dict(candidate_id='a', spec=spec(), specification_sha256='x' * 64, tau0=.001)
    tasks = CTL.full_tasks(dict(protocol=PROTOCOL, official_protocol=old), {'HR': choice, 'DK_1': choice})
    assert sum(t['kind'] == 'al' for t in tasks) == 42
    assert sum(t['kind'] == 'normal_full' for t in tasks) == 6
    assert sum(len(t['positions']) for t in tasks if t['kind'] == 'forecast') == 730
    by_name = {t['name']: t for t in tasks}
    for t in tasks:
        if t['kind'] == 'al':
            parent = by_name[t['parent_name']]
            assert parent['kind'] == ('normal_full' if t['tau'] == .5 else 'al')
            if t['tau'] != .5: assert abs(parent['tau'] - .5) < abs(t['tau'] - .5)
            assert parent['tau0'] == t['tau0']


def test_active_unsealed_output_is_not_misclassified_as_completed(tmp_path, monkeypatch):
    monkeypatch.setattr(CTL, 'OUT', tmp_path)
    (tmp_path / 'tasks_done/running').mkdir(parents=True)
    assert CTL.outcome('running') is None


@pytest.mark.parametrize('workers', [0, 16, 99])
def test_worker_cap(workers):
    with pytest.raises(ValueError): core.physical_cpus(workers, sample_seconds=0)


def test_compact_al_public_api_smoke(tmp_path):
    from pricefm_r126_contract import digest, write
    d = tmp_path / 'design'; d.mkdir()
    rng = np.random.default_rng(11); X = np.column_stack((np.ones(80), rng.normal(size=(80, 4))))
    y = X @ np.array([.1, .4, -.2, .3, -.1]) + rng.normal(0, .2, 80)
    X.astype('<f8').tofile(d / 'X.bin'); y.astype('<f8').tofile(d / 'y.bin')
    write(d / 'design.json', dict(n=80, p=5, feature_names=['intercept', 'layer1::1', 'layer1::2', 'layer1::3', 'layer1::4']))
    write(d / 'terminal.json', dict(status='completed_r128_quantile_design', test_opened=False,
        files={n: digest(d / n) for n in ('X.bin', 'y.bin', 'design.json')}))
    parent = tmp_path / 'normal'; parent.mkdir()
    np.linalg.lstsq(X, y, rcond=None)[0].astype('<f8').tofile(parent / 'beta_mean.bin')
    write(parent / 'terminal.json', dict(full_variational_certified=True, omega_rate=4., omega_shape=100.))
    data = CTL.DATA
    manifest = data / 'runtime_libraries/exdqlm_cran_1p1p1/pricefm_r67_cran111_install_manifest.json'
    adapter = DEPENDENCY / 'application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R'
    previous_type = 'normal_rhs'
    for level in (.5, .45, .25):
        output = tmp_path / ('al' + str(level))
        contract = dict(stage='R128', family='al', output_dir=str(output), max_iter=1000, tau0=.01,
            tau=level, fold=1, seed=1, tol=1e-5, n_samp=20, n_samp_xi=20,
            test_opened=False, prior_center_from_initializer=False, design_dir=str(d), parent_dir=str(parent),
            parent_type=previous_type, design_terminal_sha256=digest(d / 'terminal.json'),
            parent_terminal_sha256=digest(parent / 'terminal.json'),
            cran_adapter=str(adapter), cran_adapter_sha256=digest(adapter), cran_manifest=str(manifest),
            cran_manifest_sha256=digest(manifest), cran_library=str(manifest.parent), posterior_target_sha256='fixed-target')
        cpath = tmp_path / ('contract' + str(level) + '.json'); write(cpath, contract)
        env = dict(os.environ); env['LD_LIBRARY_PATH'] = '/data/jaguir26/local/opt/R/4.6.0/lib64/R/lib:' + env.get('LD_LIBRARY_PATH', '')
        result = subprocess.run(['/data/jaguir26/local/opt/R/4.6.0/bin/Rscript',
            str(HERE / '455_fit_pricefm_stage_r128_compact_al.R'), '--config', str(cpath)],
            capture_output=True, text=True, env=env)
        assert result.returncode == 0, result.stdout + result.stderr
        terminal = json.loads((output / 'terminal.json').read_text())
        assert terminal['finite_core'] and terminal['formal_converged']
        assert terminal['prior_center_from_initializer'] is False
        assert not (output / 'fit.rds').exists()
        assert np.fromfile(output / 'beta_cov.bin', dtype='<f8').size == 25
        parent = output; previous_type = 'quantile'


def test_certified_normal_entrypoint_and_fixed_prior_smoke(tmp_path):
    from pricefm_r126_contract import digest, write
    rng = np.random.default_rng(15); X = np.column_stack((np.ones(200), rng.normal(size=(200, 8))))
    y = X[:, 1] * .4 + rng.normal(0, .2, 200)
    stats = tmp_path / 'stats'
    RT.write_stats_packet(stats, dict(n=len(y), p=9, XtX=X.T @ X, Xty=X.T @ y, yty=float(y @ y)), {})
    helper = DEPENDENCY / 'application/R/pricefm_recursive_normal_fit.R'
    entry = DEPENDENCY / 'application/scripts/pricefm/442_fit_pricefm_stage_r123_certified_normal.R'
    runtime = CTL.DATA / 'runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm'
    contract = dict(selection_split='train_validation_only', test_access_authorized=False,
        prior_type='rhs_ns', convergence_mode='full_variational', output_dir=str(tmp_path / 'normal'),
        max_iter=2000, min_iter=100, stats_dir=str(stats), stats_terminal_sha256=digest(stats / 'terminal.json'),
        source_sha256={str(p): digest(p) for p in (helper, entry)}, helper_path=str(helper),
        package_path=str(runtime), initial_fit_path=None, initial_fit_sha256=None, tau0=.01,
        tol=1e-5, stability_window=10, predictive_tol=1e-7, relative_beta_tol=1e-6,
        sigma_relative_tol=1e-8, prior_rms_log_precision_tol=1e-6, rhs_state_tol=1e-6,
        covariance_tol=1e-6, objective_per_observation_tol=1e-8, precision_accuracy_tol=1e-5,
        posterior_target_sha256='fixed-prior-test', tag='R128_smoke', fit_id='toy', candidate_id='toy', split=1)
    path = tmp_path / 'contract.json'; write(path, contract)
    env = dict(os.environ); env['LD_LIBRARY_PATH'] = '/data/jaguir26/local/opt/R/4.6.0/lib64/R/lib:' + env.get('LD_LIBRARY_PATH', '')
    proc = subprocess.run(['/data/jaguir26/local/opt/R/4.6.0/bin/Rscript', str(entry), '--contract', str(path)],
        env=env, capture_output=True, text=True)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    terminal = json.loads((tmp_path / 'normal/terminal.json').read_text())
    assert terminal['full_variational_certified'] and terminal['precision_accuracy']['accepted']
    assert terminal['posterior_target_sha256'] == 'fixed-prior-test'
    assert terminal['prior_center_from_initializer'] is False
