#!/usr/bin/env python3
"""Fail-closed coordinator; requires a separately sealed explicit root grant.

`--check-authority` validates authority without reading target data or running R.
There is no posterior fit or production certificate publication capability.
"""
import argparse
import ctypes
import datetime
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import resource
import signal
import shutil
import subprocess
import time

ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('r522',HERE/'522_certificate_reference.py')
ref=importlib.util.module_from_spec(spec); spec.loader.exec_module(ref)


def global_permit(grant):
    ref.verify_files([grant['global_contract']])
    contract=json.loads(Path(grant['global_contract']['path']).read_text())
    if contract['schema']!='r154_global_permits_v1' or contract['max_new_numerical']!=1:
        raise ValueError('global permit must admit exactly one serial numerical worker')
    if len(contract['permits'])!=1 or grant['permit_id']!='muscat_cpu30':
        raise ValueError('not the root-authorized Muscat CPU30 permit')
    permit=contract['permits'][0]
    if permit['id']!=grant['permit_id'] or permit['cpu']!=30 or grant['affinity']!=[30]:
        raise ValueError('permit identity/CPU mismatch')
    if permit['host'].split('.')[0]!=grant['host'].split('.')[0] or 'CERTIFICATE_REFERENCE' not in permit['science']:
        raise ValueError('permit host/science mismatch')
    if permit['sequential'] is not True or contract['new_numerical_concurrency_above_one_authorized'] is not False:
        raise ValueError('nonsequential permit')
    if contract['physical31_and_SMT63_reserved_as_headroom'] is not True or contract['SMT62_science_authorized'] is not False:
        raise ValueError('headroom/SMT reservation changed')
    expected=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021/r154_parallel_repair_20261026/resources/global_locks')
    if Path(contract['lock_dir']).resolve()!=expected:raise ValueError('global lock directory mismatch')
    expiry=datetime.datetime.fromisoformat(grant['expires_UTC']).timestamp()
    if time.time()>=contract['expires_epoch'] or expiry>contract['expires_epoch']:
        raise ValueError('grant exceeds or outlives global resource authority')
    ref.verify_files(list(contract['evidence'].values()))
    policy=json.loads(Path(contract['evidence']['resource_policy']['path']).read_text())
    if time.time()>=policy['expires_epoch'] or expiry>policy['expires_epoch']:
        raise ValueError('grant exceeds resource-policy expiry')
    return contract


def fresh_peer_guard(grant):
    """Fresh actual process/thread affinity check against the sealed peer census.

    Unknown Python/R/script numerical roles intersecting CPU30 reject admission.
    Current controller ancestors are administrative launch ownership, not peers.
    A vanished process is accepted only after a fresh /proc absence check.
    PermissionError is never converted to a disappearance or ignored omission.
    """
    contract=global_permit(grant)
    census=json.loads(Path(contract['evidence']['peer_census']['path']).read_text())
    known={p['pid']:p for p in census['allowed_intersecting_processes']}
    ancestors=set();pid=os.getpid()
    while pid>1:
        ancestors.add(pid)
        raw=Path(f'/proc/{pid}/stat').read_text();f=raw[raw.rfind(')')+2:].split();pid=int(f[1])
    observed=[];gone=[]
    for process in Path('/proc').iterdir():
        if not process.name.isdigit():continue
        pid=int(process.name)
        try:
            if process.stat().st_uid!=os.getuid() or pid in ancestors:continue
            raw=(process/'stat').read_text();f=raw[raw.rfind(')')+2:].split()
            if f[0] in ('Z','X','x'):continue
            command=(process/'cmdline').read_bytes()
            threads=list((process/'task').iterdir());intersects=False
            for thread in threads:
                try:affinity=os.sched_getaffinity(int(thread.name))
                except (FileNotFoundError,ProcessLookupError):
                    if thread.exists():raise
                    continue
                if 30 in affinity:intersects=True
            if not intersects:continue
            identity=dict(pid=pid,start_ticks=int(f[19]),state=f[0],cmdline_sha256=ref.hashlib.sha256(command).hexdigest())
            entry=known.get(pid)
            if entry is not None:
                if identity['start_ticks']!=entry['start_ticks'] or identity['cmdline_sha256']!=entry['cmdline_sha256'] or identity['state'] not in entry['allowed_states']:
                    raise ValueError('reviewed peer identity/state changed: '+str(pid))
            else:
                comm=(process/'comm').read_text().strip()
                argv=[x.decode(errors='replace') for x in command.split(b'\0') if x]
                executable=Path(os.readlink(process/'exe')).name
                numerical=(comm in ('R','Rscript') or 'python' in executable.lower() or
                    any(x.endswith(('.py','.R','.r')) for x in argv))
                if numerical:raise ValueError('unreviewed numerical peer intersects CPU30: '+str(pid))
            observed.append(identity)
        except (FileNotFoundError,ProcessLookupError):
            if process.exists():raise
            gone.append(pid)
    available=int(next(row.split()[1] for row in Path('/proc/meminfo').read_text().splitlines() if row.startswith('MemAvailable:')))*1024
    free=shutil.disk_usage(Path(grant['global_contract']['path']).parent).free
    if available<192*1024**3 or free<80*1024**3:raise ValueError('Muscat RAM/disk floor failed')
    return dict(observed_epoch=time.time(),CPU=30,reviewed_intersecting_processes=observed,
        freshly_gone_pids=gone,RAM_available_GiB=available/1024**3,disk_free_GiB=free/1024**3)


