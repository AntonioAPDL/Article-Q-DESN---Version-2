"""Fixed owned build/metadata observer. No compiler, ELF or native action on admin."""
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

import datetime,json,resource,time
def _ctx(context):
    c._context_base(context)
    m.require(context.stage in {"FACILITY_PRECHECK","OWNED_NATIVE_BUILD","READONLY_DEPLOYMENT"},"fixed deployment role")
    return c.require_context(context,context.stage)
def _module(pin,name):
    raw=m.source_bytes(pin);spec=importlib.util.spec_from_file_location(name,pin["path"])
    obj=importlib.util.module_from_spec(spec);sys.modules[name]=obj;exec(compile(raw,pin["path"],"exec"),obj.__dict__);return obj
def _trace(ctx,command,prefix,env=None):
    _ctx(ctx);q=ctx.quote;pin=ctx.parameters["common"]["traced_guard"]
    m.require(pin["sha256"]==c.BASE["original_tracer"]["sha256"],"unchanged owned bootstrap tracer")
    trace=_module(pin,"_r203_fixed_deployment_tracer")
    stdout=ctx.open_slot(prefix+".stdout");stderr=ctx.open_slot(prefix+".stderr")
    file_ceiling=min(stdout.maximum_bytes,stderr.maximum_bytes,c.MAX_FILE)
    m.integer(file_ceiling,"actual paid output kernel ceiling",1,c.MAX_FILE)
    def limits():
        for kind,bound in ((resource.RLIMIT_CPU,q["child_CPU_seconds"]),(resource.RLIMIT_FSIZE,file_ceiling)):
            soft,hard=resource.getrlimit(kind)
            nextsoft=bound if soft==resource.RLIM_INFINITY else min(soft,bound)
            nexthard=bound if hard==resource.RLIM_INFINITY else min(hard,bound)
            resource.setrlimit(kind,(nextsoft,nexthard))
        resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    def peer(lifetimes):
        _ctx(ctx)
        for old in lifetimes:
            actual=trace.identity(old["pid"])
            m.require(trace.same_lifetime(actual,old) and actual["TracerPid"]==os.getpid(),
              "current exact owned ptrace lifetimes")
        return {"job_id":ctx.job_id,"owned_lifetimes":len(lifetimes)}
    base_environment=ctx.parameters["common"]["environment"]
    c.validate_environment(base_environment)
    environment=dict(base_environment,SLURM_JOB_ID=ctx.job_id,SLURMD_NODENAME=ctx.node,
      R154_GLOBAL_PERMIT_LOCK_FD=str(ctx.permit_fd))
    if env is not None:
        m.require(ctx.stage=="OWNED_NATIVE_BUILD" and type(env) is dict and
          env=={"TMPDIR":str(Path(ctx.parameters["stage"]["build_directory"])/"r203_compiler_tmp")},
          "only exact owned compiler temporary directory override")
        environment.update(env)
    try:
        guard=trace.run_traced(command,env=environment,stdout=stdout,stderr=stderr,lock_fd=ctx.permit_fd,
          affinity=ctx.request["affinity"],wall_seconds=q["owner_wall_seconds"],
          maximum_combined_CPU_seconds=q["owner_CPU_seconds"],
          absolute_deadline_UTC=datetime.datetime.fromtimestamp(ctx.stage_deadline_epoch,datetime.timezone.utc).isoformat(),
          peer_callback=peer,bootstrap_exec_allowlist=ctx.parameters["common"]["exec_allowlist"],
          owner_path=None,scope=ctx.template["purpose"],source={"kind":"R203_FIXED_PRE_NATIVE_STAGE","stage":ctx.stage,
          "control_map_sha256":ctx.control_map_sha256,"runtime_map_sha256":ctx.runtime_map_sha256},
          authority_pin=ctx.authority_pin,preexec_fn=limits,require_science_handshake=False)
        outpin=ctx.finalize_stream(prefix+".stdout");errpin=ctx.finalize_stream(prefix+".stderr")
    finally:stdout.close();stderr.close()
    guardpin=ctx.write_metadata(prefix+".guard.json",guard)
    m.require(guard.get("schema")=="r157_traced_bootstrap_guard_receipt_v1" and guard.get("status")=="EXITED"
      and guard.get("returncode")==0 and all(guard.get(k) is True for k in
      ("reaped","drained","CPU_accounting_complete","all_newborns_kernel_traced_before_execution","tracer_death_kernel_EXITKILL_enabled"))
      and guard.get("remaining_owned_lifetimes")==[] and guard.get("unexpected_untraced_child_waits")==[],
      "actual complete one owned compiler/observer trace")
    return guardpin,outpin,errpin,guard
