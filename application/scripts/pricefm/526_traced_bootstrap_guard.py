#!/usr/bin/env python3
"""Kernel-owned bootstrap tree followed by a strict helper-free boundary.

PTRACE fork/vfork/clone events attach every newborn before it executes.
EXITKILL covers tracer death; no process-group/cgroup or generic PID fallback.
CLONE_UNTRACED and namespace escapes are denied before native exec. The caller
retains the exclusive permit until every tracee is terminal/reaped.
"""
from __future__ import annotations
import ctypes
import datetime as dt
import errno
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import signal
import stat
import struct
import threading
import time

P_TRACEME=0;P_CONT=7;P_SETOPTIONS=0x4200;P_GETEVENTMSG=0x4201
OPTIONS=0x1|0x2|0x4|0x8|0x10|0x40|0x80|0x100000
WALL=0x40000000
BOOTSTRAP='TRACED_BOOTSTRAP';SCIENCE='SCIENTIFIC_FORK_DENIED'

class GuardError(RuntimeError):pass

def _libc():
    result=ctypes.CDLL(None,use_errno=True);result.ptrace.restype=ctypes.c_long
    return result

def ptrace(request,pid,data=0):
    result=_libc().ptrace(request,pid,ctypes.c_void_p(),ctypes.c_void_p(data))
    if result==-1:raise OSError(ctypes.get_errno(),os.strerror(ctypes.get_errno()))
    return result

class Registers(ctypes.Structure):
    _fields_=[(name,ctypes.c_ulonglong) for name in ('r15','r14','r13','r12','rbp','rbx','r11','r10','r9','r8','rax','rcx','rdx','rsi','rdi','orig_rax','rip','cs','eflags','rsp','ss','fs_base','gs_base','ds','es','fs','gs')]

def registers(pid):
    r=Registers();l=_libc()
    if l.ptrace(12,pid,ctypes.c_void_p(),ctypes.byref(r))!=0:raise GuardError('cannot read held tracee syscall registers')
    return r

def trace_memory(pid,address,length):
    if not 0<length<=4096:raise GuardError('bounded remote filter bytes required')
    result=bytearray();l=_libc()
    for offset in range(0,length,8):
        ctypes.set_errno(0);word=l.ptrace(2,pid,ctypes.c_void_p(address+offset),ctypes.c_void_p())
        if word==-1 and ctypes.get_errno():raise GuardError('cannot read held tracee filter')
        result.extend((word&((1<<64)-1)).to_bytes(8,'little'))
    return bytes(result[:length])

def scientific_filter_rows():
    deny=0x00050000|errno.EPERM;enosys=0x00050000|errno.ENOSYS
    return [(0x20,0,0,4),(0x15,1,0,0xc000003e),(0x06,0,0,0x80000000),
            (0x20,0,0,0),(0x45,0,1,0x40000000),(0x06,0,0,deny),
            (0x15,0,1,57),(0x06,0,0,deny),(0x15,0,1,58),(0x06,0,0,deny),
            (0x15,0,1,435),(0x06,0,0,enosys),(0x15,0,3,56),(0x20,0,0,16),
            (0x45,1,0,0x10000),(0x06,0,0,deny),(0x06,0,0,0x7fff0000)]

def attest_seccomp_entry(pid):
    regs=registers(pid)
    if (regs.orig_rax,regs.rdi,regs.rsi)!=(317,1,1):raise GuardError('only reviewed TSYNC filter syscall is admitted')
    length,pointer=struct.unpack('<H6xQ',trace_memory(pid,regs.rdx,16))
    expected=b''.join(struct.pack('<HBBI',*row) for row in scientific_filter_rows())
    actual=trace_memory(pid,pointer,length*8)
    if actual!=expected:raise GuardError('scientific filter bytes differ from reviewed fork-denial policy')
    return {'pid':pid,'operation':'SECCOMP_SET_MODE_FILTER','flags':'TSYNC','program_sha256':hashlib.sha256(actual).hexdigest(),'instruction_count':length,'kernel_return':None}

