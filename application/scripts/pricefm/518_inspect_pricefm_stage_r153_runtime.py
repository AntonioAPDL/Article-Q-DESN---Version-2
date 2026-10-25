#!/usr/bin/env python3
"""Read-only current R153 baseline/CZ observer; no service or model actions.

Resolve only the selected lane's canonical registration, then load its pinned
release/inspection API. A valid waiting gate is not completed scientific work.
Historical R152 generation-three failure is never substituted for R153 health.
"""
from __future__ import annotations
import argparse
import csv
import datetime
import hashlib
import importlib.util
import json
import math
from pathlib import Path, PurePosixPath
import socket
import sys

# Loading the selected inspection API must not create __pycache__ files even
# when this utility is invoked without Python's optional -B flag.
sys.dont_write_bytecode=True

ROOT=Path(__file__).resolve().parents[3]
ENTRY=Path(__file__).resolve()
DATA=Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
LEGACY=DATA/'launch_prep/pricefm_stage_r152_parallel_20261024'
SHARED=DATA/'launch_prep/pricefm_stage_r153_control_lifecycle_20261025'
BASELINE_POINTER=LEGACY/'baseline/explicit_successor.json'
BASELINE_RUNTIME=SHARED/'baseline'
BASELINE_AUTHORITY=BASELINE_RUNTIME/'authority.json'
CZ_ROOT=SHARED/'cz'
CZ_CLAIM=CZ_ROOT/'single_activation_claim.json'
FORBIDDEN_OUTPUT_ROOTS=(DATA,ROOT.parents[2])


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


