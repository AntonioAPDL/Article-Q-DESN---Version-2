#!/usr/bin/env python3
"""Finite owned EE recovery followed conditionally by one DK_2 cached screen.

Parents import only standard-library scheduling interfaces. Numerical forecasts
and final retained-array verification run in separately owned IDLE payloads.
No source globals are rebound and no existing scientific/runtime files replaced.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import signal
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
CONFIG = ROOT/'application/config/pricefm_stage_r151_orchestration_20261023.json'
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
RUNTIME = DATA/'launch_prep/pricefm_stage_r151_orchestration_20261023'
RESOURCE_ENTRY = ENTRY.with_name('501_recover_pricefm_stage_r150.py')
REGIONAL_ENTRY = ENTRY.with_name('502_screen_pricefm_stage_r151_region.py')
_APIS = None


def read(path): return json.loads(Path(path).read_text())
def digest(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def apis():
    global _APIS
    if _APIS is None:
        def load(name, path):
            spec=importlib.util.spec_from_file_location(name,path)
            value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value)
            return value
        _APIS=(load('r151_outer_resource',RESOURCE_ENTRY),load('r151_outer_regional',REGIONAL_ENTRY))
    if any(name in sys.modules for name in ('numpy','pandas','scipy')):
        raise RuntimeError('finite orchestration parent imported numerical dependencies')
    return _APIS


def config():
    c=read(CONFIG)
    expected=dict(stage='R151',tag='pricefm_stage_r151_orchestration_20261023',outer_seconds=37800,
        EE_coordinator_seconds=14700,regional_benchmark_seconds=1200,regional_wave_seconds=7200,
        regional_compute_seconds=5400,regional_cleanup_seconds=1800,
        regional_admissions=['benchmark','1','2','3'],max_regional_numerical_waves=3,
        regional_region='DK_2',regional_replacements=1,cpus=list(range(15,30)),max_workers=2,
        numerical_threads=1,new_model_fits=0,AL_authorized=False,promotion_authorized=False,
        baseline_mutations_authorized=False,renewals_authorized=False)
    if c!=expected:raise RuntimeError('frozen finite orchestration contract differs')
    return c


def run_folder(run_id):
    if len(run_id)!=32 or any(v not in '0123456789abcdef' for v in run_id):
        raise RuntimeError('invalid finite workflow UUID')
    return RUNTIME/'runs'/run_id


def validate_probe(resource,probe):
    if (probe.get('status')!='PASS_R151_OWNED_TREE_POLICY_AND_DRAIN'
        or probe.get('resource_entry_sha256')!=digest(RESOURCE_ENTRY)
        or probe.get('boot_id')!=resource.boot() or probe.get('cleanup_errors')!=[]):
        raise RuntimeError('same-source/boot successful owned capability probe required')


def verify_assessment(science):
    path=science.OUT/'assessment.json';seal=read(science.OUT/'assessment_seal.json')
    if seal!={'sha256':digest(path),'source':science.read_preparation()['source']}:
        raise RuntimeError('EE final assessment seal/source differs')
    result=read(path)
    if (result.get('status')!='R150_BOUNDED_SCIENTIFICALLY_COMPLETE_NOT_PROMOTED'
        or result.get('new_model_fits')!=0):raise RuntimeError('EE scientific assessment disposition differs')
    return dict(path=str(path),sha256=seal['sha256'],status=result['status'])


def EE_disposition(terminal,queue,prep,complete,assessment=None):
    """Pure gate: partial pools and operational stops can never open a region."""
    if (terminal.get('cleanup_verified') is not True or terminal.get('cleanup_errors')
        or terminal.get('status')=='R151_RECOVERY_GUARD_STOPPED'
        or terminal.get('original_stop_reason')):
        return dict(proceed=False,reason='EE resource/ownership/starvation/cleanup stop')
    if (terminal.get('status')=='R151_RECOVERY_COMPLETE' and queue.get('terminal')
        and queue.get('scientific_complete') and assessment):
        return dict(proceed=True,reason='EE complete with sealed independently replayed assessment',assessment=assessment)
    control=prep['control'];nominees=prep.get('nominees_for_gate',[])
    d=prep['all_D_for_gate'];s0=prep.get('all_S0_for_gate',[])
    if (terminal.get('status')=='R151_RECOVERY_DEFERRED' and terminal.get('resource_unfunded_pending')
        and len(nominees)==2 and len(set(nominees))==2 and control not in nominees
        and d and s0 and all(complete(name) for name in d+s0)
        and set(queue.get('unfunded_pending') or queue.get('pending',[]))==set(terminal['resource_unfunded_pending'])
        and queue.get('phase') in ('MATCHED_MC_UNFUNDED_PENDING','MATCHED_FULL_MC')):
        return dict(proceed=True,reason='EE complete D and S0; entire matched MC set explicitly unfunded',
            scientific_complete=False,unfunded_pending=terminal['resource_unfunded_pending'])
    return dict(proceed=False,reason='EE deterministic/S0 pool or explicit scientific disposition incomplete')


def ee_gate(science,terminal):
    q=science.queue_state();prep=science.read_preparation()
    v=dict(prep,all_D_for_gate=science.names_for([p['package_id'] for p in prep['packages']],'D',[0]))
    nominees=[]
    if (science.OUT/'decisions/nominees.seal.json').exists():
        nominees=science.read_decision('nominees')['nominees']
    v['nominees_for_gate']=nominees
    v['all_S0_for_gate']=science.names_for([prep['control']]+nominees,'S',[0]) if len(nominees)==2 else []
    assessment=verify_assessment(science) if q.get('terminal') and q.get('scientific_complete') else None
    return EE_disposition(terminal,q,v,science.task_complete,assessment)


def regional_remaining_capacity(leases,share,terminal_waves=(),*,now=None):
    """Unused windows plus active compute only; spent/drained tails earn no time."""
    if not math.isfinite(share) or not 0<share<=1:raise ValueError('invalid idle share')
    now=time.time() if now is None else now;seconds=0.
    for wave in ('1','2','3'):
        lease=leases.get(wave)
        if lease is None:seconds+=10800.
        elif wave not in terminal_waves:
            seconds+=2*max(0.,min(5400.,lease['expires_epoch']-1800.-now))
    return share*seconds


def allowed_next_admission(existing,terminals):
    order=['benchmark','1','2','3']
    if any(v not in order for v in existing) or len(set(existing))!=len(existing):
        raise RuntimeError('unknown or duplicate regional admission')
    if existing!=order[:len(existing)]:raise RuntimeError('regional admission order differs')
    if not existing:return 'benchmark'
    previous=terminals.get(existing[-1])
    if (not previous or previous.get('cleanup_verified') is not True or previous.get('cleanup_errors')
        or previous.get('status') not in ('R151_REGION_WAVE_COMPLETE','R151_REGION_WAVE_DEFERRED')
        or previous.get('strict_new_components',0)<=0 or previous.get('resource_unfunded_pending')):
        return None
    return order[len(existing)] if len(existing)<len(order) else None


def leases_and_terminals(science):
    base=science.PREP/'muscat_resources';leases={};terms={}
    for wave in ('benchmark','1','2','3'):
        folder=base/('wave_'+wave)
        if (folder/'lease.json').exists():leases[wave]=read(folder/'lease.json')
        if (folder/'terminal.json').exists():terms[wave]=read(folder/'terminal.json')
    return leases,terms


def regional_attempts(science):
    r,_=apis();legacy=r.load_legacy()
    return [saved for wave in ('benchmark','1','2','3')
        for saved in legacy.discover_workers(science.PREP/'muscat_resources'/('wave_'+wave))]


def attempt_charge(science,saved,prep,estimate):
    """A known finished attempt charges whole-process CPU+5; unknown keeps reserve."""
    floor=estimate
    try:
        resource,_=apis();legacy=resource.load_legacy();prior=saved['process']
        current=legacy.process(prior['pid'])
        if current and all(current[k]==prior[k] for k in ('pid','start_ticks','boot_id')):
            live=legacy.cpu_seconds(prior['pid'])
            if live is not None and math.isfinite(live) and live>=0:floor=max(floor,live+5.)
    except (OSError,KeyError,TypeError,ValueError):pass
    try:
        invocation=saved['attested']['InvocationID']
        path=science.OUT/'cpu_accounting'/saved['task']/invocation
        started=read(path/'started.json');observed=read(path/'observed.json')
        task=science.task_by_name(saved['task'],prep)
        if (read(path/'observed.seal.json')!={'sha256':digest(path/'observed.json'),'source':prep['source']}
            or started['source']!=prep['source'] or started['task']!=saved['task']
            or started['scientific_identity_sha256']!=task['scientific_identity_sha256']
            or started['policy_invocation_id']!=invocation
            or started['policy_receipt_path']!=saved['policy_receipt']
            or digest(saved['policy_receipt'])!=started['policy_receipt_sha256']
            or any(observed.get(k)!=v for k,v in started.items())
            or observed['post_observation_exit_allowance_CPU_seconds']!=5.
            or observed['hard_CPU_quota'] is not False or observed['exact_exit_CPU_measurement'] is not False):
            raise ValueError('attempt identity differs')
        values=[observed[k] for k in ('observed_process_CPU_seconds','observed_terminated_children_CPU_seconds','observed_total_CPU_seconds')]
        if any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) or v<0 for v in values):
            raise ValueError('invalid CPU values')
        if not math.isclose(sum(values[:2]),values[2],rel_tol=1e-12,abs_tol=1e-10):raise ValueError('CPU sum differs')
        if type(observed['completed_component']) is not bool:raise ValueError('invalid completion flag')
        if observed['completed_component'] and (not science.task_complete(saved['task'])
            or observed['task_final_seal_sha256']!=digest(science.OUT/'tasks_done'/saved['task']/'completed_evidence.json')):
            raise ValueError('final seal differs')
        return max(values[2]+5.,floor) if not observed['completed_component'] else values[2]+5.
    except (OSError,KeyError,TypeError,ValueError,RuntimeError):return floor


def charge_components(science,attempts,prep):
    grouped={}
    for saved in attempts:
        if saved['task'] not in ('__benchmark__','__finalize__'):
            grouped.setdefault(saved['task'],[]).append(saved)
    total=0.;details={}
    for name,saves in grouped.items():
        estimate=science.estimate_task(name)['estimated_cpu_seconds']
        if science.task_complete(name):
            value=science.completed_CPU_charge(name,prep)
            # Every ownership lifetime must be represented; missing accounting
            # cannot erase an earlier failed attempt from the cumulative total.
            known={p.parent.name for p in (science.OUT/'cpu_accounting'/name).glob('*/started.json')}
            missing=sum(s.get('attested',{}).get('InvocationID') not in known for s in saves)
            amount=value['charged_CPU_seconds']+missing*estimate
        else:
            # Partial completion has no final-seal credit. Even a valid finished
            # partial attempt keeps its full component envelope, or a larger
            # observed whole-process overrun. Missing ownership lineage adds
            # another reservation instead of erasing the old attempt.
            known={s.get('attested',{}).get('InvocationID') for s in saves}
            starts=list((science.OUT/'cpu_accounting'/name).glob('*/started.json'))
            missing=sum(p.parent.name not in known for p in starts)
            prior=set();present={p.parent.name for p in starts}
            for path in starts:
                try:
                    old=read(path);lineage=old['prior_started_invocations']
                    if not isinstance(lineage,list) or any(not isinstance(v,str) or not v or '/' in v or v in ('.','..') for v in lineage):
                        raise ValueError('malformed prior lineage')
                    prior.update(lineage)
                    if old.get('preexisting_checkpoint_count',0) and not lineage:missing+=1
                except (OSError,ValueError,KeyError,TypeError):pass
            missing+=len(prior-present)
            amount=sum(max(estimate,attempt_charge(science,s,prep,estimate)) for s in saves)+missing*estimate
        details[name]=amount;total+=amount
    return total,details


def prospective_extras(science):
    prep=science.read_preparation();nominees=science.read_decision('nominees')['nominees']
    control=science.component_loss(prep['control'],'S')
    trigger=.5*science.producer().practical_margin(control)
    qualifiers=[n for n in nominees if control-science.component_loss(n,'S')>=trigger]
    return science.names_for([prep['control']]+qualifiers,'S',[1,2]) if qualifiers else []


def replacement_reserve(science,attempts,price):
    """Token publication alone never frees its predecessor's reserve."""
    base=science.PREP/'muscat_resources'
    try:
        token=read(base/'replacement_token.json');proof=read(base/'replacement_drain.json')
        old=next(v for v in attempts if v['unit']==token['old_unit'])
        if (proof['token_sha256']!=digest(base/'replacement_token.json')
            or proof['old_unit']!=old['unit'] or proof['lease_id']!=token['lease_id']
            or old['attested']['InvocationID']!=token['old_invocation_id']
            or proof['predecessor_cgroup']!=old['attested']['ControlGroup']
            or proof['drain']['cleanup_verified'] is not True or proof['drain']['cleanup_errors']
            or not proof['drain']['cleanup'] or not all(v['drained'] for v in proof['drain']['cleanup'])):
            raise ValueError('regional replacement predecessor drain not proven')
        return 0.
    except (OSError,KeyError,ValueError,TypeError,StopIteration):return price['replacement_reserve_CPU_seconds']