def authority(manifest_path, grant_path, expected_grant_sha, target_name):
    if ref.sha256(grant_path)!=expected_grant_sha: raise ValueError('root grant digest mismatch')
    grant=json.loads(Path(grant_path).read_text())
    manifest=json.loads(Path(manifest_path).read_text()); ref.validate_scope(manifest['scope'])
    if manifest['schema']!='r154_fixed_state_seven_target_manifest_v1' or len(manifest['targets'])!=7:
        raise ValueError('not the sealed seven-target schema')
    if grant['status']!='ROOT_ADMITTED_FIXED_STATE_DIAGNOSTIC_ONLY':raise ValueError('not admitted')
    if grant['manifest_sha256']!=ref.sha256(manifest_path):raise ValueError('manifest digest mismatch')
    if grant['authorizes_posterior_fits'] is not False or grant['authorizes_production_acceptance'] is not False:
        raise ValueError('unsupported broader authority')
    if grant['authorizes_fixed_state_reconstruction'] is not True:raise ValueError('no reconstruction authority')
    if grant['target']!=target_name or target_name!='LT_fold1_al0.90':
        raise ValueError('initial admission is LT first only')
    if datetime.datetime.now(datetime.timezone.utc)>=datetime.datetime.fromisoformat(grant['expires_UTC']):
        raise ValueError('expired root grant')
    if grant['host'].split('.')[0]!=os.uname().nodename.split('.')[0]:raise ValueError('wrong host')
    cpu=grant['maximum_CPU_seconds']; wall=grant['maximum_wall_seconds']
    if not 0<cpu<=1800 or not 0<wall<=7200 or grant['cores']!=1 or len(grant['affinity'])!=1:
        raise ValueError('resource ceiling exceeded')
    if grant.get('maximum_total_diagnostic_CPU_seconds')!=2700 or \
       grant.get('reserved_source_preparation_CPU_seconds')!=300 or \
       grant.get('reserved_fixed_reference_CPU_seconds')!=600:
        raise ValueError('diagnostic shared budget/reservations differ')
    if not 0<grant['memory_GiB']<=8 or not 0<grant['disk_GiB']<=2:raise ValueError('memory/disk ceiling exceeded')
    if not set(grant['affinity'])<=os.sched_getaffinity(0):raise ValueError('unavailable affinity')
    if not grant['source_bindings']:raise ValueError('missing source bindings')
    ref.verify_files(grant['source_bindings'])
    required={str(p) for p in [Path(__file__).resolve(),HERE/'522_certificate_reference.py',
        HERE/'522_fixed_state_diagnosis.R',ROOT/'application/R/522_certificate_reference.R']}
    if not required<={x['path'] for x in grant['source_bindings']}:raise ValueError('incomplete code binding')
    python=manifest['actual_python_runtime']
    ref.verify_files([dict(path=python['executable'],sha256=python['executable_sha256']),
        dict(path=python['numpy_file'],sha256=python['numpy_file_sha256']),
        dict(path=python['scipy_file'],sha256=python['scipy_file_sha256'])])
    ref.verify_files([dict(path=p,sha256=value) for p,value in python['loaded_shared_object_sha256'].items()])
    if os.path.realpath('/proc/self/exe')!=python['executable']:raise ValueError('actual Python changed')
    global_permit(grant)
    runtime_path=grant['actual_R_runtime_binding']['path']
    ref.verify_files([grant['actual_R_runtime_binding']])
    runtime=json.loads(Path(runtime_path).read_text())
    if runtime['host'].split('.')[0]!=grant['host'].split('.')[0]:raise ValueError('wrong runtime host')
    # Recheck executable + all recorded installed package bytes immediately.
    ref.verify_files([dict(path=runtime['actual_executable'],sha256=runtime['actual_executable_sha256']),
                      dict(path=runtime['Rscript'],sha256=runtime['Rscript_sha256'])])
    ref.verify_files([dict(path=str(Path(runtime['package_path'])/name),sha256=value)
                      for name,value in runtime['package_files_sha256'].items()])
    ref.verify_files([dict(path=name,sha256=value)
                      for name,value in runtime['loaded_shared_object_sha256'].items()])
    return manifest,grant


