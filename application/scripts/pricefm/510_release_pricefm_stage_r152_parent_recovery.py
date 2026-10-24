#!/usr/bin/env python3
"""Append-only release of one cached controller under the original R152 clock.

The active baseline source, master, failed parent and scientific outputs remain
immutable. Only an explicitly invoked launch writes a new recovery authority.
"""
from __future__ import annotations
import argparse
import contextlib
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import subprocess
import time
import uuid

ROOT=Path(__file__).resolve().parents[3]
ENTRY=Path(__file__).resolve()
BROKER=ENTRY.with_name('509_resume_pricefm_stage_r152_cached_pool.py')
OLD_ROOT=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r152_parallel_20261024')
SHARED=Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/launch_prep/pricefm_stage_r152_parallel_20261024')
MASTER=SHARED/'master.json'
EE_ROOT=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r150_bounded_admission_20261023')
PYTHON='/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python'
BRANCH='work/pricefm-r152-parent-recovery-20261024'
THREADS=('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS','BLIS_NUM_THREADS','NUMEXPR_NUM_THREADS','VECLIB_MAXIMUM_THREADS')
_API=None

def read(path):return json.loads(Path(path).read_text())
def digest(path):
    value=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(1048576),b''):value.update(block)
    return value.hexdigest()
def immutable(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_name('.'+path.name+'.'+uuid.uuid4().hex+'.tmp')
    try:
        with temporary.open('x') as stream:
            stream.write(json.dumps(value,indent=2,sort_keys=True,allow_nan=False)+'\n');stream.flush();os.fsync(stream.fileno())
        os.link(temporary,path)
    finally:temporary.unlink(missing_ok=True)
    fd=os.open(str(path.parent),os.O_RDONLY)
    try:os.fsync(fd)
    finally:os.close(fd)
    return value
@contextlib.contextmanager
def locked(path):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('a') as stream:
        fcntl.flock(stream,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:yield
        finally:fcntl.flock(stream,fcntl.LOCK_UN)
def api():
    global _API
    if _API is None:
        path=OLD_ROOT/'application/scripts/pricefm/505_run_pricefm_stage_r152_shared_pool.py'
        spec=importlib.util.spec_from_file_location('r152_recovery_frozen_resource_api',path)
        _API=importlib.util.module_from_spec(spec);spec.loader.exec_module(_API)
    return _API
def finite(value,positive=False):return not isinstance(value,bool) and isinstance(value,(int,float)) and math.isfinite(value) and (value>0 if positive else value>=0)
def git(*args):return subprocess.check_output(['git','-C',str(ROOT),*args],text=True,timeout=60).strip()
def source_identity():
    source=dict(root=str(ROOT),head=git('rev-parse','HEAD'),branch=git('branch','--show-current'),
        runtime_sha256={str(path.relative_to(ROOT)):digest(path) for path in (ENTRY,BROKER)})
    verify_source(source);return source
def verify_source(source,remote=False):
    if (source.get('root')!=str(ROOT) or source.get('branch')!=BRANCH
            or git('branch','--show-current')!=BRANCH or git('rev-parse','HEAD')!=source.get('head')
            or git('status','--porcelain')):raise RuntimeError('recovery execution source is not the released clean branch/head')
    required={str(path.relative_to(ROOT)) for path in (ENTRY,BROKER)}
    if set(source.get('runtime_sha256',{}))!=required:raise RuntimeError('recovery source pin coverage differs')
    for path,wanted in source['runtime_sha256'].items():
        if digest(ROOT/path)!=wanted:raise RuntimeError('recovery executable bytes changed')
    if remote:
        line=git('ls-remote','origin','refs/heads/'+BRANCH)
        if not line or line.split()[0]!=source['head']:raise RuntimeError('fresh remote does not match released recovery source')
    return source

def original_master(expected=None,allow_expired=False):
    pool=api();master=read(MASTER);pool.validate_master(master,allow_expired=allow_expired);pool.verify_source(master['source'])
    if Path(master['source']['root'])!=OLD_ROOT:raise RuntimeError('original source root differs')
    value=dict(path=str(MASTER),sha256=digest(MASTER),scope_id=master['scope_id'],start_epoch=master['start_epoch'],
        started_epoch=master['started_epoch'],expires_epoch=master['expires_epoch'],source=master['source'])
    if expected is not None and value!=expected:raise RuntimeError('original immutable master/clock/source changed')
    return master,value

def inventory():
    dev=SHARED/'development'
    return dict(admissions=sorted(str(path) for path in (dev/'admissions').rglob('*.json')),
        attempts=sorted(str(path) for path in (dev/'attempts').rglob('*.json')),
        slots=sorted(str(path) for path in (dev/'slots').rglob('claim.json')),
        controller_absent=not (dev/'controller.json').exists(),guardian_absent=not (dev/'guardian.json').exists(),
        terminal_absent=not (dev/'terminal.json').exists())
def empty_inventory(value):
    return all(value.get(key)==[] for key in ('admissions','attempts','slots')) and all(
        value.get(key) is True for key in ('controller_absent','guardian_absent','terminal_absent'))
def unit_cpu_seconds(raw):
    try:value=int(raw)
    except (TypeError,ValueError):return None
    return value/1e9 if 0<=value<2**63 else None

def old_lifetime_absent(saved,pool):
    prior=saved.get('process')
    if prior is None:raise RuntimeError('failed parent lacks its original process lifetime')
    current=pool.legacy().process(prior['pid'])
    return current is None or not pool.hardening().same_process_identity(current,prior) or current.get('state') in ('Z','X','x')
def failed_parent(system):
    pool=api();path=SHARED/'orchestrator.json';context=read(path);saved=context['capsule']
    terminal_path=SHARED/'terminal.json';blocked_path=SHARED/'blocked.json';terminal=read(terminal_path)
    master=read(MASTER)
    if (context!=master.get('orchestrator') or saved.get('source_head')!=master['source']['head']
            or terminal.get('source_head')!=master['source']['head']
            or terminal.get('status')!='R152_ORCHESTRATION_OPERATIONAL_STOP_BASELINE_PRESERVED'
            or terminal.get('baseline_worker_signals')!=0
            or 'baseline ownership epoch/master/heartbeat differs' not in terminal.get('error','')):
        raise RuntimeError('failed predecessor is not the exact ownership-publication race')
    props=system.unit(saved['unit']);pool.legacy().verify_owned(saved,props)
    group=saved.get('expected_cgroup') or saved['attested']['ControlGroup']
    if (props.get('ActiveState') in ('active','activating') or int(props.get('MainPID',0))
            or system.members(group) or (props.get('ControlGroup') and system.members(props['ControlGroup']))
            or not old_lifetime_absent(saved,pool)):raise RuntimeError('failed predecessor is not independently drained')
    proof=dict(unit=saved['unit'],invocation_id=saved['attested']['InvocationID'],expected_cgroup=group,
        old_lifetime_absent=True,drained=True,pids=[],properties=props,epoch=time.time())
    return dict(capsule_path=str(path),capsule_sha256=digest(path),capsule=saved,
        terminal_path=str(terminal_path),terminal_sha256=digest(terminal_path),
        blocked_path=str(blocked_path),blocked_sha256=digest(blocked_path),drain_proof=proof)
def failed_parent_charge(failed):
    raw=failed['drain_proof']['properties'].get('CPUUsageNSec','')
    observed=unit_cpu_seconds(raw)
    if observed is not None and finite(observed):return dict(CPU_seconds=observed+5.,basis='ACTUAL_FAILED_PARENT_CPU_PLUS_FIVE',raw_CPUUsageNSec=raw)
    saved=failed['capsule'];terminal=read(failed['terminal_path'])
    elapsed=terminal['finished_epoch']-saved['created_epoch']
    if not finite(elapsed):raise RuntimeError('failed predecessor lifetime bound invalid')
    return dict(CPU_seconds=elapsed*15+5.,basis='FAILED_PARENT_WALL_TIMES_FIFTEEN_PLUS_FIVE',elapsed_seconds=elapsed)

def validate_probe_receipts(paths,source,master):
    if not paths:raise RuntimeError('committed-source recovery probe is required')
    rows=[]
    for path in paths:
        path=Path(path).resolve();value=read(path)
        driver=value.get('probe_driver_CPU_seconds');charges=value.get('unit_CPU_charges',[])
        if (not finite(driver,positive=True) or any(not finite(row.get('CPU_seconds'),positive=True) for row in charges)
                or not math.isclose(value.get('charged_control_CPU_seconds',-1),driver+sum(row['CPU_seconds'] for row in charges),abs_tol=1e-9)
                or value.get('original_master_sha256')!=digest(MASTER) or value.get('scope_id')!=master['scope_id']
                or value.get('boot_id')!=api().boot() or value.get('started_epoch',0)<master['start_epoch']
                or not value.get('cleanup_verified') or value.get('cleanup_errors')
                or not finite(value.get('charged_control_CPU_seconds'),positive=True)):
            raise RuntimeError('post-T0 recovery probe debit/cleanup identity differs')
        rows.append(dict(path=str(path),sha256=digest(path),charged_CPU_seconds=value['charged_control_CPU_seconds'],status=value['status']))
    latest=read(rows[-1]['path'])
    if (latest.get('status')!='PASS_R152_PARENT_RECOVERY_DISPOSABLE_PROBE' or latest.get('execution_source')!=source
            or latest.get('scientific_runs')!=0 or latest.get('production_admissions')!=0
            or latest.get('parent_death_binding_verified') is not True):raise RuntimeError('successful same-source lifecycle probe required')
    if len({row['path'] for row in rows})!=len(rows):raise RuntimeError('probe debit receipt duplicated')
    return rows

def freeze_release(output):
    if Path(output).resolve().is_relative_to(SHARED):raise RuntimeError('source release must be outside canonical runtime')
    source=source_identity();verify_source(source,remote=True);master,original=original_master()
    failed=failed_parent(api().System());zero=inventory()
    if not empty_inventory(zero):raise RuntimeError('cached workflow already has registrations or claims')
    return immutable(output,dict(schema_version=1,status='R152_PARENT_RECOVERY_RELEASE',execution_source=source,
        original_master=original,failed_parent={key:failed[key] for key in ('capsule_path','capsule_sha256','terminal_path','terminal_sha256','blocked_path','blocked_sha256')},
        zero_admission_inventory=zero,created_epoch=time.time(),new_master_clock=False))

def validate_authority(path,system=None,require_empty=True,allow_expired=False):
    path=Path(path).resolve();authority=read(path);pool=api();system=system or pool.System()
    attempt=authority.get('attempt_id','')
    if (not re.fullmatch('[a-f0-9]{32}',attempt) or path!=SHARED/'development/recovery'/attempt/'authority.json'
            or authority.get('schema_version')!=1 or authority.get('stage')!='R152'
            or authority.get('kind')!='ORIGINAL_SCOPE_PARENT_RECOVERY'):
        raise RuntimeError('unreviewed recovery authority namespace/schema')
    verify_source(authority['execution_source']);master,_=original_master(authority['original_master'],allow_expired)
    if (authority.get('effective_parent_expires_epoch')!=master['expires_epoch']-5
            or not empty_inventory(authority['zero_admission_inventory'])):raise RuntimeError('recovery clock or initial zero-claim proof differs')
    if require_empty and not empty_inventory(inventory()):raise RuntimeError('cached registrations or claims appeared before recovery authority')
    current=failed_parent(system);saved=authority['failed_parent']
    for key in ('capsule_path','capsule_sha256','capsule','terminal_path','terminal_sha256','blocked_path','blocked_sha256'):
        if saved.get(key)!=current.get(key):raise RuntimeError('failed predecessor immutable identity changed')
    release=read(authority['release_path'])
    if (digest(authority['release_path'])!=authority['release_sha256']
            or release.get('status')!='R152_PARENT_RECOVERY_RELEASE'
            or release.get('execution_source')!=authority['execution_source']
            or release.get('original_master')!=authority['original_master']):raise RuntimeError('released recovery source/master differs')
    probes=validate_probe_receipts([row['path'] for row in authority['prior_control_debit']['probe_receipts']],authority['execution_source'],master)
    debit=authority['prior_control_debit'];failed_charge=failed_parent_charge(saved)
    if (debit.get('original_limit_CPU_seconds')!=1800 or debit.get('probe_receipts')!=probes
            or debit.get('failed_parent')!=failed_charge
            or not math.isclose(debit.get('CPU_seconds',-1),failed_charge['CPU_seconds']+sum(row['charged_CPU_seconds'] for row in probes),abs_tol=1e-9)
            or debit['CPU_seconds']>=1800):raise RuntimeError('fixed original shared-control debit differs or is exhausted')
    intent=authority['control_intent'];expected=[PYTHON,'-B',str(BROKER),'--authority',str(path),'--unit',intent['unit']]
    if (not re.fullmatch('pricefm-r150-r152-recovery-[a-f0-9]{32}\\.service',intent['unit'])
            or intent.get('argv')!=expected or intent.get('source_head')!=authority['execution_source']['head']
            or intent.get('source_entry_path')!=str(BROKER) or intent.get('source_entry_sha256')!=digest(BROKER)
            or intent.get('working_directory')!=str(EE_ROOT) or intent.get('parent') is not None
            or not finite(intent.get('runtime_seconds'),positive=True)
            or intent['runtime_seconds']>math.floor(authority['effective_parent_expires_epoch']-intent['created_epoch'])
            or authority.get('attestation_path')!=str(path.parent/'controller_attestation.json')):
        raise RuntimeError('recovery control intent/source/kernel duration differs')
    pool.baseline().baseline_ownership(SHARED/'baseline',master)
    return authority

def describe_process(pool,pid):
    value=pool.legacy().process(pid)
    if value is not None:value=dict(value,cwd=os.readlink(Path('/proc')/str(pid)/'cwd'))
    return value
def kernel_deadline(system,unit,runtime_seconds):
    raw=subprocess.check_output(['systemctl','--user','show',unit,'--property=ActiveEnterTimestampMonotonic','--value'],text=True,timeout=10).strip()
    try:entered=int(raw)/1e6
    except ValueError as exc:raise RuntimeError('actual kernel lifetime anchor unavailable') from exc
    if not finite(entered,positive=True) or entered>time.monotonic():raise RuntimeError('actual kernel start anchor invalid')
    return time.time()-time.monotonic()+entered+runtime_seconds
def attest_control(system,intent,original_expiry, *, idle=False,cpu=None):
    pool=api();props=system.unit(intent['unit']);pool.legacy().verify_owned(intent,props)
    process=describe_process(pool,int(props.get('MainPID',0)))
    expected=[cpu] if idle else list(range(15,30))
    actual_seconds=pool.legacy().parse_duration(props.get('RuntimeMaxUSec',''))
    if (not process or process['affinity']!=expected or process['scheduler']!=(5 if idle else 0)
            or props.get('IOSchedulingClass')!='3' or props.get('CPUAccounting')!='yes'
            or not props.get('InvocationID') or not 0<actual_seconds<=intent['runtime_seconds']):raise RuntimeError('live recovery control policy differs')
    deadline=kernel_deadline(system,intent['unit'],actual_seconds)
    if deadline>original_expiry:raise RuntimeError('kernel lifetime would exceed original absolute expiry')
    saved=dict(intent,attested=props,process=process,expected_cgroup=props['ControlGroup'],actual_kernel_expires_epoch=deadline)
    pool.legacy().verify_owned(saved,props);return saved

def launch(release_path,probe_paths):
    pool=api();system=pool.System();release_path=Path(release_path).resolve();release=read(release_path)
    if release.get('status')!='R152_PARENT_RECOVERY_RELEASE' or release.get('schema_version')!=1:raise RuntimeError('reviewed source release required')
    source=release['execution_source'];verify_source(source,remote=True);master,_=original_master(release['original_master'])
    failed=failed_parent(system)
    for key,wanted in release['failed_parent'].items():
        if failed.get(key)!=wanted:raise RuntimeError('failed predecessor changed after source release')
    zero=inventory()
    if not empty_inventory(zero):raise RuntimeError('recovery requires zero prior cached claims')
    probes=validate_probe_receipts(probe_paths,source,master);prior=failed_parent_charge(failed)
    total=prior['CPU_seconds']+sum(row['charged_CPU_seconds'] for row in probes)
    if total>=1800:raise RuntimeError('original shared-control allowance is exhausted')
    home=SHARED/'development/recovery'
    with locked(home/'launch.lock'):
        if (home/'scope_claim.json').exists() or list(home.glob('*/authority.json')):raise RuntimeError('original scope recovery already claimed; no reset/retry')
        attempt=uuid.uuid4().hex;folder=home/attempt;path=folder/'authority.json';unit='pricefm-r150-r152-recovery-'+attempt+'.service'
        now=time.time();effective=master['expires_epoch']-5;seconds=math.floor(effective-now)
        if seconds<120:raise RuntimeError('insufficient original remaining deadline for bounded recovery')
        intent=dict(unit=unit,argv=[PYTHON,'-B',str(BROKER),'--authority',str(path),'--unit',unit],
            description='R152 original-clock parent recovery '+attempt,runtime_seconds=seconds,
            source_head=source['head'],source_entry_path=str(BROKER),source_entry_sha256=digest(BROKER),
            working_directory=str(EE_ROOT),parent=None,created_epoch=now)
        authority=dict(schema_version=1,stage='R152',kind='ORIGINAL_SCOPE_PARENT_RECOVERY',attempt_id=attempt,
            original_master=release['original_master'],execution_source=source,failed_parent=failed,
            zero_admission_inventory=zero,prior_control_debit=dict(CPU_seconds=total,failed_parent=prior,
                probe_receipts=probes,original_limit_CPU_seconds=1800),release_path=str(release_path),release_sha256=digest(release_path),
            probe_path=probes[-1]['path'],probe_sha256=probes[-1]['sha256'],control_intent=intent,
            attestation_path=str(folder/'controller_attestation.json'),effective_parent_expires_epoch=effective,
            original_T0_preserved=True,automatic_renewal=False,created_epoch=now)
        immutable(home/'scope_claim.json',dict(attempt_id=attempt,scope_id=master['scope_id'],master_sha256=digest(MASTER),expires_epoch=master['expires_epoch']))
        immutable(path,authority);validate_authority(path,system)
        strongest=intent
        try:
            system.start(unit,intent['description'],intent['argv'],cpus=list(range(15,30)),idle=False,
                runtime_seconds=seconds,working_directory=EE_ROOT,stdout=folder/'stdout')
            strongest=attest_control(system,intent,master['expires_epoch'])
            immutable(authority['attestation_path'],strongest)
            return immutable(folder/'launch.json',dict(status='R152_ORIGINAL_CLOCK_RECOVERY_LAUNCHED',authority_path=str(path),
                authority_sha256=digest(path),unit=unit,actual_kernel_expires_epoch=strongest['actual_kernel_expires_epoch'],
                original_expires_epoch=master['expires_epoch'],created_epoch=time.time()))
        except BaseException as error:
            failure=dict(error=repr(error),epoch=time.time(),cleanup_errors=[])
            try:failure['cleanup']=pool.drain_exact(system,strongest)
            except BaseException as cleanup:failure['cleanup_errors'].append(repr(cleanup))
            immutable(folder/'launch_failure.json',failure);raise

def hold(output,seconds,unit):
    if not 0<=seconds<=60 or not unit.startswith('pricefm-r150-r152-recovery-probe-'):raise RuntimeError('bounded disposable namespace required')
    pool=api();props=pool.System().unit(unit)
    if props.get('InvocationID')!=os.environ.get('INVOCATION_ID') or int(props.get('MainPID',0))!=os.getpid():raise RuntimeError('disposable hold is not its exact unit MainPID')
    snap=describe_process(pool,os.getpid());threads=next(int(line.split()[1]) for line in Path('/proc/self/status').read_text().splitlines() if line.startswith('Threads:'))
    immutable(output,dict(process=snap,threads=threads,thread_environment={key:os.environ.get(key) for key in THREADS},
        properties=props,scientific_runs=0,epoch=time.time()))
    time.sleep(seconds)

def probe_charge(saved,system):
    props=system.unit(saved['unit']);api().legacy().verify_owned(saved,props)
    observed=unit_cpu_seconds(props.get('CPUUsageNSec',''))
    if observed is not None and finite(observed):return dict(unit=saved['unit'],CPU_seconds=observed+5.,basis='ACTUAL_UNIT_CPU_PLUS_FIVE')
    cpus=saved.get('process',{}).get('affinity',saved.get('cpus',list(range(15,30))))
    return dict(unit=saved['unit'],CPU_seconds=max(0,time.time()-saved['created_epoch'])*len(cpus)+5.,basis='DISPOSABLE_LIFETIME_WALL_TIMES_PHYSICAL_CPU_BOUND_PLUS_FIVE')
def wait_file(path,deadline):
    while not Path(path).is_file():
        if time.monotonic()>=deadline:raise RuntimeError('bounded disposable observation wait expired')
        time.sleep(.025)
    return read(path)
def capability_probe(output):
    pool=api();source=source_identity();master,_=original_master();system=pool.System();output=Path(output).resolve()
    if output.is_relative_to(SHARED):raise RuntimeError('disposable probe output must be outside canonical runtime')
    folder=output.parent/(output.stem+'.'+uuid.uuid4().hex+'.runtime');folder.mkdir(parents=True)
    result=dict(status='FAIL_R152_PARENT_RECOVERY_DISPOSABLE_PROBE',execution_source=source,
        original_master_sha256=digest(MASTER),scope_id=master['scope_id'],boot_id=pool.boot(),
        started_epoch=time.time(),cleanup_errors=[],cleanup=[],scientific_runs=0,production_admissions=0,
        parent_death_binding_verified=False,cleanup_verified=False,probe_runtime=str(folder))
    saved_rows=[];charges=[]
    try:
        for role in ('parent','child'):
            unit='pricefm-r150-r152-recovery-probe-'+role+'-'+uuid.uuid4().hex+'.service'
            report=folder/(role+'.json');argv=[PYTHON,'-B',str(ENTRY),'hold','--output',str(report),'--seconds','45','--unit',unit]
            intent=dict(unit=unit,argv=argv,description='R152 disposable recovery '+role,runtime_seconds=55,
                working_directory=str(EE_ROOT),created_epoch=time.time(),source_head=source['head'],
                source_entry_path=str(ENTRY),source_entry_sha256=digest(ENTRY),parent=saved_rows[0]['unit'] if saved_rows else None,
                cpus=[24] if role=='child' else list(range(15,30)))
            immutable(folder/(role+'_intent.json'),intent);strongest=intent
            try:
                system.start(unit,intent['description'],argv,cpus=[24] if role=='child' else list(range(15,30)),
                    idle=role=='child',runtime_seconds=55,controller=intent['parent'],working_directory=EE_ROOT,stdout=folder/(role+'.stdout'))
                strongest=attest_control(system,intent,min(master['expires_epoch'],time.time()+60),idle=role=='child',cpu=24)
                if role=='child':strongest['cpu']=24
                saved_rows.append(strongest);immutable(folder/(role+'_attestation.json'),strongest)
            except BaseException:
                if strongest not in saved_rows:saved_rows.append(strongest)
                raise
            observed=wait_file(report,time.monotonic()+15)
            if observed['threads']!=1 or any(observed['thread_environment'].get(key)!='1' for key in THREADS):raise RuntimeError('disposable process thread policy differs')
        parent,child=saved_rows
        props=system.unit(child['unit'])
        if parent['unit'] not in props.get('BindsTo','').split() or parent['unit'] not in props.get('After','').split():raise RuntimeError('disposable child lacks exact parent binding')
        if not pool.hardening().strict_worker_policy(system,child):raise RuntimeError('disposable child policy proof was not live')
        pool.legacy().verify_owned(parent,system.unit(parent['unit']))
        subprocess.run(['systemctl','--user','kill','--kill-who=main','--signal=KILL',parent['unit']],check=True,timeout=10)
        deadline=time.monotonic()+15
        while system.unit(child['unit']).get('ActiveState') in ('active','activating') and time.monotonic()<deadline:time.sleep(.05)
        if system.unit(child['unit']).get('ActiveState') in ('active','activating'):raise RuntimeError('parent death did not stop the bound disposable child')
        result.update(status='PASS_R152_PARENT_RECOVERY_DISPOSABLE_PROBE',parent_death_binding_verified=True)
    except BaseException as error:result['error']=repr(error)
    finally:
        for saved in reversed(saved_rows):
            try:
                result['cleanup'].append(pool.drain_exact(system,saved));charges.append(probe_charge(saved,system))
            except BaseException as error:result['cleanup_errors'].append(dict(unit=saved['unit'],error=repr(error)))
        result['unit_CPU_charges']=charges
        result['probe_driver_CPU_seconds']=time.process_time()+os.times().children_user+os.times().children_system+5.
        result['charged_control_CPU_seconds']=sum(row['CPU_seconds'] for row in charges)+result['probe_driver_CPU_seconds']
        result['cleanup_verified']=not result['cleanup_errors'] and len(result['cleanup'])==len(saved_rows)
        if not result['cleanup_verified']:result['status']='FAIL_R152_PARENT_RECOVERY_DISPOSABLE_PROBE'
        result['finished_epoch']=time.time();immutable(output,result)
    if result['status']!='PASS_R152_PARENT_RECOVERY_DISPOSABLE_PROBE':raise RuntimeError('disposable recovery probe failed; immutable receipt preserved')
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=('freeze','probe','launch','hold','validate'))
    parser.add_argument('--output',type=Path);parser.add_argument('--release',type=Path);parser.add_argument('--probe',action='append',type=Path)
    parser.add_argument('--authority',type=Path);parser.add_argument('--unit');parser.add_argument('--seconds',type=float)
    args=parser.parse_args()
    if args.action=='freeze':value=freeze_release(args.output)
    elif args.action=='probe':value=capability_probe(args.output)
    elif args.action=='launch':value=launch(args.release,args.probe)
    elif args.action=='hold':return hold(args.output,args.seconds,args.unit)
    else:value=validate_authority(args.authority)
    print(json.dumps(value,sort_keys=True))
if __name__=='__main__':main()
