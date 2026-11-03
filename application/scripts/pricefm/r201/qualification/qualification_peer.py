"""Independent initial-only qualification source/physical and owner-release peer.
Metadata guards attest actual observed facts; source fixtures never grant runtime.
This module neither delegates policy to Root's qualification boundary/owner nor
accepts a validator, callback, production handle or scientific input manifest.
"""
import hashlib,importlib.util,os,re,time
from pathlib import Path
_ROOT=Path(__file__).absolute().parent.parent
_LEGACY_SHA="98fd0b635fbc1971306b0068db693d7a5036fe345d9f2c925e67eef92649281a"
_path=_ROOT/"owner/pilot_independent_peer.py";_raw=_path.read_bytes()
if any(p.is_symlink() for p in (_path,*_path.parents)) or hashlib.sha256(_raw).hexdigest()!=_LEGACY_SHA:
    raise ValueError("exact independently Root-reviewed helper source")
_sp=importlib.util.spec_from_file_location("_r201_qualification_legacy_primitives",_path)
legacy=importlib.util.module_from_spec(_sp);exec(compile(_raw,str(_path),"exec"),legacy.__dict__)
m=legacy.m
_ROOT_REVIEW={"path":"/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_r165_headroom_execution_20261029_1526PDT/pilot_and_reference_implementation_20261102_1449PST/review/ROOT_PEER8.REVIEW.json","sha256":"377833dfdb99d4bee39ba4c1ebd60eec1bde7d168222873624ff634b196db078"}
_oldreview=m.linked(_ROOT_REVIEW)
m.require(_oldreview.get("status")=="PASS_REVIEWED_R200_INDEPENDENT_PEER_SOURCE"
          and _oldreview.get("peer",{}).get("sha256")==_LEGACY_SHA,"independent coverage of reused primitives")
SPEC_KEYS=set(["schema","purpose","nonce","role","job_id","node","uid","affinity","root","owner","case","case_sha256","source_map_sha256","source_publication","source_pins","owner_launch","scope","ledger","quote","build_acceptance","deployment_acceptance","acknowledgement_path","resource_lock_fd","resource_lock_path","attempt_claim_path","issued_epoch","expires_epoch"])
QUOTE_KEYS=set(["schema","status","purpose","nonce","role","source_publication","source_map_sha256","case_sha256","components","whole_CPU_seconds","whole_wall_seconds","compute_CPU_reservation","administrative_CPU_reservation","remote_unknown_CPU_reservation","owner_CPU_seconds","child_CPU_seconds","owner_wall_seconds","memory_MiB","reserved_filesystem_bytes","mandatory_headroom_bytes","return_proof_reservation_bytes","proof_storage_reservation_bytes","independent_review"])
BUILD_KEYS=set(["schema","status","source_map_sha256","native_build_manifest","native_library","native_abi","result","independent_review","accounting","actual_accept_guard","created_epoch"])
DEPLOY_KEYS=set(["schema","status","source_map_sha256","build_acceptance","baseline_files","namespace_witnesses","result","independent_review","accounting","actual_accept_guard","created_epoch"])
BUILD_KEYS|={"command_pid","command_birth_ticks"}
DEPLOY_KEYS|={"command_pid","command_birth_ticks"}
LAUNCH_KEYS=set(["schema","purpose","nonce","role","job_id","node","bootstrap","native_executable","native_library","native_build_manifest","native_abi","native_build_acceptance","native_deployment_acceptance","traced_guard","baseline_files","environment","bootstrap_exec_allowlist","stdout_path","stderr_path","owned_tree_path","owned_guard_path","output_root"])
BUNDLE_KEYS=set(["schema","spec","source_publication","source_pins","source_observation_guard","physical_admission","physical_observation_guard","owner_ready","ready_observation_guard"])
SOURCE_WITNESS_KEYS=set(["schema","purpose","nonce","role","job_id","node","uid","owner","root","case_sha256","source_map_sha256","source_publication","source_pins","scope","quote","build_acceptance","deployment_acceptance","files","readonly_files","observed_epoch"])
PHYSICAL_KEYS=set(["schema","job_id","node","owner","affinity","online_thread_siblings","effective_job_cpus","cgroup_memory_limit_bytes","filesystem_available_bytes","filesystem_mandatory_headroom_bytes","scope","observed_epoch"])
READY_KEYS=set(["schema","status","purpose","nonce","role","job_id","node","uid","owner","resource_lock_fd","resource_lock_path","root","case_sha256","source_map_sha256","source_publication","scope","ledger","quote","build_acceptance","deployment_acceptance","physical_admission","created_epoch","expires_epoch"])
CAPTURE_KEYS=set(["schema","status","spec","purpose","nonce","role","job_id","node","command_pid","command_birth_ticks","observed_epoch","witness"])
CASE={"families":["diagonal","rank_one","paired_ill_conditioned"],"new_posterior_fits":0,"optimizer_updates":0,"schema":"r200_analytic_reference_fixture_request_v1","sizes":[8,16,32]}
ROLE="INITIAL_NATIVE_REFERENCE_QUALIFICATION"
IDENTITY=("purpose","nonce","role","job_id","node")
FUNDING=("scope","ledger","quote","build_acceptance","deployment_acceptance")
COMPONENTS={"startup","namespace","import","optimizer","certification","checkpoint","return","independent_peer","closure"}
THREADS=("OPENBLAS_NUM_THREADS","OMP_NUM_THREADS","MKL_NUM_THREADS","VECLIB_MAXIMUM_THREADS","NUMEXPR_NUM_THREADS","BLIS_NUM_THREADS")
TRACE_SHA="914d7d369d68579b7149c5130e3bba5d59f3b8f09a5bf691e1557ccbcd40c963"

