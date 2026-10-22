"""No live processes/services: exercise ownership, rollback and worker boundaries."""
import importlib.util
import json
import os
from pathlib import Path
import signal

import pytest

ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT / 'application/scripts/pricefm/491_supervise_pricefm_stage_r146_resource_handoff.py'
spec = importlib.util.spec_from_file_location('r146_resource_test', ENTRY)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)


def process(pid=100, state='T', start=77):
    return {'pid': pid, 'start_ticks': start, 'boot_id': 'boot',
            'cmdline_sha256': 'command', 'cwd': '/frozen', 'state': state,
            'cgroups': ['/user.slice/old.service'], 'command': 'verified supervisor'}


class Fake:
    def __init__(self, config):
        self.config = config; self.signals = []; self.starts = []; self.stops = []
        self.processes = {100: process(), 200: process(200, 'S')}
        self.unit_values = {
            config['old_unit']: {'MainPID': '100', 'ControlGroup': '/user.slice/old.service',
                'KillMode': 'control-group', 'Restart': 'no', 'ActiveState': 'active',
                'WorkingDirectory': '/frozen', 'ExecStart': 'verified'},
            config['new_unit']: {'MainPID': str(os.getpid()), 'ControlGroup': '/user.slice/new.service',
                'KillMode': 'process', 'Restart': 'on-failure', 'ActiveState': 'active'},
            config['fallback_unit']: {'MainPID': '0', 'ControlGroup': '', 'ActiveState': 'inactive'},
            'guardian.service': {'ActiveState': 'active'},
        }
        self.group_values = {'/user.slice/old.service': [100]}

    def unit(self, name): return dict(self.unit_values[name])
    def process(self, pid): return self.processes.get(pid)
    def members(self, cgroup, **kwargs): return self.group_values.get(cgroup, [])
    def signal(self, pid, value): self.signals.append((pid, value))
    def start(self, name): self.starts.append(name)
    def stop(self, name):
        self.stops.append(name)
        self.unit_values[name].update(ActiveState='inactive', MainPID='0', ControlGroup='')


@pytest.fixture
def scenario(tmp_path, monkeypatch):
    config = m.read(ROOT / 'application/config/pricefm_stage_r146_resource_handoff_20261022.json')
    config['old_runtime'] = str(tmp_path / 'old')
    config['fallback_runtime_terminal'] = str(tmp_path / 'at/terminal.json')
    system = Fake(config); owner = process(200, 'S')
    monkeypatch.setattr(m, 'freeze_old', lambda config: {'head': 'frozen'})
    receipt = {'old_frozen': {'head': 'frozen'}, 'old_unit': system.unit(config['old_unit']), 'old_process': process(),
               'source': {'head': 'head'}, 'config': config}
    state = {'attempt': 'one', 'phase': 'waiting_boundary', 'owner': owner,
             'audit': receipt, 'heartbeat': 10, 'guardian_unit': 'guardian.service'}
    runtime = tmp_path / 'resource'; runtime.mkdir()
    m.atomic(runtime / 'state.json', state)
    monkeypatch.setattr(m, 'source_identity', lambda: {'head': 'head'})
    return runtime, config, system, state


def prepare_gates(config):
    old = Path(config['old_runtime'])
    m.atomic(old / 'at.terminal.json', {'status': 'R145_LANE_DRAINED_WITH_QUARANTINED_FAILURES'})
    m.atomic(old / 'quarantine/AT.json', {'region': 'AT'})
    m.atomic(config['fallback_runtime_terminal'], {'status': 'R146_AT_FALLBACK_QUARANTINED_NOT_PROMOTED',
             'region': 'AT', 'source': {'head': 'head'}})


def test_waits_for_both_at_receipts_and_no_fallback_children(scenario):
    _, config, system, _ = scenario
    assert not m.gates(config, system)[0]
    prepare_gates(config)
    assert m.gates(config, system)[0]
    system.unit_values[config['fallback_unit']].update(ControlGroup='/user.slice/at.service')
    system.group_values['/user.slice/at.service'] = [301]
    assert not m.gates(config, system)[0]
    assert system.signals == []


