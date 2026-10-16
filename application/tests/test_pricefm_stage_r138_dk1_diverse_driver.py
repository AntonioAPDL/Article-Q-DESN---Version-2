"""Regression, numerical, and launch-contract tests for R138 DK_1."""
import inspect
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
import pricefm_r134_core as core
from pricefm_r138_cross_driver import _driver_to_receiver

if 'PRICEFM_R138_DEPENDENCY' not in os.environ:
    pytest.skip('R138 tests require the exact frozen dependency worktree', allow_module_level=True)
DEPENDENCY = Path(os.environ['PRICEFM_R138_DEPENDENCY'])
RT = core.dependencies(DEPENDENCY)
CTL = core.module('pricefm_r138_test_controller', HERE / '471_run_pricefm_stage_r138_dk1_diverse_driver.py')
CTL.setup(DEPENDENCY)
PROTOCOL = json.loads((ROOT / 'application/config/pricefm_stage_r138_dk1_diverse_driver_20261016.json').read_text())


def spec(feature='target_only', units=(16, 16), m_y=48):
    return RT.normalize_spec(dict(region='DK_1', feature_policy=feature, calendar='none',
        readout='pure_all_layers', m_y=m_y, m_x=0, source_window=3120, warmup_steps=240,
        depth=len(units), units=list(units), alpha=.2, rho=.55, input_scale=.1,
        input_fan_in=8, recurrent_sparsity=.1, seed=2026092501,
        input_policy='coverage', interlayer_gain=.2))


def candidate(name, feature='target_only', tau0=.001):
    value = spec(feature=feature)
    return dict(candidate_id=name, spec=value, specification_sha256=core.fingerprint(value),
        tau0=tau0, mean_AQL=7., worst_split_AQL=8., split_AQL={'1': 7., '2': 7., '3': 7.})


def arrays(n=1):
    rng = np.random.default_rng(7)
    return RT.ExplicitArrays(rng.normal(size=(n, 3120)), rng.normal(size=(n, 3120, 3)),
        rng.normal(size=(n, 96, 3)), rng.normal(size=(n, 96)),
        np.array([str(t) for t in pd.date_range('2023-01-01', periods=n, tz='UTC')]),
        ('DK_1::load', 'DK_1::solar', 'DK_1::wind'), ())


def normal(p=33):
    rng = np.random.default_rng(8)
    return dict(beta_mean=rng.normal(0, .05, p), beta_cov=np.eye(p) * .001,
        omega_shape=100., omega_rate=3., omega_mean=3 / 99, prior_type='rhs_ns')


def quantiles(p=33):
    return {q: dict(beta_mean=np.linspace(-.02, .02, p) + q / 100,
                    beta_cov=np.eye(p) * .0005)
            for q in RT.QUANTILES}


def prep():
    receivers = [candidate(f'receiver_{i}') for i in range(12)]
    drivers = [candidate('driver_control'), candidate('driver_target'), candidate('driver_graph', 'graph_summary_mean')]
    return dict(protocol=PROTOCOL, receiver_waves=dict(wave1=receivers[:6], wave2=receivers[6:]),
                drivers=drivers, official_protocol=json.loads((DEPENDENCY /
                'application/config/pricefm_stage_r126_matched_comparison_protocol_20261007.json').read_text()))


def test_protocol_is_bounded_reuse_only_and_nonpromotional():
    CTL.validate_protocol(PROTOCOL)
    assert PROTOCOL['region'] == 'DK_1' and PROTOCOL['maximum_workers'] == 30
    assert PROTOCOL['wave1_unique_receivers'] == PROTOCOL['wave2_unique_receivers'] == 6
    assert not PROTOCOL['new_broad_screen_authorized']


@pytest.mark.parametrize('field', ['mcmc_authorized', 'joint_authorized', 'exal_authorized',
    'new_broad_screen_authorized', 'registry_mutation_authorized', 'article_mutation_authorized',
    'promotion_authorized', 'all_region_launch_authorized', 'priors_from_initializers'])
