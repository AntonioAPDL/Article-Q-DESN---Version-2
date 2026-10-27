#!/usr/bin/env python3
"""Once-only CPU31 administrative handoff to the unchanged admitted R154 LV.

This entry admits no science. A separate loss-blind scheduling amendment must
explicitly permit LV after the stopped EE queue. The actual child remains the
original 521 entry, source, cwd, grant, preparation, first T0 and expiry.
"""
from __future__ import annotations
import argparse
import ctypes
import fcntl
import json
import math
import os
from pathlib import Path
import resource
import re
import signal
import socket
import subprocess
import sys
import time

sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from pricefm_r154_prediction_contract import (all_processes,cpu_seconds,digest,immutable,
    peer_conflicts,physical_siblings,pin,pressure,process_identity,read,require,
    resolve_pin,same_lifetime,sealed_packet,source_identity,validate_authority,verify_hashes,verify_pin)
ROOT=Path(__file__).resolve().parents[3]
ENTRY=Path(__file__).resolve()
AUDIT=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021/r155_screening_recovery_20261027/lv_handoff')


def own_source(root=ROOT):
    def git(*args):return subprocess.check_output(['git',*args],cwd=root,text=True).strip()
    require(not git('status','--porcelain'),'clean committed administrative source required')
    branch=git('branch','--show-current')
    require(branch.startswith('work/pricefm-r155-lv-handoff-'),'dedicated R155 administrative source required')
    return dict(branch=branch,head=git('rev-parse','HEAD'))


def systemd(unit):
    keys=('Id','MainPID','InvocationID','ActiveState','SubState','Restart','NRestarts','KillMode')
    raw=subprocess.check_output(['systemctl','--user','show',unit,*['--property='+k for k in keys]],text=True)
    result=dict(line.split('=',1) for line in raw.splitlines() if '=' in line)
    require(set(keys)<=set(result),'systemd ownership metadata unavailable')
    return result


def permit_free(glob,permit_id,expected=None):
    # Existing original inode only: a missing/replaced lock is not free proof.
    path=Path(glob['lock_dir'])/(permit_id+'.lock')
    with path.open('r+') as lock:
        before=os.fstat(lock.fileno())
        require(before.st_ino==path.stat().st_ino,'global lock inode changed')
        if expected is not None:
            require(expected==dict(path=str(path),device=before.st_dev,inode=before.st_ino),
                    'original global permit device/inode replaced')
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return None
        return dict(path=str(path),device=before.st_dev,inode=before.st_ino,free=True)


def predecessor_drain(a):
    old=a['predecessor']
    grant=verify_pin(old['queue_authority']);claim=verify_pin(old['queue_claim'])
    exit=verify_pin(old['queue_exit']);wait=verify_pin(old['EE_wait']);receipt=verify_pin(old['EE_supervisor_exit'])
    require(claim['authority']==old['queue_authority'] and claim['source']==grant['source'],'old queue lineage differs')
    require(exit['status']=='STOPPED_NO_RETRY' and exit['claim_consumed'] is True
            and exit['source']==grant['source'] and wait['exit_code']!=0,'old stopped queue evidence differs')
    require(receipt['child_exit_code']!=0 and receipt['all_inclusive_charged_CPU_seconds']==old['retained_EE_CPU_charge'],
            'old EE stop/charge cannot be erased or refunded')
    require(claim['stages'][1]==a['stage'] and grant['stages'][1]==a['stage'],'LV must be the same originally queued stage')
    identities=[claim['process'],receipt['parent'],receipt['payload']]
    for original in identities:
        require(not same_lifetime(process_identity(original['pid']),original),'old exact queue/guardian/payload still lives')
    unit=systemd(old['unit'])
    require(unit['Id']==old['unit'] and unit['InvocationID']==old['invocation_id']
            and unit['MainPID']=='0' and unit['ActiveState'] in ('inactive','failed')
            and unit['Restart']=='no' and unit['NRestarts']=='0' and unit['KillMode']=='process',
            'old exact queue unit is not stopped without restart')
    return dict(lifetimes=identities,all_exact_lifetimes_gone=True,unit=unit,
                retained_EE_CPU_charge=old['retained_EE_CPU_charge'],unused_credit_reusable=False)


