"""Finite R154 prediction ownership and immutable evidence contracts.

Importing this module never imports numerical libraries or starts a process.
No old queue-worker guard is invoked or rebound. CPU/RSS/I/O observations are
owned-process accounting and soft pressure guards, not cgroup isolation.
"""
from __future__ import annotations

import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import resource
import select
import shutil
import signal
import socket
import subprocess
import sys
import time
import uuid

THREAD_ENV = ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS',
              'BLIS_NUM_THREADS', 'NUMEXPR_NUM_THREADS', 'R_DATATABLE_NUM_THREADS',
              'VECLIB_MAXIMUM_THREADS')
NUMERICAL_NAMES = ('r', 'rscript', 'python', 'julia', 'matlab', 'octave')
FORBIDDEN_WORKER_NAMES = ('480_run_', '497_run_', '498_', '500_run_', '506_screen_')


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def read(path):
    return json.loads(Path(path).read_text())


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'),
                                    allow_nan=False).encode()).hexdigest()


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def verify_hashes(ledger):
    for name, expected in ledger.items():
        require(digest(name) == expected, 'pinned bytes changed: ' + name)


def immutable(path, value):
    """Create once with O_EXCL; an existing equal record is read-only reuse."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        require(read(path) == value, 'immutable record differs: ' + str(path))
        return
    payload = (json.dumps(value, sort_keys=True, indent=2, allow_nan=False)+'\n').encode()
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as f:
        f.write(payload)
        f.flush()
        os.fsync(f.fileno())


def update_owned(path, value):
    """Atomic mutable telemetry; no fsync on every progress observation.

    A crash may lose the last heartbeat. Claims, reservations and scientific
    packets use immutable durable records and are never inferred from telemetry.
    """
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
    payload=(json.dumps(value,sort_keys=True,indent=2,allow_nan=False)+'\n').encode()
    with tmp.open('xb') as stream:stream.write(payload)
    os.replace(tmp, path)


def pin(path):
    return dict(path=str(Path(path).resolve()), sha256=digest(path))


def verify_pin(value):
    require(set(value) >= {'path', 'sha256'} and len(value['sha256']) == 64,
            'missing explicit pinned evidence')
    verify_hashes({value['path']: value['sha256']})
    return read(value['path'])


def load_module(name, path, expected):
    require(digest(path) == expected, 'helper source changed: '+str(path))
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def source_identity(root):
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root, text=True).strip()
    require(not git('status', '--porcelain'), 'clean committed execution source required')
    branch = git('branch', '--show-current')
    require(branch.startswith('work/pricefm-r154-'), 'dedicated R154 feature source required')
    return dict(branch=branch, head=git('rev-parse', 'HEAD'))


def finite_positive(value, name):
    require(not isinstance(value, bool) and isinstance(value, (int, float))
            and math.isfinite(value) and value > 0, 'positive finite '+name+' required')


def validate_resource_bounds(a,global_contract,policy,now):
    require(global_contract.get('nonrenewing') is True and policy.get('nonrenewing') is True,
            'resource and pool authority must be nonrenewing')
    for envelope in (global_contract,policy):
        require(envelope['created_epoch']<=a['start_epoch']<=now<envelope['expires_epoch']
                and a['expires_epoch']<=envelope['expires_epoch'], 'study exceeds resource/pool lifetime')
    require(policy.get('schema')=='r154_resource_policy_v1','resource policy schema differs')
    allocation=policy['physical_CPU_allocation']
    require(allocation['host']==a['host'] and allocation['cpu']==a['cpu']
            and allocation['project_numerical_reservation'] is True,
            'resource allocation is not the exact project numerical permit')
    require(global_contract['max_new_numerical']<=policy['max_new_numerical_workers']<=2,
            'pool exceeds finite resource concurrency')
    require(a['study'] in policy['science'] and policy.get('sequential') is True,
            'resource study/serial ownership differs')
    require(a['minimum_available_RAM_GiB']>=policy['floors_GiB']['RAM']
            and a['minimum_free_disk_GiB']>=policy['floors_GiB']['disk'],'resource pressure floor weakened')
    sched=policy['scheduling']
    require((a['scheduler_policy'],a['nice'],a['io_class'])==(sched['policy'],sched['nice'],sched['io_class'])
            and sched['threads_per_payload']==1,'scope scheduling differs from project allocation')


def validate_authority(a, prep, prep_path, identity, now, hostname):
    require(a.get('schema') == 'r154_prediction_authority_v1'
            and a.get('status') == 'ADMITTED', 'fresh explicit admission absent')
    require(a.get('study') == prep['study'] and a.get('scope_id')
            and a.get('host') == hostname, 'study/host/scope admission differs')
    require(a.get('source') == identity, 'execution source differs')
    require(a.get('preparation') == pin(prep_path), 'preparation admission differs')
    require(a.get('nonrenewing') is True, 'authority must be nonrenewing')
    for key in ('start_epoch', 'expires_epoch', 'max_wall_seconds', 'max_execution_wall_seconds', 'full_prefix_CPU',
                'replacement_CPU', 'admin_drain_CPU', 'total_CPU_cap',
                'min_delivered_share', 'own_RSS_soft_GiB', 'minimum_free_disk_GiB',
                'minimum_available_RAM_GiB', 'new_output_soft_GiB',
                'drain_seconds', 'maximum_atomic_wall_seconds'):
        finite_positive(a.get(key), key)
    require(a['start_epoch'] <= now < a['expires_epoch'], 'authority expired/not started')
    require(a['expires_epoch']-a['start_epoch'] <= a['max_wall_seconds'], 'wall clock was reset')
    require(a['max_execution_wall_seconds']<=a['max_wall_seconds'],'active execution exceeds original absolute clock')
    require(0 < a['min_delivered_share'] <= 1, 'invalid delivered share')
    require(a.get('cpu') in range(32), 'physical core allocation required; SMT forbidden')
    require(a['full_prefix_CPU'] >= prep['historical_prefix_floor_CPU'],
            'entire scientific prefix is not priced')
    require(a['replacement_CPU'] >= prep['historical_replacement_floor_CPU'],
            'replacement reserve below declared floor')
    prior=a.get('prior_CPU_charged_seconds')
    require(isinstance(prior,(int,float)) and not isinstance(prior,bool) and math.isfinite(prior) and prior>=0,
            'explicit finite nonnegative prior charge required')
    require(prior+a['full_prefix_CPU']+a['replacement_CPU']+a['admin_drain_CPU'] <= a['total_CPU_cap'],
            'full prefix and reserves exceed cap')
    available = a['expires_epoch']-now-a['drain_seconds']
    required = (a['full_prefix_CPU']+a['replacement_CPU'])/a['min_delivered_share']
    require(available >= required+a['maximum_atomic_wall_seconds'],
            'finite whole-prefix calendar does not fit')
    require(a['max_execution_wall_seconds']-a['drain_seconds']>=required+a['maximum_atomic_wall_seconds'],
            'full prefix does not fit bounded active execution window')
    require(a.get('allow_extra_seeds') is False and a.get('new_fits') == 0
            and a.get('official_origins') == 0, 'scope expansion forbidden')
    require(a.get('max_new_tasks') == (64 if prep['study'] == 'EE' else 12), 'task ceiling differs')
    require(a.get('hard_cgroup_isolation_claimed') is False, 'false cgroup isolation claim')
    require(0<a.get('peer_census_cadence_seconds',0)<=5,'bounded peer census cadence must be <=5 seconds')
    require(isinstance(a.get('guardian_CPU_reserve'),int) and a['guardian_CPU_reserve']>=1
            and a['guardian_CPU_reserve']<a['admin_drain_CPU'],'guardian CPU must be priced inside admin reserve')
    require(a.get('scheduler_policy') in ('SCHED_OTHER','SCHED_IDLE')
            and isinstance(a.get('nice'),int) and 0<=a['nice']<=19 and a.get('io_class')==3,
            'explicit owned process scheduler/nice/IO policy required')
    for key in ('global_contract', 'peer_census', 'resource_policy', 'pricing_evidence',
                'process_classifier_proof', 'source_review', 'admin_rules'):
        verify_pin(a[key])
    global_contract = read(a['global_contract']['path'])
    require(global_contract.get('schema') == 'r154_global_permits_v1', 'global permit contract missing')
    require(global_contract.get('max_new_numerical') in (1, 2), 'global concurrency exceeds two')
    permits = global_contract['permits']
    require(len(permits) <= global_contract['max_new_numerical'], 'too many global permits')
    permit = next((p for p in permits if p['id'] == a.get('permit_id')), None)
    require(permit is not None and permit['host'] == hostname and permit['cpu'] == a['cpu']
            and prep['study'] in permit['science'], 'physical permit differs')
    require(permit.get('sequential') is True, 'permit cannot be optimistically replaced')
    require(Path(global_contract['lock_dir']).is_absolute(), 'shared host permit lock directory required')
    validate_resource_bounds(a,global_contract,read(a['resource_policy']['path']),now)
    require(Path(a['output_dir']).name == 'pricefm_stage_r154_'+prep['study'].lower()+'_'+a['scope_id'],
            'new scientific output namespace required')
    require(Path(a['output_dir']).parent == Path(prep['new_campaign_parent']),
            'output is outside new admitted namespace')
    return a


def process_identity(pid):
    root = Path('/proc')/str(pid)
    try:
        raw = (root/'stat').read_text()
        fields = raw[raw.rfind(')')+2:].split()
        cmd = (root/'cmdline').read_bytes()
        try:executable=os.readlink(root/'exe')
        except (PermissionError,FileNotFoundError,ProcessLookupError):executable=None
        return dict(pid=pid, start_ticks=int(fields[19]), state=fields[0],
                    ppid=int(fields[1]), comm=(root/'comm').read_text().strip(),
                    cmdline_sha256=hashlib.sha256(cmd).hexdigest(),
                    command=cmd.replace(b'\0', b' ').decode(errors='replace').strip(),
                    argv=[v.decode(errors='replace') for v in cmd.split(b'\0') if v],
                    executable=executable,
                    cpu_seconds=(int(fields[11])+int(fields[12]))/os.sysconf('SC_CLK_TCK'),
                    cpus=sorted(os.sched_getaffinity(pid)),
                    boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip())
    except (FileNotFoundError, ProcessLookupError):
        return None


def same_lifetime(x, y):
    return x is not None and all(x.get(k) == y.get(k) for k in ('pid', 'start_ticks', 'boot_id'))


def pidfd_open(pid):
    """Use a kernel pidfd even when Python was built against older headers.

    Muscat's pinned Python exposes pidfd_send_signal but not os.pidfd_open.
    Linux x86_64 syscall434 is the pidfd_open ABI; unknown architectures fail
    closed. There is no fallback to a numeric-PID signal.
    """
    if hasattr(os,'pidfd_open'):
        return os.pidfd_open(pid)
    import ctypes
    require(sys.platform=='linux' and os.uname().machine=='x86_64','verified pidfd ABI unavailable')
    libc=ctypes.CDLL(None,use_errno=True)
    fd=libc.syscall(ctypes.c_long(434),ctypes.c_int(pid),ctypes.c_uint(0))
    if fd<0:
        errno=ctypes.get_errno()
        raise OSError(errno,os.strerror(errno))
    os.set_inheritable(fd,False)
    return int(fd)


def signal_unreaped_direct_child(pid,identity):
    """The sole parent waiter holds this child; it cannot recycle until waitpid.

    waitid(WNOWAIT) both proves direct-child ownership and leaves an exited
    child unreaped. No other thread/handler may reap it. This is the reviewed
    old-kernel alternative, never a check-then-signal arbitrary parent PID.
    """
    state=os.waitid(os.P_PID,pid,os.WEXITED|os.WNOHANG|os.WNOWAIT)
    require(identity['ppid']==os.getpid() and same_lifetime(process_identity(pid),identity),
            'held direct child lifetime differs')
    if state is None:
        os.kill(pid,signal.SIGKILL)


def admin_match(p,cpu,rules):
    """Only frozen source + exact controller verb + explicit disjoint mask."""
    if not p['comm'].lower().startswith('python'):
        return False
    argv=p.get('argv',[])
    for rule in rules.get('rules',[]):
        path=rule['script']['path']
        interpreter=rule['interpreter']
        flags=rule['interpreter_flags']
        if flags!=['-B']:continue
        index=1+len(flags)
        if len(argv)<=index+1 or argv[:index]!=[interpreter['path'],*flags] or argv[index]!=path:
            continue
        if p.get('executable')!=str(Path(interpreter['path']).resolve()):continue
        if digest(interpreter['path'])!=interpreter['sha256']:continue
        if index+1>=len(argv) or argv[index+1]!=rule['verb']:continue
        if digest(path)!=rule['script']['sha256']:continue
        flag=rule['cpu_flag']
        value=None
        declarations=[i for i,arg in enumerate(argv) if arg==flag or arg.startswith(flag+'=')]
        if len(declarations)!=1:continue
        i=declarations[0]
        if argv[i]==flag:
            if i+1<len(argv):value=argv[i+1]
        else:value=argv[i][len(flag)+1:]
        try:
            mask=set(map(int,value.split(',')))
        except (ValueError,AttributeError):continue
        if mask and cpu not in mask and mask.issubset(set(rule['allowed_declared_cpus'])):
            return True
    return False


def peer_conflicts(cpu, census, own_pids, processes,admin_rules=None):
    allowed = {(p['boot_id'], p['pid'], p['start_ticks'], p['cmdline_sha256']):p
               for p in census['allowed_intersecting_processes']}
    conflicts=[]
    for p in processes:
        if p is None or p['pid'] in own_pids or cpu not in p['cpus']:
            continue
        # Stopped processes are retained in evidence; any later activation is
        # rejected unless its exact lifetime was explicitly accepted in census.
        comm=p['comm'].lower()
        numerical = comm=='r' or any(comm.startswith(n) for n in NUMERICAL_NAMES if n!='r')
        numerical |= any(t in p['command'] for t in census.get('numerical_markers', []))
        key=(p['boot_id'],p['pid'],p['start_ticks'],p['cmdline_sha256'])
        known=allowed.get(key)
        bad_state=known is not None and 'allowed_states' in known and p['state'] not in known['allowed_states']
        unknown=numerical and known is None and not admin_match(p,cpu,admin_rules or {})
        if bad_state or unknown:
            # Never retain foreign raw argv in a conflict output.
            conflicts.append({k:p[k] for k in ('pid','start_ticks','boot_id','state','comm','cmdline_sha256','cpus')})
    return conflicts


def all_processes():
    rows=[]
    for path in Path('/proc').iterdir():
        if path.name.isdigit():
            try:
                value=process_identity(int(path.name))
            except PermissionError:
                raise RuntimeError('unreadable peer process identity: '+path.name)
            if value is not None:
                masks=[]
                try:
                    for thread in (path/'task').iterdir():
                        try:
                            masks.append(dict(tid=int(thread.name),cpus=sorted(os.sched_getaffinity(int(thread.name)))))
                        except ProcessLookupError:
                            continue
                except FileNotFoundError:
                    continue
                value['threads']=masks
                value['cpus']=sorted(set(value['cpus']).union(*(set(t['cpus']) for t in masks)))
                rows.append(value)
    return rows


def cpu_seconds():
    own=resource.getrusage(resource.RUSAGE_SELF)
    child=resource.getrusage(resource.RUSAGE_CHILDREN)
    return own.ru_utime+own.ru_stime+child.ru_utime+child.ru_stime


def funded_payload_CPU_limit(current,total,prior,guardian,inherited_hard):
    limit=math.floor(current+total-prior-guardian-1)
    require(limit>=1 and (inherited_hard==resource.RLIM_INFINITY or inherited_hard>=limit),
            'inherited hard CPU limit cannot fund the admitted payload')
    return limit


def pressure(a, out, owned_children=(),growth_GiB=None):
    info={k:int(v.split()[0])*1024 for k,v in
          (line.split(':',1) for line in Path('/proc/meminfo').read_text().splitlines())}
    rss=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss/1024**2
    for pid in owned_children:
        try:rss+=int((Path('/proc')/str(pid)/'statm').read_text().split()[1])*os.sysconf('SC_PAGE_SIZE')/1024**3
        except (FileNotFoundError,ProcessLookupError):pass
    disk=shutil.disk_usage(out).free/1024**3
    growth=(sum(p.stat().st_size for p in Path(out).rglob('*') if p.is_file())/1024**3
            if growth_GiB is None else growth_GiB)
    require(info['MemAvailable']/1024**3 >= a['minimum_available_RAM_GiB'], 'host RAM floor')
    require(disk >= a['minimum_free_disk_GiB'], 'host disk floor')
    require(rss <= a['own_RSS_soft_GiB'], 'owned RSS soft guard')
    require(growth <= a['new_output_soft_GiB'], 'new output soft guard')
    return dict(peak_own_RSS_GiB=rss, free_disk_GiB=disk, new_output_GiB=growth)


class Lease:
    """One permanent claim; stdlib supervisor PARENT + direct payload CHILD.

    Muscat lacks pidfds. The single-threaded parent holds its direct child
    unreaped, so that child's PID cannot recycle before this parent waitpid.
    Only that held child may be terminated. Kernel PDEATHSIG protects the child
    if its supervisor dies. Both retain the same project permit lock.
    """
    def __init__(self, a, prep, authority_path):
        self.a,self.prep=a,prep
        self.out=Path(a['output_dir'])
        self.out.mkdir(parents=True,exist_ok=True)
        self.started=time.monotonic()
        self.cpu0=cpu_seconds()
        self.own=process_identity(os.getpid())
        require(self.own is not None, 'own lifetime unavailable')
        self.guardian=None
        self.reserve_total=0.0
        self._peer_at=0.0
        self._pressure_at=0.0
        self._heartbeat_at=0.0
        self._pressure={}
        self._written={}
        self._written_total=0
        self.census=read(a['peer_census']['path'])
        self.admin_rules=read(a['admin_rules']['path'])
        self.lock=(self.out/'scope.lock').open('a+')
        fcntl.flock(self.lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        global_contract=read(a['global_contract']['path'])
        lock_dir=Path(global_contract['lock_dir'])
        lock_dir.mkdir(parents=True,exist_ok=True)
        self.permit_lock=(lock_dir/(a['permit_id']+'.lock')).open('a+')
        fcntl.flock(self.permit_lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        peers=peer_conflicts(a['cpu'],self.census,{os.getpid()},all_processes(),self.admin_rules)
        require(not peers,'new numerical peer before claim: '+str([p['pid'] for p in peers]))
        self._peer_at=time.monotonic()
        # Never attach to an old claim, including one whose process vanished.
        require(not (self.out/'claim.json').exists(), 'claim already consumed; no automatic replacement')
        immutable(self.out/'claim.json',dict(schema='r154_prediction_claim_v1',authority=pin(authority_path),
            permit_id=a['permit_id'],scope_id=a['scope_id'],study=prep['study'],process=self.own,
            output_dir=str(self.out),started_epoch=time.time(),new_fits=0,official_origins=0))
        os.sched_setaffinity(0,{a['cpu']})
        require(os.sched_getaffinity(0)=={a['cpu']}, 'actual CPU pin differs')
        policy={'SCHED_OTHER':os.SCHED_OTHER,'SCHED_IDLE':os.SCHED_IDLE}
        require(a.get('scheduler_policy') in policy,'explicit actual scheduler policy required')
        os.sched_setscheduler(0,policy[a['scheduler_policy']],os.sched_param(0))
        os.setpriority(os.PRIO_PROCESS,0,a['nice'])
        require(os.sched_getscheduler(0)==policy[a['scheduler_policy']]
                and os.getpriority(os.PRIO_PROCESS,0)==a['nice'],'scheduler/nice application differs')
        require(a.get('io_class')==3,'explicit idle IO class required')
        subprocess.run(['ionice','-c','3','-p',str(os.getpid())],check=True,capture_output=True)
        require(subprocess.check_output(['ionice','-p',str(os.getpid())],text=True).startswith('idle'), 'actual IO class differs')
        for name in THREAD_ENV:
            require(os.environ.get(name)=='1', 'single-thread environment differs: '+name)
        # Hard kernel limit applies only to this disposable process, no cgroup.
        current=resource.getrusage(resource.RUSAGE_SELF)
        old=resource.getrlimit(resource.RLIMIT_CPU)
        hard=funded_payload_CPU_limit(current.ru_utime+current.ru_stime,a['total_CPU_cap'],
            a['prior_CPU_charged_seconds'],a['guardian_CPU_reserve'],old[1])
        resource.setrlimit(resource.RLIMIT_CPU,(hard,hard))
        self._start_guardian()
        try:self.check(refresh_output=True)
        except BaseException as exc:
            self.close('INCOMPLETE',dict(stage='bootstrap',type=type(exc).__name__,message=str(exc)))
            raise

    def _start_guardian(self):
        import ctypes
        parent=self.own
        parent_cpu0=self.cpu0
        own_usage=resource.getrusage(resource.RUSAGE_SELF)
        parent_own_cpu0=own_usage.ru_utime+own_usage.ru_stime
        monitor_started=time.monotonic()
        active=self.a.get('max_execution_wall_seconds',self.a['max_wall_seconds'])
        deadline=min(self.a['expires_epoch'],time.time()+active)
        local_deadline=self.started+active
        require(len(list(Path('/proc/self/task').iterdir()))==1,'supervisor must have no competing thread/reaper')
        require(signal.getsignal(signal.SIGCHLD)==signal.SIG_DFL,'custom SIGCHLD reaper forbidden')
        readfd,writefd=os.pipe()
        pid=os.fork()
        if pid==0:
            os.close(writefd)
            libc=ctypes.CDLL(None,use_errno=True)
            # PR_SET_PDEATHSIG=1, binding death to this exact current parent.
            if libc.prctl(1,signal.SIGKILL,0,0,0)!=0:
                os._exit(125)
            if os.getppid()!=parent['pid'] or not same_lifetime(process_identity(parent['pid']),parent):
                os._exit(125)
            self.own=process_identity(os.getpid())
            self.guardian=parent['pid']
            self.guardian_identity=parent
            self.guardian_cpu0=parent_cpu0
            self.cpu0=0.0
            self.started=time.monotonic()
            immutable(self.out/'payload_identity.json',dict(process=self.own,parent=parent,
                kernel_parent_death_signal='SIGKILL',post_arm_parent_check=True,
                inherited_same_permit_lock=True))
            if os.read(readfd,1)!=b'A':os._exit(125)
            os.close(readfd)
            return
        # This branch never returns into the numerical caller. It imports no
        # numerical library and owns the sole wait/reap path for the direct child.
        os.close(readfd)
        child=process_identity(pid)
        require(child is not None,'direct payload lifetime unavailable')
        immutable(self.out/'guardian.json',dict(process=parent,payload=child,deadline_epoch=deadline,
            reserved_CPU_seconds=self.a['guardian_CPU_reserve'],scope_only=True,
            signal_delivery='held_unreaped_direct_child_only',single_threaded_only_waiter=True,
            no_cgroup_or_baseline_signal=True))
        usage=resource.getrusage(resource.RUSAGE_SELF)
        parent_limit=math.floor(usage.ru_utime+usage.ru_stime+self.a['guardian_CPU_reserve'])
        resource.setrlimit(resource.RLIMIT_CPU,(parent_limit,parent_limit))
        os.write(writefd,b'A');os.close(writefd)
        reason='PAYLOAD_EXITED'
        try:
            while True:
                state=os.waitid(os.P_PID,pid,os.WEXITED|os.WNOHANG|os.WNOWAIT)
                if state is not None:break
                live=process_identity(pid)
                require(same_lifetime(live,child),'held child identity changed')
                elapsed_CPU=cpu_seconds()-parent_cpu0+live['cpu_seconds']+self.a.get('prior_CPU_charged_seconds',0)
                if time.time()>=deadline or time.monotonic()>=local_deadline or elapsed_CPU>=self.a['total_CPU_cap']:
                    reason='WALL_DEADLINE' if time.time()>=deadline or time.monotonic()>=local_deadline else 'ALL_INCLUSIVE_CPU_CAP'
                    immutable(self.out/'guardian_timeout.json',dict(parent=parent,payload=child,
                        reason=reason,action='SIGKILL_held_unreaped_direct_child_only',epoch=time.time(),
                        permit_not_released=True))
                    signal_unreaped_direct_child(pid,child)
                time.sleep(.25)
            _,status=os.waitpid(pid,0)
            code=os.waitstatus_to_exitcode(status)
            reserved=sum(read(p)['CPU_seconds'] for p in (self.out/'reservations').glob('*.json'))
            actual=cpu_seconds()-parent_cpu0
            prior=self.a.get('prior_CPU_charged_seconds',0)
            own_usage=resource.getrusage(resource.RUSAGE_SELF)
            immutable(self.out/'supervisor_exit_receipt.json',dict(status=reason,parent=parent,payload=child,
                child_exit_code=code,exact_combined_reaped_CPU_seconds=actual,
                supervisor_own_CPU_since_fork_seconds=own_usage.ru_utime+own_usage.ru_stime-parent_own_cpu0,
                supervisor_monitor_wall_seconds=time.monotonic()-monitor_started,
                prior_CPU_charged_seconds=prior,all_inclusive_observed_CPU_seconds=actual+prior,
                conservatively_reserved_component_CPU_seconds=reserved,
                all_inclusive_charged_CPU_seconds=max(actual+prior,reserved+prior),
                epoch=time.time(),guardian_reservation_CPU=self.a['guardian_CPU_reserve'],
                no_optimistic_permit_replacement=True))
            os._exit(code if code>=0 else 128-code)
        except BaseException:
            # Held-child termination remains safe even if it exited just before
            # the call: it is still unreaped and cannot be an unrelated lifetime.
            try:signal_unreaped_direct_child(pid,child)
            except (ChildProcessError,ProcessLookupError):pass
            try:os.waitpid(pid,0)
            except ChildProcessError:pass
            os._exit(125)

    def observed_CPU(self):
        guardian=process_identity(self.guardian) if self.guardian else None
        living=max(0.0,guardian['cpu_seconds']-self.guardian_cpu0) if guardian else 0.0
        return cpu_seconds()-self.cpu0+living+getattr(self,'a',{}).get('prior_CPU_charged_seconds',0)

    def note_written(self,path):
        path=Path(path)
        files=[path] if path.is_file() else [p for p in path.rglob('*') if p.is_file()]
        for p in files:
            size=p.stat().st_size
            self._written_total+=size-self._written.get(str(p),0)
            self._written[str(p)]=size

    def check(self, atomic_CPU=0.0, atomic_wall=0.0,fresh_peer=True,peer_cadence=True,refresh_output=False):
        now=time.time()
        require(now+atomic_wall+self.a['drain_seconds']<self.a['expires_epoch'], 'wall/drain admission exhausted')
        require(time.monotonic()-self.started+atomic_wall+self.a['drain_seconds']<self.a['max_execution_wall_seconds'], 'local finite active timer exhausted')
        require(self.observed_CPU()+atomic_CPU+self.a['admin_drain_CPU']<self.a['total_CPU_cap'], 'actual all-inclusive CPU/drain exhausted')
        guardian=process_identity(self.guardian) if self.guardian else None
        require(guardian is not None and guardian['state']!='Z', 'local wall guardian missing')
        require(not (self.out/'stop_request.json').exists(), 'explicit cooperative stop request')
        for task in (Path('/proc/self/task')).iterdir():
            require(os.sched_getaffinity(int(task.name))=={self.a['cpu']}, 'thread affinity differs')
        children=Path('/proc/self/task')/str(os.getpid())/'children'
        require(set(map(int,children.read_text().split())) <= {self.guardian}, 'unreviewed owned child appeared')
        clock=time.monotonic()
        if fresh_peer or (peer_cadence and clock-self._peer_at>=self.a['peer_census_cadence_seconds']):
            peers=peer_conflicts(self.a['cpu'],self.census,{os.getpid(),self.guardian},all_processes(),self.admin_rules)
            require(not peers, 'new unreviewed numerical peer intersects allocation: '+str([p['pid'] for p in peers]))
            self._peer_at=time.monotonic()
        if refresh_output:
            self._written={str(p):p.stat().st_size for p in self.out.rglob('*') if p.is_file()}
            self._written_total=sum(self._written.values())
        # All immutable packet writes are accounted immediately. A one-MiB
        # metadata tail and sixteen-MiB atomic packet reserve cover temporary
        # headers/receipts between the <=64 component reconciliation walks.
        growth=(self._written_total+17*1024**2)/1024**3
        require(growth<=self.a['new_output_soft_GiB'],'tracked output/atomic reserve exhausted')
        if fresh_peer or refresh_output or clock-self._pressure_at>=1:
            self._pressure=pressure(self.a,self.out,(self.guardian,),growth)
            self._pressure_at=time.monotonic()
        return self._pressure

    def reserve(self,name,cpu):
        finite_positive(cpu,'task reservation')
        require(self.reserve_total+cpu<=self.a['full_prefix_CPU']+self.a['replacement_CPU'], 'task reservations exceed funded prefix')
        immutable(self.out/'reservations'/(name+'.json'),dict(task=name,CPU_seconds=cpu,epoch=time.time(),
            failed_or_unsealed_reservation_retained=True,refund_authorized=False))
        self.reserve_total+=cpu

    def observe(self,event):
        quiescent=event.get('status') in ('context_loading','chunk_sealed','LV_call_complete')
        state=self.check(fresh_peer=False,peer_cadence=not quiescent)
        clock=time.monotonic()
        if quiescent or clock-self._heartbeat_at>=1:
            update_owned(self.out/'heartbeat.json',dict(event,epoch=time.time(),process=self.own,
                charged_inclusive_CPU_seconds=self.observed_CPU(),
                observed_live_CPU_seconds=self.observed_CPU()-self.a['prior_CPU_charged_seconds'],
                prior_CPU_charged_seconds=self.a['prior_CPU_charged_seconds'],
                reserved_CPU_seconds=self.reserve_total,**state))
            self.note_written(self.out/'heartbeat.json')
            self._heartbeat_at=clock

    def close(self,status,detail=None):
        immutable(self.out/'exit_receipt.json',dict(status=status,detail=detail,process=self.own,
            supervisor=self.guardian_identity,epoch=time.time(),sampled_live_CPU_seconds=self.observed_CPU()-self.a['prior_CPU_charged_seconds'],
            sampled_all_inclusive_charged_CPU_seconds=self.observed_CPU(),prior_CPU_charged_seconds=self.a['prior_CPU_charged_seconds'],
            conservatively_reserved_CPU_seconds=self.reserve_total,
            conservative_inclusive_CPU_charge=max(self.observed_CPU(),self.a['prior_CPU_charged_seconds']+self.reserve_total),
            permit_replacement_authorized=False,physical_drain_review_required=True))
        # The child exits normally after its result publication; the supervisor
        # reaps it and emits exact combined CPU before releasing its own lock.


def aliases_path(original, aliases):
    return Path(aliases.get(str(original),str(original)))


def resolve_pin(original,expected,aliases):
    path=aliases_path(original,aliases)
    require(digest(path)==expected,'read-alias bytes differ: '+str(original))
    return path


def sealed_packet(folder, expected_context=None):
    folder=Path(folder)
    seal=read(folder/'completed_evidence.json')
    require(seal.get('certified',seal.get('metadata',{}).get('certified')) is True,'uncertified cached packet')
    for name,expected in seal['artifacts'].items():
        path=(folder/name).resolve()
        require(path.is_relative_to(folder.resolve()),'unsafe artifact path')
        require(digest(path)==expected,'packet payload changed')
    if expected_context is not None:
        require(seal.get('context')==expected_context,'original scientific context differs')
    return seal
