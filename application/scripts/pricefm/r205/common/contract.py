"""Fixed r203 control admission. No source descriptor earns actual execution."""
from __future__ import annotations
import copy,datetime,fcntl,hashlib,importlib.util,json,math,os,re,resource,stat,sys,time
from pathlib import Path
ROOT=Path(__file__).absolute().parent.parent
def _captured(path,sha,maximum=4*1024**2):
    if any(p.is_symlink() for p in (path,*path.parents)):raise ValueError("physical fixed source")
    fd=os.open(path,os.O_RDONLY|os.O_NONBLOCK|os.O_NOFOLLOW)
    try:
        before=os.fstat(fd)
        if not(stat.S_ISREG(before.st_mode) and before.st_nlink==1 and before.st_uid==os.getuid()
               and 0<before.st_size<=maximum):raise ValueError("bounded owned fixed source")
        chunks=[];size=0
        while size<=maximum:
            block=os.read(fd,min(65536,maximum+1-size))
            if not block:break
            chunks.append(block);size+=len(block)
        raw=b"".join(chunks);after=os.fstat(fd)
    finally:os.close(fd)
    key=lambda s:(s.st_dev,s.st_ino,s.st_size,s.st_mode,s.st_uid,s.st_nlink,s.st_mtime_ns,s.st_ctime_ns)
    if key(before)!=key(after) or key(after)!=key(path.lstat()) or len(raw)!=before.st_size or hashlib.sha256(raw).hexdigest()!=sha:
        raise ValueError("authenticated captured source changed")
    return raw
_mp=ROOT/"common/metadata.py"
_mraw=_captured(_mp,"6593a6bbb617375029bee0c692e510cd5621662eaf9fab46445eab433ff0762b")
_ms=importlib.util.spec_from_file_location("_r203_control_metadata",_mp)
m=importlib.util.module_from_spec(_ms);exec(compile(_mraw,str(_mp),"exec"),m.__dict__)
BASE=m.strict_json(_captured(ROOT/"RUNTIME_BASE.json","85bce27c0cc4aaf16e744c1abb0988abdea64ef582c578fb8871997db6a8e543"))
POLICY=m.strict_json(_captured(ROOT/"PEER_POLICY.json","65094e86aca9121f776bffff260ddb6a84890a8f39344291ab9a6456d7cbf234"))
CAT=m.strict_json(_captured(ROOT/"SCHEMAS.json","33195e8a0a67663fc8286a682f8885c0e6b6995798d50faca592a82e4618a305"))
STAGES={"FACILITY_PRECHECK","OWNED_NATIVE_BUILD","READONLY_DEPLOYMENT","NATIVE_ABI_SUITE"}
MAX_FILE=16*1024**2
MAX_USEFUL=64*1024**2
THREADS=("OPENBLAS_NUM_THREADS","OMP_NUM_THREADS","MKL_NUM_THREADS","VECLIB_MAXIMUM_THREADS","NUMEXPR_NUM_THREADS","BLIS_NUM_THREADS")
_SEAL=object()
_LIVE={}
_UNSAFE_FDS=[]
def _shape(record,kind):
    spec=CAT[kind];m.closed(record,set(spec["keys"]),kind)
    m.require(record["schema"]==spec["schema"],"exact "+kind+" schema")
    if spec.get("status") is not None:m.require(record["status"]==spec["status"],"exact "+kind+" status")
    return record
def _same(record,template,keys=("purpose","nonce","stage")):
    for key in keys:m.require(record.get(key)==template[key],"same exact "+key)
def _proc(pid):
    folder=Path("/proc")/str(pid);raw=(folder/"stat").read_text();end=raw.rfind(")")
    fields=raw[end+2:].split();status={}
    for line in (folder/"status").read_text().splitlines():
        if ":" in line:
            k,v=line.split(":",1);status[k]=v.strip()
    return {"pid":pid,"ppid":int(fields[1]),"start_ticks":int(fields[19]),
      "TracerPid":int(status["TracerPid"]),"uid":int(status["Uid"].split()[0]),
      "NoNewPrivs":int(status.get("NoNewPrivs","0")),"Seccomp":int(status.get("Seccomp","0"))}
def _job(subject=False):
    job=os.environ.get("SLURM_JOB_ID","");node=os.uname().nodename.split(".")[0]
    m.require(job.isdigit() and job!="0" and node.startswith("node-")
      and os.environ.get("SLURMD_NODENAME")==node and os.environ.get("TZ")=="UTC",
      "actual direct Slurm job before supplied records; never admin/login execution")
    group=Path("/proc/self/cgroup").read_text()
    m.require(re.search(r"(?:^|/)job_"+re.escape(job)+r"(?:/|$)",group,re.M),"actual current job cgroup")
    proc=_proc(os.getpid())
    if subject:m.require(proc["TracerPid"]==proc["ppid"] and proc["TracerPid"]>1,"actual traced child before supplied records")
    else:m.require(proc["TracerPid"]==0,"direct Slurm control owner outside administrative H")
    return job,node,proc
def _identity(proc=None):
    p=_proc(os.getpid()) if proc is None else proc
    return {"pid":p["pid"],"start_ticks":p["start_ticks"],"boot_id":Path("/proc/sys/kernel/random/boot_id").read_text().strip()}
def _pin(path):
    # Actual owned proof files include stdout/stderr and native alias names;
    # basic metadata6593 intentionally only pins source/JSON suffixes.
    path=m.physical(str(path));raw=m.read_regular(path,limit=MAX_FILE,expected_uid=os.getuid())
    return {"path":str(path),"sha256":hashlib.sha256(raw).hexdigest()}
class _Proofs:
    def __init__(self,rows):
        m.require(type(rows) is list and len(rows)<=512,"explicit bounded canonical proof closure")
        self.allowed={}
        for row in rows:
            m.descriptor(row);m.require(row["path"] not in self.allowed,"unique canonical proof path")
            self.allowed[row["path"]]=row["sha256"]
        self.readset={}
    def linked(self,pin):
        m.descriptor(pin);m.require(Path(pin["path"]).suffix==".json","schema-required JSON metadata only, no scientific binary")
        m.require(self.allowed.get(pin["path"])==pin["sha256"],"required canonical proof missing from explicit closure")
        result=m.linked(pin);self.readset[pin["path"]]=dict(pin);return result
    def extend(self,rows):
        extra=_Proofs(rows)
        for path,sha in extra.allowed.items():
            m.require(path not in self.allowed or self.allowed[path]==sha,"same canonical proof byte identity")
            self.allowed[path]=sha
def _guard(g,cpu):
    m.require(type(g) is dict and type(g.get("returncode")) is int and type(g.get("command_returncode")) is int
      and g["returncode"]==g["command_returncode"]==0 and type(g.get("CPU_limit")) is int
      and g["CPU_limit"]==cpu and g.get("cap_reason") is None and g.get("guardian_forced_monitor_stop") is False,
      "actual original H guard cap/exit")
    for k in ("aggregate_CPU_seconds","complete_lifecycle_wall_seconds"):m.finite(g.get(k),k)
    m.require(0<=g["aggregate_CPU_seconds"]<cpu and 0<=g["complete_lifecycle_wall_seconds"]<=180
      and all(g.get(k) is True for k in POLICY["guard"]["required_true"]),"complete actual H lifecycle")
def _promoted(record,candidate_status,status,proofs):
    g=proofs.linked(record["actual_accept_guard"]);_guard(g,5)
    candidate=m.strict_json(g["stdout"])
    m.require(candidate.get("status")==candidate_status and record["status"]==status
      and dict(candidate,status=status,actual_accept_guard=record["actual_accept_guard"])==record
      and type(record["command_pid"]) is int and type(record["command_birth_ticks"]) is int
      and g["session_id"]==record["command_pid"] and g["leader_start_ticks"]==record["command_birth_ticks"],
      "real H5 candidate/stdout/PID/birth promotion")
def _capture(pair,proofs,t,mode):
    m.closed(pair,{"result","guard"},"actual native capture pair")
    r=proofs.linked(pair["result"]);g=proofs.linked(pair["guard"]);_guard(g,8)
    m.closed(r,set(POLICY["native_capture"]["keys"]),"native metadata capture")
    m.require(r["schema"]==POLICY["native_capture"]["schema"] and r["status"]==POLICY["native_capture"]["status"]
      and r["mode"]==mode and m.strict_json(g["stdout"])==r
      and g["session_id"]==r["command_pid"] and g["leader_start_ticks"]==r["command_birth_ticks"],
      "actual native H8 capture stdout/PID/birth")
    _same(r,t)
    for k in ("node","scope","ledger","quote","control_publication","control_map_sha256",
              "runtime_publication","runtime_map_sha256"):
        m.require(r[k]==t[k],"capture binding "+k)
    m.require(r["parameters_sha256"]==m.digest(t["parameters"])
      and r["controller_source"]["sha256"]==t["control_sources"]["peer/observation_capture.py"]["sha256"],
      "reviewed exact native capture controller and parameter identity")
    for k in ("observed_epoch","completed_epoch"):m.finite(r[k],k)
    m.require(r["observed_epoch"]<=r["completed_epoch"] and type(r["raw"]) is list,"bounded capture clock/raw")
    for row in r["raw"]:
        m.closed(row,{"argv","returncode","stdout","stderr"},"native raw command")
        m.require(type(row["argv"]) is list and type(row["returncode"]) is int and row["returncode"]==0
          and all(type(x) is str for x in row["argv"])
          and type(row["stdout"]) is str and type(row["stderr"]) is str,"complete native command bytes")
    seen=set()
    for row in r["records"]:
        m.closed(row,{"remote_path","sha256","local_copy"},"actual byte-copy mapping")
        m.absolute(row["remote_path"]);m.descriptor(row["local_copy"])
        m.require(row["remote_path"] not in seen and row["sha256"]==row["local_copy"]["sha256"],"unique exact metadata-copy bytes")
        seen.add(row["remote_path"])
    return r
def _maps(t,proofs):
    m.require(type(t["control_sources"]) is dict and 5<=len(t["control_sources"])<=128,"closed control source map")
    for table in (t["control_sources"],t["runtime_sources"]):
        for relative,pin in table.items():
            m.require(type(relative) is str and not Path(relative).is_absolute() and ".." not in Path(relative).parts,
              "relative source member")
            m.descriptor(pin)
    control={k:v["sha256"] for k,v in t["control_sources"].items()}
    runtime={k:v["sha256"] for k,v in t["runtime_sources"].items()}
    m.require(runtime==BASE["runtime_source_hashes"] and m.digest(runtime)==BASE["runtime_map_sha256"]==t["runtime_map_sha256"],
      "exact immutable runtime39 map; reviewed installed paths may differ")
    m.require(m.digest(control)==t["control_map_sha256"],"exact distinct control map")
    for kind,schema,status,files in (("control","r203_control_source_publication_v1",
      "PASS_PUBLISHED_R203_CONTROL_SOURCE_PREPARATION",control),("runtime","r200_source_publication_v1",
      "PASS_PUBLISHED_R200_SOURCE_PREPARATION",runtime)):
        pub=proofs.linked(t[kind+"_publication"])
        m.require(pub.get("schema")==schema and pub.get("status")==status and pub.get("files")==files
          and pub.get("commit")==pub.get("remote_readback")
          and re.fullmatch("[0-9a-f]{40}",pub.get("commit","")),"actual exact "+kind+" source publication")
    m.require(t["runtime_publication"]["sha256"]==BASE["runtime_publication"]["sha256"],"original runtime publication identity")
