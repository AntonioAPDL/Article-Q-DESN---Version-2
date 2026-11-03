"""Direct Slurm owner for the separately admitted new NO3 pilot.

No H wrapper surrounds the scientific owner. No runtime authority is created
here, and running this entrypoint on an administrative or login host is refused
before supplied metadata is opened. Native/build/price qualifications must have
been earned by separate explicitly funded purposes.
"""
from __future__ import annotations
import argparse
import datetime
import hashlib
import importlib.util
import os
from pathlib import Path
import resource
import stat
import time

_mp = Path(__file__).absolute().with_name('metadata.py')
_mraw = _mp.read_bytes()
if hashlib.sha256(_mraw).hexdigest() != '6593a6bbb617375029bee0c692e510cd5621662eaf9fab46445eab433ff0762b':
    raise ValueError('exact pinned metadata helper')
_ms = importlib.util.spec_from_file_location('_r200_owner_metadata', _mp)
m = importlib.util.module_from_spec(_ms)
exec(compile(_mraw, str(_mp), 'exec'), m.__dict__)

TRACE_SHA = '914d7d369d68579b7149c5130e3bba5d59f3b8f09a5bf691e1557ccbcd40c963'
NATIVE_R_SHA = '9d76330f01cace4574a9ec7a5407ca50b9faacc9813bbf4339595582e5c33c27'
_UNREAPED_LOCK_FDS = []


def _job():
    job = os.environ.get('SLURM_JOB_ID', '')
    node = os.uname().nodename.split('.')[0]
    m.require(job.isdigit() and job != '0' and os.environ.get('SLURMD_NODENAME') == node
              and node.startswith('node-') and os.environ.get('TZ') == 'UTC'
              and os.environ.get('SLURM_CPUS_PER_TASK') == '1',
              'direct current Slurm compute owner, never an admin/login payload')
    group = Path('/proc/self/cgroup').read_text()
    import re
    m.require(re.search(r'(?:^|/)job_' + re.escape(job) + r'(?:/|$)', group,
                        re.MULTILINE) is not None, 'actual current job cgroup')
    return job, node


def _load_source(pin, name):
    raw = m.source_bytes(pin)
    module_spec = importlib.util.spec_from_file_location(name, pin['path'])
    module = importlib.util.module_from_spec(module_spec)
    exec(compile(raw, pin['path'], 'exec'), module.__dict__)
    return module


def _kernel_physical(spec, price, *, initial_reservation=False):
    affinity = os.sched_getaffinity(0)
    m.require(affinity == set(spec['affinity']) and len(affinity) == 1,
              'actual single owned logical CPU')
    def cpus(text):
        result = set()
        for part in text.strip().split(','):
            if not part:
                continue
            span = part.split('-')
            if len(span) == 1:
                result.add(int(span[0]))
            else:
                m.require(len(span) == 2 and int(span[0]) <= int(span[1]), 'kernel CPU range')
                result.update(range(int(span[0]), int(span[1]) + 1))
        return result
    core = next(iter(affinity))
    siblings = cpus(Path('/sys/devices/system/cpu/cpu' + str(core) +
                         '/topology/thread_siblings_list').read_text())
    online = cpus(Path('/sys/devices/system/cpu/online').read_text())
    entries = Path('/proc/self/cgroup').read_text().splitlines()
    v2 = [x[3:] for x in entries if x.startswith('0::')]
    m.require(len(v2) == 1 and '..' not in Path(v2[0]).parts, 'qualified unified cgroup path')
    folder = Path('/sys/fs/cgroup') / v2[0].lstrip('/')
    effective = cpus((folder / 'cpuset.cpus.effective').read_text())
    m.require((siblings & online).issubset(effective), 'all online SMT siblings belong to job')
    limits = []
    current = folder
    while current != Path('/sys/fs/cgroup'):
        memory = current / 'memory.max'
        if memory.exists():
            value = memory.read_text().strip()
            if value != 'max':
                limits.append(int(value))
        current = current.parent
    m.require(limits and 0 < min(limits) <= price['memory_MiB'] * 1024**2,
              'actual aggregate cgroup memory within independently priced profile')
    root = m.physical(spec['root'])
    fs = os.statvfs(root)
    available = fs.f_bavail * fs.f_frsize
    needed = price['mandatory_headroom_bytes'] + (price['reserved_filesystem_bytes']
                                                  if initial_reservation else 0)
    m.require(available >= needed,
              'current disk supports physical reservation and mandatory headroom')
    return {'job_id': spec['job_id'], 'node': spec['node'], 'affinity': sorted(affinity),
            'online_thread_siblings': sorted(siblings & online),
            'effective_job_cpus': sorted(effective), 'cgroup_memory_limit_bytes': min(limits),
            'filesystem_available_bytes': available, 'observed_epoch': time.time()}


