#!/usr/bin/env python3
"""Prepared NO3/AT fixed-state diagnostics; no admission or fit is implicit.

Imports unchanged V4 permit/peer/math utilities from this isolated expansion
checkout. Every prior frozen V4 file/receipt remains an immutable source pin.
"""
import argparse
import ctypes
import datetime
import fcntl
import importlib.util
import json
import math
import os
from pathlib import Path
import resource
import signal
import subprocess
import time

ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('r522_control',HERE/'522_fixed_state_control.py')
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base);ref=base.ref
NO3='iq_NO_3_r134_283a8c333135aae3_t2.291521491921e-03_s1_al0.75'
AT='iq_AT_r134_7a422c0c3473f81f_t1.632090846764e-03_s1_al0.50'
CAPS={NO3:400,AT:800}
AUDIT=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021/r154_parallel_repair_20261026/certificates/expansion')
PRIOR_CHARGED=995.588691
PREPARATION_CHARGE=400


def load_manifest(path):
    manifest=json.loads(Path(path).read_text())
    if manifest['schema']!='r154_two_target_fixed_state_expansion_v1':raise ValueError('wrong schema')
    ref.verify_files([manifest['source_manifest']])
    original=json.loads(Path(manifest['source_manifest']['path']).read_text())
    ref.validate_scope(manifest['scope'])
    if manifest['scope']!=original['scope'] or manifest['targets']!=original['targets']:
        raise ValueError('the original seven-target set or scientific contract changed')
    if set(manifest['execution'])!=set(CAPS):raise ValueError('not the exact two diagnostic targets')
    if manifest['budget']!={'master_CPU_seconds':2700,'prior_charged_CPU_seconds':PRIOR_CHARGED,
        'new_source_reserved_CPU_seconds':300,'new_synthetic_reserved_CPU_seconds':100,
        'target_CPU_ceilings':CAPS,'unallocated_CPU_seconds':104.411309}:
        raise ValueError('remaining-budget contract changed')
    return manifest


def authority(manifest_path,grant_path,digest,target):
    if target not in CAPS:raise ValueError('target is outside the exact two-target expansion')
    ref.verify_files([dict(path=grant_path,sha256=digest)])
    grant=json.loads(Path(grant_path).read_text());manifest=load_manifest(manifest_path)
    if grant['status']!='ROOT_ADMITTED_FIXED_STATE_EXPANSION_ONLY':raise ValueError('not admitted')
    if grant['manifest_sha256']!=ref.sha256(manifest_path) or grant['target']!=target:raise ValueError('manifest/target mismatch')
    if grant['authorizes_fixed_state_reconstruction'] is not True or \
       grant['authorizes_posterior_fits'] is not False or grant['authorizes_production_acceptance'] is not False:
        raise ValueError('unsupported authority')
    if datetime.datetime.now(datetime.timezone.utc)>=datetime.datetime.fromisoformat(grant['expires_UTC']):
        raise ValueError('expired root grant')
    if grant['host'].split('.')[0]!='muscat' or os.uname().nodename.split('.')[0]!='muscat':raise ValueError('Muscat-only execution')
    if not 0<grant['maximum_CPU_seconds']<=CAPS[target] or not 0<grant['maximum_wall_seconds']<=7200:
        raise ValueError('per-target budget exceeded')
    if grant['maximum_total_diagnostic_CPU_seconds']!=2700 or grant['prior_charged_CPU_seconds']!=PRIOR_CHARGED or \
       grant['reserved_source_preparation_CPU_seconds']!=300 or grant['reserved_fixed_reference_CPU_seconds']!=100:
        raise ValueError('prior ledger or preparation charge differs')
    if grant['cores']!=1 or grant['affinity']!=[30] or 30 not in base.online_cpus() or \
       not 0<grant['memory_GiB']<=8 or not 0<grant['disk_GiB']<=2:raise ValueError('resource contract differs')
    base.global_permit(grant)
    ref.verify_files(manifest['prior_LT_receipts'])
    lt=json.loads(Path(manifest['prior_LT_receipts'][0]['path']).read_text())
    if lt['reserved_2700_envelope_usage_CPU_seconds']!=PRIOR_CHARGED or lt['returncode']!=0:
        raise ValueError('prior LT CPU ledger or exit changed')
    required=[HERE/'523_fixed_state_control.py',HERE/'523_fixed_state_diagnosis.R',
              HERE/'522_fixed_state_control.py',HERE/'522_certificate_reference.py',
              ROOT/'application/R/522_certificate_reference.R']
    if not {str(p) for p in required}<={x['path'] for x in grant['source_bindings']}:
        raise ValueError('incomplete expansion/helper source binding')
    ref.verify_files(grant['source_bindings'])
    python=json.loads(Path(manifest['source_manifest']['path']).read_text())['actual_python_runtime']
    ref.verify_files([dict(path=python['executable'],sha256=python['executable_sha256']),
        dict(path=python['numpy_file'],sha256=python['numpy_file_sha256']),
        dict(path=python['scipy_file'],sha256=python['scipy_file_sha256'])])
    ref.verify_files([dict(path=p,sha256=h) for p,h in python['loaded_shared_object_sha256'].items()])
    if os.path.realpath('/proc/self/exe')!=python['executable']:raise ValueError('actual Python changed')
    ref.verify_files([grant['actual_R_runtime_binding']])
    runtime=json.loads(Path(grant['actual_R_runtime_binding']['path']).read_text())
    if runtime['host'].split('.')[0]!='muscat':raise ValueError('execution runtime is not Muscat')
    ref.verify_files([dict(path=runtime['actual_executable'],sha256=runtime['actual_executable_sha256']),
        dict(path=runtime['Rscript'],sha256=runtime['Rscript_sha256'])])
    ref.verify_files([dict(path=str(Path(runtime['package_path'])/name),sha256=h)
        for name,h in runtime['package_files_sha256'].items()])
    ref.verify_files([dict(path=name,sha256=h) for name,h in runtime['loaded_shared_object_sha256'].items()])
    return manifest,grant


