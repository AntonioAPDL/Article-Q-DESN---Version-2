"""Durable, separately funded single-job PROFILE lifecycle; no automatic follow-on.

The controller owns new Muscat claims. A held job first admits only bounded
startup/READY; numerical authority is published after actual READY inspection.
All imports are standard-library until compute_session verifies its new grant.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import resource
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time

from . import execution_profile as e, profile_admission as a
from . import control as ctl, registry as r
from .environment import require_compute, THREAD_ENV, REFERENCE_NUMERICAL_ENV

SCHEMA = 'r164_profile_controller_spec_v1'
CENTRAL = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/hb_control_registry/profile_r164')
FINAL = {'ACCEPTED', 'FAILED_RECONCILED'}
PHASE_LIMITS = {
    'QUALIFICATION_PAIR': dict(aggregate_cpu_seconds=600, wall_seconds=1200,
        wrapper_cpu_seconds=100, ready_reserve_seconds=270, exit_reserve_seconds=30),
    'MEASUREMENT_PAIR': dict(aggregate_cpu_seconds=1700, wall_seconds=4200,
        wrapper_cpu_seconds=200, ready_reserve_seconds=570, exit_reserve_seconds=30),
}
SPEC_FIELDS = {'schema', 'scope_id', 'phase', 'created_epoch', 'expires_epoch', 'controller_expires_epoch', 'request',
    'remote_root', 'output_root', 'runtime_python', 'environment_bundle', 'node',
    'worker_limits', 'allocation_limits', 'worker_sources', 'controller_sources', 'files',
    'funding_reservation', 'prelaunch_review', 'feature_publication', 'qualification',
    'site', 'controller_limits', 'environment_provenance'}
ACCEPTED_RUNTIME_EVIDENCE = {
    'reference_release': 'c92193d8a4c21a3be5857de249bc57e9c03c3b3f13f99b604e087d1309b17910',
    'environment_completed': '7f63892e4355898b723df9a94a7c1244d1a166eeb028fd6f3b75320dd45609ad',
    'reference_completed': 'b5377b829eff20415cb517e1360fcb9b4172c78b87156c1bbf1362b0d61ed497',
    'reference_runtime': '957f37d2b2ab9135d4ec7012ebe34ffe4b61d1ee468106d25babc068b32050c7',
}
READY_WAITER = r'''import json,os,pathlib,resource,signal,stat,sys,time
root,scope,job,request,wait=sys.argv[1:];wait=int(wait)
assert 0<wait<=100
resource.setrlimit(resource.RLIMIT_CPU,(5,5));resource.setrlimit(resource.RLIMIT_CORE,(0,0))
signal.alarm(wait+1)
path=pathlib.Path(root)/'ready.json';deadline=time.monotonic()+wait
while not path.exists():
    if time.monotonic()>=deadline:raise TimeoutError('finite exact-job READY notification deadline')
    time.sleep(min(1,deadline-time.monotonic()))
assert not any(p.is_symlink() for p in (path,*path.parents))
fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
with os.fdopen(fd,'rb') as f:
    before=os.fstat(f.fileno());assert stat.S_ISREG(before.st_mode) and before.st_uid==os.getuid() and before.st_size<=16777216
    raw=f.read(16777217);after=os.fstat(f.fileno())
fp=lambda s:(s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
assert len(raw)==before.st_size and fp(before)==fp(after)==fp(path.stat())
x=json.loads(raw);assert x['status']=='COMPUTE_READY' and x['scope_id']==scope and x['allocation']['job_id']==job and x['request_sha256']==request
sys.stdout.buffer.write(raw)
'''
SBATCH_ENV_WRAPPER = "import os,sys; env={k:v for k,v in os.environ.items() if not k.startswith('SBATCH_')}; os.execvpe(sys.argv[1],sys.argv[1:],env)"
VERIFY_REMOTE_RELEASE = r'''import hashlib,json,os,pathlib,resource,signal,stat,sys
resource.setrlimit(resource.RLIMIT_CPU,(5,5));resource.setrlimit(resource.RLIMIT_CORE,(0,0));signal.alarm(100)
root=pathlib.Path(sys.argv[1]);expected=sys.argv[2]
def raw(path):
    assert not any(p.is_symlink() for p in (path,*path.parents))
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    with os.fdopen(fd,'rb') as f:
        before=os.fstat(f.fileno());assert stat.S_ISREG(before.st_mode) and before.st_uid==os.getuid() and before.st_size<=16777216
        data=f.read(16777217);after=os.fstat(f.fileno())
    fp=lambda s:(s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
    assert len(data)==before.st_size and fp(before)==fp(after)==fp(path.stat())
    return data
data=raw(root/'release_manifest.json');assert hashlib.sha256(data).hexdigest()==expected
m=json.loads(data);assert len(m['files'])<=258
assert sum(v['bytes'] for v in m['files'].values())<=67108864
for name,value in m['files'].items():
    p=pathlib.Path(name);assert not p.is_absolute() and '..' not in p.parts
    data=raw(root/p);assert len(data)==value['bytes'] and hashlib.sha256(data).hexdigest()==value['sha256']
print('VERIFIED '+expected)
'''


def require(value, message):
    if not value:
        raise ValueError(message)


def owner():
    require(socket.getfqdn() == a.OWNER, 'canonical Muscat controller required')
    require(os.sched_getaffinity(0) == {31} and sys.dont_write_bytecode,
            'administrative CPU31/-B controller required')


def pin(path):
    path = e.planning.physical(path)
    return dict(path=str(path), sha256=r.digest(path))


def read(value):
    return e.read_pin(value)


def safe_relative(value):
    require(type(value) is str and re.fullmatch(r'[A-Za-z0-9_./-]+', value) and not Path(value).is_absolute()
            and '..' not in Path(value).parts and not ({'.git', '.ssh', '.codex'} & set(Path(value).parts)),
            'safe credential-free release-relative path required')
    return Path(value)


def controller_sources():
    return dict(e.source_closure(), **{name: r.digest(Path(__file__).with_name(name))
                for name in ('profile_control.py', 'resource_qualification.py', 'profile_supervisor.py', 'profile_stream.py')})


def supervisor_source():
    return e.bounded_read(Path(__file__).with_name('profile_supervisor.py')).decode()


def remote_command(args, cpu, wall, cap):
    return ['/usr/bin/python3', '-I', '-B', '-c', supervisor_source(), '--cpu', str(cpu), '--wall', str(wall),
            '--output-cap', str(cap), '--passthrough', '--', *args]


def spec_read(spec, value, remote=False):
    """Remote metadata pins retain their hashes; local staging uses exact copies."""
    if remote:
        return read(value)
    path = Path(value['path']); root = Path(spec['remote_root'])
    if path.is_relative_to(root):
        name = str(path.relative_to(root))
        matches = [item for item in spec['files'] if item['relative'] == name]
        require(len(matches) == 1 and matches[0]['sha256'] == value['sha256'], 'complete local copy of remote pin required')
        saved = CENTRAL / spec['scope_id'] / 'release' / name
        path = str(saved) if saved.is_file() else matches[0]['local']
        return read(dict(path=path, sha256=value['sha256']))
    # A later phase retains the original policy bytes and first-release pins.
    # Only an accepted canonical earlier qualification may supply that metadata.
    roots = sorted(CENTRAL.glob('r164-profile-*')) if CENTRAL.exists() else []
    require(len(roots) <= 64, 'bounded canonical prior-claim metadata search required')
    for previous_root in roots:
        if previous_root.name == spec['scope_id']: continue
        records = historical_records(previous_root)
        if not records or records[-1]['state'] != 'ACCEPTED': continue
        previous = read(records[0]['spec'])
        require(previous['scope_id'] == previous_root.name, 'canonical prior namespace changed')
        if not path.is_relative_to(Path(previous['remote_root'])): continue
        accepted = read(records[-1]['acceptance'])
        require(accepted.get('status') == 'ACCEPTED_COMPLETE_PAIRED_COMPONENT_QUALIFICATION'
                and accepted.get('scope_id') == previous_root.name
                and accepted.get('source_files') == spec['worker_sources'],
                'prior metadata dependency requires exact accepted qualification')
        prepared = [item for item in records if item['state'] == 'PREPARED']
        require(len(prepared) == 1 and prepared[0]['release_manifest']['path'] == str(previous_root / 'release/release_manifest.json'),
                'canonical previous release-manifest proof required')
        manifest = read(prepared[0]['release_manifest']); name = str(path.relative_to(previous['remote_root']))
        require(manifest['files'].get(name, {}).get('sha256') == value['sha256'], 'prior immutable metadata pin differs')
        return read(dict(path=str(previous_root / 'release' / safe_relative(name)), sha256=value['sha256']))
    return read(value)


def runtime_provenance(spec, remote=False):
    refs = spec['environment_provenance']
    require(type(refs) is dict and set(refs) == set(ACCEPTED_RUNTIME_EVIDENCE),
            'complete original accepted runtime provenance required')
    values = {}
    for name, digest in ACCEPTED_RUNTIME_EVIDENCE.items():
        require(refs[name]['sha256'] == digest, 'accepted immutable runtime evidence changed: ' + name)
        values[name] = spec_read(spec, refs[name], remote)
    release = values['reference_release']; env = values['environment_completed']; ref = values['reference_completed']
    require(release['runtime_python'] == spec['runtime_python'] and release['environment_bundle'] == spec['environment_bundle']
            and env.get('application_passed') is True and ref.get('application_passed') is True
            and ref.get('release_sha256') == refs['reference_release']['sha256']
            and ref['files'].get('environment-runtime.json') == refs['reference_runtime']['sha256']
            and values['reference_runtime'].get('status') == 'verified',
            'runtime interpreter/bundle must derive from actual accepted environment and reference publication')
    return values['reference_runtime']


def spec_contract(spec):
    """Bind every field except the review's own pointer/manifest member."""
    review = Path(spec['prelaunch_review']['path'])
    require(review.is_relative_to(Path(spec['remote_root'])), 'prelaunch review is inside reviewed release')
    relative = str(review.relative_to(spec['remote_root']))
    value = {k: v for k, v in spec.items() if k != 'prelaunch_review'}
    value['files'] = [item for item in spec['files'] if item['relative'] != relative]
    return a.identity(value)


