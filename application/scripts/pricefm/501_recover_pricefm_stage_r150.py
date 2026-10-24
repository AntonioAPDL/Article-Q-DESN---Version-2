#!/usr/bin/env python3
"""R151 resource-only recovery; predictions remain immutable c036 R150 outputs.

The only numerical admissions are canonical R150 waves 2 and 3. This file
composes the immutable 498/500 interfaces without rebinding their globals.
Public ownership/placement primitives are also used by the R151 regional lane.
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

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
CONFIG = ROOT / 'application/config/pricefm_stage_r151_recovery_20261023.json'
SCIENCE_ROOT = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r150_bounded_admission_20261023')
SCIENCE_HEAD = 'c03613cd1a85cce5d02120760b954cdc15160410'
CANONICAL = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/launch_prep/pricefm_stage_r150_bounded_admission_20261023/muscat_resources')
THREAD_VARS = ('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS','BLIS_NUM_THREADS','NUMEXPR_NUM_THREADS','VECLIB_MAXIMUM_THREADS')
PARENT_ROOT = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r151_continuation_recovery_20261023')
PARENT_HEAD = '90ff802d09ca9b6712ccaae052d327fb23beaede'
PARENT_BUNDLE = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021/r151_continuation_implementation_20261023')
PARENT_RUNTIME = CANONICAL.parents[1]/'pricefm_stage_r151_orchestration_20261023'
PARENT_RUN = PARENT_RUNTIME/'runs/991defc791c14310a3d61680dad67afb'
PARENT_REGION_PREP = CANONICAL.parents[1]/'pricefm_stage_r151_region_20261023'
PARENT_REGION_OUT = CANONICAL.parents[2]/'campaigns/pricefm_stage_r151_region_20261023'
_LEGACY = None


def module(name, path):
    spec=importlib.util.spec_from_file_location(name,path)
    result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result)
    if 'numpy' in sys.modules:raise RuntimeError('resource API must remain standard-library only')
    return result


def load_legacy():
    global _LEGACY
    if _LEGACY is None:_LEGACY=module('r151_immutable_r150_resources',SCIENCE_ROOT/'application/scripts/pricefm/498_supervise_pricefm_stage_r150_resources.py')
    return _LEGACY


def read(path):return json.loads(Path(path).read_text())
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def boot():return Path('/proc/sys/kernel/random/boot_id').read_text().strip()
def git(*args):return subprocess.check_output(['git','-C',str(ROOT),*args],text=True).strip()


def immutable(path, value):
    """Single immutable publication, including crash durability of its directory."""
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    data=(json.dumps(value,sort_keys=True,indent=2,allow_nan=False)+'\n').encode()
    with path.open('xb') as stream:stream.write(data);stream.flush();os.fsync(stream.fileno())
    directory=os.open(str(path.parent),os.O_RDONLY)
    try:os.fsync(directory)
    finally:os.close(directory)
    return value


@contextlib.contextmanager
def canonical_lock(path, *, blocking=False):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('a') as stream:
        try:fcntl.flock(stream,fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except BlockingIOError as error:raise RuntimeError('canonical lock already owned: '+str(path)) from error
        try:yield
        finally:fcntl.flock(stream,fcntl.LOCK_UN)


def config():
    c=read(CONFIG)
    if (c['stage']!='R151' or Path(c['science_root'])!=SCIENCE_ROOT or Path(c['canonical_runtime'])!=CANONICAL
        or c['science_head']!=SCIENCE_HEAD or c['admissions']!=['2','3'] or c['wave_seconds']!=7200
        or c['coordinator_seconds']!=14700 or c['cleanup_seconds']!=1800 or c['cpus']!=list(range(15,30))
        or c['max_workers']!=2 or c['global_replacements']!=1 or c['replacement_reserve_CPU_seconds']!=1178.430003
        or c['idle_share']!=0.6724117881123404 or c['historical_charge_CPU_seconds']!=605.174710151
        or c['original_adjusted_CPU_seconds']!=21786.141934839827
        or c.get('manual_successor_parent_head')!=PARENT_HEAD
        or c.get('retirement_contract')!={'path':str(ROOT/'application/config/pricefm_stage_r151_retirement_contract_20261023.json'),
            'sha256':'6e7823c7a3f659ea6b4513e75a9822c3b0812ac5a7c86ae32752c087e3b1dfe5'}
        or c['new_benchmark_authorized'] or c['new_fits_authorized'] or c['baseline_signals_authorized']):
        raise RuntimeError('frozen R151 resource contract differs')
    return c


def capture_new_source():
    if git('status','--porcelain'):raise RuntimeError('new resource source must be committed and clean')
    paths=git('ls-files','-z').split('\0')
    hashes={name:digest(ROOT/name) for name in paths if name and (ROOT/name).is_file()}
    return dict(root=str(ROOT),path=str(ROOT),head=git('rev-parse','HEAD'),branch=git('branch','--show-current'),sha256=hashes,
        runtime_sha256={k:v for k,v in hashes.items() if k.startswith(('application/scripts/pricefm/','application/config/pricefm_'))},
        idle_wrapper_sha256=digest('/usr/bin/chrt'))


def verify_new_source(source, *, full=False):
    if source['root']!=str(ROOT) or git('rev-parse','HEAD')!=source['head'] or git('status','--porcelain'):
        raise RuntimeError('new resource source HEAD/root/cleanliness changed')
    if digest('/usr/bin/chrt')!=source['idle_wrapper_sha256']:raise RuntimeError('idle exec wrapper changed')
    for path,want in (source['sha256'] if full else source['runtime_sha256']).items():
        if digest(ROOT/path)!=want:raise RuntimeError('new resource source bytes changed: '+path)


def retirement_contract():
    pin=config()['retirement_contract']
    if digest(pin['path'])!=pin['sha256']:raise RuntimeError('retirement contract source bytes changed')
    proof=read(pin['path']);admission=read(CANONICAL/'admission.json')
    unit='pricefm-r141-muscat.service';saved=admission['baseline']['units'][unit]
    if (proof.get('status')!='REVIEWED_EXPECTED_LT_CERTIFICATE_BOUNDARY_RETIREMENT_NOT_BASELINE_RECOVERY'
        or proof.get('retired_unit')!=unit or proof.get('original_admission_path')!=str(CANONICAL/'admission.json')
        or proof.get('original_admission_sha256')!=digest(CANONICAL/'admission.json')
        or proof.get('original_saved_process')!=saved['process'] or proof.get('original_saved_properties')!=saved['properties']
        or proof.get('expected_cgroup')!=saved['properties']['ControlGroup']
        or proof.get('old_pid_gone') is not True or proof.get('old_LT_controller_pid_gone') is not True
        or proof.get('live_LT_processes')!=[] or proof.get('worker_signals')!=0 or proof.get('baseline_mutations')!=0
        or proof.get('LT_AT_repair_admitted') is not False or proof.get('new_model_fits')!=0
        or proof.get('remaining_original_units_require_unchanged_lifetimes') is not True
        or proof.get('handoff_must_remain_waiting_boundary_same_attempt') is not True
        or proof['LT_progress']['active']!=0 or proof['LT_progress']['completed']!=49 or proof['LT_progress']['pending']!=10
        or proof['host_blocked']['active']!={} or proof['host_blocked']['status']!='blocked'
        or proof['host_blocked']['health']['healthy'] is not True):
        raise RuntimeError('specific retired baseline boundary contract differs')
    for path,want in proof['pinned_evidence_sha256'].items():
        if digest(path)!=want:raise RuntimeError('retirement boundary source/evidence changed: '+path)
    head=subprocess.check_output(['git','-C',proof['baseline_source_root'],'rev-parse','HEAD'],text=True).strip()
    if head!=proof['baseline_source_head']:raise RuntimeError('retired baseline source HEAD changed')
    return proof


def verify_retired_baseline(system,proof,saved):
    """Exactly the attested absent R141 lifetime; never accept another owner."""
    r=load_legacy();props=system.unit(proof['retired_unit'])
    expected=proof['observed_retired_properties']
    keys=('Id','LoadState','ActiveState','MainPID','InvocationID','ControlGroup')
    if (any(props.get(k)!=expected.get(k) for k in keys)
        or props.get('LoadState')!='not-found' or props.get('ActiveState')!='inactive'
        or props.get('MainPID')!='0' or props.get('InvocationID') or props.get('ControlGroup')
        or saved['process']!=proof['original_saved_process'] or saved['properties']!=proof['original_saved_properties']
        or r.process(saved['process']['pid']) is not None or r.process(proof['old_LT_controller_pid']) is not None
        or system.members(proof['expected_cgroup'])):
        raise RuntimeError('retired R141 baseline reappeared, changed or is not fully drained')
    return dict(unit=proof['retired_unit'],retired_absent=True,old_cgroup_empty=True)


def assert_parent_region_unused():
    # The old namespace is prepared metadata, not an unused budget allocation
    # that can coexist with the one successor namespace.
    for parent in (PARENT_REGION_PREP,PARENT_REGION_OUT):
        for name in ('muscat_resources','benchmark','tasks_done','checkpoints','cpu_accounting','decisions','assessment.json','assessment_seal.json'):
            path=parent/name
            if path.exists():raise RuntimeError('original regional namespace acquired numerical/runtime work: '+str(path))
    if not (PARENT_REGION_PREP/'prepared.json').is_file():raise RuntimeError('original region preparation identity absent')


def parent_history_paths():
    paths=[PARENT_BUNDLE/'source_release_immutable.json',PARENT_RUNTIME/'launch.json']
    paths+=list(PARENT_RUN.rglob('*.json'))
    paths+=list((CANONICAL/'recoveries').rglob('*.json'))
    paths+=list(PARENT_REGION_PREP.glob('*.json'))+list((PARENT_REGION_OUT/'tasks').glob('*.json'))
    return sorted(set(paths))


def parent_control_capsules():
    paths=list(PARENT_RUN.glob('coordinator/intent.json'))
    paths+=list((CANONICAL/'recoveries').glob('*/coordinator/intent.json'))
    paths+=list((CANONICAL/'recoveries').glob('*/wave_*/intent.json'))
    return [control_capsule(p.parent) for p in sorted(paths)]


def parent_worker_capsules():
    r=load_legacy();folders=[CANONICAL/'wave_2',CANONICAL/'wave_3']
    folders+=list((CANONICAL/'recoveries').glob('*/assessment'))
    folders+=list((CANONICAL/'recoveries').glob('*/wave_*'))
    return [saved for folder in folders for saved in r.discover_workers(folder)]


def assert_capsules_drained(system,capsules):
    r=load_legacy()
    for saved in capsules:
        props=system.unit(saved['unit']);r.verify_owned(saved,props)
        cg=saved.get('attested',{}).get('ControlGroup') or saved.get('expected_cgroup')
        if (not cg or props.get('ActiveState') not in ('inactive','failed') or props.get('MainPID','0')!='0' or system.members(cg)):
            raise RuntimeError('prior failed R151 control has not fully drained')
    return True


def verify_parent_source(*,full=False):
    release=read(PARENT_BUNDLE/'source_release_immutable.json');source=release['source']
    head=subprocess.check_output(['git','-C',str(PARENT_ROOT),'rev-parse','HEAD'],text=True).strip()
    dirty=subprocess.check_output(['git','-C',str(PARENT_ROOT),'status','--porcelain'],text=True)
    if head!=PARENT_HEAD or source['head']!=PARENT_HEAD or dirty:raise RuntimeError('immutable prior R151 source changed')
    for path,want in (source['sha256'] if full else source['runtime_sha256']).items():
        if digest(PARENT_ROOT/path)!=want:raise RuntimeError('immutable prior R151 source bytes changed')
    terminal=read(PARENT_RUN/'terminal.json')
    if (terminal.get('status')!='R151_FINITE_WORKFLOW_GUARD_STOPPED' or terminal.get('cleanup_verified') is not True
        or terminal.get('cleanup_errors') or terminal.get('source_head')!=PARENT_HEAD
        or terminal.get('original_stop_reason')!="RuntimeError('protected baseline lifecycle changed: pricefm-r141-muscat.service')"):
        raise RuntimeError('prior failed R151 disposition changed')
    assert_parent_region_unused()
    return source


def history_paths():
    names=['admission.json','workflow_launch.json','workflow_plan.json','workflow_terminal.json',
           'wave_1/lease.json','wave_1/terminal.json','wave_1/events.jsonl','wave_1/controller_launch.json']
    # The recovery design explicitly freezes all already-published wave-1 worker
    # lifetime evidence, including policy receipts. Never rewrite it on recovery.
    paths=[CANONICAL/name for name in names]
    paths += list((CANONICAL/'wave_1/workers').glob('*/*.json'))
    paths += parent_history_paths()
    return sorted(set(paths))


def freeze_release(output):
    c=config();r=load_legacy();oldc=r.read(r.CONFIG)
    r.assert_parent_policy(oldc);r.verify_source(read(CANONICAL/'admission.json')['source'],full=True)
    science=r.load_science();prep=science.read_preparation()
    science.verify_hashes(prep['source_sha256']);science.verify_hashes(prep['input_sha256'])
    r.verify_baseline_sources(oldc);r.verify_benchmark_import(oldc,r.System())
    old=read(CANONICAL/'admission.json')
    retirement=retirement_contract();verify_parent_source(full=True)
    prior_capsules=parent_control_capsules();prior_workers=parent_worker_capsules()
    assert_capsules_drained(r.System(),prior_capsules+prior_workers)
    result=dict(status='PASS_R151_DUAL_SOURCE_RELEASE',created_epoch=time.time(),source=capture_new_source(),
        science_root=str(SCIENCE_ROOT),science_head=SCIENCE_HEAD,science_source=old['source'],
        historical_sha256={str(p):digest(p) for p in history_paths()},original_admission_sha256=digest(CANONICAL/'admission.json'),
        benchmark_import_sha256=oldc['benchmark_import']['sha256'],config_sha256=digest(CONFIG),
        allowed_admissions=['2','3'],no_new_benchmark=True,new_fits=0,baseline_worker_signals=0,
        manual_successor_parent_head=PARENT_HEAD,retirement_contract_sha256=c['retirement_contract']['sha256'],
        prior_R151_control_capsules=prior_capsules,prior_R151_worker_capsules=prior_workers,original_global_expires_epoch=read(PARENT_RUN/'context.json')['expires_epoch'])
    result['new_source']=result['source'];result['old_science']=result['science_source']
    immutable(output,result);return result


def verify_release(release, *, full=False):
    c=config();r=load_legacy();oldc=read(r.CONFIG)
    if (release['status']!='PASS_R151_DUAL_SOURCE_RELEASE' or release['science_root']!=str(SCIENCE_ROOT)
        or release['science_head']!=SCIENCE_HEAD or release['config_sha256']!=digest(CONFIG)
        or release['original_admission_sha256']!=digest(CANONICAL/'admission.json')
        or release['benchmark_import_sha256']!=oldc['benchmark_import']['sha256']
        or not isinstance(release.get('prior_R151_worker_capsules'),list)
        or not isinstance(release.get('prior_R151_control_capsules'),list)
        or len(release['prior_R151_control_capsules'])<2
        or release.get('original_global_expires_epoch')!=read(PARENT_RUN/'context.json')['expires_epoch']):
        raise RuntimeError('dual-source release identity differs')
    if release.get('new_source')!=release['source'] or release.get('old_science')!=release['science_source']:raise RuntimeError('source aliases differ')
    if release.get('manual_successor_parent_head')!=PARENT_HEAD or release.get('retirement_contract_sha256')!=c['retirement_contract']['sha256']:
        raise RuntimeError('manual successor source/retirement identity differs')
    verify_parent_source(full=full);retirement_contract()
    verify_new_source(release['source'],full=full);r.verify_source(release['science_source'],full=full)
    for path,want in release['historical_sha256'].items():
        if digest(path)!=want:raise RuntimeError('immutable original R150 history changed: '+path)
    r.verify_benchmark_import(oldc)
    return c,oldc


def passive_placement(cpus, samples=5, interval=1.):
    if samples<3 or interval<=0:raise RuntimeError('placement needs sustained passive observations')
    def counters():
        found={}
        for line in Path('/proc/stat').read_text().splitlines():
            cols=line.split()
            if cols and cols[0].startswith('cpu') and cols[0][3:].isdigit() and int(cols[0][3:]) in cpus:
                vals=list(map(int,cols[1:]));found[int(cols[0][3:])]=(sum(vals[:8]),vals[3]+vals[4])
        if set(found)!=set(cpus):raise RuntimeError('incomplete passive CPU visibility')
        return found
    first=counters();observations=[]
    for _ in range(samples):
        time.sleep(interval);second=counters();row={}
        for cpu in cpus:
            total=second[cpu][0]-first[cpu][0];idle=second[cpu][1]-first[cpu][1]
            row[cpu]=1-idle/total if total>0 else 1.
        observations.append(row);first=second
    # Physical-core uniqueness is checked, not inferred from logical CPU count.
    topology={cpu:(Path('/sys/devices/system/cpu/cpu%d/topology/physical_package_id'%cpu).read_text().strip(),
                         Path('/sys/devices/system/cpu/cpu%d/topology/core_id'%cpu).read_text().strip()) for cpu in cpus}
    if len(set(topology.values()))!=len(cpus):raise RuntimeError('eligible CPUs include SMT siblings')
    means={cpu:sum(row[cpu] for row in observations)/len(observations) for cpu in cpus}
    return dict(epoch=time.time(),samples=observations,mean_busy=means,physical_core=topology,
                ranked=sorted(cpus,key=lambda cpu:(means[cpu],cpu)),reservation=False,benchmark=False)


def start_control(system,c,folder,role,argv,runtime_seconds,parent=None):
    """Persist UUID intent before start; publish separate immutable attestation."""
    r=load_legacy();folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    unit=argv[-1] if argv and str(argv[-1]).endswith('.service') else 'pricefm-r150-'+role+'-'+uuid.uuid4().hex+'.service'
    if unit not in argv:raise RuntimeError('control argv must contain its exact unit identity')
    if parent:
        parentprops=system.unit(parent['unit']);r.verify_owned(parent,parentprops)
        hierarchy=str(Path(parentprops['ControlGroup']).parent)
    else:
        admission=read(CANONICAL/'admission.json')
        groups={str(Path(v['properties']['ControlGroup']).parent) for v in admission['baseline']['units'].values()}
        if len(groups)!=1:raise RuntimeError('ambiguous service hierarchy')
        hierarchy=groups.pop()
    intent=dict(unit=unit,argv=list(argv),description='R151 owned '+role+' '+unit,
        expected_cgroup=hierarchy+'/'+unit,role=role,runtime_seconds=runtime_seconds,epoch=time.time(),
        source_entry_path=str(Path(argv[2]).resolve()),source_entry_sha256=digest(argv[2]),source_head=git('rev-parse','HEAD'),parent=parent['unit'] if parent else None)
    immutable(folder/'intent.json',intent)
    best=intent
    try:
        system.start(unit,intent['description'],argv,cpus=c['cpus'],idle=False,runtime_seconds=runtime_seconds,
                     controller=intent['parent'],working_directory=SCIENCE_ROOT,stdout=folder/'stdout')
        props=system.unit(unit);r.verify_owned(intent,props)
        if props.get('InvocationID'):
            best=dict(intent,attested=props);immutable(folder/'observed_lifetime.json',best)
        saved=best
        verify_control(system,saved,c,required_parent=intent['parent'])
        immutable(folder/'attestation.json',saved)
        return saved
    except Exception as error:
        failure=dict(original_error=repr(error),intent=intent,strongest_ownership=best,cleanup_errors=[])
        try:failure['cleanup']=drain_exact(system,best)
        except Exception as cleanup:failure['cleanup_errors'].append(repr(cleanup))
        immutable(folder/'startup_failure.json',failure)
        raise RuntimeError('owned R151 startup failed: '+json.dumps(failure,sort_keys=True)) from error


def await_capsule(folder,timeout=15):
    folder=Path(folder);deadline=time.monotonic()+timeout
    while not (folder/'attestation.json').exists() and time.monotonic()<deadline:time.sleep(.05)
    saved=read(folder/'attestation.json')
    if {k:v for k,v in saved.items() if k!='attested'}!=read(folder/'intent.json'):
        raise RuntimeError('immutable controller capsule differs from prestart intent')
    return saved


def verify_control(system,capsule,c,required_parent=None):
    r=load_legacy();props=system.unit(capsule['unit']);r.verify_owned(capsule,props)
    proc=r.process(int(props.get('MainPID','0')))
    executable=Path(capsule['argv'][2]).resolve()
    if (capsule.get('source_entry_path')!=str(executable) or not executable.is_relative_to(ROOT)
        or digest(executable)!=capsule['source_entry_sha256'] or capsule['source_head']!=git('rev-parse','HEAD')):
        raise RuntimeError('control executable source identity differs')
    if (props.get('ActiveState')!='active' or not props.get('InvocationID')
        or props.get('ControlGroup')!=capsule['expected_cgroup'] or props.get('CPUSchedulingPolicy')!='0'
        or props.get('IOSchedulingClass')!='3' or proc is None or proc['scheduler']!=os.SCHED_OTHER
        or proc['affinity']!=c['cpus'] or r.exec_arguments(props)!=' '.join(capsule['argv'])
        or props.get('WorkingDirectory')!=str(SCIENCE_ROOT)
        or not 0<r.parse_duration(props.get('RuntimeMaxUSec',''))<=capsule['runtime_seconds']):
        raise RuntimeError('new controller lifecycle/policy proof failed')
    if required_parent and (required_parent not in props.get('BindsTo','').split() or required_parent not in props.get('After','').split()):
        raise RuntimeError('new controller lacks parent death binding')
    return props


def owned_groups(system,capsules,workers):
    """All cgroups and descendants, deduplicated, including draining lifetimes."""
    r=load_legacy();pids=set()
    for saved in list(capsules)+list(workers):
        props=system.unit(saved['unit']);r.verify_owned(saved,props)
        cg=saved.get('attested',{}).get('ControlGroup') or saved.get('expected_cgroup') or props.get('ControlGroup')
        if not cg:raise RuntimeError('owned lifetime has no cgroup evidence')
        pids.update(system.members(cg))
    return sorted(pids)


def strict_worker_policy(system,saved):
    r=load_legacy();props=system.unit(saved['unit']);r.verify_owned(saved,props)
    if props.get('ActiveState')!='active':return False
    pid=int(props.get('MainPID','0'));proc=r.process(pid);cpu=saved['cpu']
    if (cpu not in range(15,30) or not proc or proc['affinity']!=[cpu] or proc['scheduler']!=os.SCHED_IDLE
        or props.get('IOSchedulingClass')!='3' or props.get('CPUSchedulingPolicy') not in ('0','5')
        or not props.get('InvocationID') or props.get('InvocationID')!=saved['attested']['InvocationID']
        or props.get('ControlGroup')!=saved.get('expected_cgroup')):
        raise RuntimeError('active worker actual lifecycle/CPU/I/O policy changed')
    for member in system.members(props['ControlGroup']):
        memberproc=r.process(member)
        if memberproc is None:continue # exits have no RSS or runnable payload
        if memberproc['scheduler']!=os.SCHED_IDLE or memberproc['affinity']!=[cpu]:raise RuntimeError('worker descendant policy changed')
        status=Path('/proc/%d/status'%member).read_text()
        threads=next(int(line.split()[1]) for line in status.splitlines() if line.startswith('Threads:'))
        env=dict(part.split(b'=',1) for part in Path('/proc/%d/environ'%member).read_bytes().split(b'\0') if b'=' in part)
        if threads!=1 or any(env.get(name.encode())!=b'1' for name in THREAD_VARS):raise RuntimeError('worker thread policy changed')
        if not subprocess.check_output(['ionice','-p',str(member)],text=True).startswith('idle'):raise RuntimeError('worker actual I/O priority changed')
    return True


def drain_exact(system,saved,timeout=25):
    props=system.unit(saved['unit'])
    if (props.get('LoadState')!='not-found' and props.get('ActiveState') not in ('inactive','failed')
        and props.get('ControlGroup')!=saved.get('expected_cgroup')):
        raise RuntimeError('expected cgroup mismatch; no signal')
    return load_legacy().stop_and_drain(system,saved,timeout=timeout)


def cooperative_drain(system,workers,reason, *, grace=10,deadline=None):
    r=load_legacy();errors=[];proofs=[]
    for saved in workers:
        try:r.atomic(Path(saved['policy_receipt']).parent/'stop_requests'/(saved['task']+'.json'),dict(reason=reason,epoch=time.time(),cooperative=True))
        except Exception as error:errors.append(dict(unit=saved['unit'],operation='request',error=repr(error)))
    until=time.monotonic()+grace
    while time.monotonic()<until and (deadline is None or time.time()<deadline):
        if all(system.unit(saved['unit']).get('ActiveState') in ('inactive','failed') or system.unit(saved['unit']).get('LoadState')=='not-found' for saved in workers):break
        time.sleep(.2)
    for saved in workers:
        try:proofs.append(drain_exact(system,saved))
        except Exception as error:errors.append(dict(unit=saved['unit'],operation='drain',error=repr(error)))
    return dict(cleanup_verified=not errors,cleanup=proofs,cleanup_errors=errors)


def baseline_guard(c,system,admission,coordinator,controller,lease,workers,release,previous_handoff=None,*,extra_capsules=(),extra_workers=()):
    """Replacement for old guard; never depends on the dead 499 workflow."""
    r=load_legacy();verify_release(release)
    if time.time()>=release['original_global_expires_epoch']:raise RuntimeError('original global continuation deadline expired')
    r.assert_parent_policy(c);r.verify_baseline_sources(c)
    if lease is not None and (boot()!=lease['boot_id'] or time.time()>=lease['expires_epoch']):raise RuntimeError('lease expired or boot changed')
    if lease is not None and lease.get('source_head')==SCIENCE_HEAD and lease.get('wave') in ('2','3'):
        if read(CANONICAL/('wave_'+lease['wave'])/'lease.json')!=lease:raise RuntimeError('immutable numerical lease changed')
    if coordinator is None and (controller is not None or lease is not None):raise RuntimeError('preouter guard cannot carry a lease or child controller')
    if coordinator is not None:verify_control(system,coordinator,c,required_parent=coordinator.get('parent'))
    if controller:verify_control(system,controller,c,required_parent=coordinator['unit'])
    handoff=r.handoff_snapshot(c,system,previous_handoff or admission['handoff'])
    retirement=retirement_contract()
    assert_capsules_drained(system,release.get('prior_R151_control_capsules',[])+release.get('prior_R151_worker_capsules',[]))
    for name,saved in admission['baseline']['units'].items():
        if name==retirement['retired_unit']:
            verify_retired_baseline(system,retirement,saved);continue
        props=system.unit(name)
        if (props.get('ActiveState')!='active' or any(props.get(k)!=saved['properties'].get(k) for k in r.BASELINE_STABLE)
            or r.exec_arguments(props)!=r.exec_arguments(saved['properties'])
            or not r.same_lifetime(r.process(int(props.get('MainPID','0'))),saved['process'])):
            raise RuntimeError('protected baseline lifecycle changed: '+name)
    if digest(c['AT_terminal'])!=admission['baseline']['AT_terminal_sha256']:raise RuntimeError('protected AT terminal changed')
    active=[saved for saved in list(workers)+list(extra_workers) if strict_worker_policy(system,saved)]
    if lease is None and active:raise RuntimeError('numerical workers cannot exist before admission')
    if len(active)>2 or len({saved['cpu'] for saved in active})!=len(active):raise RuntimeError('global worker/physical CPU ceiling violated')
    if coordinator is not None and coordinator.get('parent') and coordinator['parent'] not in {v['unit'] for v in extra_capsules}:
        raise RuntimeError('required outer controller capsule missing')
    for capsule in extra_capsules:
        props=system.unit(capsule['unit']);r.verify_owned(capsule,props)
        if (coordinator is not None and capsule['unit']==coordinator.get('parent')) or props.get('ActiveState') in ('active','activating'):
            verify_control(system,capsule,c,required_parent=capsule.get('parent'))
    caps=([coordinator] if coordinator is not None else [])+([controller] if controller else [])+list(extra_capsules)
    pids=owned_groups(system,caps,list(workers)+list(extra_workers))
    if coordinator is None:pids=sorted(set(pids+[os.getpid()]))
    rss=r.rss_gib(pids)
    available=r.memory_available_gib();disk=__import__('shutil').disk_usage(c['disk_path']).free/1024**3
    predicate=dict(epoch=time.time(),handoff=handoff,available_memory_gib=available,disk_free_gib=disk,owned_rss_gib=rss,owned_pids=pids,active_workers=len(active))
    if available<c['min_available_memory_gib'] or disk<c['min_disk_gib'] or rss>c['max_owned_rss_gib']:
        raise RuntimeError('shared-resource/whole-owned-RSS gate failed: '+json.dumps(predicate))
    return predicate


def start_payload(system,c,folder,task,cpu,lease,controller,target_argv,source,probe_sha,stage='R151'):
    """Generic new-source launcher. EE continues to use old498.start_worker."""
    r=load_legacy();token=uuid.uuid4().hex;folder=Path(folder)/'workers'/token;folder.mkdir(parents=True)
    unit='pricefm-r150-regional-'+token+'.service';receipt_path=folder/'policy_receipt.json'
    target=[str(v).replace('{policy_receipt}',str(receipt_path)) for v in target_argv]
    spec=dict(cpu=cpu,source_head=source['head'],source_entry_sha256=digest(ENTRY),expires_epoch=lease['expires_epoch'],
        release_receipt=str(receipt_path),target_argv=target,task=task['name'],stage=stage)
    immutable(folder/'bootstrap_spec.json',spec)
    argv=r.idle_command([c['python_runtime'],'-B',str(ENTRY),'bootstrap','--spec',str(folder/'bootstrap_spec.json')])
    saved=dict(unit=unit,token=token,task=task['name'],cpu=cpu,description='R151 owned regional '+token,argv=argv,
        expected_cgroup=str(Path(controller['attested']['ControlGroup']).parent/unit),policy_receipt=str(receipt_path),
        lease_id=lease['lease_id'],estimated_cpu_seconds=task.get('estimated_cpu_seconds',0),ledger_path=str(folder/'ownership.json'),started_epoch=time.time())
    immutable(folder/'intent.json',saved)
    # Old discovery expects ownership.json even if start dies before acknowledgement.
    r.atomic(folder/'ownership.json',saved)
    try:
        system.start(unit,saved['description'],argv,cpus=[cpu],idle=True,runtime_seconds=lease['expires_epoch']-time.time(),
            controller=controller['unit'],working_directory=SCIENCE_ROOT,stdout=folder/'stdout')
        props=system.unit(unit);r.verify_owned(saved,props)
        if props.get('InvocationID'):
            saved['attested']=props;r.atomic(folder/'ownership.json',saved)
            immutable(folder/'observed_lifetime.json',saved)
        if not props.get('InvocationID') or props.get('ControlGroup')!=saved['expected_cgroup']:
            raise RuntimeError('generic payload actual identity/cgroup not attested')
        deadline=time.monotonic()+3;proc=r.process(int(props.get('MainPID','0')))
        while proc and proc['scheduler']!=os.SCHED_IDLE and time.monotonic()<deadline:
            time.sleep(.02);proc=r.process(int(props.get('MainPID','0')))
        saved.update(attested=props,process=proc)
        if controller['unit'] not in props.get('BindsTo','').split() or controller['unit'] not in props.get('After','').split():raise RuntimeError('payload lacks exact controller dependency')
        if (not strict_worker_policy(system,saved) or proc is None or not props.get('ControlGroup')
            or not props.get('InvocationID') or props.get('ControlGroup')!=saved['expected_cgroup'] or system.members(props['ControlGroup'])!=[proc['pid']]
            or props.get('KillMode')!='control-group' or props.get('Restart')!='no'
            or not 0<r.parse_duration(props.get('RuntimeMaxUSec',''))<=lease['seconds']):
            raise RuntimeError('generic payload startup proof failed')
        saved['cpu_sample']=dict(pid=proc['pid'],start_ticks=proc['start_ticks'],boot_id=proc['boot_id'],epoch=time.monotonic(),monotonic=True,cpu_seconds=r.cpu_seconds(proc['pid']))
        r.atomic(folder/'ownership.json',saved)
        receipt=dict(schema_version=1,stage=stage,task=task['name'],cpu=cpu,expected_affinity=[cpu],expected_scheduler=5,numerical_threads=1,io_class=3,
            unit=unit,controller_unit=controller['unit'],source_head=source['head'],source_sha256=source['sha256'],lease_id=lease['lease_id'],
            lease_expires_epoch=lease['expires_epoch'],worker_invocation_id=props['InvocationID'],worker_cgroup=props['ControlGroup'],probe_id=probe_sha,
            actual_probe=dict(properties=props,process=proc),stop_request_path=str(folder/'stop_requests'/(task['name']+'.json')))
        immutable(receipt_path,receipt);return saved
    except Exception as original:
        failure=dict(original_error=repr(original),intent=read(folder/'intent.json'),strongest_ownership=saved,cleanup_errors=[])
        try:failure['cleanup']=drain_exact(system,saved)
        except Exception as error:failure['cleanup_errors'].append(repr(error))
        immutable(folder/'startup_failure.json',failure)
        raise RuntimeError('generic payload startup failed: '+json.dumps(failure,sort_keys=True)) from original


def bootstrap(spec_path):
    r=load_legacy();spec=read(spec_path)
    if digest(ENTRY)!=spec['source_entry_sha256'] or git('rev-parse','HEAD')!=spec['source_head']:raise RuntimeError('new payload bootstrap source changed')
    if os.sched_getaffinity(0)!={spec['cpu']} or os.sched_getscheduler(0)!=os.SCHED_IDLE or any(os.environ.get(k)!='1' for k in THREAD_VARS):raise RuntimeError('payload first exec policy differs')
    until=min(time.time()+20,spec['expires_epoch'])
    while not Path(spec['release_receipt']).is_file() and time.time()<until:time.sleep(.05)
    receipt=read(spec['release_receipt'])
    if any(receipt.get(k)!=spec[k] for k in ('stage','task','cpu','source_head')) or receipt['lease_expires_epoch']!=spec['expires_epoch'] or time.time()>=until:raise RuntimeError('new payload release differs')
    os.execv(spec['target_argv'][0],spec['target_argv'])


def _claim_unused(root,wave,admission_sha,provenance,validate,*,now=None,boot_id=None):
    """Exactly one flock acquisition; existing leases are never joined."""
    root=Path(root)
    with canonical_lock(root/'lease.lock',blocking=True):
        if wave not in ('2','3'):raise RuntimeError('only unused wave2 then3 are authorized')
        unknown=[p.name for p in root.glob('wave_*') if p.name not in ('wave_1','wave_2','wave_3')]
        if unknown:raise RuntimeError('unknown canonical numerical namespace: '+repr(unknown))
        existing=[w for w in ('1','2','3') if (root/('wave_'+w)/'lease.json').exists()]
        if '1' not in existing or wave in existing or (wave=='3' and '2' not in existing):raise RuntimeError('admission already consumed or out of sequence')
        if wave=='2' and '3' in existing:raise RuntimeError('later admission already exists')
        validate()
        epoch=time.time() if now is None else now
        lease=dict(schema_version=1,stage='R150',wave=wave,lease_id=uuid.uuid4().hex,started_epoch=epoch,expires_epoch=epoch+7200,
            seconds=7200,source_head=SCIENCE_HEAD,admission_sha256=admission_sha,boot_id=boot() if boot_id is None else boot_id,nonrenewing=True,
            recovery=provenance)
        immutable(root/('wave_'+wave)/'lease.json',lease)
        return lease


def all_workers():
    r=load_legacy();return [saved for folder in CANONICAL.glob('wave_*') for saved in r.discover_workers(folder)]


def assert_drained_history(system,release):
    r=load_legacy();verify_release(release)
    records=[read(CANONICAL/'workflow_launch.json'),read(CANONICAL/'wave_1/controller_launch.json')]+r.discover_workers(CANONICAL/'wave_1')
    for record in records:
        if 'argv' not in record:record=dict(record,argv=record['command'])
        props=system.unit(record['unit']);r.verify_owned(record,props)
        cg=record.get('attested',{}).get('ControlGroup') or record.get('expected_cgroup') or props.get('ControlGroup')
        if not cg or props.get('ActiveState') not in ('inactive','failed') or props.get('MainPID','0')!='0' or system.members(cg):
            raise RuntimeError('old lifecycle is not independently drained')
    return True


def parent_admission_deadline(coordinator,actual_runtime_seconds,seconds,*,now=None):
    """A child admission must fit its parent's existing lifetime, with no reset."""
    now=time.time() if now is None else now
    values=(coordinator['epoch'],coordinator['runtime_seconds'],actual_runtime_seconds,seconds,now)
    if any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) for v in values):
        raise RuntimeError('parent finite lifetime evidence invalid')
    expires=coordinator['epoch']+min(coordinator['runtime_seconds'],actual_runtime_seconds)
    if actual_runtime_seconds<=0 or seconds<=0 or expires-now<seconds+5.:
        raise RuntimeError('parent finite lifetime cannot contain entire next admission')
    return expires