def validate(spec_pin, authority_pin, source_review_pin):
    job, node = _job()
    review = m.linked(source_review_pin)
    bp = review.get('source_pins', {}).get('owner/compute_boundary.py')
    m.require(bp is not None and bp['path'] ==
              str(Path(__file__).absolute().with_name('compute_boundary.py')),
              'actual fixed sibling boundary belongs to current installed source review')
    boundary = _load_source(bp, '_r200_owner_actual_boundary')
    spec = m.linked(spec_pin)
    m.closed(spec, boundary.SPEC_KEYS | {'io_request'}, 'exact pilot owner spec')
    m.require(spec['schema'] == 'r200_owned_compute_spec_v1'
              and spec['role'] == 'NO3_AL300_PILOT'
              and (spec['job_id'], spec['node'], spec['uid']) == (job, node, os.getuid())
              and spec['role_request'] == spec['io_request']
              and spec['case_sha256'] == m.digest(spec['case']), 'exact actual pilot purpose')
    parent = boundary._proc(os.getpid())
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    m.require(spec['owner'] == {'pid': os.getpid(), 'start_ticks': parent['start_ticks'],
                               'boot_id': boot} and parent['TracerPid'] == 0,
              'same READY worker owns scientific trace, outside administrative H')
    spec = dict(spec, _spec_pin=spec_pin)
    authority = m.linked(authority_pin)
    m.closed(authority, boundary.AUTHORITY_KEYS, 'separate Root runtime authority')
    boundary._same(authority, spec)
    m.require(authority['schema'] == 'r200_compute_authority_v1'
              and authority['status'] == 'ROOT_ADMITTED_NEW_R200_COMPUTE_PURPOSE'
              and authority['spec'] == spec_pin and authority['source_review'] == source_review_pin
              and type(authority['maximum_calls']) is int and authority['maximum_calls'] == 1
              and type(authority['optimizer_invocations']) is int
              and authority['optimizer_invocations'] == 1,
              'one new pilot attempt, never a metadata/source grant')
    for key in ('case_sha256', 'source_map_sha256', 'source_publication',
                'runtime_qualification', 'price', 'scope', 'ledger'):
        m.require(authority[key] == spec[key], 'same current authority ' + key)
    actual_review = boundary._validate_sources(spec, source_review_pin)
    qualification = boundary._qualification(spec['runtime_qualification'], spec)
    qualified_result = m.linked(qualification['result'])
    price = boundary._price_and_funding(spec)
    boundary._pilot_science(spec)
    provenance = boundary._input_provenance(spec, actual_review)
    owner_review = m.linked(authority['owner_review'])
    m.require(owner_review.get('status') == 'PASS_REVIEWED_R200_OWNER_RELEASE'
              and owner_review.get('spec') == spec_pin
              and owner_review.get('source_review') == source_review_pin
              and owner_review.get('source_map_sha256') == spec['source_map_sha256'],
              'actual separately authored second peer phase')
    ready = m.linked(owner_review['owner_ready'])
    m.require(ready.get('status') == 'READY_R200_OWNED_AWAIT_ROOT_RELEASE_NO_PAYLOAD'
              and ready.get('owner') == spec['owner']
              and ready.get('job_id') == job and ready.get('node') == node
              and ready.get('resource_lock_fd') == spec['resource_lock_fd']
              and ready.get('resource_lock_path') == spec['resource_lock_path'],
              'actual matching READY worker and inherited resource lock')
    now = time.time()
    m.require(type(ready.get('created_epoch')) in (int, float)
              and 0 <= now - ready['created_epoch'] < 120
              and spec['issued_epoch'] <= authority['issued_epoch'] <= now
              and now + price['whole_wall_seconds'] < authority['expires_epoch']
              <= spec['expires_epoch'], 'unchanged 120-second READY and complete remaining schedule')
    runtime_owner = {'job_id': job, 'node': node, 'uid': os.getuid(),
                     'parent_pid': os.getpid(), 'parent_birth_ticks': parent['start_ticks'],
                     'resource_lock_fd': spec['resource_lock_fd'], 'expires_epoch': spec['expires_epoch']}
    m.require(spec['runtime_owner'] == runtime_owner, 'same current R/native owner contract')
    fd = spec['resource_lock_fd']
    held = os.fstat(fd)
    lock = m.physical(spec['resource_lock_path']).stat()
    m.require(stat.S_ISREG(held.st_mode) and held.st_uid == os.getuid()
              and (held.st_dev, held.st_ino) == (lock.st_dev, lock.st_ino),
              'already held same-inode one-attempt resource lock')
    # Read only this owner's exact FD info, not a global lock/process census.
    m.require('FLOCK' in Path('/proc/self/fdinfo/' + str(fd)).read_text()
              and 'WRITE' in Path('/proc/self/fdinfo/' + str(fd)).read_text(),
              'actual existing exclusive owner FLOCK')
    launch = m.linked(spec['owner_launch'])
    keys = {'schema', 'purpose', 'nonce', 'role', 'job_id', 'node', 'bootstrap',
            'native_executable', 'traced_guard', 'baseline_files', 'environment',
            'bootstrap_exec_allowlist', 'stdout_path', 'stderr_path', 'owned_tree_path',
            'owned_guard_path', 'output_root'}
    m.closed(launch, keys, 'closed qualified launch')
    boundary._same(launch, spec)
    m.require(launch['schema'] == 'r200_owned_pilot_launch_v1'
              and launch['traced_guard']['sha256'] == TRACE_SHA
              and launch['native_executable']['sha256'] == NATIVE_R_SHA,
              'unchanged original tracer and native R identity')
    m.require(launch['bootstrap'] == actual_review['source_pins']['pilot_io/pilot_bootstrap.R'],
              'exact new reviewed bootstrap, separate from old role table')
    for pin in launch['baseline_files']:
        m.descriptor(pin)
        # Opaque code/native verification is compute-owned; target data is not read.
        m.read_regular(pin['path'], limit=64 * 1024**2, expected_sha=pin['sha256'],
                       expected_uid=os.getuid())
    m.require(launch['native_executable'] in launch['baseline_files']
              and launch['traced_guard'] in launch['baseline_files'],
              'complete qualified original native dependency closure')
    startup_python = qualified_result.get('startup_python')
    m.descriptor(startup_python)
    m.require(startup_python in launch['baseline_files']
              and startup_python['path'] == str(Path('/proc/self/exe').resolve(strict=True)),
              'actual startup Python ELF is in the immutable qualified runtime backing')
    for key in ('stdout_path', 'stderr_path', 'owned_tree_path', 'owned_guard_path', 'output_root'):
        path = m.absolute(launch[key])
        m.require(path.is_relative_to(m.absolute(spec['root'])) and not path.exists(),
                  'new private launch output ' + key)
    io = m.linked(spec['io_request'])
    m.require(io.get('case') == spec['case'] and io.get('purpose') == spec['purpose']
              and io.get('nonce') == spec['nonce']
              and io.get('output_root') == launch['output_root'],
              'same exact source-reviewed I/O and output namespace')
    slots = io.get('storage', {}).get('slots')
    m.require(type(slots) is list and len(slots) == 608
              and all(type(x.get('max_bytes')) is int and 0 < x['max_bytes'] <= 16 * 1024**2
                      for x in slots)
              and sum(x['max_bytes'] for x in slots) <= price['reserved_filesystem_bytes']
              and io['storage'].get('headroom_bytes') == price['mandatory_headroom_bytes'],
              'actual complete I/O slot allocation equals measured storage profile')
    m.require(all(launch['environment'].get(k) == '1' for k in boundary.THREAD_KEYS)
              and launch['environment'].get('SLURM_JOB_ID') == job
              and launch['environment'].get('SLURMD_NODENAME') == node
              and launch['environment'].get('TZ') == 'UTC',
              'one-thread current child environment')
    m.require(launch['environment'].get('R154_PROJECT_ROOT_ADMITTED') == '1'
              and launch['environment'].get('R154_PROJECT_MODE') == 'pilot'
              and 'LD_PRELOAD' not in launch['environment']
              and 'PYTHONPATH' not in launch['environment'],
              'unchanged consumer compatibility markers, never admission proof')
    _readonly_execution_sources(spec, launch, io)
    physical = _kernel_physical(spec, price, initial_reservation=True)
    return spec, authority, actual_review, price, launch, boundary, physical


