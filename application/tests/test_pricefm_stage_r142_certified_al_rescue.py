import importlib.util
import json
import os
from pathlib import Path
import subprocess

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'application/scripts/pricefm'
spec = importlib.util.spec_from_file_location('r142', HERE / '484_run_pricefm_stage_r142_certified_al_rescue.py')
R142 = importlib.util.module_from_spec(spec); spec.loader.exec_module(R142)
CONFIG = json.loads((ROOT / 'application/config/pricefm_stage_r142_certified_al_rescue_20261020.json').read_text())


def test_protocol_is_bounded_target_preserving_and_non_promotional():
    assert CONFIG['fit_max_iter_per_attempt'] == 300
    assert CONFIG['maximum_rescue_attempts'] == 2
    assert CONFIG['warm_start_components'] == ['beta_mean', 'likelihood_scale']
    for key in ('posterior_target_changes_authorized', 'certificate_limit_changes_authorized',
                'test_based_rescue_authorized', 'registry_mutation_authorized',
                'article_mutation_authorized', 'promotion_authorized'):
        assert CONFIG[key] is False
    source = (HERE / '484_run_pricefm_stage_r142_certified_al_rescue.py').read_text()
    fitter = (HERE / '483_fit_pricefm_stage_r142_same_target_al_rescue.R').read_text()
    assert 'exact_optimizer_resumption = FALSE' in fitter
    assert "prior_center_from_initializer = FALSE" in fitter
    assert "posterior_target_changed = FALSE" in fitter
    assert "certificate_limits_changed = FALSE" in fitter
    assert 'bridge withheld until every rescue certifies' in source
    assert "result.get('certified') is not False" in source


def test_atomic_bridge_retains_original_and_installs_certified_replacement(tmp_path):
    old_data = R142.DATA; R142.DATA = tmp_path
    try:
        config = dict(CONFIG, source_tag='source')
        campaign = tmp_path / 'campaigns/source__CZ'
        name = 'iq_CZ_candidate_s1_al0.50'
        task = {'name': name, 'kind': 'internal_al', 'region': 'CZ', 'split': 1, 'tau': .5}
        task_path = campaign / 'tasks' / (name + '.json'); R142.atomic_json(task_path, task)
        original = campaign / 'tasks_done' / name; original.mkdir(parents=True)
        R142.atomic_json(original / 'result.json', {'certified': False, 'split': 1, 'tau': .5})
        (original / 'payload.bin').write_bytes(b'original')
        R142.seal(original, {'certified': False, 'source_head': config['source_head'],
                             'task_sha256': R142.sha256(task_path)})
        promoted = tmp_path / 'campaigns' / config['tag'] / 'CZ/tasks' / name / 'promoted_task'
        (promoted / 'fit').mkdir(parents=True)
        R142.atomic_json(promoted / 'fit/terminal.json', {'computationally_certified': True})
        R142.atomic_json(promoted / 'result.json', {'certified': True, 'split': 1, 'tau': .5})
        R142.atomic_json(promoted / 'rescue_provenance.json', {'stage': 'R142'})
        R142.seal(promoted, {'certified': True, 'source_head': 'rescue-head',
                             'task_sha256': R142.sha256(task_path)})
        item = {'name': name, 'task': task, 'task_path': task_path, 'folder': original}
        R142.bridge_region(config, {'branch': 'work/pricefm-r142-test', 'head': 'rescue-head'}, 'CZ', [item])
        assert R142.verified(campaign / 'tasks_done' / name)['certified'] is True
        backup = campaign / 'uncertified_attempts' / (name + '.r141_original')
        assert R142.verified(backup)['certified'] is False
        assert (backup / 'payload.bin').read_bytes() == b'original'
    finally:
        R142.DATA = old_data