def claim_lease(c,system,wave,release,recovery,coordinator):
    if Path(c['canonical_runtime'])!=CANONICAL:raise RuntimeError('lease root cannot redirect')
    def validate():
        oldc=read(load_legacy().CONFIG)
        actual=verify_control(system,coordinator,oldc,required_parent=coordinator.get('parent'))
        parent_admission_deadline(coordinator,load_legacy().parse_duration(actual['RuntimeMaxUSec']),c['wave_seconds'])
        assert_drained_history(system,release)
        # A live controller conflict fails before a lease is created. Hold only
        # briefly here; never keep this lock while the child must acquire it.
        with canonical_lock(CANONICAL/'controller.lock'):pass
        if wave=='3':
            prior=read(CANONICAL/'wave_2/terminal.json')
            if prior.get('cleanup_verified') is not True or prior.get('status') not in ('R150_WAVE_COMPLETE','R150_WAVE_DEFERRED'):
                raise RuntimeError('preceding admission did not permit automatic continuation')
            for saved in load_legacy().discover_workers(CANONICAL/'wave_2'):
                props=system.unit(saved['unit']);load_legacy().verify_owned(saved,props)
                cg=saved.get('attested',{}).get('ControlGroup') or saved.get('expected_cgroup')
                if not cg or system.members(cg) or props.get('ActiveState') not in ('inactive','failed'):raise RuntimeError('preceding worker not drained')
    provenance=dict(recovery_id=recovery,resource_head=release['source']['head'],resource_release_sha256=digest(recovery_folder(recovery)/'release.json'),
        coordinator_unit=coordinator['unit'],coordinator_invocation_id=coordinator['attested']['InvocationID'])
    return _claim_unused(CANONICAL,wave,release['original_admission_sha256'],provenance,validate)