def _readonly_execution_sources(spec, launch, io):
    # R source()/parse()/dyn.load() reopen paths. Exact byte checks alone are
    # insufficient: actual installed code/runtime needs an immutable read-only
    # mount in this qualified owner namespace before the child is launched.
    mounts = []
    for line in Path('/proc/self/mountinfo').read_text().splitlines():
        parts = line.split()
        if len(parts) > 6:
            point = parts[4].replace('\\040', ' ').replace('\\134', '\\')
            separator = parts.index('-')
            super_options = set(parts[separator + 3].split(','))
            mounts.append((Path(point), set(parts[5].split(',')), super_options))
    paths = [x['path'] for x in spec['source_pins'].values()]
    paths += [x['path'] for x in spec['scientific_sources'].values()]
    paths += [x['path'] for x in launch['baseline_files']]
    paths += [io['io_library']['path'], io['native_boundary']['path'],
              io['scientific_context']['library']]
    for text in paths:
        path = m.physical(text)
        covering = [(point, options, super_options) for point, options, super_options in mounts
                    if path == point or path.is_relative_to(point)]
        m.require(covering, 'actual installed source/runtime mount')
        point, options, super_options = max(covering, key=lambda x: len(x[0].parts))
        m.require('ro' in options and 'ro' in super_options,
                  'qualified immutable read-only backing filesystem, not a read-only bind over a writable alias')