def stat_record(pid):
    p=Path('/proc')/str(pid);s=(p/'stat').read_text().rsplit(')',1)[1].split()
    status=(p/'status').read_text().splitlines()
    tgid=int(next(x.split()[1] for x in status if x.startswith('Tgid:')))
    tracer=int(next(x.split()[1] for x in status if x.startswith('TracerPid:')))
    filters=next((int(x.split()[1]) for x in status if x.startswith('Seccomp_filters:')),None)
    return {'pid':pid,'tgid':tgid,'TracerPid':tracer,'ppid':int(s[1]),'start_ticks':int(s[19]),'state':s[0],
            'own_ticks':int(s[11])+int(s[12]),'reaped_descendant_ticks':int(s[13])+int(s[14]),
            'Seccomp_filters':filters,'affinity':sorted(os.sched_getaffinity(pid))}

def identity(pid):
    row=stat_record(pid);row['boot_id']=Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    return row

def same_lifetime(row,expected):
    return row['pid']==expected['pid'] and row['start_ticks']==expected['start_ticks']

def held_lock(fd):
    s=os.fstat(fd)
    if not stat.S_ISREG(s.st_mode):raise GuardError('regular permit lock required')
    found=False
    for line in Path('/proc/locks').read_text().splitlines():
        w=line.split()
        if len(w)<8 or w[1]!='FLOCK' or w[3]!='WRITE' or int(w[4])!=os.getpid():continue
        d=w[5].split(':')
        if len(d)==3 and (int(d[0],16),int(d[1],16),int(d[2]))==(os.major(s.st_dev),os.minor(s.st_dev),s.st_ino):found=True
    if not found:raise GuardError('caller must hold an exclusive FLOCK')
    return {'fd':fd,'device':s.st_dev,'inode':s.st_ino,'holder_pid':os.getpid()}

def cpu():
    a=resource.getrusage(resource.RUSAGE_SELF);b=resource.getrusage(resource.RUSAGE_CHILDREN)
    return a.ru_utime+a.ru_stime,b.ru_utime+b.ru_stime

def task_runtime(pid):
    return int((Path('/proc')/str(pid)/'task'/str(pid)/'schedstat').read_text().split()[0])/1e9

def _filter(rows):
    class I(ctypes.Structure):_fields_=[('code',ctypes.c_ushort),('jt',ctypes.c_ubyte),('jf',ctypes.c_ubyte),('k',ctypes.c_uint32)]
    class P(ctypes.Structure):_fields_=[('length',ctypes.c_ushort),('filter',ctypes.POINTER(I))]
    table=(I*len(rows))(*(I(*row) for row in rows));p=P(len(rows),table);l=_libc()
    if l.prctl(38,1,0,0,0)!=0 or l.prctl(22,2,ctypes.byref(p),0,0)!=0:raise GuardError('bootstrap seccomp installation failed')

def bootstrap_boundary():
    """Permit traced helpers, deny untraced/namespace/thread-affinity escapes."""
    if os.uname().machine!='x86_64':raise GuardError('reviewed x86_64 Linux required')
    allow=0x7fff0000;deny=0x00050000|errno.EPERM;enosys=0x00050000|errno.ENOSYS
    rows=[(0x20,0,0,4),(0x15,1,0,0xc000003e),(0x06,0,0,0x80000000),
          (0x20,0,0,0),(0x45,0,1,0x40000000),(0x06,0,0,deny)]
    # No ptrace relationship changes, namespace entry, session/group escape,
    # affinity expansion, or clone3 bypass after initial TRACEME.
    for nr in (101,109,112,203,272,308):rows.extend([(0x15,0,1,nr),(0x06,0,0,deny)])
    # The later seccomp TSYNC syscall is kernel-stopped for this owning tracer,
    # which inspects the exact BPF bytes and successful syscall return. Older
    # kernels do not expose Seccomp_filters in /proc; no guessed count is used.
    rows.extend([(0x15,0,1,317),(0x06,0,0,0x7ff00000|0x157),
                 (0x15,0,1,435),(0x06,0,0,enosys),
                 (0x15,0,3,56),(0x20,0,0,16),
                 (0x45,0,1,0x7e82a000),(0x06,0,0,deny),
                 (0x06,0,0,allow)])
    _filter(rows)

