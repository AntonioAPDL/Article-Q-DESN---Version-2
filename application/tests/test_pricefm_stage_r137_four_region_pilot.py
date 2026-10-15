"""Regression, numerical, and launch-contract tests for the R137 pilot."""
import inspect
import json
import os
from pathlib import Path
import subprocess
import sys

for name in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS', 'BLIS_NUM_THREADS'):
    os.environ[name] = '1'
os.environ.setdefault('PRICEFM_R137_REGION', 'SK')

import numpy as np
import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'application/scripts/pricefm'
sys.path.insert(0, str(HERE))
import pricefm_r134_core as core

if 'PRICEFM_R137_DEPENDENCY' not in os.environ:
    pytest.skip('R137 tests require the exact frozen dependency worktree', allow_module_level=True)
DEPENDENCY = Path(os.environ['PRICEFM_R137_DEPENDENCY'])
RT = core.dependencies(DEPENDENCY)
CTL = core.module('pricefm_r137_test_controller', HERE / '469_run_pricefm_stage_r137_four_region_pilot.py')
CTL.setup(DEPENDENCY)
PROTOCOL = json.loads((ROOT / 'application/config/pricefm_stage_r137_four_region_pilot_20261015.json').read_text())


def spec(region='SK'):
    return RT.normalize_spec(dict(region=region, feature_policy='target_only', calendar='none',
        readout='pure_all_layers', m_y=48, m_x=0, source_window=3120, warmup_steps=240,
        depth=2, units=[16, 16], alpha=.2, rho=.55, input_scale=.1,
        input_fan_in=8, recurrent_sparsity=.1, seed=2026092501,
        input_policy='coverage', interlayer_gain=.2))


def arrays(n=2):
    rng = np.random.default_rng(7)
    return RT.ExplicitArrays(rng.normal(size=(n, 3120)), rng.normal(size=(n, 3120, 3)),
        rng.normal(size=(n, 96, 3)), rng.normal(size=(n, 96)),
        np.array([str(t) for t in pd.date_range('2023-01-01', periods=n, tz='UTC')]),
        ('SK::load', 'SK::solar', 'SK::wind'), ())


def normal():
    rng = np.random.default_rng(8)
    return dict(beta_mean=rng.normal(0, .05, 33), beta_cov=np.eye(33) * .001,
        omega_shape=100., omega_rate=3., omega_mean=3 / 99, prior_type='rhs_ns')


def test_protocol_is_four_region_isolated_nonpromotional_and_uncapped():
    CTL.validate_protocol(PROTOCOL)
    assert PROTOCOL['regions'] == ['SK', 'HU', 'IT_NORD', 'EE']
    assert PROTOCOL['host_allocation'] == {'jerez': ['SK', 'IT_NORD'], 'muscat': ['HU', 'EE']}
    assert PROTOCOL['maximum_workers_per_region'] == 15
    assert PROTOCOL['maximum_workers_per_host'] == 30
    assert PROTOCOL['campaign_size_cap_GiB'] is None
    assert 'maximum_output_GiB' not in PROTOCOL
    assert PROTOCOL['al_max_iter'] == 300


@pytest.mark.parametrize('field', ['mcmc_authorized', 'joint_authorized', 'exal_authorized',
    'registry_mutation_authorized', 'article_mutation_authorized', 'promotion_authorized',
    'all_region_launch_authorized', 'priors_from_initializers'])
def test_forbidden_expansion(field):
    with pytest.raises(ValueError):
        CTL.validate_protocol(dict(PROTOCOL, **{field: True}))


def test_region_environment_namespaces_every_runtime_path():
    assert CTL.REGION == 'SK'
    assert CTL.TAG.endswith('__SK')
    assert CTL.OUT.name == CTL.TAG and CTL.PREP.name == CTL.TAG


def test_r135_basin_is_exact_and_protected_under_four_input_variants():
    initial = [dict(candidate_id='initial', spec=spec(),
        specification_sha256=core.fingerprint(spec()), design_role='test')]
    rows, protected = CTL.add_r135_basin_controls(RT, initial, [], 'SK', PROTOCOL)
    controls = [row for row in rows if row['candidate_id'] in protected]
    assert len(controls) == 4
    assert {(v['spec']['feature_policy'], v['spec']['input_policy']) for v in controls} == {
        ('target_only', 'coverage'), ('target_only', 'balanced'),
        ('graph_summary_mean_std', 'coverage'), ('graph_summary_mean_std', 'balanced')}
    for row in controls:
        value = row['spec']
        assert value['m_y'] == 2016 and value['m_x'] == 4
        assert value['units'] == [192, 192]
        assert value['alpha'] == .15 and value['rho'] == .55
        assert value['input_scale'] == .01 and value['input_fan_in'] == 8
        assert value['recurrent_sparsity'] == .05 and value['interlayer_gain'] == 1.


