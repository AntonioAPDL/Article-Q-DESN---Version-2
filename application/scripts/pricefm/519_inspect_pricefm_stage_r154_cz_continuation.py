#!/usr/bin/env python3
"""Read-only actual R154 continuation observer; never charges observer CPU."""
from __future__ import annotations
import csv
import hashlib
import math
import importlib.util
import json
from pathlib import Path, PurePosixPath
import sys
import time

ENTRY=Path(__file__).resolve()
spec=importlib.util.spec_from_file_location('r154_observer_actual_gate',ENTRY.with_name('519_resolve_pricefm_stage_r154_cz_continuation.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
ROOT=m.ROOT


def require(value,message):
    if not value:raise RuntimeError(message)


def digest(path):
    p=Path(path)
    require(p.is_absolute() and p.is_file() and not p.is_symlink() and p.resolve()==p,
        'missing, symlinked or noncanonical hashed record: '+str(p))
    h=hashlib.sha256()
    with p.open('rb') as f:
        for block in iter(lambda:f.read(1048576),b''):h.update(block)
    return h.hexdigest()

def read(path):
    p=Path(path)
    require(p.is_absolute() and p.is_file() and not p.is_symlink() and p.resolve()==p,
        'missing, symlinked or noncanonical observation record: '+str(p))
    return json.loads(p.read_text())

def cz_argv(api,authority,path,role):
    argv=[str(api.PYTHON),'-B',str(api.ENTRY),'run' if role=='waiter' else 'delegate',
          '--authority',str(path)]
    if role=='science':argv+=['--delegated-entry',str(api.R144_ENTRY)]
    return argv+['--unit',authority['waiter_unit'] if role=='waiter' else authority['science_unit']]

def verify_capsule(api,authority,path,capsule,system,role,*,require_live=True):
    unit=authority['waiter_unit'] if role=='waiter' else authority['science_unit']
    expected=cz_argv(api,authority,path,role);recorded=capsule.get('process',{})
    attested=capsule.get('properties',{})
    require(capsule.get('unit')==unit and capsule.get('actual_entry')==str(api.ENTRY)
        and capsule.get('delegated_entry')==(str(api.R144_ENTRY) if role=='science' else None)
        and capsule.get('execution_source')==authority['execution_source']
        and capsule.get('scientific_source')==authority['science_source']
        and recorded.get('argv')==expected and recorded.get('cwd')==str(ROOT)
        and isinstance(recorded.get('pid'),int) and recorded['pid']>0
        and recorded.get('start_ticks') is not None and bool(recorded.get('boot_id'))
        and bool(recorded.get('cmdline_sha256'))
        and attested.get('Id')==unit and bool(attested.get('InvocationID'))
        and bool(attested.get('ControlGroup'))
        and attested.get('ControlGroup') in recorded.get('cgroups',[])
        and attested.get('Restart')=='no' and attested.get('KillMode')=='process'
        and attested.get('CPUAccounting')=='yes' and attested.get('WorkingDirectory')==str(ROOT),
        'CZ attested role/source/argv differs')
    props=system.unit(unit);current=system.process(recorded['pid'])
    if require_live:
        require(api.exact_process(current,recorded) and current.get('argv')==expected
            and int(props.get('MainPID',0))==recorded['pid'] and props.get('ActiveState')=='active'
            and props.get('Id')==unit and bool(props.get('InvocationID'))
            and props.get('InvocationID')==capsule['properties'].get('InvocationID')
            and bool(props.get('ControlGroup'))
            and props.get('ControlGroup')==capsule['properties'].get('ControlGroup')
            and props.get('ControlGroup') in current.get('cgroups',[])
            and props.get('Restart')=='no' and props.get('KillMode')=='process'
            and props.get('CPUAccounting')=='yes' and props.get('WorkingDirectory')==str(ROOT),
            'CZ current unit/lifetime/invocation differs')
    else:
        groups={capsule['properties'].get('ControlGroup',''),props.get('ControlGroup','')}-{''}
        require(not api.same_lifetime(current,recorded) and not int(props.get('MainPID',0))
            and props.get('ActiveState') not in {'active','activating','deactivating'}
            and all(not system.members(group) for group in groups),
            'CZ terminal control/model cgroup has not drained')
    return dict(unit=unit,properties=props,process=current,recorded_process=recorded)

def verify_cz_terminal(api,authority,path,value,system):
    require(value.get('authority_sha256')==digest(path),'CZ scientific terminal authority differs')
    result=value['result'];expected_source={k:authority['science_source'][k] for k in ('branch','head')}
    require(result.get('status')=='R144_CZ_FALLBACK_COMPLETE_NOT_PROMOTED'
        and result.get('source')==expected_source and result.get('region')=='CZ'
        and result.get('fallback_rank')==3
        and result.get('fallback_candidate')==authority['effective_config']['fallback_candidate']
        and result.get('source_r141_head')=='4cd92ac3654f16a84a67c8db6cfc7f381113aeb9'
        and result.get('test_used_for_selection') is False and result.get('authority_mutated') is False
        and result.get('article_mutated') is False and result.get('promotion_decided') is False
        and result.get('full_fits')==24 and result.get('official_origin_region_pairs')==365,
        'CZ result is not the original complete unpromoted scientific protocol')
    folder=api.DATA/'campaigns'/authority['effective_config']['tag']
    require(read(folder/'terminal.json')==result,'CZ original campaign and wrapper terminal differ')
    seal=read(folder/'closeout/completed_evidence.json')
    require(seal.get('metadata',{}).get('source')==expected_source
        and 'fold_comparison.csv' in seal.get('artifacts',{}),
        'CZ closeout source/seal differs')
    for name,wanted in seal['artifacts'].items():
        relative=PurePosixPath(name);target=folder/'closeout'/name
        require(not relative.is_absolute() and '..' not in relative.parts
            and target.resolve().is_relative_to((folder/'closeout').resolve())
            and not target.is_symlink() and digest(target)==wanted,'CZ closeout payload differs')
    with (folder/'closeout/fold_comparison.csv').open() as stream:rows=list(csv.DictReader(stream))
    require(len(rows)==12 and {(int(r['fold']),r['operator']) for r in rows}
        =={(fold,op) for fold in (1,2,3) for op in ('cdf_pool_clipped','mean_feature','path_specific','normal_driver')}
        and all(r['region']=='CZ' and math.isfinite(float(r['AQL'])) and float(r['AQL'])>=0 for r in rows),
        'CZ complete folded operator surface differs')
    units=verify_capsule(api,authority,path,value['actual_control_capsule'],system,'science',require_live=False)
    return dict(result=result,closeout_seal_sha256=digest(folder/'closeout/completed_evidence.json'),drain=units)

def observe(system=None):
    system=system or m.System();registry=m.RUNTIME/'single_activation_claim.json'
    common=dict(lane='cz',observed_epoch=system.now(),source_runtime_writes=0,
        model_dispatches_by_observer=0,model_signals=0,automatic_retry=False)
    if not registry.exists():return dict(common,status='R154_CZ_NOT_ACTIVATED',healthy=False,scientific_dispatches=0)
    grant=m.read(registry);path=Path(grant['authority_path']).resolve()
    require(grant.get('authority_sha256')==m.sha(path),'activation registration/authority differs')
    authority=m.validate_authority(path,system=system,allow_expired=True);root=Path(authority['runtime'])
    require(grant.get('id')==authority['id'],'registered identity differs')
    common.update(authority_path=str(path),authority_sha256=m.sha(path),current_runtime=str(root),
        execution_source=authority['execution_source'],previous_authority_path=authority['previous_authority_path'])
    m.assert_previous_drained(authority,system)
    claim=m.read(root/'science_claim.json') if (root/'science_claim.json').exists() else None
    if claim:
        require(m.read(m.RUNTIME/'science_dispatch_claim.json')==claim,'global/root scientific claims differ')
        require(claim.get('authority_sha256')==m.sha(path) and claim.get('unit')==authority['science_unit']
            and claim.get('boundary',{}).get('ready') is True,'scientific claim differs')
    m.assert_no_prior_science(authority,allow_own_preparation=bool(claim and (root/'scientific_activation.json').exists()))
    for name in ['waiter_blocked.json','science_blocked.json']:
        if (root/name).exists():return dict(common,status='R154_CZ_BLOCKED',healthy=False,
            scientific_dispatches=int(claim is not None),record=m.read(root/name))
    if (root/'science_terminal.json').exists():
        require(claim is not None,'scientific terminal without claim')
        terminal=verify_cz_terminal(m,authority,path,m.read(root/'science_terminal.json'),system)
        return dict(common,status='R154_CZ_ORIGINAL_R144_SCIENCE_COMPLETE_NOT_PROMOTED',healthy=True,
            scientific_dispatches=1,scientific_complete=True,terminal=terminal)
    if claim:
        activation=root/'scientific_activation.json'
        if not activation.exists():return dict(common,status='R154_CZ_SCIENCE_ACTIVATION_PENDING',healthy=False,scientific_dispatches=1)
        capsule=m.read(activation)['capsule'];verify_capsule(m,authority,path,capsule,system,'science')
        return dict(common,status='R154_CZ_ORIGINAL_R144_SCIENCE_ACTIVE',healthy=True,scientific_dispatches=1,
            science=capsule,waiter_grant_expired=system.now()>=authority['expires_epoch'])
    require(system.now()<authority['expires_epoch'],'new control wall ceiling expired')
    require((root/'activation.json').exists(),'new control activation capsule missing')
    capsule=m.read(root/'activation.json')['capsule'];budget=m.observe_waiter_cpu(authority,path,system,capsule)
    require(budget['within_CPU'] and budget['within_wall'],'new control CPU/wall reserve exhausted')
    progress=m.read(root/'progress.json')
    require(progress.get('authority_sha256')==m.sha(path),'actual progress authority differs')
    return dict(common,status='R154_CZ_HEALTHY_WAITING_FOR_FULL_R143_BOUNDARY',healthy=True,
        scientific_dispatches=0,budget=budget,live=capsule,boundary=m.boundary_state(authority,system),progress=progress)


def main():
    try:value=observe()
    except Exception as error:value=dict(status='R154_CZ_OBSERVER_BLOCKED',healthy=False,error=repr(error),
        observed_epoch=time.time(),source_runtime_writes=0,model_signals=0)
    print(json.dumps(value,indent=2,sort_keys=True,allow_nan=False))
    return 0 if value.get('healthy') else 1


if __name__=='__main__':raise SystemExit(main())