def required_future_names(science,queue):
    pending=list(queue['pending'])
    if queue['phase'] in ('DETERMINISTIC_POOL','NOMINATION_REQUIRED'):
        prep=science.read_preparation();price=science.pricing();scenarios=[]
        for scenario in price['all_prospective_seed0_scenarios']:
            names=science.names_for([prep['control'],scenario['A'],scenario['B']],'S',[0])
            names=[n for n in names if not science.task_complete(n)]
            scenarios.append((sum(price['task_estimates'][n]['estimated_cpu_seconds'] for n in names),scenario['A'],names))
        pending+=max(scenarios)[2]
    return list(dict.fromkeys(pending))


def regional_projection(science,queue,leases,terms,active=(),*,now=None,extra_names=None):
    resource,_=apis();price=science.pricing();prep=science.read_preparation()
    now=time.time() if now is None else now
    names=required_future_names(science,queue) if extra_names is None else list(extra_names)
    active_names={s['task'] for s in active};pending=[n for n in names if n not in active_names]
    attempts=regional_attempts(science);charges,details=charge_components(science,attempts,prep)
    reserve=replacement_reserve(science,attempts,price)
    outstanding=sum(price['task_estimates'][n]['estimated_cpu_seconds'] for n in pending)
    active_cpu=sum(price['task_estimates'][n]['estimated_cpu_seconds'] for n in active_names)
    share=price['resource_projection']['conservative_idle_share']
    cap=regional_remaining_capacity(leases,share,terms,now=now)
    numerical=[w for w in ('1','2','3') if w in leases and w not in terms]
    current=max(0.,leases[numerical[-1]]['expires_epoch']-1800.-now) if numerical else 5400.
    future=sum(w not in leases for w in ('1','2','3'))-(0 if numerical else 1)
    slots={v['task']:v['resource_slot'] for v in active}
    def pack(component_names):
        tasks=[dict(name=n,phase=(1 if science.task_by_name(n,prep)['mode']=='S' else 0),
                    **price['task_estimates'][n]) for n in list(dict.fromkeys(component_names))]
        for task in tasks:
            if task['name'] in slots:task['fixed_slot']=slots[task['name']]
        if reserve:
            tasks.append(dict(name='__regional_single_replacement_reserve__',phase=1,
                estimated_cpu_seconds=reserve,estimated_wall_seconds=max(v['estimated_wall_seconds'] for v in price['task_estimates'].values())))
        return resource.scheduling_projection(tasks,current,max(0,future))
    packing=pack(pending+sorted(active_names));scenario_packing=[]
    if extra_names is None and queue['phase'] in ('DETERMINISTIC_POOL','NOMINATION_REQUIRED'):
        for scenario in price['all_prospective_seed0_scenarios']:
            s0=science.names_for([prep['control'],scenario['A'],scenario['B']],'S',[0])
            required=[n for n in queue['pending']+s0 if not science.task_complete(n)]
            value=pack(required+sorted(active_names))
            scenario_packing.append(dict(A=scenario['A'],B=scenario['B'],packing=value))
    all_scenarios_fit=all(v['packing']['fits'] for v in scenario_packing)
    cumulative=charges+outstanding+reserve
    remaining=outstanding+active_cpu+reserve
    limit=min(32400.,price['benchmark_adjusted_available_CPU_seconds'])
    return dict(charged_CPU_seconds=charges,component_charges=details,
        cumulative_projected_CPU_seconds=cumulative,cumulative_limit_CPU_seconds=limit,
        remaining_projected_CPU_seconds=remaining,remaining_capacity_CPU_seconds=cap,
        replacement_reserve_CPU_seconds=reserve,packing=packing,all_prospective_seed0_packing=scenario_packing,
        all_prospective_seed0_scenarios_fit=all_scenarios_fit,
        fits=cumulative<=limit and remaining<=cap and packing['fits'] and all_scenarios_fit,
        fresh_extra_allowance_CPU_seconds=max(0.,min(limit-charges-reserve,cap-reserve)),
        future_components=names,hard_CPU_quota=False,exact_exit_CPU_measurement=False)