def _linked(ctx,pin):return ctx._proofs.linked(pin)
def _accepted(ctx,pin,kind):
    v=_linked(ctx,pin)
    if kind=="build":
        expected=("r201_owned_native_build_acceptance_v1","CANDIDATE_SOURCE_BUILD_ONLY_AWAIT_H5","ACCEPTED_SOURCE_BUILD_ONLY_NOT_RUNTIME","PASS_REVIEWED_R201_NATIVE_BUILD")
    elif kind=="facility":
        expected=("r203_same_path_facility_acceptance_v1","CANDIDATE_R203_FACILITY_ROUTE_AWAIT_H5",
          "ACCEPTED_R203_SAME_PATH_FACILITY_ROUTE_NOT_DEPLOYMENT","PASS_REVIEWED_R203_SAME_PATH_FACILITY_ROUTE")
    else:raise ValueError("closed prerequisite")
    schema,candidate,status,review_status=expected
    m.require(v.get("schema")==schema and v.get("source_map_sha256")==ctx.runtime_map_sha256,"applicable same-source prerequisite")
    c._promoted(v,candidate,status,ctx._proofs)
    result=_linked(ctx,v["result"]);review=_linked(ctx,v["independent_review"]);account=_linked(ctx,v["accounting"])
    m.require(review.get("status")==review_status and review.get("result")==v["result"] and review.get("accounting")==v["accounting"]
      and account.get("terminal") is True and account.get("complete") is True and account.get("primary_charge_counted_once") is True
      and account.get("job_id")==result.get("job_id") and result.get("source_map_sha256")==ctx.runtime_map_sha256,
      "actual completed independent prerequisite/accounting")
    return v,result
def _build(ctx):
    _ctx(ctx);p=ctx.parameters["stage"];began=time.time()
    facility,route=_accepted(ctx,p["facility_precheck"],"facility")
    m.require(route.get("same_path_facility_route_observed") is True and route.get("canonical_output_library")==p["output_library"],
      "real applicable same-path facility route before compiler work")
    tool=_linked(ctx,p["toolchain_closure"])
    m.closed(tool,{"schema","exec_allowlist","files","native_dependencies","independent_review"},"fixed toolchain closure")
    m.require(tool["schema"]=="r203_native_toolchain_closure_v1"
      and tool["exec_allowlist"]==ctx.parameters["common"]["exec_allowlist"],"fixed complete compiler/helper closure")
    review=_linked(ctx,tool["independent_review"]);core=dict(tool);core.pop("independent_review")
    m.require(review.get("status")=="PASS_REVIEWED_R203_IMMUTABLE_NATIVE_TOOLCHAIN"
      and review.get("toolchain_core_sha256")==m.digest(core),"independent exact native toolchain closure")
    paths=[]
    for row in tool["files"]:
        m.closed(row,{"path","sha256","bytes"},"actual build dependency")
        uid=m.physical(row["path"]).lstat().st_uid;m.require(uid in {0,os.getuid()},"immutable toolchain root/owned UID")
        m.read_regular(row["path"],limit=64*1024**2,expected_sha=row["sha256"],expected_bytes=row["bytes"],expected_uid=uid);paths.append(row["path"])
    c._mount_rows(paths)
    directory=m.physical(p["build_directory"]);st=directory.stat()
    m.require(stat.S_ISDIR(st.st_mode) and st.st_uid==os.getuid() and stat.S_IMODE(st.st_mode)==0o700,
      "facility-provided dedicated writable final compiler directory")
    output=directory/"r201_native_boundary.so"
    m.require(str(output)==p["output_library"] and not output.exists(),"fresh exact final canonical compiler output")
    temporary=directory/"r203_compiler_tmp";temporary.mkdir(mode=0o700)
    request={"schema":"r201_native_build_request_v1","purpose":ctx.template["purpose"],"nonce":ctx.template["nonce"],
      "source":p["source"],"header":p["header"],"abi":p["abi"],"compiler":p["compiler"],
      "working_directory":str(directory),"output_library":str(output),"source_review":ctx.source_review_pin,
      "scope":ctx.template["scope"],"ledger":ctx.template["ledger"],"price":ctx.template["quote"],"owner":ctx.owner}
    render=_module(ctx.runtime_sources["native_python/build_contract.py"],"_r203_unchanged_pure_build_renderer").render(request)
    guardpin,outpin,errpin,guard=_trace(ctx,render["argv"],"build",env={"TMPDIR":str(temporary)})
    events=guard.get("events")
    m.require(type(events) is list,"actual original trace event schema")
    events=[r for r in events if r.get("event")=="EXEC"]
    m.require(type(events) is list and 1<=len(events)<=p["maximum_compiler_execs"],"exact bounded compiler/helper execution accounting")
    blob=m.read_regular(output,limit=c.MAX_FILE,expected_uid=os.getuid());m.require(len(blob)>0,"complete actual native output")
    after=output.stat();library={"path":str(output),"sha256":hashlib.sha256(blob).hexdigest()}
    return {"schema":"r203_raw_native_build_evidence_v1","source_map_sha256":ctx.runtime_map_sha256,"build_request":request,
      "compiler_argv":render["argv"],"output_library":library,"output_bytes":len(blob),
      "output_identity":{"path":str(output),"device":after.st_dev,"inode":after.st_ino,"uid":after.st_uid,"mode":stat.S_IMODE(after.st_mode)},
      "dependencies":tool["native_dependencies"],"build_guard":guardpin,"build_source_review":ctx.source_review_pin,
      "toolchain_closure":p["toolchain_closure"],"facility_precheck":p["facility_precheck"],
      "optimizer_invocations":0,"scientific_target_data_read":False,"started_epoch":began,"ended_epoch":time.time(),
      "stdout":outpin,"stderr":errpin,"owned_guards":[guardpin],"terminal_accounting_pending":True}
