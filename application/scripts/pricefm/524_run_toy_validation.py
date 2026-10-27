#!/usr/bin/env python3
"""Root-admitted synthetic validation only; no production fit capability."""
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
import subprocess
import time

ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('permit_base',HERE/'522_fixed_state_control.py')
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base);ref=base.ref
AUDIT=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021/r154_parallel_repair_20261026/certificates/fullstate_consumer')
BEFORE=1605.504408;SOURCE=100;MAX_CPU=300


def physical_siblings():
    text=Path('/sys/devices/system/cpu/cpu30/topology/thread_siblings_list').read_text().strip()
    pair=set()
    for part in text.split(','):
        ends=part.split('-')
        pair.update(range(int(ends[0]),int(ends[-1])+1))
    if pair!={30,62}:raise ValueError('physical CPU30 topology differs from reviewed pair')
    return pair


def physical_peer_guard(grant, _proc_root=Path('/proc')):
    # Frozen 522 covers CPU30; the staged consumer additionally examines its
    # actual SMT sibling. No permission to run science on CPU62 is introduced.
    observation=base.fresh_peer_guard(grant);pair=physical_siblings()
    contract=base.global_permit(grant)
    census=json.loads(Path(contract['evidence']['peer_census']['path']).read_text())
    known={x['pid']:x for x in census['allowed_intersecting_processes']}
    boot=Path('/proc/sys/kernel/random/boot_id').read_text().strip();rows=[];gone=[]
    for proc in _proc_root.iterdir():
        if not proc.name.isdigit():continue
        pid=int(proc.name)
        try:
            if proc.stat().st_uid!=os.getuid() or pid==os.getpid():continue
            raw=(proc/'stat').read_text();fields=raw[raw.rfind(')')+2:].split()
            if fields[0] in ('Z','X','x'):continue
            intersects=False
            for thread in (proc/'task').iterdir():
                try:
                    affinity=os.sched_getaffinity(int(thread.name))
                    intersects=intersects or bool(affinity&pair)
                except (FileNotFoundError,ProcessLookupError):
                    if thread.exists():raise
            if not intersects:continue
            command=(proc/'cmdline').read_bytes();digest=ref.hashlib.sha256(command).hexdigest()
            entry=known.get(pid)
            if entry is not None:
                if entry['boot_id']!=boot or entry['start_ticks']!=int(fields[19]) or entry['cmdline_sha256']!=digest or fields[0] not in entry['allowed_states']:
                    raise ValueError('reviewed physical-pair peer changed: '+str(pid))
            else:
                executable=Path(os.readlink(proc/'exe')).name
                comm=(proc/'comm').read_text().strip()
                argv=[x.decode(errors='replace') for x in command.split(b'\0') if x]
                if comm in ('R','Rscript') or 'python' in executable.lower() or any(x.endswith(('.py','.R','.r')) for x in argv):
                    raise ValueError('unknown numerical peer intersects CPU30/SMT62: '+str(pid))
            rows.append(dict(pid=pid,start_ticks=int(fields[19]),state=fields[0],cmdline_sha256=digest))
        except (FileNotFoundError,ProcessLookupError):
            if proc.exists():raise
            gone.append(pid)
    observation['physical_pair']=sorted(pair);observation['physical_pair_peers']=rows
    observation['freshly_gone_physical_pair_peers']=gone
    observation['own_science_affinity']=[30];observation['SMT62_science_authorized']=False
    return observation


