#!/usr/bin/env python3
"""Source-specific read-only owner6 health; no launch, registration or retry action."""
import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path
import sys
import time
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
import pricefm_r155_baseline_contract as c


def runner():
    spec=importlib.util.spec_from_file_location('r155_readonly_baseline_owner_api',Path(__file__).with_name('530_supervise_pricefm_stage_r155_baseline_continuation.py'))
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


def host_context(a):
    try:namespace=os.readlink('/proc/self/ns/pid')
    except OSError:namespace=None
    count=sum(p.name.isdigit() for p in Path('/proc').iterdir())
    boot=Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    return dict(host=os.uname().nodename,observer_pid=os.getpid(),observer_affinity=sorted(os.sched_getaffinity(0)),
        visible_processes=count,pid_namespace=namespace,boot_id=boot,
        full_host_view_verified=count>=100 and namespace==a['expected_host_pid_namespace'] and boot==a['expected_boot_id'])


def terminal_proof(a,path,state,attestation,system):
    runtime=Path(a['runtime']);terminal=c.read(runtime/'terminal.json')
    c.require(terminal['status']=='R155_ORIGINAL_NINE_TAIL_DISPOSITIONS_NOT_GLOBAL_PROMOTION'
        and terminal['authority']==c.pin(path) and terminal['activation']==c.ACTIVATION
        and terminal['execution_source']==a['execution_source'] and terminal['completed']==state['completed']
        and terminal['quarantined']==state['quarantined'] and not state['active'],'terminal control/source/dispositions differ')
    prior=c.verify_pin(a['predecessor_authority']);config=c.core().read_config(prior['legacy_config_path'])
    c.require(terminal['numerical_source_head']==config['source_head'],'terminal scientific source changed')
    for lane,queue in config['queues'].items():
        complete=state['completed'][lane];held=state['quarantined'][lane]
        c.require(len(complete)+len(held)==len(queue) and set(complete+held)==set(queue),'missing or duplicated original regional disposition')
        for region in complete:c.require(c.core().complete_region(config,region),'strict original regional closeout is absent')
        for region in held:
            receipt=runtime/'quarantine'/(region+'.json')
            if not receipt.is_file():receipt=Path(prior['runtime'])/'quarantine'/(region+'.json')
            c.require(c.read(receipt)['failed']==c.failed_certificates(config,region),'required-fit quarantine evidence differs')
    units={};all_drained=True;all_lifetimes_gone=True;unverified=[]
    for label,name in (('owner',a['new_unit']),('guardian',a['guardian_unit'])):
        unit=system.unit(name);life=attestation[label]['process']
        gone=not c.core().same_process(system.process(life['pid']),life);all_lifetimes_gone=all_lifetimes_gone and gone
        exact=unit.get('Id')==name and unit.get('LoadState')=='loaded' and unit.get('ActiveState')=='active'
        exact=exact and unit.get('SubState')=='exited' and unit.get('MainPID')=='0' and unit.get('RemainAfterExit')=='yes'
        exact=exact and unit.get('Result')=='success' and unit.get('ExecMainStatus')=='0'
        exact=exact and unit.get('Restart')=='no' and unit.get('NRestarts')=='0' and unit.get('KillMode')=='process'
        exact=exact and unit.get('ExecMainPID')==str(life['pid'])
        exact=exact and unit.get('InvocationID')==attestation[label]['unit_properties']['InvocationID']
        pending=not gone and unit.get('Id')==name and unit.get('LoadState')=='loaded'
        pending=pending and unit.get('ActiveState')=='active' and unit.get('SubState')=='running'
        pending=pending and unit.get('MainPID')==str(life['pid']) and unit.get('RemainAfterExit')=='yes'
        pending=pending and unit.get('InvocationID')==attestation[label]['unit_properties']['InvocationID']
        pending=pending and unit.get('Restart')=='no' and unit.get('NRestarts')=='0' and unit.get('KillMode')=='process'
        pending=pending and unit.get('ExecMainPID')==str(life['pid'])
        if not (exact and gone) and not pending:unverified.append(label)
        all_drained=all_drained and exact and gone;units[label]=unit
    status='COMPLETED_RETAINED_UNITS' if all_drained else 'COMPLETE_PACKET_CONTROL_EXIT_UNVERIFIED' if unverified else 'COMPLETE_PACKET_AWAITING_RETAINED_UNIT_EXIT'
    return dict(status=status,healthy_control=not unverified,retained_unit_closure_verified=all_drained,
        terminal=c.pin(runtime/'terminal.json'),strict_original_regional_dispositions_verified=True,
        administrative_units=units,all_exact_administrative_lifetimes_gone=all_lifetimes_gone,
        unverified_control_units=unverified,
        global_campaign_complete=False,scientific_promotion=False)


