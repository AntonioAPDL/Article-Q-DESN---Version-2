"""Finite opaque-I/O qualification controller, separate from scientific ledgers.

Each explicit stage consumes a retained parent reservation. No automatic retry,
scientific capacity amendment, numerical import, loss computation, or repricing.
"""
import argparse
import datetime
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import resource
import selectors
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time

CENTRAL = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/hb_control_registry')
TRACK = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_r162_forward_implementation_20261028')
BASE = '/mnt/beegfs/home/jaguir26/pricefm_hb_r156_20261027'
END = 1793259235.5743458
PURPOSE = 'OPAQUE_RESOURCE_IO_QUALIFICATION_NO_NUMERICAL_WORK'
RESOURCES = dict(cpus=1, memory_MiB=4096, cpu_seconds=120, wall_seconds=120)
SCHEMA = 'r162_opaque_io_qualification_v1'
RUN_SCRIPT = '#!/bin/bash\nset -euo pipefail\nunset SBATCH_EXPORT\nexec srun --ntasks=1 --cpus-per-task=1 --cpu-bind=threads /usr/bin/python3 -I -B "$1/resource_io_worker.py" --contract "$1/contract.json" --contract-sha256 "$2"\n'


def require(value, message):
    if not value:
        raise ValueError(message)


def physical(path):
    p = Path(path)
    require(p.is_absolute() and '..' not in p.parts and p.resolve() == p and not any(q.is_symlink() for q in (p, *p.parents)), 'absolute canonical physical path required')
    return p


def raw(path):
    p = physical(path)
    require(p.is_file() and p.stat().st_size <= 2*1024**2, 'bounded metadata/source required')
    return p.read_bytes()


def pin(path):
    return dict(path=str(physical(path)), sha256=hashlib.sha256(raw(path)).hexdigest())


def pinned(value):
    require(isinstance(value, dict) and set(value) == {'path', 'sha256'} and pin(value['path']) == value, 'exact metadata pin required')
    return json.loads(raw(value['path']))


def put(path, value):
    p = physical(path)
    with p.open('x') as f:
        json.dump(value, f, indent=2, sort_keys=True, allow_nan=False)
        f.write('\n'); f.flush(); os.fsync(f.fileno())


def cpu():
    return sum(resource.getrusage(resource.RUSAGE_SELF)[:2]) + sum(resource.getrusage(resource.RUSAGE_CHILDREN)[:2])


def bounded(argv, *, wall, local_cpu, input_bytes=None, cap=2*1024**2):
    def limits():
        resource.setrlimit(resource.RLIMIT_CPU, (local_cpu, local_cpu))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    p = subprocess.Popen(argv, stdin=subprocess.PIPE if input_bytes is not None else subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True, preexec_fn=limits)
    start = time.monotonic(); data = {'stdout': bytearray(), 'stderr': bytearray()}; sel = selectors.DefaultSelector()
    try:
        if input_bytes is not None:
            p.stdin.write(input_bytes); p.stdin.close()
        sel.register(p.stdout, selectors.EVENT_READ, 'stdout'); sel.register(p.stderr, selectors.EVENT_READ, 'stderr')
        while sel.get_map():
            require(time.monotonic()-start < wall, 'owned administrative command wall cap')
            for key, _ in sel.select(.1):
                b = os.read(key.fd, 8192)
                if not b: sel.unregister(key.fileobj)
                else:
                    data[key.data].extend(b); require(len(data[key.data]) <= cap, 'bounded command output exceeded')
        code = p.wait(timeout=max(.01, wall-(time.monotonic()-start)))
        return dict(returncode=code, stdout=bytes(data['stdout']).decode(errors='replace'),
            stderr=bytes(data['stderr']).decode(errors='replace'), wall=time.monotonic()-start)
    finally:
        sel.close()
        if p.poll() is None: os.killpg(p.pid, signal.SIGKILL)
        p.wait(); p.stdout.close(); p.stderr.close()


def ssh_base(site):
    return ['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'PasswordAuthentication=no',
        '-o', 'KbdInteractiveAuthentication=no', '-o', 'IdentitiesOnly=yes', '-o', 'IdentityAgent=none',
        '-o', 'StrictHostKeyChecking=yes', '-o', 'ControlMaster=no', '-o', 'ControlPath=none',
        '-o', 'ForwardAgent=no', '-o', 'ForwardX11=no', '-o', 'ConnectTimeout=10',
        '-o', 'UserKnownHostsFile='+site['known_hosts_file'], '-i', site['ssh_identity_file']]


