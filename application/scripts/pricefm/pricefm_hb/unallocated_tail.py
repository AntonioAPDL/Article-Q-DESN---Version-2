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
    path = Path(__file__).absolute().with_name('startup_helper.py')
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


def failure_basis(scope,config,job,family_sha):
    evidence=scope['failure_evidence'];kind=evidence.get('kind')
    if kind=='STARTUP_DEADLINE_NO_RELEASE':
        exact_keys(evidence,{'kind','failure_receipt','cancel_guard','cancel_started'},'closed startup failure evidence')
        r=read_metadata(evidence['failure_receipt']);g=read_metadata(evidence['cancel_guard']);s=read_metadata(evidence['cancel_started'])
        h.require(r.get('status') in {'STARTUP_FAILED_NO_RELEASE','ROLE_FAILED_SPENT',
            'STARTUP_DEADLINE_EXHAUSTED_NO_RELEASE','CRITICAL_DRIVER_FAILED_SPENT_NO_AUTORETRY'}
            and r.get('no_release') is True and r.get('job_id')==job['job_id'] and r.get('role')==scope['role'],
            'actual known spent startup without release')
        healthy_guard(g,4,45)
        h.require(s.get('action')=='cancel' and s.get('limits')==dict(local_CPU=4,remote_unknown_fee=4,wall=45,maximum_calls=1),
            'actual exact cancellation action')
        h.require(all(type(x) is int for x in s['limits'].values()),'exact integer unchanged cancel limits')
    elif kind=='FAILED_NATIVE_ACTION_DRAINED':
        exact_keys(evidence,{'kind','failed_guard','failed_started'},'closed failed guard evidence')
        s=read_metadata(evidence['failed_started']);g=read_metadata(evidence['failed_guard'])
        expected=ORIGINAL_POST_SUBMISSION_LIMITS.get(s.get('action'))
        if scope['family']=='numerical' and s.get('action')=='reconcile':
            expected=dict(local_CPU=3,wall=120)
        h.require(expected is not None and s.get('limits')==expected
            and all(type(x) is int for x in s['limits'].values())
            and type(g.get('returncode')) is int
            and (g['returncode']!=0 or g.get('cap_reason') is not None)
            and g.get('guardian_forced_monitor_stop') is False
            and g.get('all_owned_descendants_reaped') is True
            and g.get('independent_guardian') is True,'actual failed submitted action fully drained')
        witness=g.get('owned_stop_witness')
        if witness is not None:
            h.require(witness.get('schema')=='r164_owned_stop_failure_witness_v1'
                and witness.get('uid')==os.getuid() and witness.get('monitor_affinity')==[31]
                and witness.get('states_are_not_accepted_for_accounting') is True
                and witness.get('session_id')==s['command_pid']
                and witness.get('leader_start_ticks')==s['command_birth_ticks']
                and any(x.get('pid')==s['command_pid'] and x.get('start_ticks')==s['command_birth_ticks']
                    and x.get('sid')==s['command_pid'] and x.get('uid')==os.getuid()
                    for x in witness.get('exact_proved_owned_items',[])), 'actual nested failed stop witness')
        if 'CPU_limit' in g:
            h.require(type(g['CPU_limit']) is int and g['CPU_limit']==s['limits']['local_CPU'],'original failed action cap')
    else:
        raise ValueError('unsupported actual failure basis')
    witness=g.get('owned_stop_witness') or {}
    h.require(s.get('status')=='ACTION_STARTED_NOT_SUCCESS' and s.get('role')==scope['role']
        and s.get('source_sha256')==family_sha and type(s.get('command_pid')) is int
        and type(s.get('command_birth_ticks')) is int and s['command_pid']>0 and s['command_birth_ticks']>0
        and g.get('session_id',witness.get('session_id'))==s['command_pid']
        and g.get('leader_start_ticks',witness.get('leader_start_ticks'))==s['command_birth_ticks'],
        'actual same family source/PID/birth failed or cancelled action')
    if kind=='STARTUP_DEADLINE_NO_RELEASE':
        p=Path(evidence['cancel_started']['path'])
        pending=read_metadata(h.pin(p.with_name(p.name.replace('.started.','.pending.'))))
        h.require(pending.get('status')=='INTERNAL_ACTION_RESULT_NOT_GUARD_SUCCESS'
            and all(pending.get(k)==v for k,v in s.items() if k!='status')
            and h.strict_json(g['stdout'])==pending['result']
            and pending['result']['job_id']==job['job_id'],'actual complete cancellation native result')