def _same(value,spec,keys=IDENTITY):
    for key in keys:m.require(value.get(key)==spec[key],"same initial qualification "+key)
def _exact(value,expected):
    m.require(type(value) is type(expected),"exact synthetic metadata type")
    if type(expected) is dict:
        m.closed(value,expected,"fixed synthetic case")
        for k in expected:_exact(value[k],expected[k])
    elif type(expected) is list:
        m.require(len(value)==len(expected),"exact synthetic case size")
        for x,y in zip(value,expected):_exact(x,y)
    else:m.require(value==expected,"exact synthetic case value")
def _now(value):
    current=time.time()
    if value is None:return current
    m.finite(value,"metadata observation time")
    m.require(abs(value-current)<=1,"actual current clock, no fixture clock admission")
    return value
def _fresh(value,key,now,maximum):
    m.finite(value.get(key),key);m.require(0<=now-value[key]<=maximum,"fresh actual "+key)
def _inspect(spec,now):
    m.closed(spec,SPEC_KEYS,"initial-only spec")
    m.require(spec["schema"]=="r201_native_reference_qualification_spec_v1" and spec["role"]==ROLE
      and type(spec["purpose"]) is str and re.fullmatch("[A-Za-z0-9_]{1,96}",spec["purpose"])
      and type(spec["nonce"]) is str and re.fullmatch("[0-9a-f]{32}",spec["nonce"])
      and type(spec["job_id"]) is str and re.fullmatch("[1-9][0-9]{0,11}",spec["job_id"])
      and type(spec["node"]) is str and re.fullmatch("node-[0-9]{2}",spec["node"]),"closed initial identity")
    _exact(spec["case"],CASE);m.require(spec["case_sha256"]==m.digest(CASE),"fixed nine-case identity")
    m.integer(spec["uid"],"actual compute UID")
    m.closed(spec["owner"],{"pid","start_ticks","boot_id"},"actual owner birth")
    m.integer(spec["owner"]["pid"],"owner PID",1);m.integer(spec["owner"]["start_ticks"],"owner birth",1)
    m.require(type(spec["owner"]["boot_id"]) is str and re.fullmatch("[0-9a-f-]{36}",spec["owner"]["boot_id"]),"boot identity")
    m.require(type(spec["affinity"]) is list and len(spec["affinity"])==1,"one owned CPU");m.integer(spec["affinity"][0],"CPU",0)
    m.integer(spec["resource_lock_fd"],"inherited permit FD",3)
    root=m.absolute(spec["root"]);m.absolute(spec["resource_lock_path"])
    for k in ("acknowledgement_path","attempt_claim_path"):m.require(m.absolute(spec[k]).is_relative_to(root),"private initial path")
    for k in ("source_publication","owner_launch",*FUNDING):m.descriptor(spec[k])
    for k in ("issued_epoch","expires_epoch"):m.finite(spec[k],k)
    m.require(spec["issued_epoch"]<=now<spec["expires_epoch"] and 0<spec["expires_epoch"]-spec["issued_epoch"]<=28800,"fixed initial lifetime")
    pins=spec["source_pins"];m.require(type(pins) is dict and 1<=len(pins)<=128,"finite complete source map")
    for name,p in pins.items():
        m.require(type(name) is str and re.fullmatch("[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*",name)
          and str(Path(name))==name and ".." not in Path(name).parts,"closed relative source")
        m.descriptor(p)
    own=pins.get("qualification/qualification_peer.py")
    m.require(own is not None and own["sha256"]==m.pin_file(Path(__file__))["sha256"],"published independent initial peer")
    pub=m.linked(spec["source_publication"])
    m.require(pub.get("schema")=="r200_source_publication_v1" and pub.get("status")=="PASS_PUBLISHED_R200_SOURCE_PREPARATION"
      and pub.get("commit")==pub.get("remote_readback") and type(pub.get("commit")) is str
      and re.fullmatch("[0-9a-f]{40}",pub["commit"]) and type(pub.get("branch")) is str
      and pub["branch"].startswith("work/pricefm-") and pub.get("files")=={k:v["sha256"] for k,v in pins.items()}
      and spec["source_map_sha256"]==m.digest(pub["files"]),"actual current published complete closure")
    return pub
