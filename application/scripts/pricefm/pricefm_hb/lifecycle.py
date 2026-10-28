"""Canonical finite R157 Slurm custody, activation, accounting and collection.

Every mutation is explicit. Existing baseline and qualification journals are
never adopted or reset. The legacy regional cost ledger remains authoritative
for its one-attempt allowance; a separate operational journal owns new jobs.
"""
from __future__ import annotations
import argparse
import atexit
import hashlib
import json
import math
import os
from pathlib import Path
import re
import resource
import shlex
import shutil
import socket
import subprocess
import time
import uuid

from . import activation as a, control as ctl, registry as r
from .environment import THREAD_ENV, REFERENCE_NUMERICAL_ENV, require_compute

SCHEMA = "r157_hb_lifecycle_v1"
RELEASE_SCHEMA = "r157_hb_release_v1"
CENTRAL = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/hb_control_registry')
FINAL = {"COLLECTED", "FAILED_RECONCILED"}
PARENT_SLICES = {}
REQUALIFICATION_SCHEMA = 'r157_control_test_requalification_v1'
CONTROL_RECOVERY_SCHEMA = 'r157_control_recovery_v1'
REPLACEMENT_PROTOCOL = 'r161_cost_replacement_v1'
QUALIFICATION_LINEAGE_SCHEMA = 'r161_control_qualification_lineage_v1'
COST_READY_OBSERVATION_GRACE = 30


def validate_historical_accepted_test(reference,state,*,current_sources=None):
    """Verify historical TEST03 JSON seals against its OLD closure, never NUM."""
    key=reference.get('claim_key');claim=state.get('claims',{}).get(key,{})
    if (claim.get('state')!='COLLECTED' or claim.get('application_accepted') is not True
            or claim.get('task',{}).get('purpose')!='CONTROL_TEST'
            or claim.get('scope_id')!='r157_control_placement_03'
            or str(claim.get('job_id'))!=str(reference.get('job_id'))):
        raise a.ActivationError('exact retained accepted TEST03 required')
    root=Path(claim['release_path']);publication=Path(claim['publication'])
    locations={'release':root/'release.json','publication':publication/'collection.json',
        'accounting':publication/'accounting.json','worker_evidence':publication/'outputs/worker_evidence.json',
        'parity_result':publication/'outputs/TEST/parity/parity.json',
        'parity_seal':publication/'outputs/TEST/parity/completed_evidence.json',
        'runtime_result':publication/'outputs/environment-runtime.json'}
    records={}
    for name,path in locations.items():
        if reference.get(name)!=pin(path):raise a.ActivationError('historical TEST03 metadata pin differs: '+name)
        records[name]=a.read_pin(reference[name])
    old=records['release'];worker=records['worker_evidence'];parity=records['parity_result'];runtime=records['runtime_result']
    if (reference['release']['sha256']!=claim['release_sha256']
            or r.digest(publication/'release.json')!=claim['release_sha256']
            or old.get('task_key')!=key or old.get('purpose')!='CONTROL_TEST'
            or old.get('scope_id')!=claim['scope_id'] or old.get('source_hashes')!=reference.get('source_hashes')
            or set(old.get('source_hashes',{}))!=set(a.BASE_SOURCES)
            or worker.get('schema')!=SCHEMA or worker.get('task_key')!=key
            or worker.get('job_id')!=claim['job_id'] or worker.get('release_sha256')!=claim['release_sha256']
            or worker.get('authority_sha256')!=claim['authority_sha256']
            or worker.get('source_hashes')!=old['source_hashes'] or worker.get('application_passed') is not True
            or worker.get('new_model_fits')!=0 or worker.get('official_origins')!=0
            or records['publication'].get('application_accepted') is not True
            or records['publication'].get('no_refund') is not True
            or records['publication'].get('task_key')!=key
            or records['publication'].get('reserved_CPU_seconds')!=old['resources']['cpu_seconds']):
        raise a.ActivationError('retained TEST03 original source/worker/paid publication differs')
    mutable={'lifecycle.py','activation.py','admission.py','benchmark.py','cost_control.py','operation_budget.py'}
    current=a.executed_sources('CONTROL_TEST') if current_sources is None else current_sources
    if any(old['source_hashes'][name]!=current.get(name) for name in set(a.BASE_SOURCES)-mutable):
        raise a.ActivationError('historical TEST03 numerical/fixture/runtime source changed')
    request_path=root/'launch-request.json'
    if r.digest(request_path)!=old['request_sha256']:raise a.ActivationError('old TEST03 launch request changed')
    request=r.read(request_path);gate=a.validate_qualification(request,reader=a.read_pin)
    from .fixture import ARRAY_SHAPES
    comparisons=parity.get('array_comparison',{})
    if (parity.get('status')!='PASS_TEST_FORECAST_PARITY' or parity.get('accepted') is not True
            or set(comparisons)!=set(ARRAY_SHAPES)
            or any(v.get('accepted') is not True or v.get('shape')!=ARRAY_SHAPES[name]
                   for name,v in comparisons.items())
            or parity.get('execution',{}).get('namespace')!='TEST'
            or parity['execution'].get('slurm_job_id')!=claim['job_id']
            or parity['execution'].get('fixture_manifest_sha256')!=request['accepted_parity_fixture_manifest_sha256']
            or records['parity_seal'].get('status')!='COMPLETE_TEST_ONLY'
            or records['parity_seal'].get('artifacts',{}).get('parity.json')!=reference['parity_result']['sha256']
            or worker.get('files',{}).get('TEST/parity/parity.json')!=reference['parity_result']['sha256']
            or worker['files'].get('TEST/parity/completed_evidence.json')!=reference['parity_seal']['sha256']
            or worker['files'].get('environment-runtime.json')!=reference['runtime_result']['sha256']
            or runtime.get('status')!='verified' or runtime.get('allocation',{}).get('job_id')!=claim['job_id']
            or any(runtime.get(name)!=gate['parity_runtime'].get(name)
                   for name in ('executable','python_version','versions','native_library_sha256'))):
        raise a.ActivationError('retained TEST03 complete15-array/runtime metadata differs')
    accounting=records['accounting'];parsed=parse_accounting(accounting['sacct_with_times'],claim['job_id'],old['resources'])
    if (accounting.get('task_key')!=key or accounting.get('job_id')!=claim['job_id']
            or accounting.get('release_sha256')!=claim['release_sha256']
            or accounting.get('squeue','').strip() or accounting.get('complete') is not True
            or accounting.get('terminal') is not True or not parsed['terminal'] or not parsed['complete']
            or parsed['scope_violations']):
        raise a.ActivationError('retained TEST03 terminal paid accounting differs')
    return claim,old


def validate_r161_control_test(value,release,state,*,now,allow_spent=False,packet=None):
    """Exactly TEST04 preserves two failures and accepted03; no fifth default."""
    from .operation_budget import OperationBudget,recovery_claims
    lineage=a.read_pin(value.get('qualification_lineage'))
    if (value.get('protocol_version')!=REPLACEMENT_PROTOCOL
            or value.get('schema')!=REQUALIFICATION_SCHEMA
            or value.get('status')!='ROOT_ADMITTED_ONE_SOURCE_BOUND_REPLACEMENT_TEST'
            or value.get('controller')!=a.OWNER or value.get('scope_id')!='r161_control_placement_04'
            or release.get('scope_id')!=value['scope_id'] or type(value.get('max_new_attempts')) is not int or value.get('max_new_attempts')!=1
            or value.get('old_charges_refunded') is not False
            or value.get('new_executed_sources')!=release.get('source_hashes')
            or value.get('new_executed_sources')!=a.executed_sources('CONTROL_TEST')
            or lineage.get('schema')!=QUALIFICATION_LINEAGE_SCHEMA
            or lineage.get('status')!='ROOT_ADMITTED_TEST04_PRESERVING_OLD_ACCEPTED_TEST'
            or lineage.get('protocol_version')!=REPLACEMENT_PROTOCOL or lineage.get('controller')!=a.OWNER
            or type(lineage.get('max_new_attempts')) is not int or lineage.get('max_new_attempts')!=1 or lineage.get('old_charges_refunded') is not False
            or lineage.get('old_clocks_mutated') is not False):
        raise a.ActivationError('explicit source-bound TEST04 lineage required')
    for document in (value,lineage):
        if (type(document.get('created_epoch')) not in (int,float) or type(document.get('expires_epoch')) not in (int,float)
                or not math.isfinite(document['created_epoch']) or not math.isfinite(document['expires_epoch'])
                or not document['created_epoch']<=now<document['expires_epoch']):
            raise a.ActivationError('finite current TEST04 decision required')
    references=lineage.get('prior_failed_tests',[])
    if not isinstance(references,list) or len(references)!=2:
        raise a.ActivationError('TEST04 retains exactly both original failed tests')
    failed=[validate_failed_test(ref,state) for ref in references]
    if [c['scope_id'] for c,_ in failed]!=['r157_control_placement_01','r157_control_placement_02']:
        raise a.ActivationError('TEST04 failed lineage order differs')
    accepted,old=validate_historical_accepted_test(lineage.get('prior_accepted_test',{}),state,
        current_sources=release['source_hashes'])
    expected=[c['task_key'] for c,_ in failed]+[accepted['task_key']]
    if allow_spent:expected.append(release['task_key'])
    if state.get('spent_tests')!=expected:
        raise a.ActivationError('TEST04 is the only explicitly admitted next qualification; no fifth')
    old_spec=old['control_cpu_scope'];new_spec=release.get('control_cpu_scope')
    if lineage.get('paid_control_authorization')!=old_spec['authorization_pin'] or new_spec==old_spec:
        raise a.ActivationError('TEST04 must preserve, not renew, paid03 control')
    paid=OperationBudget(old_spec['path']).historical_snapshot(lineage.get('paid_control_snapshot'),old_spec['authorization_pin'])
    if paid['claims'].get(accepted['task_key'],{}).get('reserved_CPU')!=230:
        raise a.ActivationError('accepted03 paid control reservation missing')
    budget,active=control_scope(release,now=now);authorization=a.read_pin(new_spec['authorization_pin'])
    roles=recovery_claims(authorization)
    if (authorization.get('protocol_version')!=REPLACEMENT_PROTOCOL
            or authorization.get('qualification_lineage')!=value['qualification_lineage']
            or active.get('kind')!='INITIAL' or active.get('CPU_ceiling')!=720
            or new_spec['scope_id']==old_spec['scope_id']
            or not roles or release.get('task_key') is not None and roles.get(release['task_key'])!={
                'purpose':'CONTROL_TEST','study':'TEST','scope_id':'r161_control_placement_04'}
            or value['expires_epoch']>active['expires_epoch'] or lineage['expires_epoch']>active['expires_epoch']
            or packet is None or active['expires_epoch']>packet['expires_epoch']):
        raise a.ActivationError('TEST04 requires exact new protocol funding/lineage without old-clock mutation')
    return value


def select_cost_qualification(release,state,packet):
    """Select one explicitly identified accepted TEST with the same current17."""
    tests=[state['claims'][key] for key in state.get('spent_tests',[])]
    accepted=[v for v in tests if v.get('state')=='COLLECTED' and v.get('application_accepted') is True]
    if any(v not in accepted and (v.get('state')!='FAILED_RECONCILED' or v.get('application_accepted') is not False) for v in tests):
        raise a.ActivationError('all other qualification attempts must retain terminal failures')
    matching=[]
    for claim in accepted:
        root=Path(claim['release_path'])
        if r.digest(root/'release.json')!=claim['release_sha256']:raise a.ActivationError('accepted TEST release changed')
        qualified=r.read(root/'release.json')
        if qualified.get('source_hashes')==release['source_hashes']:matching.append((claim,qualified))
    if len(matching)!=1:raise a.ActivationError('exactly one accepted TEST for this current17 closure required')
    selected,qualified=matching[0]
    if len(accepted)>1:
        selector=release.get('accepted_control_test')
        if (selector!={'claim_key':selected['task_key'],'release':pin(Path(selected['release_path'])/'release.json')}
                or selected.get('scope_id')!='r161_control_placement_04'):
            raise a.ActivationError('multiple accepted TESTs require explicit current TEST04 lineage selection')
    verified=verify_release(selected['release_path']) # Only CURRENT closure, never historical03.
    if verified!=qualified or verified.get('source_hashes')!=release['source_hashes']:
        raise a.ActivationError('selected current TEST metadata/source changed during verification')
    if len(tests)>1:
        value=a.read_pin(qualified.get('control_test_requalification'))
        validate_control_test_requalification(value,qualified,state,now=selected['created'],allow_spent=True,packet=packet)
        if value.get('control_recovery') is not None or value.get('scope_id')=='r161_control_placement_04':
            from .operation_budget import recovery_claims
            spec=qualified['control_cpu_scope'];roles=recovery_claims(a.read_pin(spec['authorization_pin']))
            if (release.get('control_cpu_scope')!=spec or roles.get(release['task_key'])!={
                    'purpose':'COST_ONLY','study':release['study'],'scope_id':release['scope_id']}):
                raise a.ActivationError('COST requires its exact current TEST funding and root-bound role')
    return selected,qualified


