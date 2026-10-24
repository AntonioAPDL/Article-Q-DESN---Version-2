#!/usr/bin/env python3
"""Archive and authorize one source-declared baseline owner adoption.

Only mutable current baseline state/config pointers move. Original scope,
scientific sources, live controller sessions and numerical affinities stay
unchanged. This module never stops the old baseline unit or its children.
"""
from __future__ import annotations
import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

ROOT=Path(__file__).resolve().parents[3]
ENTRY=Path(__file__).resolve()
OWNER=ENTRY.with_name('511_recover_pricefm_stage_r152_baseline_owner.py')
OLD_ROOT=ROOT.parent/'pricefm_r152_parallel_20261024'
OLD_ENTRY=OLD_ROOT/'application/scripts/pricefm/504_supervise_pricefm_stage_r152_baseline.py'
SHARED=Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/launch_prep/pricefm_stage_r152_parallel_20261024')
RUNTIME=SHARED/'baseline'
THREADS=('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS','BLIS_NUM_THREADS','NUMEXPR_NUM_THREADS','VECLIB_MAXIMUM_THREADS')
_MODULES={}


def module(name,path):
    if name not in _MODULES:
        spec=importlib.util.spec_from_file_location(name,path)
        value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);_MODULES[name]=value
        if any(key in sys.modules for key in ('numpy','scipy','pandas')):raise RuntimeError('baseline release imported numerical libraries')
    return _MODULES[name]
def release_api():return module('r152_baseline_recovery_release',ENTRY.with_name('510_release_pricefm_stage_r152_parent_recovery.py'))
def pool():return release_api().api()
def core():return pool().baseline()
def adapter():return module('r152_baseline_recovery_adapter',OWNER)
def read(path):return json.loads(Path(path).read_text())
def digest(path):return release_api().digest(path)
def immutable(path,value):return release_api().immutable(path,value)


def immutable_bytes(path,data):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_name('.'+path.name+'.'+uuid.uuid4().hex+'.tmp')
    try:
        with temporary.open('xb') as stream:stream.write(data);stream.flush();os.fsync(stream.fileno())
        os.link(temporary,path)
    finally:temporary.unlink(missing_ok=True)
    fd=os.open(str(path.parent),os.O_RDONLY)
    try:os.fsync(fd)
    finally:os.close(fd)


class System:
    """Robust baseline process shape plus complete unit-policy observations."""
    def __init__(self):
        self.process_api=adapter().RecoverySystem();self.unit_api=pool().System();self.boot_id=self.process_api.boot_id
    def __getattr__(self,name):return getattr(self.process_api,name)
    def unit(self,name):return self.unit_api.unit(name)
    def members(self,cgroup):
        # Inactive/unloaded control units legitimately expose no current path.
        if not cgroup:return []
        return self.unit_api.members(cgroup)
    def uid(self,pid):return (Path('/proc')/str(pid)).stat().st_uid
    def control_process(self,pid):
        value=pool().legacy().process(pid)
        if value is not None:value=dict(value,cwd=os.readlink(Path('/proc')/str(pid)/'cwd'))
        return value
    def start_control(self,intent,stdout):
        unit=intent['unit']
        if not re.fullmatch(r'pricefm-r152-muscat-baseline-[a-f0-9]{32}\.service',unit):raise RuntimeError('unreviewed baseline owner unit')
        command=['systemd-run','--user','--quiet','--unit='+unit,'--description='+intent['description'],
            '--property=Restart=on-failure','--property=RestartSec=5s','--property=StartLimitBurst=3',
            '--property=StartLimitIntervalSec=300s','--property=KillMode=process','--property=TimeoutStopSec=20s',
            '--property=WorkingDirectory='+str(OLD_ROOT),'--property=CPUAffinity=0-29',
            '--property=CPUSchedulingPolicy=other','--property=IOSchedulingClass=idle',
            '--property=CPUAccounting=yes','--property=MemoryAccounting=yes',
            '--property=StandardOutput=file:'+str(stdout),'--property=StandardError=file:'+str(stdout)+'.stderr']
        command+=['--setenv='+key+'=1' for key in THREADS]+['--setenv=PYTHONDONTWRITEBYTECODE=1']+intent['argv']
        subprocess.run(command,check=True,timeout=30)
    def stop_owner(self,intent):
        verify_control(self,intent)
        # KillMode=process preserves original and newly adopted model sessions.
        subprocess.run(['systemctl','--user','stop',intent['unit']],check=True,timeout=30)