def recovery_folder(recovery):
    if len(recovery)!=32 or any(c not in '0123456789abcdef' for c in recovery):raise RuntimeError('invalid UUID recovery namespace')
    return CANONICAL/'recoveries'/recovery


def control_capsule(folder):
    """Never downgrade a published observed InvocationID to weak launch intent."""
    folder=Path(folder);intent=read(folder/'intent.json')
    for name in ('attestation.json','observed_lifetime.json'):
        if (folder/name).exists():
            saved=read(folder/name)
            if {k:v for k,v in saved.items() if k!='attested'}!=intent:raise RuntimeError('control lifetime differs from immutable intent')
            return saved
    return intent


class AttestingSystem:
    """Wrap a legacy start_worker call; retain first observed identity on failure.

    This is an explicit service object passed through the immutable API. No old
    module/global is replaced. Old numerical code and policy receipt stay intact.
    """
    def __init__(self,system,runtime):self.system=system;self.runtime=Path(runtime)
    def __getattr__(self,name):return getattr(self.system,name)
    def unit(self,name):
        props=self.system.unit(name);r=load_legacy()
        for path in (self.runtime/'workers').glob('*/ownership.json'):
            saved=read(path)
            if saved['unit']!=name:continue
            if saved.get('attested'):
                r.verify_owned(saved,props);continue
            r.verify_owned(saved,props)
            if props.get('InvocationID'):
                strong=dict(saved,attested=props)
                r.atomic(path,strong) # authoritative discovery ledger first
                immutable(path.parent/'observed_lifetime.json',strong)
            if props.get('ActiveState') in ('active','activating') and props.get('ControlGroup')!=saved.get('expected_cgroup'):
                raise RuntimeError('legacy worker cgroup differs before release')
        return props


