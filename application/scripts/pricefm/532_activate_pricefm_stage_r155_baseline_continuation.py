#!/usr/bin/env python3
"""Activate exactly one independently admitted fifth baseline controller.

This entry is deliberately separate from health inspection. It preserves every
old runtime/registration and never signals a controller or numerical process.
"""
import argparse
import copy
import fcntl
import importlib.util
import json
import math
import os
from pathlib import Path
import resource
import subprocess
import sys
import time
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
import pricefm_r155_baseline_contract as c


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


def wrapper_usage():
    own=resource.getrusage(resource.RUSAGE_SELF);child=resource.getrusage(resource.RUSAGE_CHILDREN)
    raw=Path('/proc/self/stat').read_text();fields=raw[raw.rfind(')')+2:].split()
    return dict(own_CPU_seconds=own.ru_utime+own.ru_stime,reaped_subprocess_CPU_seconds=child.ru_utime+child.ru_stime,
        whole_invocation_own_plus_reaped_CPU=own.ru_utime+own.ru_stime+child.ru_utime+child.ru_stime,
        whole_process_elapsed_seconds=time.clock_gettime(time.CLOCK_BOOTTIME)-int(fields[19])/os.sysconf('SC_CLK_TCK'))


def wrapper_budget(a):
    usage=wrapper_usage();reserve=a['activation_wrapper_CPU_reserve'];drain=2.
    c.require(usage['whole_invocation_own_plus_reaped_CPU']+drain<reserve,
        'whole invocation startup/preflight/live CPU exhausted the funded activation reserve')
    cap=math.floor(reserve-usage['reaped_subprocess_CPU_seconds']);inherited=resource.getrlimit(resource.RLIMIT_CPU)[1]
    if inherited!=resource.RLIM_INFINITY:cap=min(cap,inherited)
    c.require(usage['own_CPU_seconds']+drain<cap,'remaining activation own-process CPU hard limit is insufficient')
    resource.setrlimit(resource.RLIMIT_CPU,(cap,cap));resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    return usage


def activation_disposition(proof):
    if proof.get('healthy_control') is True:return 'ONE_FIFTH_CONTROL_ACTIVATION_HEALTHY_NO_RETRY'
    if proof.get('healthy_control') is None:return 'ONE_FIFTH_CONTROL_ACTIVATION_METADATA_PENDING_NO_RETRY'
    return 'ONE_FIFTH_CONTROL_ACTIVATION_BLOCKED_AFTER_REGISTRATION_NO_RETRY'


def start_control(record,a,log):
    c.require(time.time()+a['unit_runtime_max_seconds']+30<=c.ORIGINAL_EXPIRY,
        'fixed new unit runtime no longer fits the original expiry plus bounded launch margin')
    wrapper_budget(a)
    argv=['systemd-run','--user','--quiet','--unit='+record['unit'],
        '--description=R155 explicit fifth baseline control '+record['mode'],
        '--property=Restart=no','--property=KillMode=process','--property=RemainAfterExit=yes',
        '--property=TimeoutStopSec=20s','--property=RuntimeMaxSec='+str(a['unit_runtime_max_seconds'])+'s',
        '--property=WorkingDirectory='+str(c.ROOT),'--property=CPUAffinity=31',
        '--property=CPUSchedulingPolicy=other','--property=Nice='+str(record['nice']),
        '--property=IOSchedulingClass=idle','--property=CPUAccounting=yes','--property=MemoryAccounting=yes',
        '--property=LimitCPU='+str(record['CPU_hard_limit']),
        '--property=StandardOutput=file:'+str(log),'--property=StandardError=file:'+str(log)+'.stderr']
    argv+=['--setenv='+key+'=1' for key in c.core().THREAD_ENV]
    argv+=['--setenv=PYTHONDONTWRITEBYTECODE=1',*record['argv']]
    subprocess.run(argv,check=True,timeout=20)
    return argv