def test_forbidden_expansion(field):
    with pytest.raises(ValueError):
        CTL.validate_protocol(dict(PROTOCOL, **{field: True}))


def test_unique_best_rhs_keeps_one_tau_per_structure():
    rows = [dict(candidate_id='a', tau0=.1, mean_AQL=1.),
            dict(candidate_id='a', tau0=.01, mean_AQL=1.1),
            dict(candidate_id='b', tau0=.2, mean_AQL=1.2)]
    assert CTL.unique_best_rhs(rows) == [rows[0], rows[2]]


def test_wave_task_geometry_has_six_distinct_receivers(monkeypatch):
    monkeypatch.setattr(CTL, 'parent_rhs', lambda p, candidate_id, split: Path('/parent') / candidate_id / str(split))
    tasks = CTL.quantile_tasks(prep(), prep()['receiver_waves']['wave1'], 'wave1')
    assert len(tasks) == 6 * (3 + 21 + 9)
    assert sum(t['kind'] == 'internal_design' for t in tasks) == 18
    assert sum(t['kind'] == 'internal_al' for t in tasks) == 126
    assert sum(t['kind'] == 'internal_score' for t in tasks) == 54
    assert len({t['candidate_id'] for t in tasks}) == 6


def test_median_uses_external_rhs_only_as_initializer(monkeypatch):
    monkeypatch.setattr(CTL, 'parent_rhs', lambda p, candidate_id, split: Path('/parent') / candidate_id / str(split))
    tasks = CTL.quantile_tasks(prep(), [candidate('receiver')], 'wave1')
    medians = [t for t in tasks if t['kind'] == 'internal_al' and t['tau'] == .5]
    assert len(medians) == 3
    assert all(t['parent_type'] == 'normal_rhs' and t['parent_external'] for t in medians)
    assert all(t['depends'] == [t['design_name']] for t in medians)


def test_adjacent_quantiles_are_nested_computational_initializers(monkeypatch):
    monkeypatch.setattr(CTL, 'parent_rhs', lambda *args: Path('/parent'))
    tasks = CTL.quantile_tasks(prep(), [candidate('receiver')], 'wave1')
    q45 = next(t for t in tasks if t['kind'] == 'internal_al' and t['split'] == 1 and t['tau'] == .45)
    assert q45['parent_type'] == 'quantile' and q45['parent_external'] is None
    assert q45['parent_name'] in q45['depends']


def test_each_receiver_is_crossed_with_three_drivers(monkeypatch):
    monkeypatch.setattr(CTL, 'parent_rhs', lambda *args: Path('/parent'))
    tasks = CTL.quantile_tasks(prep(), [candidate('receiver')], 'wave1')
    scores = [t for t in tasks if t['kind'] == 'internal_score']
    assert len(scores) == 9
    assert len({t['driver_candidate_id'] for t in scores}) == 3


def test_scale_transfer_round_trip():
    values = np.array([-2., 0., 3.])
    got = _driver_to_receiver(values,
        {'price_mean': 10., 'price_scale': 4.}, {'price_mean': -2., 'price_scale': 3.})
    np.testing.assert_allclose(got, (values * 4 + 10 + 2) / 3)


def test_identity_scale_transfer_is_identity():
    values = np.array([-2., 0., 3.]); scaler = {'price_mean': 10., 'price_scale': 4.}
    np.testing.assert_array_equal(_driver_to_receiver(values, scaler, scaler), values)


