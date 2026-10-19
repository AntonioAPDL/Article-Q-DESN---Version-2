"""Contract and integration tests for the two-host PriceFM R141 recovery."""
import inspect
import json
import os
from pathlib import Path
import subprocess
import sys

import numpy as np
import pytest

for name in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS', 'BLIS_NUM_THREADS'):
    os.environ[name] = '1'
os.environ.setdefault('PRICEFM_R141_REGION', 'AT')

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'application/scripts/pricefm'
sys.path.insert(0, str(HERE))
import pricefm_r134_core as core

if 'PRICEFM_R141_DEPENDENCY' not in os.environ:
    pytest.skip('R141 tests require the exact frozen dependency worktree', allow_module_level=True)
DEPENDENCY = Path(os.environ['PRICEFM_R141_DEPENDENCY'])
CTL = core.module('pricefm_r141_test_controller', HERE / '480_run_pricefm_stage_r141_region.py')
SCHED = core.module('pricefm_r141_test_scheduler', HERE / '482_schedule_pricefm_stage_r141_host.py')
CLOSE = core.module('pricefm_r141_test_closeout', HERE / '483_closeout_pricefm_stage_r141_all_region.py')
CTL.setup(DEPENDENCY)
PROTOCOL = json.loads((ROOT / 'application/config/pricefm_stage_r141_recovery_rollout_20261019.json').read_text())
R137 = json.loads((ROOT / 'application/config/pricefm_stage_r137_four_region_pilot_20261015.json').read_text())


def test_universe_is_exactly_38_regions_and_114_fold_cells():
    assert len(PROTOCOL['regions']) == len(set(PROTOCOL['regions'])) == 38
    assert len(PROTOCOL['regions']) * len(PROTOCOL['folds']) == 114
    assert set(PROTOCOL['reuse_regions']) == {'EE', 'HU', 'IT_NORD', 'SK'}


def test_two_host_queues_partition_exactly_the_34_unfinished_regions():
    queued = [region for host in PROTOCOL['host_queues'].values()
              for queue in host.values() for region in queue]
    assert len(queued) == len(set(queued)) == 34
    assert set(queued) == set(PROTOCOL['regions']) - set(PROTOCOL['reuse_regions'])
    assert {sum(map(len, host.values())) for host in PROTOCOL['host_queues'].values()} == {17}


def test_each_host_uses_two_disjoint_fifteen_physical_core_slots():
    sets = PROTOCOL['host_cpu_sets']
    assert len(sets['slot_a']) == len(sets['slot_b']) == 15
    assert set(sets['slot_a']).isdisjoint(sets['slot_b'])
    topology = SCHED.physical_topology()
    assert len({topology[cpu] for values in sets.values() for cpu in values}) == 30


def test_r141_protocol_and_r137_scientific_fields_are_exactly_compatible():
    CTL.validate_protocol(PROTOCOL)
    assert CTL.validate_r137_compatibility(PROTOCOL)
    orchestration = {'tag', 'regions', 'regional_roles', 'host_allocation',
                     'region_seed_offsets', 'all_region_launch_authorized'}
    for key, value in R137.items():
        if key not in orchestration:
            assert PROTOCOL[key] == value


def test_reused_region_seed_offsets_and_evidence_hashes_are_frozen():
    for region, offset in R137['region_seed_offsets'].items():
        assert PROTOCOL['region_seed_offsets'][region] == offset
        assert len(PROTOCOL['reuse_source']['regions'][region]['completed_evidence_sha256']) == 64
    assert PROTOCOL['reuse_source']['head'] == 'd83b62d77a11fd4df4640bf33efbd9c10faef570'


def test_controller_refuses_to_refit_a_reused_region():
    env = dict(os.environ, PRICEFM_R141_REGION='EE')
    result = subprocess.run([sys.executable, '-c',
        "import importlib.util,sys; sys.path.insert(0,'application/scripts/pricefm'); "
        "p='application/scripts/pricefm/480_run_pricefm_stage_r141_region.py'; "
        "s=importlib.util.spec_from_file_location('x',p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)"],
        cwd=ROOT, env=env, capture_output=True, text=True)
    assert result.returncode != 0 and '34 non-reused regions' in result.stderr


def test_controller_preserves_r137_al_engine_and_exact_300_iteration_target():
    source = inspect.getsource(CTL.execute)
    fitter = (HERE / '470_fit_pricefm_stage_r137_certified_al_300.R').read_text()
    assert "stage='R137', model_stage='R137'" in source
    assert "HERE / '470_fit_pricefm_stage_r137_certified_al_300.R'" in source
    assert "c$max_iter == 300L" in fitter
    assert PROTOCOL['al_max_iter'] == 300


@pytest.mark.parametrize('field', ['mcmc_authorized', 'joint_authorized', 'exal_authorized',
    'registry_mutation_authorized', 'article_mutation_authorized', 'promotion_authorized',
    'priors_from_initializers'])