def cached_empty():
    development=SHARED/'development'
    names=list(development.glob('admissions/*/*/lease.json'))+list(development.glob('attempts/*/*/ownership.json'))+list(development.glob('slots/*/claim.json'))
    names += [development/name for name in ('controller.json','guardian.json','terminal.json') if (development/name).exists()]
    if names:raise RuntimeError('baseline adoption requires no cached admissions or controller registrations')
    return dict(admissions=[],attempts=[],slots=[],controller_absent=True,guardian_absent=True,terminal_absent=True)


def master_context(original=None,allow_expired=False):
    master,identity=release_api().original_master(original,allow_expired)
    if master.get('baseline_runtime')!=str(RUNTIME):raise RuntimeError('original baseline runtime differs')
    return master,identity


def archived(authority,name):
    record=authority['snapshots'][name];path=Path(record['archive_path'])
    if digest(path)!=record['sha256']:raise RuntimeError('baseline predecessor snapshot changed: '+name)
    return read(path)


def sessions(state,system):
    result={};covered=set()
    for lane,job in state.get('active',{}).items():
        snapshot=copy.deepcopy(job);rows=core().session_members(snapshot,system)
        for process in rows:
            if hasattr(system,'uid') and system.uid(process['pid'])!=os.getuid():raise RuntimeError('baseline session contains a foreign UID')
        covered.update(row['pid'] for row in rows)
        result[lane]=dict(region=job['region'],phase=job['phase'],session_id=job['session_id'],cpus=job['cpus'],
            root=job.get('process'),observed_children=job.get('observed_children',[]),live_members=rows)
    return result,covered


def predecessor_proof(state,epoch,master,system):
    if (state.get('phase')!='blocked' or epoch.get('phase')!='blocked' or epoch.get('generation')!=1
        or epoch.get('scope_id')!=state.get('scope_id') or state.get('scope_id')!=master['scope_id']
        or epoch.get('source')!=state.get('source') or state['source']['head']!=master['source']['head']
        or epoch.get('expires_epoch')!=master['expires_epoch'] or state.get('master_sha256')!=digest(SHARED/'master.json')):
        raise RuntimeError('baseline predecessor is not the original blocked generation one')
    if digest(state['config_path'])!=state['config_sha256']:
        raise RuntimeError('original baseline configuration bytes differ from its recorded identity')
    owner=epoch['owner'];current=system.process(owner['pid']);props=system.unit(state['new_unit'])
    if int(props.get('MainPID',0)) or props.get('ActiveState') in {'active','activating'} or core().same_process(current,owner):
        raise RuntimeError('original baseline owner is still live')
    if props.get('KillMode')!='process' or props.get('WorkingDirectory')!=str(OLD_ROOT) or str(OLD_ENTRY) not in props.get('ExecStart',''):
        raise RuntimeError('original baseline service identity differs')
    candidates=set(value for value in owner.get('cgroups',[]) if value.endswith('/'+state['new_unit']))
    group=props.get('ControlGroup') or (next(iter(candidates)) if len(candidates)==1 else None)
    if not group or not group.startswith('/user.slice/'):raise RuntimeError('original baseline group identity unavailable')
    live_sessions,covered=sessions(state,system)
    remaining=[]
    for pid in system.members(group):
        process=system.process(pid)
        if process is None:continue
        if pid not in covered:raise RuntimeError('old baseline group has an unclassified live member')
        remaining.append(pid)
    guardian=epoch['guardian_unit'];guardian_props=system.unit(guardian)
    guardian_group=str(Path(group).parent/guardian)
    if (int(guardian_props.get('MainPID',0)) or guardian_props.get('ActiveState') in {'active','activating'}
        or system.members(guardian_group) or system.members(guardian_props.get('ControlGroup',''))):
        raise RuntimeError('old baseline guardian is still live')
    for process in system.processes():
        argv=process.get('argv',[])
        if str(OLD_ENTRY) in argv and 'guard' in argv and str(RUNTIME) in argv and state['attempt'] in argv:
            raise RuntimeError('old baseline guardian process remains outside its recorded unit')
    return dict(old_owner=owner,old_owner_absent=True,old_unit=state['new_unit'],old_unit_properties=props,
        old_baseline_cgroup=group,preserved_live_old_group_members=sorted(remaining),sessions=live_sessions,
        guardian_unit=guardian,guardian_group=guardian_group,guardian_properties=guardian_props,guardian_drained=True,
        numerical_worker_signals=0,epoch=time.time())