def _metadata_files(ctx,pins):
    rows=[]
    for pin in pins:
        value=_linked(ctx,pin);raw=m.read_regular(pin["path"],limit=4*1024**2,expected_sha=pin["sha256"],expected_uid=os.getuid())
        rows.append({"path":pin["path"],"sha256":pin["sha256"],"bytes":len(raw)})
    return rows
def _observe(ctx):
    c._context_base(ctx);c.require_context(ctx,ctx.stage)
    m.require(ctx._kind=="SUBJECT","metadata observations only in actual fixed traced observer child")
    p=ctx.parameters["stage"];began=time.time()
    if ctx.stage=="FACILITY_PRECHECK":
        plan=_linked(ctx,p["facility_plan"]);parent=m.physical(p["output_library"]).parent
        reasons=[];authority=plan.get("operator_capability_evidence")
        if authority is None:reasons.append("Missing independently evidenced facility same-path sealing capability")
        else:
            capability=_linked(ctx,authority)
            if not(capability.get("same_path_transition_observed") is True and capability.get("controller_mounts_or_privilege_operations") is False):
                reasons.append("Facility capability observation is incomplete or unsupported")
        if not parent.is_dir() or not os.access(parent,os.W_OK):reasons.append("Dedicated canonical build parent is not currently provisioned/writable")
        if Path(p["output_library"]).exists():reasons.append("Canonical build output already exists")
        return {"schema":"r203_raw_facility_precheck_evidence_v1","source_map_sha256":ctx.runtime_map_sha256,
          "facility_plan":p["facility_plan"],"node":ctx.node,"canonical_output_library":p["output_library"],
          "same_path_facility_route_observed":not reasons,"stop_reasons":reasons,
          "canonical_metadata_files":_metadata_files(ctx,p["canonical_metadata_inputs"]),
          "controller_mounts_or_privilege_operations":False,"optimizer_invocations":0,"scientific_target_data_read":False,
          "started_epoch":began,"ended_epoch":time.time(),"accepted_deployment":False}
    m.require(ctx.stage=="READONLY_DEPLOYMENT","fixed posttransition observer stage")
    accepted,built=_accepted(ctx,p["build_acceptance"],"build")
    manifest=_linked(ctx,p["native_build_manifest"])
    _module(ctx.runtime_sources["native_python/build_contract.py"],"_r203_pure_manifest_validator").validate_manifest_shape(manifest)
    m.require(accepted["native_build_manifest"]==p["native_build_manifest"] and accepted["native_library"]==p["native_library"]
      and manifest["output_library"]==p["native_library"] and manifest["abi"]==p["native_abi"],
      "unchanged actual compiler argv/output/manifest/library identity; no relocation")
    pins=list(ctx.control_sources.values())+list(ctx.runtime_sources.values())+p["baseline_files"]+[p["native_library"],p["native_abi"]]
    files=[]
    for pin in pins:
        uid=m.physical(pin["path"]).lstat().st_uid;m.require(uid in {0,os.getuid()},"immutable observed root/owned UID")
        raw=m.read_regular(pin["path"],limit=64*1024**2,expected_sha=pin["sha256"],expected_uid=uid);st=Path(pin["path"]).stat()
        files.append({"path":pin["path"],"sha256":pin["sha256"],"bytes":len(raw),"device":st.st_dev,"inode":st.st_ino,
          "mode":stat.S_IMODE(st.st_mode),"uid":st.st_uid})
    readonly=c._mount_rows([pin["path"] for pin in pins])
    return {"schema":"r203_raw_readonly_deployment_evidence_v1","source_map_sha256":ctx.runtime_map_sha256,
      "runtime_publication":ctx.template["runtime_publication"],"build_acceptance":p["build_acceptance"],
      "native_build_manifest":p["native_build_manifest"],"native_library":p["native_library"],"native_abi":p["native_abi"],
      "baseline_files":p["baseline_files"],"files":files,"readonly_files":readonly,
      "canonical_metadata_files":_metadata_files(ctx,p["canonical_metadata_inputs"]),"read_only_backing_verified":True,
      "same_canonical_output_path":True,"no_original_JSON_rewrite":True,"optimizer_invocations":0,
      "scientific_target_data_read":False,"started_epoch":began,"ended_epoch":time.time()}