def run_under_lock(args,manifest,grant,lock_fd):
    if not args.output_dir:raise ValueError('new output directory required')
    output=Path(args.output_dir).resolve()
    allowed=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021/r154_parallel_repair_20261026/certificates').resolve()
    if allowed not in output.parents or output.exists():raise ValueError('output must be new and in certificate audit lane')
    # Every root grant is one-shot, including a failed invocation. A second
    # attempt needs a newly reviewed grant and remaining shared-budget ledger.
    consumption=allowed/'grant_consumption';consumption.mkdir(exist_ok=True)
    ref.immutable_json(consumption/(args.root_grant_sha256+'.json'),
        dict(root_grant_sha256=args.root_grant_sha256,target=args.target,output=str(output),
             consumed_UTC=datetime.datetime.now(datetime.timezone.utc).isoformat()))
    output.mkdir()
    before=resource.getrusage(resource.RUSAGE_CHILDREN); started=time.monotonic()
    status='FAILED';returncode=None
    try:
        status,returncode=execute_target(args,manifest,grant,lock_fd,output)
    finally:
        after=resource.getrusage(resource.RUSAGE_CHILDREN)
        cpu=(after.ru_utime+after.ru_stime)-(before.ru_utime+before.ru_stime)
        parent_cpu=time.process_time()
        ref.immutable_json(output/'resource_receipt.json',dict(status=status,returncode=returncode,
            target=args.target,child_CPU_seconds=cpu,wall_seconds=time.monotonic()-started,
            parent_CPU_seconds_including_startup=parent_cpu,
            administrative_child_CPU_seconds_before_R=before.ru_utime+before.ru_stime,
            parent_plus_reaped_child_CPU_seconds=parent_cpu+after.ru_utime+after.ru_stime,
            reserved_prior_source_and_fixed_reference_CPU_seconds=900,
            reserved_2700_envelope_usage_CPU_seconds=900+cpu,
            max_child_RSS_KiB=after.ru_maxrss,root_grant_sha256=args.root_grant_sha256,
            global_contract=grant['global_contract'],permit_id=grant['permit_id'],
            posterior_fits=0,production_passflags_written=0))
    if returncode!=0:raise SystemExit(1)


