#!/usr/bin/env python3
"""Release one explicit CZ resource-gate activation; never renew cached work.

Use probe -> prepare -> fence -> launch. Only fence and launch operate on
production control services. The unchanged R144 scientific graph cannot dispatch
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
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
GATE = ENTRY.with_name('515_resolve_pricefm_stage_r153_cz_gate.py')
ORIGINAL_CONTROL_ROOT = ROOT.parent/'pricefm_r153_control_lifecycle_20261025'
ORIGINAL_CONTROL_BRANCH = 'work/pricefm-r153-control-lifecycle-20261025'
APPROVED_HISTORICAL_CONTROL_HEADS = {
    '37799978e6b399f287a9851c8b7cf3242b6b2c82',
    'bfe540920998eeeef398cfa1aad93f8d408ed6ca',
}
_API = None


def api():
    global _API
    if _API is None:
        spec = importlib.util.spec_from_file_location('r153_cz_explicit_resource_gate', GATE)
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
    if not control['branch'].startswith('work/pricefm-r153-control-lifecycle-'):
        raise RuntimeError('dedicated clean R153 control branch is required')
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
    pins = {str(path): m.sha(path) for path in [GATE, ENTRY, m.R144_ENTRY, m.R144_CONFIG,
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


def control_launch_role(process,entry):
    """Recognize only the two observed original argv spellings, truthfully."""
    m=api();entry=Path(entry)
    polls={m.R144_ENTRY:'30',m.R143_ENTRY:'15'}
    if entry not in polls or not entry.is_file() or entry.is_symlink() or entry.resolve()!=entry:
        raise RuntimeError('unapproved or substituted original control script')
    cwd=Path(process.get('cwd',''))
    if cwd!=entry.parents[3] or cwd.is_symlink() or cwd.resolve()!=cwd:
        raise RuntimeError('original control cwd differs from its frozen source')
    argv=process.get('argv',[]);relative=str(entry.relative_to(cwd))
    if (len(argv)!=6 or argv[0]!=str(m.PYTHON) or argv[1]!='-B'
            or argv[2] not in {str(entry),relative} or argv[3]!='run'
            or argv[4]!='--poll-seconds' or argv[5]!=polls[entry]):
        raise RuntimeError('original control argv/action/poll contract differs')
    resolved=(cwd/argv[2]).resolve() if not Path(argv[2]).is_absolute() else Path(argv[2]).resolve()
    if resolved!=entry:raise RuntimeError('original control script resolves outside its frozen source')
    return dict(resolved_entry=str(entry),entry_sha256=m.sha(entry),poll_seconds=int(polls[entry]),
                launch_spelling='absolute' if Path(argv[2]).is_absolute() else 'canonical_relative',
                actual_argv=list(argv),actual_cwd=process['cwd'])


def control_snapshot(system, unit, entry):
    props=system.unit(unit);pid=int(props.get('MainPID',0));process=system.process(pid) if pid else None
    if (not process or process.get('pid')!=pid or props.get('Id')!=unit
            or props.get('ActiveState')!='active' or not props.get('InvocationID')
            or not props.get('ControlGroup') or props['ControlGroup'] not in process.get('cgroups',[])):
        raise RuntimeError('expected original control owner is not live/attestable: '+unit)
    role=control_launch_role(process,entry)
    return dict(unit=unit,properties=props,invocation_id=props['InvocationID'],process=process,
                cgroup=props['ControlGroup'],launch_role=role)


def legacy_control_preflight(system):
    """Actual read-only execution of both preparation snapshot predicates."""
    m=api()
    if system.host()!='jerez':raise RuntimeError('original CZ control preflight requires Jerez')
    sources,pins=source_records(system)
    waiter=control_snapshot(system,m.OLD_WAITER_UNIT,m.R144_ENTRY)
    predecessor=control_snapshot(system,m.R143_UNIT,m.R143_ENTRY)
    members=system.members(waiter['cgroup'])
    if members!=[waiter['process']['pid']]:
        raise RuntimeError('original R144 control preflight found non-waiter children')
    return dict(status='PASS_R153_CZ_LEGACY_CONTROL_PREFLIGHT',sources=sources,
                frozen_source_sha256=pins,old_waiter=waiter,predecessor=predecessor,
                production_service_actions=0,model_dispatches=0,runtime_writes=0)


def latest_private_proof(receipt,current):
    preflight=receipt.get('legacy_control_preflight',{})
    if (receipt.get('status')!='PASS_R153_CZ_PRIVATE_CONTROL_LIFECYCLE'
            or receipt.get('execution_source')!=current
            or preflight.get('status')!='PASS_R153_CZ_LEGACY_CONTROL_PREFLIGHT'
            or preflight.get('sources',{}).get('execution_source')!=current):
        raise RuntimeError('last private proof/preflight does not match current control source')
    return receipt


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



def verify_probe_history(receipt,current,root=None):
    """Charge all safe ancestor proofs, but never refund a changed source."""
    root=Path(root or ROOT);prior=receipt.get('execution_source',{})
    charge=receipt.get('control_CPU_charged_seconds')
    same_root=(prior.get('root')==current.get('root') and prior.get('branch')==current.get('branch'))
    bridged_history=(prior.get('root')==str(ORIGINAL_CONTROL_ROOT)
        and prior.get('branch')==ORIGINAL_CONTROL_BRANCH
        and prior.get('head') in APPROVED_HISTORICAL_CONTROL_HEADS)

    if (receipt.get('status') not in {'PASS_R153_CZ_PRIVATE_CONTROL_LIFECYCLE','FAILED_R153_CZ_PRIVATE_CONTROL_LIFECYCLE'}
            or receipt.get('exact_cleanup') is not True or not isinstance(charge,(int,float))
            or not math.isfinite(charge) or charge<5
            or receipt.get('production_unit_actions')!=0 or receipt.get('model_dispatches')!=0
            or receipt.get('source_or_runtime_changes')!=0
            or not (same_root or bridged_history)
            or not re.fullmatch('[a-f0-9]{40}',str(prior.get('head','')))):
        raise RuntimeError('private probe history/cleanup/cost scope differs')
    ancestor=subprocess.run(['git','-C',str(root),'merge-base','--is-ancestor',prior['head'],current['head']],
                            capture_output=True,text=True,timeout=30)
    if ancestor.returncode:raise RuntimeError('prior private probe source is not a committed ancestor')
    expected_files=['application/scripts/pricefm/515_resolve_pricefm_stage_r153_cz_gate.py',
                    'application/scripts/pricefm/516_release_pricefm_stage_r153_cz_gate.py']
    actual=receipt.get('runtime_source_sha256',{})
    if set(actual)!=set(expected_files):raise RuntimeError('private probe source payload inventory differs')
    for relative in expected_files:
        payload=subprocess.check_output(['git','-C',str(root),'show',prior['head']+':'+relative],timeout=30)
        if hashlib.sha256(payload).hexdigest()!=actual[relative]:
            raise RuntimeError('private probe runtime bytes differ from committed ancestor')
    return float(charge)


def prepare(*, probe_receipts, system=None, wait_seconds=7*86400, control_CPU_seconds=1800):
    m = api(); system = system or m.System(); started = process_CPU()
    if system.host() != 'jerez': raise RuntimeError('CZ authority preparation requires actual Jerez host')
    if not 0 < wait_seconds <= 7*86400 or not 0 < control_CPU_seconds <= 1800:
        raise RuntimeError('CZ finite wait/control grant differs')
    records, pins = source_records(system)
    if not probe_receipts: raise RuntimeError('committed-source private lifecycle proof is required')
    probe_debit = 0.; probe_rows = []
    for filename in probe_receipts:
        path = Path(filename).resolve(); receipt = m.read(path)
        probe_debit += verify_probe_history(receipt,records['execution_source'])
        probe_rows.append(dict(path=str(path), sha256=m.sha(path), status=receipt['status'],
                               charged_CPU_seconds=receipt['control_CPU_charged_seconds']))
        pins[str(path)] = m.sha(path)
    last = m.read(probe_receipts[-1])
    latest_private_proof(last,records['execution_source'])
    config = m.read(m.R144_CONFIG); effective = m.effective_config(config)
    original = m.DATA/'launch_prep'/config['tag']/'jerez'
    if (m.DATA/'launch_prep'/config['tag']/'preparation.json').exists() or any((m.DATA/'campaigns'/config['tag']/'tasks').glob('*.json')):
        raise RuntimeError('CZ fallback already has numerical preparation; cannot grant another one-shot gate')
    waiter = control_snapshot(system, m.OLD_WAITER_UNIT, m.R144_ENTRY)
    # The old waiting service may be stopped only while it owns no numerical child.
    members = system.members(waiter['cgroup'])
    if members != [waiter['process']['pid']]:
        raise RuntimeError('old R144 waiter has unclassified or numerical cgroup children')
    prior = control_snapshot(system, m.R143_UNIT, m.R143_ENTRY)
    progress = m.read(m.DATA/'launch_prep'/config['predecessor_tag']/'jerez/progress.json')
    failures = progress.get('failures', [])
    if len(failures) != 1 or failures[0].get('region') != 'NO_3':
        raise RuntimeError('only the known NO3 quarantine can be resolved by this release')
    no3_pins = no3_failure_pins(config)
    identity = uuid.uuid4().hex; root = m.RUNTIME/identity
    root.mkdir(parents=True, exist_ok=False)
    old_progress = original/'progress.json'; archived = root/'original_waiter_progress.json'
    data = old_progress.read_bytes(); archived.write_bytes(data)
    m.immutable(root/'effective_config.json', effective)
    created=system.now()
    authority = dict(schema_version=1, kind='R153_CZ_RESOURCE_RESOLUTION', id=identity,
        runtime=str(root), created_epoch=created, expires_epoch=created+wait_seconds,
        control_CPU_allowance_seconds=control_CPU_seconds, activation_limit=1, scientific_dispatch_limit=1,
        waiter_unit='pricefm-r153-cz-gate-'+identity+'.service',
        science_unit='pricefm-r153-cz-science-'+identity+'.service',
        waiter_control_cpu=29,budget_heartbeat_max_age_seconds=90,final_publication_CPU_reserve_seconds=90,
        resource_only=True, cached_restart_authorized=False, fit_cap_changes=0,
        certificate_limit_changes=0, scientific_source_changes=0,
        approved_quarantined_regions=['NO_3'], predecessor_queue=m.QUEUE,
        approved_predecessor_failures=failures, approved_NO3_evidence_sha256=no3_pins,
        science_config_path=str(m.R144_CONFIG), science_config_sha256=m.sha(m.R144_CONFIG),
        effective_config=effective, effective_config_sha256=m.sha(root/'effective_config.json'),
        old_waiter=waiter, predecessor=prior, frozen_sha256=pins,
        archived_original_waiter_progress=dict(source=str(old_progress), archive=str(archived), sha256=hashlib.sha256(data).hexdigest()),
        private_probe_receipts=probe_rows, prior_control_CPU_charged_seconds=probe_debit+120.,
        administrative_release_CPU_reservation_seconds=120.,
        current_release_observed_CPU_seconds=process_CPU()-started+5.,
        authority_basis='User explicitly requested implementation of the reviewed Oct25 plan; one new baseline-only CZ resource-gate activation, preserving prior failed history.',
        scientific_scope='Original R144 predetermined training-only rank3 CZ fallback; original300 iteration cap and15 CPUs; no new grid or cached admission.',
        **records)
    if authority['prior_control_CPU_charged_seconds'] + 60 >= control_CPU_seconds:
        raise RuntimeError('private proofs/release reserve leave no finite waiter allowance')
    m.immutable(root/'authority.json', authority)
    m.validate_authority(root/'authority.json', system=system)
    return dict(status='R153_CZ_AUTHORITY_PREPARED_NOT_FENCED_OR_LAUNCHED', authority_path=str(root/'authority.json'),
                authority_sha256=m.sha(root/'authority.json'), waiter_unit=authority['waiter_unit'],
                science_unit=authority['science_unit'], wait_seconds=wait_seconds,
                control_CPU_allowance_seconds=control_CPU_seconds, original_waiter_still_live=True,
                model_dispatches=0, numerical_source_changes=0)


def fence(path, *, system=None):
    m=api(); system=system or m.System(); authority=m.validate_authority(path, system=system)
    root=Path(authority['runtime']); record=authority['old_waiter']; started=process_CPU()
    if (root/'activation.json').exists() or (root/'old_waiter_fence.json').exists():
        raise RuntimeError('CZ old-waiter fence is already spent or new waiter activated')
    # Exact old command/cgroup/InvocationID, sole process, and source-bound NO3
    # quarantine prove the old clean-gated waiter cannot race into numerical work.
    props=system.unit(record['unit']); current=m.recorded_process(system,record['process'])
    active=props.get('ActiveState') in {'active','activating','deactivating'} or int(props.get('MainPID',0))
    stopped=False
    if active:
        if (props.get('InvocationID')!=record['invocation_id']
                or not m.exact_process(current,record['process'])
                or props.get('ControlGroup')!=record['cgroup']
                or system.members(record['cgroup'])!=[record['process']['pid']]):
            raise RuntimeError('old R144 waiter is not its exact sole control lifetime')
        old_progress=m.read(m.DATA/'launch_prep'/authority['effective_config']['tag']/'jerez/progress.json')
        if old_progress.get('status') not in {'R144_WAITING_FOR_R143_SLOT_B','R144_WAITING_FOR_SLOT_B_PROCESS_EXIT'}:
            raise RuntimeError('old R144 process is no longer an idle resource waiter')
        original_progress=m.DATA/'launch_prep'/authority['effective_config']['tag']/'jerez/progress.json'
        exact_progress=original_progress.read_bytes()
        with (root/'old_waiter_progress_at_fence.json').open('xb') as stream:
            stream.write(exact_progress);stream.flush();os.fsync(stream.fileno())
        predecessor=m.read(m.DATA/'launch_prep'/authority['effective_config']['predecessor_tag']/'jerez/progress.json')
        m.quarantine_matches(authority,predecessor)
        subprocess.run(['systemctl','--user','stop',record['unit']],check=True,timeout=45)
        stopped=True
    result=m.old_waiter_drained(authority,system)
    if not result['drained']:raise RuntimeError('old R144 control waiter did not fully drain')
    receipt=dict(status='R153_OLD_CZ_WAITER_EXACT_CONTROL_FENCE_PASS',authority_sha256=m.sha(path),
        before=props,after=result,unit_stop_performed=stopped,models_signalled=False,
        original_waiter_progress_archive=authority['archived_original_waiter_progress'],
        control_CPU_observed_plus_five=process_CPU()-started+5.,epoch=system.now())
    m.immutable(root/'old_waiter_fence.json',receipt)
    return receipt


def launch(path, *, system=None):
    m=api(); system=system or m.System(); path=Path(path).resolve(); authority=m.validate_authority(path,system=system)
    root=Path(authority['runtime']); started=process_CPU()
    if not (root/'old_waiter_fence.json').is_file() or m.read(root/'old_waiter_fence.json')['authority_sha256']!=m.sha(path):
        raise RuntimeError('CZ waiter launch lacks exact old-control fence proof')
    if (root/'activation.json').exists() or (root/'launch_claim.json').exists():
        raise RuntimeError('CZ gate activation is already spent; no automatic retry')
    if not m.old_waiter_drained(authority,system)['drained']:raise RuntimeError('old waiter reappeared before launch')
    remaining=math_floor(authority['expires_epoch']-system.now())
    if remaining<=60:raise RuntimeError('CZ finite authority has insufficient launch time')
    unit=authority['waiter_unit']; props=system.unit(unit)
    if props.get('ActiveState') not in {None,'inactive','failed'} or int(props.get('MainPID',0)):
        raise RuntimeError('new CZ waiter unit already exists/live')
    argv=[str(m.PYTHON),'-B',str(m.ENTRY),'run','--authority',str(path),'--unit',unit]
    command=['systemd-run','--user','--quiet','--unit='+unit,'--property=Restart=no',
             '--property=KillMode=process','--property=CPUAccounting=yes',
             '--property=RuntimeMaxSec='+str(remaining),'--property=WorkingDirectory='+str(ROOT),
             '--property=CPUAffinity='+str(authority['waiter_control_cpu']),'--property=Nice=10',
             *['--setenv='+key+'=1' for key in m.THREADS],*argv]
    m.immutable(m.RUNTIME/'single_activation_claim.json',dict(claim=1,id=authority['id'],
        authority_path=str(path),authority_sha256=m.sha(path),epoch=system.now()))
    m.immutable(root/'launch_claim.json',dict(claim=1,authority_sha256=m.sha(path),unit=unit,
        expected_argv=argv,expected_RuntimeMaxSec=remaining,expected_control_source=authority['execution_source'],epoch=system.now()))
    subprocess.run(command,check=True,timeout=30)
    deadline=time.monotonic()+60
    while not (root/'activation.json').is_file():
        if (root/'waiter_blocked.json').exists():raise RuntimeError('new CZ waiter blocked; activation remains spent')
        if time.monotonic()>=deadline:raise RuntimeError('CZ waiter did not publish bounded activation proof')
        time.sleep(.05)
    capsule=m.read(root/'activation.json')['capsule']; current=system.process(capsule['process']['pid'])
    if not m.exact_process(current,capsule['process']):
        raise RuntimeError('CZ waiter published proof but its exact lifetime is not live')
    props=system.unit(unit)
    if props.get('InvocationID')!=capsule['properties']['InvocationID'] or props.get('Restart')!='no':
        raise RuntimeError('CZ live waiter unit/source invocation differs')
    result=dict(status='R153_CZ_WAITER_ACTIVATED_WAITING_FOR_FROZEN_BOUNDARY',authority_path=str(path),
        authority_sha256=m.sha(path),capsule=capsule,boundary=m.boundary_state(authority,system),
        control_CPU_observed_plus_five=process_CPU()-started+5.,production_model_signals=0,
        source_changes=0,science_dispatched=(root/'science_claim.json').exists(),epoch=system.now())
    m.immutable(root/'launch_receipt.json',result);return result


def math_floor(value):return int(value//1)


def private_owner(root,unit):
    m=api();root=Path(root).resolve()
    if not root.name.startswith('pricefm-r153-cz-probe-') or root.parent!=Path('/tmp'):
        raise RuntimeError('private owner namespace is not a unique temporary probe')
    system=m.System();props=system.unit(unit);process=system.process(os.getpid())
    if (not process or int(props.get('MainPID',0))!=os.getpid() or props.get('Restart')!='no'
            or props.get('KillMode')!='process' or props.get('CPUAccounting')!='yes'
            or not props.get('InvocationID') or props.get('ControlGroup') not in process['cgroups']
            or m.systemd_seconds(props.get('RuntimeMaxUSec',''))!=15
            or unit!='pricefm-r153-cz-probe-'+root.name.rsplit('-',1)[-1]+'.service'):
        raise RuntimeError('private CZ unit identity differs')
    own=system.own_admin_cpu()
    m.immutable(root/'ready.json',dict(unit=unit,properties=props,process=process,own_control_CPU=own,entry_sha256=m.sha(ENTRY),
                                    production_units=0,model_dispatches=0))
    until=time.monotonic()+5
    while not (root/'ack.json').exists():
        if time.monotonic()>=until:raise RuntimeError('private parent did not acknowledge exact owner')
        time.sleep(.025)
    m.immutable(root/'exiting.json',dict(epoch=system.now(),model_dispatches=0))
    return dict(status='PRIVATE_CZ_OWNER_EXITED',model_dispatches=0)


def probe(*,output_path,system=None):
    m=api();system=system or m.System();source=m.source_identity();started=process_CPU();wall=time.monotonic()
    identity=uuid.uuid4().hex;root=Path('/tmp')/('pricefm-r153-cz-probe-'+identity);root.mkdir(mode=0o700)
    unit='pricefm-r153-cz-probe-'+identity+'.service';props=None;capsule=None;errors=[];cleanup=False;argv=None
    result=dict(schema_version=1,execution_source=source,
                runtime_source_sha256={str(path.relative_to(ROOT)):m.sha(path) for path in [GATE,ENTRY]},
                private_root=str(root),private_unit=unit,
                production_unit_actions=0,model_dispatches=0,source_or_runtime_changes=0)
    try:
        result['legacy_control_preflight']=legacy_control_preflight(system)
        cpu=min(os.sched_getaffinity(0));argv=[str(m.PYTHON),'-B',str(ENTRY),'private-owner',
                    '--private-root',str(root),'--unit',unit]
        subprocess.run(['systemd-run','--user','--quiet','--unit='+unit,'--property=Restart=no',
            '--property=KillMode=process','--property=CPUAccounting=yes','--property=RuntimeMaxSec=15',
            '--property=CPUAffinity='+str(cpu),'--property=WorkingDirectory='+str(ROOT),*argv],
            check=True,timeout=30)
        until=time.monotonic()+10
        while not (root/'ready.json').is_file():
            if time.monotonic()>=until:raise RuntimeError('private source-bound owner did not become ready')
            time.sleep(.025)
        capsule=m.read(root/'ready.json');props=system.unit(unit)
        if (props.get('InvocationID')!=capsule['properties']['InvocationID']
                or not m.exact_process(system.process(capsule['process']['pid']),capsule['process'])
                or capsule['entry_sha256']!=m.sha(ENTRY) or capsule['process']['cpus']!=[cpu]):
            raise RuntimeError('private owner identity/source proof differs')
        own=capsule.get('own_control_CPU',{})
        if (not m.exact_process(own.get('process'),capsule['process'])
                or m.finite_cpu(own.get('self_CPU_seconds'),'private self CPU')<=0
                or m.finite_cpu(own.get('self_CPU_seconds'),'private self CPU')+2*own['proc_CPU']['tick_seconds']<own['proc_CPU']['self_CPU_seconds']
                or m.finite_cpu(own.get('reaped_admin_CPU_seconds'),'private admin CPU')+2*own['proc_CPU']['tick_seconds']<own['proc_CPU']['reaped_child_CPU_seconds']):
            raise RuntimeError('private measured self/admin CPU witness differs')
        m.immutable(root/'ack.json',dict(exact_owner_verified=True,measured_CPU_verified=True))
        until=time.monotonic()+10
        while True:
            final=system.unit(unit);current=system.process(capsule['process']['pid'])
            members=system.members(capsule['properties']['ControlGroup'])
            if (not m.same_lifetime(current,capsule['process']) and not members
                    and not int(final.get('MainPID',0))
                    and final.get('ActiveState') not in {'active','activating','deactivating'}):
                cleanup=True;break
            if time.monotonic()>=until:raise RuntimeError('private owner did not fully drain')
            time.sleep(.025)
        if not (root/'exiting.json').is_file():raise RuntimeError('private owner did not record cooperative exit')
        result.update(status='PASS_R153_CZ_PRIVATE_CONTROL_LIFECYCLE',private_capsule=capsule,
            exact_owner_verified=True,independent_systemd_expiry=True,create_once_claim=True,
            real_cgroup_drain=True,numerical_dispatches=0,
            control_CPU_accounting_basis='measured_self_plus_reaped_admin_children',
            native_unit_CPU_available=m.native_cpu_seconds(props) is not None,
            private_owner_measured_CPU=own)
    except BaseException as error:
        errors.append(repr(error));result['status']='FAILED_R153_CZ_PRIVATE_CONTROL_LIFECYCLE'
    finally:
        if not cleanup:
            current_props=system.unit(unit)
            if capsule is None and int(current_props.get('MainPID',0)):
                candidate=system.process(int(current_props['MainPID']))
                if (argv is not None and candidate and candidate.get('argv')==argv
                        and current_props.get('Id')==unit and current_props.get('InvocationID')
                        and current_props.get('ControlGroup') in candidate.get('cgroups',[])):
                    capsule=dict(properties=current_props,process=candidate)
            if (capsule and current_props.get('InvocationID')==capsule['properties']['InvocationID']
                    and m.exact_process(system.process(capsule['process']['pid']),capsule['process'])):
                subprocess.run(['systemctl','--user','stop',unit],check=True,timeout=30)
            final=system.unit(unit)
            cleanup=(not int(final.get('MainPID',0)) and final.get('ActiveState') not in {'active','activating','deactivating'}
                     and (not capsule or not system.members(capsule['properties']['ControlGroup']))
                     and (not capsule or not m.same_lifetime(system.process(capsule['process']['pid']),capsule['process'])))
        # The private owner is confined to one CPU with a 15-second independent
        # timer. Reserve that entire lifetime, including failed probes; no refund.
        result.update(errors=errors,exact_cleanup=cleanup,
            private_unit_CPU_reservation_seconds=15.,
            control_CPU_charged_seconds=process_CPU()-started+15.+5.,
            captured_epoch=system.now())
        output(result,output_path)
    if result['status']!='PASS_R153_CZ_PRIVATE_CONTROL_LIFECYCLE' or not cleanup:
        raise RuntimeError('private CZ proof failed; receipt and full debit preserved at '+str(output_path))
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=('probe','prepare','inspect','fence','launch','private-owner'))
    parser.add_argument('--authority',type=Path);parser.add_argument('--output',type=Path)
    parser.add_argument('--probe-receipt',type=Path,action='append',default=[])
    parser.add_argument('--wait-seconds',type=int,default=7*86400)
    parser.add_argument('--control-CPU-seconds',type=float,default=1800)
    parser.add_argument('--private-root',type=Path);parser.add_argument('--unit')
    args=parser.parse_args();m=api()
    if args.action=='private-owner':value=private_owner(args.private_root,args.unit)
    elif args.action=='probe':
        if not args.output:raise RuntimeError('private probe requires unique --output receipt')
        value=probe(output_path=args.output)
    elif args.action=='prepare':value=prepare(probe_receipts=args.probe_receipt,
                    wait_seconds=args.wait_seconds,control_CPU_seconds=args.control_CPU_seconds)
    elif args.action=='inspect':
        system=m.System();authority=m.validate_authority(args.authority,system=system)
        value=dict(authority_path=str(args.authority),old_waiter=m.old_waiter_drained(authority,system),
                   boundary=m.boundary_state(authority,system),model_dispatches=0)
    elif args.action=='fence':value=fence(args.authority)
    else:value=launch(args.authority)
    if args.action!='probe':output(value,args.output)
    print(json.dumps(value,indent=2,sort_keys=True),flush=True)

if __name__=='__main__':main()
