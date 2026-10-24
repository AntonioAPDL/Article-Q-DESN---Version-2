#!/usr/bin/env python3
"""Finite R152 common cached-screen dispatcher and admission/accounting ledger.

Parents remain standard-library-only. Scientific prediction, benchmark and
array assessment execute in independently attested one-core IDLE services.
The historical EE producer/preparation/leases are never patched or rewritten.
"""
from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import importlib.util
import itertools
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
CONFIG = ROOT/'application/config/pricefm_stage_r152_pool_20261024.json'
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
SHARED = DATA/'launch_prep/pricefm_stage_r152_parallel_20261024'
EE_ROOT = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r150_bounded_admission_20261023')
EE_HEAD = 'c03613cd1a85cce5d02120760b954cdc15160410'
EE_CANONICAL = DATA/'launch_prep/pricefm_stage_r150_bounded_admission_20261023/muscat_resources'
THREAD_VARS = ('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS','BLIS_NUM_THREADS','NUMEXPR_NUM_THREADS','VECLIB_MAXIMUM_THREADS')
_MODULES = {}


def read(path): return json.loads(Path(path).read_text())
def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''): h.update(block)
    return h.hexdigest()
def fingerprint(value): return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
def finite(value, *, positive=False):
    return not isinstance(value,bool) and isinstance(value,(int,float)) and math.isfinite(value) and (value>0 if positive else value>=0)


