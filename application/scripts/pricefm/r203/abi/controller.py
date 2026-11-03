"""Actual admitted ABI stage: one founder observation and nine owned subjects.

Raw facts only. The independently authored Root peer reconstructs required cases
after complete terminal accounting; this engine never emits an accepted suite.
"""
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
TRACER_SHA="914d7d369d68579b7149c5130e3bba5d59f3b8f09a5bf691e1557ccbcd40c963"

def _contract():
    path=ROOT/"abi/contract.py";raw=path.read_bytes()
    if any(p.is_symlink() for p in (path,*path.parents)) or not re.fullmatch("[0-9a-f]{64}",ABI_CONTRACT_SHA) or hashlib.sha256(raw).hexdigest()!=ABI_CONTRACT_SHA:
        raise ValueError("fixed ABI contract before interpretation")
    name="_r203_abi_contract";old=sys.modules.get(name)
    if old is not None:
        if old.__file__!=str(path) or getattr(old,"_r203_source_sha256",None)!=ABI_CONTRACT_SHA:
            raise ValueError("same ABI contract instance")
        return old
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec)
    sys.modules[name]=module;exec(compile(raw,str(path),"exec"),module.__dict__)
    module._r203_source_sha256=ABI_CONTRACT_SHA
    return module

def _usage():
    own=resource.getrusage(resource.RUSAGE_SELF);children=resource.getrusage(resource.RUSAGE_CHILDREN)
    return dict(SELF_CPU_seconds=own.ru_utime+own.ru_stime,
      all_waited_CHILDREN_CPU_seconds=children.ru_utime+children.ru_stime,observed_epoch=time.time())

def _proc_parent(c):
    pid=os.getppid()
    def text(leaf):
        with open("/proc/%d/%s"%(pid,leaf)) as stream:value=stream.read(16385)
        c.require(len(value)<=16384,"bounded actual parent metadata");return value
    raw=text("stat");tail=raw[raw.rindex(")")+2:].split()
    rows=dict(line.split(":",1) for line in text("status").splitlines() if ":" in line)
    return dict(pid=pid,start_ticks=int(tail[19]),uid=[int(x) for x in rows["Uid"].split()],
      ppid=int(tail[1]),tracer_pid=int(rows["TracerPid"]),
      boot_id=Path("/proc/sys/kernel/random/boot_id").read_text().strip())

def _permit(c,ctx):
    c.require_context(ctx);s=os.fstat(ctx.permit_fd)
    with open("/proc/self/fdinfo/%d"%ctx.permit_fd) as stream:text=stream.read(8193)
    c.require(len(text)<=8192,"bounded exact own permit fdinfo")
    locks=[]
    for line in text.splitlines():
        if line.startswith("lock:"):
            m=re.fullmatch(r"lock:\s+[0-9]+:\s+FLOCK\s+ADVISORY\s+WRITE\s+([0-9]+)\s+([0-9a-f]+):([0-9a-f]+):([0-9]+)\s+0\s+EOF",line)
            c.require(m is not None,"actual exact own kernel FLOCK")
            locks.append(dict(holder_pid=int(m[1]),major=int(m[2],16),minor=int(m[3],16),inode=int(m[4])))
    c.require(len(locks)==1 and locks[0]==dict(holder_pid=os.getpid(),major=os.major(s.st_dev),
      minor=os.minor(s.st_dev),inode=s.st_ino),"real current owner-held permit")
    return dict(fd=ctx.permit_fd,device=s.st_dev,inode=s.st_ino,uid=s.st_uid,mode=s.st_mode&0o777,
      kernel_FLOCK=locks[0],fdinfo_sha256=hashlib.sha256(text.encode()).hexdigest())

def _kernel_state(c,ctx):
    c.require_context(ctx)
    # Actual read-only kernel queries only AFTER the real compute context.
    import ctypes
    import fcntl
    libc=ctypes.CDLL(None,use_errno=True);value=ctypes.c_int()
    c.require(libc.prctl(37,ctypes.byref(value),0,0,0)==0,"actual child-subreaper query")
    scan=os.open("/proc/self/fd",os.O_RDONLY|os.O_DIRECTORY|os.O_CLOEXEC)
    fds={}
    try:
        for name in os.listdir(scan):
            if not name.isdigit() or int(name)==scan:continue
            fd=int(name)
            try:s=os.fstat(fd)
            except OSError:continue
            fds[name]=dict(device=s.st_dev,inode=s.st_ino,mode=s.st_mode,
              flags=fcntl.fcntl(fd,fcntl.F_GETFL),descriptor_flags=fcntl.fcntl(fd,fcntl.F_GETFD))
    finally:os.close(scan)
    c.require(signal.getsignal(signal.SIGCHLD)==signal.SIG_DFL,"default SIGCHLD remains")
    return dict(subreaper=value.value,fd_set=fds,permit=_permit(c,ctx))