def validate(a,identity,now,host,admitted=True):
    require(a.get('schema')=='r155_lv_handoff_authority_v1'
            and a.get('status')==('ADMITTED' if admitted else 'PROPOSED'),'new explicit administrative authority required')
    require(a['source']==identity and a['host']==host and a['administrative_cpu']==31,'administrative source/host/CPU differs')
    require(a['new_fits']==0 and a['new_forecasts']==0 and a['automatic_retry'] is False
            and a['nonrenewing'] is True and a['max_dispatches']==1,'no new science, retry or repeated dispatch admitted')
    require(a['start_epoch']<=now<a['expires_epoch'] and 0<a['max_CPU_seconds']<=120
            and a['expires_epoch']-a['start_epoch']<=a['max_wall_seconds']<=86400,'finite administrative envelope invalid')
    require(a['prior_administrative_CPU_charged_seconds']>=0 and a['administrative_total_CPU_cap']
            >=a['prior_administrative_CPU_charged_seconds']+a['max_CPU_seconds'],
            'preparatory administrative costs cannot be hidden or refunded')
    out=Path(a['output_dir'])
    require(out.parent==AUDIT/'runs' and out.name=='pricefm_stage_r155_lv_handoff_'+a['scope_id'],'new isolated administrative namespace required')
    require(a['unit']=='pricefm-r155-lv-handoff-'+a['scope_id']+'.service','scope-specific once-only unit required')
    verify_hashes(a['source_sha256'])
    require(str(ENTRY) in a['source_sha256'] and str(ENTRY.with_name('pricefm_r154_prediction_contract.py')) in a['source_sha256'],
            'actual administrative entry and imported contract must be pinned')
    require(digest(a['python'])==a['python_sha256'] and Path(a['python']).resolve()==Path(sys.executable).resolve(),'interpreter differs')
    glob=verify_pin(a['global_contract'])
    require(glob['created_epoch']<=a['start_epoch'] and a['expires_epoch']<=glob['expires_epoch'],'original global clock exceeded')
    require(a['permit_identity']['path']==str(Path(glob['lock_dir'])/'muscat_cpu30.lock')
            and a['permit_identity']['device']>0 and a['permit_identity']['inode']>0,'original permit inode identity required')
    amendment=verify_pin(a['order_amendment'])
    require(amendment['schema']=='r155_loss_blind_order_amendment_v1' and amendment['status']==('ADMITTED' if admitted else 'PROPOSED')
            and amendment['transition']=='EE_STOPPED_TO_LV_FIRST' and amendment['loss_blind'] is True
            and amendment['LV_scientifically_independent_of_EE'] is True
            and amendment['unchanged_LV_authority']==a['stage']['authority']
            and amendment['predecessor_queue_authority']==a['predecessor']['queue_authority']
            and amendment['scientific_scope_changed'] is False,'explicit loss-blind scheduling amendment absent')
    stage=a['stage'];grant=verify_pin(stage['authority']);prep=verify_pin(stage['preparation'])
    require(stage['study']=='LV' and grant['study']=='LV' and prep['study']=='LV','exact original LV required')
    original=source_identity(Path(a['scientific_source_root']))
    require(original==a['scientific_source']==grant['source'],'actual original scientific source differs')
    require(Path(a['scientific_entry'])==Path(a['scientific_source_root'])/'application/scripts/pricefm/521_run_pricefm_stage_r154_predictions.py',
            'actual stage-specific original 521 path required')
    require(a['global_contract']==grant['global_contract'] and a['expires_epoch']<=grant['expires_epoch'],
            'administrative handoff cannot renew LV or pool')
    require(a['original_LV_start_epoch']==grant['start_epoch'] and a['original_LV_expires_epoch']==grant['expires_epoch'],
            'original LV first T0/expiry must be explicit and unchanged')
    validate_authority(grant,prep,stage['preparation']['path'],original,now,host)
    required=(grant['full_prefix_CPU']+grant['replacement_CPU'])/grant['min_delivered_share']+grant['drain_seconds']+grant['maximum_atomic_wall_seconds']
    require(a['expires_epoch']-now>=required and a['max_wall_seconds']>=required,
            'whole LV prefix does not fit finite administrative calendar')
    require(not (Path(grant['output_dir'])/'claim.json').exists(),'original LV claim already consumed')
    require(not (out/'claim.json').exists(),'administrative claim already consumed')
    require(5<=a['incident_observation_seconds']<=60 and a['incident_observer_CPU_stop_fraction']==0.7,
            'bounded read-only observation policy differs')
    require(a['pricing_evidence']['path'] and verify_pin(a['pricing_evidence'])['prior_administrative_CPU_charged_seconds']
            ==a['prior_administrative_CPU_charged_seconds'],'explicit source-preparation pricing pin required')
    return glob,grant,prep