def context(scope_pin):
    scope=read_metadata(scope_pin);now=time.time()
    h.require(scope.get('schema')=='node_unallocated_failure_tail_scope_v1'
        and scope.get('status')=='PROSPECTIVE_EXACT_UNALLOCATED_NODE_ROLE_DRAIN_SCOPE','distinct prospective tail purpose')
    config=read_metadata(scope['config']);parent=read_metadata(scope['parent_scope']);budget=read_metadata(scope['parent_budget'])
    h.require(scope['parent_scope']==config['scope'] and scope['parent_budget']==config['failure_tail_budgets'][scope['role']]
        and scope['allocations']==ALLOCATIONS and type(scope['total_administrative_CPU']) is int
        and scope['total_administrative_CPU']==28
        and all(type(x) is int and x==4 for x in scope['allocations'].values())
        and all(type(scope[k]) is int and scope[k]==1 for k in ['maximum_query_calls','maximum_drain_calls','maximum_peer_calls']),
        'complete separately retained tail28')
    h.require(budget.get('schema')=='node_unallocated_failure_budget_v1'
        and budget.get('status')=='PROSPECTIVE_DISTINCT_NODE_UNALLOCATED_FAILURE_TAIL_BUDGET'
        and budget.get('parent_scope')==config['scope'] and budget.get('role')==scope['role']
        and budget.get('allocations')==ALLOCATIONS and type(budget.get('total_administrative_CPU')) is int
        and budget['total_administrative_CPU']==28
        and all(type(x) is int and x==4 for x in budget['allocations'].values())
        and all(type(budget.get(k)) is int and budget[k]==1 for k in ['maximum_query_calls','maximum_drain_calls','maximum_peer_calls'])
        and budget['expires_epoch']==parent['expires_epoch'],'prepriced parent tail budget')
    h.require(all(finite(x) for x in [parent['issued_epoch'],scope['issued_epoch'],scope['expires_epoch'],parent['expires_epoch']])
        and parent['issued_epoch']<=scope['issued_epoch']<=now<scope['expires_epoch']<=parent['expires_epoch'],
        'fresh unextended actual tail scope')
    node=scope['execution_node'];route=scope['qualification_route_id']
    h.require(node in {'node-%02d'%i for i in range(15,22)} and node==scope['qualification_node']==config['node']
        and parent['execution_node']==parent['qualification_node']==node
        and type(route) is str and re.fullmatch('[0-9a-f]{32}',route)
        and parent['qualification_route_id']==route and parent['cached_artifact_origin_node']=='node-13',
        'fresh exact node qualification route')
    authority=read_metadata(config['canonical_authority'])
    statuses={'startup':'ROOT_AUTHORIZED_CANONICAL_STARTUP_BATCH_CONFIG',
        'scientific':'ROOT_AUTHORIZED_CANONICAL_SCIENTIFIC_METADATA_CONFIG',
        'numerical':'ROOT_AUTHORIZED_CANONICAL_FROZEN525_NUMERICAL_CONFIG'}
    family=scope['family'];h.require(family in statuses,'closed exact role family')
    h.require(authority.get('status')==statuses[family]
        and authority['binding']=={k:v for k,v in config.items() if k!='canonical_authority'}
        and parent['issued_epoch']<=authority['issued_epoch']<=now<authority['expires_epoch']<=parent['expires_epoch'],
        'whole canonical configuration authority')
    pub=read_metadata(config['publication']);review=read_metadata(config['source_review'])
    h.require(pub['status'].startswith('PASS_') and 'PUBLICATION' in pub['status']
        and review['status'].startswith('PASS_REVIEWED_') and pub['commit']==review['source_commit']
        and re.fullmatch('[0-9a-f]{40}',pub['commit']) and pub['source_files']==review['source_files']
        and len(pub['source_files'])==dict(startup=14,scientific=15,numerical=21)[family],
        'published independently reviewed exact family')
    source_dir=h.physical(config['source_dir'])
    for name,sha in pub['source_files'].items():
        h.require('/' not in name and name.endswith(('.py','.R')),'closed source filename')
        h.read_pin(dict(path=str(source_dir/name),sha256=sha))
    own=h.pin(Path(__file__).absolute())
    extra=pub.get('extra_administrative_source_files',{})
    h.require(extra==review.get('extra_administrative_source_files')
        and extra.get('unallocated_tail.py')==own['sha256']
        and scope['query_source']==scope['drain_source']==own,'reviewed actual tail producer')
    approval=read_metadata(scope['peer_source_approval']);peer=scope['peer_source']
    h.read_pin(peer)
    h.require(approval['status'].startswith('PASS_REVIEWED_')
        and approval.get('independent_source_files',{}).get('independent_unallocated_drain_review.py')==peer['sha256']
        and pub['independent_source_files']==review['independent_source_files']==approval['independent_source_files']
        and peer['path']==str(source_dir/'independent_unallocated_drain_review.py'),'separately authored approved peer')
    job=read_metadata(scope['job']);packet=read_metadata(scope['packet']);registry=h.physical(config['registry'])/scope['role']
    h.require(scope['job']['path'] in {str(registry/'JOB.json'),str(registry/'RECONCILED_JOB.json')}
        and scope['packet']==h.pin(registry/'PACKET.json')
        and type(job['job_id']) is str and re.fullmatch('[1-9][0-9]*',job['job_id'])
        and job['job_id']==scope['job_id'] and job['scope_id']==packet['scope_id']==scope['scope_id']
        and packet['role']==scope['role'] and packet['execution_node']==node
        and packet['qualification_route_id']==route,'actual exact known submitted job and packet')
    source_name=dict(startup='startup_batch_stop.py',scientific='scientific_batch.py',numerical='numerical_batch.py')[family]
    failure_basis(scope,config,job,pub['source_files'][source_name])
    root=h.physical(scope['allowed_output_root'])
    h.require(str(root).startswith('/home/jaguir26/.local/state/pricefm/') and root.is_dir()
        and root.stat().st_uid==os.getuid() and root.stat().st_mode&0o077==0,'exact private persistent output root')
    site=read_metadata(config['site'])
    h.require((site['host'],site['user'],site['account'],site['partition'],site['qos'])
        ==('hb.ucsc.edu','jaguir26','128x24','128x24','normal'),'exact verified site association')
    for key in ['known_hosts_file','ssh_identity_file']:
        h.require(h.physical(site[key]).is_file(),'configured physical SSH trust and key path')
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
        and account==partition=='128x24' and state=='CANCELLED' and exitcode=='0:0'
        and cpu in {'00:00:00','00:00.000','00:00:00.000'} and elapsed=='0' and alloc=='0' and req=='1'
        and start in {'None','Unknown','N/A'} and end not in {'','None','Unknown','N/A'}
        and node in {'None','None assigned','(null)','Unknown','N/A'},'exact never-started cancelled Alloc0/CPU0 job')


def run(phase,scope_pin,authority_pin=None):
    outer_context()
    scope,config,root,site,expected=context(scope_pin)
    identity=dict(config=scope['config'],tail_scope=scope_pin,parent_scope=scope['parent_scope'],
        family=scope['family'],role=scope['role'],job=scope['job'],packet=scope['packet'],
        job_id=scope['job_id'],scope_id=scope['scope_id'],execution_node=scope['execution_node'],
        qualification_route_id=scope['qualification_route_id'],source=h.pin(Path(__file__).absolute()))
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
        require_unallocated(raw,scope['job_id'],scope['scope_id'])
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
        out=dict(schema='node_unallocated_query_v1',status='OBSERVED_EXACT_UNALLOCATED_JOB_AND_OWN_CLAIM',
            **identity,command_pid=os.getpid(),command_birth_ticks=h.process_birth_ticks(),
            observed_epoch=time.time(),raw_accounting=account,raw_queue=queue,observations=observations)
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
        and review['review_source']==scope['peer_source'] and review['source_approval']==scope['peer_source_approval']
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
    out=dict(schema='node_unallocated_drain_v1',status='EXACT_UNALLOCATED_NODE_ROLE_CLAIM_ABSENCE_PENDING_OUTER_GUARD',
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

