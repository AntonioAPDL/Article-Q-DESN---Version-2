#!/usr/bin/env python3
"""Fail-closed supervisor for ONE newly admitted, disposable direct child.

No model code, target data, grants, scheduling, or baseline-process signals.
The caller supplies reviewed authority, holds the global exclusive flock, and
must retain that lock until this function reports reaped AND drained.
"""
import ctypes
import datetime
import errno
import fcntl
import hashlib
import math
import os
from pathlib import Path
import resource
import shutil
import signal
import stat
import subprocess
import threading
import time

PAIR = frozenset({30, 62})
GIB = 1024 ** 3
_UNREAPED = []  # retain Popen ownership after an uninterruptible-child failure


class GuardError(RuntimeError):
    pass


def _absent(path):
    """Fresh absence only; PermissionError is deliberately not swallowed."""
    try:
        Path(path).stat()
    except FileNotFoundError:
        return True
    return False


def proc_stat(pid, proc_root=Path('/proc')):
    text = (Path(proc_root) / str(pid) / 'stat').read_text()
    left, right = text.find('('), text.rfind(')')
    if left < 0 or right < left:
        raise GuardError('malformed process stat')
    f = text[right + 2:].split()
    return dict(pid=int(text[:left].strip()), comm=text[left + 1:right],
                state=f[0], ppid=int(f[1]), start_ticks=int(f[19]),
                own_ticks=int(f[11]) + int(f[12]),
                reaped_descendant_ticks=int(f[13]) + int(f[14]))


def boot_id(proc_root=Path('/proc')):
    return (Path(proc_root) / 'sys/kernel/random/boot_id').read_text().strip()


def physical_pair():
    raw = Path('/sys/devices/system/cpu/cpu30/topology/thread_siblings_list').read_text().strip()
    cpus = set()
    for part in raw.split(','):
        ends = part.split('-')
        cpus.update(range(int(ends[0]), int(ends[-1]) + 1))
    if cpus != PAIR:
        raise GuardError('reviewed physical topology differs from {30,62}')
    return cpus


def _threads(process, affinity_reader):
    rows = []
    for thread in (process / 'task').iterdir():
        if not thread.name.isdigit():
            continue
        try:
            rows.append((int(thread.name), set(affinity_reader(int(thread.name)))))
        except (FileNotFoundError, ProcessLookupError):
            if not _absent(thread):
                raise GuardError('thread observation failed while still present')
    if not rows:
        raise GuardError('present process has no observable threads')
    return rows


def _same_lifetime(row, owned):
    return (row['pid'] == owned['pid'] and row['start_ticks'] == owned['start_ticks']
            and row['ppid'] == owned['ppid'])