def _tracer(c,ctx):
    record=ctx.parameters["common"]["traced_guard"]
    c.require(record["sha256"]==TRACER_SHA,"unchanged original r157 trace helper")
    raw=c.captured(record["path"]);c.require(hashlib.sha256(raw).hexdigest()==TRACER_SHA,"actual tracer source")
    name="_r203_original_r157";old=sys.modules.get(name)
    if old is not None:
        c.require(old.__file__==record["path"] and old._r203_source_sha256==TRACER_SHA,"one exact tracer module")
        return old
    spec=importlib.util.spec_from_file_location(name,record["path"]);module=importlib.util.module_from_spec(spec)
    sys.modules[name]=module;exec(compile(raw,record["path"],"exec"),module.__dict__)
    module._r203_source_sha256=TRACER_SHA
    return module

def _founder(c,ctx,native):
    identity=c.actual_identity();parent=_proc_parent(c);permit=_permit(c,ctx)
    c.require(identity["tracer_pid"]==0 and identity["pid"]==ctx.owner["pid"]
      and parent["pid"]==identity["ppid"] and parent["start_ticks"]>0,"actual direct-Slurm founder/parent")
    env={key:os.environ.get(key) for key in ("R154_GLOBAL_PERMIT_LOCK_FD","R157_FILTER_PROOF_FD",
                                           "R157_FILTER_ACK_FD","R157_FILTER_TOKEN")}
    c.require(all(env[k] is None for k in ("R157_FILTER_PROOF_FD","R157_FILTER_ACK_FD","R157_FILTER_TOKEN")),
      "INCONCLUSIVE unexpected inherited handshake; no fake pipes")
    matrix=dict(actual_tracer_pid=0,parent_is_actual_kernel_tracer=False,
      parent_holds_expected_FLOCK=permit["kernel_FLOCK"]["holder_pid"]==parent["pid"],
      actual_FLOCK_holder_pid=permit["kernel_FLOCK"]["holder_pid"],
      R154_environment_matches=env["R154_GLOBAL_PERMIT_LOCK_FD"]==str(ctx.permit_fd),
      real_proof_pipe_available=False,real_ACK_pipe_available=False,real_original_token_available=False,
      expected_first_error="exact inherited original handshake unavailable",
      unavailable_required_facts=[])
    api=native.Native(ctx);api.prepare(ctx.stage_deadline_epoch,founder_parent=parent)
    result=dict(schema="r203_ABI_founder_raw_observation_v1",status="RAW_FOUNDER_NATIVE_OBSERVATION_NOT_ACCEPTED",
      request=ctx.request_pin,authority=ctx.authority_pin,job_id=ctx.job_id,node=ctx.node,
      owner=identity,actual_parent=parent,actual_tracer_pid=0,native_role=1,
      native_expiry_epoch=ctx.stage_deadline_epoch,permit=permit,environment_preconditions=env,
      unmet_precondition_matrix=matrix,abi_probe=api.probe,operations=api.operations,
      isolated_trace_predicate_proved=False,private_terminal_state_observed=None,no_target_data=True)
    proof=ctx.write_metadata("abi_founder_observation.json",result)
    row=api.operations[0]
    c.require(len(api.operations)==1 and row["operation"]=="r201_prepare_v1" and
      row["return_value"]==-1 and row["errno"]==1 and
      row["first_error"]==matrix["expected_first_error"],"founder raw native facts inconsistent; no acceptance")
    return dict(pin=proof,value=result)