def authority(config_path,grant_path,grant_sha):
    if os.path.realpath('/proc/self/exe')!=os.path.realpath(ref.PINNED_PYTHON):raise ValueError('pinned Python required')
    ref.verify_files([dict(path=grant_path,sha256=grant_sha)])
    grant=json.loads(Path(grant_path).read_text());cfg=json.loads(Path(config_path).read_text())
    if grant['status']!='ROOT_ADMITTED_TOY_FULLSTATE_VALIDATION_ONLY':raise ValueError('not root admitted')
    if cfg['schema']!='r154_toy_fullstate_validation_v1' or grant['config_sha256']!=ref.sha256(config_path):raise ValueError('wrong config')
    if grant['global_contract']!=cfg['global_contract'] or grant['actual_R_runtime_binding']!=cfg['actual_R_runtime_binding']:
        raise ValueError('global V2 or execution runtime pin differs')
    if grant['expected_stock_body_sha256']!=cfg['expected_stock_body_sha256']:raise ValueError('stock source body differs')
    if grant['authorizes_toy_optimizer'] is not True or grant['authorizes_production_fits'] is not False or grant['authorizes_production_acceptance'] is not False:raise ValueError('unsupported authority')
    if not 0<grant['maximum_CPU_seconds']<=MAX_CPU or grant['prior_charged_CPU_seconds']!=BEFORE or grant['new_source_charge_CPU_seconds']!=SOURCE:
        raise ValueError('original master ledger differs')
    if (grant['maximum_cases'],grant['maximum_optimizer_invocations'],grant['maximum_n'],grant['maximum_p'],grant['maximum_total_optimizer_iterations'])!=(8,8,128,32,30):raise ValueError('toy bounds differ')
    if grant['host']!='muscat' or os.uname().nodename.split('.')[0]!='muscat' or grant['affinity']!=[30] or grant['cores']!=1:raise ValueError('host/permit differs')
    if grant['memory_GiB']!=8 or not 0<grant['maximum_wall_seconds']<=7200:raise ValueError('resource bounds differ')
    if datetime.datetime.now(datetime.timezone.utc)>=datetime.datetime.fromisoformat(grant['expires_UTC']):raise ValueError('expired grant')
    ref.verify_files([cfg['earliest_LT_grant']])
    earliest=json.loads(Path(cfg['earliest_LT_grant']['path']).read_text())
    pool=json.loads(Path(grant['global_contract']['path']).read_text())
    deadline=min(datetime.datetime.fromisoformat(earliest['expires_UTC']).timestamp(),pool['expires_epoch'])
    if cfg['stage_deadline_epoch']!=deadline or grant['stage_deadline_epoch']!=deadline or \
       datetime.datetime.fromisoformat(grant['expires_UTC']).timestamp()>deadline or time.time()>=deadline:
        raise ValueError('earliest diagnostic-stage deadline changed or expired')
    base.global_permit(grant)
    ref.verify_files(cfg['prior_receipts'])
    receipt=json.loads(Path(cfg['prior_receipts'][0]['path']).read_text())
    if receipt['total_charged_master_CPU_seconds']!=BEFORE or receipt['returncode']!=0:raise ValueError('prior diagnostic charge differs')
    required={str(ROOT/'application/R/524_toy_fullstate_consumer.R'),str(ROOT/'application/tests/524_fullstate_toy_validation.R'),str(Path(__file__).resolve()),str(HERE/'522_fixed_state_control.py'),str(HERE/'522_certificate_reference.py')}
    if not required<={x['path'] for x in grant['source_bindings']}:raise ValueError('missing source pins')
    ref.verify_files(grant['source_bindings']);ref.verify_files([grant['actual_R_runtime_binding']])
    runtime=json.loads(Path(grant['actual_R_runtime_binding']['path']).read_text())
    ref.verify_files([dict(path=runtime['actual_executable'],sha256=runtime['actual_executable_sha256']),dict(path=runtime['Rscript'],sha256=runtime['Rscript_sha256'])])
    ref.verify_files([dict(path=str(Path(runtime['package_path'])/k),sha256=v) for k,v in runtime['package_files_sha256'].items()])
    ref.verify_files([dict(path=k,sha256=v) for k,v in runtime['loaded_shared_object_sha256'].items()])
    if BEFORE+SOURCE+grant['maximum_CPU_seconds']>2700:raise ValueError('master ceiling exceeded')
    return cfg,grant


