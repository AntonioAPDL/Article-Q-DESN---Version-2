#!/usr/bin/env python3
"""Transfer Muscat slot A only at a worker-free boundary; never signal workers.

Run requires a clean, frozen R146 worktree and a separately saved `audit` receipt.
The resource service MUST use KillMode=process and Restart=on-failure. A separate
transient guardian resumes the old supervisor on pre-commit failure. The commit
receipt assigns queue ownership to this service before stopping the empty old
unit; restart then adopts children rather than returning ownership to R145.
"""
from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
CONFIG = ROOT / 'application/config/pricefm_stage_r146_resource_handoff_20261022.json'
CGROUP_ROOT = Path('/sys/fs/cgroup')
PRECOMMIT = {'pausing', 'paused', 'waiting_boundary', 'ready_to_commit'}
COMMITTED = {'committed', 'old_unit_stopped', 'draining', 'complete', 'drained_with_quarantine'}
TERMINAL = {'complete', 'drained_with_quarantine', 'rolled_back'}
QUEUE = ['DE_LU', 'FI', 'IT_CALA', 'IT_SICI', 'NL', 'NO_4', 'RO', 'SE_4']


def read(path):
    return json.loads(Path(path).read_text())


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def atomic(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.tmp.' + str(os.getpid()))
    temporary.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')
    os.replace(temporary, path)


@contextlib.contextmanager
def locked(path):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def state_update(runtime, changes, *, owner=None, attempt=None, allowed_phases=None):
    with locked(runtime / 'state.lock'):
        state = read(runtime / 'state.json')
        if owner is not None and state['owner'] != owner:
            raise RuntimeError('handoff owner identity changed')
        if attempt is not None and state['attempt'] != attempt:
            raise RuntimeError('handoff attempt changed')
        if allowed_phases is not None and state['phase'] not in allowed_phases:
            raise RuntimeError('handoff phase changed or was rolled back')
        state.update(changes); atomic(runtime / 'state.json', state)
        return state


class System:
    def __init__(self, config):
        self.config = config

    def unit(self, name):
        output = subprocess.check_output(['systemctl', '--user', 'show', name,
            '--property=MainPID,ControlGroup,KillMode,Restart,ActiveState,WorkingDirectory,ExecStart'], text=True)
        return dict(line.split('=', 1) for line in output.splitlines() if '=' in line)

    def process(self, pid):
        try:
            folder = Path('/proc') / str(pid)
            stat = (folder / 'stat').read_text().rsplit(')', 1)[1].split()
            return {'pid': int(pid), 'start_ticks': int(stat[19]),
                    'boot_id': Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
                    'state': stat[0], 'ppid': int(stat[1]),
                    'cmdline_sha256': hashlib.sha256((folder / 'cmdline').read_bytes()).hexdigest(),
                    'command': (folder / 'cmdline').read_bytes().replace(b'\0', b' ').decode(),
                    'argv': [value.decode() for value in (folder / 'cmdline').read_bytes().split(b'\0') if value],
                    'cwd': str((folder / 'cwd').resolve()),
                    'cgroups': [line.split(':', 2)[2] for line in (folder / 'cgroup').read_text().splitlines()],
                    'affinity': sorted(os.sched_getaffinity(pid))}
        except (FileNotFoundError, ProcessLookupError):
            return None

    def members(self, cgroup, *, allow_missing=False):
        if not cgroup.startswith('/user.slice/') or '..' in Path(cgroup).parts:
            raise RuntimeError('refusing unexpected service control group')
        # Hosts currently use cgroup-v1 name=systemd; retain v2 support. Missing
        # active membership must never be interpreted as an empty service.
        candidates = [CGROUP_ROOT / cgroup.lstrip('/'),
                      CGROUP_ROOT / 'systemd' / cgroup.lstrip('/')]
        roots = [root for root in candidates if (root / 'cgroup.procs').is_file()]
        if not roots:
            if allow_missing and not any(root.exists() for root in candidates):
                return []
            raise RuntimeError('service control-group membership is not observable')
        if len(roots) != 1:
            raise RuntimeError('service control-group hierarchy is ambiguous')
        paths = list(roots[0].rglob('cgroup.procs'))
        return sorted({int(value) for path in paths for value in path.read_text().split()})

    def signal(self, pid, value):
        os.kill(pid, value)

    def stop(self, name):
        subprocess.run(['systemctl', '--user', 'stop', name], check=True, timeout=120)

    def start(self, name):
        subprocess.run(['systemctl', '--user', 'start', name], check=True, timeout=30)

    def guardian(self, config_path, runtime, attempt):
        name = 'pricefm-r146-resource-guardian-' + attempt[:12] + '-' + str(os.getpid()) + '-' + str(time.time_ns()) + '.service'
        subprocess.run(['systemd-run', '--user', '--quiet', '--collect', '--unit=' + name,
            '--property=Restart=no', '--property=KillMode=process',
            '--property=WorkingDirectory=' + str(ROOT), self.config['python_runtime'], '-B', str(ENTRY),
            'guard', '--config', str(config_path), '--runtime', str(runtime), '--attempt', attempt],
            check=True, timeout=30)
        props = self.unit(name)
        if props.get('ActiveState') not in {'active', 'activating'} or props.get('ControlGroup') == self.unit(
                self.config['new_unit']).get('ControlGroup'):
            raise RuntimeError('independent fail-safe guardian is not active')
        return name


def entry_matches(process, expected):
    argv = process.get('argv', [])
    for value in argv:
        if not value or value.startswith('-'):
            continue
        path = Path(value)
        candidate = path if path.is_absolute() else Path(process['cwd']) / path
        if candidate.resolve() == Path(expected).resolve():
            return True
    return False


def same_process(current, expected):
    return current is not None and all(current.get(key) == expected.get(key)
        for key in ['pid', 'start_ticks', 'boot_id', 'cmdline_sha256', 'cwd'])


def same_unit(current, expected):
    return all(current.get(key) == expected.get(key) for key in
               ['ControlGroup', 'KillMode', 'Restart', 'WorkingDirectory', 'ExecStart'])


def source_identity():
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()
    result = {'head': git('rev-parse', 'HEAD'), 'branch': git('branch', '--show-current')}
    if result['branch'] != 'work/pricefm-r146-at-training-fallback-20261022' or git('status', '--porcelain'):
        raise RuntimeError('clean committed R146 source worktree required')
    return result


def validate_config(config):
    if (config['continuation_regions'] != QUEUE or config['cpus'] != list(range(15))
            or config['protected_cpus'] != list(range(15, 30))
            or config['old_unit'] != 'pricefm-r145-muscat-at-recovery.service'
            or config['new_unit'] != 'pricefm-r146-muscat-resource-handoff.service'):
        raise RuntimeError('resource handoff differs from the bounded Muscat queue')
    if config['signal_workers'] or config['scientific_changes_authorized']:
        raise RuntimeError('worker signals and scientific changes are forbidden')


def freeze_old(config):
    root = Path(config['old_worktree'])
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    dirty = subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip()
    if head != config['old_head'] or dirty:
        raise RuntimeError('old source HEAD changed or worktree is dirty')
    observed = {name: digest(root / name) for name in config['old_frozen_sha256']}
    if observed != config['old_frozen_sha256']:
        raise RuntimeError('old supervisor/configuration source hashes changed')
    return {'head': head, 'sha256': observed}


def audit(config, system, expected_pid):
    validate_config(config)
    if socket.gethostname().split('.')[0].lower() != 'muscat':
        raise RuntimeError('resource handoff is Muscat-only')
    frozen = freeze_old(config)
    unit = system.unit(config['old_unit']); pid = int(unit['MainPID'])
    process = system.process(pid)
    if (pid != expected_pid or unit['ActiveState'] != 'active'
            or unit['KillMode'] != 'control-group' or unit['Restart'] != 'no'
            or process is None or process['cwd'] != config['old_worktree']
            or not entry_matches(process, config['old_entry'])
            or unit['ControlGroup'] not in process['cgroups']):
        raise RuntimeError('old service/process identity differs from the live audit')
    children = [system.process(value) for value in system.members(unit['ControlGroup']) if value != pid]
    return {'status': 'R146_RESOURCE_READONLY_AUDIT', 'old_unit': unit, 'old_process': process,
            'owned_children': [value for value in children if value],
            'source': source_identity(), 'config': config, 'old_frozen': frozen, 'epoch': time.time()}


def assert_old(system, config, receipt):
    if freeze_old(config) != receipt['old_frozen']:
        raise RuntimeError('old frozen source receipt differs')
    current = system.unit(config['old_unit'])
    if not same_unit(current, receipt['old_unit']) or int(current.get('MainPID', 0)) != receipt['old_process']['pid']:
        raise RuntimeError('old service identity changed')
    process = system.process(receipt['old_process']['pid'])
    if not same_process(process, receipt['old_process']):
        raise RuntimeError('old supervisor PID/start time/boot identity changed')
    return process


def gates(config, system):
    old_runtime = Path(config['old_runtime'])
    terminal = old_runtime / 'at.terminal.json'; quarantine = old_runtime / 'quarantine/AT.json'
    fallback = Path(config['fallback_runtime_terminal'])
    if not all(path.is_file() for path in [terminal, quarantine, fallback]):
        return False, 'waiting_for_both_AT_terminal_receipts'
    if read(terminal).get('status') != 'R145_LANE_DRAINED_WITH_QUARANTINED_FAILURES':
        raise RuntimeError('old AT lane is not the audited terminal quarantine')
    evidence = read(fallback)
    if evidence.get('status') not in config['fallback_terminal_statuses'] or evidence.get('region') != 'AT':
        raise RuntimeError('new AT fallback terminal is malformed')
    if evidence.get('source', {}).get('head') != source_identity()['head']:
        raise RuntimeError('AT fallback source differs from the frozen handoff')
    unit = system.unit(config['fallback_unit'])
    if unit.get('ActiveState') not in {'inactive', 'failed'} or int(unit.get('MainPID', 0)):
        return False, 'waiting_for_AT_fallback_unit_exit'
    cgroup = unit.get('ControlGroup')
    if cgroup and system.members(cgroup, allow_missing=True):
        return False, 'waiting_for_AT_fallback_process_exit'
    # Old AT numerical children must also be absent. The original supervisor and
    # healthy continuation controller remain allowed; no signals go to children.
    old = system.unit(config['old_unit']); main = int(old.get('MainPID', 0))
    for pid in system.members(old['ControlGroup']):
        if pid == main:
            continue
        proc = system.process(pid)
        if proc and any(marker in proc['command'] for marker in config['at_process_markers']):
            return False, 'waiting_for_old_AT_process_exit'
    return True, 'AT_lanes_terminal_and_processes_exited'


def require_resource_service(config, system):
    unit = system.unit(config['new_unit'])
    if (int(unit.get('MainPID', 0)) != os.getpid() or unit.get('KillMode') != 'process'
            or unit.get('Restart') != 'on-failure'):
        raise RuntimeError('resource service requires own MainPID, KillMode=process, Restart=on-failure')
    return unit


def rollback(runtime, config, system, reason, attempt):
    with locked(runtime / 'state.lock'):
        state = read(runtime / 'state.json')
        if state['attempt'] != attempt or state['phase'] in COMMITTED:
            return False
        if state['phase'] in PRECOMMIT:
            proc = assert_old(system, config, state['audit'])
            system.signal(proc['pid'], signal.SIGCONT)
        state.update(phase='rolled_back', rollback_reason=reason, rollback_epoch=time.time())
        atomic(runtime / 'state.json', state)
        return True


def guardian_once(runtime, config, system, attempt, now=None):
    now = time.time() if now is None else now
    state = read(runtime / 'state.json')
    if state['attempt'] != attempt or state['phase'] in TERMINAL:
        return 'exit'
    owner_alive = same_process(system.process(state['owner']['pid']), state['owner'])
    lease_fresh = now - state['heartbeat'] <= config['guardian_lease_seconds']
    if owner_alive and lease_fresh:
        return 'wait'
    if state['phase'] not in COMMITTED:
        rollback(runtime, config, system, 'owner_dead_or_lease_expired', attempt)
        return 'exit'
    # Ownership is committed. Restart only the new supervisor; KillMode=process
    # preserves an already running R141 child. Never restart the old supervisor.
    require = system.unit(config['new_unit'])
    if require.get('KillMode') != 'process' or require.get('Restart') != 'on-failure':
        raise RuntimeError('unsafe new-service recovery settings')
    atomic(runtime / ('guardian_recovery_' + attempt + '.json'),
           {'phase': state['phase'], 'owner_alive': owner_alive, 'lease_fresh': lease_fresh,
            'epoch': now, 'worker_signals': 0})
    if owner_alive:
        # A live but stale owner may still be inside a blocking safe operation;
        # do not terminate it or any child. Report and let lease validation stop it.
        return 'wait'
    system.start(config['new_unit'])
    return 'exit'


def guard(runtime, config, system, attempt):
    while guardian_once(runtime, config, system, attempt) == 'wait':
        time.sleep(config['poll_seconds'])


def heartbeat(runtime, owner, attempt, stop):
    while not stop.wait(3):
        try:
            state = state_update(runtime, {'heartbeat': time.time()}, owner=owner, attempt=attempt)
            if state['phase'] in TERMINAL:
                return
        except (RuntimeError, FileNotFoundError):
            return


def pause_old(runtime, config, system, owner, attempt):
    # Serialize STOP with guardian rollback. Without this lock a stale-lease
    # rollback could CONT first and a resumed owner could STOP without a guardian.
    with locked(runtime / 'state.lock'):
        state = read(runtime / 'state.json')
        if state['attempt'] != attempt or state['owner'] != owner or state['phase'] != 'armed':
            raise RuntimeError('pause ownership was rolled back or replaced')
        if system.unit(state['guardian_unit']).get('ActiveState') != 'active':
            raise RuntimeError('independent guardian is not active before pause')
        process = assert_old(system, config, state['audit'])
        state.update(phase='pausing', heartbeat=time.time())
        atomic(runtime / 'state.json', state)
        system.signal(process['pid'], signal.SIGSTOP)
        state.update(phase='waiting_boundary', heartbeat=time.time())
        atomic(runtime / 'state.json', state)
        return state


def ready_to_commit(runtime, config, system, owner, attempt):
    with locked(runtime / 'state.lock'):
        state = read(runtime / 'state.json')
        if state['attempt'] != attempt or state['owner'] != owner or state['phase'] not in PRECOMMIT:
            raise RuntimeError('handoff lease/ownership was rolled back')
        process = assert_old(system, config, state['audit'])
        if process['state'] not in {'T', 't'}:
            raise RuntimeError('old supervisor is not stopped at the commit boundary')
        members = system.members(state['audit']['old_unit']['ControlGroup'])
        if set(members) != {process['pid']}:
            raise RuntimeError('old service still owns healthy work or preparation')
        guardian = system.unit(state['guardian_unit'])
        if guardian.get('ActiveState') != 'active':
            raise RuntimeError('independent rollback guardian is not active')
        ready, reason = gates(config, system)
        if not ready:
            raise RuntimeError(reason)
        # Decisive ownership commit. Before this point rollback CONT is safe;
        # afterwards recovery finishes this handoff and never resumes R145.
        state.update(phase='committed', boundary_proof={'members': members,
            'old_process': process, 'epoch': time.time()}, heartbeat=time.time())
        atomic(runtime / 'state.json', state)
        return state


def finish_old_stop(runtime, config, system, owner, attempt):
    state = read(runtime / 'state.json')
    old = system.unit(config['old_unit'])
    if old.get('ActiveState') not in {'inactive', 'failed'}:
        process = assert_old(system, config, state['audit'])
        if process['state'] not in {'T', 't'} or set(system.members(old['ControlGroup'])) != {process['pid']}:
            raise RuntimeError('old service gained children or resumed after ownership commit')
        system.stop(config['old_unit'])
    old = system.unit(config['old_unit'])
    if old.get('ActiveState') not in {'inactive', 'failed'} or int(old.get('MainPID', 0)):
        raise RuntimeError('old service has not fully stopped')
    if old.get('ControlGroup') and system.members(old['ControlGroup'], allow_missing=True):
        raise RuntimeError('old service retains processes after stop')
    return state_update(runtime, {'phase': 'old_unit_stopped', 'heartbeat': time.time()}, owner=owner, attempt=attempt)


def load_old(config):
    path = Path(config['old_entry'])
    spec = importlib.util.spec_from_file_location('r146_frozen_r145', path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def owned_processes(config, system):
    unit = system.unit(config['new_unit'])
    values = []
    for pid in system.members(unit['ControlGroup']):
        if pid == os.getpid():
            continue
        value = system.process(pid)
        if value is not None and value.get('state') != 'Z':
            values.append(value)
    return values


def owned_work_state(config, system, old, old_config, region):
    """Only a verified same-region R141 controller tree may be adopted.

    Orphan preparation/rescue/R processes left by a prior supervisor crash must
    finish before any preparation or retry can rename or reuse their files.
    """
    processes = owned_processes(config, system)
    if not processes:
        return 'clear'
    controller = old.controller_pid(old_config, region)
    by_pid = {value['pid']: value for value in processes}
    if controller is None or controller not in by_pid:
        return 'waiting_for_orphan_preparation_or_rescue_children'
    recorded = read(old.source_campaign(old_config, region) / 'controller_identity.json')
    if recorded.get('pid') != controller or recorded.get('cpus') != config['cpus']:
        raise RuntimeError('live continuation controller identity/declared affinity differs')
    descendants = {controller}
    while True:
        additional = {value['pid'] for value in processes if value['ppid'] in descendants}
        if additional.issubset(descendants):
            break
        descendants.update(additional)
    if set(by_pid) - descendants:
        return 'waiting_for_orphan_preparation_or_rescue_children'
    allowed = set(config['cpus'])
    if any(not set(value.get('affinity', [])).issubset(allowed)
           for value in processes if value['pid'] != controller):
        return 'waiting_for_owned_worker_affinity_validation'
    return 'adoptable'


def wait_owned_work(runtime, config, system, old, old_config, region):
    while True:
        state = owned_work_state(config, system, old, old_config, region)
        if state in {'clear', 'adoptable'}:
            return state
        atomic(runtime / 'owned_work_wait.json', {'region': region, 'status': state,
                                                 'epoch': time.time(), 'worker_signals': 0})
        time.sleep(config['poll_seconds'])


def verify_region_closeout(old, old_config, region):
    if not old.region_complete(old_config, region):
        return False
    folder = old.source_campaign(old_config, region) / 'closeout'
    metadata = old.R142.verified(folder)
    return metadata.get('source', {}).get('head') == old_config['source_head']


def protected_scheduler_exit_proof(runtime, config, system, old, old_config):
    source_config = read(Path(old_config['source_worktree']) /
                         'application/config/pricefm_stage_r141_recovery_rollout_20261019.json')
    path = Path(config['old_runtime']).parents[1] / old_config['source_tag'] / 'host_scheduler/muscat/blocked.json'
    # old_runtime is .../launch_prep/<R145tag>/muscat, so launch_prep is parents[1].
    if not path.is_file():
        raise RuntimeError('original scheduler exited without a sealed protected-slot drain')
    value = read(path)
    if (value.get('status') != 'blocked' or value.get('host') != 'muscat'
            or value.get('source', {}).get('head') != old_config['source_head']
            or value.get('active') != {} or not value.get('failures')
            or any(item.get('slot') != 'slot_a' or item.get('region') != 'AT'
                   for item in value['failures'])):
        raise RuntimeError('original scheduler exit is not the expected AT-only host block')
    regions = source_config['host_queues']['muscat']['slot_b']
    if any(not verify_region_closeout(old, old_config, region) for region in regions):
        raise RuntimeError('protected slot-B regions have not all sealed')
    if any(old.controller_pid(old_config, region) is not None for region in regions):
        raise RuntimeError('protected slot-B controller remains active')
    proof = {'status': 'R146_PROTECTED_SLOT_B_DRAIN_VERIFIED', 'regions': regions,
             'blocked_sha256': digest(path), 'epoch': time.time(), 'protected_cpus_reused': False}
    atomic(runtime / 'protected_scheduler_exit_proof.json', proof)
    return proof


def install_scheduler_guard(runtime, config, system, old, old_config):
    capture = runtime / 'original_scheduler_identity.json'
    pids = old.scheduler_pids(old_config)
    if capture.exists():
        expected = read(capture)
    elif len(pids) == 1:
        expected = system.process(pids[0])
        if expected is None:
            raise RuntimeError('original scheduler vanished during identity capture')
        atomic(capture, expected)
    elif not pids:
        protected_scheduler_exit_proof(runtime, config, system, old, old_config)
        expected = None
    else:
        raise RuntimeError('original scheduler identity is ambiguous')

    def check(_config, pid):
        current = old.scheduler_pids(old_config)
        if expected is not None and current == [expected['pid']]:
            if not same_process(system.process(expected['pid']), expected):
                raise RuntimeError('original scheduler PID identity was reused')
            old.scheduler_failure(old_config)
            return
        if current:
            raise RuntimeError('original scheduler was replaced unexpectedly')
        protected_scheduler_exit_proof(runtime, config, system, old, old_config)
    # Resource-only compatibility wrapper; the frozen file and scientific engine
    # remain unchanged. Finished protected slot B must not veto slot A forever.
    old.assert_scheduler_unchanged = check
    return expected['pid'] if expected else 0


def original_queue_finished(config, system):
    unit = system.unit(config['old_unit'])
    if unit.get('ActiveState') not in {'inactive', 'failed'} or int(unit.get('MainPID', 0)):
        return None
    freeze_old(config)
    old = load_old(config); old_config = read(config['old_config'])
    complete = []; failures = []
    for region in QUEUE:
        if verify_region_closeout(old, old_config, region):
            complete.append(region); continue
        path = Path(config['old_runtime']) / 'quarantine' / (region + '.json')
        if not path.exists() or read(path).get('reason') == 'original Muscat scheduler identity changed during R145':
            return None
        failures.append(read(path))
    if unit.get('ControlGroup') and system.members(unit['ControlGroup'], allow_missing=True):
        raise RuntimeError('inactive old queue still has owned children')
    return {'phase': 'drained_with_quarantine' if failures else 'complete',
            'completed': complete, 'failures': failures, 'no_takeover_required': True,
            'worker_signals': 0, 'epoch': time.time()}


def noneligible_blocked_tasks(old, old_config, region):
    folder = old.source_campaign(old_config, region)
    blocked = folder / 'blocked.json'
    if not blocked.is_file():
        return []
    eligible = {item['name'] for item in old.R142.eligible_tasks(old_config, region)}
    failed = []
    for launch in (folder / 'launched').glob('*.json'):
        name = launch.stem; task_path = folder / 'tasks' / (name + '.json')
        if not task_path.is_file():
            raise RuntimeError('launched task has no immutable task contract')
        kind = read(task_path)['kind']
        packet = folder / 'tasks_done' / name / 'completed_evidence.json'
        if packet.is_file():
            metadata = old.R142.verified(packet.parent)
            bad = kind in {'al', 'internal_al'} and metadata.get('certified') is not True
        else:
            bad = True
        if bad and name not in eligible:
            failed.append(name)
    # A historical blocked.json can outlive a successful certified rescue. If no
    # launched task remains failed, resume the certified DAG rather than treating
    # that stale marker as a new scientific failure.
    return failed


def drain(runtime, config, system):
    old = load_old(config); old_config = read(config['old_config'])
    old.validate_static(old_config)
    identity = old.source_identity()
    if identity['head'] != config['old_head']:
        raise RuntimeError('frozen R145 source head differs')
    scheduler_pid = install_scheduler_guard(runtime, config, system, old, old_config)
    lane_runtime = runtime / 'continuation'; lane_runtime.mkdir(exist_ok=True)
    completed = [region for region in QUEUE if old.region_complete(old_config, region)]
    failures = []
    for region in QUEUE:
        if region in completed:
            continue
        prior = Path(config['old_runtime']) / 'quarantine' / (region + '.json')
        target = lane_runtime / 'quarantine' / (region + '.json')
        if prior.is_file() and not target.exists():
            record = read(prior); record['handoff_source_sha256'] = digest(prior)
            atomic(target, record)
        if target.is_file():
            failures.append(read(target)); continue
        if region in completed:
            continue
        wait_owned_work(runtime, config, system, old, old_config, region)
        blocked = old.source_campaign(old_config, region) / 'blocked.json'
        if (old.controller_pid(old_config, region) is None
                and noneligible_blocked_tasks(old, old_config, region)):
            failure = {'region': region, 'lane': 'continuation',
                'reason': 'preexisting_noneligible_controller_failure', 'blocked_sha256': digest(blocked),
                'test_opened': False, 'posterior_target_changed': False, 'epoch': time.time()}
            atomic(target, failure); failures.append(failure)
            continue
        try:
            result = old.run_region(old_config, identity, {'scheduler_pid': scheduler_pid},
                                    region, config['cpus'], lane_runtime,
                                    'continuation', config['poll_seconds'])
        except Exception as error:
            # Fail/restart while a healthy controller, preparation or rescue child
            # remains. KillMode=process preserves it; the next owner adopts/waits.
            # Never inherit R145's catch-and-advance behavior while work is live.
            scientific_terminal = ('bounded recovery cycles exhausted' in str(error)
                or 'without an eligible AL failure' in str(error)
                or 'bounded rescue exhausted without certification:' in str(error))
            if (owned_processes(config, system) or not old.health(old_config)['healthy']
                    or not scientific_terminal):
                atomic(runtime / 'blocked.json', {'region': region,
                    'status': 'R146_RESOURCE_OWNER_RESTART_REQUIRED', 'reason': str(error),
                    'owned_children_preserved': True, 'epoch': time.time()})
                raise
            failure = {'region': region, 'lane': 'continuation',
                'error_type': type(error).__name__, 'reason': str(error),
                'test_opened': False, 'posterior_target_changed': False, 'epoch': time.time()}
            atomic(target, failure); failures.append(failure)
        else:
            completed.append(region); atomic(lane_runtime / (region + '.completed.json'), result)
        atomic(lane_runtime / 'continuation.progress.json', old.lane_progress(old_config,
            'continuation', None, completed, failures, scheduler_pid))
    result = old.lane_progress(old_config, 'continuation', None, completed, failures, scheduler_pid)
    result['status'] = ('R146_CONTINUATION_COMPLETE_NOT_PROMOTED' if not failures
                        else 'R146_CONTINUATION_DRAINED_WITH_QUARANTINED_FAILURES')
    atomic(lane_runtime / 'continuation.terminal.json', result)
    return result


def run(runtime, config, system, audit_path, config_path):
    runtime.mkdir(parents=True, exist_ok=True)
    with (runtime / 'supervisor.lock').open('a') as supervisor_lock:
        fcntl.flock(supervisor_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        validate_config(config); identity = source_identity(); require_resource_service(config, system)
        finished = original_queue_finished(config, system)
        if finished is not None:
            atomic(runtime / 'no_takeover_terminal.json', finished)
            return finished
        owner = system.process(os.getpid())
        prior = read(runtime / 'state.json') if (runtime / 'state.json').exists() else None
        if prior and prior['phase'] in {'complete', 'drained_with_quarantine'}:
            return prior
        if prior and prior['phase'] in COMMITTED:
            if prior['audit']['source'] != identity or prior['audit']['config'] != config:
                raise RuntimeError('committed handoff source/configuration changed')
            attempt = prior['attempt']
            state_update(runtime, {'owner': owner, 'heartbeat': time.time()})
        else:
            if prior and prior['phase'] in PRECOMMIT:
                rollback(runtime, config, system, 'restart_before_commit', prior['attempt'])
            receipt = read(audit_path)
            if receipt['source'] != identity or receipt['config'] != config:
                raise RuntimeError('read-only audit source/configuration differs')
            assert_old(system, config, receipt)
            while True:
                finished = original_queue_finished(config, system)
                if finished is not None:
                    atomic(runtime / 'no_takeover_terminal.json', finished)
                    return finished
                ready, reason = gates(config, system)
                if ready:
                    break
                atomic(runtime / 'waiting.json', {'status': reason, 'epoch': time.time(), 'worker_signals': 0})
                assert_old(system, config, receipt); time.sleep(config['poll_seconds'])
            attempt = uuid.uuid4().hex
            atomic(runtime / 'state.json', {'attempt': attempt, 'phase': 'armed',
                   'owner': owner, 'audit': receipt, 'heartbeat': time.time()})
        guardian_name = system.guardian(config_path, runtime, attempt)
        state_update(runtime, {'guardian_unit': guardian_name}, owner=owner, attempt=attempt)
        stopped = threading.Event()
        thread = threading.Thread(target=heartbeat, args=(runtime, owner, attempt, stopped), daemon=True)
        thread.start()
        try:
            state = read(runtime / 'state.json')
            if state['phase'] not in COMMITTED:
                pause_old(runtime, config, system, owner, attempt)
                while True:
                    state = state_update(runtime, {'phase': 'waiting_boundary'}, owner=owner, attempt=attempt,
                                         allowed_phases=PRECOMMIT)
                    if system.unit(guardian_name).get('ActiveState') != 'active':
                        raise RuntimeError('independent rollback guardian exited before commit')
                    process = assert_old(system, config, state['audit'])
                    if process['state'] not in {'T', 't'}:
                        raise RuntimeError('old supervisor did not remain paused')
                    members = system.members(state['audit']['old_unit']['ControlGroup'])
                    atomic(runtime / 'boundary_progress.json', {'owned_children': [pid for pid in members
                        if pid != process['pid']], 'epoch': time.time(), 'worker_signals': 0})
                    if set(members) == {process['pid']}:
                        break
                    time.sleep(config['poll_seconds'])
                ready_to_commit(runtime, config, system, owner, attempt)
            finish_old_stop(runtime, config, system, owner, attempt)
            state_update(runtime, {'phase': 'draining'}, owner=owner, attempt=attempt)
            result = drain(runtime, config, system)
            phase = 'drained_with_quarantine' if result['failures'] else 'complete'
            return state_update(runtime, {'phase': phase, 'result': result, 'completed_epoch': time.time()},
                                owner=owner, attempt=attempt)
        except BaseException:
            rollback(runtime, config, system, 'resource_supervisor_aborted', attempt)
            raise
        finally:
            stopped.set(); thread.join(timeout=5)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['audit', 'run', 'guard'])
    parser.add_argument('--config', type=Path, default=CONFIG)
    parser.add_argument('--runtime', type=Path)
    parser.add_argument('--audit', type=Path)
    parser.add_argument('--expected-old-pid', type=int)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--attempt')
    args = parser.parse_args(); config = read(args.config); system = System(config)
    if args.action == 'audit':
        if args.expected_old_pid is None or args.output is None:
            parser.error('audit requires --expected-old-pid and --output')
        atomic(args.output, audit(config, system, args.expected_old_pid))
    elif args.action == 'run':
        if args.runtime is None or args.audit is None:
            parser.error('run requires --runtime and --audit')
        run(args.runtime, config, system, args.audit, args.config)
    else:
        if args.runtime is None or args.attempt is None:
            parser.error('guard requires --runtime and --attempt')
        guard(args.runtime, config, system, args.attempt)