def predecessor_proof(authority, contract):
    if contract['max_tasks'] == 2:
        require(authority.get('previous_qualification') is None, 'first stage has no borrowed predecessor')
        return
    pointer = authority.get('previous_qualification'); prior = pinned(pointer)
    require(prior.get('status') == 'COLLECTED_OPAQUE_IO_PROOF' and prior.get('accepted') is True
        and prior.get('task_count') == 2 and prior.get('parallel_opaque_IO_qualified') is True
        and prior.get('distinct_physical_cores') == 2 and prior.get('common_source_hash_overlap_seconds', 0) > 0
        and prior.get('scientific_scale_admitted') is False, 'accepted two-task parallel proof required before four')
    claim = json.loads(raw(CENTRAL/'r162_io_stage_2_20261028.claim.json'))
    registry = json.loads(raw(CENTRAL/(claim['scope_id']+'.registry.json')))
    require(registry['state'] == 'COLLECTED_OPAQUE_IO_PROOF' and registry.get('accepted') is True
        and pointer['path'] == registry['publication']+'/collection.json', 'canonical accepted predecessor publication required')
    old = json.loads(raw(Path(registry['publication'])/'contract.json'))
    require(pin(Path(registry['publication'])/'contract.json')['sha256'] == prior['contract_sha256']
        and old['source_files'] == contract['source_files'] and old['tasks'] == contract['tasks'][:2]
        and contract['tasks'][2]['files'] == old['tasks'][0]['files'] and contract['tasks'][3]['files'] == old['tasks'][1]['files'], 'same source/input qualification lineage required')


def validate_authority(pointer, now=None):
    now = time.time() if now is None else now
    a = pinned(pointer)
    require(a.get('schema') == 'r162_resource_io_root_authority_v1' and a.get('status') == 'ROOT_ADMITTED_EXACT_OPAQUE_IO_QUALIFICATION', 'new exact root qualification authority required')
    require(a.get('controller') == socket.getfqdn() == 'muscat.be.ucsc.edu', 'canonical Muscat controller required')
    require(a.get('purpose') == PURPOSE and a.get('numerical_work') is False and a.get('scientific_scale_admitted') is False, 'opaque nonnumerical purpose required')
    require(a['created_epoch'] <= now < a['expires_epoch'] <= min(END, a['created_epoch']+1800), 'finite qualification clock required')
    require(a.get('control_CPU_cap') == 90 and a.get('parent_slices') == 3 and a.get('metadata_limit') == 13 and a.get('transfer_limit') == 2, 'exact prepriced control grid required')
    require(a.get('controller_source') == pin(__file__), 'controller source changed')
    publication = pinned(a['publication'])
    require(publication.get('status') == 'FEATURE_PUBLISHED_FETCHED_CLEAN' and publication.get('controller_sha256') == a['controller_source']['sha256'], 'source publication readback required')
    site = pinned(a['site']); require((site['host'], site['user'], site['account'], site['partition'], site['qos']) == ('hb.ucsc.edu', 'jaguir26', '128x24', '128x24', 'normal'), 'exact qualified site required')
    require(a['known_hosts'] == pin(site['known_hosts_file']), 'host trust changed')
    contract = pinned(a['contract']); require(contract.get('schema') == SCHEMA and contract.get('purpose') == PURPOSE, 'new opaque contract required')
    n = contract.get('max_tasks'); require(type(n) is int and n in (2, 4) and contract.get('max_concurrent') == n, 'exact two- or four-task stage required')
    require(a.get('max_tasks') == n and a.get('allocated_CPU_cap') == n*120 and a.get('aggregate_memory_MiB') == n*4096, 'exact aggregate reservation required')
    require(contract.get('resources') == RESOURCES and contract['created_epoch'] <= now < contract['expires_epoch'] == a['expires_epoch'], 'contract resources/clock differ')
    scope = contract['scope_id']; require(re.fullmatch(r'r162_io_[a-f0-9]{32}', scope) and contract['remote_root'] == BASE+'/'+scope, 'new unique remote scope required')
    require(contract['node'] == 'node-13' and a['registry_path'] == str(CENTRAL/(scope+'.registry.json')), 'exact node/new canonical registry required')
    output = physical(a['output_root']); require(output.is_relative_to(TRACK), 'new tracker output root required')
    release = physical(a['release_path']); require(release.is_relative_to(TRACK) and set(p.name for p in release.iterdir()) == {'resource_io_worker.py', 'run_io.sh', 'contract.json'}, 'exact compact release membership required')
    require(pin(release/'contract.json') == a['contract'], 'contract must be actual staged file')
    require(set(contract['source_files']) == {'resource_io_worker.py', 'run_io.sh'}, 'exact worker source files required')
    for name, v in contract['source_files'].items():
        b = raw(release/name); require(hashlib.sha256(b).hexdigest() == v['sha256'] and len(b) == v['bytes'], 'compact payload source changed')
    require(raw(release/'run_io.sh').decode() == RUN_SCRIPT and publication['worker_sha256'] == contract['source_files']['resource_io_worker.py']['sha256'], 'published worker/entry source differs')
    predecessor_proof(a, contract)
    return a, contract, site


