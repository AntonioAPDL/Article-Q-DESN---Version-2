#!/usr/bin/env python3
"""Metadata-only sixth-owner preparation; no service, fit or dispatch action."""
import argparse
import copy
import json
import math
import os
from pathlib import Path
import sys
import time
import uuid
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
import pricefm_r155_baseline_contract as c
BASE=c.ROOT.parents[1]/'pricefm_chat_continuation_20261021/r155_screening_recovery_20261027'
AUDIT=BASE/'baseline_control_owner6'
INCIDENT=BASE/'review/baseline_owner_failure_01/INDEPENDENT_INCIDENT_REVIEW_01.json'
INCIDENT_SHA='796ff92fc6d2f7c7a8041aecd43d166ea2b84a26c70b597b7c394b9e39807d60'


def immutable(path,value):
    return c.core().immutable(Path(path),value)


def prepare(destination,authority_path):
    c.require(os.sched_getaffinity(0)=={31},'metadata preparation must enter CPU31')
    destination=Path(destination).resolve();authority_path=Path(authority_path).resolve()
    c.require(destination.is_relative_to(AUDIT) and not destination.exists(),'new isolated audit preparation namespace required')
    source=c.source_identity();old=c.read(c.OLD_AUTHORITY);state=c.read(Path(old['runtime'])/'state.json')
    incident=c.read(INCIDENT);c.require(c.digest(INCIDENT)==INCIDENT_SHA
        and incident['status']=='CONFIRMED_CONTROL_BLOCKED_ORIGINAL_REGIONAL_WORKERS_PROGRESSING','exact independent incident review required')
    system=c.System(incident['actual_host_context']['pidns'])
    config=c.core().read_config(old['legacy_config_path']);locks=[]
    for name in config['legacy_locks']:
        path=Path(name);st=path.stat();c.require(not path.is_symlink(),'original dispatch lock symlink')
        locks.append(dict(path=str(path),device=st.st_dev,inode=st.st_ino))
    destination.mkdir(parents=True)
    raw=(Path(old['runtime'])/'state.json').read_bytes()
    with (destination/'predecessor_state.json').open('xb') as stream:stream.write(raw)
    bindings=dict(predecessor_authority=c.pin(c.OLD_AUTHORITY),predecessor_state=c.pin(destination/'predecessor_state.json'),
        predecessor_state_original=c.pin(Path(old['runtime'])/'state.json'),
        predecessor_attestation=c.pin(Path(old['runtime'])/'launch_attestation.json'),original_dispatch_locks=locks,
        spent_owner5=c.read(AUDIT/'SPENT_OWNER5_BINDING_01.json'),paid_scope_ledger=c.pin(AUDIT/'PAID_SCOPE_LEDGER_01.json'),
        historical_owner5_start_ticks_unavailable_acknowledged=True,
        guardian_priority_compatibility_proof=c.pin(AUDIT/'NICE_FIXTURE_PROOF_01.json'))
    c.verify_guardian_priority_proof(bindings['guardian_priority_compatibility_proof'])
    try:
        predecessor=c.verify_predecessor(bindings,system,require_full_census=True)
        c.verify_original_locks(bindings,require_free=True)
    except c.CensusDeferred as deferred:
        immutable(destination/'census_deferred.json',deferred.observation)
        result=dict(status='DEFER_ALL_NEW_DISPATCH_NO_ADMISSION',execution_source=source,bindings=bindings,
            census=c.pin(destination/'census_deferred.json'),models=0,services=0,scientific_dispatches=0)
        immutable(destination/'prepared.json',result);return result
    policy=c.old.ContractPolicy(config,system);sessions={};failed={};copied=copy.deepcopy(state)
    for lane,job in copied['active'].items():
        members=c.old.session_members(job,system,policy,census=predecessor['census'])
        sessions[lane]=dict(region=job['region'],cpus=job['cpus'],session_id=job['session_id'],
            original_root=state['active'][lane]['process'],live_members=members,refreshed_observed_children=job['observed_children'])
        diagnostics={};blockers=c.failed_certificates(config,job['region'],diagnostics)
        failed[job['region']]=dict(blockers=blockers,diagnostics=diagnostics)
    policy.verify_sources();c.core().verify_pins(config['source_sha256']);c.core().verify_pins(config['evidence_sha256'])
    runtime_limit_observation={}
    for lane,job in state['active'].items():
        observed=[]
        for member in sessions[lane]['live_members']:
            pid=member['pid'];lines=(Path('/proc')/str(pid)/'limits').read_text().splitlines()
            limit=next(line for line in lines if line.startswith('Max cpu time'))
            c.require('unlimited' in limit,'existing scientific session CPU inheritance is not unlimited')
            observed.append(dict(pid=pid,Max_cpu_time=limit))
        runtime_limit_observation[lane]=dict(original_root=job['process'],live_members=observed,
            no_members_means_natural_terminal_candidate_not_a_restart=not observed)
    dependency=dict(c.ADMIN_DEPENDENCIES)
    dependency.update({str(Path(old['execution_source']['root'])/p):sha for p,sha in old['execution_source']['runtime_sha256'].items()})
    failed5=c.verify_pin(bindings['spent_owner5']['authority'])
    dependency.update({str(Path(failed5['execution_source']['root'])/p):sha for p,sha in failed5['execution_source']['runtime_sha256'].items()})
    proof=dict(schema='r155_baseline_preparation_v1',status='PREPARED_SOURCE_ONLY_NOT_ADMITTED',execution_source=source,
        **bindings,incident_review=c.pin(INCIDENT),dependency_sha256=dependency,
        predecessor_runtime_sha256={str(p):c.digest(p) for p in Path(old['runtime']).rglob('*.json')},
        spent_owner5_runtime_sha256={str(p):c.digest(p) for p in Path(failed5['runtime']).iterdir() if p.is_file()},
        original_config=c.pin(old['legacy_config_path']),normal_build_context=old['normal_build_context'],
        census=system.last_census,sessions=sessions,failed_certificate_metadata=failed,
        scientific_controller_CPU_limits=runtime_limit_observation,policy_source_pins=policy.source_pins,
        policy_preparation_pins=policy.preparations,approved_identity_events=policy.events,
        original_control_clock=dict(starts_epoch=c.ORIGINAL_START,expires_epoch=c.ORIGINAL_EXPIRY,CPU_ceiling=c.ORIGINAL_CPU),
        original_pointer_preserved=c.pin(Path(old['legacy_baseline_runtime'])/'explicit_successor.json'),
        old_owner_unit=predecessor['old_owner_unit'],old_guardian_unit=predecessor['old_guardian_unit'],
        guardian_historical_exit=predecessor['guardian_historical_exit'],models=0,forecasts=0,services=0,scientific_dispatches=0,
        source_preparation_allowance=c.pin(AUDIT/'ALLOWANCE_01.json'),created_epoch=time.time())
    c.require(c.source_identity()==source,'new baseline source changed during preparation')
    immutable(destination/'preparation.json',proof)
    scope=uuid.uuid4().hex;runtime=c.DATA/'launch_prep'/('pricefm_stage_r155_baseline_continuation_'+scope)
    owner='pricefm-r155-baseline-owner-'+scope+'.service';guardian='pricefm-r155-baseline-guardian-'+scope+'.service'
    prior=c.OWNER6_PRIOR_CPU
    proposal=dict(schema='r155_baseline_control_authority_v1',status='PROPOSED',authority_id=scope,
        activation=c.ACTIVATION,automatic_retry=False,cached_restart_authorized=False,numerical_parameters_changed=False,
        runtime=str(runtime),new_unit=owner,guardian_unit=guardian,execution_source=source,preparation=c.pin(destination/'preparation.json'),
        **bindings,source_review=dict(path='ROOT_DISTINCT_RUNTIME_SOURCE_REVIEW',sha256='ROOT_SHA256'),
        predecessor_control_CPU_retained=c.PRIOR_CONTROL_CPU,predecessor_unobserved_tail_CPU_reserve=60,
        retained_owner5_fixed_control_CPU=c.OWNER5_FIXED_PAID_CPU,failure_inspection_CPU_debit=10,
        guardian_priority_policy='unit0_kernel10_self_only_before_attestation',
        preparation_CPU_debit=200,activation_wrapper_CPU_reserve=30,guardian_CPU_reserve=600,
        grant=dict(starts_epoch=c.ORIGINAL_START,expires_epoch=c.ORIGINAL_EXPIRY,wall_seconds=604800,
            control_CPU_seconds=c.ORIGINAL_CPU,prior_control_CPU_seconds=prior,
            administrative_source_check_CPU_reservation=.5,administrative_poll_CPU_reservation=.1),
        administrative_cpu=31,expected_host_pid_namespace=incident['actual_host_context']['pidns'],
        expected_boot_id=state['owner']['boot_id'],activation_epoch=None,unit_runtime_max_seconds=None,
        poll_seconds=20,source_verify_seconds=60,guardian_lease_seconds=180,
        control_intent=c.intent(owner,'run',authority_path),guardian_intent=c.intent(guardian,'guard',authority_path),
        original_scientific_limits_inherited_without_new_owner_CPU_cap=True,
        owner_budget_is_cooperative_with_independent_guardian_and_absolute_unit_deadline=True,
        hard_cgroup_CPU_enforcement_claimed=False,new_registration_path=str(runtime/'registration.json'))
    immutable(destination/'authority_proposal.json',proposal)
    result=dict(status='PASS_METADATA_PREPARED_NOT_ADMITTED',execution_source=source,
        preparation=c.pin(destination/'preparation.json'),authority_proposal=c.pin(destination/'authority_proposal.json'),
        original_budget_CPU_remaining_after_prior_debits=c.ORIGINAL_CPU-prior,
        new_owner_count=6,explicit_additional_activations=1,models=0,forecasts=0,services=0,scientific_dispatches=0)
    immutable(destination/'prepared.json',result);return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--destination',required=True)
    parser.add_argument('--authority-path',default=str(AUDIT/'ROOT_BASELINE_OWNER6_AUTHORITY_ADMITTED_01.json'))
    args=parser.parse_args()
    try:result=prepare(args.destination,args.authority_path)
    except c.CensusDeferred as deferred:
        destination=Path(args.destination).resolve()
        c.require(destination.is_relative_to(AUDIT),'deferred preparation escaped its audit namespace')
        immutable(destination/'late_census_deferred.json',deferred.observation)
        result=dict(status='DEFER_ALL_NEW_DISPATCH_NO_ADMISSION',census=c.pin(destination/'late_census_deferred.json'),
            models=0,forecasts=0,services=0,scientific_dispatches=0)
        immutable(destination/'prepared.json',result)
    print(json.dumps(result,indent=2,sort_keys=True))