def observe(grant,owned_child=None):
    started=time.monotonic();cpu0=cpu_seconds()
    processes=all_processes()
    own_pids={os.getpid()};owned=[]
    if owned_child is not None:
        actual=next((p for p in processes if same_lifetime(p,owned_child)),None)
        require(actual is not None and actual['ppid']==os.getpid(),'held LV child unavailable during incident observation')
        owned=[actual]
        record=Path(grant['output_dir'])/'guardian.json'
        if record.exists():
            guardian=read(record)
            require(same_lifetime(guardian['process'],owned_child),'original LV guardian identity differs')
            payload=next((p for p in processes if same_lifetime(p,guardian['payload'])),None)
            if payload is not None:
                require(payload['ppid']==actual['pid'],'LV payload is not exact guardian direct child')
                owned.append(payload)
        own_pids.update(p['pid'] for p in owned)
    conflicts=peer_conflicts(grant['cpu'],read(grant['peer_census']['path']),own_pids,processes,
                            read(grant['admin_rules']['path']),grant['physical_sibling_cpus'])
    pids={v['pid'] for v in conflicts}
    details=[]
    for row in processes:
        if row['pid'] not in pids:continue
        item=dict(row,classifier_reason='unchanged R154 peer_conflicts rejection; no exemption added')
        try:item['cwd']=os.readlink(Path('/proc')/str(row['pid'])/'cwd')
        except (OSError,PermissionError):item['cwd']=None
        details.append(item)
    return dict(epoch=time.time(),elapsed_seconds=time.monotonic()-started,CPU_seconds=cpu_seconds()-cpu0,
        processes_examined=len(processes),threads_examined=sum(len(p.get('threads',[])) for p in processes),
        conflicts=conflicts,conflicting_lifetime_details=details,unreadable_or_departed_facts_unknown=True,
        exact_owned_LV_observation_exclusions=[{k:p[k] for k in ('pid','start_ticks','boot_id','ppid')} for p in owned],
        classifier_changed=False,foreign_processes_signalled=False)


def preflight(a,identity,admitted=True):
    glob,grant,prep=validate(a,identity,time.time(),socket.gethostname().split('.')[0],admitted)
    verify_hashes(prep['execution_source_sha256'])
    aliases=verify_pin(grant['read_aliases'])
    require(aliases['preparation']==grant['preparation'] and set(aliases['read_aliases'])==set(prep['input_files_sha256']),
            'entire original staged input member set differs')
    for name,expected in prep['input_files_sha256'].items():resolve_pin(name,expected,aliases['read_aliases'])
    drain=predecessor_drain(a)
    permit=permit_free(glob,grant['permit_id'],a['permit_identity'])
    require(permit is not None,'same original physical permit busy; no wait or retry')
    require(physical_siblings(grant['cpu'])==set(grant['physical_sibling_cpus']),'actual SMT siblings differ')
    peers=observe(grant)
    require(not peers['conflicts'],'fresh unchanged classifier found numerical conflict')
    # Pressure reader writes nothing into the old scientific namespace.
    resources=pressure(grant,Path(a['output_dir']).parent.parent,growth_GiB=0)
    return glob,grant,prep,dict(epoch=time.time(),drain=drain,permit=permit,peers=peers,resources=resources,
        verified_execution_source_files=len(prep['execution_source_sha256']),verified_staged_input_files=len(prep['input_files_sha256']),
        LV_calendar_revalidated=True,original_LV_first_T0=grant['start_epoch'],original_LV_expiry=grant['expires_epoch'])


def child_limit(grant):return math.ceil(grant['total_CPU_cap']-grant['prior_CPU_charged_seconds'])


def apply_limits(budget,grant):
    usage=resource.getrusage(resource.RUSAGE_SELF);soft=math.floor(usage.ru_utime+usage.ru_stime+budget)
    hard=max(soft,child_limit(grant));inherited=resource.getrlimit(resource.RLIMIT_CPU)[1]
    require(inherited==resource.RLIM_INFINITY or inherited>=hard,'inherited CPU hard ceiling cannot fund LV child')
    signal.signal(signal.SIGXCPU,signal.SIG_DFL);resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    resource.setrlimit(resource.RLIMIT_CPU,(soft,hard))
    return dict(administrative_soft_CPU_limit=soft,inherited_child_hard_CPU_ceiling=hard)