def immutable(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    payload=(json.dumps(value,sort_keys=True,indent=2,allow_nan=False)+'\n').encode()
    temporary=path.with_name('.'+path.name+'.'+uuid.uuid4().hex+'.tmp')
    try:
        with temporary.open('xb') as stream:stream.write(payload);stream.flush();os.fsync(stream.fileno())
        # link preserves create-once semantics while readers see either absence
        # or the complete fsynced JSON; no exposed partially written master.
        os.link(temporary,path)
    finally:
        if temporary.exists():temporary.unlink()
    fd=os.open(str(path.parent),os.O_RDONLY)
    try:os.fsync(fd)
    finally:os.close(fd)
    return value


def atomic(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_name(path.name+'.tmp.'+uuid.uuid4().hex)
    immutable(temporary,value);os.replace(temporary,path)


@contextlib.contextmanager
def locked(path, *, blocking=False):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('a') as stream:
        try:fcntl.flock(stream,fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except BlockingIOError as error:raise RuntimeError('resource lock already held: '+str(path)) from error
        try:yield
        finally:fcntl.flock(stream,fcntl.LOCK_UN)


def event(runtime,kind,**details):
    runtime=Path(runtime);row=dict(epoch=time.time(),kind=kind,**details)
    with locked(runtime/'events.lock',blocking=True):
        with (runtime/'events.jsonl').open('a') as stream:
            stream.write(json.dumps(row,sort_keys=True,allow_nan=False)+'\n');stream.flush();os.fsync(stream.fileno())
    return row


def module(name,path):
    path=Path(path).resolve();key=(name,str(path))
    if key not in _MODULES:
        spec=importlib.util.spec_from_file_location(name,path)
        value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);_MODULES[key]=value
    if 'numpy' in sys.modules:raise RuntimeError('resource parent imported a numerical library')
    return _MODULES[key]


def legacy(): return module('r152_immutable_resource_primitives',EE_ROOT/'application/scripts/pricefm/498_supervise_pricefm_stage_r150_resources.py')
def hardening(): return module('r152_policy_hardening',ROOT/'application/scripts/pricefm/501_recover_pricefm_stage_r150.py')
def baseline(): return module('r152_baseline_resource_owner',ROOT/'application/scripts/pricefm/504_supervise_pricefm_stage_r152_baseline.py')
def regional(): return module('r152_explicit_regional_science',ROOT/'application/scripts/pricefm/506_screen_pricefm_stage_r152_region.py')
def boot(): return Path('/proc/sys/kernel/random/boot_id').read_text().strip()
def git(root,*argv):return subprocess.check_output(['git','-C',str(root),*argv],text=True).strip()


def read_config(path=None):
    c=read(path or CONFIG)
    fixed={'schema_version':1,'stage':'R152','mode':'HYBRID6','base_cpus':list(range(24,30)),
        'optional_cpus':[22,23],'parent_cpus':list(range(15,30)),'base_workers':6,'max_workers':8,
        'master_seconds':43200,'wave_seconds':7200,'compute_seconds':5400,'assessment_seconds':1800,
        'benchmark_seconds':1200,'transition_seconds':5,'poll_seconds':5,'cooperative_grace_seconds':10,
        'stop_seconds':15,'max_control_capsules':6,'EE_science_head':EE_HEAD,
        'EE_historical_frozen_charge_CPU_seconds':999.1737615444998,
        'EE_historical_reservation_CPU_seconds':1085.4499848279995,'EE_science_limit_CPU_seconds':21786.141934839827,
        'EE_conservative_share':0.6724117881123404,'EE_replacement_CPU_seconds':1178.430003,
        'regional_nominal_science_CPU_seconds':32400,'benchmark_CPU_seconds':1200,'assessment_CPU_seconds':1800,
        'shared_control_CPU_seconds':1800,'global_fixed_CPU_seconds':9600,'global_max_CPU_seconds':96186.14193483983,
        'new_model_fits':0,'AL_authorized':False,'baseline_worker_signals_authorized':False,'automatic_renewal':False}
    if any(c.get(k)!=v for k,v in fixed.items()):raise RuntimeError('R152 shared-pool finite contract differs')
    if c['min_available_memory_gib']<192 or c['min_disk_gib']<80 or c['max_owned_rss_gib']>24:
        raise RuntimeError('shared-resource floors/aggregate RSS scope differs')
    if Path(c['EE_science_root'])!=EE_ROOT:raise RuntimeError('immutable EE source root differs')
    return c


def source_identity(full=False):
    if git(ROOT,'status','--porcelain'):raise RuntimeError('resource source must be committed and clean')
    branch=git(ROOT,'branch','--show-current')
    if branch!='work/pricefm-r152-parallel-recovery-20261024':raise RuntimeError('dedicated resource task branch required')
    names=git(ROOT,'ls-files','-z').split('\0')
    if not full:names=[name for name in names if name.startswith(('application/scripts/pricefm/','application/config/pricefm_'))]
    pins={name:digest(ROOT/name) for name in names if name and (ROOT/name).is_file()}
    return dict(root=str(ROOT),head=git(ROOT,'rev-parse','HEAD'),branch=branch,runtime_sha256=pins)


def verify_source(source):
    if (source.get('root')!=str(ROOT) or source.get('head')!=git(ROOT,'rev-parse','HEAD') or git(ROOT,'status','--porcelain')
        or source.get('branch')!=git(ROOT,'branch','--show-current') or source.get('branch')!='work/pricefm-r152-parallel-recovery-20261024'):
        raise RuntimeError('resource source/root/HEAD/cleanliness changed')
    for name,wanted in source['runtime_sha256'].items():
        if digest(ROOT/name)!=wanted:raise RuntimeError('resource executable bytes changed: '+name)


def validate_master(master,c=None, *, now=None,allow_expired=False):
    c=c or read_config();now=time.time() if now is None else now
    partition=master.get('partition',{})
    a=partition.get('baseline_A',partition.get('baseline_A_cpus'))
    b=partition.get('baseline_B',partition.get('baseline_B_cpus'))
    d=partition.get('development_base',partition.get('development_cpus'))
    if (master.get('schema_version',master.get('schema'))!=1 or master.get('stage')!='R152'
        or not master.get('scope_id') or not finite(master.get('start_epoch'),positive=True)
        or master.get('started_epoch',master.get('start_epoch'))!=master['start_epoch']
        or not math.isclose(master.get('expires_epoch',0)-master['start_epoch'],43200,abs_tol=1e-6)
        or a!=list(range(15)) or b!=list(range(15,24)) or d!=list(range(24,30))):
        raise RuntimeError('single-clock master/physical partition differs')
    if not allow_expired and now>=master['expires_epoch']:raise RuntimeError('master scope expired')
    if now<master['start_epoch']-5:raise RuntimeError('master clock is in the future')
    return master


def commit_master(pending,shared_runtime,partition_release_fields=None, *, now=None):
    """504 calls this once after exact fenced quiescence and guardian arming."""
    c=read_config();pending=read(pending) if not isinstance(pending,dict) else dict(pending)
    fields=dict(partition_release_fields or {});shared_runtime=Path(shared_runtime)
    start=time.time() if now is None else now
    source=pending.get('source')
    if not isinstance(source,dict):raise RuntimeError('pending source attestation missing')
    verify_source(source)
    if not fields.get('baseline_owner') or not fields.get('baseline_guardian_unit') or not fields.get('baseline_runtime'):
        raise RuntimeError('baseline owner/guardian/namespace missing before commitment')
    owner=fields['baseline_owner'];current=legacy().process(os.getpid())
    if current is None or any(current.get(k)!=owner.get(k) for k in ('pid','start_ticks','boot_id')):
        raise RuntimeError('partition committing actor is not the attested baseline owner')
    partition=dict(baseline_A=list(range(15)),baseline_B=list(range(15,24)),development_base=list(range(24,30)),optional=[22,23])
    if fields.get('partition',partition)!=partition:raise RuntimeError('baseline committing partition differs')
    master=dict(pending);master.update(fields)
    master.update(schema_version=1,stage='R152',scope_id=pending.get('scope_id') or uuid.uuid4().hex,
        start_epoch=start,started_epoch=start,expires_epoch=start+43200,seconds=43200,boot_id=boot(),
        host=__import__('socket').gethostname(),source=source,partition=partition)
    validate_master(master,c,now=start)
    with locked(shared_runtime/'master.lock'):
        if (shared_runtime/'master.json').exists():raise RuntimeError('master commitment already exists; no reset/join')
        immutable(shared_runtime/'master.json',master)
    return master


def admission_identifiers(study,kind='numerical'):
    if study not in ('EE','FI','DK2'):raise RuntimeError('unknown study')
    if kind=='benchmark':return [] if study=='EE' else [study+'-B0']
    if kind=='assessment':return [study+'-A0']
    if kind!='numerical':raise RuntimeError('unknown admission kind')
    return [study+'-C'+str(i) for i in range(1,3 if study=='EE' else 4)]


def admission_files(runtime,study,kind=None):
    rows=[]
    for path in sorted((Path(runtime)/'admissions'/study).glob('*/lease.json')):
        row=read(path)
        if kind is None or row['kind']==kind:rows.append((path,row))
    return rows


def claim_admission(runtime,master,study,kind,source_head,prep_sha256,controller_unit, *, now=None,projection=None):
    """One immutable claim; complete lease/parent containment before publication."""
    runtime=Path(runtime);now=time.time() if now is None else now;validate_master(master,now=now)
    seconds={'numerical':7200,'benchmark':1200,'assessment':1800}.get(kind)
    if seconds is None:raise RuntimeError('invalid admission kind')
    if kind=='benchmark' and study=='EE':raise RuntimeError('new EE benchmark forbidden')
    if projection is None or projection.get('fits') is not True:raise RuntimeError('complete joint funding proof required')
    with locked(runtime/'admission.lock'):
        rows=admission_files(runtime,study)
        live=[r for p,r in rows if not (p.parent/'terminal.json').exists()]
        if live and not (kind=='assessment' and len(live)==1 and live[0]['kind']=='numerical'):
            raise RuntimeError('study has an unclosed admission; joining/overlap forbidden')
        names=admission_identifiers(study,kind);used={row['admission_id'] for _,row in rows}
        identifier=next((name for name in names if name not in used),None)
        if identifier is None:raise RuntimeError('finite study admissions exhausted')
        if kind=='assessment':
            waves=[r for _,r in rows if r['kind']=='numerical']
            if not waves:raise RuntimeError('assessment requires a numerical window')
            parent_path=runtime/'admissions'/study/waves[-1]['admission_id']/'lease.json'
            closed=parent_path.parent/'compute_closed.json'
            if not closed.is_file() or read(closed).get('active_workers')!=[] or read(closed).get('numerical_dispatch_closed') is not True:
                raise RuntimeError('assessment requires a closed compute phase and drained workers')
            bound=min(master['expires_epoch']-5,waves[-1]['expires_epoch'])
            seconds=min(1800,bound-now)
            if seconds<30:raise RuntimeError('assessment reserve cannot fit')
        elif now+seconds+5>master['expires_epoch']:
            raise RuntimeError('whole new admission is not contained in master')
        path=runtime/'admissions'/study/identifier/'lease.json'
        value=dict(schema_version=1,stage='R152',study=study,kind=kind,admission_id=identifier,lease_id=uuid.uuid4().hex,
            started_epoch=now,start_epoch=now,expires_epoch=now+seconds,seconds=seconds,
            compute_expires_epoch=now+(5400 if kind=='numerical' else seconds),
            master_scope_id=master['scope_id'],master_sha256=digest(runtime.parent/'master.json'),
            source_head=master['source']['head'],study_source_head=source_head,prep_sha256=prep_sha256,
            controller_unit=controller_unit,boot_id=master['boot_id'],projection_sha256=fingerprint(projection))
        if kind=='assessment':
            value.update(parent_admission_path=str(parent_path),parent_admission_sha256=digest(parent_path),
                parent_lease_id=waves[-1]['lease_id'],compute_closed_path=str(closed),compute_closed_sha256=digest(closed))
            request=runtime/'studies'/study/'assessment_request.json'
            if request.is_file():value.update(assessment_request_path=str(request),assessment_request_sha256=digest(request))
        immutable(path.parent/'funding.json',projection);immutable(path,value)
    return path,value


def close_admission(path,status,**details):
    path=Path(path);value=dict(schema_version=1,status=status,lease_sha256=digest(path),epoch=time.time(),**details)
    immutable(path.parent/'terminal.json',value);return value


def compute_windows(runtime,study,master, *, now=None):
    """Real current numerical interval plus whole serial future windows only."""
    now=time.time() if now is None else now;rows=admission_files(runtime,study,'numerical')
    values=[];cursor=now;used={row['admission_id'] for _,row in rows}
    for path,row in rows:
        if (path.parent/'terminal.json').exists():continue
        if row['compute_expires_epoch']>now:
            values.append(dict(id=row['admission_id'],start=now,end=row['compute_expires_epoch']-5,lease_end=row['expires_epoch']-5,current=True))
        cursor=max(cursor,row['expires_epoch']+5)
    for identifier in admission_identifiers(study):
        if identifier in used:continue
        if cursor+7200+5>master['expires_epoch']:break
        values.append(dict(id=identifier,start=cursor,end=cursor+5400-5,lease_end=cursor+7200-5,current=False));cursor+=7205
    return values


def first_gap(blocks,lo,hi,duration):
    begin=lo
    for left,right in sorted(blocks):
        if right<=begin:continue
        if left>=begin+duration:break
        begin=max(begin,right)
    return begin if begin+duration<=hi+1e-9 else None


def pack_joint(jobs,windows, *, cpus=tuple(range(24,30)),active=(),study_cpus=None,now=None):
    """Concrete nonpreemptive calendar, separate within-study phase barriers.

    A failed heuristic is only no exhibited feasible schedule, never proof of
    impossibility. Optional22/23 are deliberately not accepted as funding CPUs.
    """
    now=time.time() if now is None else now;cpus=list(cpus)
    if cpus!=list(range(24,30)):raise RuntimeError('mandatory funding uses exactly six reserved physical slots')
    blocks={cpu:[] for cpu in cpus};allocation=[];barriers={};active_names=set()
    for row in active:
        if row['cpu'] not in cpus:continue
        end=max(now,row['projected_end_epoch']);name=(row['study'],row['name']);active_names.add(name)
        if end>now:blocks[row['cpu']].append((now,end))
        allocation.append(dict(row,start=now,end=end,active=True))
        barriers[(row['study'],int(row.get('phase',0)))]=max(barriers.get((row['study'],int(row.get('phase',0))),now),end)
    pending=[dict(job) for job in jobs if (job['study'],job['name']) not in active_names]
    phase_keys=sorted({(row['study'],int(row.get('phase',0))) for row in pending},key=lambda key:(key[1],{'EE':0,'FI':1,'DK2':2}.get(key[0],9)))
    for study,phase in phase_keys:
        prior=max([v for (s,p),v in barriers.items() if s==study and p<phase]+[now])
        group=sorted([row for row in pending if row['study']==study and int(row.get('phase',0))==phase],key=lambda row:(-row['estimated_wall_seconds'],row['name']))
        finish=[]
        for job in group:
            duration=job['estimated_wall_seconds']
            if not finite(duration,positive=True):raise RuntimeError('task has no valid complete wall envelope')
            eligible=list((study_cpus or {}).get(study,cpus))
            if not eligible or not set(eligible).issubset(cpus):raise RuntimeError('invalid study calendar partition')
            choices=[]
            for window in windows.get(study,[]):
                for cpu in eligible:
                    end_bound=window.get('lease_end',window['end']) if job.get('kind')=='assessment_reserve' else window['end']
                    begin=first_gap(blocks[cpu],max(now,window['start'],prior),end_bound,duration)
                    if begin is not None:choices.append((begin+duration,begin,cpu,window['id']))
            if not choices:return dict(fits=False,unplaced=dict(study=study,task=job['name']),allocation=allocation,proof='NO_EXHIBITED_FEASIBLE_SCHEDULE')
            end,begin,cpu,window_id=min(choices)
            blocks[cpu].append((begin,end));finish.append(end)
            allocation.append(dict(study=study,name=job['name'],phase=phase,cpu=cpu,window_id=window_id,start=begin,end=end,
                estimated_wall_seconds=duration,estimated_cpu_seconds=job['estimated_cpu_seconds'],active=False))
        if finish:barriers[(study,phase)]=max(barriers.get((study,phase),now),max(finish))
    return dict(fits=True,allocation=allocation,within_study_phase_barriers=True,base_cpus=cpus,
        no_optional_capacity_credit=True,proof='EXHIBITED_NONOVERLAPPING_JOINT_CALENDAR')


def stop_tail_reserve(c,active_count):
    if active_count>c['max_workers']:raise RuntimeError('active worker ceiling exceeded')
    return (active_count+c['max_control_capsules'])*(c['poll_seconds']+c['cooperative_grace_seconds']+c['stop_seconds'])


def nominal_global_limit(c,regional_limits):
    if any(not finite(v) or v>32400 for v in regional_limits.values()):raise RuntimeError('invalid priced regional ceiling')
    return c['EE_science_limit_CPU_seconds']+sum(regional_limits.values())+c['global_fixed_CPU_seconds']


def claim_slot(runtime,master,lease_path,task,cpu,unit, *, now=None):
    runtime=Path(runtime);now=time.time() if now is None else now
    lease=read(lease_path)
    if now>=lease['expires_epoch'] or lease['master_scope_id']!=master['scope_id']:raise RuntimeError('slot requires a live matching admission')
    allowed=list(range(24,30))
    if cpu not in allowed:raise RuntimeError('optional slots require a separately verified expansion gate')
    with locked(runtime/'slots.lock'):
        directory=runtime/'slots';directory.mkdir(exist_ok=True)
        for path in directory.glob('*/claim.json'):
            row=read(path)
            if not (path.parent/'released.json').exists() and (row['cpu']==cpu or (row['study']==lease['study'] and row['task']==task)):
                raise RuntimeError('physical slot or task already claimed')
        token=uuid.uuid4().hex;path=directory/token/'claim.json'
        row=dict(schema_version=1,token=token,scope_id=master['scope_id'],master_scope_id=master['scope_id'],
            master_sha256=digest(runtime.parent/'master.json'),lease_id=lease['lease_id'],admission_id=lease['admission_id'],
            admission_path=str(Path(lease_path).resolve()),study=lease['study'],task=task,cpu=cpu,unit=unit,epoch=now)
        immutable(path,row)
    return path,row


def release_slot(path,proof):
    if proof.get('drained') is not True or proof.get('members',proof.get('pids',[])):
        raise RuntimeError('slot release requires exact drained lifetime proof')
    path=Path(path)
    if proof.get('unit')!=read(path)['unit']:raise RuntimeError('slot drain unit differs')
    immutable(path.parent/'released.json',dict(claim_sha256=digest(path),proof=proof,epoch=time.time()))


class EEStudy:
    """Read-only metadata API and commands for the immutable c036 producer."""
    study_id='EE'
    PREP=DATA/'launch_prep/pricefm_stage_r150_bounded_admission_20261023'
    OUT=DATA/'campaigns/pricefm_stage_r150_bounded_admission_20261023'
    def __init__(self,c,runtime):
        self.c=c;self.runtime=Path(runtime)
        self.api=module('r152_immutable_EE_science',EE_ROOT/'application/scripts/pricefm/500_run_pricefm_stage_r150_bounded_admission.py')
    def read_preparation(self):return self.api.read_preparation()
    def queue_state(self):return self.api.queue_state()
    def task_complete(self,name):return self.api.task_complete(name)
    def pricing(self):return self.read_preparation()['pricing']
    def estimate_task(self,name):return self.pricing()['task_estimates'][name]
    def advance(self,**ignored):return self.api.advance()
    def science_limit(self):return self.c['EE_science_limit_CPU_seconds']
    def source(self):
        prep=self.read_preparation();return dict(root=str(EE_ROOT),head=EE_HEAD,sha256=prep['source_sha256'])
    def command(self,name,cpu,receipt):
        if name=='__finalize__':
            return [self.c['python_runtime'],'-B',str(ENTRY),'assess-ee','--runtime',str(self.runtime.parent),'--cpu',str(cpu),'--policy-receipt',str(receipt)]
        return [self.c['python_runtime'],'-B',str(EE_ROOT/'application/scripts/pricefm/500_run_pricefm_stage_r150_bounded_admission.py'),
            'worker','--task',name,'--cpu',str(cpu),'--policy-receipt',str(receipt)]
    def complete_prefix(self):
        prep=self.read_preparation();q=self.queue_state()
        if not (self.OUT/'decisions/nominees.seal.json').exists():return False
        nom=self.api.read_decision('nominees')['nominees']
        names=self.api.names_for([v['package_id'] for v in prep['packages']],'D',[0])+self.api.names_for([prep['control']]+nom,'S',[0])
        return all(self.task_complete(n) for n in names)


def task_phase(name):return 1 if '_S_seed' in name else 0


def required_scenarios(study,q):
    """All predeclared nominee scenarios, never partial-D winner selection."""
    prep=study.read_preparation();pricing=study.pricing();names=list(q.get('pending',[]))
    if q['phase'] in ('DETERMINISTIC_POOL','NOMINATION_REQUIRED'):
        scenarios=(prep.get('prefix_contract') or pricing).get('all_prospective_seed0_scenarios')
        if scenarios is None:scenarios=pricing.get('all_prospective_seed0_scenarios')
        if not scenarios:raise RuntimeError('complete original-seed scenario envelope missing')
        ids=[v['package_id'] for v in prep['packages']]
        D=[task['name'] for task in prep['tasks'] if task['mode']=='D' and not study.task_complete(task['name'])]
        values=[]
        for scenario in scenarios:
            packages=[prep['control'],scenario['A'],scenario['B']]
            S=[task['name'] for task in prep['tasks'] if task['mode']=='S' and task['seed_index']==0 and task['package_id'] in packages and not study.task_complete(task['name'])]
            values.append(dict(A=scenario['A'],B=scenario['B'],names=list(dict.fromkeys(D+S))))
        return values
    return [dict(names=[n for n in names if n not in q.get('unfunded_pending',[])])]


def projected_study_jobs(study,q,scenario,c, *, reserve=True):
    prices=study.pricing()['task_estimates'];jobs=[]
    for name in scenario['names']:
        estimate=prices[name]
        jobs.append(dict(study=study.study_id,name=name,phase=task_phase(name),
            estimated_cpu_seconds=estimate['estimated_cpu_seconds'],estimated_wall_seconds=estimate['estimated_wall_seconds']))
    if reserve:
        if study.study_id=='EE':cpu=c['EE_replacement_CPU_seconds'];share=c['EE_conservative_share']
        else:
            cpu=max(row['estimated_cpu_seconds'] for row in prices.values())
            share=study.pricing()['resource_projection']['conservative_idle_share']
        jobs.append(dict(study=study.study_id,name='__replacement_reserve__',phase=1,
            estimated_cpu_seconds=cpu,estimated_wall_seconds=cpu/share))
    return jobs


def study_cpu_charge(runtime,study,c, *, active_observations=None):
    runtime=Path(runtime);total=c['EE_historical_reservation_CPU_seconds'] if study=='EE' else 0.;rows=[]
    for path in sorted((runtime/'attempts'/study).glob('*/ownership.json')):
        saved=read(path);kind=saved['kind']
        if kind!='numerical':continue
        estimate=saved['estimated_cpu_seconds'];charge=estimate;verified=False
        receipt=path.parent/'charge.json'
        if receipt.exists():
            value=read(receipt)
            if value.get('ownership_sha256')!=digest(path) or not finite(value.get('charged_CPU_seconds')):
                raise RuntimeError('attempt charge receipt differs')
            charge=value['charged_CPU_seconds'];verified=True
        observation=(active_observations or {}).get(saved['unit'],{})
        charge=max(charge,observation.get('cpu_seconds',0.)+5 if observation else 0.)
        total+=charge;rows.append(dict(unit=saved['unit'],task=saved['task'],charge=charge,final_receipt=verified))
    return total,rows


def historical_bridge(runtime,c):
    """Freeze both debit interpretations; never create an old wave3 claim."""
    runtime=Path(runtime);path=runtime/'EE_history_bridge.json'
    old=EE_CANONICAL
    required=[old/'wave_1/lease.json',old/'wave_1/terminal.json',old/'wave_2/lease.json',old/'wave_2/terminal.json']
    for value in required:
        if not value.is_file():raise RuntimeError('historical EE admission evidence missing')
    if (old/'wave_3/lease.json').exists():raise RuntimeError('old unclaimed wave3 is no longer absent')
    state=dict(schema_version=1,scientific_source_head=EE_HEAD,consumed=['1','2'],unclaimed_expired=['3'],
        old_paths_read_only=True,new_admissions=['EE-C1','EE-C2'],max_actual_admissions=4,
        historical_frozen_charge_CPU_seconds=c['EE_historical_frozen_charge_CPU_seconds'],
        prospective_historical_reservation_CPU_seconds=c['EE_historical_reservation_CPU_seconds'],
        replacement_token_consumed=(old/'r151_replacement_token.json').exists(),
        evidence_sha256={str(value):digest(value) for value in required})
    if path.exists():
        if read(path)!=state:raise RuntimeError('immutable historical EE bridge differs')
    else:immutable(path,state)
    return state


class System:
    """Exact R150/R152 names only for mutation; read-only arbitrary unit queries."""
    def __init__(self):self.old=legacy().System()
    def unit(self,name):
        value=self.old.unit(name)
        extra=subprocess.check_output(['systemctl','--user','show',name,'--property=CPUUsageNSec,CPUAccounting,MemoryCurrent'],text=True,timeout=15)
        value.update(dict(line.split('=',1) for line in extra.splitlines() if '=' in line));return value
    def members(self,cgroup):return self.old.members(cgroup)
    def process(self,pid):return legacy().process(pid)
    def start(self,name,description,argv, *, cpus,idle,runtime_seconds,controller=None,working_directory=EE_ROOT,stdout=None):
        if not name.startswith('pricefm-r150-r152-') or not name.endswith('.service'):
            raise RuntimeError('refusing a foreign service namespace')
        if not finite(runtime_seconds,positive=True):raise RuntimeError('finite service runtime required')
        command=['systemd-run','--user','--quiet','--unit='+name,'--description='+description,
            '--property=Restart=no','--property=KillMode=control-group','--property=TimeoutStopSec=15s',
            '--property=CPUAccounting=yes','--property=MemoryAccounting=yes',
            '--property=RuntimeMaxSec='+str(max(1,int(runtime_seconds)))+'s',
            '--property=WorkingDirectory='+str(working_directory),'--property=CPUAffinity='+' '.join(map(str,cpus)),
            '--property=CPUSchedulingPolicy='+('idle' if idle else 'other'),'--property=IOSchedulingClass=idle']
        if controller:command+=['--property=BindsTo='+controller,'--property=After='+controller]
        if stdout:command+=['--property=StandardOutput=file:'+str(stdout),'--property=StandardError=file:'+str(stdout)+'.stderr']
        command+=['--setenv='+name+'=1' for name in THREAD_VARS]
        command+=['--setenv=PYTHONDONTWRITEBYTECODE=1']+list(argv)
        subprocess.run(command,check=True,timeout=30)
    def stop(self,name):
        if not name.startswith('pricefm-r150-r152-'):raise RuntimeError('refusing to stop a foreign unit')
        subprocess.run(['systemctl','--user','stop',name],check=True,timeout=30)
    def stop_async(self,name):
        if not name.startswith('pricefm-r150-r152-'):raise RuntimeError('refusing to stop a foreign unit')
        return subprocess.Popen(['systemctl','--user','--no-block','stop',name],stdout=subprocess.PIPE,stderr=subprocess.PIPE)


def control_capsules(runtime):
    runtime=Path(runtime);result=[]
    for path in (runtime/'controller.json',runtime/'guardian.json',runtime.parent/'orchestrator.json'):
        if path.is_file():
            row=read(path)
            if 'capsule' in row:row=row['capsule']
            if 'unit' in row:result.append(row)
    return result


def verify_control_capsule(system,saved,c, *, allow_inactive=False):
    r=legacy();props=system.unit(saved['unit']);r.verify_owned(saved,props)
    if props.get('ActiveState') not in ('active','activating'):
        if allow_inactive:return props
        raise RuntimeError('required finite control lifetime exited: '+saved['unit'])
    proc=r.process(int(props.get('MainPID','0')))
    if (not proc or proc['scheduler']!=os.SCHED_OTHER or proc['affinity']!=c['parent_cpus']
        or props.get('IOSchedulingClass')!='3' or not props.get('InvocationID')
        or not 0<r.parse_duration(props.get('RuntimeMaxUSec',''))<=saved['runtime_seconds']):
        raise RuntimeError('responsive finite control policy differs')
    if saved.get('process') and not hardening().same_process_identity(proc,saved['process']):
        raise RuntimeError('finite control PID lifetime changed')
    if saved.get('parent') and (saved['parent'] not in props.get('BindsTo','').split() or saved['parent'] not in props.get('After','').split()):
        raise RuntimeError('finite control lost parent-death binding')
    return props


def attest_self(system,unit,c,source,runtime_seconds, *, parent=None):
    props=system.unit(unit);proc=legacy().process(os.getpid())
    if not proc or int(props.get('MainPID','0'))!=os.getpid() or not props.get('InvocationID'):
        raise RuntimeError('controller is not actual service MainPID')
    argv=[c['python_runtime'],'-B',str(ENTRY)]+sys.argv[1:]
    if legacy().exec_arguments(props)!=' '.join(argv):raise RuntimeError('controller command differs from actual argv')
    saved=dict(unit=unit,argv=argv,description=props['Description'],attested=props,process=proc,
        expected_cgroup=props['ControlGroup'],source_head=source['head'],source_entry_sha256=digest(ENTRY),
        source_entry_path=str(ENTRY),runtime_seconds=runtime_seconds,parent=parent,started_epoch=time.time())
    verify_control_capsule(system,saved,c);return saved


def launch_duration(system,path,unit,master):
    """Use the fixed pre-start lifetime bound, never a shrinking current timer."""
    intent=read(path)
    if (intent.get('unit')!=unit or intent.get('source_head')!=master['source']['head']
        or not finite(intent.get('runtime_seconds'),positive=True)
        or intent['runtime_seconds']>43200):
        raise RuntimeError('finite control launch intent differs')
    props=system.unit(unit);legacy().verify_owned(intent,props)
    if props.get('ActiveState') not in ('active','activating'):raise RuntimeError('control launch is not live')
    return intent['runtime_seconds']


def start_guardian(system,c,runtime,controller,master):
    runtime=Path(runtime);unit='pricefm-r150-r152-guardian-'+uuid.uuid4().hex+'.service'
    argv=[c['python_runtime'],'-B',str(ENTRY),'guard','--runtime',str(runtime.parent),'--config',str(CONFIG),
        '--controller-unit',controller['unit'],'--guardian-unit',unit]
    seconds=max(1.,master['expires_epoch']-time.time()-5)
    intent=dict(unit=unit,argv=argv,description='R152 independent cached-only guardian '+unit,
        expected_cgroup=str(Path(controller['attested']['ControlGroup']).parent/unit),
        source_head=master['source']['head'],source_entry_sha256=digest(ENTRY),source_entry_path=str(ENTRY),
        runtime_seconds=seconds,parent=None,started_epoch=time.time())
    immutable(runtime/'guardian_intent.json',intent)
    system.start(unit,intent['description'],argv,cpus=c['parent_cpus'],idle=False,runtime_seconds=seconds,working_directory=EE_ROOT,stdout=runtime/'guardian.stdout')
    props=system.unit(unit);legacy().verify_owned(intent,props)
    saved=dict(intent,attested=props,process=legacy().process(int(props.get('MainPID','0'))))
    verify_control_capsule(system,saved,c);immutable(runtime/'guardian.json',saved);return saved


def absolute_source_pins(source):
    root=Path(source.get('root',ROOT));pins=source.get('sha256',source.get('source_sha256',{}))
    return {str(Path(name) if Path(name).is_absolute() else root/name):value for name,value in pins.items()}


def scientific_source(study):
    if isinstance(study,EEStudy):return study.source()
    prep=study.read_preparation();identity=prep['source'];head=identity['head']
    root=identity.get('root') or identity.get('path')
    if root is None:
        root=str(ROOT) if head==git(ROOT,'rev-parse','HEAD') else str(ROOT.parent/'pricefm_r151_retirement_aware_20261023')
    return dict(root=root,head=head,sha256=prep.get('source_sha256',identity.get('sha256',{})))


def start_payload(system,c,folder,task,cpu,lease,controller,target_argv,source,probe_sha, *,
                  master_path=None,admission_path=None,slot_path=None,study=None,kind='numerical',estimated_cpu_seconds=None):
    """UUID intent precedes start; policy receipt follows actual first-exec proof.

    Used by root's source-bound disposable probe too; caller supplies its
    isolated master/admission/slot pins. No old lease writer is called.
    """
    r=legacy();folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    if master_path is None:raise RuntimeError('explicit source-bound master required')
    master_path=Path(master_path);master=read(master_path)
    admission_path=Path(admission_path) if admission_path else None
    if admission_path is None or read(admission_path)!=lease:raise RuntimeError('immutable admission file required')
    if time.time()+5>=lease['expires_epoch']:raise RuntimeError('payload cannot fit live finite admission')
    token=uuid.uuid4().hex;attempt=folder/token;attempt.mkdir()
    unit='pricefm-r150-r152-worker-'+token+'.service';receipt_path=attempt/'policy_receipt.json'
    name=task['name'];study=study or lease['study']
    if slot_path is None:
        slot_path,_=claim_slot(folder.parents[1] if folder.parent.name=='attempts' else folder.parent,master,admission_path,name,cpu,unit)
    else:
        slot_path=Path(slot_path);claim=read(slot_path)
        if claim.get('unit')!=unit:
            # Explicit probe slots may predeclare a unit/token; production does
            # not pass this path and always obtains its own atomic claim.
            unit=claim['unit']
    claim=read(slot_path)
    if claim['task']!=name or claim['cpu']!=cpu or claim['lease_id']!=lease['lease_id']:
        raise RuntimeError('global physical slot binding differs')
    target=[str(value).replace('{policy_receipt}',str(receipt_path)) for value in target_argv]
    bootstrap=ROOT/'application/scripts/pricefm/508_bootstrap_pricefm_stage_r152_payload.py'
    src=scientific_source(study) if not isinstance(study,str) else source
    scientific_head=src['head'];scientific_root=src.get('root',str(ROOT));scientific_pins=absolute_source_pins(src)
    stage='R150' if lease['study']=='EE' else 'R152'
    spec=dict(schema_version=1,stage=stage,task=name,cpu=cpu,
        resource_source_head=source['head'],resource_entry_path=str(ENTRY),resource_entry_sha256=digest(ENTRY),
        scientific_source_head=scientific_head,scientific_source_root=scientific_root,scientific_source_sha256=scientific_pins,
        source_sha256=scientific_pins,bootstrap_path=str(bootstrap),bootstrap_sha256=digest(bootstrap),
        expires_epoch=lease['expires_epoch'],policy_receipt_path=str(receipt_path),release_receipt=str(receipt_path),
        target_argv=target,master_path=str(master_path),master_sha256=digest(master_path),master_scope_id=master['scope_id'],
        admission_path=str(admission_path),admission_sha256=digest(admission_path),global_slot_path=str(slot_path),
        global_slot_sha256=digest(slot_path),lease_id=lease['lease_id'],unit=unit,controller_unit=controller['unit'],
        controller_invocation_id=controller['attested']['InvocationID'],
        instrumented_admin=(kind!='numerical'),accounting_path=str(attempt/'admin_accounting'))
    immutable(attempt/'bootstrap_spec.json',spec)
    argv=r.idle_command([c['python_runtime'],'-B',str(bootstrap),'bootstrap','--spec',str(attempt/'bootstrap_spec.json')])
    estimate=estimated_cpu_seconds if estimated_cpu_seconds is not None else task.get('estimated_cpu_seconds',0.)
    saved=dict(schema_version=1,unit=unit,token=token,study=lease['study'],kind=kind,task=name,cpu=cpu,
        description='R152 owned '+lease['study']+' '+kind+' '+token,argv=argv,
        expected_cgroup=str(Path(controller['attested']['ControlGroup']).parent/unit),
        policy_receipt=str(receipt_path),lease_id=lease['lease_id'],admission_path=str(admission_path),
        source_head=source['head'],study_source_head=scientific_head,master_scope_id=master['scope_id'],
        estimated_cpu_seconds=estimate,estimated_wall_seconds=task.get('estimated_wall_seconds',estimate),
        global_slot_path=str(slot_path),global_slot_sha256=digest(slot_path),
        accounting_path=str(attempt/'admin_accounting'),started_epoch=time.time())
    immutable(attempt/'intent.json',saved);atomic(attempt/'ownership.json',saved)
    try:
        system.start(unit,saved['description'],argv,cpus=[cpu],idle=True,
            runtime_seconds=max(1,lease['expires_epoch']-time.time()-5),controller=controller['unit'],working_directory=EE_ROOT,stdout=attempt/'stdout')
        props=system.unit(unit);r.verify_owned(saved,props)
        if props.get('InvocationID'):
            saved['attested']=props;atomic(attempt/'ownership.json',saved)
        if not props.get('InvocationID') or props.get('ControlGroup')!=saved['expected_cgroup']:
            raise RuntimeError('payload actual unit/cgroup not attested')
        until=time.monotonic()+3;proc=r.process(int(props.get('MainPID','0')))
        while proc and proc['scheduler']!=os.SCHED_IDLE and time.monotonic()<until:
            time.sleep(.02);proc=r.process(int(props.get('MainPID','0')))
        saved['process']=proc
        if proc is None or not hardening().strict_worker_policy(system,saved):raise RuntimeError('payload first-exec policy failed')
        if controller['unit'] not in props.get('BindsTo','').split() or controller['unit'] not in props.get('After','').split():
            raise RuntimeError('payload parent-death binding missing')
        saved['cpu_sample']=dict(epoch=time.monotonic(),cpu_seconds=r.cpu_seconds(proc['pid']) or 0.,pid=proc['pid'],
            start_ticks=proc['start_ticks'],boot_id=proc['boot_id'])
        atomic(attempt/'ownership.json',saved)
        receipt=dict(schema_version=1,stage=stage,task=name,cpu=cpu,expected_affinity=[cpu],expected_scheduler=5,
            numerical_threads=1,io_class=3,unit=unit,controller_unit=controller['unit'],controller_invocation_id=controller['attested']['InvocationID'],source_head=scientific_head,
            source_sha256=scientific_pins,resource_source_head=source['head'],resource_head=source['head'],lease_id=lease['lease_id'],
            lease_expires_epoch=lease['expires_epoch'],worker_invocation_id=props['InvocationID'],worker_cgroup=props['ControlGroup'],
            probe_id=probe_sha,actual_probe=dict(properties=props,process=proc),stop_request_path=str(attempt/'stop_requests'/(name+'.json')),
            master_path=str(master_path),master_sha256=digest(master_path),master_scope_id=master['scope_id'],
            admission_path=str(admission_path),admission_sha256=digest(admission_path),
            global_slot_path=str(slot_path),global_slot_sha256=digest(slot_path),
            study_source_head=scientific_head,prep_sha256=lease['prep_sha256'])
        immutable(receipt_path,receipt);return saved
    except Exception as error:
        failure=dict(error=repr(error),strongest_ownership=saved,cleanup_errors=[])
        try:failure['cleanup']=drain_exact(system,saved)
        except Exception as cleanup:failure['cleanup_errors'].append(repr(cleanup))
        immutable(attempt/'startup_failure.json',failure)
        raise RuntimeError('R152 payload startup failed: '+json.dumps(failure,sort_keys=True)) from error


def all_attempts(runtime):
    return [(path,read(path)) for path in sorted((Path(runtime)/'attempts').glob('*/*/ownership.json'))]


def unit_observation(system,saved):
    props=system.unit(saved['unit']);legacy().verify_owned(saved,props)
    group=(saved.get('attested') or {}).get('ControlGroup') or saved.get('expected_cgroup')
    members=system.members(group) if group else []
    cpu_value=props.get('CPUUsageNSec','');cpu=None
    try:
        number=int(cpu_value)
        if 0<=number<2**63:cpu=number/1e9
    except (ValueError,TypeError):pass
    live_cpu=0.;live_pids=[]
    for pid in members:
        proc=legacy().process(pid)
        if proc is not None and proc['state'] not in ('Z','X','x'):
            value=legacy().cpu_seconds(pid)
            if value is None:raise RuntimeError('owned live CPU observation unreadable')
            live_cpu+=value;live_pids.append(pid)
    return dict(properties=props,cgroup=group,members=members,live_pids=live_pids,
        cpu_seconds=max(live_cpu,cpu or 0.),active=props.get('ActiveState') in ('active','activating'),epoch=time.time())


def old_lifetime_absent(saved):
    prior=saved.get('process')
    if prior is None:return True
    current=legacy().process(prior['pid'])
    return current is None or not hardening().same_process_identity(current,prior) or current.get('state') in ('Z','X','x')


def drain_exact(system,saved,timeout=25):
    observation=unit_observation(system,saved)
    if observation['active']:
        legacy().verify_owned(saved,observation['properties']);system.stop(saved['unit'])
    until=time.monotonic()+timeout
    while True:
        value=unit_observation(system,saved)
        if not value['active'] and not value['members'] and old_lifetime_absent(saved):
            return dict(unit=saved['unit'],drained=True,members=[],pids=[],expected_cgroup=value['cgroup'],
                old_lifetime_absent=True,properties=value['properties'],epoch=time.time())
        if time.monotonic()>=until:raise RuntimeError('exact-owned unit did not drain: '+saved['unit'])
        time.sleep(.1)


def drain_scope(system,c,runtime,reason, *, deadline=None):
    """Fan out cooperative requests and stop jobs before common-deadline waits."""
    runtime=Path(runtime);saved_rows=[row for _,row in all_attempts(runtime)]
    errors=[];cleanup=[];stop_jobs=[]
    for saved in saved_rows:
        try:
            props=system.unit(saved['unit']);legacy().verify_owned(saved,props)
            if props.get('ActiveState') in ('active','activating'):
                path=Path(saved['policy_receipt']).parent/'stop_requests'/(saved['task']+'.json')
                atomic(path,dict(reason=reason,epoch=time.time(),lease_id=saved['lease_id']))
        except Exception as error:errors.append(dict(unit=saved['unit'],operation='cooperative_request',error=repr(error)))
    grace_end=min(time.monotonic()+c['cooperative_grace_seconds'],time.monotonic()+max(0,(deadline or (time.time()+30))-time.time()-c['stop_seconds']))
    while time.monotonic()<grace_end:
        if all(not unit_observation(system,saved)['active'] for saved in saved_rows):break
        time.sleep(.1)
    for saved in saved_rows:
        try:
            props=system.unit(saved['unit']);legacy().verify_owned(saved,props)
            if props.get('ActiveState') in ('active','activating'):
                stop_jobs.append((saved,system.stop_async(saved['unit'])))
        except Exception as error:errors.append(dict(unit=saved['unit'],operation='fanout_stop',error=repr(error)))
    until=time.monotonic()+c['stop_seconds']+3
    for saved,job in stop_jobs:
        try:
            code=job.wait(timeout=max(.1,until-time.monotonic()))
            if code:errors.append(dict(unit=saved['unit'],operation='stop_submit',returncode=code))
        except Exception as error:errors.append(dict(unit=saved['unit'],operation='stop_submit_wait',error=repr(error)))
    pending=list(saved_rows)
    while pending and time.monotonic()<until:
        for saved in list(pending):
            try:
                value=unit_observation(system,saved)
                if not value['active'] and not value['members'] and old_lifetime_absent(saved):
                    proof=dict(unit=saved['unit'],drained=True,members=[],pids=[],expected_cgroup=value['cgroup'],old_lifetime_absent=True,epoch=time.time())
                    cleanup.append(proof);pending.remove(saved)
                    claim=Path(saved['global_slot_path'])
                    if not (claim.parent/'released.json').exists():release_slot(claim,proof)
            except Exception as error:
                errors.append(dict(unit=saved['unit'],operation='drain_observe',error=repr(error)));pending.remove(saved)
        if pending:time.sleep(.1)
    errors.extend(dict(unit=saved['unit'],operation='drain_timeout') for saved in pending)
    return dict(cleanup_verified=not errors and len(cleanup)==len(saved_rows),cleanup_errors=errors,cleanup=cleanup,
        owned_pids=[],owned_units=[saved['unit'] for saved in saved_rows],fanout_stop=True,
        cleanup_scope='REGISTERED_NUMERICAL_BENCHMARK_ASSESSMENT_UNITS_ONLY')


def freeze_attempt_charge(path,saved,observation,study=None):
    path=Path(path);target=path.parent/'charge.json'
    if target.exists():return read(target)
    amount=max(saved['estimated_cpu_seconds'],observation['cpu_seconds']+5);verified=False;basis='CONSERVATIVE_FULL_RESERVATION'
    admin=Path(saved['accounting_path'])/'observed.json'
    seal=Path(saved['accounting_path'])/'observed.seal.json'
    if admin.is_file() and seal.is_file():
        try:
            value=read(admin);sealed=read(seal);started=read(admin.parent/'started.json')
            spec_path=path.parent/'bootstrap_spec.json';spec=read(spec_path)
            invocation=saved.get('attested',{}).get('InvocationID')
            identity=dict(task=saved['task'],unit=saved['unit'],lease_id=saved['lease_id'],invocation_id=invocation,
                resource_source_head=saved['source_head'],scientific_source_head=saved['study_source_head'],
                target_argv=spec['target_argv'],target_sha256=digest(spec['target_argv'][2]),bootstrap_spec_sha256=digest(spec_path))
            if (not invocation or sealed!={'sha256':digest(admin),'resource_source_head':saved['source_head'],'unit':saved['unit'],'invocation_id':invocation}
                or any(value.get(k)!=v or started.get(k)!=v for k,v in identity.items())
                or any(value.get(k)!=v for k,v in started.items())
                or spec['policy_receipt_path']!=saved['policy_receipt']
                or type(value.get('completed')) is not bool
                or value.get('post_observation_exit_allowance_CPU_seconds')!=5.):
                raise RuntimeError('admin CPU receipt identity differs')
            if not saved.get('process') or any(started.get('process',{}).get(k)!=saved['process'].get(k) for k in ('pid','start_ticks','boot_id')):
                raise RuntimeError('admin CPU process lifetime differs')
            policy=read(saved['policy_receipt'])
            if policy.get('worker_invocation_id')!=invocation or policy.get('task')!=saved['task'] or policy.get('source_head')!=saved['study_source_head']:
                raise RuntimeError('admin CPU policy binding differs')
            numbers=[value[key] for key in ('observed_process_CPU_seconds','observed_terminated_children_CPU_seconds','observed_total_CPU_seconds')]
            if any(not finite(number) for number in numbers) or not math.isclose(numbers[0]+numbers[1],numbers[2],abs_tol=1e-9):
                raise RuntimeError('admin CPU amount invalid')
            amount=max(numbers[2]+5.,observation['cpu_seconds']+5.)
            verified=True;basis='SEALED_FULL_PROCESS_ADMIN_OBSERVATION_PLUS_FIVE_SECOND_TAIL'
        except (OSError,KeyError,TypeError,ValueError,RuntimeError):pass
    if saved['kind']=='numerical' and isinstance(study,EEStudy):
        # This helper verifies exact original source, invocation, scientific
        # identity and final packet seal; absent/partial receipts keep prices.
        amount=max(hardening().attempt_charge(saved,study.api,study.read_preparation()),observation['cpu_seconds']+5)
        verified=study.task_complete(saved['task']);basis='IMMUTABLE_EE_ATTEMPT_ACCOUNTING'
    elif saved['kind']=='numerical' and study is not None:
        if hasattr(study,'attempt_charge'):
            value=study.attempt_charge(saved)
            candidate=value.get('charged_CPU_seconds') if isinstance(value,dict) else value
            if isinstance(value,dict):
                known={row.get('attested',{}).get('InvocationID') for _,row in all_attempts(path.parents[3]) if row['study']==saved['study'] and row['task']==saved['task']}
                unexpected=set(value.get('prior_started_invocations',[]))-known
                if unexpected or value.get('missing_prior_invocations'):
                    raise RuntimeError('scientific attempts are not completely represented in the canonical owned ledger')
            if finite(candidate):
                verified=bool(isinstance(value,dict) and value.get('verified_final_observation'))
                amount=max(candidate,observation['cpu_seconds']+5,0 if verified else saved['estimated_cpu_seconds'])
                basis='REGIONAL_VERIFIED_ATTEMPT' if verified else 'REGIONAL_CONSERVATIVE_FULL_RESERVATION'
    value=dict(schema_version=1,ownership_sha256=digest(path),unit=saved['unit'],study=saved['study'],kind=saved['kind'],
        task=saved['task'],charged_CPU_seconds=amount,verified_final_observation=verified,basis=basis,
        live_or_unit_CPU_lower_bound=observation['cpu_seconds'],epoch=time.time())
    immutable(target,value);return value


def observe_union(system,c,runtime, *, controls=()):
    runtime=Path(runtime);pids=set();observations={};active=[];charges={};admin={};control_cpu=0.
    for path,saved in all_attempts(runtime):
        value=unit_observation(system,saved);observations[saved['unit']]=value;pids.update(value['members'])
        if value['active']:
            hardening().strict_worker_policy(system,saved);active.append(saved)
            charge=max(saved['estimated_cpu_seconds'],value['cpu_seconds']+5)
        elif (path.parent/'charge.json').is_file():charge=read(path.parent/'charge.json')['charged_CPU_seconds']
        else:charge=max(saved['estimated_cpu_seconds'],value['cpu_seconds']+5)
        ledger=charges if saved['kind']=='numerical' else admin
        ledger[saved['study']]=ledger.get(saved['study'],0.)+charge
    for saved in controls:
        value=unit_observation(system,saved);pids.update(value['members']);control_cpu+=value['cpu_seconds']
    if len(controls)>c['max_control_capsules']:raise RuntimeError('control-capsule bound exceeded')
    if len(active)>c['max_workers'] or len({row['cpu'] for row in active})!=len(active):raise RuntimeError('global worker/physical slot ceiling exceeded')
    memory=legacy().memory_available_gib();disk=__import__('shutil').disk_usage(c['disk_path']).free/1024**3
    rss=legacy().rss_gib(sorted(pids))
    if memory<c['min_available_memory_gib'] or disk<c['min_disk_gib'] or rss>c['max_owned_rss_gib']:
        raise RuntimeError('host floor or whole-development RSS gate failed')
    return dict(epoch=time.time(),observations=observations,active=active,owned_pids=sorted(pids),owned_rss_gib=rss,
        available_memory_gib=memory,disk_free_gib=disk,science_charges=charges,admin_charges=admin,
        control_CPU_seconds=control_cpu)


def open_studies(c,runtime):
    result={'EE':EEStudy(c,runtime)}
    api=regional()
    result['FI']=api.open_study('FI',config_path=str(ROOT/c['FI_config']))
    result['DK2']=api.open_study('DK2')
    return result


def study_prepared(study):
    return (Path(study.PREP)/'preparation.json').is_file()


def study_price(study):
    price=study.pricing()
    if not isinstance(price,dict) or not price.get('task_estimates'):raise RuntimeError('complete frozen pricing missing')
    return price


def study_limit(study,c):
    if study.study_id=='EE':return c['EE_science_limit_CPU_seconds']
    price=study_price(study)
    value=price.get('benchmark_adjusted_available_CPU_seconds')
    if value is None:
        share=price['resource_projection']['conservative_idle_share'];value=32400*share
    if not finite(value,positive=True) or value>32400:raise RuntimeError('regional pricing ceiling invalid')
    return value


def study_source_and_prep(study):
    source=scientific_source(study)
    return source,digest(Path(study.PREP)/'preparation.json')


def command_for(study,c,name,cpu,receipt):
    if isinstance(study,EEStudy):return study.command(name,cpu,receipt)
    return study.worker_command(name,cpu,receipt,c['python_runtime'])


def replacement_available(runtime,study,c):
    if study=='EE' and (EE_CANONICAL/'r151_replacement_token.json').exists():return False
    return not (Path(runtime)/'replacement_tokens'/(study+'.json')).exists()


def projection(runtime,master,c,studies,enabled, *, observation=None,now=None,extra_blocks=()):
    """Exhibit every possible initial nominee-pair calendar on the same six CPUs."""
    runtime=Path(runtime);now=time.time() if now is None else now
    active=list((observation or {}).get('active',[]));obs=(observation or {}).get('observations',{})
    enabled=[name for name in ('EE','FI','DK2') if name in enabled and current_admission(runtime,name,'assessment')[0] is None]
    if 'EE' in enabled and 'DK2' in enabled:raise RuntimeError('EE and gated DK2 cannot share a scientific phase')
    scenarios={};queues={};limits={};charges={};window_map={};act=[];admin_active=list(extra_blocks)
    all_charges={name:study_cpu_charge(runtime,name,c,active_observations=obs)[0] for name in studies}
    regional_limits={}
    for name in ('FI','DK2'):
        try:regional_limits[name]=study_limit(studies[name],c)
        except (OSError,RuntimeError,KeyError,ValueError):pass
    for name in enabled:
        study=studies[name];q=study.queue_state();queues[name]=q
        scenarios[name]=required_scenarios(study,q)
        limits[name]=study_limit(study,c)
        charges[name]=study_cpu_charge(runtime,name,c,active_observations=obs)[0]
        window_map[name]=compute_windows(runtime,name,master,now=now)
    for saved in active:
        if saved['kind']!='numerical':
            admin_active.append(dict(study=saved['study'],name=saved['task'],phase=-1,cpu=saved['cpu'],
                projected_end_epoch=min(read(saved['admission_path'])['expires_epoch'],saved['started_epoch']+saved.get('estimated_wall_seconds',saved['estimated_cpu_seconds']))))
            continue
        if saved['study'] not in enabled:raise RuntimeError('unfunded study has a live numerical worker')
        estimate=studies[saved['study']].estimate_task(saved['task'])
        remaining=verified_remaining_wall(studies[saved['study']],saved['task'],c)
        end=now+remaining['estimated_remaining_wall_seconds']
        lease=read(saved['admission_path'])
        if end>lease['compute_expires_epoch']:return dict(fits=False,reason='active task cannot fit current finite compute interval',unit=saved['unit'])
        act.append(dict(study=saved['study'],name=saved['task'],phase=task_phase(saved['task']),cpu=saved['cpu'],projected_end_epoch=end))
    preferred={}
    if len(enabled)>1:
        lead=next(name for name in ('EE','DK2') if name in enabled)
        preferred={lead:list(range(24,28)),'FI':[28,29]}
    else:preferred={name:list(range(24,30)) for name in enabled}
    failures=[];proofs=[];worst=None
    # Nominal limits of unpriced/unadmitted regions are not spendable.
    global_limit=nominal_global_limit(c,regional_limits)
    for selected in itertools.product(*(scenarios[name] for name in enabled)):
        jobs=[];cumulative={};future={}
        for name,scenario in zip(enabled,selected):
            study=studies[name];q=queues[name]
            reserve=replacement_available(runtime,name,c) and bool(scenario['names'])
            current_jobs=projected_study_jobs(study,q,scenario,c,reserve=reserve)
            active_names={row['task'] for row in active if row['study']==name and row['kind']=='numerical'}
            pending_cpu=sum(row['estimated_cpu_seconds'] for row in current_jobs if row['name'] not in active_names)
            cumulative[name]=charges[name]+pending_cpu
            future[name]=sum(row['estimated_cpu_seconds'] for row in current_jobs)
            jobs.extend(current_jobs)
            jobs.append(dict(study=name,name='__independent_assessment_reserve__',phase=2,kind='assessment_reserve',
                estimated_wall_seconds=1800.,estimated_cpu_seconds=1800.))
        bad=[name for name in enabled if cumulative[name]>limits[name]+1e-9]
        if bad:
            failures.append(dict(reason='per-study scientific CPU ceiling',studies=bad,cumulative=cumulative));continue
        packing=pack_joint(jobs,window_map,active=act+admin_active,study_cpus=preferred,now=now)
        projected=sum(cumulative.values())+sum(value for name,value in all_charges.items() if name not in enabled)+c['global_fixed_CPU_seconds']
        if projected>global_limit+1e-9 or not packing['fits']:
            failures.append(dict(reason='global CPU or joint phase calendar',cumulative=cumulative,global_projected=projected,packing=packing));continue
        proof=dict(nominees={name:{k:v for k,v in scenario.items() if k!='names'} for name,scenario in zip(enabled,selected)},
            cumulative=cumulative,future=future,global_projected_CPU_seconds=projected,packing=packing)
        proofs.append(proof)
        if worst is None or sum(future.values())>sum(worst['future'].values()):worst=proof
    return dict(fits=not failures and bool(proofs),reason=None if not failures else failures[0]['reason'],
        checked_epoch=now,enabled=enabled,study_cpus=preferred,study_limits_CPU_seconds=limits,
        global_limit_CPU_seconds=global_limit,all_nominee_scenarios=len(proofs)+len(failures),
        scenario_proofs=proofs,failures=failures,worst=worst,base_only=True,optional_credit=0.)


def verified_remaining_wall(study,name,c):
    """No elapsed-time credit; only strict sealed checkpoints can reduce wall.

    The full task CPU price remains reserved independently in the charge ledger.
    This function never treats an elapsed timer as proof of numerical progress.
    """
    estimate=study.estimate_task(name)
    result=dict(estimated_remaining_wall_seconds=estimate['estimated_wall_seconds'],
        checkpoint_windows_verified=0,CPU_reservation_unchanged=True,elapsed_wall_credit=0.)
    if not isinstance(study,EEStudy):
        if hasattr(study,'verified_remaining_wall'):
            value=study.verified_remaining_wall(name)
            if not finite(value.get('estimated_remaining_wall_seconds'),positive=True):raise RuntimeError('regional remaining wall proof invalid')
            return dict(value,CPU_reservation_unchanged=True,elapsed_wall_credit=0.)
        return result
    prep=study.read_preparation();task=study.api.task_by_name(name,prep);producer=study.api.producer()
    required=('cpu_seconds_per_window','setup_cpu_seconds_once','origin_clock_windows')
    if not all(key in estimate for key in required):return result
    done=0
    for descriptor in producer.chunks(task):
        folder=study.OUT/'checkpoints'/name/descriptor['name']
        if not folder.exists():continue
        seal=producer.verify_packet(folder,{'chunk.json','predictions.npz'})
        identity=dict(context=producer.context_identity(task,prep),descriptor=descriptor)
        if seal.get('certified') is not True or seal.get('identity')!=identity:
            raise RuntimeError('checkpoint-derived remaining wall identity differs')
        done+=len(descriptor['origin_positions'])
    if done<0 or done>estimate['origin_clock_windows']:raise RuntimeError('checkpoint window count exceeds component support')
    if done:
        share=c['EE_conservative_share']
        cpu=estimate['setup_cpu_seconds_once']+estimate['cpu_seconds_per_window']*(estimate['origin_clock_windows']-done)
        result.update(checkpoint_windows_verified=done,estimated_remaining_wall_seconds=max(.001,cpu/share))
    return result


def free_slot(runtime,cpus):
    occupied=set()
    for path in (Path(runtime)/'slots').glob('*/claim.json'):
        if not (path.parent/'released.json').exists():occupied.add(read(path)['cpu'])
    return next((cpu for cpu in cpus if cpu not in occupied),None)


def current_admission(runtime,study,kind='numerical'):
    rows=[(path,row) for path,row in admission_files(runtime,study,kind) if not (path.parent/'terminal.json').exists()]
    if len(rows)>1:raise RuntimeError('duplicate live study admissions')
    return rows[0] if rows else (None,None)


def metadata_terminal(runtime,study,status,**details):
    path=Path(runtime)/'studies'/study/'terminal.json'
    if path.exists():return read(path)
    value=dict(schema_version=1,study=study,status=status,epoch=time.time(),new_posterior_fits=0,**details)
    immutable(path,value);return value


def study_terminal(runtime,study):
    path=Path(runtime)/'studies'/study/'terminal.json'
    return read(path) if path.exists() else None


def ee_gate(runtime):
    term=study_terminal(runtime,'EE')
    if not term or term.get('status') not in ('SCIENTIFIC_COMPLETE','CLEAN_PREFIX_COMPLETE_EXTRAS_UNFUNDED'):
        return dict(proceed=False,reason='EE has no clean complete-prefix disposition')
    path=Path(runtime)/'assessments/EE/assessment.json';seal=path.with_name('assessment.seal.json')
    if not path.is_file() or not seal.is_file() or read(seal).get('sha256')!=digest(path):
        raise RuntimeError('EE independent assessment seal missing or changed')
    value=read(path)
    if not value.get('all_D_and_matched_S0_complete') or not value.get('cleanup_preassessment_verified'):
        return dict(proceed=False,reason='EE full D/matched seed0 or drainage not verified')
    if value.get('scientific_complete') is True:return dict(proceed=True,reason='EE scientific complete assessment',assessment_sha256=digest(path))
    if value.get('entire_extra_set_unfunded_pending') is True:
        return dict(proceed=True,reason='EE clean complete prefix; entire matched extras pending',assessment_sha256=digest(path))
    return dict(proceed=False,reason='EE outcome does not satisfy original scientific/budget gate')


def assess_ee(shared_runtime,cpu,policy_receipt):
    """Owned IDLE array readback for full EE or a clean D+S0-only deferral."""
    shared=Path(shared_runtime);runtime=shared/'development';c=read_config();study=EEStudy(c,runtime)
    study.api.guard(cpu,policy_receipt,'__finalize__')
    receipt=read(policy_receipt);master=read(shared/'master.json');validate_master(master,c)
    if receipt.get('master_sha256')!=digest(shared/'master.json'):raise RuntimeError('assessment master pin differs')
    prep=study.read_preparation();q=study.queue_state()
    if not study.complete_prefix():raise RuntimeError('partial deterministic/seed0 pool cannot be assessed as a valid disposition')
    notes=read(runtime/'studies/EE/assessment_request.json')
    lease=read(receipt['admission_path'])
    if lease.get('assessment_request_sha256')!=digest(runtime/'studies/EE/assessment_request.json'):
        raise RuntimeError('assessment request source binding differs')
    if notes.get('active_workers')!=[] or not notes.get('cleanup_preassessment_verified'):
        raise RuntimeError('assessment requires exact preassessment drainage')
    full=q['terminal'] and not q.get('unfunded_pending')
    if full:original=study.api.finalize()
    else:
        if not notes.get('entire_extra_set_unfunded_pending'):
            raise RuntimeError('uncompleted extras need an atomic pending disposition')
        original=None
    # The immutable producer is used without rebinding globals or fitting.
    p=study.api.producer();nom=study.api.read_decision('nominees')['nominees']
    names=study.api.names_for([v['package_id'] for v in prep['packages']],'D',[0])+study.api.names_for([prep['control']]+nom,'S',[0])
    if full:names=study.api.manifest_state()[1]
    verification=list(original['verification']) if original else []
    for name in ([] if original else dict.fromkeys(names)):
        if not study.task_complete(name):raise RuntimeError('strict EE assessment component missing')
        task=study.api.task_by_name(name,prep)
        arrays=p.imported_arrays(task) if task['reuse'] else p.read_npz(study.OUT/'tasks_done'/name/'predictions.npz')
        p.validate_arrays(task,arrays,read(task['scaler_path']));measured=p.metrics(arrays)
        recorded=p.validate_reuse(task) if task['reuse'] else read(study.OUT/'tasks_done'/name/'result.json')['metrics']
        if any(not math.isclose(measured[k],recorded[k],rel_tol=1e-11,abs_tol=1e-10) for k in measured):
            raise RuntimeError('independent EE retained metric differs')
        verification.append(dict(name=name,metrics=measured,imported=bool(task['reuse'])))
    result=dict(schema_version=1,status='SCIENTIFIC_COMPLETE' if full else 'CLEAN_PREFIX_COMPLETE_EXTRAS_UNFUNDED',
        scientific_complete=full,all_D_and_matched_S0_complete=True,entire_extra_set_unfunded_pending=not full,
        cleanup_preassessment_verified=True,verification=verification,source=prep['source'],
        resource_source_head=master['source']['head'],master_scope_id=master['scope_id'],
        original_assessment_sha256=digest(study.OUT/'assessment.json') if original else None,
        new_model_fits=0,official_test_opened=False,promotion_authorized=False)
    out=runtime/'assessments/EE';immutable(out/'assessment.json',result)
    immutable(out/'assessment.seal.json',dict(sha256=digest(out/'assessment.json'),source=prep['source']))
    return result


def prepare(shared_runtime=SHARED,config_path=None):
    c=read_config(config_path);shared=Path(shared_runtime);runtime=shared/'development'
    source=source_identity();historical_bridge(runtime,c)
    studies=open_studies(c,runtime);preparations={}
    for name in ('FI','DK2'):
        studies[name].prepare()
        preparations[name]=dict(path=str(studies[name].PREP/'preparation.json'),sha256=digest(studies[name].PREP/'preparation.json'))
    value=dict(schema_version=1,status='R152_POOL_PREPARED_NOT_ADMITTED',source=source,config_path=str(Path(config_path or CONFIG).resolve()),
        config_sha256=digest(config_path or CONFIG),EE_bridge_sha256=digest(runtime/'EE_history_bridge.json'),
        studies=preparations,new_admissions=0,new_forecasts=0,new_model_fits=0)
    target=runtime/'prepared.json'
    if target.exists():
        if read(target)!=value:raise RuntimeError('existing pool preparation differs')
    else:immutable(target,value)
    return value


def live_guard(system,c,shared,master,controller,studies,enabled):
    shared=Path(shared);runtime=shared/'development'
    validate_master(master,c)
    if read(shared/'master.json')!=master or boot()!=master['boot_id']:raise RuntimeError('master bytes or host boot changed')
    verify_source(master['source'])
    if git(EE_ROOT,'rev-parse','HEAD')!=EE_HEAD or git(EE_ROOT,'status','--porcelain'):
        raise RuntimeError('immutable numerical EE source changed')
    baseline().baseline_ownership(shared/'baseline',master)
    controls=control_capsules(runtime)
    for capsule in controls:verify_control_capsule(system,capsule,c)
    observation=observe_union(system,c,runtime,controls=controls)
    actual_science=dict(observation['science_charges'])
    actual_science['EE']=actual_science.get('EE',0.)+c['EE_historical_reservation_CPU_seconds']
    limits={'EE':c['EE_science_limit_CPU_seconds']}
    for name in ('FI','DK2'):
        try:limits[name]=study_limit(studies[name],c)
        except (OSError,RuntimeError,KeyError,ValueError):limits[name]=0.
    for name,amount in actual_science.items():
        if amount>limits.get(name,0.)+1e-8:raise RuntimeError('per-study cumulative scientific allowance exhausted: '+name)
    if observation['control_CPU_seconds']>=c['shared_control_CPU_seconds']-stop_tail_reserve(c,0):
        raise RuntimeError('shared control CPU allowance stop headroom exhausted')
    global_used=sum(actual_science.values())+sum(observation['admin_charges'].values())+observation['control_CPU_seconds']
    global_limit=nominal_global_limit(c,{name:limit for name,limit in limits.items() if name!='EE'})
    tail=stop_tail_reserve(c,len(observation['active']))
    if global_used+tail>global_limit:raise RuntimeError('global cumulative CPU stop-tail headroom exhausted')
    for saved in observation['active']:
        lease=read(saved['admission_path'])
        if (lease['master_scope_id']!=master['scope_id'] or lease['source_head']!=master['source']['head']
            or lease['boot_id']!=master['boot_id'] or time.time()>=lease['expires_epoch']):
            raise RuntimeError('active task escaped its immutable admission/master')
        starvation=legacy().starvation_predicate(saved,dict(starvation_observation_seconds=300,starvation_min_cpu_share=.10))
        if starvation and starvation.get('starved'):raise RuntimeError('live task starvation requires bounded replacement or defer: '+saved['unit'])
    observation.update(global_charged_CPU_seconds=global_used,global_limit_CPU_seconds=global_limit,
        stop_tail_reserve_CPU_seconds=tail,study_limits_CPU_seconds=limits)
    return observation


def finish_worker(system,c,runtime,path,saved,study):
    observation=unit_observation(system,saved)
    if observation['active']:return None
    proof=drain_exact(system,saved);charge=freeze_attempt_charge(path,saved,observation,study)
    slot=Path(saved['global_slot_path'])
    if not (slot.parent/'released.json').exists():release_slot(slot,proof)
    marker=path.parent/'finished.json'
    if not marker.exists():immutable(marker,dict(cleanup=proof,charge_sha256=digest(path.parent/'charge.json'),epoch=time.time()))
    return dict(proof=proof,charge=charge,observation=observation)


def drained_attempts(runtime,study=None):
    rows=[]
    for path,saved in all_attempts(runtime):
        if study is not None and saved['study']!=study:continue
        if not (path.parent/'finished.json').exists():return False
        if not read(path.parent/'finished.json')['cleanup'].get('drained'):return False
        rows.append(saved)
    return True


def active_for(observation,study,kind=None):
    return [row for row in observation['active'] if row['study']==study and (kind is None or row['kind']==kind)]


def strict_new_count(study,started_complete):
    return len(set(study.queue_state().get('complete',[]))-set(started_complete))


def close_compute(runtime,study,lease_path, *, reason,unfunded=()):
    if not drained_attempts(runtime,study):raise RuntimeError('compute closure needs every study lifetime drained')
    lease=read(lease_path);path=Path(lease_path).parent/'compute_closed.json'
    value=dict(schema_version=1,lease_id=lease['lease_id'],study=study,active_workers=[],closed_epoch=time.time(),
        numerical_dispatch_closed=True,reason=reason,entire_extra_set_unfunded_pending=list(unfunded))
    if path.exists():return read(path)
    immutable(path,value);return value


def defer_current_wave(system,c,runtime,study,lease_path,reason):
    """Finite planned checkpoint stop, not a replacement or new lease refund."""
    selected=[saved for _,saved in all_attempts(runtime) if saved['study']==study and read(saved['admission_path'])['lease_id']==read(lease_path)['lease_id']]
    for saved in selected:
        row=unit_observation(system,saved)
        if row['active']:
            atomic(Path(saved['policy_receipt']).parent/'stop_requests'/(saved['task']+'.json'),dict(reason=reason,epoch=time.time()))
            marker=Path(saved['policy_receipt']).parent/'planned_stop.json'
            if not marker.exists():immutable(marker,dict(reason=reason,lease_id=saved['lease_id'],epoch=time.time()))
    # Fan out exact stop jobs after a common checkpoint grace, rather than
    # block on one unit while the other five can continue past their deadline.
    until=time.monotonic()+c['cooperative_grace_seconds']
    while time.monotonic()<until and any(unit_observation(system,s)['active'] for s in selected):time.sleep(.1)
    jobs=[]
    for saved in selected:
        value=unit_observation(system,saved)
        if value['active']:
            legacy().verify_owned(saved,value['properties']);jobs.append(system.stop_async(saved['unit']))
    stop_end=time.monotonic()+c['stop_seconds']+3
    for job in jobs:job.wait(timeout=max(.1,stop_end-time.monotonic()))
    return reason


def _projection_or_defer(runtime,master,c,studies,enabled,observation):
    result=projection(runtime,master,c,studies,enabled,observation=observation)
    atomic(Path(runtime)/'latest_projection.json',result)
    return result


def admin_projection(runtime,master,c,studies,enabled,study,kind,cpu,observation):
    amount=c['benchmark_CPU_seconds'] if kind=='benchmark' else c['assessment_CPU_seconds']
    remaining=set(enabled)-({study} if kind=='assessment' else set())
    now=time.time();duration=c['benchmark_seconds'] if kind=='benchmark' else c['assessment_seconds']
    block=dict(study=study,name='__'+kind+'__',phase=-1,cpu=cpu,projected_end_epoch=now+duration)
    base=projection(runtime,master,c,studies,remaining,observation=observation,now=now,extra_blocks=[block])
    return dict(fits=base.get('fits') is True,kind=kind,study=study,CPU_allowance=amount,base_projection=base,
        global_charged_CPU_seconds=observation.get('global_charged_CPU_seconds',0),
        global_limit_CPU_seconds=observation.get('global_limit_CPU_seconds',0),base_projection_sha256=fingerprint(base),
        no_candidate_losses_used=(kind=='benchmark'))


def start_study_task(system,c,shared,runtime,master,controller,study,name,cpu,lease_path,lease,kind,probe_sha):
    source=master['source'];estimate=(dict(estimated_cpu_seconds=c['benchmark_CPU_seconds'],estimated_wall_seconds=c['benchmark_seconds']) if kind=='benchmark'
        else dict(estimated_cpu_seconds=c['assessment_CPU_seconds'],estimated_wall_seconds=c['assessment_seconds']) if kind=='assessment'
        else study.estimate_task(name))
    target=command_for(study,c,name,cpu,'{policy_receipt}')
    if estimate.get('name',name)!=name:raise RuntimeError('scientific price names a different task')
    task=dict(estimate);task['name']=name
    saved=start_payload(system,c,runtime/'attempts'/study.study_id,task,cpu,lease,controller,target,source,probe_sha,
        master_path=shared/'master.json',admission_path=lease_path,study=study,kind=kind)
    event(runtime,'worker_released',study=study.study_id,task=name,unit=saved['unit'],cpu=cpu,payload_kind=kind,admission_id=lease['admission_id'])
    return saved


def _assessment_ready(study,q,runtime):
    if study.study_id=='EE':
        if not study.complete_prefix():return False,[]
        if q.get('terminal') or q.get('unfunded_pending'):return True,q.get('unfunded_pending',[])
        resource=Path(runtime)/'studies/EE/extras_resource_admission.json'
        if resource.exists() and not read(resource)['admitted']:return True,read(resource)['components']
        return False,[]
    resource=Path(runtime)/'studies'/study.study_id/'extras_resource_admission.json'
    if q.get('phase')=='MATCHED_FULL_MC' and resource.exists() and not read(resource)['admitted']:
        prep=study.read_preparation();nom=study.read_decision('nominees')['nominees']
        prefix=study.names_for([row['package_id'] for row in prep['packages']],'D',[0])+study.names_for([prep['control']]+nom,'S',[0])
        if not all(study.task_complete(name) for name in prefix):raise RuntimeError('resource pending extras lack full D/matched S0')
        return True,read(resource)['components']
    return bool(q.get('assessment_ready') or q.get('terminal')) and q.get('phase') not in ('BENCHMARK','BENCHMARK_REQUIRED','DEFERRED_UNFUNDED_PREFIX'),q.get('unfunded_pending',[])


def regional_prefix_priced(price):
    if type(price.get('prefix_admitted')) is not bool:raise RuntimeError('regional full-prefix pricing decision missing')
    return price['prefix_admitted']


def run(shared_runtime=SHARED,config_path=None,unit=None):
    c=read_config(config_path);shared=Path(shared_runtime);runtime=shared/'development';system=System()
    if unit is None:raise RuntimeError('actual unit identity required')
    master=read(shared/'master.json');validate_master(master,c);verify_source(master['source'])
    if (runtime/'terminal.json').exists():raise RuntimeError('terminal shared scope cannot restart/join')
    if not (runtime/'prepared.json').is_file():raise RuntimeError('pool must be prepared before master/loan commitment')
    prepared=read(runtime/'prepared.json')
    if prepared['source']!=master['source']:raise RuntimeError('prepared/master resource source differs')
    with contextlib.ExitStack() as stack:
        for path in (runtime/'dispatcher.lock',EE_CANONICAL/'workflow.lock',EE_CANONICAL/'controller.lock'):
            stack.enter_context(locked(path))
        historical_bridge(runtime,c)
        parent=read(shared/'orchestrator.json')
        if 'capsule' in parent:parent=parent['capsule']
        duration=launch_duration(system,runtime/'control/intent.json',unit,master)
        capsule=attest_self(system,unit,c,master['source'],duration,parent=parent['unit'])
        immutable(runtime/'controller.json',capsule)
        studies=open_studies(c,runtime);guardian=start_guardian(system,c,runtime,capsule,master)
        initial={name:studies[name].queue_state().get('complete',[]) if study_prepared(studies[name]) else [] for name in studies}
        funded={'EE'};stopped=[False];fatal=None;terminal_status='R152_SHARED_TRANCHE_DEFERRED';delivery_verified=False
        for signum in (signal.SIGTERM,signal.SIGINT):signal.signal(signum,lambda *_:stopped.__setitem__(0,True))
        probe_sha=master.get('probe_sha256',master.get('capability_probe_sha256',''))
        if not probe_sha:
            probe=shared/'probe.json'
            if not probe.is_file():raise RuntimeError('committed-source capability probe pin missing')
            probe_sha=digest(probe)
        try:
            while True:
                if stopped[0]:raise RuntimeError('finite master requested cooperative stop')
                if time.time()>=master['expires_epoch']-c['cooperative_grace_seconds']-c['stop_seconds']-c['poll_seconds']:
                    terminal_status='R152_MASTER_EXPIRED';break
                observation=live_guard(system,c,shared,master,capsule,studies,funded)
                # Reap only our exact units and finish their nonoverlapping CPU
                # accounts before any new scientific decision or slot release.
                for path,saved in all_attempts(runtime):
                    if (path.parent/'finished.json').exists():continue
                    value=observation['observations'][saved['unit']]
                    if value['active']:continue
                    result=finish_worker(system,c,runtime,path,saved,studies[saved['study']])
                    if result is None:continue
                    kind=saved['kind'];name=saved['study'];study=studies[name]
                    lease_path=Path(saved['admission_path'])
                    if kind=='numerical':
                        if not study.task_complete(saved['task']) and not (path.parent/'planned_stop.json').exists():
                            raise RuntimeError('numerical worker exited without strict component seal: '+saved['task'])
                        if study.task_complete(saved['task']) and name=='EE':
                            share=result['charge'].get('live_or_unit_CPU_lower_bound',0.)/max(.001,time.time()-saved['started_epoch'])
                            if share>=c['EE_conservative_share']:delivery_verified=True
                    elif kind=='benchmark':
                        try:
                            price=study_price(study)
                            if result['observation']['properties'].get('ExecMainStatus','0')!='0':raise RuntimeError('regional benchmark exited with error')
                        except (OSError,KeyError,ValueError,RuntimeError) as error:
                            close_admission(lease_path,'BENCHMARK_DEFERRED',cleanup_verified=True,error=repr(error))
                            metadata_terminal(runtime,name,'DEFERRED_BENCHMARK',reason=repr(error));continue
                        close_admission(lease_path,'BENCHMARK_COMPLETE',cleanup_verified=True,pricing_sha256=fingerprint(price))
                        if not regional_prefix_priced(price):
                            metadata_terminal(runtime,name,'DEFERRED_PREFIX_UNFUNDED',reason='own full-prefix science allowance does not fit',pricing_sha256=fingerprint(price))
                            continue
                        candidate=set(funded)|{name}
                        projected=_projection_or_defer(runtime,master,c,studies,candidate,observation)
                        if projected['fits']:funded.add(name)
                        else:metadata_terminal(runtime,name,'DEFERRED_PREFIX_UNFUNDED',reason=projected['reason'],projection_sha256=fingerprint(projected))
                    else:
                        if result['observation']['properties'].get('ExecMainStatus','0')!='0':raise RuntimeError('independent assessment failed: '+name)
                        if name=='EE':
                            assessed=read(runtime/'assessments/EE/assessment.json');status=assessed['status']
                        else:
                            assessed=study.queue_state()
                            if not assessed.get('execution_terminal') and not assessed.get('scientific_complete'):
                                raise RuntimeError('regional assessment produced no sealed terminal')
                            status='SCIENTIFIC_COMPLETE' if assessed.get('scientific_complete') else 'CLEAN_PREFIX_COMPLETE_EXTRAS_UNFUNDED'
                        close_admission(lease_path,'ASSESSMENT_COMPLETE',cleanup_verified=True)
                        parent_path=Path(read(lease_path)['parent_admission_path'])
                        close_admission(parent_path,'NUMERICAL_COMPLETE_ASSESSED',cleanup_verified=True)
                        metadata_terminal(runtime,name,status,cleanup_verified=True,assessment_sealed=True)
                        funded.discard(name)
                observation=live_guard(system,c,shared,master,capsule,studies,funded)
                # Owned assessments/admin caps stop with tail headroom. A timed
                # regional benchmark is local to that stage; no automatic rerun.
                for saved in list(observation['active']):
                    lease=read(saved['admission_path']);obs=observation['observations'][saved['unit']]
                    if saved['kind']!='numerical' and (obs['cpu_seconds']>=saved['estimated_cpu_seconds']-30 or time.time()>=lease['expires_epoch']-30):
                        defer_current_wave(system,c,runtime,saved['study'],Path(saved['admission_path']),'finite admin allowance stop')
                # Advance each region using metadata only; full D and ready
                # matched decisions remain enforced by the immutable science.
                for name in list(funded):
                    if active_for(observation,name):continue
                    study=studies[name]
                    study.advance(remaining_CPU_seconds=max(0.,study_limit(study,c)-study_cpu_charge(runtime,name,c)[0]),budget_view=None)
                observation=live_guard(system,c,shared,master,capsule,studies,funded)
                # End numerical allocations at their finite compute cutoff.
                for name in list(funded):
                    lease_path,lease=current_admission(runtime,name)
                    if lease is None:continue
                    if (lease_path.parent/'compute_closed.json').exists():continue
                    if time.time()>=lease['compute_expires_epoch']-c['cooperative_grace_seconds']-c['stop_seconds']-c['poll_seconds']:
                        defer_current_wave(system,c,runtime,name,lease_path,'finite numerical allocation elapsed')
                observation=live_guard(system,c,shared,master,capsule,studies,funded)
                projected=_projection_or_defer(runtime,master,c,studies,funded,observation) if funded else dict(fits=True,enabled=[],worst=None)
                # A complete matched-extra set is an atomic, independent
                # resource decision; it cannot silently claim a partial seed.
                for name in list(funded):
                    study=studies[name];q=study.queue_state()
                    if q['phase']=='MATCHED_FULL_MC' and not active_for(observation,name):
                        components=list(q['pending']);gate=runtime/'studies'/name/'extras_resource_admission.json'
                        if not gate.exists():immutable(gate,dict(components=components,admitted=projected['fits'],projection_sha256=fingerprint(projected),epoch=time.time()))
                        if read(gate)['components']!=components and not read(gate)['admitted']:
                            raise RuntimeError('unfunded matched-extra component set changed')
                    ready,unfunded=_assessment_ready(study,q,runtime)
                    lease_path,lease=current_admission(runtime,name)
                    if ready and lease is not None and not active_for(observation,name) and current_admission(runtime,name,'assessment')[0] is None:
                        close_compute(runtime,name,lease_path,reason='science complete or entire extras unfunded',unfunded=unfunded)
                        request=dict(active_workers=[],cleanup_preassessment_verified=drained_attempts(runtime,name),
                            entire_extra_set_unfunded_pending=bool(unfunded),unfunded_components=list(unfunded),epoch=time.time())
                        disposition=runtime/'studies'/name/'extras_resource_admission.json'
                        if disposition.is_file():request.update(resource_disposition_path=str(disposition),resource_disposition_sha256=digest(disposition))
                        target=runtime/'studies'/name/'assessment_request.json'
                        if not target.exists():immutable(target,request)
                        source,prep_sha=study_source_and_prep(study)
                        cpu=free_slot(runtime,list(range(24,30)))
                        if cpu is None:raise RuntimeError('no physical slot for admitted assessment')
                        approval=admin_projection(runtime,master,c,studies,funded,name,'assessment',cpu,observation)
                        if not approval['fits']:raise RuntimeError('assessment cannot fit common funded calendar')
                        apath,alease=claim_admission(runtime,master,name,'assessment',source['head'],prep_sha,unit,projection=approval)
                        start_study_task(system,c,shared,runtime,master,capsule,study,'__finalize__',cpu,apath,alease,'assessment',probe_sha)
                # Regional cost-only studies can start after actual accepted EE
                # delivery. No FI score is opened by preparation or pricing.
                for name in ('FI','DK2'):
                    if study_terminal(runtime,name) or admission_files(runtime,name,'benchmark'):continue
                    if name=='FI' and not delivery_verified:continue
                    if name=='DK2' and not ee_gate(runtime)['proceed']:continue
                    study=studies[name]
                    if not study_prepared(study):metadata_terminal(runtime,name,'DEFERRED_PREPARATION_MISSING');continue
                    cpu=free_slot(runtime,list(range(24,30)))
                    if cpu is None:continue
                    # Benchmarks take one real global slot and fixed CPU; the
                    # conservative simultaneous proof retains EE/FI prefixes.
                    base=_projection_or_defer(runtime,master,c,studies,funded,observation) if funded else dict(fits=True)
                    if not base['fits']:continue
                    source,prep_sha=study_source_and_prep(study)
                    approval=admin_projection(runtime,master,c,studies,funded,name,'benchmark',cpu,observation)
                    if not approval['fits']:continue
                    try:path,lease=claim_admission(runtime,master,name,'benchmark',source['head'],prep_sha,unit,
                        projection=approval)
                    except RuntimeError as error:
                        metadata_terminal(runtime,name,'DEFERRED_BENCHMARK_WINDOW',reason=repr(error));continue
                    start_study_task(system,c,shared,runtime,master,capsule,study,'__benchmark__',cpu,path,lease,'benchmark',probe_sha)
                observation=live_guard(system,c,shared,master,capsule,studies,funded)
                projected=_projection_or_defer(runtime,master,c,studies,funded,observation) if funded else dict(fits=True,worst=None)
                dispatched=False
                if projected['fits']:
                    assignments=(projected.get('worst') or {}).get('packing',{}).get('allocation',[])
                    for name in ('EE','FI','DK2'):
                        if name not in funded or study_terminal(runtime,name):continue
                        study=studies[name];q=study.queue_state();ready=[row for row in q.get('ready',[]) if row['name'] not in {x['task'] for x in observation['active']}]
                        if not ready:continue
                        path,lease=current_admission(runtime,name)
                        if lease is None:
                            source,prep_sha=study_source_and_prep(study)
                            try:path,lease=claim_admission(runtime,master,name,'numerical',source['head'],prep_sha,unit,projection=projected)
                            except RuntimeError as error:
                                metadata_terminal(runtime,name,'DEFERRED_NO_WHOLE_WINDOW',reason=repr(error));funded.discard(name);continue
                            immutable(path.parent/'start_complete.json',dict(names=q.get('complete',[]),epoch=time.time()))
                            projected=_projection_or_defer(runtime,master,c,studies,funded,observation)
                            assignments=(projected.get('worst') or {}).get('packing',{}).get('allocation',[])
                        if (path.parent/'compute_closed.json').exists():continue
                        for task in ready:
                            choices=[row for row in assignments if row.get('study')==name and row.get('name')==task['name'] and row.get('window_id')==lease['admission_id'] and not row.get('active')]
                            if not choices:continue
                            choice=min(choices,key=lambda x:(x['start'],x['cpu']))
                            if choice['start']>time.time()+c['poll_seconds']:continue
                            cpu=choice['cpu']
                            if free_slot(runtime,[cpu]) is None:continue
                            start_study_task(system,c,shared,runtime,master,capsule,study,task['name'],cpu,path,lease,'numerical',probe_sha)
                            dispatched=True
                # Planned compute stops close their window only after every
                # worker/CPU account has drained, then reserve a new whole lease.
                observation=live_guard(system,c,shared,master,capsule,studies,funded)
                for name in list(funded):
                    path,lease=current_admission(runtime,name)
                    if lease and time.time()>=lease['compute_expires_epoch']-c['cooperative_grace_seconds']-c['stop_seconds']-c['poll_seconds'] and not active_for(observation,name):
                        close_admission(path,'FINITE_WINDOW_DEFERRED',cleanup_verified=drained_attempts(runtime,name))
                        if len(admission_files(runtime,name,'numerical'))>=len(admission_identifiers(name)):
                            metadata_terminal(runtime,name,'DEFERRED_PARTIAL_PREFIX',strict_new_components=strict_new_count(studies[name],initial[name]));funded.discard(name)
                if not projected.get('fits',True) and not observation['active']:
                    for name in list(funded):
                        study=studies[name];q=study.queue_state()
                        if q.get('phase')=='MATCHED_FULL_MC' and (runtime/'studies'/name/'extras_resource_admission.json').exists():continue
                        metadata_terminal(runtime,name,'DEFERRED_JOINT_FUNDING',reason=projected.get('reason'));funded.discard(name)
                if study_terminal(runtime,'EE') and not delivery_verified and not admission_files(runtime,'FI','benchmark') and not study_terminal(runtime,'FI'):
                    metadata_terminal(runtime,'FI','DEFERRED_POOL_DELIVERY_NOT_VALIDATED')
                done=all(study_terminal(runtime,name) is not None for name in ('EE','FI'))
                if done and not study_terminal(runtime,'DK2') and not ee_gate(runtime)['proceed']:
                    metadata_terminal(runtime,'DK2','BLOCKED_EE_DISPOSITION')
                if all(study_terminal(runtime,name) is not None for name in studies) and not observation['active']:
                    terminal_status='R152_FINITE_TRANCHE_DISPOSITION_SEALED';break
                atomic(runtime/'progress.json',dict(status='R152_RUNNING',epoch=time.time(),scope_id=master['scope_id'],
                    phases={name:(studies[name].queue_state().get('phase') if study_prepared(studies[name]) else 'UNPREPARED') for name in studies},
                    active=[dict(study=row['study'],task=row['task'],cpu=row['cpu'],unit=row['unit']) for row in observation['active']],
                    observation={k:v for k,v in observation.items() if k not in ('observations','active')},
                    funded_studies=sorted(funded),delivery_verified=delivery_verified,dispatched=dispatched))
                time.sleep(c['poll_seconds'])
        except Exception as error:
            fatal=repr(error);terminal_status='R152_GUARD_STOPPED';event(runtime,'guard_stopped',error=fatal)
        finally:
            proof=drain_scope(system,c,runtime,fatal or terminal_status,deadline=master['expires_epoch'])
            for path,saved in all_attempts(runtime):
                try:
                    if not (path.parent/'finished.json').exists():finish_worker(system,c,runtime,path,saved,studies[saved['study']])
                except Exception as error:proof['cleanup_errors'].append(dict(unit=saved['unit'],operation='final_cpu_account',error=repr(error)));proof['cleanup_verified']=False
            if proof['cleanup_verified']:
                immutable(runtime/'drained.json',dict(schema_version=1,scope_id=master['scope_id'],master_sha256=digest(shared/'master.json'),
                    source_head=master['source']['head'],epoch=time.time(),**proof))
            terminal=dict(schema_version=1,status=terminal_status,original_stop_reason=fatal,scope_id=master['scope_id'],
                master_sha256=digest(shared/'master.json'),epoch=time.time(),source_head=master['source']['head'],
                study_dispositions={name:study_terminal(runtime,name) for name in studies},new_model_fits=0,baseline_signals=0,**proof)
            immutable(runtime/'terminal.json',terminal)
            try:
                props=system.unit(guardian['unit']);legacy().verify_owned(guardian,props)
                if props.get('ActiveState') in ('active','activating'):system.stop(guardian['unit'])
            except Exception as error:
                atomic(runtime/'guardian_cleanup_error.json',dict(error=repr(error),epoch=time.time()))
        return terminal


def guard(shared_runtime=SHARED,config_path=None,controller_unit=None,guardian_unit=None):
    c=read_config(config_path);shared=Path(shared_runtime);runtime=shared/'development';system=System()
    master=read(shared/'master.json')
    validate_master(master,c,allow_expired=True);verify_source(master['source'])
    if guardian_unit is None:raise RuntimeError('actual independent guardian unit required')
    duration=launch_duration(system,runtime/'guardian_intent.json',guardian_unit,master)
    own=attest_self(system,guardian_unit,c,master['source'],duration)
    until=time.monotonic()+20
    while (not (runtime/'controller.json').exists() or not (runtime/'guardian.json').exists()) and time.monotonic()<until:time.sleep(.05)
    registered=read(runtime/'guardian.json')
    if registered['attested']['InvocationID']!=own['attested']['InvocationID'] or registered['unit']!=guardian_unit:
        raise RuntimeError('guardian is not the registered exact owned lifetime')
    controller=read(runtime/'controller.json')
    if controller_unit!=controller['unit']:raise RuntimeError('guardian controller identity differs')
    while not (runtime/'terminal.json').exists():
        reason=None
        try:
            props=system.unit(controller['unit']);legacy().verify_owned(controller,props)
            if props.get('ActiveState') not in ('active','activating'):reason='owned broker lifetime exited'
        except Exception as error:reason='owned broker identity became unavailable or changed: '+repr(error)
        if reason or time.time()>=master['expires_epoch']-30:
            proof=drain_scope(system,c,runtime,'independent guardian: '+(reason or 'master expiry'),deadline=master['expires_epoch'])
            atomic(runtime/'guardian_drain.json',dict(epoch=time.time(),scope_id=master['scope_id'],**proof));return proof
        time.sleep(c['poll_seconds'])
    return dict(status='GUARDIAN_EXITED_AFTER_BROKER_TERMINAL',epoch=time.time())


def verify_all_drained(shared_runtime,master=None,system=None):
    shared=Path(shared_runtime);runtime=shared/'development';master=master or read(shared/'master.json');system=system or System()
    rows=[]
    for _,saved in all_attempts(runtime):
        observation=unit_observation(system,saved)
        if observation['active'] or observation['members'] or not old_lifetime_absent(saved):raise RuntimeError('cached-owned lifetime is not drained')
        rows.append(dict(unit=saved['unit'],drained=True,expected_cgroup=observation['cgroup'],pids=[]))
    for name in ('controller.json','guardian.json'):
        if not (runtime/name).exists():continue
        saved=read(runtime/name);observation=unit_observation(system,saved)
        if observation['active'] or observation['members'] or not old_lifetime_absent(saved):raise RuntimeError('cached control lifetime is not drained: '+name)
        rows.append(dict(unit=saved['unit'],drained=True,expected_cgroup=observation['cgroup'],pids=[]))
    return dict(schema_version=1,scope_id=master['scope_id'],master_sha256=digest(shared/'master.json'),cleanup_verified=True,
        owned_pids=[],owned_units=[row['unit'] for row in rows],cleanup=rows,epoch=time.time(),source_head=master['source']['head'],
        cleanup_scope='CACHED_PAYLOADS_BROKER_GUARDIAN_EXCLUDING_CALLING_PUBLISHER')


def status(shared_runtime=SHARED):
    shared=Path(shared_runtime);runtime=shared/'development';result=dict(stage='R152',new_model_fits=0)
    for name in ('prepared','controller','progress','terminal','drained'):
        path=runtime/(name+'.json')
        if path.exists():result[name]=read(path)
    if (shared/'master.json').exists():result['master']=read(shared/'master.json')
    return result


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=('prepare','run','guard','status','assess-ee'))
    parser.add_argument('--runtime',default=str(SHARED));parser.add_argument('--config',default=str(CONFIG))
    parser.add_argument('--unit');parser.add_argument('--controller-unit');parser.add_argument('--guardian-unit')
    parser.add_argument('--cpu',type=int);parser.add_argument('--policy-receipt')
    args=parser.parse_args(argv)
    if args.command=='prepare':value=prepare(args.runtime,args.config)
    elif args.command=='run':value=run(args.runtime,args.config,args.unit)
    elif args.command=='guard':value=guard(args.runtime,args.config,args.controller_unit,args.guardian_unit)
    elif args.command=='assess-ee':value=assess_ee(args.runtime,args.cpu,args.policy_receipt)
    else:value=status(args.runtime)
    print(json.dumps(value,sort_keys=True,allow_nan=False));return 0


if __name__=='__main__':raise SystemExit(main())
