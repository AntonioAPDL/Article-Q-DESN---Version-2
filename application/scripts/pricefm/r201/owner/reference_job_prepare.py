"""Closed metadata-only preparation for two reference launch roles; never submits."""
from __future__ import annotations
import copy,hashlib,importlib.util,json,os,re,shlex,stat,time
from pathlib import Path
_cp=Path(__file__).absolute().with_name("reference_common.py")
# Authenticate one captured fixed-source byte string BEFORE interpretation.
_COMMON_SHA="e9e35192e82bf0669cdbce20614cfc68e195ecd3c4c2655d479b8267544fc870"
if any(v.is_symlink() for v in (_cp,*_cp.parents)):
    raise ValueError("fixed common source requires physical nonsymlink path")
_cfd=os.open(_cp,os.O_RDONLY|os.O_NONBLOCK|os.O_NOFOLLOW)
try:
    _cbefore=os.fstat(_cfd)
    if not (stat.S_ISREG(_cbefore.st_mode) and _cbefore.st_nlink==1
            and _cbefore.st_uid==os.getuid() and 0<_cbefore.st_size<=1024**2):
        raise ValueError("bounded owned regular single-link common source")
    _craw=b""
    while len(_craw)<=1024**2:
        _cblock=os.read(_cfd,min(65536,1024**2+1-len(_craw)))
        if not _cblock:break
        _craw+=_cblock
    _cafter=os.fstat(_cfd)
finally:
    os.close(_cfd)
_cstate=lambda v:(v.st_dev,v.st_ino,v.st_size,v.st_mtime_ns,v.st_ctime_ns,
                  v.st_mode,v.st_uid,v.st_nlink)
if (_cstate(_cbefore)!=_cstate(_cafter) or _cstate(_cafter)!=_cstate(_cp.lstat())
        or len(_craw)!=_cbefore.st_size or hashlib.sha256(_craw).hexdigest()!=_COMMON_SHA):
    raise ValueError("exact captured common source SHA and physical lifetime")
_cs=importlib.util.spec_from_file_location("_r201_prepare_common",_cp)
c=importlib.util.module_from_spec(_cs);exec(compile(_craw,str(_cp),"exec"),c.__dict__)
m=c.m
COMMON={"schema","purpose","nonce","role","node","root","source_publication","source_pins",
 "owner_launch_template","resource_lock_path","ready_path","physical_path","source_witness_path",
 "canonical_ready_path","canonical_physical_path","canonical_source_witness_path","release_path",
 "spec_path","owner_launch_path","acknowledgement_path","attempt_claim_path","startup_python",
 "scope","ledger","issued_epoch","expires_epoch"}
INITIAL_EXTRA={"case","quote","build_acceptance","deployment_acceptance"}
PRODUCTION_EXTRA={"reference_request","input_manifest","input_provenance","price","runtime_qualification",
 "scientific_source","scientific_sources","metadata_namespace"}
BOOT_COMMON={"schema","status","template","purpose","nonce","role","node","scope","ledger",
 "source_publication","issued_epoch","expires_epoch","maximum_calls","maximum_jobs",
 "optimizer_invocations","scientific_target_data_read"}