def execute_target(args,manifest,grant,lock_fd,output):
    target=ref.verify_target(manifest,args.target)
    ref.immutable_json(output/'admission.json',dict(root_grant_sha256=args.root_grant_sha256,
        manifest_sha256=ref.sha256(args.manifest),target=args.target,environment=ref.environment_binding()))
    ref.immutable_json(output/'fresh_peer_guard.json',fresh_peer_guard(grant))
    env=dict(os.environ,TZ='UTC',R154_FIXED_STATE_ROOT_ADMITTED='1',
             R154_FIXED_STATE_GRANT=str(Path(args.root_grant).resolve()),
             R154_FIXED_STATE_GRANT_SHA256=args.root_grant_sha256,
             R154_GLOBAL_PERMIT_LOCK_FD=str(lock_fd))
    for key in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS','BLIS_NUM_THREADS',
                'VECLIB_MAXIMUM_THREADS','NUMEXPR_NUM_THREADS'):env[key]='1'
    def limits():
        # This is a newly created disposable R child, never a baseline worker.
        libc=ctypes.CDLL(None,use_errno=True)
        if libc.prctl(1,signal.SIGKILL,0,0,0)!=0:os._exit(126)  # PR_SET_PDEATHSIG
        if os.getppid()!=expected_parent_pid:os._exit(125)
        os.sched_setaffinity(0,grant['affinity'])
        os.sched_setscheduler(0,os.SCHED_OTHER,os.sched_param(0))
        os.setpriority(os.PRIO_PROCESS,0,10)
        resource.setrlimit(resource.RLIMIT_CPU,(int(grant['maximum_CPU_seconds']),)*2)
        resource.setrlimit(resource.RLIMIT_AS,(int(grant['memory_GiB']*1024**3),)*2)
        # Output is scalar JSON only. No large state export is admitted.
        resource.setrlimit(resource.RLIMIT_FSIZE,(min(int(grant['disk_GiB']*1024**3),16*1024**2),)*2)
    command=[manifest['runtime']['Rscript'],str(HERE/'522_fixed_state_diagnosis.R'),str(ROOT),
             str(Path(args.manifest).resolve()),args.target,str(output/'fixed_state_diagnosis.json')]
    expected_parent_pid=os.getpid()
    status='FAILED';returncode=None
    try:
        with open(output/'stdout.log','x') as stdout,open(output/'stderr.log','x') as stderr:
            run=subprocess.run(command,env=env,stdout=stdout,stderr=stderr,
                preexec_fn=limits,pass_fds=(lock_fd,),timeout=grant['maximum_wall_seconds'],check=False)
        returncode=run.returncode;status='DIAGNOSTIC_RETURNED' if returncode==0 else 'FAILED'
    except subprocess.TimeoutExpired:
        status='WALL_LIMIT_REACHED'
    return status,returncode


def main():
    p=argparse.ArgumentParser();p.add_argument('--manifest',required=True)
    p.add_argument('--root-grant',required=True);p.add_argument('--root-grant-sha256',required=True)
    p.add_argument('--target',default='LT_fold1_al0.90');p.add_argument('--output-dir')
    p.add_argument('--check-authority',action='store_true');args=p.parse_args()
    # Even read-only source/runtime hashing by this controller uses the admitted
    # administrative CPU and priority. This changes only this new process.
    os.sched_setaffinity(0,[30])
    os.sched_setscheduler(0,os.SCHED_OTHER,os.sched_param(0))
    os.setpriority(os.PRIO_PROCESS,0,10)
    subprocess.run(['ionice','-c','3','-p',str(os.getpid())],check=True,capture_output=True)
    if not subprocess.check_output(['ionice','-p',str(os.getpid())],text=True).startswith('idle'):
        raise ValueError('actual I/O class differs from resource policy')
    manifest,grant=authority(args.manifest,args.root_grant,args.root_grant_sha256,args.target)
    if args.check_authority:
        print('PASS authority only; target inputs not opened and numerical diagnosis not run');return
    contract=global_permit(grant)
    lock_path=Path(contract['lock_dir'])/(grant['permit_id']+'.lock')
    # Same flock inode and permit_id as EE/LV. Fail busy before consuming grant.
    # The child inherits the fd, so controller exit cannot free a running R job's
    # permit; the lock survives until that child closes/exits as well.
    with open(lock_path,'a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        ref.verify_files([grant['global_contract']])
        os.sched_setaffinity(0,[30])
        os.sched_setscheduler(0,os.SCHED_OTHER,os.sched_param(0))
        os.setpriority(os.PRIO_PROCESS,0,10)
        # Administrative work is charged to the reserved source300 bucket. The
        # child may raise its soft limit within the inherited 1800 hard ceiling.
        resource.setrlimit(resource.RLIMIT_CPU,(300,1800))
        run_under_lock(args,manifest,grant,lock.fileno())


if __name__=='__main__':main()