def _lineage(current,base):
    m.descriptor(base);seen=set();counters=("total_administrative_reservation","total_new_administrative_reservation","total_qualification_compute_reservation","total_new_qualification_compute_reservation")
    for unused in range(64):
        if current==base:m.linked(base);return
        m.require(current["sha256"] not in seen,"acyclic whole funding lineage");seen.add(current["sha256"])
        after=m.linked(current);prior=after.get("previous");before=m.linked(prior)
        m.require(set(after)==set(before)|{"previous","created_epoch"} and type(after.get("scopes")) is list
          and after["scopes"][:-1]==before["scopes"] and len(after["scopes"])==len(before["scopes"])+1,"retain all scopes and append once")
        row=after["scopes"][-1];admin=m.integer(row.get("administrative_CPU_reservation"),"new complete admin fee",1)
        compute=m.integer(row.get("compute_CPU_reservation"),"new primary compute fee",0);grant=m.linked(row["scope"])
        m.require(grant.get("previous_ledger",grant.get("ledger_before"))==prior and grant.get("purpose")==row.get("purpose")
          and grant.get("new_administrative_CPU_reservation")==admin,"grant binds unchanged previous whole ledger")
        wanted=grant.get("compute_CPU_reservation",grant.get("new_compute_CPU_reservation"))
        m.require(type(wanted) is int and wanted==compute and all(x.get("purpose")!=row["purpose"] for x in before["scopes"]),"no fee or purpose replay")
        for key,delta in zip(counters,(admin,admin,compute,compute)):
            m.integer(after[key],key);m.integer(before[key],key);m.require(after[key]==before[key]+delta,"whole conserved "+key)
        oldroles,newroles=before["compute_roles"],after["compute_roles"]
        m.require(type(oldroles) is list and type(newroles) is list and newroles[:len(oldroles)]==oldroles,"all old compute roles retained")
        if compute:m.require(len(newroles)==len(oldroles)+1 and newroles[-1].get("scope")==row["scope"] and newroles[-1].get("compute_CPU_reservation")==compute,"one new primary charge")
        else:m.require(newroles==oldroles,"source-only fee creates no compute role")
        for key in before:
            if key not in {"previous","created_epoch","scopes","compute_roles",*counters}:m.require(after[key]==before[key],"historical field retained "+key)
        current=prior
    raise ValueError("whole current ledger must reach published source ledger in64 appends")