def _parent_gate(spec_pin, authority_pin, review_pin, spec, review, raw, phase, state):
    m.require(phase == 'SCIENTIFIC_FORK_DENIED' and state.get('state') == 'LIVE'
              and state.get('kernel_trace_owned') is True
              and state.get('scientific_filter_accepted') is True,
              'actual original tracer pre-ACK capture transition')
    m.require(len(raw) <= 1024**2, 'bounded parse-only stdout')
    frames = [m.strict_json(line) for line in raw.splitlines()
              if line.lstrip().startswith(b'{')]
    m.require(len(frames) == 1, 'one exact parse frame before ACK')
    frame = m.closed(frames[0], {
        'status', 'purpose', 'nonce', 'role', 'job_id', 'node', 'source_pins',
        'optimizer_invocations', 'scientific_target_data_read'}, 'parse frame')
    m.require(frame['status'] == 'R200_PINNED_SOURCE_PARSE_PASS_BEFORE_ENTRYPOINT'
              and frame['source_pins'] == review['source_pins']
              and frame['optimizer_invocations'] == 0
              and type(frame['optimizer_invocations']) is int
              and frame['scientific_target_data_read'] is False,
              'all pinned source parsed with zero optimizer/target access')
    for key in ('purpose', 'nonce', 'role', 'job_id', 'node'):
        m.require(frame[key] == spec[key], 'current exact parsed ' + key)
    roots = [x for x in state.get('live_lifetimes', [])
             if x.get('ppid') == os.getpid() and x.get('TracerPid') == os.getpid()]
    m.require(len(roots) == 1, 'one actual directly traced scientific child')
    child = roots[0]
    record = dict(schema='r200_parent_parse_gate_v1',
                  status='OWNER_VALIDATED_EXACT_PARSE_BEFORE_KERNEL_ACK',
                  spec=spec_pin, authority=authority_pin, source_review=review_pin,
                  purpose=spec['purpose'], nonce=spec['nonce'], role=spec['role'],
                  job_id=spec['job_id'], node=spec['node'], uid=spec['uid'],
                  owner=spec['owner'], child={'pid': child['pid'], 'start_ticks': child['start_ticks']},
                  source_pins=review['source_pins'], frame=frame, created_epoch=time.time(),
                  kernel_ACK_requires_real_boundary_call=True)
    return m.write_new(spec['acknowledgement_path'], record)


