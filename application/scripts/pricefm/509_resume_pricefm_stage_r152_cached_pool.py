#!/usr/bin/env python3
"""One explicit parent recovery within the unchanged committed R152 scope.

The combined controller uses the original cba resource/scientific APIs by
composition. Its own execution source is separately attested; it never changes
imported globals, the original master, the failed parent or scientific inputs.
"""
from __future__ import annotations

import argparse
import contextlib
import importlib.util
import math
import os
from pathlib import Path
import signal
import sys
import time

ROOT=Path(__file__).resolve().parents[3]
ENTRY=Path(__file__).resolve()
OLD_ROOT=ROOT.parent/'pricefm_r152_parallel_20261024'
OLD_HEAD='cba0b6c861f20ebdffcd970d59b0fa38afd80a42'
_API=None
_AUTHORITY_API=None


def load_module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value)
    if any(key in sys.modules for key in ('numpy','scipy','pandas')):
        raise RuntimeError('recovery controller imported numerical dependencies')
    return value


def original_api():
    global _API
    if _API is None:
        _API=load_module('r152_recovery_original_pool',OLD_ROOT/'application/scripts/pricefm/505_run_pricefm_stage_r152_shared_pool.py')
    return _API


def validate_authority(path, *, system=None,require_empty=False,allow_expired=False):
    global _AUTHORITY_API
    if _AUTHORITY_API is None:
        _AUTHORITY_API=load_module('r152_recovery_release',ENTRY.with_name('510_release_pricefm_stage_r152_parent_recovery.py'))
    return _AUTHORITY_API.validate_authority(path,system=system,require_empty=require_empty,allow_expired=allow_expired)


def control_deadline(authority,capsule=None):
    expiry=authority['original_master']['expires_epoch']
    effective=authority['effective_parent_expires_epoch']
    if not math.isfinite(effective) or effective>expiry or effective<=authority['original_master']['start_epoch']:
        raise RuntimeError('recovery parent horizon differs from original scope')
    if capsule is not None:
        actual=capsule.get('actual_kernel_expires_epoch')
        if not isinstance(actual,(int,float)) or isinstance(actual,bool) or not math.isfinite(actual) or actual>expiry:
            raise RuntimeError('actual parent kernel deadline exceeds original master')
        effective=min(effective,actual)
    return effective


def planning_master(master,authority,capsule=None):
    """A calendar bound only. Never persist or pass this to a lease validator."""
    return dict(master,expires_epoch=min(master['expires_epoch'],control_deadline(authority,capsule)-90))


def claim_admission(api,runtime,master,study,kind,source_head,prep_sha,unit, *, authority,controller,projection,now=None):
    now=time.time() if now is None else now
    seconds={'numerical':7200,'benchmark':1200,'assessment':1800}[kind]
    if kind=='assessment':
        _,parent=api.current_admission(runtime,study)
        if parent is None:raise RuntimeError('assessment requires a current numerical window')
        seconds=min(seconds,min(master['expires_epoch']-5,parent['expires_epoch'])-now)
    if seconds<=0 or now+seconds+5>control_deadline(authority,controller)-90:
        raise RuntimeError('whole admission cannot fit the actual recovery parent horizon')
    approved=dict(projection,recovery_authority_sha256=authority['_authority_sha256'],
        recovery_control_deadline=control_deadline(authority,controller),recovery_admission_deadline=control_deadline(authority,controller)-90)
    return api.claim_admission(runtime,master,study,kind,source_head,prep_sha,unit,now=now,projection=approved)


def projection(api,runtime,master,c,studies,enabled,observation,authority,controller):
    value=api.projection(runtime,planning_master(master,authority,controller),c,studies,enabled,observation=observation)
    value.update(recovery_authority_sha256=authority['_authority_sha256'],
        recovery_control_deadline=control_deadline(authority,controller),recovery_admission_deadline=control_deadline(authority,controller)-90,
        original_master_expires_epoch=master['expires_epoch'])
    api.atomic(Path(runtime)/'latest_projection.json',value)
    return value


def admin_projection(api,runtime,master,c,studies,enabled,study,kind,cpu,observation,authority,controller):
    value=api.admin_projection(runtime,planning_master(master,authority,controller),c,studies,enabled,study,kind,cpu,observation)
    value.update(recovery_authority_sha256=authority['_authority_sha256'],recovery_control_deadline=control_deadline(authority,controller),
        recovery_admission_deadline=control_deadline(authority,controller)-90)
    return value