def verify_execution_target(manifest,target):
    t=next(x for x in manifest['targets'] if x['name']==target);execution=manifest['execution'][target]
    if execution['source_host']!=t['host'] or execution['execution_host']!='muscat':raise ValueError('host provenance changed')
    aliases=execution['aliases']
    if target==NO3:
        ref.verify_files([execution['alias_manifest']])
        alias=json.loads(Path(execution['alias_manifest']['path']).read_text())
        if alias['target']!=target or alias['aliases']!=aliases or alias['source_host']!='jerez' or alias['execution_host']!='muscat':
            raise ValueError('alias provenance mismatch')
    elif aliases:raise ValueError('AT must use its original Muscat bytes')
    resolve=lambda p:aliases.get(p,p)
    for item in t['bindings']:
        path=Path(resolve(item['path']))
        if path.is_symlink():raise ValueError('symlink target binding')
        ref.verify_files([dict(path=str(path),sha256=item['sha256'])])
    actual=json.loads(Path(resolve(t['bindings'][0]['path'])).read_text())
    if actual!=t['contract']:raise ValueError('original contract changed in alias')
    design=Path(resolve(actual['design_dir']));terminal=json.loads((design/'terminal.json').read_text())
    if terminal['status']!='completed_r137_quantile_design' or terminal['test_opened'] is not False:
        raise ValueError('design seal differs')
    ref.verify_files([dict(path=str(design/name),sha256=h) for name,h in terminal['files'].items()])
    d=json.loads((design/'design.json').read_text())
    if d['n']!=t['n'] or d['p']!=t['p'] or d['feature_names'][0]!='intercept':raise ValueError('design identity differs')
    for name,size in [('X.bin',t['n']*t['p']*8),('y.bin',t['n']*8)]:
        if (design/name).stat().st_size!=size:raise ValueError('design byte dimensions differ')
    fit=Path(resolve(actual['output_dir']))
    if json.loads((fit/'terminal.json').read_text())!=t['stored_terminal']:raise ValueError('failed terminal changed')
    return t


def ledger(manifest):
    spent=PRIOR_CHARGED+PREPARATION_CHARGE;completed=[]
    for target,execution in manifest['execution'].items():
        result=AUDIT/execution['output_name'];claim=AUDIT/'target_consumption'/(ref.canonical_hash(target)+'.json')
        receipt=result/'resource_receipt.json'
        if claim.exists() and not receipt.is_file():raise ValueError('claimed target lacks reaped-child receipt; root drain/review required')
        if receipt.exists():
            r=json.loads(receipt.read_text())
            if r['target']!=target or r['scope']!='r154_two_target_fixed_state_expansion_v1':raise ValueError('foreign receipt')
            if not math.isfinite(r['child_CPU_seconds']) or not 0<=r['child_CPU_seconds']<=CAPS[target]+2:
                raise ValueError('invalid or over-ceiling receipt cost')
            spent+=r['child_CPU_seconds'];completed.append(dict(path=str(receipt),sha256=ref.sha256(receipt)))
    return spent,completed