def claim_regional_lease(science,wave,release,outer):
    resource,_=apis();c=config();base=science.PREP/'muscat_resources'
    with resource.canonical_lock(base/'lease.lock',blocking=True):
        leases,terms=leases_and_terminals(science)
        if wave!=allowed_next_admission(list(leases),terms):raise RuntimeError('regional finite admission unavailable or out of order')
        seconds=c['regional_benchmark_seconds'] if wave=='benchmark' else c['regional_wave_seconds']
        outer_context=read(base/'outer_context.json');launch=read(run_folder(outer_context['run_id'])/'context.json')
        # The lease is consumed only after a fresh entire-tree/baseline/floor
        # predicate and a nonblocking conflict check of the shared dispatch lock.
        system=resource.load_legacy().System()
        with resource.canonical_lock(resource.CANONICAL/'controller.lock'):
            guard(system,release,outer,None,None,science,outer_context['EE_recovery_id'])
        now=time.time()
        if launch['expires_epoch']-now<seconds+5:raise RuntimeError('outer finite lifetime cannot contain this entire new admission')
        value=dict(schema_version=1,stage='R151_REGION',region='DK_2',wave=wave,
            lease_id=uuid.uuid4().hex,started_epoch=now,expires_epoch=now+seconds,seconds=seconds,
            boot_id=resource.boot(),nonrenewing=True,source_head=release['source']['head'],
            preparation_sha256=digest(science.PREP/'preparation.json'),
            outer_unit=outer['unit'],outer_invocation_id=outer['attested']['InvocationID'],
            outer_run_id=outer_context['run_id'],outer_context_sha256=digest(base/'outer_context.json'),
            orchestration_config_sha256=digest(CONFIG))
        resource.immutable(base/('wave_'+wave)/'lease.json',value);return value