def await_baseline_ownership(api,shared,master, *, timeout=20,system=None):
    """Retry only the proved armed→first-master-heartbeat publication interval."""
    until=time.monotonic()+timeout
    while True:
        try:return api.baseline().baseline_ownership(Path(shared)/'baseline',master,system=system)
        except RuntimeError as error:
            if str(error)!='baseline ownership epoch/master/heartbeat differs':raise
            runtime=Path(shared)/'baseline'
            state=api.read(runtime/'state.json');epoch=api.read(runtime/'resource_ownership_epoch.json')
            fresh=time.time()-epoch.get('heartbeat',0)<20
            pending=(epoch.get('phase')=='armed' and epoch.get('expires_epoch') is None
                and state.get('phase') in ('armed','running') and fresh
                and state.get('scope_id')==epoch.get('scope_id')==master['scope_id']
                and state.get('source')==epoch.get('source')
                and epoch.get('source',{}).get('head')==master['source']['head'])
            if not pending or time.monotonic()>=until:raise
            time.sleep(.05)


def await_controller(api,system,c,authority,authority_path,unit, *, timeout=20):
    path=Path(authority['attestation_path']);until=time.monotonic()+timeout
    while not path.is_file():
        if time.monotonic()>=until or time.time()>=control_deadline(authority)-90:
            raise RuntimeError('bounded recovery controller attestation wait expired')
        time.sleep(.05)
    capsule=api.read(path);intent=authority['control_intent'];props=system.unit(unit)
    if (unit!=intent['unit'] or capsule.get('unit')!=unit
        or any(capsule.get(k)!=intent.get(k) for k in ('argv','description','source_head','source_entry_path','source_entry_sha256','runtime_seconds','parent'))
        or capsule.get('source_head')!=authority['execution_source']['head']
        or capsule.get('source_entry_path')!=str(ENTRY) or capsule.get('source_entry_sha256')!=api.digest(ENTRY)
        or capsule.get('parent') is not None
        or capsule.get('process',{}).get('pid')!=os.getpid()
        or int(props.get('MainPID',0))!=os.getpid()
        or capsule.get('attested',{}).get('InvocationID')!=props.get('InvocationID')
        or api.legacy().exec_arguments(props)!=' '.join(intent['argv'])):
        raise RuntimeError('recovery controller source/unit/intent/lifetime differs')
    api.verify_control_capsule(system,capsule,c)
    control_deadline(authority,capsule)
    return capsule


def control_CPU_with_children(api,system,capsule):
    """Own+waited-child CPU for live cgroup members; cgroup totals are a max."""
    observation=api.unit_observation(system,capsule);total=0.
    for pid in observation['live_pids']:
        before=api.legacy().process(pid)
        if before is None:continue
        try:fields=(Path('/proc')/str(pid)/'stat').read_text().rsplit(')',1)[1].split()
        except FileNotFoundError:continue
        if int(fields[19])!=before['start_ticks']:raise RuntimeError('control CPU PID lifetime changed during observation')
        ticks=[int(fields[i]) for i in (11,12,13,14)]
        if any(value<0 for value in ticks):raise RuntimeError('control CPU counters invalid')
        total+=sum(ticks)/os.sysconf('SC_CLK_TCK')
    return max(total,observation['cpu_seconds'])


def control_CPU_total(api,system,runtime,master,controls,authority):
    path=Path(authority['attestation_path']).parent/'control_CPU_samples.json'
    rows={}
    if path.is_file():
        stored=api.read(path)
        if stored.get('authority_sha256')!=authority['_authority_sha256'] or stored.get('scope_id')!=master['scope_id']:
            raise RuntimeError('control CPU history belongs to another recovery')
        rows=stored['units']
        if not isinstance(rows,dict) or any(not isinstance(row,dict) or not row.get('invocation_id')
                or not api.finite(row.get('CPU_seconds')) for row in rows.values()):
            raise RuntimeError('control CPU history amount or invocation invalid')
    for capsule in controls:
        unit=capsule['unit'];invocation=capsule['attested']['InvocationID']
        old=rows.get(unit,{})
        if old and old.get('invocation_id')!=invocation:raise RuntimeError('control CPU invocation history differs')
        amount=control_CPU_with_children(api,system,capsule)
        rows[unit]=dict(invocation_id=invocation,CPU_seconds=max(amount,old.get('CPU_seconds',0.)))
    api.atomic(path,dict(authority_sha256=authority['_authority_sha256'],scope_id=master['scope_id'],units=rows,epoch=time.time()))
    return authority['prior_control_debit']['CPU_seconds']+sum(row['CPU_seconds'] for row in rows.values())