def run_owned(args,manifest,grant,lock_fd):
    target=args.target;execution=manifest['execution'][target];output=AUDIT/execution['output_name']
    if output.exists():raise ValueError('fixed output already exists; no automatic retry')
    before=resource.getrusage(resource.RUSAGE_CHILDREN);started=time.monotonic()
    spent,completed=ledger(manifest)
    if grant['prior_completed_receipts']!=completed:raise ValueError('root grant does not bind current completed-target receipts')
    if spent+grant['maximum_CPU_seconds']>2700:raise ValueError('insufficient remaining master budget')
    observation=base.fresh_peer_guard(grant)
    verify_execution_target(manifest,target)
    consumption=AUDIT/'target_consumption';consumption.mkdir(exist_ok=True)
    ref.immutable_json(consumption/(ref.canonical_hash(target)+'.json'),dict(target=target,
        root_grant_sha256=args.root_grant_sha256,manifest_sha256=ref.sha256(args.manifest),
        scope='r154_two_target_fixed_state_expansion_v1',prior_receipts=completed))
    output.mkdir()
    ref.immutable_json(output/'admission.json',dict(target=target,grant_sha256=args.root_grant_sha256,
        prior_charged_CPU_seconds=spent,completed_receipts=completed,environment=ref.environment_binding()))
    ref.immutable_json(output/'fresh_peer_guard.json',observation)
    env=dict(os.environ,TZ='UTC',R154_FIXED_STATE_ROOT_ADMITTED='1',R154_FIXED_STATE_GRANT=str(Path(args.root_grant).resolve()),
        R154_FIXED_STATE_GRANT_SHA256=args.root_grant_sha256,R154_GLOBAL_PERMIT_LOCK_FD=str(lock_fd))
    for key in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS','BLIS_NUM_THREADS','VECLIB_MAXIMUM_THREADS','NUMEXPR_NUM_THREADS'):env[key]='1'
    parent=os.getpid()
    def limits():
        libc=ctypes.CDLL(None,use_errno=True)
        if libc.prctl(1,signal.SIGKILL,0,0,0)!=0 or os.getppid()!=parent:os._exit(125)
        os.sched_setaffinity(0,[30]);os.sched_setscheduler(0,os.SCHED_OTHER,os.sched_param(0));os.setpriority(os.PRIO_PROCESS,0,10)
        resource.setrlimit(resource.RLIMIT_CPU,(int(grant['maximum_CPU_seconds']),)*2)
        resource.setrlimit(resource.RLIMIT_AS,(int(grant['memory_GiB']*1024**3),)*2)
        resource.setrlimit(resource.RLIMIT_FSIZE,(16*1024**2,)*2)
    status='FAILED';returncode=None
    try:
        with open(output/'stdout.log','x') as stdout,open(output/'stderr.log','x') as stderr:
            global_contract=base.global_permit(grant)
            remaining_wall=min(grant['maximum_wall_seconds'],
                datetime.datetime.fromisoformat(grant['expires_UTC']).timestamp()-time.time(),
                global_contract['expires_epoch']-time.time())
            if remaining_wall<=0:raise ValueError('original resource/grant clock expired before launch')
            result=subprocess.run([manifest['Rscript'],str(HERE/'523_fixed_state_diagnosis.R'),str(ROOT),
                str(Path(args.manifest).resolve()),target,str(output/'fixed_state_diagnosis.json')],env=env,
                stdout=stdout,stderr=stderr,preexec_fn=limits,pass_fds=(lock_fd,),timeout=remaining_wall,check=False)
        returncode=result.returncode;status='DIAGNOSTIC_RETURNED' if returncode==0 else 'FAILED'
    except subprocess.TimeoutExpired:status='WALL_LIMIT_REACHED'
    finally:
        after=resource.getrusage(resource.RUSAGE_CHILDREN);cpu=after.ru_utime+after.ru_stime-before.ru_utime-before.ru_stime
        ref.immutable_json(output/'resource_receipt.json',dict(scope='r154_two_target_fixed_state_expansion_v1',
            status=status,returncode=returncode,target=target,child_CPU_seconds=cpu,parent_CPU_seconds=time.process_time(),
            parent_plus_reaped_child_CPU_seconds=time.process_time()+after.ru_utime+after.ru_stime,
            wall_seconds=time.monotonic()-started,max_child_RSS_KiB=after.ru_maxrss,
            prior_charged_including_preparation_CPU_seconds=spent,total_charged_master_CPU_seconds=spent+cpu,
            unspent_but_unadmitted_CPU_seconds=2700-spent-cpu,root_grant_sha256=args.root_grant_sha256,
            permit_id='muscat_cpu30',posterior_fits=0,production_passflags_written=0))
    if returncode!=0:raise SystemExit(1)


def main():
    p=argparse.ArgumentParser();p.add_argument('--manifest',required=True);p.add_argument('--root-grant',required=True)
    p.add_argument('--root-grant-sha256',required=True);p.add_argument('--target',required=True);p.add_argument('--check-authority',action='store_true');args=p.parse_args()
    if os.sched_getaffinity(0)!={31}:raise ValueError('administrative caller must remain CPU31')
    manifest,grant=authority(args.manifest,args.root_grant,args.root_grant_sha256,args.target)
    if args.check_authority:print('PASS expansion authority only; no claim or target data read');return
    contract=base.global_permit(grant)
    with open(Path(contract['lock_dir'])/'muscat_cpu30.lock','a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        ref.verify_files([grant['global_contract']])
        os.sched_setaffinity(0,[30]);os.sched_setscheduler(0,os.SCHED_OTHER,os.sched_param(0));os.setpriority(os.PRIO_PROCESS,0,10)
        subprocess.run(['ionice','-c','3','-p',str(os.getpid())],check=True,capture_output=True)
        if not subprocess.check_output(['ionice','-p',str(os.getpid())],text=True).startswith('idle'):raise ValueError('I/O class differs')
        resource.setrlimit(resource.RLIMIT_CPU,(100,800))
        run_owned(args,manifest,grant,lock.fileno())


if __name__=='__main__':main()