def _guard(c,g,case):
    flags=("reaped","drained","CPU_accounting_complete","all_newborns_kernel_traced_before_execution",
           "tracer_death_kernel_EXITKILL_enabled")
    c.require(g.get("schema")=="r157_traced_bootstrap_guard_receipt_v1" and g.get("status")=="EXITED"
      and type(g.get("returncode")) is int and g["returncode"]==0 and
      all(g.get(k) is True for k in flags) and g.get("remaining_owned_lifetimes")==[]
      and g.get("unexpected_untraced_child_waits")==[],"actual complete original subject guard")
    if case["handshake"]:
        att=g.get("scientific_filter_kernel_attestation") or {}
        c.require(g.get("postbootstrap_TSYNC_scientific_fork_denial") is True and
          g.get("scientific_target_access_handshake") is True and
          att.get("operation")=="SECCOMP_SET_MODE_FILTER" and att.get("flags")=="TSYNC"
          and att.get("kernel_return")==0,"actual kernel TSYNC/token/ACK")
    else:
        c.require(g.get("postbootstrap_TSYNC_scientific_fork_denial") is False and
          g.get("scientific_target_access_handshake") is False and
          g.get("scientific_filter_kernel_attestation") is None,"negative no-ACK guard remains honest")

def _expected(c,result):
    # Operational fail-closed checks only. Independent Root peer never calls this
    # producer validator and does not accept its output as qualification.
    c.raw_result_shape(result);case=result["case_id"];ops=result["operations"]
    names={"pre_ack_live":["r201_prepare_v1","r201_validate_live_v1"],
      "wrong_lifetime":["r201_prepare_v1"],"wrong_permit":["r201_prepare_v1"],
      "late_transition":["r201_prepare_v1","r201_scientific_boundary_v1"],
      "repeat_transition":["r201_prepare_v1","r201_scientific_boundary_v1","r201_receipt_v1","r201_scientific_boundary_v1"],
      "real_ACK":["r201_prepare_v1","r201_scientific_boundary_v1","r201_validate_live_v1","r201_receipt_v1"],
      "live_rechecks":["r201_prepare_v1","r201_scientific_boundary_v1","r201_validate_live_v1","r201_receipt_v1",
                       "r201_validate_live_v1","r201_receipt_v1"],
      "noreplace_collision":["r201_prepare_v1","r201_scientific_boundary_v1","r201_receipt_v1","r201_rename_noreplace_v1"],
      "bounded_storage":["r201_prepare_v1","r201_scientific_boundary_v1","r201_rename_noreplace_v1",
                         "r201_validate_live_v1","r201_receipt_v1"]}
    errors={"pre_ack_live":"actual once-earned native lifetime is no longer live",
      "wrong_lifetime":"actual owner trace permit or handshake pipe mismatch",
      "wrong_permit":"inherited permit missing",
      "late_transition":"actual prepared owner required before once-only kernel transition",
      "repeat_transition":"actual prepared owner required before once-only kernel transition",
      "noreplace_collision":"existing or unprovable final refuses without cleanup"}
    c.require([o["operation"] for o in ops]==names[case],"exact native operation sequence")
    for index,row in enumerate(ops):
        failure=case in errors and index==len(ops)-1
        c.require(row["return_value"]==(-1 if failure else 0),"unexpected native return stops whole stage")
        if failure:c.require(row["errno"]==1 and row["first_error"]==errors[case],"exact native first refusal")
    obs=result["observations"]
    if case=="wrong_permit":
        wrong=obs["wrong_native_argument"]
        c.require(wrong["requested_fd"]==2147483647 and wrong["actual_fstat_errno"]==9
          and ops[0]["arguments"]["permit_fd"]==2147483647,"actual invalid native argument, Root permit intact")
    if case=="late_transition":
        c.require(obs["prepare_before_native_expiry"] is True and
          obs["transition_attempt_epoch"]>=result["actual_native_expiry_epoch"]+1,"actual post-prepare expiry")
    if case=="noreplace_collision":
        c.require(obs["before"]==obs["after"],"collision must preserve both paid files")
    if case=="bounded_storage":
        before=obs["payload_before"];after=obs["payload_after"];cap=obs["kernel_cap_probe"]
        c.require(obs["rename_source_absent"] is True and
          (before["device"],before["inode"],before["sha256"],before["bytes"])==
          (after["device"],after["inode"],after["sha256"],after["bytes"]) and
          cap["actual_RLIMIT_FSIZE"]==[c.FILE_CAP,c.FILE_CAP] and cap["actual_errno"]==27
          and cap["before_bytes"]==cap["after_bytes"]==cap["actual_cursor"]==c.FILE_CAP,
          "actual sameinode NOREPLACE plus real retained kernel byte cap")