def validate_spec(spec, *, now=None, remote=False, admit_new_work=True):
    now = time.time() if now is None else now
    require(type(spec) is dict and set(spec) == SPEC_FIELDS and spec['schema'] == SCHEMA,
            'exact new profile lifecycle specification required')
    require(re.fullmatch(r'r164-profile-[a-z0-9]{16,64}', spec['scope_id'])
            and spec['phase'] in PHASE_LIMITS, 'distinct supported new profiling scope required')
    require(a.number(spec['created_epoch']) and a.number(spec['expires_epoch'])
            and spec['created_epoch'] <= now and spec['created_epoch'] < spec['expires_epoch']
            and spec['expires_epoch'] - spec['created_epoch'] <= 86400,
            'new finite lifecycle window required')
    require(a.number(spec['controller_expires_epoch']) and now < spec['controller_expires_epoch']
            and spec['expires_epoch'] <= spec['controller_expires_epoch'] <= spec['expires_epoch'] + 1800,
            'separately declared finite controller/accounting tail is expired or invalid')
    limits = a.validate_limits(spec['worker_limits'])
    whole = spec['allocation_limits']; expected = dict(PHASE_LIMITS[spec['phase']], memory_MiB=limits['memory_MiB'])
    require(whole == expected and type(whole['aggregate_cpu_seconds']) is int,
            'exact prospectively funded whole-job envelope required')
    want = (500, 900) if spec['phase'] == 'QUALIFICATION_PAIR' else (1500, 3600)
    require((limits['aggregate_cpu_seconds'], limits['wall_seconds']) == want,
            'exact declared complete paired worker allowance required')
    if admit_new_work:
        require(now + whole['wall_seconds'] <= spec['expires_epoch'], 'whole job does not fit new finite window')
    require(re.fullmatch(r'/(?:home|mnt/beegfs/home)/jaguir26/[A-Za-z0-9_/-]+', spec['remote_root'])
            and '..' not in Path(spec['remote_root']).parts
            and Path(spec['remote_root']).name == spec['scope_id'], 'owned new remote release namespace required')
    require(spec['output_root'] == spec['remote_root'] + '/outputs/ACTUAL_COMPONENT_PROFILE/' + spec['scope_id'],
            'exact separate component output namespace required')
    require(type(spec['node']) is str and re.fullmatch(r'node-[0-9]+', spec['node']), 'reviewed single compute node required')
    for key in ('runtime_python', 'environment_bundle'):
        require(Path(spec[key]).is_absolute() and '..' not in Path(spec[key]).parts, 'absolute reviewed runtime required')
    runtime_provenance(spec, remote)
    require(spec['worker_sources'] == e.source_closure()
            and spec['controller_sources'] == controller_sources(), 'immutable worker/controller source closure changed')
    require(type(spec['files']) is list and spec['files'] and len(spec['files']) <= 256, 'bounded explicit stage allowlist required')
    names = []
    for item in spec['files']:
        require(type(item) is dict and set(item) == {'local', 'relative', 'sha256', 'bytes'}, 'exact staged file pin required')
        names.append(str(safe_relative(item['relative'])))
        require(type(item['bytes']) is int and 0 <= item['bytes'] <= e.MAX_METADATA
                and re.fullmatch('[a-f0-9]{64}', item['sha256']), 'bounded source/JSON metadata stage required')
        require(Path(item['relative']).suffix in ('.py', '.json'), 'only source/metadata staged; no new numerical payload copies')
    require(len(names) == len(set(names)), 'duplicate staged path prohibited')
    require(sum(item['bytes'] for item in spec['files']) <= 60 * 1024**2,
            'metadata/source stage must fit bounded64MiB release-verification envelope')
    required = {'code/pricefm_hb/' + name for name in spec['controller_sources']}
    require(required <= set(names), 'complete worker/launcher source stage required')
    for item in spec['files']:
        if Path(item['relative']).suffix == '.py':
            name = Path(item['relative']).name
            require(item['relative'] == 'code/pricefm_hb/' + name and name in spec['controller_sources']
                    and item['sha256'] == spec['controller_sources'][name],
                    'staged source not in reviewed closure')
    controls = spec['controller_limits']
    require(type(controls) is dict and set(controls) == {'max_operations', 'operation_wall_seconds',
        'operation_CPU_seconds', 'max_output_bytes', 'transport_CPU_seconds', 'transport_wall_seconds', 'max_transfer_bytes',
        'aggregate_reserved_CPU_seconds', 'aggregate_reserved_wall_seconds', 'proof_CPU_seconds', 'proof_wall_seconds',
        'validation_CPU_seconds', 'validation_wall_seconds', 'local_administrative_CPU_reserve_seconds', 'max_status_polls'}
        | {'ready_CPU_seconds', 'ready_wall_seconds', 'ready_wait_seconds'}
        and all(type(v) is int and v > 0 for v in controls.values())
        and controls['max_operations'] <= 32 and controls['operation_wall_seconds'] <= 180
        and controls['operation_CPU_seconds'] <= 5 and controls['operation_wall_seconds'] <= 20
        and controls['proof_CPU_seconds'] <= 5 and controls['proof_wall_seconds'] <= 30
        and controls['max_output_bytes'] <= e.MAX_METADATA
        and controls['transport_CPU_seconds'] <= 40 and controls['transport_wall_seconds'] <= 120
        and controls['validation_CPU_seconds'] <= 40 and controls['validation_wall_seconds'] <= 180
        and controls['local_administrative_CPU_reserve_seconds'] <= 10
        and controls['ready_CPU_seconds'] <= 5 and controls['ready_wall_seconds'] <= 120
        and controls['ready_wait_seconds'] <= 100 and controls['ready_wall_seconds'] >= controls['ready_wait_seconds'] + 10
        and controls['max_transfer_bytes'] <= 8 * 1024**3
        and controls['aggregate_reserved_CPU_seconds'] <= 1000
        and controls['aggregate_reserved_wall_seconds'] <= 14400
        and controls['max_status_polls'] <= 4, 'finite separately funded controller/transport limits required')
    n_metadata = 12 + 2 * controls['max_status_polls']
    required_CPU = (2 * n_metadata * controls['operation_CPU_seconds'] + 6 * controls['proof_CPU_seconds']
        + 4 * controls['transport_CPU_seconds'] + controls['validation_CPU_seconds']
        + controls['local_administrative_CPU_reserve_seconds'] + 4 * controls['ready_CPU_seconds'])
    required_wall = (n_metadata * controls['operation_wall_seconds'] + 3 * controls['proof_wall_seconds']
        + 2 * controls['transport_wall_seconds'] + controls['validation_wall_seconds'] + 2 * controls['ready_wall_seconds'])
    require(controls['max_operations'] >= n_metadata + 8
            and controls['aggregate_reserved_CPU_seconds'] >= required_CPU
            and controls['aggregate_reserved_wall_seconds'] >= required_wall,
            'complete bounded controller lifecycle/poll/transport/validation calendar must be funded before launch')
    if admit_new_work:
        require(now + whole['wall_seconds'] + required_wall + 300 * controls['max_status_polls'] < spec['controller_expires_epoch'],
                'whole-job and complete controller/poll calendar do not fit declared finite administrative window')
    review = spec_read(spec, spec['prelaunch_review'], remote)
    require(review.get('status') == 'PASS_REVIEWED_NEW_PROFILE_LIFECYCLE'
            and review.get('scope_id') == spec['scope_id'] and review.get('request') == spec['request']
            and review.get('worker_sources') == spec['worker_sources']
            and review.get('controller_sources') == spec['controller_sources']
            and review.get('allocation_limits') == whole and review.get('worker_limits') == limits
            and review.get('controller_limits') == controls
            and review.get('spec_contract_sha256') == spec_contract(spec)
            and review.get('no_old_grants_reused') is True, 'exact independently reviewed new lifecycle required')
    publication = spec_read(spec, spec['feature_publication'], remote)
    require(publication.get('status') == 'VERIFIED_FEATURE_PUBLICATION'
            and publication.get('source_files') == spec['controller_sources']
            and publication.get('fresh_remote_hash_verified') is True, 'fresh published feature source proof required')
    reserved = spec_read(spec, spec['funding_reservation'], remote)
    require(reserved.get('schema') == 'r164_profile_reservation_v1'
            and reserved.get('status') == 'CPU_RESERVED_BEFORE_SUBMISSION'
            and reserved.get('scope_id') == spec['scope_id'] and reserved.get('phase') == spec['phase']
            and reserved.get('request_sha256') == spec['request']['sha256']
            and reserved.get('source_files') == spec['worker_sources']
            and reserved.get('reserved_CPU_seconds') == whole['aggregate_cpu_seconds']
            and whole['aggregate_cpu_seconds'] <= reserved.get('cumulative_reserved_CPU_seconds', 0) <= 2300
            and reserved.get('created_epoch', now + 1) <= now, 'new whole-job funding must precede held submission')
    if spec['phase'] == 'MEASUREMENT_PAIR':
        qualification = spec_read(spec, spec['qualification'], remote)
        require(qualification.get('status') == 'ACCEPTED_COMPLETE_PAIRED_COMPONENT_QUALIFICATION'
                and qualification.get('source_files') == spec['worker_sources']
                and qualification.get('whole_accounting_accepted') is True
                and qualification.get('all_canonical_array_bytes_equal') is True,
                'accepted complete qualification required before separate measurement')
    else:
        require(spec['qualification'] is None, 'qualification phase cannot substitute a previous measurement')
    if admit_new_work:
        request = spec_read(spec, spec['request'], remote)
        policy = spec_read(spec, request['policy'], remote)
        a.validate_policy(policy, now, read_evidence=lambda value: spec_read(spec, value, remote))
    if remote:
        request = read(spec['request']); a.validate_request(request)
        a.validate_policy(read(request['policy']), now)
    return spec