def arm(expected_parent,limit):
    libc=ctypes.CDLL(None,use_errno=True)
    if libc.prctl(1,signal.SIGKILL,0,0,0)!=0 or os.getppid()!=expected_parent:os._exit(125)
    signal.signal(signal.SIGXCPU,signal.SIG_DFL)
    resource.setrlimit(resource.RLIMIT_CPU,(limit,limit))


def held_state(worker):
    # WNOWAIT leaves even an exited child held by this sole parent waiter.
    return os.waitid(os.P_PID,worker.pid,os.WEXITED|os.WNOHANG|os.WNOWAIT)


def stop_held(worker,identity):
    state=held_state(worker)
    require(identity['ppid']==os.getpid() and same_lifetime(process_identity(worker.pid),identity),
            'sole held direct child lifetime differs; no arbitrary PID fallback')
    if state is None:worker.kill()
    return worker.wait()


def scientific_argv(a):
    stage=a['stage']
    return [a['python'],'-B',a['scientific_entry'],'--preparation',stage['preparation']['path'],
            '--authority',stage['authority']['path'],'--authority-sha256',stage['authority']['sha256']]


def complete(grant,permit_identity):
    out=Path(grant['output_dir']);seal=read(out/'assessment_seal.json');assessment=read(out/'assessment.json')
    require(seal['assessment']==pin(out/'assessment.json') and assessment['status'].startswith('COMPLETE_TRAINING_DIAGNOSTIC'),
            'LV diagnostic incomplete or assessment bytes differ')
    execution=seal['execution']
    require(execution['source']==grant['source'] and execution['scope_id']==grant['scope_id']
            and execution['authority']==pin(out/'authority.json'),'LV original scientific execution lineage differs')
    receipt=read(out/'supervisor_exit_receipt.json')
    require(receipt['child_exit_code']==0,'LV payload failed')
    for key in ('parent','payload'):
        require(not same_lifetime(process_identity(receipt[key]['pid']),receipt[key]),'LV exact lifetime not drained')
    require(permit_free(read(grant['global_contract']['path']),grant['permit_id'],permit_identity) is not None,'LV permit not physically drained')
    return dict(assessment=pin(out/'assessment.json'),seal=pin(out/'assessment_seal.json'),supervisor=pin(out/'supervisor_exit_receipt.json'),physical_drain=True)