def run(spec_pin, authority_pin, source_review_pin):
    spec, authority, review, price, launch, boundary, initial_physical = validate(
        spec_pin, authority_pin, source_review_pin)
    # Spend the attempt before any target interpretation or scientific child.
    claim = dict(schema='r200_compute_attempt_claim_v1',
                 status='SPENT_CURRENT_OWNER_ATTEMPT_NO_RETRY',
                 spec=spec_pin, authority=authority_pin, owner=spec['owner'],
                 purpose=spec['purpose'], nonce=spec['nonce'], role=spec['role'],
                 job_id=spec['job_id'], node=spec['node'], created_epoch=time.time())
    m.require(m.absolute(spec['attempt_claim_path']).is_relative_to(m.absolute(spec['root'])),
              'fixed purpose attempt path')
    claim_pin = m.write_new(spec['attempt_claim_path'], claim)
    trace = _load_source(launch['traced_guard'], '_r200_unchanged_native_tracer')
    # r157 exposes its complete internally defined callback protocol; callbacks
    # below are trusted fixed source, not supplied by a request or caller.
    fd = spec['resource_lock_fd']
    output = m.physical(launch['output_root'])
    output.mkdir(mode=0o700)
    gate_pin = None
    safe = False
    started = time.monotonic()
    def peer(owned):
        _job()
        current = _kernel_physical(spec, price)
        m.require(current['online_thread_siblings'] == initial_physical['online_thread_siblings']
                  and current['effective_job_cpus'] == initial_physical['effective_job_cpus'],
                  'current physical/SMT ownership preserved')
        for prior in owned:
            actual = trace.identity(prior['pid'])
            m.require(trace.same_lifetime(actual, prior)
                      and actual['TracerPid'] == os.getpid()
                      and actual['affinity'] == spec['affinity'],
                      'actual same-lifetime current ptrace ownership')
        return {'job_id': spec['job_id'], 'owned_lifetimes': len(owned)}
    def limits():
        resource.setrlimit(resource.RLIMIT_CPU,
                           (price['child_CPU_seconds'], price['child_CPU_seconds']))
        resource.setrlimit(resource.RLIMIT_FSIZE, (16 * 1024**2, 16 * 1024**2))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    command = [launch['native_executable']['path'], '--no-echo', '--no-restore',
               '--no-save', '--no-environ', '--no-site-file', '--no-init-file',
               '--file=' + launch['bootstrap']['path'], '--args',
               spec_pin['path'], spec_pin['sha256'], authority_pin['path'],
               authority_pin['sha256'], source_review_pin['path'], source_review_pin['sha256']]
    env = dict(launch['environment'], R154_GLOBAL_PERMIT_LOCK_FD=str(fd))
    try:
        for path, digest in launch['bootstrap_exec_allowlist'].items():
            m.read_regular(path, limit=64 * 1024**2, expected_sha=digest,
                           expected_uid=os.getuid())
        with Path(launch['stdout_path']).open('xb') as stdout, Path(launch['stderr_path']).open('xb') as stderr:
            def capture(lock_fd, phase, state):
                nonlocal gate_pin
                if phase == 'SCIENTIFIC_FORK_DENIED' and state.get('state') == 'LIVE' and gate_pin is None:
                    m.require(lock_fd == fd, 'same original owner permit')
                    gate_pin = _parent_gate(spec_pin, authority_pin, source_review_pin,
                                            spec, review, Path(launch['stdout_path']).read_bytes(),
                                            phase, state)
            receipt = trace.run_traced(
                command, env=env, stdout=stdout, stderr=stderr, lock_fd=fd,
                affinity=spec['affinity'], wall_seconds=price['owner_wall_seconds'],
                maximum_combined_CPU_seconds=price['owner_CPU_seconds'],
                absolute_deadline_UTC=datetime.datetime.fromtimestamp(
                    authority['expires_epoch'], datetime.timezone.utc).isoformat(),
                peer_callback=peer, bootstrap_exec_allowlist=launch['bootstrap_exec_allowlist'],
                owner_path=launch['owned_tree_path'], scope=spec['purpose'],
                source={'kind': 'SEPARATE_R200_PILOT_OWNER_UNCHANGED_R157_TRACER',
                        'source_map_sha256': spec['source_map_sha256']},
                authority_pin=authority_pin, preexec_fn=limits,
                require_science_handshake=True, owner_capture_callback=capture)
        safe = (receipt.get('reaped') is True and receipt.get('drained') is True
                and receipt.get('remaining_owned_lifetimes') == [])
        guard_pin = m.write_new(launch['owned_guard_path'], receipt)
        flags = ('reaped', 'drained', 'CPU_accounting_complete',
                 'all_newborns_kernel_traced_before_execution',
                 'tracer_death_kernel_EXITKILL_enabled',
                 'postbootstrap_TSYNC_scientific_fork_denial',
                 'scientific_target_access_handshake')
        attestation = receipt.get('scientific_filter_kernel_attestation') or {}
        m.require(receipt.get('schema') == 'r157_traced_bootstrap_guard_receipt_v1'
                  and receipt.get('status') == 'EXITED'
                  and receipt.get('returncode') == 0
                  and all(receipt.get(k) is True for k in flags)
                  and receipt.get('remaining_owned_lifetimes') == []
                  and receipt.get('unexpected_untraced_child_waits') == []
                  and attestation.get('operation') == 'SECCOMP_SET_MODE_FILTER'
                  and attestation.get('flags') == 'TSYNC'
                  and attestation.get('kernel_return') == 0 and gate_pin is not None,
                  'complete actual native kernel ACK/reap/drain proof')
        m.require(time.monotonic() - started < price['owner_wall_seconds']
                  and time.time() < authority['expires_epoch'], 'complete fixed owned interval')
        result = dict(status='R200_PILOT_RETURN_CANDIDATE_AWAIT_COMPLETE_INDEPENDENT_ACCEPTANCE',
                      purpose=spec['purpose'], nonce=spec['nonce'], role=spec['role'],
                      job_id=spec['job_id'], node=spec['node'], spec=spec_pin,
                      authority=authority_pin, source_review=source_review_pin,
                      attempt_claim=claim_pin, owned_guard=guard_pin, parent_parse_gate=gate_pin,
                      source_map_sha256=spec['source_map_sha256'], production_acceptance=False,
                      automatic_dependent_release=False,
                      full_inventory_accounting_independent_review_still_required=True)
        m.write_new(Path(spec['root']) / 'OWNER_CANDIDATE.json', result)
        return result
    except BaseException as error:
        failure = Path(spec['root']) / 'OWNER_FAILED_SPENT.json'
        if not failure.exists():
            m.write_new(failure, {'status': 'FAILED_R200_PILOT_ATTEMPT_FEES_RETAINED',
                                 'purpose': spec['purpose'], 'nonce': spec['nonce'],
                                 'role': spec['role'], 'automatic_retry': False,
                                 'attempt_claim': claim_pin,
                                 'error': type(error).__name__ + ': ' + str(error)})
        raise
    finally:
        if not safe:
            _UNREAPED_LOCK_FDS.append(fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('spec', 'authority', 'source-review'):
        parser.add_argument('--' + key, required=True)
        parser.add_argument('--' + key + '-sha256', required=True)
    args = parser.parse_args()
    def pin(name):
        return {'path': getattr(args, name), 'sha256': getattr(args, name + '_sha256')}
    return run(pin('spec'), pin('authority'), pin('source_review'))


if __name__ == '__main__':
    main()