class Budget:
    def __init__(self, authority, pointer, contract):
        self.a, self.pointer, self.c = authority, pointer, contract
        self.path = physical(authority['registry_path']); self.lock = self.path.with_suffix('.lock')

    def update(self, fn):
        with self.lock.open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            state = json.loads(self.path.read_text())
            require(state['authority'] == self.pointer, 'registry authority changed')
            value = fn(state)
            tmp = self.path.with_name(self.path.name+'.'+str(os.getpid())+'.tmp')
            put(tmp, state); os.replace(tmp, self.path)
            return value

    def begin(self, stage):
        if stage == 'stage':
            with self.lock.open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                claim = self.path.parent/('r162_io_stage_'+str(self.c['max_tasks'])+'_20261028.claim.json')
                put(claim, dict(schema='r162_opaque_io_stage_claim_v1', scope_id=self.c['scope_id'], authority=self.pointer,
                    task_count=self.c['max_tasks'], no_refund=True, no_retry=True, created_epoch=time.time()))
                put(self.path, dict(schema='r162_opaque_io_registry_v1', authority=self.pointer,
                    state='RESERVED', purpose=PURPOSE, control_CPU_reserved=90,
                    compute_CPU_reserved=self.a['allocated_CPU_cap'], no_refund=True,
                    counts=dict(metadata=0, transfer=0), parent_reserved_CPU=0, actions={}, operations=[]))
        def change(s):
            expected = {'stage': {'RESERVED'}, 'submit': {'STAGED'}, 'finish': {'SUBMITTED', 'HELD', 'RELEASE_INTENT', 'SUBMISSION_INTENT'}}[stage]
            require(s['state'] in expected and stage not in s['actions'] and s['parent_reserved_CPU']+8 <= 24, 'one-use stage/parent limit')
            s['parent_reserved_CPU'] += 8; s['actions'][stage] = dict(status='INTENT_BEFORE_IO', reserved_CPU=8, pid=os.getpid(), epoch=time.time())
        self.update(change)

    def operation(self, kind):
        def change(s):
            limit = self.a['metadata_limit'] if kind == 'metadata' else self.a['transfer_limit']
            require(s['counts'][kind] < limit, 'operation limit exhausted')
            s['counts'][kind] += 1; s['operations'].append(dict(kind=kind, epoch=time.time(), reserved_CPU=3 if kind == 'metadata' else 11))
            return len(s['operations'])-1
        return self.update(change)

    def complete_operation(self, index, value):
        self.update(lambda s: s['operations'][index].update(result=value, complete_epoch=time.time()))

    def snapshot(self):
        return self.update(lambda s: json.loads(json.dumps(s)))


def remote(budget, site, argv):
    index = budget.operation('metadata')
    script = "import json,resource,signal,subprocess,sys;resource.setrlimit(resource.RLIMIT_CPU,(1,1));signal.alarm(18);p=subprocess.run(json.loads(sys.argv[1]),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=15);r=resource.getrusage(resource.RUSAGE_SELF);c=resource.getrusage(resource.RUSAGE_CHILDREN);assert len(p.stdout)<65536 and len(p.stderr)<65536;print(json.dumps(dict(returncode=p.returncode,stdout=p.stdout.decode(),stderr=p.stderr.decode(),remote_CPU=r.ru_utime+r.ru_stime+c.ru_utime+c.ru_stime)))"
    command = shlex.join(['/usr/bin/python3', '-I', '-c', script, json.dumps(argv)])
    result = bounded(ssh_base(site)+[site['user']+'@'+site['host'], command], wall=30, local_cpu=1)
    require(result['returncode'] == 0, 'metadata transport failed')
    value = json.loads(result['stdout']); budget.complete_operation(index, value)
    require(value['returncode'] == 0 and value['remote_CPU'] <= 2, 'bounded metadata command failed')
    return value['stdout']


def transfer(budget, site, source, target):
    index = budget.operation('transfer')
    # Reserve11CPU; stricter4local/5remote hard limits leave kernel rounding slack.
    script = "import os,resource,signal,sys;resource.setrlimit(resource.RLIMIT_CPU,(5,5));signal.alarm(110);os.execvp('rsync',['rsync']+sys.argv[1:])"
    rsync_path = shlex.join(['/usr/bin/python3', '-I', '-c', script])
    result = bounded(['rsync', '-rlt', '--safe-links', '--no-links', '--rsync-path='+rsync_path,
        '-e', shlex.join(ssh_base(site)), source, target], wall=115, local_cpu=4)
    budget.complete_operation(index, result); require(result['returncode'] == 0, 'one-use transfer failed')