def _validate_ledger_append(t,scope,q,ledger,previous):
    """Pure ledger shape/lineage checks; this does not issue an authority."""
    m.require(type(previous) is dict and type(ledger) is dict,"ledger objects")
    m.closed(ledger,set(previous),"identical inherited ledger keyset")
    counters={"total_administrative_reservation","total_new_administrative_reservation",
              "total_qualification_compute_reservation","total_new_qualification_compute_reservation"}
    m.require({"scopes","compute_roles","previous","created_epoch",*counters}<=set(previous),
      "complete inherited ledger fields")
    m.require(ledger["previous"]==scope["previous_ledger"],"exact immediate previous ledger pin")
    m.finite(previous["created_epoch"],"previous ledger creation")
    m.finite(ledger["created_epoch"],"new ledger creation")
    m.require(previous["created_epoch"]<=ledger["created_epoch"]
      and scope["issued_epoch"]<=ledger["created_epoch"]<=t["issued_epoch"],
      "new ledger creation fits already issued scope/template without renewal")
    m.integer(scope["new_administrative_CPU_reservation"],"new administrative fee",0)
    m.integer(q["compute_CPU_reservation"],"new positive primary compute fee",1)
    expected_row=dict(purpose=t["purpose"],scope=t["scope"],
      administrative_CPU_reservation=scope["new_administrative_CPU_reservation"],
      compute_CPU_reservation=q["compute_CPU_reservation"])
    expected_role=dict(purpose=t["purpose"],stage=t["stage"],scope=t["scope"],
      compute_CPU_reservation=q["compute_CPU_reservation"],primary_actual_CPU=None)
    for key,expected in (("scopes",expected_row),("compute_roles",expected_role)):
        prior=previous[key];current=ledger[key]
        m.require(type(prior) is list and type(current) is list
          and len(current)==len(prior)+1 and current[:-1]==prior,
          "exactly one appended row and every historical row unchanged")
        row=current[-1];m.closed(row,set(expected),"closed new "+key+" row")
        m.require(type(row["purpose"]) is str and row["purpose"]==t["purpose"]
          and row["scope"]==t["scope"],"exact new purpose/scope")
        m.integer(row["compute_CPU_reservation"],"typed appended compute reservation",1)
        if key=="scopes":m.integer(row["administrative_CPU_reservation"],"typed appended admin reservation",0)
        else:m.require(type(row["stage"]) is str and row["stage"]==t["stage"]
          and row["primary_actual_CPU"] is None,"one stage-bound prospective primary role")
        m.require(row==expected,"exact appended scope/primary role funding")
    for key,value in previous.items():
        if key in counters:
            delta=(scope["new_administrative_CPU_reservation"] if "administrative" in key
                   else q["compute_CPU_reservation"])
            m.integer(value,"previous retained counter",0)
            m.integer(ledger[key],"new retained counter",0)
            m.require(ledger[key]==value+delta,"exact full reserved fee counter")
        elif key not in {"scopes","compute_roles","previous","created_epoch"}:
            m.require(ledger[key]==value,"every other historical field/null/clock unchanged")
    return None

def _quote_and_scope(t,proofs):
    scope=proofs.linked(t["scope"]);_shape(scope,"runtime_scope")
    m.require(scope["compute_CPU_reservation"]>0 and type(scope["compute_CPU_reservation"]) is int,
      "actual separately funded compute stage, never source448 or old fee reuse")
    q=proofs.linked(t["quote"]);_shape(q,"quote");_same(q,t);_same(scope,t)
    params=m.digest(t["parameters"])
    for key in ("control_publication","control_map_sha256","runtime_publication","runtime_map_sha256"):
        m.require(q[key]==scope[key]==t[key],"quote/scope maps/publications "+key)
    m.require(q["parameters_sha256"]==scope["parameters_sha256"]==params and q["output_root"]==scope["remote_namespace"]==t["output_root"]
      and scope["quote"]==t["quote"],"same full stage parameters/namespace/quote")
    names={"startup","namespace","import","optimizer","certification","checkpoint","return","independent_peer","closure"}
    m.require(type(q["components"]) is dict and set(q["components"])==names,"complete nine-component quote")
    channels=("compute_CPU_upper_seconds","administrative_CPU_upper_seconds","remote_unknown_CPU_reservation")
    for row in q["components"].values():
        m.closed(row,{"covered","CPU_upper_seconds","wall_upper_seconds",*channels},"disjoint quote component")
        m.require(row["covered"] is True,"every lifecycle component covered")
        for key in ("CPU_upper_seconds","wall_upper_seconds",*channels):m.integer(row[key],key,0)
        m.require(row["CPU_upper_seconds"]==sum(row[k] for k in channels),"exact disjoint component channels")
    total_names=("compute_CPU_reservation","administrative_CPU_reservation","remote_unknown_CPU_reservation")
    for channel,total in zip(channels,total_names):
        m.integer(q[total],total,0);m.require(q[total]==sum(v[channel] for v in q["components"].values()),"exact whole channel sum")
    for key in ("whole_CPU_seconds","whole_wall_seconds","owner_CPU_seconds","child_CPU_seconds","owner_wall_seconds",
                "memory_MiB","reserved_filesystem_bytes","mandatory_headroom_bytes","return_proof_reservation_bytes",
                "proof_storage_reservation_bytes","transient_tree_reservation_bytes"):m.integer(q[key],key,1)
    m.require(q["whole_CPU_seconds"]==sum(q[k] for k in total_names)
      and q["whole_wall_seconds"]==sum(v["wall_upper_seconds"] for v in q["components"].values())
      and q["components"]["startup"]["wall_upper_seconds"]>=120
      and q["components"]["optimizer"]["compute_CPU_upper_seconds"]==0
      and q["child_CPU_seconds"]<=q["owner_CPU_seconds"]<=q["compute_CPU_reservation"]
      and q["owner_wall_seconds"]<=q["whole_wall_seconds"]
      and q["return_proof_reservation_bytes"]>=16*1024**2 and q["transient_tree_reservation_bytes"]>=32*1024**2,
      "complete inclusive stage/startup/proof/transient quote")
    review=proofs.linked(q["independent_review"]);core=dict(q);core.pop("independent_review")
    m.require(review.get("status")=="PASS_REVIEWED_R203_CONTROL_STAGE_QUOTE"
      and review.get("quote_core_sha256")==m.digest(core),"acyclic independent quote review")
    for key in ("issued_epoch","expires_epoch"):
        m.finite(scope[key],key);m.finite(t[key],key)
    m.require(scope["issued_epoch"]<=t["issued_epoch"]<t["expires_epoch"]==scope["expires_epoch"]
      and 0<t["expires_epoch"]-scope["issued_epoch"]<=28800,"funded fixed scope/template interval, no quote clock or renewal")
    maximum=9 if t["stage"]=="NATIVE_ABI_SUITE" else 1
    m.require(type(scope["maximum_jobs"]) is int and scope["maximum_jobs"]==1
      and type(scope["maximum_owner_calls"]) is int and scope["maximum_owner_calls"]==1
      and type(scope["maximum_traced_subjects"]) is int and scope["maximum_traced_subjects"]==maximum
      and scope["automatic_retry"] is False and scope["requeue"] is False
      and type(scope["optimizer_invocations"]) is int and scope["optimizer_invocations"]==0
      and type(scope["new_posterior_fits"]) is int and scope["new_posterior_fits"]==0
      and scope["target_input_manifest"] is None,"one closed no-target stage purpose")
    m.require(scope["compute_CPU_reservation"]==q["compute_CPU_reservation"]
      and type(scope["new_administrative_CPU_reservation"]) is int
      and scope["new_administrative_CPU_reservation"]>=q["administrative_CPU_reservation"]+q["remote_unknown_CPU_reservation"],
      "complete compute/admin/remote funding")
    ledger=proofs.linked(t["ledger"]);previous=proofs.linked(scope["previous_ledger"])
    _validate_ledger_append(t,scope,q,ledger,previous)
    source_pub=proofs.linked(t["control_publication"])
    source_base=proofs.linked(source_pub["source_ledger"])
    for key in ("scopes","compute_roles"):
        m.require(previous.get(key,[])[:len(source_base.get(key,[]))]==source_base.get(key,[]),"ledger descends published source base")
    return q
def _storage(t,q):
    block=t["parameters"]["common"]["storage_policy"]
    m.closed(block,{"slots","payload_useful_limit_bytes","return_proof_reservation_bytes","physical_proof_reservation_bytes",
      "transient_tree_reservation_bytes","dynamic_artifact_reservation_bytes"},"closed physical storage plan")
    m.require(type(block["slots"]) is list and 1<=len(block["slots"])<=256,"bounded exact slot inventory")
    names=set();aliases=set();total=0
    for row in block["slots"]:
        m.closed(row,{"name","kind","maximum_bytes","final_alias"},"fixed slot")
        m.require(type(row["name"]) is str and re.fullmatch("[A-Za-z0-9_.-]{1,128}",row["name"]) and row["name"] not in names,
          "unique fixed basename")
        names.add(row["name"]);m.integer(row["maximum_bytes"],"slot bytes",1,MAX_FILE);total+=row["maximum_bytes"]
        m.require(row["kind"] in {"proof","payload","stream","native_probe"},"closed slot kind")
        if row["final_alias"] is not None:
            m.require(type(row["final_alias"]) is str and re.fullmatch("[A-Za-z0-9_.-]{1,128}",row["final_alias"])
              and row["final_alias"] not in aliases,"unique sameinode terminal alias")
            aliases.add(row["final_alias"])
    m.require(not(names&aliases),"final aliases initially absent and not separately reserved")
    required={"reservation.json","startup_claim.json","source_capture.json","physical_witness.json","ready.json","stage_claim.json",
      "stage_failed.json","raw_stage_result.json","proof_inventory.json","owner_usage.json"}
    if t["stage"]=="NATIVE_ABI_SUITE":
        required|={"abi_case_catalog.json"}|{"abi_descriptor_%02d.json"%i for i in range(1,10)}
    elif t["stage"] in {"FACILITY_PRECHECK","READONLY_DEPLOYMENT"}:required|={"observer_descriptor.json","observer.stdout","observer.stderr","observer.guard.json"}
    elif t["stage"]=="OWNED_NATIVE_BUILD":required|={"build.stdout","build.stderr","build.guard.json"}
    m.require(required<=names,"all mandatory common/descriptor proofs prepaid")
    for key in ("payload_useful_limit_bytes","return_proof_reservation_bytes","physical_proof_reservation_bytes",
                "transient_tree_reservation_bytes","dynamic_artifact_reservation_bytes"):m.integer(block[key],key,0)
    m.require(block["payload_useful_limit_bytes"]+block["return_proof_reservation_bytes"]<=MAX_USEFUL
      and block["return_proof_reservation_bytes"]==q["return_proof_reservation_bytes"]>=16*1024**2
      and block["physical_proof_reservation_bytes"]==q["proof_storage_reservation_bytes"]
      and block["transient_tree_reservation_bytes"]==q["transient_tree_reservation_bytes"]>=32*1024**2
      and total==block["physical_proof_reservation_bytes"]==q["proof_storage_reservation_bytes"]
      and total+block["transient_tree_reservation_bytes"]+block["dynamic_artifact_reservation_bytes"]<=q["reserved_filesystem_bytes"],
      "prewrite full physical and useful payload/proof/storage envelope")
    return block