def immutable(path,value):
    path=Path(path)
    with path.open('x') as f:json.dump(value,f,indent=2,sort_keys=True);f.write('\n');f.flush();os.fsync(f.fileno())

def _replace(path,value):
    p=Path(path);t=p.with_name(p.name+'.tmp-'+str(os.getpid()))
    with t.open('x') as f:json.dump(value,f,sort_keys=True);f.write('\n');f.flush();os.fsync(f.fileno())
    os.replace(t,p)

def inspect_owner(path,expected_lock):
    """Read-only live owner evidence. A receipt is not an authority itself."""
    p=Path(path)
    if p.is_symlink() or any(x.is_symlink() for x in p.parents):raise GuardError('owner receipt symlink')
    value=json.loads(p.read_text())
    if value.get('schema')!='r157_ptrace_owner_v1' or value.get('state')!='LIVE':raise GuardError('not a live traced owner')
    parent=identity(value['supervisor']['pid'])
    if not same_lifetime(parent,value['supervisor']) or parent['boot_id']!=value['supervisor']['boot_id']:raise GuardError('owner lifetime changed')
    lock=Path(expected_lock).stat();proof=value['permit']
    if (lock.st_dev,lock.st_ino)!=(proof['device'],proof['inode']):raise GuardError('wrong lock identity')
    fd=Path('/proc')/str(parent['pid'])/'fd'/str(proof['fd']);held=fd.stat()
    if (held.st_dev,held.st_ino)!=(lock.st_dev,lock.st_ino):raise GuardError('owner no longer holds the declared fd')
    info=(fd.parent.parent/'fdinfo'/str(proof['fd'])).read_text()
    if 'FLOCK' not in info or 'WRITE' not in info:raise GuardError('held fd lacks exclusive kernel lock record')
    if time.time()>=value['absolute_deadline_epoch']:raise GuardError('owner authority expired')
    return {'schema':'r157_ptrace_owner_observation_v1','status':'VERIFIED_CURRENT_TRACE_OWNER',
            'observed_epoch':time.time(),'supervisor':parent,'permit':proof,'phase':value['phase'],
            'scope':value['scope'],'source':value['source'],'authority_pin':value['authority_pin'],
            'owner_receipt_pin':{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()},
            'raw_owner':value}