def job_id(stdout):
    text = stdout.strip(); require(re.fullmatch(r'[0-9]+(?:;[A-Za-z0-9_-]+)?', text), 'ambiguous Slurm reply; no retry')
    return text.split(';')[0]


def sbatch_args(c):
    r = c['remote_root']; n = c['max_tasks']
    return ['sbatch', '--parsable', '--hold', '--export=NONE', '--propagate=NONE', '--no-requeue',
        '--nodes=1', '--ntasks=1', '--cpus-per-task=1', '--mem=4096M', '--time=00:02:00',
        '--hint=nomultithread', '--account=128x24', '--partition=128x24', '--qos=normal',
        '--nodelist='+c['node'], '--array=0-'+str(n-1)+'%'+str(n), '--job-name='+c['scope_id'],
        '--chdir='+r, '--output='+r+'/logs/%A_%a.out', '--error='+r+'/logs/%A_%a.err',
        r+'/run_io.sh', r, c['_sha256']]


def seconds(text):
    day, clock = text.split('-', 1) if '-' in text else ('0', text)
    fields = list(map(float, clock.split(':')))
    if len(fields) == 2: fields.insert(0, 0)
    require(len(fields) == 3, 'Slurm CPU duration required')
    return int(day)*86400 + fields[0]*3600 + fields[1]*60 + fields[2]


def owned_job(info, contract, jid, *, pending_only=False):
    lines = [v for v in info.splitlines() if v.strip()]
    require(lines, 'owned pending job evidence required')
    for line in lines:
        fields = dict(re.findall(r'(\w+)=([^\s]+)', line))
        require(fields.get('JobName') == contract['scope_id'] and fields.get('WorkDir') == contract['remote_root']
            and fields.get('UserId', '').split('(')[0] == 'jaguir26'
            and (fields.get('JobId', '').split('_')[0] == jid or fields.get('ArrayJobId') == jid),
            'exact owned metadata array identity required')
        if pending_only: require(fields.get('JobState') == 'PENDING', 'only wholly pending metadata array may be cancelled')
    return [dict(re.findall(r'(\w+)=([^\s]+)', line)).get('JobState') for line in lines]


def owned_pending(info, contract, jid):
    owned_job(info, contract, jid, pending_only=True)
    return True


def accounting(raw_text, base, count):
    rows = [v.split('|') for v in raw_text.splitlines() if v.strip()]
    require(all(len(v) == 11 for v in rows), 'eleven-column accounting with raw job ID required')
    expanded = []
    for row in rows:
        match = re.fullmatch(re.escape(base)+r'_\[([0-9,%-]+)\]', row[0])
        if match:
            require(row[2].split()[0].rstrip('+') in {'PENDING', 'CANCELLED', 'FAILED'}, 'successful grouped accounting cannot attest individual tasks')
            members = []
            for part in match.group(1).split('%')[0].split(','):
                bounds = list(map(int, part.split('-')))
                require(len(bounds) in (1, 2), 'bounded pending array range required')
                if len(bounds) == 1: bounds.append(bounds[0])
                require(0 <= bounds[0] <= bounds[1] < count, 'foreign grouped task range')
                members.extend(range(bounds[0], bounds[1]+1))
            require(len(members) == len(set(members)), 'duplicate pending task range')
            for index in members:
                copy = row.copy(); copy[0] = base+'_'+str(index); expanded.append(copy)
        else: expanded.append(row)
    rows = expanded
    expected = {base+'_'+str(i) for i in range(count)}
    ids = {v[0] for v in rows}
    require(all(v[0] == base or any(v[0] == x or v[0].startswith(x+'.') for x in expected) for v in rows), 'foreign accounting row rejected')
    have_primary = expected <= ids
    terminal = bool(rows) and have_primary and all(v[2].split()[0].rstrip('+') in {'COMPLETED', 'FAILED', 'CANCELLED', 'TIMEOUT', 'OUT_OF_MEMORY', 'NODE_FAIL', 'PREEMPTED'} for v in rows)
    passed = terminal and all(v+'.batch' in ids and v+'.0' in ids for v in expected) and all(v[2] == 'COMPLETED' and v[3] == '0:0' for v in rows)
    primary = [v for v in rows if v[0] in expected]
    require(len(primary) == len({v[0] for v in primary}), 'duplicate primary accounting rows')
    violations = []
    for v in primary:
        require(v[1].isdigit(), 'numeric primary raw job ID required')
        if not (int(v[5]) == 1 and 0 <= int(v[4]) <= 120 and 0 <= seconds(v[6]) <= 120): violations.append(v[0]+':allocation limit')
        if passed and not (int(v[4]) > 0 and v[8] == 'node-13'): violations.append(v[0]+':node/elapsed')
    for v in rows:
        if v[7]:
            unit = v[7][-1] if v[7][-1].isalpha() else 'K'; value = float(v[7][:-1] if v[7][-1].isalpha() else v[7])
            if not (math.isfinite(value) and 0 <= value*{'K': 1/1024, 'M': 1, 'G': 1024}[unit] <= 4096): violations.append(v[0]+':RSS')
    return dict(terminal=terminal, complete=passed and not violations, rows=rows, scope_violations=violations,
        allocated_primary_CPU=sum(seconds(v[6]) for v in primary), allocated_primary_wall=sum(int(v[4]) for v in primary))