def physical_peer_guard(census, disk_path, owned_identity=None, *,
                        proc_root=Path('/proc'), affinity_reader=os.sched_getaffinity,
                        resource_reader=None, verify_topology=True):
    """Inspect all same-UID processes, including the unused physical sibling.

    Census is already hash-bound by the caller. Its reviewed entries bind PID,
    start ticks, command hash, boot and allowed states. Only this observer and
    the exact live direct child can be excluded. Unknown Python/R/script peers
    intersecting either physical sibling reject. Permission errors always fail.
    Test-only injected proc/resources do not change production defaults.
    """
    if verify_topology:
        physical_pair()
    proc_root = Path(proc_root)
    boot = boot_id(proc_root)
    entries = census['allowed_intersecting_processes']
    known = {int(x['pid']): x for x in entries}
    if len(known) != len(entries) or any(x['boot_id'] != boot for x in entries):
        raise GuardError('census duplicate PID or boot mismatch')
    if owned_identity is not None:
        if owned_identity.get('boot_id') != boot or owned_identity.get('ppid') != os.getpid():
            raise GuardError('owned exclusion is not this observer direct child')
    observed, gone = [], []
    for process in proc_root.iterdir():
        if not process.name.isdigit():
            continue
        pid = int(process.name)
        if pid == os.getpid():
            continue
        try:
            if process.stat().st_uid != os.getuid():
                continue  # explicit census scope, not a permission-error omission
            row = proc_stat(pid, proc_root)
            if owned_identity is not None and pid == owned_identity['pid']:
                if not _same_lifetime(row, owned_identity):
                    raise GuardError('owned child exclusion lifetime changed')
                continue
            if row['state'] in ('Z', 'X', 'x'):
                continue
            threads = _threads(process, affinity_reader)
            intersects = any(mask & PAIR for _, mask in threads)
            entry = known.get(pid)
            if not intersects and entry is None:
                continue
            command = (process / 'cmdline').read_bytes()
            row['cmdline_sha256'] = hashlib.sha256(command).hexdigest()
            if entry is not None:
                if (row['start_ticks'] != entry['start_ticks'] or
                        row['cmdline_sha256'] != entry['cmdline_sha256'] or
                        row['state'] not in entry['allowed_states']):
                    raise GuardError('reviewed peer identity/state changed: ' + str(pid))
            elif intersects:
                # Kernel threads have empty command lines and no exe. Permission
                # errors are never interpreted as kernel-thread evidence.
                executable = '' if not command else Path(os.readlink(process / 'exe')).name
                argv = [x.decode(errors='replace') for x in command.split(b'\0') if x]
                numerical = (row['comm'] in ('R', 'Rscript') or
                             'python' in executable.lower() or
                             any(x.endswith(('.py', '.R', '.r')) for x in argv) or
                             any(marker in ' '.join(argv) for marker in census.get('numerical_markers', [])))
                if numerical:
                    raise GuardError('unknown numerical peer intersects CPU30/SMT62: ' + str(pid))
            after = proc_stat(pid, proc_root)
            if (not _same_lifetime(after, row) or
                    (entry is not None and after['state'] not in entry['allowed_states'])):
                raise GuardError('peer changed during observation: ' + str(pid))
            observed.append(dict(pid=pid, start_ticks=row['start_ticks'], state=row['state'],
                                 cmdline_sha256=row['cmdline_sha256'],
                                 intersects_physical_pair=intersects))
        except (FileNotFoundError, ProcessLookupError):
            if not _absent(process):
                raise GuardError('process observation failed while still present: ' + str(pid))
            gone.append(pid)
    if resource_reader is None:
        available = int(next(x.split()[1] for x in (proc_root / 'meminfo').read_text().splitlines()
                             if x.startswith('MemAvailable:'))) * 1024
        free = shutil.disk_usage(disk_path).free
    else:
        available, free = resource_reader()
    if available < 192 * GIB or free < 80 * GIB:
        raise GuardError('Muscat RAM192GiB/disk80GiB floor failed')
    return dict(observed_epoch=time.time(), physical_pair=sorted(PAIR),
                own_science_affinity=[30], SMT62_science_authorized=False,
                boot_id=boot, peers=observed, freshly_gone_pids=gone,
                RAM_available_bytes=available, disk_free_bytes=free)


def verify_held_flock(fd):
    """Require an exclusive caller-owned FLOCK, not just an open lock file."""
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode):
        raise GuardError('global permit FD is not a regular lock file')
    found = False
    for line in Path('/proc/locks').read_text().splitlines():
        words = line.split()
        if len(words) < 8 or words[1] != 'FLOCK' or words[3] != 'WRITE':
            continue
        device = words[5].split(':')
        if (int(words[4]) == os.getpid() and len(device) == 3 and
                int(device[0], 16) == os.major(info.st_dev) and
                int(device[1], 16) == os.minor(info.st_dev) and
                int(device[2]) == info.st_ino):
            found = True
    if not found:
        raise GuardError('exclusive global permit flock is not held by this caller')
    return dict(fd=fd, device=info.st_dev, inode=info.st_ino, holder_pid=os.getpid())


def _cpu_usage():
    own = resource.getrusage(resource.RUSAGE_SELF)
    child = resource.getrusage(resource.RUSAGE_CHILDREN)
    return own.ru_utime + own.ru_stime, child.ru_utime + child.ru_stime