def test_forbidden_scientific_or_authority_expansion(field):
    with pytest.raises(ValueError):
        CTL.validate_protocol(dict(PROTOCOL, **{field: True}))


def test_all_region_computation_is_authorized_but_promotion_is_not():
    assert PROTOCOL['all_region_launch_authorized'] is True
    assert PROTOCOL['promotion_authorized'] is False
    source = inspect.getsource(CTL.closeout)
    assert 'authority_replaced=False' in source
    assert 'R141_REGION_COMPLETE_NOT_PROMOTED' in source


def test_scheduler_has_health_gates_without_a_campaign_size_cap():
    source = inspect.getsource(SCHED.run) + inspect.getsource(SCHED.health)
    assert 'host_minimum_free_disk_GiB' in source
    assert 'host_minimum_free_memory_GiB' in source
    assert 'campaign_size_cap_GiB' not in source
    assert 'kill' not in source and 'terminate' not in source


def test_scheduler_launches_one_controller_per_slot_with_exact_cpu_set():
    source = inspect.getsource(SCHED.launch_region)
    assert "config['host_cpu_sets'][slot]" in source
    assert "'--workers', str(len(cpus))" in source
    assert "'--cpus', ','.join(map(str, cpus))" in source


def test_scheduler_is_resumable_and_does_not_duplicate_completed_regions():
    source = inspect.getsource(SCHED.run)
    assert 'adopted_pid' in source
    assert 'complete(config, region' in source
    assert 'next_region' in source


def test_closeout_maps_every_region_to_exactly_one_evidence_host():
    assert {CLOSE.region_host(PROTOCOL, region) for region in PROTOCOL['regions']} == {'muscat', 'jerez'}
    for region in PROTOCOL['regions']:
        assert CLOSE.region_host(PROTOCOL, region) in ('muscat', 'jerez')


def test_closeout_requires_all_38_regions_and_never_promotes():
    source = inspect.getsource(CLOSE.collect)
    assert "len(folds) != 114" in source
    assert "'authority_mutated': False" in source
    assert "'article_mutated': False" in source
    assert "'promotion_decided': False" in source


def test_runtime_and_dependency_contracts_remain_pinned():
    assert CTL.RSCRIPT == Path('/data/jaguir26/local/opt/R/4.6.0/bin/Rscript')
    assert PROTOCOL['dependency_head'] == '1e24342e1ecd2dd7a99d8df2445f29be7f7a03d2'
    assert PROTOCOL['paths'] == 500
    assert PROTOCOL['primary_quantile_operator'] == 'cdf_pool_clipped'
    assert PROTOCOL['readout'] == 'intercept_plus_all_layers_no_input_bypass_no_calendar'


def test_recovery_scope_is_exact_and_designs_are_always_regenerated():
    recovery = PROTOCOL['recovery_source']
    assert set(recovery['regions']) == {'AT', 'BG', 'BE', 'CZ'}
    assert set(recovery['allowed_task_kinds']) == {'ridge', 'stats', 'rhs'}
    assert {'internal_design', 'internal_al', 'internal_score', 'design', 'al', 'forecast'} <= set(
        recovery['regenerate_task_kinds'])
    assert PROTOCOL['design_contract_status'] == 'completed_r137_quantile_design'


def test_r141_writer_and_r137_fitter_share_the_exact_design_contract():
    writer = inspect.getsource(CTL.write_quantile_design)
    fitter = (HERE / '470_fit_pricefm_stage_r137_certified_al_300.R').read_text()
    assert "status=status" in writer
    assert "identical(t$status, 'completed_r137_quantile_design')" in fitter
    assert PROTOCOL['design_contract_status'] in fitter


def test_recovery_imports_only_sealed_prerequisites_as_hardlinks(tmp_path, monkeypatch):
    data = tmp_path / 'pricefm'
    current = data / 'campaigns' / (PROTOCOL['tag'] + '__AT')
    recovery = dict(PROTOCOL['recovery_source'], tag='old_r140')
    old = data / 'campaigns/old_r140__AT'
    old_prep = data / 'launch_prep/old_r140__AT/preparation.json'
    ridge = dict(name='AT_candidate', kind='ridge', region='AT', candidate_id='candidate')
    stats = dict(name='stats_AT_candidate_s1', kind='stats', region='AT', split=1)
    rhs = dict(name='rhs_AT_candidate_s1_t1', kind='rhs', region='AT', split=1, tau0=.001)
    excluded = dict(name='iq_AT_candidate_design', kind='internal_design', region='AT', split=1)
    CTL.write(old_prep, dict(source=dict(head=recovery['head']),
        protocol=dict(tag='old_r140__AT', regions=['AT']), source_sha256={}))
    for task in (ridge, stats, rhs, excluded):
        task_path = old / 'tasks' / (task['name'] + '.json')
        CTL.write(task_path, task)
        folder = old / 'tasks_done' / task['name']; folder.mkdir(parents=True)
        CTL.write(folder / 'result.json', dict(certified=True, marker=task['name']))
        CTL.seal(folder, dict(task_sha256=CTL.digest(task_path),
            source_head=recovery['head'], certified=True))
    monkeypatch.setattr(CTL, 'DATA', data)
    monkeypatch.setattr(CTL, 'OUT', current)
    prep = dict(protocol=dict(PROTOCOL, recovery_source=recovery), tasks=[ridge])
    receipt = CTL.import_r140_prerequisites(prep)
    assert receipt['counts'] == {'rhs': 1, 'ridge': 1, 'stats': 1}
    assert not (current / 'tasks_done' / excluded['name']).exists()
    for task in (ridge, stats, rhs):
        source_result = old / 'tasks_done' / task['name'] / 'result.json'
        imported_result = current / 'tasks_done' / task['name'] / 'result.json'
        assert imported_result.is_file()
        assert source_result.stat().st_ino == imported_result.stat().st_ino
        assert CTL.verified(imported_result.parent)
    assert CTL.import_r140_prerequisites(prep) == receipt


