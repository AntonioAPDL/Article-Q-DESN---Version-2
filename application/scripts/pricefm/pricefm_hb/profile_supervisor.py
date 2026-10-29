"""Linux owned-command subtree supervisor, standard library only.

Every command gets a fresh session, one inherited logical CPU, a kernel escape
filter and an orphan-reaping parent. Only that proved new session is signaled.
The CLI is also used as source text remotely, before a package is staged.
"""
from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import json
import math
import mmap
import os
from pathlib import Path
import platform
import resource
import selectors
import signal
import stat
import subprocess
import struct
import sys
import tempfile
import time

GUARD_SHARED = None
BOOTSTRAP_ANCHOR_TAG = 'OWNED_PRE_FIRST_FORK_CPU_AND_WAITED_MONOTONIC_V2'


class OwnedStopError(RuntimeError):
    """Keep exact proved-owned state visible through unchanged caller errors."""
    def __init__(self,witness):
        self.witness=witness
        raw=json.dumps(witness,sort_keys=True,separators=(',',':'),allow_nan=False)
        if len(raw.encode())>65536:raise RuntimeError('owned stop witness exceeds bounded diagnostic size')
        super().__init__('owned command group failed to stop for accounting; owned_stop_witness='+raw)


def require(value, message):
    if not value:
        raise RuntimeError(message)


def prctl(option, arg):
    libc = ctypes.CDLL(None, use_errno=True)
    require(libc.prctl(option, arg, 0, 0, 0) == 0,
            'required Linux process isolation unavailable: ' + str(ctypes.get_errno()))


def child_guard(core):
    """Executed only in the new child, before any reviewed command can run."""
    os.setsid(); os.sched_setaffinity(0, {core})
    prctl(38, 1)  # PR_SET_NO_NEW_PRIVS; inherited by every fork/exec.
    class Filter(ctypes.Structure):
        _fields_ = [('code', ctypes.c_ushort), ('jt', ctypes.c_ubyte),
                    ('jf', ctypes.c_ubyte), ('k', ctypes.c_uint)]
    class Program(ctypes.Structure):
        _fields_ = [('len', ctypes.c_ushort), ('filter', ctypes.POINTER(Filter))]
    # x86_64 only. Deny escape/reparent/affinity/priority changes and signals
    # originating in a command; the unfiltered supervisor owns cancellation.
    blocked = (109, 112, 203, 272, 308, 101, 311, 62, 200, 234, 129, 297,
               424, 142, 144, 141, 314)
    rules = [(0x20, 0, 0, 4), (0x15, 1, 0, 0xc000003e), (0x06, 0, 0, 0),
             (0x20, 0, 0, 0), (0x35, 0, 1, 0x40000000),
             (0x06, 0, 0, 0x00050000 | errno.EPERM)]
    for number in blocked:
        rules.extend([(0x15, 0, 1, number), (0x06, 0, 0, 0x00050000 | errno.EPERM)])
    # clone3's opaque structure cannot be inspected by classic BPF. ENOSYS
    # permits libc's ordinary clone/fork fallback; namespace/parent flags are
    # rejected for clone itself, preserving the proved session and ancestry.
    rules.extend([(0x15, 0, 1, 435), (0x06, 0, 0, 0x00050000 | errno.ENOSYS),
        (0x15, 0, 3, 56), (0x20, 0, 0, 16),
        (0x45, 0, 1, 0x7e828000), (0x06, 0, 0, 0x00050000 | errno.EPERM),
        (0x06, 0, 0, 0x7fff0000)])
    array = (Filter * len(rules))(*(Filter(*item) for item in rules))
    program = Program(len(rules), array)
    libc = ctypes.CDLL(None, use_errno=True)
    require(libc.prctl(22, 2, ctypes.byref(program), 0, 0) == 0,
            'required kernel seccomp escape filter unavailable: ' + str(ctypes.get_errno()))
    if GUARD_SHARED is not None:
        item = process_record(os.getpid())
        GUARD_SHARED[0:24] = struct.pack('QQQ', os.getpid(), item['start_ticks'], os.getuid())
        GUARD_SHARED[24:32] = struct.pack('Q', 1)
        until = time.monotonic() + 2
        while struct.unpack('Q', GUARD_SHARED[56:64])[0] != 1:
            if os.getppid() != struct.unpack('Q', GUARD_SHARED[48:56])[0] or time.monotonic() >= until:
                os._exit(125)
            time.sleep(.001)


def process_record(pid):
    root = Path('/proc') / str(pid)
    uid = root.stat().st_uid
    fields = (root / 'stat').read_text().rsplit(')', 1)[1].split()
    return dict(pid=pid, uid=uid, state=fields[0], ppid=int(fields[1]),
        pgid=int(fields[2]), sid=int(fields[3]), start_ticks=int(fields[19]),
        own_ticks=int(fields[11]) + int(fields[12]),
        waited_ticks=int(fields[13]) + int(fields[14]), last_processor=int(fields[36]))