def validate_environment(environment):
    allowed=set(THREADS)|{"TZ","PATH","LANG","LC_ALL"}
    required=set(THREADS)|{"TZ"}
    m.require(type(environment) is dict and required<=set(environment)<=allowed,
      "closed one-thread native bootstrap environment")
    m.require(environment["TZ"]=="UTC" and all(environment[k]=="1" for k in THREADS),
      "fixed one-thread UTC environment")
    for key,value in environment.items():
        m.require(type(key) is str and type(value) is str,"typed fixed environment")
        if key=="PATH":m.require(value=="/usr/bin:/bin","fixed reviewed native PATH")
        elif key in {"LANG","LC_ALL"}:m.require(value=="C","fixed C locale")
    return environment

def validate_runtime_environment(actual,expected):
    """Full fixed environment is required after the reviewed script exports it."""
    validate_environment(expected)
    m.require(type(actual) is dict and all(actual.get(k)==v for k,v in expected.items()),
      "actual Python owner has every fixed environment key/value")
    m.require(not any(k.startswith(("LD_","PYTHON","BASH_FUNC_")) or
      k in {"BASH_ENV","ENV","SHELLOPTS","BASHOPTS","CDPATH","GLOBIGNORE"} for k in actual),
      "actual Python owner has no inherited loader/Python/shell injection")
    return None

def validate_native_sbatch_argv(argv):
    m.require(type(argv) is list and len(argv)>=4 and all(type(x) is str for x in argv),
      "typed native sbatch argv")
    m.absolute(argv[0]);m.require(Path(argv[0]).name=="sbatch","literal absolute native sbatch")
    valued={"--partition","--qos","--nodes","--ntasks","--cpus-per-task","--mem","--time","--nodelist",
      "--job-name","--output","--error","--chdir","--account","--reservation","--hint",
      "--threads-per-core","--ntasks-per-node","--distribution","--export"}
    flags={"--parsable","--no-requeue"};seen=set()
    for token in argv[1:-1]:
        key,separator,value=token.partition("=")
        m.require(key not in seen,"no duplicate native sbatch option");seen.add(key)
        if key in flags:m.require(not separator,"canonical boolean native option")
        else:
            m.require(key in valued and separator=="=" and value and "\x00" not in value
              and "\n" not in value,"canonical valued native option; no abbreviation/short/wrap/heterogeneous/positionals")
        if key=="--export":m.require(token=="--export=NIL","one exact NIL export only")
    m.require({"--export","--no-requeue"}<=seen,"one NIL export and explicit no-requeue")
    m.absolute(argv[-1])
    return argv

def _check_first_exec_environment(actual,expected,node,spank_names):
    validate_environment(expected)
    m.require(type(actual) is dict and all(type(k) is str and type(v) is str for k,v in actual.items()),
      "actual typed first-exec environment")
    forbidden={"BASH_ENV","ENV","SHELLOPTS","BASHOPTS","CDPATH","GLOBIGNORE",
               "GCONV_PATH","LOCPATH","NLSPATH"}
    m.require(not any(k in forbidden or k.startswith(("LD_","PYTHON","BASH_FUNC_")) for k in actual),
      "first exec has no loader/Python/shell/function injection")
    m.require(all(k not in actual or actual[k]==v for k,v in expected.items()),
      "PRE_BASH expected values if present; reviewed script exports full environment later")
    for key in actual:
        m.require(key in expected or key.startswith("SLURM_") or key=="SLURMD_NODENAME"
          or key in spank_names,"only closed base/actual Slurm/enumerated site SPANK")
    m.require(actual.get("SLURM_JOB_ID","").isdigit() and actual["SLURM_JOB_ID"]!="0"
      and actual.get("SLURMD_NODENAME")==node,"actual first-exec Slurm identity")

def _validate_native_clean_launch(t,facility,proofs):
    """Consume actual externally reviewed prerequisite; never mint one here."""
    prerequisite=facility.get("native_clean_launch_contract")
    m.descriptor(prerequisite)
    record=proofs.linked(prerequisite)
    keys={"schema","status","node","site","sbatch","bash","launcher","environment",
          "submission_policy","site_SPANK_policy","actual_evidence","independent_review"}
    m.closed(record,keys,"actual clean-launch prerequisite")
    m.require(record["schema"]=="r203_native_clean_launch_contract_v1" and
      record["status"]=="PASS_REVIEWED_R203_NATIVE_CLEAN_LAUNCH_BEFORE_INTERPRETER"
      and record["node"]==t["node"] and record["site"]=="hb.ucsc.edu",
      "actual site clean launch prerequisite; expected source plan is insufficient")
    validate_environment(record["environment"])
    m.require(record["environment"]==t["parameters"]["common"]["environment"]
      and record["submission_policy"]=="EXACT_REVIEWED_SBATCH_ARGV_ONE_EXPORT_NIL_NO_USER_ENV_NO_WRAP",
      "exact native clean environment/submission policy")
    for key in ("sbatch","bash","launcher"):m.descriptor(record[key])
    m.require(Path(record["sbatch"]["path"]).name=="sbatch" and
      Path(record["bash"]["path"]).name=="bash","fixed native tool identities")
    profile=proofs.linked(t["parameters"]["common"]["physical_profile"])
    validate_native_sbatch_argv(profile["rendered_sbatch_argv"])
    m.require(profile["rendered_sbatch_argv"][0]==record["sbatch"]["path"],"same approved native submit tool")
    policy=record["site_SPANK_policy"]
    m.closed(policy,{"allowed_environment_names"},"explicit reviewed site SPANK policy")
    names=policy["allowed_environment_names"]
    m.require(type(names) is list and len(names)==len(set(names))
      and all(type(k) is str and re.fullmatch("SPANK_[A-Z0-9_]+",k) for k in names),
      "enumerated site SPANK names, no wildcard")
    pair=record["actual_evidence"];m.closed(pair,{"result","guard"},"actual clean evidence pair")
    result=proofs.linked(pair["result"]);guard=proofs.linked(pair["guard"]);_guard(guard,8)
    result_keys={"schema","status","node","site","sbatch","bash","launcher","environment",
      "submission_policy","site_SPANK_policy","actual_probe_argv","first_exec_environment","first_exec_events",
      "raw_native_observations","command_source","source_review","command_pid","command_birth_ticks","observed_epoch"}
    m.closed(result,result_keys,"actual native clean-launch observation")
    m.require(result["schema"]=="r203_actual_native_clean_launch_evidence_v1" and
      result["status"]=="CAPTURED_ACTUAL_SITE_FIRST_EXEC_ENVIRONMENT_NOT_RUNTIME_QUALIFICATION",
      "actual clean first-exec evidence, not source plan/runtime qualification")
    for key in ("node","site","sbatch","bash","launcher","environment","submission_policy","site_SPANK_policy"):
        m.require(result[key]==record[key],"actual clean evidence binding "+key)
    m.integer(result["command_pid"],"actual clean collector PID",1)
    m.integer(result["command_birth_ticks"],"actual clean collector birth",1)
    m.finite(result["observed_epoch"],"actual clean observation epoch")
    m.require(result["observed_epoch"]<=time.time() and
      guard["session_id"]==result["command_pid"] and guard["leader_start_ticks"]==result["command_birth_ticks"]
      and m.strict_json(guard["stdout"])==result,"actual H8 stdout and command lifetime")
    m.descriptor(result["command_source"])
    review=proofs.linked(result["source_review"])
    m.require(review.get("status")=="PASS_REVIEWED_R203_NATIVE_CLEAN_START_COLLECTOR_SOURCE"
      and review.get("source")==result["command_source"],"independently pinned actual clean collector source")
    validate_native_sbatch_argv(result["actual_probe_argv"])
    m.require(result["actual_probe_argv"][0]==record["sbatch"]["path"],"actual pinned native sbatch")
    _check_first_exec_environment(result["first_exec_environment"],record["environment"],t["node"],set(names))
    events=result["first_exec_events"];raw=result["raw_native_observations"]
    m.require(type(events) is list and 0<len(events)<=256 and all(type(e) is dict and e for e in events),
      "nonempty actual first-exec event rows")
    m.require(type(raw) is list and 0<len(raw)<=64,"nonempty actual site/NIL/first-exec native observations")
    for row in raw:
        m.closed(row,{"argv","returncode","stdout","stderr"},"actual native clean observation row")
        m.require(type(row["argv"]) is list and row["argv"] and all(type(x) is str for x in row["argv"])
          and type(row["returncode"]) is int and row["returncode"]==0
          and type(row["stdout"]) is str and type(row["stderr"]) is str,
          "actual successful native observation bytes")
    independent=proofs.linked(record["independent_review"]);core=dict(record);core.pop("independent_review")
    m.finite(independent.get("issued_epoch"),"clean prerequisite independent review issue")
    m.finite(independent.get("expires_epoch"),"clean prerequisite independent review expiry")
    m.require(result["observed_epoch"]<=independent["issued_epoch"]<=t["issued_epoch"]
      and t["expires_epoch"]<=independent["expires_epoch"]<=independent["issued_epoch"]+86400,
      "finite actual clean review interval covers original template, no lease renewal")
    m.require(independent.get("status")=="PASS_REVIEWED_R203_NATIVE_CLEAN_LAUNCH_BEFORE_INTERPRETER"
      and independent.get("clean_launch_core_sha256")==m.digest(core)
      and independent.get("actual_evidence")==pair,"independent actual clean prerequisite core/evidence")
    return None

def _parameters(t):
    p=t["parameters"];m.closed(p,{"schema","common","stage"},"closed stage parameters")
    m.require(p["schema"]=="r203_stage_parameters_v1","exact parameter schema")
    c=p["common"];m.closed(c,set(CAT["parameters"]["common"]["keys"]),"common parameters")
    m.require(c["schema"]=="r203_common_stage_parameters_v1","exact common parameter schema")
    stage=CAT["parameters"]["per_stage"][t["stage"]]
    m.closed(p["stage"],set(stage["keys"]),"fixed stage parameters")
    m.require(p["stage"]["schema"]==stage["schema"],"exact stage parameter schema")
    for key in ("startup_python","traced_guard","physical_profile"):m.descriptor(c[key])
    m.require(c["traced_guard"]["sha256"]==BASE["original_tracer"]["sha256"],"unchanged original tracer")
    m.absolute(c["permit_path"]);m.absolute(c["canonical_metadata_root"])
    m.closed(c["source_and_baseline"],{"baseline_files","dependency_inventory"},"baseline closure")
    m.require(type(c["source_and_baseline"]["baseline_files"]) is list,"exact baseline list")
    for row in c["source_and_baseline"]["baseline_files"]:m.descriptor(row)
    m.descriptor(c["source_and_baseline"]["dependency_inventory"])
    m.require(type(c["exec_allowlist"]) is dict and c["startup_python"]["path"] in c["exec_allowlist"],"fixed startup exec closure")
    for path,sha in c["exec_allowlist"].items():m.descriptor({"path":path,"sha256":sha})
    validate_environment(c["environment"])