def run_traced(command,*,env,stdout,stderr,lock_fd,affinity,wall_seconds,
               maximum_combined_CPU_seconds,absolute_deadline_UTC,peer_callback,
               bootstrap_exec_allowlist,owner_path=None,scope='PRIVATE_METADATA_FIXTURE',
               source=None,authority_pin=None,preexec_fn=None,require_science_handshake=True,
               ready_token='R157_TSYNC_FORK_DENIAL_READY_V1',interval_seconds=.02,peer_interval_seconds=10,
               owner_capture_callback=None):
    """Own exactly one newly created native tree; no existing process adoption.

    CPU debit is this supervisor+self's RUSAGE_CHILDREN, not summed wait4 rows.
    ptrace wait rows include true-parent inclusive usage and would double count.
    Tracer is an exclusive child-subreaper and drains all created tree members.
    """
    if threading.active_count()!=1 or signal.getsignal(signal.SIGCHLD)!=signal.SIG_DFL:raise GuardError('exclusive single-thread/defaultSIGCHLD required')
    if any(t.read_text().strip() for t in Path('/proc/self/task').glob('*/children')):raise GuardError('existing children preclude exclusive reaping')
    if not callable(peer_callback) or not isinstance(command,list) or not command:raise GuardError('explicit argv and peer callback required')
    for v in (wall_seconds,maximum_combined_CPU_seconds,interval_seconds):
        if isinstance(v,bool) or not math.isfinite(v) or v<=0:raise GuardError('finite positive bounds required')
    if interval_seconds>1:raise GuardError('owned observation interval too large')
    if not 0<peer_interval_seconds<=10:raise GuardError('full peer interval must be <=10seconds')
    deadline=dt.datetime.fromisoformat(absolute_deadline_UTC)
    if deadline.tzinfo is None or deadline.timestamp()<=time.time():raise GuardError('live absolute UTC deadline required')
    lock=held_lock(lock_fd);initial=peer_callback([]);before_self,before_children=cpu()
    if before_self+before_children>=maximum_combined_CPU_seconds:raise GuardError('CPU already spent')
    l=_libc();old_sub=ctypes.c_int()
    if l.prctl(37,ctypes.byref(old_sub),0,0,0)!=0 or l.prctl(36,1,0,0,0)!=0:raise GuardError('child subreaper unavailable')
    rr,rw=os.pipe2(os.O_CLOEXEC|os.O_NONBLOCK);ar,aw=os.pipe2(os.O_CLOEXEC)
    child_env=dict(env,R157_FILTER_PROOF_FD=str(rw),R157_FILTER_ACK_FD=str(ar),R157_FILTER_TOKEN=ready_token)
    started=time.monotonic();parent=os.getpid();boot=Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    child=os.fork()
    if child==0:
        try:
            os.close(rr);os.close(aw)
            if l.prctl(1,signal.SIGKILL,0,0,0)!=0 or os.getppid()!=parent:os._exit(125)
            os.sched_setaffinity(0,set(affinity));resource.setrlimit(resource.RLIMIT_CORE,(0,0))
            seconds=max(1,math.ceil(maximum_combined_CPU_seconds-before_self-before_children));resource.setrlimit(resource.RLIMIT_CPU,(seconds,seconds))
            signal.signal(signal.SIGALRM,signal.SIG_DFL);signal.setitimer(signal.ITIMER_REAL,min(wall_seconds,deadline.timestamp()-time.time()))
            if preexec_fn:preexec_fn()
            ptrace(P_TRACEME,0);os.kill(os.getpid(),signal.SIGSTOP)
            bootstrap_boundary()
            for fd in (rw,ar,lock_fd):os.set_inheritable(fd,True)
            os.dup2(stdout.fileno(),1);os.dup2(stderr.fileno(),2)
            null=os.open('/dev/null',os.O_RDONLY);os.dup2(null,0)
            os.execve(command[0],command,child_env)
        except BaseException:os._exit(125)
    os.close(rw);os.close(ar)
    identities={};active=set();events=[];wait_rows=[];phase=BOOTSTRAP;handshake=False;task_CPU={};pending_seccomp={};boundary_attestation=None;early_birth_stops=set()
    abort=None;error=None;root_code=None;trace_options=False;proof=b'';last_peer=started
    owner_file=Path(owner_path) if owner_path else None
    source=source or {'guard_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    def publish(state='LIVE'):
        if owner_file:
            value={'schema':'r157_ptrace_owner_v1','state':state,'supervisor':identity(parent),
                   'root':identities.get(child),'permit':lock,'phase':phase,'scope':scope,
                   'source':source,'authority_pin':authority_pin,'absolute_deadline_epoch':deadline.timestamp(),
                   'observed_epoch':time.time(),'traced_live_lifetimes':[identities[p] for p in sorted(active)]}
            if owner_file.exists():_replace(owner_file,value)
            else:immutable(owner_file,value)
        if owner_capture_callback is not None:
            owner_capture_callback(lock_fd,phase if state=='LIVE' else 'FINALIZATION',
                                   {'kernel_trace_owned':trace_options,'live_lifetimes':[identities[p] for p in sorted(active)],
                                    'all_helpers_owned':True,'scientific_filter_accepted':handshake,'state':state})
    def register(pid,kind):
        if pid in active:
            row=identity(pid)
            if not same_lifetime(row,identities[pid]):raise GuardError('provisional newborn lifetime changed')
            events.append({'event':'KERNEL_BIRTH_CORROBORATED','kind':kind,'identity':row})
            return
        active.add(pid);identities[pid]={'pid':pid,'kernel_held_identity_incomplete':True}
        row=identity(pid)
        identities[pid]=row
        if row['boot_id']!=boot or row['affinity']!=sorted(affinity):raise GuardError('new tracee identity/affinity differs')
        task_CPU[pid]=task_runtime(pid);events.append({'event':'KERNEL_OWNED_NEWBORN','kind':kind,'identity':row})
    def signal_owned(pid):
        if pid not in active:raise GuardError('not a kernel-held tracee')
        if identities[pid].get('kernel_held_identity_incomplete'):
            # PTRACE_CONT only succeeds for this tracer's stopped tracee;
            # unlike kill(pid), it cannot signal a reused/foreign PID.
            try:ptrace(P_CONT,pid,signal.SIGKILL)
            except OSError:pass
            return
        try:
            row=stat_record(pid)
            if not same_lifetime(row,identities[pid]):raise GuardError('held lifetime mismatch')
            os.kill(pid,signal.SIGKILL)
        except ProcessLookupError:pass # terminal ptrace wait still required
    def stop_all(reason):
        nonlocal abort
        abort=abort or reason
        for pid in tuple(active):signal_owned(pid)
    try:
        waited,status,usage=os.wait4(child,0)
        if not os.WIFSTOPPED(status) or os.WSTOPSIG(status)!=signal.SIGSTOP:raise GuardError('initial kernel stop absent')
        register(child,'ROOT');ptrace(P_SETOPTIONS,child,OPTIONS);trace_options=True
        publish();ptrace(P_CONT,child)
        while active:
            if time.monotonic()-started>=wall_seconds or time.time()>=deadline.timestamp():stop_all('WALL_OR_ABSOLUTE_LIMIT')
            own,reaped=cpu()
            for pid in tuple(active):
                try:
                    row=stat_record(pid)
                    if not same_lifetime(row,identities[pid]) or row['affinity']!=sorted(affinity):raise GuardError('tracee identity/affinity changed')
                    task_CPU[pid]=task_runtime(pid)
                except FileNotFoundError:pass
            # Exclusive task runtimes retain exited tasks and count threads
            # once. Two scheduler ticks per tracee conservatively cover final
            # kernel cleanup; final billing uses exact RUSAGE_CHILDREN once.
            live_upper=sum(task_CPU.values())+2*len(identities)/os.sysconf('SC_CLK_TCK')
            if own+before_children+live_upper>=maximum_combined_CPU_seconds:stop_all('COMBINED_CPU_LIMIT')
            if time.monotonic()-last_peer>=peer_interval_seconds:
                peer_callback([identities[p] for p in sorted(active)]);last_peer=time.monotonic();publish()
            try:part=os.read(rr,4096);proof+=part
            except BlockingIOError:pass
            if proof and not handshake:
                if proof!=ready_token.encode():raise GuardError('invalid scientific handshake token')
                if not boundary_attestation or boundary_attestation['kernel_return']!=0:raise GuardError('scientific filter kernel syscall not attested')
                for pid in active:
                    row=stat_record(pid)
                    if row['tgid']!=child:raise GuardError('bootstrap helper survives at scientific boundary')
                peer_callback([identities[p] for p in sorted(active)])
                handshake=True;phase=SCIENCE;publish();os.write(aw,b'1');os.close(aw);aw=-1
            try:pid,status,usage=os.wait4(-1,os.WNOHANG|WALL)
            except ChildProcessError:
                if active:raise GuardError('kernel trace ownership vanished before terminal waits')
                break
            if pid==0:time.sleep(interval_seconds);continue
            if pid not in active:
                if os.WIFSTOPPED(status) and os.WSTOPSIG(status)==signal.SIGSTOP:
                    # Linux may report the auto-attached newborn's initial stop
                    # before its parent's FORK/VFORK/CLONE event. Kernel tracer
                    # ownership permits us to hold it, never to run it yet.
                    row=stat_record(pid)
                    if row['TracerPid']!=parent:raise GuardError('unknown stopped process is not our tracee')
                    register(pid,'PROVISIONAL_KERNEL_STOP');early_birth_stops.add(pid);continue
                if pid in identities and (os.WIFEXITED(status) or os.WIFSIGNALED(status)):
                    # A ptraced orphan can also produce the later real-parent
                    # reap; record it but never sum raw inclusive wait usage.
                    wait_rows.append({'pid':pid,'returncode':os.waitstatus_to_exitcode(status),'second_real_parent_reap':True,'raw_wait4_inclusive_CPU_seconds':usage.ru_utime+usage.ru_stime});continue
                raise GuardError('unregistered child wait: '+str((pid,status)))
            if os.WIFSTOPPED(status):
                event=status>>16;sig=os.WSTOPSIG(status)
                if event in (1,2,3):
                    value=ctypes.c_ulong()
                    if l.ptrace(P_GETEVENTMSG,pid,0,ctypes.byref(value))!=0:raise GuardError('missing kernel birth identity')
                    register(value.value,('FORK','VFORK','CLONE')[event-1])
                    if phase==SCIENCE and stat_record(value.value)['tgid']!=child:stop_all('SCIENTIFIC_SUBPROCESS_BIRTH')
                    if value.value in early_birth_stops:
                        early_birth_stops.remove(value.value);ptrace(P_CONT,value.value,signal.SIGKILL if abort else 0)
                elif event==4:
                    exe=Path(os.readlink('/proc/'+str(pid)+'/exe')).resolve()
                    expected=bootstrap_exec_allowlist.get(str(exe))
                    if not expected or hashlib.sha256(exe.read_bytes()).hexdigest()!=expected:stop_all('UNREVIEWED_BOOTSTRAP_EXECUTABLE')
                    events.append({'event':'EXEC','pid':pid,'path':str(exe),'sha256':expected})
                elif event==6:
                    task_CPU[pid]=task_runtime(pid)
                    events.append({'event':'EXIT_STOP','pid':pid,'stat':stat_record(pid)})
                elif event==7:
                    if pid!=child or boundary_attestation is not None:raise GuardError('unexpected or repeated scientific filter install')
                    pending_seccomp[pid]=attest_seccomp_entry(pid)
                    # Exactly one syscall-exit stop proves kernel acceptance.
                    ptrace(24,pid);continue
                elif sig==(signal.SIGTRAP|0x80):
                    if pid not in pending_seccomp:raise GuardError('unexpected syscall stop')
                    regs=registers(pid)
                    if regs.orig_rax!=317 or regs.rax!=0:raise GuardError('TSYNC scientific kernel filter was not accepted')
                    boundary_attestation=pending_seccomp.pop(pid);boundary_attestation['kernel_return']=0
                    events.append({'event':'SCIENTIFIC_FILTER_KERNEL_ATTESTED','proof':boundary_attestation})
                    ptrace(P_CONT,pid);continue
                elif sig not in (signal.SIGSTOP,signal.SIGTRAP):
                    if sig in (signal.SIGXCPU,signal.SIGALRM):stop_all('KERNEL_LIMIT_SIGNAL')
                if abort:ptrace(P_CONT,pid,signal.SIGKILL)
                else:ptrace(P_CONT,pid,0 if event or sig in (signal.SIGSTOP,signal.SIGTRAP) else sig)
            else:
                code=os.waitstatus_to_exitcode(status);active.remove(pid)
                wait_rows.append({'pid':pid,'returncode':code,'raw_wait4_inclusive_CPU_seconds':usage.ru_utime+usage.ru_stime})
                if pid==child:
                    root_code=code
                    if any(identities[p].get('tgid')!=child for p in active):stop_all('ROOT_EXIT_WITH_LIVE_HELPER')
        if require_science_handshake and not handshake:abort=abort or 'SCIENTIFIC_HANDSHAKE_ABSENT'
    except BaseException as exc:
        error=type(exc).__name__+': '+str(exc);abort=abort or 'OWNERSHIP_OR_OBSERVER_FAILURE'
        # Every known identity is still a kernel-held tracee until final wait.
        stop_all(abort)
        end=time.monotonic()+10
        while active and time.monotonic()<end:
            try:pid,s,u=os.wait4(-1,os.WNOHANG|WALL)
            except ChildProcessError:break
            if not pid:time.sleep(.01);continue
            if os.WIFSTOPPED(s):
                if s>>16 in(1,2,3):
                    v=ctypes.c_ulong();l.ptrace(P_GETEVENTMSG,pid,0,ctypes.byref(v));register(v.value,'ABORT_NEWBORN')
                ptrace(P_CONT,pid,signal.SIGKILL)
            else:
                active.discard(pid);code=os.waitstatus_to_exitcode(s);wait_rows.append({'pid':pid,'returncode':code,'raw_wait4_inclusive_CPU_seconds':u.ru_utime+u.ru_stime})
                if pid==child:root_code=code
    finally:
        os.close(rr)
        if aw>=0:os.close(aw)
    # No final child or thread may be omitted. This loop only reaps this newly
    # created exclusive tree; there were no pre-existing children.
    extras=[]
    while True:
        try:pid,s,u=os.wait4(-1,os.WNOHANG|WALL)
        except ChildProcessError:break
        if not pid:break
        extras.append({'pid':pid,'status':s,'raw_wait4_inclusive_CPU_seconds':u.ru_utime+u.ru_stime})
        if os.WIFEXITED(s) or os.WIFSIGNALED(s):active.discard(pid)
    unknown_reaps=[r['pid'] for r in extras if r['pid'] not in identities]
    if unknown_reaps:abort=abort or 'UNTRACED_CHILD_WAIT'
    own,reaped=cpu();tree_cpu=reaped-before_children;complete=not active and trace_options and not unknown_reaps
    if own+reaped>=maximum_combined_CPU_seconds:abort=abort or 'COMBINED_CPU_LIMIT_AFTER_REAP'
    if complete:
        try:peer_callback([])
        except Exception as exc:abort=abort or 'FINAL_PEER_GUARD_FAILURE';error=str(exc)
        l.prctl(36,old_sub.value,0,0,0)
    publish('CLOSED' if complete else 'UNREAPED_BLOCKED')
    return {'schema':'r157_traced_bootstrap_guard_receipt_v1','status':'EXITED' if complete and abort is None else 'ABORTED',
            'abort_reason':abort,'error':error,'returncode':root_code,'owned_root':identities.get(child),
            'supervisor':identity(parent),'permit':lock,'reaped':complete,'drained':complete,
            'CPU_accounting_complete':complete,'child_tree_CPU_seconds':tree_cpu,
            'CPU_accounting_basis':'exclusive_subreaper_RUSAGE_CHILDREN_delta_once; raw_wait4_rows_not_summed',
            'parent_CPU_seconds_since_start':own,'prior_reaped_child_CPU_seconds':before_children,
            'parent_plus_all_reaped_child_CPU_seconds':own+reaped,
            'exclusive_tracee_runtime_seconds':task_CPU,
            'maximum_combined_CPU_seconds':maximum_combined_CPU_seconds,'raw_wait4_rows':wait_rows,'extra_reap_rows':extras,
            'kernel_trace_options':OPTIONS,'all_newborns_kernel_traced_before_execution':trace_options and not unknown_reaps,
            'unexpected_untraced_child_waits':unknown_reaps,
            'tracer_death_kernel_EXITKILL_enabled':trace_options,'bootstrap_subprocess_creation_allowed':True,
            'whole_startup_subprocess_creation_kernel_denied':False,'postbootstrap_TSYNC_scientific_fork_denial':handshake,
            'scientific_filter_kernel_attestation':boundary_attestation,
            'scientific_target_access_handshake':handshake,'events':events,
            'remaining_owned_lifetimes':[identities[p] for p in sorted(active)],
            'signal_scope':'exact_kernel_ptrace_owned_lifetimes_only','wall_seconds':time.monotonic()-started,
            'absolute_deadline_UTC':absolute_deadline_UTC,'initial_peer_observation':initial}