def recovery_capsules(recovery):
    folder=recovery_folder(recovery)
    capsules=[control_capsule(p.parent) for p in sorted(folder.glob('*/intent.json'))]
    if (folder/'outer_capsule.json').exists():capsules.append(read(folder/'outer_capsule.json'))
    return capsules


def recovery_attempts():
    r=load_legacy();return [saved for wave in ('2','3') for saved in r.discover_workers(CANONICAL/('wave_'+wave))]


def attempt_charge(saved,science,prep):
    """Known overruns raise reservations; only completed final receipts earn credit."""
    estimate=prep['pricing']['task_estimates'][saved['task']]['estimated_cpu_seconds']
    invocation=saved.get('attested',{}).get('InvocationID');live=0.
    # Bootstrap exec changes argv but not pid/start_ticks/boot_id. Those fields
    # bind this read-only CPU lower bound; no PID is ever signalled here.
    try:
        prior=saved['process'];r=load_legacy();current=r.process(prior['pid'])
        if current and all(current[k]==prior[k] for k in ('pid','start_ticks','boot_id')):
            amount=r.cpu_seconds(prior['pid'])
            if amount is not None and math.isfinite(amount) and amount>=0:live=amount+5.
    except (KeyError,OSError,TypeError,ValueError):pass
    floor=max(estimate,live)
    try:
        folder=science.OUT/'cpu_accounting'/saved['task']/invocation
        started=read(folder/'started.json');value=read(folder/'observed.json')
        task=science.task_by_name(saved['task'],prep)
        if (read(folder/'observed.seal.json')!={'sha256':digest(folder/'observed.json'),'source':prep['source']}
            or started['source']!=prep['source'] or started['task']!=saved['task'] or started['policy_invocation_id']!=invocation
            or started['scientific_identity_sha256']!=task['scientific_identity_sha256'] or any(value.get(k)!=v for k,v in started.items())
            or digest(started['policy_receipt_path'])!=started['policy_receipt_sha256']
            or started['policy_receipt_path']!=saved['policy_receipt'] or type(value['completed_component']) is not bool
            or value['post_observation_exit_allowance_CPU_seconds']!=5.):raise RuntimeError('receipt identity incomplete')
        policy=read(started['policy_receipt_path'])
        if policy.get('worker_invocation_id')!=invocation or policy.get('task')!=saved['task'] or policy.get('source_head')!=SCIENCE_HEAD:
            raise RuntimeError('receipt policy source/invocation changed')
        numbers=[value[k] for k in ('observed_process_CPU_seconds','observed_terminated_children_CPU_seconds','observed_total_CPU_seconds')]
        if any(isinstance(n,bool) or not isinstance(n,(float,int)) or not math.isfinite(n) or n<0 for n in numbers) or not math.isclose(sum(numbers[:2]),numbers[2],abs_tol=1e-9):raise RuntimeError('receipt amount invalid')
        observed=numbers[2]+5.
        if (value['completed_component'] and science.task_complete(saved['task'])
            and value['task_final_seal_sha256']==digest(science.OUT/'tasks_done'/saved['task']/'completed_evidence.json')):
            return max(observed,live)
        return max(floor,observed)
    except (OSError,KeyError,TypeError,ValueError,RuntimeError):return floor