def test_rejects_fallback_from_different_source(scenario):
    _, config, system, _ = scenario; prepare_gates(config)
    value = m.read(config['fallback_runtime_terminal']); value['source']['head'] = 'other'
    m.atomic(config['fallback_runtime_terminal'], value)
    with pytest.raises(RuntimeError, match='source differs'):
        m.gates(config, system)


def test_old_at_workers_prevent_pause_gate(scenario):
    _, config, system, _ = scenario; prepare_gates(config)
    system.group_values['/user.slice/old.service'] = [100, 300]
    system.processes[300] = dict(process(300, 'R'), command='Rscript /contracts/iq_AT_example')
    assert not m.gates(config, system)[0]
    assert system.signals == []


@pytest.mark.parametrize('difference', ['start_ticks', 'boot_id', 'cmdline_sha256', 'cwd'])
def test_pid_reuse_or_process_drift_never_signals(scenario, difference):
    runtime, config, system, _ = scenario
    system.processes[100][difference] = 'different'
    with pytest.raises(RuntimeError, match='identity changed'):
        m.rollback(runtime, config, system, 'test', 'one')
    assert system.signals == []


def test_guardian_resumes_only_old_supervisor_after_owner_dies(scenario):
    runtime, config, system, _ = scenario
    del system.processes[200]
    assert m.guardian_once(runtime, config, system, 'one', now=11) == 'exit'
    assert system.signals == [(100, signal.SIGCONT)]
    assert m.read(runtime / 'state.json')['phase'] == 'rolled_back'
    assert system.stops == []


def test_lease_expiry_rolls_back_and_cannot_be_overwritten(scenario):
    runtime, config, system, state = scenario
    m.guardian_once(runtime, config, system, 'one', now=1000)
    with pytest.raises(RuntimeError, match='rolled back'):
        m.state_update(runtime, {'phase': 'waiting_boundary'}, owner=state['owner'],
                       attempt='one', allowed_phases=m.PRECOMMIT)
    assert system.signals == [(100, signal.SIGCONT)]


def test_healthy_child_or_preparation_prevents_commit_and_stop(scenario):
    runtime, config, system, state = scenario; prepare_gates(config)
    system.group_values['/user.slice/old.service'] = [100, 300]
    with pytest.raises(RuntimeError, match='healthy work or preparation'):
        m.ready_to_commit(runtime, config, system, state['owner'], 'one')
    assert m.read(runtime / 'state.json')['phase'] == 'waiting_boundary'
    assert system.stops == [] and system.signals == []


def test_dead_guardian_prevents_commit(scenario):
    runtime, config, system, state = scenario; prepare_gates(config)
    system.unit_values['guardian.service']['ActiveState'] = 'failed'
    with pytest.raises(RuntimeError, match='guardian is not active'):
        m.ready_to_commit(runtime, config, system, state['owner'], 'one')
    assert system.stops == []


def test_commit_is_one_way_and_stop_checks_empty_cgroup(scenario):
    runtime, config, system, state = scenario; prepare_gates(config)
    value = m.ready_to_commit(runtime, config, system, state['owner'], 'one')
    assert value['phase'] == 'committed'
    assert not m.rollback(runtime, config, system, 'post_commit_error', 'one')
    system.group_values['/user.slice/old.service'] = [100, 300]
    with pytest.raises(RuntimeError, match='gained children'):
        m.finish_old_stop(runtime, config, system, state['owner'], 'one')
    assert system.stops == []
    system.group_values['/user.slice/old.service'] = [100]
    m.finish_old_stop(runtime, config, system, state['owner'], 'one')
    assert system.stops == [config['old_unit']]
    assert system.signals == []


def test_postcommit_owner_death_starts_new_service_never_old(scenario):
    runtime, config, system, _ = scenario
    m.state_update(runtime, {'phase': 'committed'})
    del system.processes[200]
    assert m.guardian_once(runtime, config, system, 'one', now=1000) == 'exit'
    assert system.starts == [config['new_unit']]
    assert system.signals == []