def execute(path,expected,audit_only=False):
    cpu0=cpu_seconds();own0=resource.getrusage(resource.RUSAGE_SELF);started=time.monotonic()
    require(os.sched_getaffinity(0)=={31},'all administrative Python must enter pinned CPU31')
    require(len(list(Path('/proc/self/task').iterdir()))==1 and signal.getsignal(signal.SIGCHLD)==signal.SIG_DFL,
            'one thread/default SIGCHLD sole direct-child waiter required')
    require(digest(path)==expected,'exact administrative authority pin required')
    a=read(path);identity=own_source()
    glob,grant,prep,proof=preflight(a,identity,not audit_only)
    if audit_only:
        return dict(status='PROPOSED_METADATA_ONLY_NO_CLAIM_NO_FORECAST',proof=proof,source=identity,
                    measured_administrative_CPU_seconds=cpu_seconds()-cpu0,elapsed_seconds=time.monotonic()-started)
    unit=systemd(a['unit'])
    require(unit['Id']==a['unit'] and unit['MainPID']==str(os.getpid()) and unit['InvocationID']==os.environ.get('INVOCATION_ID')
            and unit['Restart']=='no' and unit['NRestarts']=='0' and unit['KillMode']=='process','own unique once-only unit differs')
    require(cpu_seconds()-cpu0<a['max_CPU_seconds']*.5,'preflight used insufficiently priced administrative CPU')
    limits=apply_limits(a['max_CPU_seconds']-(cpu_seconds()-cpu0),grant)
    out=Path(a['output_dir']);out.mkdir(parents=True,exist_ok=True)
    # Exclusive permanent claim; no equal-record reuse and no automatic retry.
    with (out/'claim.json').open('x') as stream:
        json.dump(dict(authority=pin(path),source=identity,process=process_identity(os.getpid()),unit=unit,
            original_LV_authority=a['stage']['authority'],automatic_retry=False),stream,sort_keys=True,indent=2)
        stream.flush();os.fsync(stream.fileno())
    immutable(out/'preclaim_proof.json',proof);immutable(out/'CPU_limits.json',limits)
    immutable(out/'launch_intent.json',dict(argv=scientific_argv(a),cwd=a['scientific_source_root'],
        actual_scientific_source=grant['source'],original_LV_authority=a['stage']['authority'],attempt=1,new_fits=0))
    worker=None;child=None;scientific_CPU=0.0;child_reaped=False
    child0=resource.getrusage(resource.RUSAGE_CHILDREN)
    try:
        # Fresh final physical/calendar checks just before the one dispatch.
        validate_authority(grant,prep,a['stage']['preparation']['path'],grant['source'],time.time(),a['host'])
        require(permit_free(glob,grant['permit_id'],a['permit_identity']) is not None,'permit became busy; no retry')
        parent=os.getpid()
        with (out/'LV_stdout.log').open('xb') as stdout,(out/'LV_stderr.log').open('xb') as stderr:
            worker=subprocess.Popen(scientific_argv(a),cwd=a['scientific_source_root'],stdout=stdout,stderr=stderr,
                start_new_session=True,preexec_fn=lambda:arm(parent,child_limit(grant)))
            child=process_identity(worker.pid)
            require(child is not None and child['ppid']==parent,'actual direct child identity unavailable')
            immutable(out/'LV_process.json',dict(process=child,parent=process_identity(parent),PDEATHSIG='SIGKILL',sole_waiter=True))
            next_observation=time.monotonic()+a['incident_observation_seconds'];observation_count=0;observer_enabled=True
            while held_state(worker) is None:
                own=resource.getrusage(resource.RUSAGE_SELF)
                own_CPU=own.ru_utime+own.ru_stime-own0.ru_utime-own0.ru_stime
                require(time.time()<a['expires_epoch'] and time.monotonic()-started<a['max_wall_seconds'],
                        'fixed administrative absolute/active clock exhausted')
                require(own_CPU<a['max_CPU_seconds']*.9,'finite own administrative CPU approaching cap')
                if observer_enabled and own_CPU>=a['max_CPU_seconds']*a['incident_observer_CPU_stop_fraction']:
                    immutable(out/'incident_observation_stopped.json',dict(reason='retain administrative drain CPU',own_CPU=own_CPU,epoch=time.time()))
                    observer_enabled=False
                if observer_enabled and time.monotonic()>=next_observation:
                    observation_count+=1
                    try:
                        record=observe(grant,child)
                        # Read-only evidence; no signal or exemption. Optional
                        # observer failure must not interrupt the ready LV study.
                        immutable(out/('incident_observation_%05d.json'%observation_count),record)
                    except Exception as observation_error:
                        immutable(out/'incident_observation_failed.json',dict(epoch=time.time(),
                            type=type(observation_error).__name__,reason=str(observation_error),LV_interrupted=False))
                        observer_enabled=False
                    next_observation=time.monotonic()+a['incident_observation_seconds']
                time.sleep(1)
            code=worker.wait();child_reaped=True
            final=resource.getrusage(resource.RUSAGE_CHILDREN)
            scientific_CPU=final.ru_utime+final.ru_stime-child0.ru_utime-child0.ru_stime
            immutable(out/'LV_wait_receipt.json',dict(exit_code=code,epoch=time.time(),scientific_reaped_CPU_seconds=scientific_CPU,
                stdout=pin(out/'LV_stdout.log'),stderr=pin(out/'LV_stderr.log'),automatic_retry=False))
            if code!=0:
                try:immutable(out/'failure_incident_observation.json',failure_incident(grant,out/'LV_stderr.log'))
                except Exception as error:immutable(out/'failure_incident_observation_unavailable.json',dict(reason=str(error),type=type(error).__name__))
            require(code==0,'unchanged LV worker stopped; no retry')
        result=dict(status='COMPLETE_LV_TRAINING_DIAGNOSTIC_NOT_PROMOTED',LV=complete(grant,a['permit_identity']))
    except BaseException as exc:
        if worker is not None and not child_reaped:
            # Popen owns its unreaped direct child even if /proc acquisition failed.
            if child is None:
                if held_state(worker) is None:worker.kill()
                worker.wait()
            else:stop_held(worker,child)
            child_reaped=True
            final=resource.getrusage(resource.RUSAGE_CHILDREN)
            scientific_CPU=final.ru_utime+final.ru_stime-child0.ru_utime-child0.ru_stime
        result=dict(status='STOPPED_NO_RETRY',reason=str(exc),type=type(exc).__name__,claim_consumed=True)
        immutable(out/'exit_receipt.json',dict(result,source=identity,original_LV_authority=a['stage']['authority'],
            measured_administrative_CPU_seconds=cpu_seconds()-cpu0-scientific_CPU,
            scientific_reaped_CPU_seconds=scientific_CPU,inclusive_CPU_must_not_be_added_again=True,
            elapsed_seconds=time.monotonic()-started,automatic_followon=False))
        raise
    result.update(source=identity,original_LV_authority=a['stage']['authority'],
        measured_administrative_CPU_seconds=cpu_seconds()-cpu0-scientific_CPU,scientific_reaped_CPU_seconds=scientific_CPU,
        inclusive_CPU_must_not_be_added_again=True,elapsed_seconds=time.monotonic()-started,automatic_followon=False)
    immutable(out/'exit_receipt.json',result)
    return result