def _baseline(t,a,proofs):
    baseline=proofs.linked(a["qualified_startup_baseline"])
    m.closed(baseline,{"schema","status","node","control_publication","control_map_sha256","runtime_publication",
      "runtime_map_sha256","startup_python","traced_guard","source_and_baseline","physical_profile",
      "facility_policy","parameters_sha256","independent_review"},"expected immutable startup plan")
    m.require(baseline["schema"]=="r203_expected_startup_baseline_plan_v1"
      and baseline["status"]=="PASS_REVIEWED_R203_EXPECTED_STARTUP_BASELINE_PLAN","expected plan, not prior native qualification")
    c=t["parameters"]["common"]
    for key in ("node","control_publication","control_map_sha256","runtime_publication","runtime_map_sha256"):
        m.require(baseline[key]==t[key],"startup plan binding "+key)
    for key in ("startup_python","traced_guard","source_and_baseline","physical_profile"):
        m.require(baseline[key]==c[key],"expected startup baseline "+key)
    m.require(baseline["parameters_sha256"]==m.digest(t["parameters"]),"baseline exact stage parameters")
    review=proofs.linked(baseline["independent_review"]);core=dict(baseline);core.pop("independent_review")
    m.require(review.get("status")=="PASS_REVIEWED_R203_EXPECTED_STARTUP_BASELINE_PLAN"
      and review.get("baseline_core_sha256")==m.digest(core),"independent expected baseline source plan")
    facility=proofs.linked(baseline["facility_policy"])
    m.require(facility.get("schema")=="r203_same_path_facility_plan_v1"
      and facility.get("status")=="APPROVED_FACILITY_PLAN_REQUIRES_ACTUAL_OBSERVATION"
      and facility.get("node")==t["node"] and facility.get("controller_mounts_or_privilege_operations") is False
      and facility.get("canonical_output_path_preserved") is True,"approved explicit facility route, no assumed privileges")
    _validate_native_clean_launch(t,facility,proofs)
    return baseline
def _profile(t,proofs):
    p=proofs.linked(t["parameters"]["common"]["physical_profile"])
    m.closed(p,set(POLICY["physical_profile"]["keys"]),"exact physical/calendar profile")
    m.require(p["schema"]==POLICY["physical_profile"]["schema"]
      and p["status"]==POLICY["physical_profile"]["status"] and p["node"]==t["node"],"independently reviewed fixed physical profile")
    for k in ("not_before_epoch","latest_first_submit_epoch","window_end_epoch"):m.finite(p[k],k)
    for k in ("requested_CPUs","memory_MiB","mandatory_headroom_bytes"):m.integer(p[k],k,1)
    m.integer(p["reserve_seconds"],"fixed window reserve",0)
    m.require(type(p["affinity"]) is list and len(p["affinity"])==1
      and all(type(n) is int and n>=0 for n in p["affinity"])
      and type(p["online_thread_siblings"]) is list and p["affinity"][0] in p["online_thread_siblings"],
      "one selected actual logical CPU and explicit physical siblings")
    m.require(type(p["rendered_sbatch_argv"]) is list and all(type(v) is str for v in p["rendered_sbatch_argv"])
      and p["rendered_sbatch_argv"] and Path(p["rendered_sbatch_argv"][0]).name=="sbatch"
      and p["rendered_sbatch_argv"][-1]==p["job_script"]["path"] and p["job_name"]==t["purpose"]
      and not any("--wrap" in v or "--array" in v or "--requeue"==v for v in p["rendered_sbatch_argv"]),
      "closed independently reviewed direct Slurm command")
    validate_native_sbatch_argv(p["rendered_sbatch_argv"])
    review=proofs.linked(p["independent_review"]);core=dict(p);core.pop("independent_review")
    m.require(review.get("status")=="PASS_REVIEWED_R203_FIXED_CONTROL_PHYSICAL_CALENDAR_PROFILE"
      and review.get("profile_core_sha256")==m.digest(core),"independent profile core review")
    return p
def _admission(t,q,proofs,*,now=None,check_current=True):
    a=proofs.linked(t["admission"]);_shape(a,"admission")
    _same(a,t)
    for key in ("node","control_publication","control_map_sha256","runtime_publication","runtime_map_sha256",
                "scope","ledger","quote","output_root"):m.require(a[key]==t[key],"admission binding "+key)
    m.require(a["parameters_sha256"]==m.digest(t["parameters"]) and type(a["maximum_jobs"]) is int
      and a["maximum_jobs"]==1 and type(a["optimizer_invocations"]) is int and a["optimizer_invocations"]==0
      and type(a["new_posterior_fits"]) is int and a["new_posterior_fits"]==0,"single no-target admission")
    _promoted(a,POLICY["admission"]["candidate_status"],POLICY["admission"]["status"],proofs)
    baseline=_baseline(t,a,proofs);p=_profile(t,proofs)
    observed=_capture(a["actual_resource_observation"],proofs,t,"ADMISSION")
    calendar=_capture(a["actual_calendar_assessment"],proofs,t,"ADMISSION")
    m.require(observed["job_id"] is None and observed["template"] is None and observed["request"] is None,
      "admission never invents future job/template/request")
    m.require(calendar["job_id"] is None and calendar["template"] is None and calendar["request"] is None,
      "calendar never invents future job/template/request")
    nodes=[row for row in observed["raw"] if any(Path(v).name=="scontrol" for v in row["argv"]) and "node" in row["argv"]]
    m.require(len(nodes)==1,"one exact native selected-node observation")
    text=nodes[0]["stdout"];fields=dict(re.findall(r"(?:^|\s)([A-Za-z][A-Za-z0-9_]*)=([^\s]+)",text))
    m.require(fields.get("NodeName")==t["node"],"exact selected scheduler node")
    for key in ("RealMemory","AllocMem","CPUTot","CPUAlloc"):m.require(fields.get(key,"").isdigit(),"typed native scheduler "+key)
    m.require(int(fields["RealMemory"])-int(fields["AllocMem"])>=q["memory_MiB"]==p["memory_MiB"]
      and int(fields["CPUTot"])-int(fields["CPUAlloc"])>=p["requested_CPUs"],
      "scheduler unallocated RAM/CPU, never OS FreeMem")
    expected=p["rendered_sbatch_argv"][:-1]+["--test-only",p["rendered_sbatch_argv"][-1]]
    tests=[row for row in calendar["raw"] if row["argv"]==expected]
    m.require(len(tests)==1,"one exact reviewed sbatch --test-only, no shell or arbitrary flags")
    reply=tests[0]["stdout"]+"\n"+tests[0]["stderr"]
    starts=re.findall(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:\d{2})",reply)
    m.require(len(starts)==1 and "start" in reply.lower() and t["node"] in reply,"one explicit UTC/offset native scheduler prediction")
    start=datetime.datetime.fromisoformat(starts[0].replace("Z","+00:00")).timestamp()
    m.require(p["not_before_epoch"]<=start and start+q["whole_wall_seconds"]+p["reserve_seconds"]<=p["window_end_epoch"],
      "predicted full quoted stage and reserve fit original fixed window")
    review=proofs.linked(a["independent_review"])
    m.require(review.get("status")=="PASS_REVIEWED_R203_CONTROL_STAGE_ADMISSION"
      and review.get("admission_core_sha256")==m.digest({k:v for k,v in a.items()
        if k not in {"independent_review","actual_accept_guard","status","issued_epoch","command_pid","command_birth_ticks"}}),
      "independent genuine admission review core")
    for k in ("issued_epoch","expires_epoch"):m.finite(a[k],k)
    if check_current:
        now=time.time() if now is None else now
        m.require(t["issued_epoch"]<=a["issued_epoch"]<=now<a["expires_epoch"]<=t["expires_epoch"]
          and 0<=a["issued_epoch"]-observed["completed_epoch"]<=90
          and 0<=a["issued_epoch"]-calendar["completed_epoch"]<=90
          and a["issued_epoch"]<=p["latest_first_submit_epoch"]<=a["issued_epoch"]+255,
          "genuine fixed-window fresh admission, no fee/clock renewal")
    return a,p,baseline
def inspect_template_metadata(t,*,proofs=None,check_current=False):
    _shape(t,"template");m.require(t["stage"] in STAGES and re.fullmatch("[A-Za-z0-9_]{1,96}",t["purpose"])
      and re.fullmatch("[0-9a-f]{32}",t["nonce"]) and re.fullmatch("node-[0-9]+",t["node"]),"closed stage/purpose/node")
    _parameters(t);_phase_metadata(t)
    boot=m.linked(t["bootstrap_authority"]) if proofs is None else proofs.linked(t["bootstrap_authority"])
    _shape(boot,"bootstrap_authority")
    reader=_Proofs(boot["canonical_input_proofs"]) if proofs is None else proofs
    # Bootstrap/template are the only initial permitted record reads; closure is acyclic.
    reader.allowed[t["bootstrap_authority"]["path"]]=t["bootstrap_authority"]["sha256"]
    q=_quote_and_scope(t,reader);_maps(t,reader);_storage(t,q)
    core=dict(t);core.pop("bootstrap_authority")
    m.require(boot["template_core_sha256"]==m.digest(core),"acyclic bootstrap exact template core")
    _same(boot,t)
    for key in ("node","control_publication","control_map_sha256","runtime_publication","runtime_map_sha256",
                "scope","ledger","quote","admission","output_root"):m.require(boot[key]==t[key],"bootstrap binding "+key)
    m.require(boot["parameters_sha256"]==m.digest(t["parameters"])
      and type(boot["maximum_jobs"]) is int and boot["maximum_jobs"]==1
      and type(boot["maximum_owner_calls"]) is int and boot["maximum_owner_calls"]==1
      and type(boot["optimizer_invocations"]) is int and boot["optimizer_invocations"]==0
      and boot["scientific_target_data_read"] is False,"metadata-only single startup, no payload grant")
    for k in ("issued_epoch","expires_epoch"):m.finite(boot[k],k)
    if check_current:m.require(t["issued_epoch"]<=boot["issued_epoch"]<=time.time()<boot["expires_epoch"]<=t["expires_epoch"],"live metadata bootstrap")
    admission,profile,baseline=_admission(t,q,reader,check_current=check_current)
    return {"status":"CONSISTENT_METADATA_ONLY_NOT_EXECUTION_AUTHORITY","runtime_admitted":False,
      "template":copy.deepcopy(t),"quote":q,"bootstrap":boot,"admission":admission,"profile":profile,"baseline":baseline,"proofs":reader}
