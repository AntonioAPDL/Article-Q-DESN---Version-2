"""Fixed direct-Slurm owner; raw results never terminal accounting or acceptance."""
from __future__ import annotations
import hashlib,importlib.util,os,stat,sys
from pathlib import Path
_CONTROL_ROOT=Path(__file__).absolute().parent.parent
_COMMON_SHA="3090fb684b3c8796bc7754b036b5b4c3a1f92a92051f1ccc700e5d3d657900a7"
def _common():
    name="_r203_control_contract";path=_CONTROL_ROOT/"common/contract.py"
    if name in sys.modules:
        module=sys.modules[name]
        if getattr(module,"_r203_source_sha256",None)!=_COMMON_SHA or Path(module.__file__).absolute()!=path:
            raise ValueError("same authenticated Common source/module instance")
        return module
    if any(p.is_symlink() for p in (path,*path.parents)):raise ValueError("physical Common source")
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        before=os.fstat(fd)
        if not(stat.S_ISREG(before.st_mode) and before.st_nlink==1 and before.st_uid==os.getuid() and 0<before.st_size<=1024**2):
            raise ValueError("owned bounded Common source")
        raw=b""
        while len(raw)<=1024**2:
            block=os.read(fd,min(65536,1024**2+1-len(raw)))
            if not block:break
            raw+=block
        after=os.fstat(fd)
    finally:os.close(fd)
    key=lambda v:(v.st_dev,v.st_ino,v.st_size,v.st_mtime_ns,v.st_ctime_ns,v.st_mode,v.st_uid,v.st_nlink)
    if key(before)!=key(after) or key(after)!=key(path.lstat()) or len(raw)!=before.st_size or hashlib.sha256(raw).hexdigest()!=_COMMON_SHA:
        raise ValueError("authenticated captured Common bytes before interpretation")
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);sys.modules[name]=module
    exec(compile(raw,str(path),"exec"),module.__dict__);module._r203_source_sha256=_COMMON_SHA
    return module
c=_common()
m=c.m

import json,time,resource
def _usage():
    a=resource.getrusage(resource.RUSAGE_SELF);b=resource.getrusage(resource.RUSAGE_CHILDREN)
    return {"SELF_user_seconds":a.ru_utime,"SELF_system_seconds":a.ru_stime,
      "CHILDREN_user_seconds":b.ru_utime,"CHILDREN_system_seconds":b.ru_stime,
      "inclusive_CPU_seconds":a.ru_utime+a.ru_stime+b.ru_utime+b.ru_stime,
      "no_sum_of_cumulative_trace_receipts":True}
def _no_children():
    return not(Path("/proc/self/task")/str(os.getpid())/"children").read_text().strip()
def run(template_pin):
    c._job()
    ctx=None;safe=False
    try:
        ctx=c.owner_startup(template_pin);c.wait_and_admit(ctx)
        engine=c.load_control("abi/controller.py" if ctx.stage=="NATIVE_ABI_SUITE" else "deployment/worker.py",ctx)
        evidence=engine.run(ctx);c.require_context(ctx,ctx.stage)
        m.require(type(evidence) is dict,"fixed engine raw dictionary")
        guards=evidence.get("owned_guards");expected=9 if ctx.stage=="NATIVE_ABI_SUITE" else 1
        m.require(type(guards) is list and len(guards)==expected,"exact closed owned-subject count")
        for pin in guards:
            g=m.linked(pin)
            m.require(g.get("schema")=="r157_traced_bootstrap_guard_receipt_v1" and g.get("status")=="EXITED"
              and type(g.get("returncode")) is int and g["returncode"]==0
              and g.get("reaped") is True and g.get("drained") is True and g.get("CPU_accounting_complete") is True
              and g.get("remaining_owned_lifetimes")==[] and g.get("unexpected_untraced_child_waits")==[]
              and g.get("all_newborns_kernel_traced_before_execution") is True
              and g.get("tracer_death_kernel_EXITKILL_enabled") is True,"complete actual trace/reap/drain")
        safe=_no_children();m.require(safe,"no unknown live descendants")
        usage=_usage();ctx.write_metadata("owner_usage.json",usage)
        inv=ctx.write_metadata("proof_inventory.json",c.inventory(ctx))
        raw={"schema":c.CAT["raw_result"]["schema"],"status":c.CAT["raw_result"]["status"],
          "template":ctx.template_pin,"request":ctx.request_pin,"authority":ctx.authority_pin,
          "source_review":ctx.source_review_pin,"owner_review":ctx.owner_review_pin,
          "purpose":ctx.template["purpose"],"nonce":ctx.template["nonce"],"stage":ctx.stage,"job_id":ctx.job_id,"node":ctx.node,
          "owner":ctx.owner,"stage_claim":ctx.stage_claim_pin,"started_epoch":ctx._data["owner_started_epoch"],"ended_epoch":time.time(),
          "control_publication":ctx.template["control_publication"],"control_map_sha256":ctx.control_map_sha256,
          "runtime_publication":ctx.template["runtime_publication"],"runtime_map_sha256":ctx.runtime_map_sha256,
          "parameters_sha256":m.digest(ctx.parameters),"phase_evidence":evidence,"owned_guards":guards,"inventory":inv,"usage":usage,
          "terminal_accounting_pending":True,"runtime_qualified":False,"scientific_acceptance":False}
        m.closed(raw,set(c.CAT["raw_result"]["keys"]),"exact raw result")
        result=ctx.write_metadata("raw_stage_result.json",raw);c.inventory(ctx)
        return {"status":raw["status"],"raw_result":result,"terminal_accounting_pending":True}
    except BaseException as error:
        if ctx is not None:
            try:ctx.write_metadata("stage_failed.json",{"schema":"r203_failed_owned_stage_v1",
              "status":"FAILED_WHOLE_STAGE_FEES_AND_PARTIALS_RETAINED","error":type(error).__name__+": "+str(error),
              "template":template_pin,"automatic_retry":False})
            except BaseException:pass
        raise
    finally:
        if ctx is not None:ctx.close(safe and _no_children())
def main(argv=None):
    c._job()
    args=sys.argv[1:] if argv is None else argv;m.require(len(args)==1,"canonical template PATH only; no cyclic final SHA")
    m.require(Path(args[0]).suffix==".json","CLI template JSON metadata only")
    pin=m.pin_file(m.physical(args[0]));print(json.dumps(run(pin),sort_keys=True));return 0
if __name__=="__main__":raise SystemExit(main())