def failure_incident(grant,stderr):
    with Path(stderr).open('rb') as stream:
        stream.seek(max(0,Path(stderr).stat().st_size-1048576));text=stream.read().decode(errors='replace')
    pids=set()
    for match in re.findall(r'(?:unreviewed numerical peer intersects allocation|new numerical peer before claim):\s*(\[[0-9, ]*\])',text):
        pids.update(json.loads(match))
    rows=all_processes();details=[]
    for pid in sorted(pids):
        actual=next((p for p in rows if p['pid']==pid),None)
        item=dict(reported_PID=pid,current_identity=actual,
                  reported_lifetime_unknown=True,no_PID_based_exemption=True,
                  classifier_reason='PID reported by unchanged original 521 traceback')
        if actual is not None:
            try:item['current_cwd']=os.readlink(Path('/proc')/str(pid)/'cwd')
            except OSError:item['current_cwd']=None
            item['current_PID_may_be_reused']=True
        else:item['status']='UNAVAILABLE_ALREADY_DEPARTED_OR_UNREADABLE'
        details.append(item)
    return dict(epoch=time.time(),stderr=pin(stderr),reported_peers=details,current_unchanged_classifier=observe(grant),
                foreign_signals=0,automatic_retry=False,prior_reported_PID_lifetime_cannot_be_reconstructed=True)