def validate_live_authority(api,system,c,master,authority,validator,cache):
    """Full source pins once per poll; immutable identity checks on every call."""
    if api.digest(authority['_authority_path'])!=authority['_authority_sha256']:
        raise RuntimeError('immutable recovery authority bytes changed')
    key=(authority['_authority_sha256'],authority['original_master']['sha256'],master['scope_id'],
        master['source']['head'],authority['execution_source']['head'])
    if cache.get('key',key)!=key:raise RuntimeError('validation cache source/scope differs')
    now=time.monotonic();previous=cache.get('verified_monotonic')
    if previous is not None and now<previous:raise RuntimeError('validation cache monotonic clock regressed')
    if previous is None or now-previous>=min(5.,c['poll_seconds']):
        current=validator(authority['_authority_path'],system=system,require_empty=False)
        if current!={key:value for key,value in authority.items() if not key.startswith('_')}:
            raise RuntimeError('immutable recovery authority changed')
        if api.git(api.EE_ROOT,'rev-parse','HEAD')!=api.EE_HEAD or api.git(api.EE_ROOT,'status','--porcelain'):
            raise RuntimeError('immutable numerical EE source changed')
        cache.update(key=key,verified_monotonic=now)


def live_guard(api,system,c,shared,master,controller,studies,enabled,authority,validator,validation_cache):
    shared=Path(shared);runtime=shared/'development'
    validate_live_authority(api,system,c,master,authority,validator,validation_cache)
    api.validate_master(master,c)
    if (api.digest(shared/'master.json')!=authority['original_master']['sha256']
        or api.read(shared/'master.json')!=master or api.boot()!=master['boot_id']):
        raise RuntimeError('original master bytes or host boot changed')
    failed=authority['failed_parent']['capsule'];failed_state=api.unit_observation(system,failed)
    if failed_state['active'] or failed_state['members'] or not api.old_lifetime_absent(failed):
        raise RuntimeError('superseded original parent lifetime is not drained')
    api.baseline().baseline_ownership(shared/'baseline',master)
    controls=[controller]
    guardian=runtime/'guardian.json'
    if guardian.is_file():controls.append(api.read(guardian))
    for capsule in controls:api.verify_control_capsule(system,capsule,c)
    observation=api.observe_union(system,c,runtime,controls=controls)
    observation['control_CPU_seconds']=control_CPU_total(api,system,runtime,master,controls,authority)
    actual_science=dict(observation['science_charges'])
    actual_science['EE']=actual_science.get('EE',0.)+c['EE_historical_reservation_CPU_seconds']
    limits={'EE':c['EE_science_limit_CPU_seconds']}
    for name in ('FI','DK2'):
        try:limits[name]=api.study_limit(studies[name],c)
        except (OSError,RuntimeError,KeyError,ValueError):limits[name]=0.
    for name,amount in actual_science.items():
        if amount>limits.get(name,0.)+1e-8:raise RuntimeError('per-study cumulative scientific allowance exhausted: '+name)
    if observation['control_CPU_seconds']>=c['shared_control_CPU_seconds']-api.stop_tail_reserve(c,0):
        raise RuntimeError('shared control CPU allowance stop headroom exhausted')
    global_used=sum(actual_science.values())+sum(observation['admin_charges'].values())+observation['control_CPU_seconds']
    global_limit=api.nominal_global_limit(c,{name:limit for name,limit in limits.items() if name!='EE'})
    tail=api.stop_tail_reserve(c,len(observation['active']))
    if global_used+tail>global_limit:raise RuntimeError('global cumulative CPU stop-tail headroom exhausted')
    floors=api.read_delivery_floors(runtime,master);updated=False
    for saved in observation['active']:
        lease=api.read(saved['admission_path'])
        if (lease['master_scope_id']!=master['scope_id'] or lease['source_head']!=master['source']['head']
            or lease['boot_id']!=master['boot_id'] or time.time()>=lease['expires_epoch']
            or lease['expires_epoch']>control_deadline(authority,controller)-90):
            raise RuntimeError('active task escaped immutable admission/master/recovery parent')
        starvation=api.delivery_window(runtime,saved,c)
        if starvation and starvation.get('starved'):raise RuntimeError('live task starvation requires bounded defer: '+saved['unit'])
        if starvation:
            floors[saved['study']]=min(floors.get(saved['study'],1.),starvation['delivered_cpu_share'],1.);updated=True
    if updated:api.atomic(runtime/'delivery_floors.json',dict(scope_id=master['scope_id'],source_head=master['source']['head'],shares=floors,epoch=time.time()))
    observation.update(global_charged_CPU_seconds=global_used,global_limit_CPU_seconds=global_limit,
        stop_tail_reserve_CPU_seconds=tail,study_limits_CPU_seconds=limits,delivered_share_floor=floors,
        recovery_prior_control_CPU_seconds=authority['prior_control_debit']['CPU_seconds'],recovery_control_deadline=control_deadline(authority,controller))
    return observation


