#!/usr/bin/env python3
"""Finite R150 cached development waves, owned by dedicated systemd units.

This is a new ownership design. It does not diagnose the second R149 refusal.
Only an attested, UUID-named R150 worker unit can be stopped by this program;
there are deliberately no kill/killpg calls and no baseline mutation methods.
All imports and admission work are standard-library-only.
"""
from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
CONFIG = ROOT / 'application/config/pricefm_stage_r150_bounded_resources_20261023.json'
SCIENCE = ROOT / 'application/scripts/pricefm/500_run_pricefm_stage_r150_bounded_admission.py'
PRIOR_HEAD = 'add35d3ea5df7397122bedf6509799cce634538c'
WORKFLOW_DESCRIPTION = 'R150 approved bounded successor three-wave workflow'
THREAD_VARS = ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS',
               'BLIS_NUM_THREADS', 'NUMEXPR_NUM_THREADS', 'VECLIB_MAXIMUM_THREADS')
UNIT_PROPERTIES = ('Id', 'LoadState', 'ActiveState', 'SubState', 'MainPID',
    'InvocationID', 'ControlGroup', 'ExecStart', 'Description', 'WorkingDirectory',
    'BindsTo', 'After', 'RuntimeMaxUSec', 'CPUAffinity', 'CPUSchedulingPolicy',
    'IOSchedulingClass', 'KillMode', 'Restart', 'Result', 'ExecMainStatus', 'NRestarts')
WORKER_STABLE = ('Id', 'InvocationID', 'ControlGroup', 'Description',
                 'WorkingDirectory', 'KillMode', 'Restart', 'BindsTo', 'After',
                 'RuntimeMaxUSec', 'CPUAffinity', 'CPUSchedulingPolicy', 'IOSchedulingClass')
BASELINE_STABLE = ('Id', 'InvocationID', 'ControlGroup', 'WorkingDirectory',
                   'KillMode', 'Restart', 'NRestarts')
IDENTITY_KEYS = ('pid', 'start_ticks', 'boot_id', 'cmdline_sha256')
IDLE_WRAPPER = '/usr/bin/chrt'


def idle_command(argv):
    return [IDLE_WRAPPER, '--idle', '0'] + list(argv)


def read(path):
    return json.loads(Path(path).read_text())


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def atomic(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.tmp.' + uuid.uuid4().hex)
    with temporary.open('x') as stream:
        json.dump(value, stream, sort_keys=True, indent=2); stream.write('\n')
        stream.flush(); os.fsync(stream.fileno())
    os.replace(temporary, path)


@contextlib.contextmanager
def locked(path):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX); yield


def event(runtime, kind, **details):
    runtime = Path(runtime); runtime.mkdir(parents=True, exist_ok=True)
    item = dict(epoch=time.time(), kind=kind); item.update(details)
    with locked(runtime / 'events.lock'):
        with (runtime / 'events.jsonl').open('a') as stream:
            stream.write(json.dumps(item, sort_keys=True) + '\n')
            stream.flush(); os.fsync(stream.fileno())
    return item


def process(pid):
    """Read-only lifetime evidence; never used to signal a PID or process group."""
    try:
        folder = Path('/proc') / str(int(pid))
        fields = (folder / 'stat').read_text().rsplit(')', 1)[1].split()
        command = (folder / 'cmdline').read_bytes()
        return dict(pid=int(pid), start_ticks=int(fields[19]), state=fields[0],
            boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
            cmdline_sha256=hashlib.sha256(command).hexdigest(),
            argv=[part.decode() for part in command.split(b'\0') if part],
            affinity=sorted(os.sched_getaffinity(int(pid))),
            scheduler=os.sched_getscheduler(int(pid)))
    except (FileNotFoundError, ProcessLookupError):
        return None


def same_lifetime(current, saved):
    return current is not None and all(current.get(k) == saved.get(k) for k in IDENTITY_KEYS)


def exec_arguments(props):
    text = props.get('ExecStart', '')
    return text.split('argv[]=', 1)[1].split(' ; ignore_errors=', 1)[0] if 'argv[]=' in text else text


def parse_duration(value):
    """systemctl's human-formatted RuntimeMaxUSec, including multi-unit spans."""
    if value in ('', 'infinity'):
        return math.inf
    units = {'us': 1e-6, 'ms': .001, 's': 1., 'min': 60., 'h': 3600., 'd': 86400.}
    matches = re.findall(r'([0-9]+(?:\.[0-9]+)?)\s*(us|ms|min|s|h|d)', value)
    if not matches or re.sub(r'([0-9]+(?:\.[0-9]+)?)\s*(us|ms|min|s|h|d)\s*', '', value):
        raise RuntimeError('unrecognized systemd duration: ' + value)
    return sum(float(number) * units[unit] for number, unit in matches)


def parse_cpu_affinity(value):
    # systemd 239 displays the CPU bitmask as hexadecimal bytes.
    if re.fullmatch(r'[0-9a-fA-F]+', value or ''):
        mask = int(value, 16)
        return [i for i in range(mask.bit_length()) if mask & (1 << i)]
    result = []
    for item in value.split():
        if '-' in item:
            a, b = map(int, item.split('-')); result.extend(range(a, b + 1))
        else:
            result.append(int(item))
    return sorted(set(result))


class System:
    """The only service-manager mutation is starting/stopping our own units."""
    def unit(self, name):
        output = subprocess.check_output(['systemctl', '--user', 'show', name,
            '--property=' + ','.join(UNIT_PROPERTIES)], text=True, timeout=15)
        return dict(line.split('=', 1) for line in output.splitlines() if '=' in line)

    def members(self, cgroup):
        if not cgroup.startswith('/user.slice/') or '..' in Path(cgroup).parts:
            raise RuntimeError('untrusted service cgroup path')
        candidates = [Path('/sys/fs/cgroup') / cgroup.lstrip('/'),
                      Path('/sys/fs/cgroup/systemd') / cgroup.lstrip('/')]
        existing = [path for path in candidates if path.exists()]
        if not existing:
            return []
        roots = [path for path in existing if (path / 'cgroup.procs').is_file()]
        if len(roots) != 1:
            raise RuntimeError('cgroup membership unavailable or ambiguous')
        for _ in range(3):
            try:
                return sorted({int(pid) for f in roots[0].rglob('cgroup.procs') for pid in f.read_text().split()})
            except FileNotFoundError:
                # A draining cgroup may disappear between traversal and read.
                # Bound rereads; persistent partial visibility is not emptiness.
                if not roots[0].exists():
                    return []
        raise RuntimeError('cgroup remained partially unreadable after3 snapshots: ' + str(roots[0]))

    def start(self, name, description, argv, *, cpus, idle, runtime_seconds,
              controller=None, working_directory=ROOT, stdout=None):
        if not re.fullmatch(r'pricefm-r150-(?:test-)?[a-zA-Z0-9_.-]+\.service', name):
            raise RuntimeError('refusing a non-R150 unit')
        command = ['systemd-run', '--user', '--quiet', '--unit=' + name,
            '--description=' + description, '--property=Restart=no',
            '--property=KillMode=control-group', '--property=TimeoutStopSec=15s',
            '--property=RuntimeMaxSec=' + str(max(1, int(runtime_seconds))) + 's',
            '--property=WorkingDirectory=' + str(working_directory),
            '--property=CPUAffinity=' + ' '.join(map(str, cpus)),
            '--property=CPUSchedulingPolicy=' + ('idle' if idle else 'other'),
            '--property=IOSchedulingClass=idle']
        if controller:
            command += ['--property=BindsTo=' + controller, '--property=After=' + controller]
        if stdout:
            command += ['--property=StandardOutput=file:' + str(stdout),
                        '--property=StandardError=file:' + str(stdout) + '.stderr']
        for variable in THREAD_VARS:
            command.append('--setenv=' + variable + '=1')
        command += ['--setenv=PYTHONDONTWRITEBYTECODE=1'] + list(argv)
        subprocess.run(command, check=True, timeout=30)

    def stop(self, name):
        # This method is called only after verify_owned() validates the immutable
        # InvocationID and the controller-issued intent. Never stop by prefix alone.
        subprocess.run(['systemctl', '--user', 'stop', name], check=True, timeout=30)

    def fail_owned_test_controller(self, saved):
        """Fault injection exists only for UUID disposable test units."""
        if not saved['unit'].startswith('pricefm-r150-test-'):
            raise RuntimeError('abrupt-death injection is restricted to disposable test units')
        verify_owned(saved, self.unit(saved['unit']))
        subprocess.run(['systemctl', '--user', 'kill', '--kill-who=main',
                        '--signal=KILL', saved['unit']], check=True, timeout=15)