def validate_authority(path,system=None,require_staged=True):
    path=Path(path).resolve();authority=read(path);system=system or System()
    attempt=authority.get('attempt_id','')
    if (not re.fullmatch('[a-f0-9]{32}',attempt) or path!=RUNTIME/'recovery'/attempt/'authority.json'
        or authority.get('schema_version')!=1 or authority.get('kind')!='R152_BASELINE_OWNER_RECOVERY'
        or authority.get('baseline_runtime')!=str(RUNTIME) or authority.get('shared_runtime')!=str(SHARED)
        or authority.get('expected_generation')!=2):raise RuntimeError('unreviewed baseline authority namespace/schema')
    release_api().verify_source(authority['execution_source'])
    master,_=master_context(authority['original_master'],allow_expired=require_staged)
    for name,record in authority['scope_evidence'].items():
        if digest(record['path'])!=record['sha256']:raise RuntimeError('original immutable scope receipt changed: '+name)
    state=archived(authority,'state');epoch=archived(authority,'epoch');archived(authority,'blocked');original_config=archived(authority,'config')
    if state['source']!=master['source'] and state['source']!={key:master['source'][key] for key in ('root','head','branch')}:
        raise RuntimeError('baseline core source differs from original master')
    if (state.get('phase')!='blocked' or epoch.get('phase')!='blocked' or epoch.get('generation')!=1
        or epoch.get('scope_id')!=state.get('scope_id') or state.get('scope_id')!=master['scope_id']
        or epoch.get('source')!=state.get('source') or epoch.get('expires_epoch')!=master['expires_epoch']
        or state.get('master_sha256')!=digest(SHARED/'master.json')):
        raise RuntimeError('archived predecessor scope/generation differs')
    config=core().read_config(authority['config_path']);expected=dict(original_config,new_unit=authority['new_unit'])
    if config!=expected or digest(authority['config_path'])!=authority['config_sha256']:
        raise RuntimeError('recovered baseline configuration changes more than its unit')
    release=read(authority['release_path'])
    if (digest(authority['release_path'])!=authority['release_sha256']
        or release.get('execution_source')!=authority['execution_source']
        or release.get('original_master')!=authority['original_master']):raise RuntimeError('baseline adoption source release differs')
    receipts=release_api().validate_probe_receipts([row['path'] for row in authority['probe_receipts']],authority['execution_source'],master)
    if receipts!=authority['probe_receipts']:raise RuntimeError('baseline adoption probe provenance differs')
    expected_empty=dict(admissions=[],attempts=[],slots=[],controller_absent=True,guardian_absent=True,terminal_absent=True)
    if authority.get('initial_cached_inventory')!=expected_empty:raise RuntimeError('initial cached inventory was not empty')
    if not require_staged:cached_empty()
    intent=authority['control_intent'];expected_argv=[original_config['python_runtime'],'-B',str(OWNER),'--authority',str(path),
        '--unit',authority['new_unit'],'--delegated-entry',str(OLD_ENTRY)]
    if (not re.fullmatch(r'pricefm-r152-muscat-baseline-[a-f0-9]{32}\.service',authority['new_unit'])
        or intent.get('unit')!=authority['new_unit'] or intent.get('argv')!=expected_argv
        or intent.get('source_head')!=authority['execution_source']['head'] or intent.get('source_entry_path')!=str(OWNER)
        or intent.get('source_entry_sha256')!=digest(OWNER) or intent.get('working_directory')!=str(OLD_ROOT)
        or authority.get('pending_path')!=str(SHARED/'master_pending.json')
        or authority.get('attestation_path')!=str(path.parent/'controller_attestation.json')
        or authority.get('execution_bridge_path')!=str(path.parent/'execution_bridge.json')):
        raise RuntimeError('baseline delegated owner intent differs')
    if require_staged:
        current=read(RUNTIME/'state.json')
        if (current.get('source')!=state['source'] or current.get('attempt')!=state['attempt']
            or current.get('scope_id')!=state['scope_id'] or current.get('new_unit')!=authority['new_unit']
            or current.get('config_path')!=authority['config_path'] or current.get('config_sha256')!=authority['config_sha256']
            or current.get('phase') not in {'running','complete'}
            or current.get('owner_recovery_authority_path')!=str(path)
            or current.get('owner_recovery_authority_sha256')!=digest(path)
            or current.get('execution_control_source')!=authority['execution_source']):
            raise RuntimeError('current baseline adoption pointer differs')
        current_epoch=read(RUNTIME/'resource_ownership_epoch.json')
        if current_epoch.get('generation')==1:
            if digest(RUNTIME/'resource_ownership_epoch.json')!=authority['snapshots']['epoch']['sha256']:
                raise RuntimeError('pre-adoption generation-one epoch changed')
        elif not 2<=current_epoch.get('generation',0)<=config['max_owner_generations']:
            raise RuntimeError('baseline bounded owner generations differ')
    else:
        for name in ('state','epoch','blocked'):
            record=authority['snapshots'][name]
            if digest(record['original_path'])!=record['sha256']:raise RuntimeError('predecessor changed before adoption: '+name)
        predecessor_proof(state,epoch,master,system)
    return authority