def finalize(api,system,c,shared,master,capsule,studies,guardian,authority,status,error):
    runtime=Path(shared)/'development'
    if guardian is None and (runtime/'guardian_intent.json').is_file():
        # A start can succeed before first-exec attestation raises. The intent
        # still names the exact unit/cgroup that must be drained.
        guardian=api.read(runtime/'guardian_intent.json')
        props=system.unit(guardian['unit']);api.legacy().verify_owned(guardian,props)
        if props.get('InvocationID'):
            guardian=dict(guardian,attested=props,process=api.legacy().process(int(props.get('MainPID',0))))
    proof=api.drain_scope(system,c,runtime,error or status,deadline=control_deadline(authority,capsule))
    for path,saved in api.all_attempts(runtime):
        try:
            if not (path.parent/'finished.json').exists():api.finish_worker(system,c,runtime,path,saved,studies[saved['study']])
        except Exception as failure:
            proof['cleanup_errors'].append(dict(unit=saved['unit'],operation='final_CPU_account',error=repr(failure)));proof['cleanup_verified']=False
    if proof['cleanup_verified']:
        api.immutable(runtime/'drained.json',dict(schema_version=1,scope_id=master['scope_id'],master_sha256=api.digest(Path(shared)/'master.json'),
            source_head=master['source']['head'],epoch=time.time(),**proof))
    guardian_proof=None
    if guardian is not None:
        try:
            if guardian.get('attested',{}).get('InvocationID'):
                control_CPU_total(api,system,runtime,master,[capsule,guardian],authority)
        except Exception as failure:
            proof['cleanup_errors'].append(dict(unit=guardian['unit'],operation='guardian_final_CPU_sample',error=repr(failure)));proof['cleanup_verified']=False
        try:guardian_proof=api.drain_exact(system,guardian)
        except Exception as failure:
            proof['cleanup_errors'].append(dict(unit=guardian['unit'],operation='guardian_final_drain',error=repr(failure)));proof['cleanup_verified']=False
    controls=[capsule]+([guardian] if guardian and guardian.get('attested',{}).get('InvocationID') else [])
    try:raw_control=control_CPU_total(api,system,runtime,master,controls,authority)
    except Exception as failure:
        proof['cleanup_errors'].append(dict(operation='final_control_CPU_sample',error=repr(failure)));proof['cleanup_verified']=False
        raw_control=c['shared_control_CPU_seconds']
    # Retain a single final reserve, not a tail on each live poll. On the
    # actual v1 host an unloaded guardian has no exact exit CPU counter. Its
    # bounded stop tail and this publisher's serialization/exit tail remain
    # charged inside the already withheld six-control shutdown reserve.
    final_tail=api.stop_tail_reserve(c,0)
    final_control=raw_control+final_tail
    accounting=Path(authority['attestation_path']).parent/'final_control_charge.json'
    api.immutable(accounting,dict(scope_id=master['scope_id'],authority_sha256=authority['_authority_sha256'],
        prior_and_observed_control_CPU_seconds=raw_control,charged_CPU_seconds=final_control,
        single_final_stop_serialization_and_exit_reserve_CPU_seconds=final_tail,
        guardian_stop_reserve_CPU_seconds=min(final_tail,c['stop_seconds']+5),
        publisher_remaining_reserve_CPU_seconds=max(0,final_tail-c['stop_seconds']-5),
        original_limit_CPU_seconds=c['shared_control_CPU_seconds'],epoch=time.time(),
        final_charge_includes_prior_debit=True,no_per_poll_exit_tail=True))
    if final_control>c['shared_control_CPU_seconds']:
        status='R152_RECOVERY_CONTROL_BUDGET_STOPPED'
        error=(error+'; ' if error else '')+'final conservative control charge exceeds original allowance'
    terminal=dict(schema_version=1,status=status,original_stop_reason=error,scope_id=master['scope_id'],
        master_sha256=api.digest(Path(shared)/'master.json'),epoch=time.time(),source_head=master['source']['head'],
        control_execution_source=authority['execution_source'],recovery_authority_sha256=authority['_authority_sha256'],
        control_charged_CPU_seconds=final_control,final_control_charge_sha256=api.digest(accounting),
        study_dispositions={name:api.study_terminal(runtime,name) for name in studies},new_model_fits=0,baseline_signals=0,**proof)
    api.immutable(runtime/'terminal.json',terminal)
    if proof['cleanup_verified']:
        cleanup=list(proof['cleanup'])
        if guardian_proof:cleanup.append(guardian_proof)
        final=dict(schema_version=1,scope_id=master['scope_id'],master_sha256=api.digest(Path(shared)/'master.json'),source_head=master['source']['head'],
            cleanup_verified=True,owned_pids=[],owned_units=[row['unit'] for row in cleanup],cleanup=cleanup,epoch=time.time(),
            cleanup_scope='ALL_CACHED_PAYLOADS_AND_GUARDIAN_EXCLUDING_RECOVERY_CONTROLLER_PUBLISHER',
            publisher_capsule=capsule,publisher_pending_drain=True,recovery_authority_sha256=authority['_authority_sha256'])
        api.immutable(runtime/'final_drained.json',final)
        api.immutable(Path(shared)/'development_closed.json',dict(scope_id=master['scope_id'],master_sha256=api.digest(Path(shared)/'master.json'),
            source_head=master['source']['head'],future_admissions_closed=True,cleanup_verified=True,
            terminal_sha256=api.digest(runtime/'terminal.json'),final_drained_sha256=api.digest(runtime/'final_drained.json'),epoch=time.time(),
            publisher_capsule=capsule,publisher_pending_drain=True,recovery_authority_sha256=authority['_authority_sha256'],
            cleanup_scope='Publisher exit independently fenced by original504 canonical controller check'))
    return terminal