def stage(b, a, c, site):
    census = pinned(a['census'])
    require(census.get('complete_for_root_review') is True and census.get('own_queue_empty') is True and time.time()-census['observed_epoch'] <= 1800, 'fresh exact resource census required')
    node = dict(re.findall(r'(\w+)=([^\s]+)', census['commands']['node_node-13']['stdout']))
    require(int(node['CPUEfctv'])-int(node['CPUAlloc']) >= c['max_tasks'] and int(node['RealMemory'])-int(node['AllocMem']) >= c['max_tasks']*4096 and int(node['FreeMem']) >= c['max_tasks']*4096+2048, 'observed aggregate capacity insufficient')
    require(not remote(b, site, ['squeue', '-h', '-u', site['user'], '-o', '%i']).strip(), 'own HB queue must be drained')
    r = c['remote_root']
    script = "import os,pathlib,sys;p=pathlib.Path(sys.argv[1]);assert str(p.parent)==sys.argv[2] and not p.exists() and '..' not in p.parts and not any(q.is_symlink() for q in (p,*p.parents));p.mkdir(mode=448);[(p/n).mkdir(mode=448) for n in ('logs','results','rendezvous')];print('CREATED')"
    remote(b, site, ['/usr/bin/python3', '-I', '-c', script, r, BASE])
    transfer(b, site, str(Path(a['release_path']))+'/', site['user']+'@'+site['host']+':'+r+'/')
    script = "import hashlib,json,pathlib,sys;p=pathlib.Path(sys.argv[1]);c=json.loads((p/'contract.json').read_text());assert hashlib.sha256((p/'contract.json').read_bytes()).hexdigest()==sys.argv[2];assert set(q.name for q in p.iterdir())=={'resource_io_worker.py','run_io.sh','contract.json','logs','results','rendezvous'};assert all(not q.is_symlink() for q in p.rglob('*'));assert all(hashlib.sha256((p/n).read_bytes()).hexdigest()==v['sha256'] and (p/n).stat().st_size==v['bytes'] for n,v in c['source_files'].items());print('SOURCE_VERIFIED')"
    remote(b, site, ['/usr/bin/python3', '-I', '-c', script, r, c['_sha256']])
    b.update(lambda s: s.update(state='STAGED'))


def submit(b, a, c, site):
    census = pinned(a['census']); require(time.time()-census['observed_epoch'] <= 1800, 'pre-submit census expired; no submission')
    require(not remote(b, site, ['squeue', '-h', '-u', site['user'], '-o', '%i']).strip(), 'own HB queue must remain drained')
    b.update(lambda s: s.update(state='SUBMISSION_INTENT'))
    jid = job_id(remote(b, site, sbatch_args(c)))
    b.update(lambda s: s.update(state='HELD', job_id=jid, submitted_epoch=time.time()))
    authority = dict(schema='r162_io_job_authorization_v1', status='ROOT_AUTHORIZED_OPAQUE_IO_QUALIFICATION',
        scope_id=c['scope_id'], contract_sha256=c['_sha256'], slurm_array_job_id=jid,
        resources=c['resources'], max_tasks=c['max_tasks'], max_concurrent=c['max_concurrent'],
        source_files=c['source_files'], created_epoch=time.time(), expires_epoch=c['expires_epoch'])
    encoded = json.dumps(authority, sort_keys=True, indent=2)+'\n'
    script = "import hashlib,pathlib,sys;p=pathlib.Path(sys.argv[1]);assert '..' not in p.parts and not any(q.is_symlink() for q in (p,*p.parents));f=p.open('x');f.write(sys.argv[2]);f.close();print(hashlib.sha256(p.read_bytes()).hexdigest())"
    sha = remote(b, site, ['/usr/bin/python3', '-I', '-c', script, c['remote_root']+'/authorization.json', encoded]).strip()
    require(sha == hashlib.sha256(encoded.encode()).hexdigest(), 'job authority write differs')
    b.update(lambda s: s.update(authorization=authority, authorization_sha256=sha, state='RELEASE_INTENT'))
    remote(b, site, ['scontrol', 'release', jid])
    b.update(lambda s: s.update(state='SUBMITTED', released_epoch=time.time()))