def children_of(pid):
    result = set(); root = Path('/proc') / str(pid) / 'task'
    try: tasks = list(root.iterdir())
    except FileNotFoundError: return result
    require(len(tasks) <= 64, 'owned thread-count bound exceeded')
    for task in tasks:
        try: raw = (task / 'children').read_text()
        except FileNotFoundError: continue
        require(len(raw) <= 65536, 'bounded owned child inventory required')
        result.update(int(value) for value in raw.split())
    return result


def session_records(sid, leader_start, uid, core, enforce_count=True):
    # Linux subreaper ancestry supplies exact descendants. No global PID census
    # or inaccessible-process exemption is needed, and no baseline is inspected.
    result = []; pending = list(children_of(os.getpid()) | {sid}); seen = set()
    while pending:
        pid = pending.pop()
        if pid in seen: continue
        seen.add(pid)
        try:
            item = process_record(pid)
        except (FileNotFoundError, ProcessLookupError):
            continue
        require(item['sid'] == sid and item['uid'] == uid and item['pgid'] == sid and item['start_ticks'] >= leader_start,
                'owned session provenance changed')
        if item['state'] != 'Z':
            try: affinity = os.sched_getaffinity(item['pid'])
            except ProcessLookupError: continue
            require(affinity == {core}, 'command affinity escaped the proved single CPU')
            item.update(affinity=sorted(affinity),affinity_proved=True)
        else:item.update(affinity=None,affinity_proved=False)
        result.append(item)
        pending.extend(children_of(pid))
        if enforce_count: require(len(result) <= 64, 'owned helper-count bound exceeded')
    return result


def guardian_self_upper(core,ticks,bootstrap_anchor=None):
    """Fresh exact-owned guardian SELF; no unpaired shared CPU/time sample."""
    if GUARD_SHARED is None:
        require(bootstrap_anchor is None, 'inherited history requires owned guardian context')
        return 0.,0.
    pid=struct.unpack('Q',GUARD_SHARED[40:48])[0]
    birth=struct.unpack('Q',GUARD_SHARED[72:80])[0]
    item=process_record(pid)
    require(birth>0 and item['pid']==pid==os.getppid() and item['uid']==os.getuid()
            and item['start_ticks']==birth,'owned guardian CPU sample identity changed')
    require(os.sched_getaffinity(pid)=={core},'owned guardian CPU sample affinity changed')
    rounding=2/ticks  # Separate proc utime/stime conversions can each round down.
    own_upper = item['own_ticks']/ticks+rounding
    if bootstrap_anchor is not None:
        bootstrap_anchor_fields(bootstrap_anchor, core, ticks, time.monotonic())
        require(bootstrap_anchor[1:4] == (pid,birth,os.getuid())
                and item['waited_ticks']/ticks <= bootstrap_anchor[9],
                'guardian inherited waited history identity or bound changed')
        return (own_upper+bootstrap_anchor[9],
                rounding+bootstrap_anchor[9]-bootstrap_anchor[8])
    return own_upper,rounding


def bootstrap_anchor_digest(values):
    return hashlib.sha256(struct.pack('QQQQQdddd', *values)).hexdigest()


def bootstrap_anchor_fields(anchor, core, ticks, now):
    """Validate one immutable, typed pre-fork sample, never a mutable pair."""
    require(type(anchor) is tuple and len(anchor) == 11 and anchor[0] == BOOTSTRAP_ANCHOR_TAG,
            'immutable bootstrap anchor tuple required')
    require(all(type(value) is int and value >= 0 for value in anchor[1:6])
            and anchor[1] > 0 and anchor[2] > 0 and anchor[5] > 0,
            'bootstrap anchor identity fields invalid')
    require(anchor[4] == core and anchor[5] == ticks,
            'bootstrap anchor CPU or clock identity changed')
    require(all(type(v) is float and math.isfinite(v) for v in anchor[6:10])
            and 0 <= anchor[6] <= now and anchor[8] >= 0
            and anchor[9] >= anchor[8] + 2/ticks
            and anchor[7] >= anchor[9] + 2/ticks,
            'bootstrap anchor CPU or monotonic ordering invalid')
    require(type(anchor[10]) is str and anchor[10] == bootstrap_anchor_digest(anchor[1:10]),
            'bootstrap anchor immutable sample fingerprint changed')
    return anchor