def _quote(spec,pub):
    q=m.linked(spec["quote"]);m.closed(q,QUOTE_KEYS,"prospective initial quote")
    m.require(q["schema"]=="r201_prospective_qualification_quote_v1" and q["status"]=="REVIEWED_PROSPECTIVE_R201_QUALIFICATION_QUOTE","reviewed prospective quote, not measured production price")
    _same(q,spec,("purpose","nonce","role","source_publication","source_map_sha256","case_sha256"))
    m.require(type(q["components"]) is dict and set(q["components"])==COMPONENTS,"all nine complete lifecycle components")
    for c in q["components"].values():
        m.require(type(c) is dict and c.get("covered") is True,"complete prospective component")
        for key in ("CPU_upper_seconds","wall_upper_seconds","compute_CPU_upper_seconds","administrative_CPU_upper_seconds","remote_unknown_CPU_reservation"):m.integer(c.get(key),key,0)
        m.require(c["CPU_upper_seconds"]==c["compute_CPU_upper_seconds"]+c["administrative_CPU_upper_seconds"]+c["remote_unknown_CPU_reservation"],"disjoint component fees")
    for key in ("whole_CPU_seconds","whole_wall_seconds","compute_CPU_reservation","administrative_CPU_reservation","owner_CPU_seconds","child_CPU_seconds","owner_wall_seconds","memory_MiB","reserved_filesystem_bytes","mandatory_headroom_bytes"):m.integer(q[key],key,1)
    m.integer(q["remote_unknown_CPU_reservation"],"remote uncertainty",0)
    m.integer(q["return_proof_reservation_bytes"],"useful proof reserve",16*1024**2,64*1024**2)
    m.integer(q["proof_storage_reservation_bytes"],"physical proof reserve",64*1024**2)
    m.require(q["reserved_filesystem_bytes"]>=q["proof_storage_reservation_bytes"]+64*1024**2
      and q["components"]["optimizer"]["compute_CPU_upper_seconds"]==0,"complete return/proof storage and zero optimizer")
    for part,total in (("compute_CPU_upper_seconds","compute_CPU_reservation"),("administrative_CPU_upper_seconds","administrative_CPU_reservation"),("remote_unknown_CPU_reservation","remote_unknown_CPU_reservation")):
        m.require(sum(c[part] for c in q["components"].values())<=q[total],"whole channel covers all components")
    m.require(q["whole_CPU_seconds"]>=q["compute_CPU_reservation"]+q["administrative_CPU_reservation"]+q["remote_unknown_CPU_reservation"]
      and sum(c["wall_upper_seconds"] for c in q["components"].values())<=q["whole_wall_seconds"]
      and q["child_CPU_seconds"]<=q["owner_CPU_seconds"]<=q["compute_CPU_reservation"]
      and q["owner_wall_seconds"]<=q["whole_wall_seconds"] and q["components"]["startup"]["wall_upper_seconds"]>=120,"complete nested initial bounds")
    review=m.linked(q["independent_review"])
    # The quote excludes its own review pin to keep the descriptor graph acyclic.
    m.require(review.get("status")=="PASS_REVIEWED_R201_PROSPECTIVE_QUALIFICATION_QUOTE"
      and review.get("quote_core_sha256")==m.digest({k:v for k,v in q.items() if k!="independent_review"}),"independent prospective core review")
    s=m.linked(spec["scope"]);ledger=m.linked(spec["ledger"])
    m.require(s.get("schema")=="r201_initial_reference_qualification_runtime_scope_v1" and s.get("status")=="ROOT_FUNDED_INITIAL_REFERENCE_QUALIFICATION_ONLY","new actual initial compute purpose, never source448")
    _same(s,spec,("purpose","nonce","role","quote","source_publication","source_map_sha256"))
    m.require(s.get("remote_namespace")==spec["root"] and s.get("target_input_manifest") is None
      and "input_manifest" not in s and "target_paths" not in s
      and type(s.get("maximum_jobs")) is int and s["maximum_jobs"]==1
      and s.get("automatic_retry") is False and s.get("requeue") is False
      and type(s.get("optimizer_invocations")) is int and s["optimizer_invocations"]==0
      and type(s.get("new_posterior_fits")) is int and s["new_posterior_fits"]==0,"synthetic-only one job, no targets or optimization")
    m.require(type(s.get("compute_CPU_reservation")) is int and s["compute_CPU_reservation"]==q["compute_CPU_reservation"]
      and type(s.get("new_administrative_CPU_reservation")) is int
      and s["new_administrative_CPU_reservation"]>=q["administrative_CPU_reservation"]+q["remote_unknown_CPU_reservation"]
      and s.get("issued_epoch")<=spec["issued_epoch"] and s.get("expires_epoch")==spec["expires_epoch"],"separate fully funded fixed window")
    rows=[x for x in ledger.get("scopes",[]) if x.get("scope")==spec["scope"]]
    roles=[x for x in ledger.get("compute_roles",[]) if x.get("scope")==spec["scope"]]
    m.require(len(rows)==len(roles)==1 and rows[0].get("administrative_CPU_reservation")==s["new_administrative_CPU_reservation"]
      and rows[0].get("compute_CPU_reservation")==roles[0].get("compute_CPU_reservation")==q["compute_CPU_reservation"],"one exact primary role and complete admin row")
    _lineage(spec["ledger"],pub["source_ledger"]);return q