def test_new_service_cannot_kill_healthy_child_on_restart(scenario):
    _, config, system, _ = scenario
    m.require_resource_service(config, system)
    system.unit_values[config['new_unit']]['KillMode'] = 'control-group'
    with pytest.raises(RuntimeError, match='KillMode=process'):
        m.require_resource_service(config, system)


def test_stale_guardian_cannot_touch_a_new_attempt(scenario):
    runtime, config, system, _ = scenario
    m.state_update(runtime, {'attempt': 'two'})
    assert m.guardian_once(runtime, config, system, 'one', now=1000) == 'exit'
    assert system.signals == [] and system.starts == []


def test_static_allocation_never_includes_protected_slot_b(scenario):
    _, config, _, _ = scenario
    m.validate_config(config)
    config['cpus'] = list(range(30))
    with pytest.raises(RuntimeError, match='bounded Muscat queue'):
        m.validate_config(config)


def test_relative_supervisor_entry_is_resolved_against_verified_cwd():
    proc = dict(process(), argv=['/python', '-B', 'application/scripts/pricefm/488.py', 'run'])
    assert m.entry_matches(proc, '/frozen/application/scripts/pricefm/488.py')
    assert not m.entry_matches(proc, '/different/application/scripts/pricefm/488.py')


@pytest.mark.parametrize('hierarchy', ['v1', 'v2'])
def test_cgroup_membership_supports_systemd_v1_and_v2(tmp_path, monkeypatch, hierarchy):
    monkeypatch.setattr(m, 'CGROUP_ROOT', tmp_path)
    path = tmp_path / ('systemd' if hierarchy == 'v1' else '') / 'user.slice/old.service'
    path.mkdir(parents=True); (path / 'cgroup.procs').write_text('100\n300\n')
    nested = path / 'worker'; nested.mkdir(); (nested / 'cgroup.procs').write_text('301\n')
    assert m.System({}).members('/user.slice/old.service') == [100, 300, 301]


def test_missing_active_cgroup_fails_closed(tmp_path, monkeypatch):
    monkeypatch.setattr(m, 'CGROUP_ROOT', tmp_path)
    with pytest.raises(RuntimeError, match='not observable'):
        m.System({}).members('/user.slice/missing.service')
    assert m.System({}).members('/user.slice/missing.service', allow_missing=True) == []


def test_orphan_rescue_child_must_finish_before_preparation_or_retry(scenario):
    _, config, system, _ = scenario
    system.group_values['/user.slice/new.service'] = [os.getpid(), 301]
    system.processes[301] = dict(process(301, 'R'), ppid=1,
                                command='Rscript same_target_rescue.R', affinity=[3])
    class Old:
        @staticmethod
        def controller_pid(config, region): return None
    assert m.owned_work_state(config, system, Old, {}, 'DE_LU') == 'waiting_for_orphan_preparation_or_rescue_children'
    assert system.signals == []


def test_adoption_checks_controller_tree_and_actual_worker_affinity(scenario, tmp_path):
    _, config, system, _ = scenario
    m.atomic(tmp_path / 'controller_identity.json', {'pid': 300, 'cpus': config['cpus']})
    system.group_values['/user.slice/new.service'] = [os.getpid(), 300, 301]
    system.processes[300] = dict(process(300, 'S'), ppid=1)
    system.processes[301] = dict(process(301, 'R'), ppid=300, affinity=[8])
    class Old:
        @staticmethod
        def controller_pid(config, region): return 300
        @staticmethod
        def source_campaign(config, region): return tmp_path
    assert m.owned_work_state(config, system, Old, {}, 'DE_LU') == 'adoptable'
    system.processes[301]['affinity'] = [20]
    assert m.owned_work_state(config, system, Old, {}, 'DE_LU') == 'waiting_for_owned_worker_affinity_validation'