def verify_owned(saved, current):
    """Unit identity is authoritative; a mixed post-exit /proc read is irrelevant."""
    if not saved['unit'].startswith('pricefm-r150-'):
        raise RuntimeError('unit lacks R150 ownership namespace')
    if current.get('LoadState') == 'not-found':
        return 'unloaded'
    expected = saved.get('attested')
    if not expected:
        # Before the launch acknowledgement, immutable intent still proves which
        # unique unit we requested. No payload is released until attestation.
        if (current.get('Id') != saved['unit']
                or current.get('Description') != saved['description']
                or exec_arguments(current) != ' '.join(saved['argv'])
                or current.get('WorkingDirectory') != str(ROOT)
                or current.get('KillMode') != 'control-group'
                or current.get('Restart') != 'no'):
            raise RuntimeError('pre-attestation unit intent mismatch')
    else:
        drift = {k: [expected.get(k), current.get(k)] for k in WORKER_STABLE
                 if k != 'ControlGroup' and current.get(k) != expected.get(k)}
        if current.get('ControlGroup') != expected.get('ControlGroup'):
            if not (current.get('ControlGroup', '') == ''
                    and current.get('ActiveState') in ('inactive', 'failed')
                    and current.get('MainPID', '0') == '0'):
                drift['ControlGroup'] = [expected.get('ControlGroup'), current.get('ControlGroup')]
        if exec_arguments(current) != exec_arguments(expected):
            drift['ExecStart.argv'] = [exec_arguments(expected), exec_arguments(current)]
        if drift:
            raise RuntimeError('owned unit identity mismatch: ' + json.dumps(drift, sort_keys=True))
    return 'owned'


def stop_and_drain(system, saved, *, timeout=25):
    current = system.unit(saved['unit']); proof = verify_owned(saved, current)
    cgroup = (saved.get('attested') or {}).get('ControlGroup') or saved.get('expected_cgroup') or current.get('ControlGroup', '')
    if proof == 'owned' and current.get('ActiveState') not in ('inactive', 'failed'):
        system.stop(saved['unit'])
    deadline = time.monotonic() + timeout
    while True:
        current = system.unit(saved['unit']); verify_owned(saved, current)
        members = system.members(cgroup) if cgroup else []
        if current.get('ActiveState') in ('inactive', 'failed') and current.get('MainPID', '0') == '0' and not members:
            return dict(unit=saved['unit'], drained=True, properties=current, members=[], epoch=time.time())
        if current.get('LoadState') == 'not-found' and not members:
            return dict(unit=saved['unit'], drained=True, properties=current, members=[], epoch=time.time())
        if time.monotonic() >= deadline:
            raise RuntimeError('owned unit did not drain: ' + json.dumps(dict(properties=current, members=members)))
        time.sleep(.1)


def validate_config(c):
    if (c['stage'] != 'R150' or c['mode'] != 'B'
            or c['cpus'] != list(range(15, 30)) or c['max_workers'] != 2
            or c['benchmark_seconds'] != 1200 or c['wave_seconds'] != 7200
            or c['max_waves'] != 3 or c['projection_cpu_seconds'] != 5400
            or c['wave_cleanup_buffer_seconds'] != 1800
            or c['min_available_memory_gib'] < 192 or c['min_disk_gib'] < 80
            or c['max_owned_rss_gib'] > 24 or c['handoff_fresh_seconds'] != 30
            or c['starvation_observation_seconds'] != 300
            or c['starvation_min_cpu_share'] != .10 or c['starvation_requeue_limit'] != 0
            or c['admitted_order'] != ['1','2','3'] or c['workflow_runtime_seconds'] != 365*60
            or c['benchmark_import_required'] is not True or c['new_benchmark_lease_authorized'] is not False
            or c['baseline_signals_authorized'] is not False
            or c['shared_quota_writes_authorized'] is not False
            or c['new_fits_authorized'] is not False
            or c['automatic_AL_authorized'] is not False):
        raise RuntimeError('R150 bounded Mode B resource contract differs')
    if Path(c['science_entry']) != SCIENCE or Path(c['source_root']) != ROOT:
        raise RuntimeError('unfrozen resource/scientific entry')


def assert_parent_policy(c):
    if sorted(os.sched_getaffinity(0)) != c['cpus'] or os.sched_getscheduler(0) != os.SCHED_OTHER:
        raise RuntimeError('preflight/controller must run on CPUs15-29 with SCHED_OTHER from first exec')
    if any(os.environ.get(name) != '1' for name in THREAD_VARS):
        raise RuntimeError('all numerical thread environment variables must equal1 before exec')


def source_release():
    head = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    dirty = subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain'], text=True)
    if dirty:
        raise RuntimeError('source must be committed and clean before resource admission')
    paths = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z']).decode().split('\0')
    hashes = {name: digest(ROOT / name) for name in paths if name and (ROOT / name).is_file()}
    # Admission attests the whole tracked tree. Frequent guards rehash executable
    # scientific/resource source and configuration, rather than manuscript PDFs.
    runtime_hashes = {name: value for name, value in hashes.items()
                     if name.startswith('application/scripts/pricefm/')
                     or name.startswith('application/config/pricefm_')}
    return dict(head=head, sha256=hashes, runtime_sha256=runtime_hashes,
                idle_wrapper_sha256=digest(IDLE_WRAPPER))


def verify_source(release, *, full=False):
    head = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    if head != release['head']:
        raise RuntimeError('frozen source HEAD changed')
    if digest(IDLE_WRAPPER) != release['idle_wrapper_sha256']:
        raise RuntimeError('frozen SCHED_IDLE exec wrapper changed')
    for name, expected in (release['sha256'] if full else release['runtime_sha256']).items():
        if digest(ROOT / name) != expected:
            raise RuntimeError('frozen source bytes changed: ' + name)


def verify_baseline_sources(c):
    for release in c['frozen_baseline_sources']:
        root = Path(release['root'])
        head = subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip()
        if head != release['head']:
            raise RuntimeError('baseline source HEAD changed: ' + str(root))
        for name, expected in release['sha256'].items():
            if digest(root/name) != expected:
                raise RuntimeError('baseline source bytes changed: ' + str(root/name))