def _acceptance(spec,name):
    value=m.linked(spec[name]);build=name=="build_acceptance"
    m.closed(value,BUILD_KEYS if build else DEPLOY_KEYS,"actual build/deployment acceptance")
    schema="r201_owned_native_build_acceptance_v1" if build else "r201_readonly_namespace_acceptance_v1"
    status="ACCEPTED_SOURCE_BUILD_ONLY_NOT_RUNTIME" if build else "ACCEPTED_READONLY_NAMESPACE_ONLY_NOT_RUNTIME"
    candidate_status="CANDIDATE_SOURCE_BUILD_ONLY_AWAIT_H5" if build else "CANDIDATE_READONLY_NAMESPACE_ONLY_AWAIT_H5"
    m.require(value["schema"]==schema and value["status"]==status and value["source_map_sha256"]==spec["source_map_sha256"],"applicable source/build acceptance only")
    guard,candidate=legacy._healthy(value["actual_accept_guard"],5)
    m.integer(value["command_pid"],"acceptance command PID",1);m.integer(value["command_birth_ticks"],"acceptance command birth",1)
    m.require(guard.get("session_id")==candidate.get("command_pid")==value["command_pid"]
      and guard.get("leader_start_ticks")==candidate.get("command_birth_ticks")==value["command_birth_ticks"],"actual H5 stdout PID and birth")
    m.require(candidate.get("status")==candidate_status and dict(candidate,status=status,actual_accept_guard=value["actual_accept_guard"])==value,"actual guarded accepted source candidate")
    result=m.linked(value["result"]);review=m.linked(value["independent_review"]);account=m.linked(value["accounting"])
    expected="PASS_REVIEWED_R201_NATIVE_BUILD" if build else "PASS_REVIEWED_R201_READONLY_NAMESPACE"
    m.require(review.get("status")==expected and review.get("result")==value["result"] and review.get("accounting")==value["accounting"]
      and result.get("source_map_sha256")==spec["source_map_sha256"] and type(result.get("job_id")) is str
      and result.get("job_id")==account.get("job_id") and account.get("terminal") is True and account.get("complete") is True
      and account.get("primary_charge_counted_once") is True,"actual independently accepted complete build/deployment lifecycle")
    if not build:m.require(value["build_acceptance"]==spec["build_acceptance"],"deployment of this exact accepted build")
    return value