def validate_template(t,*,on_compute=False):
    m.require(type(t) is dict and t.get("role") in c.ROLES,"closed reference template role")
    initial=t["role"]==c.INITIAL
    m.closed(t,COMMON|(INITIAL_EXTRA if initial else PRODUCTION_EXTRA),"closed reference startup template")
    m.require(t["schema"]=="r201_reference_job_template_v1" and t["node"]=="node-13"
      and type(t["purpose"]) is str and re.fullmatch("[A-Za-z0-9_]{1,96}",t["purpose"])
      and type(t["nonce"]) is str and re.fullmatch("[0-9a-f]{32}",t["nonce"]),"closed node/purpose/nonce")
    for key in ("issued_epoch","expires_epoch"):m.finite(t[key],key)
    m.require(0<t["expires_epoch"]-t["issued_epoch"]<=28800,"new finite scope; no clock renewal")
    scope=m.linked(t["scope"])
    expected="r201_initial_reference_qualification_runtime_scope_v1" if initial else "r200_compute_runtime_scope_v1"
    m.require(scope.get("schema")==expected and type(scope.get("compute_CPU_reservation")) is int
      and scope["compute_CPU_reservation"]>0 and scope.get("purpose")==t["purpose"]
      and scope.get("nonce")==t["nonce"] and scope.get("role")==t["role"]
      and scope.get("remote_namespace")==t["root"] and scope.get("automatic_retry") is False
      and scope.get("requeue") is False and type(scope.get("maximum_jobs")) is int
      and scope["maximum_jobs"]==1 and scope.get("expires_epoch")==t["expires_epoch"],
      "actual separately funded role scope; source448 is never a compute grant")
    publication=m.linked(t["source_publication"])
    m.require(publication.get("schema")=="r200_source_publication_v1"
      and publication.get("status")=="PASS_PUBLISHED_R200_SOURCE_PREPARATION"
      and publication.get("remote_readback")==publication.get("commit")
      and re.fullmatch("[0-9a-f]{40}",publication.get("commit",""))
      and publication.get("branch","").startswith("work/pricefm-"),"actual exact source publication")
    pins=t["source_pins"]
    m.require(type(pins) is dict and set(pins)==set(publication.get("files",{})),"entire published current map")
    for name,pin in pins.items():
        m.require(type(name) is str and not Path(name).is_absolute() and ".." not in Path(name).parts,
                  "closed relative source member")
        m.descriptor(pin);m.require(pin["sha256"]==publication["files"][name],"published source hash")
        if on_compute:m.source_bytes(pin)
    for name in ("owner/reference_common.py","owner/reference_job_prepare.py","owner/reference_startup_worker.py"):
        local=c.ROOT/name
        m.require(name in pins and (pins[name]["path"]==str(local) if on_compute
          else m.pin_file(local)["sha256"]==pins[name]["sha256"]),"exact local installed producer")
    if initial:
        case={"schema":"r200_analytic_reference_fixture_request_v1","sizes":[8,16,32],
          "families":["diagonal","rank_one","paired_ill_conditioned"],"optimizer_updates":0,"new_posterior_fits":0}
        m.require(t["case"]==case and type(t["case"]["optimizer_updates"]) is int
          and type(t["case"]["new_posterior_fits"]) is int,"fixed9 analytic cases; no target grant")
        price=m.linked(t["quote"])
        m.require(scope.get("status")=="ROOT_FUNDED_INITIAL_REFERENCE_QUALIFICATION_ONLY"
          and scope.get("target_input_manifest") is None and scope.get("quote")==t["quote"]
          and scope.get("source_publication")==t["source_publication"]
          and type(scope.get("optimizer_invocations")) is int and scope["optimizer_invocations"]==0
          and type(scope.get("new_posterior_fits")) is int and scope["new_posterior_fits"]==0,
          "initial-only funded scope has no target/pilot privilege")
        m.require(price.get("schema")=="r201_prospective_qualification_quote_v1"
          and price.get("status")=="REVIEWED_PROSPECTIVE_R201_QUALIFICATION_QUOTE",
          "new prospective quote, never inherited production measurement")
    else:
        case=m.linked(t["reference_request"]);price=m.linked(t["price"])
    ctx=dict(t,case=case,case_sha256=m.digest(case),source_map_sha256=m.digest(publication["files"]))
    for key in ("purpose","nonce","role"):m.require(price.get(key)==t[key],"same complete price "+key)
    m.require(price.get("case_sha256")==ctx["case_sha256"]
      and price.get("source_map_sha256")==ctx["source_map_sha256"],"price binds complete fixed case/source")
    if not initial:
        ctx.update(controller_source=t["source_publication"],role_request=t["reference_request"])
        boundary=c.load("owner/compute_boundary.py",pins,local_metadata=not on_compute)
        price=boundary._price_and_funding(ctx)
        qualified=boundary._qualification(t["runtime_qualification"],ctx)
        result=m.linked(qualified["result"]);namespace=m.linked(t["metadata_namespace"])
        m.require(result.get("startup_python")==t["startup_python"]
          and result.get("canonical_metadata_namespace")==t["metadata_namespace"]
          and namespace.get("status")=="QUALIFIED_CANONICAL_METADATA_NAMESPACE"
          and namespace.get("source_publication")==t["source_publication"]
          and namespace.get("same_bytes_without_old_JSON_rewrite") is True,
          "production needs actual canonical control namespace qualification")
    launch=t["owner_launch_template"];m.closed(launch,c.LAUNCH_KEYS-{"job_id"},"acyclic launch template")
    m.require(launch["schema"]=="r201_owned_reference_launch_v1"
      and launch["bootstrap"]==pins["native_python/python_bootstrap.py"]
      and launch["native_executable"]==t["startup_python"],"fixed new Python bootstrap and actual ELF")
    for key in ("purpose","nonce","role","node"):m.require(launch[key]==t[key],"same launch "+key)
    m.require(launch["environment"].get("TZ")=="UTC"
      and all(launch["environment"].get(key)=="1" for key in c.THREAD_KEYS)
      and not any(key in launch["environment"] for key in
                  ("SLURM_JOB_ID","SLURMD_NODENAME","PYTHONPATH","LD_PRELOAD","PYTHONSTARTUP")),
      "acyclic fixed one-thread environment")
    root=m.absolute(t["root"])
    for key in ("ready_path","physical_path","source_witness_path","release_path",
                "acknowledgement_path","attempt_claim_path"):
        m.require(m.absolute(t[key]).is_relative_to(root),"fixed remote path "+key)
    for key in ("canonical_ready_path","canonical_physical_path","canonical_source_witness_path",
                "spec_path","owner_launch_path","resource_lock_path"):m.absolute(t[key])
    if initial:
        # Full pure metadata admission BEFORE a startup job can be rendered/spent.
        # No invented job/PID, peer PASS, runtime RO or scientific admission.
        funding=c.load("qualification/qualification_contract.py",pins,local_metadata=not on_compute)
        price=funding.validate_bootstrap_metadata(ctx,launch,pins)
    m.require(price["components"]["startup"]["wall_upper_seconds"]>=120,"complete120second READY price")
    for key in ("whole_wall_seconds","owner_CPU_seconds","child_CPU_seconds","owner_wall_seconds","memory_MiB"):
        m.integer(price.get(key),key,1,2**31-1)
    c.load("owner/reference_return.py",pins,local_metadata=not on_compute).plan(ctx,price)
    return ctx,price