def test_same_spec_cross_driver_reproduces_canonical_forecast():
    from pricefm_r126_replay import forecast as canonical
    from pricefm_r138_cross_driver import forecast as cross
    a = arrays(); value = spec(); nfit = normal(); qfits = quantiles(); positions = [17]
    scaler = {'price_mean': 0., 'price_scale': 1.}
    expected, _ = canonical(RT, a, value, nfit, qfits, positions, 987)
    observed, audit = cross(RT, a, value, scaler, a, value, scaler,
                            nfit, qfits, positions, 987)
    for key in expected:
        np.testing.assert_allclose(observed[key], expected[key], rtol=0, atol=2e-12)
    assert audit['driver_specification_distinct'] is False


def test_cross_driver_rejects_misaligned_origins():
    from dataclasses import replace
    from pricefm_r138_cross_driver import forecast
    a = arrays(); b = replace(a, anchors=np.array(['different']))
    with pytest.raises(ValueError, match='origins differ'):
        forecast(RT, a, spec(), {'price_mean': 0., 'price_scale': 1.},
                 b, spec(), {'price_mean': 0., 'price_scale': 1.},
                 normal(), quantiles(), [1], 2)


def test_full_task_graph_refits_receiver_and_distinct_driver():
    value = prep(); choice = dict(receiver=candidate('receiver'), driver=candidate('driver'), tau0=.001)
    tasks = CTL.full_tasks(value, choice)
    assert sum(t['kind'] == 'design' for t in tasks) == 6
    assert sum(t['kind'] == 'normal_full' for t in tasks) == 6
    assert sum(t['kind'] == 'al' for t in tasks) == 21
    assert sum(len(t['positions']) for t in tasks if t['kind'] == 'forecast') == 365


def test_full_task_graph_reuses_receiver_normal_when_driver_matches():
    value = prep(); receiver = candidate('same')
    choice = dict(receiver=receiver, driver=dict(receiver), tau0=receiver['tau0'])
    tasks = CTL.full_tasks(value, choice)
    assert sum(t['kind'] == 'design' for t in tasks) == 3
    assert sum(t['kind'] == 'normal_full' for t in tasks) == 3


def test_wave2_gate_is_training_only_and_strict():
    source = inspect.getsource(CTL.controller)
    assert "mean_AQL'] >= prep['protocol']['r135_internal_AQL']" in source
    assert "test_used_for_gate=False" in source
    assert source.index('frozen_choice') < source.index('full_tasks')


def test_prepare_reuses_ridge_and_rhs_without_new_screen():
    source = inspect.getsource(CTL.prepare)
    assert 'historical_ridge_reused=640' in source and 'new_ridge_fits=0' in source
    assert 'balanced_candidates' not in source and 'fit_scaled_ridge' not in source


def test_selection_key_includes_driver_identity():
    assert "['candidate_id', 'tau0', 'driver_candidate_id']" in inspect.getsource(CTL.rank_quantile_pairs)


def test_closeout_cannot_promote_or_mutate_authority():
    source = inspect.getsource(CTL.closeout)
    assert 'authority_replaced=False' in source and 'all_region_rollout_authorized=False' in source
    assert 'R138_DK1_COMPLETE_NOT_PROMOTED' in source


def test_al_target_is_cran_111_300_iteration_and_initializer_not_prior():
    fitter = (HERE / '472_fit_pricefm_stage_r138_certified_al_300.R').read_text()
    assert "c$max_iter == 300L" in fitter and "identical(c$stage, 'R138')" in fitter
    assert "expected_version = '1.1.1'" in fitter and 'prior_center_from_initializer = FALSE' in fitter


def test_r_invocation_is_pinned_to_project_r_460():
    assert CTL.RSCRIPT == Path('/data/jaguir26/local/opt/R/4.6.0/bin/Rscript')
    version = subprocess.check_output([str(CTL.RSCRIPT), '--version'], text=True, stderr=subprocess.STDOUT)
    assert '4.6.0' in version


