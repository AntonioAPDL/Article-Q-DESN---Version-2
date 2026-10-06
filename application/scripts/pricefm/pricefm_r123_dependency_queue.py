"""Bounded dependency scheduling and identity-safe process adoption."""
from __future__ import annotations

from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from pathlib import Path
import ctypes
import errno
import os
import platform
from queue import Queue
import signal
import time


def process_identity(pid, proc=Path("/proc")):
    folder = proc / str(pid)
    try:
        fields = (folder / "stat").read_text().rsplit(")", 1)[1].split()
        argv = (folder / "cmdline").read_bytes().decode().rstrip("\0").split("\0")
        return dict(pid=int(pid), start_ticks=int(fields[19]), state=fields[0], argv=argv)
    except (OSError, ValueError, UnicodeError):
        return None


def same_process(expected, actual):
    return actual is not None and all(actual[k] == expected[k] for k in ("pid", "start_ticks", "argv"))


def signal_exact(expected, sig):
    if not same_process(expected, process_identity(expected["pid"])):
        raise RuntimeError("process identity changed; refusing signal")
    try:
        descriptor = pidfd_open(expected["pid"])
    except OSError as error:
        if error.errno != errno.ENOSYS: raise
        # EL8's kernel has no pidfd support. Never signal a process group, and
        # recheck the full identity immediately before each legacy PID signal.
        if not same_process(expected, process_identity(expected["pid"])):
            raise RuntimeError("process identity changed before legacy PID signal")
        os.kill(expected["pid"],sig)
        return
    try:
        if not same_process(expected, process_identity(expected["pid"])):
            raise RuntimeError("process identity changed before pidfd signal")
        if hasattr(signal,"pidfd_send_signal"):
            signal.pidfd_send_signal(descriptor, sig)
        else:
            linux_syscall(424,descriptor,int(sig),0,0)
    finally:
        os.close(descriptor)


def linux_syscall(number,*args):
    if platform.system() != "Linux" or platform.machine() not in ("x86_64","aarch64"):
        raise RuntimeError("identity-safe process signaling requires supported Linux pidfds")
    libc=ctypes.CDLL(None,use_errno=True)
    libc.syscall.restype=ctypes.c_long
    result=libc.syscall(ctypes.c_long(number),*(ctypes.c_long(value) for value in args))
    if result == -1:
        error=ctypes.get_errno(); raise OSError(error,os.strerror(error))
    return result


def pidfd_open(pid):
    return os.pidfd_open(pid) if hasattr(os,"pidfd_open") else linux_syscall(434,pid,0)


def choose_cpu_pool(old_cpus,occupied,allowed,physical,busy,foreign,ceiling=15):
    if len(old_cpus)!=15 or len({physical[cpu] for cpu in old_cpus})!=15:
        raise RuntimeError("original physical-core pool differs")
    if not set(occupied)<=set(allowed) or len(occupied)>ceiling:
        raise RuntimeError("adopted core is outside the permitted budget")
    chosen=sorted(occupied); used={physical[cpu] for cpu in chosen}
    if len(used)!=len(chosen): raise RuntimeError("adopted workers share a physical core")
    if used & set(foreign): raise RuntimeError("adopted core now conflicts with another pinned task")
    for cpu in list(old_cpus)+sorted(allowed):
        group=physical[cpu]
        if len(chosen)>=ceiling: break
        if cpu not in allowed or group in used or group in foreign or busy[group]>20: continue
        chosen.append(cpu); used.add(group)
    if len(chosen)<max(3,min(ceiling,len(occupied)+2)):
        raise RuntimeError("insufficient healthy cores for ready branches and scoring")
    return sorted(chosen)


class BoundedScorer:
    """Assign a distinct available CPU to each frozen ladder-scoring call."""
    def __init__(self,callback,cpus):
        self.callback=callback; self.free=Queue()
        for cpu in cpus: self.free.put(cpu)

    def __call__(self,*args):
        cpu=self.free.get()
        try: return self.callback(*args[:-1],cpu)
        finally: self.free.put(cpu)


def validate_graph(parents):
    for key, parent in parents.items():
        seen = {key}
        while parent is not None:
            if parent not in parents or parent in seen:
                raise ValueError("dependency missing or cyclic")
            seen.add(parent)
            parent = parents[parent]


def run_dependencies(parents, completed, adopted, cpus, execute, observe=lambda value: None,
                     before_launch=lambda: None):
    """execute(key,cpu,adopted_record) returns acceptance, not merely existence."""
    validate_graph(parents)
    if not cpus or len(cpus) != len(set(cpus)):
        raise ValueError("distinct nonempty CPU pool required")
    done, rejected = set(completed), set()
    if not done <= parents.keys() or not adopted.keys() <= parents.keys() or done & adopted.keys():
        raise ValueError("completed/adopted inventory differs from graph")
    if any(parent is not None and parent not in done for key in done for parent in [parents[key]]):
        raise ValueError("completed node lacks accepted ancestor")
    occupied = [record["cpu"] for record in adopted.values()]
    if len(occupied) != len(set(occupied)) or not set(occupied) <= set(cpus):
        raise ValueError("adopted CPU assignments collide or exceed budget")
    running, submitted = {}, set(done)
    with ThreadPoolExecutor(max_workers=len(cpus)) as pool:
        def submit(key, cpu, record=None):
            if key in submitted:
                raise RuntimeError("duplicate task submission")
            submitted.add(key)
            running[pool.submit(execute, key, cpu, record)] = (key, cpu)

        for key, record in adopted.items():
            parent = parents[key]
            if parent is not None and parent not in done:
                raise ValueError("adopted fit lacks accepted parent")
            submit(key, record["cpu"], record)
        while len(done) + len(rejected) < len(parents):
            for key, parent in parents.items():
                if key not in submitted and parent in rejected:
                    rejected.add(key); submitted.add(key)
            free = sorted(set(cpus) - {cpu for _, cpu in running.values()})
            for key, parent in parents.items():
                if not free: break
                if key not in submitted and (parent is None or parent in done):
                    before_launch()
                    submit(key, free.pop(0))
            observe(dict(complete=len(done), rejected=len(rejected), total=len(parents),
                         active=[dict(key=key, cpu=cpu) for key, cpu in running.values()],
                         pending=len(parents) - len(submitted), at_epoch=time.time()))
            if not running:
                if len(done) + len(rejected) != len(parents):
                    raise RuntimeError("dependency queue stalled")
                break
            finished, _ = wait(running, timeout=5, return_when=FIRST_COMPLETED)
            for future in finished:
                key, _ = running.pop(future)
                (done if future.result() is True else rejected).add(key)
    if rejected:
        raise RuntimeError(f"rejected quantile nodes and descendants: {sorted(rejected)}")
    observe(dict(complete=len(done), rejected=0, total=len(parents), active=[], pending=0,
                 at_epoch=time.time()))
    return done
