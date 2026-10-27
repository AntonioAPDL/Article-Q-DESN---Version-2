#!/usr/bin/env python3
"""Release one explicit CZ resource-gate activation; never renew cached work.

Use preflight -> probe -> prepare -> reviewed handoff. Only handoff operates
on a production administrative control lifetime; it never signals a model. The unchanged R144 scientific graph cannot dispatch
until the entire R143 boundary is independently verified by entry 515.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import math
import re
import os
import signal
import select
import resource
import ctypes
import platform
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
GATE = ENTRY.with_name('519_resolve_pricefm_stage_r154_cz_continuation.py')
OBSERVER = ENTRY.with_name('519_inspect_pricefm_stage_r154_cz_continuation.py')
PREVIOUS_ROOT = ROOT.parent/'pricefm_r153_cz_release_20261025'
PREVIOUS_ENTRY = PREVIOUS_ROOT/'application/scripts/pricefm/515_resolve_pricefm_stage_r153_cz_gate.py'
PREVIOUS_REGISTRY = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/launch_prep/pricefm_stage_r153_control_lifecycle_20261025/cz/single_activation_claim.json')
_API = None


def api():
    global _API
    if _API is None:
        spec = importlib.util.spec_from_file_location('r154_cz_explicit_resource_gate', GATE)
        _API = importlib.util.module_from_spec(spec); spec.loader.exec_module(_API)
    return _API


def process_CPU():
    values = os.times()
    return time.process_time() + values.children_user + values.children_system


def output(value, path=None):
    text = json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n'
    if path:
        target = Path(path); target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('x') as stream: stream.write(text)
    return value


def source_records(system):
    m = api(); config = m.read(m.R144_CONFIG); predecessor = m.read(m.R143_CONFIG)
    control = system.source(ROOT)
    if not control['branch'].startswith('work/pricefm-r154-cz-continuation-'):
        raise RuntimeError('dedicated clean R154 control branch is required')
    records = dict(execution_source=control, science_source=system.source(m.R144_ROOT),
                   predecessor_source=system.source(m.R143_ROOT),
                   process_adapter_source=system.source(m.ADAPTER.parents[3]),
                   resource_core_source=system.source(m.ADAPTER.parents[3].parent/'pricefm_r152_parallel_20261024'))
    if (records['science_source']['head'] != 'f96fcb0e3dc47da236d656cda2f0e58fb537ee1f'
            or records['predecessor_source']['head'] != config['predecessor_head']
            or records['process_adapter_source']['head'] != 'cbf11c6e41d6be49ebdf9c3648fb79d2e641e234'
            or records['resource_core_source']['head'] != 'cba0b6c861f20ebdffcd970d59b0fa38afd80a42'):
        raise RuntimeError('frozen science/predecessor/process dependency heads differ')
    if predecessor['continuation_regions'] != m.QUEUE or predecessor['source_head'] != config['source_head']:
        raise RuntimeError('R143 whole-queue source contract differs')
    records['previous_control_source']=system.source(PREVIOUS_ROOT)
    if records['previous_control_source']['head']!='17bd756aacb0f4ce458978f10af45c75200b9a65':
        raise RuntimeError('previous R153 control source differs')
    pins = {str(path): m.sha(path) for path in [GATE, ENTRY, OBSERVER, PREVIOUS_ENTRY, PREVIOUS_ENTRY.with_name('516_release_pricefm_stage_r153_cz_gate.py'), m.R144_ENTRY, m.R144_CONFIG,
            m.R143_ENTRY, m.R143_CONFIG, m.ADAPTER,
            Path(records['resource_core_source']['root'])/'application/scripts/pricefm/504_supervise_pricefm_stage_r152_baseline.py']}
    for relative, expected in config['frozen_source_sha256'].items():
        path = Path(config['source_worktree'])/relative
        if m.sha(path) != expected: raise RuntimeError('frozen R141 dependency differs: '+relative)
        pins[str(path)] = expected
    for path in [m.DATA/'launch_prep'/(config['source_tag']+'__CZ')/'preparation.json',
                 m.DATA/'campaigns'/(config['source_tag']+'__CZ')/'rhs_closeout.json']:
        pins[str(path)] = m.sha(path)
    if pins[str(m.DATA/'launch_prep'/(config['source_tag']+'__CZ')/'preparation.json')] != config['source_preparation_sha256']:
        raise RuntimeError('CZ frozen preparation differs')
    if pins[str(m.DATA/'campaigns'/(config['source_tag']+'__CZ')/'rhs_closeout.json')] != config['source_rhs_closeout_sha256']:
        raise RuntimeError('CZ frozen RHS rank differs')
    for name, expected in config['prerequisites'].items():
        folder = m.DATA/'campaigns'/(config['source_tag']+'__CZ')
        for path, digest in [(folder/'tasks'/(name+'.json'),expected['task_sha256']),
                             (folder/'tasks_done'/name/'completed_evidence.json',expected['completed_evidence_sha256'])]:
            if m.sha(path) != digest: raise RuntimeError('frozen CZ prerequisite differs: '+name)
            pins[str(path)] = digest
    return records, pins


def no3_failure_pins(config):
    m = api(); root = m.DATA/'campaigns'/(config['source_tag']+'__NO_3'); pins = {}
    for name in m.APPROVED_NO3_TASKS:
        paths = [root/'tasks'/(name+'.json'), root/'contracts'/(name+'.json'),
                 root/'tasks_done'/name/'completed_evidence.json', root/'tasks_done'/name/'result.json',
                 root/'tasks_done'/name/'fit/fixedpoint_certificate.json',
                 root/'tasks_done'/name/'fit/terminal.json']
        for path in paths: pins[str(path)] = m.sha(path)
        expected=m.APPROVED_NO3_REVIEWED_SHA[name]
        if (m.sha(paths[0])!=expected['task'] or m.sha(paths[2])!=expected['seal']
                or m.sha(paths[-2])!=expected['certificate']):
            raise RuntimeError('NO3 evidence is not the exact reviewed failure target: '+name)
        task = m.read(paths[0]); cert = m.read(paths[-2]); seal = m.read(paths[2])
        if (task.get('kind') != 'internal_al' or task.get('region') != 'NO_3'
                or float(task.get('tau', task.get('quantile', 0))) != .75
                or seal.get('metadata', {}).get('certified') is not False
                or cert.get('certified') is not False):
            raise RuntimeError('NO3 approved failure identity/certificate differs: '+name)
    return pins


def previous_preflight(system):
    """Read the actual old owner. No old file or process is changed."""
    m=api(); registered=m.read(PREVIOUS_REGISTRY)
    path=Path(registered['authority_path']).resolve()
    if registered.get('authority_sha256')!=m.sha(path):
        raise RuntimeError('previous registration/authority differs')
    old_api=m.module('r154_frozen_previous_CZ_api',PREVIOUS_ENTRY)
    old=old_api.validate_authority(path,system=system,allow_expired=True)
    if old['execution_source']['root']!=str(PREVIOUS_ROOT):
        raise RuntimeError('previous source root differs')
    capsule=m.read(path.parent/'activation.json')['capsule']
    props=system.unit(old['waiter_unit']); current=m.recorded_process(system,capsule['process'])
    expected=[str(m.PYTHON),'-B',str(PREVIOUS_ENTRY),'run','--authority',str(path),'--unit',old['waiter_unit']]
    if (not m.exact_process(current,capsule['process']) or current.get('argv')!=expected
            or current.get('cpus')!=[29] or props.get('ActiveState')!='active'
            or int(props.get('MainPID',0))!=current['pid']
            or props.get('InvocationID')!=capsule['properties']['InvocationID']
            or props.get('ControlGroup')!=capsule['properties']['ControlGroup']
            or props.get('Restart')!='no' or props.get('KillMode')!='process'):
        raise RuntimeError('previous administrative owner is not its exact live lifetime')
    if not old_api.old_waiter_drained(old,system)['drained']:
        raise RuntimeError('original R144 waiter is not drained')
    m.assert_no_prior_science(dict(previous_authority_path=str(path),effective_config=old['effective_config']))
    state=old_api.boundary_state(old,system)
    budget=old_api.observe_waiter_cpu(old,path,system,capsule)
    if not budget['within_CPU'] or not budget['within_wall']:
        raise RuntimeError('previous waiter funding is already exhausted')
    return dict(status='PASS_R154_PREVIOUS_CONTROL_PREFLIGHT',authority_path=str(path),
        authority_sha256=m.sha(path),authority=old,boundary=state,budget=budget,
        previous_waiter=dict(unit=old['waiter_unit'],process=capsule['process'],
            invocation_id=props['InvocationID'],cgroup=props['ControlGroup'],properties=props),
        production_unit_actions=0,models_signalled=False)


def previous_immutable_pins(preflight):
    m=api(); root=Path(preflight['authority_path']).parent
    names=['authority.json','activation.json','launch_claim.json','launch_receipt.json',
           'old_waiter_fence.json','effective_config.json','original_waiter_progress.json']
    return {str(p):m.sha(p) for p in [PREVIOUS_REGISTRY]+[root/name for name in names]}


def make_authority(root,identity,system,preflight,records,pins,*,private=False,
                   proof_actual=0.,pricing=None,control_CPU_seconds=6400,proof_rows=None):
    m=api(); old=preflight['authority']; value=json.loads(json.dumps(old))
    root=Path(root); root.mkdir(parents=True,exist_ok=False)
    original=m.DATA/'launch_prep'/old['effective_config']['tag']/'jerez/progress.json'
    archived=root/'original_waiter_progress.json'; archived.write_bytes(original.read_bytes())
    m.immutable(root/'effective_config.json',old['effective_config'])
    proof_reserve=max(240.,proof_actual);created=system.now()
    value.update(records)
    value.update(schema_version=1,kind='R154_CZ_PRIVATE_PROFILE' if private else 'R154_CZ_CONTROL_CONTINUATION',
        id=identity,runtime=str(root),created_epoch=created,expires_epoch=created+7*86400,
        waiter_unit=('pricefm-r154-cz-probe-' if private else 'pricefm-r154-cz-gate-')+identity+'.service',
        science_unit='pricefm-r154-cz-science-'+identity+'.service',
        control_CPU_allowance_seconds=float(control_CPU_seconds),poll_seconds=60,
        additional_control_activations=1,historical_debits_credited=False,historical_claims_or_clocks_reset=False,
        previous_authority_path=preflight['authority_path'],previous_authority_sha256=preflight['authority_sha256'],
        previous_waiter=preflight['previous_waiter'],previous_immutable_sha256=previous_immutable_pins(preflight),
        historical_old_authority_CPU_allowance_seconds=old['control_CPU_allowance_seconds'],
        historical_old_measured_budget_at_preparation=preflight['budget'],
        proof_CPU_actual_charged_seconds=proof_actual,proof_CPU_charged_seconds=proof_reserve,
        proof_CPU_reserve_includes_unspent_headroom=True,
        administrative_release_CPU_reservation_seconds=120.,prior_control_CPU_charged_seconds=proof_reserve+120.,
        frozen_sha256=pins,pricing=pricing or dict(CPU_seconds_per_hour_upper=15.,
            worst_check_wall_seconds=25.,publication_wall_margin_seconds=5.),
        archived_original_waiter_progress=dict(source=str(original),archive=str(archived),sha256=m.sha(archived)),
        authority_basis='Explicit user authorization to implement the reviewed finite Oct26 control continuation; one additional control activation, unchanged original CZ science.',
        private_probe_receipts=list(proof_rows or []),
        current_release_observed_CPU_seconds=0.,private_profile_cannot_dispatch=bool(private))
    m.immutable(root/'authority.json',value)
    m.validate_authority(root/'authority.json',system=system,_private_profile=private)
    return value


def profile_check(authority,path,system,*,deep=False):
    """Run the actual new waiting checks, with extra ready-boundary probes."""
    m=api();begin=time.monotonic()
    m.validate_authority(path,system=system,_private_profile=True)
    previous=m.previous_waiter_drained(authority,system)  # observed, not required in private proof
    m.assert_no_prior_science(authority)
    state=m.boundary_state(authority,system)
    # These additional read-only probes price the existing full closeout and
    # process census rather than claiming the future PT/SE3 closeouts exist.
    closeouts={r:m.complete_region(authority['effective_config'],r) for r in m.QUEUE if r!='NO_3'} if deep else {}
    census=system.processes() if deep else [];conflicts=m.numerical_conflicts(authority,census)
    own=system.own_admin_cpu()
    return dict(check_wall_seconds=time.monotonic()-begin,own=own,boundary=state,
        previous_waiter_drained=previous['drained'],completed_region_probes=closeouts,
        numerical_census_size=len(census),numerical_conflicts=len(conflicts))


def private_owner(root,unit):
    m=api();root=Path(root).resolve();identity=root.name.removeprefix('pricefm-r154-cz-probe-')
    if root!=Path('/tmp')/('pricefm-r154-cz-probe-'+identity) or not re.fullmatch('[a-f0-9]{32}',identity):
        raise RuntimeError('private owner namespace differs')
    system=m.System();props=system.unit(unit);process=system.process(os.getpid())
    expected=[str(m.PYTHON),'-B',str(ENTRY),'private-owner','--private-root',str(root),'--unit',unit]
    if (process is None or process.get('argv')!=expected or process.get('cwd')!=str(ROOT)
            or process.get('cpus')!=[29] or int(props.get('MainPID',0))!=os.getpid()
            or props.get('Restart')!='no' or props.get('KillMode')!='process'
            or props.get('CPUAccounting')!='yes' or not props.get('InvocationID')
            or props.get('ControlGroup') not in process.get('cgroups',[])
            or m.systemd_seconds(props.get('RuntimeMaxUSec',''))!=420
            or unit!='pricefm-r154-cz-probe-'+identity+'.service'):
        raise RuntimeError('private unit exact source/lifetime/policy differs')
    m.immutable(root/'ready.json',dict(unit=unit,properties=props,process=process,entry_sha256=m.sha(ENTRY)))
    until=time.monotonic()+15
    while not (root/'ack.json').exists():
        if time.monotonic()>=until:raise RuntimeError('private parent failed to attest owner')
        system.sleep(.025)
    path=root/'authority.json';authority=m.read(path);samples=[]
    for index in range(6):
        sample=profile_check(authority,path,system,deep=index==0);sample['deep_cold_probe']=index==0;sample['epoch']=system.now();samples.append(sample)
        m.immutable(root/('profile_%02d.json'%index),sample)
        if index<5:system.sleep(60)
    own=system.own_admin_cpu()
    m.immutable(root/'exiting.json',dict(epoch=system.now(),own=own,sample_count=len(samples),
        models_dispatched=0,production_unit_actions=0,all_admin_children_reaped=True))
    return dict(status='PRIVATE_CONTROL_PROFILE_FINISHED',model_dispatches=0)


def pidfd_open(pid):
    if callable(getattr(os,'pidfd_open',None)):return os.pidfd_open(pid,0)
    if platform.machine()!='x86_64':raise RuntimeError('no verified pidfd syscall adapter for this architecture')
    libc=ctypes.CDLL(None,use_errno=True);fd=libc.syscall(434,int(pid),0)
    if fd<0:raise OSError(ctypes.get_errno(),'pidfd_open syscall unavailable or denied')
    return fd


def pidfd_send(fd,number):
    if callable(getattr(signal,'pidfd_send_signal',None)):
        return signal.pidfd_send_signal(fd,number,None,0)
    if platform.machine()!='x86_64':raise RuntimeError('no verified pidfd signal adapter for this architecture')
    libc=ctypes.CDLL(None,use_errno=True);result=libc.syscall(424,int(fd),int(number),ctypes.c_void_p(),0)
    if result<0:raise OSError(ctypes.get_errno(),'pidfd_send_signal syscall unavailable or denied')


def exact_pidfd_term(system,expected):
    """Signal only an attested administrative lifetime, never a shared group."""
    m=api()
    fd=pidfd_open(expected['pid'])
    try:
        if not m.exact_process(m.recorded_process(system,expected),expected):
            raise RuntimeError('administrative lifetime changed before pidfd signal')
        if select.select([fd],[],[],0)[0]:
            raise RuntimeError('administrative lifetime exited before signal')
        pidfd_send(fd,signal.SIGTERM)
    finally:os.close(fd)
    return dict(pid=expected['pid'],start_ticks=expected['start_ticks'],boot_id=expected['boot_id'],
        exact_pidfd=True,signal='SIGTERM',models_signalled=False)


def private_fence_owner(root,unit):
    m=api();root=Path(root).resolve();identity=root.name.removeprefix('pricefm-r154-cz-fence-')
    if root!=Path('/tmp')/('pricefm-r154-cz-fence-'+identity) or not re.fullmatch('[a-f0-9]{32}',identity):
        raise RuntimeError('private fence namespace differs')
    system=m.System();props=system.unit(unit);process=system.process(os.getpid())
    argv=[str(m.PYTHON),'-B',str(ENTRY),'private-fence-owner','--private-root',str(root),'--unit',unit]
    if (not process or process.get('argv')!=argv or process.get('cpus')!=[29]
            or props.get('MainPID')!=str(os.getpid()) or props.get('Restart')!='no'
            or props.get('KillMode')!='process' or m.systemd_seconds(props.get('RuntimeMaxUSec',''))!=15
            or props.get('ControlGroup') not in process.get('cgroups',[])):
        raise RuntimeError('private fence exact lifetime differs')
    m.immutable(root/'ready.json',dict(process=process,properties=props,own=system.own_admin_cpu()))
    time.sleep(12)
    raise RuntimeError('private fence parent did not exercise exact stop')


def prove_pidfd_fence(system):
    m=api();identity=uuid.uuid4().hex;root=Path('/tmp')/('pricefm-r154-cz-fence-'+identity);root.mkdir(mode=0o700)
    unit='pricefm-r154-cz-fence-'+identity+'.service';capsule=None;signal_receipt=None;errors=[];drained=False
    argv=[str(m.PYTHON),'-B',str(ENTRY),'private-fence-owner','--private-root',str(root),'--unit',unit]
    try:
        subprocess.run(['systemd-run','--user','--quiet','--unit='+unit,'--property=Restart=no',
            '--property=KillMode=process','--property=CPUAccounting=yes','--property=RuntimeMaxSec=15',
            '--property=CPUAffinity=29','--property=Nice=10','--property=WorkingDirectory='+str(ROOT),*argv],check=True,timeout=30)
        until=time.monotonic()+8
        while not (root/'ready.json').exists():
            if time.monotonic()>=until:raise RuntimeError('private pidfd owner failed readiness')
            time.sleep(.025)
        capsule=m.read(root/'ready.json');props=system.unit(unit)
        if (capsule['process'].get('argv')!=argv or props.get('InvocationID')!=capsule['properties'].get('InvocationID')
                or system.members(props['ControlGroup'])!=[capsule['process']['pid']]):
            raise RuntimeError('private pidfd lifetime/cgroup changed')
        signal_receipt=exact_pidfd_term(system,capsule['process'])
    except BaseException as error:errors.append(repr(error))
    finally:
        until=time.monotonic()+25
        while True:
            props=system.unit(unit)
            groups={props.get('ControlGroup','')}
            if capsule:groups.add(capsule['properties']['ControlGroup'])
            members=[pid for group in groups if group for pid in system.members(group)]
            current=m.recorded_process(system,capsule['process']) if capsule else None
            if (not current and not members and not int(props.get('MainPID',0))
                    and props.get('ActiveState') not in {'active','activating','deactivating'}):
                drained=True;break
            if time.monotonic()>=until:break
            time.sleep(.05)
    result=dict(status='PASS_PRIVATE_EXACT_PIDFD_FENCE_AND_DRAIN' if not errors and drained else 'FAILED_PRIVATE_EXACT_PIDFD_FENCE_AND_DRAIN',
        capsule=capsule,signal=signal_receipt,errors=errors,independent_expiry_seconds=15,
        charged_CPU_reservation_seconds=15.,exact_cleanup=drained,unit=unit,root=str(root),
        model_dispatches=0,production_unit_actions=0)
    m.immutable(root/'proof.json',result);return result


def verify_probe_history(receipt,current):
    m=api();old=receipt.get('execution_source',{});charge=receipt.get('control_CPU_charged_seconds')
    if (receipt.get('status') not in {'PASS_R154_PRIVATE_CONTROL_PROFILE','FAILED_R154_PRIVATE_CONTROL_PROFILE'}
            or old.get('root')!=current['root'] or old.get('branch')!=current['branch']
            or receipt.get('exact_cleanup') is not True or not isinstance(charge,(int,float))
            or not math.isfinite(charge) or charge<0 or receipt.get('model_dispatches')!=0
            or receipt.get('production_unit_actions')!=0):
        raise RuntimeError('private proof scope, cleanup or retained debit differs')
    subprocess.run(['git','-C',str(ROOT),'merge-base','--is-ancestor',old['head'],current['head']],check=True,timeout=30)
    for name,digest in receipt['runtime_source_sha256'].items():
        payload=subprocess.check_output(['git','-C',str(ROOT),'show',old['head']+':'+name],timeout=30)
        if hashlib.sha256(payload).hexdigest()!=digest:raise RuntimeError('private proof source blob differs')
    if set(receipt['runtime_source_sha256'])!={str(p.relative_to(ROOT)) for p in [GATE,ENTRY,OBSERVER]}:
        raise RuntimeError('private proof source inventory differs')
    return float(charge)


def probe(output_path):
    m=api();system=m.System();start=process_CPU();wall=time.monotonic();source=m.source_identity()
    identity=uuid.uuid4().hex;root=Path('/tmp')/('pricefm-r154-cz-probe-'+identity)
    output_path=Path(output_path).resolve()
    if output_path.exists():raise RuntimeError('private receipt already exists; never overwrite an attempt')
    attempt=m.RUNTIME/'private_attempts'/identity
    m.immutable(attempt/'started.json',dict(id=identity,execution_source=source,
        output_path=str(output_path),started_epoch=system.now(),automatic_retry=False))
    unit='pricefm-r154-cz-probe-'+identity+'.service';capsule=None;cleanup=False;launched=False;errors=[];fence_debit=0.
    result=dict(schema_version=1,execution_source=source,private_root=str(root),private_unit=unit,
        runtime_source_sha256={str(p.relative_to(ROOT)):m.sha(p) for p in [GATE,ENTRY,OBSERVER]},
        production_unit_actions=0,model_dispatches=0,source_or_runtime_changes=0)
    try:
        records,pins=source_records(system);preflight=previous_preflight(system)
        authority=make_authority(root,identity,system,preflight,records,pins,private=True)
        result['previous_control_preflight']=preflight
        argv=[str(m.PYTHON),'-B',str(ENTRY),'private-owner','--private-root',str(root),'--unit',unit]
        subprocess.run(['systemd-run','--user','--quiet','--unit='+unit,'--property=Restart=no',
            '--property=KillMode=process','--property=CPUAccounting=yes','--property=RuntimeMaxSec=420',
            '--property=CPUAffinity=29','--property=Nice=10','--property=WorkingDirectory='+str(ROOT),
            *['--setenv='+k+'=1' for k in m.THREADS],*argv],check=True,timeout=30)
        launched=True;until=time.monotonic()+20
        while not (root/'ready.json').exists():
            if time.monotonic()>=until:raise RuntimeError('private owner did not publish source capsule')
            time.sleep(.025)
        capsule=m.read(root/'ready.json');props=system.unit(unit)
        if (not m.exact_process(system.process(capsule['process']['pid']),capsule['process'])
                or capsule['process']['argv']!=argv or capsule['process']['cpus']!=[29]
                or props.get('InvocationID')!=capsule['properties']['InvocationID']
                or capsule['entry_sha256']!=m.sha(ENTRY)):
            raise RuntimeError('private exact source/capsule proof differs')
        m.immutable(root/'ack.json',dict(exact_owner_verified=True))
        until=time.monotonic()+380
        while not (root/'exiting.json').exists():
            if time.monotonic()>=until:raise RuntimeError('private profiling exceeded finite calendar')
            time.sleep(.1)
        exiting=m.read(root/'exiting.json');last_epoch=exiting['epoch'];until=time.monotonic()+15
        while True:
            final=system.unit(unit);current=m.recorded_process(system,capsule['process'])
            members=system.members(capsule['properties']['ControlGroup'])
            if (not current and not members and not int(final.get('MainPID',0))
                    and final.get('ActiveState') not in {'active','activating','deactivating'}):
                cleanup=True;break
            if time.monotonic()>=until:raise RuntimeError('private administrative cgroup failed physical drain')
            time.sleep(.025)
        samples=[m.read(p) for p in sorted(root.glob('profile_*.json'))]
        if len(samples)!=6:raise RuntimeError('private warm profile is incomplete')
        warm=[]
        for a,b in zip(samples,samples[1:]):
            def cpu(v):
                q=v['own'];return q['self_CPU_seconds']+q['reaped_admin_CPU_seconds']+q['admin_measurement_reserve_seconds']
            elapsed=b['epoch']-a['epoch']
            if elapsed<60:raise RuntimeError('private profile did not prove60-second polling')
            warm.append(max(0.,cpu(b)-cpu(a))*3600/elapsed)
        worst=max(s['check_wall_seconds'] for s in samples)
        # Budget an explicit additional 100% check-wall headroom, plus5s
        # publication margin; runtime fails closed if that bound is exceeded.
        pricing=dict(CPU_seconds_per_hour_upper=max(warm),measured_window_rates=warm,
            worst_measured_check_wall_seconds=worst,worst_check_wall_seconds=worst*2+1,
            publication_wall_margin_seconds=5.,poll_seconds=60,sample_count=6,
            future_PT_SE3_closeout_sizes_unmeasured=True)
        if 60+pricing['worst_check_wall_seconds']+5>90:
            raise RuntimeError('measured cold/check/poll freshness price does not fit90seconds')
        own=exiting['own'];owner_cpu=own['self_CPU_seconds']+own['reaped_admin_CPU_seconds']+own['admin_measurement_reserve_seconds']
        tail=max(0.,system.now()-last_epoch)
        result.update(status='PASS_R154_PRIVATE_CONTROL_PROFILE',private_capsule=capsule,
            pricing=pricing,samples=samples,private_owner_final_accounting=own,
            private_owner_CPU_charged_upper_seconds=owner_cpu+tail,
            private_owner_tail_single_CPU_wall_reserve_seconds=tail,
            exact_owner_verified=True,real_cgroup_drain=True,independent_expiry_seconds=420,
            numerical_dispatches=0,observer_CPU_used_for_owner=False)
        fence_debit=15.  # retained even if this private subproof fails
        result['exact_pidfd_fence_proof']=prove_pidfd_fence(system)
        cleanup=cleanup and result['exact_pidfd_fence_proof']['exact_cleanup']
        if result['exact_pidfd_fence_proof']['status']!='PASS_PRIVATE_EXACT_PIDFD_FENCE_AND_DRAIN':
            raise RuntimeError('actual private pidfd fence failed; full15-second debit retained')
    except BaseException as error:
        errors.append(repr(error));result['status']='FAILED_R154_PRIVATE_CONTROL_PROFILE'
    finally:
        if launched and not cleanup:
            props=system.unit(unit)
            if capsule and props.get('InvocationID')==capsule['properties']['InvocationID']:
                current=m.recorded_process(system,capsule['process'])
                if current:result['private_cleanup_signal']=exact_pidfd_term(system,capsule['process'])
            until=time.monotonic()+30
            while True:
                props=system.unit(unit)
                members=system.members(capsule['properties']['ControlGroup']) if capsule else []
                if not int(props.get('MainPID',0)) and props.get('ActiveState') not in {'active','activating','deactivating'} and not members:
                    cleanup=True;break
                if time.monotonic()>=until:break
                time.sleep(.05)
        if not launched:cleanup=True
        cleanup=cleanup and result.get('exact_pidfd_fence_proof',{}).get('exact_cleanup',True)
        owner_debit=result.get('private_owner_CPU_charged_upper_seconds',min(420.,max(0.,time.monotonic()-wall)) if launched else 0.)
        result.update(errors=errors,exact_cleanup=cleanup,control_CPU_charged_seconds=process_CPU()-start+owner_debit+fence_debit+5.,
            private_pidfd_proof_CPU_reservation_seconds=fence_debit,
            parent_actual_self_plus_reaped_admin_CPU_seconds=process_CPU()-start,
            failed_attempts_refunded=False,captured_epoch=system.now())
        output(result,output_path)
        m.immutable(attempt/'finished.json',dict(id=identity,receipt_path=str(output_path),
            receipt_sha256=m.sha(output_path),control_CPU_charged_seconds=result['control_CPU_charged_seconds'],
            exact_cleanup=result['exact_cleanup'],status=result['status'],execution_source=source))
    if result['status']!='PASS_R154_PRIVATE_CONTROL_PROFILE' or not cleanup:
        raise RuntimeError('private proof failed; retained charged receipt: '+str(output_path))
    return result


def prepare(probe_receipts,*,system=None,control_CPU_seconds=None):
    m=api();system=system or m.System();records,pins=source_records(system)
    if not probe_receipts:raise RuntimeError('actual current-source private proof required')
    supplied={str(Path(p).resolve()) for p in probe_receipts}
    if len(supplied)!=len(probe_receipts):raise RuntimeError('duplicate private receipt; each attempt charged exactly once')
    registered=set()
    for folder in sorted((m.RUNTIME/'private_attempts').glob('*')):
        begin=m.read(folder/'started.json')
        if not (folder/'finished.json').exists():raise RuntimeError('unresolved private attempt; no free reset or omitted failure')
        end=m.read(folder/'finished.json');receipt_path=Path(end['receipt_path'])
        if (begin['output_path']!=str(receipt_path) or m.sha(receipt_path)!=end['receipt_sha256']
                or end.get('exact_cleanup') is not True):
            raise RuntimeError('private attempt receipt/cleanup differs')
        registered.add(str(receipt_path.resolve()))
    if supplied!=registered:raise RuntimeError('all registered private attempts, including failures, must be charged')
    rows=[];debit=0.
    for filename in probe_receipts:
        receipt=m.read(filename);debit+=verify_probe_history(receipt,records['execution_source'])
        pins[str(Path(filename).resolve())]=m.sha(filename)
        rows.append(dict(path=str(Path(filename).resolve()),sha256=m.sha(filename),CPU_seconds=receipt['control_CPU_charged_seconds']))
    last=m.read(probe_receipts[-1])
    if last.get('status')!='PASS_R154_PRIVATE_CONTROL_PROFILE' or last['execution_source']!=records['execution_source']:
        raise RuntimeError('latest actual private proof is not current-source successful')
    pricing=last['pricing'];reserve=max(240.,debit)
    needed=pricing['CPU_seconds_per_hour_upper']*168*1.25+reserve+120+90
    selected=3600. if needed<=3600 and pricing['CPU_seconds_per_hour_upper']<=15 else 6400.
    if control_CPU_seconds is not None:selected=float(control_CPU_seconds)
    if selected>6400 or selected<=0 or needed>selected:
        raise RuntimeError('measured complete-window control price exceeds finite selected grant')
    preflight=previous_preflight(system);identity=uuid.uuid4().hex;root=m.RUNTIME/identity
    value=make_authority(root,identity,system,preflight,records,pins,proof_actual=debit,
        pricing=pricing,control_CPU_seconds=selected,proof_rows=rows)
    # A production activation and the old lifetime remain untouched.
    return dict(status='R154_AUTHORITY_PREPARED_NOT_ACTIVATED_OR_FENCED',authority_path=str(root/'authority.json'),
        authority_sha256=m.sha(root/'authority.json'),selected_control_CPU_seconds=selected,
        complete_window_price_CPU_seconds=needed,private_proofs=rows,production_actions=0)


def fence_previous(authority,path,system):
    m=api();root=Path(authority['runtime']);record=authority['previous_waiter']
    m.assert_no_prior_science(authority)
    props=system.unit(record['unit']);current=m.recorded_process(system,record['process'])
    if (not m.exact_process(current,record['process']) or props.get('InvocationID')!=record['invocation_id']
            or props.get('ControlGroup')!=record['cgroup'] or props.get('Restart')!='no'
            or props.get('KillMode')!='process' or int(props.get('MainPID',0))!=record['process']['pid']
            or system.members(record['cgroup'])!=[record['process']['pid']]):
        raise RuntimeError('old waiter is not the exact sole administrative lifetime; no signal')
    oldroot=Path(authority['previous_authority_path']).parent
    archive={name:dict(sha256=m.sha(oldroot/name),value=m.read(oldroot/name)) for name in
             ['progress.json','control_budget_heartbeat.json']}
    m.immutable(root/'previous_state_before_fence.json',dict(files=archive,unit=props,epoch=system.now()))
    m.assert_no_prior_science(authority)
    signal_receipt=exact_pidfd_term(system,record['process'])
    until=time.monotonic()+45
    while True:
        drained=m.previous_waiter_drained(authority,system)
        if drained['drained']:break
        if time.monotonic()>=until:raise RuntimeError('old exact administrative unit/cgroup failed physical drain')
        time.sleep(.05)
    # Old code could have claimed science after the last absence check. Never
    # erase/retry that claim. The caller now checks again under original locks.
    receipt=dict(status='R154_EXACT_OLD_CONTROL_PHYSICALLY_DRAINED',authority_sha256=m.sha(path),
        signal=signal_receipt,drain=drained,epoch=system.now(),models_signalled=False)
    m.immutable(root/'old_waiter_fence.json',receipt)
    return receipt


def start_waiter(authority,path,system):
    m=api();root=Path(authority['runtime']);unit=authority['waiter_unit'];remaining=int(authority['expires_epoch']-system.now())
    if remaining<=90:raise RuntimeError('finite authority expired before launch')
    props=system.unit(unit)
    if int(props.get('MainPID',0)) or props.get('ActiveState') in {'active','activating','deactivating'}:
        raise RuntimeError('new waiter unit already exists')
    argv=[str(m.PYTHON),'-B',str(GATE),'run','--authority',str(path),'--unit',unit]
    m.immutable(root/'launch_claim.json',dict(claim=1,authority_sha256=m.sha(path),unit=unit,
        expected_argv=argv,expected_RuntimeMaxSec=remaining,expected_control_source=authority['execution_source'],epoch=system.now()))
    subprocess.run(['systemd-run','--user','--quiet','--unit='+unit,'--property=Restart=no',
        '--property=KillMode=process','--property=CPUAccounting=yes','--property=RuntimeMaxSec='+str(remaining),
        '--property=WorkingDirectory='+str(ROOT),'--property=CPUAffinity=29','--property=Nice=10',
        *['--setenv='+key+'=1' for key in m.THREADS],*argv],check=True,timeout=30)
    until=time.monotonic()+60
    while not (root/'activation.json').exists():
        if (root/'waiter_blocked.json').exists():raise RuntimeError('new waiter blocked; activation remains spent')
        if time.monotonic()>=until:raise RuntimeError('new waiter activation timed out; no automatic retry')
        time.sleep(.05)
    capsule=m.read(root/'activation.json')['capsule'];props=system.unit(unit)
    if (not m.exact_process(system.process(capsule['process']['pid']),capsule['process'])
            or props.get('InvocationID')!=capsule['properties']['InvocationID']):
        raise RuntimeError('new waiter readiness capsule is no longer its exact lifetime')
    budget=m.observe_waiter_cpu(authority,path,system,capsule)
    if not budget['within_CPU'] or not budget['within_wall']:
        raise RuntimeError('new waiter readiness budget does not fit')
    receipt=dict(status='R154_CZ_SUCCESSOR_READY_WAITING',authority_path=str(path),authority_sha256=m.sha(path),
        capsule=capsule,budget=budget,epoch=system.now(),models_signalled=False)
    m.immutable(root/'launch_receipt.json',receipt)
    m.immutable(m.RUNTIME/'successor.json',receipt)
    return receipt


def handoff_and_launch(path,*,system=None):
    """One reviewed transaction; never hold original supervisor at launch."""
    m=api();system=system or m.System();path=Path(path).resolve()
    authority=m.validate_authority(path,system=system);root=Path(authority['runtime'])
    original=m.DATA/'launch_prep'/authority['effective_config']['tag']/'jerez'
    with m.locked(m.RUNTIME/'handoff.lock'):
        if (m.RUNTIME/'single_activation_claim.json').exists():
            raise RuntimeError('one additional R154 control activation is already spent')
        m.assert_no_prior_science(authority)
        fence_previous(authority,path,system)
        # Old source never consults the new lock: the physical fence MUST
        # precede the original supervisor and cross-lineage final recheck.
        with m.locked(original/'supervisor.lock'),m.locked(m.RUNTIME/'science_dispatch.lock'):
            m.assert_previous_drained(authority,system)
            m.assert_no_prior_science(authority)
            if (m.RUNTIME/'science_dispatch_claim.json').exists():
                raise RuntimeError('global CZ science already claimed; preserve it')
            m.validate_authority(path,system=system)
            state=m.boundary_state(authority,system)
            m.immutable(root/'handoff_receipt.json',dict(status='R154_HANDOFF_FINAL_LOCKED_RECHECK_PASS',
                authority_sha256=m.sha(path),boundary=state,epoch=system.now(),models_signalled=False))
            m.immutable(m.RUNTIME/'single_activation_claim.json',dict(claim=1,id=authority['id'],
                authority_path=str(path),authority_sha256=m.sha(path),epoch=system.now()))
        # Crucial: original supervisor lock is released before the new waiter
        # acquires it to publish its own activation capsule.
        return start_waiter(authority,path,system)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=('preflight','probe','prepare','handoff','private-owner','private-fence-owner'))
    parser.add_argument('--output',type=Path);parser.add_argument('--authority',type=Path)
    parser.add_argument('--probe-receipt',type=Path,action='append',default=[])
    parser.add_argument('--control-CPU-seconds',type=float);parser.add_argument('--private-root',type=Path)
    parser.add_argument('--unit');args=parser.parse_args()
    if args.action=='private-owner':value=private_owner(args.private_root,args.unit)
    elif args.action=='private-fence-owner':value=private_fence_owner(args.private_root,args.unit)
    elif args.action=='probe':
        if not args.output:raise RuntimeError('private probe requires create-once output')
        value=probe(args.output)
    elif args.action=='preflight':value=previous_preflight(api().System())
    elif args.action=='prepare':value=prepare(args.probe_receipt,control_CPU_seconds=args.control_CPU_seconds)
    else:value=handoff_and_launch(args.authority)
    if args.action!='probe':output(value,args.output)
    print(json.dumps(value,indent=2,sort_keys=True,allow_nan=False),flush=True)


if __name__=='__main__':main()