def test_declared_cpu_list_requires_distinct_physical_cores():
    rows = []
    for line in subprocess.check_output(['lscpu', '-p=CPU,CORE,SOCKET'], text=True).splitlines():
        if line.startswith('#'): continue
        cpu, core_id, socket_id = map(int, line.split(','))
        if cpu in os.sched_getaffinity(0) and (socket_id, core_id) not in {(r[1], r[2]) for r in rows}:
            rows.append((cpu, socket_id, core_id))
    cpus = [rows[0][0], rows[1][0]]
    assert CTL.declared_cpus(','.join(map(str, cpus)), 2) == cpus
    with pytest.raises(ValueError): CTL.declared_cpus(f'{cpus[0]},{cpus[0]}', 2)


def test_compact_cran_al_111_real_smoke_at_300(tmp_path):
    from pricefm_r126_contract import digest, write
    design = tmp_path / 'design'; design.mkdir(); rng = np.random.default_rng(11)
    X = np.column_stack((np.ones(100), rng.normal(size=(100, 4))))
    y = X @ np.array([.1, .4, -.2, .3, -.1]) + rng.normal(0, .2, 100)
    X.astype('<f8').tofile(design / 'X.bin'); y.astype('<f8').tofile(design / 'y.bin')
    write(design / 'design.json', dict(n=len(y), p=X.shape[1],
        feature_names=['intercept', 'layer1::1', 'layer1::2', 'layer1::3', 'layer1::4']))
    write(design / 'terminal.json', dict(status='completed_r138_quantile_design', test_opened=False,
        files={name: digest(design / name) for name in ('X.bin', 'y.bin', 'design.json')}))
    parent = tmp_path / 'normal'; parent.mkdir()
    np.linalg.lstsq(X, y, rcond=None)[0].astype('<f8').tofile(parent / 'beta_mean.bin')
    write(parent / 'terminal.json', dict(full_variational_certified=True, omega_rate=4., omega_shape=100.))
    manifest = CTL.DATA / 'runtime_libraries/exdqlm_cran_1p1p1/pricefm_r67_cran111_install_manifest.json'
    adapter = DEPENDENCY / 'application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R'
    fixedpoint = ROOT / 'application/R/pricefm_r129_al_fixedpoint_certificate.R'
    contract = dict(stage='R138', model_stage='R138', tag='smoke', family='al',
        output_dir=str(tmp_path / 'al'), max_iter=300, tau0=.01, tau=.5, fold=1, seed=1,
        tol=1e-5, n_samp=20, n_samp_xi=20, test_opened=False,
        prior_center_from_initializer=False, design_dir=str(design), parent_dir=str(parent),
        parent_type='normal_rhs', design_terminal_sha256=digest(design / 'terminal.json'),
        parent_terminal_sha256=digest(parent / 'terminal.json'), cran_adapter=str(adapter),
        cran_adapter_sha256=digest(adapter), cran_manifest=str(manifest),
        cran_manifest_sha256=digest(manifest), cran_library=str(manifest.parent),
        fixedpoint_helper=str(fixedpoint), fixedpoint_helper_sha256=digest(fixedpoint),
        certificate_limits=PROTOCOL['certificate_limits'], max_rhs_iter=PROTOCOL['max_rhs_iter'],
        posterior_target_sha256='fixed-target')
    cpath = tmp_path / 'contract.json'; write(cpath, contract)
    env = dict(os.environ, LD_LIBRARY_PATH=str(CTL.R_LIBRARY_DIR) + ':' + os.environ.get('LD_LIBRARY_PATH', ''))
    result = subprocess.run([str(CTL.RSCRIPT), str(HERE / '472_fit_pricefm_stage_r138_certified_al_300.R'),
        '--config', str(cpath)], capture_output=True, text=True, env=env)
    assert result.returncode == 0, result.stdout + result.stderr
    terminal = json.loads((tmp_path / 'al/terminal.json').read_text())
    assert terminal['finite_core'] and terminal['computationally_certified']
    assert terminal['package']['version'] == '1.1.1' and not (tmp_path / 'al/fit.rds').exists()
