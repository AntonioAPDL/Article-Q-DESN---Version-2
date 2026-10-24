#!/usr/bin/env python3
"""First-exec policy and dual-source release for an owned R152 payload.

This standard-library bootstrap never forecasts or changes scheduler policy.
The parent must attest its exact unit before publishing the one-use receipt.
EE's immutable worker continues to see its original scientific source identity.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import runpy
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
THREAD_VARS = ('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS',
               'BLIS_NUM_THREADS','NUMEXPR_NUM_THREADS','VECLIB_MAXIMUM_THREADS')
PYTHON = '/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python'

def read(path):
    return json.loads(Path(path).read_text())

def digest(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            result.update(block)
    return result.hexdigest()

def git(root,*args):
    return subprocess.check_output(['git','-C',str(root),*args],text=True,
        timeout=30).strip()

def finite_number(value):
    return not isinstance(value,bool) and isinstance(value,(int,float)) and math.isfinite(value)

def process_snapshot():
    text = Path('/proc/self/stat').read_text()
    tail = text[text.rfind(')')+2:].split()
    threads=next(int(line.split()[1]) for line in Path('/proc/self/status').read_text().splitlines() if line.startswith('Threads:'))
    return dict(pid=os.getpid(),start_ticks=int(tail[19]),state=tail[0],threads=threads,
        boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
        affinity=sorted(os.sched_getaffinity(0)),scheduler=os.sched_getscheduler(0))

def first_exec_policy(cpu):
    if type(cpu) is not int or cpu not in range(15,30):
        raise RuntimeError('payload CPU is outside the immutable numerical domain')
    snap = process_snapshot()
    if snap['affinity'] != [cpu] or snap['scheduler'] != os.SCHED_IDLE:
        raise RuntimeError('first-exec physical affinity or IDLE policy differs')
    if any(os.environ.get(key) != '1' for key in THREAD_VARS):
        raise RuntimeError('first-exec numerical thread environment differs')
    if not subprocess.check_output(['ionice','-p',str(os.getpid())],text=True,
                                   timeout=5).startswith('idle'):
        raise RuntimeError('first-exec idle I/O is required')
    return snap

def validate_spec(spec, *, now=None, resource_root=ROOT, verify_files=True):
    now = time.time() if now is None else now
    if spec.get('schema_version',spec.get('schema')) != 1:
        raise RuntimeError('unknown payload specification schema')
    if spec.get('stage') not in ('R150','R152'):
        raise RuntimeError('unknown payload scientific stage')
    if type(spec.get('cpu')) is not int or spec['cpu'] not in range(15,30):
        raise RuntimeError('invalid payload physical CPU')
    if not finite_number(spec.get('expires_epoch')) or spec['expires_epoch'] <= now:
        raise RuntimeError('payload expiry is absent, non-finite or expired')
    for key in ('task','lease_id','unit','controller_unit','resource_source_head',
                'scientific_source_head','master_path','master_sha256',
                'admission_path','admission_sha256','global_slot_path',
                'policy_receipt_path','resource_entry_path','resource_entry_sha256',
                'bootstrap_path','scientific_source_root'):
        if not isinstance(spec.get(key),str) or not spec[key]:
            raise RuntimeError('missing payload identity: '+key)
    slot_sha = spec.get('global_slot_sha256',spec.get('global_slot_claim_sha256',spec.get('claimsha')))
    if not isinstance(slot_sha,str) or len(slot_sha) != 64:
        raise RuntimeError('missing immutable global slot claim hash')
    bootstrap_sha = spec.get('bootstrap_sha256',spec.get('bootstrap_sha'))
    if not isinstance(bootstrap_sha,str) or len(bootstrap_sha) != 64:
        raise RuntimeError('missing bootstrap source hash')
    if not spec['unit'].startswith('pricefm-r150-r152-') or not spec['unit'].endswith('.service'):
        raise RuntimeError('payload unit lacks its owned UUID namespace')
    if not spec['controller_unit'].startswith('pricefm-r150-r152-'):
        raise RuntimeError('payload controller lacks the owned namespace')
    if not isinstance(spec.get('scientific_source_sha256'),dict) or not spec['scientific_source_sha256']:
        raise RuntimeError('scientific source pins are required')
    resource_root = Path(resource_root).resolve()
    scientific_root = Path(spec['scientific_source_root']).resolve()
    entry = Path(spec['resource_entry_path']).resolve()
    if not entry.is_relative_to(resource_root) or not Path(spec['bootstrap_path']).resolve().is_relative_to(resource_root):
        raise RuntimeError('resource executable escaped its attested tree')
    argv = spec.get('target_argv')
    if (not isinstance(argv,list) or len(argv) < 3 or argv[0] != PYTHON
            or argv[1] != '-B' or any(not isinstance(value,str) for value in argv)):
        raise RuntimeError('payload argv must directly invoke the pinned Python')
    target = Path(argv[2]).resolve()
    if not (target.is_relative_to(resource_root) or target.is_relative_to(scientific_root)):
        raise RuntimeError('numerical target escaped both attested source trees')
    if spec.get('instrumented_admin',False):
        accounting = spec.get('accounting_path')
        if (not isinstance(accounting,str) or not accounting
                or not Path(accounting).resolve().is_relative_to(Path(spec['policy_receipt_path']).resolve().parent)):
            raise RuntimeError('admin accounting escaped the owned payload directory')
    if verify_files:
        if digest(entry) != spec['resource_entry_sha256'] or digest(spec['bootstrap_path']) != bootstrap_sha:
            raise RuntimeError('resource or bootstrap source bytes changed')
        if git(resource_root,'rev-parse','HEAD') != spec['resource_source_head'] or git(resource_root,'status','--porcelain'):
            raise RuntimeError('resource source head or clean state differs')
        if git(scientific_root,'rev-parse','HEAD') != spec['scientific_source_head']:
            raise RuntimeError('scientific source head differs from its own preparation')
        for path,expected in spec['scientific_source_sha256'].items():
            if digest(path) != expected:
                raise RuntimeError('scientific source pin changed: '+path)
        for key,path_key in (('master_sha256','master_path'),('admission_sha256','admission_path')):
            if digest(spec[path_key]) != spec[key]:
                raise RuntimeError('immutable execution contract changed: '+path_key)
        if digest(spec['global_slot_path']) != slot_sha:
            raise RuntimeError('global worker-slot claim changed')
    return spec

def validate_contracts(spec,master,admission,slot, *, now=None):
    now = time.time() if now is None else now
    expiry = master.get('expires_epoch')
    if not finite_number(expiry) or expiry <= now or spec['expires_epoch'] > expiry:
        raise RuntimeError('master cannot contain the payload')
    if spec.get('master_scope_id') and master.get('scope_id') != spec['master_scope_id']:
        raise RuntimeError('master scope identity differs')
    if admission.get('lease_id',admission.get('id')) != spec['lease_id']:
        raise RuntimeError('admission identity differs')
    if not finite_number(admission.get('expires_epoch')) or spec['expires_epoch'] > admission['expires_epoch']:
        raise RuntimeError('admission cannot contain payload expiry')
    for key in ('cpu','task','unit'):
        if slot.get(key) != spec[key]:
            raise RuntimeError('global slot '+key+' differs')
    if slot.get('lease_id') != spec['lease_id']:
        raise RuntimeError('global slot lease differs')
    if slot.get('master_scope_id',slot.get('scope_id',master.get('scope_id'))) != master.get('scope_id'):
        raise RuntimeError('slot master scope differs')
    return True

def validate_receipt(spec,receipt, *, now=None, actual=None):
    now = time.time() if now is None else now
    expected = dict(schema_version=1,stage=spec['stage'],task=spec['task'],cpu=spec['cpu'],
        expected_affinity=[spec['cpu']],expected_scheduler=5,numerical_threads=1,io_class=3,
        unit=spec['unit'],controller_unit=spec['controller_unit'],
        source_head=spec['scientific_source_head'],lease_id=spec['lease_id'],
        lease_expires_epoch=spec['expires_epoch'])
    for key,value in expected.items():
        if receipt.get(key) != value:
            raise RuntimeError('dual-source payload receipt differs: '+key)
    if receipt.get('resource_source_head',receipt.get('resource_head')) != spec['resource_source_head']:
        raise RuntimeError('receipt resource head differs from bootstrap head')
    if not receipt.get('probe_id') or not receipt.get('worker_invocation_id') or not receipt.get('worker_cgroup'):
        raise RuntimeError('payload receipt lacks live policy proof')
    if spec['expires_epoch'] <= now:
        raise RuntimeError('payload expired while awaiting release')
    proof = receipt.get('actual_probe',{})
    props,process = proof.get('properties',{}),proof.get('process',{})
    if (props.get('Id') != spec['unit'] or props.get('InvocationID') != receipt['worker_invocation_id']
            or props.get('ControlGroup') != receipt['worker_cgroup'] or props.get('IOSchedulingClass') != '3'
            or process.get('affinity') != [spec['cpu']] or process.get('scheduler') != 5):
        raise RuntimeError('released payload actual policy proof differs')
    if spec.get('controller_invocation_id') and receipt.get('controller_invocation_id') != spec['controller_invocation_id']:
        raise RuntimeError('receipt parent lifetime differs')
    if actual is not None:
        for key in ('pid','start_ticks','boot_id'):
            if process.get(key) != actual.get(key):
                raise RuntimeError('released payload lifetime differs: '+key)
        if os.environ.get('INVOCATION_ID') != receipt['worker_invocation_id']:
            raise RuntimeError('actual payload InvocationID differs')
        groups={line.split(':',2)[2] for line in Path('/proc/self/cgroup').read_text().splitlines()}
        if receipt['worker_cgroup'] not in groups:
            raise RuntimeError('actual payload cgroup differs')
    return True

def immutable(path,value):
    path = Path(path)
    path.parent.mkdir(parents=True,exist_ok=True)
    temporary = path.with_name('.'+path.name+'.'+uuid.uuid4().hex+'.tmp')
    try:
        with temporary.open('x') as stream:
            stream.write(json.dumps(value,indent=2,sort_keys=True,allow_nan=False)+'\n')
            stream.flush();os.fsync(stream.fileno())
        os.link(temporary,path)
    finally:
        if temporary.exists():temporary.unlink()
    fd = os.open(str(path.parent),os.O_RDONLY)
    try:os.fsync(fd)
    finally:os.close(fd)
    return value

def run_instrumented_admin(spec,spec_path):
    """Execute a fresh namespace; retain whole-process exit CPU without patching."""
    folder = Path(spec['accounting_path'])
    identity = dict(schema_version=1,stage='R152_ADMIN_ACCOUNTING',task=spec['task'],
        unit=spec['unit'],lease_id=spec['lease_id'],invocation_id=os.environ.get('INVOCATION_ID'),
        process=process_snapshot(),resource_source_head=spec['resource_source_head'],
        scientific_source_head=spec['scientific_source_head'],target_argv=spec['target_argv'],
        target_sha256=digest(spec['target_argv'][2]),bootstrap_spec_sha256=digest(spec_path))
    started = dict(identity,started_epoch=time.time())
    immutable(folder/'started.json',started)
    old_argv = sys.argv[:]
    completed = False
    error = None
    try:
        sys.argv = list(spec['target_argv'][2:])
        runpy.run_path(sys.argv[0],run_name='__main__')
        completed = True
    except SystemExit as exc:
        completed = exc.code is None or exc.code == 0
        if not completed:error=repr(exc)
        raise
    except BaseException as exc:
        error=repr(exc)
        raise
    finally:
        sys.argv = old_argv
        own = time.process_time()
        child = os.times().children_user + os.times().children_system
        observed = dict(started,finished_epoch=time.time(),completed=completed,error=error,
            observed_process_CPU_seconds=own,observed_terminated_children_CPU_seconds=child,
            observed_total_CPU_seconds=own+child,post_observation_exit_allowance_CPU_seconds=5.,
            hard_CPU_quota=False,exact_exit_CPU_measurement=False,
            accounting_scope='Full process lifetime plus terminated children; no cgroup double charge')
        immutable(folder/'observed.json',observed)
        immutable(folder/'observed.seal.json',dict(sha256=digest(folder/'observed.json'),
            resource_source_head=spec['resource_source_head'],unit=spec['unit'],
            invocation_id=identity['invocation_id']))

def bootstrap(spec_path):
    spec = read(spec_path)
    actual = first_exec_policy(spec.get('cpu'))
    validate_spec(spec)
    validate_contracts(spec,read(spec['master_path']),read(spec['admission_path']),read(spec['global_slot_path']))
    deadline = min(time.monotonic()+20,time.monotonic()+spec['expires_epoch']-time.time())
    receipt_path = Path(spec['policy_receipt_path'])
    while not receipt_path.is_file() and time.monotonic() < deadline:
        time.sleep(.025)
    if not receipt_path.is_file():
        raise RuntimeError('payload attestation was not released within its bounded startup')
    receipt = read(receipt_path)
    first_exec_policy(spec['cpu'])
    validate_receipt(spec,receipt,actual=actual)
    # Hash/clock checks are repeated after waiting, not inferred from startup.
    validate_spec(spec)
    validate_contracts(spec,read(spec['master_path']),read(spec['admission_path']),read(spec['global_slot_path']))
    if spec.get('instrumented_admin',False):
        return run_instrumented_admin(spec,spec_path)
    os.execv(spec['target_argv'][0],spec['target_argv'])

def probe_payload(output,seconds,unit=None):
    """Disposable source-bound policy observation; no numerical dependencies."""
    if not os.environ.get('INVOCATION_ID'):
        raise RuntimeError('disposable payload requires an owned systemd lifetime')
    if not 0 <= seconds <= 60:
        raise ValueError('bounded disposable lifetime required')
    if unit:
        invocation=subprocess.check_output(['systemctl','--user','show',unit,
            '--property=InvocationID','--value'],text=True,timeout=5).strip()
        if invocation != os.environ['INVOCATION_ID']:
            raise RuntimeError('disposable probe does not own the named unit')
    value = dict(status='R152_DISPOSABLE_PAYLOAD_POLICY_OBSERVED',epoch=time.time(),
        process=process_snapshot(),thread_environment={key:os.environ.get(key) for key in THREAD_VARS},
        invocation_id=os.environ['INVOCATION_ID'],numerical_work=False)
    immutable(output,value)
    time.sleep(seconds)
    return value

def legacy_guard_probe(output,cpu,receipt,task,seconds=1,numerical_libraries=False,fault_threads=False):
    """Exercise the immutable EE policy guard without forecasting or fitting."""
    path=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r150_bounded_admission_20261023/application/scripts/pricefm/500_run_pricefm_stage_r150_bounded_admission.py')
    spec=importlib.util.spec_from_file_location('r152_disposable_immutable_guard',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    proof=module.guard(cpu,Path(receipt),task)
    if not numerical_libraries and any(name in sys.modules for name in ('numpy','pandas','scipy')):
        raise RuntimeError('policy-only probe unexpectedly imported numerical dependencies')
    pools=None
    if numerical_libraries:
        kernel=module.producer().kernel()
        # Force lazy BLAS initialization without a model, forecast or fit.
        import numpy as np
        import scipy.linalg
        # Import exactly the worker's frozen core/runtime dependencies without
        # loading a feature bank, parent moments or producing predictions.
        module.producer().original().load_numerical(module.read_preparation())
        if not np.array_equal(np.eye(2)@np.eye(2),np.eye(2)):
            raise RuntimeError('disposable numerical-library initialization failed')
        pools=kernel.numerical_threadpools()
        if not pools or any(row['num_threads']!=1 for row in pools):
            raise RuntimeError('actual numerical-library thread policy differs')
        module.guard(cpu,Path(receipt),task)
    stop=None;thread=None
    if fault_threads:
        import threading
        stop=threading.Event();thread=threading.Thread(target=lambda:stop.wait(60),daemon=True);thread.start()
    try:value=probe_payload(output,seconds)
    finally:
        if stop is not None:stop.set();thread.join(timeout=2)
    return dict(value,status='R152_IMMUTABLE_EE_GUARD_COMPATIBILITY_PASSED',
        scientific_source_head=proof['source_head'],guard_sha256=digest(path),
        actual_numerical_library_policy=pools,scientific_predictions=0,model_fits=0)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command',required=True)
    item = sub.add_parser('bootstrap')
    item.add_argument('--spec',required=True)
    item = sub.add_parser('probe-payload')
    item.add_argument('--output',required=True)
    item.add_argument('--seconds',type=float,default=2)
    item.add_argument('--unit')
    item=sub.add_parser('legacy-guard-probe')
    item.add_argument('--output',required=True)
    item.add_argument('--cpu',type=int,required=True)
    item.add_argument('--policy-receipt',required=True)
    item.add_argument('--task',required=True)
    item.add_argument('--seconds',type=float,default=1)
    item.add_argument('--numerical-libraries',action='store_true')
    item.add_argument('--fault-threads',action='store_true')
    args = parser.parse_args()
    if args.command == 'bootstrap':
        bootstrap(args.spec)
    elif args.command=='probe-payload':
        print(json.dumps(probe_payload(args.output,args.seconds,args.unit),sort_keys=True))
    else:
        print(json.dumps(legacy_guard_probe(args.output,args.cpu,args.policy_receipt,args.task,args.seconds,
            args.numerical_libraries,args.fault_threads),sort_keys=True))

if __name__ == '__main__':
    main()