def attest(record,a,system,api):
    deadline=time.monotonic()+20;label='owner' if record['mode']=='run' else 'guardian';last=None
    while time.monotonic()<deadline:
        wrapper_budget(a)
        props=system.unit(record['unit']);pid=int(props.get('MainPID',0));current=system.process(pid) if pid else None
        if current and props.get('ActiveState')=='active':
            c.require(time.time()+a['unit_runtime_max_seconds']<=c.ORIGINAL_EXPIRY,
                'actual attested new unit runtime cannot be proved inside the original expiry')
            capsule=dict(intent=record,process=current,unit_properties=props,attested_epoch=time.time())
            api.control_capsule(a,{label:capsule},record['mode'],system)
            return capsule
        last=dict(unit=props,process=current);time.sleep(.1)
    raise RuntimeError('bounded new administrative unit attestation expired: '+repr(last))


def activate(path,sha):
    c.require(os.sched_getaffinity(0)=={31},'activation wrapper must enter administrative31')
    wrapper_budget(dict(activation_wrapper_CPU_reserve=30))
    path=Path(path).resolve();a=c.validate_authority(path,sha,unclaimed=True)
    c.require(time.time()-a['activation_epoch']<=300,'new materialized authority activation window expired; no claim consumed')
    c.require(not any(name in sys.modules for name in ('numpy','scipy','pandas')),'activation wrapper imported numerical libraries')
    # Only this standalone administrative wrapper is limited. The new owner
    # explicitly inherits unlimited per-process CPU, preserving original science.
    wrapper_budget(a);started=time.monotonic()
    c.verify_source(a['execution_source'],remote=True)
    system=c.System(a['expected_host_pid_namespace']);runtime=Path(a['runtime'])
    try:
        predecessor=c.verify_predecessor(a,system,require_full_census=True);c.verify_original_locks(a,require_free=True)
        config=c.core().read_config(predecessor['authority']['legacy_config_path']);policy=c.old.ContractPolicy(config,system)
        for job in predecessor['state']['active'].values():
            c.old.session_members(copy.deepcopy(job),system,policy,census=predecessor['census'])
        policy.verify_sources()
    except c.CensusDeferred as deferred:
        return dict(status='DEFER_ALL_NEW_DISPATCH_NO_ACTIVATION_CLAIM',authority=c.pin(path),
            observation=deferred.observation,services_started=0,numerical_worker_signals=0,automatic_retry=False,
            whole_invocation_usage=wrapper_usage(),startup_and_prevalidation_CPU_included=True,
            final_publication_and_exit_CPU_reserved_seconds=2)
    runtime.mkdir(parents=True,exist_ok=True)
    lock_path=runtime/'release.lock';c.require(not lock_path.is_symlink(),'release lock is a symlink')
    with lock_path.open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        st=lock_path.stat();fd=os.fstat(lock.fileno());c.require((st.st_dev,st.st_ino)==(fd.st_dev,fd.st_ino),'release lock replaced')
        c.validate_authority(path,sha,unclaimed=True)
        wrapper_budget(a)
        # Fresh fixed dispatch flocks and exact old administrative drain again
        # after obtaining the new release lock, before spending the sole claim.
        c.verify_predecessor(a,system);c.verify_original_locks(a,require_free=True)
        c.require(time.time()+a['unit_runtime_max_seconds']+30<=c.ORIGINAL_EXPIRY,
            'activation preflight consumed the original unit-deadline margin; no claim consumed')
        c.core().immutable(runtime/'authority.json',a)
        c.core().immutable(runtime/'activation_claim.json',dict(schema='r155_baseline_owner5_activation_claim_v1',
            authority=c.pin(path),activation=c.ACTIVATION,execution_source=a['execution_source'],
            original_absolute_expiry=c.ORIGINAL_EXPIRY,original_cumulative_CPU=c.ORIGINAL_CPU,
            new_unit=a['new_unit'],guardian_unit=a['guardian_unit'],claimed_epoch=time.time(),claimant_pid=os.getpid(),
            numerical_worker_signals=0,automatic_retry=False))
        api=module('r155_actual_baseline_owner_api',Path(__file__).with_name('530_supervise_pricefm_stage_r155_baseline_continuation.py'))
        observer=module('r155_actual_baseline_health_api',Path(__file__).with_name('533_inspect_pricefm_stage_r155_baseline_continuation.py'))
        launches=[]
        try:
            for label,key in (('owner','control_intent'),('guardian','guardian_intent')):
                launches.append(dict(label=label,argv=start_control(a[key],a,runtime/(label+'.log'))))
            owner=attest(a['control_intent'],a,system,api);guardian=attest(a['guardian_intent'],a,system,api)
            c.core().immutable(runtime/'launch_attestation.json',dict(schema='r155_baseline_owner5_launch_attestation_v1',
                authority=c.pin(path),execution_source=a['execution_source'],owner=owner,guardian=guardian,
                exact_launch_commands=launches,epoch=time.time()))
            deadline=time.monotonic()+75;last=None
            while time.monotonic()<deadline:
                wrapper_budget(a)
                if (runtime/'ready.json').is_file():
                    try:ready=c.read_published(runtime/'ready.json',deadline=deadline,max_wait_seconds=1.)
                    except c.PublicationPending as pending:
                        last=pending.observation;time.sleep(.025);continue
                    c.require(ready['authority']==c.pin(path) and ready['activation']==c.ACTIVATION
                        and ready['execution_source']==a['execution_source'],'new control readiness source differs')
                    last=observer.inspect(path,sha,system)
                    if last.get('healthy_control') is True:
                        wrapper_budget(a)
                        c.core().immutable(runtime/'registration.json',dict(schema='r155_baseline_owner5_registration_v1',
                            kind='EXPLICIT_FIFTH_BASELINE_CONTROL_ONLY',authority=c.pin(path),activation=c.ACTIVATION,
                            execution_source=a['execution_source'],runtime=str(runtime),cached_restart_authorized=False,
                            original_registration_unchanged=c.verify_pin(a['preparation'])['original_pointer_preserved'],
                            registered_epoch=time.time()))
                        immediate=observer.inspect(path,sha,system)
                        usage=wrapper_budget(a);cpu=usage['whole_invocation_own_plus_reaped_CPU']
                        c.require(cpu<a['activation_wrapper_CPU_reserve'],'finite activation wrapper CPU reservation exhausted')
                        receipt=dict(status=activation_disposition(immediate),authority=c.pin(path),
                            execution_source=a['execution_source'],activation=c.ACTIVATION,immediate_proof=immediate,
                            activation_spent=True,healthy_control=immediate.get('healthy_control'),
                            dispatch_currently_permitted=immediate.get('dispatch_currently_permitted') is True,
                            registration=c.pin(runtime/'registration.json'),administrative_own_plus_reaped_CPU=cpu,
                            whole_invocation_usage=usage,startup_and_prevalidation_CPU_included=True,
                            measured_through_before_final_receipt_write=True,final_publication_and_exit_CPU_reserved_seconds=2,
                            wrapper_CPU_fully_reserved_in_prior=a['activation_wrapper_CPU_reserve'],
                            metadata_publication_observations=c.PUBLICATION_OBSERVATIONS[-64:],
                            elapsed_seconds=time.monotonic()-started,numerical_worker_signals=0,automatic_retry=False,epoch=time.time())
                        c.core().immutable(runtime/'activation_verified.json',receipt);return receipt
                time.sleep(.2)
            raise RuntimeError('new fifth control did not reach bounded readiness: '+repr(last))
        except BaseException as error:
            # No controller, fit or service is signalled. A missing publication
            # keeps every new dispatch held; bounded bootstrap/lease/unit expiry
            # closes the new controls naturally. The spent claim cannot retry.
            c.core().immutable(runtime/'activation_failed.json',dict(authority=c.pin(path),error=repr(error),
                activation_spent=True,launches=launches,numerical_worker_signals=0,control_signals=0,
                whole_invocation_usage=wrapper_usage(),startup_and_prevalidation_CPU_included=True,
                measured_through_before_failure_receipt_write=True,final_publication_and_exit_CPU_reserved_seconds=2,
                metadata_publication_observations=c.PUBLICATION_OBSERVATIONS[-64:],
                automatic_retry=False,epoch=time.time()))
            raise


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--authority',required=True)
    parser.add_argument('--authority-sha256',required=True);args=parser.parse_args()
    try:result=activate(args.authority,args.authority_sha256)
    except BaseException as error:
        print(json.dumps(dict(status='ACTIVATION_INVOCATION_FAILED',error=repr(error),whole_invocation_usage=wrapper_usage(),
            startup_and_prevalidation_CPU_included=True,automatic_retry=False,numerical_worker_signals=0),sort_keys=True),file=sys.stderr)
        raise
    print(json.dumps(result,indent=2,sort_keys=True,allow_nan=False))
