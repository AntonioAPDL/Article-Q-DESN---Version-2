#!/usr/bin/env python3
"""One explicitly admitted sixth baseline control owner; original science stays frozen."""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import pricefm_r155_baseline_contract as c
ROOT=c.ROOT;ENTRY=Path(__file__).resolve()
TERMINAL={'complete','blocked','control_expired','control_budget_exhausted'}


def cpu_limits(pid):
    line=next(line for line in (Path('/proc')/str(pid)/'limits').read_text().splitlines() if line.startswith('Max cpu time'))
    match=re.fullmatch(r'Max cpu time\s+(\S+)\s+(\S+)\s+seconds\s*',line)
    c.require(match is not None,'control inherited CPU limits unreadable')
    return match.group(1),match.group(2)


def observe_control_capsule(a,attestation,mode,system):
    """All final readiness predicates with explicit unavailable kernel facts."""
    label='owner' if mode=='run' else 'guardian';expected=a['control_intent' if mode=='run' else 'guardian_intent']
    capsule=attestation[label];current=system.process(capsule['process']['pid']);props=system.unit(expected['unit'])
    checks=dict(process_present=current is not None,intent=capsule['intent']==expected)
    checks.update(same_process=c.core().same_process(current,capsule['process']),
        active=props.get('ActiveState')=='active',running=props.get('SubState')=='running',
        invocation=bool(props.get('InvocationID')) and props.get('InvocationID')==capsule['unit_properties'].get('InvocationID'),
        restart=props.get('Restart')=='no',restart_count=props.get('NRestarts')=='0',kill_mode=props.get('KillMode')=='process',
        retained=props.get('RemainAfterExit')=='yes',unit_cwd=props.get('WorkingDirectory')==str(ROOT),
        unit_IO_class=props.get('IOSchedulingClass')=='3',
        unit_entry=str(ENTRY) in props.get('ExecStart',''),unit_nice=props.get('Nice')==str(expected['unit_nice']),
        original_deadline=c.old.runtime_seconds(props.get('RuntimeMaxUSec',''))==a['unit_runtime_max_seconds'])
    kernel={};errors=[]
    if current is not None:
        checks.update(argv=current['argv']==expected['argv'],cwd=current['cwd']==str(ROOT),uids=current['uids']==[os.getuid()]*4,
            affinity=current['cpus']==[31],main_pid=props.get('MainPID')==str(current['pid']))
        try:
            kernel=dict(nice=os.getpriority(os.PRIO_PROCESS,current['pid']),scheduler=os.sched_getscheduler(current['pid']),
                cpu_limits=cpu_limits(current['pid']),executable=os.readlink(Path('/proc')/str(current['pid'])/'exe'),
                threads=[dict(tid=int(thread.name),cpus=sorted(os.sched_getaffinity(int(thread.name))))
                    for thread in (Path('/proc')/str(current['pid'])/'task').iterdir()])
        except OSError as error:errors.append(dict(error=type(error).__name__,detail=str(error)))
    required=('unlimited','unlimited') if mode=='run' else ('600','600')
    checks.update(kernel_available=bool(kernel) and not errors,kernel_nice=kernel.get('nice')==expected['kernel_nice'],
        kernel_scheduler=kernel.get('scheduler')==os.SCHED_OTHER,kernel_cpu_limits=kernel.get('cpu_limits')==required,
        kernel_executable=bool(kernel.get('executable')) and Path(kernel['executable']).resolve()==Path(expected['argv'][0]).resolve(),
        every_thread_affinity=bool(kernel.get('threads')) and all(thread['cpus']==[31] for thread in kernel['threads']))
    return dict(label=label,epoch=time.time(),checks=checks,all_pass=all(checks.values()),
        failed_fields=[key for key,value in checks.items() if not value],process=current,unit_properties=props,
        kernel=kernel,actual_kernel_IO_class_independently_verified=False,unavailable=errors,expected_intent=expected)


def control_capsule(a,attestation,mode,system):
    observation=observe_control_capsule(a,attestation,mode,system)
    if not observation['all_pass']:
        error=RuntimeError('actual new control capsule failed: '+repr(observation['failed_fields']))
        error.observation=observation;raise error
    return observation['process'],observation['unit_properties']