def _inspect(path,sha,system=None):
    c.require(os.sched_getaffinity(0)=={31},'read-only baseline health must use administrative31')
    path=Path(path).resolve();c.require(c.digest(path)==sha,'read-only actual authority pin differs');a=c.read(path)
    context=host_context(a)
    base=dict(schema='r155_baseline_owner6_readonly_health_v1',authority=c.pin(path),execution_source=a['execution_source'],
        activation=a['activation'],host_context=context,models=0,forecasts=0,services=0,runtime_writes=0,
        numerical_worker_signals=0,automatic_retry=False,global_campaign_complete=False,epoch=time.time())
    if not context['full_host_view_verified']:
        return dict(base,status='UNVERIFIED_OBSERVER_NAMESPACE',healthy_control=None,
            dispatch_currently_permitted=False,reason='private or incomplete process view cannot establish host health')
    c.verify_source(a['execution_source']);runtime=Path(a['runtime'])
    if a.get('status')=='PROPOSED':
        c.require(not (runtime/'activation_claim.json').exists(),'proposed authority unexpectedly consumed a claim')
        return dict(base,status='PREPARED_NOT_ADMITTED',healthy_control=None,activation_spent=False,dispatch_currently_permitted=False)
    a=c.validate_authority(path,sha);system=system or c.System(a['expected_host_pid_namespace'])
    if not (runtime/'activation_claim.json').is_file():
        return dict(base,status='ADMITTED_UNCLAIMED',healthy_control=None,activation_spent=False,dispatch_currently_permitted=False)
    claim=c.read(runtime/'activation_claim.json')
    c.require(claim['authority']==c.pin(path) and claim['activation']==c.ACTIVATION and claim['execution_source']==a['execution_source'],
        'actual one-use owner6 claim differs')
    base['activation_spent']=True
    if not (runtime/'state.json').is_file() or not (runtime/'launch_attestation.json').is_file():
        recent=time.time()-claim['claimed_epoch']<=120
        return dict(base,status='ACTIVATION_INITIALIZING' if recent else 'ACTIVATION_INCOMPLETE_OR_FAILED_NO_RETRY',
            healthy_control=None if recent else False,dispatch_currently_permitted=False,
            owner_unit=system.unit(a['new_unit']),guardian_unit=system.unit(a['guardian_unit']))
    state=c.read(runtime/'state.json');attestation=c.read(runtime/'launch_attestation.json')
    c.require(state['authority']==c.pin(path) and state['activation']==c.ACTIVATION and state['source']==a['execution_source']
        and attestation['authority']==c.pin(path) and attestation['execution_source']==a['execution_source'],
        'actual owner6 state/attestation source differs')
    if state.get('phase')=='complete' and (runtime/'terminal.json').is_file():
        proof=terminal_proof(a,path,state,attestation,system)
        return dict(base,**proof,dispatch_currently_permitted=False,
            completed=state['completed'],quarantined=state['quarantined'],control_budget=state['control_budget'])
    api=runner()
    try:
        owner,unit=api.control_capsule(a,attestation,'run',system);guardian=api.guardian_live(a,attestation,system)
        bootstrap=c.read(runtime/'guardian_priority_bootstrap.json')
        c.require(bootstrap['authority']==c.pin(path) and bootstrap['execution_source']==a['execution_source']
            and bootstrap['compatibility_proof']==a['guardian_priority_compatibility_proof']
            and bootstrap['pid']==guardian['pid'] and bootstrap['after_kernel_nice']==10
            and bootstrap['foreign_process_changes']==0,'guardian own-process priority bootstrap differs')
        epoch=c.read(runtime/'resource_ownership_epoch.json')
        c.require(epoch['authority']==c.pin(path) and epoch['activation']==c.ACTIVATION
            and epoch['execution_source']==a['execution_source'] and c.core().same_process(epoch['owner'],owner)
            and time.time()-epoch['heartbeat']<=a['guardian_lease_seconds'],'actual owner6 heartbeat/lease differs')
        charge=api.budget(a,state,system)
        healthy=charge['within_wall'] and charge['within_CPU'] and charge['within_guardian_CPU'] and state['phase'] not in api.TERMINAL
    except c.PublicationPending:raise
    except (RuntimeError,OSError,KeyError) as error:
        return dict(base,status='CONTROL_BLOCKED_OR_UNVERIFIED',healthy_control=False,dispatch_currently_permitted=False,
            state_phase=state.get('phase'),reason=repr(error),control_observation=getattr(error,'observation',None),
            owner_unit=system.unit(a['new_unit']),guardian_unit=system.unit(a['guardian_unit']))
    rows,census=c.collect_census(system);sessions={};current_gate=census['complete']
    if current_gate:
        prior=c.verify_pin(a['predecessor_authority']);config=c.core().read_config(prior['legacy_config_path']);policy=c.old.ContractPolicy(config,system)
        try:
            for lane,job in state['active'].items():
                copied=copy.deepcopy(job);members=c.old.session_members(copied,system,policy,census=rows)
                sessions[lane]=dict(region=job['region'],cpus=job['cpus'],session_id=job['session_id'],live_members=members)
        except c.CensusDeferred as deferred:census=deferred.observation;current_gate=False
    permitted=healthy and current_gate and state['phase']=='running' and state.get('adoption_verified') is True and not state.get('all_new_dispatch_deferred',True)
    return dict(base,status='CONTROL_HEALTHY_DISPATCH_DEFERRED' if healthy and not permitted else 'CONTROL_RUNNING' if healthy else 'CONTROL_NOT_HEALTHY',
        healthy_control=healthy,dispatch_currently_permitted=permitted,recorded_phase=state['phase'],
        owner=owner,guardian=guardian,owner_unit=unit,heartbeat=epoch['heartbeat'],heartbeat_age=time.time()-epoch['heartbeat'],
        census=census,sessions=sessions,control_budget=charge,completed=state['completed'],quarantined=state['quarantined'],
        guardian_priority_bootstrap=c.pin(runtime/'guardian_priority_bootstrap.json'),
        scheduling_policy=dict(owner=a['control_intent'],guardian=a['guardian_intent'],actual_kernel_IO_independently_verified=False),
        scientific_complete=False,original_controllers_and_fit_masks_unchanged=True)


def inspect(path,sha,system=None):
    try:return _inspect(path,sha,system)
    except c.PublicationPending as pending:
        return dict(schema='r155_baseline_owner6_readonly_health_v1',status='METADATA_PUBLICATION_PENDING',
            authority=dict(path=str(path),sha256=sha),healthy_control=None,dispatch_currently_permitted=False,
            publication=pending.observation,metadata_publication_observations=c.PUBLICATION_OBSERVATIONS[-64:],
            models=0,forecasts=0,services=0,runtime_writes=0,numerical_worker_signals=0,automatic_retry=False,epoch=time.time())


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--authority',required=True)
    parser.add_argument('--authority-sha256',required=True);args=parser.parse_args()
    print(json.dumps(inspect(args.authority,args.authority_sha256),indent=2,sort_keys=True,allow_nan=False))