def test_scheduler_drains_the_healthy_slot_after_another_slot_fails():
    source = inspect.getsource(SCHED.run)
    assert "slot in {failure['slot'] for failure in failures}" in source
    assert 'healthy_remaining = any(' in source
    assert 'blocked after healthy slots drained' in source
    assert 'if failures:\n                atomic_json(runtime / \'blocked.json\', payload)\n                raise' not in source


def test_generated_r141_design_runs_through_real_cran_al_111(tmp_path):
    design = tmp_path / 'design'
    rng = np.random.default_rng(141)
    X = np.column_stack((np.ones(80), rng.normal(size=(80, 3))))
    y = X @ np.array([.2, .35, -.15, .1]) + rng.normal(0, .2, 80)
    CTL.write_quantile_design(design, X, y, {}, dict(n=len(y), p=X.shape[1],
        feature_names=['intercept', 'layer1::1', 'layer1::2', 'layer1::3'],
        test_opened=False), PROTOCOL['design_contract_status'])
    terminal = json.loads((design / 'terminal.json').read_text())
    assert terminal['status'] == 'completed_r137_quantile_design'
    assert terminal['producer_stage'] == 'R141'

    parent = tmp_path / 'normal'; parent.mkdir()
    np.linalg.lstsq(X, y, rcond=None)[0].astype('<f8').tofile(parent / 'beta_mean.bin')
    CTL.write(parent / 'terminal.json',
        dict(full_variational_certified=True, omega_rate=4., omega_shape=80.))
    manifest = CTL.DATA / 'runtime_libraries/exdqlm_cran_1p1p1/pricefm_r67_cran111_install_manifest.json'
    adapter = DEPENDENCY / 'application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R'
    fixedpoint = ROOT / 'application/R/pricefm_r129_al_fixedpoint_certificate.R'
    contract = dict(stage='R137', model_stage='R137', tag='r141_boundary_smoke', family='al',
        output_dir=str(tmp_path / 'al'), max_iter=300, tau0=.01, tau=.5, fold=1, seed=141,
        tol=1e-5, n_samp=20, n_samp_xi=20, test_opened=False,
        prior_center_from_initializer=False, design_dir=str(design), parent_dir=str(parent),
        parent_type='normal_rhs', design_terminal_sha256=CTL.digest(design / 'terminal.json'),
        parent_terminal_sha256=CTL.digest(parent / 'terminal.json'),
        cran_adapter=str(adapter), cran_adapter_sha256=CTL.digest(adapter),
        cran_manifest=str(manifest), cran_manifest_sha256=CTL.digest(manifest),
        cran_library=str(manifest.parent), fixedpoint_helper=str(fixedpoint),
        fixedpoint_helper_sha256=CTL.digest(fixedpoint),
        certificate_limits=PROTOCOL['certificate_limits'], max_rhs_iter=PROTOCOL['max_rhs_iter'],
        posterior_target_sha256='r141-fixed-target')
    contract_path = tmp_path / 'contract.json'; CTL.write(contract_path, contract)
    env = dict(os.environ)
    env['LD_LIBRARY_PATH'] = str(CTL.R_LIBRARY_DIR) + ':' + env.get('LD_LIBRARY_PATH', '')
    result = subprocess.run([str(CTL.RSCRIPT),
        str(HERE / '470_fit_pricefm_stage_r137_certified_al_300.R'),
        '--config', str(contract_path)], capture_output=True, text=True, env=env)
    assert result.returncode == 0, result.stdout + result.stderr
    fitted = json.loads((tmp_path / 'al/terminal.json').read_text())
    assert fitted['finite_core'] and fitted['computationally_certified']
    assert fitted['package']['version'] == '1.1.1'
    assert fitted['prior_center_from_initializer'] is False