def load_release(lane):
    name={'baseline':'514_release_pricefm_stage_r153_control_repair.py',
          'cz':'516_release_pricefm_stage_r153_cz_gate.py'}[lane]
    path=ENTRY.with_name(name)
    spec=importlib.util.spec_from_file_location('r153_readonly_'+lane+'_release',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def absent(lane,registration):
    return dict(status='R153_'+lane.upper()+'_NOT_REGISTERED',healthy=False,registered=False,
        registration_path=str(registration),phase='not_registered',scientific_complete=False,
        reason='No current explicit registration exists; historical source state is not a current-health proof')


def inspect_baseline(system=None):
    if not BASELINE_POINTER.exists():return absent('baseline',BASELINE_POINTER)
    record=read(BASELINE_POINTER)
    require(record.get('kind')=='EXPLICIT_R153_BASELINE_ONLY_SUCCESSOR'
        and record.get('authority_path')==str(BASELINE_AUTHORITY)
        and record.get('runtime')==str(BASELINE_RUNTIME)
        and record.get('legacy_generations_spent')==3
        and record.get('explicit_additional_activation')==1
        and record.get('cumulative_owner_count')==4
        and record.get('cached_restart_authorized') is False,
        'baseline registration namespace/single-activation contract differs')
    require(digest(BASELINE_AUTHORITY)==record.get('authority_sha256'),
        'registered baseline authority hash differs')
    release=load_release('baseline')
    require(release.AUTHORITY==BASELINE_AUTHORITY and release.RUNTIME==BASELINE_RUNTIME,
        'baseline inspection API uses a different namespace')
    authority=release.validate_authority(BASELINE_AUTHORITY,system=system)
    require(authority['execution_source']==record.get('source')
        and authority['execution_source'].get('root')==str(ROOT),
        'registered baseline source differs from its verified authority')
    proof=release.owner().inspect_owner(BASELINE_AUTHORITY,system=system)
    require(proof.get('execution_source')==authority['execution_source']
        and proof.get('cached_scope_closed') is True, 'baseline proof/source/closure differs')
    finished=proof.get('tail_finished') is True
    return dict(status='R153_BASELINE_TAIL_DISPOSITIONS_COMPLETE' if finished else 'R153_BASELINE_OWNER_OBSERVED',
        healthy=proof.get('healthy') is True,registered=True,phase=proof.get('phase'),
        registration_path=str(BASELINE_POINTER),authority_path=str(BASELINE_AUTHORITY),
        authority_sha256=record['authority_sha256'],current_runtime=str(BASELINE_RUNTIME),
        legacy_generation_three_is_historical=True,baseline_tail_finished=finished,
        scientific_complete=False,global_campaign_complete=False,proof=proof)


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


def inspect_cz(system=None):
    if not CZ_CLAIM.exists():return absent('cz',CZ_CLAIM)
    claim=read(CZ_CLAIM);identity=claim.get('id','');path=Path(claim.get('authority_path',''))
    require(len(identity)==32 and all(c in '0123456789abcdef' for c in identity)
        and claim.get('claim')==1 and path==CZ_ROOT/identity/'authority.json'
        and digest(path)==claim.get('authority_sha256'),'CZ global claim/authority identity differs')
    release=load_release('cz');api=release.api();system=system or api.System()
    require(api.RUNTIME==CZ_ROOT,'CZ inspection API uses a different namespace')
    authority=api.validate_authority(path,system=system,allow_expired=True)
    require(authority['id']==identity and authority['runtime']==str(path.parent)
        and authority['execution_source'].get('root')==str(ROOT),'CZ authority runtime/source differs')
    root=path.parent;common=dict(registered=True,registration_path=str(CZ_CLAIM),authority_path=str(path),
        authority_sha256=claim['authority_sha256'],current_runtime=str(root),
        source=authority['execution_source'],scientific_complete=False,automatic_retry=False)
    science_claim=read(root/'science_claim.json') if (root/'science_claim.json').exists() else None
    if science_claim:
        require(science_claim.get('claim')==1 and science_claim.get('authority_sha256')==digest(path)
            and science_claim.get('unit')==authority['science_unit']
            and science_claim.get('claimed_epoch',float('inf'))<authority['expires_epoch']
            and science_claim.get('boundary',{}).get('ready') is True,'CZ scientific claim differs')
    for name in ('science_blocked.json','waiter_blocked.json'):
        if (root/name).exists():
            return dict(common,status='R153_CZ_BLOCKED',healthy=False,phase='blocked',
                scientific_dispatches=int(science_claim is not None),blocked_record=read(root/name))
    require(api.old_waiter_drained(authority,system)['drained'] is True,'original CZ waiter is not drained')
    if (root/'science_terminal.json').exists():
        require(science_claim is not None,'CZ terminal lacks a scientific claim')
        terminal=verify_cz_terminal(api,authority,path,read(root/'science_terminal.json'),system)
        return dict(common,status='R153_CZ_SCIENCE_COMPLETE_NOT_PROMOTED',healthy=True,
            phase='complete',scientific_complete=True,scientific_dispatches=1,terminal=terminal)
    if science_claim:
        activation=root/'scientific_activation.json'
        if not activation.exists():
            return dict(common,status='R153_CZ_DELEGATION_NOT_YET_ATTESTED',healthy=False,
                phase='delegation_pending',scientific_dispatches=1,
                waiter_grant_expired=system.now()>=authority['expires_epoch'])
        value=read(activation)
        require(value.get('activation')==1 and value.get('authority_sha256')==digest(path)
            and value.get('effective_config_sha256')==authority['effective_config_sha256'],
            'CZ scientific activation source/config differs')
        live=verify_capsule(api,authority,path,value['capsule'],system,'science')
        # Own delegated numerical work now occupies slot B. Re-running the
        # pre-dispatch empty-slot test here would create a false failure.
        return dict(common,status='R153_CZ_ORIGINAL_SCIENCE_RUNNING',healthy=True,
            phase='delegated',scientific_dispatches=1,live=live,
            boundary_verified_at_claim=science_claim['boundary'],
            waiter_grant_expired=system.now()>=authority['expires_epoch'])
    if system.now()>=authority['expires_epoch']:
        return dict(common,status='R153_CZ_WAIT_ALLOWANCE_EXPIRED',healthy=False,
            phase='expired',scientific_dispatches=0)
    activation=root/'activation.json'
    if not activation.exists():
        return dict(common,status='R153_CZ_WAIT_ACTIVATION_NOT_YET_ATTESTED',healthy=False,
            phase='activation_pending',scientific_dispatches=0)
    value=read(activation)
    require(value.get('activation')==1 and value.get('authority_sha256')==digest(path),
        'CZ waiter activation authority differs')
    live=verify_capsule(api,authority,path,value['capsule'],system,'waiter')
    launch=read(root/'launch_claim.json')
    require(launch.get('claim')==1 and launch.get('unit')==authority['waiter_unit']
        and launch.get('authority_sha256')==digest(path)
        and launch.get('expected_control_source')==authority['execution_source']
        and launch.get('expected_argv')==cz_argv(api,authority,path,'waiter')
        and 0<api.systemd_seconds(live['properties'].get('RuntimeMaxUSec',''))<=7*86400
        and api.systemd_seconds(live['properties'].get('RuntimeMaxUSec',''))==launch.get('expected_RuntimeMaxSec'),
        'CZ live waiter expiry/launch identity differs')
    api.cpu_guard(authority,system)
    progress=read(root/'progress.json')
    require(progress.get('authority_sha256')==digest(path)
        and 0<=system.now()-progress.get('epoch',0)<=180,'CZ waiting progress is stale or mismatched')
    boundary=api.boundary_state(authority,system)
    return dict(common,status='R153_CZ_WAITING_FOR_PREDECESSOR_BOUNDARY',healthy=True,
        phase='boundary_ready' if boundary.get('ready') else 'waiting',scientific_dispatches=0,
        boundary=boundary,live=live,progress=progress)


def observe(lane,system=None):
    base=dict(lane=lane,observed_UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        observed_host=socket.gethostname().split('.')[0],observer_sha256=digest(ENTRY),
        model_signals=0,service_actions=0,canonical_runtime_writes=0,
        source_edits=0,model_dispatches_by_observer=0)
    try:
        result=inspect_baseline(system) if lane=='baseline' else inspect_cz(system)
        return dict(base,**result)
    except (RuntimeError,OSError,KeyError,ValueError,TypeError) as error:
        return dict(base,status='R153_'+lane.upper()+'_OBSERVATION_FAILED',healthy=False,
            phase='verification_failed',scientific_complete=False,error=repr(error))


def write_new_output(path,value):
    target=Path(path)
    require(target.is_absolute() and not target.exists() and not target.is_symlink(),
        'observer output must be a new absolute file')
    resolved=target.resolve()
    require(all(not resolved.is_relative_to(root.resolve()) for root in FORBIDDEN_OUTPUT_ROOTS),
        'observer output may not enter canonical data or source worktrees')
    target.parent.mkdir(parents=True,exist_ok=True)
    with target.open('x') as stream:stream.write(json.dumps(value,indent=2,sort_keys=True,allow_nan=False)+'\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('lane',choices=('baseline','cz'))
    parser.add_argument('--output',type=Path)
    args=parser.parse_args();value=observe(args.lane)
    if args.output:
        try:write_new_output(args.output,value)
        except (RuntimeError,OSError) as error:
            print(json.dumps(dict(status='R153_OBSERVER_OUTPUT_REJECTED',error=str(error)),sort_keys=True),file=sys.stderr)
            return 1
    print(json.dumps(value,indent=2,sort_keys=True,allow_nan=False))
    return 0 if value.get('healthy') is True else 1


if __name__=='__main__':raise SystemExit(main())