def wait_attestation(a,path,mode,unit,system):
    c.require(unit==a['new_unit' if mode=='run' else 'guardian_unit'],'entry unit differs from authority')
    deadline=time.monotonic()+30;record=Path(a['runtime'])/'launch_attestation.json'
    while True:
        c.require(time.monotonic()<deadline,'bounded new control attestation wait expired')
        if not record.is_file():system.sleep(.025);continue
        try:attestation=c.read_published(record,deadline=deadline,max_wait_seconds=1.)
        except c.PublicationPending:continue
        break
    c.require(attestation['authority']==c.pin(path) and attestation['execution_source']==a['execution_source'],
        'actual new launch attestation authority/source differs')
    current,_=control_capsule(a,attestation,mode,system)
    c.require(current['pid']==os.getpid(),'control entry is not its own attested process')
    return attestation,current


def budget(a,state,system,now=None):
    now=time.time() if now is None else now
    guardian_path=Path(a['runtime'])/'guardian_heartbeat.json'
    guardian=c.read(guardian_path) if guardian_path.is_file() else {}
    own=system.cpu_seconds(state['owner']['pid'],state['owner']['start_ticks'])
    actual_guardian=guardian.get('control_CPU_seconds',0.)
    heavy=state.get('heavy_source_checks',0)*a['grant']['administrative_source_check_CPU_reservation']
    polls=state.get('poll_count',0)*a['grant']['administrative_poll_CPU_reservation']
    # Administrative subprocess reservations avoid including scientific-child
    # rusage in the owner budget. Guardian600 and exit100 are fully retained.
    charged=a['grant']['prior_control_CPU_seconds']+own+heavy+polls+a['guardian_CPU_reserve']+100
    return dict(owner_actual_CPU_seconds=own,guardian_observed_CPU_seconds=actual_guardian,
        guardian_fully_reserved_CPU_seconds=a['guardian_CPU_reserve'],
        source_check_admin_reserved_CPU_seconds=heavy,poll_admin_reserved_CPU_seconds=polls,
        prior_control_CPU_seconds=a['grant']['prior_control_CPU_seconds'],final_control_tail_CPU_reserve=100,
        cumulative_control_charged_CPU_seconds=charged,control_ceiling_CPU_seconds=c.ORIGINAL_CPU,
        control_expires_epoch=c.ORIGINAL_EXPIRY,within_CPU=charged<c.ORIGINAL_CPU,
        within_wall=now<c.ORIGINAL_EXPIRY,within_guardian_CPU=actual_guardian<600,
        numerical_CPU_included=False,cgroup_CPU_used=False,hard_cgroup_CPU_enforcement_claimed=False)


def heartbeat(runtime,state,path,a,system):
    state['metadata_publication_observations']=c.PUBLICATION_OBSERVATIONS[-64:]
    state['epoch']=time.time();state['control_budget']=budget(a,state,system)
    c.core().atomic(runtime/'state.json',state)
    c.core().atomic(runtime/'resource_ownership_epoch.json',dict(schema='r155_baseline_owner_epoch_v1',
        authority=c.pin(path),activation=c.ACTIVATION,owner=state['owner'],guardian_unit=a['guardian_unit'],
        phase=state['phase'],heartbeat=state['epoch'],execution_source=a['execution_source'],
        control_budget=state['control_budget'],all_new_dispatch_deferred=state.get('all_new_dispatch_deferred',True)))


def guardian_live(a,attestation,system):
    current,_=control_capsule(a,attestation,'guard',system)
    receipt=c.read(Path(a['runtime'])/'guardian_heartbeat.json')
    c.require(c.core().same_process(current,receipt['process']) and receipt['authority_id']==a['authority_id']
        and time.time()-receipt['heartbeat']<=a['guardian_lease_seconds'] and receipt['status']=='running'
        and not (Path(a['runtime'])/'guardian_blocked.json').exists(),'new guardian lifetime/heartbeat/lease blocked dispatch')
    return current


def reconcile_sessions(state,system,policy):
    census=system.processes()
    for job in state['active'].values():c.old.session_members(job,system,policy,census=census)
    return census