def verify_collection(root, c, state, parsed, *, collection_receipt=None):
    root = physical(root)
    require(not any(q.is_symlink() for q in root.rglob('*')), 'linked collection rejected')
    require(pin(root/'contract.json')['sha256'] == c['_sha256'], 'retrieved contract differs')
    require(pin(root/'authorization.json')['sha256'] == state['authorization_sha256'], 'retrieved authority differs')
    members = {'resource_io_worker.py', 'run_io.sh', 'contract.json', 'authorization.json', 'results', 'logs', 'rendezvous'}
    if collection_receipt is not None:
        members.add('collection.json'); require(json.loads(raw(root/'collection.json')) == collection_receipt, 'local collection receipt changed')
    require(set(q.name for q in root.iterdir()) == members, 'collected root membership differs')
    for name, record in c['source_files'].items():
        require(pin(root/name)['sha256'] == record['sha256'] and (root/name).stat().st_size == record['bytes'], 'retrieved source differs')
    require(set(q.name for q in (root/'results').iterdir()) == {'task_'+str(i) for i in range(c['max_tasks'])}, 'exact result task membership required')
    require(set(q.name for q in (root/'rendezvous').iterdir()) == {'task_'+str(i)+'.ready.json' for i in range(c['max_tasks'])}, 'complete ready membership required')
    expected_logs = {state['job_id']+'_'+str(i)+ext for i in range(c['max_tasks']) for ext in ('.out', '.err')}
    require(set(q.name for q in (root/'logs').iterdir()) <= expected_logs and all(q.is_file() and q.stat().st_size <= 65536 for q in (root/'logs').iterdir()), 'bounded owned logs required')
    results = []
    ready = {str(i): json.loads(raw(root/'rendezvous'/('task_'+str(i)+'.ready.json'))) for i in range(c['max_tasks'])}
    for i in range(c['max_tasks']):
        folder = root/'results'/('task_'+str(i))
        value = json.loads(raw(folder/'result.json')); seal = json.loads(raw(folder/'completed_evidence.json'))
        require(set(q.name for q in folder.iterdir()) == {'result.json', 'completed_evidence.json'}, 'exact successful task files required')
        require(seal['result_sha256'] == pin(folder/'result.json')['sha256'], 'worker result seal differs')
        allocation = value['allocation']
        require(ready[str(i)]['scope_id'] == c['scope_id'] and ready[str(i)]['contract_sha256'] == c['_sha256']
            and ready[str(i)]['allocation'] == allocation and value['rendezvous']['peers'] == ready, 'ready/result peer identities differ')
        require(seal['task_id'] == i and value['scope_id'] == c['scope_id'] and allocation['array_task_id'] == i and allocation['array_job_id'] == state['job_id'], 'worker/task/job identity differs')
        require(value['contract_sha256'] == c['_sha256'] and value['authorization_sha256'] == state['authorization_sha256'], 'worker authority/contract differs')
        primary = next(v for v in parsed['rows'] if v[0] == state['job_id']+'_'+str(i))
        require(allocation['job_id'] in {primary[0], primary[1]}, 'worker raw job ID is not scheduler-attested')
        start = datetime.datetime.fromisoformat(primary[9]).replace(tzinfo=datetime.timezone.utc).timestamp()
        end = datetime.datetime.fromisoformat(primary[10]).replace(tzinfo=datetime.timezone.utc).timestamp()
        require(start-1 <= value['started_epoch'] <= value['ended_epoch'] <= end+1 and value['aggregate_CPU_seconds'] <= seconds(primary[6])+1, 'worker accounting period differs from allocation')
        require(seal['status'] == 'COMPLETE_OPAQUE_IO_ONLY' and seal['scope_id'] == c['scope_id'] and seal['contract_sha256'] == c['_sha256'] and seal['authorization_sha256'] == state['authorization_sha256'] and seal['allocation'] == allocation and seal['source_files'] == c['source_files'], 'complete execution seal identity differs')
        require(value.get('status') == 'OPAQUE_IO_COMPLETE_NO_SCIENTIFIC_SCALE_ADMISSION' and value.get('purpose') == PURPOSE and value.get('cache_state') == 'UNKNOWN', 'opaque worker completion required')
        require(value.get('source_files') == c['source_files'] and value.get('new_model_fits') == value.get('new_predictions') == value.get('numerical_arrays_deserialized') == 0 and value.get('scientific_scale_admitted') is False, 'no numerical/scientific work permitted')
        require(allocation['node'] == c['node'] and allocation['user'] == 'jaguir26' and allocation['cpus_per_task'] == 1 and allocation['memory_MiB'] == 4096 and allocation['array_task_count'] == c['max_tasks'] and len(allocation['affinity']) == 1, 'actual allocation differs')
        require(0 <= value['aggregate_CPU_seconds'] <= 100 and 0 < value['elapsed_seconds'] <= 90 and value['peak_RSS_KiB'] <= 4096*1024, 'worker resource violation')
        io = value['io']; task = c['tasks'][i]
        floor = value['aggregate_scratch_floor']; require(floor['all_task_bytes'] == sum(v['bytes'] for t in c['tasks'] for v in t['files'].values())
            and floor['required_free_bytes'] == 2*floor['all_task_bytes']+1024**3 and floor['observed_free_bytes'] >= floor['required_free_bytes'], 'aggregate scratch floor proof required')
        require(value['study'] == task['study'] and io['files'] == len(task['files']) and io['total_bytes'] == sum(v['bytes'] for v in task['files'].values()) and io['source_immutable'] is True and io['scratch_cleanup'] == 'OWNED_TREE_REMOVED' and io['cache_state'] == 'UNKNOWN', 'complete unchanged opaque input proof required')
        require(set(io['source_fingerprints']) == set(task['files']), 'complete source fingerprints required')
        for name, record in task['files'].items():
            require(all(io['source_fingerprints'][name][k] == record[k] for k in ('sha256', 'bytes')), 'opaque source member differs')
        require([v['name'] for v in io['phases']] == ['source_hash', 'copy_to_scratch', 'scratch_hash'], 'complete I/O phases required')
        for phase in io['phases']:
            require(0 <= phase['CPU'] <= phase['wall']+1 and 0 <= phase['wall'] <= 90 and phase['started_epoch'] <= phase['ended_epoch'] and phase['details']['files'] == len(task['files']) and phase['details']['bytes'] == io['total_bytes'], 'finite whole phase accounting required')
            require(value['started_epoch'] <= phase['started_epoch'] <= phase['ended_epoch'] <= value['ended_epoch'], 'phase outside worker period')
        results.append(value)
    return results