def test_health_error_with_live_controller_never_advances_queue(scenario, monkeypatch):
    runtime, config, system, _ = scenario
    called = []
    class Old:
        @staticmethod
        def validate_static(config): pass
        @staticmethod
        def source_identity(): return {'head': config['old_head']}
        @staticmethod
        def scheduler_pids(config): return [9]
        @staticmethod
        def scheduler_failure(config): pass
        @staticmethod
        def region_complete(config, region): return False
        @staticmethod
        def source_campaign(config, region): return runtime / 'nonexistent'
        @staticmethod
        def controller_pid(config, region): return 300
        @staticmethod
        def run_region(*args):
            called.append(args[3]); raise RuntimeError('resource reserve crossed while monitoring')
        @staticmethod
        def health(config): return {'healthy': False}
    monkeypatch.setattr(m, 'load_old', lambda config: Old)
    monkeypatch.setattr(m, 'install_scheduler_guard', lambda *args: 9)
    monkeypatch.setattr(m, 'read', lambda path: {} if str(path) == config['old_config'] else json.loads(Path(path).read_text()))
    monkeypatch.setattr(m, 'wait_owned_work', lambda *args: 'adoptable')
    monkeypatch.setattr(m, 'owned_processes', lambda *args: [process(300, 'R')])
    with pytest.raises(RuntimeError, match='resource reserve'):
        m.drain(runtime, config, system)
    assert called == ['DE_LU']
    assert not (runtime / 'continuation/quarantine/DE_LU.json').exists()


def test_pause_and_guardian_rollback_are_serialized(scenario):
    import threading
    runtime, config, system, state = scenario
    m.state_update(runtime, {'phase': 'armed'})
    del system.processes[200]
    worker = []
    def send(pid, value):
        system.signals.append((pid, value))
        if value == signal.SIGSTOP:
            thread = threading.Thread(target=lambda: m.guardian_once(
                runtime, config, system, 'one', now=10**20))
            worker.append(thread); thread.start()
    system.signal = send
    m.pause_old(runtime, config, system, state['owner'], 'one')
    worker[0].join(timeout=3)
    assert not worker[0].is_alive()
    assert system.signals == [(100, signal.SIGSTOP), (100, signal.SIGCONT)]
    assert m.read(runtime / 'state.json')['phase'] == 'rolled_back'
    with pytest.raises(RuntimeError, match='rolled back'):
        m.pause_old(runtime, config, system, state['owner'], 'one')


def test_source_drift_prevents_signal_and_commit(scenario, monkeypatch):
    runtime, config, system, state = scenario
    monkeypatch.setattr(m, 'freeze_old', lambda config: {'head': 'changed'})
    m.state_update(runtime, {'phase': 'armed'})
    with pytest.raises(RuntimeError, match='frozen source'):
        m.pause_old(runtime, config, system, state['owner'], 'one')
    assert system.signals == []


def test_already_drained_inactive_old_queue_needs_no_takeover(scenario, monkeypatch):
    _, config, system, _ = scenario
    system.unit_values[config['old_unit']].update(ActiveState='inactive', MainPID='0', ControlGroup='')
    monkeypatch.setattr(m, 'load_old', lambda config: object())
    monkeypatch.setattr(m, 'read', lambda path: {})
    monkeypatch.setattr(m, 'verify_region_closeout', lambda *args: True)
    result = m.original_queue_finished(config, system)
    assert result['completed'] == m.QUEUE and result['no_takeover_required']
    assert system.signals == [] and system.stops == []