def pre_fork_cpu_anchor(core, ticks):
    """Include startup SELF and inherited waited CPU before any new child.

    The timestamp precedes both counter reads, so their interval is counted
    twice conservatively. Later owned work shares this one CPU. A tuple is
    inherited by fork/COW; no writer publishes another CPU/time sample.
    Exec preserves a login shell's earlier waited CPU even with no live
    children. That coherent kernel history is charged, not assumed absent:
    its exact C0 is used in final totals and its upper H0 in live bounds.
    """
    pid = os.getpid(); before = process_record(pid)
    def child_history():
        usage = resource.getrusage(resource.RUSAGE_CHILDREN)
        values = (usage.ru_utime, usage.ru_stime)
        require(all(type(v) in (int,float) and math.isfinite(v) and v >= 0 for v in values),
                'bootstrap inherited waited CPU counter invalid')
        return values
    before_history = child_history()
    def no_live_children_or_threads():
        require(os.sched_getaffinity(0) == {core}
                and len(list((Path('/proc') / str(pid) / 'task').iterdir())) == 1
                and not children_of(pid),
                'bootstrap anchor requires one CPU/thread and no live children')
    no_live_children_or_threads()
    require(before['uid'] == os.getuid() and before['waited_ticks'] >= 0,
            'bootstrap anchor initial identity or waited CPU invalid')
    anchor_time = time.monotonic()  # BEFORE either SELF counter read.
    usage = resource.getrusage(resource.RUSAGE_SELF)
    sampled_history = child_history()
    sample = process_record(pid)
    require((sample['pid'], sample['start_ticks'], sample['uid'])
            == (before['pid'], before['start_ticks'], before['uid'])
            and sample['waited_ticks'] == before['waited_ticks'],
            'bootstrap anchor identity or inherited waited CPU changed during sample')
    no_live_children_or_threads()
    after_history = child_history(); after = process_record(pid)
    require(before_history == sampled_history == after_history
            and (after['pid'],after['start_ticks'],after['uid'],after['waited_ticks'])
                == (before['pid'],before['start_ticks'],before['uid'],before['waited_ticks']),
            'bootstrap inherited waited CPU history changed during sample')
    history_cpu = sum(sampled_history)
    history_upper = max(history_cpu, sample['waited_ticks']/ticks) + 2/ticks
    upper = max(usage.ru_utime + usage.ru_stime, sample['own_ticks'] / ticks) + 2/ticks + history_upper
    values = (pid, sample['start_ticks'], sample['uid'], core, ticks, anchor_time, upper,
              history_cpu, history_upper)
    anchor = (BOOTSTRAP_ANCHOR_TAG, *values, bootstrap_anchor_digest(values))
    return bootstrap_anchor_fields(anchor, core, ticks, time.monotonic())


def validate_bootstrap_anchor(anchor, core, ticks, now):
    bootstrap_anchor_fields(anchor, core, ticks, now)
    require(GUARD_SHARED is not None, 'bootstrap anchor guardian context missing')
    pid = struct.unpack('Q', GUARD_SHARED[40:48])[0]
    birth = struct.unpack('Q', GUARD_SHARED[72:80])[0]
    item = process_record(pid)
    require(anchor[1:4] == (pid, birth, os.getuid()) and pid == os.getppid()
            and (item['pid'], item['start_ticks'], item['uid']) == anchor[1:4]
            and item['waited_ticks']/ticks <= anchor[9],
            'bootstrap anchor guardian identity changed')
    require(os.sched_getaffinity(pid) == {core}
            and len(list((Path('/proc') / str(pid) / 'task').iterdir())) == 1,
            'bootstrap anchor guardian affinity or thread count changed')
    return anchor


def one_core_stop_upper(last_cpu,last_anchor,birth_ticks,ticks,now,bootstrap_anchor=None,core=None):
    if last_cpu is None:
        if bootstrap_anchor is not None:
            validate_bootstrap_anchor(bootstrap_anchor, core, ticks, now)
            fresh_now = time.monotonic()  # Include validation/counter-read work.
            require(fresh_now >= now, 'bootstrap anchor monotonic clock changed')
            return bootstrap_anchor[7] + fresh_now - bootstrap_anchor[6]
        # Birth tick is floored. This bounds startup before the first complete
        # snapshot for legacy direct utility calls. Actual guarded monitors
        # require the immutable pre-first-fork sample before command creation.
        return time.clock_gettime(time.CLOCK_BOOTTIME)-birth_ticks/ticks
    require(last_anchor is not None and now>=last_anchor,'proved CPU anchor clock changed')
    return last_cpu+now-last_anchor


def inherited_monitor_SELF_cap(cpu_seconds, reaped_cpu, bootstrap_anchor):
    """Prior waited work cannot become new monitor SELF allowance."""
    history_upper = 0. if bootstrap_anchor is None else bootstrap_anchor[9]
    return math.floor(cpu_seconds-reaped_cpu-history_upper)


def guardian_SELF_boundary(cpu_seconds, own_cpu, bootstrap_anchor):
    """Keep inherited work in the independent guardian emergency boundary."""
    return bootstrap_anchor[9]+own_cpu >= cpu_seconds-1


