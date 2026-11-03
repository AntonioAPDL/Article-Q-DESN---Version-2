"""Independent metadata-only peer for the exact W191 unallocated failure tail.

This program never submits/cancels jobs, runs native commands, or opens target
data. Its one-shot recommendation permits only an exactly witnessed own marker
and empty lock to be removed by the separately reviewed producer.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import resource
import signal
import stat
import time

ROLE = 'ZERO_UPDATE_BRIDGE'
NODE = 'node-13'
COMMIT = '91a0423d5baab068e55c19b9e62e2fb5f13047bc'
TRACKERS = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers')
W191 = TRACKERS/'worktrees/pricefm_r191_independent_watch_peer_20261031'
SOURCE = W191/'application/scripts/pricefm/pricefm_hb'
H_SHA = '7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1'
PUBLICATION = dict(path=str(TRACKERS/'pricefm_r165_headroom_execution_20261029_1526PDT/continuation_execution_20261031_2022PDT/independent_startup_peer/SOURCE_PUBLICATION.json'),sha256='9c4dbc62dcef754637879e249e8361630f0923fd3a223883347fa8434061758f')
SOURCE_REVIEW = dict(path=str(TRACKERS/'pricefm_r165_headroom_execution_20261029_1526PDT/continuation_execution_20261031_2022PDT/independent_startup_peer/independent_review/REVIEW.json'),sha256='4e6f84ba807a9d828de9c56382b1a1ce9897dab99d99cd782c1a536c8e9a0f45')
ALLOCATIONS = dict(query_local4=4,query_remote4=4,independent_review4=4,
                   drain_local4=4,drain_remote4=4,preparation4=4,closeout4=4)
FIELDS = 'JobIDRaw,JobName%128,User,UID,Account,Partition,State,ExitCode,TotalCPU,ElapsedRaw,AllocCPUS,ReqCPUS,Start,End,NodeList'
OBSERVATIONS = {'ready','release','return','marker','lock'}
TERMINAL = {'COMPLETED','FAILED','CANCELLED','TIMEOUT','OUT_OF_MEMORY','NODE_FAIL','PREEMPTED','BOOT_FAIL'}
READS = {}


def check(value, message):
    if not value:
        raise ValueError(message)


def integer(value, expected=None):
    return type(value) is int and (expected is None or value == expected)


def finite(value, message):
    check(type(value) in (int,float) and math.isfinite(value), message)
    return value


def exact_keys(value, names, message):
    check(type(value) is dict and set(value) == set(names), message)


def strict(raw):
    def pairs(items):
        out = {}
        for key,value in items:
            check(key not in out, 'duplicate metadata key')
            out[key] = value
        return out
    def bad(value):
        raise ValueError('nonfinite metadata '+value)
    def real(value):
        return finite(float(value),'nonfinite metadata exponent')
    return json.loads(raw,object_pairs_hook=pairs,parse_constant=bad,parse_float=real)


def bytes_at(path, sha=None, code=False):
    p = Path(path)
    check(p.is_absolute() and '..' not in p.parts and not any(x.is_symlink() for x in (p,*p.parents)),
          'physical absolute metadata/source path')
    check('target_cache' not in p.parts and (p.suffix in {'.py','.R'} if code else p.suffix in {'.json','.stdout','.stderr'}),
          'metadata/source only; target inputs are never opened')
    fd = os.open(p,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    with os.fdopen(fd,'rb') as f:
        a = os.fstat(f.fileno())
        check(stat.S_ISREG(a.st_mode) and a.st_nlink == 1 and a.st_uid in {0,os.getuid()}
              and a.st_size <= 32*1024**2, 'bounded owned regular single-link input')
        data = f.read(32*1024**2+1)
        b = os.fstat(f.fileno())
    identity = lambda x:(x.st_dev,x.st_ino,x.st_size,x.st_mtime_ns,x.st_ctime_ns)
    digest = hashlib.sha256(data).hexdigest()
    check(identity(a)==identity(b)==identity(p.stat()) and len(data)==a.st_size and (sha is None or sha==digest),
          'stable exact SHA-bound input')
    READS[str(p)] = dict(path=str(p),sha256=digest,bytes=len(data))
    return data


def pin(path, code=False):
    return dict(path=str(Path(path)),sha256=hashlib.sha256(bytes_at(path,code=code)).hexdigest())


def check_pin(value):
    exact_keys(value,{'path','sha256'},'closed SHA pin')
    check(type(value['path']) is str and value['path'].startswith('/') and '..' not in PurePosixPath(value['path']).parts
          and type(value['sha256']) is str and re.fullmatch('[0-9a-f]{64}',value['sha256']), 'absolute strict SHA pin')
    return value


def linked(value, code=False):
    check_pin(value)
    data = bytes_at(value['path'],value['sha256'],code=code)
    return data if code else strict(data)


def local(path):
    return strict(bytes_at(path))


def write_new(path, value):
    p = Path(path)
    check(p.parent.resolve(strict=True)==p.parent and not p.is_symlink(),'physical create-only output')
    fd = os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'w') as f:
        json.dump(value,f,sort_keys=True,indent=2,allow_nan=False)
        f.write('\n');f.flush();os.fsync(f.fileno())


def guard(value, cpu, wall):
    check(integer(value.get('returncode'),0) and integer(value.get('command_returncode'),0)
          and integer(value.get('CPU_limit'),cpu) and value.get('cap_reason') is None,
          'actual successful unchanged original guard and cap')
    check(0<=finite(value.get('aggregate_CPU_seconds'),'finite guard CPU')<cpu
          and 0<=finite(value.get('complete_lifecycle_wall_seconds'),'finite guard wall')<=wall,
          'complete original guard accounting within paid limits')
    check(value.get('guardian_forced_monitor_stop') is False and all(value.get(k) is True for k in
          ('all_owned_descendants_reaped','independent_guardian','kernel_escape_filter','orphan_subreaper',
           'guardian_included_in_CPU','inherited_waited_history_included_once')),
          'actual original guardian and complete owned-child reaping')


def native(value, argv, code, message):
    exact_keys(value,{'argv','returncode','stdout','stderr'},message+' schema')
    check(value['argv']==argv and integer(value['returncode'],code) and type(value['stdout']) is str
          and value['stderr']=='', message)
    return value['stdout']


def accounting(value, job_id, scope_id, uid):
    check(type(job_id) is str and re.fullmatch('[1-9][0-9]*',job_id) and type(scope_id) is str
          and re.fullmatch('[A-Za-z0-9_-]{1,128}',scope_id) and integer(uid) and uid==os.getuid(),
          'exact current W191 role ID and owner')
    text = native(value,['sacct','-j',job_id,'-n','-P','--format='+FIELDS],0,'exact native SACCT15')
    rows = [line for line in text.splitlines() if line.strip()]
    check(len(rows)==1,'one primary unallocated row, no steps or foreign jobs')
    row = rows[0].split('|')
    if len(row)==16 and row[-1]=='':
        row.pop()
    check(len(row)==15,'exact SACCT15 fields')
    jid,name,user,owner,account,partition,state,exit_code,cpu,elapsed,allocated,requested,start,end,node = row
    check(jid==job_id and name==scope_id and user=='jaguir26' and owner==str(uid)
          and account==partition=='128x24' and state in {'CANCELLED','CANCELLED by '+str(uid)}
          and exit_code=='0:0' and cpu in {'00:00:00','00:00.000','00:00:00.000'}
          and elapsed=='0' and allocated=='0' and requested=='1' and start in {'None','Unknown','N/A'}
          and node in {'None','None assigned','(null)','Unknown','N/A'} and end not in {'','None','Unknown','N/A'},
          'exact own-UID cancelled/unallocated CPU0 elapsed0 no-start/no-node accounting')
    return dict(job_id=jid,state=state,normalized_state='CANCELLED',owner_uid=uid,AllocCPUS=0,ReqCPUS=1,
                TotalCPU_seconds=0,ElapsedRaw=0,never_allocated=True,raw_primary_counted_once=True)


def stat_identity(value, lock, marker):
    fmt='%u|%d|%i|%s|%h|%f|%n\n'
    text=native(value,['stat','--printf='+fmt,'--',lock,marker],0,'native no-follow exact claim identity')
    lines=text.splitlines();check(len(lines)==2,'exactly two claim identity lines')
    out={}
    for label,path,line in zip(('lock','marker'),(lock,marker),lines):
        fields=line.split('|')
        check(len(fields)==7 and fields[-1]==path and all(re.fullmatch('[0-9]+',x) for x in fields[:5])
              and re.fullmatch('[0-9a-fA-F]+',fields[5]),'exact path and typed native stat fields')
        uid,dev,ino,size,nlink=map(int,fields[:5]);mode=int(fields[5],16)
        check(uid==os.getuid() and dev>=0 and ino>0 and size>=0 and nlink>=1,'real owned native claim')
        check((stat.S_ISDIR(mode) if label=='lock' else stat.S_ISREG(mode) and size==0 and nlink==1),
              'directory and zero-byte single-link regular marker; symlinks refused')
        out[label]=dict(path=path,uid=uid,device=dev,inode=ino,bytes=size,nlink=nlink,mode=mode)
    return out


def published_w191(config):
    check(config['publication']==PUBLICATION and config['source_review']==SOURCE_REVIEW
          and config['source_dir']==str(SOURCE),'exact original W191 source identities')
    publication=linked(PUBLICATION);review=linked(SOURCE_REVIEW)
    check(publication['status']=='PASS_FROZEN525_NUMERICAL_BATCH_SOURCE_PUBLICATION'
          and publication['commit']==review['source_commit']==COMMIT
          and review['status']=='PASS_REVIEWED_FROZEN525_NUMERICAL_BATCH_SOURCE'
          and review['actual_source_admission'] is True and not review['errors'],
          'actual independently reviewed published W191')
    for key,count in (('source_files',21),('administrative_source_files',3),('scientific_source_files',5)):
        mapping=publication[key]
        check(type(mapping) is dict and len(mapping)==count and mapping==review[key],'untouched W19121/admin3/math5 maps')
        for name,sha in mapping.items():
            source=W191/name if '/' in name else SOURCE/name
            bytes_at(source,sha,code=True)
    check(publication['source_files']['startup_helper.py'] and pin(SOURCE/'profile_supervisor.py',code=True)['sha256']==H_SHA,
          'original H unchanged')
    return publication


def failure_basis(scope, config, job, packet, publication):
    evidence=scope['failure_evidence'];kind=evidence.get('kind')
    family_sha=publication['source_files']['numerical_batch.py']
    if kind=='W191_STARTUP_CANCELLED_NO_RELEASE':
        exact_keys(evidence,{'kind','failure_receipt','role_failed','driver_intent','cancel_guard','cancel_started'},
                   'closed W191 startup failure evidence')
        failed=linked(evidence['failure_receipt']);spent=linked(evidence['role_failed']);intent=linked(evidence['driver_intent'])
        check(failed['status']=='FAILED_STARTUP_EXACT_CANCEL_REQUESTED_NOT_TERMINAL_PROOF'
              and failed.get('no_release') is True and failed.get('no_retry') is True
              and failed.get('all_reserved_fees_retained') is True and failed.get('cancel_error') is None
              and failed.get('cancel_guard')==evidence['cancel_guard'], 'actual W191 cancellation request, never terminal proof alone')
        check(spent['status']=='FAILED_ROLE_SPENT_DRAIN_OR_DIAGNOSIS_ONLY'
              and spent.get('failed_startup')==evidence['failure_receipt'] and spent.get('old_fees_retained') is True,
              'actual immutable spent W191 role')
        check(intent['status']=='STARTED_BOUNDED_NUMERICAL_CRITICAL_LIFECYCLE_NOT_SUCCESS'
              and intent.get('config')==scope['config'] and intent.get('old_fees_retained') is True
              and intent.get('no_retry') is True
              and intent['driver']==dict(path=str(SOURCE/'numerical_critical_driver.py'),sha256=publication['administrative_source_files']['numerical_critical_driver.py'])
              and intent['peer_program']==dict(path=str(SOURCE/'numerical_independent_peer.py'),sha256=publication['administrative_source_files']['numerical_independent_peer.py']),
              'actual exact source-bound critical driver intent')
        authority=linked(intent['authority'])
        check(authority['status']=='ROOT_AUTHORIZED_FROZEN525_NUMERICAL_CRITICAL_LIFECYCLE'
              and authority.get('config')==scope['config'] and authority.get('scope')==scope['parent_scope']
              and authority.get('role')==ROLE and authority.get('driver_source')==intent['driver']
              and authority.get('peer_program')==intent['peer_program'] and authority.get('max_calls')==1
              and authority.get('automatic_retry') is False,'exact one-shot current driver authority')
        start=linked(evidence['cancel_started']);g=linked(evidence['cancel_guard']);guard(g,4,45)
        check(start['status']=='ACTION_STARTED_NOT_SUCCESS' and start['action']=='cancel'
              and start['role']==ROLE and start['source_sha256']==family_sha
              and start['limits']==dict(local_CPU=4,remote_unknown_fee=4,wall=45,maximum_calls=1)
              and g['session_id']==start['command_pid'] and g['leader_start_ticks']==start['command_birth_ticks'],
              'same-source original H4 cancellation action journal')
        pending_path=Path(evidence['cancel_started']['path'])
        pending=local(pending_path.with_name(pending_path.name.replace('.started.','.pending.')))
        check(pending['status']=='INTERNAL_ACTION_RESULT_NOT_GUARD_SUCCESS'
              and all(pending.get(k)==v for k,v in start.items() if k!='status')
              and strict(g['stdout'])==pending['result']
              and pending['result']==dict(status='CANCEL_REQUESTED_NOT_TERMINAL_PROOF',job_id=job['job_id']),
              'exact known-job cancellation result and pending journal')
    elif kind=='FAILED_NATIVE_ACTION_DRAINED':
        exact_keys(evidence,{'kind','failed_guard','failed_started'},'closed failed native evidence')
        start=linked(evidence['failed_started']);g=linked(evidence['failed_guard'])
        limits={'ready':dict(local_CPU=6,remote_unknown_fee=6,wall=330,maximum_calls=1),
                'release':dict(local_CPU=4,remote_unknown_fee=4,wall=180,maximum_calls=1),
                'observe':dict(local_CPU=3,remote_unknown_fee=3,wall=45,maximum_calls=3),
                'collect':dict(local_CPU=6,remote_unknown_fee=6,wall=300,maximum_calls=1),
                'accept':dict(local_CPU=5,remote_unknown_fee=5,wall=180,maximum_calls=1),
                'cancel':dict(local_CPU=4,remote_unknown_fee=4,wall=45,maximum_calls=1),
                'reconcile':dict(local_CPU=3,wall=120)}
        check(start['status']=='ACTION_STARTED_NOT_SUCCESS' and start['role']==ROLE and start['source_sha256']==family_sha
              and start['action'] in limits and start['limits']==limits[start['action']], 'exact submitted-action failure; ambiguous submit blocked')
        check(integer(g.get('returncode')) and g['returncode']!=0 and g.get('all_owned_descendants_reaped') is True
              and g.get('independent_guardian') is True and g.get('guardian_forced_monitor_stop') is False
              and g.get('guardian_included_in_CPU') is True and g.get('inherited_waited_history_included_once') is True,
              'failed original guard fully reaped; never infer action success')
        witness=g.get('owned_stop_witness')
        if witness is not None:
            check(witness.get('schema')=='r164_owned_stop_failure_witness_v1' and witness.get('uid')==os.getuid()
                  and witness.get('monitor_affinity')==[31] and witness.get('states_are_not_accepted_for_accounting') is True,
                  'actual D/stop witness does not prove stopped accounting')
        sid=g.get('session_id',witness.get('session_id') if witness else None)
        birth=g.get('leader_start_ticks',witness.get('leader_start_ticks') if witness else None)
        check(integer(sid) and integer(birth) and sid==start['command_pid'] and birth==start['command_birth_ticks'],
              'failed action PID and birth match actual journal')
        if 'CPU_limit' in g:
            check(integer(g['CPU_limit'],start['limits']['local_CPU']),'failed original cap unchanged')
    else:
        raise ValueError('unsupported failure basis; no original H3 fallback')


def expected_paths(config, packet, scope_id):
    remote=packet['remote_root'];lock=config['remote_namespace']+'/qualification.lock'
    return dict(ready=remote+'/READY.json',release=remote+'/release/RELEASE.json',
                return_=remote+'/result/RETURN_MANIFEST.json',lock=lock,marker=lock+'/OWNED_'+scope_id)


def validate_context(scope_path, now=None):
    tpin=pin(scope_path);scope=linked(tpin);config=linked(scope['config']);parent=linked(scope['parent_scope'])
    now=time.time() if now is None else finite(now,'finite review time')
    check(scope['schema']=='legacy_w191_unallocated_tail_scope_v1'
          and scope['status']=='PROSPECTIVE_EXACT_UNALLOCATED_W191_ROLE_DRAIN_SCOPE'
          and scope['role']==config['role']==ROLE and scope['execution_node']==config['node']==NODE
          and config['schema']=='r182_numerical_batch_config_v1' and scope['parent_scope']==config['scope'],
          'exact compatible W191 role/node/parent; no newCORE route')
    canonical_root=Path(parent['allowed_metadata_output_root'])
    check(str(canonical_root).startswith('/home/jaguir26/.local/state/pricefm/r180_native_4503eef91eaa/Legacy_NODE13_')
          and canonical_root.resolve(strict=True)==canonical_root and canonical_root.is_dir()
          and canonical_root.stat().st_uid==os.getuid() and canonical_root.stat().st_mode&0o077==0
          and Path(config['registry'])==canonical_root/'canonical_registry'
          and re.fullmatch('/mnt/beegfs/home/jaguir26/pricefm_r182_LEGACY_[A-Za-z0-9_]{1,64}_[0-9a-f]{32}',config['remote_namespace']),
          'one actual private fresh legacy canonical root and closed remote namespace')
    check(parent['status']=='PROSPECTIVE_FRESH_FROZEN525_NUMERICAL_JOB_SCOPE' and parent['roles']==[ROLE]
          and all(integer(parent.get(k),v) for k,v in dict(maximum_jobs=1,max_concurrent_jobs=1,compute_CPU_reservation=600,
              wall_seconds=1200,memory_MiB=8192,threads=1,cpus_per_task=1).items())
          and parent.get('automatic_retry') is False and parent.get('requeue') is False
          and parent['issued_epoch']<=scope['issued_epoch']<=now<scope['expires_epoch']<=parent['expires_epoch'],
          'prospective fresh original single-role limits and full fee')
    check(scope['allocations']==ALLOCATIONS and all(integer(v,4) for v in scope['allocations'].values())
          and integer(scope['total_administrative_CPU'],28)
          and all(integer(scope[k],1) for k in ('maximum_query_calls','maximum_drain_calls','maximum_peer_calls')),
          'whole separate28 includes remote uncertainty, no old H3 credit')
    budget=linked(scope['parent_budget'])
    check(budget['schema']=='legacy_w191_unallocated_failure_budget_v1'
          and budget['status']=='PROSPECTIVE_W191_COMPATIBLE_SEPARATE_H4_FAILURE_TAIL_BUDGET'
          and budget['parent_scope']==scope['parent_scope'] and budget['role']==ROLE and budget['allocations']==ALLOCATIONS
          and all(integer(v,4) for v in budget['allocations'].values()) and integer(budget['total_administrative_CPU'],28)
          and all(integer(budget[k],1) for k in ('maximum_query_calls','maximum_drain_calls','maximum_peer_calls'))
          and budget['expires_epoch']==parent['expires_epoch'],'exact prospective scope-bound tail budget')
    ledger=linked(budget['funding_ledger'])
    rows=[x for x in ledger['scopes'] if x.get('scope')==scope['parent_scope']]
    extras=parent['extra_setup_forecast_tail']
    exact_keys(extras,{'separate_preparation_CPU','scheduler_evidence_CPU','compatible_failure_tail_CPU'},'closed complete extra price')
    check(all(integer(v) and v>0 for v in extras.values()) and extras['compatible_failure_tail_CPU']==28
          and integer(parent['new_separate_administrative_CPU_reservation'],234)
          and parent['complete_administrative_CPU_reservation']==234+sum(extras.values()),'exact normal234 plus separately priced support and tail')
    check(len(rows)==1 and integer(parent['complete_administrative_CPU_reservation'])
          and rows[0]['administrative_CPU_reservation']==parent['complete_administrative_CPU_reservation']>=262
          and integer(rows[0]['compute_CPU_reservation'],600), 'full exact new runtime/tail funding row')
    before=linked(ledger['previous'])
    same=lambda x,y:json.dumps(x,sort_keys=True,allow_nan=False)==json.dumps(y,sort_keys=True,allow_nan=False)
    check(same(ledger['scopes'],before['scopes']+[rows[0]])
          and same(ledger['compute_roles'],before['compute_roles']+[dict(canonical_home_root=str(canonical_root),
              reservation=600,scope=scope['parent_scope'])]),'exact append preserves every prior typed fee and compute role')
    for key,delta in (('total_administrative_reservation',parent['complete_administrative_CPU_reservation']),
                      ('total_new_administrative_reservation',parent['complete_administrative_CPU_reservation']),
                      ('total_qualification_compute_reservation',600),('total_new_qualification_compute_reservation',600)):
        check(integer(before.get(key)) and integer(ledger.get(key)) and ledger[key]==before[key]+delta,
              'whole exact new funding counter, no old fee credit')
    publication=published_w191(config)
    canonical=linked(config['canonical_authority'])
    check(canonical['status']=='ROOT_AUTHORIZED_CANONICAL_FROZEN525_NUMERICAL_CONFIG'
          and canonical['binding']=={k:v for k,v in config.items() if k!='canonical_authority'}
          and parent['issued_epoch']<=canonical['issued_epoch']<=now<canonical['expires_epoch']<=parent['expires_epoch'],
          'exact complete current canonical authority, no old config grant')
    own=pin(__file__,code=True);approval=linked(scope['source_approval'])
    check(scope['query_source']==scope['drain_source'] and scope['peer_source']==own
          and approval['status']=='PASS_REVIEWED_W191_COMPATIBLE_SEPARATE_H4_FAILURE_PROTOCOL'
          and approval['source_publication']==PUBLICATION and approval['source_review']==SOURCE_REVIEW
          and approval['producer']==scope['query_source'] and approval['independent_peer']==own
          and approval['role']==ROLE and approval['node']==NODE and approval.get('original_H3_unchanged') is True
          and integer(approval.get('query_local_CPU'),4) and integer(approval.get('drain_local_CPU'),4)
          and approval.get('remote_CPU_uncertainty_included') is True and integer(approval.get('total_administrative_CPU'),28)
          and approval.get('automatic_retry') is False,'actual independently reviewed compatible producer and independent peer source')
    linked(scope['query_source'],code=True)
    support=linked(scope['support_publication'])
    check(support.get('status')=='PASS_PUBLISHED_LEGACY_NODE13_SUPPORT_SOURCE'
          and re.fullmatch('[0-9a-f]{40}',support.get('commit','')) and support.get('remote_readback')==support.get('commit')
          and type(support.get('branch')) is str and support['branch']!='main'
          and support.get('independent_review')==approval['support_source_review']
          and support['source_files'].get(Path(scope['query_source']['path']).name)==scope['query_source']['sha256']
          and support['source_files'].get(Path(own['path']).name)==own['sha256'],
          'actual separate support source publication; no fake W191 map replacement')
    support_review=linked(support['independent_review'])
    check(support_review.get('status')=='PASS_REVIEWED_LEGACY_NODE13_SUPPORT_SOURCE'
          and support_review.get('source_files')==support['source_files'],
          'actual whole independent support review binds the published source map')
    job=linked(scope['job']);packet=linked(scope['packet']);root=Path(config['registry'])/ROLE
    check(scope['job']['path'] in {str(root/'JOB.json'),str(root/'RECONCILED_JOB.json')}
          and scope['packet']==pin(root/'PACKET.json') and job['job_id']==scope['job_id']
          and job['scope_id']==packet['scope_id']==scope['scope_id'] and packet['role']==ROLE
          and packet['remote_root']==config['remote_namespace']+'/'+packet['scope_id']
          and packet['source_publication']==PUBLICATION and packet['source_review']==SOURCE_REVIEW,
          'actual unique known submitted W191 job, packet and namespace')
    expected_sources={name:dict(path=packet['remote_root']+'/package/pricefm_hb/'+name,sha256=sha)
                      for name,sha in publication['source_files'].items()}
    check(packet.get('sources')==expected_sources,'exact staged packet W191 compute-source map and paths')
    argv=['sbatch','--parsable','--export=NONE','--propagate=NONE','--mail-type=NONE',
          '--account=128x24','--partition=128x24','--qos=normal','--nodelist=node-13','--nodes=1','--ntasks=1',
          '--cpus-per-task=1','--hint=nomultithread','--mem=8192M','--time=00:20:00','--no-requeue',
          '--job-name='+job['scope_id'],'--output='+packet['remote_root']+'/slurm-%j.out',
          '--error='+packet['remote_root']+'/slurm-%j.err',packet['remote_root']+'/job.sbatch']
    check(native(job['submission'],argv,0,'actual exact original native sbatch result')==job['job_id']+'\n',
          'same known job returned by exact resource/node-bound submission')
    check(re.fullmatch('[1-9][0-9]*',job['job_id']) and re.fullmatch('r182-bridge-[0-9a-f]{20}',job['scope_id']),
          'closed exact known job and nonce')
    before=linked(config['known_jobs_registry']);prior=before.get('jobs')
    check(type(prior) is list and len(prior)>=17 and len({x['job_id'] for x in prior})==len(prior)
          and all(x.get('state') in TERMINAL for x in prior) and job['job_id'] not in {x['job_id'] for x in prior},
          'complete historical terminal registry and genuinely new job')
    current=linked(scope['known_jobs_registry']);jobs=current.get('jobs')
    check(type(jobs) is list and len(jobs)==len(prior)+1 and jobs[:-1]==prior
          and jobs[-1]['job_id']==job['job_id'] and jobs[-1]['job_name']==job['scope_id'],
          'current full registry preserves every prior job and appends the exact new identity')
    failure=scope['failure_evidence']
    if failure.get('kind')=='W191_STARTUP_CANCELLED_NO_RELEASE':
        check(jobs[-1]['state']=='CANCEL_REQUESTED_AWAIT_QUERY' and jobs[-1]['cancel_guard']==failure['cancel_guard'],
              'current registry binds actual cancellation request, never pretended terminal state')
    else:
        check(failure.get('kind')=='FAILED_NATIVE_ACTION_DRAINED' and jobs[-1]['state']=='FAILED_NATIVE_ACTION_AWAIT_QUERY'
              and jobs[-1]['failed_guard']==failure['failed_guard'], 'current registry binds the actual failed native action')
    failure_basis(scope,config,job,packet,publication)
    return tpin,scope,config,parent,job,packet,publication


def review_query(result_path, guard_path, tail_scope_path, output_path, now=None):
    now=time.time() if now is None else now
    tpin,scope,config,parent,job,packet,publication=validate_context(tail_scope_path,now)
    value=local(result_path);g=local(guard_path);guard(g,4,120)
    fields={'schema','status','config','tail_scope','parent_scope','role','job','packet','job_id','scope_id',
            'execution_node','source','command_pid','command_birth_ticks','observed_epoch','raw_accounting','raw_queue',
            'observations','accounting_state'}
    exact_keys(value,fields|({'claim_identity'} if 'claim_identity' in value else set()),'closed exact W191 query result')
    check(value['schema']=='legacy_w191_unallocated_query_v1' and value['status']=='OBSERVED_EXACT_UNALLOCATED_JOB_AND_OWN_CLAIM'
          and value['tail_scope']==tpin and value['config']==scope['config'] and value['parent_scope']==scope['parent_scope']
          and all(value[k]==scope[k] for k in ('role','job','packet','job_id','scope_id','execution_node'))
          and value['source']==scope['query_source'] and integer(value['command_pid']) and value['command_pid']>0
          and integer(value['command_birth_ticks']) and value['command_birth_ticks']>0
          and g['session_id']==value['command_pid'] and g['leader_start_ticks']==value['command_birth_ticks']
          and strict(g['stdout'])==value and scope['issued_epoch']<=finite(value['observed_epoch'],'finite observation')<=now
          and 0<=now-value['observed_epoch']<=120,'actual current H4 query stdout/source/PID/birth/known job binding')
    out=Path(scope['allowed_output_root']);target=Path(output_path)
    check(out.resolve(strict=True)==out and out.is_dir() and out.stat().st_uid==os.getuid() and out.stat().st_mode&0o077==0
          and target==out/'QUERY_REVIEW.json' and Path(result_path)==out/'QUERY_RESULT.json' and Path(guard_path)==out/'QUERY_GUARD.json',
          'one actual private canonical output root')
    intent=local(out/'QUERY_INTENT.json')
    ident={k:value[k] for k in ('config','tail_scope','parent_scope','role','job','packet','job_id','scope_id','execution_node',
                              'source','command_pid','command_birth_ticks')}
    exact_keys(intent,set(ident)|{'status','issued_epoch'},'closed durable one-shot query intent')
    check(intent['status']=='ONE_SHOT_QUERY_STARTED_NO_REPLAY' and all(intent[k]==v for k,v in ident.items())
          and scope['issued_epoch']<=finite(intent['issued_epoch'],'finite query intent')<=value['observed_epoch'],
          'durable actual query intent before raw observations')
    state=accounting(linked(value['raw_accounting']),job['job_id'],packet['scope_id'],os.getuid())
    check(value['accounting_state']==dict(raw_state=state['state'],normalized_state='CANCELLED',owner_uid=os.getuid())
          and type(value['accounting_state']['owner_uid']) is int,'typed state metadata equals preserved raw state')
    queue=linked(value['raw_queue']);exact_keys(queue,{'argv','returncode','stdout','stderr'},'closed native SQUEUE')
    check(queue['argv']==['squeue','-h','-j',job['job_id'],'-o','%i|%T|%j|%u|%N'] and queue['stdout']==''
          and ((integer(queue['returncode'],0) and queue['stderr']=='') or
               (integer(queue['returncode'],1) and queue['stderr']=='slurm_load_jobs error: Invalid job id specified\n')),
          'actual queue absent under exact terminal accounting, no arbitrary-error absence')
    paths=expected_paths(config,packet,packet['scope_id']);paths['return']=paths.pop('return_')
    exact_keys(value['observations'],OBSERVATIONS,'closed five scoped absence/presence observations')
    rawrefs=[value['raw_accounting'],value['raw_queue']];presence={}
    for name in sorted(OBSERVATIONS):
        row=value['observations'][name];exact_keys(row,{'path','exists','observation'},'closed native observation')
        check(row['path']==paths[name] and type(row['exists']) is bool,'same exact owned namespace paths')
        text=native(linked(row['observation']),['test','-e',paths[name]],0 if row['exists'] else 1,'exact native existence')
        check(text=='' and (name in {'lock','marker'} or not row['exists']),'READY/release/return payload never present')
        presence[name]=row['exists'];rawrefs.append(row['observation'])
    check(presence['lock']==presence['marker'],'lock and marker must both exist or both be absent')
    identity=None
    if presence['marker']:
        check('claim_identity' in value,'present claim needs exact prospective identity')
        ci=value['claim_identity'];exact_keys(ci,{'raw_stat','lock','marker'},'closed native claim identity')
        identity=stat_identity(linked(ci['raw_stat']),paths['lock'],paths['marker'])
        check(ci['lock']==identity['lock'] and ci['marker']==identity['marker'],'typed claim identity equals raw native stat')
        rawrefs.append(ci['raw_stat'])
    else:
        check('claim_identity' not in value,'absent claim carries no invented inode evidence')
    check(len({x['path'] for x in rawrefs})==len(rawrefs),'one distinct raw receipt per paid native command')
    for ref in rawrefs:
        check_pin(ref);check(Path(ref['path']).parent==out,'all raw receipts under same paid output root')
    expected={Path(x['path']).name for x in rawrefs}|{'QUERY_INTENT.json','QUERY_RESULT.json','QUERY_GUARD.json'}
    check({x.name for x in out.glob('QUERY_*.json')}==expected,'complete exact query artifact set before review')
    result=dict(schema='legacy_w191_unallocated_query_review_v1',status='PASS_REVIEWED_EXACT_UNALLOCATED_NODE_ROLE_DRAIN',
                query_result=pin(result_path),query_guard=pin(guard_path),config=scope['config'],tail_scope=tpin,parent_scope=scope['parent_scope'],
                job=scope['job'],packet=scope['packet'],job_id=scope['job_id'],scope_id=scope['scope_id'],role=ROLE,execution_node=NODE,
                expected_lock=paths['lock'],expected_marker=paths['marker'],observed_presence=presence,claim_identity=identity,
                accounting=state,review_source=pin(__file__,code=True),source_approval=scope['source_approval'],support_publication=scope['support_publication'],
                observed_epoch=now,expires_epoch=min(scope['expires_epoch'],value['observed_epoch']+120),
                permitted_operation='REMOVE_EXACT_OWNED_ZERO_BYTE_MARKER_THEN_NONRECURSIVE_EMPTY_LOCK' if identity else 'VERIFY_TWO_EXACT_ABSENCES_ONLY',
                no_blanket_delete=True,no_numerical_success_or_runtime_admission=True,old_failed_action_fee_retained=True,
                distinct_failure_tail28_fully_retained=True,read_set=list(READS.values()))
    write_new(output_path,result)
    return result


def main():
    check(os.sched_getaffinity(0)=={31},'administrative CPU31 required')
    resource.setrlimit(resource.RLIMIT_CPU,(4,4));resource.setrlimit(resource.RLIMIT_CORE,(0,0));signal.alarm(45)
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('query-result','query-guard','tail-scope','output'):
        parser.add_argument('--'+name,required=True)
    args=parser.parse_args();out=Path(args.output)
    write_new(out.with_name('PEER_REVIEW_INTENT.json'),dict(status='EXACT_UNALLOCATED_REVIEW_STARTED_NO_REPLAY',
              source=pin(__file__,code=True),tail_scope=pin(args.tail_scope),issued_epoch=time.time()))
    result=review_query(args.query_result,args.query_guard,args.tail_scope,args.output)
    u=resource.getrusage(resource.RUSAGE_SELF)
    write_new(out.with_name('PEER_REVIEW_RECEIPT.json'),dict(status='COMPLETED_INDEPENDENT_EXACT_UNALLOCATED_REVIEW',
              output=pin(out),SELF_CPU_seconds=u.ru_utime+u.ru_stime,CPU_cap=4,wall_cap=45,all28_fees_retained=True,read_set=list(READS.values())))
    print(json.dumps(dict(status=result['status'],SELF_CPU=u.ru_utime+u.ru_stime),sort_keys=True))


if __name__=='__main__':
    main()
