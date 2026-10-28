"""Charged-before-I/O SSH and rsync with CPU receipts and process limits.

The meter reserves whole command ceilings without refunds. RLIMIT_CPU limits
individual processes, not a cgroup: aggregate measured violations and missing
remote receipts block further I/O. A disconnected remote command is never
assigned a zero CPU cost. Callers checkpoint their own parent CPU separately.
"""
from __future__ import annotations
import base64
import json
import os
from pathlib import Path
import resource
import shlex
import subprocess
import time
import uuid
from . import control as ctl

SCHEMA = "r157_metered_remote_command_receipt_v1"
MAX_OUTPUT = 8 * 1024 * 1024


class MeteredIOError(RuntimeError):
    def __init__(self, message, receipt=None):
        super().__init__(message)
        self.receipt = receipt


def _limit(seconds):
    def apply(): resource.setrlimit(resource.RLIMIT_CPU, (seconds, seconds))
    return apply


def _children_cpu():
    value=resource.getrusage(resource.RUSAGE_CHILDREN)
    return value.ru_utime+value.ru_stime


def _run(argv, *, timeout, stdin=None, cpu=1):
    start=_children_cpu()
    try:
        result=subprocess.run(argv,input=stdin,text=True,capture_output=True,timeout=timeout,
                              preexec_fn=_limit(cpu))
    except BaseException as exc:
        exc.local_CPU=max(0,_children_cpu()-start)
        raise
    return result,max(0,_children_cpu()-start)


def _remote_script(argv, timeout, mode="COMMAND", script=None):
    payload=json.dumps(dict(argv=argv,timeout=timeout,mode=mode,script=script))
    return '''import base64,contextlib,io,json,os,resource,signal,subprocess,time,traceback
payload=json.loads(__PAYLOAD__)
def cpu():
 s=resource.getrusage(resource.RUSAGE_SELF);c=resource.getrusage(resource.RUSAGE_CHILDREN)
 return s.ru_utime+s.ru_stime+c.ru_utime+c.ru_stime
resource.setrlimit(resource.RLIMIT_AS,(512*1024**2,)*2)
resource.setrlimit(resource.RLIMIT_FSIZE,(16*1024**2,)*2)
resource.setrlimit(resource.RLIMIT_CPU,((10,10) if payload['mode']=='WATCH' else (1,1)))
signal.alarm(max(1,int(payload['timeout'])+1))
out='';err='';rc=0
try:
 if payload['mode']=='WATCH':
  target=io.StringIO()
  with contextlib.redirect_stdout(target):exec(compile(payload['script'],'<fixed-one-file-watch>','exec'),{})
  out=target.getvalue()
 else:
  result=subprocess.run(payload['argv'],text=True,capture_output=True,timeout=payload['timeout'])
  out=result.stdout;err=result.stderr;rc=result.returncode
except BaseException as exc:
 rc=125;err=type(exc).__name__+': '+str(exc)
if len(out.encode())+len(err.encode())>8*1024**2:rc=126;out='';err='remote command output limit exceeded'
record=dict(schema='r157_metered_remote_command_receipt_v1',mode=payload['mode'],
 argv=payload['argv'],returncode=rc,stdout_b64=base64.b64encode(out.encode()).decode(),
 stderr_b64=base64.b64encode(err.encode()).decode(),CPU_seconds_observed_before_final_receipt=cpu(),
 final_receipt_CPU_included_in_reserved_upper_bound=True,observed_epoch=time.time())
print(json.dumps(record,separators=(',',':')))
'''.replace('__PAYLOAD__',repr(payload))