def await_owned_stop(records,*,stop_start,inner_deadline,active_ceiling,cpu_upper,heartbeat,context,killed):
    """Wait finitely; unknown running/kernel work is charged as one-core wall."""
    stop_end=min(inner_deadline,stop_start+5.)
    while True:
        heartbeat(time.monotonic());items=records();now=time.monotonic();heartbeat(now)
        stopped=all(item['state'] in ('T','t','Z') for item in items)
        if stopped and (killed() or now<stop_end):return items,now-stop_start
        upper=cpu_upper(now)
        failure=('STOP_WAIT_INNER_WALL' if now>=inner_deadline else
                 'STOP_WAIT_WINDOW_EXHAUSTED' if now>=stop_end else
                 'STOP_WAIT_CPU_UPPER_BOUNDARY' if upper>=active_ceiling else None)
        if failure:
            witness=dict(context,schema='r164_owned_stop_failure_witness_v1',failure=failure,
                monitor_pid=os.getpid(),monitor_host=os.uname().nodename,observed_monotonic=now,
                stop_requested_monotonic=stop_start,stop_deadline_monotonic=stop_end,
                original_inner_deadline_monotonic=inner_deadline,stop_wait_limit_seconds=5.,
                elapsed_stop_wait_seconds=now-stop_start,one_core_CPU_upper=upper,
                CPU_active_ceiling=active_ceiling,permitted_stopped_states=['T','t','Z'],
                exact_proved_owned_items=items,states_are_not_accepted_for_accounting=True)
            raise OwnedStopError(witness)
        time.sleep(min(.001,max(0,stop_end-now)))