def step_lanes(config,runtime,shared,state,master,system,policy):
    """Preserve the original queue and natural boundaries, with fresh full census."""
    for lane,queue in config['queues'].items():
        census=reconcile_sessions(state,system,policy)
        job=state['active'].get(lane)
        if job:
            if c.old.session_members(job,system,policy,census=census):continue
            region=job['region']
            if job['phase']=='prepare':
                preparation=policy.preparation_path(region)
                c.require(preparation.is_file() and c.read(preparation).get('source',{}).get('head')==config['source_head'],
                    'original preparation drained without exact immutable numerical preparation')
                state['active'][lane]=c.core().launch_region(config,runtime,lane,region,'controller',job['cpus'],system)
            elif c.core().complete_region(config,region):
                state['completed'][lane].append(region);del state['active'][lane]
                c.core().immutable(runtime/'regions'/(region+'.complete.json'),dict(region=region,
                    status='R155_ORIGINAL_BASELINE_NUMERICAL_SOURCE_PRESERVED',source_head=config['source_head'],
                    terminal_sha256=c.digest(c.core().campaign(config,region)/'terminal.json'),epoch=time.time()))
            else:
                diagnostics={};failures=c.failed_certificates(config,region,diagnostics)
                c.require(failures,'controller drained without strict closeout or required-fit original-cap blocker')
                c.core().immutable(runtime/'quarantine'/(region+'.json'),dict(region=region,lane=lane,
                    status='R155_REQUIRED_FIT_ORIGINAL_CAP_QUARANTINE',failed=failures,source_head=config['source_head'],
                    fit_retry_admitted=False,certificate_limits_changed=False,**diagnostics,epoch=time.time()))
                state['quarantined'][lane].append(region);del state['active'][lane]
            # A changed lane is reconciled by a new full scan on the next loop.
            return state
        pending=[region for region in queue if region not in state['completed'][lane] and region not in state['quarantined'][lane]]
        if not pending:continue
        region=pending[0]
        if c.core().complete_region(config,region):state['completed'][lane].append(region);return state
        preparation=policy.preparation_path(region);phase='controller' if preparation.is_file() else 'prepare'
        cpus=c.old.choose_cpus(config,lane,runtime,shared,master,system)
        state['active'][lane]=c.core().launch_region(config,runtime,lane,region,phase,cpus,system)
        return state
    return state


def record_defer(runtime,state,error):
    evidence=error.observation
    state.update(phase='deferred_census_visibility',all_new_dispatch_deferred=True,last_census=evidence)
    state['census_deferred_observations']=state.get('census_deferred_observations',0)+1
    stable=[dict(pid=p.get('pid'),stat=p.get('census_pre_read_stat'),uid=p.get('directory_uid'),
        predicates=p.get('protected_predicate_observations'),unavailable=p.get('unavailable_fields')) for p in evidence.get('unresolved',[])]
    key=hashlib.sha256(json.dumps(stable,sort_keys=True).encode()).hexdigest()
    path=runtime/'census_deferred'/(key+'.json')
    if not path.exists():c.core().immutable(path,dict(evidence=evidence,action='DEFER_ALL_NEW_DISPATCH',numerical_worker_signals=0))