def run(authority_path,unit, *, api=None,system=None,validator=None):
    api=api or original_api();system=system or api.System();validator=validator or validate_authority
    authority=validator(authority_path,system=system,require_empty=True)
    authority=dict(authority,_authority_path=str(Path(authority_path).resolve()),_authority_sha256=api.digest(authority_path))
    shared=Path(authority['original_master']['path']).parent
    if shared!=api.SHARED or shared.resolve()!=shared:raise RuntimeError('recovery must use the canonical original runtime directly')
    c=api.read_config();master=api.read(shared/'master.json');runtime=shared/'development'
    if master['source']['head']!=OLD_HEAD or master['source']['root']!=str(OLD_ROOT):raise RuntimeError('original cba resource authority differs')
    api.validate_master(master,c);api.verify_source(master['source'])
    prepared=api.read(runtime/'prepared.json')
    if prepared['source']!=master['source']:raise RuntimeError('prepared/original master resource source differs')
    capsule=await_controller(api,system,c,authority,authority_path,unit)
    guardian=None;studies={}
    with contextlib.ExitStack() as stack:
        for path in (runtime/'dispatcher.lock',api.EE_CANONICAL/'workflow.lock',api.EE_CANONICAL/'controller.lock'):
            stack.enter_context(api.locked(path))
        # Recheck emptiness while holding the real original dispatch fences.
        validator(authority_path,system=system,require_empty=True)
        api.historical_bridge(runtime,c)
        await_baseline_ownership(api,shared,master)
        api.immutable(runtime/'controller.json',dict(capsule,recovery_authority_path=authority['_authority_path'],
            recovery_authority_sha256=authority['_authority_sha256'],original_resource_source=master['source']))
        try:
            studies=api.open_studies(c,runtime)
            guardian=api.start_guardian(system,c,runtime,capsule,master)
            return dispatch(api,system,c,shared,master,capsule,studies,guardian,authority,validator)
        except BaseException as error:
            if (runtime/'terminal.json').exists():raise
            finalize(api,system,c,shared,master,capsule,studies,guardian,authority,'R152_RECOVERY_STARTUP_GUARD_STOPPED',repr(error))
            raise


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--authority',required=True);parser.add_argument('--unit',required=True)
    args=parser.parse_args(argv)
    import json
    print(json.dumps(run(args.authority,args.unit),sort_keys=True,allow_nan=False))
    return 0