def test_real_cran_111_same_target_rescue_boundary(tmp_path):
    rng = np.random.default_rng(142)
    X = np.column_stack((np.ones(100), rng.normal(size=(100, 3))))
    y = X @ np.array([.2, .45, -.2, .1]) + rng.normal(0, .25, 100)
    design = tmp_path / 'design'; design.mkdir()
    np.asarray(X, dtype='<f8').tofile(design / 'X.bin')
    np.asarray(y, dtype='<f8').tofile(design / 'y.bin')
    R142.atomic_json(design / 'design.json', {'n': len(y), 'p': X.shape[1],
        'feature_names': ['intercept', 'layer1::1', 'layer1::2', 'layer1::3']})
    files = {name: R142.sha256(design / name) for name in ('X.bin', 'y.bin', 'design.json')}
    R142.atomic_json(design / 'terminal.json', {'status': 'completed_r137_quantile_design',
        'test_opened': False, 'files': files})

    source = tmp_path / 'source'; source.mkdir()
    beta = np.linalg.lstsq(X, y, rcond=None)[0]
    np.asarray(beta, dtype='<f8').tofile(source / 'beta_mean.bin')
    R142.atomic_json(source / 'terminal.json', {'finite_core': True,
        'computationally_certified': False, 'test_opened': False,
        'prior_center_from_initializer': False, 'posterior_target_sha256': 'same-target',
        'tau': .5, 'tau0': .1, 'sigma': .3, 'iterations': 300})

    library = R142.DATA / 'runtime_libraries/exdqlm_cran_1p1p1'
    manifest = library / 'pricefm_r67_cran111_install_manifest.json'
    if not manifest.is_file():
        import pytest
        pytest.skip('audited local CRAN exdqlm 1.1.1 runtime is unavailable')
    adapter = HERE / 'pricefm_stage_r67_cran111_adapter.R'
    helper = ROOT / 'application/R/pricefm_r129_al_fixedpoint_certificate.R'
    limits = {'beta_posterior_sd_rms': 1e-4, 'predictor_rms': 1e-6,
              'covariance_whitened_rms': 1e-4, 'sigma_relative': 1e-6,
              'rhs_joint_log_rates': 1e-6, 'rhs_start_log_precision': 1e-6,
              'elbo_relative': 1e-8}
    contract = {'stage': 'R142', 'family': 'al', 'output_dir': str(tmp_path / 'fit'),
        'design_dir': str(design), 'source_fit_dir': str(source),
        'source_terminal_sha256': R142.sha256(source / 'terminal.json'),
        'source_beta_mean_sha256': R142.sha256(source / 'beta_mean.bin'),
        'design_terminal_sha256': R142.sha256(design / 'terminal.json'),
        'cran_library': str(library), 'cran_manifest': str(manifest),
        'cran_manifest_sha256': R142.sha256(manifest), 'cran_adapter': str(adapter),
        'cran_adapter_sha256': R142.sha256(adapter), 'fixedpoint_helper': str(helper),
        'fixedpoint_helper_sha256': R142.sha256(helper), 'certificate_limits': limits,
        'max_rhs_iter': 20000, 'max_iter': 300, 'tol': 1e-5, 'n_samp': 20,
        'n_samp_xi': 20, 'seed': 142, 'attempt_index': 1, 'maximum_rescue_attempts': 2,
        'prior_attempt_iterations': 300, 'posterior_target_sha256': 'same-target',
        'tau': .5, 'tau0': .1, 'fold': 1, 'test_opened': False,
        'prior_center_from_initializer': False, 'posterior_target_changed': False,
        'certificate_limits_changed': False, 'exact_optimizer_resumption': False}
    contract_path = tmp_path / 'contract.json'; R142.atomic_json(contract_path, contract)
    env = dict(os.environ)
    env['LD_LIBRARY_PATH'] = str(R142.R_LIBRARY_DIR) + ':' + env.get('LD_LIBRARY_PATH', '')
    result = subprocess.run([str(R142.RSCRIPT), str(HERE / '483_fit_pricefm_stage_r142_same_target_al_rescue.R'),
                             '--config', str(contract_path)], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    terminal = json.loads((tmp_path / 'fit/terminal.json').read_text())
    assert terminal['finite_core'] and terminal['computationally_certified']
    assert terminal['posterior_target_sha256'] == 'same-target'
    assert terminal['posterior_target_changed'] is False
    assert terminal['prior_center_from_initializer'] is False
    assert terminal['exact_optimizer_resumption'] is False