def run(path,unit,system=None):
    path=Path(path).resolve();a=c.validate_authority(path);system=system or c.System(a['expected_host_pid_namespace'])
    runtime=Path(a['runtime']);attestation,current=wait_attestation(a,path,'run',unit,system)
    predecessor=c.verify_predecessor(a,system);prior=predecessor['authority'];state=copy.deepcopy(predecessor['state'])
    claim=c.read(runtime/'activation_claim.json')
    c.require(claim['authority']==c.pin(path) and claim['activation']==c.ACTIVATION,'new one-use activation claim differs')
    c.core().immutable(runtime/'owner_start.json',dict(authority=c.pin(path),owner=current,activation=c.ACTIVATION,
        InvocationID=attestation['owner']['unit_properties']['InvocationID'],epoch=time.time()))
    state['predecessor_error']=state.pop('error',None)
    state.update(schema='r155_baseline_control_state_v1',phase='adopted_ready',authority_id=a['authority_id'],
        authority=c.pin(path),predecessor_state=a['predecessor_state'],predecessor_activation=state['activation'],
        activation=c.ACTIVATION,legacy_resource_source=state['source'],source=a['execution_source'],new_unit=unit,
        owner=current,guardian_unit=a['guardian_unit'],heavy_source_checks=0,poll_count=0,
        numerical_worker_signals=0,all_new_dispatch_deferred=True,adoption_verified=False)
    config=c.core().read_config(prior['legacy_config_path']);policy=c.old.ContractPolicy(config,system)
    with c.core().fences(runtime,config,expected_locks=a['original_dispatch_locks']):
        try:
            c.verify_original_locks(a);c.verify_source(a['execution_source']);policy.verify_sources();state['heavy_source_checks']+=1
            heartbeat(runtime,state,path,a,system)
            deadline=time.monotonic()+30
            while not (runtime/'guardian_heartbeat.json').is_file():
                c.require(time.monotonic()<deadline,'bounded initial guardian readiness wait expired');system.sleep(.025)
            guardian_live(a,attestation,system)
            c.core().immutable(runtime/'ready.json',dict(authority=c.pin(path),activation=c.ACTIVATION,owner=current,
                execution_source=a['execution_source'],original_sessions_not_restarted=True,
                dispatch_held_until_registration_and_full_reconciliation=True,epoch=time.time()))
            last_heavy=time.monotonic()
            while True:
                state['poll_count']+=1;c.verify_original_locks(a)
                charge=budget(a,state,system)
                if not charge['within_wall'] or not charge['within_CPU'] or not charge['within_guardian_CPU']:
                    state.update(phase='control_expired' if not charge['within_wall'] else 'control_budget_exhausted',all_new_dispatch_deferred=True)
                    heartbeat(runtime,state,path,a,system)
                    c.core().immutable(runtime/'control_terminal.json',dict(status=state['phase'],authority=c.pin(path),
                        activation_spent=True,control_budget=state['control_budget'],numerical_worker_signals=0,epoch=time.time()))
                    return state
                guardian_live(a,attestation,system)
                if time.monotonic()-last_heavy>=a['source_verify_seconds']:
                    c.verify_source(a['execution_source']);policy.verify_sources()
                    c.old.frozen_context(prior,a['predecessor_authority']['path'])
                    c.core().verify_pins(config['source_sha256']);c.core().verify_pins(config['evidence_sha256'])
                    state['heavy_source_checks']+=1;last_heavy=time.monotonic()
                health=c.core().host_health(config);c.require(health['healthy'],'original baseline resource floor crossed')
                try:
                    reconcile_sessions(state,system,policy);state['adoption_verified']=True;state['last_census']=system.last_census
                    registration=runtime/'registration.json'
                    if not registration.is_file():
                        state.update(phase='waiting_registration',all_new_dispatch_deferred=True)
                        c.require(time.time()-attestation['epoch']<120,'bounded new registration wait expired')
                    else:
                        record=c.read(registration)
                        c.require(record['authority']==c.pin(path) and record['activation']==c.ACTIVATION
                            and record['execution_source']==a['execution_source'],'new separate owner5 registration differs')
                        state.update(phase='running',all_new_dispatch_deferred=False)
                        state=step_lanes(config,runtime,prior['legacy_shared_runtime'],state,
                            c.read(prior['legacy_master']['path']),system,policy)
                except c.CensusDeferred as deferred:record_defer(runtime,state,deferred)
                state['health']=health;state['approved_identity_events']=policy.events[-128:]
                done=all(len(state['completed'][lane])+len(state['quarantined'][lane])==len(queue) for lane,queue in config['queues'].items())
                if done and not state['all_new_dispatch_deferred']:state['phase']='complete'
                heartbeat(runtime,state,path,a,system);c.core().atomic(runtime/'progress.json',state)
                if state['phase']=='complete':
                    c.core().immutable(runtime/'terminal.json',dict(status='R155_ORIGINAL_NINE_TAIL_DISPOSITIONS_NOT_GLOBAL_PROMOTION',
                        authority=c.pin(path),activation=c.ACTIVATION,execution_source=a['execution_source'],
                        completed=state['completed'],quarantined=state['quarantined'],numerical_source_head=config['source_head'],
                        control_budget=state['control_budget'],numerical_worker_signals=0,epoch=time.time()))
                    return state
                system.sleep(a['poll_seconds'])
        except BaseException as error:
            state.update(phase='blocked',error=repr(error),all_new_dispatch_deferred=True)
            heartbeat(runtime,state,path,a,system)
            c.core().immutable(runtime/'blocked.json',dict(authority=c.pin(path),error=repr(error),activation_spent=True,
                numerical_worker_signals=0,cached_restart_authorized=False,epoch=time.time()))
            raise