def verify_regional_lease(lease,science,release,outer):
    resource,_=apis();wave=lease.get('wave');base=science.PREP/'muscat_resources'
    if wave not in ('benchmark','1','2','3'):raise RuntimeError('unknown regional lease namespace')
    context=read(base/'outer_context.json');seconds=1200 if wave=='benchmark' else 7200
    if (read(base/('wave_'+wave)/'lease.json')!=lease
        or lease.get('stage')!='R151_REGION' or lease.get('region')!='DK_2'
        or lease.get('seconds')!=seconds or lease.get('nonrenewing') is not True
        or lease.get('source_head')!=release['source']['head'] or lease.get('boot_id')!=resource.boot()
        or lease.get('preparation_sha256')!=digest(science.PREP/'preparation.json')
        or lease.get('orchestration_config_sha256')!=digest(CONFIG)
        or lease.get('outer_context_sha256')!=digest(base/'outer_context.json')
        or lease.get('outer_run_id')!=context['run_id'] or lease.get('outer_unit')!=outer['unit']
        or lease.get('outer_invocation_id')!=outer['attested']['InvocationID']
        or read(context['outer_capsule_path'])!=outer
        or not math.isfinite(lease['started_epoch']) or not math.isfinite(lease['expires_epoch'])
        or not math.isclose(lease['expires_epoch']-lease['started_epoch'],seconds,abs_tol=1e-6)):
        raise RuntimeError('regional immutable lease/source/preparation/outer identity changed')
    return True


def all_owned_workers(science,recovery=None):
    resource,_=apis();workers=regional_attempts(science)
    if recovery:
        workers+=resource.recovery_attempts()
        workers+=resource.load_legacy().discover_workers(resource.recovery_folder(recovery)/'assessment')
    return list({s['unit']:s for s in workers}.values())


def guard(system,release,outer,controller,lease,science,recovery,previous=None):
    resource,_=apis();legacy=resource.load_legacy();oldc=read(legacy.CONFIG)
    if lease is not None and 'wave' in lease:verify_regional_lease(lease,science,release,outer)
    extra=[]
    if recovery:
        for capsule in resource.recovery_capsules(recovery):
            if capsule['unit'] in (outer['unit'],controller['unit'] if controller else None):continue
            props=system.unit(capsule['unit']);legacy.verify_owned(capsule,props)
            extra.append(capsule)
    for path in sorted((science.PREP/'muscat_resources').glob('wave_*/controller/intent.json')):
        capsule=resource.control_capsule(path.parent)
        if capsule['unit'] not in (outer['unit'],controller['unit'] if controller else None):extra.append(capsule)
    return resource.baseline_guard(oldc,system,read(resource.CANONICAL/'admission.json'),
        outer,controller,lease,all_owned_workers(science,recovery),release,previous,extra_capsules=extra)