class Journal:
    """Create-only chained records under one exclusive canonical claim lock."""
    def __init__(self, scope_id):
        owner(); require(re.fullmatch(r'r164-profile-[a-z0-9]{16,64}', scope_id), 'scope ID required')
        e.planning.physical(CENTRAL).mkdir(parents=True, exist_ok=True)
        self.global_fd = os.open(CENTRAL / 'global.lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        self.fd = None
        try:
            fcntl.flock(self.global_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.root = e.planning.physical(CENTRAL / scope_id)
            self.root.mkdir(parents=True, exist_ok=True)
            self.fd = os.open(self.root / 'lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
            fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BaseException:
            if self.fd is not None: os.close(self.fd)
            os.close(self.global_fd); raise
    def close(self):
        os.close(self.fd); os.close(self.global_fd)
    def records(self):
        names = sorted(self.root.glob('record_*.json')); require(len(names) <= 256, 'bounded durable lifecycle journal required')
        result = []; previous = None
        for index, path in enumerate(names):
            require(path.name == 'record_%04d.json' % index, 'missing or reordered lifecycle journal')
            item = e.planning.decode_json(e.bounded_read(path))
            require(item.get('previous_sha256') == previous, 'lifecycle journal chain changed')
            result.append(item); previous = r.digest(path)
        return result
    def put(self, state, **values):
        records = self.records(); last = records[-1] if records else None
        item = dict(state=state, created_epoch=time.time(), previous_sha256=None if last is None
                    else r.digest(self.root / ('record_%04d.json' % (len(records) - 1))), **values)
        e.write_new(self.root / ('record_%04d.json' % len(records)), item)
        return item
    def last(self):
        records = self.records(); require(records, 'prepared lifecycle claim required'); return records[-1]


def state(journal, *allowed):
    value = journal.last(); require(value['state'] in allowed, 'invalid lifecycle transition; no retry/resubmission')
    return value


def historical_records(path):
    # Caller holds the one global canonical lock, so no second lock is opened.
    view = Journal.__new__(Journal); view.root = e.planning.physical(path)
    return view.records()


def single_active(scope):
    # Completed or ambiguous charged scopes do not create a reusable claim.
    for path in CENTRAL.glob('r164-profile-*'):
        if path.name == scope: continue
        records = historical_records(path)
        if records:
            last = records[-1]
            require(last.get('state') in FINAL, 'another new profile claim remains active; single worker only')


def funding_history(spec):
    request = spec_read(spec, spec['request'])
    policy_sha = request['policy']['sha256']; spent = 0
    for path in CENTRAL.glob('r164-profile-*'):
        if path.name == spec['scope_id']: continue
        records = historical_records(path)
        if not records: continue
        first = records[0]
        previous = read(first['spec'])
        previous_request = spec_read(previous, previous['request'])
        if previous_request['policy']['sha256'] == policy_sha:
            require(previous['phase'] != spec['phase'], 'same profiling phase already consumed under this policy; no implicit retry')
            spent += previous['allocation_limits']['aggregate_cpu_seconds']
    reserved = spec_read(spec, spec['funding_reservation'])
    require(reserved['cumulative_reserved_CPU_seconds'] == spent + spec['allocation_limits']['aggregate_cpu_seconds']
            and reserved['cumulative_reserved_CPU_seconds'] <= 2300,
            'canonical cumulative new funding cannot reset or refund previous profile claims')


def prepare_run(spec_path):
    owner(); spec = read(pin(spec_path)); validate_spec(spec)
    j = Journal(spec['scope_id'])
    try:
        require(not j.records(), 'new scope is create-only; no implicit rerun')
        single_active(spec['scope_id'])
        funding_history(spec)
        e.write_new(j.root / 'controller_spec.json', spec)
        j.put('PREPARATION_INTENT', spec=pin(j.root / 'controller_spec.json'),
              reservation=spec['funding_reservation'], full_reservation_retained_on_failure=True)
        release = j.root / 'release'; release.mkdir(exist_ok=False)
        for item in spec['files']:
            target = release / safe_relative(item['relative']); target.parent.mkdir(parents=True, exist_ok=True)
            raw = e.bounded_read(item['local'])
            require(len(raw) == item['bytes'] and hashlib.sha256(raw).hexdigest() == item['sha256'], 'stage source/metadata changed')
            with target.open('xb') as handle:
                handle.write(raw); handle.flush(); os.fsync(handle.fileno())
        e.write_new(release / 'controller_spec.json', spec)
        script = ('#!/bin/bash\nset -euo pipefail\n'
            'export PYTHONDONTWRITEBYTECODE=1 PYTHONNOUSERSITE=1\n'
            'export PATH=/usr/bin:/bin SLURM_EXPORT_ENV=ALL\n'
            'export PYTHONPATH=' + shlex.quote(spec['remote_root'] + '/code') + '\n'
            + ''.join('export ' + key + '=' + shlex.quote(value) + '\n'
                      for key, value in {**THREAD_ENV, **REFERENCE_NUMERICAL_ENV}.items())
            + 'exec /usr/bin/srun --ntasks=1 --cpus-per-task=1 --cpu-bind=cores --hint=nomultithread '
            + shlex.quote(spec['runtime_python']) + ' -B -m pricefm_hb.profile_control --compute-session '
            + shlex.quote(spec['remote_root'] + '/controller_spec.json') + '\n')
        with (release / 'job.sh').open('x') as handle:
            handle.write(script); handle.flush(); os.fsync(handle.fileno())
        os.chmod(release / 'job.sh', 0o700)
        manifest = {str(path.relative_to(release)): dict(sha256=r.digest(path), bytes=path.stat().st_size)
                    for path in sorted(release.rglob('*')) if path.is_file()}
        e.write_new(release / 'release_manifest.json', dict(schema='r164_profile_release_v1', scope_id=spec['scope_id'], files=manifest))
        return j.put('PREPARED', spec=pin(release / 'controller_spec.json'),
                     release_manifest=pin(release / 'release_manifest.json'), reservation=spec['funding_reservation'])
    finally:
        j.close()


def bounded(argv, *, wall, cpu, cap):
    command = [sys.executable, '-I', '-B', str(Path(__file__).with_name('profile_supervisor.py')),
               '--cpu', str(cpu), '--wall', str(wall), '--output-cap', str(cap), '--', *argv]
    completed = subprocess.run(command, capture_output=True, text=True, timeout=wall + 5,
                               start_new_session=True)
    require(bool(completed.stdout), 'owned command supervisor failed before a complete receipt: ' + completed.stderr[-2000:])
    result = e.planning.decode_json(completed.stdout)
    require(result.get('all_owned_descendants_reaped') is True and result.get('kernel_escape_filter') is True
            and result.get('aggregate_CPU_seconds', float('inf')) < cpu
            and completed.returncode == result.get('returncode') == 0,
            'owned aggregate command failed: ' + str(result.get('cap_reason')) + ': ' + result.get('stderr', '')[-2000:])
    return result['stdout']


def operation(j, spec, label, argv, runner=bounded, *, transfer=False, proof=False, validation=False, ready=False, remote_CPU=None):
    intents = [x for x in j.records() if x['state'] == 'OPERATION_INTENT']
    require(len(intents) < spec['controller_limits']['max_operations'], 'finite controller operation count exhausted')
    controls = spec['controller_limits']
    require(sum((bool(transfer), bool(proof), bool(validation), bool(ready))) <= 1, 'one operation accounting role required')
    prefix = 'transport' if transfer else 'proof' if proof else 'validation' if validation else 'ready' if ready else 'operation'
    wall, cpu = controls[prefix + '_wall_seconds'], controls[prefix + '_CPU_seconds']
    require(time.time() + wall < spec['controller_expires_epoch'],
            'operation cannot outlive prospectively funded finite controller window')
    remote_cpu = cpu if ready else 0 if remote_CPU is None else remote_CPU
    require(type(remote_cpu) is int and remote_cpu in (0, cpu), 'exact bounded local/remote operation funding required')
    reserved_cpu = cpu + remote_cpu
    require(sum(x['CPU_limit'] for x in intents) + reserved_cpu + controls['local_administrative_CPU_reserve_seconds'] <= controls['aggregate_reserved_CPU_seconds']
            and sum(x['wall_limit'] for x in intents) + wall <= controls['aggregate_reserved_wall_seconds'],
            'separately funded aggregate controller operation reservation exhausted')
    j.put('OPERATION_INTENT', operation=label, argv=argv, wall_limit=wall, CPU_limit=reserved_cpu,
          local_CPU_limit=cpu, remote_CPU_reservation=remote_cpu)
    start = time.monotonic(); before = e.b.aggregate_cpu_seconds()
    try:
        text = runner(argv, wall=wall, cpu=cpu, cap=controls['max_output_bytes'])
        require(type(text) is str and len(text.encode()) <= controls['max_output_bytes'], 'bounded controller response required')
        return text
    except BaseException as exc:
        j.put('AMBIGUOUS_SPENT', operation=label, diagnostic=str(exc), reservation_retained=True)
        raise
    finally:
        e.write_new(j.root / ('operation_%04d.json' % len(intents)), dict(operation=label,
            wall_seconds=time.monotonic() - start, local_parent_children_CPU=e.b.aggregate_cpu_seconds() - before,
            observational_only=label not in {'held_sbatch', 'create_new_remote_release', 'stage_reviewed_release',
                'release_bounded_startup_only', 'publish_job_proofs_before_marker', 'publish_exact_authority_marker_last',
                'retrieve_all_useful_raw_outputs', 'bounded_owned_full_raw_validation',
                'cancel_exact_owned_profile_job', 'publish_canonical_terminal_accounting'},
            whole_job_charge_not_duplicated=True))


def remote(j, spec, site, label, args, runner=bounded):
    controls = spec['controller_limits']; cpu = controls['operation_CPU_seconds']; wall = controls['operation_wall_seconds']
    command = remote_command(args, cpu, wall, controls['max_output_bytes'])
    return operation(j, spec, label, ctl.ssh(site) + [shlex.join(command)], runner, remote_CPU=cpu)


def scope_spec(j, admit_new_work=True):
    first = j.records()[0]; spec = read(first['spec']); validate_spec(spec, admit_new_work=admit_new_work); return spec


def identify_site(spec):
    site = ctl.config(spec['site']['path'])
    require(r.digest(spec['site']['path']) == spec['site']['sha256'], 'site configuration changed')
    require(Path(spec['remote_root']).is_relative_to(Path(site['remote_root'])), 'release outside verified remote namespace')
    return site


def transfer(j, spec, site, label, source, target, runner=bounded, *, proof=False):
    controls = spec['controller_limits']; prefix = 'proof' if proof else 'transport'
    cpu, wall = controls[prefix + '_CPU_seconds'], controls[prefix + '_wall_seconds']
    task = dict(source=str(source), target=str(target), ssh_argv=ctl.ssh(site),
        remote_helper_source=supervisor_source(), cpu=cpu, wall=wall,
        max_bytes=controls['max_transfer_bytes'], scope=spec['scope_id'])
    task_path = j.root / ('stream_task_%04d.json' % len([x for x in j.records() if x['state'] == 'OPERATION_INTENT']))
    e.write_new(task_path, task)
    argv = [sys.executable, '-I', '-B', str(Path(__file__).with_name('profile_stream.py')), '--task', str(task_path)]
    return operation(j, spec, label, argv, runner, transfer=not proof, proof=proof, remote_CPU=cpu)


def stage_run(scope_id, runner=bounded):
    j = Journal(scope_id)
    try:
        state(j, 'PREPARED'); spec = scope_spec(j); site = identify_site(spec)
        require(not remote(j, spec, site, 'own_queue_before_stage', ['squeue', '-h', '-u', site['user'], '-o', '%i'], runner).strip(),
                'own HB queue is not empty; single worker profile deferred')
        remote(j, spec, site, 'create_new_remote_release', ['mkdir', spec['remote_root']], runner)
        transfer(j, spec, site, 'stage_reviewed_release', str(j.root / 'release') + '/',
                 site['user'] + '@' + site['host'] + ':' + spec['remote_root'] + '/', runner)
        value = remote(j, spec, site, 'remote_manifest_hash', ['sha256sum', spec['remote_root'] + '/release_manifest.json'], runner)
        manifest = pin(j.root / 'release' / 'release_manifest.json')
        require(value.split()[0] == manifest['sha256'], 'remote release manifest differs')
        return j.put('STAGED', release_manifest=manifest, remote_root=spec['remote_root'])
    finally:
        j.close()


def sbatch_args(spec, site):
    whole = spec['allocation_limits']; seconds = whole['wall_seconds']
    duration = '%02d:%02d:%02d' % (seconds // 3600, seconds % 3600 // 60, seconds % 60)
    return ['sbatch', '--parsable', '--hold', '--export=NONE', '--propagate=NONE', '--no-requeue', '--mail-type=NONE',
        '--nodes=1', '--ntasks=1', '--cpus-per-task=1', '--hint=nomultithread',
        '--mem=' + str(whole['memory_MiB']) + 'M', '--time=' + duration,
        '--account=128x24', '--partition=128x24', '--qos=normal', '--nodelist=' + spec['node'],
        '--job-name=' + spec['scope_id'], '--chdir=' + spec['remote_root'],
        '--output=' + spec['remote_root'] + '/%j.stdout', '--error=' + spec['remote_root'] + '/%j.stderr',
        spec['remote_root'] + '/job.sh']


def submit_run(scope_id, runner=bounded):
    j = Journal(scope_id)
    try:
        state(j, 'STAGED'); spec = scope_spec(j); site = identify_site(spec); single_active(scope_id)
        require(not remote(j, spec, site, 'own_queue_before_submit', ['squeue', '-h', '-u', site['user'], '-o', '%i'], runner).strip(),
                'own HB queue is not empty; do not submit')
        j.put('SUBMISSION_INTENT', reservation=spec['funding_reservation'], no_retry=True)
        reply = remote(j, spec, site, 'held_sbatch', ['python3', '-I', '-B', '-c', SBATCH_ENV_WRAPPER,
                       *sbatch_args(spec, site)], runner).strip()
        if not re.fullmatch(r'[1-9][0-9]*(?:;[A-Za-z0-9_.-]+)?', reply):
            j.put('AMBIGUOUS_SPENT', diagnostic='ambiguous held sbatch reply', reservation_retained=True)
            raise ValueError('submission may have reached Slurm; no automatic retry')
        job = reply.split(';')[0]
        submission = dict(schema='r164_profile_submission_v1', status='HELD_SUBMISSION_JOB_IDENTIFIED',
            scope_id=scope_id, job_id=job, reservation=spec['funding_reservation'], created_epoch=time.time())
        e.write_new(j.root / 'submission.json', submission)
        return j.put('HELD', job_id=job, submission=pin(j.root / 'submission.json'))
    finally:
        j.close()


def release_startup(scope_id, runner=bounded):
    j = Journal(scope_id)
    try:
        claim = state(j, 'HELD'); spec = scope_spec(j); site = identify_site(spec)
        text = remote(j, spec, site, 'verify_exact_owned_held_job', ['scontrol', 'show', 'job', '-o', claim['job_id']], runner)
        fields = dict(re.findall(r'(\S+?)=(\S*)', text))
        _no_hidden_resources(fields)
        require(fields.get('JobId') == claim['job_id'] and fields.get('JobName') == scope_id
                and fields.get('WorkDir') == spec['remote_root'] and fields.get('JobState') == 'PENDING'
                and fields.get('Command') == spec['remote_root'] + '/job.sh'
                and fields.get('ReqNodeList') == spec['node']
                and fields.get('UserId', '').split('(')[0] == 'jaguir26'
                and fields.get('NumCPUs') == fields.get('NumTasks') == fields.get('NumNodes') == '1'
                and fields.get('Requeue') == '0' and fields.get('Account') == fields.get('Partition') == '128x24'
                and fields.get('QOS') == 'normal'
                and a._wall_seconds(fields.get('TimeLimit', '')) == spec['allocation_limits']['wall_seconds']
                and a._memory_MiB(fields.get('MinMemoryNode') or fields.get('MinMemoryCPU', ''))
                    == spec['allocation_limits']['memory_MiB'], 'exact owned held resource envelope required')
        expected_manifest = pin(j.root / 'release' / 'release_manifest.json')['sha256']
        verified = operation(j, spec, 'verify_every_remote_release_byte_before_startup', ctl.ssh(site) + [shlex.join([
            'python3', '-I', '-B', '-c', VERIFY_REMOTE_RELEASE, spec['remote_root'], expected_manifest])], runner, ready=True)
        require(verified.strip() == 'VERIFIED ' + expected_manifest, 'every staged code/metadata/job.sh byte must pass before startup release')
        j.put('STARTUP_RELEASE_INTENT', job_id=claim['job_id'], worker_authority_not_yet_granted=True)
        remote(j, spec, site, 'release_bounded_startup_only', ['scontrol', 'release', claim['job_id']], runner)
        return j.put('STARTUP_READY_PENDING', job_id=claim['job_id'], submitted=claim['submission'])
    finally:
        j.close()


def _owned_fields(text, spec, job_id):
    fields = dict(re.findall(r'(\S+?)=(\S*)', text))
    _no_hidden_resources(fields)
    require(fields.get('JobId') == job_id and fields.get('JobName') == spec['scope_id']
            and fields.get('WorkDir') == spec['remote_root'] and fields.get('UserId', '').split('(')[0] == 'jaguir26'
            and fields.get('Command') == spec['remote_root'] + '/job.sh' and fields.get('ReqNodeList') == spec['node']
            and fields.get('NumCPUs') == fields.get('NumTasks') == fields.get('NumNodes') == '1'
            and fields.get('Account') == fields.get('Partition') == '128x24' and fields.get('QOS') == 'normal'
            and fields.get('Requeue') == '0'
            and a._wall_seconds(fields.get('TimeLimit', '')) == spec['allocation_limits']['wall_seconds']
            and a._memory_MiB(fields.get('MinMemoryNode') or fields.get('MinMemoryCPU', '')) == spec['allocation_limits']['memory_MiB'],
            'cancellation requires exact owned new job and unchanged resource envelope')
    return fields


def _no_hidden_resources(fields):
    require(fields.get('ArrayJobId', '0') in ('0', 'N/A')
            and fields.get('ArrayTaskId', 'N/A') in ('N/A', '4294967294'),
            'single held job must not be an inherited array')
    absent = ('', '(null)', 'N/A', 'None')
    for name in ('Gres', 'GresDetail', 'TresPerNode', 'TresPerTask', 'TresPerSocket', 'TresPerJob'):
        require(fields.get(name, '') in absent, 'unexpected GPU/GRES/per-task resource request rejected')
    for name in ('TRES', 'ReqTRES', 'AllocTRES'):
        value = fields.get(name, '')
        if value in absent: continue
        entries = value.split(',')
        require(all('=' in item and item.split('=', 1)[0] in {'cpu', 'mem', 'node', 'billing'} for item in entries),
                'unexpected whole-job TRES request rejected')


def _cancel_owned(j, spec, site, job_id, runner):
    before = remote(j, spec, site, 'verify_exact_owned_cancel_target', ['scontrol', 'show', 'job', '-o', job_id], runner)
    fields = _owned_fields(before, spec, job_id)
    require(fields.get('JobState') in ('PENDING', 'RUNNING', 'CONFIGURING', 'COMPLETING'), 'owned active new job required for cancellation')
    j.put('OWNED_CANCEL_INTENT', job_id=job_id, before=before, full_reservation_retained=True)
    remote(j, spec, site, 'cancel_exact_owned_profile_job', ['scancel', job_id], runner)
    after = remote(j, spec, site, 'verify_exact_owned_job_after_cancel', ['scontrol', 'show', 'job', '-o', job_id], runner)
    _owned_fields(after, spec, job_id)
    queue = remote(j, spec, site, 'own_queue_after_cancel', ['squeue', '-h', '-u', site['user'], '-o', '%i|%T'], runner)
    text = remote(j, spec, site, 'terminal_accounting_after_cancel', ['sacct', '-nP', '--units=K', '-j', job_id,
        '--format=JobID,State%30,ExitCode,ElapsedRaw,AllocCPUS,TotalCPU,MaxRSS,NodeList'], runner)
    raw_rows = [line.split('|') for line in text.splitlines() if line.strip()]
    never_allocated = (len(raw_rows) == 1 and len(raw_rows[0]) == 8 and raw_rows[0][0] == job_id
        and raw_rows[0][1].split()[0] == 'CANCELLED' and raw_rows[0][3] == '0'
        and raw_rows[0][4] in ('0', '1') and ctl.cpu_seconds(raw_rows[0][5]) == 0
        and raw_rows[0][7] in ('', 'None assigned', 'Unknown'))
    parsed = (dict(terminal=True, complete=False, canonical_primary_CPU_seconds=0)
              if never_allocated else parse_accounting(text, job_id, spec))
    queued = any(line.split('|')[0] == job_id for line in queue.splitlines())
    if parsed['terminal'] and not queued:
        return j.put('FAILED_RECONCILED', job_id=job_id, before=before, after=after, sacct=text,
            charged_CPU_seconds=max(spec['allocation_limits']['aggregate_cpu_seconds'], parsed['canonical_primary_CPU_seconds'] or 0),
            cancellation_terminal_proved=True, retry_or_refund_authorized=False)
    return j.put('CANCELLATION_REQUESTED_UNRECONCILED', job_id=job_id, before=before, after=after,
                 sacct=text, reservation_retained=True, blocks_new_profile=True)


def cancel_exact_owned_job(scope_id, runner=bounded):
    j = Journal(scope_id)
    try:
        spec = scope_spec(j, False)
        known = [item for item in j.records() if item.get('job_id')]
        require(bool(known) and j.last()['state'] not in FINAL, 'one unresolved known own job required')
        return _cancel_owned(j, spec, identify_site(spec), known[-1]['job_id'], runner)
    finally:
        j.close()


def observe_ready(scope_id, notification_pin, runner=bounded):
    """One explicitly funded exact-job READY notification; not a health poll loop."""
    j = Journal(scope_id)
    try:
        claim = state(j, 'STARTUP_READY_PENDING'); spec = scope_spec(j); site = identify_site(spec)
        notice = read(notification_pin)
        require(notice.get('status') == 'ROOT_FUNDED_EXACT_JOB_READY_NOTIFICATION'
                and notice.get('scope_id') == scope_id and notice.get('job_id') == claim['job_id']
                and notice.get('prelaunch_review') == spec['prelaunch_review'], 'funded exact READY notification required')
        try:
            text = operation(j, spec, 'single_bounded_exact_job_ready_notification', ctl.ssh(site) + [shlex.join([
                '/usr/bin/python3', '-I', '-B', '-c', READY_WAITER, spec['remote_root'], scope_id,
                claim['job_id'], spec['request']['sha256'], str(spec['controller_limits']['ready_wait_seconds'])])], runner, ready=True)
        except BaseException:
            # Pending time is outside Slurm allocation wall. Reconcile this
            # exact owned new job instead of leaving a silently pending lease.
            _cancel_owned(j, spec, site, claim['job_id'], runner)
            raise
        ready = e.planning.decode_json(text)
        require(ready.get('scope_id') == scope_id and ready.get('status') == 'COMPUTE_READY'
                and ready.get('allocation', {}).get('job_id') == claim['job_id']
                and ready.get('allocation', {}).get('node') == spec['node']
                and ready.get('request_sha256') == spec['request']['sha256']
                and ready.get('worker_sources') == spec['worker_sources']
                and ready.get('controller_sources') == spec['controller_sources']
                and ready.get('runtime', {}).get('status') == 'verified'
                and 0 <= time.time() - ready.get('observed_epoch', 0) <= 300, 'fresh actual-job READY required')
        e.write_new(j.root / 'ready.json', ready)
        return j.put('READY_OBSERVED', job_id=claim['job_id'], attestation=pin(j.root / 'ready.json'), submitted=claim['submitted'])
    finally:
        j.close()


def release_worker(scope_id, authority_pin, *, staged_files, runner=bounded):
    j = Journal(scope_id)
    try:
        claim = state(j, 'READY_OBSERVED'); spec = scope_spec(j); site = identify_site(spec)
        authority = read(authority_pin); ready = read(claim['attestation'])
        require(authority.get('job_id') == claim['job_id'] and authority.get('scope_id') == scope_id
                and authority.get('source_files') == spec['worker_sources']
                and authority.get('attestation_sha256') == claim['attestation']['sha256']
                and authority.get('limits') == spec['worker_limits']
                and authority.get('allocation_limits') == spec['allocation_limits']
                and authority.get('output_root') == spec['output_root']
                and authority.get('parity_runtime') == ready['runtime'], 'exact reviewed worker authority/READY binding required')
        require(type(staged_files) is list and 0 < len(staged_files) <= 32, 'explicit new job-bound proof staging required')
        # Job-bound funding/review/authority cannot exist before the held job ID.
        # Stage every exact proof first; worker_authority.json is the last marker.
        marker = None
        for item in staged_files:
            require(type(item) is dict and set(item) == {'local', 'relative', 'sha256'}, 'exact proof stage pin required')
            relative = safe_relative(item['relative']); data = e.bounded_read(item['local'])
            require(hashlib.sha256(data).hexdigest() == item['sha256'], 'new job proof changed')
            if str(relative) == 'worker_authority.json':
                require(item['sha256'] == authority_pin['sha256'], 'release marker must be exact authority')
                marker = item
        require(marker is not None, 'create-only exact authority release marker required')
        require(len({item['relative'] for item in staged_files}) == len(staged_files), 'unique new proof paths required')
        def new_proof(value):
            path = Path(value['path'])
            require(path.is_relative_to(Path(spec['remote_root'])), 'job-bound proof must be in exact remote release')
            relative = str(path.relative_to(spec['remote_root']))
            matches = [item for item in staged_files if item['relative'] == relative]
            if matches:
                require(len(matches) == 1 and matches[0]['sha256'] == value['sha256'], 'exact new proof pin required')
                return read(dict(path=matches[0]['local'], sha256=value['sha256']))
            return spec_read(spec, value)
        request = spec_read(spec, spec['request'])
        require(authority.get('schema') == a.AUTHORITY_SCHEMA
                and authority.get('status') == 'ROOT_ADMITTED_COMPONENT_PROFILE_PAIR'
                and authority.get('purpose') == a.PURPOSE and authority.get('phase') == spec['phase']
                and authority.get('request_sha256') == spec['request']['sha256']
                and authority.get('policy') == request['policy']
                and authority.get('node') == ready['allocation']['node']
                and authority.get('created_epoch', float('inf')) <= time.time()
                and time.time() + spec['worker_limits']['wall_seconds'] < authority.get('expires_epoch', 0) <= spec['expires_epoch']
                and time.time() + spec['worker_limits']['wall_seconds'] + spec['allocation_limits']['exit_reserve_seconds']
                    < ready['scheduler_resources']['end_epoch'], 'complete fresh exact worker contract must fit allocation')
        review = new_proof(authority['review'])
        require(review.get('status') == 'PASS' and review.get('schema') == 'r164_profile_source_review_v1'
                and review.get('authority_contract_sha256') == a.identity({k: v for k, v in authority.items() if k != 'review'})
                and review.get('source_files') == spec['worker_sources']
                and review.get('request_sha256') == spec['request']['sha256']
                and review.get('limits') == spec['worker_limits']
                and review.get('allocation_limits') == spec['allocation_limits'], 'complete job-bound source review required before release')
        funding = new_proof(authority['funding'])
        submitted = new_proof(funding['submission'])
        require(funding.get('schema') == 'r164_profile_funding_v1'
                and funding.get('status') == 'RESERVED_BEFORE_SUBMISSION'
                and funding.get('scope_id') == scope_id and funding.get('phase') == spec['phase']
                and funding.get('job_id') == claim['job_id'] and funding.get('source_files') == spec['worker_sources']
                and funding.get('request_sha256') == spec['request']['sha256']
                and funding.get('reservation') == spec['funding_reservation']
                and funding.get('reserved_CPU_seconds') == spec['allocation_limits']['aggregate_cpu_seconds']
                and submitted == read(claim['submitted']), 'immutable whole-job reservation/submission/funding chain required')
        j.put('WORKER_RELEASE_INTENT', job_id=claim['job_id'], authority=authority_pin,
              attestation=claim['attestation'], staged_files=staged_files, submitted=claim['submitted'])
        targets = [spec['remote_root'] + '/' + str(safe_relative(item['relative'])) for item in staged_files]
        absence = ' && '.join(shlex.join(['test', '!', '-e', target]) for target in targets)
        remote(j, spec, site, 'all_new_job_proof_paths_must_be_absent', ['bash', '-c', absence], runner)
        bundle = j.root / 'job_bound_proofs'; bundle.mkdir(exist_ok=False)
        for item in staged_files:
            if item is marker: continue
            target = bundle / safe_relative(item['relative']); target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('xb') as handle:
                handle.write(e.bounded_read(item['local'])); handle.flush(); os.fsync(handle.fileno())
        transfer(j, spec, site, 'publish_job_proofs_before_marker', str(bundle) + '/',
                 site['user'] + '@' + site['host'] + ':' + spec['remote_root'] + '/', runner, proof=True)
        transfer(j, spec, site, 'publish_exact_authority_marker_last', marker['local'],
                 site['user'] + '@' + site['host'] + ':' + spec['remote_root'] + '/worker_authority.json', runner, proof=True)
        lines = remote(j, spec, site, 'verify_all_published_job_proof_hashes', ['sha256sum', *targets], runner).splitlines()
        observed = {line.split()[1]: line.split()[0] for line in lines if len(line.split()) == 2}
        require(observed == {target: item['sha256'] for target, item in zip(targets, staged_files)},
                'published exact job proof hashes differ')
        return j.put('RUNNING', job_id=claim['job_id'], authority=authority_pin,
                     attestation=claim['attestation'], submitted=claim['submitted'], staged_files=staged_files)
    finally:
        j.close()


def parse_accounting(text, job_id, spec):
    parsed = ctl.accounting(text, job_id, dict(spec['allocation_limits'], cpus=1))
    rows = parsed['rows']; primary = [row for row in rows if row[0] == job_id]
    require(len(primary) <= 1, 'one canonical primary Slurm charge required')
    if not primary:
        return dict(status='PENDING_ACCOUNTING_RESERVATION_RETAINED', complete=False, terminal=False,
            job_id=job_id, canonical_primary_CPU_seconds=None, canonical_primary_wall_seconds=None,
            unresolved_full_reservation_CPU_seconds=spec['allocation_limits']['aggregate_cpu_seconds'],
            rows=rows, step_and_child_CPU_added_as_another_charge=False)
    cpu = ctl.cpu_seconds(primary[0][5]); wall = int(primary[0][3]); whole = spec['allocation_limits']
    require(cpu <= whole['aggregate_cpu_seconds'] and wall <= whole['wall_seconds'], 'whole job exceeds new finite funding')
    require(all(row[7] in ('', spec['node']) for row in rows), 'foreign scheduler node rejected')
    return dict(status='ACCEPTED_COMPLETE_JOB_ACCOUNTING' if parsed['complete'] else 'TERMINAL_OR_INCOMPLETE_JOB_ACCOUNTING',
        complete=parsed['complete'], terminal=parsed['terminal'], job_id=job_id,
        canonical_primary_CPU_seconds=cpu, canonical_primary_wall_seconds=wall, rows=rows,
        step_and_child_CPU_added_as_another_charge=False)


def observe_run(scope_id, runner=bounded, *, now=None):
    now = time.time() if now is None else now
    j = Journal(scope_id)
    try:
        claim = state(j, 'RUNNING', 'TERMINAL_OBSERVED', 'AMBIGUOUS_SPENT')
        if claim['state'] == 'AMBIGUOUS_SPENT':
            known = [item for item in j.records() if item['state'] in ('RUNNING', 'WORKER_RELEASE_INTENT')]
            require(bool(known), 'unknown submitted job identity remains blocked; no automatic identification/resubmission')
            claim = known[-1]
        spec = scope_spec(j, False); site = identify_site(spec)
        polls = [x for x in j.records() if x['state'] == 'POLL_INTENT']
        require(len(polls) < spec['controller_limits']['max_status_polls'], 'finite status poll count exhausted')
        require(not polls or now - polls[-1]['checked_epoch'] >= 300, 'health/accounting polls throttled at least300seconds')
        j.put('POLL_INTENT', checked_epoch=now, job_id=claim['job_id'])
        queue = remote(j, spec, site, 'own_queue_poll', ['squeue', '-h', '-u', site['user'], '-o', '%i|%T'], runner)
        text = remote(j, spec, site, 'canonical_primary_and_step_accounting', ['sacct', '-nP', '--units=K', '-j', claim['job_id'],
            '--format=JobID,State%30,ExitCode,ElapsedRaw,AllocCPUS,TotalCPU,MaxRSS,NodeList'], runner)
        parsed = parse_accounting(text, claim['job_id'], spec)
        active = any(line.split('|')[0] == claim['job_id'] for line in queue.splitlines())
        receipt = dict(parsed, checked_epoch=now, squeue=queue, sacct=text, job_still_queued=active)
        path = j.root / ('accounting_%04d.json' % len(polls)); e.write_new(path, receipt)
        return j.put('TERMINAL_OBSERVED' if parsed['terminal'] and not active else 'RUNNING', job_id=claim['job_id'],
            authority=claim['authority'], attestation=claim['attestation'], submitted=claim['submitted'],
            staged_files=claim['staged_files'], accounting=pin(path))
    finally:
        j.close()


def reconcile_failure(scope_id):
    j = Journal(scope_id)
    try:
        claim = state(j, 'TERMINAL_OBSERVED'); spec = scope_spec(j, False)
        receipt = read(claim['accounting'])
        require(receipt.get('terminal') is True and receipt.get('complete') is False
                and not receipt.get('job_still_queued'), 'proved own terminal unsuccessful job required for failure reconciliation')
        return j.put('FAILED_RECONCILED', job_id=claim['job_id'], accounting=claim['accounting'],
            charged_CPU_seconds=max(spec['allocation_limits']['aggregate_cpu_seconds'],
                                    receipt.get('canonical_primary_CPU_seconds') or 0),
            old_failed_claim_retained=True, retry_or_refund_authorized=False)
    finally:
        j.close()


def verify_return(root, spec, claim):
    root = e.planning.physical(root); require(root.is_dir(), 'collected raw release directory required')
    for path in root.rglob('*'):
        require(not path.is_symlink() and (path.is_file() or path.is_dir()), 'safe regular return tree required')
    trusted_manifest_path = CENTRAL / spec['scope_id'] / 'release' / 'release_manifest.json'
    manifest = read(pin(trusted_manifest_path))
    require(r.digest(root / 'release_manifest.json') == r.digest(trusted_manifest_path),
            'returned immutable source/metadata release manifest changed')
    for name, meta in manifest['files'].items():
        path = e.planning.physical(root / safe_relative(name))
        require(path.stat().st_size == meta['bytes'] and r.digest(path) == meta['sha256'],
                'returned reviewed source/prelaunch metadata changed')
    require(type(claim.get('staged_files')) is list and claim['staged_files'], 'published exact-job proof manifest required')
    for item in claim['staged_files']:
        require(r.digest(e.planning.physical(root / safe_relative(item['relative']))) == item['sha256'],
                'returned job-bound proof changed')
    pair = root / 'outputs' / 'ACTUAL_COMPONENT_PROFILE' / spec['scope_id']
    require(not (pair / 'failure.json').exists(), 'failed pair cannot be accepted')
    completed = read(pin(pair / 'completed_evidence.json'))
    require(completed.get('status') == 'COMPLETE_PAIRED_PROFILE_NOT_SCREENING_ADMISSION'
            and completed.get('exact_whole_component_parity') is True, 'complete paired profile raw evidence required')
    for name, sha in completed['artifacts'].items():
        require(r.digest(e.planning.physical(pair / safe_relative(name))) == sha, 'returned full raw artifact changed')
    identity = read(pin(pair / 'execution_identity.json'))
    require(identity['authority_sha256'] == claim['authority']['sha256']
            and identity['attestation_sha256'] == claim['attestation']['sha256']
            and identity['request_sha256'] == spec['request']['sha256']
            and identity['executed_sources'] == spec['worker_sources']
            and identity['allocation']['job_id'] == claim['job_id'], 'returned exact source/job/request binding differs')
    original_ready = read(claim['attestation'])
    binding = dict(request_sha256=spec['request']['sha256'], authority_sha256=claim['authority']['sha256'],
        attestation_sha256=claim['attestation']['sha256'], executed_sources=spec['worker_sources'],
        allocation=original_ready['allocation'], scope_id=spec['scope_id'],
        task_sha256=spec_read(spec, spec['request'])['task_sha256'],
        native_library_sha256=original_ready['runtime']['native_library_sha256'])
    binding.update(canonical_return_expectation(spec))
    require(all(identity.get(key) == value for key, value in binding.items()),
            'returned parity universe differs from independently pinned canonical task/inputs')
    parity = e.verify_pair(pair / 'reference', pair / 'instrumented', binding)
    post = read(pin(pair / 'post_seal_accounting.json'))
    require(post.get('status') == 'POST_SEAL_ACCOUNTING_SNAPSHOT' and post.get('execution') == identity
            and post.get('completed_evidence_sha256') == r.digest(pair / 'completed_evidence.json'),
            'final sealing/epilogue accounting is missing or detached')
    whole_pair_CPU = post['accounting']['lifetime_CPU_at_snapshot']
    require(a.number(whole_pair_CPU) and whole_pair_CPU <= spec['worker_limits']['aggregate_cpu_seconds'],
            'observed complete paired process exceeds its finite numerical allowance')
    launcher = read(pin(root / 'launcher_accounting.json'))
    require(launcher.get('status') == 'COMPLETE_PROFILE_JOB_WRAPPER' and launcher.get('worker_returncode') == 0
            and launcher.get('scope_id') == spec['scope_id'] and launcher.get('job_id') == claim['job_id']
            and launcher.get('wrapper_CPU_seconds', float('inf')) <= spec['allocation_limits']['wrapper_cpu_seconds'],
            'complete whole startup/worker/wrapper accounting required')
    accounting = read(claim['accounting'])
    require(a.number(launcher.get('whole_subtree_CPU_seconds'))
            and accounting['canonical_primary_CPU_seconds'] + .01 >= max(whole_pair_CPU, launcher['whole_subtree_CPU_seconds']),
            'canonical primary charge underreports retained whole process CPU; retain reservation, no acceptance')
    return dict(parity=parity, identity=identity, launcher=launcher, component_pair_result=pin(pair / 'profile_result.json'))


def canonical_return_expectation(spec):
    """Muscat JSON/source-only reconstruction, independent of returned metadata."""
    request = spec_read(spec, spec['request'])
    require(request['study'] in e.planning.CANONICAL, 'original study required')
    canonical = e.planning.CANONICAL[request['study']]
    require(request['cost_plan']['sha256'] == canonical['cost_plan'], 'accepted original cost source changed')
    cost = spec_read(spec, request['cost_plan']); prep_pin = cost['canonical_preparation']
    require(prep_pin['sha256'] == canonical['preparation'], 'accepted original preparation source changed')
    prep = read(dict(path=prep_pin['path'], sha256=prep_pin['sha256']))
    tasks = [t for t in prep['tasks'] if t['name'] == request['task']]
    require(len(tasks) == 1 and r.identity(tasks[0]) == request['task_sha256'], 'exact original return task required')
    task = tasks[0]; contract = e.p.load_contract()
    descriptors = e.p.original('chunks')(task)
    context = e.p.original('context_identity')(task, prep)
    def shapes(n):
        return {key: dict(dtype='<i8' if key in e.b.RETAINED_INT_KEYS else '<f8', shape=list(value))
                for key, value in contract.array_shapes(n).items()}
    packets = {'predictions.npz': shapes(4 * len(task['daily_origin_positions']))}; identities = {}
    for descriptor in descriptors:
        name = 'checkpoints/' + descriptor['name'] + '/predictions.npz'
        packets[name] = shapes(len(descriptor['origin_positions']))
        identities[name] = dict(context=context, descriptor=descriptor)
    return dict(expected_packets=packets, expected_chunk_identities=identities,
        expected_result=dict(schema=e.p.RESULT_SCHEMA, name=task['name'], source=prep['source'], mode=task['mode'],
            scientific_identity_sha256=task['scientific_identity_sha256'], task_sha256=r.identity(task),
            origin_clock_windows=4 * len(task['daily_origin_positions']), chunk_count=len(descriptors),
            certified=True, new_model_fits=0, posterior_updated=False, test_opened=False,
            promotion_authorized=False, equal_origin_clock_weights=True, units='EUR/MWh'))


def collect_run(scope_id, runner=bounded):
    j = Journal(scope_id)
    try:
        claim = state(j, 'TERMINAL_OBSERVED'); spec = scope_spec(j, False); site = identify_site(spec)
        accounting = read(claim['accounting'])
        require(accounting.get('complete') is True and not accounting.get('job_still_queued'), 'complete terminal accounting required before collection')
        incoming = j.root / 'returned_raw'; require(not incoming.exists(), 'create-only raw return; no overwrite')
        incoming.mkdir()
        j.put('COLLECTION_INTENT', job_id=claim['job_id'], authority=claim['authority'], accounting=claim['accounting'])
        remote_accounting = spec['remote_root'] + '/completed_job_accounting.json'
        remote(j, spec, site, 'completed_accounting_path_must_be_absent', ['test', '!', '-e', remote_accounting], runner)
        transfer(j, spec, site, 'publish_canonical_terminal_accounting', claim['accounting']['path'],
                 site['user'] + '@' + site['host'] + ':' + remote_accounting, runner, proof=True)
        observed = remote(j, spec, site, 'verify_published_terminal_accounting', ['sha256sum', remote_accounting], runner).split()[0]
        require(observed == claim['accounting']['sha256'], 'published terminal accounting changed')
        size_text = remote(j, spec, site, 'bound_remote_raw_return_size',
                          ['du', '--apparent-size', '-s', '--block-size=1', spec['remote_root']], runner)
        require(size_text.split()[0].isdigit()
                and int(size_text.split()[0]) <= spec['controller_limits']['max_transfer_bytes'],
                'remote raw return exceeds funded transfer/storage before copy')
        transfer(j, spec, site, 'retrieve_all_useful_raw_outputs', site['user'] + '@' + site['host'] + ':' + spec['remote_root'] + '/', str(incoming) + '/', runner)
        total = sum(path.stat().st_size for path in incoming.rglob('*') if path.is_file())
        require(total <= spec['controller_limits']['max_transfer_bytes'], 'raw return exceeds separately funded transport envelope')
        claim_path = j.root / 'validation_claim.json'; e.write_new(claim_path, claim)
        validation = j.root / 'return_validation.json'
        operation(j, spec, 'bounded_owned_full_raw_validation', [sys.executable, '-B', '-m', 'pricefm_hb.profile_control',
            '--validate-return', str(incoming), '--spec', str(j.root / 'controller_spec.json'),
            '--claim', str(claim_path), '--receipt', str(validation)], runner, validation=True)
        verified = read(pin(validation))
        require(verified.get('status') == 'PASS_FULL_RAW_RETURN_VALIDATION'
                and verified.get('scope_id') == scope_id and verified.get('job_id') == claim['job_id'],
                'bounded full raw return validation did not pass')
        accepted = dict(status='ACCEPTED_COMPLETE_PAIRED_COMPONENT_QUALIFICATION' if spec['phase'] == 'QUALIFICATION_PAIR'
            else 'ACCEPTED_COMPLETE_PAIRED_COMPONENT_MEASUREMENT', scope_id=scope_id, source_files=spec['worker_sources'],
            whole_accounting_accepted=True, all_canonical_array_bytes_equal=True,
            request=spec['request'], parity_runtime=read(claim['attestation'])['runtime'],
            whole_accounting=dict(path=remote_accounting, sha256=claim['accounting']['sha256']),
            component_pair_result=dict(path=spec['output_root'] + '/profile_result.json',
                                       sha256=verified['component_pair_result']['sha256']),
            local_whole_accounting=claim['accounting'], local_component_pair_result=verified['component_pair_result'],
            full_raw_manifest=verified['full_raw_manifest'],
            raw_return=str(incoming), total_return_bytes=total, screening_admitted=False, prices_revised=False)
        e.write_new(j.root / 'accepted.json', accepted)
        return j.put('ACCEPTED', job_id=claim['job_id'], acceptance=pin(j.root / 'accepted.json'),
                     canonical_charged_CPU_seconds=accounting['canonical_primary_CPU_seconds'], reservation_retained=True)
    finally:
        j.close()


def compute_session(spec_path):
    """Admitted compute-only startup; waits finitely for separately reviewed worker authority."""
    allocation = require_compute()
    spec = read(pin(spec_path)); validate_spec(spec, remote=True)
    root = e.planning.physical(spec['remote_root'])
    require(Path.cwd() == root and allocation['node'] == spec['node'], 'exact owned allocation/working directory required')
    whole = spec['allocation_limits']; start = time.monotonic(); start_cpu = e.b.aggregate_cpu_seconds()
    deadline = min(start + whole['wall_seconds'], start + spec['expires_epoch'] - time.time())
    def expired(*_): raise TimeoutError('new finite whole-job startup/worker window exhausted')
    signal.signal(signal.SIGALRM, expired); signal.signal(signal.SIGXCPU, expired)
    signal.setitimer(signal.ITIMER_REAL, deadline - start)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    # Keep the inherited hard ceiling high enough for the separately bounded
    # worker; wrapper SELF is reduced permanently immediately after its spawn.
    resource.setrlimit(resource.RLIMIT_CPU, (whole['wrapper_cpu_seconds'], whole['aggregate_cpu_seconds']))
    manifest = read(pin(root / 'release_manifest.json'))
    for name, meta in manifest['files'].items():
        path = e.planning.physical(root / safe_relative(name))
        require(path.stat().st_size == meta['bytes'] and r.digest(path) == meta['sha256'], 'remote release source/metadata changed')
    from .environment import verify_runtime
    runtime = verify_runtime(spec['environment_bundle'], root / 'runtime_ready.json')
    scheduler = a.scheduler_evidence(allocation)
    deadline = min(deadline, time.monotonic() + scheduler['end_epoch'] - time.time())
    signal.setitimer(signal.ITIMER_REAL, max(.001, deadline - time.monotonic()))
    ready = dict(schema='r164_profile_job_attestation_v1', status='COMPUTE_READY', scope_id=spec['scope_id'],
        observed_epoch=time.time(), allocation=allocation, runtime=runtime, scheduler_resources=scheduler,
        request_sha256=spec['request']['sha256'], worker_sources=spec['worker_sources'],
        controller_sources=spec['controller_sources'], release_manifest_sha256=r.digest(root / 'release_manifest.json'))
    e.write_new(root / 'ready.json', ready)
    wait_end = min(deadline - spec['worker_limits']['wall_seconds'] - whole['exit_reserve_seconds'],
                   start + whole['ready_reserve_seconds'])
    authority_path = root / 'worker_authority.json'
    while not authority_path.exists():
        require(time.monotonic() < wait_end and e.b.aggregate_cpu_seconds() < whole['wrapper_cpu_seconds'],
                'bounded READY wait exhausted; no numerical authority; reservation retained')
        time.sleep(min(.25, max(.001, wait_end - time.monotonic())))
    authority = read(pin(authority_path))
    require(authority.get('scope_id') == spec['scope_id'] and authority.get('output_root') == spec['output_root']
            and authority.get('limits') == spec['worker_limits'] and authority.get('allocation_limits') == whole,
            'exact newly published paired worker envelope required')
    request = spec['request']; request_path = request['path']
    require(r.digest(request_path) == request['sha256'], 'remote actual request changed')
    command = [spec['runtime_python'], '-B', '-m', 'pricefm_hb.execution_profile',
        '--request', request_path, '--authority', str(authority_path), '--attestation', str(root / 'ready.json'), '--output', spec['output_root']]
    invocation = dict(executable=spec['runtime_python'], working_directory=str(root), request_path=request_path,
                      authority_path=str(authority_path), attestation_path=str(root / 'ready.json'))
    require(authority.get('invocation') == invocation, 'exact worker invocation must be reviewed')
    worker_cpu = spec['worker_limits']['aggregate_cpu_seconds']
    waited_before = resource.getrusage(resource.RUSAGE_CHILDREN)
    def child_limits():
        resource.setrlimit(resource.RLIMIT_CPU, (worker_cpu, worker_cpu))
    with (root / 'worker.stdout').open('xb') as stdout, (root / 'worker.stderr').open('xb') as stderr:
        child = subprocess.Popen(command, stdout=stdout, stderr=stderr, preexec_fn=child_limits)
        initial_child_CPU = waited_before.ru_utime + waited_before.ru_stime
        self_limit = math.floor(whole['wrapper_cpu_seconds'] - initial_child_CPU)
        resource.setrlimit(resource.RLIMIT_CPU, (self_limit, self_limit))
        try:
            code = child.wait(timeout=min(spec['worker_limits']['wall_seconds'], deadline - time.monotonic() - whole['exit_reserve_seconds']))
        except BaseException:
            child.kill(); child.wait(); raise
    waited_after = resource.getrusage(resource.RUSAGE_CHILDREN)
    worker_used = waited_after.ru_utime + waited_after.ru_stime - initial_child_CPU
    wrapper_used = e.b.aggregate_cpu_seconds() - worker_used
    e.write_new(root / 'launcher_accounting.json', dict(status='COMPLETE_PROFILE_JOB_WRAPPER' if code == 0 else 'FAILED_PROFILE_JOB_NO_RETRY',
        scope_id=spec['scope_id'], job_id=allocation['job_id'], worker_returncode=code,
        wrapper_CPU_seconds=wrapper_used, worker_subtree_CPU_seconds=worker_used,
        whole_subtree_CPU_seconds=e.b.aggregate_cpu_seconds(), wall_seconds=time.monotonic() - start,
        process_startup_CPU_before_entry=start_cpu, wrapper_started_monotonic=start,
        process_lifetime_wall_seconds=time.monotonic() - e.process_start_wall(),
        canonical_Slurm_charge_includes_batch_extern_and_final_receipt_tail=True,
        attribution_counters_are_not_another_charge=True))
    require(code == 0, 'paired component failed; all raw output retained; no automatic retry')
    return ready


def validate_return_operation(root, spec_path, claim_path, receipt_path):
    owner(); spec = read(pin(spec_path)); validate_spec(spec, admit_new_work=False)
    claim = read(pin(claim_path)); expected = e.planning.physical(CENTRAL / spec['scope_id'])
    require(e.planning.physical(root) == expected / 'returned_raw'
            and e.planning.physical(receipt_path) == expected / 'return_validation.json'
            and e.planning.physical(spec_path) == expected / 'controller_spec.json'
            and e.planning.physical(claim_path) == expected / 'validation_claim.json',
            'validation is confined to exact owned returned scope and create-only receipt')
    verified = verify_return(root, spec, claim)
    files = sorted(path for path in Path(root).rglob('*') if path.is_file())
    require(len(files) <= 5000, 'bounded complete raw return file count required')
    members = {}
    for path in files:
        e.planning.physical(path); before = path.stat()
        digest = r.digest(path)
        require(e.fingerprint(before) == e.fingerprint(path.stat()), 'raw return changed during manifest hashing')
        members[str(path.relative_to(root))] = dict(bytes=before.st_size, sha256=digest)
    raw_manifest = expected / 'returned_raw_manifest.json'
    e.write_new(raw_manifest, dict(schema='r164_complete_return_manifest_v1', scope_id=spec['scope_id'],
        job_id=claim['job_id'], root=str(root), members=members))
    result = dict(status='PASS_FULL_RAW_RETURN_VALIDATION', scope_id=spec['scope_id'], job_id=claim['job_id'],
                  component_pair_result=verified['component_pair_result'], exact_whole_component_parity=True,
                  full_raw_manifest=pin(raw_manifest))
    e.write_new(receipt_path, result)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compute-session')
    parser.add_argument('--validate-return'); parser.add_argument('--spec'); parser.add_argument('--claim'); parser.add_argument('--receipt')
    parser.add_argument('--prepare'); parser.add_argument('--scope')
    parser.add_argument('--notification'); parser.add_argument('--authority'); parser.add_argument('--proof-staging')
    parser.add_argument('--action', choices=('stage', 'submit', 'release-startup', 'observe-ready', 'await-ready', 'release-worker', 'observe', 'collect', 'reconcile-failure', 'cancel-owned'))
    args = parser.parse_args(argv)
    if args.compute_session: value = compute_session(args.compute_session)
    elif args.validate_return:
        require(args.spec and args.claim and args.receipt, 'bounded validation needs exact spec/claim/receipt paths')
        resource.setrlimit(resource.RLIMIT_CPU, (40, 40)); resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError('180wall raw validation cap')))
        signal.alarm(180)
        value = validate_return_operation(args.validate_return, args.spec, args.claim, args.receipt)
    elif args.prepare: value = prepare_run(args.prepare)
    else:
        require(args.scope is not None and args.action is not None, 'explicit lifecycle action/scope required')
        if args.action in ('observe-ready', 'await-ready'):
            require(args.notification, 'exact funded READY notification pin required')
            value = observe_ready(args.scope, pin(args.notification))
        elif args.action == 'release-worker':
            require(args.authority and args.proof_staging, 'exact authority and staged job-proof list required')
            files = e.planning.decode_json(e.bounded_read(args.proof_staging))
            value = release_worker(args.scope, pin(args.authority), staged_files=files)
        else:
            value = {'stage': stage_run, 'submit': submit_run, 'release-startup': release_startup,
                     'observe': observe_run, 'collect': collect_run, 'reconcile-failure': reconcile_failure,
                     'cancel-owned': cancel_exact_owned_job}[args.action](args.scope)
    print(json.dumps(value, sort_keys=True))


if __name__ == '__main__':
    main()