def _mount_rows(paths):
    mounts=[]
    for line in Path("/proc/self/mountinfo").read_text().splitlines():
        parts=line.split();sep=parts.index("-");point=parts[4]
        for old,new in ((r"\040"," "),(r"\011","\t"),(r"\012","\n"),(r"\134","\\")):point=point.replace(old,new)
        mounts.append((Path(point),parts[5].split(","),parts[sep+3].split(",")))
    rows=[]
    for text in sorted(set(paths)):
        path=m.physical(text);cover=[v for v in mounts if path==v[0] or path.is_relative_to(v[0])]
        m.require(cover,"actual source/runtime backing mount")
        mount,options,superopts=max(cover,key=lambda v:len(v[0].parts))
        m.require("ro" in options and "ro" in superopts,"real readonly mount AND backing superblock, no bind-only alias")
        rows.append({"path":str(path),"mountpoint":str(mount),"mount_options":options,"super_options":superopts})
    return rows
def _realize_sources(t,baseline,proofs):
    c=t["parameters"]["common"];rows=[];paths=[]
    for group in ("control_sources","runtime_sources"):
        for relative,pin in sorted(t[group].items()):
            raw=m.source_bytes(pin);st=Path(pin["path"]).stat();paths.append(pin["path"])
            rows.append({"path":pin["path"],"sha256":pin["sha256"],"bytes":len(raw),"device":st.st_dev,
              "inode":st.st_ino,"mode":stat.S_IMODE(st.st_mode),"uid":st.st_uid})
    inventory=proofs.linked(c["source_and_baseline"]["dependency_inventory"])
    m.closed(inventory,{"schema","files","exec_allowlist"},"complete immutable baseline dependency inventory")
    m.require(inventory["schema"]=="r203_immutable_dependency_inventory_v1"
      and inventory["exec_allowlist"]==c["exec_allowlist"] and type(inventory["files"]) is list
      and 1<=len(inventory["files"])<=256,"fixed complete baseline/exec closure")
    pins=list(c["source_and_baseline"]["baseline_files"])
    m.require(c["startup_python"] in pins and c["traced_guard"] in pins,"startup Python ELF and unchanged tracer in baseline")
    for dep in inventory["files"]:
        m.closed(dep,{"path","sha256","bytes"},"actual dependency descriptor")
        m.integer(dep["bytes"],"dependency size",1,64*1024**2)
        dep_uid=m.physical(dep["path"]).lstat().st_uid
        m.require(dep_uid in {0,os.getuid()},"immutable system or owned baseline file")
        raw=m.read_regular(dep["path"],limit=64*1024**2,expected_sha=dep["sha256"],
          expected_bytes=dep["bytes"],expected_uid=dep_uid)
        st=Path(dep["path"]).stat();paths.append(dep["path"])
        rows.append({"path":dep["path"],"sha256":dep["sha256"],"bytes":len(raw),"device":st.st_dev,
          "inode":st.st_ino,"mode":stat.S_IMODE(st.st_mode),"uid":st.st_uid})
    declared={(p["path"],p["sha256"]) for p in inventory["files"]}
    m.require(all((p["path"],p["sha256"]) in declared for p in pins)
      and all((path,sha) in declared for path,sha in c["exec_allowlist"].items()),"all exec/native baseline files in actual dependency inventory")
    m.require(str(Path("/proc/self/exe").resolve())==c["startup_python"]["path"],"actual startup Python immutable ELF")
    for relative in ("common/contract.py","common/metadata.py","RUNTIME_BASE.json","PEER_POLICY.json","SCHEMAS.json"):
        m.require(t["control_sources"][relative]["path"]==str(ROOT/relative),"actual fixed installed Common/source premise")
    module=sys.modules.get("_r203_control_contract")
    m.require(module is not None and module.__dict__ is globals()
      and getattr(module,"_r203_source_sha256",None)==t["control_sources"]["common/contract.py"]["sha256"],
      "one authenticated fixed Common module instance")
    return rows,_mount_rows(paths)
def _cpus(text):
    result=set()
    for part in text.strip().split(","):
        if not part:continue
        span=part.split("-")
        if len(span)==1:result.add(int(span[0]))
        else:
            m.require(len(span)==2 and int(span[0])<=int(span[1]),"kernel CPU range")
            result.update(range(int(span[0]),int(span[1])+1))
    return result
def _physical(t,q,p,*,before_reservation=False):
    affinity=os.sched_getaffinity(0);m.require(affinity==set(p["affinity"]) and len(affinity)==1,"actual selected one-core affinity")
    core=next(iter(affinity));online=_cpus(Path("/sys/devices/system/cpu/online").read_text())
    siblings=_cpus((Path("/sys/devices/system/cpu")/("cpu"+str(core))/"topology/thread_siblings_list").read_text())&online
    rows=Path("/proc/self/cgroup").read_text().splitlines();unified=[r[3:] for r in rows if r.startswith("0::")]
    m.require(len(unified)==1 and ".." not in Path(unified[0]).parts,"actual qualified unified cgroup")
    folder=Path("/sys/fs/cgroup")/unified[0].lstrip("/");effective=_cpus((folder/"cpuset.cpus.effective").read_text())
    m.require(siblings<=effective and sorted(siblings)==p["online_thread_siblings"],"all online physical SMT siblings reserved")
    limits=[];current=folder
    while current!=Path("/sys/fs/cgroup"):
        value=(current/"memory.max").read_text().strip()
        if value!="max":limits.append(int(value))
        current=current.parent
    m.require(limits and 0<min(limits)<=q["memory_MiB"]*1024**2,"actual aggregate cgroup memory cap")
    fs=os.statvfs(m.physical(t["output_root"]));available=fs.f_bavail*fs.f_frsize
    storage=t["parameters"]["common"]["storage_policy"]
    needed=q["mandatory_headroom_bytes"]+(q["reserved_filesystem_bytes"] if before_reservation else
      storage["transient_tree_reservation_bytes"]+storage["dynamic_artifact_reservation_bytes"])
    m.require(available>=needed,"actual physical reservation/headroom plus priced dynamic/transient envelope")
    return {"affinity":sorted(affinity),"online_thread_siblings":sorted(siblings),"effective_job_cpus":sorted(effective),
      "cgroup_path":unified[0],"cgroup_memory_limit_bytes":min(limits),"filesystem_available_bytes":available,
      "mandatory_headroom_bytes":q["mandatory_headroom_bytes"],"observed_epoch":time.time()}
def _held_permit(fd,path,owner_pid):
    m.integer(fd,"real inherited permit FD",3);a=os.fstat(fd);b=m.physical(path).stat()
    m.require(stat.S_ISREG(a.st_mode) and a.st_uid==os.getuid() and a.st_nlink==1
      and (a.st_dev,a.st_ino)==(b.st_dev,b.st_ino),"same owned real permit inode")
    own=Path("/proc/self/fdinfo")/str(fd)
    text=own.read_text();m.require("FLOCK" in text and "WRITE" in text,"actual exclusive existing kernel FLOCK")
    if owner_pid!=os.getpid():
        other=Path("/proc")/str(owner_pid)/"fdinfo"/str(fd)
        m.require("FLOCK" in other.read_text() and "WRITE" in other.read_text(),"actual readable parent same-lock FD witness")