def wait_owned(system,capsule,deadline,poll,callback=None):
    resource,_=apis();legacy=resource.load_legacy()
    while True:
        props=system.unit(capsule['unit']);legacy.verify_owned(capsule,props)
        if props.get('ActiveState') not in ('active','activating'):break
        if time.time()>=deadline:raise RuntimeError('owned finite controller deadline reached')
        if callback:callback()
        time.sleep(min(poll,max(.01,deadline-time.time())))
    return resource.drain_exact(system,capsule)


def launch(release_path,probe_path):
    resource,science=apis();c=config();release=read(release_path)
    _,oldc=resource.verify_release(release,full=True);resource.load_legacy().assert_parent_policy(oldc)
    probe=read(probe_path);validate_probe(resource,probe);system=resource.load_legacy().System()
    with resource.canonical_lock(RUNTIME/'launch.lock'):
        if (RUNTIME/'launch.json').exists():raise RuntimeError('this finite workflow was already launched; no automatic restart')
        with resource.canonical_lock(resource.CANONICAL/'workflow.lock'):pass
        with resource.canonical_lock(resource.CANONICAL/'controller.lock'):pass
        resource.assert_drained_history(system,release)
        if any((resource.CANONICAL/('wave_'+w)/'lease.json').exists() for w in ('2','3')):
            raise RuntimeError('EE unused admission consumed before finite orchestrator launch')
        if (science.PREP/'muscat_resources/outer_context.json').exists():raise RuntimeError('regional lane already assigned')
        run_id=uuid.uuid4().hex;folder=run_folder(run_id);folder.mkdir(parents=True)
        resource.immutable(folder/'release.json',release);resource.immutable(folder/'probe.json',probe)
        now=time.time();resource.immutable(folder/'context.json',dict(run_id=run_id,started_epoch=now,
            expires_epoch=now+c['outer_seconds'],boot_id=resource.boot(),config_sha256=digest(CONFIG),
            release_sha256=digest(release_path),probe_sha256=digest(probe_path)))
        unit='pricefm-r150-r151-finite-'+uuid.uuid4().hex+'.service'
        argv=[oldc['python_runtime'],'-B',str(ENTRY),'coordinate','--run-id',run_id,'--controller-unit',unit]
        capsule=resource.start_control(system,oldc,folder/'coordinator','finite-orchestrator',argv,c['outer_seconds'])
        result=dict(status='R151_FINITE_ORCHESTRATOR_LAUNCHED',run_id=run_id,folder=str(folder),coordinator=capsule)
        resource.immutable(RUNTIME/'launch.json',result);resource.immutable(folder/'launch.json',result)
        return result