def test_broad_search_and_selection_geometry_remains_r135_style():
    assert PROTOCOL['broad_candidate_draws'] == 960
    assert PROTOCOL['broad_candidates_per_region'] == 640
    assert PROTOCOL['rhs_shortlist_structures'] == 30
    assert PROTOCOL['quantile_finalists'] == 2
    assert max(core.M_Y) == 2880 and max(core.M_X) == 672
    assert max(map(len, core.UNITS)) == 6
    assert PROTOCOL['tau_multipliers'] == [.1, 1., 10.]


def test_forecast_is_recursive_inside_origin_and_teacher_forced_between_origins():
    from dataclasses import replace
    a = arrays(); fit = normal()
    result, audit = core.normal_predictions(RT, a, spec(), fit, [10, 20], 987, paths=80)
    poisoned, _ = core.normal_predictions(RT, replace(a, response=np.full_like(a.response, 1e20)),
        spec(), fit, [10, 20], 987, paths=80)
    np.testing.assert_array_equal(result, poisoned)
    assert audit['recursive_within_origin'] and audit['teacher_forcing_between_origins']
    assert audit['future_target_access'] is False


def test_generated_target_lag_and_current_exogenous_timing():
    a = arrays(); value = spec()
    u0 = RT.BASE.explicit_input(a, value, [0], 0, np.empty((1, 0)))
    assert u0[0, 0] == a.price_history[0, -1]
    np.testing.assert_array_equal(u0[0, value['m_y']:value['m_y'] + 3], a.exog_future[0, 0])
    u1 = RT.BASE.explicit_input(a, value, [0], 1, np.array([[123.]]))
    assert u1[0, 0] == 123. and u1[0, 1] == a.price_history[0, -1]


def test_rank_requires_three_certified_inner_splits():
    rows = [dict(candidate_id='good', split=s, AQL=float(s), certified=True) for s in (1, 2, 3)]
    rows += [dict(candidate_id='bad', split=s, AQL=1., certified=s != 2) for s in (1, 2, 3)]
    ranking, excluded = core.rank_groups(rows, ['candidate_id'])
    assert [v['candidate_id'] for v in ranking] == ['good'] and len(excluded) == 1


def test_staged_dag_bounds_quantile_confirmation(tmp_path, monkeypatch):
    candidate = dict(candidate_id='candidate', spec=spec(), specification_sha256='a' * 64,
        design_role='r135_basin_control')
    prep = dict(protocol=dict(PROTOCOL, regions=['SK'], rhs_shortlist_structures=1,
        quantile_finalists=2), tasks=[dict(name='SK_candidate', kind='ridge', region='SK')],
        regional={'SK': dict(candidates=[candidate], protected_candidates=['candidate'], protected_tau0=.01)})
    monkeypatch.setattr(CTL, 'OUT', tmp_path)
    ridge = dict(records=[dict(candidate_id='candidate', split=s, AQL=1., certified=True) for s in (1, 2, 3)])
    monkeypatch.setattr(CTL, 'outcome', lambda name: ridge)
    rhs = CTL.rhs_tasks(prep)
    assert sum(t['kind'] == 'stats' for t in rhs) == 3
    assert sum(t['kind'] == 'rhs' for t in rhs) == 12
    lookup = {t['name']: t for t in rhs if t['kind'] == 'rhs'}
    monkeypatch.setattr(CTL, 'outcome', lambda name: dict(candidate_id='candidate',
        tau0=lookup[name]['tau0'], split=lookup[name]['split'], AQL=1., certified=True))
    quantile = CTL.quantile_tasks(prep, rhs)
    assert sum(t['kind'] == 'internal_design' for t in quantile) == 6
    assert sum(t['kind'] == 'internal_al' for t in quantile) == 42
    assert sum(t['kind'] == 'internal_score' for t in quantile) == 6


def test_one_region_official_dag_has_all_folds_levels_and_origins():
    official = json.loads((DEPENDENCY / 'application/config/pricefm_stage_r126_matched_comparison_protocol_20261007.json').read_text())
    choice = dict(candidate_id='a', spec=spec(), specification_sha256='x' * 64, tau0=.001)
    tasks = CTL.full_tasks(dict(protocol=dict(PROTOCOL, regions=['SK']), official_protocol=official), {'SK': choice})
    assert sum(t['kind'] == 'al' for t in tasks) == 21
    assert sum(t['kind'] == 'normal_full' for t in tasks) == 3
    assert sum(len(t['positions']) for t in tasks if t['kind'] == 'forecast') == 365


def test_al_target_is_300_iteration_certified_and_initializer_is_not_prior():
    fitter = (HERE / '470_fit_pricefm_stage_r137_certified_al_300.R').read_text()
    runner = inspect.getsource(CTL.execute)
    assert "c$max_iter == 300L" in fitter
    assert "identical(c$stage, 'R137')" in fitter and "identical(c$model_stage, 'R137')" in fitter
    assert 'r129_certificate' in fitter and 'computationally_certified <- finite &&' in fitter
    assert 'prior_center_from_initializer = FALSE' in fitter
    assert "terminal['computationally_certified']" in runner
    assert "HERE / '470_fit_pricefm_stage_r137_certified_al_300.R'" in runner