def test_original_scheduler_exit_requires_complete_sealed_slot_b(scenario, monkeypatch, tmp_path):
    runtime, config, system, _ = scenario
    config['old_runtime'] = str(tmp_path / 'launch_prep/r145/muscat')
    old_config = {'source_tag': 'r141', 'source_worktree': str(tmp_path / 'source'), 'source_head': 'r141head'}
    source_path = tmp_path / 'source/application/config/pricefm_stage_r141_recovery_rollout_20261019.json'
    m.atomic(source_path, {'host_queues': {'muscat': {'slot_b': ['BG', 'GR']}}})
    block = tmp_path / 'launch_prep/r141/host_scheduler/muscat/blocked.json'
    m.atomic(block, {'status': 'blocked', 'host': 'muscat', 'source': {'head': 'r141head'},
                    'active': {}, 'failures': [{'slot': 'slot_a', 'region': 'AT'}]})
    class Old:
        @staticmethod
        def controller_pid(config, region): return None
    monkeypatch.setattr(m, 'verify_region_closeout', lambda *args: False)
    with pytest.raises(RuntimeError, match='not all sealed'):
        m.protected_scheduler_exit_proof(runtime, config, system, Old, old_config)
    monkeypatch.setattr(m, 'verify_region_closeout', lambda *args: True)
    proof = m.protected_scheduler_exit_proof(runtime, config, system, Old, old_config)
    assert proof['protected_cpus_reused'] is False
    assert system.signals == []


def test_current_noneligible_failure_is_not_silently_retried(tmp_path):
    folder = tmp_path / 'region'
    m.atomic(folder / 'blocked.json', {'error': 'worker failure'})
    m.atomic(folder / 'launched/bad.json', {'pid': 9})
    m.atomic(folder / 'tasks/bad.json', {'kind': 'internal_al'})
    class Rescue:
        @staticmethod
        def eligible_tasks(config, region): return []
        @staticmethod
        def verified(folder): return {'certified': True}
    class Old:
        R142 = Rescue
        @staticmethod
        def source_campaign(config, region): return folder
    assert m.noneligible_blocked_tasks(Old, {}, 'DE_LU') == ['bad']
    m.atomic(folder / 'tasks_done/bad/completed_evidence.json', {'metadata': {'certified': True}})
    assert m.noneligible_blocked_tasks(Old, {}, 'DE_LU') == []


def test_committed_restart_can_launch_a_distinct_guardian(scenario, monkeypatch):
    runtime, config, _, _ = scenario
    commands = []
    monkeypatch.setattr(m.subprocess, 'run', lambda command, **kwargs: commands.append(command))
    system = m.System(config)
    monkeypatch.setattr(system, 'unit', lambda name: {'ActiveState': 'active',
        'ControlGroup': '/user.slice/new.service' if name == config['new_unit'] else '/user.slice/guardian.service'})
    one = system.guardian(Path('/config'), runtime, 'sameattempt')
    two = system.guardian(Path('/config'), runtime, 'sameattempt')
    assert one != two
    assert '--property=KillMode=process' in commands[0]


def test_exhausted_rescue_quarantines_only_after_children_exit(scenario, monkeypatch):
    runtime, config, system, _ = scenario
    calls = []
    class Old:
        @staticmethod
        def validate_static(config): pass
        @staticmethod
        def source_identity(): return {'head': config['old_head']}
        @staticmethod
        def region_complete(config, region): return False
        @staticmethod
        def source_campaign(config, region): return runtime / 'nonexistent'
        @staticmethod
        def controller_pid(config, region): return None
        @staticmethod
        def run_region(*args):
            calls.append(args[3]); raise RuntimeError('bounded rescue exhausted without certification: task')
        @staticmethod
        def health(config): return {'healthy': True}
        @staticmethod
        def lane_progress(config, lane, region, complete, failures, pid):
            return {'failures': failures, 'completed': complete}
    monkeypatch.setattr(m, 'load_old', lambda config: Old)
    monkeypatch.setattr(m, 'install_scheduler_guard', lambda *args: 9)
    monkeypatch.setattr(m, 'read', lambda path: {} if str(path) == config['old_config'] else json.loads(Path(path).read_text()))
    monkeypatch.setattr(m, 'wait_owned_work', lambda *args: 'clear')
    monkeypatch.setattr(m, 'noneligible_blocked_tasks', lambda *args: [])
    monkeypatch.setattr(m, 'owned_processes', lambda *args: [])
    value = m.drain(runtime, config, system)
    assert calls == m.QUEUE and len(value['failures']) == len(m.QUEUE)
    assert (runtime / 'continuation/quarantine/DE_LU.json').is_file()