def coordinate(run_id,unit):
    resource,science=apis();c=config();folder=run_folder(run_id);release=read(folder/'release.json')
    _,oldc=resource.verify_release(release);system=resource.load_legacy().System()
    outer=resource.await_capsule(folder/'coordinator');context=read(folder/'context.json')
    if outer['unit']!=unit or context['boot_id']!=resource.boot() or context['config_sha256']!=digest(CONFIG):
        raise RuntimeError('outer immutable capsule/context differs')
    stopped=[False]
    for sig in (signal.SIGTERM,signal.SIGINT):signal.signal(sig,lambda *_:stopped.__setitem__(0,True))
    terminal=dict(status='R151_FINITE_WORKFLOW_DEFERRED',new_model_fits=0,baseline_worker_signals=0,
        AL_launched=False,promotion_authorized=False,no_renewals=True,cleanup_errors=[])
    recovery=None;current=None;ee=None
    with resource.canonical_lock(RUNTIME/'workflow.lock'):
        try:
            resource.verify_control(system,outer,oldc)
            ee=resource.launch(folder/'release.json',folder/'probe.json',folder/'coordinator/attestation.json')
            recovery=ee['recovery_id'];resource.immutable(folder/'EE_launch.json',ee);current=ee['coordinator']
            previous=[None]
            def heartbeat():
                if stopped[0]:raise RuntimeError('outer cooperative stop')
                synthetic=dict(boot_id=context['boot_id'],expires_epoch=context['expires_epoch'])
                predicate=guard(system,release,outer,current,synthetic,science,recovery,previous[0]);previous[0]=predicate['handoff']
                resource.load_legacy().atomic(folder/'heartbeat.json',dict(phase='EE_RECOVERY',epoch=time.time(),predicates=predicate))
            wait_owned(system,current,min(context['expires_epoch'],time.time()+c['EE_coordinator_seconds']),oldc['poll_seconds'],heartbeat)
            current=None
            path=resource.recovery_folder(recovery)/'terminal.json'
            if not path.exists():raise RuntimeError('EE coordinator exited without strict terminal; no regional continuation')
            ee_terminal=read(path)
            for saved in resource.recovery_attempts()+resource.load_legacy().discover_workers(resource.recovery_folder(recovery)/'assessment'):
                resource.drain_exact(system,saved)
            disposition=ee_gate(resource.load_legacy().load_science(),ee_terminal)
            resource.immutable(folder/'EE_disposition.json',dict(disposition,terminal=ee_terminal,actual_owned_drain_verified=True))
            if not disposition['proceed']:raise RuntimeError(disposition['reason'])
            if stopped[0]:raise RuntimeError('outer cooperative stop before regional preparation')
            science.prepare();resource.immutable(science.PREP/'muscat_resources/outer_context.json',dict(run_id=run_id,
                outer_capsule_path=str(folder/'coordinator/attestation.json'),EE_recovery_id=recovery,
                release_path=str(folder/'release.json'),probe_path=str(folder/'probe.json')))
            for wave in c['regional_admissions']:
                if science.queue_state().get('scientific_complete'):break
                leases,terms=leases_and_terminals(science)
                if wave!=allowed_next_admission(list(leases),terms):break
                if wave!='benchmark':
                    q=science.queue_state()
                    if q['phase']=='DEFERRED_UNFUNDED_PREFIX':break
                    projection=regional_projection(science,q,leases,terms)
                    resource.immutable(folder/('regional_pre_wave_'+wave+'.json'),projection)
                    if not projection['fits']:
                        terminal['regional_budget_disposition']=projection;break
                lease=claim_regional_lease(science,wave,release,outer)
                control='pricefm-r150-r151-region-wave-'+wave+'-'+uuid.uuid4().hex+'.service'
                argv=[oldc['python_runtime'],'-B',str(ENTRY),'regional-wave','--run-id',run_id,'--wave',wave,'--controller-unit',control]
                current=resource.start_control(system,oldc,science.PREP/'muscat_resources'/('wave_'+wave)/'controller',
                    'regional-wave-'+wave,argv,lease['expires_epoch']-time.time(),parent=outer)
                previous=[None]
                def regional_heartbeat():
                    if stopped[0]:raise RuntimeError('outer cooperative stop')
                    predicate=guard(system,release,outer,current,lease,science,recovery,previous[0]);previous[0]=predicate['handoff']
                    resource.load_legacy().atomic(folder/'heartbeat.json',dict(phase='REGIONAL',wave=wave,epoch=time.time(),predicates=predicate))
                wait_owned(system,current,min(context['expires_epoch'],lease['expires_epoch']),oldc['poll_seconds'],regional_heartbeat)
                current=None;termpath=science.PREP/'muscat_resources'/('wave_'+wave)/'terminal.json'
                if not termpath.exists():raise RuntimeError('regional controller exited without terminal')
                result=read(termpath)
                if result.get('cleanup_verified') is not True or result.get('status')=='R151_REGION_GUARD_STOPPED':
                    raise RuntimeError('regional guard/cleanup stop')
                if result.get('resource_unfunded_pending'):
                    terminal['regional_unfunded_pending']=result['resource_unfunded_pending'];break
                if science.queue_state().get('scientific_complete'):break
            terminal['regional_queue']=science.queue_state()
            if terminal['regional_queue']['scientific_complete']:
                terminal['status']='R151_FINITE_WORKFLOW_COMPLETE_NOT_PROMOTED'
        except Exception as error:
            terminal.update(status='R151_FINITE_WORKFLOW_GUARD_STOPPED',original_stop_reason=repr(error))
        finally:
            workers=all_owned_workers(science,recovery)
            terminal.update(resource.cooperative_drain(system,workers,terminal.get('original_stop_reason','finite workflow ended'),grace=oldc['cooperative_grace_seconds']))
            capsules=[]
            if recovery:capsules=resource.recovery_capsules(recovery)
            capsules+=[resource.control_capsule(p.parent) for p in sorted((science.PREP/'muscat_resources').glob('wave_*/controller/intent.json'))]
            if current:capsules.append(current)
            for capsule in list({v['unit']:v for v in capsules if v['unit']!=outer['unit']}.values())[::-1]:
                try:resource.drain_exact(system,capsule)
                except Exception as error:terminal['cleanup_errors'].append(dict(unit=capsule['unit'],error=repr(error)))
            if terminal['cleanup_errors']:terminal['cleanup_verified']=False
            terminal.update(epoch=time.time(),run_id=run_id,source_head=release['source']['head'],EE_recovery_id=recovery)
            resource.immutable(folder/'terminal.json',terminal)
    return 0 if terminal['cleanup_verified'] and terminal['status']!='R151_FINITE_WORKFLOW_GUARD_STOPPED' else 2


def finalize_owned(system,release,outer,controller,lease,science,recovery,runtime):
    resource,_=apis();legacy=resource.load_legacy();oldc=read(legacy.CONFIG)
    if science.task_complete('__finalize__'):return
    if lease['expires_epoch']-time.time()<30:raise RuntimeError('finite lease lacks validation reserve')
    cpu=resource.passive_placement(oldc['cpus'])['ranked'][0]
    task=dict(name='__finalize__',estimated_cpu_seconds=0.)
    argv=[oldc['python_runtime'],'-B',str(REGIONAL_ENTRY),'worker','--name','__finalize__','--cpu',str(cpu),'--policy-receipt','{policy_receipt}']
    saved=resource.start_payload(system,oldc,runtime,task,cpu,lease,controller,argv,release['source'],digest(run_folder(read(science.PREP/'muscat_resources/outer_context.json')['run_id'])/'probe.json'))
    try:
        previous=[None]
        def observe():
            result=guard(system,release,outer,controller,lease,science,recovery,previous[0]);previous[0]=result['handoff']
        wait_owned(system,saved,lease['expires_epoch'],oldc['poll_seconds'],
            observe)
        if not science.task_complete('__finalize__'):raise RuntimeError('owned regional finalization lacks strict assessment seal')
    finally:
        proof=resource.cooperative_drain(system,[saved],'owned regional validation ended',grace=0,deadline=lease['expires_epoch'])
        if not proof['cleanup_verified']:raise RuntimeError('regional finalization cleanup failed')