def prepare(release_path,probe_paths,system=None):
    system=system or System();release_path=Path(release_path).resolve();release=read(release_path)
    release_api().verify_source(release['execution_source'],remote=True)
    master,identity=master_context(release['original_master']);initial_cached_inventory=cached_empty()
    probes=release_api().validate_probe_receipts(probe_paths,release['execution_source'],master)
    state=read(RUNTIME/'state.json');epoch=read(RUNTIME/'resource_ownership_epoch.json')
    predecessor=predecessor_proof(state,epoch,master,system)
    original_config=core().read_config(state['config_path'])
    if epoch['generation']+1>original_config['max_owner_generations']:raise RuntimeError('bounded owner generation allowance exhausted')
    home=RUNTIME/'recovery'
    with release_api().locked(home/'release.lock'):
        if list(home.glob('*/authority.json')):raise RuntimeError('baseline recovery authority already claimed')
        attempt=uuid.uuid4().hex;folder=home/attempt;path=folder/'authority.json'
        unit='pricefm-r152-muscat-baseline-'+attempt+'.service';snapshots={}
        originals=dict(state=RUNTIME/'state.json',epoch=RUNTIME/'resource_ownership_epoch.json',blocked=RUNTIME/'blocked.json',config=Path(state['config_path']))
        for name,original in originals.items():
            target=folder/'original'/f'{name}.json';immutable_bytes(target,original.read_bytes())
            snapshots[name]=dict(original_path=str(original),archive_path=str(target),sha256=digest(target))
        config=dict(original_config,new_unit=unit);config_path=folder/'config.json';immutable(config_path,config)
        intent=dict(unit=unit,argv=[config['python_runtime'],'-B',str(OWNER),'--authority',str(path),'--unit',unit,'--delegated-entry',str(OLD_ENTRY)],
            description='R152 baseline owner recovery '+attempt,source_head=release['execution_source']['head'],source_entry_path=str(OWNER),
            source_entry_sha256=digest(OWNER),working_directory=str(OLD_ROOT),parent=None,created_epoch=time.time(),
            scientific_scope='ORIGINAL_R141_FINITE_QUEUES_WITH_UNCHANGED_NUMERICAL_LIMITS')
        evidence={name:dict(path=str(SHARED/name),sha256=digest(SHARED/name)) for name in
            ('master.json','master_pending.json','orchestrator.json','blocked.json','terminal.json','baseline/partition_release.json','baseline/owner_epochs/001.json')}
        authority=dict(schema_version=1,kind='R152_BASELINE_OWNER_RECOVERY',attempt_id=attempt,original_master=identity,
            baseline_runtime=str(RUNTIME),shared_runtime=str(SHARED),pending_path=str(SHARED/'master_pending.json'),
            execution_source=release['execution_source'],expected_generation=2,new_unit=unit,config_path=str(config_path),config_sha256=digest(config_path),
            snapshots=snapshots,predecessor_proof=predecessor,scope_evidence=evidence,control_intent=intent,
            attestation_path=str(folder/'controller_attestation.json'),execution_bridge_path=str(folder/'execution_bridge.json'),
            release_path=str(release_path),release_sha256=digest(release_path),probe_receipts=probes,created_epoch=time.time(),
            initial_cached_inventory=initial_cached_inventory,
            baseline_current_status_mutable=True,archived_original_status_immutable=True,numerical_worker_signals=0)
        immutable(path,authority);validate_authority(path,system=system,require_staged=False)
    return dict(status='R152_BASELINE_ADOPTION_PREPARED_NOT_LAUNCHED',authority_path=str(path),authority_sha256=digest(path),new_unit=unit)