def run(context):
    c=_contract();ctx=c.require_context(context);stage,policy=c.policy(ctx)
    before_usage=_usage();native=c.load_fixed(ctx,"abi/native_abi.py","_r203_native_ABI")
    founder=_founder(c,ctx,native);trace=_tracer(c,ctx)
    full_ceiling=c.integer(ctx.quote["owner_CPU_seconds"],1)
    c.require(_usage()["SELF_CPU_seconds"]+_usage()["all_waited_CHILDREN_CPU_seconds"]<full_ceiling,
      "full stage CPU includes all previous owner/startup history")
    subjects=[];guards=[]
    for case in policy["cases"]:
        c.require_context(ctx)
        desc=c.descriptor(ctx,case);dp=ctx.write_metadata("abi_descriptor_%02d.json"%case["ordinal"],desc)
        stdout_name,stderr_name,guard_name=c.case_slots(case["case_id"])[:3]
        parse_observation={}
        with ctx.open_slot(stdout_name,"r+b") as stdout,ctx.open_slot(stderr_name,"r+b") as stderr:
            initial=_kernel_state(c,ctx)
            def peer(lifetimes):
                c.require_context(ctx)
                return dict(stage=ctx.stage,request=ctx.request_pin,owner=ctx.owner,
                  job_id=ctx.job_id,node=ctx.node,actual_owned_lifetimes=lifetimes,
                  stage_deadline_epoch=ctx.stage_deadline_epoch)
            def capture(lock_fd,phase,state):
                c.require_context(ctx);c.require(lock_fd==ctx.permit_fd,"same actual inherited Root permit")
                if phase=="SCIENTIFIC_FORK_DENIED" and state.get("scientific_filter_accepted") is True:
                    raw=os.pread(stdout.fileno(),stdout.tell(),0)
                    lines=raw.splitlines();c.require(len(lines)==1,"one fixed ready frame before actual ACK")
                    frame=c.closed(c.strict_json(lines[0]),c.FRAME_KEYS,"pre-ACK frame")
                    live=[r for r in state.get("live_lifetimes",[]) if r.get("ppid")==os.getpid()
                          and r.get("TracerPid")==os.getpid()]
                    c.require(len(live)==1 and frame["child"]["pid"]==live[0]["pid"] and
                      frame["child"]["start_ticks"]==live[0]["start_ticks"] and
                      frame["descriptor"]==dp and frame["request"]==ctx.request_pin and
                      frame["authority"]==ctx.authority_pin and frame["case_id"]==case["case_id"] and
                      frame["ordinal"]==case["ordinal"] and frame["owner"]==ctx.owner and
                      frame["native_library"]==stage["native_library"] and
                      frame["runtime_map_sha256"]==ctx.runtime_map_sha256 and
                      frame["control_map_sha256"]==ctx.control_map_sha256,
                      "exact real traced child/source/case before actual original ACK")
                    parse_observation.update(status="CHECKED_BEFORE_ACTUAL_ORIGINAL_ACK",
                      frame_sha256=hashlib.sha256(lines[0]).hexdigest(),owner=ctx.owner,
                      child=dict(pid=live[0]["pid"],start_ticks=live[0]["start_ticks"]),
                      observed_epoch=time.time(),claim_kernel_ACK_earned=False)
            common=ctx.parameters["common"];python=common["startup_python"]["path"]
            subject=ctx.control_sources["abi/subject.py"]
            env=dict(common["environment"],SLURM_JOB_ID=ctx.job_id,SLURMD_NODENAME=ctx.node,
              R154_GLOBAL_PERMIT_LOCK_FD=str(ctx.permit_fd))
            if "SLURM_JOB_NODELIST" in os.environ:env["SLURM_JOB_NODELIST"]=os.environ["SLURM_JOB_NODELIST"]
            wall=min(case["wall_seconds"],ctx.stage_deadline_epoch-time.time())
            c.require(wall>0,"fixed fullstage deadline")
            file_ceiling=min(stdout.maximum_bytes,stderr.maximum_bytes,c.FILE_CAP)
            c.integer(file_ceiling,1,c.FILE_CAP)
            def child_limits():
                for kind,bound in ((resource.RLIMIT_CPU,case["child_CPU_seconds"]),
                                   (resource.RLIMIT_FSIZE,file_ceiling)):
                    soft,hard=resource.getrlimit(kind)
                    nextsoft=bound if soft==resource.RLIM_INFINITY else min(soft,bound)
                    nexthard=bound if hard==resource.RLIM_INFINITY else min(hard,bound)
                    resource.setrlimit(kind,(nextsoft,nexthard))
                resource.setrlimit(resource.RLIMIT_CORE,(0,0))
            import datetime
            guard=trace.run_traced([python,"-I","-B",subject["path"],dp["path"],dp["sha256"]],
              env=env,stdout=stdout,stderr=stderr,lock_fd=ctx.permit_fd,
              affinity=set(os.sched_getaffinity(0)),
              wall_seconds=wall,maximum_combined_CPU_seconds=full_ceiling,
              absolute_deadline_UTC=datetime.datetime.fromtimestamp(ctx.stage_deadline_epoch,
                datetime.timezone.utc).isoformat(),peer_callback=peer,
              bootstrap_exec_allowlist=common["exec_allowlist"],owner_path=None,
              scope=ctx.request_pin,source=dict(control_map_sha256=ctx.control_map_sha256,
                runtime_map_sha256=ctx.runtime_map_sha256,subject=subject),
              authority_pin=ctx.authority_pin,preexec_fn=child_limits,
              require_science_handshake=case["handshake"],owner_capture_callback=capture)
            used_out=stdout.tell();used_err=stderr.tell()
            raw=os.pread(stdout.fileno(),used_out,0)
            final=_kernel_state(c,ctx)
            outpin=ctx.finalize_stream(stdout_name,used_out);errpin=ctx.finalize_stream(stderr_name,used_err)
        gp=ctx.write_metadata(guard_name,guard)
        c.require(initial==final,"actual subreaper/FD/permit restoration before next call")
        _guard(c,guard,case)
        lines=raw.splitlines();c.require(len(lines)==2,"exact frame and raw native result")
        frame=c.closed(c.strict_json(lines[0]),c.FRAME_KEYS,"ready frame")
        result=c.raw_result_shape(c.strict_json(lines[1]))
        root=guard["owned_root"]
        c.require(result["descriptor"]==dp and result["request"]==ctx.request_pin and
          result["authority"]==ctx.authority_pin and result["case_id"]==case["case_id"] and
          result["ordinal"]==case["ordinal"] and result["owner"]==ctx.owner and
          result["child"]["pid"]==root["pid"] and result["child"]["start_ticks"]==root["start_ticks"]
          and result["child"]["ppid"]==result["child"]["tracer_pid"]==ctx.owner["pid"]
          and result["runtime_map_sha256"]==ctx.runtime_map_sha256 and
          result["control_map_sha256"]==ctx.control_map_sha256,"actual guarded raw result identity/source")
        if case["handshake"]:c.require(parse_observation,"real parent parse observation")
        else:c.require(not parse_observation,"negative never claims ACK")
        _expected(c,result)
        subjects.append(dict(case_id=case["case_id"],ordinal=case["ordinal"],descriptor=dp,stdout=outpin,
          stderr=errpin,owned_guard=gp,ready_frame=frame,raw_result=result,
          parent_parse_observation=parse_observation,post_cleanup=dict(before=initial,after=final)))
        guards.append(gp)
    after_usage=_usage();c.require(after_usage["SELF_CPU_seconds"]+
      after_usage["all_waited_CHILDREN_CPU_seconds"]<full_ceiling,"same full stage absolute CPU ceiling")
    raw=dict(schema="r203_ABI_engine_raw_result_v1",status="RAW_ABI_STAGE_FACTS_NOT_ACCEPTED",
      request=ctx.request_pin,authority=ctx.authority_pin,job_id=ctx.job_id,node=ctx.node,owner=ctx.owner,
      runtime_map_sha256=ctx.runtime_map_sha256,control_map_sha256=ctx.control_map_sha256,
      runtime_publication=ctx.template["runtime_publication"],control_publication=ctx.template["control_publication"],
      native_library=stage["native_library"],native_abi=stage["native_abi"],founder_observation=founder,
      subjects=subjects,owned_guards=guards,owner_usage_before=before_usage,owner_usage_after=after_usage,
      storage_inventory=dict(policy=ctx.parameters["common"]["storage_policy"],
        no_hidden_duplicate_final=True,all_actual_inventory_owned_by_common_finalizer=True),
      coverage_limits=dict(founder_isolated_trace_predicate_proved=False,private_failure_state_observed=False,
        production_writer_or_analytic9_27_qualified=False,terminal_accounting_claimed=False,
        original_held_lock_global_kernel_table_read_disclosed=True))
    ctx.write_metadata("abi_case_catalog.json",raw)
    return raw