def verify_benchmark_import(c, system=None):
    """Read-only proof that the sole benchmark is sealed, original and drained."""
    pin = c['benchmark_import']
    if digest(pin['path']) != pin['sha256']:
        raise RuntimeError('immutable original benchmark import receipt changed')
    receipt = read(pin['path'])
    if (receipt.get('status') != 'PASS_IMMUTABLE_ORIGINAL_BENCHMARK_IMPORT'
            or receipt['original_science_source']['head'] != PRIOR_HEAD
            or receipt.get('new_benchmark_lease_authorized') is not False
            or receipt.get('old_numerical_leases_absent') != ['1','2','3']
            or receipt.get('original_benchmark_calls') != 18):
        raise RuntimeError('original benchmark import identity/budget differs')
    root = Path(receipt['original_science_source']['root'])
    if subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip() != PRIOR_HEAD:
        raise RuntimeError('original benchmark source HEAD changed')
    for path, expected in receipt['immutable_file_sha256'].items():
        if digest(path) != expected:
            raise RuntimeError('original benchmark/source/runtime changed: ' + path)
    runtime = Path(receipt['original_runtime'])
    if any((runtime/('wave_'+wave)/'lease.json').exists() for wave in ('1','2','3')):
        raise RuntimeError('old runtime consumed a numerical wave; no duplicate admissions')
    wave = receipt['original_wave']; lease = read(wave['lease_path'])
    terminal = read(wave['terminal_path']); drain = read(wave['independent_drain_path'])
    timings = read(Path(receipt['original_benchmark']['folder'])/'timings.json')
    workflow = read(runtime/'workflow_terminal.json')
    if (lease['source_head'] != PRIOR_HEAD or lease['wave'] != 'benchmark' or lease['seconds'] != 1200
            or lease['nonrenewing'] is not True or terminal['lease'] != lease
            or terminal['status'] != 'R150_WAVE_COMPLETE' or terminal['cleanup_verified'] is not True
            or terminal['source']['head'] != PRIOR_HEAD or terminal['baseline_worker_signals'] != 0
            or drain['cleanup_verified'] is not True or drain.get('errors')
            or drain['controller']['drained'] is not True or not all(item['drained'] for item in drain['workers'])
            or workflow['completed_admissions'] != ['benchmark'] or workflow.get('cleanup_failures')
            or len(timings['rows']) != 18 or timings['source']['head'] != PRIOR_HEAD
            or timings['new_model_fits'] != 0 or timings['no_new_candidate_AQL_computed'] is not True
            or not 0 < receipt['original_available_cpu_seconds'] <= 32400):
        raise RuntimeError('original benchmark/lease/cleanup semantics differ')
    if system is not None:
        ledgers = [read(runtime/'workflow_launch.json'), read(runtime/'wave_benchmark/controller_launch.json')]
        ledgers += discover_workers(runtime/'wave_benchmark')
        for saved in ledgers:
            if 'argv' not in saved:
                saved['argv'] = saved['command']
            props = system.unit(saved['unit']); verify_owned(saved, props)
            cgroup = saved.get('expected_cgroup') or saved.get('attested',{}).get('ControlGroup')
            if (props.get('ActiveState') not in ('inactive','failed') or props.get('MainPID','0') != '0'
                    or not cgroup or system.members(cgroup)):
                raise RuntimeError('original benchmark/controller/workflow is not fully drained')
    return receipt


def memory_available_gib():
    values = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
    return int(values['MemAvailable'].split()[0]) / 1024 ** 2


def rss_gib(pids):
    total = 0
    for pid in set(pids):
        try:
            for line in (Path('/proc') / str(pid) / 'status').read_text().splitlines():
                if line.startswith('VmRSS:'):
                    total += int(line.split()[1]) * 1024
        except FileNotFoundError:
            continue
    return total / 1024 ** 3


def cpu_seconds(pid):
    try:
        fields = (Path('/proc') / str(pid) / 'stat').read_text().rsplit(')', 1)[1].split()
        return (int(fields[11]) + int(fields[12])) / os.sysconf('SC_CLK_TCK')
    except FileNotFoundError:
        return None


def least_busy_cpus(cpus):
    def counters():
        result = {}
        for line in Path('/proc/stat').read_text().splitlines():
            fields = line.split()
            if fields and re.fullmatch(r'cpu[0-9]+', fields[0]):
                cpu = int(fields[0][3:]); values = list(map(int, fields[1:]))
                if cpu in cpus:
                    # Guest time is already counted in user/nice; do not double it.
                    result[cpu] = (sum(values[:8]), values[3] + values[4])
        return result
    first = counters(); time.sleep(.2); second = counters()
    def busy(cpu):
        total = second[cpu][0] - first[cpu][0]
        idle = second[cpu][1] - first[cpu][1]
        return (1 - idle / total if total else 1, cpu)
    return sorted(cpus, key=busy)


def starvation_predicate(saved, c, now=None):
    sample = saved.get('cpu_sample')
    if now is None:
        now = time.monotonic() if sample and sample.get('monotonic') else time.time()
    if not sample or now - sample['epoch'] < c['starvation_observation_seconds']:
        return None
    proc = process(sample['pid'])
    if proc is None or proc['start_ticks'] != sample['start_ticks'] or proc['boot_id'] != sample['boot_id']:
        return None  # Unit exit handling owns this case; never infer PID ownership.
    current = cpu_seconds(sample['pid'])
    if current is None:
        return None
    wall = now - sample['epoch']; share = (current - sample['cpu_seconds']) / wall
    result = dict(task=saved['task'], unit=saved['unit'], observation_seconds=wall,
                delivered_cpu_share=share, starved=share < c['starvation_min_cpu_share'],
                action='cooperative_checkpoint_drain_and_defer_without_requeue')
    # Reset each nonstarved window. An early burst must not hide a later full
    # 300s without CPU. Persisted ownership identity is unchanged by this sample.
    if not result['starved']:
        saved['cpu_sample'] = dict(sample, epoch=now, cpu_seconds=current)
    return result


def baseline_snapshot(c, system):
    result = {}
    for name in c['baseline_units']:
        props = system.unit(name)
        if props.get('ActiveState') != 'active' or int(props.get('MainPID', '0')) <= 0:
            raise RuntimeError('expected healthy current baseline service is not active: ' + name)
        proc = process(int(props['MainPID']))
        if proc is None:
            raise RuntimeError('baseline process disappeared during admission: ' + name)
        result[name] = dict(properties=props, process=proc)
    terminal = read(c['AT_terminal'])
    if terminal['status'] not in c['AT_allowed_terminal_statuses']:
        raise RuntimeError('AT must remain in explicitly audited terminal state')
    return dict(units=result, AT_terminal_sha256=digest(c['AT_terminal']))


def handoff_snapshot(c, system, previous=None, *, now=None):
    now = time.time() if now is None else now
    state = read(c['handoff_state']); heartbeat = state.get('heartbeat')
    if (state.get('phase') != 'waiting_boundary' or not isinstance(heartbeat, (int, float))
            or not math.isfinite(heartbeat) or not 0 <= now - heartbeat <= c['handoff_fresh_seconds']):
        raise RuntimeError('handoff phase/freshness predicate failed: ' + json.dumps(state, sort_keys=True))
    owner = process(state['owner']['pid'])
    if not same_lifetime(owner, state['owner']) or owner.get('state') == 'Z':
        raise RuntimeError('handoff owner lifetime differs from current state')
    guardian = system.unit(state['guardian_unit'])
    guardian_proc = process(int(guardian.get('MainPID', '0')))
    if guardian.get('ActiveState') != 'active' or guardian_proc is None or guardian_proc.get('state') == 'Z':
        raise RuntimeError('handoff guardian is not healthy')
    snapshot = dict(attempt=state['attempt'], phase=state['phase'], heartbeat=heartbeat,
        owner=owner, guardian_unit=state['guardian_unit'], guardian=guardian, guardian_process=guardian_proc)
    if previous:
        if (snapshot['attempt'] != previous['attempt'] or snapshot['phase'] != previous['phase']
                or not same_lifetime(owner, previous['owner'])
                or snapshot['guardian_unit'] != previous['guardian_unit']
                or not same_lifetime(guardian_proc, previous['guardian_process'])
                or guardian['InvocationID'] != previous['guardian']['InvocationID']
                or heartbeat < previous['heartbeat']):
            raise RuntimeError('handoff owner/attempt/phase/guardian lifetime or heartbeat regressed')
    return snapshot