def validate_failed_test(reference, state):
    """Read the original failed publication without reinterpreting its old code."""
    key=reference.get('prior_failed_claim_key');claim=state.get('claims',{}).get(key,{})
    if (claim.get('task',{}).get('purpose')!='CONTROL_TEST' or claim.get('state')!='FAILED_RECONCILED'
            or claim.get('application_accepted') is not False or not re.fullmatch(r'[1-9][0-9]*',str(claim.get('job_id','')))
            or reference.get('prior_failed_job_id')!=claim['job_id']):
        raise a.ActivationError('exact canonical failed drained TEST reference required')
    publication=r.no_links(claim['publication'])
    expected={'prior_publication':publication/'collection.json'}
    evidence=reference.get('prior_evidence',{})
    expected.update({name:publication/rel for name,rel in (
        ('accounting','accounting.json'),('worker_evidence','outputs/worker_evidence.json'),
        ('worker_failure','outputs/worker-failure.json'))})
    records={}
    for name,path in expected.items():
        value=reference.get(name) if name=='prior_publication' else evidence.get(name)
        if value!=pin(path):raise a.ActivationError('exact failed TEST publication/evidence pin required')
        records[name]=a.read_pin(value)
    old_path=Path(claim['release_path'])/'release.json'
    if r.digest(old_path)!=claim['release_sha256'] or r.digest(publication/'release.json')!=claim['release_sha256']:
        raise a.ActivationError('original failed release bytes changed')
    old=r.read(old_path);collection=records['prior_publication'];accounting=records['accounting'];worker=records['worker_evidence']
    if (old.get('purpose')!='CONTROL_TEST' or old.get('task_key')!=key
            or collection.get('schema')!=SCHEMA or collection.get('task_key')!=key
            or collection.get('application_accepted') is not False or collection.get('no_refund') is not True
            or collection.get('reserved_CPU_seconds')!=old['resources']['cpu_seconds']
            or accounting.get('task_key')!=key or accounting.get('job_id')!=claim['job_id']
            or accounting.get('release_sha256')!=claim['release_sha256'] or accounting.get('terminal') is not True
            or accounting.get('complete') is not False or accounting.get('squeue','').strip()
            or worker.get('schema')!=SCHEMA or worker.get('task_key')!=key
            or worker.get('job_id')!=claim['job_id'] or worker.get('release_sha256')!=claim['release_sha256']
            or worker.get('application_passed') is not False
            or worker.get('files',{}).get('worker-failure.json')!=evidence['worker_failure']['sha256']
            or worker.get('error')!=records['worker_failure'] or not worker.get('error')):
        raise a.ActivationError('complete failed TEST collection/accounting/worker identity required')
    parsed=parse_accounting(accounting['sacct_with_times'],claim['job_id'],old['resources'])
    if not parsed['terminal'] or parsed['complete']:
        raise a.ActivationError('prior failed TEST must have independently parsed terminal failure')
    return claim,old


def validate_control_test_requalification(value,release,state,*,now=None,allow_spent=False,packet=None):
    """One prospective source-bound replacement; old paid attempts stay spent."""
    now=time.time() if now is None else now
    if value.get('scope_id')=='r161_control_placement_04':
        return validate_r161_control_test(value,release,state,now=now,allow_spent=allow_spent,packet=packet)
    if (value.get('schema')!=REQUALIFICATION_SCHEMA
            or value.get('status')!='ROOT_ADMITTED_ONE_SOURCE_BOUND_REPLACEMENT_TEST'
            or value.get('controller')!=a.OWNER or type(value.get('max_new_attempts')) is not int or value.get('max_new_attempts')!=1
            or value.get('old_charges_refunded') is not False or value.get('all_prior_failed_terminal') is not True
            or not re.fullmatch(r'[A-Za-z0-9_-]{8,160}',str(value.get('scope_id','')))
            or value.get('scope_id') not in {'r157_control_placement_02','r157_control_placement_03'}
            or value.get('scope_id')!=release.get('scope_id')
            or value.get('new_executed_sources')!=release.get('source_hashes')
            or value.get('new_executed_sources')!=a.executed_sources('CONTROL_TEST')
            or type(value.get('created_epoch')) not in (int,float) or type(value.get('expires_epoch')) not in (int,float)
            or not math.isfinite(value['created_epoch']) or not math.isfinite(value['expires_epoch'])
            or not value['created_epoch']<=now<value['expires_epoch']):
        raise a.ActivationError('exact finite new-source replacement TEST authorization required')
    if value['scope_id']=='r157_control_placement_03':
        references=value.get('prior_failed_tests')
        fields=('prior_failed_claim_key','prior_failed_job_id','prior_publication','prior_evidence')
        if (not isinstance(references,list) or len(references)!=2
                or any(not isinstance(v,dict) for v in references)
                or any(value.get(k)!=references[-1].get(k) for k in fields)
                or value.get('control_recovery') is None):
            raise a.ActivationError('third TEST requires both ordered failures and the latest failed reference')
        predecessors=[validate_failed_test(reference,state) for reference in references]
        if [claim['scope_id'] for claim,_ in predecessors]!=['r157_control_placement_01','r157_control_placement_02']:
            raise a.ActivationError('third TEST requires exactly the original and second failed TEST scopes')
    else:
        if value.get('prior_failed_tests') is not None:
            raise a.ActivationError('scope02 retains its single original failed TEST lineage')
        predecessors=[validate_failed_test(value,state)]
        if predecessors[0][0]['job_id']!='868958' or predecessors[0][0]['scope_id']!='r157_control_placement_01':
            raise a.ActivationError('scope02 requires the original failed TEST868958')
    prior,old=predecessors[-1]
    if release['scope_id']==prior['scope_id']:raise a.ActivationError('replacement TEST requires its own distinct scope')
    spent=state.get('spent_tests',[])
    expected=[claim['task_key'] for claim,_ in predecessors]+([release['task_key']] if allow_spent else [])
    if spent!=expected:raise a.ActivationError('only one explicitly authorized replacement TEST is permitted')
    from .operation_budget import OperationBudget
    if value.get('control_recovery') is not None:
        recovered=validate_control_recovery(a.read_pin(value['control_recovery']),old,release,now=now,packet=packet,state=state)
        if value['expires_epoch']>recovered['expires_epoch']:
            raise a.ActivationError('replacement cannot exceed its new finite recovery scope')
    else:
        original=OperationBudget(old['control_cpu_scope']['path']).snapshot(now)
        if (original['kind']!='INITIAL' or original['authorization']!=old['control_cpu_scope']['authorization_pin']
                or value['expires_epoch']>original['expires_epoch']):
            raise a.ActivationError('replacement cannot reset the original paid control clock')
    if packet is not None and value['expires_epoch']>packet['expires_epoch']:
        raise a.ActivationError('replacement cannot extend current resource policy expiry')
    return value


def validate_control_recovery(value,old,release,*,now,packet,state=None):
    """A distinct prospective budget preserves, rather than renews, old history."""
    from .operation_budget import OperationBudget, recovery_claims
    old_spec=old['control_cpu_scope'];new_spec=release.get('control_cpu_scope')
    statuses={'ROOT_ADMITTED_NEW_FINITE_CONTROL_RECOVERY_PRESERVING_EXPIRED_HISTORY',
              'ROOT_ADMITTED_NEW_FINITE_CONTROL_RECOVERY_PRESERVING_PAID_HISTORY'}
    if (value.get('schema')!=CONTROL_RECOVERY_SCHEMA or value.get('status') not in statuses
            or value.get('controller')!=a.OWNER or value.get('old_control_cpu_scope')!=old_spec
            or value.get('new_control_cpu_scope')!=new_spec or new_spec==old_spec
            or value.get('old_charges_refunded') is not False or value.get('old_clocks_mutated') is not False
            or value.get('automatic_retry') is not False or type(value.get('max_new_claims')) is not int
            or value.get('max_new_claims')!=3 or value.get('kind')!='INITIAL' or value.get('CPU_ceiling')!=720
            or not isinstance(new_spec,dict)
            or type(value.get('created_epoch')) not in (int,float) or type(value.get('expires_epoch')) not in (int,float)
            or not math.isfinite(value['created_epoch']) or not math.isfinite(value['expires_epoch'])
            or not value['created_epoch']<=now<value['expires_epoch']
            or packet is None or value['expires_epoch']>packet['expires_epoch']):
        raise a.ActivationError('explicit prospective source-bound control recovery required')
    historical=OperationBudget(old_spec['path']).historical_snapshot(value.get('old_snapshot'),old_spec['authorization_pin'])
    if value['status']=='ROOT_ADMITTED_NEW_FINITE_CONTROL_RECOVERY_PRESERVING_EXPIRED_HISTORY':
        if historical['expires_epoch']>value['created_epoch']:
            raise a.ActivationError('expired-history recovery cannot renew an unexpired control scope')
    else:
        claims=(state or {}).get('claims',{})
        if (not historical['claims'] or any(key not in claims or claims[key].get('state')!='FAILED_RECONCILED'
                or claims[key].get('application_accepted') is not False
                or r.read(Path(claims[key]['release_path'])/'release.json').get('control_cpu_scope')!=old_spec
                for key in historical['claims'])):
            raise a.ActivationError('paid-history recovery requires every admitted old control claim failed and reconciled')
    budget,active=control_scope(release,now=now)
    authorization=a.read_pin(new_spec['authorization_pin']);restrictions=recovery_claims(authorization)
    if (historical['scope_id']!=old_spec['scope_id']
            or active['kind']!='INITIAL' or active['CPU_ceiling']!=720 or restrictions is None
            or active.get('recovery_claims')!=restrictions
            or not value['created_epoch']<=active['created_epoch']<=now
            or value['expires_epoch']>active['expires_epoch']
            or active['expires_epoch']>packet['expires_epoch']
            or release.get('task_key') is not None and restrictions.get(release['task_key'])!={
                'purpose':'CONTROL_TEST','study':'TEST','scope_id':release['scope_id']}):
        raise a.ActivationError('recovery must retain expired history and bind exactly one new TEST/FI/DK2 budget')
    return dict(active,expires_epoch=min(active['expires_epoch'],value['expires_epoch']))


def validate_compute_limits(resources,*,getter=None):
    """Observe exact declared process ceilings before numerical package imports."""
    getter=resource.getrlimit if getter is None else getter
    cpu=math.ceil(resources['cpu_seconds']);memory=resources['memory_MiB']*1024**2
    observed_cpu=getter(resource.RLIMIT_CPU);observed_as=getter(resource.RLIMIT_AS)
    if (observed_cpu!=(cpu,cpu) or observed_as[0]!=memory
            or observed_as[1]!=resource.RLIM_INFINITY and observed_as[1]<memory):
        raise a.ActivationError('actual CPU/address-space limits differ from declared compute allocation')
    return dict(schema='r157_declared_compute_process_limits_v1',status='VERIFIED_BEFORE_NUMERICAL_IMPORTS',
        CPU_soft_seconds=observed_cpu[0],CPU_hard_seconds=observed_cpu[1],AS_soft_bytes=observed_as[0],
        AS_hard_bytes=observed_as[1],declared_CPU_seconds=cpu,allocated_memory_MiB=resources['memory_MiB'],
        sbatch_propagate='NONE',scheduler_resources_unchanged=True)


def establish_compute_limits(resources,authority,*,evidence_path,getter=None,setter=None):
    """Record raw limits, then clamp only within the sealed allocated bounds."""
    getter=resource.getrlimit if getter is None else getter
    setter=resource.setrlimit if setter is None else setter
    def observed():
        return dict(CPU=list(getter(resource.RLIMIT_CPU)),AS=list(getter(resource.RLIMIT_AS)))
    before=observed();path=Path(evidence_path)
    evidence=dict(schema='r158_compute_process_limits_v1',before=before,
        declared_resources=resources,authority_resources=authority.get('resources'),
        sbatch_propagate='NONE',scheduler_resources_unchanged=True)
    write_new(path.with_name(path.stem+'-before'+path.suffix),dict(evidence,status='RAW_OBSERVED_BEFORE_NUMERICAL_IMPORTS'))
    try:
        purpose=authority.get('purpose');cpu=resources.get('cpu_seconds');memory=resources.get('memory_MiB')
        if (authority.get('resources')!=resources or purpose not in a.PURPOSES
                or resources.get('cpus')!=1 or type(cpu) not in (int,float) or not math.isfinite(cpu)
                or type(resources.get('wall_seconds')) is not int
                or not 0<cpu<=resources['wall_seconds']<=a.PURPOSES[purpose]
                or type(memory) is not int or not 1024<=memory<=8192):
            raise a.ActivationError('declared process limits must match exact sealed purpose/allocation resources')
        desired=dict(CPU=math.ceil(cpu),AS=memory*1024**2)
        if any(before[name][1]!=resource.RLIM_INFINITY and before[name][1]<limit for name,limit in desired.items()):
            raise a.ActivationError('existing hard limit cannot cover the declared allocation')
        setter(resource.RLIMIT_CPU,(desired['CPU'],desired['CPU']))
        setter(resource.RLIMIT_AS,(desired['AS'],desired['AS']))
        after=observed()
        if after!={name:[limit,limit] for name,limit in desired.items()}:
            raise a.ActivationError('kernel did not establish exact declared process limits')
        evidence.update(status='VERIFIED_BEFORE_NUMERICAL_IMPORTS',after=after)
    except BaseException as exc:
        evidence.update(status='REJECTED_BEFORE_NUMERICAL_IMPORTS',after=observed(),
            error=dict(type=type(exc).__name__,message=str(exc)))
        write_new(path,evidence)
        raise a.ActivationError('compute limit establishment failed; before='+repr(before)+
            '; after='+repr(evidence['after'])+'; '+str(exc)) from exc
    write_new(path,evidence)
    return evidence


def job_script(resources):
    cpu=math.ceil(resources['cpu_seconds']);memory_KiB=resources['memory_MiB']*1024
    script='''#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin SLURM_EXPORT_ENV=ALL
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
root=$1
sha=$2
export PYTHONPATH="$root/code" PRICEFM_RELEASE_ROOT="$root"
'''
    script+='\n'.join('export '+k+'='+shlex.quote(v) for k,v in sorted(dict(THREAD_ENV,**REFERENCE_NUMERICAL_ENV).items()))+'\n'
    script+='ulimit -t '+str(cpu)+'\n'
    script+='ulimit -S -v '+str(memory_KiB)+'\n'
    return script+'exec /usr/bin/srun --cpu-bind=cores /usr/bin/python3 -B -m pricefm_hb.lifecycle worker --release "$root" --release-sha256 "$sha"\n'


