"""Fresh fixed native-only ABI subject; never an administrative fixture."""
import errno
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import resource
import signal
import sys
import time
ROOT=Path(__file__).absolute().parent.parent
ABI_CONTRACT_SHA="0d6ae35a0b2d20af4ff1f9db8d511d9564bbc686e3c9434bca3f71c6c6d06c7d"

def _actual_gate():
    job=os.environ.get("SLURM_JOB_ID","")
    if re.fullmatch("[1-9][0-9]{0,19}",job) is None:raise ValueError("actual Slurm before records")
    rows=dict(z.split(":",1) for z in Path("/proc/self/status").read_text().splitlines() if ":" in z)
    cgroup=Path("/proc/self/cgroup").read_text()
    if int(rows["TracerPid"])!=os.getppid() or "slurm" not in cgroup or not re.search(
      r"(?:^|/)job_"+re.escape(job)+r"(?:/|\n|$)",cgroup):
        raise ValueError("actual traced same-parent subject before records")

def _contract():
    path=ROOT/"abi/contract.py";raw=path.read_bytes()
    if any(p.is_symlink() for p in (path,*path.parents)) or not re.fullmatch("[0-9a-f]{64}",ABI_CONTRACT_SHA) or hashlib.sha256(raw).hexdigest()!=ABI_CONTRACT_SHA:
        raise ValueError("exact ABI contract before interpretation")
    name="_r203_abi_contract";module=sys.modules.get(name)
    if module is not None:
        if module.__file__!=str(path) or getattr(module,"_r203_source_sha256",None)!=ABI_CONTRACT_SHA:
            raise ValueError("same ABI contract")
        return module
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec)
    sys.modules[name]=module;exec(compile(raw,str(path),"exec"),module.__dict__)
    module._r203_source_sha256=ABI_CONTRACT_SHA;return module

def _narrow(c,case):
    for kind,bound in ((resource.RLIMIT_CPU,case["child_CPU_seconds"]),
                       (resource.RLIMIT_FSIZE,c.FILE_CAP)):
        soft,hard=resource.getrlimit(kind)
        nextsoft=bound if soft==resource.RLIM_INFINITY else min(soft,bound)
        nexthard=bound if hard==resource.RLIM_INFINITY else min(hard,bound)
        c.require(nextsoft>0 and nexthard>0,"nonzero narrower child limit")
        resource.setrlimit(kind,(nextsoft,nexthard))
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))

def _file(c,path):
    raw=c.captured(path,c.FILE_CAP);s=Path(path).stat()
    return dict(path=str(path),sha256=hashlib.sha256(raw).hexdigest(),bytes=len(raw),
      device=s.st_dev,inode=s.st_ino,mode=s.st_mode&0o777,uid=s.st_uid,nlink=s.st_nlink)

def _ascii_slot(ctx,name,value):
    with ctx.open_slot(name,"r+b") as stream:
        stream.write(value);stream.flush();os.fsync(stream.fileno())
        ctx.finalize_stream(name,stream.tell())