def _reserve(root,plan,owner):
    rows=[]
    for row in plan["slots"]:
        path=root/row["name"];fd=os.open(path,os.O_RDWR|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
        try:
            os.posix_fallocate(fd,0,row["maximum_bytes"]);os.fsync(fd);st=os.fstat(fd)
            m.require(st.st_size==row["maximum_bytes"] and st.st_nlink==1 and st.st_uid==os.getuid(),"actual physical paid single-link slot")
            rows.append(dict(row,device=st.st_dev,inode=st.st_ino))
        finally:os.close(fd)
        if row["final_alias"] is not None:m.require(not(root/row["final_alias"]).exists(),"sameinode final alias starts absent")
    record={"schema":"r203_actual_preREADY_reservation_v1","owner":owner,"root":str(root),
      "slots":rows,"physical_slot_bytes":sum(r["maximum_bytes"] for r in rows),"created_epoch":time.time(),
      "no_sparse_fallback_or_cleanup":True}
    slot=next(r for r in rows if r["name"]=="reservation.json");_write_slot(root,slot,m.canonical(record)+b"\n")
    return record,_pin(root/"reservation.json")
def _write_slot(root,row,raw):
    m.require(type(raw) is bytes and 0<len(raw)<row["maximum_bytes"],"complete proof fits prepaid slot beforewrite")
    fd=os.open(root/row["name"],os.O_RDWR|os.O_NOFOLLOW)
    try:
        st=os.fstat(fd);m.require((st.st_dev,st.st_ino)==(row["device"],row["inode"]) and st.st_size==row["maximum_bytes"]
          and st.st_nlink==1 and st.st_uid==os.getuid() and os.pread(fd,min(64,st.st_size),0)==bytes(min(64,st.st_size)),
          "fresh unused paid sameinode slot, failed partial never reused")
        done=0
        while done<len(raw):
            n=os.write(fd,raw[done:]);m.require(n>0 and done+n<=len(raw),"counted complete proof write");done+=n
        os.ftruncate(fd,done);os.fsync(fd)
    finally:os.close(fd)
    return _pin(root/row["name"])

def _context_base(context):
    m.require(type(context) is OwnerContext and _LIVE.get(id(context)) is context
      and context._seal is _SEAL,"actual private sealed control context, never duck types")
    module=sys.modules.get("_r203_control_contract")
    m.require(module is not None and module.__dict__ is globals()
      and getattr(module,"_r203_source_sha256",None)==context._data["control_sources"]["common/contract.py"]["sha256"],
      "same authenticated fixed Common source-module instance")
    return context
def require_context(context,stage):
    _context_base(context);m.require(stage in STAGES and context._data["stage"]==stage,"exact separately admitted stage")
    m.require(context._state=="RELEASED","actual full stage release and one-call claim required")
    context.verify_live();return context
class _BoundedSlotStream:
    """Prewrite bounds for trusted actor streams; children also need kernel FSIZE."""
    __slots__=("_file","_capacity","_writable","_identity","_sealed")
    def __init__(self,stream,maximum_bytes,writable):
        m.integer(maximum_bytes,"paid stream capacity",1,MAX_FILE)
        self._file=stream;self._capacity=maximum_bytes;self._writable=writable;self._sealed=False
        st=os.fstat(stream.fileno());self._identity=(st.st_dev,st.st_ino)
    @property
    def maximum_bytes(self):return self._capacity
    @property
    def closed(self):return self._file.closed
    def fileno(self):return self._file.fileno()
    def tell(self):
        cursor=self._file.tell();m.integer(cursor,"actual bounded stream cursor",0,self._capacity)
        return cursor
    def _check(self):
        st=os.fstat(self.fileno())
        m.require((st.st_dev,st.st_ino)==self._identity and 0<=st.st_size<=self._capacity,
          "same paid stream inode never exceeds capacity")
    def write(self,value):
        m.require(self._writable and not self._sealed and type(value) in (bytes,bytearray,memoryview),"bounded byte stream write")
        data=memoryview(value).cast("B");cursor=self.tell();self._check()
        m.require(data.nbytes<=self._capacity-cursor,"complete next stream write fits before mutation")
        written=self._file.write(data)
        m.require(type(written) is int and 0<=written<=data.nbytes,"actual counted stream write")
        return written
    def seek(self,offset,whence=os.SEEK_SET):
        m.require(type(offset) is int and type(whence) is int and
          whence in (os.SEEK_SET,os.SEEK_CUR,os.SEEK_END),"typed bounded stream seek")
        current=self.tell();base=(0 if whence==os.SEEK_SET else current if whence==os.SEEK_CUR
                                 else os.fstat(self.fileno()).st_size)
        target=base+offset;m.integer(target,"bounded seek target",0,self._capacity)
        m.require(not self._writable or target==current,"write stream cannot seek back/discard complete output")
        return self._file.seek(offset,whence)
    def truncate(self,size=None):
        actual=self.tell();size=actual if size is None else size
        m.integer(size,"bounded truncation",0,self._capacity)
        m.require(self._writable and not self._sealed and size==actual,"only complete actual shared cursor may finalize")
        self._check();return self._file.truncate(size)
    def seal(self):
        self._check();m.require(os.fstat(self.fileno()).st_size==self.tell(),"complete cursor before stream seal")
        self._sealed=True
    def read(self,size=-1):
        m.require(type(size) is int and -1<=size<=self._capacity,"bounded stream read")
        self._check();return self._file.read(size)
    def flush(self):return self._file.flush()
    def close(self):return self._file.close()
    def __enter__(self):return self
    def __exit__(self,kind,value,tb):self.close();return False

class OwnerContext:
    __slots__=("_data","_proofs","_slots","_streams","_state","_kind","_seal")
    def __init__(self,data,proofs,slots,kind,seal):
        m.require(seal is _SEAL,"private actual context constructor")
        for name,value in (("_data",data),("_proofs",proofs),("_slots",{r["name"]:r for r in slots}),
          ("_streams",{}),("_state","READY"),("_kind",kind),("_seal",seal)):object.__setattr__(self,name,value)
        _LIVE[id(self)]=self
    def __setattr__(self,name,value):raise AttributeError("sealed context attributes are read-only")
    def _get(self,key):return copy.deepcopy(self._data.get(key))
    def verify_live(self):
        _context_base(self)
        job,node,proc=_job(subject=self._kind=="SUBJECT")
        d=self._data;owner=d["owner"]
        m.require((job,node,os.getuid())==(d["job_id"],d["node"],d["request_uid"]),"actual same job/node/UID")
        if self._kind=="OWNER":m.require(_identity(proc)==owner,"same actual control owner PID/birth/boot")
        else:
            parent=_proc(proc["ppid"])
            m.require(proc["ppid"]==proc["TracerPid"]==owner["pid"] and parent["start_ticks"]==owner["start_ticks"]
              and proc["start_ticks"]==d["child"]["start_ticks"],"actual same traced subject/parent lifetime")
        _held_permit(d["permit_fd"],d["template"]["parameters"]["common"]["permit_path"],owner["pid"])
        now=time.time();q=d["quote"]
        m.require(now<d["template"]["expires_epoch"],"original full funded stage deadline remains live")
        usage=resource.getrusage(resource.RUSAGE_SELF);children=resource.getrusage(resource.RUSAGE_CHILDREN)
        total=usage.ru_utime+usage.ru_stime+children.ru_utime+children.ru_stime
        m.require(total<q["owner_CPU_seconds"],"whole owner plus inherited waited children CPU, no per-case reset")
        if self._state=="READY":
            m.require(now<d["ready_expires_epoch"] and now<d["bootstrap"]["expires_epoch"],"fixed metadata READY/bootstrap wait")
        else:
            m.require(self._state=="RELEASED" and now<d["authority"]["expires_epoch"]<=d["stage_deadline_epoch"]
              and now-d["stage_started_epoch"]<q["owner_wall_seconds"],"same full stage authority/clock, no lease renewal")
        _physical(d["template"],q,d["profile"])
        if d.get("immutable_paths"):_mount_rows(d["immutable_paths"])
        return self
    def _row(self,name):
        m.require(type(name) is str and name in self._slots,"only fixed paid slot names")
        row=self._slots[name];path=self._data["root"]/name
        alias=row["final_alias"]
        if alias is not None and (self._data["root"]/alias).exists():
            m.require(not path.exists(),"positive final alias is sameinode rename, no duplicate copy")
            path=self._data["root"]/alias
        st=path.lstat()
        m.require(stat.S_ISREG(st.st_mode) and st.st_uid==os.getuid() and st.st_nlink==1
          and (st.st_dev,st.st_ino)==(row["device"],row["inode"]) and 0<=st.st_size<=row["maximum_bytes"],
          "same actual paid slot inode/capacity")
        return row,path
    def open_slot(self,name,mode="r+b"):
        _context_base(self);require_context(self,self._data["stage"])
        m.require(mode in {"r+b","rb"} and name not in self._streams,"closed one-use slot stream mode")
        row,path=self._row(name)
        m.require(path.name==row["name"] and path.stat().st_size==row["maximum_bytes"],"fresh reserved stream before first write")
        if mode=="r+b":
            fd=os.open(path,os.O_RDWR|os.O_NOFOLLOW)
            m.require(os.pread(fd,min(64,row["maximum_bytes"]),0)==bytes(min(64,row["maximum_bytes"])),"unused physical slot")
        else:fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW)
        stream=_BoundedSlotStream(os.fdopen(fd,mode,buffering=0),row["maximum_bytes"],mode=="r+b")
        self._streams[name]=stream;return stream
    def finalize_stream(self,name,used_bytes=None):
        _context_base(self);require_context(self,self._data["stage"])
        m.require(name in self._streams,"actual tracked shared stream")
        stream=self._streams[name];row,path=self._row(name);length=stream.tell()
        m.integer(length,"actual complete shared cursor",0,row["maximum_bytes"])
        if used_bytes is not None:
            m.integer(used_bytes,"declared complete cursor",0,row["maximum_bytes"])
            m.require(used_bytes==length,"cannot drop prefix/truncate arbitrary recorded output")
        stream.truncate(length);stream.flush();os.fsync(stream.fileno());stream.seal()
        return _pin(path)
    def write_metadata(self,name,value):
        _context_base(self);self.verify_live()
        if self._state=="READY":m.require(name in {"startup_claim.json","source_capture.json","physical_witness.json","ready.json","stage_failed.json"},
          "metadata-only startup cannot write payload or stage-start claim")
        else:require_context(self,self._data["stage"])
        row,path=self._row(name);m.require(path.name==name,"metadata cannot overwrite terminal alias")
        raw=m.canonical(value)+b"\n";return _write_slot(self._data["root"],row,raw)
    def close(self,safe):
        _context_base(self)
        if safe:
            fcntl.flock(self._data["permit_fd"],fcntl.LOCK_UN);os.close(self._data["permit_fd"])
            object.__setattr__(self,"_state","CLOSED");_LIVE.pop(id(self),None)
        else:_UNSAFE_FDS.append(self._data["permit_fd"])
for _name in ("stage","template","template_pin","request","request_pin","authority","authority_pin","source_review_pin",
  "owner_review_pin","quote","root","permit_fd","job_id","node","owner","runtime_sources","control_sources",
  "runtime_map_sha256","control_map_sha256","parameters","stage_started_epoch","stage_deadline_epoch","stage_claim_pin",
  "child","parent","case_id","ordinal","native_deadline_epoch"):
    setattr(OwnerContext,_name,property(lambda self,key=_name:self._get(key)))
def load_control(relative,context):
    _context_base(context);require_context(context,context._data["stage"])
    m.require(type(relative) is str and relative in context._data["control_sources"]
      and relative in {"abi/controller.py","abi/subject.py","deployment/worker.py"},"fixed source dispatch only")
    pin=context._data["control_sources"][relative]
    m.require(pin["path"]==str(ROOT/relative),"actual installed fixed control sibling")
    raw=m.source_bytes(pin);spec=importlib.util.spec_from_file_location("_r203_fixed_"+relative.replace("/","_"),pin["path"])
    module=importlib.util.module_from_spec(spec);sys.modules[spec.name]=module
    exec(compile(raw,pin["path"],"exec"),module.__dict__);return module
def owner_startup(template_pin):
    job,node,proc=_job()  # MUST precede supplied template reads.
    owner_started_epoch=time.time()
    m.descriptor(template_pin);m.require(Path(template_pin["path"]).suffix==".json","template JSON metadata only")
    t=m.linked(template_pin);inspected=inspect_template_metadata(t,check_current=True)
    validate_runtime_environment(dict(os.environ),t["parameters"]["common"]["environment"])
    q=inspected["quote"];profile=inspected["profile"];c=t["parameters"]["common"]
    m.require(node==t["node"] and set(profile["affinity"])<=os.sched_getaffinity(0),"actual assigned selected node/core")
    for key in THREADS:m.require(os.environ.get(key)=="1","actual single-thread startup "+key)
    root=m.physical(t["output_root"]);root.mkdir(mode=0o700)
    st=root.stat();m.require(st.st_uid==os.getuid() and stat.S_IMODE(st.st_mode)==0o700,"fresh owned stage namespace")
    os.sched_setaffinity(0,set(profile["affinity"]))  # Only this new job's own process.
    physical=_physical(t,q,profile,before_reservation=True)
    files,readonly=_realize_sources(t,inspected["baseline"],inspected["proofs"])
    fd=os.open(m.physical(c["permit_path"]),os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW|os.O_CLOEXEC,0o600)
    fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);os.set_inheritable(fd,True);owner=_identity(proc)
    _held_permit(fd,c["permit_path"],owner["pid"])
    resource.setrlimit(resource.RLIMIT_CPU,(q["owner_CPU_seconds"],q["owner_CPU_seconds"]))
    resource.setrlimit(resource.RLIMIT_FSIZE,(MAX_FILE,MAX_FILE));resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    reservation,reservation_pin=_reserve(root,c["storage_policy"],owner)
    physical=_physical(t,q,profile)
    created=time.time();expiry=min(t["expires_epoch"],inspected["bootstrap"]["expires_epoch"],created+120)
    data={"stage":t["stage"],"template":t,"template_pin":template_pin,"request":None,"request_pin":None,
      "authority":None,"authority_pin":None,"source_review_pin":None,"owner_review_pin":None,"quote":q,"root":root,
      "permit_fd":fd,"job_id":job,"node":node,"owner":owner,"request_uid":os.getuid(),
      "runtime_sources":t["runtime_sources"],"control_sources":t["control_sources"],
      "runtime_map_sha256":t["runtime_map_sha256"],"control_map_sha256":t["control_map_sha256"],
      "parameters":t["parameters"],"stage_started_epoch":None,"stage_deadline_epoch":t["expires_epoch"],"owner_started_epoch":owner_started_epoch,
      "stage_claim_pin":None,"ready_expires_epoch":expiry,"bootstrap":inspected["bootstrap"],"profile":profile,
      "immutable_paths":[r["path"] for r in readonly],"reservation":reservation,"reservation_pin":reservation_pin,
      "parent":_proc(os.getppid()),"child":None,"case_id":None,"ordinal":None,"native_deadline_epoch":None}
    ctx=OwnerContext(data,inspected["proofs"],reservation["slots"],"OWNER",_SEAL)
    ctx.write_metadata("startup_claim.json",{"schema":"r203_metadata_startup_spent_v1","status":"SPENT_METADATA_STARTUP_NO_RETRY",
      "template":template_pin,"owner":owner,"job_id":job,"node":node,"created_epoch":created})
    source={k:t[k] for k in ("purpose","nonce","stage","control_publication","control_map_sha256","runtime_publication","runtime_map_sha256",
      "control_sources","runtime_sources")}
    source.update(schema=POLICY["startup_source_witness"]["schema"],template=template_pin,job_id=job,node=node,owner=owner,
      files=files,readonly_files=readonly,baseline_files=c["source_and_baseline"]["baseline_files"],
      parameters_sha256=m.digest(t["parameters"]),observed_epoch=time.time())
    sourcepin=ctx.write_metadata("source_capture.json",source)
    witness={k:t[k] for k in ("purpose","nonce","stage")}
    witness.update(physical,schema=POLICY["physical_witness"]["schema"],template=template_pin,job_id=job,node=node,owner=owner,
      reservation=reservation_pin,parameters_sha256=m.digest(t["parameters"]))
    physicalpin=ctx.write_metadata("physical_witness.json",witness)
    ready={k:t[k] for k in ("purpose","nonce","stage","control_publication","control_map_sha256","runtime_publication",
      "runtime_map_sha256","scope","ledger","quote")}
    ready.update(schema=CAT["ready"]["schema"],status=CAT["ready"]["status"],template=template_pin,job_id=job,node=node,uid=os.getuid(),
      owner=owner,affinity=profile["affinity"],root=str(root),permit_fd=fd,permit_path=c["permit_path"],source_capture=sourcepin,
      physical_witness=physicalpin,parameters_sha256=m.digest(t["parameters"]),owner_started_epoch=owner_started_epoch,created_epoch=created,expires_epoch=expiry)
    data["ready_pin"]=ctx.write_metadata("ready.json",ready);data["source_capture_pin"]=sourcepin
    data["physical_witness_pin"]=physicalpin
    return ctx