def _launch(spec,build,deploy):
    value=m.linked(spec["owner_launch"]);m.closed(value,LAUNCH_KEYS,"closed initial launch")
    m.require(value["schema"]=="r201_owned_reference_launch_v1","new reference launch")
    _same(value,spec);m.require(value["bootstrap"]==spec["source_pins"]["native_python/python_bootstrap.py"]
      and value["native_build_acceptance"]==spec["build_acceptance"] and value["native_deployment_acceptance"]==spec["deployment_acceptance"]
      and value["native_library"]==build["native_library"] and value["native_build_manifest"]==build["native_build_manifest"]
      and value["native_abi"]==build["native_abi"] and value["traced_guard"]["sha256"]==TRACE_SHA,"fixed new bootstrap/build and unchanged tracer")
    for name in ("native_executable","native_library","native_build_manifest","native_abi","traced_guard"):m.descriptor(value[name])
    baseline=value["baseline_files"];m.require(type(baseline) is list and 1<=len(baseline)<=256 and baseline==deploy["baseline_files"],"exact complete accepted runtime closure")
    for p in baseline:m.descriptor(p)
    m.require(value["native_executable"] in baseline and value["native_library"] in baseline and value["traced_guard"] in baseline,"Python ELF/native/tracer baseline membership")
    for name in ("stdout_path","stderr_path","owned_tree_path","owned_guard_path","output_root"):
        m.require(m.absolute(value[name]).is_relative_to(m.absolute(spec["root"])),"new private output")
    env=value["environment"];m.require(type(env) is dict and env.get("TZ")=="UTC" and env.get("SLURM_JOB_ID")==spec["job_id"]
      and env.get("SLURMD_NODENAME")==spec["node"] and env.get("SLURM_CPUS_PER_TASK")=="1"
      and all(env.get(k)=="1" for k in THREADS) and "LD_PRELOAD" not in env and "PYTHONPATH" not in env,"closed one-thread actual job launch")
    return value
def _capture(pin,spec_pin,spec,now,schema,status):
    _,value=legacy._healthy(pin,8,dict(spec,_spec_path=spec_pin["path"]),status,now)
    m.closed(value,CAPTURE_KEYS,"actual guarded current capture")
    m.require(value["schema"]==schema,"capture schema");m.descriptor(value["witness"]);return value
def _readonly_paths(readonly,required):
    m.require(type(readonly) is list and len(readonly)<=512,"bounded readonly coverage")
    paths=set()
    for row in readonly:
        m.closed(row,{"path","mount_readonly","superblock_readonly"},"actual readonly row");m.absolute(row["path"])
        m.require(row["path"] not in paths and row["mount_readonly"] is True and row["superblock_readonly"] is True,"actual immutable backing, not writable alias bind");paths.add(row["path"])
    m.require(required<=paths,"every code/native/Python baseline has actual readonly backing")