def dispatch(api,system,c,shared,master,capsule,studies,guardian,authority,validator):
    runtime=Path(shared)/"development";unit=capsule["unit"]
    validation_cache={}
    initial={name:studies[name].queue_state().get('complete',[]) if api.study_prepared(studies[name]) else [] for name in studies}
    funded={'EE'};stopped=[False];fatal=None;terminal_status='R152_SHARED_TRANCHE_DEFERRED';delivery_verified=False
    for signum in (signal.SIGTERM,signal.SIGINT):signal.signal(signum,lambda *_:stopped.__setitem__(0,True))
    probe_sha=master.get('probe_sha256',master.get('capability_probe_sha256',''))
    if not probe_sha:
        probe=shared/'probe.json'
        if not probe.is_file():raise RuntimeError('committed-source capability probe pin missing')
        probe_sha=api.digest(probe)
    try:
        while True:
            if stopped[0]:raise RuntimeError('finite master requested cooperative stop')
            if time.time()>=control_deadline(authority,capsule)-90:
                terminal_status='R152_MASTER_EXPIRED';break
            observation=live_guard(api,system,c,shared,master,capsule,studies,funded,authority,validator,validation_cache)
            # Reap only our exact units and finish their nonoverlapping CPU
            # accounts before any new scientific decision or slot release.
            for path,saved in api.all_attempts(runtime):
                if (path.parent/'finished.json').exists():continue
                value=observation['observations'][saved['unit']]
                if value['active']:continue
                result=api.finish_worker(system,c,runtime,path,saved,studies[saved['study']])
                if result is None:continue
                kind=saved['kind'];name=saved['study'];study=studies[name]
                lease_path=Path(saved['admission_path'])
                if kind=='numerical':
                    if not study.task_complete(saved['task']) and not (path.parent/'planned_stop.json').exists():
                        raise RuntimeError('numerical worker exited without strict component seal: '+saved['task'])
                    if study.task_complete(saved['task']):
                        share=api.completed_delivery_share(saved,result['charge'])
                        # Zero with no receipt is absent CPU evidence, not
                        # an observed starvation result. Preserve the full
                        # charge and keep the FI delivery gate closed.
                        if share>0:api.record_delivered_share(runtime,master,name,share)
                        if name=='EE' and share>=c['EE_conservative_share']:delivery_verified=True
                elif kind=='benchmark':
                    try:
                        price=api.study_price(study)
                        if result['observation']['properties'].get('ExecMainStatus','0')!='0':raise RuntimeError('regional benchmark exited with error')
                    except (OSError,KeyError,ValueError,RuntimeError) as error:
                        api.close_admission(lease_path,'BENCHMARK_DEFERRED',cleanup_verified=True,error=repr(error))
                        api.metadata_terminal(runtime,name,'DEFERRED_BENCHMARK',reason=repr(error));continue
                    api.close_admission(lease_path,'BENCHMARK_COMPLETE',cleanup_verified=True,pricing_sha256=api.fingerprint(price))
                    if not api.regional_prefix_priced(price):
                        api.metadata_terminal(runtime,name,'DEFERRED_PREFIX_UNFUNDED',reason='own full-prefix science allowance does not fit',pricing_sha256=api.fingerprint(price))
                        continue
                    candidate=set(funded)|{name}
                    projected=projection(api,runtime,master,c,studies,candidate,observation,authority,capsule)
                    if projected['fits']:funded.add(name)
                    else:api.metadata_terminal(runtime,name,'DEFERRED_PREFIX_UNFUNDED',reason=projected['reason'],projection_sha256=api.fingerprint(projected))
                else:
                    if result['observation']['properties'].get('ExecMainStatus','0')!='0':raise RuntimeError('independent assessment failed: '+name)
                    if name=='EE':
                        assessed=api.read(runtime/'assessments/EE/assessment.json');status=assessed['status']
                    else:
                        assessed=study.queue_state()
                        if not assessed.get('execution_terminal') and not assessed.get('scientific_complete'):
                            raise RuntimeError('regional assessment produced no sealed terminal')
                        status='SCIENTIFIC_COMPLETE' if assessed.get('scientific_complete') else 'CLEAN_PREFIX_COMPLETE_EXTRAS_UNFUNDED'
                    api.close_admission(lease_path,'ASSESSMENT_COMPLETE',cleanup_verified=True)
                    parent_path=Path(api.read(lease_path)['parent_admission_path'])
                    api.close_admission(parent_path,'NUMERICAL_COMPLETE_ASSESSED',cleanup_verified=True)
                    api.metadata_terminal(runtime,name,status,cleanup_verified=True,assessment_sealed=True)
                    funded.discard(name)
            observation=live_guard(api,system,c,shared,master,capsule,studies,funded,authority,validator,validation_cache)
            # Owned assessments/admin caps stop with tail headroom. A timed
            # regional benchmark is local to that stage; no automatic rerun.
            for saved in list(observation['active']):
                lease=api.read(saved['admission_path']);obs=observation['observations'][saved['unit']]
                if saved['kind']!='numerical' and (obs['cpu_seconds']>=saved['estimated_cpu_seconds']-30 or time.time()>=lease['expires_epoch']-30):
                    api.defer_current_wave(system,c,runtime,saved['study'],Path(saved['admission_path']),'finite admin allowance stop')
            # Advance each region using metadata only; full D and ready
            # matched decisions remain enforced by the immutable science.
            for name in list(funded):
                if api.active_for(observation,name):continue
                study=studies[name]
                study.advance(remaining_CPU_seconds=max(0.,api.study_limit(study,c)-api.study_cpu_charge(runtime,name,c)[0]),budget_view=None)
            observation=live_guard(api,system,c,shared,master,capsule,studies,funded,authority,validator,validation_cache)
            # End numerical allocations at their finite compute cutoff.
            for name in list(funded):
                lease_path,lease=api.current_admission(runtime,name)
                if lease is None:continue
                if (lease_path.parent/'compute_closed.json').exists():continue
                if time.time()>=lease['compute_expires_epoch']-c['cooperative_grace_seconds']-c['stop_seconds']-c['poll_seconds']:
                    api.defer_current_wave(system,c,runtime,name,lease_path,'finite numerical allocation elapsed')
            observation=live_guard(api,system,c,shared,master,capsule,studies,funded,authority,validator,validation_cache)
            projected=projection(api,runtime,master,c,studies,funded,observation,authority,capsule) if funded else dict(fits=True,enabled=[],worst=None)
            api.require_delivered_calendar(projected,observation,studies,c)
            # A complete matched-extra set is an atomic, independent
            # resource decision; it cannot silently claim a partial seed.
            for name in list(funded):
                study=studies[name];q=study.queue_state()
                if q['phase']=='MATCHED_FULL_MC' and not api.active_for(observation,name):
                    components=list(q['pending']);gate=runtime/'studies'/name/'extras_resource_admission.json'
                    if not gate.exists():api.immutable(gate,dict(components=components,admitted=projected['fits'],projection_sha256=api.fingerprint(projected),epoch=time.time()))
                    if api.read(gate)['components']!=components and not api.read(gate)['admitted']:
                        raise RuntimeError('unfunded matched-extra component set changed')
                ready,unfunded=api._assessment_ready(study,q,runtime)
                lease_path,lease=api.current_admission(runtime,name)
                if ready and lease is not None and not api.active_for(observation,name) and api.current_admission(runtime,name,'assessment')[0] is None:
                    api.close_compute(runtime,name,lease_path,reason='science complete or entire extras unfunded',unfunded=unfunded)
                    request=dict(active_workers=[],cleanup_preassessment_verified=api.drained_attempts(runtime,name),
                        entire_extra_set_unfunded_pending=bool(unfunded),unfunded_components=list(unfunded),epoch=time.time())
                    disposition=runtime/'studies'/name/'extras_resource_admission.json'
                    if disposition.is_file():request.update(resource_disposition_path=str(disposition),resource_disposition_sha256=api.digest(disposition))
                    target=runtime/'studies'/name/'assessment_request.json'
                    if not target.exists():api.immutable(target,request)
                    source,prep_sha=api.study_source_and_prep(study)
                    cpu=api.free_slot(runtime,list(range(24,30)))
                    if cpu is None:raise RuntimeError('no physical slot for admitted assessment')
                    approval=admin_projection(api,runtime,master,c,studies,funded,name,'assessment',cpu,observation,authority,capsule)
                    if not approval['fits']:raise RuntimeError('assessment cannot fit common funded calendar')
                    apath,alease=claim_admission(api,runtime,master,name,'assessment',source['head'],prep_sha,unit,authority=authority,controller=capsule,projection=approval)
                    api.start_study_task(system,c,shared,runtime,master,capsule,study,'__finalize__',cpu,apath,alease,'assessment',probe_sha)
            # Regional cost-only studies can start after actual accepted EE
            # delivery. No FI score is opened by preparation or pricing.
            for name in ('FI','DK2'):
                if api.study_terminal(runtime,name) or api.admission_files(runtime,name,'benchmark'):continue
                if name=='FI' and not delivery_verified:continue
                if name=='DK2' and not api.ee_gate(runtime)['proceed']:continue
                study=studies[name]
                if not api.study_prepared(study):api.metadata_terminal(runtime,name,'DEFERRED_PREPARATION_MISSING');continue
                cpu=api.free_slot(runtime,list(range(24,30)))
                if cpu is None:continue
                # Benchmarks take one real global slot and fixed CPU; the
                # conservative simultaneous proof retains EE/FI prefixes.
                base=projection(api,runtime,master,c,studies,funded,observation,authority,capsule) if funded else dict(fits=True)
                if not base['fits']:continue
                source,prep_sha=api.study_source_and_prep(study)
                approval=admin_projection(api,runtime,master,c,studies,funded,name,'benchmark',cpu,observation,authority,capsule)
                if not approval['fits']:continue
                try:path,lease=claim_admission(api,runtime,master,name,'benchmark',source['head'],prep_sha,unit,
                    authority=authority,controller=capsule,projection=approval)
                except RuntimeError as error:
                    api.metadata_terminal(runtime,name,'DEFERRED_BENCHMARK_WINDOW',reason=repr(error));continue
                api.start_study_task(system,c,shared,runtime,master,capsule,study,'__benchmark__',cpu,path,lease,'benchmark',probe_sha)
            observation=live_guard(api,system,c,shared,master,capsule,studies,funded,authority,validator,validation_cache)
            projected=projection(api,runtime,master,c,studies,funded,observation,authority,capsule) if funded else dict(fits=True,worst=None)
            api.require_delivered_calendar(projected,observation,studies,c)
            dispatched=False
            if projected['fits']:
                assignments=(projected.get('worst') or {}).get('packing',{}).get('allocation',[])
                for name in ('EE','FI','DK2'):
                    if name not in funded or api.study_terminal(runtime,name):continue
                    study=studies[name];q=study.queue_state();ready=[row for row in q.get('ready',[]) if row['name'] not in {x['task'] for x in observation['active']}]
                    if not ready:continue
                    path,lease=api.current_admission(runtime,name)
                    if lease is None:
                        source,prep_sha=api.study_source_and_prep(study)
                        try:path,lease=claim_admission(api,runtime,master,name,'numerical',source['head'],prep_sha,unit,authority=authority,controller=capsule,projection=projected)
                        except RuntimeError as error:
                            api.metadata_terminal(runtime,name,'DEFERRED_NO_WHOLE_WINDOW',reason=repr(error));funded.discard(name);continue
                        api.immutable(path.parent/'start_complete.json',dict(names=q.get('complete',[]),epoch=time.time()))
                        projected=projection(api,runtime,master,c,studies,funded,observation,authority,capsule)
                        assignments=(projected.get('worst') or {}).get('packing',{}).get('allocation',[])
                    if (path.parent/'compute_closed.json').exists():continue
                    for task in ready:
                        choices=[row for row in assignments if row.get('study')==name and row.get('name')==task['name'] and row.get('window_id')==lease['admission_id'] and not row.get('active')]
                        if not choices:continue
                        choice=min(choices,key=lambda x:(x['start'],x['cpu']))
                        if choice['start']>time.time()+c['poll_seconds']:continue
                        cpu=choice['cpu']
                        if api.free_slot(runtime,[cpu]) is None:continue
                        api.start_study_task(system,c,shared,runtime,master,capsule,study,task['name'],cpu,path,lease,'numerical',probe_sha)
                        dispatched=True
            # Planned compute stops close their window only after every
            # worker/CPU account has drained, then reserve a new whole lease.
            observation=live_guard(api,system,c,shared,master,capsule,studies,funded,authority,validator,validation_cache)
            for name in list(funded):
                path,lease=api.current_admission(runtime,name)
                if lease and time.time()>=lease['compute_expires_epoch']-c['cooperative_grace_seconds']-c['stop_seconds']-c['poll_seconds'] and not api.active_for(observation,name):
                    api.close_admission(path,'FINITE_WINDOW_DEFERRED',cleanup_verified=api.drained_attempts(runtime,name))
                    if len(api.admission_files(runtime,name,'numerical'))>=len(api.admission_identifiers(name)):
                        api.metadata_terminal(runtime,name,'DEFERRED_PARTIAL_PREFIX',strict_new_components=api.strict_new_count(studies[name],initial[name]));funded.discard(name)
            if not projected.get('fits',True) and not observation['active']:
                for name in list(funded):
                    study=studies[name];q=study.queue_state()
                    if q.get('phase')=='MATCHED_FULL_MC' and (runtime/'studies'/name/'extras_resource_admission.json').exists():continue
                    api.metadata_terminal(runtime,name,'DEFERRED_JOINT_FUNDING',reason=projected.get('reason'));funded.discard(name)
            if api.study_terminal(runtime,'EE') and not delivery_verified and not api.admission_files(runtime,'FI','benchmark') and not api.study_terminal(runtime,'FI'):
                api.metadata_terminal(runtime,'FI','DEFERRED_POOL_DELIVERY_NOT_VALIDATED')
            done=all(api.study_terminal(runtime,name) is not None for name in ('EE','FI'))
            if done and not api.study_terminal(runtime,'DK2') and not api.ee_gate(runtime)['proceed']:
                api.metadata_terminal(runtime,'DK2','BLOCKED_EE_DISPOSITION')
            if all(api.study_terminal(runtime,name) is not None for name in studies) and not observation['active']:
                terminal_status='R152_FINITE_TRANCHE_DISPOSITION_SEALED';break
            api.atomic(runtime/'progress.json',dict(status='R152_RUNNING',epoch=time.time(),scope_id=master['scope_id'],
                phases={name:(studies[name].queue_state().get('phase') if api.study_prepared(studies[name]) else 'UNPREPARED') for name in studies},
                active=[dict(study=row['study'],task=row['task'],cpu=row['cpu'],unit=row['unit']) for row in observation['active']],
                observation={k:v for k,v in observation.items() if k not in ('observations','active')},
                funded_studies=sorted(funded),delivery_verified=delivery_verified,dispatched=dispatched))
            time.sleep(c['poll_seconds'])
    except BaseException as error:
        fatal=repr(error);terminal_status="R152_GUARD_STOPPED";api.event(runtime,"guard_stopped",error=fatal)
    return finalize(api,system,c,shared,master,capsule,studies,guardian,authority,terminal_status,fatal)


if __name__=="__main__":raise SystemExit(main())