def regional_wave(run_id,wave,unit):
    resource,science=apis();legacy=resource.load_legacy();folder=run_folder(run_id)
    release=read(folder/'release.json');_,oldc=resource.verify_release(release);c=config();system=legacy.System()
    outer=resource.await_capsule(folder/'coordinator');runtime=science.PREP/'muscat_resources'/('wave_'+wave)
    controller=resource.await_capsule(runtime/'controller');lease=read(runtime/'lease.json')
    if controller['unit']!=unit or lease['wave']!=wave:raise RuntimeError('regional controller/lease differs')
    recovery=read(science.PREP/'muscat_resources/outer_context.json')['EE_recovery_id']
    active={};stopped=[False];previous=None;reason=None;unfunded=[];status='R151_REGION_WAVE_DEFERRED'
    start=set(science.queue_state()['complete']);attempts_before=len(regional_attempts(science))
    for sig in (signal.SIGTERM,signal.SIGINT):signal.signal(sig,lambda *_:stopped.__setitem__(0,True))
    # Shared canonical scientific dispatch mutex is never replaced or renewed.
    with resource.canonical_lock(resource.CANONICAL/'controller.lock'):
        try:
            while True:
                predicate=guard(system,release,outer,controller,lease,science,recovery,previous);previous=predicate['handoff']
                if stopped[0]:raise RuntimeError('regional cooperative controller stop')
                for name,saved in list(active.items()):
                    props=system.unit(saved['unit']);legacy.verify_owned(saved,props)
                    if props.get('ActiveState') not in ('active','activating'):
                        resource.drain_exact(system,saved);del active[name]
                        if not science.task_complete(name):raise RuntimeError('regional payload exited without strict final seal: '+name)
                q=science.queue_state()
                if not active and q['phase']=='NOMINATION_REQUIRED':q=science.advance()
                if not active and q['phase']=='EXTRA_SEED_DECISION_REQUIRED':
                    leases,terms=leases_and_terminals(science);extras=prospective_extras(science)
                    projection=regional_projection(science,q,leases,terms,extra_names=extras)
                    allowance=projection['fresh_extra_allowance_CPU_seconds'] if projection['fits'] else 0.
                    view=dict(epoch=time.time(),lease_id=lease['lease_id'],projection=projection,
                        extra_components=extras,remaining_CPU_seconds=allowance,all_workers_drained=True)
                    legacy.atomic(science.PREP/'muscat_resources/resource_budget_view.json',view)
                    q=science.advance(remaining_CPU_seconds=allowance,budget_view=view)
                if not active and q['phase']=='MATCHED_MC_UNFUNDED_PENDING':
                    unfunded=q['unfunded_pending'];reason='entire matched extra set unfunded; no scientific completion claim';break
                if not active and q['terminal']:
                    if wave=='benchmark' and q['phase']!='DEFERRED_UNFUNDED_PREFIX':
                        status='R151_REGION_WAVE_COMPLETE';reason='benchmark sealed and drained';break
                    finalize_owned(system,release,outer,controller,lease,science,recovery,runtime)
                    status='R151_REGION_WAVE_COMPLETE';reason='owned regional assessment sealed';break
                if wave=='benchmark' and science.task_complete('__benchmark__') and not active:
                    status='R151_REGION_WAVE_COMPLETE';reason='fixed cost-only benchmark sealed and drained';break
                cutoff=lease['expires_epoch']-(0 if wave=='benchmark' else c['regional_cleanup_seconds'])
                if time.time()>=cutoff:reason='finite numerical window exhausted';break
                ready=[t for t in q['ready'] if t['name'] not in active]
                if (wave=='benchmark' and any(t['name']!='__benchmark__' for t in ready)) or (wave!='benchmark' and any(t['name']=='__benchmark__' for t in ready)):
                    raise RuntimeError('benchmark and numerical admissions mixed')
                projection=None
                if wave!='benchmark':
                    leases,terms=leases_and_terminals(science);projection=regional_projection(science,q,leases,terms,list(active.values()))
                dispatched=False
                if ready and len(active)<2:
                    cpus=[cpu for cpu in oldc['cpus'] if cpu not in [v['cpu'] for v in active.values()]]
                    placement=resource.passive_placement(cpus);legacy.atomic(runtime/'latest_placement.json',placement)
                    assignments={v['task']:v['slot'] for v in projection['packing']['allocation'] if v['slot']<2} if projection else {'__benchmark__':0}
                    occupied={v['resource_slot'] for v in active.values()}
                    for task in ready:
                        if len(active)>=(1 if wave=='benchmark' else 2):break
                        slot=assignments.get(task['name'])
                        if slot is None or slot in occupied:continue
                        if wave!='benchmark' and (not projection['fits'] or task['estimated_wall_seconds']>cutoff-time.time()):continue
                        cpu=placement['ranked'].pop(0)
                        argv=[oldc['python_runtime'],'-B',str(REGIONAL_ENTRY),'worker','--name',task['name'],'--cpu',str(cpu),'--policy-receipt','{policy_receipt}']
                        saved=resource.start_payload(system,oldc,runtime,task,cpu,lease,controller,argv,release['source'],digest(folder/'probe.json'))
                        saved['resource_slot']=slot;occupied.add(slot);legacy.atomic(saved['ledger_path'],saved)
                        active[task['name']]=saved;dispatched=True
                starved=[v for v in active.values() if (legacy.starvation_predicate(v,oldc) or {}).get('starved')]
                if starved:
                    if wave=='benchmark' or len(starved)>1:raise RuntimeError('regional benchmark/multiple-worker starvation')
                    saved=starved[0];token=science.PREP/'muscat_resources/replacement_token.json'
                    leases,terms=leases_and_terminals(science);projection=regional_projection(science,q,leases,terms,list(active.values()))
                    if token.exists() or not projection['fits']:raise RuntimeError('regional single replacement unavailable or unfunded')
                    with resource.canonical_lock(token.with_suffix('.lock'),blocking=True):
                        resource.immutable(token,dict(epoch=time.time(),task=saved['task'],old_unit=saved['unit'],
                            old_invocation_id=saved['attested']['InvocationID'],
                            lease_id=lease['lease_id'],source_head=release['source']['head'],resource_projection=projection))
                    proof=resource.cooperative_drain(system,[saved],'one regional same-lease placement replacement',grace=10,deadline=lease['expires_epoch'])
                    if not proof['cleanup_verified']:raise RuntimeError('regional replacement predecessor not drained')
                    resource.immutable(science.PREP/'muscat_resources/replacement_drain.json',dict(
                        token_sha256=digest(token),old_unit=saved['unit'],lease_id=lease['lease_id'],
                        predecessor_cgroup=saved['attested']['ControlGroup'],drain=proof))
                    del active[saved['task']]
                    if not science.task_complete(saved['task']):
                        task=science.estimate_task(saved['task'])
                        projection=regional_projection(science,science.queue_state(),leases,terms,list(active.values()))
                        occupied={v['resource_slot'] for v in active.values()}
                        assignment=next((a['slot'] for a in projection['packing']['allocation']
                            if a['task']==task['name'] and a['slot']<2 and a['slot'] not in occupied),None)
                        if not projection['fits'] or assignment is None or task['estimated_wall_seconds']>cutoff-time.time():
                            raise RuntimeError('regional replacement does not fit unchanged lease and remaining cohort')
                        choices=[cpu for cpu in oldc['cpus'] if cpu!=saved['cpu'] and cpu not in [v['cpu'] for v in active.values()]]
                        cpu=resource.passive_placement(choices)['ranked'][0]
                        argv=[oldc['python_runtime'],'-B',str(REGIONAL_ENTRY),'worker','--name',task['name'],'--cpu',str(cpu),'--policy-receipt','{policy_receipt}']
                        replacement=resource.start_payload(system,oldc,runtime,task,cpu,lease,controller,argv,release['source'],digest(folder/'probe.json'))
                        replacement['resource_slot']=assignment;legacy.atomic(replacement['ledger_path'],replacement)
                        active[task['name']]=replacement
                    resource.immutable(runtime/'replacement_proof.json',dict(token=read(token),predecessor_drain=proof,replacement=active.get(saved['task'])))
                legacy.atomic(runtime/'heartbeat.json',dict(epoch=time.time(),phase=q['phase'],active=list(active),predicates=predicate,resource_projection=projection))
                if not active and not dispatched:reason='no ready regional component fits current finite gates';break
                time.sleep(oldc['poll_seconds'])
        except Exception as error:status='R151_REGION_GUARD_STOPPED';reason=repr(error)
        finally:
            cleanup=resource.cooperative_drain(system,legacy.discover_workers(runtime),reason or 'finite regional wave ended',
                grace=oldc['cooperative_grace_seconds'],deadline=lease['expires_epoch'])
            current=science.queue_state();complete=set(current['complete'])
            if wave=='benchmark':new=int(science.task_complete('__benchmark__'))
            else:new=len(complete-start)
            terminal=dict(status=status,original_stop_reason=reason,cleanup_verified=cleanup['cleanup_verified'],
                cleanup_errors=cleanup['cleanup_errors'],cleanup=cleanup['cleanup'],epoch=time.time(),lease=lease,
                source_head=release['source']['head'],strict_new_components=new,
                resource_unfunded_pending=unfunded,scientific_complete=current['scientific_complete'],
                new_payload_attempts=len(regional_attempts(science))-attempts_before,new_model_fits=0,baseline_worker_signals=0)
            resource.immutable(runtime/'terminal.json',terminal)
    return 0 if cleanup['cleanup_verified'] and status!='R151_REGION_GUARD_STOPPED' else 2