def deny_subprocess_creation():
    """Irreversible NEW-child-only Linux x86_64 seccomp boundary.

    A periodic observer cannot prove that an unobserved fork did not escape.
    Deny process creation at the kernel boundary instead. Ordinary thread
    clone is allowed; clone3 returns ENOSYS so pthreads use checked clone.
    Unsupported kernels/architectures fail before executing the target.
    """
    if os.uname().machine != 'x86_64':
        raise GuardError('subprocess boundary supports reviewed Linux x86_64 only')
    class Instruction(ctypes.Structure):
        _fields_ = [('code', ctypes.c_ushort), ('jt', ctypes.c_ubyte),
                    ('jf', ctypes.c_ubyte), ('k', ctypes.c_uint32)]
    class Program(ctypes.Structure):
        _fields_ = [('length', ctypes.c_ushort), ('filter', ctypes.POINTER(Instruction))]
    allow, kill = 0x7fff0000, 0x80000000
    denied, unavailable = 0x00050000 | errno.EPERM, 0x00050000 | errno.ENOSYS
    # seccomp_data: nr offset0, arch offset4, args[0] offset16. AUDIT_ARCH_X86_64.
    rows = [(0x20, 0, 0, 4), (0x15, 1, 0, 0xc000003e), (0x06, 0, 0, kill),
            (0x20, 0, 0, 0), (0x45, 0, 1, 0x40000000), (0x06, 0, 0, denied),
            (0x15, 0, 1, 57), (0x06, 0, 0, denied),       # fork
            (0x15, 0, 1, 58), (0x06, 0, 0, denied),       # vfork
            (0x15, 0, 1, 435), (0x06, 0, 0, unavailable), # clone3 fallback
            (0x15, 0, 3, 56), (0x20, 0, 0, 16),          # clone flags
            (0x45, 1, 0, 0x10000), (0x06, 0, 0, denied),  # CLONE_THREAD only
            (0x06, 0, 0, allow)]
    instructions = (Instruction * len(rows))(*(Instruction(*row) for row in rows))
    program = Program(len(rows), instructions)
    libc = ctypes.CDLL(None, use_errno=True)
    if (libc.prctl(38, 1, 0, 0, 0) != 0 or
            libc.prctl(22, 2, ctypes.byref(program), 0, 0) != 0):
        raise GuardError('cannot install mandatory no-subprocess seccomp boundary')


def _live_tree(identity):
    """Cheap owned-TGID accounting under mandatory no-process-creation filter.

    Never scan global /proc in the <=1s hot path. The kernel filter forbids
    fork/vfork/non-thread clone; inspect every owned thread's children file as
    an independent fail-closed check. Full peer census is separately timed.
    """
    root = proc_stat(identity['pid'])
    if not _same_lifetime(root, identity):
        raise GuardError('owned direct child lifetime/parent changed')
    descendants = []
    for task in (Path('/proc')/str(identity['pid'])/'task').iterdir():
        try:
            for value in (task/'children').read_text().split():
                descendants.append(proc_stat(int(value)))
        except (FileNotFoundError, ProcessLookupError):
            if not _absent(task):
                raise GuardError('owned thread child observation failed while it exists')
    ticks = root['own_ticks'] + root['reaped_descendant_ticks']
    return ticks / os.sysconf('SC_CLK_TCK'), descendants


