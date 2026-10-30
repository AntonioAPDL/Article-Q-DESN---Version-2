"""Opaque bounded wire spool, then the unchanged original offline receiver.

Run this standalone with the frozen original pricefm_hb package on PYTHONPATH.
The caller owns the original whole-process CPU/wall guardian and its receipts.
Neither stage grants acceptance or installs a canonical return directory.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import select
import shlex
import stat
import struct
import time
from pricefm_hb import profile_stream as s

STREAM_SHA='4f8cbb837817296125fd27d3ddf52f90959062526be2142c536814d0411a739c'
SUPERVISOR_SHA='7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1'
WIRE_MAX=s.BYTE_MAX+s.HEADER_MAX+128
CONFIG_KEYS={'schema','scope_id','job_id','source','ssh_argv','remote_helper_source','cpu','wall','max_bytes','bindings'}


def identity(value):
    return dict(device=value.st_dev,inode=value.st_ino,uid=value.st_uid,mode=value.st_mode)


def owned_read(path,limit):
    path=s.physical(path);before=s.regular(path)
    s.require(before.st_size<=limit,'bounded metadata size exceeded')
    with s.source_file(path,s.fingerprint(before)) as f:
        raw=f.read(limit+1)
        s.require(len(raw)==before.st_size and s.fingerprint(os.fstat(f.fileno()))==s.fingerprint(before),
                  'metadata changed during read')
    s.require(s.fingerprint(s.regular(path))==s.fingerprint(before),'metadata path changed')
    return raw


def read_json(path):return s.decode(owned_read(path,s.HEADER_MAX))


def pin(path,raw):return dict(path=str(s.physical(path)),sha256=hashlib.sha256(raw).hexdigest())


def new_directory(path):
    path=s.physical(path)
    s.require('hb_control_registry' not in path.parts,'canonical registry destination prohibited')
    fd=s.directory_fd(path.parent)
    try:
        s.require(os.fstat(fd).st_uid==os.getuid(),'owned destination parent required')
        os.mkdir(path.name,mode=0o700,dir_fd=fd)
    finally:os.close(fd)
    return path


def create(path):
    path=s.physical(path);fd=s.directory_fd(path.parent)
    try:out=os.open(path.name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW|os.O_NONBLOCK,0o600,dir_fd=fd)
    finally:os.close(fd)
    return os.fdopen(out,'wb',buffering=0)


def write_all(f,block):
    view=memoryview(block)
    while view:
        n=f.write(view);s.require(type(n) is int and n>0,'short spool write');view=view[n:]


def save(path,value):
    raw=json.dumps(value,sort_keys=True,allow_nan=False,separators=(',',':')).encode()+b'\n'
    with create(path) as f:write_all(f,raw);os.fsync(f.fileno())
    return pin(path,raw)


def fixed_sources():
    raw=owned_read(Path(s.__file__),s.HEADER_MAX)
    s.require(hashlib.sha256(raw).hexdigest()==STREAM_SHA,'original stream source differs')
    return raw.decode()


def validate_config(value):
    s.require(type(value) is dict and set(value)==CONFIG_KEYS and value['schema']=='r165_artifact_spool_task_v1',
              'exact spool config required')
    s.require(type(value['scope_id']) is str and re.fullmatch(r'r164-profile-[a-f0-9]{32}',value['scope_id']), 'scope identity differs')
    s.require(type(value['job_id']) is str and re.fullmatch(r'[0-9]{1,12}',value['job_id']),'job identity differs')
    s.require(type(value['cpu']) is int and value['cpu']==40 and type(value['wall']) is int and value['wall']==120 and
              type(value['max_bytes']) is int and value['max_bytes']==s.BYTE_MAX,'original fixed transfer caps required')
    argv=value['ssh_argv']
    s.require(type(argv) is list and len(argv)>=2 and all(type(x) is str and x and '\x00' not in x for x in argv),
              'exact approved SSH argv required')
    prefix=argv[-1]+':'
    s.require(type(value['source']) is str and value['source'].startswith(prefix),'remote source destination differs')
    remote=value['source'][len(prefix):]
    s.require(re.fullmatch(r'/(?:home|mnt/beegfs/home)/jaguir26/[A-Za-z0-9_./-]+',remote) and
              '..' not in Path(remote).parts and remote.endswith('/'),'owned remote directory required')
    helper=value['remote_helper_source']
    s.require(type(helper) is str and hashlib.sha256(helper.encode()).hexdigest()==SUPERVISOR_SHA,
              'original supervisor source differs')
    bindings=value['bindings']
    s.require(type(bindings) is dict and set(bindings)=={'spec','request','source_manifest'},'exact binding roles required')
    for role,p in bindings.items():
        s.require(type(p) is dict and set(p)=={'path','sha256'} and type(p['path']) is str and
                  type(p['sha256']) is str and re.fullmatch(r'[a-f0-9]{64}',p['sha256']), 'invalid binding '+role)
        s.physical(p['path'])
    return remote


def sender_argv(config):
    remote=validate_config(config);source=fixed_sources()
    payload=['/usr/bin/python3','-I','-B','-c',source,'--send','--path',remote,'--max-bytes',str(s.BYTE_MAX)]
    command=['/usr/bin/python3','-I','-B','-c',config['remote_helper_source'],'--cpu','40','--wall','120',
             '--output-cap',str(WIRE_MAX),'--passthrough','--',*payload]
    return [*config['ssh_argv'],shlex.join(command)]


def capture_process(process,wire,stderr,deadline,wire_limit=WIRE_MAX):
    """Incremental diagnostics survive helper exceptions; outer SIGKILL may prevent final JSON."""
    wire_h=hashlib.sha256();err_h=hashlib.sha256();count=seen=retained=observed=0;error=None
    streams={process.stdout:'stdout',process.stderr:'stderr'}
    process.stdin.close()
    for f in streams:os.set_blocking(f.fileno(),False)
    try:
        while streams:
            remaining=deadline-time.monotonic()
            s.require(remaining>0,'network absolute wall deadline exhausted')
            ready,_,_=select.select(list(streams),[],[],min(remaining,.2))
            for f in ready:
                try:block=os.read(f.fileno(),s.CHUNK)
                except BlockingIOError:continue
                if not block:streams.pop(f);continue
                if streams[f]=='stderr':
                    seen+=len(block);part=block[:max(0,s.RESPONSE_MAX-retained)]
                    if part:write_all(stderr,part);err_h.update(part);retained+=len(part)
                else:
                    observed+=len(block)
                    if observed>wire_limit:
                        error=error or dict(type='ValueError',message='wire byte cap exceeded')
                        streams.pop(f);f.close()
                    elif error is None:
                        try:write_all(wire,block);wire_h.update(block);count+=len(block)
                        except BaseException as exc:
                            error=dict(type=type(exc).__name__,message=str(exc)[:2000]);streams.pop(f);f.close()
        remaining=deadline-time.monotonic()
        s.require(remaining>0,'network deadline exhausted before wait')
        code=process.wait(timeout=remaining)
        if code!=0:error=error or dict(type='SSHNonzeroExit',message='SSH returncode '+str(code))
    except BaseException as exc:
        error=error or dict(type=type(exc).__name__,message=str(exc)[:2000])
    code=process.poll()
    return dict(capture_complete=error is None and code==0,wire_bytes=count,wire_sha256=wire_h.hexdigest(),
                stdout_bytes_observed=observed,ssh_returncode=code,ssh_reaped_by_helper=code is not None,
                sender_returncode=0 if code==0 and error is None else None,
                sender_returncode_evidence='SSH exit through unchanged passthrough guardian; nonzero sender status unavailable',
                stderr_bytes_seen=seen,stderr_bytes_retained=retained,stderr_truncated=seen>retained,
                stderr_sha256=err_h.hexdigest(),error=error,remote_CPU_or_owned_reap_receipt_available=False,
                diagnostics_limit='Incremental bounded stderr retained; outer guardian receipt is separate. Forced termination may leave no final helper receipt and unknown rc.')


def spool(config_path,receipt_dir):
    raw=owned_read(config_path,s.HEADER_MAX);config=s.decode(raw);argv=sender_argv(config)
    root=new_directory(receipt_dir);save(root/'intent.json',dict(config_pin=pin(config_path,raw),config=config))
    process=None;result={};start=time.monotonic()
    try:
        with create(root/'wire.spool') as wire,create(root/'ssh_stderr.bin') as stderr:
            try:
                process=s.fork_safe_popen(argv)
                result=capture_process(process,wire,stderr,start+120)
            except BaseException as exc:result=dict(capture_complete=False,error=dict(type=type(exc).__name__,message=str(exc)[:2000]))
            finally:
                os.fsync(wire.fileno());os.fsync(stderr.fileno())
    finally:
        if process is not None:
            for f in (process.stdin,process.stdout,process.stderr):
                if f and not f.closed:f.close()
    wire=s.regular(root/'wire.spool');err=s.regular(root/'ssh_stderr.bin')
    receipt=dict(schema='r165_artifact_spool_receipt_v1',
        status='WIRE_SPOOL_COMPLETE_UNVERIFIED_STREAM' if result.get('capture_complete') else 'FAILED_WIRE_SPOOL',
        scope_id=config['scope_id'],job_id=config['job_id'],bindings=config['bindings'],config_pin=pin(config_path,raw),
        wire=dict(path=str(root/'wire.spool'),bytes=wire.st_size,sha256=result.get('wire_sha256') if result.get('wire_bytes')==wire.st_size else None,
                  identity=identity(wire),fingerprint=list(s.fingerprint(wire))),
        stderr=dict(path=str(root/'ssh_stderr.bin'),bytes=err.st_size,sha256=result.get('stderr_sha256') if result.get('stderr_bytes_retained')==err.st_size else None),
        max_bytes=s.BYTE_MAX,max_stream_bytes=WIRE_MAX,original_stream_source_sha256=STREAM_SHA,
        original_supervisor_source_sha256=SUPERVISOR_SHA,original_wire_protocol_validated=False,
        required_outer_guard=dict(cpu=40,wall=120),**result)
    save(root/'spool_receipt.json',receipt)
    return receipt


def decode(spool_receipt_path,fresh_staging_root,receipt_dir):
    fixed_sources();raw=owned_read(spool_receipt_path,s.HEADER_MAX);receipt=s.decode(raw)
    s.require(receipt.get('schema')=='r165_artifact_spool_receipt_v1' and
              receipt.get('status')=='WIRE_SPOOL_COMPLETE_UNVERIFIED_STREAM' and receipt.get('capture_complete') is True and
              type(receipt.get('ssh_returncode')) is int and receipt['ssh_returncode']==0 and
              receipt.get('max_bytes')==s.BYTE_MAX and receipt.get('max_stream_bytes')==WIRE_MAX and
              receipt.get('original_stream_source_sha256')==STREAM_SHA and receipt.get('original_supervisor_source_sha256')==SUPERVISOR_SHA,
              'completed exact frozen-source spool receipt required')
    wire_path=s.physical(receipt['wire']['path']);before=s.regular(wire_path)
    s.require(wire_path.name=='wire.spool' and wire_path.parent==s.physical(spool_receipt_path).parent and
              0<before.st_size<=WIRE_MAX and before.st_size==receipt['wire']['bytes'] and
              identity(before)==receipt['wire']['identity'] and list(s.fingerprint(before))==receipt['wire']['fingerprint'],
              'exact spool role/identity/size differs')
    target=s.physical(fresh_staging_root)
    s.require(target.parent.stat().st_dev==before.st_dev,'offline destination must share spool filesystem')
    root=new_directory(receipt_dir);result=dict(schema='r165_artifact_spool_decode_receipt_v1',status='FAILED_OFFLINE_DECODE',
        scope_id=receipt['scope_id'],job_id=receipt['job_id'],bindings=receipt['bindings'],spool_receipt=pin(spool_receipt_path,raw),
        wire=receipt['wire'],wire_bytes=before.st_size,target_root=str(target),all_frames_verified=False,
        canonical_install_performed=False,required_outer_guard=dict(cpu=20,wall=300))
    try:
        target=new_directory(target);target_state=target.stat();result['target_identity']=identity(target_state)
        with s.source_file(wire_path,s.fingerprint(before)) as f:
            h=hashlib.sha256();remaining=before.st_size
            while remaining:
                block=f.read(min(s.CHUNK,remaining));s.require(block,'wire truncated during SHA');h.update(block);remaining-=len(block)
            s.require(not f.read(1) and h.hexdigest()==receipt['wire']['sha256'],'wire SHA/size differs')
            f.seek(0);s.require(s.exact(f.read,len(s.MAGIC))==s.MAGIC,'wire magic differs')
            size=struct.unpack('!Q',s.exact(f.read,8))[0];s.require(0<size<=s.HEADER_MAX,'wire header bound exceeded')
            header=s.exact(f.read,size);manifest=s.validate_manifest(s.decode(header),s.BYTE_MAX)
            f.seek(0);original=s.receive(target,f.read,s.BYTE_MAX,directory=True)
            s.require(s.fingerprint(os.fstat(f.fileno()))==s.fingerprint(before)==s.fingerprint(s.regular(wire_path)),
                      'wire changed during offline decode')
        s.require(identity(target.stat())==identity(target_state),'target root identity changed')
        digest=hashlib.sha256(header).hexdigest()
        s.require(digest==original['manifest_sha256'],'original receiver manifest differs')
        result.update(status='PASS_OFFLINE_DECODE',all_frames_verified=True,original_receive_receipt=original,
                      payload_bytes=original['bytes'],wire_manifest=manifest,wire_manifest_sha256=digest)
    except BaseException as exc:result['error']=dict(type=type(exc).__name__,message=str(exc)[:2000])
    save(root/'decode_receipt.json',result)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__);mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--spool-config');mode.add_argument('--decode-receipt');parser.add_argument('--target-root')
    parser.add_argument('--receipt-dir',required=True);args=parser.parse_args()
    result=spool(args.spool_config,args.receipt_dir) if args.spool_config else decode(args.decode_receipt,args.target_root,args.receipt_dir)
    print(json.dumps(result,sort_keys=True,allow_nan=False),flush=True)
    return 0 if result['status'] in ('WIRE_SPOOL_COMPLETE_UNVERIFIED_STREAM','PASS_OFFLINE_DECODE') else 1


if __name__=='__main__':raise SystemExit(main())