def _observations(spec_pin,bundle_pin,now):
    spec=m.linked(spec_pin);pub=_inspect(spec,now);q=_quote(spec,pub)
    build=_acceptance(spec,"build_acceptance");deploy=_acceptance(spec,"deployment_acceptance");launch=_launch(spec,build,deploy)
    bundle=m.linked(bundle_pin);m.closed(bundle,BUNDLE_KEYS,"closed actual initial observation bundle")
    m.require(bundle["schema"]=="r201_qualification_observation_bundle_v1" and bundle["spec"]==spec_pin
      and bundle["source_publication"]==spec["source_publication"] and bundle["source_pins"]==spec["source_pins"],"same current capture purpose")
    source=_capture(bundle["source_observation_guard"],spec_pin,spec,now,"r201_qualification_source_capture_v1","CAPTURED_R201_QUALIFICATION_SOURCE_READONLY_METADATA")
    witness=m.linked(source["witness"]);m.closed(witness,SOURCE_WITNESS_KEYS,"pre-READY source and readonly witness")
    m.require(witness["schema"]=="r201_qualification_source_readonly_witness_v1","source witness schema")
    _same(witness,spec,(*IDENTITY,"uid","owner","root","case_sha256","source_map_sha256","source_publication","source_pins","scope","quote","build_acceptance","deployment_acceptance"));_fresh(witness,"observed_epoch",now,90)
    files=witness["files"];m.require(type(files) is list and len(files)==len(spec["source_pins"]),"complete actual source inventory");captured={}
    for row in files:
        m.closed(row,{"relative","path","sha256","bytes","uid","mode","nlink"},"actual source row")
        m.integer(row["bytes"],"source bytes",1,1024**2);m.integer(row["mode"],"source mode",0,0o177777)
        m.require(row["relative"] not in captured and type(row["uid"]) is int and row["uid"]==spec["uid"]
          and type(row["nlink"]) is int and row["nlink"]==1 and row["mode"]&0o022==0,"actual private single-link source")
        captured[row["relative"]]={"path":row["path"],"sha256":row["sha256"]}
    m.require(captured==spec["source_pins"],"actual installed full source map")
    required={p["path"] for p in spec["source_pins"].values()}|{p["path"] for p in launch["baseline_files"]}|{build["native_library"]["path"]}
    _readonly_paths(witness["readonly_files"],required)
    physical=_capture(bundle["physical_observation_guard"],spec_pin,spec,now,"r201_qualification_physical_capture_v1","CAPTURED_R201_QUALIFICATION_PHYSICAL_METADATA")
    m.require(physical["witness"]==bundle["physical_admission"],"actual physical capture pin")
    physical=m.linked(bundle["physical_admission"]);m.closed(physical,PHYSICAL_KEYS,"actual physical witness")
    m.require(physical["schema"]=="r200_actual_physical_core_witness_v1","actual physical schema");_same(physical,spec,("job_id","node","owner","affinity","scope"));_fresh(physical,"observed_epoch",now,90)
    siblings=physical["online_thread_siblings"];effective=physical["effective_job_cpus"]
    m.require(type(siblings) is list and type(effective) is list and siblings
      and all(type(x) is int and x>=0 for x in siblings+effective) and len(set(siblings))==len(siblings)
      and len(set(effective))==len(effective) and spec["affinity"][0] in siblings and set(siblings)<=set(effective),"all physical-core SMT siblings actually owned")
    for key in ("cgroup_memory_limit_bytes","filesystem_available_bytes","filesystem_mandatory_headroom_bytes"):m.integer(physical[key],key,1)
    m.require(physical["cgroup_memory_limit_bytes"]<=q["memory_MiB"]*1024**2
      and physical["filesystem_mandatory_headroom_bytes"]>=q["mandatory_headroom_bytes"]
      and physical["filesystem_available_bytes"]>=q["reserved_filesystem_bytes"]+physical["filesystem_mandatory_headroom_bytes"],"actual prepaid memory/full storage plus headroom")
    return spec,bundle