def test_r_invocation_is_pinned_to_project_r_460():
    assert CTL.RSCRIPT == Path('/data/jaguir26/local/opt/R/4.6.0/bin/Rscript')
    version = subprocess.check_output([str(CTL.RSCRIPT), '--version'], text=True, stderr=subprocess.STDOUT)
    assert '4.6.0' in version


def test_declared_cpu_list_requires_distinct_physical_cores():
    allowed = os.sched_getaffinity(0); rows = []
    for line in subprocess.check_output(['lscpu', '-p=CPU,CORE,SOCKET'], text=True).splitlines():
        if line.startswith('#'): continue
        cpu, core_id, socket_id = map(int, line.split(','))
        if cpu in allowed and (socket_id, core_id) not in {(r[1], r[2]) for r in rows}:
            rows.append((cpu, socket_id, core_id))
    cpus = [rows[0][0], rows[1][0]]
    assert CTL.declared_cpus(','.join(map(str, cpus)), 2) == cpus
    with pytest.raises(ValueError): CTL.declared_cpus(f'{cpus[0]},{cpus[0]}', 2)


def test_runtime_has_no_campaign_size_cap_or_automatic_al_extension():
    source = inspect.getsource(CTL.resources) + inspect.getsource(CTL.controller)
    assert 'maximum_output_GiB' not in source
    assert 'campaign_size_cap_GiB' not in source
    assert 'al_max_iter' not in inspect.getsource(CTL.controller)


def test_closeout_cannot_promote_or_mutate_authority():
    source = inspect.getsource(CTL.closeout)
    assert 'authority_replaced=False' in source
    assert 'all_region_rollout_authorized=False' in source
    assert 'R137_REGION_COMPLETE_NOT_PROMOTED' in source


def test_compact_cran_al_111_real_smoke_at_300(tmp_path):
    from pricefm_r126_contract import digest, write
    design = tmp_path / 'design'; design.mkdir()
    rng = np.random.default_rng(11)
    X = np.column_stack((np.ones(100), rng.normal(size=(100, 4))))
    y = X @ np.array([.1, .4, -.2, .3, -.1]) + rng.normal(0, .2, 100)
    X.astype('<f8').tofile(design / 'X.bin'); y.astype('<f8').tofile(design / 'y.bin')
    write(design / 'design.json', dict(n=len(y), p=X.shape[1],
        feature_names=['intercept', 'layer1::1', 'layer1::2', 'layer1::3', 'layer1::4']))
    write(design / 'terminal.json', dict(status='completed_r137_quantile_design', test_opened=False,
        files={name: digest(design / name) for name in ('X.bin', 'y.bin', 'design.json')}))
    parent = tmp_path / 'normal'; parent.mkdir()
    np.linalg.lstsq(X, y, rcond=None)[0].astype('<f8').tofile(parent / 'beta_mean.bin')
    write(parent / 'terminal.json', dict(full_variational_certified=True, omega_rate=4., omega_shape=100.))
    manifest = CTL.DATA / 'runtime_libraries/exdqlm_cran_1p1p1/pricefm_r67_cran111_install_manifest.json'
    adapter = DEPENDENCY / 'application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R'
    fixedpoint = ROOT / 'application/R/pricefm_r129_al_fixedpoint_certificate.R'
    contract = dict(stage='R137', model_stage='R137', tag='smoke', family='al',
        output_dir=str(tmp_path / 'al'), max_iter=300, tau0=.01, tau=.5, fold=1, seed=1,
        tol=1e-5, n_samp=20, n_samp_xi=20, test_opened=False,
        prior_center_from_initializer=False, design_dir=str(design), parent_dir=str(parent),
        parent_type='normal_rhs', design_terminal_sha256=digest(design / 'terminal.json'),
        parent_terminal_sha256=digest(parent / 'terminal.json'),
        cran_adapter=str(adapter), cran_adapter_sha256=digest(adapter), cran_manifest=str(manifest),
        cran_manifest_sha256=digest(manifest), cran_library=str(manifest.parent),
        fixedpoint_helper=str(fixedpoint), fixedpoint_helper_sha256=digest(fixedpoint),
        certificate_limits=PROTOCOL['certificate_limits'], max_rhs_iter=PROTOCOL['max_rhs_iter'],
        posterior_target_sha256='fixed-target')
    cpath = tmp_path / 'contract.json'; write(cpath, contract)
    env = dict(os.environ)
    env['LD_LIBRARY_PATH'] = str(CTL.R_LIBRARY_DIR) + ':' + env.get('LD_LIBRARY_PATH', '')
    result = subprocess.run([str(CTL.RSCRIPT), str(HERE / '470_fit_pricefm_stage_r137_certified_al_300.R'),
        '--config', str(cpath)], capture_output=True, text=True, env=env)
    assert result.returncode == 0, result.stdout + result.stderr
    terminal = json.loads((tmp_path / 'al/terminal.json').read_text())
    assert terminal['finite_core'] and terminal['computationally_certified']
    assert terminal['iterations'] <= 300 and terminal['prior_center_from_initializer'] is False
    assert terminal['package']['version'] == '1.1.1'
    assert not (tmp_path / 'al/fit.rds').exists()