def inspect(path,expected):
    """Read actual source-bound handoff/LV evidence; no launch or runtime writes."""
    require(os.sched_getaffinity(0)=={31},'read-only administrative observer must be pinned CPU31')
    require(digest(path)==expected,'exact administrative authority pin required')
    a=read(path);identity=own_source()
    require(a['schema']=='r155_lv_handoff_authority_v1' and a['status']=='ADMITTED' and a['source']==identity,'actual administrative source differs')
    verify_hashes(a['source_sha256']);grant=verify_pin(a['stage']['authority']);prep=verify_pin(a['stage']['preparation'])
    require(source_identity(Path(a['scientific_source_root']))==grant['source']==a['scientific_source'],'original LV source differs')
    out=Path(a['output_dir']);science=Path(grant['output_dir'])
    def captured(p):return None if not p.is_file() else dict(pin=pin(p),value=read(p))
    admin={name:captured(out/name) for name in ('claim.json','preclaim_proof.json','CPU_limits.json','launch_intent.json','LV_process.json','LV_wait_receipt.json','exit_receipt.json','incident_observation_failed.json','incident_observation_stopped.json','failure_incident_observation.json')}
    records={name:captured(science/name) for name in ('claim.json','authority.json','guardian.json','payload_identity.json','heartbeat.json','terminal.json','assessment.json','assessment_seal.json','supervisor_exit_receipt.json')}
    if admin['claim.json']:require(admin['claim.json']['value']['authority']==pin(path),'administrative claim authority differs')
    if records['claim.json']:
        require(records['claim.json']['value']['authority']==a['stage']['authority'],'original LV claim authority differs')
        require(records['authority.json']['pin']['sha256']==a['stage']['authority']['sha256'],'original LV runtime authority changed')
    def actual(record,role):
        current=process_identity(record['pid']);live=same_lifetime(current,record)
        result=dict(role=role,recorded=record,current=current,live_exact_lifetime=live)
        if live:
            require(current['argv']==record['argv'],'live source argv changed')
            root=Path('/proc')/str(record['pid'])
            fields=(root/'stat').read_text().rsplit(')',1)[1].split();nice=int(fields[16])
            masks={t.name:sorted(os.sched_getaffinity(int(t.name))) for t in (root/'task').iterdir()}
            expected_cpu=31 if role=='administrative' else 30
            require(current['cpus']==[expected_cpu] and all(m==[expected_cpu] for m in masks.values()),'actual process/thread affinity differs')
            if role!='administrative':
                require(nice==10 and os.sched_getscheduler(record['pid'])==os.SCHED_OTHER,'original LV numerical scheduler/nice differs')
                require(subprocess.check_output(['ionice','-p',str(record['pid'])],text=True).startswith('idle'),'original LV idle IO differs')
            result.update(nice=nice,thread_masks=masks,cwd=os.readlink(root/'cwd'),kernel_limits=(root/'limits').read_text())
        return result
    processes=[]
    if admin['claim.json']:processes.append(actual(admin['claim.json']['value']['process'],'administrative'))
    if records['guardian.json']:processes.append(actual(records['guardian.json']['value']['process'],'guardian'))
    if records['payload_identity.json']:processes.append(actual(records['payload_identity.json']['value']['process'],'payload'))
    calls={row['id']:row for row in prep['call_manifest']};verified=[]
    execution=dict(source=grant['source'],scope_id=grant['scope_id'],permit_id=grant['permit_id'],
                   authority=pin(science/'authority.json'),read_aliases=grant['read_aliases']) if records['authority.json'] else None
    for seal_path in sorted((science/'tasks_done').glob('*/completed_evidence.json')):
        if '.attempt.' in seal_path.parent.name:continue
        seal=sealed_packet(seal_path.parent);result=read(seal_path.parent/'result.json')
        require(seal['schema']=='r154_prediction_packet_v1' and seal['scientific_context']==calls[seal_path.parent.name]
                and seal['execution']==execution,'original LV call lineage differs')
        require(result['new_fits']==0 and result['official_origins']==0 and result['no_extra_forecast_call']
                and result['numerical_threadpools'] and all(p['num_threads']==1 for p in result['numerical_threadpools']),
                'LV call scope or recorded numerical pools differ')
        verified.append(dict(id=seal_path.parent.name,seal=pin(seal_path),result=pin(seal_path.parent/'result.json'),
                             measured_CPU_seconds=result['measured_CPU_seconds'],numerical_threadpools=result['numerical_threadpools']))
    glob=verify_pin(a['global_contract']);free=permit_free(glob,grant['permit_id'],a['permit_identity'])
    return dict(status='READ_ONLY_EXACT_R155_ADMIN_AND_ORIGINAL_R154_LV_HEALTH',epoch=time.time(),
        administrative_source=identity,original_scientific_source=grant['source'],unit=systemd(a['unit']),
        administrative_authority=pin(path),original_LV_authority=a['stage']['authority'],administrative_records=admin,
        LV_records=records,actual_processes=processes,verified_call_seals=verified,complete_calls=len(verified),calls_remaining=12-len(verified),
        LV_first_T0=grant['start_epoch'],LV_absolute_expiry=grant['expires_epoch'],LV_seconds_to_absolute_expiry=grant['expires_epoch']-time.time(),
        original_global_expiry=glob['expires_epoch'],same_original_permit_free=free is not None,
        resources=pressure(grant,AUDIT,growth_GiB=0),runtime_mutations=0,scientific_dispatches=0,signals=0,
        scientific_completion_requires_assessment_and_physical_drain=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--authority',required=True);parser.add_argument('--authority-sha256',required=True)
    parser.add_argument('--audit-proposal',action='store_true',help='PROPOSED metadata/input/peer checks only; no claim or forecast')
    parser.add_argument('--inspect',action='store_true',help='Read-only actual source/lifetime/claims/pools/seals; never a release command')
    args=parser.parse_args()
    require(not(args.inspect and args.audit_proposal),'choose one read-only mode')
    value=inspect(args.authority,args.authority_sha256) if args.inspect else execute(args.authority,args.authority_sha256,args.audit_proposal)
    print(json.dumps(value,sort_keys=True,indent=2))


if __name__=='__main__':main()