def run(context):
    ctx=_ctx(context)
    if ctx.stage=="OWNED_NATIVE_BUILD":return _build(ctx)
    case="facility_observer" if ctx.stage=="FACILITY_PRECHECK" else "readonly_observer"
    issued=time.time();descriptor={"schema":"r203_control_subject_descriptor_v1","request":ctx.request_pin,"authority":ctx.authority_pin,
      "stage_claim":ctx.stage_claim_pin,"case_id":case,"ordinal":1,"owner":ctx.owner,"job_id":ctx.job_id,"node":ctx.node,
      "root":str(ctx.root),"permit_fd":ctx.permit_fd,"native_deadline_epoch":ctx.stage_deadline_epoch,
      "issued_epoch":issued,"expires_epoch":ctx.stage_deadline_epoch}
    pin=ctx.write_metadata("observer_descriptor.json",descriptor)
    command=[ctx.parameters["common"]["startup_python"]["path"],"-I","-B",ctx.control_sources["deployment/worker.py"]["path"],
      pin["path"],pin["sha256"],case]
    guardpin,outpin,errpin,guard=_trace(ctx,command,"observer")
    raw=m.read_regular(outpin["path"],limit=c.MAX_FILE,expected_sha=outpin["sha256"],expected_uid=os.getuid())
    evidence=m.strict_json(raw);m.require(type(evidence) is dict and evidence.get("schema") in
      {"r203_raw_facility_precheck_evidence_v1","r203_raw_readonly_deployment_evidence_v1"},"complete fixed raw observer stdout")
    evidence.update(owned_guards=[guardpin],stdout=outpin,stderr=errpin,terminal_accounting_pending=True)
    return evidence
def main(argv=None):
    c._job(subject=True)
    args=sys.argv[1:] if argv is None else argv;m.require(len(args)==3 and args[2] in {"facility_observer","readonly_observer"},"fixed observer CLI")
    ctx=c.enter_subject({"path":args[0],"sha256":args[1]},args[2])
    print(json.dumps(_observe(ctx),sort_keys=True,separators=(",",":")),flush=True);return 0
if __name__=="__main__":raise SystemExit(main())