def guard_once(path,unit,system,a,attestation,now=None):
    now=time.time() if now is None else now
    current,_=control_capsule(a,attestation,'guard',system)
    c.require(current['pid']==os.getpid() and unit==a['guardian_unit'],'guardian is not its exact attested process')
    runtime=Path(a['runtime'])
    c.core().atomic(runtime/'guardian_heartbeat.json',dict(authority_id=a['authority_id'],process=current,
        heartbeat=now,control_CPU_seconds=system.cpu_seconds(current['pid'],current['start_ticks']),status='running',numerical_worker_signals=0))
    if not (runtime/'state.json').is_file():
        if now-attestation['epoch']<30:return 'wait'
        reason='owner_never_published_initial_state'
    else:
        state=c.read(runtime/'state.json')
        c.require(state.get('authority')==c.pin(path) and state.get('activation')==c.ACTIVATION
            and state.get('source')==a['execution_source'],'guardian state source/authority/activation differs')
        if state.get('phase') in TERMINAL:return 'complete'
        try:
            owner,_=control_capsule(a,attestation,'run',system)
            try:epoch=c.read(runtime/'resource_ownership_epoch.json')
            except (FileNotFoundError,c.PublicationPending):
                if now-attestation['epoch']<30 and state.get('phase')=='adopted_ready' and c.core().same_process(owner,state.get('owner')):
                    return 'wait'
                raise
            c.require(c.core().same_process(owner,epoch['owner']) and epoch['authority']==c.pin(path)
                and epoch['activation']==c.ACTIVATION and epoch['execution_source']==a['execution_source']
                and now-epoch['heartbeat']<=a['guardian_lease_seconds'],'owner lifetime/lease differs')
            c.require(now<c.ORIGINAL_EXPIRY and epoch['control_budget']['within_CPU'],'original cumulative clock/budget exhausted')
            return 'wait'
        except (RuntimeError,OSError,KeyError) as error:reason=repr(error)
    c.core().immutable(runtime/'guardian_blocked.json',dict(authority=c.pin(path),reason=reason,
        owner_restart_attempts=0,numerical_worker_signals=0,epoch=now))
    return 'blocked'


def guard(path,unit,system=None):
    path=Path(path).resolve();a=c.validate_authority(path);system=system or c.System(a['expected_host_pid_namespace'])
    c.require(unit==a['guardian_unit'],'guardian bootstrap unit differs')
    bootstrap=c.establish_guardian_priority()
    c.core().immutable(Path(a['runtime'])/'guardian_priority_bootstrap.json',dict(authority=c.pin(path),
        execution_source=a['execution_source'],compatibility_proof=a['guardian_priority_compatibility_proof'],**bootstrap))
    attestation,_=wait_attestation(a,path,'guard',unit,system)
    while guard_once(path,unit,system,a,attestation)=='wait':system.sleep(a['poll_seconds'])


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['run','guard'])
    parser.add_argument('--authority',required=True);parser.add_argument('--unit',required=True);args=parser.parse_args()
    c.require(os.sched_getaffinity(0)=={31},'all new baseline administration must start on31')
    c.require(not any(key in sys.modules for key in ('numpy','scipy','pandas')),'administration imported numerical libraries')
    value=run(args.authority,args.unit) if args.action=='run' else guard(args.authority,args.unit)
    if value is not None:print(json.dumps(value,indent=2,sort_keys=True,allow_nan=False))


if __name__=='__main__':main()