def run(argv, *, cpu_seconds, wall_seconds, output_cap, passthrough=False,
        bootstrap_anchor=None, guardian_deadline=None):
    require(sys.platform == 'linux' and platform.machine() == 'x86_64', 'Linux x86_64 kernel guards required')
    require(type(cpu_seconds) is int and 2 <= cpu_seconds <= 300
            and type(wall_seconds) is int and 0 < wall_seconds <= 1800
            and type(output_cap) is int and 0 < output_cap <= 8 * 1024**3 + 16 * 1024**2 + 128,
            'finite command CPU/wall/output caps required')
    require(argv and all(type(value) is str and '\x00' not in value for value in argv), 'exact command argv required')
    prctl(36, 1)  # PR_SET_CHILD_SUBREAPER, only this new isolated supervisor.
    prctl(4, 0)   # Child commands cannot ptrace this cancellation authority.
    core = min(os.sched_getaffinity(0)); os.sched_setaffinity(0, {core})
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    old = resource.getrlimit(resource.RLIMIT_CPU)
    hard = cpu_seconds if old[1] == resource.RLIM_INFINITY else min(cpu_seconds, old[1])
    resource.setrlimit(resource.RLIMIT_CPU, (hard, hard))
    ticks = os.sysconf('SC_CLK_TCK'); start = time.monotonic()
    own_start = process_record(os.getpid())['start_ticks'] / ticks
    lifetime = time.clock_gettime(time.CLOCK_BOOTTIME) - own_start
    deadline = min(start + wall_seconds, start + max(0, wall_seconds - lifetime))
    if GUARD_SHARED is not None:
        validate_bootstrap_anchor(bootstrap_anchor, core, ticks, time.monotonic())
        require(type(guardian_deadline) is float and math.isfinite(guardian_deadline),
                'original guardian wall deadline required')
        deadline = min(deadline, guardian_deadline - 3.)
        require(time.monotonic() < deadline, 'original inner wall exhausted before command spawn')
    # Leave at least one full CPU-second for conservative whole-tick SELF
    # backstops and publication/drain. This is a stop reserve, never a refund.
    active_ceiling = cpu_seconds - 1.25 - 2 / ticks
    require(active_ceiling > 0, 'command CPU too small for aggregate accounting reserve')
    child = subprocess.Popen(argv, stdin=None if passthrough else subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, preexec_fn=lambda: child_guard(core))
    leader = process_record(child.pid)
    require(leader['uid'] == os.getuid() and leader['pgid'] == leader['sid'] == child.pid,
            'fresh own session/PGID not established')
    sid = child.pid; uid = os.getuid(); reaped_cpu = 0.; reaped = []; status = None
    selector = selectors.DefaultSelector(); captured = {'stdout': bytearray(), 'stderr': bytearray()}
    pending = {'stdout': bytearray(), 'stderr': bytearray()}; counts = {'stdout': 0, 'stderr': 0}
    for name, stream in (('stdout', child.stdout), ('stderr', child.stderr)):
        os.set_blocking(stream.fileno(), False); selector.register(stream, selectors.EVENT_READ, name)
    old_blocking = {}
    if passthrough:
        for name, fd in (('stdout', 1), ('stderr', 2)):
            old_blocking[name] = os.get_blocking(fd); os.set_blocking(fd, False)
    reason = None; max_cpu = 0.; max_rounding = 0.; killed = False; completed = False
    max_stop_wait = 0.; proved_snapshots = 0
    last_snapshot_cpu=None;last_snapshot_anchor=None
    birth_ticks=(struct.unpack('Q',GUARD_SHARED[72:80])[0] if GUARD_SHARED is not None
                 else process_record(os.getpid())['start_ticks'])
    require(birth_ticks>0,'owned process birth required before stop CPU proof')

    def group_signal(value):
        # seccomp prevents descendants changing SID/PGID or joining an older
        # session. The leader PID/start/UID was proved before any signal.
        try:
            witness = process_record(sid)
            require(witness['uid'] == uid and witness['pgid'] == witness['sid'] == sid
                    and witness['start_ticks'] == leader['start_ticks'], 'leader identity changed before owned signal')
        except (FileNotFoundError, ProcessLookupError):
            witnesses = session_records(sid, leader['start_ticks'], uid, core, enforce_count=False)
            if not witnesses: return
        try: os.killpg(sid, value)
        except ProcessLookupError: pass

    def reap():
        nonlocal reaped_cpu, status
        while True:
            if GUARD_SHARED is not None:
                GUARD_SHARED[64:72] = struct.pack('d', time.monotonic())
            try: pid, code, usage = os.wait4(-1, os.WNOHANG)
            except ChildProcessError: break
            if not pid: break
            reaped_cpu += usage.ru_utime + usage.ru_stime
            reaped.append(dict(pid=pid, CPU_seconds=usage.ru_utime + usage.ru_stime,
                               returncode=os.waitstatus_to_exitcode(code)))
            if pid == child.pid:
                status = os.waitstatus_to_exitcode(code); child.returncode = status

    def snapshot_group():
        nonlocal max_rounding,max_stop_wait,proved_snapshots,last_snapshot_cpu,last_snapshot_anchor
        stop_start=time.monotonic()
        group_signal(signal.SIGSTOP)
        def heartbeat(now):
            if GUARD_SHARED is not None:GUARD_SHARED[64:72]=struct.pack('d',now)
        _,waited=await_owned_stop(lambda:session_records(sid,leader['start_ticks'],uid,core),
            stop_start=stop_start,inner_deadline=deadline,active_ceiling=active_ceiling,
            cpu_upper=lambda now:one_core_stop_upper(last_snapshot_cpu,last_snapshot_anchor,birth_ticks,ticks,now,
                bootstrap_anchor=bootstrap_anchor,core=core),
            heartbeat=heartbeat,killed=lambda:killed,context=dict(monitor_affinity=[core],session_id=sid,
                leader_start_ticks=leader['start_ticks'],uid=uid,proved_prior_snapshots=proved_snapshots,
                last_proved_CPU_upper=last_snapshot_cpu,last_proved_monotonic_anchor=last_snapshot_anchor,
                initial_guardian_or_monitor_birth_ticks=birth_ticks,monitor_lifetime_wall_at_entry=lifetime,
                bootstrap_anchor_CPU_upper=None if bootstrap_anchor is None else bootstrap_anchor[7],
                bootstrap_anchor_monotonic=None if bootstrap_anchor is None else bootstrap_anchor[6],
                inherited_waited_CPU_seconds=0. if bootstrap_anchor is None else bootstrap_anchor[8],
                inherited_waited_CPU_upper=0. if bootstrap_anchor is None else bootstrap_anchor[9],
                initial_bound_source='PRE_FIRST_FORK_CPU_COUNTER_PLUS_ONE_CORE_WALL' if bootstrap_anchor is not None else 'LEGACY_BIRTH_WALL'))
        max_stop_wait=max(max_stop_wait,waited)
        accounting_anchor=time.monotonic()  # BEFORE every counter/accounting read.
        reap()
        items = session_records(sid, leader['start_ticks'], uid, core)
        require(all(item['state'] in ('T','t','Z') for item in items),'owned accounting state changed after stop proof')
        own = resource.getrusage(resource.RUSAGE_SELF)
        # Group is stopped. Each live process's waited_ticks describes only
        # already-reaped, absent descendants. Orphans reaped by this supervisor
        # are absent from that set and counted exactly once via wait4 usage.
        guardian_cpu,guardian_rounding=guardian_self_upper(core,ticks,bootstrap_anchor=bootstrap_anchor)
        rounding = 4 * len(items) / ticks+guardian_rounding; max_rounding = max(max_rounding, rounding)
        cpu = own.ru_utime + own.ru_stime + guardian_cpu + reaped_cpu + rounding + sum(
            item['own_ticks'] + item['waited_ticks'] for item in items) / ticks
        # guardian_cpu already includes its two-tick rounding above.
        cpu-=guardian_rounding
        last_snapshot_cpu=cpu;last_snapshot_anchor=accounting_anchor
        proved_snapshots+=1
        return items, cpu

    def expired(*_):
        nonlocal reason, killed
        reason = reason or 'WALL_BOUNDARY'; group_signal(signal.SIGKILL); killed = True
    signal.signal(signal.SIGALRM, expired); signal.signal(signal.SIGXCPU, expired)
    signal.setitimer(signal.ITIMER_REAL, max(.001, deadline - time.monotonic()))
    try:
        while True:
            if GUARD_SHARED is not None and os.getppid() != struct.unpack('Q', GUARD_SHARED[40:48])[0]:
                reason = 'GUARDIAN_EXITED'; group_signal(signal.SIGKILL); killed = True
            items, cpu = snapshot_group(); max_cpu = max(max_cpu, cpu)
            if not killed and (cpu >= active_ceiling or time.monotonic() >= deadline):
                reason = 'AGGREGATE_CPU_BOUNDARY' if cpu >= active_ceiling else 'WALL_BOUNDARY'
                group_signal(signal.SIGKILL); killed = True
            if not killed and items: group_signal(signal.SIGCONT)
            for key, _ in selector.select(.01):
                name = key.data
                if passthrough and len(pending[name]) >= 65536: continue
                try: block = os.read(key.fd, 32768)
                except BlockingIOError: continue
                if not block:
                    selector.unregister(key.fileobj); continue
                counts[name] += len(block)
                if counts[name] > output_cap:
                    reason = 'OUTPUT_BOUNDARY'; group_signal(signal.SIGKILL); killed = True
                elif passthrough: pending[name].extend(block)
                else: captured[name].extend(block)
            if passthrough:
                for name, fd in (('stdout', 1), ('stderr', 2)):
                    if not pending[name]: continue
                    try: written = os.write(fd, pending[name])
                    except BlockingIOError: written = 0
                    del pending[name][:written]
            reap()
            if not items and status is not None and not selector.get_map() and not any(pending.values()): break
            if killed and time.monotonic() > deadline + 3:
                raise RuntimeError('owned group drain/reap deadline exceeded; no complete accounting')
        reap(); remaining = session_records(sid, leader['start_ticks'], uid, core)
        require(not remaining and status is not None, 'owned descendants remain; no completed command')
        own = resource.getrusage(resource.RUSAGE_SELF)
        inherited_history = 0. if bootstrap_anchor is None else bootstrap_anchor[8]
        actual = own.ru_utime + own.ru_stime + reaped_cpu + inherited_history
        # Kernel SELF hard limit is reduced by every reaped descendant before
        # final receipt publication; a fork cannot multiply the remaining cap.
        self_cap = inherited_monitor_SELF_cap(cpu_seconds,reaped_cpu,bootstrap_anchor)
        require(self_cap >= 1 and own.ru_utime + own.ru_stime < self_cap,
                'no conservative aggregate CPU left for final receipt')
        resource.setrlimit(resource.RLIMIT_CPU, (min(hard, self_cap), min(hard, self_cap)))
        require(actual < cpu_seconds, 'aggregate CPU grant exhausted')
        completed = True
        return dict(returncode=status if reason is None else 124, command_returncode=status,
            stdout=bytes(captured['stdout']).decode(errors='replace'), stderr=bytes(captured['stderr']).decode(errors='replace'),
            cap_reason=reason, aggregate_CPU_seconds=actual, conservative_max_snapshot_CPU=max_cpu,
            CPU_limit=cpu_seconds, CPU_active_ceiling=active_ceiling, wall_seconds=time.monotonic() - start,
            maximum_live_tick_rounding_seconds=max_rounding,
            maximum_stop_wait_seconds=max_stop_wait,proved_stopped_snapshots=proved_snapshots,
            guardian_CPU_snapshot_source='OWNED_PROC_SELF_TICKS_PLUS_TWO_ROUNDING_TICKS',
            initial_bound_source='PRE_FIRST_FORK_CPU_COUNTER_PLUS_ONE_CORE_WALL' if bootstrap_anchor is not None else 'LEGACY_BIRTH_WALL',
            bootstrap_anchor=None if bootstrap_anchor is None else dict(
                tag=bootstrap_anchor[0],guardian_pid=bootstrap_anchor[1],guardian_birth_ticks=bootstrap_anchor[2],
                uid=bootstrap_anchor[3],affinity=[bootstrap_anchor[4]],clock_ticks=bootstrap_anchor[5],
                monotonic_before_counter=bootstrap_anchor[6],startup_CPU_upper=bootstrap_anchor[7],
                sample_fingerprint=bootstrap_anchor[10],counter_rounding_seconds=2/ticks,
                inherited_waited_CPU_seconds=bootstrap_anchor[8],inherited_waited_CPU_upper=bootstrap_anchor[9]),
            inherited_waited_CPU_seconds=inherited_history,
            inherited_waited_CPU_upper=0. if bootstrap_anchor is None else bootstrap_anchor[9],
            guardian_inherited_history_source='IMMUTABLE_PRE_FIRST_FORK_RUSAGE_CHILDREN',
            session_id=sid, leader_start_ticks=leader['start_ticks'], uid=uid, affinity=[core],
            reaped=reaped, all_owned_descendants_reaped=True, kernel_escape_filter=True,
            orphan_subreaper=True, counters_are_attribution_not_another_charge=True)
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        if not completed:
            group_signal(signal.SIGKILL)
            end = time.monotonic() + 2
            while time.monotonic() < end:
                reap()
                if not session_records(sid, leader['start_ticks'], uid, core, enforce_count=False): break
                time.sleep(.01)
        selector.close(); child.stdout.close(); child.stderr.close()
        for name, fd in (('stdout', 1), ('stderr', 2)):
            if name in old_blocking: os.set_blocking(fd, old_blocking[name])


