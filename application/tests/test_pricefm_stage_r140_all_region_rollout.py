"""Contract tests for the frozen two-host PriceFM R140 rollout."""
import inspect
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest

for name in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS', 'BLIS_NUM_THREADS'):
    os.environ[name] = '1'
os.environ.setdefault('PRICEFM_R140_REGION', 'AT')

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'application/scripts/pricefm'
sys.path.insert(0, str(HERE))
import pricefm_r134_core as core

if 'PRICEFM_R140_DEPENDENCY' not in os.environ:
    pytest.skip('R140 tests require the exact frozen dependency worktree', allow_module_level=True)
DEPENDENCY = Path(os.environ['PRICEFM_R140_DEPENDENCY'])
CTL = core.module('pricefm_r140_test_controller', HERE / '476_run_pricefm_stage_r140_region.py')
SCHED = core.module('pricefm_r140_test_scheduler', HERE / '478_schedule_pricefm_stage_r140_host.py')
CLOSE = core.module('pricefm_r140_test_closeout', HERE / '479_closeout_pricefm_stage_r140_all_region.py')
CTL.setup(DEPENDENCY)
PROTOCOL = json.loads((ROOT / 'application/config/pricefm_stage_r140_frozen_all_region_rollout_20261018.json').read_text())
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


def test_r140_protocol_and_r137_scientific_fields_are_exactly_compatible():
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
    env = dict(os.environ, PRICEFM_R140_REGION='EE')
    result = subprocess.run([sys.executable, '-c',
        "import importlib.util,sys; sys.path.insert(0,'application/scripts/pricefm'); "
        "p='application/scripts/pricefm/476_run_pricefm_stage_r140_region.py'; "
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
    assert 'R140_REGION_COMPLETE_NOT_PROMOTED' in source


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