def _decode(result, *, expected_argv, mode):
    if result.returncode:
        raise MeteredIOError("SSH did not return a complete CPU receipt: "+result.stderr[-2000:])
    if len(result.stdout.encode()) > 2 * MAX_OUTPUT:
        raise MeteredIOError("remote CPU receipt exceeds bounded output")
    try:
        value=json.loads(result.stdout)
        if (value.get('schema')!=SCHEMA or value.get('argv')!=expected_argv or value.get('mode')!=mode
                or value.get('final_receipt_CPU_included_in_reserved_upper_bound') is not True
                or type(value.get('returncode')) is not int):
            raise ValueError('receipt command identity differs')
        value['stdout']=base64.b64decode(value['stdout_b64'],validate=True).decode()
        value['stderr']=base64.b64decode(value['stderr_b64'],validate=True).decode()
    except (ValueError,TypeError,KeyError,UnicodeError) as exc:
        raise MeteredIOError('invalid remote CPU/output receipt') from exc
    return value


def _command(config, argv, budget, key, *, timeout, mode='COMMAND', script=None):
    kind='ready_watch' if mode=='WATCH' else 'metadata'
    token=budget.start_operation(key,kind)
    local=None;receipt=None
    try:
        if (not isinstance(argv,list) or any(not isinstance(v,str) or '\x00' in v for v in argv)
                or type(timeout) not in (int,float) or not 0<timeout<=1805):
            raise ValueError('explicit bounded command arguments required')
        result,local=_run(ctl.ssh(config)+['/usr/bin/python3 -B -'],timeout=timeout+5,
                         stdin=_remote_script(argv,timeout,mode,script),cpu=1)
        receipt=_decode(result,expected_argv=argv,mode=mode)
    except BaseException as exc:
        local=getattr(exc,'local_CPU',local)
        budget.finish_operation(key,token,local_CPU=local,remote_CPU=None,
            outcome='NO_COMPLETE_REMOTE_RECEIPT:'+type(exc).__name__+':'+str(exc)[-2000:])
        raise
    budget.finish_operation(key,token,local_CPU=local,
        remote_CPU=receipt['CPU_seconds_observed_before_final_receipt'],
        outcome='COMPLETE' if receipt['returncode']==0 else 'REMOTE_COMMAND_FAILED')
    if receipt['returncode']:
        raise MeteredIOError('remote command failed: '+receipt['stderr'][-2000:],receipt)
    return receipt['stdout']


def remote(config,argv,budget,key,timeout=30):
    return _command(config,argv,budget,key,timeout=timeout)


def watch(config,script,budget,key,timeout):
    if not isinstance(script,str) or len(script.encode())>65536:raise ValueError('bounded fixed watcher source required')
    return _command(config,[],budget,key,timeout=timeout,mode='WATCH',script=script)


def _rsync_wrapper(receipt_path):
    """The binary rsync protocol owns stdout; CPU evidence uses a separate file."""
    return '''import json,os,pathlib,resource,signal,subprocess,sys,time
receipt=pathlib.Path(__RECEIPT__)
for parent in (receipt.parent,*receipt.parents):
 if parent.is_symlink():raise ValueError('symlink CPU receipt ancestor')
receipt.parent.mkdir(parents=True,exist_ok=True)
signal.signal(signal.SIGXCPU,signal.SIG_DFL)
resource.setrlimit(resource.RLIMIT_CPU,(1,5))
def child():resource.setrlimit(resource.RLIMIT_CPU,(4,4))
rc=subprocess.call(['/usr/bin/rsync']+sys.argv[1:],preexec_fn=child)
s=resource.getrusage(resource.RUSAGE_SELF);c=resource.getrusage(resource.RUSAGE_CHILDREN)
value=dict(schema='r157_rsync_remote_CPU_receipt_v1',returncode=rc,
 CPU_seconds_observed_before_final_receipt=s.ru_utime+s.ru_stime+c.ru_utime+c.ru_stime,
 final_receipt_CPU_included_in_reserved_upper_bound=True,observed_epoch=time.time())
with receipt.open('x') as stream:json.dump(value,stream,separators=(',',':'))
raise SystemExit(rc)
'''.replace('__RECEIPT__',repr(receipt_path))