def verify_control(system,intent):
    props=system.unit(intent['unit'])
    if (props.get('Id')!=intent['unit'] or props.get('Description')!=intent['description']
        or props.get('KillMode')!='process' or props.get('Restart')!='on-failure' or props.get('WorkingDirectory')!=str(OLD_ROOT)
        or pool().legacy().exec_arguments(props)!=' '.join(intent['argv'])):
        raise RuntimeError('baseline owner unit differs from its exact delegated intent')
    return props


def attest(system,intent):
    props=verify_control(system,intent);pid=int(props.get('MainPID',0));process=system.control_process(pid)
    if (not process or not props.get('InvocationID') or process.get('affinity')!=list(range(30))
        or process.get('scheduler')!=os.SCHED_OTHER or props.get('IOSchedulingClass')!='3'
        or props.get('CPUAccounting')!='yes' or process.get('cwd')!=str(OLD_ROOT)):
        raise RuntimeError('actual baseline owner policy/lifetime differs')
    return dict(intent,attested=props,process=process,expected_cgroup=props['ControlGroup'])


def launch(authority_path,system=None,timeout=60):
    system=system or System();authority_path=Path(authority_path).resolve()
    authority=validate_authority(authority_path,system=system,require_staged=False)
    config=core().read_config(authority['config_path']);folder=authority_path.parent
    with release_api().locked(folder/'launch.lock'):
        if (folder/'launch_claim.json').exists():raise RuntimeError('baseline adoption launch already claimed')
        with core().fences(RUNTIME,config):
            validate_authority(authority_path,system=system,require_staged=False)
            state=archived(authority,'state')
            state.pop('error',None)
            state.update(phase='running',new_unit=authority['new_unit'],config_path=authority['config_path'],config_sha256=authority['config_sha256'],
                owner_recovery_authority_path=str(authority_path),owner_recovery_authority_sha256=digest(authority_path),
                execution_control_source=authority['execution_source'])
            immutable(folder/'launch_claim.json',dict(authority_sha256=digest(authority_path),epoch=time.time(),next_generation=2))
            core().atomic(RUNTIME/'state.json',state)
        intent=authority['control_intent'];capsule=None
        try:
            system.start_control(intent,folder/'stdout');capsule=attest(system,intent)
            immutable(authority['attestation_path'],capsule)
            until=time.monotonic()+timeout
            while True:
                current=read(RUNTIME/'state.json');epoch=read(RUNTIME/'resource_ownership_epoch.json')
                if epoch.get('generation')==2 and epoch.get('owner',{}).get('pid')==capsule['process']['pid'] and current.get('phase') in {'running','complete'}:
                    master,_=master_context(authority['original_master'])
                    proof=adapter().verify_baseline(RUNTIME,master,system=system)
                    session_proof,_=sessions(current,system)
                    return immutable(folder/'recovered.json',dict(status='R152_BASELINE_OWNER_ADOPTED_GENERATION_TWO',authority_sha256=digest(authority_path),
                        owner_capsule=capsule,owner_generation=2,master_sha256=digest(SHARED/'master.json'),scope_id=master['scope_id'],
                        original_expires_epoch=master['expires_epoch'],ownership=proof,sessions=session_proof,
                        numerical_worker_signals=0,old_baseline_unit_stopped=False,epoch=time.time()))
                if current.get('phase')=='blocked' or time.monotonic()>=until:raise RuntimeError('bounded baseline owner adoption did not become healthy')
                time.sleep(.1)
        except BaseException as error:
            failure=dict(error=repr(error),authority_sha256=digest(authority_path),epoch=time.time(),numerical_worker_signals=0,
                state_rollback_attempted=False,old_baseline_unit_stopped=False,cleanup_errors=[])
            try:
                current=read(RUNTIME/'state.json')
                if (current.get('new_unit')!=authority['new_unit'] or current.get('scope_id')!=authority['original_master']['scope_id']
                    or current.get('owner_recovery_authority_path')!=str(authority_path)
                    or current.get('owner_recovery_authority_sha256')!=digest(authority_path)):
                    raise RuntimeError('refusing to change an unrelated current baseline owner state')
                immutable_bytes(folder/'launch_failure_current_state.json',(RUNTIME/'state.json').read_bytes())
                current.update(phase='blocked',error='baseline owner recovery launch failed: '+repr(error),
                    owner_recovery_launch_failure=True,epoch=time.time())
                core().atomic(RUNTIME/'state.json',current)
                core().atomic(RUNTIME/'blocked.json',dict(current,baseline_children_signalled=False,
                    cached_guard_must_defer=True,owner_recovery_launch_failure=True))
                failure['current_owner_marked_blocked_before_stop']=True
            except BaseException as cleanup:failure['cleanup_errors'].append(repr(cleanup))
            try:
                system.stop_owner(intent)
                failure['new_owner_stop_requested_process_only']=True
            except BaseException as cleanup:failure['cleanup_errors'].append(repr(cleanup))
            immutable(folder/'launch_failure.json',failure);raise


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('command',choices=('prepare','launch','validate'))
    parser.add_argument('--release',type=Path);parser.add_argument('--probe',type=Path,action='append');parser.add_argument('--authority',type=Path)
    args=parser.parse_args()
    value=prepare(args.release,args.probe) if args.command=='prepare' else launch(args.authority) if args.command=='launch' else validate_authority(args.authority)
    print(json.dumps(value,sort_keys=True,allow_nan=False))
if __name__=='__main__':main()