def validate_bootstrap_authority(a,template_pin,t):
    extras=INITIAL_EXTRA-{"case"} if t["role"]==c.INITIAL else {"price","runtime_qualification"}
    m.closed(a,BOOT_COMMON|extras,"Root metadata-only bootstrap authority")
    m.require(a["schema"]=="r201_reference_metadata_bootstrap_authority_v1"
      and a["status"]=="ROOT_ADMITTED_R201_REFERENCE_METADATA_BOOTSTRAP_ONLY"
      and a["template"]==template_pin and type(a["maximum_calls"]) is int and a["maximum_calls"]==1
      and type(a["maximum_jobs"]) is int and a["maximum_jobs"]==1
      and type(a["optimizer_invocations"]) is int and a["optimizer_invocations"]==0
      and a["scientific_target_data_read"] is False,"one metadata startup, no compute authority")
    for key in ({"purpose","nonce","role","node","scope","ledger","source_publication"}|extras):
        m.require(a[key]==t[key],"same bootstrap "+key)
    for key in ("issued_epoch","expires_epoch"):m.finite(a[key],key)
    m.require(t["issued_epoch"]<=a["issued_epoch"]<a["expires_epoch"]<=t["expires_epoch"],"finite bootstrap interval")

def render_sbatch(template_pin,bootstrap_authority_pin,output_path):
    """Create ASCII source only; no job submission or authority mint."""
    t=m.linked(template_pin);ctx,price=validate_template(t)
    validate_bootstrap_authority(m.linked(bootstrap_authority_pin),template_pin,t)
    seconds=m.integer(price["whole_wall_seconds"],"Slurm whole wall",1,28800)
    wall="%02d:%02d:%02d"%(seconds//3600,(seconds%3600)//60,seconds%60)
    command=[t["startup_python"]["path"],"-I","-B",t["source_pins"]["owner/reference_startup_worker.py"]["path"],
      "--template",template_pin["path"],"--template-sha256",template_pin["sha256"],
      "--bootstrap-authority",bootstrap_authority_pin["path"],"--bootstrap-authority-sha256",bootstrap_authority_pin["sha256"]]
    rows=["#!/bin/bash","#SBATCH --account=128x24","#SBATCH --partition=128x24","#SBATCH --qos=normal",
      "#SBATCH --nodelist=node-13","#SBATCH --nodes=1","#SBATCH --ntasks=1","#SBATCH --cpus-per-task=1",
      "#SBATCH --hint=nomultithread","#SBATCH --mem="+str(price["memory_MiB"])+"M",
      "#SBATCH --time="+wall,"#SBATCH --no-requeue","#SBATCH --job-name="+t["purpose"],"set -eu","export TZ=UTC"]
    rows+=["export "+key+"=1" for key in c.THREAD_KEYS]
    rows+=["exec "+shlex.join(command),""]
    raw="\n".join(rows).encode("ascii");path=m.physical(output_path)
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,"wb") as f:f.write(raw);f.flush();os.fsync(f.fileno())
    return {"status":"RENDERED_ONLY_NOT_SUBMITTED_NOT_RUNTIME_AUTHORITY","script":m.pin_file(path),
            "template":template_pin,"jobs_submitted":0}