def owner():
    if socket.getfqdn() != a.OWNER or os.sched_getaffinity(0) != {31}:
        raise a.ActivationError("canonical Muscat administrative31 required")


def write_new(path, value):
    path = r.no_links(path)
    if path.exists():
        raise FileExistsError("create-only evidence: " + str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    r.write(path, value)
    return {"path": str(path), "sha256": r.digest(path)}


def pin(path):
    return {"path": str(r.no_links(path)), "sha256": r.digest(path)}


def policy_document(policy_pin):
    from . import policy
    packet = a.read_pin(policy_pin)
    policy.validate_policy(packet, require_admitted=True, check_files=True)
    return packet


def hb_concurrency(packet):
    # The explicit policy API supplies a canonical limit; reject unknown schema
    # rather than interpreting blank scheduler/user fields as unlimited.
    from . import policy
    if hasattr(policy, "hb_concurrency"):
        return policy.hb_concurrency(packet)
    matrix = packet.get("resource_matrix", packet.get("matrix", {}))
    hb = matrix.get("HB", matrix.get("hummingbird", {}))
    limit = hb.get("max_workers", hb.get("max_numerical_workers", packet.get("HB_max_workers")))
    if type(limit) is not int or not 1 <= limit <= 72:
        raise a.ActivationError("explicit validated HB concurrency limit required")
    return limit


class Ledger:
    def __init__(self):
        owner(); CENTRAL.mkdir(parents=True, exist_ok=True)
        self.path = CENTRAL/'activation_registry.json'

    def snapshot(self):
        with r.lock(CENTRAL/'activation_registry.lock'):
            return r.read(self.path) if self.path.exists() else dict(schema=SCHEMA, owner=a.OWNER, claims={}, spent_tests=[])

    def reserve(self, release, release_path, config):
        packet = policy_document(release['policy_pin'])
        key = release['task_key']
        if release.get('cost_replacement') is not None:
            from . import cost_control
            plan=r.read(Path(release_path)/'plan.json')
            cost_control.validate_replacement(release['cost_replacement'],plan,release['plan_sha256'],phase='preclaim')
        with r.lock(CENTRAL/'activation_registry.lock'):
            state = r.read(self.path) if self.path.exists() else dict(schema=SCHEMA, owner=a.OWNER, claims={}, spent_tests=[])
            if state.get('schema') != SCHEMA or state.get('owner') != a.OWNER:
                raise a.ActivationError('operational registry identity differs')
            active = [v for v in state['claims'].values() if v['state'] not in FINAL]
            if key in state['claims'] or len(active) >= hb_concurrency(packet):
                raise a.ActivationError('duplicate/spent task or concurrent claim ceiling')
            if release['purpose'] in {'CONTROL_TEST','COST_ONLY'} and active:
                raise a.ActivationError('test and cost stages require complete previous claim drain')
            if release['purpose']=='COST_ONLY':
                selected,_ = select_cost_qualification(release,state,packet)
                if selected.get('scope_id')=='r161_control_placement_04' and release.get('cost_replacement') is None:
                    raise a.ActivationError('TEST04 COST requires its explicit replacement permit before reservation')
            if release['purpose'] == 'CONTROL_TEST' and state['spent_tests']:
                value=a.read_pin(release.get('control_test_requalification'))
                validate_control_test_requalification(value,release,state,packet=packet)
            elif release['purpose']=='CONTROL_TEST' and release.get('control_test_requalification') is not None:
                raise a.ActivationError('replacement TEST cannot discard its original failed lineage')
            claim = dict(task_key=key, task=dict(purpose=release['purpose'], study=release['study'],
                scientific_exclusion_key=release['scientific_exclusion_key'], plan_sha256=release['plan_sha256']),
                scope_id=release['scope_id'], state='RESERVED', created=time.time(), events=[],
                release_path=str(Path(release_path).absolute()), release_sha256=r.digest(Path(release_path)/'release.json'),
                remote_root=release['remote_root'], config_sha256=r.identity(config),
                resources=release['resources'], policy_pin=release['policy_pin'], backend=release.get('backend'),
                control_test_requalification=release.get('control_test_requalification'),
                cost_replacement=release.get('cost_replacement'),accepted_control_test=release.get('accepted_control_test'))
            state['claims'][key] = claim
            if release['purpose'] == 'CONTROL_TEST': state['spent_tests'].append(key)
            r.write(self.path, state)
            return claim

    def transition(self, key, expected, target, **fields):
        allowed = {'RESERVED':{'STAGED','AMBIGUOUS'},'STAGED':{'SUBMISSION_INTENT','AMBIGUOUS'},
            'SUBMISSION_INTENT':{'HELD','AMBIGUOUS'},'HELD':{'AUTHORITY_INTENT','AMBIGUOUS'},
            'AUTHORITY_INTENT':{'AUTHORIZED','AMBIGUOUS'},'AUTHORIZED':{'RELEASE_INTENT','AMBIGUOUS'},
            'RELEASE_INTENT':{'SUBMITTED','AMBIGUOUS'},'SUBMITTED':{'ACTIVATION_INTENT','AMBIGUOUS',*FINAL},
            'ACTIVATION_INTENT':{'ACTIVATED','AMBIGUOUS'},'ACTIVATED':{'AMBIGUOUS',*FINAL},'AMBIGUOUS':FINAL}
        if target not in allowed.get(expected,set()): raise a.ActivationError('unreviewed lifecycle transition')
        protected={'task_key','task','scope_id','created','events','state','release_path','release_sha256','remote_root','config_sha256','resources','policy_pin','backend','control_test_requalification','cost_replacement','accepted_control_test'}
        if protected & fields.keys():raise a.ActivationError('immutable operational claim fields')
        with r.lock(CENTRAL/'activation_registry.lock'):
            state=r.read(self.path);claim=state['claims'][key]
            if claim['state']!=expected:raise a.ActivationError('lifecycle state changed')
            claim['events'].append(dict(from_state=expected,to_state=target,epoch=time.time()))
            claim.update(fields,state=target);r.write(self.path,state);return claim

    def update(self, key, **fields):
        if set(fields)-{'last_poll','startup_event_claimed','startup_failure_pin','ready_pin','scientific_reservation','legacy_cost_key','authority_sha256','authority_identity_sha256','activation_sha256'}:
            raise a.ActivationError('unreviewed journal annotation')
        with r.lock(CENTRAL/'activation_registry.lock'):
            state=r.read(self.path);claim=state['claims'][key]
            if 'startup_event_claimed' in fields and (fields['startup_event_claimed'] is not True or claim.get('startup_event_claimed')):
                raise a.ActivationError('startup observation cannot be reset/repeated')
            if 'startup_failure_pin' in fields and claim.get('startup_failure_pin') is not None:
                raise a.ActivationError('startup failure evidence cannot be replaced')
            if 'last_poll' in fields and fields['last_poll']<claim.get('last_poll',0):raise a.ActivationError('poll clock cannot move backward')
            claim.update(fields);r.write(self.path,state)
            return state['claims'][key]

    def poll(self,key):
        with r.lock(CENTRAL/'activation_registry.lock'):
            state=r.read(self.path);claim=state['claims'][key];now=time.time()
            if claim['state'] not in {'SUBMITTED','ACTIVATED','AMBIGUOUS'} or not claim.get('job_id'):
                raise a.ActivationError('submitted known job required')
            if now-claim.get('last_poll',0)<300:raise a.ActivationError('minimum300second ordinary poll interval')
            claim['last_poll']=now;r.write(self.path,state);return claim


def pack_proofs(destination, pins, prefix='proofs'):
    """Copy explicit validator-read proof roles without rewriting original bytes.

    A proof's internal provenance is opaque here. Historical assessments include
    thousands of runtime, array and retired-path pins; those are not new launch
    inputs. Callers explicitly list every JSON proof read by worker validators.
    """
    manifest={}
    def add(value):
        if isinstance(value,dict) and set(value)=={'path','sha256'}:
            path=r.no_links(value['path'])
            if {'.ssh','.git','.codex'} & set(path.parts) or path.name in {'id_rsa','id_ed25519','authorized_keys'}:
                raise a.ActivationError('credential/agent/Git path excluded from proof bundle')
            if r.digest(path)!=value['sha256']:raise a.ActivationError('changed input proof')
            if path.suffix!='.json' or path.stat().st_size>16*1024**2:
                raise a.ActivationError('explicit bounded JSON proof role required')
            logical=str(path)
            if logical in manifest:return
            relative=Path(prefix)/value['sha256']/path.name;target=Path(destination)/relative
            target.parent.mkdir(parents=True,exist_ok=True)
            if not target.exists():shutil.copyfile(path,target)
            if r.digest(target)!=value['sha256']:raise a.ActivationError('staged proof differs')
            manifest[logical]=dict(relative_path=str(relative),sha256=value['sha256'],bytes=path.stat().st_size)
        elif isinstance(value,dict):
            for child in value.values():add(child)
        elif isinstance(value,list):
            for child in value:add(child)
    add(pins);return manifest


def seal_release(destination, *, purpose, study, task_key, scientific_exclusion_key,
                 plan_sha256, resources, runtime_python, node, policy_pin, proof_manifest,
                 backend=None, scope_id=None, environment_bundle=None, request_sha256=None):
    owner();root=ctl.safe_tree(destination)
    if purpose not in a.PURPOSES or (root/'release.json').exists():raise a.ActivationError('new supported release required')
    if r.digest(root/'plan.json')!=plan_sha256:raise a.ActivationError('plan bytes differ')
    policy_document(policy_pin)
    source=a.executed_sources(purpose);code=root/'code/pricefm_hb';code.mkdir(parents=True,exist_ok=True)
    for name,sha in source.items():
        source_path=Path(__file__).with_name(name);target=code/name
        if target.exists() and r.digest(target)!=sha:raise a.ActivationError('staged code differs')
        if not target.exists():shutil.copyfile(source_path,target)
    release_id='r157-'+uuid.uuid4().hex
    # Physical remote root is supplied in a reviewed preparation descriptor.
    preparation=r.read(root/'preparation.json')
    remote_root=preparation['remote_base']+'/'+release_id
    if not re.fullmatch(r'/mnt/beegfs/home/jaguir26/[A-Za-z0-9_/-]+',remote_root):
        raise a.ActivationError('verified physical HB path required')
    cap=resources['wall_seconds'];cpu=resources['cpu_seconds']
    if resources.get('cpus')!=1 or type(cap)is not int or not 1<=cap<=a.PURPOSES[purpose] or not 0<cpu<=cap:
        raise a.ActivationError('invalid complete allocated resource cap')
    (root/'job.sh').write_text(job_script(resources))
    files={str(p.relative_to(root)):dict(sha256=r.digest(p),bytes=p.stat().st_size) for p in sorted(root.rglob('*')) if p.is_file()}
    m=dict(schema=RELEASE_SCHEMA,release_id=release_id,purpose=purpose,study=study,task_key=task_key,
        scientific_exclusion_key=scientific_exclusion_key,scope_id=scope_id or preparation['scope_id'],
        plan_sha256=plan_sha256,resources=resources,runtime_python=runtime_python,node=node,
        policy_pin=policy_pin,proof_manifest=proof_manifest,source_hashes=source,remote_root=remote_root,
        environment_bundle=environment_bundle or preparation['environment_bundle'],backend=backend,
        request_sha256=request_sha256 or r.digest(root/'launch-request.json'),
        control_cpu_scope=r.read(root/'launch-request.json').get('control_cpu_scope'),
        control_test_requalification=r.read(root/'launch-request.json').get('control_test_requalification'),files=files)
    request=r.read(root/'launch-request.json')
    m['cost_replacement']=request.get('cost_replacement')
    m['accepted_control_test']=request.get('accepted_control_test')
    if m['cost_replacement'] is not None:m['protocol_version']=REPLACEMENT_PROTOCOL
    write_new(root/'release.json',m);return m


def verify_release(root):
    root=ctl.safe_tree(root);m=r.read(root/'release.json')
    if m.get('schema')!=RELEASE_SCHEMA or m.get('purpose') not in a.PURPOSES or not re.fullmatch(r'r157-[a-f0-9]{32}',m.get('release_id','')):
        raise a.ActivationError('invalid immutable release')
    observed={str(p.relative_to(root)) for p in root.rglob('*') if p.is_file() and p.relative_to(root).parts[0] not in {'outputs','logs','authorization'}}
    if observed != set(m['files'])|{'release.json'}:raise a.ActivationError('release membership changed')
    for rel,v in m['files'].items():
        path=Path(rel)
        if path.is_absolute() or '..' in path.parts or r.digest(root/path)!=v['sha256'] or (root/path).stat().st_size!=v['bytes']:
            raise a.ActivationError('release member changed: '+rel)
    if m['source_hashes']!=a.executed_sources(m['purpose']) or r.digest(root/'plan.json')!=m['plan_sha256']:
        raise a.ActivationError('release actual source/plan differs')
    if r.digest(root/'launch-request.json') != m.get('request_sha256'):
        raise a.ActivationError('original launch request differs')
    return m


def _bound_claim(key,config_path):
    ledger=Ledger();claim=ledger.snapshot()['claims'][key];config=ctl.config(config_path)
    if r.identity(config)!=claim['config_sha256'] or r.digest(Path(claim['release_path'])/'release.json')!=claim['release_sha256']:
        raise a.ActivationError('canonical claim source/config changed')
    release=r.read(Path(claim['release_path'])/'release.json')
    bind_control(config,release)
    verify_release(claim['release_path'])
    return ledger,claim,release,config


def control_scope(release,*,now=None):
    from .operation_budget import OperationBudget
    spec=release.get('control_cpu_scope')
    if not isinstance(spec,dict) or set(spec)!={'path','authorization_pin','scope_id'}:
        raise a.ActivationError('prospectively admitted control CPU scope required before I/O')
    path=r.no_links(spec['path'])
    if path.parent!=CENTRAL or path.name!=spec['scope_id']+'.control_cpu.json':
        raise a.ActivationError('canonical control budget path differs')
    budget=OperationBudget(path);state=budget.snapshot(now)
    if state['scope_id']!=spec['scope_id'] or state['authorization']!=spec['authorization_pin']:
        raise a.ActivationError('control scope authorization differs')
    return budget,state


def bind_control(config,release,*,reserve=False):
    budget,state=control_scope(release);key=release['task_key']
    if reserve:
        if state['kind'] in {'INITIAL','INITIAL_SUPPLEMENT'}:
            budget.reserve_claim(key,purpose=release['purpose'],study=release['study'],scope_id=release['scope_id'])
        else:
            backend=release.get('backend') or {}
            price=a.read_pin(backend.get('operation_price_pin'))
            budget.reserve_claim(key,reservation=price['reservation_CPU'],limits=price['operation_limits'],
                parent_CPU_cap=price['parent_CPU_cap'],price_pin=backend['operation_price_pin'])
    elif key not in state['claims']:
        raise a.ActivationError('control claim was not charged before I/O')
    marker=(str(budget.path),key)
    if marker not in PARENT_SLICES:
        fields=(Path('/proc/self/stat').read_text().rsplit(')',1)[1]).split()
        identity=dict(pid=os.getpid(),start_ticks=int(fields[19]),
            boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip())
        budget.reserve_parent_slice(key,identity,CPU_cap=8)
        old=resource.getrlimit(resource.RLIMIT_CPU)[1]
        limit=8 if old==resource.RLIM_INFINITY else min(8,old)
        resource.setrlimit(resource.RLIMIT_CPU,(limit,limit))
        PARENT_SLICES[marker]=(budget,identity)
        def finish():
            if marker not in PARENT_SLICES:return
            value=resource.getrusage(resource.RUSAGE_SELF);children=resource.getrusage(resource.RUSAGE_CHILDREN)
            budget.close_parent_slice(key,identity,value.ru_utime+value.ru_stime+children.ru_utime+children.ru_stime)
            PARENT_SLICES.pop(marker,None)
        PARENT_SLICES[marker]=(budget,identity,finish)
        atexit.register(finish)
    config['_r157_control_budget']=budget;config['_r157_task_key']=key
    return budget


def finish_parent_contexts():
    for _,_,finish in list(PARENT_SLICES.values()):finish()


def remote(config,argv,timeout=30):
    from . import metered_io
    return metered_io.remote(config,argv,config['_r157_control_budget'],config['_r157_task_key'],timeout=timeout)


def transfer(config,source,target,*,link_dest=None,pull=False):
    from . import metered_io
    if pull:source=config['user']+'@'+config['host']+':'+str(source)
    return metered_io.transfer(config,source,target,config['_r157_control_budget'],config['_r157_task_key'],
        link_dest=link_dest)


def cancel_held(key,config_path):
    ledger,claim,release,config=_bound_claim(key,config_path)
    if claim['state'] not in {'HELD','AUTHORITY_INTENT','AUTHORIZED','SUBMITTED'}:
        raise a.ActivationError('one known unactivated job required')
    info=remote(config,['scontrol','show','job',claim['job_id'],'-o'])
    fields=dict(re.findall(r'(\w+)=([^\s]+)',info))
    if fields.get('JobId')!=claim['job_id'] or fields.get('JobState')!='PENDING':
        raise a.ActivationError('cancellation requires server-confirmed pending job; running science untouched')
    ledger.transition(key,claim['state'],'AMBIGUOUS',diagnostic='explicit owned pending cancellation; terminal accounting still required')
    if claim.get('legacy_cost_key'):
        from . import cost_control
        old=cost_control.Ledger();v=old.snapshot()['claims'][claim['legacy_cost_key']]
        if v['state']!='AMBIGUOUS':old.transition(v['task_key'],v['state'],'AMBIGUOUS',diagnostic='explicit known pending cancellation')
    remote(config,['scancel',claim['job_id']])
    return ledger.snapshot()['claims'][key]


def _cost_transition(key,expected,target,**fields):
    claim=Ledger().snapshot()['claims'][key]
    if not claim.get('legacy_cost_key'):return
    from . import cost_control
    cost_control.Ledger().transition(claim['legacy_cost_key'],expected,target,**fields)


def submit_component(release_path,config_path):
    """Generic explicit held submission; reserve science before any SSH mutation."""
    owner();release=verify_release(release_path);config=ctl.config(config_path)
    request=r.read(Path(release_path)/'launch-request.json')
    validate_request(request,release=release)
    ledger=Ledger();claim=ledger.reserve(release,release_path,config);key=claim['task_key']
    try:
        bind_control(config,release,reserve=True)
        if remote(config,['squeue','-h','-u',config['user'],'-o','%i']).strip() and release['purpose'] in {'CONTROL_TEST','COST_ONLY'}:
            raise a.ActivationError('own HB queue not empty; control attempt retained without submission')
        if release['purpose']=='COST_ONLY':
            from . import cost_control
            cost=cost_control.Ledger().reserve(r.read(Path(release_path)/'plan.json'),release['plan_sha256'],claim['release_sha256'],claim['config_sha256'],Path(release_path).absolute(),release['remote_root'],replacement_pin=release.get('cost_replacement'))
            ledger.update(key,legacy_cost_key=cost['task_key'])
        elif release['purpose'] in {'CACHED_NORMAL_COMPONENT','PREFIX_ASSESSMENT'}:
            from . import prefix_control
            scientific=prefix_control.lifecycle_reserve(release,release_path,ctl.config(config_path))
            ledger.update(key,scientific_reservation=scientific)
        remote(config,['mkdir','-p',config['remote_root']]);remote(config,['mkdir',release['remote_root']])
        backend=release.get('backend') or {};link_dest=backend.get('rsync_link_dest')
        if link_dest:
            from . import prefix_control
            # Validate against the original pure site config, before internal I/O context was added.
            cached=a.read_pin(backend['shared_cache_receipt'])
            if cached['plan']['sha256']!=release['plan_sha256']:
                raise a.ActivationError('cache was prepared for another scientific plan')
            cache=prefix_control.validate_cache_receipt(backend['shared_cache_receipt']['path'],
                cached['plan']['path'],ctl.config(config_path))
            if pin(backend['shared_cache_receipt']['path'])!=backend['shared_cache_receipt'] or cache['remote_root']!=link_dest:
                raise a.ActivationError('cache linkage differs from verified canonical receipt')
        transfer(config,release_path,release['remote_root'],link_dest=link_dest)
        if remote(config,['sha256sum',release['remote_root']+'/release.json']).split()[0]!=claim['release_sha256']:
            raise a.ActivationError('staged release hash differs')
        remote(config,['mkdir',release['remote_root']+'/outputs',release['remote_root']+'/logs'])
        ledger.transition(key,'RESERVED','STAGED')
        _cost_transition(key,'RESERVED','STAGED')
    except Exception as exc:
        ledger.transition(key,'RESERVED','AMBIGUOUS',diagnostic='staging/scientific reservation interrupted: '+str(exc));raise
    seconds=release['resources']['wall_seconds'];wall='%02d:%02d:%02d'%(seconds//3600,seconds%3600//60,seconds%60)
    argv=['sbatch','--parsable','--hold','--export=NONE','--propagate=NONE','--nodes=1','--ntasks=1','--cpus-per-task=1','--no-requeue',
        '--nodelist='+release['node'],'--mem='+str(release['resources']['memory_MiB'])+'M','--time='+wall,
        '--account=128x24','--partition=128x24','--qos=normal','--job-name='+release['release_id'],
        '--chdir='+release['remote_root'],'--output='+release['remote_root']+'/logs/%j.out',
        '--error='+release['remote_root']+'/logs/%j.err',release['remote_root']+'/job.sh',release['remote_root'],claim['release_sha256']]
    ledger.transition(key,'STAGED','SUBMISSION_INTENT',submission_argv=argv)
    _cost_transition(key,'STAGED','SUBMISSION_INTENT',submission_argv=argv)
    try:
        answer=remote(config,argv).strip()
        if not re.fullmatch(r'[1-9][0-9]*(?:;[A-Za-z0-9_.-]+)?',answer):raise a.ActivationError('ambiguous held submission reply')
    except Exception as exc:
        ledger.transition(key,'SUBMISSION_INTENT','AMBIGUOUS',diagnostic='submission may have reached Slurm: '+str(exc));raise
    result=ledger.transition(key,'SUBMISSION_INTENT','HELD',job_id=answer.split(';',1)[0])
    _cost_transition(key,'SUBMISSION_INTENT','HELD',job_id=result['job_id'])
    return result


def validate_request(request,release=None):
    """Actual preclaim checks; a preparation record cannot issue authority."""
    if (request.get('schema')!=a.REQUEST_SCHEMA or request.get('automatic_retry') is not False
            or request.get('purpose') not in a.PURPOSES
            or request.get('study') not in {'TEST','FI','DK2'}
            or not isinstance(request.get('scientific_exclusion_key'),str)):
        raise a.ActivationError('fresh R157 purpose-specific launch request required')
    packet=policy_document(request['policy_pin'])
    from . import handoff
    closed=a.read_pin(request['handoff_receipt'])
    handoff.validate_handoff_receipt(closed,packet,check_live=True)
    if not a.fresh(closed):raise a.ActivationError('handoff receipt stale')
    qualified=a.validate_qualification(request,reader=a.read_pin)
    hosts=a.read_pin(request['all_hosts_observation']);site=a.read_pin(request['site_admission'])
    if (hosts.get('status')!='NO_OVERLAP' or hosts.get('overlapping_scientific_claims')!=[] or not a.fresh(hosts)
            or hosts.get('controller')!=a.OWNER
            or set(hosts.get('hosts',[]))!={a.OWNER,'jerez.be.ucsc.edu','hb.ucsc.edu'}
            or hosts.get('scientific_exclusion_key')!=request['scientific_exclusion_key']):
        raise a.ActivationError('fresh physical cross-host no-overlap proof required')
    if (site.get('status')!='ADMITTED_COST_ONLY_RESOURCES' or not a.fresh(site)
            or site.get('available_cpus',0)<1 or site.get('memory_mib',0)>site.get('available_memory_mib',-1)
            or site.get('memory_mib',0)<site.get('minimum_required_memory_mib',1)
            or not re.fullmatch(r'node-[0-9]+',site.get('node',''))
            or site.get('account')!='128x24' or site.get('partition')!='128x24' or site.get('qos')!='normal'):
        raise a.ActivationError('fresh measured eligible node/account/memory proof required')
    if release:
        if (request.get('cost_replacement')!=release.get('cost_replacement')
                or request.get('accepted_control_test')!=release.get('accepted_control_test')):
            raise a.ActivationError('immutable cost replacement/qualification pointer differs')
        if any(request.get(field)!=release[field] for field in ('purpose','study','scientific_exclusion_key')):
            raise a.ActivationError('request task purpose/study/scientific identity differs')
        if request.get('execution_plan_sha256',request.get('plan',{}).get('sha256'))!=release['plan_sha256']:
            raise a.ActivationError('request execution plan identity differs')
        if (release['node']!=site['node'] or release['resources']['memory_MiB']!=site['memory_mib']
                or release['runtime_python']!=qualified['runtime']['executable']
                or release['policy_pin']!=request['policy_pin']):
            raise a.ActivationError('immutable release resources/runtime/policy differ')
        if (site.get('purpose')!=release['purpose'] or site.get('study')!=release['study']
                or site.get('execution_plan_sha256')!=release['plan_sha256']):
            raise a.ActivationError('site admission is for a different task')
        a.validate_policy_sources(packet,release['source_hashes'])
        end=min(site['calendar_expires_epoch'],(release.get('backend') or {}).get('calendar_expires_epoch',float('inf')))
        if release.get('cost_replacement') is not None:
            from . import cost_control
            replacement=a.read_pin(release['cost_replacement'])
            cost_control.validate_replacement_document_binding(replacement,release['plan_sha256'],release['study'],
                release['scope_id'],release['source_hashes'])
            if (replacement['new_operational_task_key']!=release['task_key']
                    or replacement['new_control_cpu_scope']!=release['control_cpu_scope']
                    or replacement['resource_policy']!=release['policy_pin'] or replacement['resources']!=release['resources']):
                raise a.ActivationError('replacement request/release grant binding differs')
            end=min(end,replacement['expires_epoch'])
        if end-time.time()<release['resources']['wall_seconds']+61:
            raise a.ActivationError('whole allocated work and cleanup no longer fit calendar')
    return dict(qualified,site=site,hosts=hosts,policy=packet,handoff=closed)


def prepare(plan_path,request_path,config_path,destination,purpose='COST_ONLY',fixture=None):
    owner()
    if purpose not in {'COST_ONLY','CONTROL_TEST'}:raise a.ActivationError('prefix preparation belongs to its reviewed scientific controller')
    from . import cost_control,benchmark_plan
    plan=cost_control.load_plan(plan_path);request=r.read(request_path);gate=validate_request(request)
    if request.get('cost_replacement') is not None:
        if purpose!='COST_ONLY':raise a.ActivationError('replacement permit is cost-only')
        cost_control.validate_replacement(request['cost_replacement'],plan,r.digest(plan_path),phase='preclaim')
    if purpose!=request['purpose']:
        raise a.ActivationError('preparation purpose differs from reviewed request')
    if request.get('execution_plan_sha256')!=r.digest(plan_path):
        raise a.ActivationError('preparation plan differs from reviewed request')
    config=ctl.config(config_path);destination=r.no_links(destination)
    if destination.exists():raise FileExistsError('fresh release required')
    destination.mkdir(parents=True)
    shutil.copyfile(plan_path,destination/'plan.json');(destination/'plan.sha256').write_text(r.digest(plan_path)+'\n')
    shutil.copyfile(request_path,destination/'launch-request.json')
    if purpose=='COST_ONLY':
        for logical,entry in plan['input_allowlist'].items():
            source=r.no_links(logical);relative=Path(entry['staged_relative_path'])
            if relative!=Path('files')/source.relative_to('/') or '..' in relative.parts:
                raise a.ActivationError('unsafe input membership')
            if {'.ssh','.git','.codex'}&set(source.parts) or r.digest(source)!=entry['sha256'] or source.stat().st_size!=entry['bytes']:
                raise a.ActivationError('changed or excluded input')
            target=destination/'stage'/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
            if r.digest(target)!=entry['sha256']:raise a.ActivationError('copied input differs')
        scope=plan['claim']['planned_attempt_id'];exclusion=plan['claim']['scientific_exclusion_key'];study=plan['study'];wall=1200
    else:
        from .fixture import load_fixture
        if not fixture:raise a.ActivationError('fixed original parity fixture required')
        fixture=r.no_links(fixture);fixed=load_fixture(fixture)
        if r.digest(fixture)!=request['accepted_parity_fixture_manifest_sha256']:
            raise a.ActivationError('TEST cannot choose a different fixture')
        shutil.copytree(fixture.parent,destination/'fixture');load_fixture(destination/'fixture'/fixture.name)
        scope='r157_control_placement_01';study='TEST';wall=120
        if request.get('control_test_requalification') is not None:
            q=a.read_pin(request['control_test_requalification'])
            scope=q.get('scope_id')
            prospective=dict(scope_id=scope,source_hashes=a.executed_sources('CONTROL_TEST'),
                control_cpu_scope=request.get('control_cpu_scope'))
            validate_control_test_requalification(q,prospective,Ledger().snapshot(),packet=gate.get('policy'))
        exclusion='R157_CONTROL_TEST|'+r.digest(fixture)
    write_new(destination/'preparation.json',dict(remote_base=config['remote_root'],scope_id=scope,
        environment_bundle=request['environment_bundle'],purpose=purpose,fixture_sha256=r.digest(fixture) if fixture else None))
    roots={k:request[k] for k in ('runtime_result','runtime_qualification_seal','runtime_accounting','parity_result','parity_seal','parity_runtime_result',
        'parity_qualification_seal','parity_accounting','policy_pin','handoff_receipt','all_hosts_observation','site_admission','adapter_review',
        'control_test_requalification','cost_replacement') if k in request}
    manifest=pack_proofs(destination,roots)
    task_key=r.identity(dict(purpose=purpose,scope_id=scope,study=study,scientific_exclusion_key=exclusion,plan_sha256=r.digest(plan_path)))
    return seal_release(destination,purpose=purpose,study=study,task_key=task_key,
        scientific_exclusion_key=exclusion,plan_sha256=r.digest(plan_path),resources=dict(cpus=1,memory_MiB=gate['site']['memory_mib'],wall_seconds=wall,cpu_seconds=wall),
        runtime_python=request['runtime_python'],node=gate['site']['node'],policy_pin=request['policy_pin'],proof_manifest=manifest,scope_id=scope)


def issue_authority(key,config_path):
    ledger,claim,release,config=_bound_claim(key,config_path)
    if claim['state']!='HELD':raise a.ActivationError('one known held job required')
    request=r.read(Path(claim['release_path'])/'launch-request.json');gate=validate_request(request,release)
    now=time.time();backend=release.get('backend') or {}
    end=min(gate['site']['calendar_expires_epoch'],backend.get('calendar_expires_epoch',float('inf')))
    if release.get('cost_replacement') is not None:
        end=min(end,a.read_pin(release['cost_replacement'])['expires_epoch'])
    queue=min(1800,int(end-now-release['resources']['wall_seconds']-60),int(backend.get('dispatch_expires_epoch',now+1800)-now))
    if release['purpose']=='COST_ONLY':queue=min(180,queue)
    if queue<1:raise a.ActivationError('whole allocated work and finite queue do not fit')
    authority=dict(schema=a.AUTHORITY_SCHEMA,status='ADMITTED_QUEUED_EXECUTION',issuer=a.OWNER,controller=a.OWNER,
        purpose=release['purpose'],study=release['study'],scope_id=release['scope_id'],task_key=key,
        plan_sha256=release['plan_sha256'],scientific_exclusion_key=release['scientific_exclusion_key'],
        slurm_job_id=claim['job_id'],node=release['node'],resources=release['resources'],issued_epoch=now,
        calendar_expires_epoch=end,max_queue_seconds=queue,release_sha256=claim['release_sha256'],
        executed_sources=release['source_hashes'],reference_numerical_environment=REFERENCE_NUMERICAL_ENV,
        proof_manifest=release['proof_manifest'],policy_pin=release['policy_pin'],automatic_retry=False,new_model_fits=0,
        official_origins=0,promotion=False,full_prefix_admitted=release['purpose'] in {'CACHED_NORMAL_COMPONENT','PREFIX_ASSESSMENT'})
    if release['purpose']=='COST_ONLY':
        authority['role']=release['study']+'_COST_ONLY_BENCHMARK'
        if release.get('cost_replacement') is not None:
            authority.update(cost_replacement=release['cost_replacement'],protocol_version='r161_cost_replacement_v1',
                control_cpu_scope=release['control_cpu_scope'])
    for field in ('runtime_result','runtime_qualification_seal','runtime_accounting','parity_result','parity_seal','parity_runtime_result','parity_qualification_seal','parity_accounting','adapter_review','accepted_parity_fixture_manifest_sha256'):
        if field in request:authority[field]=request[field]
    if release['purpose'] in {'CACHED_NORMAL_COMPONENT','PREFIX_ASSESSMENT'}:
        from . import prefix_control
        authority.update(prefix_control.lifecycle_authority_fields(release))
        authority.update(backend.get('authority_fields',{}))
        if release['purpose']=='CACHED_NORMAL_COMPONENT':authority['schema']='r157_hb_cached_normal_component_authority_v1'
    a.validate_authority(authority,release['purpose'],release['plan_sha256'],release['source_hashes'])
    ledger.transition(key,'HELD','AUTHORITY_INTENT')
    _cost_transition(key,'HELD','AUTHORITY_INTENT')
    directory=Path(claim['release_path'])/'authorization'
    authority_pin=write_new(directory/'authority.json',authority)
    packet=dict(schema=SCHEMA,task_key=key,release_sha256=claim['release_sha256'],authority_sha256=authority_pin['sha256'],authority_identity_sha256=r.identity(authority))
    packet_pin=write_new(directory/'packet.json',packet)
    try:
        transfer(config,directory,claim['remote_root']+'/authorization')
        if remote(config,['sha256sum',claim['remote_root']+'/authorization/packet.json']).split()[0]!=packet_pin['sha256']:
            raise a.ActivationError('remote immutable authority packet differs')
    except Exception as exc:
        ledger.transition(key,'AUTHORITY_INTENT','AMBIGUOUS',diagnostic='authority transfer interrupted: '+str(exc));raise
    result=ledger.transition(key,'AUTHORITY_INTENT','AUTHORIZED',authority_sha256=authority_pin['sha256'],authority_identity_sha256=r.identity(authority))
    _cost_transition(key,'AUTHORITY_INTENT','AUTHORIZED',authority_sha256=authority_pin['sha256'])
    return result


def release_job(key,config_path):
    ledger,claim,release,config=_bound_claim(key,config_path)
    if claim['state']!='AUTHORIZED':raise a.ActivationError('known authorized held job required')
    directory=Path(claim['release_path'])/'authorization';authority=r.read(directory/'authority.json')
    if r.digest(directory/'authority.json')!=claim['authority_sha256']:
        raise a.ActivationError('original authority changed')
    if release['purpose']=='COST_ONLY':
        a.validate_authority(authority,'COST_ONLY',release['plan_sha256'],release['source_hashes'])
        if (authority.get('task_key')!=key or authority.get('slurm_job_id')!=claim['job_id']
                or authority.get('release_sha256')!=claim['release_sha256']
                or authority.get('scope_id')!=release['scope_id']
                or time.time()>=authority['issued_epoch']+authority['max_queue_seconds']):
            raise a.ActivationError('original cost authority/job/queue must remain valid before release')
    if authority['calendar_expires_epoch']-time.time()<release['resources']['wall_seconds']+60:
        raise a.ActivationError('remaining original calendar insufficient')
    ledger.transition(key,'AUTHORIZED','RELEASE_INTENT')
    _cost_transition(key,'AUTHORIZED','RELEASE_INTENT')
    try:remote(config,['scontrol','release',claim['job_id']])
    except Exception as exc:
        ledger.transition(key,'RELEASE_INTENT','AMBIGUOUS',diagnostic='release may have reached scheduler: '+str(exc));raise
    result=ledger.transition(key,'RELEASE_INTENT','SUBMITTED',released_epoch=time.time())
    _cost_transition(key,'RELEASE_INTENT','SUBMITTED')
    return result


def watch_ready(key,config_path,destination):
    """One finite READY-or-failure stream, no repeated scheduler queries.

    BeeGFS updates originate on a different kernel, so Linux inotify cannot be
    assumed to notify the login host. A declared bounded one-second stat of one
    READY path and worker-seal path provide the stream, with the same10CPU cap
    and original queue end. A failed seal is never interpreted as READY.
    """
    ledger,claim,release,config=_bound_claim(key,config_path)
    if claim['state']!='SUBMITTED' or claim.get('startup_event_claimed'):
        raise a.ActivationError('startup subscription is one-use')
    authority=r.read(Path(claim['release_path'])/'authorization/authority.json')
    grace=COST_READY_OBSERVATION_GRACE if release['purpose']=='COST_ONLY' else 0
    end=min(authority['issued_epoch']+authority['max_queue_seconds']+grace,authority['calendar_expires_epoch'])
    if end<=time.time():raise a.ActivationError('original bounded startup observation window exhausted')
    ledger.update(key,startup_event_claimed=True)
    script='''import json,os,pathlib,resource,signal,time
resource.setrlimit(resource.RLIMIT_CPU,(10,10))
path=pathlib.Path(__PATH__);failure=pathlib.Path(__FAILURE__);deadline=__END__
signal.alarm(max(1,int(deadline-time.time())+2))
while time.time()<deadline:
 if failure.is_file():
  if failure.is_symlink() or failure.stat().st_size>1048576:raise ValueError('invalid worker seal')
  print(json.dumps(dict(event='FAILED',evidence=json.loads(failure.read_text()))),flush=True);break
 if path.is_file():
  if path.is_symlink() or path.stat().st_size>1048576:raise ValueError('invalid READY file')
  print(json.dumps(dict(event='READY',evidence=json.loads(path.read_text()))),flush=True);break
 time.sleep(min(1,max(.01,deadline-time.time())))
else:raise TimeoutError('finite startup subscription expired')
'''.replace('__PATH__',repr(claim['remote_root']+'/outputs/ready.json')).replace(
        '__FAILURE__',repr(claim['remote_root']+'/outputs/worker_evidence.json')).replace('__END__',repr(end))
    from . import metered_io
    observed=metered_io.watch(config,script,config['_r157_control_budget'],key,timeout=max(1,end-time.time()+5))
    event=json.loads(observed)
    if event.get('event')=='FAILED':
        failure=event.get('evidence',{})
        if (failure.get('schema')!=SCHEMA or failure.get('task_key')!=key
                or failure.get('job_id')!=claim['job_id'] or failure.get('release_sha256')!=claim['release_sha256']
                or failure.get('source_hashes')!=release['source_hashes']
                or failure.get('authority_sha256')!=claim['authority_sha256']
                or failure.get('application_passed') is not False or not failure.get('error')):
            raise a.ActivationError('observed failed worker identity/source differs')
        failure_pin=write_new(Path(destination).with_name('worker-failure-event.json'),event)
        ledger.update(key,startup_failure_pin=failure_pin)
        raise a.ActivationError('exact worker failed before activation; retained claim requires terminal collection')
    if event.get('event')!='READY':raise a.ActivationError('unrecognized startup stream event')
    ready=event.get('evidence',{})
    if ready.get('job_id')!=claim['job_id'] or ready.get('release_sha256')!=claim['release_sha256']:
        raise a.ActivationError('observed READY identity differs')
    ready_pin=write_new(destination,ready);ledger.update(key,ready_pin=ready_pin)
    return ready


def activate(key,config_path,request_path):
    ledger,claim,release,config=_bound_claim(key,config_path)
    if claim['state']!='SUBMITTED' or not claim.get('ready_pin'):
        raise a.ActivationError('one observed READY required')
    ready=a.read_pin(claim['ready_pin']);request=r.read(request_path);gate=validate_request(request,release)
    now=time.time();authority=r.read(Path(claim['release_path'])/'authorization/authority.json')
    if release['purpose']=='COST_ONLY':
        if (r.digest(Path(claim['release_path'])/'authorization/authority.json')!=claim['authority_sha256']
                or r.identity(authority)!=claim['authority_identity_sha256']):
            raise a.ActivationError('immutable COST authority changed before activation')
        for role in ('handoff','hosts','site'):
            evidence=gate.get(role,{})
            if (not isinstance(evidence,dict) or not a.fresh(evidence,now)
                    or evidence['observed_epoch']<authority['issued_epoch']):
                raise a.ActivationError('COST activation requires the fresh post-authority observation')
    if (ready.get('schema')!=a.READY_SCHEMA or ready.get('authority_sha256')!=claim['authority_sha256']
            or ready.get('authority_identity_sha256')!=claim['authority_identity_sha256']
            or ready.get('node')!=release['node'] or ready.get('plan_sha256')!=release['plan_sha256']
            or ready.get('job_id')!=claim['job_id'] or ready.get('release_sha256')!=claim['release_sha256']
            or ready.get('allocation',{}).get('job_id')!=claim['job_id']
            or ready.get('allocation',{}).get('node')!=release['node']
            or not 0<=now-ready['observed_epoch']<=30
            or gate['site']['node']!=release['node']):
        raise a.ActivationError('fresh exact READY/resource activation required')
    start=ready['allocation_start_epoch'];end=min(start+release['resources']['wall_seconds'],authority['calendar_expires_epoch'])
    if start-authority['issued_epoch']>authority['max_queue_seconds'] or now>=end-5:
        raise a.ActivationError('queued/allocated original ceiling exhausted')
    directory=Path(claim['release_path'])/'authorization/activation'
    roots={k:request[k] for k in ('handoff_receipt','all_hosts_observation','site_admission')}
    # READY's logical path is the actual job-side original file. Preserve its
    # canonical bytes; remote worker wrote it with the same canonical writer.
    ready_path=directory/'ready-original.json';write_new(ready_path,ready)
    remote_ready=dict(path=claim['remote_root']+'/outputs/ready.json',sha256=r.digest(ready_path))
    proof_manifest=pack_proofs(directory,roots,prefix='proofs')
    proof_manifest={logical:dict(v,relative_path='authorization/activation/'+v['relative_path']) for logical,v in proof_manifest.items()}
    proof_manifest[remote_ready['path']]=dict(relative_path='outputs/ready.json',sha256=remote_ready['sha256'],bytes=ready_path.stat().st_size)
    packet=dict(schema=a.ACTIVATION_SCHEMA,status='ACTIVATED_ONCE',controller=a.OWNER,job_id=claim['job_id'],
        node=release['node'],plan_sha256=release['plan_sha256'],authority_sha256=claim['authority_sha256'],
        authority_identity_sha256=claim['authority_identity_sha256'],release_sha256=claim['release_sha256'],ready=remote_ready,
        observed_epoch=now,started_epoch=start,expires_epoch=end,handoff_receipt=request['handoff_receipt'],
        all_hosts_observation=request['all_hosts_observation'],proof_manifest=proof_manifest)
    ledger.transition(key,'SUBMITTED','ACTIVATION_INTENT')
    packet_pin=write_new(directory/'packet.json',packet)
    try:
        transfer(config,directory,claim['remote_root']+'/authorization/activation')
        if remote(config,['sha256sum',claim['remote_root']+'/authorization/activation/packet.json']).split()[0]!=packet_pin['sha256']:
            raise a.ActivationError('remote activation packet differs')
    except Exception as exc:
        ledger.transition(key,'ACTIVATION_INTENT','AMBIGUOUS',diagnostic='activation may have reached worker: '+str(exc));raise
    return ledger.transition(key,'ACTIVATION_INTENT','ACTIVATED',activation_sha256=packet_pin['sha256'],allocation_start_epoch=start,expires_epoch=end)


def release_and_activate(key,config_path,operator_config,resource_plan,destination,owner_receipt_pin=None):
    """One parent slice owns release, READY, fresh observation and activation."""
    from . import admission
    current=Ledger().snapshot()['claims'][key]
    if current.get('task',{}).get('purpose')=='COST_ONLY':
        raise a.ActivationError('COST_ONLY uses authority-and-observe, release-job, then watch-and-activate; no combined cold observer path')
    ledger,claim,release,config=_bound_claim(key,config_path)
    destination=r.no_links(destination)
    if destination.exists():raise FileExistsError('fresh activation audit required')
    destination.mkdir(parents=True)
    release_job(key,config_path)
    watch_ready(key,config_path,destination/'ready.json')
    budget=config['_r157_control_budget'];token=budget.start_operation(key,'admission_refresh')
    start_self=resource.getrusage(resource.RUSAGE_SELF);start_child=resource.getrusage(resource.RUSAGE_CHILDREN)
    result=None
    try:
        claim=ledger.snapshot()['claims'][key]
        execution_pin=pin(Path(claim['release_path'])/'plan.json') if release['purpose'] in {'CACHED_NORMAL_COMPONENT','PREFIX_ASSESSMENT'} else None
        result=admission.refresh_request(resource_plan,operator_config,release['policy_pin'],destination/'fresh',
            self_claim=claim,purpose=release['purpose'],owner_receipt_pin=owner_receipt_pin,
            execution_plan_pin=execution_pin,execution_plan_sha256=release['plan_sha256'],
            scientific_exclusion_key=release['scientific_exclusion_key'])
    finally:
        value=resource.getrusage(resource.RUSAGE_SELF);child=resource.getrusage(resource.RUSAGE_CHILDREN)
        used=(value.ru_utime+value.ru_stime+child.ru_utime+child.ru_stime
              -start_self.ru_utime-start_self.ru_stime-start_child.ru_utime-start_child.ru_stime)
        remote_used=(result or {}).get('observer_budget',{}).get('remote_CPU_seconds')
        budget.finish_operation(key,token,local_CPU=used,remote_CPU=remote_used,
            outcome='COMPLETE' if result and result.get('request') else 'REFRESH_FAILED')
    if result.get('status')!='READY_FOR_PREPARE_ONLY_NOT_ADMITTED':
        raise a.ActivationError('fresh compute-ready observation blocked; attempt retained')
    return activate(key,config_path,result['request']['path'])


def _cost_proof_fresh(request,authority,release,*,now=None,startup_observation=False):
    """Keep the single post-authority proof inside the original queue/TTL."""
    now=time.time() if now is None else now
    a.validate_authority(authority,'COST_ONLY',release['plan_sha256'],release['source_hashes'],now)
    if (authority.get('scope_id')!=release['scope_id'] or authority.get('release_sha256') is None
            or not 0<authority['max_queue_seconds']<=180):
        raise a.ActivationError('exact original short-queue cost authority required')
    epochs=[]
    for name in ('handoff_receipt','all_hosts_observation','site_admission'):
        value=a.read_pin(request[name]);epoch=value.get('observed_epoch')
        if not a.fresh(value,now) or epoch<authority['issued_epoch']:
            raise a.ActivationError('one fresh post-authority held observation required')
        epochs.append(epoch)
    if type(startup_observation) is not bool:
        raise a.ActivationError('explicit bounded startup observation mode required')
    grace=COST_READY_OBSERVATION_GRACE if startup_observation else 0
    if (now>=authority['issued_epoch']+authority['max_queue_seconds']+grace
            or authority['issued_epoch']+authority['max_queue_seconds']-min(epochs)>=300):
        raise a.ActivationError('original queue no longer fits the existing proof freshness')
    validate_request(request,release)
    return min(epochs)


def authority_and_observe(key,config_path,operator_config,resource_plan,destination,owner_receipt_pin=None):
    """One8CPU parent: one authority bound/hash plus one charged held observer."""
    from . import admission,cost_control
    destination=r.no_links(destination)
    if destination.exists():raise FileExistsError('new authorized-observer audit required')
    current=Ledger().snapshot()['claims'][key]
    if current.get('task',{}).get('purpose')!='COST_ONLY' or current.get('state')!='HELD':
        raise a.ActivationError('one held cost-only job required')
    destination.mkdir(parents=True)
    try:
        authorized=issue_authority(key,config_path) # Sole full release hash before observer.
        release=r.read(Path(authorized['release_path'])/'release.json')
        if r.digest(Path(authorized['release_path'])/'release.json')!=authorized['release_sha256']:
            raise a.ActivationError('immutable authorized release metadata changed')
        legacy=cost_control.Ledger().snapshot()['claims'][authorized['legacy_cost_key']]
        admission.authorized_cost_pair(authorized,release,legacy)
        config=ctl.config(config_path);budget=bind_control(config,release) # Reuses PARENT_SLICES.
        token=budget.start_operation(key,'admission_refresh')
        start_self=resource.getrusage(resource.RUSAGE_SELF);start_child=resource.getrusage(resource.RUSAGE_CHILDREN);result=None
        try:
            result=admission.refresh_request(resource_plan,operator_config,release['policy_pin'],destination/'fresh',
                self_claim=authorized,purpose='COST_ONLY',owner_receipt_pin=owner_receipt_pin,
                execution_plan_sha256=release['plan_sha256'])
        finally:
            value=resource.getrusage(resource.RUSAGE_SELF);child=resource.getrusage(resource.RUSAGE_CHILDREN)
            used=value.ru_utime+value.ru_stime+child.ru_utime+child.ru_stime-start_self.ru_utime-start_self.ru_stime-start_child.ru_utime-start_child.ru_stime
            budget.finish_operation(key,token,local_CPU=used,
                remote_CPU=(result or {}).get('observer_budget',{}).get('remote_CPU_seconds'),
                outcome='AUTHORIZED_HELD_REFRESH_COMPLETE' if result and result.get('request') else 'AUTHORIZED_HELD_REFRESH_FAILED')
        if not result or result.get('status')!='READY_FOR_PREPARE_ONLY_NOT_ADMITTED':
            raise a.ActivationError('fresh authorized cost observer blocked; no second refresh')
        request=a.read_pin(result['request']);authority=r.read(Path(authorized['release_path'])/'authorization/authority.json')
        _cost_proof_fresh(request,authority,release)
        proof=dict(schema=SCHEMA,status='AUTHORIZED_WITH_ONE_FRESH_HELD_PROOF',task_key=key,
            job_id=authorized['job_id'],authority_sha256=authorized['authority_sha256'],request=result['request'],
            no_second_refresh=True,original_calendar_expires_epoch=authority['calendar_expires_epoch'])
        return write_new(destination/'authorized-fresh.json',proof)
    finally:finish_parent_contexts()


def watch_and_activate(key,config_path,request_path,destination):
    """One8CPU parent, two stock bounds/hashes, no observer or outer bound."""
    claim=Ledger().snapshot()['claims'][key]
    if claim.get('task',{}).get('purpose')!='COST_ONLY' or claim.get('state')!='SUBMITTED':
        raise a.ActivationError('one released COST_ONLY job required')
    root=Path(claim['release_path']);release=r.read(root/'release.json');authority=r.read(root/'authorization/authority.json')
    if r.digest(root/'release.json')!=claim['release_sha256'] or r.digest(root/'authorization/authority.json')!=claim['authority_sha256']:
        raise a.ActivationError('original cost metadata changed')
    _cost_proof_fresh(r.read(request_path),authority,release,startup_observation=True)
    destination=r.no_links(destination)
    if destination.exists():raise FileExistsError('new READY/activation audit required')
    destination.mkdir(parents=True)
    try:
        watch_ready(key,config_path,destination/'ready.json')
        return activate(key,config_path,request_path)
    finally:finish_parent_contexts()


def worker(root,expected_sha):
    """Stdlib srun bootstrap; qualified Python starts only after fresh activation."""
    root=r.no_links(root);outputs=root/'outputs';passed=False;error=None;allocation=None;release=None
    try:
        if r.digest(root/'release.json')!=expected_sha:raise a.ActivationError('bound release SHA differs')
        release=verify_release(root);allocation=require_compute()
        packet=r.read(root/'authorization/packet.json');authority=r.read(root/'authorization/authority.json')
        if (packet.get('release_sha256')!=expected_sha or packet.get('authority_sha256')!=r.digest(root/'authorization/authority.json')
                or authority.get('release_sha256')!=expected_sha or authority.get('slurm_job_id')!=allocation['job_id']
                or authority.get('node')!=allocation['node']):raise a.ActivationError('immutable job authority differs')
        a.validate_authority(authority,release['purpose'],release['plan_sha256'],release['source_hashes'])
        establish_compute_limits(release['resources'],authority,evidence_path=outputs/'allocation-process-limits.json')
        start=a.allocation_start(allocation)
        if start-authority['issued_epoch']>authority['max_queue_seconds']:raise a.ActivationError('queue ceiling exhausted')
        end=min(start+release['resources']['wall_seconds'],authority['calendar_expires_epoch'])
        ready=dict(schema=a.READY_SCHEMA,job_id=allocation['job_id'],node=allocation['node'],allocation=allocation,
            allocation_start_epoch=start,observed_epoch=time.time(),authority_sha256=packet['authority_sha256'],
            authority_identity_sha256=r.identity(authority),release_sha256=expected_sha,plan_sha256=release['plan_sha256'],nonce=uuid.uuid4().hex)
        write_new(outputs/'ready.json',ready)
        activation_path=root/'authorization/activation/packet.json'
        while time.time()<min(ready['observed_epoch']+30,end-5):
            if activation_path.is_file():break
            time.sleep(.1)
        else:raise a.ActivationError('bounded fresh activation not received')
        activation=r.read(activation_path);os.environ['PRICEFM_RELEASE_ROOT']=str(root)
        a.validate_worker(authority,activation,allocation,release['purpose'],release['plan_sha256'],release['source_hashes'])
        env=dict(os.environ,**THREAD_ENV,**REFERENCE_NUMERICAL_ENV,PYTHONPATH=str(root/'code'),
            PRICEFM_ACTIVATION_PATH=str(activation_path),PRICEFM_ACTIVATION_SHA256=r.digest(activation_path),
            PYTHONNOUSERSITE='1',PYTHONDONTWRITEBYTECODE='1')
        remaining=end-time.time()-3
        if remaining<=0:raise a.ActivationError('allocated cleanup reserve reached')
        subprocess.run([release['runtime_python'],'-B','-m','pricefm_hb.lifecycle','payload','--release',str(root),
            '--release-sha256',expected_sha],env=env,check=True,timeout=remaining)
        passed=True
    except BaseException as exc:
        error=dict(type=type(exc).__name__,message=str(exc))
        if outputs.is_dir() and not (outputs/'worker-failure.json').exists():write_new(outputs/'worker-failure.json',error)
    if not outputs.is_dir():raise RuntimeError('worker failed before output namespace')
    ctl.safe_tree(outputs)
    files={str(p.relative_to(outputs)):r.digest(p) for p in sorted(outputs.rglob('*')) if p.is_file()}
    write_new(outputs/'worker_evidence.json',dict(schema=SCHEMA,task_key=release['task_key'] if release else None,
        release_sha256=expected_sha,job_id=allocation['job_id'] if allocation else None,allocation=allocation,
        source_hashes=release['source_hashes'] if release else None,
        application_passed=passed,error=error,files=files,new_model_fits=0,official_origins=0,
        full_prefix_admitted=bool(release and release['purpose'] in {'CACHED_NORMAL_COMPONENT','PREFIX_ASSESSMENT'}),
        authority_sha256=r.digest(root/'authorization/authority.json') if (root/'authorization/authority.json').exists() else None,
        final_process_CPU_seconds=time.process_time()))
    if not passed:raise RuntimeError('finite worker failed; no retry')
    return dict(status='COMPLETE_PENDING_ACCOUNTING_AND_COLLECTION')


def payload(root,expected_sha):
    """Called by the qualified interpreter, after job and activation checks."""
    import signal
    from . import environment
    root=Path(root);release=verify_release(root)
    if r.digest(root/'release.json')!=expected_sha:raise a.ActivationError('payload release differs')
    authority=r.read(root/'authorization/authority.json');activation=r.read(root/'authorization/activation/packet.json')
    allocation=require_compute()
    gate=a.validate_worker(authority,activation,allocation,release['purpose'],release['plan_sha256'],release['source_hashes'])
    establish_compute_limits(release['resources'],authority,evidence_path=root/'outputs/payload-process-limits.json')
    remaining=gate['expires_epoch']-time.time()-2
    if remaining<=0:raise a.ActivationError('allocated deadline exhausted')
    def stop(*args):raise TimeoutError('allocated payload deadline')
    signal.signal(signal.SIGALRM,stop);signal.setitimer(signal.ITIMER_REAL,remaining)
    cap=max(1,int(release['resources']['cpu_seconds']-5));old=resource.getrlimit(resource.RLIMIT_CPU)[1]
    if old!=resource.RLIM_INFINITY:cap=min(cap,old)
    resource.setrlimit(resource.RLIMIT_CPU,(cap,cap));outputs=root/'outputs'
    if release['purpose']=='CONTROL_TEST':
        actual=environment.verify_runtime(release['environment_bundle'],outputs/'environment-runtime.json')
        if actual['native_library_sha256']!=gate['parity_runtime']['native_library_sha256']:raise a.ActivationError('actual native bytes differ')
        from .science import run_fixture
        if run_fixture(root/'fixture/manifest.json',outputs/'TEST/parity').get('accepted') is not True:raise a.ActivationError('fixed TEST parity failed')
    elif release['purpose']=='COST_ONLY':
        from . import benchmark
        plan=r.read(root/'plan.json');relative=Path('BENCHMARK_TEST')/release['study']/plan['canonical_preparation']['sha256'][:16]/release['scope_id']
        benchmark.run_benchmark(root/'plan.json',root/'authorization/authority.json',r.digest(root/'authorization/authority.json'),root/'stage',outputs/relative)
    elif release['purpose']=='CACHED_NORMAL_COMPONENT':
        from . import prefix
        prefix.run_component(root/'plan.json',root/'authorization/authority.json',root/'authorization/activation/packet.json',root/'stage',outputs/'PREFIX_TRAINING'/release['study']/release['backend']['component_name'])
    elif release['purpose']=='PREFIX_ASSESSMENT':
        from . import prefix
        prefix.run_assessment(root/'plan.json',root/'authorization/authority.json',root/'authorization/activation/packet.json',root/'stage',
            root/'assessment_snapshot.json',root/'components',outputs/'PREFIX_ASSESSMENT'/release['study'])
    else:raise a.ActivationError('unreviewed payload purpose')
    signal.setitimer(signal.ITIMER_REAL,0)
    return dict(status='PAYLOAD_COMPLETE',purpose=release['purpose'])


def parse_accounting(text,job_id,resources):
    rows=[line.split('|') for line in text.splitlines() if line.strip()]
    if any(len(row)!=10 for row in rows):raise a.ActivationError('ten accounting columns required')
    allowed={job_id,job_id+'.batch',job_id+'.extern',job_id+'.0'}
    if len({v[0] for v in rows})!=len(rows) or any(v[0] not in allowed for v in rows):
        raise a.ActivationError('unexpected/duplicate accounting identity')
    for row in rows:
        if (not re.fullmatch(r'[0-9]+:[0-9]+',row[2]) or not re.fullmatch(r'[0-9]+',row[3])
                or not re.fullmatch(r'[01]',row[4])):raise a.ActivationError('invalid accounting exit/elapsed/CPU')
        ctl.cpu_seconds(row[5])
    first8='\n'.join('|'.join(row[:8]) for row in rows)+'\n';primary=[row for row in rows if row[0]==job_id]
    if len(primary)!=1:raise a.ActivationError('one exact primary accounting row required')
    absent_time=('Unknown','None','N/A','')
    unallocated=(int(primary[0][3])==0 and ctl.cpu_seconds(primary[0][5])==0 and primary[0][8] in absent_time)
    if unallocated:
        if (primary[0][4]!='0' or {v[0] for v in rows}-{job_id,job_id+'.extern'}
                or any(v[3]!='0' or v[4]!='0' or ctl.cpu_seconds(v[5])!=0 or v[8] not in absent_time for v in rows)
                or any(v[0]!=job_id and v[1].split()[0] not in {'CANCELLED','COMPLETED','FAILED'} for v in rows)
                or primary[0][1].split()[0] not in {'PENDING','CANCELLED','FAILED','DEADLINE'}):
            raise a.ActivationError('unallocated job accounting is inconsistent')
    terminal_unstarted=unallocated and primary[0][1].split()[0] in {'CANCELLED','FAILED','DEADLINE'}
    parsed=(dict(complete=False,terminal=terminal_unstarted,rows=[v[:8] for v in rows],unstarted_cancelled=terminal_unstarted) if unallocated else
        ctl.accounting(first8,job_id,dict(cpus=1,memory_MiB=resources['memory_MiB'],wall_seconds=resources['wall_seconds'])))
    violations=[v[0] for v in rows if int(v[3])>resources['wall_seconds'] or ctl.cpu_seconds(v[5])>resources['cpu_seconds']]
    if violations:parsed['complete']=False
    parsed.update(sacct=first8,start_end_rows=rows,scope_violations=violations);return parsed


def status(key,config_path,receipt_path):
    ledger,claim,release,config=_bound_claim(key,config_path);ledger.poll(key)
    own=remote(config,['squeue','-h','-u',config['user'],'-o','%i|%T|%R'])
    queue='\n'.join(v for v in own.splitlines() if v.split('|',1)[0]==claim['job_id'])
    raw=remote(config,['env','TZ=UTC','sacct','-nP','--units=K','-j',claim['job_id'],
        '--format=JobID,State%30,ExitCode,ElapsedRaw,AllocCPUS,TotalCPU,MaxRSS,NodeList,Start,End'])
    parsed=parse_accounting(raw,claim['job_id'],release['resources'])
    result=dict(schema=SCHEMA,task_key=key,job_id=claim['job_id'],release_sha256=claim['release_sha256'],checked=time.time(),
        squeue=queue,own_queue=own,sacct=parsed.pop('sacct'),sacct_with_times=raw,
        complete=not queue.strip() and parsed['complete'],terminal=not queue.strip() and parsed['terminal'],accounting=parsed)
    write_new(receipt_path,result);return result


def _wait_cost_status_epoch(target,deadline):
    if target>=deadline:raise a.ActivationError('terminal status wait cannot extend original control expiry')
    while time.time()<target:
        now=time.time()
        if now>=deadline:raise a.ActivationError('original terminal status control clock expired')
        time.sleep(min(1,target-now,deadline-now))


def terminal_status_cost(key,config_path,destination):
    """At most two ordinary status calls in one8CPU lifetime; never collect."""
    ledger=Ledger();claim=ledger.snapshot()['claims'][key]
    if (claim.get('task',{}).get('purpose')!='COST_ONLY' or claim.get('state') not in {'ACTIVATED','SUBMITTED'}
            or not re.fullmatch(r'[1-9][0-9]*',str(claim.get('job_id','')))):
        raise a.ActivationError('known submitted/activated COST job required')
    root=Path(claim['release_path']);release=r.read(root/'release.json');config=ctl.config(config_path)
    if (r.digest(root/'release.json')!=claim['release_sha256'] or r.identity(config)!=claim['config_sha256']
            or release.get('task_key')!=key or release.get('source_hashes')!=a.executed_sources('COST_ONLY')):
        raise a.ActivationError('immutable terminal status metadata identity differs')
    allocation=claim.get('allocation_start_epoch')
    if allocation is None:
        event=a.read_pin(claim.get('startup_failure_pin'))
        failure=event.get('evidence',{})
        if (event.get('event')!='FAILED' or failure.get('task_key')!=key
                or failure.get('job_id')!=claim['job_id'] or failure.get('release_sha256')!=claim['release_sha256']):
            raise a.ActivationError('unactivated status requires the exact observed worker-failure seal')
    destination=r.no_links(destination)
    if destination.exists():raise FileExistsError('new finite status audit required')
    destination.mkdir(parents=True)
    try:
        budget=bind_control(config,release) # Metadata-only prewait, no outer full bound/hash.
        _,clock=control_scope(release);deadline=clock['expires_epoch']
        first=max(time.time(),allocation+305) if allocation is not None else time.time()
        _wait_cost_status_epoch(first,deadline)
        if time.time()>=deadline:raise a.ActivationError('original status clock expired before I/O')
        receipt=status(key,config_path,destination/'status-1.json')
        result=pin(destination/'status-1.json')
        if not receipt.get('terminal'):
            second=max(receipt['checked']+301,allocation+1265) if allocation is not None else receipt['checked']+301
            _wait_cost_status_epoch(second,deadline)
            if time.time()>=deadline:raise a.ActivationError('original status clock expired before I/O')
            receipt=status(key,config_path,destination/'status-2.json');result=pin(destination/'status-2.json')
        summary=dict(schema=SCHEMA,task_key=key,job_id=claim['job_id'],receipt=result,
            status='COST_TERMINAL_ACCOUNTING_READY' if receipt.get('terminal') else 'COST_STATUS_LIMIT_REACHED_NOT_TERMINAL',
            terminal=bool(receipt.get('terminal')),ordinary_status_calls=2 if (destination/'status-2.json').exists() else 1,
            maximum_status_calls=2,automatic_collect=False,implicit_third_call=False)
        write_new(destination/'status-closeout.json',summary);return summary
    finally:finish_parent_contexts()


def validate_outputs(outputs,claim,release):
    outputs=ctl.safe_tree(outputs);seal=r.read(outputs/'worker_evidence.json')
    if (seal.get('schema')!=SCHEMA or seal.get('task_key')!=claim.get('operational_task_key',claim['task_key'])
            or seal.get('release_sha256')!=r.digest(Path(claim['release_path'])/'release.json') or seal.get('job_id')!=claim['job_id']
            or seal.get('authority_sha256')!=claim['authority_sha256'] or seal.get('new_model_fits')!=0 or seal.get('official_origins')!=0):
        raise a.ActivationError('worker source/job identity differs')
    members={str(p.relative_to(outputs)) for p in outputs.rglob('*') if p.is_file() and p!=outputs/'worker_evidence.json'}
    if members!=set(seal['files']):raise a.ActivationError('partial/unsealed outputs')
    for name,sha in seal['files'].items():
        if Path(name).is_absolute() or '..' in Path(name).parts or r.digest(outputs/name)!=sha:raise a.ActivationError('output hash differs')
    return seal.get('application_passed') is True


def validate_cost_outputs(outputs,claim,release):
    """Accept the whole original18-call protocol and its exact retained bytes.

    This is the legacy COST_ONLY acceptance contract with the explicit startup
    measurement now needed by prospective full-prefix pricing. It reads JSON
    and streaming hashes only; retained numerical packets remain opaque here.
    """
    if release.get('purpose')!='COST_ONLY':raise a.ActivationError('cost-only release required')
    if not validate_outputs(outputs,claim,release):return False
    from . import benchmark_plan
    outputs=ctl.safe_tree(outputs);outer=r.read(outputs/'worker_evidence.json')
    if outer.get('full_prefix_admitted') is not False:
        raise a.ActivationError('cost outer seal cannot admit a scientific prefix')
    plan=r.read(Path(claim['release_path'])/'plan.json')
    schedule=plan.get('schedule',[])
    if (not isinstance(schedule,list) or len(schedule)!=18 or any(not isinstance(v,dict) for v in schedule)
            or [v.get('sequence') for v in schedule]!=list(range(1,19))):
        raise a.ActivationError('exact ordered original18-call cost schedule required')
    timed=[v for v in schedule if v.get('kind')=='timed_prediction']
    replay=[(i,v) for i,v in enumerate(schedule) if v.get('kind')=='control_replay']
    if (len(timed)!=16 or len(replay)!=2 or {v.get('mode') for _,v in replay}!={'D','S'}
            or any(i==0 or schedule[i-1].get('kind')!='timed_prediction'
                or schedule[i-1].get('package_id')!='C0' or schedule[i-1].get('repetition')!=0
                or any(v.get(k)!=schedule[i-1].get(k) for k in ('mode','task','package_id'))
                or v.get('reference_to_prediction_sequence')!=schedule[i-1]['sequence'] for i,v in replay)):
        raise a.ActivationError('both exact adjacent first-C0 control replays required')
    packets=[v.get('serialization',{}).get('retained_packet') for v in timed]
    if (any(not isinstance(name,str) or Path(name).name!=name or not name.endswith('.npz') for name in packets)
            or len(set(packets))!=16
            or any(v.get('serialization',{}).get('compute_loss') is not False
                or v.get('serialization',{}).get('zero_origin_AQL') is not True for v in timed)):
        raise a.ActivationError('sixteen unique original loss-free retained packet names required')
    relative=Path('BENCHMARK_TEST')/release['study']/plan['canonical_preparation']['sha256'][:16]/claim['scope_id']
    root=outputs/relative;result=r.read(root/'timings.json');seal=r.read(root/'completed_evidence.json')
    if not isinstance(result,dict) or not isinstance(seal,dict):raise a.ActivationError('complete benchmark JSON records required')
    rows=result.get('rows');execution=result.get('execution',{})
    if not isinstance(execution,dict) or not isinstance(rows,list) or any(not isinstance(v,dict) for v in rows):
        raise a.ActivationError('complete benchmark execution and row records required')
    allocation=execution.get('allocation',{})
    if (result.get('status')!='COMPLETE_COST_ONLY_18_CALL_PANEL_NO_SELECTION_NO_ADMISSION'
            or seal.get('status')!='COMPLETE_COST_PANEL_ONLY_NO_SCIENCE_ADMISSION'
            or execution!=seal.get('execution') or execution.get('plan_sha256')!=release['plan_sha256']
            or execution.get('authority_sha256')!=claim['authority_sha256'] or execution.get('scope_id')!=claim['scope_id']
            or execution.get('namespace')!='BENCHMARK_TEST' or execution.get('full_prefix_admitted') is not False
            or execution.get('scientific_exclusion_key')!=plan['claim']['scientific_exclusion_key']
            or allocation.get('job_id')!=claim['job_id'] or allocation.get('cpus_per_task')!=1
            or not isinstance(allocation.get('affinity'),list) or len(allocation['affinity'])!=1
            or result.get('arithmetic_calls')!=18 or result.get('timed_prediction_calls')!=16
            or result.get('untimed_control_replay_prediction_calls')!=2 or len(rows)!=16
            or result.get('no_new_candidate_AQL_computed') is not True or result.get('no_scientific_selection') is not True
            or result.get('full_prefix_admitted') is not False or result.get('prefix_pricing_performed') is not False
            or result.get('automatic_retry') is not False or result.get('new_model_fits')!=0 or result.get('official_origins')!=0
            or any(type(result.get(k)) not in (int,float) or not math.isfinite(result[k]) or not 0<=result[k]<=1200
                for k in ('process_CPU_seconds','aggregate_CPU_seconds','elapsed_seconds','startup_cpu_seconds'))):
        raise a.ActivationError('incomplete or scientifically expanded cost panel')
    if not result['startup_cpu_seconds']<=result['process_CPU_seconds']+1e-6<=result['aggregate_CPU_seconds']+2e-6:
        raise a.ActivationError('startup/process/aggregate CPU measurements are inconsistent')
    expected_calls=[{k:v[k] for k in ('sequence','kind','task')} for v in schedule]
    expected_rows=[tuple(v[k] for k in ('mode','package_id','repetition','p')) for v in timed]
    actual_rows=[tuple(v.get(k) for k in ('mode','package_id','repetition','p')) for v in rows]
    if (result.get('calls')!=expected_calls or actual_rows!=expected_rows
            or result.get('numerical_preflight',{}).get('parents')!=benchmark_plan.COUNTS[release['study']]['parents']
            or any(v.get('split')!=3 or v.get('clock_offset_steps')!=0 or v.get('origin_count')!=8 for v in rows)):
        raise a.ActivationError('cost result exact schedule or all-parent preflight differs')
    artifacts=seal.get('artifacts',{})
    if (not isinstance(artifacts,dict) or set(artifacts)!={'execution_identity.json','timings.json',*packets}
            or r.read(root/'execution_identity.json')!=execution):
        raise a.ActivationError('complete retained packet/identity membership required')
    members={str(q.relative_to(root)) for q in root.rglob('*') if q.is_file() and q!=root/'completed_evidence.json'}
    if members!=set(artifacts):raise a.ActivationError('partial inner benchmark output seal')
    for name,sha in artifacts.items():
        if Path(name).is_absolute() or '..' in Path(name).parts or r.digest(root/name)!=sha:
            raise a.ActivationError('inner benchmark output seal differs')
    for row,name in zip(rows,packets):
        pools=row.get('numerical_threadpools')
        if (not isinstance(pools,list) or not pools or any(not isinstance(v,dict)
                or type(v.get('num_threads')) is not int or v['num_threads']!=1 for v in pools)):
            raise a.ActivationError('actual benchmark numerical pool count differs')
        packet=root/name
        if (row.get('retained_prediction_packet')!=name or row.get('retained_prediction_sha256')!=artifacts[name]
                or type(row.get('compressed_bytes')) is not int or row['compressed_bytes']<=0
                or packet.stat().st_size!=row['compressed_bytes']):
            raise a.ActivationError('retained packet row/hash/bytes mismatch')
        if any(type(row.get(k)) not in (int,float) or not math.isfinite(row[k]) or not 0<=row[k]<=1200
                for k in ('cold_context_cpu_seconds','arithmetic_cpu_seconds','serialization_cpu_seconds')):
            raise a.ActivationError('finite complete measured prospective task CPU required')
    return True


def collect(key,config_path,receipt_path,incoming,destination):
    ledger,claim,release,config=_bound_claim(key,config_path);receipt=r.read(receipt_path)
    if (claim['state'] not in {'ACTIVATED','SUBMITTED','AMBIGUOUS'} or receipt.get('task_key')!=key or receipt.get('job_id')!=claim['job_id']
            or receipt.get('release_sha256')!=claim['release_sha256'] or time.time()-receipt.get('checked',0)>300
            or receipt.get('squeue','').strip() or not receipt.get('terminal')):raise a.ActivationError('fresh exact terminal accounting required')
    parsed=parse_accounting(receipt['sacct_with_times'],claim['job_id'],release['resources'])
    if not parsed['terminal']:raise a.ActivationError('all job steps must be terminal')
    if claim.get('allocation_start_epoch'):
        from datetime import datetime,timezone
        row=next(v for v in parsed['start_end_rows'] if v[0]==claim['job_id'])
        if abs(datetime.fromisoformat(row[8]).replace(tzinfo=timezone.utc).timestamp()-claim['allocation_start_epoch'])>1:
            raise a.ActivationError('accounting/activation starts disagree')
    incoming=r.no_links(incoming);destination=r.no_links(destination)
    if incoming.exists() or destination.exists():raise FileExistsError('new quarantine/publication required')
    incoming.mkdir(parents=True)
    for name in ('outputs','logs'):
        transfer(config,claim['remote_root']+'/'+name,incoming/name,pull=True)
    ctl.safe_tree(incoming);accepted=False;diagnosis=None
    try:
        accepted=bool(parsed['complete'] and validate_outputs(incoming/'outputs',claim,release))
        if accepted and release['purpose']=='COST_ONLY':accepted=validate_cost_outputs(incoming/'outputs',claim,release)
        if accepted and release['purpose']=='CONTROL_TEST':
            parity=r.read(incoming/'outputs/TEST/parity/parity.json');actual=r.read(incoming/'outputs/environment-runtime.json')
            accepted=parity.get('accepted') is True and len(parity.get('array_comparison',{}))==15 and actual.get('status')=='verified'
    except (OSError,ValueError,KeyError) as exc:diagnosis=str(exc);accepted=False
    write_new(incoming/'accounting.json',receipt);shutil.copyfile(Path(claim['release_path'])/'release.json',incoming/'release.json')
    for rel,name in (('authorization/authority.json','authority.json'),('authorization/activation/packet.json','activation.json')):
        source=Path(claim['release_path'])/rel
        if source.exists():shutil.copyfile(source,incoming/name)
    write_new(incoming/'collection.json',dict(schema=SCHEMA,task_key=key,application_accepted=accepted,diagnosis=diagnosis,
        reserved_CPU_seconds=release['resources']['cpu_seconds'],scope_violations=parsed['scope_violations'],no_refund=True))
    destination.parent.mkdir(parents=True,exist_ok=True);temporary=destination.with_name('.'+destination.name+'.incoming-'+uuid.uuid4().hex)
    shutil.copytree(incoming,temporary)
    if accepted:
        validate_outputs(temporary/'outputs',claim,release)
        if release['purpose']=='COST_ONLY':validate_cost_outputs(temporary/'outputs',claim,release)
    with r.lock(destination.parent/'publication.lock'):
        if destination.exists():raise FileExistsError('publication exists')
        temporary.rename(destination)
    if release['purpose']=='COST_ONLY':
        from . import cost_control
        old=cost_control.Ledger();legacy=old.snapshot()['claims'][claim['legacy_cost_key']]
        if legacy['state'] not in {'SUBMITTED','AMBIGUOUS'} or accepted and legacy['state']!='SUBMITTED':raise a.ActivationError('canonical cost claim not reconcilable')
        old.transition(legacy['task_key'],legacy['state'],'COLLECTED_COST_ONLY' if accepted else 'FAILED_RECONCILED',
            operational_task_key=key,application_accepted=accepted,publication=str(destination),authority_sha256=claim['authority_sha256'])
    elif release['purpose'] in {'CACHED_NORMAL_COMPONENT','PREFIX_ASSESSMENT'}:
        from . import prefix_control
        prefix_control.lifecycle_complete(key,dict(application_passed=accepted),str(destination),receipt)
    return ledger.transition(key,claim['state'],'COLLECTED' if accepted else 'FAILED_RECONCILED',
        application_accepted=accepted,publication=str(destination),diagnosis=diagnosis,scope_violations=parsed['scope_violations'])


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='action',required=True)
    q=sub.add_parser('prepare')
    for name in ('plan','request','config','destination'):q.add_argument('--'+name,required=True)
    q.add_argument('--purpose',choices=('CONTROL_TEST','COST_ONLY'),default='COST_ONLY');q.add_argument('--fixture')
    q=sub.add_parser('submit-held');q.add_argument('--release',required=True);q.add_argument('--config',required=True)
    q=sub.add_parser('submit-replacement-part1')
    for name in ('release','config','destination'):q.add_argument('--'+name,required=True)
    q=sub.add_parser('submit-replacement-part2')
    for name in ('phase1','config','destination'):q.add_argument('--'+name,required=True)
    for action in ('issue-authority','authority-and-observe','release-job','watch-ready','activate','watch-and-activate','release-and-activate','status','terminal-status-cost','collect','cancel-held'):
        q=sub.add_parser(action);q.add_argument('--key',required=True);q.add_argument('--config',required=True)
        if action=='watch-ready':q.add_argument('--destination',required=True)
        if action=='activate':q.add_argument('--request',required=True)
        if action=='watch-and-activate':q.add_argument('--request',required=True);q.add_argument('--destination',required=True)
        if action in ('release-and-activate','authority-and-observe'):
            for name in ('operator-config','resource-plan','destination'):q.add_argument('--'+name,required=True)
            q.add_argument('--owner-receipt')
        if action in ('status','collect'):q.add_argument('--receipt',required=True)
        if action=='terminal-status-cost':q.add_argument('--destination',required=True)
        if action=='collect':q.add_argument('--incoming',required=True);q.add_argument('--destination',required=True)
    for action in ('worker','payload'):
        q=sub.add_parser(action);q.add_argument('--release',required=True);q.add_argument('--release-sha256',required=True)
    args=parser.parse_args(argv)
    if args.action=='prepare':result=prepare(args.plan,args.request,args.config,args.destination,args.purpose,args.fixture)
    elif args.action=='submit-held':
        if r.read(Path(args.release)/'release.json').get('cost_replacement') is not None:
            raise a.ActivationError('replacement uses submit-replacement-part1/part2; no stock full transfer')
        result=submit_component(args.release,args.config)
    elif args.action=='submit-replacement-part1':
        from . import cost_control
        result=cost_control.submit_replacement_part1(args.release,args.config,args.destination)
    elif args.action=='submit-replacement-part2':
        from . import cost_control
        result=cost_control.submit_replacement_part2(args.phase1,args.config,args.destination)
    elif args.action=='issue-authority':result=issue_authority(args.key,args.config)
    elif args.action=='authority-and-observe':result=authority_and_observe(args.key,args.config,args.operator_config,
        args.resource_plan,args.destination,pin(args.owner_receipt) if args.owner_receipt else None)
    elif args.action=='release-job':result=release_job(args.key,args.config)
    elif args.action=='watch-ready':result=watch_ready(args.key,args.config,args.destination)
    elif args.action=='activate':result=activate(args.key,args.config,args.request)
    elif args.action=='watch-and-activate':result=watch_and_activate(args.key,args.config,args.request,args.destination)
    elif args.action=='release-and-activate':result=release_and_activate(args.key,args.config,args.operator_config,
        args.resource_plan,args.destination,pin(args.owner_receipt) if args.owner_receipt else None)
    elif args.action=='status':result=status(args.key,args.config,args.receipt)
    elif args.action=='terminal-status-cost':result=terminal_status_cost(args.key,args.config,args.destination)
    elif args.action=='collect':result=collect(args.key,args.config,args.receipt,args.incoming,args.destination)
    elif args.action=='cancel-held':result=cancel_held(args.key,args.config)
    elif args.action=='worker':result=worker(args.release,args.release_sha256)
    else:result=payload(args.release,args.release_sha256)
    finish_parent_contexts()
    print(json.dumps(result,sort_keys=True,allow_nan=False))


if __name__=='__main__':
    try:main()
    finally:finish_parent_contexts()