def main(argv=None):
    _actual_gate()
    args=sys.argv[1:] if argv is None else argv
    if len(args)!=2:raise ValueError("exact descriptor path/SHA")
    match=re.fullmatch(r"abi_descriptor_(0[1-9])\.json",Path(args[0]).name)
    if match is None:raise ValueError("fixed descriptor ordinal filename")
    c=_contract();ordinal=int(match[1]);case_id=c.CASES[ordinal-1][0]
    descriptor={"path":args[0],"sha256":args[1]}
    ctx=c.common().enter_subject(descriptor,case_id)
    stage,policy=c.policy(ctx);case=policy["cases"][ordinal-1]
    c.require(ctx.ordinal==ordinal and ctx.case_id==case_id,"actual fixed child descriptor")
    _narrow(c,case)
    native=c.load_fixed(ctx,"abi/native_abi.py","_r203_native_ABI")
    api=native.Native(ctx)
    observations={}
    if case_id=="noreplace_collision":
        _ascii_slot(ctx,"abi_noreplace_collision.partial",b"retained ABI collision partial\n")
        _ascii_slot(ctx,"abi_noreplace_collision.final",b"retained ABI preexisting final\n")
        observations["before"]={name:_file(c,ctx.root/name) for name in
          ("abi_noreplace_collision.partial","abi_noreplace_collision.final")}
    elif case_id=="bounded_storage":
        _ascii_slot(ctx,"abi_bounded_storage.payload.partial",b"bounded ABI ASCII payload\n")
        observations["payload_before"]=_file(c,ctx.root/"abi_bounded_storage.payload.partial")
        c.require(not(ctx.root/"abi_bounded_storage.payload.final").exists(),"NOREPLACE final initially absent")
    ready_epoch=time.time();ready_monotonic=time.monotonic()
    expiry,derivation=c.native_expiry_metadata(case_id,ready_epoch,ready_monotonic,
      ctx.native_deadline_epoch,ctx.stage_deadline_epoch)
    frame=c.ready_frame(ctx,descriptor,expiry)
    print(json.dumps(frame,sort_keys=True,separators=(",",":")),flush=True)
    if case_id=="wrong_permit":
        actual=os.fstat(ctx.permit_fd)
        try:os.fstat(2147483647)
        except OSError as exc:
            c.require(exc.errno==errno.EBADF,"actual wrong argument EBADF")
            observations["wrong_native_argument"]=dict(requested_fd=2147483647,actual_fstat_errno=exc.errno,
              Root_permit_fd=ctx.permit_fd,Root_permit_device=actual.st_dev,Root_permit_inode=actual.st_ino,
              coverage="WRONG_NATIVE_ARGUMENT_NOT_EVERY_LIVE_WRONG_INODE")
        else:raise ValueError("fixed wrong argument unexpectedly available")
    prepared=api.prepare(expiry)
    if prepared["return_value"]==0:
        if case_id=="pre_ack_live":api.live()
        elif case_id in ("wrong_lifetime","wrong_permit"):pass
        elif case_id=="late_transition":
            observations["prepare_before_native_expiry"]=prepared["finished_epoch"]<expiry
            c.require(observations["prepare_before_native_expiry"],"INCONCLUSIVE prepare missed native expiry")
            while time.time()<expiry+1:
                c.require(time.time()<ctx.stage_deadline_epoch and
                  time.monotonic()-ready_monotonic<case["wall_seconds"],"unchanged fullstage wait bound")
                time.sleep(min(0.02,max(0.0,expiry+1-time.time())))
            observations["transition_attempt_epoch"]=time.time();api.boundary()
        else:
            boundary=api.boundary()
            if boundary["return_value"]==0:
                if case_id=="repeat_transition":
                    api.receipt();api.boundary()
                elif case_id=="real_ACK":
                    api.live();api.receipt()
                elif case_id=="live_rechecks":
                    observations["first_identity"]=c.actual_identity()
                    api.live();api.receipt()
                    observations["second_identity"]=c.actual_identity()
                    api.live();api.receipt()
                elif case_id=="noreplace_collision":
                    api.receipt()
                    fd=os.open(ctx.root,os.O_RDONLY|os.O_DIRECTORY|os.O_CLOEXEC|os.O_NOFOLLOW)
                    try:api.rename(fd,"abi_noreplace_collision.partial","abi_noreplace_collision.final")
                    finally:os.close(fd)
                    observations["after"]={name:_file(c,ctx.root/name) for name in observations["before"]}
                elif case_id=="bounded_storage":
                    fd=os.open(ctx.root,os.O_RDONLY|os.O_DIRECTORY|os.O_CLOEXEC|os.O_NOFOLLOW)
                    try:renamed=api.rename(fd,"abi_bounded_storage.payload.partial","abi_bounded_storage.payload.final")
                    finally:os.close(fd)
                    observations["rename_source_absent"]=not(ctx.root/"abi_bounded_storage.payload.partial").exists()
                    observations["payload_after"]=_file(c,ctx.root/"abi_bounded_storage.payload.final")
                    with ctx.open_slot("abi_bounded_storage.cap_probe.partial","r+b") as stream:
                        block=b"A"*4096
                        for _ in range(c.FILE_CAP//len(block)):stream.write(block)
                        stream.flush();os.fsync(stream.fileno())
                        before=os.fstat(stream.fileno());old=signal.signal(signal.SIGXFSZ,signal.SIG_IGN)
                        overflow_errno=None
                        try:
                            try:os.write(stream.fileno(),b"!")
                            except OSError as exc:overflow_errno=exc.errno
                        finally:signal.signal(signal.SIGXFSZ,old)
                        after=os.fstat(stream.fileno())
                        observations["kernel_cap_probe"]=dict(limit_bytes=c.FILE_CAP,
                          actual_RLIMIT_FSIZE=list(resource.getrlimit(resource.RLIMIT_FSIZE)),
                          before_bytes=before.st_size,after_bytes=after.st_size,
                          actual_errno=overflow_errno,actual_cursor=stream.tell(),
                          coverage="ABI_CONTROL_ASCII_KERNEL_FSIZE_NOT_PRODUCTION_WRITER")
                        ctx.finalize_stream("abi_bounded_storage.cap_probe.partial",stream.tell())
                    api.live();api.receipt()
    result=dict(schema="r203_ABI_subject_raw_result_v1",status="RAW_NATIVE_SUBJECT_FACTS_NOT_ACCEPTED",
      case_id=case_id,ordinal=ordinal,descriptor=descriptor,request=ctx.request_pin,authority=ctx.authority_pin,
      job_id=ctx.job_id,node=ctx.node,owner=ctx.owner,child=c.actual_identity(),
      runtime_map_sha256=ctx.runtime_map_sha256,control_map_sha256=ctx.control_map_sha256,native_role=1,
      native_deadline_upper_bound_epoch=ctx.native_deadline_epoch,actual_native_expiry_epoch=expiry,
      expiry_derivation=derivation,abi_probe=api.probe,operations=api.operations,observations=observations,
      no_target_data=True,no_optimizer_or_fit=True)
    c.raw_result_shape(result)
    print(json.dumps(result,sort_keys=True,separators=(",",":")),flush=True)
    return 0
if __name__=="__main__":raise SystemExit(main())
