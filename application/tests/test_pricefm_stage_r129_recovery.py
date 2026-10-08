"""The corrected certificate cannot change posterior targets or duplicate R128."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import pytest

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'application/scripts/pricefm'
PARENT = Path(os.environ['PRICEFM_R129_PARENT'])
DEPENDENCY = Path(os.environ['PRICEFM_R129_DEPENDENCY'])
spec = importlib.util.spec_from_file_location('r129_test_controller', HERE / '459_run_pricefm_stage_r129_recovery.py')
CTL = importlib.util.module_from_spec(spec); spec.loader.exec_module(CTL)
RT = CTL.setup(PARENT, DEPENDENCY)
P = json.loads(CTL.PROTOCOL.read_text())


@pytest.mark.parametrize('field', ['package_mutation_authorized', 'screening_authorized',
    'mcmc_authorized', 'joint_authorized', 'exal_authorized', 'promotion_authorized',
    'registry_mutation_authorized', 'article_mutation_authorized', 'priors_from_initializers',
    'test_used_for_selection', 'all_region_launch_authorized'])
def test_no_scientific_expansion(field):
    CTL.validate_protocol(P)
    with pytest.raises(ValueError): CTL.validate_protocol(dict(P, **{field: True}))


@pytest.mark.parametrize('workers', [0, 16, 100])
def test_worker_cap(workers):
    # Guard is before locks or jobs, and cannot accept16 logical workers as15 cores.
    with pytest.raises(ValueError): CTL.base.core.physical_cpus(workers, sample_seconds=0)


def test_exact_recovery_DAG_and_no_new_normal_or_screening():
    old = json.loads((PARENT / 'application/config/pricefm_stage_r128_stochastic_regional_pilots_20261008.json').read_text())
    official = json.loads((DEPENDENCY / 'application/config/pricefm_stage_r126_matched_comparison_protocol_20261007.json').read_text())
    choice = dict(candidate_id='a', specification_sha256='a' * 64, tau0=.001,
        spec=RT.normalize_spec(dict(region='HR', depth=2, units=[16, 16], m_y=8, m_x=2,
            source_window=3120, calendar='none', readout='pure_all_layers', feature_policy='target_only',
            alpha=.2, rho=.55, input_scale=.1, input_fan_in=8, recurrent_sparsity=.1,
            seed=2026092501, input_policy='coverage', interlayer_gain=.2)))
    medians, remaining = CTL.build_tasks(dict(protocol=old, official_protocol=official), {'HR': choice, 'DK_1': choice})
    assert len(medians) == 6 and len(remaining) == 100
    assert sum(t['kind'] == 'al' for t in remaining) == 36
    assert sum(len(t['positions']) for t in remaining if t['kind'] == 'forecast') == 730
    assert {t['kind'] for t in medians + remaining} == {'median_certificate', 'al', 'forecast'}
    by_name = {t['name']: t for t in medians + remaining}
    for t in remaining:
        assert all(d in by_name for d in t['depends'])
        if t['kind'] == 'al':
            parent = by_name[t['parent_name']]
            assert parent['tau0'] == t['tau0']
            assert abs(parent['tau'] - .5) < abs(t['tau'] - .5)


def test_legacy_false_flag_is_not_used_as_new_certificate(tmp_path):
    CTL.base.OUT = tmp_path; CTL.base._OUTCOMES = {}
    assert CTL.base.outcome('unsealed') is None
    d = tmp_path / 'tasks_done/failed'; d.mkdir(parents=True)
    CTL.write(d / 'result.json', dict(certified=False, original_or_public_formal_converged=False))
    CTL.seal(d, dict(certified=False))
    assert CTL.base.outcome('failed')['certified'] is False


def test_contract_initializers_never_define_prior(tmp_path, monkeypatch):
    # Compare two upstream summaries with different beta/sigma contents.
    old = tmp_path / 'parent'; current = tmp_path / 'current'
    design = old / 'tasks_done/HR_fold1_design/design'; design.mkdir(parents=True)
    CTL.write(design / 'terminal.json', dict(status='design'))
    CTL.write(design / 'design.json', dict(n=100, p=5))
    parent = current / 'tasks_done/HR_fold1_al0.50/fit'; parent.mkdir(parents=True)
    for filename in ('terminal.json', 'certificate.json', 'beta_mean.bin', 'beta_cov.bin'):
        (parent / filename).write_bytes(b'first initializer')
    monkeypatch.setattr(CTL, 'OUT', current)
    prep = dict(protocol=P, parent_out=str(old), dependency=str(DEPENDENCY), control={'cran_library': 'pinned'})
    t = dict(region='HR', fold=1, kind='al', name='HR_fold1_al0.45', parent_name='HR_fold1_al0.50', tau=.45, tau0=.001)
    first = CTL.contract(prep, t, tmp_path / 'out')
    (parent / 'beta_mean.bin').write_bytes(b'very different initializer')
    second = CTL.contract(prep, t, tmp_path / 'out')
    assert first['posterior_target_sha256'] == second['posterior_target_sha256']
    assert first['tau0'] == second['tau0'] == .001
    assert first['input_sha256'] != second['input_sha256']


def test_real_public_cran_fit_and_full_certificate(tmp_path):
    env = dict(os.environ, OPENBLAS_NUM_THREADS='1', OMP_NUM_THREADS='1', MKL_NUM_THREADS='1')
    library = CTL.DATA / 'runtime_libraries/exdqlm_cran_1p1p1'
    run = subprocess.run(['/data/jaguir26/local/opt/R/4.6.0/bin/Rscript',
        str(ROOT / 'application/tests/test_pricefm_stage_r129_al_fixedpoint.R'), str(CTL.HELPER), str(library), str(tmp_path / 'fixture')],
        env=env, capture_output=True, text=True)
    assert run.returncode == 0, run.stdout + run.stderr
    assert 'PASS:' in run.stdout
    fixture = tmp_path / 'fixture'
    old = CTL.read(fixture / 'terminal.json')
    files = [CTL.HELPER, fixture / 'terminal.json', fixture / 'design.json',
        fixture / 'X.bin', fixture / 'y.bin', fixture / 'beta_mean.bin', fixture / 'beta_cov.bin']
    config = dict(stage='R129', action='saved_median_certificate', test_opened=False,
        output_dir=str(tmp_path / 'certificate'), input_sha256={str(f): CTL.digest(f) for f in files},
        helper=str(CTL.HELPER), helper_sha256=CTL.digest(CTL.HELPER), cran_library=str(library),
        design_dir=str(fixture), parent_dir=str(fixture), tau0=.1, posterior_target_sha256='test-target',
        limits=P['certificate_limits'], max_rhs_iter=P['max_rhs_iter'])
    path = tmp_path / 'audit_config.json'; CTL.write(path, config)
    audit = subprocess.run(['/data/jaguir26/local/opt/R/4.6.0/bin/Rscript',
        str(HERE / '457_audit_pricefm_stage_r129_al_fixedpoint.R'), '--config', str(path)],
        env=env, capture_output=True, text=True)
    assert audit.returncode == 0, audit.stdout + audit.stderr
    result = CTL.read(tmp_path / 'certificate/certificate.json')
    assert result['certified']
    assert result['original_formal_converged'] == old['formal_converged']
    assert result['no_model_fit_performed']


def test_real_certified_public_fit_entrypoint(tmp_path):
    import numpy as np
    rng = np.random.default_rng(129)
    X = np.column_stack((np.ones(160), rng.normal(size=(160, 4))))
    y = X @ np.array([.2, .5, -.3, .1, -.1]) + rng.normal(0, .3, 160)
    design = tmp_path / 'design'; design.mkdir()
    X.astype('<f8').tofile(design / 'X.bin'); y.astype('<f8').tofile(design / 'y.bin')
    CTL.write(design / 'design.json', dict(n=160, p=5, feature_names=['intercept', 'h1', 'h2', 'h3', 'h4']))
    CTL.write(design / 'terminal.json', dict(test_opened=False))
    parent = tmp_path / 'parent'; parent.mkdir()
    np.linalg.lstsq(X, y, rcond=None)[0].astype('<f8').tofile(parent / 'beta_mean.bin')
    (np.eye(5) * .01).astype('<f8').tofile(parent / 'beta_cov.bin')
    CTL.write(parent / 'terminal.json', dict(independent_fixedpoint_certified=True,
        tau=.5, tau0=.1, p=5, sigma=.1, formal_converged=False))
    CTL.write(parent / 'certificate.json', dict(certified=True))
    adapter = DEPENDENCY / 'application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R'
    files = [CTL.HELPER, adapter, design / 'design.json', design / 'terminal.json',
        parent / 'beta_mean.bin', parent / 'beta_cov.bin', parent / 'terminal.json', parent / 'certificate.json']
    config = dict(stage='R129', action='public_AL_fit', test_opened=False, output_dir=str(tmp_path / 'fit'),
        input_sha256={str(f): CTL.digest(f) for f in files}, cran_adapter=str(adapter), helper=str(CTL.HELPER),
        cran_library=str(CTL.DATA / 'runtime_libraries/exdqlm_cran_1p1p1'), design_dir=str(design),
        parent_dir=str(parent), tau=.45, tau0=.1, fold=1, max_iter=1000, tol=1e-8, n_samp=20,
        seed=129, limits=P['certificate_limits'], max_rhs_iter=P['max_rhs_iter'], posterior_target_sha256='test-target')
    path = tmp_path / 'config.json'; CTL.write(path, config)
    run = subprocess.run(['/data/jaguir26/local/opt/R/4.6.0/bin/Rscript',
        str(HERE / '458_fit_pricefm_stage_r129_certified_al.R'), '--config', str(path)],
        env=dict(os.environ, OPENBLAS_NUM_THREADS='1', OMP_NUM_THREADS='1', MKL_NUM_THREADS='1'),
        capture_output=True, text=True)
    assert run.returncode == 0, run.stdout + run.stderr
    terminal = CTL.read(tmp_path / 'fit/terminal.json')
    certificate = CTL.read(tmp_path / 'fit/certificate.json')
    assert terminal['public_cran_version'] == '1.1.1'
    assert terminal['finite_core'] and not terminal['prior_center_from_initializer']
    assert terminal['independent_fixedpoint_certified'] == certificate['certified']
    assert certificate['certified']
    assert not (tmp_path / 'fit/fit.rds').exists()


def test_same_state_certificate_not_lookahead():
    text = CTL.HELPER.read_text()
    assert 'rhs_joint_residual <- r129_rhs_block_residual(prior, first$state, m, V)' in text
    assert 'rhs_lookahead_log_rates_not_stationarity_gate = rhs_lookahead_residual' in text
    assert P['certificate_limits']['rhs_joint_log_rates'] == 1e-6
    assert P['al_computational_stop_tol'] == 1e-5