def workflow_members(c, system, source_head, controller):
    """Observe the separately owned499 tree; never stop it from a wave guard."""
    path = Path(c['runtime']) / 'workflow_launch.json'
    if not path.is_file():
        return []
    record = read(path)
    workflow_entry = ENTRY.with_name('499_execute_pricefm_stage_r150_finite_workflow.py')
    command = record.get('command', [])
    expected_prefix = [c['python_runtime'], '-B', str(workflow_entry), 'run', '--release']
    if (not re.fullmatch(r'pricefm-r150-workflow-[0-9a-f]{32}\.service', record.get('unit', ''))
            or record.get('source_head') != source_head
            or record.get('source_entry_sha256') != digest(workflow_entry)
            or len(command) != 6 or command[:5] != expected_prefix
            or not Path(command[5]).is_absolute()
            or record.get('admitted_order') != ['1','2','3']
            or record.get('runtime_seconds') != 365*60
            or record.get('release_sha256') != digest(command[5])):
        raise RuntimeError('owned workflow launch record source/unit/command differs')
    release = read(command[5])
    if (release.get('status') != 'PASS_PROTECTED_SOURCES_MANIFESTS_AND_R150_RELEASE'
            or release.get('source',{}).get('head') != source_head
            or release.get('source',{}).get('remote_head') != source_head):
        raise RuntimeError('owned workflow release differs from admitted source')
    expected_cgroup = str(Path(controller['ControlGroup']).parent / record['unit'])
    description = WORKFLOW_DESCRIPTION
    if record.get('description', description) != description or record.get('expected_cgroup',expected_cgroup) != expected_cgroup:
        raise RuntimeError('owned workflow intent/cgroup differs')
    saved = dict(unit=record['unit'], argv=command, description=description,
                 expected_cgroup=expected_cgroup)
    if record.get('attested'):
        saved['attested'] = record['attested']
    props = system.unit(record['unit']); verify_owned(saved, props)
    if (props.get('ActiveState') != 'active' or props.get('ControlGroup') != expected_cgroup
            or not props.get('InvocationID') or props.get('CPUSchedulingPolicy') != '0'):
        raise RuntimeError('owned workflow controller is not the audited active lifecycle')
    return system.members(expected_cgroup)


def guard(c, system, admission, lease, workers, controller, previous_handoff=None):
    now = time.time()
    if now >= lease['expires_epoch']:
        raise RuntimeError('nonrenewing lease expired')
    if lease['boot_id'] != Path('/proc/sys/kernel/random/boot_id').read_text().strip():
        raise RuntimeError('lease cannot cross host boots')
    verify_source(admission['source'])
    verify_baseline_sources(c)
    verify_benchmark_import(c, system)
    assert_parent_policy(c)
    handoff = handoff_snapshot(c, system, previous_handoff or admission['handoff'])
    for name, saved in admission['baseline']['units'].items():
        props = system.unit(name)
        if (props.get('ActiveState') != 'active'
                or any(props.get(k) != saved['properties'].get(k) for k in BASELINE_STABLE)
                or exec_arguments(props) != exec_arguments(saved['properties'])
                or not same_lifetime(process(int(props.get('MainPID', '0'))), saved['process'])):
            raise RuntimeError('current audited baseline lifecycle changed: ' + name)
    if digest(c['AT_terminal']) != admission['baseline']['AT_terminal_sha256']:
        raise RuntimeError('audited AT terminal changed')
    available = memory_available_gib(); disk = shutil.disk_usage(c['disk_path']).free / 1024 ** 3
    pids = system.members(controller['ControlGroup'])
    pids += workflow_members(c, system, admission['source']['head'], controller)
    for worker in workers:
        props = system.unit(worker['unit']); verify_owned(worker, props)
        cg = (worker.get('attested') or props).get('ControlGroup')
        if cg:
            pids += system.members(cg)
    owned_rss = rss_gib(pids)
    predicate = dict(epoch=now, available_memory_gib=available, disk_free_gib=disk,
                     owned_rss_gib=owned_rss, handoff=handoff)
    if available < c['min_available_memory_gib'] or disk < c['min_disk_gib'] or owned_rss > c['max_owned_rss_gib']:
        raise RuntimeError('shared-resource floor/owned-RSS predicate failed: ' + json.dumps(predicate, sort_keys=True))
    return predicate


def admit(c, runtime, system):
    assert_parent_policy(c); release = source_release(); verify_baseline_sources(c)
    verify_benchmark_import(c, system)
    probe = read(c['capability_probe'])
    if (probe.get('status') != 'PASS_OWNED_UNIT_POLICY_AND_BINDS_TO_DRAIN'
            or probe.get('resource_entry_sha256') != digest(ENTRY)
            or probe.get('boot_id') != Path('/proc/sys/kernel/random/boot_id').read_text().strip()):
        raise RuntimeError('actual same-source same-boot owned-unit capability proof required')
    first = handoff_snapshot(c, system)
    # Two cheap readings prove advancement. Do not wait for scientific work.
    deadline = time.monotonic() + 20
    second = first
    while second['heartbeat'] == first['heartbeat'] and time.monotonic() < deadline:
        time.sleep(1); second = handoff_snapshot(c, system, first)
    if second['heartbeat'] <= first['heartbeat']:
        raise RuntimeError('handoff heartbeat did not advance at admission')
    admission = dict(schema_version=1, stage='R150', epoch=time.time(), source=release,
        mode='B', cpus=c['cpus'], capability_probe_sha256=digest(c['capability_probe']),
        baseline=baseline_snapshot(c, system), handoff=second)
    if memory_available_gib() < c['min_available_memory_gib'] or shutil.disk_usage(c['disk_path']).free / 1024 ** 3 < c['min_disk_gib']:
        raise RuntimeError('memory/disk admission floor failed')
    path = Path(runtime) / 'admission.json'
    if path.exists():
        existing = read(path)
        verify_source(existing['source'], full=True)
        if existing['source'] != admission['source'] or existing['baseline'] != admission['baseline']:
            # Baseline snapshots contain transient formatting/state. Compare only
            # lifetime and immutable service fields, not uptime or current /proc S/R.
            for name, saved in existing['baseline']['units'].items():
                current = admission['baseline']['units'].get(name)
                if (not current or not same_lifetime(current['process'], saved['process'])
                        or any(current['properties'].get(k) != saved['properties'].get(k) for k in BASELINE_STABLE)
                        or exec_arguments(current['properties']) != exec_arguments(saved['properties'])):
                    raise RuntimeError('cannot replace frozen admission with a new baseline lifetime')
            if (existing['source'] != admission['source']
                    or existing['baseline']['AT_terminal_sha256'] != admission['baseline']['AT_terminal_sha256']):
                raise RuntimeError('cannot replace frozen admission source/AT receipt')
        handoff_snapshot(c, system, existing['handoff'])
        atomic(Path(runtime) / 'preflights' / (str(time.time_ns()) + '.json'), admission)
        return existing
    atomic(path, admission)
    return admission