def remaining_capacity(c,leases,*,now=None):
    now=time.time() if now is None else now
    seconds=0.
    for wave in ('2','3'):
        lease=leases.get(wave)
        if lease is None:seconds+=5400*2
        elif (CANONICAL/('wave_'+wave)/'terminal.json').exists():continue
        else:seconds+=max(0.,min(5400.,lease['expires_epoch']-1800-now))*2
    return seconds*c['idle_share']


def scheduling_projection(tasks,current_seconds,future_waves,*,workers=2):
    """Nonpreemptive list scheduling with D-before-S phase barriers.

    Timeline coordinates count only the finite 90min compute windows; moving to
    a later window does not spend the previous window's cleanup reserve.
    """
    durations=[max(0.,current_seconds)]+[5400.]*future_waves
    bounds=[];offset=0.
    for duration in durations:
        bounds.append((offset,offset+duration));offset+=duration
    ends=[[start]*workers for start,_ in bounds];allocation=[];barrier=0.
    for phase in sorted({t.get('phase',0) for t in tasks}):
        stage=[t for t in tasks if t.get('phase',0)==phase]
        phase_ends=[]
        for task in sorted(stage,key=lambda t:(0 if 'fixed_slot' in t else 1,-t['estimated_wall_seconds'],t['name'])):
            wall=task['estimated_wall_seconds'];choices=[]
            for wave,(start,stop) in enumerate(bounds):
                for worker in range(workers):
                    if 'fixed_slot' in task and (wave!=0 or worker!=task['fixed_slot']):continue
                    begin=max(start,ends[wave][worker],barrier)
                    if begin+wall<=stop:choices.append((begin+wall,begin,wave,worker))
            if not choices:
                return dict(fits=False,bins_remaining=[bounds[w][1]-v for w,row in enumerate(ends) for v in row],unplaced=task['name'],allocation=allocation)
            finish,begin,wave,worker=min(choices,key=lambda v:(v[2],bounds[v[2]][1]-v[0],v[3]));ends[wave][worker]=finish;phase_ends.append(finish)
            allocation.append(dict(task=task['name'],slot=wave*workers+worker,phase=phase,start=begin,end=finish,wall_seconds=wall))
        if phase_ends:barrier=max(phase_ends)
    return dict(fits=True,bins_remaining=[bounds[w][1]-v for w,row in enumerate(ends) for v in row],allocation=allocation,phase_barrier_respected=True)


def replacement_reserve(c,attempts):
    """Do not spend a token's reserve while its predecessor is unaccounted."""
    try:
        token=read(CANONICAL/'r151_replacement_token.json')
        proof=read(CANONICAL/'r151_replacement_drain.json')
        old=next(saved for saved in attempts if saved['unit']==token['old_unit'])
        if (proof['token_sha256']!=digest(CANONICAL/'r151_replacement_token.json')
            or proof['old_unit']!=old['unit'] or proof['lease_id']!=token['lease_id']
            or old['attested']['InvocationID']!=token['old_invocation_id']
            or proof['drain']['cleanup_verified'] is not True or proof['drain']['cleanup_errors']
            or not proof['drain']['cleanup'] or not all(v['drained'] for v in proof['drain']['cleanup'])):
            raise RuntimeError('replacement drain provenance incomplete')
        # The token cannot be reused. Every old/new attempt retains its charge;
        # any not-yet-started replacement is still full pending work in projection.
        return 0.
    except (OSError,ValueError,KeyError,TypeError,StopIteration,RuntimeError):
        return c['replacement_reserve_CPU_seconds']


