#!/usr/bin/env python3
"""Once-only, CPU31 administrative EE→LV chain for two exact admitted grants.

This entry executes no model or numerical library itself. Every child retains
its own original authority clocks and revalidates its full scientific prefix.
An EE failure, busy permit, missing seal/drain or expired LV stops the chain.
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
from pricefm_r154_prediction_contract import (cpu_seconds,digest,immutable,pin,read,require,
    process_identity,same_lifetime,source_identity,validate_authority,verify_hashes,verify_pin)
ROOT=Path(__file__).resolve().parents[3]
ENTRY=Path(__file__).resolve()
PREDICTION_ENTRY=ENTRY.with_name('521_run_pricefm_stage_r154_predictions.py')
DATA=Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
QUEUE_AUDIT=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021/r154_parallel_repair_20261026/screening/serial_queues')


def permit_free(global_contract,permit_id):
    directory=Path(global_contract['lock_dir']);directory.mkdir(parents=True,exist_ok=True)
    with (directory/(permit_id+'.lock')).open('a+') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return False
        return True


def validate_queue(a,identity,now,host):
    require(a.get('schema')=='r154_serial_queue_authority_v1' and a.get('status')=='ADMITTED', 'queue authority absent')
    require(a['source']==identity and a['host']==host and a.get('administrative_cpu')==31,'queue source/host/admin core differs')
    require(a['new_fits']==0 and a['new_forecasts']==0 and a['automatic_retry'] is False,'queue cannot admit science or retry')
    require(a['nonrenewing'] is True and a['start_epoch']<=now<a['expires_epoch']
            and a['expires_epoch']-a['start_epoch']<=a['max_wall_seconds'],'queue absolute clock invalid')
    require(0<a['max_CPU_seconds']<=360 and a['max_wall_seconds']<=86400,'queue administrative envelope unbounded')
    require(a.get('scope_id') and Path(a['output_dir']).name=='pricefm_stage_r154_queue_'+a['scope_id']
            and Path(a['output_dir']).parent in (DATA/'campaigns',QUEUE_AUDIT),'new queue namespace required')
    verify_hashes(a['source_sha256'])
    require(digest(a['python'])==a['python_sha256'],'pinned interpreter bytes differ')
    require(Path(a['python']).resolve()==Path(sys.executable).resolve(),'queue interpreter differs from declared Python')
    verify_pin(a['global_contract'])
    glob=read(a['global_contract']['path'])
    require(glob['created_epoch']<=a['start_epoch'] and a['expires_epoch']<=glob['expires_epoch'], 'queue exceeds original pool clock')
    require([r['study'] for r in a['stages']]==['EE','LV'],'exact EE then LV stages required')
    grants=[]
    for stage in a['stages']:
        authority=verify_pin(stage['authority'])
        prep=verify_pin(stage['preparation'])
        require(authority['preparation']==stage['preparation'] and authority['study']==stage['study'], 'stage binding differs')
        require(authority['source']==identity and authority['global_contract']==a['global_contract'], 'stage source/pool differs')
        require(authority['status']=='ADMITTED' and authority['schema']=='r154_prediction_authority_v1', 'both studies must already be fully admitted')
        validate_authority(authority,prep,stage['preparation']['path'],identity,now,host)
        require(not (Path(authority['output_dir'])/'claim.json').exists(), 'existing stage claim cannot be reused')
        grants.append((stage,authority,prep))
    require(grants[0][1]['permit_id']==grants[1][1]['permit_id'],'same serial permit required')
    return glob,grants


def complete_and_drained(study,authority,identity):
    out=Path(authority['output_dir'])
    seal=read(out/'assessment_seal.json')
    require(seal['assessment']==pin(out/'assessment.json'),'assessment bytes/seal differ')
    execution=seal['execution']
    require(execution['source']==identity and execution['scope_id']==authority['scope_id']
            and execution['authority']==pin(out/'authority.json'),'assessment execution lineage differs')
    assessment=read(out/'assessment.json')
    expected='COMPLETE_INITIAL_PREFIX' if study=='EE' else 'COMPLETE_TRAINING_DIAGNOSTIC'
    require(assessment['status'].startswith(expected),'incomplete/failed scientific stage')
    receipt=read(out/'supervisor_exit_receipt.json')
    require(receipt['child_exit_code']==0,'payload failed before physical drain')
    for name in ('parent','payload'):
        original=receipt[name]
        require(not same_lifetime(process_identity(original['pid']),original),'old exact stage lifetime still present')
    return dict(assessment=pin(out/'assessment.json'),assessment_seal=pin(out/'assessment_seal.json'),
                supervisor_receipt=pin(out/'supervisor_exit_receipt.json'),physical_drain=True)


def child_live_CPU_limit(authority):
    return math.ceil(authority['total_CPU_cap']-authority['prior_CPU_charged_seconds'])


def apply_queue_CPU_limits(admin_CPU,grants):
    """Bound own SOFT CPU while preserving funded child HARD inheritance."""
    required=max(child_live_CPU_limit(authority) for _,authority,_ in grants)
    usage=resource.getrusage(resource.RUSAGE_SELF)
    soft=math.floor(usage.ru_utime+usage.ru_stime+admin_CPU)
    hard=max(required,soft)
    inherited=resource.getrlimit(resource.RLIMIT_CPU)[1]
    require(inherited==resource.RLIM_INFINITY or inherited>=hard,'inherited hard CPU limit cannot fund stage children')
    signal.signal(signal.SIGXCPU,signal.SIG_DFL)
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    resource.setrlimit(resource.RLIMIT_CPU,(soft,hard))
    return dict(administrative_soft_CPU_limit=soft,inherited_child_hard_CPU_ceiling=hard)


def parent_death_arm(expected_parent,CPU_hard):
    """Popen direct child only; kernel kills the worker if queue parent dies."""
    libc=ctypes.CDLL(None,use_errno=True)
    if libc.prctl(1,signal.SIGKILL,0,0,0)!=0 or os.getppid()!=expected_parent:
        os._exit(125)
    # The new child may raise its own SOFT limit only within the separately
    # funded inherited HARD ceiling. Never inherit the queue's tiny admin cap.
    signal.signal(signal.SIGXCPU,signal.SIG_DFL)
    resource.setrlimit(resource.RLIMIT_CPU,(CPU_hard,CPU_hard))


def run_stage(stage,authority,prep,identity,out,queue_expiry,queue_local_deadline,python):
    # Re-evaluate BOTH fixed absolute and active windows now, never reset T0.
    validate_authority(authority,prep,stage['preparation']['path'],identity,time.time(),socket.gethostname().split('.')[0])
    require(permit_free(read(authority['global_contract']['path']),authority['permit_id']), 'shared permit busy; no retry')
    name=stage['study']
    immutable(out/(name+'_launch_intent.json'),dict(stage=stage,authority=stage['authority'],
        argv=[python,'-B',str(PREDICTION_ENTRY),'--preparation',stage['preparation']['path'],
              '--authority',stage['authority']['path'],'--authority-sha256',stage['authority']['sha256']],
        original_start_epoch=authority['start_epoch'],original_expires_epoch=authority['expires_epoch'],
        active_execution_window_seconds=authority['max_execution_wall_seconds'],epoch=time.time(),attempt=1))
    stdout=(out/(name+'_stdout.log')).open('xb');stderr=(out/(name+'_stderr.log')).open('xb')
    parent=os.getpid()
    worker=subprocess.Popen([python,'-B',str(PREDICTION_ENTRY),'--preparation',stage['preparation']['path'],
        '--authority',stage['authority']['path'],'--authority-sha256',stage['authority']['sha256']],
        cwd=ROOT,stdout=stdout,stderr=stderr,start_new_session=True,
        preexec_fn=lambda:parent_death_arm(parent,child_live_CPU_limit(authority)))
    immutable(out/(name+'_process.json'),dict(process=process_identity(worker.pid),authority=stage['authority'],
        parent=process_identity(parent),kernel_parent_death_signal='SIGKILL'))
    try:
        while worker.poll() is None:
            if time.time()>=queue_expiry or time.monotonic()>=queue_local_deadline:
                # Popen's sole calling thread still holds this direct child
                # unreaped. Its PID cannot recycle before this exact wait.
                worker.kill();worker.wait()
                raise RuntimeError('fixed queue clock exhausted; no next stage')
            time.sleep(2)
        code=worker.wait()
    finally:
        stdout.close();stderr.close()
    immutable(out/(name+'_wait_receipt.json'),dict(exit_code=code,epoch=time.time(),
        stdout=pin(out/(name+'_stdout.log')),stderr=pin(out/(name+'_stderr.log')),
        original_authority=stage['authority'],automatic_retry=False))
    require(code==0,'stage process failed; queue stopped')
    proof=complete_and_drained(name,authority,identity)
    require(permit_free(read(authority['global_contract']['path']),authority['permit_id']),'stage permit still held after process reap')
    immutable(out/(name+'_closed.json'),proof)
    return proof


def run_chain(grants,run_one):
    """Separate testable once-only order; exceptions prevent a later dispatch."""
    result=[]
    for stage,authority,prep in grants:result.append(run_one(stage,authority,prep))
    return result


def execute(authority_path,authority_sha):
    require(digest(authority_path)==authority_sha,'exact queue authority pin required')
    a=read(authority_path);identity=source_identity(ROOT)
    glob,grants=validate_queue(a,identity,time.time(),socket.gethostname().split('.')[0])
    os.sched_setaffinity(0,{31})
    require(os.sched_getaffinity(0)=={31},'administrative queue CPU differs')
    require(len(list(Path('/proc/self/task').iterdir()))==1 and signal.getsignal(signal.SIGCHLD)==signal.SIG_DFL,
            'queue must have one thread/default sole child waiter')
    limits=apply_queue_CPU_limits(a['max_CPU_seconds'],grants)
    out=Path(a['output_dir']);out.mkdir(parents=True,exist_ok=True)
    require(not (out/'claim.json').exists(),'queue claim already consumed')
    immutable(out/'claim.json',dict(authority=pin(authority_path),source=identity,process=process_identity(os.getpid()),
        stages=a['stages'],created_epoch=time.time(),automatic_retry=False,new_fits=0,new_forecasts=0))
    immutable(out/'administrative_CPU_limits.json',limits)
    started=time.monotonic();cpu0=cpu_seconds()
    usage0=resource.getrusage(resource.RUSAGE_SELF)
    local_deadline=started+a['max_wall_seconds']
    try:
        results=run_chain(grants,lambda s,g,p:run_stage(s,g,p,identity,out,a['expires_epoch'],local_deadline,a['python']))
        status='COMPLETE_EE_INITIAL_PREFIX_AND_LV_DIAGNOSTIC_NOT_PROMOTED'
    except BaseException as exc:
        immutable(out/'exit_receipt.json',dict(status='STOPPED_NO_RETRY',reason=str(exc),type=type(exc).__name__,
            measured_combined_reaped_CPU_seconds=cpu_seconds()-cpu0,elapsed_seconds=time.monotonic()-started,
            inclusive_CPU_must_not_be_added_again_to_stage_CPU=True,
            claim_consumed=True,source=identity))
        raise
    result=dict(status=status,stages=results,measured_combined_reaped_CPU_seconds=cpu_seconds()-cpu0,
        measured_administrative_own_CPU_seconds=(resource.getrusage(resource.RUSAGE_SELF).ru_utime+
            resource.getrusage(resource.RUSAGE_SELF).ru_stime-usage0.ru_utime-usage0.ru_stime),
        inclusive_CPU_must_not_be_added_again_to_stage_CPU=True,
        elapsed_seconds=time.monotonic()-started,source=identity,automatic_followon=False,new_fits=0,
        official_origins=0,promotion_authorized=False)
    immutable(out/'exit_receipt.json',result)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--authority',required=True);parser.add_argument('--authority-sha256',required=True)
    args=parser.parse_args();print(json.dumps(execute(args.authority,args.authority_sha256),sort_keys=True,indent=2))


if __name__=='__main__':main()