def guarded_run(command, args):
    """Independent ancestor guardian survives an inner monitor crash.

    Conversely, the monitor detects loss of its guardian and drains its own
    command. A command publishes immutable SID/start/UID before exec/fork.
    """
    global GUARD_SHARED
    require(args.wall >= 4, 'funded command wall must include three-second drain reserve')
    prctl(36, 1); prctl(4, 0)
    GUARD_SHARED = mmap.mmap(-1, 128)
    GUARD_SHARED[40:48] = struct.pack('Q', os.getpid())
    GUARD_SHARED[72:80] = struct.pack('Q',process_record(os.getpid())['start_ticks'])
    GUARD_SHARED[64:72] = struct.pack('d', time.monotonic())
    core = min(os.sched_getaffinity(0)); os.sched_setaffinity(0, {core})
    old = resource.getrlimit(resource.RLIMIT_CPU)
    ceiling = args.cpu if old[1] == resource.RLIM_INFINITY else min(args.cpu, old[1])
    resource.setrlimit(resource.RLIMIT_CPU, (ceiling, ceiling))
    own = resource.getrusage(resource.RUSAGE_SELF)
    GUARD_SHARED[32:40] = struct.pack('d', own.ru_utime + own.ru_stime)
    start = time.monotonic(); ticks = os.sysconf('SC_CLK_TCK')
    startup_lifetime = time.clock_gettime(time.CLOCK_BOOTTIME) - struct.unpack('Q', GUARD_SHARED[72:80])[0] / ticks
    deadline = start + max(0., args.wall - startup_lifetime)
    pid = None; monitor_usage = None; status = None; forced = False
    with tempfile.TemporaryFile(mode='w+b') as receipt:
        bootstrap_anchor = pre_fork_cpu_anchor(core, ticks)
        require(bootstrap_anchor[7] < args.cpu - 1.25 - 2/ticks,
                'startup CPU exhausts original active command allowance')
        require(time.monotonic() < deadline - 3.,
                'startup wall leaves no original three-second drain reserve')
        # No monitor exists before this first fork. Start its progress clock
        # now; the original absolute wall deadline and CPU anchor do not move.
        GUARD_SHARED[64:72] = struct.pack('d', time.monotonic())
        pid = os.fork()
        if pid == 0:
            GUARD_SHARED[48:56] = struct.pack('Q', os.getpid())
            try:
                value = run(command, cpu_seconds=args.cpu, wall_seconds=args.wall - 3,
                            output_cap=args.output_cap, passthrough=args.passthrough,
                            bootstrap_anchor=bootstrap_anchor, guardian_deadline=deadline)
                receipt.write(json.dumps(value, sort_keys=True).encode()); receipt.flush()
                os._exit(value['returncode'])
            except BaseException as exc:
                failure={'returncode':125,'cap_reason':type(exc).__name__+': '+str(exc)}
                if isinstance(exc,OwnedStopError):failure['owned_stop_witness']=exc.witness
                receipt.write(json.dumps(failure,allow_nan=False).encode())
                receipt.flush(); os._exit(125)
        monitor = process_record(pid)
        while True:
            own = resource.getrusage(resource.RUSAGE_SELF)
            GUARD_SHARED[32:40] = struct.pack('d', own.ru_utime + own.ru_stime)
            if struct.unpack('Q', GUARD_SHARED[24:32])[0] == 1 and struct.unpack('Q', GUARD_SHARED[56:64])[0] == 0:
                sid, expected_start, uid = struct.unpack('QQQ', GUARD_SHARED[0:24])
                candidate = process_record(sid)
                require(candidate['uid'] == uid == os.getuid() and candidate['sid'] == candidate['pgid'] == sid
                        and candidate['start_ticks'] == expected_start, 'guardian startup ownership acknowledgement failed')
                GUARD_SHARED[56:64] = struct.pack('Q', 1)
            got, code, usage = os.wait4(pid, os.WNOHANG)
            if got:
                monitor_usage = usage; status = os.waitstatus_to_exitcode(code); break
            stale = (struct.unpack('Q', GUARD_SHARED[56:64])[0] == 1
                     and time.monotonic() - struct.unpack('d', GUARD_SHARED[64:72])[0] > 1)
            if not forced and (time.monotonic() >= deadline - 2 or stale
                               or guardian_SELF_boundary(args.cpu, own.ru_utime+own.ru_stime, bootstrap_anchor)):
                current = process_record(pid)
                require(current['uid'] == os.getuid() and current['start_ticks'] == monitor['start_ticks']
                        and current['ppid'] == os.getpid(), 'guardian monitor identity changed')
                os.kill(pid, signal.SIGKILL); forced = True
            time.sleep(.01)
        def pairs(items):
            value = {}
            for key, item in items:
                require(key not in value, 'duplicate guardian receipt key'); value[key] = item
            return value
        def bad(value): raise RuntimeError('nonfinite guardian receipt: ' + value)
        try:
            receipt.seek(0); limit = 2 * min(args.output_cap, 16777216) + 262144
            before = os.fstat(receipt.fileno()); raw = receipt.read(limit + 1)
            require(len(raw) <= limit and len(raw) == before.st_size, 'bounded complete guardian receipt required')
            value = json.loads(raw, object_pairs_hook=pairs, parse_constant=bad) if raw else {'returncode': 125, 'cap_reason': 'MONITOR_EXITED_WITHOUT_RECEIPT'}
            require(type(value) is dict, 'guardian receipt object required')
        except BaseException as exc:
            value = {'returncode': 125, 'cap_reason': 'INVALID_MONITOR_RECEIPT: ' + str(exc)}
        successful_drain = (value.get('all_owned_descendants_reaped') is True
                            and type(value.get('returncode')) is int and value['returncode'] == status
                            and not children_of(os.getpid()))
        adopted_cpu = 0.; adopted = []
        if not successful_drain:
            drain_end = min(deadline, time.monotonic() + 2)
            while time.monotonic() < drain_end:
                # Publication is checked throughout drain. Before publication,
                # adopted pre-exec children cannot pass the acknowledgement.
                if struct.unpack('Q', GUARD_SHARED[24:32])[0] == 1:
                    sid, expected_start, uid = struct.unpack('QQQ', GUARD_SHARED[0:24])
                    items = session_records(sid, expected_start, uid, min(os.sched_getaffinity(0)), enforce_count=False)
                    if items: os.killpg(sid, signal.SIGKILL)
                else:
                    for adopted_pid in children_of(os.getpid()):
                        item = process_record(adopted_pid)
                        require(item['ppid'] == os.getpid() and item['uid'] == os.getuid()
                                and item['start_ticks'] >= monitor['start_ticks'], 'unpublished adopted child provenance changed')
                        os.kill(adopted_pid, signal.SIGKILL)
                try: got, code, usage = os.wait4(-1, os.WNOHANG)
                except ChildProcessError: break
                if not got:
                    time.sleep(.01); continue
                adopted_cpu += usage.ru_utime + usage.ru_stime
                adopted.append(got)
            require(not children_of(os.getpid()), 'guardian cannot prove owned orphan drain')
            value.update(returncode=125, cap_reason=value.get('cap_reason') or 'MONITOR_ABNORMAL_EXIT',
                         all_owned_descendants_reaped=True, guardian_adopted=adopted)
        own = resource.getrusage(resource.RUSAGE_SELF)
        # Fork resets the monitor's waited history. Its wait4 usage contains
        # new descendants, not guardian C0; add that prior history exactly once.
        aggregate = (bootstrap_anchor[8] + own.ru_utime + own.ru_stime
                     + monitor_usage.ru_utime + monitor_usage.ru_stime + adopted_cpu)
        require(aggregate < args.cpu, 'complete guardian/monitor/command CPU grant exhausted')
        value.update(aggregate_CPU_seconds=aggregate, guardian_included_in_CPU=True,
                     inherited_waited_CPU_seconds=bootstrap_anchor[8],
                     inherited_waited_CPU_upper=bootstrap_anchor[9],
                     inherited_waited_history_included_once=True,
                     independent_guardian=True, guardian_forced_monitor_stop=forced,
                     guardian_nondumpable=True,
                     guarded_run_wall_seconds=time.monotonic() - start,
                     guardian_startup_lifetime_seconds=startup_lifetime,
                     complete_lifecycle_wall_seconds=time.clock_gettime(time.CLOCK_BOOTTIME)
                        - struct.unpack('Q', GUARD_SHARED[72:80])[0]/ticks)
        if not args.passthrough: print(json.dumps(value, sort_keys=True))
        return value['returncode']


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cpu', type=int, required=True); parser.add_argument('--wall', type=int, required=True)
    parser.add_argument('--output-cap', type=int, required=True); parser.add_argument('--passthrough', action='store_true')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args(argv); command = args.command
    if command[:1] == ['--']: command = command[1:]
    return guarded_run(command, args)


if __name__ == '__main__':
    raise SystemExit(main())