def lease_once(c, root_runtime, wave, admission):
    if wave not in ('1', '2', '3'):
        raise RuntimeError('only three remaining finite waves admitted; no new benchmark lease')
    root_runtime = Path(root_runtime)
    path = root_runtime / ('wave_' + wave) / 'lease.json'
    with locked(root_runtime / 'lease.lock'):
        if path.exists():
            lease = read(path)
            if lease['source_head'] != admission['source']['head']:
                raise RuntimeError('existing lease belongs to different source')
            if lease['expires_epoch'] <= time.time():
                raise RuntimeError('expired lease cannot be renewed or replaced')
            if lease['admission_sha256'] != digest(root_runtime / 'admission.json'):
                raise RuntimeError('immutable admission changed under existing lease')
            return lease
        if wave == '1':
            imported = verify_benchmark_import(c)
        else:
            previous = str(int(wave) - 1)
            prior = root_runtime / ('wave_' + previous) / 'terminal.json'
            if not prior.is_file() or read(prior).get('cleanup_verified') is not True:
                raise RuntimeError('preceding wave must be terminal and fully drained')
            if read(prior)['status'] not in ('R150_WAVE_COMPLETE', 'R150_WAVE_DEFERRED'):
                raise RuntimeError('guard-stopped predecessor requires a new explicit review')
        now = time.time(); duration = c['wave_seconds']
        lease = dict(schema_version=1, stage='R150', wave=wave, lease_id=uuid.uuid4().hex,
            started_epoch=now, expires_epoch=now + duration, seconds=duration,
            source_head=admission['source']['head'], admission_sha256=digest(root_runtime / 'admission.json'),
            boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(), nonrenewing=True)
        if wave == '1':
            lease['original_benchmark_producer_head'] = imported['original_science_source']['head']
            lease['original_benchmark_lease_id'] = read(imported['original_wave']['lease_path'])['lease_id']
            lease['original_benchmark_import_sha256'] = c['benchmark_import']['sha256']
        atomic(path, lease)
        return lease


def load_science():
    spec = importlib.util.spec_from_file_location('r150_science_resource_api', SCIENCE)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    if 'numpy' in sys.modules:
        raise RuntimeError('scientific scheduling API imported numerical dependencies in controller')
    return module


def controller_proof(system, name, c):
    props = system.unit(name)
    if (not name.startswith('pricefm-r150-') or props.get('MainPID') != str(os.getpid())
            or props.get('ActiveState') != 'active' or props.get('KillMode') != 'control-group'
            or props.get('Restart') != 'no' or not props.get('InvocationID')
            or props.get('CPUSchedulingPolicy') != '0' or not props.get('ControlGroup')):
        raise RuntimeError('controller must be the pinned active dedicated R150 unit')
    assert_parent_policy(c)
    return props


def start_worker(c, system, runtime, task, cpu, lease, admission, controller):
    token = uuid.uuid4().hex
    unit = 'pricefm-r150-w' + lease['wave'] + '-' + token + '.service'
    directory = Path(runtime) / 'workers' / token; directory.mkdir(parents=True)
    receipt_path = directory / 'policy_receipt.json'
    spec_path = directory / 'bootstrap_spec.json'
    target = [c['python_runtime'], '-B', str(SCIENCE), 'worker', '--task', task['name'],
              '--cpu', str(cpu), '--policy-receipt', str(receipt_path)]
    spec = dict(stage='R150', task=task['name'], cpu=cpu, release_receipt=str(receipt_path),
                expires_epoch=lease['expires_epoch'], target_argv=target,
                source_entry_sha256=digest(ENTRY), source_head=admission['source']['head'])
    atomic(spec_path, spec)
    argv = idle_command([c['python_runtime'], '-B', str(ENTRY), 'bootstrap', '--spec', str(spec_path)])
    description = 'R150 owned ' + token + ' lease ' + lease['lease_id'] + ' source ' + admission['source']['head']
    saved = dict(unit=unit, token=token, task=task['name'], cpu=cpu,
        description=description, argv=argv, spec_sha256=digest(spec_path),
        lease_id=lease['lease_id'], started_epoch=time.time(), policy_receipt=str(receipt_path),
        ledger_path=str(directory / 'ownership.json'),
        expected_cgroup=str(Path(controller['ControlGroup']).parent / unit),
        estimated_cpu_seconds=task.get('estimated_cpu_seconds', 0))
    # Intent persists before the only external side effect. Cleanup can attest
    # the exact UUID/description/argv if an interrupt lands before acknowledgement.
    atomic(saved['ledger_path'], saved)
    system.start(unit, description, argv, cpus=[cpu], idle=True,
        runtime_seconds=min(lease['expires_epoch'] - time.time(), c['benchmark_seconds'] if lease['wave'] == 'benchmark' else c['wave_seconds']),
        controller=controller['Id'], stdout=directory / 'worker.stdout')
    deadline = time.monotonic() + 10
    props = system.unit(unit)
    while props.get('ActiveState') == 'activating' and time.monotonic() < deadline:
        time.sleep(.05); props = system.unit(unit)
    verify_owned(saved, props)
    proc = process(int(props.get('MainPID', '0')))
    deadline = time.monotonic() + 3
    while proc and proc['scheduler'] != os.SCHED_IDLE and time.monotonic() < deadline:
        time.sleep(.02); proc = process(int(props.get('MainPID', '0')))
    if (props.get('ActiveState') != 'active' or not props.get('InvocationID')
            or controller['Id'] not in props.get('BindsTo', '').split()
            or controller['Id'] not in props.get('After', '').split()
            or props.get('CPUSchedulingPolicy') not in ('0', '5') or props.get('IOSchedulingClass') != '3'
            or not 0 < parse_duration(props.get('RuntimeMaxUSec', '')) <= lease['seconds']
            or proc is None or proc['affinity'] != [cpu] or proc['scheduler'] != os.SCHED_IDLE
            or system.members(props['ControlGroup']) != [proc['pid']]):
        raise RuntimeError('owned worker policy/cgroup proof failed: ' + json.dumps(dict(properties=props, process=proc)))
    saved['attested'] = props; saved['process'] = proc
    saved['cpu_sample'] = dict(pid=proc['pid'], start_ticks=proc['start_ticks'],
        boot_id=proc['boot_id'], epoch=time.monotonic(), monotonic=True, cpu_seconds=cpu_seconds(proc['pid']))
    atomic(saved['ledger_path'], saved)
    receipt = dict(schema_version=1, stage='R150', task=task['name'], cpu=cpu,
        expected_affinity=[cpu], expected_scheduler=os.SCHED_IDLE, numerical_threads=1, io_class=3,
        unit=unit, controller_unit=controller['Id'], source_head=admission['source']['head'],
        source_sha256=admission['source']['sha256'], lease_id=lease['lease_id'],
        lease_expires_epoch=lease['expires_epoch'], worker_invocation_id=props['InvocationID'],
        worker_cgroup=props['ControlGroup'], probe_id=admission['capability_probe_sha256'],
        actual_probe=dict(properties=props, process=proc), stop_request_path=str(directory / 'stop_requests' / (task['name'] + '.json')))
    receipt['requested_unit_scheduling_policy'] = 'idle'
    receipt['actual_unit_scheduling_policy_property'] = props.get('CPUSchedulingPolicy')
    receipt['idle_exec_wrapper'] = dict(argv_prefix=[IDLE_WRAPPER,'--idle','0'],
                                       sha256=admission['source']['idle_wrapper_sha256'])
    atomic(receipt_path, receipt)
    return saved


