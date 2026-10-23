"""Exit interleavings may be refreshed; live ownership drift must fail closed."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('r149_exit_snapshot_kernel', ROOT / 'application/scripts/pricefm/493_supervise_pricefm_stage_r148_ee_idle_resources.py')
M = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(M)


@pytest.fixture
def identity():
    return {'pid': 111, 'start_ticks': 100, 'boot_id': 'boot', 'pgrp': 111,
            'cgroups': ['1:name=systemd:/private.service'], 'state': 'S'}


def fake_proc_root(monkeypatch, names):
    monkeypatch.setattr(M, 'Path', lambda path: SimpleNamespace(
        iterdir=lambda: [SimpleNamespace(name=str(pid)) for pid in names]))


@pytest.mark.parametrize('after', ['zombie', 'vanished'])
def test_mixed_member_snapshot_is_ignored_only_after_fresh_exit_proof(identity, monkeypatch, after):
    mixed = dict(identity, cgroups=['1:name=systemd:/'])
    fresh = dict(mixed, state='Z') if after == 'zombie' else None
    reads = iter([mixed, fresh, fresh])
    fake_proc_root(monkeypatch, [111]); monkeypatch.setattr(M, 'process', lambda pid: next(reads))
    assert M.group_members(identity) == []


def test_final_leader_check_refreshes_same_lifetime_exit(identity, monkeypatch):
    mixed = dict(identity, cgroups=['1:name=systemd:/']); zombie = dict(mixed, state='Z')
    reads = iter([mixed, zombie])
    fake_proc_root(monkeypatch, []); monkeypatch.setattr(M, 'process', lambda pid: next(reads))
    assert M.group_members(identity) == []


def test_persistent_live_cgroup_mismatch_remains_rejected(identity, monkeypatch):
    mixed = dict(identity, cgroups=['1:name=systemd:/unowned.service'])
    fake_proc_root(monkeypatch, [111]); monkeypatch.setattr(M, 'process', lambda pid: mixed)
    pauses = []; monkeypatch.setattr(M.time, 'sleep', lambda seconds: pauses.append(seconds))
    with pytest.raises(RuntimeError, match='ownership is not proven'):
        M.group_members(identity)
    assert pauses == [.002, .002]


def test_reused_PID_cannot_be_accepted_as_fresh_zombie(identity, monkeypatch):
    mixed = dict(identity, cgroups=['1:name=systemd:/'])
    reused = dict(mixed, state='Z', start_ticks=101)
    reads = iter([mixed, reused])
    fake_proc_root(monkeypatch, [111]); monkeypatch.setattr(M, 'process', lambda pid: next(reads))
    with pytest.raises(RuntimeError, match='reused'):
        M.group_members(identity)


def test_reused_final_leader_still_fails_before_exit_refresh(identity, monkeypatch):
    reused = dict(identity, state='Z', start_ticks=101, cgroups=['1:name=systemd:/'])
    fake_proc_root(monkeypatch, []); monkeypatch.setattr(M, 'process', lambda pid: reused)
    with pytest.raises(RuntimeError, match='PID was reused'):
        M.group_members(identity)


def test_fresh_original_membership_can_be_proven_again(identity, monkeypatch):
    mixed = dict(identity, cgroups=['1:name=systemd:/'])
    reads = iter([mixed, identity, identity])
    fake_proc_root(monkeypatch, [111]); monkeypatch.setattr(M, 'process', lambda pid: next(reads))
    assert M.group_members(identity) == [identity]


def test_verify_job_handles_exit_between_stat_and_cgroup_read(identity, monkeypatch):
    mixed = dict(identity, cgroups=['1:name=systemd:/']); zombie = dict(mixed, state='Z')
    reads = iter([mixed, zombie]); monkeypatch.setattr(M, 'process', lambda pid: next(reads))
    M.verify_job({'identity': identity, 'process': SimpleNamespace(poll=lambda: 0)})


def test_verify_job_does_not_tolerate_persistent_live_ownership_drift(identity, monkeypatch):
    mixed = dict(identity, cgroups=['1:name=systemd:/unowned.service'])
    monkeypatch.setattr(M, 'process', lambda pid: mixed); monkeypatch.setattr(M.time, 'sleep', lambda seconds: None)
    with pytest.raises(RuntimeError, match='identity changed'):
        M.verify_job({'identity': identity, 'process': SimpleNamespace(poll=lambda: None)})


def test_real_child_exit_between_stat_and_cgroup_reads(monkeypatch):
    """Force the exact observed read boundary; no fit or baseline signal."""
    config = M.read(M.CONFIG); before = M.cpu_times(); M.time.sleep(.1)
    config['allowed_cpus'] = sorted(set(range(30)) & os.sched_getaffinity(0))
    cpu = M.choose_cpu(config, before, M.cpu_times(), [])
    child = subprocess.Popen([sys.executable, '-B', '-c', 'import time;time.sleep(.1)'],
        start_new_session=True, preexec_fn=lambda: M.apply_idle(cpu), env=M.numerical_env())
    original_read = Path.read_text; original_process = M.process; captured = []; forced = {'done': False}
    try:
        saved = M.process(child.pid)
        assert saved['state'] != 'Z'
        def delayed_cgroup(path, *args, **kwargs):
            if path == Path('/proc') / str(child.pid) / 'cgroup' and not forced['done']:
                deadline = M.time.monotonic() + 2
                while M.time.monotonic() < deadline:
                    state = original_read(Path('/proc') / str(child.pid) / 'stat').rsplit(')', 1)[1].split()[0]
                    if state == 'Z':
                        break
                    M.time.sleep(.002)
                forced['done'] = True
            return original_read(path, *args, **kwargs)
        def capture(pid):
            current = original_process(pid)
            if pid == child.pid:
                captured.append(current)
            return current
        monkeypatch.setattr(Path, 'read_text', delayed_cgroup)
        monkeypatch.setattr(M, 'process', capture)
        assert M.group_members(saved) == []
        assert captured[0]['state'] != 'Z' and captured[0]['cgroups'] != saved['cgroups']
        assert any(p['state'] == 'Z' and M.same_lifetime(p, saved) for p in captured[1:])
        M.verify_job({'identity': saved, 'process': child})
        assert child.wait(timeout=1) == 0
    finally:
        monkeypatch.setattr(Path, 'read_text', original_read)
        if child.poll() is None:
            child.kill(); child.wait(timeout=1)