def finish(b, a, c, site):
    state = b.snapshot(); output = physical(a['output_root'])
    if 'job_id' not in state:
        candidates = remote(b, site, ['squeue', '-h', '-u', site['user'], '--name='+c['scope_id'], '-o', '%A|%j'])
        found = {v.split('|')[0] for v in candidates.splitlines() if len(v.split('|')) == 2 and v.split('|')[1] == c['scope_id']}
        require(len(found) == 1 and next(iter(found)).isdigit(), 'ambiguous submission cannot be identified; no resubmit')
        jid = found.pop(); b.update(lambda s: s.update(job_id=jid, recovered_known_held_submission=True)); state = b.snapshot()
    jid = state['job_id']
    if state['state'] != 'SUBMITTED':
        info = remote(b, site, ['scontrol', 'show', 'job', jid, '-o'])
        states = owned_job(info, c, jid)
        if all(value == 'PENDING' for value in states):
            remote(b, site, ['scancel', jid]); b.update(lambda s: s.update(pending_cancel_requested=True))
        else:
            require(state.get('authorization_sha256') and all(value in {'RUNNING', 'COMPLETING', 'COMPLETED', 'FAILED', 'CANCELLED', 'TIMEOUT', 'OUT_OF_MEMORY', 'NODE_FAIL', 'PENDING'} for value in states), 'ambiguous release needs known exact job authority before tracking')
    require(not (output/'incoming').exists() and not (output/'published').exists(), 'new collection paths required')
    # One priced lifetime, at most two checks, >=300seconds between calls.
    wait_until = state.get('released_epoch', state.get('submitted_epoch', time.time()))+305
    receipt = None
    for number in range(2):
        while time.time() < wait_until: time.sleep(min(1, wait_until-time.time()))
        own = remote(b, site, ['squeue', '-h', '-u', site['user'], '-o', '%i|%T|%R'])
        raw_text = remote(b, site, ['env', 'TZ=UTC', 'sacct', '-nP', '--units=K', '-j', jid,
            '--format=JobID,JobIDRaw,State%30,ExitCode,ElapsedRaw,AllocCPUS,TotalCPU,MaxRSS,NodeList,Start,End'])
        parsed = accounting(raw_text, jid, c['max_tasks'])
        receipt = dict(checked_epoch=time.time(), own_queue=own, raw_accounting=raw_text, accounting=parsed)
        put(output/('status_'+str(number+1)+'.json'), receipt)
        if parsed['terminal'] and not own.strip(): break
        if number == 0 and own.strip() and all('PENDING' in v for v in own.splitlines()):
            info = remote(b, site, ['scontrol', 'show', 'job', jid, '-o'])
            owned_pending(info, c, jid)
            remote(b, site, ['scancel', jid])
        wait_until = receipt['checked_epoch']+301
    require(receipt['accounting']['terminal'] and not receipt['own_queue'].strip(), 'terminal/drained accounting required; no implicit third poll')
    incoming = output/'incoming'; incoming.mkdir()
    transfer(b, site, site['user']+'@'+site['host']+':'+c['remote_root']+'/', str(incoming)+'/')
    require(time.time()-receipt['checked_epoch'] < 300, 'fresh exact accounting required')
    values = verify_collection(incoming, c, b.snapshot(), receipt['accounting']) if receipt['accounting']['complete'] else []
    accepted = len(values) == c['max_tasks'] and receipt['accounting']['complete']
    result = dict(status='COLLECTED_OPAQUE_IO_PROOF' if accepted else 'FAILED_RECONCILED',
        accepted=accepted, scientific_scale_admitted=False, numerical_work=False,
        task_count=c['max_tasks'], job_id=jid, contract_sha256=c['_sha256'], accounting=receipt)
    if accepted:
        physical_cores = {(v['allocation']['node'], v['allocation']['boot_id'], v['allocation']['physical_core']['physical_package_id'], v['allocation']['physical_core']['core_id']) for v in values}
        intervals = [(v['io']['phases'][0]['started_epoch'], v['io']['phases'][0]['ended_epoch']) for v in values]
        overlap = min(v[1] for v in intervals)-max(v[0] for v in intervals)
        result.update(distinct_physical_cores=len(physical_cores), common_source_hash_overlap_seconds=max(0, overlap),
            parallel_opaque_IO_qualified=len(physical_cores) == c['max_tasks'] and overlap > 0,
            scientific_memory_and_capacity_proven=False, cache_state='UNKNOWN')
    put(incoming/'collection.json', result)
    temporary = output/'.published.partial'; shutil.copytree(incoming, temporary)
    if accepted: verify_collection(temporary, c, b.snapshot(), receipt['accounting'], collection_receipt=result)
    temporary.rename(output/'published')
    b.update(lambda s: s.update(state=result['status'], publication=str(output/'published'), accepted=accepted))
    return result


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('--authority', required=True); p.add_argument('--authority-sha256', required=True)
    p.add_argument('--stage', choices=['stage', 'submit', 'finish'], required=True); args = p.parse_args(argv)
    require(os.sched_getaffinity(0) == {31} and sys.dont_write_bytecode, 'administrative CPU31/-B required')
    resource.setrlimit(resource.RLIMIT_CPU, (8, 8)); resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    pointer = dict(path=args.authority, sha256=args.authority_sha256); a, c, site = validate_authority(pointer)
    c['_sha256'] = a['contract']['sha256']; output = physical(a['output_root'])
    if args.stage == 'stage': output.mkdir(exist_ok=False)
    require(output.is_dir(), 'prior explicit stage output required')
    remaining = min(900 if args.stage == 'finish' else 180, a['expires_epoch']-time.time()); require(remaining > 0, 'original scope expired')
    signal.signal(signal.SIGALRM, lambda *unused: (_ for _ in ()).throw(TimeoutError('finite qualification stage wall/calendar')))
    signal.setitimer(signal.ITIMER_REAL, remaining)
    budget = Budget(a, pointer, c); budget.begin(args.stage); started = time.monotonic(); error = None; result = None
    try:
        result = globals()[args.stage](budget, a, c, site)
    except BaseException as exc:
        error = dict(type=type(exc).__name__, message=str(exc))
    finally:
        measured = cpu()
        if measured > 8 or time.time() >= a['expires_epoch']: error = dict(type='LimitExceeded', message='retained parent/calendar cap exceeded', earlier_error=error)
        budget.update(lambda s: s['actions'][args.stage].update(status='FAILED_RETAINED' if error else 'COMPLETE', CPU=measured, wall=time.monotonic()-started, error=error))
        put(output/(args.stage+'_RESULT.json'), dict(status='FAILED_RETAINED' if error else 'COMPLETE', error=error, result=result, CPU=measured, wall=time.monotonic()-started, authority=pointer, no_refund=True))
    if error: raise ValueError(error['message'])
    print(json.dumps(pin(output/(args.stage+'_RESULT.json')), sort_keys=True))


if __name__ == '__main__':
    main()