def bootstrap(spec_path):
    spec = read(spec_path)
    if digest(ENTRY) != spec['source_entry_sha256']:
        raise RuntimeError('bootstrap source changed')
    if sorted(os.sched_getaffinity(0)) != [spec['cpu']] or os.sched_getscheduler(0) != os.SCHED_IDLE:
        raise RuntimeError('bootstrap was not pinned and idle from first exec')
    deadline = min(time.time() + 20, spec['expires_epoch'])
    while not Path(spec['release_receipt']).is_file() and time.time() < deadline:
        time.sleep(.05)
    receipt = read(spec['release_receipt'])
    if (receipt['task'] != spec['task'] or receipt['cpu'] != spec['cpu']
            or receipt['lease_expires_epoch'] != spec['expires_epoch']
            or receipt['source_head'] != spec['source_head'] or time.time() >= spec['expires_epoch']
            or any(os.environ.get(name) != '1' for name in THREAD_VARS)):
        raise RuntimeError('bootstrap release/lease/thread proof failed')
    os.execv(spec['target_argv'][0], spec['target_argv'])


def discover_workers(runtime):
    return [read(path) for path in sorted((Path(runtime) / 'workers').glob('*/ownership.json'))]


def projection_fits(task, c, lease, active_count):
    if lease['wave'] == 'benchmark':
        raise RuntimeError('new benchmark lease/task is forbidden in bounded successor')
    if task.get('name') == '__benchmark__':
        raise RuntimeError('original benchmark must be imported; no numerical benchmark rerun')
    estimate = task.get('estimated_cpu_seconds')
    if estimate is None or not math.isfinite(estimate) or estimate < 0:
        raise RuntimeError('nonbenchmark task lacks frozen conservative timing estimate')
    wall = task.get('estimated_wall_seconds')
    if wall is None or not math.isfinite(wall) or wall < estimate:
        raise RuntimeError('nonbenchmark task lacks benchmark-adjusted conservative wall estimate')
    remaining = lease['expires_epoch'] - time.time() - c['wave_cleanup_buffer_seconds']
    return estimate <= c['projection_cpu_seconds'] and wall <= remaining


def run(c, wave, controller_unit):
    system = System(); root_runtime = Path(c['runtime'])
    runtime = root_runtime / ('wave_' + wave)
    with locked(root_runtime / 'controller.lock'):
        if (runtime / 'terminal.json').exists():
            raise RuntimeError('terminal wave cannot be restarted automatically')
        controller = controller_proof(system, controller_unit, c)
        admission = read(root_runtime / 'admission.json')
        verify_source(admission['source'])
        lease = lease_once(c, root_runtime, wave, admission)
        if parse_duration(controller.get('RuntimeMaxUSec', '')) > lease['expires_epoch'] - lease['started_epoch'] + 30:
            raise RuntimeError('controller RuntimeMaxSec exceeds finite wave budget')
        science = load_science(); active = {}; stop = [False]; original_reason = None
        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, lambda _signum, _frame: stop.__setitem__(0, True))
        status = 'R150_WAVE_DEFERRED'; cleanup_errors = []; cleanup = []
        last_handoff = admission['handoff']; last_heartbeat = 0; queue = {}
        try:
            # Admission writes are metadata-only; science preparation must already
            # be pinned. An interrupted previous startup is drained before dispatch.
            for saved in discover_workers(runtime):
                cleanup.append(stop_and_drain(system, saved))
            while True:
                predicate = guard(c, system, admission, lease, list(active.values()), controller, last_handoff)
                last_handoff = predicate['handoff']
                if time.time() - last_heartbeat >= 15:
                    atomic(runtime / 'heartbeat.json', dict(status='R150_RUNNING', wave=wave,
                        active=list(active), lease_id=lease['lease_id'], predicates=predicate))
                    last_heartbeat = time.time()
                if stop[0]:
                    original_reason = 'cooperative controller stop requested'; break
                for name, saved in list(active.items()):
                    props = system.unit(saved['unit']); verify_owned(saved, props)
                    if props.get('ActiveState') in ('inactive', 'failed') or props.get('LoadState') == 'not-found':
                        cleanup.append(stop_and_drain(system, saved)); del active[name]
                        if not science.task_complete(name):
                            raise RuntimeError('worker exited without strict task seal: ' + name)
                        event(runtime, 'task_complete', task=name, unit=saved['unit'])
                # Strict numerical seals can precede worker CPU-accounting tails.
                # Transition only after every current worker has exited/drained;
                # pending work within the current phase remains dispatchable.
                if not active:
                    science.advance()
                queue = science.queue_state()
                if queue['terminal'] and not active:
                    status = 'R150_WAVE_COMPLETE'; original_reason = 'all scientific tasks strictly complete'; break
                if wave == 'benchmark' and science.task_complete('__benchmark__'):
                    status = 'R150_WAVE_COMPLETE'; original_reason = 'benchmark sealed; branch frozen; no numerical pool launched in benchmark lease'; break
                ready = [task for task in queue['ready'] if task['name'] not in active]
                if wave != 'benchmark' and any(task['name'] == '__benchmark__' for task in ready):
                    raise RuntimeError('benchmark must finish in its separate finite lease')
                available_cpus = [cpu for cpu in c['cpus'] if cpu not in [saved['cpu'] for saved in active.values()]]
                if ready and available_cpus and len(active) < c['max_workers']:
                    available_cpus = least_busy_cpus(available_cpus)
                deferred = []
                for task in ready:
                    if len(active) >= c['max_workers']:
                        break
                    if not projection_fits(task, c, lease, len(active)):
                        deferred.append(task['name']); continue
                    reserved = sum(item.get('estimated_cpu_seconds', 0) for item in discover_workers(runtime))
                    if wave != 'benchmark' and reserved + task['estimated_cpu_seconds'] > c['projection_cpu_seconds'] * c['max_workers']:
                        deferred.append(task['name']); continue
                    cpu = available_cpus.pop(0)
                    saved = start_worker(c, system, runtime, task, cpu, lease, admission, controller)
                    active[task['name']] = saved
                    event(runtime, 'worker_released', task=task['name'], unit=saved['unit'], cpu=cpu,
                          worker_invocation_id=saved['attested']['InvocationID'])
                if not active and (deferred or not ready):
                    original_reason = 'no ready task fits frozen projection budget' if deferred else 'no ready scientific task; no implicit completion'
                    break
                starved = [value for value in (starvation_predicate(saved, c) for saved in active.values())
                           if value and value['starved']]
                if starved:
                    # A first conservative deferral uses zero retries. This is
                    # stricter than the plan's maximum one verified requeue and
                    # avoids replaying R149's last-task rescheduling episode.
                    event(runtime, 'idle_cpu_starvation', predicates=starved, requeues_used=0)
                    original_reason = 'idle CPU share below.10 for300s; checkpoint and defer without requeue'; break
                # A wave stops numerical work with its final 30min still reserved.
                if wave != 'benchmark' and time.time() >= lease['expires_epoch'] - c['wave_cleanup_buffer_seconds']:
                    original_reason = '90min numerical allocation exhausted; preserve checkpoints'; break
                time.sleep(c['poll_seconds'])
        except Exception as error:
            original_reason = repr(error); status = 'R150_GUARD_STOPPED'
            event(runtime, 'original_stop_reason', reason=original_reason)
        finally:
            # Preserve the original exception independently of every cleanup
            # predicate. Never replace it with a secondary cleanup failure.
            for saved in discover_workers(runtime):
                try:
                    receipt_path = Path(saved['policy_receipt'])
                    request = receipt_path.parent / 'stop_requests' / (saved['task'] + '.json')
                    atomic(request, dict(stage='R150', reason=original_reason, epoch=time.time(), cooperative=True))
                except Exception as error:
                    cleanup_errors.append(dict(unit=saved['unit'], operation='cooperative_request', error=repr(error)))
            # A short grace allows an in-flight chunk to seal. BindsTo and the
            # finite unit timeout remain independent backstops for parent death.
            if active:
                queue_projection = queue.get('resource_projection', {})
                observed_chunk = queue_projection.get('max_chunk_wall_seconds', 0)
                grace = max(c['cooperative_grace_seconds'], min(observed_chunk * 1.5, 120))
                # Units that finish their chunk need no remaining grace. Polling
                # avoids sleeping past an already proven drain.
                deadline = time.monotonic() + min(grace, max(0, lease['expires_epoch'] - time.time()))
                while time.monotonic() < deadline:
                    if all(system.unit(saved['unit']).get('ActiveState') in ('inactive', 'failed')
                           for saved in active.values()):
                        break
                    time.sleep(.2)
            for saved in discover_workers(runtime):
                try:
                    cleanup.append(stop_and_drain(system, saved))
                except Exception as error:
                    try:
                        current = system.unit(saved['unit'])
                    except Exception as read_error:
                        current = dict(read_error=repr(read_error))
                    cleanup_errors.append(dict(unit=saved['unit'], operation='manager_stop_and_cgroup_drain',
                        error=repr(error), saved=saved, current=current))
            terminal = dict(schema_version=1, stage='R150', wave=wave, status=status,
                original_stop_reason=original_reason, cleanup_verified=not cleanup_errors,
                cleanup_errors=cleanup_errors, cleanup=cleanup, source=admission['source'],
                lease=lease, epoch=time.time(), baseline_worker_signals=0,
                shared_quota_writes=0, numerical_fits=0, no_automatic_promotion=True)
            atomic(runtime / 'terminal.json', terminal)
            event(runtime, 'terminal', **terminal)
        return 0 if not cleanup_errors and status != 'R150_GUARD_STOPPED' else 2


