#!/usr/bin/env python3
"""Root-endowed, once-only admin31 wait for LV drain then exact two-S0 EE.

Only the future proof pin may be filled in the frozen child authority. No
science, budget, source, scope or first-T0/expiry field is selected at runtime.
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
import signal
import socket
import subprocess
import sys
import time
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import pricefm_r155_completion_contract as c
ROOT=Path(__file__).resolve().parents[3]
ENTRY=Path(__file__).resolve()
AUDIT=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021/r155_screening_recovery_20261027/ee_completion')


def systemd(unit):
    keys=('Id','MainPID','InvocationID','ActiveState','SubState','Restart','NRestarts','KillMode','Result','ExecMainStatus')
    raw=subprocess.check_output(['systemctl','--user','show',unit,*['--property='+k for k in keys]],text=True)
    result=dict(line.split('=',1) for line in raw.splitlines() if '=' in line)
    c.require(set(keys)<=set(result),'systemd lifecycle metadata unavailable')
    return result


def source_at(root):
    def git(*args):return subprocess.check_output(['git',*args],cwd=root,text=True).strip()
    c.require(not git('status','--porcelain'),'pinned LV administrative source became dirty')
    return dict(branch=git('branch','--show-current'),head=git('rev-parse','HEAD'))


def whole_calendar(template,now):
    required=(template['full_prefix_CPU']+template['replacement_CPU']+template['admin_drain_CPU'])/template['min_delivered_share']
    required+=template['drain_seconds']+template['maximum_atomic_wall_seconds']
    c.require(now+required<template['expires_epoch'] and required<template['max_execution_wall_seconds'],
              'entire fixed EE endowment no longer fits; no clock reset')
    return required


def validate(a,path):
    c.require(a.get('schema')=='r155_ee_conditional_endowment_v1' and a.get('status')=='ROOT_CONDITIONALLY_ADMITTED',
              'explicit root conditional admission absent')
    identity=c.source_identity(ROOT)
    c.require(a['source']==identity and a['host']==socket.gethostname().split('.')[0]
              and a['administrative_cpu']==31,'actual conditional source/host/CPU differs')
    c.require(a['max_dispatches']==1 and a['automatic_retry'] is False and a['nonrenewing'] is True
              and a['allowed_child_template_mutations']==['LV_completed_drain_proof'],'conditional scope expansion forbidden')
    c.require(a['new_fits']==0 and a['new_forecasts_in_controller']==0,'administrative controller cannot forecast')
    c.verify_hashes(a['source_sha256'])
    c.require(a['source_sha256'].get(str(ENTRY))==c.digest(ENTRY)
              and a['source_sha256'].get(str(Path(c.__file__)))==c.digest(c.__file__),'actual controller/contract pins absent')
    template=c.verify_pin(a['child_authority_template']);prep=c.verify_pin(template['preparation'])
    c.require(template['schema']=='r155_ee_completion_authority_v1' and template['status']=='ADMITTED'
              and template['source']==identity and prep['source']==identity
              and template['max_new_tasks']==2 and template['LV_completed_drain_proof'] is None,
              'frozen conditional child authority differs')
    c.verify_hashes(prep['execution_source_sha256'])
    c.require(a['start_epoch']==template['start_epoch'] and a['expires_epoch']==template['expires_epoch']
              and a['max_wall_seconds']==template['max_wall_seconds'] and a['max_wall_seconds']<=57600,
              'conditional first clock differs from frozen child')
    now=time.time();c.require(a['start_epoch']<=now<a['expires_epoch'],'conditional endowment expired/not started')
    c.require(a['expires_epoch']-a['start_epoch']<=a['max_wall_seconds'],'conditional absolute clock renewed')
    glob=c.verify_pin(template['global_contract'])
    c.require(template['global_contract']==prep['global_contract'] and glob['created_epoch']<=a['start_epoch']
              and a['expires_epoch']<=glob['expires_epoch'],'original shared resource lifetime changed')
    c.require(a['administrative_live_CPU_cap']==120 and a['combined_new_CPU_cap']==template['total_CPU_cap']+120,
              'controller CPU/wait costs not separately included')
    c.require(template['prior_CPU_charged_seconds']==a['new_preparation_CPU_debit']==600
              and a['new_preparation_debit_is_separate_from_previous_paid_scope'] is True,
              'new preparation debit cannot be credited from the old scope')
    c.require(a['previous_paid_scope']==prep['previous_paid_scope']==template['previous_paid_scope'],
              'old paid lineage changed')
    c.require(c.digest(a['python'])==a['python_sha256'] and Path(a['python']).resolve()==Path(sys.executable).resolve(),
              'conditional interpreter differs')
    lv_admin=c.verify_pin(a['LV_admin_authority'])
    c.require(lv_admin['schema']=='r155_lv_handoff_authority_v1' and lv_admin['status']=='ADMITTED'
              and lv_admin['stage']['authority']==prep['LV_completed_gate']['authority']
              and source_at(a['LV_admin_source_root'])==lv_admin['source']==a['LV_admin_source'],
              'original LV/new administrative stage/source differs')
    c.verify_hashes(lv_admin['source_sha256'])
    c.require(a['poll_seconds']==30 and isinstance(a['max_status_observations'],int)
              and 1<=a['max_status_observations']<=1921,'finite administrative wait observation budget differs')
    out=Path(a['output_dir'])
    c.require(out.parent==AUDIT/'runs' and out.name=='pricefm_stage_r155_ee_conditional_'+a['scope_id'],
              'isolated append-only conditional namespace required')
    c.require(a['unit']=='pricefm-r155-ee-conditional-'+a['scope_id']+'.service','conditional scope-specific unit differs')
    c.require(not (out/'claim.json').exists() and not (Path(template['output_dir'])/'claim.json').exists(),
              'conditional or scientific claim already spent; no retry')
    c.require(os.sched_getaffinity(0)=={31},'conditional controller must stay on admin31')
    whole_calendar(template,now)
    c.verify_pin(a['pricing_evidence']);c.verify_pin(a['source_review'])
    return identity,template,prep,lv_admin


def same_free_inode(template):
    glob=c.verify_pin(template['global_contract'])
    path=Path(glob['lock_dir'])/(template['permit_id']+'.lock')
    expected=template['original_global_lock_identity']
    def identity(st):return dict(device=st.st_dev,inode=st.st_ino)
    c.require(identity(path.stat())==expected,'original physical permit path replaced')
    with path.open('r+') as lock:
        c.require(identity(os.fstat(lock.fileno()))==expected,'opened permit inode replaced')
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        c.require(identity(path.stat())==expected,'permit path replaced during free proof')
        return dict(path=str(path),**expected,free=True)


def LV_ready(admin,prep,authority_pin):
    out=Path(admin['output_dir'])
    receipt_path=out/'exit_receipt.json'
    if not receipt_path.exists():
        claim_path=out/'claim.json'
        if claim_path.exists():
            claim=c.read(claim_path)
            c.require(claim['authority']==authority_pin,'waiting LV administrative claim differs')
            c.require(c.same_lifetime(c.process_identity(claim['process']['pid']),claim['process']),
                      'LV administrative controller died without complete receipt; no retry')
        return None
    receipt=c.read(receipt_path)
    c.require(receipt['status']=='COMPLETE_LV_TRAINING_DIAGNOSTIC_NOT_PROMOTED',
              'LV administrative stage failed; conditional EE stopped without retry')
    claim=c.read(out/'claim.json')
    c.require(claim['authority']==authority_pin and claim['source']==admin['source']
              and claim['original_LV_authority']==prep['LV_completed_gate']['authority']
              and receipt['source']==admin['source']
              and receipt['original_LV_authority']==prep['LV_completed_gate']['authority']
              and receipt['LV']['physical_drain'] is True,
              'LV administrative claim source/original authority differs')
    if c.same_lifetime(c.process_identity(claim['process']['pid']),claim['process']):return None
    unit=systemd(admin['unit'])
    c.require(unit['InvocationID']==claim['unit']['InvocationID'] and unit['Id']==admin['unit']
              and unit['MainPID']=='0' and unit['ActiveState'] in ('inactive','failed')
              and unit['Restart']=='no' and unit['NRestarts']=='0' and unit['KillMode']=='process',
              'exact LV administrative unit has not drained unchanged')
    c.require(unit['Result']=='success' and unit['ExecMainStatus']=='0','LV administrative unit did not exit successfully')
    c.validate_LV_completion(prep['LV_completed_gate'])
    return dict(administrative_claim=c.pin(out/'claim.json'),administrative_exit=c.pin(receipt_path),unit=unit)


def arm(parent,limit):
    libc=ctypes.CDLL(None,use_errno=True)
    if libc.prctl(1,signal.SIGKILL,0,0,0)!=0 or os.getppid()!=parent['pid']:
        os._exit(125)
    if not c.same_lifetime(c.process_identity(parent['pid']),parent):os._exit(125)
    signal.signal(signal.SIGXCPU,signal.SIG_DFL)
    resource.setrlimit(resource.RLIMIT_CPU,(limit,limit))


def derive_child(template,proof_pin):
    c.require(template['LV_completed_drain_proof'] is None,'frozen proof slot already filled')
    return dict(template,LV_completed_drain_proof=proof_pin)


def stop_held(worker,identity):
    """Popen child remains held by this sole waiter, even if /proc vanished."""
    c.require(len(list(Path('/proc/self/task').iterdir()))==1 and signal.getsignal(signal.SIGCHLD)==signal.SIG_DFL,
              'direct-child stop requires sole waiter')
    state=os.waitid(os.P_PID,worker.pid,os.WEXITED|os.WNOHANG|os.WNOWAIT)
    if identity is not None:c.signal_unreaped_direct_child(worker.pid,identity)
    elif state is None:
        # waitid proves direct-child ownership and WNOWAIT preserves its PID.
        # No caller can supply a foreign PID; worker is our unreaped Popen.
        os.kill(worker.pid,signal.SIGKILL)


def apply_limits(a,template,cpu0):
    remaining=a['administrative_live_CPU_cap']-(c.cpu_seconds()-cpu0)
    c.require(remaining>1,'preflight exhausted the live administrative CPU budget')
    usage=resource.getrusage(resource.RUSAGE_SELF)
    soft=math.floor(usage.ru_utime+usage.ru_stime+remaining)
    child_limit=math.ceil(template['total_CPU_cap']-template['prior_CPU_charged_seconds'])
    hard=max(soft,child_limit);inherited=resource.getrlimit(resource.RLIMIT_CPU)[1]
    c.require(inherited==resource.RLIM_INFINITY or inherited>=hard,'inherited hard cap cannot fund EE child')
    signal.signal(signal.SIGXCPU,signal.SIG_DFL);resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    resource.setrlimit(resource.RLIMIT_CPU,(soft,hard))
    return child_limit


def execute(endowment,expected):
    c.require(c.digest(endowment)==expected,'root endowment pin differs')
    cpu0=c.cpu_seconds();a=c.read(endowment)
    identity,template,prep,lv_admin=validate(a,endowment)
    out=Path(a['output_dir']);out.mkdir(parents=True,exist_ok=True)
    scope_lock=(out/'scope.lock').open('a+');fcntl.flock(scope_lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    c.require(not (out/'claim.json').exists(),'conditional claim consumed')
    own=c.process_identity(os.getpid());unit=systemd(a['unit'])
    c.require(unit['Id']==a['unit'] and unit['InvocationID']==os.environ.get('INVOCATION_ID')
              and bool(unit['InvocationID']) and unit['MainPID']==str(os.getpid()) and unit['Restart']=='no' and unit['NRestarts']=='0'
              and unit['KillMode']=='process','conditional unit lifecycle differs')
    c.immutable(out/'claim.json',dict(schema='r155_ee_conditional_claim_v1',authority=c.pin(endowment),
        source=identity,process=own,unit=unit,child_authority_template=a['child_authority_template'],
        original_LV_authority=prep['LV_completed_gate']['authority'],LV_admin_authority=a['LV_admin_authority'],
        automatic_retry=False,max_dispatches=1))
    child_limit=apply_limits(a,template,cpu0)
    worker=None;child_identity=None;reaped=False;scientific_reaped=0.0
    try:
        ready=None
        for observation in range(a['max_status_observations']):
            whole_calendar(template,time.time())
            c.require(c.cpu_seconds()-cpu0<a['administrative_live_CPU_cap']*.9,'conditional administrative CPU reserve exhausted')
            ready=LV_ready(lv_admin,prep,a['LV_admin_authority'])
            if ready is not None:break
            time.sleep(min(a['poll_seconds'],max(0,a['expires_epoch']-time.time())))
        c.require(ready is not None,'finite LV wait exhausted; no automatic refill')
        c.require(source_at(a['LV_admin_source_root'])==a['LV_admin_source'],'LV administrative source changed while waiting')
        c.require(c.source_identity(ROOT)==identity,'conditional source changed while waiting')
        permit=same_free_inode(template)
        processes=c.all_processes()
        conflicts=c.peer_conflicts(template['cpu'],c.verify_pin(template['peer_census']),{os.getpid()},processes,
            c.verify_pin(template['admin_rules']),template['physical_sibling_cpus'])
        if conflicts:
            c.immutable(out/'peer_rejection.json',dict(conflicts=conflicts,epoch=time.time(),classifier_unchanged=True))
        c.require(not conflicts,'fresh physical30/62 peer conflict after LV drain')
        resources=c.pressure(template,Path(prep['new_campaign_parent']),growth_GiB=0)
        lvout=Path(prep['LV_completed_gate']['output_dir'])
        proof=dict(schema='r155_LV_complete_drain_v1',status='PASS',LV_complete=True,
            exact_lifetimes_gone=True,same_global_flock_free=True,epoch=time.time(),source=identity,
            root_conditional_endowment=c.pin(endowment),original_LV_authority=prep['LV_completed_gate']['authority'],
            LV_admin_authority=a['LV_admin_authority'],LV_admin=ready,permit=permit,
            assessment=c.pin(lvout/'assessment.json'),assessment_seal=c.pin(lvout/'assessment_seal.json'),
            LV_exit=c.pin(lvout/'exit_receipt.json'),LV_supervisor_exit=c.pin(lvout/'supervisor_exit_receipt.json'),
            fresh_peer_processes=len(processes),fresh_peer_threads=sum(len(p['threads']) for p in processes),
            conflicts=[],resources=resources,classifier_changed=False,automatic_retry=False)
        c.immutable(out/'LV_COMPLETED_DRAIN_PROOF.json',proof)
        child=derive_child(template,c.pin(out/'LV_COMPLETED_DRAIN_PROOF.json'))
        c.validate_authority(child,prep,child['preparation']['path'],identity,time.time(),a['host'])
        c.immutable(out/'derived_EE_authority.json',child)
        c.immutable(out/'dispatch.json',dict(number=1,entry=c.pin(ENTRY.with_name('524_run_pricefm_stage_r155_ee_completion.py')),
            source=identity,authority=c.pin(out/'derived_EE_authority.json'),first_T0=child['start_epoch'],
            expiry=child['expires_epoch'],scientific_fields_changed=False,automatic_retry=False))
        c.require(len(list(Path('/proc/self/task').iterdir()))==1 and signal.getsignal(signal.SIGCHLD)==signal.SIG_DFL,
                  'conditional controller requires sole single-threaded waiter')
        command=[a['python'],'-B',str(ENTRY.with_name('524_run_pricefm_stage_r155_ee_completion.py')),
            '--preparation',child['preparation']['path'],'--authority',str(out/'derived_EE_authority.json'),
            '--authority-sha256',c.digest(out/'derived_EE_authority.json')]
        aux_usage=resource.getrusage(resource.RUSAGE_CHILDREN)
        administrative_reaped_before_child=aux_usage.ru_utime+aux_usage.ru_stime
        with (out/'scientific.log').open('xb') as log:
            worker=subprocess.Popen(command,cwd=ROOT,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,
                env=dict(os.environ,**{name:'1' for name in c.THREAD_ENV}),preexec_fn=lambda:arm(own,child_limit))
            child_identity=c.process_identity(worker.pid)
            c.require(child_identity is not None and child_identity['ppid']==os.getpid(),'direct EE child lifetime unavailable')
            c.immutable(out/'child_identity.json',child_identity)
            while os.waitid(os.P_PID,worker.pid,os.WEXITED|os.WNOHANG|os.WNOWAIT) is None:
                own_usage=resource.getrusage(resource.RUSAGE_SELF)
                live_admin=own_usage.ru_utime+own_usage.ru_stime+administrative_reaped_before_child-cpu0
                c.require(live_admin<a['administrative_live_CPU_cap']*.95,
                          'live conditional control CPU reserve exhausted; held child must drain')
                if time.time()>=child['expires_epoch']:
                    stop_held(worker,child_identity)
                time.sleep(.5)
            _,status,usage=os.wait4(worker.pid,0);reaped=True;worker.returncode=os.waitstatus_to_exitcode(status)
            scientific_reaped=usage.ru_utime+usage.ru_stime
        c.require(worker.returncode==0,'EE child failed; no automatic continuation/retry')
        eeout=Path(child['output_dir'])
        assessment=c.read(eeout/'assessment.json')
        c.require(assessment['new_S0']==2 and assessment['new_D']==0 and assessment['new_component_names']==prep['remaining_component_names'],
                  'exact EE completion assessment absent')
        c.require(c.read(eeout/'assessment_seal.json')['assessment']==c.pin(eeout/'assessment.json'),'EE assessment seal differs')
        c.require(c.read(eeout/'supervisor_exit_receipt.json')['child_exit_code']==0,'EE supervisor did not complete')
        supervisor=c.read(eeout/'supervisor_exit_receipt.json')
        for old in (supervisor['parent'],supervisor['payload']):
            c.require(not c.same_lifetime(c.process_identity(old['pid']),old),'EE numerical lifetime has not drained')
        same_free_inode(child)
        administrative=c.cpu_seconds()-cpu0-scientific_reaped
        c.immutable(out/'exit_receipt.json',dict(status='COMPLETE_EE_AFTER_LV_NOT_PROMOTED',source=identity,
            assessment=c.pin(eeout/'assessment.json'),child_authority=c.pin(out/'derived_EE_authority.json'),
            measured_administrative_CPU_seconds=administrative,scientific_reaped_CPU_seconds=scientific_reaped,
            inclusive_own_and_reaped_CPU_seconds=c.cpu_seconds()-cpu0,
            new_preparation_conservative_debit=600,combined_new_CPU_cap=a['combined_new_CPU_cap'],
            previous_paid_scope=a['previous_paid_scope'],old_unused_budget_credited=False,
            automatic_retry=False,automatic_extra_seed_dispatch=False))
        return c.read(out/'exit_receipt.json')
    except BaseException as exc:
        if worker is not None and not reaped:
            try:
                stop_held(worker,child_identity)
                _,status,usage=os.wait4(worker.pid,0);worker.returncode=os.waitstatus_to_exitcode(status)
                scientific_reaped=usage.ru_utime+usage.ru_stime;reaped=True
            except (ChildProcessError,ProcessLookupError):pass
        c.immutable(out/'exit_receipt.json',dict(status='STOPPED_NO_RETRY',source=identity,
            exception_type=type(exc).__name__,reason=str(exc),
            peer_observation=getattr(exc,'evidence',None),scientific_reaped_CPU_seconds=scientific_reaped,
            inclusive_own_and_reaped_CPU_seconds=c.cpu_seconds()-cpu0,
            prior_preparation_debit=600,claims_and_failed_charges_retained=True,
            first_T0=a['start_epoch'],expiry=a['expires_epoch'],automatic_retry=False))
        raise


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--endowment',required=True);parser.add_argument('--endowment-sha256',required=True)
    args=parser.parse_args()
    print(json.dumps(execute(args.endowment,args.endowment_sha256),sort_keys=True,indent=2))