def resource_projection(c,science,queue,leases,active=(),*,now=None):
    prep=science.read_preparation();prices=dict(prep['pricing']['task_estimates']);attempts=recovery_attempts()
    now=time.time() if now is None else now
    charged=sum(attempt_charge(saved,science,prep) for saved in attempts)
    attempted={saved['task'] for saved in attempts};active_names={saved['task'] for saved in active}
    pending=[n for n in queue['pending'] if n not in active_names]
    envelope=[]
    if queue['phase'] in ('DETERMINISTIC_POOL','NOMINATION_REQUIRED'):
        # Componentwise maxima dominate every possible fixed A/B pair, including
        # task-shape fragmentation. No candidate scores enter this projection.
        columns=[]
        for package in prep['packages']:
            if package['package_id']==prep['control']:continue
            names=science.names_for([package['package_id']],'S',[0])
            if not columns:columns=[[] for _ in names]
            if len(names)!=len(columns):raise RuntimeError('S0 split envelope changed')
            for index,name in enumerate(names):
                if not science.task_complete(name):columns[index].append(prices[name])
        for nominee in (1,2):
            for index,column in enumerate(columns):
                if not column:continue
                name='__nominee%d_split%d_S_seed0_envelope__'%(nominee,index+1)
                prices[name]=dict(estimated_cpu_seconds=max(v['estimated_cpu_seconds'] for v in column),
                    estimated_wall_seconds=max(v['estimated_wall_seconds'] for v in column))
                envelope.append(dict(name=name,**prices[name]))
                pending.append(name)
        control=[n for n in science.names_for([prep['control']],'S',[0]) if not science.task_complete(n) and n not in active_names]
        pending=list(dict.fromkeys(pending+control))
    # Active reservations are already in charged; their future compute still
    # consumes a current-window bin and remaining delivered capacity.
    outstanding=sum(prices[n]['estimated_cpu_seconds'] for n in pending)
    active_cpu=sum(prices[n]['estimated_cpu_seconds'] for n in active_names)
    reserve=replacement_reserve(c,attempts)
    original=c['historical_charge_CPU_seconds']+charged+outstanding+reserve
    future=outstanding+active_cpu+reserve
    cap=remaining_capacity(c,leases,now=now)
    latest=max(leases) if leases else None
    current=max(0.,leases[latest]['expires_epoch']-1800-now) if latest else 5400.
    if latest and (CANONICAL/('wave_'+latest)/'terminal.json').exists():current=0.
    future_waves=len([w for w in ('2','3') if w not in leases])
    if latest is None:future_waves-=1
    tasks=[dict(name=n,phase=(1 if '_S_seed' in n or n.endswith('S') else 0),**prices[n]) for n in pending+sorted(active_names)]
    active_slots={saved['task']:saved['resource_slot'] for saved in active if 'resource_slot' in saved}
    for task in tasks:
        if task['name'] in active_slots:task['fixed_slot']=active_slots[task['name']]
    if reserve:
        tasks.append(dict(name='__single_replacement_reserve__',phase=1,estimated_cpu_seconds=reserve,estimated_wall_seconds=reserve/c['idle_share']))
    packing=scheduling_projection(tasks,current,future_waves)
    return dict(original_cumulative_CPU_seconds=original,original_limit_CPU_seconds=c['original_adjusted_CPU_seconds'],
        remaining_projected_CPU_seconds=future,remaining_adjusted_capacity_CPU_seconds=cap,
        recovery_attempt_charges_CPU_seconds=charged,replacement_reserve_CPU_seconds=reserve,
        original_fits=original<=c['original_adjusted_CPU_seconds'] and original<=32400.,remaining_fits=future<=cap,
        packing=packing,initial_S_componentwise_envelope=envelope,fits=original<=c['original_adjusted_CPU_seconds'] and original<=32400. and future<=cap and packing['fits'])


def reserve_replacement(c,recovery,saved,lease,projection):
    if not projection['fits'] or time.time()>=lease['expires_epoch']-c['cleanup_seconds']:raise RuntimeError('replacement lacks original/remaining resource capacity')
    # Global canonical token, consumed before any cooperative stop. No retry of
    # a crash between token publication and actual replacement.
    with canonical_lock(CANONICAL/'replacement.lock',blocking=True):
        token=CANONICAL/'r151_replacement_token.json'
        if token.exists():raise RuntimeError('single global replacement already consumed')
        value=dict(recovery_id=recovery,task=saved['task'],old_unit=saved['unit'],old_invocation_id=saved['attested']['InvocationID'],
            lease_id=lease['lease_id'],expires_epoch=lease['expires_epoch'],epoch=time.time(),resource_projection=projection)
        immutable(token,value);return value


def bounded_recovery_runtime(requested,global_expires,*,now=None):
    now=time.time() if now is None else now
    runtime=min(requested,global_expires-now-5.)
    if not math.isfinite(runtime) or runtime<=0:raise RuntimeError('original global continuation deadline cannot contain coordinator')
    return runtime


def bounded_child_runtime(requested,parent,actual_parent_runtime,*,now=None):
    now=time.time() if now is None else now
    bound=parent['epoch']+min(parent['runtime_seconds'],actual_parent_runtime)
    runtime=min(requested,bound-now-5.)
    if not math.isfinite(runtime) or runtime<=0:raise RuntimeError('outer finite lifetime cannot contain a new coordinator')
    return runtime


def launch(release_path,probe_path,outer_capsule=None):
    release=read(release_path);c,oldc=verify_release(release,full=True);r=load_legacy();r.assert_parent_policy(oldc)
    system=r.System();probe=read(probe_path)
    bounded_recovery_runtime(c['coordinator_seconds'],release['original_global_expires_epoch'])
    if probe.get('status')!='PASS_R151_OWNED_TREE_POLICY_AND_DRAIN' or probe.get('resource_entry_sha256')!=digest(ENTRY) or probe.get('boot_id')!=boot():raise RuntimeError('same-source/boot R151 capability probe required')
    with canonical_lock(CANONICAL/'recovery_launch.lock'):
        # Read-only conflict checks must precede new coordinator intent.
        with canonical_lock(CANONICAL/'workflow.lock'):pass
        assert_drained_history(system,release)
        assert_capsules_drained(system,release['prior_R151_control_capsules']+release['prior_R151_worker_capsules'])
        retirement=retirement_contract()
        verify_retired_baseline(system,retirement,read(CANONICAL/'admission.json')['baseline']['units'][retirement['retired_unit']])
        if (CANONICAL/'wave_2/lease.json').exists() or (CANONICAL/'wave_3/lease.json').exists():raise RuntimeError('remaining numerical admission already consumed')
        first=r.handoff_snapshot(oldc,system,read(CANONICAL/'admission.json')['handoff']);second=first;until=time.monotonic()+20
        while second['heartbeat']==first['heartbeat'] and time.monotonic()<until:
            time.sleep(1);second=r.handoff_snapshot(oldc,system,first)
        if second['heartbeat']<=first['heartbeat']:raise RuntimeError('handoff heartbeat not advancing')
        recovery=uuid.uuid4().hex;folder=recovery_folder(recovery);folder.mkdir(parents=True)
        immutable(folder/'release.json',release);immutable(folder/'probe.json',probe)
        if outer_capsule:
            outer=read(outer_capsule);outer_props=verify_control(system,outer,oldc);verify_new_source(release['source'])
            immutable(folder/'outer_capsule.json',outer)
        else:outer=None
        immutable(folder/'launch_context.json',dict(release_path=str(Path(release_path).resolve()),release_sha256=digest(release_path),probe_sha256=digest(probe_path),handoff=second))
        unit='pricefm-r150-recovery-coordinator-'+uuid.uuid4().hex+'.service'
        argv=[oldc['python_runtime'],'-B',str(ENTRY),'coordinate','--recovery',recovery,'--controller-unit',unit]
        runtime_seconds=bounded_recovery_runtime(c['coordinator_seconds'],release['original_global_expires_epoch'])
        if outer:runtime_seconds=bounded_child_runtime(runtime_seconds,outer,r.parse_duration(outer_props['RuntimeMaxUSec']))
        capsule=start_control(system,oldc,folder/'coordinator','recovery-coordinator',argv,runtime_seconds,parent=outer)
        result=dict(recovery_id=recovery,folder=str(folder),coordinator=capsule)
        immutable(folder/'launch.json',result);return result


def coordinate(recovery,unit):
    r=load_legacy();folder=recovery_folder(recovery);release=read(folder/'release.json');c,oldc=verify_release(release)
    system=r.System();coordinator=await_capsule(folder/'coordinator');baseline=read(CANONICAL/'admission.json')
    if coordinator['unit']!=unit:raise RuntimeError('coordinator unit mismatch')
    with canonical_lock(CANONICAL/'workflow.lock'):
        current=None;terminal=dict(status='R151_RECOVERY_DEFERRED',cleanup_errors=[],completed_admissions=[],baseline_worker_signals=0,new_fits=0)
        try:
            verify_control(system,coordinator,oldc)
            for wave in ('2','3'):
                science=r.load_science();q=science.queue_state()
                if q['terminal']:
                    if not q['scientific_complete']:raise RuntimeError('science complete but owned assessment was not sealed inside a wave')
                    terminal['status']='R151_RECOVERY_COMPLETE';break
                if (CANONICAL/('wave_'+wave)/'lease.json').exists():raise RuntimeError('existing admission cannot be joined')
                leases={w:read(CANONICAL/('wave_'+w)/'lease.json') for w in ('2','3') if (CANONICAL/('wave_'+w)/'lease.json').exists()}
                projection=resource_projection(c,science,q,leases)
                immutable(folder/('pre_wave_'+wave+'_projection.json'),projection)
                # During D the queue does not yet include nominees. The prefix
                # reservation ensures no optimistic D-only admission calculation.
                if not projection['fits']:raise RuntimeError('remaining prefix/capacity/bin-packing gate failed')
                baseline_guard(oldc,system,baseline,coordinator,None,None,all_workers(),release,
                    extra_capsules=[v for v in recovery_capsules(recovery) if v['unit']!=coordinator['unit']])
                lease=claim_lease(c,system,wave,release,recovery,coordinator)
                controlunit='pricefm-r150-recovery-wave-'+wave+'-'+uuid.uuid4().hex+'.service'
                argv=[oldc['python_runtime'],'-B',str(ENTRY),'run-wave','--recovery',recovery,'--wave',wave,'--controller-unit',controlunit]
                current=start_control(system,oldc,folder/('wave_'+wave),'recovery-wave-'+wave,argv,lease['expires_epoch']-time.time(),parent=coordinator)
                # Persist canonical compatibility record; old controller source
                # identity is retained separately from actual resource code.
                immutable(CANONICAL/('wave_'+wave)/'r151_controller.json',current)
                previous=None
                while True:
                    props=system.unit(current['unit']);r.verify_owned(current,props)
                    if props.get('ActiveState') not in ('active','activating'):break
                    workers=all_workers();caps=recovery_capsules(recovery)
                    # Independent coordinator enforces whole tree predicates.
                    # It does not dispatch science or acquire controller.lock.
                    predicate=baseline_guard(oldc,system,baseline,coordinator,current,lease,workers,release,previous,
                        extra_capsules=[v for v in caps if v['unit'] not in (coordinator['unit'],current['unit'])])
                    previous=predicate['handoff'];r.atomic(folder/'heartbeat.json',dict(status='R151_COORDINATING',wave=wave,predicates=predicate))
                    time.sleep(oldc['poll_seconds'])
                drain_exact(system,current);current=None
                termpath=CANONICAL/('wave_'+wave)/'terminal.json'
                if not termpath.exists():raise RuntimeError('wave exited without terminal; owned cleanup required')
                result=read(termpath)
                if result.get('cleanup_verified') is not True or result.get('status') not in ('R150_WAVE_COMPLETE','R150_WAVE_DEFERRED'):
                    raise RuntimeError('wave stopped without continuation permission')
                terminal['completed_admissions'].append(wave)
                if science.queue_state()['terminal'] and science.queue_state()['scientific_complete']:
                    terminal['status']='R151_RECOVERY_COMPLETE';break
                if result.get('strict_new_components',0)==0:raise RuntimeError('zero-progress admission stops automatic continuation')
                if result.get('resource_unfunded_pending'):
                    terminal['resource_unfunded_pending']=result['resource_unfunded_pending'];break
                if science.queue_state()['terminal']:
                    terminal['status']='R151_RECOVERY_COMPLETE';break
        except Exception as error:terminal['original_stop_reason']=repr(error);terminal['status']='R151_RECOVERY_GUARD_STOPPED'
        finally:
            proof=cooperative_drain(system,recovery_attempts(),terminal.get('original_stop_reason','finite recovery ended'),grace=oldc['cooperative_grace_seconds'])
            terminal.update(proof)
            if current:
                try:terminal['controller_cleanup']=drain_exact(system,current)
                except Exception as error:terminal['cleanup_errors'].append(dict(operation='controller_drain',error=repr(error)));terminal['cleanup_verified']=False
            terminal.update(epoch=time.time(),source_head=release['source']['head'],science_head=SCIENCE_HEAD,recovery_id=recovery)
            immutable(folder/'terminal.json',terminal)
        return 0 if terminal['cleanup_verified'] and terminal['status']!='R151_RECOVERY_GUARD_STOPPED' else 2