def inspect(run_id=None):
    resource,science=apis();result=dict(config=config(),new_fits=0,regional_prepared=(science.PREP/'preparation.json').exists())
    if run_id:
        folder=run_folder(run_id)
        result.update({name:read(folder/(name+'.json')) for name in ('launch','heartbeat','EE_disposition','terminal') if (folder/(name+'.json')).exists()})
    return result


def main():
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest='action',required=True)
    p=sub.add_parser('launch');p.add_argument('--release',required=True);p.add_argument('--probe',required=True)
    for action in ('coordinate','regional-wave'):
        p=sub.add_parser(action);p.add_argument('--run-id',required=True);p.add_argument('--controller-unit',required=True)
        if action=='regional-wave':p.add_argument('--wave',choices=('benchmark','1','2','3'),required=True)
    p=sub.add_parser('inspect');p.add_argument('--run-id')
    p=sub.add_parser('test-hold');p.add_argument('--controller-unit',required=True)
    args=parser.parse_args()
    if args.action=='launch':value=launch(args.release,args.probe)
    elif args.action=='coordinate':raise SystemExit(coordinate(args.run_id,args.controller_unit))
    elif args.action=='regional-wave':raise SystemExit(regional_wave(args.run_id,args.wave,args.controller_unit))
    elif args.action=='test-hold':
        if not args.controller_unit.startswith('pricefm-r150-test-'):raise RuntimeError('hold is restricted to disposable probe units')
        time.sleep(60);return
    else:value=inspect(args.run_id)
    print(json.dumps(value,sort_keys=True,allow_nan=False),flush=True)


if __name__=='__main__':main()