def _peer_pair(t,request,request_pin,source_pin,owner_pin,proofs,entry_epoch):
    source=proofs.linked(source_pin);owner=proofs.linked(owner_pin)
    for record,kind in ((source,"source_peer"),(owner,"owner_peer")):
        _shape(record,kind);_same(record,t)
        m.require(record["request"]==request_pin and record["template"]==request["template"]
          and record["job_id"]==request["job_id"] and record["node"]==request["node"]
          and record["parameters_sha256"]==m.digest(t["parameters"])
          and record["control_map_sha256"]==t["control_map_sha256"]
          and record["runtime_map_sha256"]==t["runtime_map_sha256"]
          and record["independent_program"]["sha256"]==t["control_sources"]["peer/independent_peer.py"]["sha256"]
          and record["runtime_admitted"] is False,"exact independently authored actual peer")
        for key in ("issued_epoch","expires_epoch"):m.finite(record[key],key)
        m.require(record["issued_epoch"]<=entry_epoch<record["expires_epoch"]<=record["issued_epoch"]+60,
          "first entry inside original immutable peer lease")
    m.require(owner["source_review"]==source_pin and source["source_capture"]==request["source_capture"]
      and source["physical_witness"]==owner["physical_witness"]==request["physical_witness"]
      and owner["owner_ready"]==request["ready"],"two independent actual captured phases")
    first=_capture(source["observation"],proofs,t,"SOURCE_PHYSICAL")
    second=_capture(owner["observation"],proofs,t,"OWNER_READY")
    for r in (first,second):
        m.require(r["job_id"]==request["job_id"] and r["request"]==request_pin
          and r["template"]==request["template"] and 0<=entry_epoch-r["completed_epoch"]<90,"fresh actual own-job capture")
    return source,owner
def _release_context(context,release,historical_claim=None):
    d=context._data;t=d["template"];_shape(release,"release")
    m.require(release["template"]==d["template_pin"],"exact current template release")
    context._proofs.extend(release["canonical_input_proofs"])
    proofs=context._proofs;request=proofs.linked(release["request"]);_shape(request,"request")
    m.require(request["template"]==d["template_pin"] and request["purpose"]==t["purpose"] and request["nonce"]==t["nonce"]
      and request["stage"]==t["stage"] and request["job_id"]==d["job_id"] and request["node"]==d["node"]
      and request["uid"]==os.getuid() and request["owner"]==d["owner"] and request["root"]==str(d["root"])
      and request["permit_fd"]==d["permit_fd"] and request["permit_path"]==t["parameters"]["common"]["permit_path"]
      and request["affinity"]==d["profile"]["affinity"],"same actual READY owner/core/permit")
    for key in ("control_map_sha256","runtime_map_sha256","scope","ledger","quote"):m.require(request[key]==t[key],"same request "+key)
    ready=proofs.linked(request["ready"]);_shape(ready,"ready")
    m.require(ready["owner"]==d["owner"] and release["ready"]==request["ready"]
      and ready["source_capture"]==request["source_capture"] and ready["physical_witness"]==request["physical_witness"],
      "same immutable actual READY/source/physical pins")
    if context._kind=="OWNER":
        m.require(request["ready"]==d["ready_pin"] and request["source_capture"]==d["source_capture_pin"]
          and request["physical_witness"]==d["physical_witness_pin"],"cannot renew or substitute actual original READY witnesses")
    for key in ("issued_epoch","expires_epoch"):m.finite(release[key],"release "+key)
    entry=time.time() if historical_claim is None else historical_claim["stage_started_epoch"]
    m.finite(ready["owner_started_epoch"],"actual original owner startup epoch")
    m.require(ready["owner_started_epoch"]==d["owner_started_epoch"]<=ready["created_epoch"]
      and ready["created_epoch"]<=entry<ready["expires_epoch"]<=ready["created_epoch"]+120,
      "actual owner clock and first entry inside original READY120")
    m.require(ready["created_epoch"]<=request["issued_epoch"]<=entry and request["expires_epoch"]==t["expires_epoch"]
      and release["issued_epoch"]<=entry<release["expires_epoch"]<=ready["expires_epoch"],"original request/release clocks without renewal")
    source,owner=_peer_pair(t,request,release["request"],release["source_review"],release["owner_review"],proofs,entry)
    authority=proofs.linked(release["authority"]);_shape(authority,"authority");_same(authority,t)
    m.require(authority["request"]==release["request"] and authority["source_review"]==release["source_review"]
      and authority["owner_review"]==release["owner_review"] and authority["job_id"]==d["job_id"]
      and authority["node"]==d["node"] and authority["owner"]==d["owner"] and authority["uid"]==os.getuid()
      and authority["root"]==str(d["root"]) and authority["permit_fd"]==d["permit_fd"]
      and authority["parameters_sha256"]==m.digest(t["parameters"]),"full exact Root stage authority")
    for key in ("control_publication","control_map_sha256","runtime_publication","runtime_map_sha256","scope","ledger","quote","admission"):
        m.require(authority[key]==t[key],"same authority "+key)
    for key in ("issued_epoch","expires_epoch"):m.finite(authority[key],key)
    m.require(max(source["issued_epoch"],owner["issued_epoch"])<=authority["issued_epoch"]<=entry
      and time.time()<authority["expires_epoch"]<=min(t["expires_epoch"],ready["owner_started_epoch"]+d["quote"]["owner_wall_seconds"])
      and entry<authority["expires_epoch"],
      "authority issued inside both peers with complete fixed whole-stage clock")
    maximum=9 if t["stage"]=="NATIVE_ABI_SUITE" else 1
    m.require(type(authority["maximum_owner_calls"]) is int and authority["maximum_owner_calls"]==1
      and type(authority["maximum_traced_subjects"]) is int and authority["maximum_traced_subjects"]==maximum
      and type(authority["optimizer_invocations"]) is int and authority["optimizer_invocations"]==0
      and type(authority["new_posterior_fits"]) is int and authority["new_posterior_fits"]==0
      and authority["scientific_target_data_read"] is False,"one finite no-target controller stage")
    d.update(request=request,request_pin=release["request"],authority=authority,authority_pin=release["authority"],
      source_review_pin=release["source_review"],owner_review_pin=release["owner_review"],
      stage_started_epoch=entry,stage_deadline_epoch=min(authority["expires_epoch"],
        d.get("owner_started_epoch",historical_claim["owner_started_epoch"] if historical_claim is not None else entry)+d["quote"]["owner_wall_seconds"]))
    return d
def wait_and_admit(context):
    _context_base(context);m.require(context._kind=="OWNER" and context._state=="READY","single actual owner release")
    context.verify_live();d=context._data;marker=d["root"]/"RELEASE.ready"
    deadline=time.monotonic()+max(0,d["ready_expires_epoch"]-time.time())
    while not marker.exists() and time.monotonic()<deadline:
        context.verify_live();time.sleep(.1)
    m.read_regular(marker,limit=0,expected_bytes=0,expected_uid=os.getuid())
    release=m.strict_json(m.read_regular(d["root"]/"RELEASE.json",limit=4*1024**2,expected_uid=os.getuid()))
    _release_context(context,release)
    claim={"schema":CAT["stage_claim"]["schema"],"status":CAT["stage_claim"]["status"],
      "request":d["request_pin"],"authority":d["authority_pin"],"source_review":d["source_review_pin"],"owner_review":d["owner_review_pin"],
      "purpose":d["template"]["purpose"],"nonce":d["template"]["nonce"],"stage":d["stage"],"job_id":d["job_id"],"node":d["node"],
      "owner":d["owner"],"permit_fd":d["permit_fd"],"stage_started_epoch":d["stage_started_epoch"],"owner_started_epoch":d["owner_started_epoch"],
      "stage_deadline_epoch":d["stage_deadline_epoch"],"maximum_owner_calls":1,
      "maximum_traced_subjects":9 if d["stage"]=="NATIVE_ABI_SUITE" else 1}
    d["stage_claim_pin"]=_write_slot(d["root"],context._slots["stage_claim.json"],m.canonical(claim)+b"\n")
    object.__setattr__(context,"_state","RELEASED");context.verify_live();return context