def run_owned(command, *, env, stdout, stderr, preexec_fn, pass_fds,
              lock_fd, wall_seconds, maximum_combined_CPU_seconds,
              absolute_deadline_UTC, peer_check_callback,
              expected_child_affinity=frozenset({30}), interval_seconds=1.0,
              peer_interval_seconds=1.0, maximum_administrative_CPU_seconds=None,
              kill_grace_seconds=10.0):
    """Run one new child; return an immutable-receipt-ready plain dict.

    Combined CPU includes *all* this controller's CPU since startup, its prior
    reaped administrative children and the new child tree. Caller grants must
    fund that exact meaning. callback receives None preflight, then an exact
    held direct-child identity during execution. No generic PID stop API exists.
    Only this function's unreaped direct child may receive SIGKILL. Never call
    Popen.poll/wait/communicate concurrently or install another child reaper.
    """
    if threading.active_count() != 1 or signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL:
        raise GuardError('exclusive wait4 ownership requires single thread/default SIGCHLD')
    if not callable(peer_check_callback) or not callable(preexec_fn):
        raise GuardError('reviewed preexec and periodic peer callback required')
    if lock_fd not in pass_fds or not command or isinstance(command, (str, bytes)):
        raise GuardError('argument vector and inherited global lock FD required')
    for value in (wall_seconds, maximum_combined_CPU_seconds, interval_seconds, peer_interval_seconds, kill_grace_seconds):
        if isinstance(value, bool) or not math.isfinite(value) or value <= 0:
            raise GuardError('invalid positive guard limit')
    if interval_seconds > 1 or peer_interval_seconds > 10 or kill_grace_seconds > 10:
        raise GuardError('periodic guard interval/grace exceeds reviewed bound')
    if maximum_administrative_CPU_seconds is not None and (isinstance(maximum_administrative_CPU_seconds, bool) or not math.isfinite(maximum_administrative_CPU_seconds) or maximum_administrative_CPU_seconds <= 0):
        raise GuardError('invalid administrative CPU reserve')
    deadline = datetime.datetime.fromisoformat(absolute_deadline_UTC)
    if deadline.tzinfo is None:
        raise GuardError('absolute deadline must contain timezone')
    deadline_epoch = deadline.timestamp()
    lock = verify_held_flock(lock_fd)
    census_costs = []
    def observe_peer(identity):
        before_cpu = sum(_cpu_usage()); before_wall = time.monotonic()
        observation = peer_check_callback(identity)
        census_costs.append(dict(CPU_seconds=sum(_cpu_usage())-before_cpu,
                                wall_seconds=time.monotonic()-before_wall))
        return observation
    initial_observation = observe_peer(None)
    before_self, before_children = _cpu_usage()
    if before_self + before_children >= maximum_combined_CPU_seconds:
        raise GuardError('combined CPU already exhausted before launch')
    if maximum_administrative_CPU_seconds is not None and before_self + before_children >= maximum_administrative_CPU_seconds:
        raise GuardError('administrative CPU already exhausted before launch')
    if time.time() >= deadline_epoch:
        raise GuardError('absolute global/stage deadline expired before launch')
    parent, boot = os.getpid(), boot_id()
    proof_read, proof_write = os.pipe2(os.O_CLOEXEC)

    def guarded_preexec():
        libc = ctypes.CDLL(None, use_errno=True)
        if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0 or os.getppid() != parent:
            os._exit(125)
        # Popen waits for exec before returning. A private-child wall timer also
        # bounds reviewed preexec setup; it never targets another process.
        signal.signal(signal.SIGALRM, signal.SIG_DFL)
        signal.setitimer(signal.ITIMER_REAL, max(0.001, min(
            wall_seconds - (time.monotonic() - started), deadline_epoch - time.time())))
        try:
            deny_subprocess_creation()
        except Exception:
            os._exit(125)
        preexec_fn()
        actual = ctypes.c_int()
        if (libc.prctl(2, ctypes.byref(actual), 0, 0, 0) != 0 or
                actual.value != signal.SIGKILL or os.getppid() != parent or
                set(os.sched_getaffinity(0)) != set(expected_child_affinity) or
                os.fstat(lock_fd).st_ino != lock['inode'] or
                os.fstat(lock_fd).st_dev != lock['device']):
            os._exit(125)
        signal.signal(signal.SIGALRM, signal.SIG_DFL)
        signal.setitimer(signal.ITIMER_REAL, max(0.001, min(
            wall_seconds - (time.monotonic() - started), deadline_epoch - time.time())))
        os.write(proof_write, b'PDEATH_LOCK_AFFINITY_SECCOMP_READY_V1')
        os.close(proof_write)  # target cannot forge the pre-exec kernel proof

    started = time.monotonic()
    last_peer_time = started
    try:
        process = subprocess.Popen(command, env=env, stdout=stdout, stderr=stderr,
                                   preexec_fn=guarded_preexec,
                                   pass_fds=tuple(set(pass_fds) | {proof_write}), close_fds=True)
    except BaseException:
        os.close(proof_read)
        raise
    finally:
        os.close(proof_write)
    try:
        kernel_boundary_proved = os.read(proof_read, 128) == b'PDEATH_LOCK_AFFINITY_SECCOMP_READY_V1'
    finally:
        os.close(proof_read)
    identity = None
    reason = None if kernel_boundary_proved else 'CHILD_KERNEL_BOUNDARY_NOT_PROVED'
    error, reaped, usage, code = None, False, None, None
    signalled, observations, descendant_seen, descendants = False, 0, False, {}
    ownership_lost = False
    maximum_live_CPU = 0.0
    last_observation = initial_observation
    kill_started = None
    try:
        row = proc_stat(process.pid)
        if row['ppid'] != parent:
            raise GuardError('Popen child is no longer this observer direct child')
        identity = dict(pid=process.pid, start_ticks=row['start_ticks'], ppid=parent, boot_id=boot)
        while True:
            # WNOHANG is the sole reaper. Until a successful wait4, the kernel
            # retains this direct child's PID even after exit (zombie included).
            waited, status, waited_usage = os.wait4(process.pid, os.WNOHANG)
            if waited:
                reaped, usage = True, waited_usage
                code = os.waitstatus_to_exitcode(status)
                process.returncode = code
                break
            try:
                row = proc_stat(process.pid)
                if boot_id() != boot or not _same_lifetime(row, identity):
                    raise GuardError('owned held direct child identity changed')
                masks = _threads(Path('/proc') / str(process.pid), os.sched_getaffinity)
                if any(mask != set(expected_child_affinity) for _, mask in masks):
                    raise GuardError('owned child thread affinity differs from exact grant')
                live_CPU, live_descendants = _live_tree(identity)
                maximum_live_CPU = max(maximum_live_CPU, live_CPU)
                for child in live_descendants:
                    descendants[(child['pid'], child['start_ticks'])] = child
                descendant_seen = descendant_seen or bool(live_descendants)
                if live_descendants:
                    raise GuardError('unadmitted subprocess descendant observed; only root may be stopped')
                own_CPU, reaped_CPU = _cpu_usage()
                if maximum_administrative_CPU_seconds is not None and own_CPU + reaped_CPU >= maximum_administrative_CPU_seconds:
                    reason = 'ADMINISTRATIVE_CPU_LIMIT'
                elif own_CPU + reaped_CPU + live_CPU >= maximum_combined_CPU_seconds:
                    reason = 'COMBINED_CPU_LIMIT'
                elif time.monotonic() - started >= wall_seconds:
                    reason = 'WALL_LIMIT'
                elif time.time() >= deadline_epoch:
                    reason = 'ABSOLUTE_DEADLINE'
                elif time.monotonic() - last_peer_time >= peer_interval_seconds:
                    last_observation = observe_peer(identity)
                    observations += 1
                    last_peer_time = time.monotonic()
            except Exception as exc:
                reason = reason or 'RESOURCE_OR_PEER_GUARD_FAILED'
                error = type(exc).__name__ + ': ' + str(exc)
            if reason and not signalled:
                # Re-check the precise direct-child lifetime immediately before
                # signalling. No wait, process group or generic PID path exists.
                row = proc_stat(process.pid)
                if boot_id() != boot or not _same_lifetime(row, identity):
                    raise GuardError('cannot prove exact held child for safe abort')
                os.kill(process.pid, signal.SIGKILL)
                signalled, kill_started = True, time.monotonic()
            if signalled and time.monotonic() - kill_started >= kill_grace_seconds:
                reason = 'OWNED_CHILD_NOT_REAPED_AFTER_KILL'
                break
            time.sleep(min(interval_seconds, 0.05 if signalled else interval_seconds))
    except BaseException as exc:
        # Ctrl-C/observer faults must not release the inherited permit while the
        # owned child runs. Attempt only the same precise unreaped direct child.
        reason = 'OWNERSHIP_OR_OBSERVER_FAILURE'
        ownership_lost = True
        error = type(exc).__name__ + ': ' + str(exc)
        if identity is not None and not reaped:
            try:
                row = proc_stat(process.pid)
                if boot_id() == boot and _same_lifetime(row, identity):
                    os.kill(process.pid, signal.SIGKILL)
                    signalled = True
                    end = time.monotonic() + kill_grace_seconds
                    while time.monotonic() < end:
                        waited, status, waited_usage = os.wait4(process.pid, os.WNOHANG)
                        if waited:
                            reaped, usage, code = True, waited_usage, os.waitstatus_to_exitcode(status)
                            process.returncode = code
                            break
                        time.sleep(0.01)
            except (OSError, GuardError):
                pass  # failure is recorded; NEVER signal an unproved/reused PID
    if not reaped:
        _UNREAPED.append(process)
    live_descendant_ids = []
    for key in descendants:
        try:
            row = proc_stat(key[0])
            if row['start_ticks'] == key[1] and row['state'] not in ('Z', 'X', 'x'):
                live_descendant_ids.append(dict(pid=key[0], start_ticks=key[1]))
        except (FileNotFoundError, ProcessLookupError):
            if not _absent(Path('/proc') / str(key[0])):
                live_descendant_ids.append(dict(pid=key[0], start_ticks=key[1], observation_failed=True))
        except PermissionError:
            live_descendant_ids.append(dict(pid=key[0], start_ticks=key[1], observation_failed=True))
    final_observation = None
    if reaped and not descendant_seen and not ownership_lost:
        try:
            final_observation = observe_peer(None)
        except Exception as exc:
            reason = reason or 'FINAL_RESOURCE_OR_PEER_GUARD_FAILED'
            error = type(exc).__name__ + ': ' + str(exc)
    if reason is None and time.monotonic() - started >= wall_seconds:
        reason = 'WALL_LIMIT_AFTER_REAP'
    if reason is None and time.time() >= deadline_epoch:
        reason = 'ABSOLUTE_DEADLINE_AFTER_REAP'
    own_CPU, reaped_CPU = _cpu_usage()
    child_CPU = None if usage is None else usage.ru_utime + usage.ru_stime
    if reason is None and own_CPU + reaped_CPU >= maximum_combined_CPU_seconds:
        reason = 'COMBINED_CPU_LIMIT_AFTER_REAP'
    administrative_CPU = own_CPU + reaped_CPU - (child_CPU or 0)
    if reason is None and maximum_administrative_CPU_seconds is not None and administrative_CPU >= maximum_administrative_CPU_seconds:
        reason = 'ADMINISTRATIVE_CPU_LIMIT_AFTER_REAP'
    # wait4 ru_* includes descendants reaped by this direct child. A process
    # that escaped/reparented cannot be silently claimed as fully accounted.
    complete = reaped and not descendant_seen and not ownership_lost and kernel_boundary_proved
    return dict(schema='r154_owned_stage_guard_receipt_v1',
                status='EXITED' if reason is None and reaped else 'ABORTED',
                abort_reason=reason, error=error, returncode=code,
                owned_child=identity, direct_child_kernel_held_until_wait4=not ownership_lost,
                reaped=reaped, drained=reaped and not live_descendant_ids,
                child_signalled=signalled, signal_scope='exact_owned_direct_child_only',
                inherited_global_lock=lock, child_CPU_seconds=child_CPU,
                parent_CPU_seconds_including_startup=own_CPU,
                prior_administrative_child_CPU_seconds=before_children,
                parent_CPU_seconds_during_supervision=own_CPU - before_self,
                parent_plus_all_reaped_child_CPU_seconds=reaped_CPU + own_CPU,
                administrative_CPU_seconds_including_startup_and_helpers=administrative_CPU,
                maximum_administrative_CPU_seconds=maximum_administrative_CPU_seconds,
                maximum_observed_live_tree_CPU_seconds=maximum_live_CPU,
                CPU_accounting_complete=complete,
                subprocess_creation_kernel_denied=kernel_boundary_proved,
                preexec_kernel_boundary_proved=kernel_boundary_proved,
                unadmitted_descendant_seen=descendant_seen,
                still_live_descendant_lifetimes=live_descendant_ids,
                max_child_RSS_KiB=None if usage is None else usage.ru_maxrss,
                wall_seconds=time.monotonic() - started,
                maximum_combined_CPU_seconds=maximum_combined_CPU_seconds,
                absolute_deadline_UTC=absolute_deadline_UTC,
                periodic_observations=observations,
                owned_lifetime_CPU_wall_interval_seconds=interval_seconds,
                full_peer_resource_interval_seconds=peer_interval_seconds,
                measured_peer_census_costs=census_costs,
                initial_peer_observation=initial_observation,
                final_periodic_peer_observation=last_observation,
                post_reap_peer_observation=final_observation)
