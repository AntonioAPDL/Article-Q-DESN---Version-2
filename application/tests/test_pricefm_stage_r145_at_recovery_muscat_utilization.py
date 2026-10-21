"""Contract and orchestration tests for the Muscat R145 recovery stage."""
import importlib.util
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'application/scripts/pricefm'
SPEC = importlib.util.spec_from_file_location(
    'r145', HERE / '488_run_pricefm_stage_r145_at_recovery.py')
R145 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R145)
CONFIG = json.loads((
    ROOT / 'application/config/pricefm_stage_r145_at_recovery_muscat_utilization_20261021.json'
).read_text())


def test_contract_partitions_only_failed_muscat_slot_a_and_preserves_target():
    assert R145.validate_static(CONFIG)
    assert CONFIG['blocked_region'] == 'AT'
    assert CONFIG['at_cpus'] == list(range(8))
    assert CONFIG['continuation_cpus'] == list(range(8, 15))
    assert set(CONFIG['at_cpus']).isdisjoint(CONFIG['continuation_cpus'])
    assert CONFIG['fit_max_iter_per_attempt'] == 300
    assert CONFIG['maximum_rescue_attempts'] == 2
    assert CONFIG['warm_start_components'] == ['beta_mean', 'likelihood_scale']
    assert set(CONFIG['frozen_recovery_sha256']) == {
        'application/scripts/pricefm/483_fit_pricefm_stage_r142_same_target_al_rescue.R',
        'application/scripts/pricefm/484_run_pricefm_stage_r142_certified_al_rescue.py',
        'application/tests/test_pricefm_stage_r142_certified_al_rescue.py',
    }
    for key in ('posterior_target_changes_authorized', 'certificate_limit_changes_authorized',
                'test_based_rescue_authorized', 'test_data_access_authorized',
                'registry_mutation_authorized', 'article_mutation_authorized',
                'promotion_authorized'):
        assert CONFIG[key] is False


def test_orchestrator_reuses_certified_rescue_and_frozen_r141_controller():
    source = (HERE / '488_run_pricefm_stage_r145_at_recovery.py').read_text()
    assert '484_run_pricefm_stage_r142_certified_al_rescue.py' in source
    assert 'R142.rescue_region(rescue, identity, region, pending)' in source
    assert "source_controller(config)), 'prepare'" in source
    assert "source_controller(config)), 'controller'" in source
    assert 'posterior_target_changes' in source
    assert 'R145_MUSCAT_SLOT_A_DRAINED_WITH_QUARANTINED_FAILURES' in source


def test_rescue_cycle_is_resumable_and_never_reuses_a_closed_bridge(tmp_path):
    old_data = R145.DATA
    R145.DATA = tmp_path
    try:
        pending = [{'name': 'task_a'}]
        assert R145.next_rescue_cycle(CONFIG, 'AT', pending) == 1
        cycle_one = tmp_path / 'campaigns' / (CONFIG['tag'] + '__AT__cycle_01') / 'AT'
        (cycle_one / 'tasks/task_a').mkdir(parents=True)
        assert R145.next_rescue_cycle(CONFIG, 'AT', pending) == 1
        R145.atomic_json(cycle_one / 'bridge_receipt.json', {'status': 'closed'})
        assert R145.next_rescue_cycle(CONFIG, 'AT', pending) == 2
        cycle_two = tmp_path / 'campaigns' / (CONFIG['tag'] + '__AT__cycle_02') / 'AT'
        (cycle_two / 'tasks/task_b').mkdir(parents=True)
        assert R145.next_rescue_cycle(CONFIG, 'AT', [{'name': 'task_b'}]) == 2
    finally:
        R145.DATA = old_data


def test_interrupted_rescue_attempt_is_preserved_before_restart(tmp_path):
    old_data = R145.DATA
    R145.DATA = tmp_path
    try:
        config = dict(CONFIG, tag='r145__AT__cycle_01', cpus=list(range(8)))
        attempt = tmp_path / 'campaigns/r145__AT__cycle_01/AT/tasks/task_a/attempt_01'
        (attempt / 'fit').mkdir(parents=True)
        (attempt / 'fit/partial.bin').write_bytes(b'partial')
        preserved = R145.preserve_interrupted_attempts(config, 'AT', [{'name': 'task_a'}])
        assert len(preserved) == 1
        destination = Path(preserved[0])
        assert (destination / 'fit/partial.bin').read_bytes() == b'partial'
        assert (destination / 'r145_interruption.json').is_file()
        assert not attempt.exists()
    finally:
        R145.DATA = old_data


def test_queue_lane_quarantines_one_region_and_continues(tmp_path):
    old_complete = R145.region_complete
    old_run = R145.run_region
    old_health = R145.health
    completed = set()
    try:
        R145.region_complete = lambda _config, region: region in completed
        R145.health = lambda _config: {'healthy': True}

        def fake_run(_config, _identity, _audit, region, _cpus, _runtime, _lane, _poll):
            if region == 'FI':
                raise RuntimeError('finite isolated test failure')
            completed.add(region)
            return {'region': region, 'controller_cycles': 0, 'status': 'complete'}

        R145.run_region = fake_run
        runtime = tmp_path / 'runtime'; runtime.mkdir()
        config = dict(CONFIG, continuation_regions=['DE_LU', 'FI', 'IT_CALA'])
        result = R145.drain_lane(config, {'head': 'test'}, {'scheduler_pid': 7},
                                 'continuation', config['continuation_regions'],
                                 config['continuation_cpus'], runtime, 0)
        assert result['completed'] == ['DE_LU', 'IT_CALA']
        assert [item['region'] for item in result['failures']] == ['FI']
        assert (runtime / 'quarantine/FI.json').is_file()
        assert result['status'] == 'R145_LANE_DRAINED_WITH_QUARANTINED_FAILURES'
    finally:
        R145.region_complete = old_complete
        R145.run_region = old_run
        R145.health = old_health