def transfer(config,source,target,budget,key,link_dest=None):
    """One push or pull rsync, with a separately stored exact remote CPU receipt.

    A push uses local source and absolute remote target. A pull uses a source
    beginning user@host: and an absolute local target. The receipt fetch is part
    of this same precharged transfer: local rsync3+SSH1+fetch1, remote rsync5+fetch1.
    Final measured aggregate costs must fit the5/6 transfer unit reservation.
    """
    token=budget.start_operation(key,'transfer');local=None;receipt=None;start=_children_cpu()
    receipt_path=config['remote_root'].rstrip('/')+'/.r157-control-CPU/'+uuid.uuid4().hex+'.json'
    prefix=config['user']+'@'+config['host']+':'
    pull=isinstance(source,str) and source.startswith(prefix)
    if pull:
        remote_path=source[len(prefix):]
        destination=str(Path(target).absolute())+'/'
        source_arg=source.rstrip('/')+'/'
    else:
        remote_path=str(target)
        destination=prefix+remote_path.rstrip('/')+'/'
        source_arg=str(Path(source).absolute())+'/'
    try:
        if (not remote_path.startswith(config['remote_root'].rstrip('/')+'/')
                or '..' in Path(remote_path).parts or '\x00' in remote_path):
            raise ValueError('transfer must remain in exact approved remote root')
        # rsync creates one transport child. Its Python exec trampoline lowers
        # that SSH process to1CPU, while the rsync process itself is capped3CPU.
        ssh=ctl.ssh(config)[:-1]
        trampoline="import os,resource,sys;resource.setrlimit(resource.RLIMIT_CPU,(1,1));os.execvp(sys.argv[1],sys.argv[1:])"
        transport=shlex.join(['/usr/bin/python3','-B','-c',trampoline]+ssh)
        remote_command=shlex.join(['/usr/bin/python3','-B','-c',_rsync_wrapper(receipt_path)])
        argv=['rsync','-rlt','--checksum','--partial','--delay-updates','--no-links',
              '-e',transport,'--rsync-path='+remote_command]
        if link_dest is not None:argv.append('--link-dest='+str(link_dest))
        argv.extend([source_arg,destination])
        result,_unused=_run(argv,timeout=240,cpu=3)
        # Fetch via one Python process (not another command wrapper/child).
        fetch="import pathlib,resource;resource.setrlimit(resource.RLIMIT_CPU,(1,1));print(pathlib.Path("+repr(receipt_path)+").read_text())"
        fetched,_unused=_run(ctl.ssh(config)+['/usr/bin/python3 -B -'],timeout=15,stdin=fetch,cpu=1)
        if fetched.returncode:raise MeteredIOError('remote transfer CPU receipt unavailable')
        receipt=json.loads(fetched.stdout)
        if (receipt.get('schema')!='r157_rsync_remote_CPU_receipt_v1'
                or receipt.get('final_receipt_CPU_included_in_reserved_upper_bound') is not True
                or receipt.get('returncode')!=result.returncode):
            raise MeteredIOError('remote transfer receipt differs from rsync exit')
        # The separate receipt-fetch process is prospectively charged its full
        #1CPU upper bound; its final CPU cannot be queried without infinite regress.
        remote_CPU=receipt['CPU_seconds_observed_before_final_receipt']+1
        local=max(0,_children_cpu()-start)
    except BaseException as exc:
        local=max(0,_children_cpu()-start)
        budget.finish_operation(key,token,local_CPU=local,remote_CPU=None,
            outcome='NO_COMPLETE_REMOTE_RECEIPT:'+type(exc).__name__+':'+str(exc)[-2000:])
        raise
    budget.finish_operation(key,token,local_CPU=local,remote_CPU=remote_CPU,
        outcome='COMPLETE' if result.returncode==0 else 'TRANSFER_FAILED')
    if result.returncode:raise MeteredIOError('rsync transfer failed: '+result.stderr[-2000:],receipt)
    return result.stdout