def run_wave(recovery,wave,unit):
    r=load_legacy();folder=recovery_folder(recovery);release=read(folder/'release.json');c,oldc=verify_release(release)
    system=r.System();coordinator=await_capsule(folder/'coordinator');controller=await_capsule(folder/('wave_'+wave))
    if controller['unit']!=unit:raise RuntimeError('wave controller unit mismatch')
    runtime=CANONICAL/('wave_'+wave);lease=read(runtime/'lease.json');baseline=read(CANONICAL/'admission.json')
    if lease['recovery']['recovery_id']!=recovery:raise RuntimeError('lease belongs to different recovery')
    with canonical_lock(CANONICAL/'controller.lock'):
        if (runtime/'terminal.json').exists():raise RuntimeError('terminal admission cannot restart')
        science=r.load_science();active={};stopped=[False];previous=None;unfunded=[];status='R150_WAVE_DEFERRED';reason=None
        start_complete=set(science.queue_state()['complete']);cleanup={};leases={w:read(CANONICAL/('wave_'+w)/'lease.json') for w in ('2','3') if (CANONICAL/('wave_'+w)/'lease.json').exists()}
        for sig in (signal.SIGTERM,signal.SIGINT):signal.signal(sig,lambda *_:stopped.__setitem__(0,True))
        try:
            while True:
                predicate=baseline_guard(oldc,system,baseline,coordinator,controller,lease,all_workers(),release,previous,
                    extra_capsules=[v for v in recovery_capsules(recovery) if v['unit'] not in (coordinator['unit'],controller['unit'])])
                previous=predicate['handoff']
                if stopped[0]:reason='cooperative controller stop';break
                for name,saved in list(active.items()):
                    props=system.unit(saved['unit']);r.verify_owned(saved,props)
                    if props.get('ActiveState') in ('inactive','failed') or props.get('LoadState')=='not-found':
                        drain_exact(system,saved);del active[name]
                        if not science.task_complete(name):raise RuntimeError('worker exited without strict seal: '+name)
                if not active:science.advance() # accounting tails drained first
                queue=science.queue_state()
                if queue['terminal'] and not active:
                    finalize_owned(system,c,oldc,release,recovery,coordinator,controller,lease,baseline,science)
                    status='R150_WAVE_COMPLETE';reason='all required science strictly complete and owned assessment sealed';break
                projection=resource_projection(c,science,queue,leases,list(active.values()))
                # Optional seed set admission is atomic and persisted before its
                # first dispatch. Original500 scientific decision is untouched.
                if queue['phase']=='MATCHED_FULL_MC':
                    extra=science.read_decision('extra_seeds')['required_extra_components']
                    gate=folder/'extra_resource_admission.json'
                    if not gate.exists() and not active:
                        decision=dict(epoch=time.time(),components=extra,projection=projection,admitted=projection['fits'])
                        immutable(gate,decision)
                    if not gate.exists() or read(gate)['components']!=extra:raise RuntimeError('extra resource gate absent or altered')
                    if not read(gate)['admitted']:
                        unfunded=extra;reason='RESOURCE_UNFUNDED_PENDING entire matched extra set';break
                if queue.get('unfunded_pending') and not active:unfunded=queue['unfunded_pending'];reason='original cumulative budget left extras unfunded';break
                if time.time()>=lease['expires_epoch']-c['cleanup_seconds']:reason='finite 90min numerical allocation exhausted';break
                ready=[task for task in queue['ready'] if task['name'] not in active]
                cpus=[cpu for cpu in oldc['cpus'] if cpu not in [s['cpu'] for s in active.values()]]
                dispatched=False
                if ready and len(active)<2:
                    placement=passive_placement(cpus);r.atomic(runtime/'latest_placement.json',placement);cpus=placement['ranked']
                    occupied={saved['resource_slot'] for saved in active.values()}
                    assignments={v['task']:v['slot'] for v in projection['packing']['allocation'] if v['slot']<2}
                    for task in ready:
                        if len(active)>=2:break
                        slot=assignments.get(task['name'])
                        if slot is None or slot in occupied:continue
                        # A fit for the whole remaining prefix and every current
                        # task's own deadline are both required, independently.
                        if not projection['fits'] or not r.projection_fits(task,oldc,lease,len(active)):continue
                        saved=r.start_worker(oldc,AttestingSystem(system,runtime),runtime,task,cpus.pop(0),lease,baseline,controller['attested'])
                        saved['resource_slot']=slot;occupied.add(slot)
                        immutable(runtime/'resource_slots'/(saved['token']+'.json'),dict(task=task['name'],unit=saved['unit'],slot=slot,lease_id=lease['lease_id']))
                        active[task['name']]=saved;dispatched=True
                        r.event(runtime,'r151_worker_released',task=task['name'],unit=saved['unit'],resource_head=release['source']['head'],science_head=SCIENCE_HEAD)
                stars=[s for s in active.values() if (r.starvation_predicate(s,oldc) or {}).get('starved')]
                if stars:
                    if len(stars)>1:raise RuntimeError('multiple starved workers exceed single replacement')
                    saved=stars[0];projection=resource_projection(c,science,queue,leases,list(active.values()))
                    token=reserve_replacement(c,recovery,saved,lease,projection)
                    drained=cooperative_drain(system,[saved],'single global same-lease placement replacement',grace=10,deadline=lease['expires_epoch'])
                    if not drained['cleanup_verified']:raise RuntimeError('replacement predecessor failed drain')
                    immutable(CANONICAL/'r151_replacement_drain.json',dict(token_sha256=digest(CANONICAL/'r151_replacement_token.json'),
                        old_unit=saved['unit'],lease_id=lease['lease_id'],drain=drained))
                    del active[saved['task']]
                    if science.task_complete(saved['task']):continue
                    choices=[cpu for cpu in oldc['cpus'] if cpu!=saved['cpu'] and cpu not in [v['cpu'] for v in active.values()]]
                    placement=passive_placement(choices);task=next(t for t in queue['ready'] if t['name']==saved['task'])
                    projection=resource_projection(c,science,science.queue_state(),leases,list(active.values()))
                    if not projection['fits'] or not r.projection_fits(task,oldc,lease,len(active)):raise RuntimeError('replacement cannot fit unchanged lease')
                    occupied={v['resource_slot'] for v in active.values()}
                    assignment=next((v['slot'] for v in projection['packing']['allocation'] if v['task']==task['name'] and v['slot']<2 and v['slot'] not in occupied),None)
                    if assignment is None:raise RuntimeError('replacement has no free current-window packing slot')
                    replacement=r.start_worker(oldc,AttestingSystem(system,runtime),runtime,task,placement['ranked'][0],lease,baseline,controller['attested'])
                    replacement['resource_slot']=assignment
                    immutable(runtime/'resource_slots'/(replacement['token']+'.json'),dict(task=task['name'],unit=replacement['unit'],slot=assignment,lease_id=lease['lease_id']))
                    active[task['name']]=replacement
                    immutable(folder/'replacement_proof.json',dict(token=token,old_drain=drained,replacement=replacement,placement=placement))
                r.atomic(runtime/'heartbeat.json',dict(status='R151_RUNNING',wave=wave,active=list(active),phase=queue['phase'],predicates=predicate,resource_projection=projection))
                if not active and not dispatched:reason='no ready task fits unchanged wave/resource gates';break
                time.sleep(oldc['poll_seconds'])
        except Exception as error:status='R150_GUARD_STOPPED';reason=repr(error)
        finally:
            cleanup=cooperative_drain(system,r.discover_workers(runtime),reason,grace=oldc['cooperative_grace_seconds'],deadline=lease['expires_epoch'])
            final_complete=set(science.queue_state()['complete'])
            terminal=dict(status=status,original_stop_reason=reason,lease=lease,source=baseline['source'],resource_source_head=release['source']['head'],
                epoch=time.time(),baseline_worker_signals=0,new_fits=0,strict_new_components=len(final_complete-start_complete),resource_unfunded_pending=unfunded,**cleanup)
            immutable(runtime/'terminal.json',terminal)
        return 0 if cleanup['cleanup_verified'] and status!='R150_GUARD_STOPPED' else 2


