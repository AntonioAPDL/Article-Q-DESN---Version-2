#!/usr/bin/env python3
"""Source-bound release and one finite R152 baseline/EE/FI/DK2 workflow.

The baseline owner is independent of the finite development parent. Every
production controller waits for source/unit attestation. T0 is published only
by the fenced baseline owner, before its first new regional dispatch.
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
import signal
import subprocess
import sys
import time
import uuid

ROOT=Path(__file__).resolve().parents[3]
ENTRY=Path(__file__).resolve()
CONFIG=ROOT/'application/config/pricefm_stage_r152_parallel_20261024.json'
EE_ROOT=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r150_bounded_admission_20261023')
THREAD_VARS=('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS','BLIS_NUM_THREADS','NUMEXPR_NUM_THREADS','VECLIB_MAXIMUM_THREADS')

def read(path):return json.loads(Path(path).read_text())
def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(1048576),b''):h.update(block)
    return h.hexdigest()
def atomic(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
    with tmp.open('x') as stream:
        stream.write(json.dumps(value,indent=2,sort_keys=True,allow_nan=False)+'\n');stream.flush();os.fsync(stream.fileno())
    os.replace(tmp,path)
def immutable(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_name('.'+path.name+'.'+uuid.uuid4().hex+'.tmp')
    try:
        with temporary.open('x') as stream:
            stream.write(json.dumps(value,indent=2,sort_keys=True,allow_nan=False)+'\n');stream.flush();os.fsync(stream.fileno())
        os.link(temporary,path)
    finally:
        if temporary.exists():temporary.unlink()
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
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    item=importlib.util.module_from_spec(spec);spec.loader.exec_module(item)
    if any(key in sys.modules for key in ('numpy','pandas','scipy')):
        raise RuntimeError('orchestration parent imported numerical dependencies')
    return item
def apis():
    folder=ENTRY.parent
    return (module('r152_outer_baseline',folder/'504_supervise_pricefm_stage_r152_baseline.py'),
            module('r152_outer_pool',folder/'505_run_pricefm_stage_r152_shared_pool.py'))
def git(*argv):return subprocess.check_output(['git','-C',str(ROOT),*argv],text=True,timeout=60).strip()

def read_config(path=CONFIG):
    c=read(path)
    fixed=dict(schema_version=1,stage='R152',required_branch='work/pricefm-r152-parallel-recovery-20261024',
        master_seconds=43200,precommit_seconds=300,kernel_backstop_seconds=60,poll_seconds=5,
        parent_cpus=list(range(15,30)),new_cached_posterior_fits=0,LT_AT_repair_fits=0,
        AL_authorized=False,promotion_authorized=False,automatic_renewal=False,Jerez_mutations_authorized=False)
    if any(c.get(key)!=value for key,value in fixed.items()):raise RuntimeError('R152 finite orchestration scope differs')
    canonical=Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/launch_prep/pricefm_stage_r152_parallel_20261024')
    if Path(c['runtime'])!=canonical:raise RuntimeError('unreviewed runtime namespace')
    for key,name in (('baseline_config','pricefm_stage_r152_baseline_20261024.json'),
                     ('pool_config','pricefm_stage_r152_pool_20261024.json'),
                     ('FI_config','pricefm_stage_r152_fi_20261024.json')):
        if c[key]!='application/config/'+name:raise RuntimeError('unreviewed component configuration: '+key)
    return c

def verify_plan(c):
    if digest(c['plan_path'])!=c['plan_sha256'] or digest(c['plan_manifest_path'])!=c['plan_manifest_sha256']:
        raise RuntimeError('reviewed plan identity changed')
    plan=read(c['plan_path'])
    if plan['status']!='PLAN_PREPARED_NOT_IMPLEMENTED' or plan['master']['proposed_duration_seconds']!=43200:
        raise RuntimeError('reviewed prospective plan scope differs')
    return plan

def fresh_remote(source):
    line=subprocess.check_output(['git','-C',str(ROOT),'ls-remote','origin',
        'refs/heads/'+source['branch']],text=True,timeout=60).strip()
    if not line or line.split()[0]!=source['head']:raise RuntimeError('fresh CLI remote differs from released source')
    return dict(head=line.split()[0],branch=source['branch'],checked_epoch=time.time())

def freeze_release(output,config_path=CONFIG):
    c=read_config(config_path);plan=verify_plan(c);baseline,pool=apis()
    baseline.read_config(ROOT/c['baseline_config']);pool.read_config(ROOT/c['pool_config'])
    source=pool.source_identity()
    whole_source=pool.source_identity(full=True)
    if source['branch']!=c['required_branch']:raise RuntimeError('dedicated task branch required')
    remote=fresh_remote(source)
    paths=[CONFIG,ROOT/c['baseline_config'],ROOT/c['pool_config'],ROOT/c['FI_config']]
    value=dict(schema_version=1,status='R152_COMMITTED_IMPLEMENTATION_RELEASE',source=source,
        whole_tracked_source_sha256=whole_source['runtime_sha256'],
        fresh_remote=remote,config_path=str(Path(config_path).resolve()),config_sha256=digest(config_path),
        configuration_sha256={str(path):digest(path) for path in paths},
        plan_sha256=c['plan_sha256'],plan_manifest_sha256=c['plan_manifest_sha256'],
        scope=dict(master_seconds=43200,baseline_A=list(range(15)),baseline_B=list(range(15,24)),
            development=list(range(24,30)),optional=[22,23],EE_new_windows=2,FI_new_windows_max=3,DK2_new_windows_max=3),
        numerical_sources=dict(EE=plan['numerical_sources']['immutable_EE'],baseline=plan['numerical_sources']['baseline']),
        stage_started=False,source_or_baseline_mutations=False,created_epoch=time.time())
    return immutable(output,value)

def verify_release(c,release,probe=None, *, remote=False):
    _,pool=apis();verify_plan(c)
    pool.verify_source(release['source'])
    if (release.get('status')!='R152_COMMITTED_IMPLEMENTATION_RELEASE'
            or release.get('config_sha256')!=digest(CONFIG)
            or release.get('plan_sha256')!=c['plan_sha256']):
        raise RuntimeError('committed release differs')
    for path,wanted in release['configuration_sha256'].items():
        if digest(path)!=wanted:raise RuntimeError('configuration changed after release: '+path)
    if remote:
        fresh_remote(release['source'])
        for name,wanted in release.get('whole_tracked_source_sha256',{}).items():
            if digest(ROOT/name)!=wanted:raise RuntimeError('whole released tree differs: '+name)
    if probe is not None:
        if (probe.get('status')!='PASS_R152_SOURCE_BOUND_POLICY_LIFECYCLE_AND_DRAIN'
                or probe.get('source_head')!=release['source']['head']
                or probe.get('boot_id')!=pool.boot() or probe.get('cleanup_errors')):
            raise RuntimeError('same-source/boot successful resource probe required')
        if probe.get('baseline_probe_status')!='PASS_ACTUAL_SOURCE_BASELINE_PRIMITIVE_PROBE':
            raise RuntimeError('same-source baseline control-plane probe required')
    return True

def describe_process(pool,pid):
    value=pool.legacy().process(pid)
    if value is not None:
        value=dict(value,cwd=os.readlink(Path('/proc')/str(pid)/'cwd'))
    return value

def start_control(pool,folder,argv,c, *, parent=None,runtime_seconds=None,role='master'):
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    unit=argv[-1]
    if not unit.startswith('pricefm-r150-r152-') or not unit.endswith('.service'):
        raise RuntimeError('control argv must end with its unique owned unit')
    seconds=runtime_seconds or c['master_seconds']+c['precommit_seconds']+c['kernel_backstop_seconds']
    intent=dict(unit=unit,argv=argv,description='R152 owned '+role+' '+unit,
        role=role,runtime_seconds=seconds,source_head=git('rev-parse','HEAD'),
        source_entry_path=argv[2],source_entry_sha256=digest(argv[2]),parent=parent,
        working_directory=str(EE_ROOT),created_epoch=time.time())
    immutable(folder/'intent.json',intent)
    system=pool.System() if hasattr(pool,'System') else pool.legacy().System()
    strongest=intent
    try:
        system.start(unit,intent['description'],argv,cpus=c['parent_cpus'],idle=False,
            runtime_seconds=seconds,controller=parent,working_directory=EE_ROOT,stdout=folder/'stdout')
        props=system.unit(unit)
        pool.legacy().verify_owned(intent,props)
        saved=dict(intent,attested=props,expected_cgroup=props.get('ControlGroup'),
            process=describe_process(pool,int(props.get('MainPID',0))))
        strongest=saved
        pool.legacy().verify_owned(saved,props)
        if (not props.get('InvocationID') or not saved['process']
                or props.get('CPUSchedulingPolicy')!='0' or props.get('IOSchedulingClass')!='3'
                or saved['process']['affinity']!=c['parent_cpus']):
            raise RuntimeError('new parent live policy differs')
        immutable(folder/'attestation.json',saved)
        return saved
    except BaseException as error:
        failure=dict(error=repr(error),intent=intent,epoch=time.time(),cleanup_errors=[])
        try:failure['cleanup']=pool.legacy().stop_and_drain(system,strongest,timeout=25)
        except BaseException as cleanup:failure['cleanup_errors'].append(repr(cleanup))
        atomic(folder/'startup_failure.json',failure)
        raise

def launch(release_path,probe_path,config_path=CONFIG):
    c=read_config(config_path);release=read(release_path);probe=read(probe_path)
    verify_release(c,release,probe,remote=True)
    _,pool=apis();runtime=Path(c['runtime'])
    with locked(runtime/'launch.lock'):
        if any((runtime/name).exists() for name in ('launch.json','master.json','launch_intent.json')):
            raise RuntimeError('finite R152 workflow already claimed; no reset or join')
        prepared=pool.prepare(runtime,ROOT/c['pool_config'])
        record=read(runtime/'development/prepared.json')
        if record.get('source')!=release['source']:
            raise RuntimeError('prepared dispatcher and release source differ before resource commitment')
        unit='pricefm-r150-r152-master-'+uuid.uuid4().hex+'.service'
        argv=[c['python_runtime'],'-B',str(ENTRY),'coordinate','--runtime',str(runtime),
            '--config',str(Path(config_path).resolve()),'--unit',unit]
        immutable(runtime/'release.json',release);immutable(runtime/'probe.json',probe)
        immutable(runtime/'launch_intent.json',dict(unit=unit,argv=argv,source=release['source'],
            release_sha256=digest(runtime/'release.json'),probe_sha256=digest(runtime/'probe.json'),
            epoch=time.time(),master_started=False))
        capsule=start_control(pool,runtime/'orchestrator',argv,c,role='finite-master')
        return immutable(runtime/'launch.json',dict(status='R152_FINITE_WORKFLOW_LAUNCHED',
            unit=unit,orchestrator=capsule,runtime=str(runtime),created_epoch=time.time(),
            no_new_LT_AT_repairs=True,no_renewal=True))

def start_baseline(c,shared,pending):
    baseline,_=apis();cfg=baseline.read_config(ROOT/c['baseline_config'])
    unit=c['baseline_unit']
    props=baseline.System().unit(unit)
    if props.get('ActiveState') in ('active','activating') or int(props.get('MainPID',0)):
        raise RuntimeError('new baseline successor is already owned')
    folder=Path(shared)/'baseline';folder.mkdir(parents=True,exist_ok=True)
    argv=[c['python_runtime'],'-B',str(ENTRY.with_name('504_supervise_pricefm_stage_r152_baseline.py')),
        'run','--config',str(ROOT/c['baseline_config']),'--runtime',str(folder),
        '--shared-runtime',str(shared),'--pending',str(pending)]
    intent=dict(unit=unit,argv=argv,source_head=git('rev-parse','HEAD'),
        baseline_numerical_source=cfg['source_head'],epoch=time.time())
    immutable(folder/'service_intent.json',intent)
    command=['systemd-run','--user','--quiet','--unit='+unit,'--description=R152 Muscat baseline successor',
        '--property=Restart=on-failure','--property=RestartSec=5s','--property=StartLimitBurst=3',
        '--property=StartLimitIntervalSec=300s','--property=KillMode=process','--property=TimeoutStopSec=20s',
        '--property=WorkingDirectory='+str(ROOT),'--property=CPUAffinity='+' '.join(map(str,range(30))),
        '--property=CPUSchedulingPolicy=other','--property=IOSchedulingClass=idle',
        '--property=CPUAccounting=yes','--property=MemoryAccounting=yes',
        '--property=StandardOutput=file:'+str(folder/'stdout'),
        '--property=StandardError=file:'+str(folder/'stdout.stderr')]
    command+=['--setenv='+key+'=1' for key in THREAD_VARS]
    command+=['--setenv=PYTHONDONTWRITEBYTECODE=1']+argv
    subprocess.run(command,check=True,timeout=30)
    return intent

def wait_file(path,deadline):
    while not Path(path).exists():
        if time.time()>=deadline:raise RuntimeError('bounded precommit/attestation wait expired: '+str(path))
        time.sleep(.05)
    return read(path)

def pending_contract(c,release,orchestrator,release_sha,probe_sha,config_path=CONFIG):
    """Precommit carries no resource grant or running master clock."""
    start=orchestrator['startup_epoch'];deadline=orchestrator['precommit_expires_epoch']
    if (not math.isfinite(start) or not math.isfinite(deadline)
            or not math.isclose(deadline-start,c['precommit_seconds'],abs_tol=1e-6)
            or not orchestrator.get('unit') or not orchestrator.get('invocation_id')
            or not orchestrator.get('process')):
        raise RuntimeError('finite precommit parent lifetime differs')
    return dict(schema_version=1,stage='R152',scope_id=uuid.uuid4().hex,source=release['source'],
        source_head=release['source']['head'],orchestrator=orchestrator,
        precommit_expires_epoch=deadline,release_sha256=release_sha,probe_sha256=probe_sha,
        plan_sha256=c['plan_sha256'],config_sha256=digest(config_path),
        pool_config_sha256=digest(ROOT/c['pool_config']),baseline_config_sha256=digest(ROOT/c['baseline_config']),
        FI_config_sha256=digest(ROOT/c['FI_config']),master_seconds=c['master_seconds'],
        parent_unit=orchestrator['unit'],parent_invocation_id=orchestrator['invocation_id'])

def orchestrator_context(capsule,props,own,source_head,startup,deadline,attestation_path):
    if (not own or own['pid']!=int(props.get('MainPID',0))
            or capsule['unit']!=props.get('Id')
            or capsule.get('attested',{}).get('InvocationID')!=props.get('InvocationID')):
        raise RuntimeError('parent context cannot forward a different attested lifetime')
    return dict(unit=capsule['unit'],invocation_id=props['InvocationID'],process=own,
        properties=props,cgroup=props['ControlGroup'],source_head=source_head,
        startup_epoch=startup,precommit_expires_epoch=deadline,capsule=capsule,
        attestation_path=str(attestation_path),attestation_sha256=digest(attestation_path))

def await_development_drained(pool,runtime,master,system,timeout=25):
    """The independent guardian can take one poll to observe broker completion."""
    until=time.monotonic()+timeout
    while True:
        try:return pool.verify_all_drained(runtime,master,system=system)
        except RuntimeError as error:
            if 'not drained' not in str(error) or time.monotonic()>=until:raise
            time.sleep(.1)

def coordinate(runtime,unit,config_path=CONFIG):
    c=read_config(config_path);runtime=Path(runtime);baseline,pool=apis()
    startup=time.time();deadline=startup+c['precommit_seconds']
    capsule=wait_file(runtime/'orchestrator/attestation.json',min(deadline,startup+20))
    system=pool.System() if hasattr(pool,'System') else pool.legacy().System()
    props=system.unit(unit);pool.legacy().verify_owned(capsule,props)
    own=describe_process(pool,os.getpid())
    if capsule['unit']!=unit or int(props.get('MainPID',0))!=os.getpid() or not own:
        raise RuntimeError('finite master lifetime differs')
    release=read(runtime/'release.json');probe=read(runtime/'probe.json')
    verify_release(c,release,probe)
    orchestrator=orchestrator_context(capsule,props,own,release['source']['head'],
        startup,deadline,runtime/'orchestrator/attestation.json')
    immutable(runtime/'orchestrator.json',orchestrator)
    pending=pending_contract(c,release,orchestrator,digest(runtime/'release.json'),digest(runtime/'probe.json'),config_path)
    immutable(runtime/'master_pending.json',pending)
    stopped=[False]
    for sig in (signal.SIGTERM,signal.SIGINT):signal.signal(sig,lambda *_:stopped.__setitem__(0,True))
    terminal=dict(status='R152_ORCHESTRATION_NOT_SCIENTIFICALLY_COMPLETE',cleanup_verified=False,
        source_head=release['source']['head'],baseline_worker_signals=0,new_LT_AT_fits=0)
    broker=None
    try:
        start_baseline(c,runtime,runtime/'master_pending.json')
        master=wait_file(runtime/'master.json',deadline)
        wait_file(runtime/'baseline/partition_release.json',deadline)
        pool.validate_master(master)
        baseline.baseline_ownership(runtime/'baseline',master)
        if time.time()>=deadline:raise RuntimeError('partition committed too late for finite parent containment')
        broker_unit='pricefm-r150-r152-pool-'+uuid.uuid4().hex+'.service'
        argv=[c['python_runtime'],'-B',str(ENTRY.with_name('505_run_pricefm_stage_r152_shared_pool.py')),
            'run','--runtime',str(runtime),'--config',str(ROOT/c['pool_config']),'--unit',broker_unit]
        broker=start_control(pool,runtime/'development/control',argv,c,parent=unit,
            runtime_seconds=master['expires_epoch']-time.time(),role='shared-pool')
        while True:
            current=system.unit(broker_unit);pool.legacy().verify_owned(broker,current)
            atomic(runtime/'progress.json',dict(status='R152_WORKFLOW_ACTIVE',epoch=time.time(),
                master_scope_id=master['scope_id'],expires_epoch=master['expires_epoch'],
                baseline_state=read(runtime/'baseline/state.json'),
                development=read(runtime/'development/progress.json') if (runtime/'development/progress.json').exists() else {'status':'STARTING'}))
            if current.get('ActiveState') not in ('active','activating'):break
            if stopped[0] or time.time()>=master['expires_epoch']-45:
                atomic(runtime/'development/stop_request.json',dict(reason='finite_master_stop',epoch=time.time()))
            if time.time()>=master['expires_epoch']:
                system.stop(broker_unit);break
            time.sleep(c['poll_seconds'])
        proof=pool.legacy().stop_and_drain(system,broker,timeout=25)
        terminal.update(status='R152_FINITE_POOL_EXITED_BASELINE_CONTINUES',broker_cleanup=proof,
            development_terminal=read(runtime/'development/terminal.json') if (runtime/'development/terminal.json').exists() else None)
        if hasattr(pool,'verify_all_drained'):
            terminal['development_cleanup']=await_development_drained(pool,runtime,master,system)
            terminal['cleanup_verified']=terminal['development_cleanup'].get('cleanup_verified') is True
        if terminal['cleanup_verified'] and (runtime/'development/terminal.json').exists():
            immutable(runtime/'development/final_drained.json',dict(terminal['development_cleanup'],
                cleanup_scope='Cached workers, broker and guardian; finite-master publisher excluded',
                publisher_capsule=capsule,publisher_pending_drain=True))
            immutable(runtime/'development_closed.json',dict(scope_id=master['scope_id'],
                master_sha256=digest(runtime/'master.json'),source_head=release['source']['head'],
                future_admissions_closed=True,cleanup_verified=True,
                terminal_sha256=digest(runtime/'development/terminal.json'),epoch=time.time(),
                final_drained_sha256=digest(runtime/'development/final_drained.json'),
                publisher_capsule=capsule,publisher_pending_drain=True,
                cleanup_scope='Cached workers and broker/guardian; publisher drain verified independently by baseline'))
    except BaseException as error:
        terminal.update(status='R152_ORCHESTRATION_OPERATIONAL_STOP_BASELINE_PRESERVED',error=repr(error))
        if broker is not None:
            try:terminal['broker_cleanup']=pool.legacy().stop_and_drain(system,broker,timeout=25)
            except BaseException as cleanup:terminal['cleanup_error']=repr(cleanup)
        atomic(runtime/'blocked.json',dict(terminal,epoch=time.time()))
        raise
    finally:
        terminal['finished_epoch']=time.time()
        immutable(runtime/'terminal.json',terminal)
    return terminal

def status(runtime):
    runtime=Path(runtime)
    return {key:read(runtime/name) for key,name in (('launch','launch.json'),('master','master.json'),
        ('progress','progress.json'),('terminal','terminal.json'),('blocked','blocked.json')) if (runtime/name).exists()}

def capability_probe(output,config_path=CONFIG):
    """Actual committed-source policy/lifetime checks, zero scientific predictions.

    Every file/UUID unit is confined to this disposable output namespace.
    The probe never calls baseline cutover, a scientific worker or old claims.
    """
    c=read_config(config_path);baseline,pool=apis();source=pool.source_identity(full=True)
    if os.sched_getscheduler(0)!=os.SCHED_OTHER or sorted(os.sched_getaffinity(0))!=c['parent_cpus']:
        raise RuntimeError('probe parent requires its declared ordinary physical CPU domain')
    if any(os.environ.get(key)!='1' for key in THREAD_VARS):raise RuntimeError('probe parent thread environment differs')
    output=Path(output);probe_root=output.parent/(output.stem+'.'+uuid.uuid4().hex+'.runtime')
    probe_root.mkdir(parents=True)
    if probe_root.is_relative_to(Path(c['runtime'])):raise RuntimeError('disposable proof must not occupy production runtime')
    result=dict(status='R152_PROBE_INCOMPLETE',source_head=source['head'],boot_id=pool.boot(),
        started_epoch=time.time(),cleanup_errors=[],cases=[],scientific_predictions=0,new_model_fits=0,
        production_admissions=0,runtime=str(probe_root))
    system=pool.System();parents=[]
    try:
        bfile=probe_root/'baseline_control_probe.json'
        command=[c['python_runtime'],'-B',str(ENTRY.with_name('504_supervise_pricefm_stage_r152_baseline.py')),
            'probe','--config',str(ROOT/c['baseline_config']),'--output',str(bfile)]
        observed=subprocess.run(command,text=True,capture_output=True,timeout=90)
        (probe_root/'baseline_probe.stdout').write_text(observed.stdout)
        (probe_root/'baseline_probe.stderr').write_text(observed.stderr)
        if observed.returncode or not bfile.exists():raise RuntimeError('baseline disposable control probe failed')
        b=read(bfile)
        result['baseline_probe_status']=b['status'];result['baseline_probe_sha256']=digest(bfile)
        if (b['status']!='PASS_ACTUAL_SOURCE_BASELINE_PRIMITIVE_PROBE'
                or b.get('source',{}).get('head')!=source['head']
                or not b.get('source_bound') or not b.get('exact_disposable_cleanup')
                or b.get('real_legacy_controls_changed') is not False or b.get('baseline_workers_launched')!=0):
            raise RuntimeError('baseline disposable control proof is incomplete')
        now=time.time()
        master=dict(schema_version=1,stage='R152',scope_id='probe-'+uuid.uuid4().hex,
            start_epoch=now,started_epoch=now,expires_epoch=now+43200,source=source,probe_only=True,
            partition=dict(baseline_A=list(range(15)),baseline_B=list(range(15,24)),development_base=list(range(24,30)),optional=[22,23]))
        immutable(probe_root/'master.json',master)
        pool.validate_master(master)
        dev=probe_root/'development';dev.mkdir()
        study=pool.EEStudy(pool.read_config(ROOT/c['pool_config']),dev)
        source_pool=pool.source_identity()
        parent_unit='pricefm-r150-r152-probe-parent-'+uuid.uuid4().hex+'.service'
        bootstrap=ENTRY.with_name('508_bootstrap_pricefm_stage_r152_payload.py')
        parent_argv=[c['python_runtime'],'-B',str(bootstrap),'probe-payload','--output',str(probe_root/'parent_observation.json'),
            '--seconds','60','--unit',parent_unit]
        parent=start_control(pool,probe_root/'control',parent_argv,c,runtime_seconds=90,role='probe-parent')
        parents.append(parent)
        wait_file(probe_root/'parent_observation.json',time.time()+15)
        pc=pool.read_config(ROOT/c['pool_config'])
        for index,case in enumerate(('immutable_guard','numerical_libraries','admin_accounting','positive_thread_violation','parent_death')):
            name='__r152_disposable_'+case+'__';report=probe_root/(case+'.json')
            start=time.time()
            lease=dict(schema_version=1,stage='R152_PROBE_ONLY',study='EE',kind='numerical',
                admission_id='PROBE-'+str(index),lease_id=uuid.uuid4().hex,started_epoch=start,
                expires_epoch=start+50,compute_expires_epoch=start+40,seconds=50,probe_only=True,
                source_head=source['head'],study_source_head=pool.EE_HEAD,
                master_scope_id=master['scope_id'],master_sha256=digest(probe_root/'master.json'),
                prep_sha256=digest(study.PREP/'preparation.json'),controller_unit=parent_unit,nonrenewing=True)
            lease_path=probe_root/'probe_admissions'/(case+'.json');immutable(lease_path,lease)
            seconds='15' if case in ('positive_thread_violation','parent_death') else '2'
            target=[c['python_runtime'],'-B',str(bootstrap),'legacy-guard-probe','--output',str(report),
                '--cpu','24','--policy-receipt','{policy_receipt}','--task',name,'--seconds',seconds]
            if case=='numerical_libraries':target.append('--numerical-libraries')
            if case=='positive_thread_violation':target.append('--fault-threads')
            task=dict(name=name,estimated_cpu_seconds=50.,estimated_wall_seconds=50.)
            saved=pool.start_payload(system,pc,dev/'attempts'/'EE',task,24,lease,parent,target,source_pool,
                'source-bound-disposable-probe',master_path=probe_root/'master.json',admission_path=lease_path,
                study=study,kind='assessment' if case=='admin_accounting' else 'numerical',estimated_cpu_seconds=50.)
            wait_file(report,time.time()+30)
            record=dict(case=case,unit=saved['unit'],observation=read(report))
            if case=='positive_thread_violation':
                try:pool.hardening().strict_worker_policy(system,saved)
                except RuntimeError as expected:
                    record['expected_rejection']=str(expected)
                    if 'active process OS thread count changed' not in str(expected):
                        raise RuntimeError('thread probe failed at a different policy boundary') from expected
                else:raise RuntimeError('stable two-thread policy violation was not rejected')
                if record['observation']['process']['threads']!=2:raise RuntimeError('thread fault did not reach its intended boundary')
            else:
                if not pool.hardening().strict_worker_policy(system,saved):
                    raise RuntimeError('compliant payload exited before live policy proof')
                if record['observation']['process']['threads']!=1:raise RuntimeError('compliant payload owns additional threads')
            if case=='parent_death':
                props=system.unit(parent_unit);pool.legacy().verify_owned(parent,props)
                if not parent_unit.startswith('pricefm-r150-r152-probe-parent-'):raise RuntimeError('parent-death fault escaped disposable scope')
                subprocess.run(['systemctl','--user','kill','--kill-who=main','--signal=KILL',parent_unit],check=True,timeout=15)
                until=time.time()+25
                while pool.unit_observation(system,saved)['active'] and time.time()<until:time.sleep(.1)
                if pool.unit_observation(system,saved)['active']:raise RuntimeError('parent death did not drain its bound payload')
            elif case!='positive_thread_violation':
                until=time.time()+20
                while pool.unit_observation(system,saved)['active'] and time.time()<until:time.sleep(.1)
                if pool.unit_observation(system,saved)['active']:raise RuntimeError('disposable guard payload failed to complete')
            if case=='admin_accounting':
                admin=Path(saved['accounting_path'])/'observed.json'
                if not admin.exists() or read(admin).get('completed') is not True:
                    raise RuntimeError('same-PID administrative CPU receipt is missing')
                if read(Path(saved['accounting_path'])/'observed.seal.json')['sha256']!=digest(admin):
                    raise RuntimeError('administrative CPU seal differs')
                record['admin_CPU']=read(admin)
            record['cleanup']=pool.drain_exact(system,saved)
            pool.release_slot(saved['global_slot_path'],record['cleanup'])
            result['cases'].append(record)
        if len(result['cases'])!=5:raise RuntimeError('source-bound capability case set is incomplete')
        result['status']='PASS_R152_SOURCE_BOUND_POLICY_LIFECYCLE_AND_DRAIN'
    except BaseException as error:
        result.update(status='FAIL_R152_SOURCE_BOUND_POLICY_LIFECYCLE_AND_DRAIN',error=repr(error))
        raise
    finally:
        if (probe_root/'development').exists():
            try:
                cleanup=pool.drain_scope(system,pool.read_config(ROOT/c['pool_config']),probe_root/'development',
                    'disposable_capability_cleanup',deadline=time.time()+30)
                result['cleanup']=cleanup
                result['cleanup_errors'].extend(cleanup['cleanup_errors'])
            except BaseException as error:result['cleanup_errors'].append(repr(error))
        for parent in parents:
            try:pool.legacy().stop_and_drain(system,parent,timeout=25)
            except BaseException as error:result['cleanup_errors'].append(repr(error))
        if result['cleanup_errors']:result['status']='FAIL_R152_SOURCE_BOUND_POLICY_LIFECYCLE_AND_DRAIN'
        result['finished_epoch']=time.time();immutable(output,result)
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=('freeze','probe','launch','coordinate','status'))
    parser.add_argument('--config',type=Path,default=CONFIG)
    parser.add_argument('--runtime',type=Path)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--release',type=Path)
    parser.add_argument('--probe',type=Path)
    parser.add_argument('--unit')
    args=parser.parse_args();c=read_config(args.config);runtime=args.runtime or Path(c['runtime'])
    if args.action=='freeze':
        if not args.output:parser.error('--output required')
        result=freeze_release(args.output,args.config)
    elif args.action=='probe':
        if not args.output:parser.error('--output required')
        result=capability_probe(args.output,args.config)
    elif args.action=='launch':
        if not args.release or not args.probe:parser.error('--release and --probe required')
        result=launch(args.release,args.probe,args.config)
    elif args.action=='coordinate':
        if not args.unit:parser.error('--unit required')
        result=coordinate(runtime,args.unit,args.config)
    else:result=status(runtime)
    print(json.dumps(result,indent=2,sort_keys=True,allow_nan=False))

if __name__=='__main__':main()
