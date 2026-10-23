"""Adversarial resource-policy tests; no model fits or baseline signals."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('r148_idle', ROOT / 'application/scripts/pricefm/493_supervise_pricefm_stage_r148_ee_idle_resources.py')
M = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(M)


@pytest.fixture
def config(tmp_path):
    value = M.read(M.CONFIG)
    value.update({'data_root': str(tmp_path), 'campaign_root': str(tmp_path / 'campaign'),
                  'runtime': str(tmp_path / 'runtime'), 'handoff_state': str(tmp_path / 'state.json'),
                  'handoff_waiting': str(tmp_path / 'waiting.json')})
    M.atomic(value['handoff_waiting'], {'status': 'waiting_for_both_AT_terminal_receipts', 'worker_signals': 0})
    return value


@pytest.fixture
def lease(monkeypatch):
    monkeypatch.setattr(M, 'process', lambda pid: {'boot_id': 'boot'})
    return {'expires_epoch': M.time.time() + 7200, 'expires_monotonic': M.time.monotonic() + 7200,
            'boot_id': 'boot', 'initial_output_bytes': 0}


def healthy(monkeypatch):
    monkeypatch.setattr(M, 'available_memory', lambda: 300 * M.GIB)
    monkeypatch.setattr(M.shutil, 'disk_usage', lambda path: SimpleNamespace(free=500 * M.GIB))


@pytest.mark.parametrize('field,value', [
    ('max_workers', 3), ('lease_seconds', 7201), ('poll_seconds', 2),
    ('worker_policy', 'SCHED_OTHER'), ('io_class', 'best-effort'), ('numerical_threads', 2),
    ('baseline_signals_authorized', True), ('exclusive_cpu_ownership', True),
    ('allowed_cpus', list(range(31))), ('allowed_task_kinds', ['ridge']),
    ('min_available_memory_gib', 179), ('min_free_disk_gib', 79),
])
def test_config_cannot_expand_authorized_work(config, field, value):
    config[field] = value
    with pytest.raises(RuntimeError):
        M.validate_config(config)


def test_exact_bounded_contract(config):
    M.validate_config(config)
    assert config['allowed_cpus'] == list(range(30))
    assert config['service_properties']['KillMode'] == 'control-group'
    assert config['service_properties']['Restart'] == 'no'


def test_guard_healthy_waiting_is_read_only(config, lease, monkeypatch):
    healthy(monkeypatch)
    before = Path(config['handoff_waiting']).read_bytes()
    M.guard(config, lease)
    assert Path(config['handoff_waiting']).read_bytes() == before
    assert not Path(config['handoff_state']).exists()


def test_handoff_creation_immediately_blocks_new_payload(config, lease, monkeypatch):
    healthy(monkeypatch); M.atomic(config['handoff_state'], {'phase': 'pausing'})
    with pytest.raises(RuntimeError, match='handoff state observed'):
        M.guard(config, lease)


def test_missing_wait_gate_fails_closed(config, lease, monkeypatch):
    healthy(monkeypatch); Path(config['handoff_waiting']).unlink()
    with pytest.raises(FileNotFoundError):
        M.guard(config, lease)


def test_baseline_process_exit_stops_development_without_signalling_it(config, lease, monkeypatch):
    healthy(monkeypatch)
    config['_observed_baseline_processes'] = [{'unit': 'baseline.service', 'identity': {'pid': 999}}]
    monkeypatch.setattr(M, 'same_process', lambda current, saved: False)
    calls = []; monkeypatch.setattr(M.os, 'kill', lambda *a: calls.append(a))
    with pytest.raises(RuntimeError, match='baseline service identity changed'):
        M.guard(config, lease)
    assert calls == []


@pytest.mark.parametrize('field', ['expires_epoch', 'expires_monotonic'])
def test_either_lease_clock_can_expire(config, lease, monkeypatch, field):
    healthy(monkeypatch); lease[field] = 0
    with pytest.raises(RuntimeError, match='lease expired'):
        M.guard(config, lease)


def test_memory_floor_stops_owned_work(config, lease, monkeypatch):
    healthy(monkeypatch); monkeypatch.setattr(M, 'available_memory', lambda: 191 * M.GIB)
    with pytest.raises(RuntimeError, match='memory'):
        M.guard(config, lease)


def test_disk_floor_stops_owned_work(config, lease, monkeypatch):
    healthy(monkeypatch); monkeypatch.setattr(M.shutil, 'disk_usage', lambda path: SimpleNamespace(free=79 * M.GIB))
    with pytest.raises(RuntimeError, match='disk'):
        M.guard(config, lease)


def test_output_growth_has_no_arbitrary_campaign_cap(config, lease, monkeypatch):
    healthy(monkeypatch)
    M.guard(config, lease, output_size=100 * M.GIB)


def test_lease_restart_never_renews_deadline(config, monkeypatch):
    monkeypatch.setattr(M, 'process', lambda pid: {'boot_id': 'boot'})
    first = M.new_lease(config, Path(config['runtime']))
    monkeypatch.setattr(M.time, 'time', lambda: first['started_epoch'] + 1000)
    second = M.new_lease(config, Path(config['runtime']))
    assert second == first
    assert second['expires_epoch'] - second['started_epoch'] == 7200


def test_cpu_choice_only_approved_physical_not_other_owned_slot(config):
    before = {cpu: (100, 50) for cpu in range(64)}
    after = {cpu: (200, 140 if cpu == 29 else 60) for cpu in range(64)}
    assert M.choose_cpu(config, before, after, []) == 29
    assert M.choose_cpu(config, before, after, [29]) in range(29)


def test_all_numeric_thread_controls_one(monkeypatch):
    monkeypatch.setenv('OPENBLAS_NUM_THREADS', '64')
    result = M.numerical_env()
    assert all(result[key] == '1' for key in M.THREADS)


def test_worker_gate_requires_single_thread_before_any_science(monkeypatch):
    monkeypatch.setenv('OPENBLAS_NUM_THREADS', '2')
    args = SimpleNamespace(cpu=0)
    with pytest.raises(RuntimeError, match='CPU/thread'):
        M.worker_gate(args)


def test_worker_gate_rejects_reserve_or_smt(monkeypatch):
    args = SimpleNamespace(cpu=30)
    with pytest.raises(RuntimeError, match='CPU/thread'):
        M.worker_gate(args)


def test_payload_cannot_run_if_actual_policy_proof_fails(monkeypatch):
    monkeypatch.setattr(M.subprocess, 'run', lambda *a, **k: None)
    monkeypatch.setattr(M, 'verify_policy', lambda *a, **k: (_ for _ in ()).throw(RuntimeError('bad actual policy')))
    for key in M.THREADS:
        monkeypatch.setenv(key, '1')
    called = []; monkeypatch.setattr(M.os, 'execve', lambda *a: called.append(a))
    with pytest.raises(RuntimeError, match='bad actual policy'):
        M.worker_gate(SimpleNamespace(cpu=0))
    assert called == []


def test_closed_permit_never_executes_payload(monkeypatch):
    monkeypatch.setattr(M.subprocess, 'run', lambda *a, **k: None)
    monkeypatch.setattr(M, 'verify_policy', lambda *a, **k: None)
    for key in M.THREADS:
        monkeypatch.setenv(key, '1')
    ready_r, ready_w = os.pipe(); permit_r, permit_w = os.pipe(); os.close(permit_w)
    called = []; monkeypatch.setattr(M.os, 'execve', lambda *a: called.append(a))
    try:
        assert M.worker_gate(SimpleNamespace(cpu=0, ready_fd=ready_w, permit_fd=permit_r)) == 3
        assert called == []
        assert json.loads(os.read(ready_r, 4096))['pid'] == os.getpid()
    finally:
        os.close(ready_r)


def test_stop_only_proven_owned_groups(monkeypatch):
    calls = []; job = {'identity': {'pgrp': 123}, 'process': SimpleNamespace(wait=lambda timeout: 0),
                       'log': SimpleNamespace(close=lambda: None)}
    checks = iter([[{'pid': 123, 'state': 'S'}], [], []])
    monkeypatch.setattr(M, 'group_members', lambda saved: next(checks))
    monkeypatch.setattr(M.os, 'killpg', lambda group, sig: calls.append((group, sig)))
    M.stop_owned([job], grace_seconds=0)
    assert calls == [(123, signal.SIGTERM)]


def test_unproven_group_never_receives_signal(monkeypatch):
    calls = []; monkeypatch.setattr(M, 'group_members', lambda saved: (_ for _ in ()).throw(RuntimeError('ownership')))
    monkeypatch.setattr(M.os, 'killpg', lambda *args: calls.append(args))
    with pytest.raises(RuntimeError, match='ownership'):
        M.stop_owned([{'identity': {'pgrp': 123}}])
    assert calls == []


def test_actual_nonidle_thread_rejected(monkeypatch, tmp_path):
    real_path = M.Path
    task = tmp_path / 'task'; task.mkdir(); (task / '42').mkdir()
    monkeypatch.setattr(M, 'Path', lambda value: tmp_path if value == '/proc' else real_path(value))
    # Construct the /proc/42/task stand-in through a process-folder symlink.
    (tmp_path / '42').mkdir(); (tmp_path / '42' / 'task').symlink_to(task, target_is_directory=True)
    monkeypatch.setattr(M.os, 'sched_getscheduler', lambda pid: os.SCHED_OTHER)
    with pytest.raises(RuntimeError, match='escaped SCHED_IDLE'):
        M.verify_policy(42, 0)


def test_finished_worker_disappearing_between_polls_is_not_a_policy_violation(monkeypatch):
    monkeypatch.setattr(M, 'process', lambda pid: None)
    job = {'identity': {'pid': 42}, 'process': SimpleNamespace(poll=lambda: 0)}
    M.verify_job(job)


def test_live_worker_identity_change_still_fails_closed(monkeypatch):
    monkeypatch.setattr(M, 'process', lambda pid: None)
    job = {'identity': {'pid': 42}, 'process': SimpleNamespace(poll=lambda: None)}
    with pytest.raises(RuntimeError, match='identity changed'):
        M.verify_job(job)


def test_finished_worker_proc_thread_race_is_accepted(monkeypatch):
    monkeypatch.setattr(M, 'process', lambda pid: {'pid': pid})
    monkeypatch.setattr(M, 'same_process', lambda *a: True)
    monkeypatch.setattr(M, 'group_members', lambda *a: [{'pid': 42, 'state': 'S'}])
    monkeypatch.setattr(M, 'verify_policy', lambda *a: (_ for _ in ()).throw(FileNotFoundError()))
    M.verify_job({'identity': {'pid': 42}, 'cpu': 0, 'process': SimpleNamespace(poll=lambda: 0)})


def test_run_failure_stops_only_own_children_and_seals_terminal(config, monkeypatch):
    runtime = Path(config['runtime']); runtime.mkdir()
    M.atomic(runtime / 'release.json', {'source': {'head': 'frozen'}})
    M.atomic(runtime / 'policy_probe.json', {'status': 'R148_IDLE_POLICY_PROBE_PASSED', 'source': {'head': 'frozen'}})
    for name in ('verify_release', 'verify_own_service', 'physical_cpu_check'):
        monkeypatch.setattr(M, name, lambda *a: None)
    monkeypatch.setattr(M, 'new_lease', lambda *a: {'lease_id': 'lease', 'initial_output_bytes': 0})
    module = SimpleNamespace(preparation_complete=lambda: True, pending_task_names=lambda: ['a', 'b', 'c'],
                             write_closeout=lambda *a, **k: {'status': 'partial'})
    monkeypatch.setattr(M, 'load_science', lambda: module)
    monkeypatch.setattr(M, 'cpu_times', lambda: {})
    monkeypatch.setattr(M, 'choose_cpu', lambda config, before, after, occupied: len(occupied))
    guards = {'n': 0}
    def guarded(*a, **kw):
        guards['n'] += 1
        if guards['n'] == 2:
            raise RuntimeError('handoff observed')
    monkeypatch.setattr(M, 'guard', guarded)
    launched = []
    def spawn(config, runtime, lease, name, cpu):
        launched.append(name)
        return {'name': name, 'cpu': cpu, 'identity': {}, 'process': SimpleNamespace(pid=100, poll=lambda: None),
                'log_path': 'own.log'}
    monkeypatch.setattr(M, 'launch', spawn)
    stopped = []; monkeypatch.setattr(M, 'stop_owned', lambda jobs: stopped.extend(jobs))
    monkeypatch.setattr(M.time, 'sleep', lambda seconds: None)
    result = M.run(config, runtime)
    assert launched == ['a', 'b'] and len(stopped) == 2
    assert result['reason'] == 'handoff observed'
    assert result['baseline_worker_signals'] == 0
    assert (runtime / 'terminal.json').exists()


def test_launch_guard_runs_before_subprocess_creation(config, lease, monkeypatch):
    calls = []
    monkeypatch.setattr(M, 'guard', lambda *a, **k: (_ for _ in ()).throw(RuntimeError('handoff observed')))
    monkeypatch.setattr(M.subprocess, 'Popen', lambda *a, **k: calls.append(a))
    with pytest.raises(RuntimeError, match='handoff observed'):
        M.launch(config, Path(config['runtime']), lease, 'blocked', 0)
    assert calls == []


def test_existing_terminal_cannot_restart_work(config, monkeypatch):
    runtime = Path(config['runtime']); runtime.mkdir()
    terminal = {'status': 'R148_IDLE_LEASE_STOPPED', 'reason': 'expired'}
    M.atomic(runtime / 'terminal.json', terminal)
    M.atomic(runtime / 'release.json', {'source': {'head': 'frozen'}})
    M.atomic(runtime / 'policy_probe.json', {'status': 'R148_IDLE_POLICY_PROBE_PASSED', 'source': {'head': 'frozen'}})
    for name in ('verify_release', 'verify_own_service', 'physical_cpu_check'):
        monkeypatch.setattr(M, name, lambda *a: None)
    monkeypatch.setattr(M, 'load_science', lambda: pytest.fail('terminal must prevent worker import'))
    assert M.run(config, runtime) == terminal


def test_actual_subprocess_proves_policy_before_probe_payload(config, lease, monkeypatch):
    """Short real process; no scientific import, model fit, or baseline signal."""
    monkeypatch.setattr(M, 'guard', lambda *a, **k: None)
    # Keep real process identities: the lease fixture only needs a synthetic boot.
    monkeypatch.undo()
    monkeypatch.setattr(M, 'guard', lambda *a, **k: None)
    before = M.cpu_times(); M.time.sleep(0.2)
    config['allowed_cpus'] = sorted(set(range(30)) & os.sched_getaffinity(0))
    cpu = M.choose_cpu(config, before, M.cpu_times(), [])
    job = M.launch(config, Path(config['runtime']), lease, 'actual_policy_probe', cpu, payload='probe')
    try:
        assert job['process'].wait(timeout=15) == 0, Path(job['log_path']).read_text()
    finally:
        M.stop_owned([job], grace_seconds=0)


def test_shared_v1_controllers_are_reported_without_setting_limits():
    own = '/user.slice/user-1.slice/user@1.service/dev.service'
    result = M.controller_capability({'cgroups': ['2:cpu,cpuacct:/',
        '3:memory:/user.slice/user-1.slice/user@1.service', '1:name=systemd:' + own]}, own)
    assert result['hard_cgroup_limits_applied'] is False
    assert result['private_controllers'] == {'cpu': False, 'memory': False}
    assert 'soft guard' in result['fallback']


def test_resource_properties_never_set_limits_on_shared_hierarchies(config):
    assert config['service_properties'] == {'KillMode': 'control-group', 'Restart': 'no'}


def test_owned_RSS_guard_stops_development_above_24GiB(config, lease, monkeypatch):
    healthy(monkeypatch); monkeypatch.setattr(M, 'owned_rss', lambda config: 25 * M.GIB)
    with pytest.raises(RuntimeError, match='RSS exceeded'):
        M.guard(config, lease)
    assert config['_owned_rss_bytes'] == 25 * M.GIB


def test_owned_RSS_includes_parent_and_all_owned_group_descendants(config, monkeypatch):
    config['_owned_jobs'] = [{'identity': {'pgrp': 111}}, {'identity': {'pgrp': 222}}]
    monkeypatch.setattr(M, 'group_members', lambda saved: [{'pid': saved['pgrp']}, {'pid': saved['pgrp'] + 1}])
    seen = []
    monkeypatch.setattr(M, 'process_rss', lambda pid: seen.append(pid) or 100)
    assert M.owned_rss(config) == 500
    assert set(seen) == {os.getpid(), 111, 112, 222, 223}


def test_owned_RSS_deduplicates_parent_and_pending_gate_descendants(config, monkeypatch):
    config['_owned_jobs'] = [{'identity': {}}]; config['_pending_gate_identity'] = {'pgrp': 111}
    monkeypatch.setattr(M, 'group_members', lambda saved: [{'pid': os.getpid()}, {'pid': 111}])
    monkeypatch.setattr(M, 'process_rss', lambda pid: 100)
    assert M.owned_rss(config) == 200


def test_pending_gate_memory_is_counted_before_permitting_payload(config, monkeypatch):
    config['_pending_gate_identity'] = {'pgrp': 222}
    monkeypatch.setattr(M, 'group_members', lambda saved: [{'pid': 222}])
    monkeypatch.setattr(M, 'process_rss', lambda pid: 200 if pid == 222 else 100)
    assert M.owned_rss(config) == 300


def test_only_private_service_membership_can_prove_ownership():
    unit = 'dev.service'; cgroup = '/user.slice/user-1.slice/' + unit
    assert M.private_service_membership({'cgroups': ['1:name=systemd:' + cgroup]}, cgroup, unit)
    assert M.private_service_membership({'cgroups': ['0::' + cgroup]}, cgroup, unit)
    assert not M.private_service_membership({'cgroups': ['11:memory:' + cgroup]}, cgroup, unit)
    assert not M.private_service_membership({'cgroups': ['1:name=systemd:/user.slice/shared']}, '/user.slice/shared', unit)


def test_real_unreaped_zombie_cgroup_release_is_safe(monkeypatch):
    """Reproduce the Muscat failure without fitting or signalling any baseline."""
    before = M.cpu_times(); M.time.sleep(.1)
    config = M.read(M.CONFIG)
    config['allowed_cpus'] = sorted(set(range(30)) & os.sched_getaffinity(0))
    cpu = M.choose_cpu(config, before, M.cpu_times(), [])
    child = subprocess.Popen([sys.executable, '-B', '-c', 'import time;time.sleep(.1)'],
        start_new_session=True, preexec_fn=lambda: M.apply_idle(cpu), env=M.numerical_env())
    try:
        saved = M.process(child.pid)
        assert saved['state'] != 'Z'
        deadline = M.time.monotonic() + 2
        while M.time.monotonic() < deadline:
            zombie = M.process(child.pid)
            if zombie['state'] == 'Z':
                break
            M.time.sleep(.01)
        assert zombie['state'] == 'Z'
        assert M.same_lifetime(zombie, saved)
        assert zombie['cgroups'] != saved['cgroups']
        assert M.group_members(saved) == []
        assert child.wait(timeout=1) == 0
    finally:
        if child.poll() is None:
            child.kill(); child.wait(timeout=1)


def test_reused_zombie_leader_still_rejected(monkeypatch):
    saved = {'pid': 111, 'start_ticks': 100, 'boot_id': 'boot', 'pgrp': 111, 'cgroups': ['private']}
    zombie = dict(saved, state='Z', start_ticks=200, cgroups=['root'])
    class EmptyProc:
        def iterdir(self):
            return []
    monkeypatch.setattr(M, 'Path', lambda path: EmptyProc())
    monkeypatch.setattr(M, 'process', lambda pid: zombie)
    with pytest.raises(RuntimeError, match='PID was reused'):
        M.group_members(saved)


def test_preparation_finish_releases_scoring_workers_and_closes_out(config, monkeypatch):
    runtime = Path(config['runtime']); runtime.mkdir()
    source = {'head': 'frozen'}
    M.atomic(runtime / 'release.json', {'source': source})
    M.atomic(runtime / 'policy_probe.json', {'status': 'R148_IDLE_POLICY_PROBE_PASSED', 'source': source})
    for name in ('verify_release', 'verify_own_service', 'physical_cpu_check', 'guard'):
        monkeypatch.setattr(M, name, lambda *a, **kw: None)
    monkeypatch.setattr(M, 'new_lease', lambda *a: {'initial_output_bytes': 0})
    monkeypatch.setattr(M, 'cpu_times', lambda: {})
    monkeypatch.setattr(M, 'choose_cpu', lambda config, before, after, occupied: len(occupied))
    monkeypatch.setattr(M, 'group_members', lambda saved: [])
    monkeypatch.setattr(M.time, 'sleep', lambda seconds: None)
    ready = {'prepared': False}; complete = set(); names = ['score1', 'score2', 'score3']
    def sealed(name):
        complete.add(name); return True
    module = SimpleNamespace(preparation_complete=lambda: ready['prepared'],
        pending_task_names=lambda: [name for name in names if name not in complete],
        task_complete=sealed, write_closeout=lambda *a, **kw: {'status': 'complete'})
    monkeypatch.setattr(M, 'load_science', lambda: module)
    launched = []
    class Finished:
        returncode = 0
        pid = 111
        def poll(self):
            ready['prepared'] = True
            return 0
    def spawn(config, runtime, lease, name, cpu, payload='worker'):
        launched.append((name, payload))
        return {'name': name, 'payload': payload, 'cpu': cpu, 'identity': {},
                'process': Finished(), 'log': SimpleNamespace(close=lambda: None), 'log_path': 'own.log'}
    monkeypatch.setattr(M, 'launch', spawn)
    monkeypatch.setattr(M, 'stop_owned', lambda jobs: None)
    result = M.run(config, runtime)
    assert launched == [('preparation', 'prepare'), *[(name, 'worker') for name in names]]
    assert complete == set(names)
    assert result['status'] == 'R148_IDLE_TASKS_COMPLETE_NOT_PROMOTED'
    assert result['cleanup_verified'] is True


def test_cleanup_error_cannot_suppress_terminal_receipt(config, monkeypatch):
    runtime = Path(config['runtime']); runtime.mkdir()
    source = {'head': 'frozen'}
    M.atomic(runtime / 'release.json', {'source': source})
    M.atomic(runtime / 'policy_probe.json', {'status': 'R148_IDLE_POLICY_PROBE_PASSED', 'source': source})
    for name in ('verify_release', 'verify_own_service', 'physical_cpu_check'):
        monkeypatch.setattr(M, name, lambda *a: None)
    monkeypatch.setattr(M, 'new_lease', lambda *a: {'initial_output_bytes': 0})
    monkeypatch.setattr(M, 'load_science', lambda: SimpleNamespace())
    monkeypatch.setattr(M, 'guard', lambda *a, **kw: (_ for _ in ()).throw(RuntimeError('guard stopped')))
    monkeypatch.setattr(M, 'stop_owned', lambda jobs: (_ for _ in ()).throw(RuntimeError('ownership unproven')))
    result = M.run(config, runtime)
    assert result['status'] == 'R148_IDLE_LEASE_STOPPED'
    assert result['cleanup_verified'] is False
    assert result['cleanup_error'] == 'ownership unproven'
    assert M.read(runtime / 'terminal.json') == result


def test_main_cleanup_failure_returns_nonzero(monkeypatch):
    monkeypatch.setattr(M.sys, 'argv', [str(M.ENTRY), 'run'])
    monkeypatch.setattr(M, 'run', lambda *a: {'cleanup_verified': False})
    assert M.main() == 1


def test_released_source_paths_exist():
    assert all(path.is_file() for path in M.source_paths())