def finalize_owned(system,c,oldc,release,recovery,coordinator,controller,lease,baseline,science):
    """Full array verification stays IDLE and inside the current finite lease."""
    folder=recovery_folder(recovery)/'assessment'
    if (science.OUT/'assessment_seal.json').exists():
        seal=read(science.OUT/'assessment_seal.json')
        if seal!={'sha256':digest(science.OUT/'assessment.json'),'source':science.read_preparation()['source']}:raise RuntimeError('existing assessment seal differs')
        return read(science.OUT/'assessment.json')
    if time.time()>=lease['expires_epoch']-30:raise RuntimeError('no remaining finite reserve for owned assessment')
    cpu=passive_placement(oldc['cpus'])['ranked'][0]
    task=dict(name='__assessment__',estimated_cpu_seconds=0.)
    target=[oldc['python_runtime'],'-B',str(SCIENCE_ROOT/'application/scripts/pricefm/500_run_pricefm_stage_r150_bounded_admission.py'),'finalize']
    saved=start_payload(system,oldc,folder,task,cpu,lease,controller,target,release['source'],digest(recovery_folder(recovery)/'probe.json'))
    reason=None;previous=None
    try:
        while True:
            props=system.unit(saved['unit']);load_legacy().verify_owned(saved,props)
            if props.get('ActiveState') not in ('active','activating'):break
            predicate=baseline_guard(oldc,system,baseline,coordinator,controller,lease,all_workers(),release,previous,
                extra_capsules=[v for v in recovery_capsules(recovery) if v['unit'] not in (coordinator['unit'],controller['unit'])],extra_workers=[saved])
            previous=predicate['handoff'];time.sleep(oldc['poll_seconds'])
        proof=drain_exact(system,saved)
        seal=read(science.OUT/'assessment_seal.json')
        if seal!={'sha256':digest(science.OUT/'assessment.json'),'source':science.read_preparation()['source']}:raise RuntimeError('owned final assessment seal/source mismatch')
        result=read(science.OUT/'assessment.json')
        if result.get('status')!='R150_BOUNDED_SCIENTIFICALLY_COMPLETE_NOT_PROMOTED' or result.get('new_model_fits')!=0:raise RuntimeError('assessment disposition differs')
        immutable(folder/'verification.json',dict(worker=saved,drain=proof,assessment_sha256=seal['sha256'],lease_id=lease['lease_id']))
        return result
    except Exception as error:reason=repr(error);raise
    finally:
        proof=cooperative_drain(system,[saved],reason or 'owned assessment ended',grace=0,deadline=lease['expires_epoch'])
        if not proof['cleanup_verified']:raise RuntimeError('owned assessment cleanup failed: '+json.dumps(proof))


def inspect(recovery=None):
    r=load_legacy();science=r.load_science();q=science.queue_state()
    result=dict(science=q,science_head=SCIENCE_HEAD,leases={w:read(CANONICAL/('wave_'+w)/'lease.json') for w in ('1','2','3') if (CANONICAL/('wave_'+w)/'lease.json').exists()},new_fits=0)
    if recovery:
        folder=recovery_folder(recovery);result['recovery']=recovery
        for key in ('launch','heartbeat','terminal'):
            if (folder/(key+'.json')).exists():result[key]=read(folder/(key+'.json'))
    return result


def capability_probe(output,python):
    """Disposable actual three-level tree; never creates a numerical lease."""
    r=load_legacy();c=config();oldc=read(r.CONFIG);r.assert_parent_policy(oldc)
    result=dict(resource_entry_sha256=digest(ENTRY),boot_id=boot(),epoch=time.time(),baseline_worker_signals=0,new_fits=0,cleanup_errors=[])
    log=Path(output).parent/('r151_probe_'+uuid.uuid4().hex);log.mkdir(parents=True)
    # The immutable implementation already tests rapid exits, identity mismatch,
    # worker timeout, scheduler workaround and owned-descendant cleanup.
    legacy_output=log/'legacy_capability.json';r.capability_probe(legacy_output,python);result['legacy_probe']=read(legacy_output)
    system=r.System();owned=[]
    try:
        def control(role,parent=None,seconds=35,entry=ENTRY):
            name='pricefm-r150-test-r151-'+role+'-'+uuid.uuid4().hex+'.service'
            argv=[python,'-B',str(entry),'test-hold','--controller-unit',name]
            saved=start_control(system,oldc,log/role,role,argv,seconds,parent=parent);owned.append(saved);return saved
        outer_entry=ENTRY.with_name('503_orchestrate_pricefm_stage_r151.py')
        if not outer_entry.is_file():raise RuntimeError('actual503outerprobe entry absent')
        outer=control('outer',seconds=60,entry=outer_entry)
        coordinator=control('coordinator',outer,seconds=50);controller=control('controller',coordinator,seconds=40)
        name='pricefm-r150-test-r151-worker-'+uuid.uuid4().hex+'.service';cpu=passive_placement(oldc['cpus'])['ranked'][0]
        argv=r.idle_command([python,'-B',str(ENTRY),'test-tree'])
        saved=dict(unit=name,argv=argv,description='R151 disposable payload '+name,expected_cgroup=str(Path(controller['attested']['ControlGroup']).parent/name),cpu=cpu)
        immutable(log/'worker_intent.json',saved);owned.append(saved)
        system.start(name,saved['description'],argv,cpus=[cpu],idle=True,runtime_seconds=25,controller=controller['unit'],working_directory=SCIENCE_ROOT,stdout=log/'payload.stdout')
        saved['attested']=system.unit(name);until=time.monotonic()+3
        while time.monotonic()<until:
            proc=r.process(int(saved['attested']['MainPID']))
            if proc and proc['scheduler']==os.SCHED_IDLE:break
            time.sleep(.02)
        until=time.monotonic()+5
        while len(system.members(saved['attested']['ControlGroup']))<2 and time.monotonic()<until:time.sleep(.05)
        if len(system.members(saved['attested']['ControlGroup']))<2:raise RuntimeError('probe payload descendant was never observed')
        strict_worker_policy(system,saved);result['actual_payload']=dict(properties=saved['attested'],process=proc,
            descendant_processes=[r.process(pid) for pid in system.members(saved['attested']['ControlGroup'])])
        result['control_capsules']=[outer,coordinator,controller]
        result['whole_tree_pids']=owned_groups(system,[outer,coordinator,controller],[saved])
        if len(result['whole_tree_pids'])<5:raise RuntimeError('four levels plus descendant not actually observed')
        # SIGKILL exists only through the existing UUID disposable API.
        system.fail_owned_test_controller(outer)
        result['parent_death_drains']=[drain_exact(system,item) for item in (saved,controller,coordinator,outer)]
        result['status']='PASS_R151_OWNED_TREE_POLICY_AND_DRAIN'
    except Exception as error:result.update(status='FAIL_R151_OWNED_TREE_POLICY_AND_DRAIN',original_error=repr(error))
    finally:
        for saved in reversed(owned):
            try:drain_exact(system,saved)
            except Exception as error:result['cleanup_errors'].append(dict(unit=saved['unit'],error=repr(error)))
        if result['cleanup_errors']:result['status']='FAIL_R151_OWNED_TREE_POLICY_AND_DRAIN'
        immutable(output,result)
    if result['status']!='PASS_R151_OWNED_TREE_POLICY_AND_DRAIN':raise RuntimeError(json.dumps(result,sort_keys=True))
    return result


def main():
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest='action',required=True)
    p=sub.add_parser('freeze-release');p.add_argument('--output',required=True)
    p=sub.add_parser('probe');p.add_argument('--output',required=True);p.add_argument('--python',default=read(load_legacy().CONFIG)['python_runtime'])
    p=sub.add_parser('launch');p.add_argument('--release',required=True);p.add_argument('--probe',required=True);p.add_argument('--outer-capsule')
    for action in ('coordinate','run-wave'):
        p=sub.add_parser(action);p.add_argument('--recovery',required=True);p.add_argument('--controller-unit',required=True)
        if action=='run-wave':p.add_argument('--wave',choices=('2','3'),required=True)
    p=sub.add_parser('inspect');p.add_argument('--recovery')
    p=sub.add_parser('bootstrap');p.add_argument('--spec',required=True)
    p=sub.add_parser('test-hold');p.add_argument('--controller-unit')
    sub.add_parser('test-tree');args=parser.parse_args()
    if args.action=='freeze-release':result=freeze_release(args.output)
    elif args.action=='probe':result=capability_probe(args.output,args.python)
    elif args.action=='launch':result=launch(args.release,args.probe,args.outer_capsule)
    elif args.action=='coordinate':return coordinate(args.recovery,args.controller_unit)
    elif args.action=='run-wave':return run_wave(args.recovery,args.wave,args.controller_unit)
    elif args.action=='inspect':result=inspect(args.recovery)
    elif args.action=='bootstrap':return bootstrap(args.spec)
    elif args.action=='test-hold':
        while True:time.sleep(1)
    elif args.action=='test-tree':
        child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(120)'])
        while True:time.sleep(1)
    print(json.dumps(result,sort_keys=True));return 0

if __name__=='__main__':raise SystemExit(main())