def run_locked(args,cfg,grant,lock_fd):
    output=AUDIT/'TOY_VALIDATION_01'
    if output.exists():raise ValueError('no automatic retry')
    peer=physical_peer_guard(grant)
    ref.immutable_json(AUDIT/'toy_claim.json',dict(scope=cfg['schema'],root_grant_sha256=args.root_grant_sha256,source_charge=SOURCE,prior_charge=BEFORE))
    output.mkdir();ref.immutable_json(output/'fresh_peer_guard.json',peer)
    env=dict(os.environ,TZ='UTC',R154_TOY_ROOT_ADMITTED='1',R154_GLOBAL_PERMIT_LOCK_FD=str(lock_fd))
    for k in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS','BLIS_NUM_THREADS','VECLIB_MAXIMUM_THREADS','NUMEXPR_NUM_THREADS'):env[k]='1'
    expected_parent=os.getpid()
    def child_limits():
        libc=ctypes.CDLL(None,use_errno=True)
        if libc.prctl(1,signal.SIGKILL,0,0,0)!=0 or os.getppid()!=expected_parent:os._exit(125)
        os.sched_setaffinity(0,[30]);os.sched_setscheduler(0,os.SCHED_OTHER,os.sched_param(0));os.setpriority(os.PRIO_PROCESS,0,10)
        resource.setrlimit(resource.RLIMIT_CPU,(int(grant['maximum_CPU_seconds']),)*2)
        resource.setrlimit(resource.RLIMIT_AS,(8*1024**3,)*2);resource.setrlimit(resource.RLIMIT_FSIZE,(16*1024**2,)*2)
    before=resource.getrusage(resource.RUSAGE_CHILDREN);started=time.monotonic();code=None;status='FAILED'
    try:
        contract=base.global_permit(grant)
        wall=min(grant['maximum_wall_seconds'],contract['expires_epoch']-time.time(),datetime.datetime.fromisoformat(grant['expires_UTC']).timestamp()-time.time(),cfg['stage_deadline_epoch']-time.time())
        if wall<=0:raise ValueError('original resource clock expired')
        with open(output/'stdout.log','x') as stdout,open(output/'stderr.log','x') as stderr:
            result=subprocess.run([cfg['Rscript'],str(ROOT/'application/tests/524_fullstate_toy_validation.R'),str(ROOT),str(Path(args.root_grant).resolve()),args.root_grant_sha256,str(output/'toy_validation.json')],env=env,stdout=stdout,stderr=stderr,preexec_fn=child_limits,pass_fds=(lock_fd,),timeout=wall,check=False)
        code=result.returncode;status='TOY_VALIDATION_RETURNED' if code==0 else 'FAILED'
    except subprocess.TimeoutExpired:status='WALL_LIMIT_REACHED'
    finally:
        after=resource.getrusage(resource.RUSAGE_CHILDREN);cpu=after.ru_utime+after.ru_stime-before.ru_utime-before.ru_stime
        ref.immutable_json(output/'resource_receipt.json',dict(status=status,returncode=code,child_CPU_seconds=cpu,parent_CPU_seconds=time.process_time(),wall_seconds=time.monotonic()-started,max_child_RSS_KiB=after.ru_maxrss,prior_charge_CPU_seconds=BEFORE,new_source_charge_CPU_seconds=SOURCE,total_charged_master_CPU_seconds=BEFORE+SOURCE+cpu,remaining_unspent_unadmitted_CPU_seconds=2700-BEFORE-SOURCE-cpu,production_fit_invocations=0,production_passflags_written=0,root_grant_sha256=args.root_grant_sha256))
    if code!=0:raise SystemExit(1)


def main():
    p=argparse.ArgumentParser();p.add_argument('--config',required=True);p.add_argument('--root-grant',required=True);p.add_argument('--root-grant-sha256',required=True);p.add_argument('--check-authority',action='store_true');args=p.parse_args()
    if os.sched_getaffinity(0)!={31}:raise ValueError('administrative caller CPU31 required')
    cfg,grant=authority(args.config,args.root_grant,args.root_grant_sha256)
    if args.check_authority:print('PASS toy authority only; no optimizer/claim');return
    contract=base.global_permit(grant)
    with open(Path(contract['lock_dir'])/'muscat_cpu30.lock','a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);ref.verify_files([grant['global_contract']])
        os.sched_setaffinity(0,[30]);os.sched_setscheduler(0,os.SCHED_OTHER,os.sched_param(0));os.setpriority(os.PRIO_PROCESS,0,10)
        subprocess.run(['ionice','-c','3','-p',str(os.getpid())],check=True,capture_output=True)
        if not subprocess.check_output(['ionice','-p',str(os.getpid())],text=True).startswith('idle'):raise ValueError('I/O class differs')
        resource.setrlimit(resource.RLIMIT_CPU,(60,300))
        run_locked(args,cfg,grant,lock.fileno())


if __name__=='__main__':main()