def launch(c, wave):
    """Launch controller after preflight; never silently start a subsequent wave."""
    assert_parent_policy(c); system = System(); runtime = Path(c['runtime'])
    admission = admit(c, runtime, system); lease = lease_once(c, runtime, wave, admission)
    name = 'pricefm-r150-controller-' + wave + '-' + uuid.uuid4().hex + '.service'
    argv = [c['python_runtime'], '-B', str(ENTRY), 'run', '--wave', wave, '--controller-unit', name]
    parent_groups = {str(Path(item['properties']['ControlGroup']).parent)
                     for item in admission['baseline']['units'].values()}
    if len(parent_groups) != 1:
        raise RuntimeError('audited baseline user-service hierarchy is ambiguous')
    expected_cgroup = next(iter(parent_groups)) + '/' + name
    if not expected_cgroup.startswith('/user.slice/'):
        raise RuntimeError('audited controller cgroup is outside user-service hierarchy')
    record = dict(unit=name, argv=argv, description='R150 finite controller lease ' + lease['lease_id'],
        lease=lease, source_head=admission['source']['head'], epoch=time.time(), expected_cgroup=expected_cgroup)
    folder = runtime / ('wave_' + wave)
    # Persist intent before start so rapid exits cannot erase the only evidence
    # of which cgroup must be observed during independent cleanup.
    atomic(folder/'controller_launch.json', record)
    try:
        system.start(name, record['description'], argv,
            cpus=c['cpus'], idle=False, runtime_seconds=lease['expires_epoch'] - time.time(),
            stdout=folder/'controller.stdout')
        props = system.unit(name); verify_owned(record, props)
        if props.get('ActiveState') == 'active':
            if props.get('ControlGroup') != expected_cgroup or not props.get('InvocationID'):
                raise RuntimeError('controller cgroup/invocation differs from persisted intent')
            record['attested'] = props
            atomic(folder/'controller_launch.json', record)
    except Exception as original:
        failure = dict(original_launch_error=repr(original), intent=record, epoch=time.time())
        try:
            failure['cleanup'] = stop_and_drain(system, record)
            failure['cleanup_verified'] = True
        except Exception as cleanup_error:
            failure.update(cleanup_verified=False, cleanup_error=repr(cleanup_error))
        try:
            atomic(folder/('controller_launch_failure_'+uuid.uuid4().hex+'.json'), failure)
        except Exception as receipt_error:
            failure['receipt_write_error'] = repr(receipt_error)
        raise RuntimeError('owned controller launch failed: ' + json.dumps(failure,sort_keys=True)) from original
    return record