def build_spec(template_pin,ready_pin):
    """Bind actual current READY and produce no peer PASS or Root authority."""
    t=m.linked(template_pin);ctx,price=validate_template(t);r=m.linked(ready_pin);initial=t["role"]==c.INITIAL
    expected="r201_qualification_ready_v1" if initial else "r200_owned_ready_v1"
    status="READY_R201_INITIAL_QUALIFICATION_AWAIT_ROOT_NO_PAYLOAD" if initial else "READY_R200_OWNED_AWAIT_ROOT_RELEASE_NO_PAYLOAD"
    m.require(ready_pin["path"]==t["canonical_ready_path"] and r.get("schema")==expected
      and r.get("status")==status,"exact canonical READY")
    for key in ("purpose","nonce","role","node","root","source_publication","scope","ledger"):
        m.require(r[key]==t[key],"same current READY "+key)
    now=time.time()
    m.require(0<=now-r["created_epoch"]<120 and now<r["expires_epoch"]
      and r["resource_lock_path"]==t["resource_lock_path"] and r["case_sha256"]==ctx["case_sha256"]
      and r["source_map_sha256"]==ctx["source_map_sha256"],"fresh exact120second READY")
    witness=m.linked(r["physical_admission"])
    m.require(r["physical_admission"]["path"]==t["canonical_physical_path"]
      and witness["owner"]==r["owner"] and witness["job_id"]==r["job_id"]
      and witness["node"]==r["node"] and 0<=now-witness["observed_epoch"]<90,
      "fresh90second physical witness")
    launch=copy.deepcopy(t["owner_launch_template"]);launch["job_id"]=r["job_id"]
    launch["environment"].update(SLURM_JOB_ID=r["job_id"],SLURMD_NODENAME=r["node"])
    launchpin=m.write_new(t["owner_launch_path"],launch)
    spec={key:t[key] for key in ("purpose","nonce","role","root","source_publication","source_pins",
       "scope","ledger","acknowledgement_path","resource_lock_path","attempt_claim_path","expires_epoch")}
    spec.update(schema="r201_native_reference_qualification_spec_v1" if initial else "r200_owned_compute_spec_v1",
      job_id=r["job_id"],node=r["node"],uid=r["uid"],owner=r["owner"],affinity=witness["affinity"],
      case=ctx["case"],case_sha256=ctx["case_sha256"],source_map_sha256=ctx["source_map_sha256"],
      owner_launch=launchpin,resource_lock_fd=r["resource_lock_fd"],issued_epoch=now)
    if initial:
        for key in ("quote","build_acceptance","deployment_acceptance"):
            m.require(r[key]==t[key],"same READY "+key);spec[key]=t[key]
        checker=c.load("qualification/qualification_contract.py",t["source_pins"],local_metadata=True)
    else:
        for key in ("price","runtime_qualification","input_manifest","input_provenance","scientific_source","scientific_sources"):
            spec[key]=t[key]
        spec.update(reference_request=t["reference_request"],role_request=t["reference_request"],
          controller_source=t["source_publication"],runtime_owner=dict(job_id=r["job_id"],node=r["node"],uid=r["uid"],
          parent_pid=r["owner"]["pid"],parent_birth_ticks=r["owner"]["start_ticks"],
          resource_lock_fd=r["resource_lock_fd"],expires_epoch=t["expires_epoch"]))
        checker=c.load("owner/pilot_independent_peer.py",t["source_pins"],local_metadata=True)
    checker.inspect_spec_metadata(spec)  # Metadata consistency only, never admission.
    return {"status":"PREPARED_REFERENCE_SPEC_AWAIT_TWO_ACTUAL_PEERS_AND_ROOT_AUTHORITY",
      "spec":m.write_new(t["spec_path"],spec),"owner_launch":launchpin,"ready":ready_pin,"grants_runtime":False}