def enter_subject(descriptor_pin,expected_case):
    job,node,proc=_job(subject=True)  # Actual traced child BEFORE supplied descriptor.
    m.descriptor(descriptor_pin);m.require(Path(descriptor_pin["path"]).suffix==".json","subject JSON metadata only")
    desc=m.linked(descriptor_pin);m.closed(desc,set(CAT["subject"]["keys"]),"fixed subject descriptor")
    m.require(desc["schema"]=="r203_control_subject_descriptor_v1" and desc["case_id"]==expected_case
      and desc["owner"]["pid"]==proc["ppid"]==proc["TracerPid"] and desc["job_id"]==job and desc["node"]==node,
      "actual child/owner/job and fixed subject case")
    request=m.linked(desc["request"]);t=m.linked(request["template"])
    info=inspect_template_metadata(t,check_current=False);proofs=info["proofs"]
    root=m.physical(desc["root"]);release=m.strict_json(m.read_regular(root/"RELEASE.json",limit=4*1024**2,expected_uid=os.getuid()))
    m.read_regular(root/"RELEASE.ready",limit=0,expected_bytes=0,expected_uid=os.getuid())
    claim=m.linked(desc["stage_claim"]);_shape(claim,"stage_claim")
    # PostREADY closure carries actual physical/claim records; no arbitrary history walk.
    proofs.extend(release["canonical_input_proofs"])
    physical=proofs.linked(request["physical_witness"]);reservation=proofs.linked(physical["reservation"])
    parent=_proc(proc["ppid"])
    m.require(desc["owner"]==request["owner"]==_identity(parent) and root==m.absolute(request["root"])
      and desc["permit_fd"]==request["permit_fd"] and claim["request"]==desc["request"]
      and claim["authority"]==desc["authority"] and claim["owner"]==request["owner"]
      and desc["stage_claim"]["path"]==str(root/"stage_claim.json"),"derived exact actual admitted stage and one-call claim")
    data={"stage":t["stage"],"template":t,"template_pin":request["template"],"request":request,"request_pin":desc["request"],
      "authority":None,"authority_pin":desc["authority"],"source_review_pin":None,"owner_review_pin":None,
      "quote":info["quote"],"root":root,"permit_fd":desc["permit_fd"],"job_id":job,"node":node,"owner":desc["owner"],
      "request_uid":os.getuid(),"runtime_sources":t["runtime_sources"],"control_sources":t["control_sources"],
      "runtime_map_sha256":t["runtime_map_sha256"],"control_map_sha256":t["control_map_sha256"],"parameters":t["parameters"],
      "stage_started_epoch":claim["stage_started_epoch"],"stage_deadline_epoch":claim["stage_deadline_epoch"],"owner_started_epoch":claim["owner_started_epoch"],
      "stage_claim_pin":desc["stage_claim"],"ready_expires_epoch":0,"bootstrap":info["bootstrap"],"profile":info["profile"],
      "immutable_paths":[],"reservation":reservation,"reservation_pin":physical["reservation"],"parent":parent,
      "child":{"pid":proc["pid"],"start_ticks":proc["start_ticks"]},"case_id":expected_case,"ordinal":desc["ordinal"],
      "native_deadline_epoch":desc["native_deadline_epoch"]}
    ctx=OwnerContext(data,proofs,reservation["slots"],"SUBJECT",_SEAL)
    _release_context(ctx,release,historical_claim=claim)
    m.require(ctx._data["request_pin"]==desc["request"] and ctx._data["authority_pin"]==desc["authority"],"same subject authority")
    if t["stage"]=="NATIVE_ABI_SUITE":
        cases=t["parameters"]["stage"]["subject_policy"]["cases"]
        row=next((r for r in cases if r["case_id"]==expected_case),None)
        m.require(row is not None and type(desc["ordinal"]) is int and row["ordinal"]==desc["ordinal"],"fixed ABI ordinal/case")
    else:
        m.require((t["stage"],expected_case) in {("FACILITY_PRECHECK","facility_observer"),("READONLY_DEPLOYMENT","readonly_observer")}
          and type(desc["ordinal"]) is int and desc["ordinal"]==1,"fixed metadata observer subject")
    for key in ("native_deadline_epoch","issued_epoch","expires_epoch"):m.finite(desc[key],key)
    m.require(claim["stage_started_epoch"]<=desc["issued_epoch"]<=time.time()<desc["expires_epoch"]<=claim["stage_deadline_epoch"]
      and desc["native_deadline_epoch"]<=desc["expires_epoch"],"subject bounded by original full stage, no renewal")
    files,readonly=_realize_sources(t,info["baseline"],proofs);data["immutable_paths"]=[r["path"] for r in readonly]
    object.__setattr__(ctx,"_state","RELEASED");ctx.verify_live();return ctx

def _phase_metadata(t):
    p=t["parameters"]["stage"];stage=t["stage"]
    if stage=="FACILITY_PRECHECK":
        for k in ("facility_plan","toolchain_closure"):m.descriptor(p[k])
        m.absolute(p["output_library"]);m.require(type(p["canonical_paths"]) is list and 1<=len(p["canonical_paths"])<=256,"exact facility path plan")
        for row in p["canonical_paths"]:
            m.closed(row,{"path","kind","may_be_missing_before_build"},"facility path row");m.absolute(row["path"])
            m.require(type(row["kind"]) is str and type(row["may_be_missing_before_build"]) is bool,"typed declared facility path")
    elif stage=="OWNED_NATIVE_BUILD":
        for k in ("facility_precheck","facility_plan","source","header","abi","compiler","toolchain_closure"):m.descriptor(p[k])
        for k,name in (("source","native_python/r201_native_boundary.c"),("header","native_python/r201_native_boundary.h"),
                       ("abi","native_python/native_abi.json")):
            m.require(p[k]==t["runtime_sources"][name],"exact unchanged native build source "+k)
        m.require(m.absolute(p["output_library"]).parent==m.absolute(p["build_directory"])
          and Path(p["output_library"]).name=="r201_native_boundary.so","actual final canonical compiler path")
        m.integer(p["maximum_compiler_execs"],"separate compiler/helper exec bound",1,64)
    elif stage=="READONLY_DEPLOYMENT":
        for k in ("facility_plan","build_acceptance","native_build_manifest","native_library","native_abi"):m.descriptor(p[k])
        for row in p["baseline_files"]:m.descriptor(row)
    else:
        for k in ("native_library","native_abi","native_build_manifest","build_acceptance","deployment_acceptance"):m.descriptor(p[k])
        m.require(p["native_abi"]==t["runtime_sources"]["native_python/native_abi.json"],"fixed runtime native ABI")
        for row in p["native_dependencies"]:
            m.closed(row,{"path","sha256","bytes"},"fixed native dependency");m.descriptor({k:row[k] for k in ("path","sha256")})
            m.integer(row["bytes"],"native dependency bytes",1,64*1024**2)
        policy=p["subject_policy"];m.closed(policy,{"cases","founder","storage_slots"},"fixed ABI subject policy")
        expected=[("pre_ack_live",False),("wrong_lifetime",False),("wrong_permit",False),("late_transition",False),
          ("repeat_transition",True),("real_ACK",True),("live_rechecks",True),("noreplace_collision",True),("bounded_storage",True)]
        m.require(type(policy["cases"]) is list and len(policy["cases"])==9,"exact nine fresh ABI subjects")
        for ordinal,(row,(case,handshake)) in enumerate(zip(policy["cases"],expected),1):
            m.closed(row,{"case_id","ordinal","handshake","child_CPU_seconds","wall_seconds","native_deadline_rule"},"fixed case rule")
            m.require(row["case_id"]==case and type(row["ordinal"]) is int and row["ordinal"]==ordinal
              and row["handshake"] is handshake,"exact case/ordinal/handshake")
            for k in ("child_CPU_seconds","wall_seconds"):m.integer(row[k],k,1,28800)
            rule=row["native_deadline_rule"]
            if case=="late_transition":
                m.closed(rule,{"kind","descriptor_window_seconds","native_interval_seconds","wait_margin_seconds"},"fixed narrow-late rule")
                m.require(rule=={"kind":"PREP_READY_PLUS_SECONDS_WITH_FIXED_DESCRIPTOR_UPPER_BOUND",
                  "descriptor_window_seconds":30,"native_interval_seconds":2,"wait_margin_seconds":1}
                  and row["wall_seconds"]>=40,"fixed preparation/late clock; never renew")
            else:m.require(rule=={"kind":"STAGE_DEADLINE"},"ordinary immutable fullstage deadline")
        groups=policy["storage_slots"];m.require(type(groups) is dict and set(groups)=={"founder","proof",*(v[0] for v in expected)},
          "exact founder/case/proof storage groups")
        declared={row["name"]:row for row in t["parameters"]["common"]["storage_policy"]["slots"]};seen=set()
        for key,row in groups.items():
            m.closed(row,{"slot_names","file_cap_bytes","slot_count","physical_reserved_bytes"},"fixed storage group")
            m.integer(row["file_cap_bytes"],"maximum group file cap",1,MAX_FILE)
            m.integer(row["slot_count"],"group slot count",1,256);m.integer(row["physical_reserved_bytes"],"group physical sum",1)
            m.require(type(row["slot_names"]) is list and len(row["slot_names"])==row["slot_count"]
              and all(name in declared and name not in seen for name in row["slot_names"]),"exact unique declared storage rows")
            caps=[declared[name]["maximum_bytes"] for name in row["slot_names"]]
            m.require(row["file_cap_bytes"]==max(caps) and row["physical_reserved_bytes"]==sum(caps),"mixed proof MAX cap and actual SUM, no double charge")
            if key!="proof":m.require(all(cap==512*1024 for cap in caps),"fixed founder/case512KiB slots")
            seen.update(row["slot_names"])
        m.require(seen==set(declared),"no hidden proof slot inventory")
    if "canonical_metadata_inputs" in p:
        m.require(type(p["canonical_metadata_inputs"]) is list and len(p["canonical_metadata_inputs"])<=256,"closed canonical metadata path list")
        for row in p["canonical_metadata_inputs"]:m.descriptor(row)
    if "same_path_policy" in p:m.require(p["same_path_policy"]=="FACILITY_SEALS_SAME_CANONICAL_BUILD_OUTPUT_NO_JSON_REWRITE","no relocated output or JSON rewrite")
def inventory(context):
    require_context(context,context._data["stage"]);rows=[];root=context._data["root"]
    allowed=set(context._slots)|{r["final_alias"] for r in context._slots.values() if r["final_alias"] is not None}
    ingress=set(POLICY["record_transport"]["allowed_names"])
    useful=0;physical=0
    for path in root.iterdir():
        st=path.lstat()
        m.require(stat.S_ISREG(st.st_mode) and st.st_uid==os.getuid() and st.st_nlink==1
          and path.name in allowed|ingress and st.st_size<=MAX_FILE,"complete declared owned file inventory, no hidden files")
        physical+=st.st_size
        blank_unused=False
        if path.name in context._slots and st.st_size==context._slots[path.name]["maximum_bytes"]:
            data=m.read_regular(path,limit=MAX_FILE,expected_uid=os.getuid());blank_unused=not any(data)
        if path.name in ingress or not blank_unused:
            useful+=st.st_size
        rows.append({"name":path.name,"bytes":st.st_size,"device":st.st_dev,"inode":st.st_ino,
          "sha256":_pin(path)["sha256"],"prepaid":path.name in allowed})
    m.require(useful<=MAX_USEFUL,"whole useful return including mandatory proofs and ingress <=64MiB")
    return {"schema":"r203_complete_owned_proof_inventory_v1","files":rows,"observed_epoch":time.time(),
      "useful_bytes_at_observation":useful,"physical_logical_bytes_at_observation":physical,
      "final_inventory_and_terminal_accounting_pending":True,"no_cleanup":True}