def capability_probe(output, python):
    """Real disposable units prove scheduler/affinity/I/O/BindsTo drain, no science."""
    if sorted(os.sched_getaffinity(0)) != list(range(15, 30)):
        raise RuntimeError('capability probe itself must inherit CPUs15-29 from first exec')
    system = System(); token = uuid.uuid4().hex
    probe_cpu = least_busy_cpus(list(range(15,30)))[0]
    log_root = Path(output).parent / 'owned_unit_probe_logs' / token
    log_root.mkdir(parents=True)
    parent = 'pricefm-r150-test-parent-' + token + '.service'
    child = 'pricefm-r150-test-child-' + token + '.service'
    parent_argv = [python, '-B', str(ENTRY), 'test-hold']
    child_argv = idle_command([python, '-B', str(ENTRY), 'test-tree'])
    parent_saved = dict(unit=parent, description='R150 disposable parent ' + token, argv=parent_argv)
    child_saved = dict(unit=child, description='R150 disposable child ' + token, argv=child_argv)
    result = dict(stage='R150', epoch=time.time(), resource_entry_sha256=digest(ENTRY),
        boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
        parent_unit=parent, child_unit=child, probe_cpu=probe_cpu, baseline_worker_signals=0)
    owned = [parent_saved, child_saved]
    try:
        system.start(parent, parent_saved['description'], parent_argv, cpus=list(range(15, 30)), idle=False,
                     runtime_seconds=45, stdout=log_root/'parent.stdout')
        pp = system.unit(parent); parent_saved['attested'] = pp; verify_owned(parent_saved, pp)
        system.start(child, child_saved['description'], child_argv, cpus=[probe_cpu], idle=True,
                     runtime_seconds=30, controller=parent, stdout=log_root/'child.stdout')
        cp = system.unit(child); child_saved['attested'] = cp; verify_owned(child_saved, cp)
        child_proc = process(int(cp.get('MainPID', '0')))
        deadline = time.monotonic() + 3
        while child_proc and child_proc['scheduler'] != os.SCHED_IDLE and time.monotonic() < deadline:
            time.sleep(.02); child_proc = process(int(cp.get('MainPID', '0')))
        result.update(parent_properties=pp, child_properties=cp, child_process=child_proc)
        if (cp.get('CPUSchedulingPolicy') not in ('0','5') or cp.get('IOSchedulingClass') != '3'
                or child_proc is None or child_proc['affinity'] != [probe_cpu]
                or child_proc['scheduler'] != os.SCHED_IDLE
                or parent not in cp.get('BindsTo', '').split()
                or parent not in cp.get('After', '').split()
                or parse_duration(cp['RuntimeMaxUSec']) != 30):
            raise RuntimeError('actual disposable worker numerical policy failed')
        deadline = time.monotonic() + 5
        descendants = system.members(cp['ControlGroup'])
        while len(descendants) < 2 and time.monotonic() < deadline:
            time.sleep(.05); descendants = system.members(cp['ControlGroup'])
        if len(descendants) < 2:
            raise RuntimeError('disposable descendant tree did not become observable')
        result.update(parent_properties=pp, child_properties=cp, child_process=child_proc,
                      pre_fault_descendants=descendants)
        actual_child = json.loads((log_root/'child.stdout').read_text().splitlines()[0])
        if (actual_child['invocation_id'] != cp['InvocationID']
                or actual_child['scheduler'] != os.SCHED_IDLE or actual_child['affinity'] != [probe_cpu]
                or actual_child['io_class'] != 'idle'
                or any(actual_child['thread_env'].get(name) != '1' for name in THREAD_VARS)):
            raise RuntimeError('first Python exec policy/InvocationID mismatch: ' + json.dumps(actual_child))
        result['actual_child_first_exec_policy'] = actual_child
        result['idle_exec_wrapper'] = dict(argv_prefix=[IDLE_WRAPPER,'--idle','0'], sha256=digest(IDLE_WRAPPER),
            requested_unit_scheduling_policy='idle', actual_unit_scheduling_policy_property=cp.get('CPUSchedulingPolicy'))
        # Abrupt controller death rather than a graceful shutdown must itself
        # drain the dependent worker AND its descendant through the manager.
        system.fail_owned_test_controller(parent_saved)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            current = system.unit(child)
            if current.get('ActiveState') in ('inactive', 'failed') and not system.members(cp['ControlGroup']):
                break
            time.sleep(.1)
        else:
            raise RuntimeError('BindsTo did not drain descendant tree after abrupt controller death')
        result['parent_drain'] = stop_and_drain(system, parent_saved)
        result['child_drain'] = stop_and_drain(system, child_saved)

        timeout_parent = 'pricefm-r150-test-timeout-parent-' + token + '.service'
        timeout_child = 'pricefm-r150-test-timeout-child-' + token + '.service'
        timeout_parent_saved = dict(unit=timeout_parent, description='R150 disposable timeout parent ' + token,
                                    argv=parent_argv)
        timeout_child_argv = idle_command(parent_argv)
        timeout_child_saved = dict(unit=timeout_child, description='R150 disposable timeout child ' + token,
                                   argv=timeout_child_argv)
        owned += [timeout_parent_saved, timeout_child_saved]
        system.start(timeout_parent, timeout_parent_saved['description'], parent_argv,
                     cpus=list(range(15,30)), idle=False, runtime_seconds=20, stdout=log_root/'timeout_parent.stdout')
        timeout_parent_saved['attested'] = system.unit(timeout_parent)
        system.start(timeout_child, timeout_child_saved['description'], timeout_child_argv,
                     cpus=[probe_cpu], idle=True, runtime_seconds=2, controller=timeout_parent,
                     stdout=log_root/'timeout_child.stdout')
        timeout_child_saved['attested'] = system.unit(timeout_child)
        timeout_cg = timeout_child_saved['attested']['ControlGroup']
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            timeout_props = system.unit(timeout_child)
            if timeout_props.get('ActiveState') in ('inactive','failed') and not system.members(timeout_cg):
                break
            time.sleep(.1)
        else:
            raise RuntimeError('actual RuntimeMaxSec timeout did not drain worker')
        if system.unit(timeout_parent).get('ActiveState') != 'active':
            raise RuntimeError('timeout was not isolated to owned child')
        result['runtime_expiry'] = dict(properties=timeout_props,
            parent_remained_active=True, drain=stop_and_drain(system, timeout_child_saved))

        rapid = 'pricefm-r150-test-rapid-' + token + '.service'
        rapid_argv = idle_command([python, '-B', str(ENTRY), 'test-rapid'])
        rapid_saved = dict(unit=rapid, description='R150 disposable rapid exit ' + token, argv=rapid_argv,
            expected_cgroup=str(Path(timeout_parent_saved['attested']['ControlGroup']).parent / rapid))
        owned.append(rapid_saved)
        system.start(rapid, rapid_saved['description'], rapid_argv, cpus=[probe_cpu], idle=True,
                     runtime_seconds=5, controller=timeout_parent, stdout=log_root/'rapid.stdout')
        rapid_props = system.unit(rapid)
        if rapid_props.get('LoadState') != 'not-found':
            verify_owned(rapid_saved, rapid_props); rapid_saved['attested'] = rapid_props
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            rapid_props = system.unit(rapid)
            if rapid_props.get('ActiveState') in ('inactive','failed') and not system.members(rapid_saved['expected_cgroup']):
                break
            time.sleep(.05)
        else:
            raise RuntimeError('rapid exit did not leave empty owned cgroup')
        result['rapid_exit'] = stop_and_drain(system, rapid_saved)
        result['status'] = 'PASS_OWNED_UNIT_POLICY_AND_BINDS_TO_DRAIN'
    except Exception as error:
        result.update(status='FAIL_OWNED_UNIT_CAPABILITY_PROBE', error=repr(error)); raise
    finally:
        for saved in reversed(owned):
            try:
                current = system.unit(saved['unit'])
                if current.get('LoadState') != 'not-found':
                    stop_and_drain(system, saved)
            except Exception as error:
                result.setdefault('cleanup_errors', []).append(repr(error))
        if result.get('cleanup_errors'):
            result['status'] = 'FAIL_OWNED_UNIT_CAPABILITY_PROBE'
        atomic(Path(output).with_name(Path(output).stem + '_' + token + '.json'), result)
        atomic(output, result)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['preflight', 'launch', 'run', 'bootstrap', 'probe', 'test-hold', 'test-tree', 'test-rapid', 'status'])
    parser.add_argument('--wave', choices=['1', '2', '3'])
    parser.add_argument('--controller-unit'); parser.add_argument('--spec'); parser.add_argument('--output')
    args = parser.parse_args(argv)
    if args.action == 'test-hold':
        time.sleep(40); return 0
    if args.action == 'test-tree':
        print(json.dumps(dict(invocation_id=os.environ.get('INVOCATION_ID'),
            scheduler=os.sched_getscheduler(0), affinity=sorted(os.sched_getaffinity(0)),
            io_class=subprocess.check_output(['/usr/bin/ionice','-p',str(os.getpid())],text=True).strip(),
            thread_env={name:os.environ.get(name) for name in THREAD_VARS})),flush=True)
        subprocess.Popen([sys.executable, '-B', str(ENTRY), 'test-hold'])
        time.sleep(40); return 0
    if args.action == 'test-rapid':
        # Rapid child exits exercise disappearing group membership without
        # repurposing baseline processes or a numerical workload.
        for _ in range(3):
            subprocess.run([sys.executable, '-B', '-c', 'pass'], check=True)
        return 0
    if args.action == 'bootstrap':
        bootstrap(args.spec); return 0
    if args.action == 'probe':
        print(json.dumps(capability_probe(args.output, sys.executable), sort_keys=True)); return 0
    c = read(CONFIG); validate_config(c)
    if args.action == 'status':
        runtime = Path(c['runtime'])
        print(json.dumps({wave: read(runtime / ('wave_' + wave) / 'terminal.json')
                         for wave in ('1', '2', '3')
                         if (runtime / ('wave_' + wave) / 'terminal.json').is_file()}, sort_keys=True)); return 0
    assert_parent_policy(c)
    if args.action == 'preflight':
        print(json.dumps(admit(c, Path(c['runtime']), System()), sort_keys=True)); return 0
    if args.wave is None:
        parser.error('wave is required')
    if args.action == 'launch':
        print(json.dumps(launch(c, args.wave), sort_keys=True)); return 0
    if not args.controller_unit:
        parser.error('run requires controller-unit')
    return run(c, args.wave, args.controller_unit)


if __name__ == '__main__':
    raise SystemExit(main())
