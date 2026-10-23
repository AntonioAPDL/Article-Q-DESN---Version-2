#!/usr/bin/env python3
"""Bounded, nonexclusive SCHED_IDLE EE development; never controls baseline jobs.

The responsive supervisor stays SCHED_OTHER. Its own gated worker processes use
SCHED_IDLE and idle I/O before the scientific payload is permitted to execute.
Observing an R146 handoff transition ends this lease. Polling is not an atomic
interlock with the frozen baseline: SCHED_IDLE protects its normal-priority work
during that observation race. This service MUST use KillMode=control-group and
Restart=no; it has no baseline signal, systemctl-stop, or affinity-write path.
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
import select
import shutil
import signal
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
CONFIG = ROOT / 'application/config/pricefm_stage_r148_ee_idle_resources_20261023.json'
SCIENCE = ROOT / 'application/scripts/pricefm/492_run_pricefm_stage_r148_ee_parallel_development.py'
THREADS = ('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS',
           'VECLIB_MAXIMUM_THREADS', 'NUMEXPR_NUM_THREADS', 'BLIS_NUM_THREADS')
GIB = 1024 ** 3
STAGE = 'R148'
REQUIRED_BRANCH = 'work/pricefm-r148-ee-parallel-screening-20261023'
REQUIRED_UNIT = 'pricefm-r148-muscat-ee-idle-development.service'
ALLOWED_TASK_KINDS = ['cached_rhs_rescore']
SOURCE_PATHS = None
REQUIRE_ALL_TASKS_COMPLETE = False


def read(path):
    return json.loads(Path(path).read_text())


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def atomic(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.tmp.' + str(os.getpid()))
    temporary.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')
    os.replace(temporary, path)


def git(*args, root=None):
    return subprocess.check_output(['git', *args], cwd=ROOT if root is None else root, text=True).strip()


def validate_config(config):
    if (config['allowed_cpus'] != list(range(30)) or config['max_workers'] != 2
            or config['lease_seconds'] != 7200 or config['poll_seconds'] > 1
            or config['poll_seconds'] < 0.1 or config['worker_policy'] != 'SCHED_IDLE'
            or config['io_class'] != 'idle' or config['numerical_threads'] != 1
            or config['baseline_signals_authorized'] is not False
            or config['exclusive_cpu_ownership'] is not False
            or config['allowed_task_kinds'] != ALLOWED_TASK_KINDS
            or config['own_rss_guard_gib'] != 24
            or config['resource_limit_mode'] != 'idle_policy_affinity_and_soft_owned_RSS_guard'
            or config['service_properties'] != {'KillMode': 'control-group', 'Restart': 'no'}
            or config['unit'] != REQUIRED_UNIT):
        raise RuntimeError('configuration exceeds the authorized idle development lease')
    if config['min_available_memory_gib'] < 180 or config['min_free_disk_gib'] < 80:
        raise RuntimeError('baseline resource floors may not be lowered')


def source_identity():
    result = {'head': git('rev-parse', 'HEAD'), 'branch': git('branch', '--show-current')}
    if result['branch'] != REQUIRED_BRANCH or git('status', '--porcelain'):
        raise RuntimeError('clean committed ' + STAGE + ' development worktree required')
    return result


def source_paths():
    if SOURCE_PATHS is not None:
        return list(SOURCE_PATHS)
    return [ENTRY, CONFIG, SCIENCE,
        ROOT / 'application/config/pricefm_stage_r148_ee_parallel_development_20261023.json',
        ROOT / 'application/config/pricefm_stage_r148_ee_cached_controls_20261023.json',
        ROOT / 'application/tests/test_pricefm_stage_r148_ee_idle_resources.py',
        ROOT / 'application/tests/test_pricefm_stage_r148_ee_parallel_development.py',
        ROOT / 'application/tests/test_pricefm_stage_r148_scientific_review.py',
        ROOT / 'docs/implementation_notes/pricefm_stage_r148_ee_parallel_development_20261023.md']


def freeze_baseline(config):
    for item in config['frozen_baseline_sources']:
        root = Path(item['root'])
        if git('rev-parse', 'HEAD', root=root) != item['head']:
            raise RuntimeError('baseline source HEAD changed')
        for relative, expected in item['sha256'].items():
            if digest(root / relative) != expected:
                raise RuntimeError('baseline source fingerprint changed: ' + relative)


def release(config, runtime):
    validate_config(config); freeze_baseline(config)
    value = {'status': STAGE + '_IDLE_RELEASE_FROZEN', 'source': source_identity(),
             'sha256': {str(path.relative_to(ROOT)): digest(path) for path in source_paths()},
             'config_sha256': digest(CONFIG), 'epoch': time.time()}
    target = Path(runtime) / 'release.json'
    if target.exists():
        old = read(target)
        if any(old[key] != value[key] for key in ('source', 'sha256', 'config_sha256')):
            raise RuntimeError('immutable resource release already exists with different source')
        return old
    atomic(target, value)
    return value


def verify_release(config, runtime):
    frozen = read(Path(runtime) / 'release.json')
    if frozen['source'] != source_identity() or frozen['config_sha256'] != digest(CONFIG):
        raise RuntimeError(STAGE + ' resource release source changed')
    for relative, expected in frozen['sha256'].items():
        if digest(ROOT / relative) != expected:
            raise RuntimeError(STAGE + ' released source file changed: ' + relative)
    freeze_baseline(config)
    return frozen


def process(pid):
    try:
        folder = Path('/proc') / str(pid)
        fields = (folder / 'stat').read_text().rsplit(')', 1)[1].split()
        return {'pid': int(pid), 'start_ticks': int(fields[19]), 'ppid': int(fields[1]),
                'pgrp': int(fields[2]), 'state': fields[0],
                'boot_id': Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
                'cgroups': (folder / 'cgroup').read_text().splitlines()}
    except (FileNotFoundError, ProcessLookupError):
        return None


def same_process(current, saved):
    return current is not None and all(current[key] == saved[key]
        for key in ('pid', 'start_ticks', 'boot_id', 'pgrp', 'cgroups'))


def same_lifetime(current, saved):
    return current is not None and all(current[key] == saved[key]
        for key in ('pid', 'start_ticks', 'boot_id', 'pgrp'))


def unit_properties(name):
    value = subprocess.check_output(['systemctl', '--user', 'show', name,
        '--property=MainPID,ControlGroup,KillMode,Restart,ActiveState,WorkingDirectory,ExecStart,MemoryMax,MemoryLimit,CPUQuotaPerSecUSec'], text=True)
    return dict(line.split('=', 1) for line in value.splitlines() if '=' in line)


def private_service_membership(identity, cgroup, unit):
    return (cgroup.endswith('/' + unit) and any(
        line.split(':', 2)[1] in {'name=systemd', ''} and line.split(':', 2)[2] == cgroup
        for line in identity['cgroups']))


def verify_own_service(config):
    value = unit_properties(config['unit'])
    if (int(value.get('MainPID', 0)) != os.getpid() or value.get('KillMode') != 'control-group'
            or value.get('Restart') != 'no' or value.get('ActiveState') != 'active'
            or value.get('WorkingDirectory') != str(ROOT) or str(ENTRY) not in value.get('ExecStart', '')
            or not value.get('ControlGroup', '').startswith('/user.slice/')):
        raise RuntimeError('dedicated own cgroup service with Restart=no and KillMode=control-group required')
    own = process(os.getpid())
    if not own or not private_service_membership(own, value['ControlGroup'], config['unit']):
        raise RuntimeError('own service cgroup membership is not proven')
    observed = []
    for name in config['observed_baseline_units']:
        other = unit_properties(name)
        if other.get('ControlGroup') == value['ControlGroup']:
            raise RuntimeError('development and baseline share a service cgroup')
        baseline = process(int(other.get('MainPID') or 0))
        if other.get('ActiveState') != 'active' or not baseline or baseline['state'] in {'Z', 'X'}:
            raise RuntimeError('observed baseline service is no longer healthy: ' + name)
        observed.append({'unit': name, 'identity': baseline})
    if os.sched_getscheduler(0) != os.SCHED_OTHER:
        raise RuntimeError('responsive supervisor must retain SCHED_OTHER policy')
    # Muscat v1 delegates only name=systemd privately. CPU is shared '/' and
    # memory belongs to user@UID.service. Never write limits to those groups.
    value['kernel_limit_capability'] = controller_capability(own, value['ControlGroup'])
    config['_observed_baseline_processes'] = observed
    config['_kernel_limit_capability'] = value['kernel_limit_capability']
    return value


def controller_capability(identity, own_cgroup):
    paths = {}
    for line in identity['cgroups']:
        _, controllers, relative = line.split(':', 2)
        if not controllers:
            paths.update(cpu=relative, memory=relative)
        else:
            for controller in controllers.split(','):
                if controller in {'cpu', 'memory'}:
                    paths[controller] = relative
    return {'hard_cgroup_limits_applied': False, 'controller_paths': paths,
            'private_controllers': {name: path == own_cgroup for name, path in paths.items()},
            'reason': 'No CPU/memory delegation on audited Muscat v1; shared controller hierarchies must remain untouched',
            'fallback': 'SCHED_IDLE plus one physical CPU per worker;24GiB owned RSS soft guard and host reserve floors'}


def process_rss(pid):
    try:
        for line in (Path('/proc') / str(pid) / 'status').read_text().splitlines():
            if line.startswith('VmRSS:'):
                return int(line.split()[1]) * 1024
        return 0  # A just-finished/zombie process has no resident address space.
    except (FileNotFoundError, ProcessLookupError):
        return 0


def owned_rss(config):
    pids = {os.getpid()}
    for job in config.get('_owned_jobs', []):
        pids.update(member['pid'] for member in group_members(job['identity']))
    pending = config.get('_pending_gate_identity')
    if pending:
        pids.update(member['pid'] for member in group_members(pending))
    return sum(process_rss(pid) for pid in pids)


def physical_cpu_check(config):
    pairs = []
    for cpu in config['allowed_cpus']:
        topology = Path('/sys/devices/system/cpu') / ('cpu' + str(cpu)) / 'topology'
        pairs.append(((topology / 'physical_package_id').read_text().strip(),
                      (topology / 'core_id').read_text().strip()))
    if len(set(pairs)) != 30 or not set(config['allowed_cpus']).issubset(os.sched_getaffinity(0)):
        raise RuntimeError('CPU IDs0–29 must be available distinct physical cores')


def available_memory():
    for line in Path('/proc/meminfo').read_text().splitlines():
        if line.startswith('MemAvailable:'):
            return int(line.split()[1]) * 1024
    raise RuntimeError('MemAvailable is not observable')


def tree_size(path):
    root = Path(path)
    return sum(p.stat().st_size for p in root.rglob('*') if p.is_file()) if root.exists() else 0


def guard(config, lease, *, check_sources=False, runtime=None, output_size=None):
    if time.time() >= lease['expires_epoch'] or time.monotonic() >= lease['expires_monotonic']:
        raise RuntimeError('two-hour development lease expired')
    if process(os.getpid())['boot_id'] != lease['boot_id']:
        raise RuntimeError('development lease boot identity changed')
    for item in config.get('_observed_baseline_processes', []):
        current = process(item['identity']['pid'])
        if not same_process(current, item['identity']) or current['state'] in {'Z', 'X'}:
            raise RuntimeError('observed baseline service identity changed: ' + item['unit'])
    if Path(config['handoff_state']).exists():
        raise RuntimeError('R146 resource handoff state observed; idle development yields')
    waiting = read(config['handoff_waiting'])
    if (waiting.get('status') != 'waiting_for_both_AT_terminal_receipts'
            or waiting.get('worker_signals') != 0):
        raise RuntimeError('R146 handoff is no longer at the approved waiting gate')
    if available_memory() < config['min_available_memory_gib'] * GIB:
        raise RuntimeError('available memory fell below the baseline reserve floor')
    rss = owned_rss(config); config['_owned_rss_bytes'] = rss
    if rss > config['own_rss_guard_gib'] * GIB:
        raise RuntimeError('owned development RSS exceeded its24GiB soft memory guard')
    if shutil.disk_usage(config['data_root']).free < config['min_free_disk_gib'] * GIB:
        raise RuntimeError('free disk fell below the baseline reserve floor')
    if check_sources:
        verify_release(config, runtime)


def cpu_times():
    result = {}
    for line in Path('/proc/stat').read_text().splitlines():
        parts = line.split()
        if parts and parts[0].startswith('cpu') and parts[0][3:].isdigit():
            values = list(map(int, parts[1:9]))
            result[int(parts[0][3:])] = (sum(values), values[3] + values[4])
    return result


def choose_cpu(config, before, after, occupied):
    def busy(cpu):
        total = after[cpu][0] - before[cpu][0]
        idle = after[cpu][1] - before[cpu][1]
        return (1 - idle / total if total > 0 else 1, cpu)
    candidates = set(config['allowed_cpus']) - set(occupied)
    if not candidates:
        raise RuntimeError('no development CPU slot available')
    return min(candidates, key=busy)


def numerical_env():
    value = os.environ.copy()
    value.update({key: '1' for key in THREADS})
    value.update({'PYTHONDONTWRITEBYTECODE': '1', 'OMP_DYNAMIC': 'FALSE', 'MKL_DYNAMIC': 'FALSE'})
    return value


def apply_idle(cpu):
    os.sched_setscheduler(0, os.SCHED_IDLE, os.sched_param(0))
    os.sched_setaffinity(0, {cpu})
    os.nice(19)


def verify_policy(pid, cpu, *, check_io=False):
    threads = list((Path('/proc') / str(pid) / 'task').iterdir())
    if not threads:
        raise RuntimeError('worker thread policy is not observable')
    for thread in threads:
        tid = int(thread.name)
        try:
            if os.sched_getscheduler(tid) != os.SCHED_IDLE or os.sched_getaffinity(tid) != {cpu}:
                raise RuntimeError('development worker escaped SCHED_IDLE or its pinned physical CPU')
        except ProcessLookupError:
            if thread.exists():
                raise
    if check_io and subprocess.check_output(['/usr/bin/ionice', '-p', str(pid)], text=True).strip() != 'idle':
        raise RuntimeError('development worker does not have idle I/O priority')


def worker_gate(args):
    """No scientific import or payload before parent proves the actual child PID."""
    if args.cpu not in range(30) or any(os.environ.get(key) != '1' for key in THREADS):
        raise RuntimeError('worker gate CPU/thread contract violated')
    subprocess.run(['/usr/bin/ionice', '-c', '3', '-p', str(os.getpid())], check=True, timeout=10)
    verify_policy(os.getpid(), args.cpu, check_io=True)
    with os.fdopen(args.ready_fd, 'w') as stream:
        stream.write(json.dumps(process(os.getpid())) + '\n'); stream.flush()
    with os.fdopen(args.permit_fd, 'rb') as stream:
        if stream.read(1) != b'G':
            return 3
    verify_policy(os.getpid(), args.cpu, check_io=True)
    if args.payload == 'probe':
        return 0
    command = [sys.executable, '-B', str(SCIENCE), args.payload, '--cpu', str(args.cpu)]
    if args.payload == 'worker':
        command += ['--name', args.name]
    os.execve(sys.executable, command, numerical_env())
    return 4


def group_members(saved):
    members = []
    for path in Path('/proc').iterdir():
        if not path.name.isdigit():
            continue
        current = process(int(path.name))
        if current and current['pgrp'] == saved['pgrp']:
            # Linux releases a zombie's cgroup memberships to controller roots
            # before its parent reaps it. It has no address space or runnable
            # work and must never receive resource/signal ownership treatment.
            if current['state'] == 'Z':
                continue
            if (current['cgroups'] != saved['cgroups'] or current['boot_id'] != saved['boot_id']
                    or current['start_ticks'] < saved['start_ticks'] or current['pid'] == os.getpid()):
                raise RuntimeError('refusing signal: worker process group ownership is not proven')
            members.append(current)
    leader = process(saved['pid'])
    if leader and not same_process(leader, saved):
        if leader['state'] != 'Z' or not same_lifetime(leader, saved):
            raise RuntimeError('refusing signal: worker PID was reused')
    return members


def stop_owned(jobs, *, grace_seconds=3):
    """Only dedicated groups launched by this supervisor; never baseline PIDs."""
    for job in jobs:
        if any(p['state'] != 'Z' for p in group_members(job['identity'])):
            with contextlib.suppress(ProcessLookupError):
                os.killpg(job['identity']['pgrp'], signal.SIGTERM)
    deadline = time.monotonic() + grace_seconds
    while time.monotonic() < deadline and any(any(p['state'] != 'Z' for p in group_members(j['identity'])) for j in jobs):
        time.sleep(0.05)
    for job in jobs:
        if any(p['state'] != 'Z' for p in group_members(job['identity'])):
            with contextlib.suppress(ProcessLookupError):
                os.killpg(job['identity']['pgrp'], signal.SIGKILL)
        job['process'].wait(timeout=5)
        job['log'].close()


def verify_job(job):
    """A process completing between poll and /proc inspection is not a violation."""
    try:
        current = process(job['identity']['pid'])
        if not same_process(current, job['identity']):
            if job['process'].poll() is not None:
                return
            raise RuntimeError('owned development worker identity changed')
        for member in group_members(job['identity']):
            if member['state'] != 'Z':
                try:
                    verify_policy(member['pid'], job['cpu'])
                except (FileNotFoundError, ProcessLookupError):
                    if process(member['pid']) is None or job['process'].poll() is not None:
                        continue
                    raise
    except (FileNotFoundError, ProcessLookupError, RuntimeError):
        if job['process'].poll() is None:
            raise


def launch(config, runtime, lease, name, cpu, *, payload='worker'):
    guard(config, lease, check_sources=True, runtime=runtime,
          output_size=tree_size(config['campaign_root']))
    ready_read, ready_write = os.pipe(); permit_read, permit_write = os.pipe()
    log = (Path(runtime) / 'logs' / (name + '.' + str(time.time_ns()) + '.log'))
    log.parent.mkdir(parents=True, exist_ok=True); stream = log.open('ab')
    command = [config['python_runtime'], '-B', str(ENTRY), 'worker-gate', '--cpu', str(cpu),
        '--ready-fd', str(ready_write), '--permit-fd', str(permit_read), '--payload', payload, '--name', name]
    child = None
    try:
        child = subprocess.Popen(command, env=numerical_env(), start_new_session=True,
            preexec_fn=lambda: apply_idle(cpu), pass_fds=(ready_write, permit_read),
            stdout=stream, stderr=subprocess.STDOUT, cwd=ROOT)
        os.close(ready_write); ready_write = None
        os.close(permit_read); permit_read = None
        deadline = time.monotonic() + 30; packet = b''
        while b'\n' not in packet:
            guard(config, lease)
            if time.monotonic() >= deadline:
                raise RuntimeError('worker policy handshake timed out before payload')
            if select.select([ready_read], [], [], config['poll_seconds'])[0]:
                block = os.read(ready_read, 4096)
                if not block:
                    raise RuntimeError('worker policy gate exited before readiness proof')
                packet += block
                if len(packet) > 8192:
                    raise RuntimeError('worker policy gate sent oversized readiness proof')
        os.close(ready_read); ready_read = None
        saved = json.loads(packet)
        if (saved['pid'] != child.pid or saved['pgrp'] != child.pid
                or not same_process(process(child.pid), saved)
                or saved['cgroups'] != process(os.getpid())['cgroups']):
            raise RuntimeError('actual worker PID/group/cgroup identity could not be proven')
        verify_policy(child.pid, cpu, check_io=True)
        config['_pending_gate_identity'] = saved
        guard(config, lease, check_sources=True, runtime=runtime,
              output_size=tree_size(config['campaign_root']))
        os.write(permit_write, b'G'); os.close(permit_write); permit_write = None
        return {'name': name, 'cpu': cpu, 'process': child, 'identity': saved,
                'log': stream, 'log_path': str(log), 'payload': payload}
    except BaseException:
        # Closing the permit makes the pre-payload gate exit without fitting.
        if permit_write is not None:
            os.close(permit_write); permit_write = None
        if child is not None:
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                current = process(child.pid)
                if current and current['pgrp'] == child.pid and current['cgroups'] == process(os.getpid())['cgroups']:
                    stop_owned([{'identity': current, 'process': child, 'log': stream}], grace_seconds=1)
        stream.close()
        raise
    finally:
        config.pop('_pending_gate_identity', None)
        for fd in (ready_read, ready_write, permit_read, permit_write):
            if fd is not None:
                os.close(fd)


def load_science():
    spec = importlib.util.spec_from_file_location('pricefm_' + STAGE.lower() + '_science_resource_api', SCIENCE)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def new_lease(config, runtime):
    path = Path(runtime) / 'lease.json'
    if path.exists():
        return read(path)  # Never renew a bounded lease on process/service restart.
    now = time.time(); monotonic = time.monotonic()
    result = {'lease_id': uuid.uuid4().hex, 'started_epoch': now, 'expires_epoch': now + 7200,
              'started_monotonic': monotonic, 'expires_monotonic': monotonic + 7200,
              'boot_id': process(os.getpid())['boot_id'],
              'initial_output_bytes': tree_size(config['campaign_root'])}
    atomic(path, result)
    return result


def run(config, runtime):
    validate_config(config); verify_release(config, runtime); verify_own_service(config); physical_cpu_check(config)
    runtime = Path(runtime); runtime.mkdir(parents=True, exist_ok=True)
    probe = read(runtime / 'policy_probe.json')
    if (probe.get('status') != STAGE + '_IDLE_POLICY_PROBE_PASSED'
            or probe.get('source') != read(runtime / 'release.json')['source']):
        raise RuntimeError('successful actual policy probe of the frozen source required before payloads')
    with (runtime / 'supervisor.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if (runtime / 'terminal.json').exists():
            return read(runtime / 'terminal.json')
        lease = new_lease(config, runtime); jobs = []; pending = None
        config['_owned_jobs'] = jobs
        module = load_science(); before = cpu_times(); last_output_check = 0; output_bytes = 0
        prepared = False
        stopping = {'signal': None}
        def requested(signum, frame):
            stopping['signal'] = signum
        previous = {sig: signal.signal(sig, requested) for sig in (signal.SIGTERM, signal.SIGINT)}
        status = STAGE + '_IDLE_LEASE_STOPPED'; reason = None
        try:
            while True:
                if stopping['signal'] is not None:
                    raise RuntimeError('own supervisor stop requested')
                if time.monotonic() - last_output_check >= 5:
                    output_bytes = tree_size(config['campaign_root']); last_output_check = time.monotonic()
                guard(config, lease, output_size=output_bytes)
                finished = [job for job in jobs if job['process'].poll() is not None]
                for job in finished:
                    if group_members(job['identity']):
                        raise RuntimeError('finished worker left live owned descendants')
                    code = job['process'].returncode; job['log'].close(); jobs.remove(job)
                    if code != 0:
                        raise RuntimeError('development worker failed: ' + job['name'] + ' exit=' + str(code))
                    if job['payload'] == 'worker' and not module.task_complete(job['name']):
                        raise RuntimeError('worker exited without a strictly verified task seal')
                    pending = None
                for job in jobs:
                    verify_job(job)
                after = cpu_times()
                if not prepared:
                    prepared = module.preparation_complete()
                if not prepared:
                    if not jobs:
                        cpu = choose_cpu(config, before, after, [])
                        jobs.append(launch(config, runtime, lease, 'preparation', cpu, payload='prepare'))
                else:
                    if pending is None:
                        pending = module.pending_task_names()
                    while pending and len(jobs) < config['max_workers']:
                        name = pending.pop(0)
                        if name in {job['name'] for job in jobs}:
                            continue
                        cpu = choose_cpu(config, before, after, [j['cpu'] for j in jobs])
                        jobs.append(launch(config, runtime, lease, name, cpu))
                    if not pending and not jobs:
                        verify_release(config, runtime)
                        if not module.preparation_complete():
                            raise RuntimeError('immutable scientific preparation missing at final closeout')
                        complete = getattr(module, 'all_tasks_complete', None)
                        if REQUIRE_ALL_TASKS_COMPLETE and not callable(complete):
                            raise RuntimeError('scientific all-task completion verifier is required')
                        if callable(complete) and not complete():
                            raise RuntimeError('ready queue empty while required scientific tasks remain incomplete')
                        status = STAGE + '_IDLE_TASKS_COMPLETE_NOT_PROMOTED'; reason = 'all allowed development task seals verified'; break
                atomic(runtime / 'progress.json', {'status': STAGE + '_IDLE_RUNNING', 'epoch': time.time(),
                    'lease': lease, 'active': [{'name': j['name'], 'cpu': j['cpu'], 'pid': j['process'].pid,
                    'policy': 'SCHED_IDLE', 'log_path': j['log_path']} for j in jobs],
                    'pending': pending, 'output_bytes': output_bytes,
                    'owned_rss_bytes': config.get('_owned_rss_bytes'),
                    'kernel_limit_capability': config.get('_kernel_limit_capability'),
                    'output_growth_bytes': output_bytes - lease['initial_output_bytes'],
                    'exclusive_cpu_ownership': False, 'baseline_worker_signals': 0})
                before = after; time.sleep(config['poll_seconds'])
        except Exception as exc:
            reason = str(exc)
        finally:
            cleanup_error = None
            try:
                stop_owned(jobs)
            except Exception as exc:
                cleanup_error = str(exc)
                status = STAGE + '_IDLE_LEASE_STOPPED'
                reason = 'own development cleanup was not proven: ' + cleanup_error
            finally:
                for sig, handler in previous.items():
                    signal.signal(sig, handler)
        closeout = None; closeout_error = None
        if prepared:
            try:
                closeout = module.write_closeout('tasks_complete' if status == STAGE + '_IDLE_TASKS_COMPLETE_NOT_PROMOTED'
                    else 'lease_end' if reason and 'lease expired' in reason else 'resource_guard_stop',
                    details={'reason': reason, 'baseline_worker_signals': 0, 'exclusive_cpu_ownership': False})
            except Exception as exc:
                closeout_error = str(exc)
                status = STAGE + '_IDLE_LEASE_STOPPED'
                reason = 'scientific closeout failed: ' + closeout_error
        terminal = {'status': status, 'reason': reason, 'epoch': time.time(), 'lease': lease,
                    'source': read(runtime / 'release.json')['source'], 'baseline_worker_signals': 0,
                    'exclusive_cpu_ownership': False, 'stopped_only_owned_development_groups': True,
                    'cleanup_verified': cleanup_error is None, 'cleanup_error': cleanup_error,
                    'scientific_closeout': closeout, 'scientific_closeout_error': closeout_error}
        terminal['kernel_limit_capability'] = config.get('_kernel_limit_capability')
        terminal['owned_rss_bytes_at_stop'] = config.get('_owned_rss_bytes')
        atomic(runtime / 'terminal.json', terminal)
        return terminal


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['release', 'status', 'run', 'probe', 'worker-gate'])
    parser.add_argument('--config', type=Path, default=CONFIG)
    parser.add_argument('--runtime', type=Path)
    parser.add_argument('--cpu', type=int); parser.add_argument('--name', default='')
    parser.add_argument('--payload', choices=['prepare', 'worker', 'probe'], default='worker')
    parser.add_argument('--ready-fd', type=int); parser.add_argument('--permit-fd', type=int)
    args = parser.parse_args()
    if args.action == 'worker-gate':
        return worker_gate(args)
    config = read(args.config); validate_config(config)
    runtime = args.runtime or Path(config['runtime'])
    if args.config.resolve() != CONFIG.resolve() or runtime.resolve() != Path(config['runtime']).resolve():
        raise RuntimeError('only the frozen ' + STAGE + ' config and separate runtime are authorized')
    if args.action == 'release':
        value = release(config, runtime)
    elif args.action == 'run':
        value = run(config, runtime)
    elif args.action == 'probe':
        verify_release(config, runtime); physical_cpu_check(config)
        lease = new_lease(config, runtime)
        guard(config, lease)
        before = cpu_times(); time.sleep(config['poll_seconds'])
        cpu = choose_cpu(config, before, cpu_times(), [])
        job = launch(config, runtime, lease, 'policy_probe', cpu, payload='probe')
        try:
            if job['process'].wait(timeout=10) != 0:
                raise RuntimeError('actual SCHED_IDLE/idle-I/O/affinity probe failed')
            value = {'status': STAGE + '_IDLE_POLICY_PROBE_PASSED', 'epoch': time.time(),
                     'pid_identity': job['identity'], 'source': read(runtime / 'release.json')['source']}
            atomic(runtime / 'policy_probe.json', value)
        finally:
            stop_owned([job])
    else:
        value = {name: read(runtime / (name + '.json')) if (runtime / (name + '.json')).exists() else None
                 for name in ('release', 'lease', 'progress', 'terminal')}
    print(json.dumps(value, sort_keys=True, indent=2))
    if args.action == 'run' and value.get('cleanup_verified') is False:
        return 1  # systemd tears down this private own cgroup; never baseline.
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
