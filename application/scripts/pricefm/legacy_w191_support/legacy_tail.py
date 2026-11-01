"""One-shot native-only H4 query/drain for an exact never-allocated job.

This administrative producer cannot grant scientific admission or authorize its
own drain. Both phases require a prospectively funded distinct 28 CPU tail;
drain additionally requires the actual independent query review and ROOT grant.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import resource
import shlex
import stat
import subprocess
import time

HELPER_SHA = '8833cb4af5c8e5037ad6ed9e86dbed7955a8cbbe77d97c72dd7d74ca733f882b'
SACCT_FIELDS = 'JobIDRaw,JobName%128,User,UID,Account,Partition,State,ExitCode,TotalCPU,ElapsedRaw,AllocCPUS,ReqCPUS,Start,End,NodeList'
ALLOCATIONS = dict(query_local4=4,query_remote4=4,independent_review4=4,
    drain_local4=4,drain_remote4=4,preparation4=4,closeout4=4)
NATIVE = {'sacct','squeue','test','stat','rm','rmdir'}
ORIGINAL_POST_SUBMISSION_LIMITS = {
    'ready':dict(local_CPU=6,remote_unknown_fee=6,wall=330,maximum_calls=1),
    'release':dict(local_CPU=4,remote_unknown_fee=4,wall=180,maximum_calls=1),
    'observe':dict(local_CPU=3,remote_unknown_fee=3,wall=45,maximum_calls=3),
    'collect':dict(local_CPU=6,remote_unknown_fee=6,wall=300,maximum_calls=1),
    'accept':dict(local_CPU=5,remote_unknown_fee=5,wall=180,maximum_calls=1),
    'cancel':dict(local_CPU=4,remote_unknown_fee=4,wall=45,maximum_calls=1),
    'retire_failed':dict(local_CPU=3,wall=120),
}


def helper():
    path = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r191_independent_watch_peer_20261031/application/scripts/pricefm/pricefm_hb/startup_helper.py')
    if path.is_symlink() or any(p.is_symlink() for p in path.parents):
        raise ValueError('physical frozen helper required')
    if hashlib.sha256(path.read_bytes()).hexdigest() != HELPER_SHA:
        raise ValueError('unchanged startup helper required before import')
    spec = importlib.util.spec_from_file_location('_unallocated_tail_helper',path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


h = helper()


def exact_keys(value, keys, reason):
    h.require(type(value) is dict and set(value)==set(keys), reason)


def finite(value):
    return type(value) in (int,float) and math.isfinite(value)


def outer_context():
    fields = dict(line.split(':',1) for line in Path('/proc/self/status').read_text().splitlines() if ':' in line)
    h.require(os.getpid()==os.getsid(0)==os.getpgrp() and os.sched_getaffinity(0)=={31}
        and fields['NoNewPrivs'].strip()=='1' and fields['Seccomp'].strip()=='2'
        and resource.getrlimit(resource.RLIMIT_CPU)==(4,4),
        'actual unchanged original H4 administrative31 context required')


def read_metadata(value):
    h.require(Path(value['path']).suffix=='.json','metadata JSON input only')
    return h.read(value)


def healthy_guard(value,cpu,wall):
    h.require(value.get('returncode')==0 and type(value.get('returncode')) is int
        and value.get('command_returncode')==0 and type(value.get('command_returncode')) is int
        and value.get('CPU_limit')==cpu and type(value.get('CPU_limit')) is int
        and value.get('cap_reason') is None
        and finite(value.get('aggregate_CPU_seconds')) and 0<=value['aggregate_CPU_seconds']<cpu
        and finite(value.get('complete_lifecycle_wall_seconds')) and 0<=value['complete_lifecycle_wall_seconds']<=wall
        and value.get('guardian_forced_monitor_stop') is False
        and all(value.get(k) is True for k in ('all_owned_descendants_reaped','independent_guardian',
            'kernel_escape_filter','orphan_subreaper','guardian_included_in_CPU','inherited_waited_history_included_once')),
        'actual complete original guard required')


def paths(config,packet):
    namespace=config['remote_namespace'];remote=packet['remote_root'];nonce=packet['scope_id']
    h.require(type(namespace) is str and namespace.startswith('/mnt/beegfs/home/jaguir26/pricefm_')
        and re.fullmatch(r'[A-Za-z0-9_./-]+',namespace) and '..' not in PurePosixPath(namespace).parts
        and type(nonce) is str and re.fullmatch(r'[A-Za-z0-9_-]+',nonce)
        and remote==namespace+'/'+nonce,'one exact private owned remote namespace and packet')
    lock=namespace+'/qualification.lock'
    return dict(ready=remote+'/READY.json',release=remote+'/release/RELEASE.json',
        return_=remote+'/result/RETURN_MANIFEST.json',lock=lock,marker=lock+'/OWNED_'+nonce)



W191=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r191_independent_watch_peer_20261031')
SOURCE=W191/'application/scripts/pricefm/pricefm_hb'
TRACKERS=W191.parents[1]
PUB=dict(path=str(TRACKERS/'pricefm_r165_headroom_execution_20261029_1526PDT/continuation_execution_20261031_2022PDT/independent_startup_peer/SOURCE_PUBLICATION.json'),sha256='9c4dbc62dcef754637879e249e8361630f0923fd3a223883347fa8434061758f')
REVIEW=dict(path=str(TRACKERS/'pricefm_r165_headroom_execution_20261029_1526PDT/continuation_execution_20261031_2022PDT/independent_startup_peer/independent_review/REVIEW.json'),sha256='4e6f84ba807a9d828de9c56382b1a1ce9897dab99d99cd782c1a536c8e9a0f45')
ROLE='ZERO_UPDATE_BRIDGE'
def failure_basis(scope,config,job,pub):
    e=scope['failure_evidence'];kind=e.get('kind');sha=pub['source_files']['numerical_batch.py']
    if kind=='W191_STARTUP_CANCELLED_NO_RELEASE':
        exact_keys(e,{'kind','failure_receipt','role_failed','driver_intent','cancel_guard','cancel_started'},'exact W191 startup failure evidence')
        r=read_metadata(e['failure_receipt']);spent=read_metadata(e['role_failed']);intent=read_metadata(e['driver_intent'])
        h.require(r.get('status')=='FAILED_STARTUP_EXACT_CANCEL_REQUESTED_NOT_TERMINAL_PROOF'
            and r.get('no_release') is True and r.get('no_retry') is True and r.get('all_reserved_fees_retained') is True
            and r.get('cancel_guard')==e['cancel_guard'] and r.get('cancel_error') is None,'actual cancelled W191 startup, not terminal proof alone')
        h.require(spent.get('status')=='FAILED_ROLE_SPENT_DRAIN_OR_DIAGNOSIS_ONLY' and spent.get('failed_startup')==e['failure_receipt']
            and spent.get('old_fees_retained') is True,'actual spent role')
        h.require(intent.get('status')=='STARTED_BOUNDED_NUMERICAL_CRITICAL_LIFECYCLE_NOT_SUCCESS' and intent['config']==scope['config']
            and intent.get('old_fees_retained') is True and intent.get('no_retry') is True
            and intent['driver']==dict(path=str(SOURCE/'numerical_critical_driver.py'),sha256=pub['administrative_source_files']['numerical_critical_driver.py'])
            and intent['peer_program']==dict(path=str(SOURCE/'numerical_independent_peer.py'),sha256=pub['administrative_source_files']['numerical_independent_peer.py']),'actual original driver intent')
        a=read_metadata(intent['authority'])
        h.require(a.get('status')=='ROOT_AUTHORIZED_FROZEN525_NUMERICAL_CRITICAL_LIFECYCLE' and a['config']==scope['config']
            and a['scope']==scope['parent_scope'] and a['role']==ROLE and a['driver_source']==intent['driver']
            and a['peer_program']==intent['peer_program'] and a['max_calls']==1 and a['automatic_retry'] is False,'actual one-shot driver authority')
        start=read_metadata(e['cancel_started']);g=read_metadata(e['cancel_guard']);healthy_guard(g,4,45)
        h.require(start.get('status')=='ACTION_STARTED_NOT_SUCCESS' and start.get('role')==ROLE and start.get('action')=='cancel'
            and start.get('source_sha256')==sha and start.get('limits')==ORIGINAL_POST_SUBMISSION_LIMITS['cancel']
            and all(type(x) is int for x in start['limits'].values())
            and g['session_id']==start['command_pid'] and g['leader_start_ticks']==start['command_birth_ticks'],'actual same-source exact original H4 cancel')
        f=Path(e['cancel_started']['path']);pending=read_metadata(h.pin(f.with_name(f.name.replace('.started.','.pending.'))))
        h.require(pending.get('status')=='INTERNAL_ACTION_RESULT_NOT_GUARD_SUCCESS'
            and all(pending.get(k)==v for k,v in start.items() if k!='status')
            and h.strict_json(g['stdout'])==pending['result']
            and pending['result']==dict(status='CANCEL_REQUESTED_NOT_TERMINAL_PROOF',job_id=job['job_id']),'actual cancel raw result/journal')
    elif kind=='FAILED_NATIVE_ACTION_DRAINED':
        exact_keys(e,{'kind','failed_guard','failed_started'},'exact native failure evidence')
        start=read_metadata(e['failed_started']);g=read_metadata(e['failed_guard'])
        limits=ORIGINAL_POST_SUBMISSION_LIMITS.get(start.get('action'))
        if start.get('action')=='reconcile':limits=dict(local_CPU=3,wall=120)
        h.require(start.get('action')!='retire_failed' and limits is not None and start.get('limits')==limits and all(type(x) is int for x in start['limits'].values())
            and start.get('status')=='ACTION_STARTED_NOT_SUCCESS' and start.get('role')==ROLE and start.get('source_sha256')==sha
            and type(g.get('returncode')) is int and g['returncode']!=0 and g.get('all_owned_descendants_reaped') is True
            and g.get('independent_guardian') is True and g.get('guardian_forced_monitor_stop') is False
            and g.get('guardian_included_in_CPU') is True and g.get('inherited_waited_history_included_once') is True,'actual failed submitted action fully drained')
        w=g.get('owned_stop_witness') or {}
        if w:h.require(w.get('schema')=='r164_owned_stop_failure_witness_v1' and w.get('uid')==os.getuid()
            and w.get('monitor_affinity')==[31] and w.get('states_are_not_accepted_for_accounting') is True,'failed stop witness never stopped proof')
        h.require(g.get('session_id',w.get('session_id'))==start['command_pid']
            and g.get('leader_start_ticks',w.get('leader_start_ticks'))==start['command_birth_ticks'],'actual failed PID/birth')
        if 'CPU_limit' in g:h.require(type(g['CPU_limit']) is int and g['CPU_limit']==start['limits']['local_CPU'],'original failed cap unchanged')
    else:raise ValueError('unsupported failure basis; allocated and ambiguous jobs cannot use this tail')

def context(scope_pin):
    scope=read_metadata(scope_pin);now=time.time();config=read_metadata(scope['config']);parent=read_metadata(scope['parent_scope'])
    h.require(scope.get('schema')=='legacy_w191_unallocated_tail_scope_v1'
        and scope.get('status')=='PROSPECTIVE_EXACT_UNALLOCATED_W191_ROLE_DRAIN_SCOPE'
        and scope['role']==config['role']==ROLE and scope['execution_node']==config['node']=='node-13'
        and config['schema']=='r182_numerical_batch_config_v1' and scope['parent_scope']==config['scope'],'exact W191 role/config')
    h.require(parent.get('status')=='PROSPECTIVE_FRESH_FROZEN525_NUMERICAL_JOB_SCOPE' and parent['roles']==[ROLE]
        and parent['issued_epoch']<=scope['issued_epoch']<=now<scope['expires_epoch']<=parent['expires_epoch']
        and all(type(parent.get(k)) is int and parent[k]==v for k,v in dict(maximum_jobs=1,max_concurrent_jobs=1,compute_CPU_reservation=600,wall_seconds=1200,memory_MiB=8192,threads=1,cpus_per_task=1).items())
        and parent['automatic_retry'] is False and parent['requeue'] is False,'prospective exact single-role scope')
    base=h.physical(parent['allowed_metadata_output_root']);registry=h.physical(config['registry'])/ROLE
    h.require(str(base).startswith('/home/jaguir26/.local/state/pricefm/r180_native_4503eef91eaa/Legacy_NODE13_')
        and base.stat().st_uid==os.getuid() and base.stat().st_mode&0o077==0 and Path(config['registry'])==base/'canonical_registry'
        and re.fullmatch('/mnt/beegfs/home/jaguir26/pricefm_r182_LEGACY_[A-Za-z0-9_]{1,64}_[0-9a-f]{32}',config['remote_namespace']),'fresh private canonical legacy namespace')
    h.require(scope['allocations']==ALLOCATIONS and all(type(x) is int and x==4 for x in scope['allocations'].values())
        and type(scope['total_administrative_CPU']) is int and scope['total_administrative_CPU']==28
        and all(type(scope[k]) is int and scope[k]==1 for k in ['maximum_query_calls','maximum_drain_calls','maximum_peer_calls']),'full distinct tail28')
    budget=read_metadata(scope['parent_budget'])
    h.require(budget.get('schema')=='legacy_w191_unallocated_failure_budget_v1'
        and budget.get('status')=='PROSPECTIVE_W191_COMPATIBLE_SEPARATE_H4_FAILURE_TAIL_BUDGET'
        and budget['parent_scope']==scope['parent_scope'] and budget['role']==ROLE and budget['allocations']==ALLOCATIONS
        and budget['total_administrative_CPU']==28 and type(budget['total_administrative_CPU']) is int
        and all(type(budget[k]) is int and budget[k]==1 for k in ['maximum_query_calls','maximum_drain_calls','maximum_peer_calls'])
        and budget['expires_epoch']==parent['expires_epoch'],'fresh exact tail budget')
    extras=parent['extra_setup_forecast_tail']
    exact_keys(extras,{'separate_preparation_CPU','scheduler_evidence_CPU','compatible_failure_tail_CPU'},'complete closed extra price')
    h.require(all(type(v) is int and v>0 for v in extras.values()) and extras['compatible_failure_tail_CPU']==28
        and type(parent['new_separate_administrative_CPU_reservation']) is int and parent['new_separate_administrative_CPU_reservation']==234
        and parent['complete_administrative_CPU_reservation']==234+sum(extras.values()),'original normal234 plus full separately funded support')
    ledger=read_metadata(budget['funding_ledger']);rows=[r for r in ledger['scopes'] if r.get('scope')==scope['parent_scope']]
    h.require(len(rows)==1 and rows[0]['administrative_CPU_reservation']==parent['complete_administrative_CPU_reservation']
        and type(rows[0]['compute_CPU_reservation']) is int and rows[0]['compute_CPU_reservation']==600,'exact full new role funding')
    h.require(config['publication']==PUB and config['source_review']==REVIEW and config['source_dir']==str(SOURCE),'exact unchanged W191 source identity')
    pub=read_metadata(PUB);review=read_metadata(REVIEW)
    h.require(pub['commit']=='91a0423d5baab068e55c19b9e62e2fb5f13047bc'
        and pub['status']=='PASS_FROZEN525_NUMERICAL_BATCH_SOURCE_PUBLICATION' and review['status']=='PASS_REVIEWED_FROZEN525_NUMERICAL_BATCH_SOURCE','actual original W191 publication/review')
    for k,count in [('source_files',21),('administrative_source_files',3),('scientific_source_files',5)]:
        h.require(pub[k]==review[k] and len(pub[k])==count,'exact original source closure')
        for name,sha in pub[k].items():h.read_pin(dict(path=str(W191/name if '/' in name else SOURCE/name),sha256=sha))
    a=read_metadata(config['canonical_authority'])
    h.require(a.get('status')=='ROOT_AUTHORIZED_CANONICAL_FROZEN525_NUMERICAL_CONFIG'
        and a['binding']=={k:v for k,v in config.items() if k!='canonical_authority'}
        and parent['issued_epoch']<=a['issued_epoch']<=now<a['expires_epoch']<=parent['expires_epoch'],'current whole config authority')
    own=h.pin(Path(__file__).absolute());approval=read_metadata(scope['source_approval'])
    h.require(scope['query_source']==scope['drain_source']==own
        and approval.get('status')=='PASS_REVIEWED_W191_COMPATIBLE_SEPARATE_H4_FAILURE_PROTOCOL'
        and approval['source_publication']==PUB and approval['source_review']==REVIEW and approval['producer']==own
        and approval['independent_peer']==scope['peer_source'] and approval['role']==ROLE and approval['node']=='node-13'
        and approval['original_H3_unchanged'] is True and approval['query_local_CPU']==approval['drain_local_CPU']==4
        and approval['remote_CPU_uncertainty_included'] is True and approval['total_administrative_CPU']==28
        and approval['automatic_retry'] is False,'independently reviewed compatible support, no fake W191 source maps')
    h.read_pin(scope['peer_source']);support=read_metadata(scope['support_publication']);sr=read_metadata(approval['support_source_review'])
    h.require(support.get('status')=='PASS_PUBLISHED_LEGACY_NODE13_SUPPORT_SOURCE'
        and support['independent_review']==approval['support_source_review']
        and re.fullmatch('[0-9a-f]{40}',support['commit']) and support['remote_readback']==support['commit'] and support['branch']!='main'
        and sr.get('status')=='PASS_REVIEWED_LEGACY_NODE13_SUPPORT_SOURCE' and sr['source_files']==support['source_files']
        and support['source_files'].get(Path(own['path']).name)==own['sha256']
        and support['source_files'].get(Path(scope['peer_source']['path']).name)==scope['peer_source']['sha256'],'actual separate support publication and source hashes')
    job=read_metadata(scope['job']);packet=read_metadata(scope['packet'])
    h.require(scope['job']['path'] in {str(registry/'JOB.json'),str(registry/'RECONCILED_JOB.json')}
        and scope['packet']==h.pin(registry/'PACKET.json') and re.fullmatch('[1-9][0-9]*',job['job_id'])
        and job['job_id']==scope['job_id'] and job['scope_id']==packet['scope_id']==scope['scope_id']
        and re.fullmatch('r182-bridge-[0-9a-f]{20}',job['scope_id']) and packet['role']==ROLE
        and packet['remote_root']==config['remote_namespace']+'/'+packet['scope_id']
        and packet['source_publication']==PUB and packet['source_review']==REVIEW,'actual known exact current job/packet')
    prior=read_metadata(config['known_jobs_registry'])['jobs'];current=read_metadata(scope['known_jobs_registry'])['jobs']
    h.require(len(prior)>=17 and len({r['job_id'] for r in prior})==len(prior) and all(r['state'] in {'COMPLETED','FAILED','CANCELLED','TIMEOUT','OUT_OF_MEMORY','NODE_FAIL','PREEMPTED','BOOT_FAIL'} for r in prior)
        and len(current)==len(prior)+1 and current[:-1]==prior and current[-1]['job_id']==job['job_id']
        and current[-1]['job_name']==job['scope_id'] and job['job_id'] not in {r['job_id'] for r in prior},'complete current registry appends exact new job')
    e=scope['failure_evidence'];last=current[-1]
    if e['kind']=='W191_STARTUP_CANCELLED_NO_RELEASE':
        h.require(last['state']=='CANCEL_REQUESTED_AWAIT_QUERY' and last['cancel_guard']==e['cancel_guard'],'cancel requested is not terminal until actual query')
    else:h.require(e['kind']=='FAILED_NATIVE_ACTION_DRAINED' and last['state']=='FAILED_NATIVE_ACTION_AWAIT_QUERY' and last['failed_guard']==e['failed_guard'],'actual failure registry')
    failure_basis(scope,config,job,pub)
    root=h.physical(scope['allowed_output_root'])
    h.require(root.parent==base and root.is_dir() and root.stat().st_uid==os.getuid() and root.stat().st_mode&0o077==0,'exact private tail output root')
    site=read_metadata(config['site'])
    h.require((site['host'],site['user'],site['account'],site['partition'],site['qos'])==('hb.ucsc.edu','jaguir26','128x24','128x24','normal'),'exact verified site')
    for k in ['known_hosts_file','ssh_identity_file']:h.require(h.physical(site[k]).is_file(),'enrolled physical SSH paths')
    expected=paths(config,packet);expected['return']=expected.pop('return_')
    return scope,config,root,site,expected

def ssh_options(site):
    options = {'BatchMode':'yes','StrictHostKeyChecking':'yes','UpdateHostKeys':'no',
        'CheckHostIP':'no','ControlMaster':'no','ControlPath':'none','IdentitiesOnly':'yes',
        'IdentityAgent':'none','ForwardAgent':'no','ClearAllForwardings':'yes',
        'PreferredAuthentications':'publickey','PasswordAuthentication':'no','KbdInteractiveAuthentication':'no',
        'ConnectTimeout':'10','ConnectionAttempts':'1','UserKnownHostsFile':site['known_hosts_file']}
    return [item for key,value in options.items() for item in ('-o',key+'='+value)]+['-i',site['ssh_identity_file']]


def native(site,argv):
    h.require(type(argv) is list and argv and argv[0] in NATIVE
        and all(type(x) is str and '\x00' not in x for x in argv),'closed native-only argv')
    result=subprocess.run(['/usr/bin/ssh',*ssh_options(site),site['user']+'@'+site['host'],shlex.join(argv)],
        capture_output=True,text=True,preexec_fn=lambda:None)
    h.require(len(result.stdout.encode())+len(result.stderr.encode())<=2*1024**2,'bounded native reply')
    return dict(argv=argv,returncode=result.returncode,stdout=result.stdout,stderr=result.stderr)


def native_ok(value,argv,rc):
    exact_keys(value,{'argv','returncode','stdout','stderr'},'closed raw native result')
    h.require(value['argv']==argv and type(value['returncode']) is int and value['returncode']==rc
        and value['stderr']=='','successful exact native operation')
    return value['stdout']


def stat_identity(value,lock,marker):
    fmt='%u|%d|%i|%s|%h|%f|%n\n'
    text=native_ok(value,['stat','--printf='+fmt,'--',lock,marker],0)
    lines=text.splitlines();h.require(len(lines)==2,'two exact claim identities')
    result={}
    for label,path,line in zip(['lock','marker'],[lock,marker],lines):
        fields=line.split('|')
        h.require(len(fields)==7 and fields[-1]==path
            and all(re.fullmatch('[0-9]+',x) for x in fields[:5]) and re.fullmatch('[0-9a-fA-F]+',fields[5]),'typed no-follow stat')
        uid,dev,ino,size,links=map(int,fields[:5]);mode=int(fields[5],16)
        h.require(uid==os.getuid() and ino>0 and dev>=0 and size>=0 and links>=1
            and (stat.S_ISDIR(mode) if label=='lock' else stat.S_ISREG(mode) and size==0 and links==1),
            'owned directory and zero-byte regular single-link marker; symlinks rejected')
        result[label]=dict(path=path,uid=uid,device=dev,inode=ino,bytes=size,nlink=links,mode=mode)
    return result


def require_unallocated(value,job_id,scope_id):
    text=native_ok(value,['sacct','-j',job_id,'-n','-P','--format='+SACCT_FIELDS],0)
    rows=[x.split('|') for x in text.splitlines() if x.strip()]
    h.require(len(rows)==1,'one exact primary accounting row')
    row=rows[0]
    if len(row)==16 and row[-1]=='':row.pop()
    h.require(len(row)==15,'exact original SACCT15 fields')
    jid,name,user,uid,account,partition,state,exitcode,cpu,elapsed,alloc,req,start,end,node=row
    h.require(jid==job_id and name==scope_id and user=='jaguir26' and uid==str(os.getuid())
        and account==partition=='128x24' and state in {'CANCELLED','CANCELLED by '+str(os.getuid())} and exitcode=='0:0'
        and cpu in {'00:00:00','00:00.000','00:00:00.000'} and elapsed=='0' and alloc=='0' and req=='1'
        and start in {'None','Unknown','N/A'} and end not in {'','None','Unknown','N/A'}
        and node in {'None','None assigned','(null)','Unknown','N/A'},'exact never-started cancelled Alloc0/CPU0 job')
    return dict(raw_state=state,normalized_state='CANCELLED',owner_uid=os.getuid())


def run(phase,scope_pin,authority_pin=None):
    outer_context()
    scope,config,root,site,expected=context(scope_pin)
    identity=dict(config=scope['config'],tail_scope=scope_pin,parent_scope=scope['parent_scope'],
        role=scope['role'],job=scope['job'],packet=scope['packet'],
        job_id=scope['job_id'],scope_id=scope['scope_id'],execution_node=scope['execution_node'],
        source=h.pin(Path(__file__).absolute()))
    def put(name,value):
        target=root/name;h.write_new(target,value);return h.pin(target)
    def observe(label,argv):
        raw=native(site,argv)
        ref=put(phase.upper()+'_'+label+'.json',raw)
        return raw,ref
    if phase=='query':
        put('QUERY_INTENT.json',dict(status='ONE_SHOT_QUERY_STARTED_NO_REPLAY',**identity,
            command_pid=os.getpid(),command_birth_ticks=h.process_birth_ticks(),issued_epoch=time.time()))
        raw,account=observe('accounting',['sacct','-j',scope['job_id'],'-n','-P','--format='+SACCT_FIELDS])
        normalized=require_unallocated(raw,scope['job_id'],scope['scope_id'])
        raw,queue=observe('queue',['squeue','-h','-j',scope['job_id'],'-o','%i|%T|%j|%u|%N'])
        h.require(raw['stdout']=='' and type(raw['returncode']) is int
            and ((raw['returncode']==0 and raw['stderr']=='') or
                (raw['returncode']==1 and raw['stderr']=='slurm_load_jobs error: Invalid job id specified\n')),
            'exact terminal job queue absence, never transport error as absence')
        observations={}
        for label in ['ready','release','return','marker','lock']:
            path=expected[label];raw,ref=observe(label,['test','-e',path])
            h.require(type(raw['returncode']) is int and raw['returncode'] in (0,1)
                and raw['stdout']==raw['stderr']=='','actual scoped existence only')
            observations[label]=dict(path=path,exists=raw['returncode']==0,observation=ref)
        h.require(not any(observations[k]['exists'] for k in ['ready','release','return'])
            and observations['lock']['exists']==observations['marker']['exists'],'no payload and paired own claim state')
        out=dict(schema='legacy_w191_unallocated_query_v1',status='OBSERVED_EXACT_UNALLOCATED_JOB_AND_OWN_CLAIM',
            **identity,command_pid=os.getpid(),command_birth_ticks=h.process_birth_ticks(),
            observed_epoch=time.time(),raw_accounting=account,raw_queue=queue,observations=observations,accounting_state=normalized)
        if observations['marker']['exists']:
            raw,ref=observe('claim_stat',['stat','--printf=%u|%d|%i|%s|%h|%f|%n\n','--',expected['lock'],expected['marker']])
            out['claim_identity']=dict(raw_stat=ref,**stat_identity(raw,expected['lock'],expected['marker']))
        put('QUERY_RESULT.json',out)
        return out
    h.require(phase=='drain' and authority_pin is not None,'actual ROOT drain authority required')
    authority=read_metadata(authority_pin);querypin=h.pin(root/'QUERY_RESULT.json');query=read_metadata(querypin)
    review=read_metadata(authority['independent_review']);now=time.time()
    h.require(authority.get('status')=='ROOT_AUTHORIZED_EXACT_UNALLOCATED_NODE_ROLE_DRAIN'
        and all(authority[k]==v for k,v in identity.items() if k!='source')
        and authority['source']==identity['source'] and authority['parent_budget']==scope['parent_budget']
        and authority['query_result']==querypin and authority['query_guard']==h.pin(root/'QUERY_GUARD.json')
        and scope['issued_epoch']<=authority['issued_epoch']<=now<authority['expires_epoch']<=scope['expires_epoch'],
        'fresh exact ROOT drain authority issued after actual reviewed query')
    healthy_guard(read_metadata(authority['query_guard']),4,120)
    h.require(review.get('status')=='PASS_REVIEWED_EXACT_UNALLOCATED_NODE_ROLE_DRAIN'
        and all(review[k]==v for k,v in identity.items() if k!='source')
        and review['query_result']==querypin and review['query_guard']==authority['query_guard']
        and review['review_source']==scope['peer_source'] and review['source_approval']==scope['source_approval']
        and review['observed_epoch']<=authority['issued_epoch'] and now<review['expires_epoch']
        and review['expected_lock']==expected['lock'] and review['expected_marker']==expected['marker'],
        'actual fresh independent query review; producer grants no authority')
    g=read_metadata(authority['query_guard'])
    h.require(h.strict_json(g['stdout'])==query and g['session_id']==query['command_pid']
        and g['leader_start_ticks']==query['command_birth_ticks']
        and query['source']==identity['source'] and query['tail_scope']==scope_pin
        and all(query[k]==v for k,v in identity.items()) and 0<=now-query['observed_epoch']<=120,
        'actual healthy query bytes and source/PID/birth, not a constructed fixture')
    obs=query['observations']
    h.require(not any(obs[k]['exists'] for k in ['ready','release','return'])
        and obs['lock']['exists']==obs['marker']['exists']
        and review['observed_presence']=={k:v['exists'] for k,v in obs.items()},'exact reviewed payload and claim state')
    put('DRAIN_INTENT.json',dict(status='ONE_SHOT_DRAIN_STARTED_NO_REPLAY',**identity,
        authority=authority_pin,query_result=querypin,issued_epoch=now))
    checks=[]
    def checked(label,argv,rc):
        raw,ref=observe(label,argv);checks.append(ref)
        h.require(native_ok(raw,argv,rc)=='','exact native claim operation output')
    if obs['marker']['exists']:
        raw,ref=observe('claim_stat',['stat','--printf=%u|%d|%i|%s|%h|%f|%n\n','--',expected['lock'],expected['marker']])
        checks.append(ref)
        current=stat_identity(raw,expected['lock'],expected['marker'])
        h.require(current=={k:query['claim_identity'][k] for k in ['lock','marker']}
            and current==review['claim_identity']
            and review['permitted_operation']=='REMOVE_EXACT_OWNED_ZERO_BYTE_MARKER_THEN_NONRECURSIVE_EMPTY_LOCK',
            'fresh full device/inode/type/owner identity equals independent reviewed own claim')
        checked('unlink_own_marker',['rm','--',expected['marker']],0)
        checked('remove_empty_lock',['rmdir',expected['lock']],0)
    else:
        h.require(review['claim_identity'] is None and review['permitted_operation']=='VERIFY_TWO_EXACT_ABSENCES_ONLY',
            'absent own claim authorizes absence verification only')
    checked('lock_absent',['test','-e',expected['lock']],1)
    checked('marker_absent',['test','-e',expected['marker']],1)
    out=dict(schema='legacy_w191_unallocated_drain_v1',status='EXACT_UNALLOCATED_NODE_ROLE_CLAIM_ABSENCE_PENDING_OUTER_GUARD',
        **identity,parent_budget=scope['parent_budget'],authority=authority_pin,
        query_result=querypin,query_guard=authority['query_guard'],independent_review=authority['independent_review'],
        checks=checks,command_pid=os.getpid(),command_birth_ticks=h.process_birth_ticks(),
        no_R_or_job_retry=True,no_numerical_success_or_runtime_admission=True,all28_fees_retained=True)
    put('DRAIN_RESULT.json',out)
    return out


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('phase',choices=['query','drain'])
    p.add_argument('--tail-scope',required=True);p.add_argument('--tail-scope-sha256',required=True)
    p.add_argument('--authority');p.add_argument('--authority-sha256')
    a=p.parse_args()
    h.require((a.authority is None)==(a.authority_sha256 is None),'complete optional ROOT authority pin')
    out=run(a.phase,dict(path=a.tail_scope,sha256=a.tail_scope_sha256),
        None if a.authority is None else dict(path=a.authority,sha256=a.authority_sha256))
    print(json.dumps(out,sort_keys=True,allow_nan=False))


if __name__=='__main__':main()