def source_physical(spec_pin,bundle_pin,output_path,now=None):
    now=_now(now);spec,bundle=_observations(spec_pin,bundle_pin,now)
    m.require(bundle["owner_ready"] is None and bundle["ready_observation_guard"] is None,"first source/physical phase, not release")
    result=dict(schema="r201_qualification_source_review_v1",status="PASS_REVIEWED_R201_QUALIFICATION_SOURCE_PHYSICAL",
      spec=spec_pin,**{k:spec[k] for k in IDENTITY},source_pins=spec["source_pins"],source_map_sha256=spec["source_map_sha256"],
      case_sha256=spec["case_sha256"],source_publication=spec["source_publication"],controller_source=spec["source_publication"],
      physical_admission=bundle["physical_admission"],scope=spec["scope"],ledger=spec["ledger"],quote=spec["quote"],
      build_acceptance=spec["build_acceptance"],deployment_acceptance=spec["deployment_acceptance"],
      independent_program=m.pin_file(Path(__file__)),issued_epoch=now,expires_epoch=min(spec["expires_epoch"],now+60),runtime_admitted=False)
    return m.write_new(m.absolute(str(output_path)),result)
def owner_release(spec_pin,source_review_pin,bundle_pin,output_path,now=None):
    now=_now(now);spec,bundle=_observations(spec_pin,bundle_pin,now);review=m.linked(source_review_pin)
    _same(review,spec)
    m.require(review.get("schema")=="r201_qualification_source_review_v1" and review.get("status")=="PASS_REVIEWED_R201_QUALIFICATION_SOURCE_PHYSICAL"
      and review.get("spec")==spec_pin and review.get("source_pins")==spec["source_pins"]
      and review.get("source_map_sha256")==spec["source_map_sha256"] and review.get("case_sha256")==spec["case_sha256"]
      and review.get("physical_admission")==bundle["physical_admission"] and review.get("runtime_admitted") is False
      and review.get("source_publication")==review.get("controller_source")==spec["source_publication"]
      and review.get("independent_program")==m.pin_file(Path(__file__))
      and review.get("issued_epoch")<=now<review.get("expires_epoch"),"same complete current independent first phase")
    _same(review,spec,FUNDING)
    ready_capture=_capture(bundle["ready_observation_guard"],spec_pin,spec,now,"r201_qualification_ready_capture_v1","CAPTURED_R201_QUALIFICATION_READY_METADATA")
    m.require(ready_capture["witness"]==bundle["owner_ready"],"actual fresh READY capture")
    ready=m.linked(bundle["owner_ready"]);m.closed(ready,READY_KEYS,"actual initial-only READY")
    m.require(ready["schema"]=="r201_qualification_ready_v1" and ready["status"]=="READY_R201_INITIAL_QUALIFICATION_AWAIT_ROOT_NO_PAYLOAD","initial-only READY schema")
    _same(ready,spec,(*IDENTITY,"uid","owner","root","case_sha256","source_map_sha256","source_publication",*FUNDING,"resource_lock_fd","resource_lock_path"))
    m.require(ready["physical_admission"]==bundle["physical_admission"],"same physical witness");_fresh(ready,"created_epoch",now,120);m.finite(ready["expires_epoch"],"READY expiry")
    m.require(ready["created_epoch"]<ready["expires_epoch"]<=min(spec["expires_epoch"],ready["created_epoch"]+120) and now<ready["expires_epoch"],"fixed one READY interval")
    result=dict(schema="r201_qualification_owner_release_review_v1",status="PASS_REVIEWED_R201_QUALIFICATION_OWNER_RELEASE",
      spec=spec_pin,source_review=source_review_pin,**{k:spec[k] for k in IDENTITY},source_map_sha256=spec["source_map_sha256"],
      case_sha256=spec["case_sha256"],owner_ready=bundle["owner_ready"],physical_admission=bundle["physical_admission"],
      **{k:spec[k] for k in FUNDING},independent_program=m.pin_file(Path(__file__)),issued_epoch=now,
      expires_epoch=min(spec["expires_epoch"],ready["expires_epoch"],review["expires_epoch"]),runtime_admitted=False)
    return m.write_new(m.absolute(str(output_path)),result)
