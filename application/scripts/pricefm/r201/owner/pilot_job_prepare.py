"""Render-only pilot startup/job metadata; no submit, peer PASS or authority mint.
Canonical control metadata deployment and new runtime/price qualification are
mandatory. The source-preparation scope cannot satisfy the runtime scope gate.
"""
from __future__ import annotations
import copy, hashlib, importlib.util, math, os, re, shlex, stat, time
from pathlib import Path
_MSHA="6593a6bbb617375029bee0c692e510cd5621662eaf9fab46445eab433ff0762b"
_mp=Path(__file__).absolute().with_name("metadata.py")
_raw=_mp.read_bytes()
if _mp.is_symlink() or hashlib.sha256(_raw).hexdigest()!=_MSHA: raise ValueError("exact fixed metadata source")
_ms=importlib.util.spec_from_file_location("_r200_job_metadata",_mp)
m=importlib.util.module_from_spec(_ms);exec(compile(_raw,str(_mp),"exec"),m.__dict__)
TEMPLATE_KEYS={"schema","purpose","nonce","role","node","root","source_publication","source_pins",
 "scientific_source","scientific_sources","io_request","input_manifest","input_provenance",
 "price","runtime_qualification","scope","ledger","owner_launch_template","resource_lock_path",
 "ready_path","physical_path","canonical_ready_path","canonical_physical_path","release_path",
 "spec_path","owner_launch_path","acknowledgement_path","attempt_claim_path",
 "startup_python","metadata_namespace","issued_epoch","expires_epoch"}
BOOT_KEYS={"schema","status","template","purpose","nonce","role","node","scope","ledger","price",
 "runtime_qualification","source_publication","issued_epoch","expires_epoch","maximum_calls",
 "maximum_jobs","optimizer_invocations","scientific_target_data_read"}
LAUNCH_KEYS={"schema","purpose","nonce","role","node","bootstrap","native_executable","traced_guard",
 "baseline_files","environment","bootstrap_exec_allowlist","stdout_path","stderr_path",
 "owned_tree_path","owned_guard_path","output_root"}

def _load(pin,name,sibling):
    m.require(pin["path"]==str(Path(__file__).absolute().with_name(sibling)),"fixed sibling source")
    raw=m.source_bytes(pin);s=importlib.util.spec_from_file_location(name,pin["path"])
    module=importlib.util.module_from_spec(s);exec(compile(raw,pin["path"],"exec"),module.__dict__)
    return module

def validate_template(template, *, on_compute=False):
    m.closed(template,TEMPLATE_KEYS,"closed new startup template")
    t=template
    m.require(t["schema"]=="r200_pilot_job_template_v1" and t["role"]=="NO3_AL300_PILOT"
              and t["node"]=="node-13" and re.fullmatch("[A-Za-z0-9_]{1,96}",t["purpose"] or "")
              and re.fullmatch("[0-9a-f]{32}",t["nonce"] or ""),"fixed pilot/node/purpose")
    for key in ("issued_epoch","expires_epoch"):m.finite(t[key],key)
    m.require(0<t["expires_epoch"]-t["issued_epoch"]<=28800,"finite new at-most-eight-hour scope")
    # Reject source392 before looking for any purported runtime or price PASS.
    scope=m.linked(t["scope"])
    m.require(scope.get("schema")=="r200_compute_runtime_scope_v1"
              and type(scope.get("compute_CPU_reservation")) is int
              and scope["compute_CPU_reservation"]>0,"actual funded runtime scope, never source preparation")
    publication=m.linked(t["source_publication"])
    m.require(publication.get("schema")=="r200_source_publication_v1"
              and publication.get("status")=="PASS_PUBLISHED_R200_SOURCE_PREPARATION"
              and publication.get("remote_readback")==publication.get("commit")
              and re.fullmatch("[0-9a-f]{40}",publication.get("commit",""))
              and publication.get("branch","").startswith("work/pricefm-"),"actual new source publication")
    pins=t["source_pins"];m.require(type(pins) is dict and set(pins)==set(publication.get("files",{})),
                                   "entire installed source map")
    for name,pin in pins.items():
        m.require(not Path(name).is_absolute() and ".." not in Path(name).parts
                  and pin["sha256"]==publication["files"][name],"published exact source member")
        if on_compute:m.source_bytes(pin)
    for name in ("owner/pilot_job_prepare.py","owner/pilot_startup_worker.py"):
        local=Path(__file__).absolute().with_name(Path(name).name)
        if on_compute:m.require(pins[name]["path"]==str(local),"actual installed startup sibling")
        else:m.require(m.pin_file(local)["sha256"]==pins[name]["sha256"],"same published local metadata interface")
    def code_pin(name):
        remote=pins["owner/"+name]
        return remote if on_compute else dict(path=str(Path(__file__).absolute().with_name(name)),sha256=remote["sha256"])
    boundary=_load(code_pin("compute_boundary.py"),"_r200_prepare_boundary","compute_boundary.py")
    owner=_load(code_pin("pilot_compute_owner.py"),"_r200_prepare_owner","pilot_compute_owner.py")
    dispatch=_load(code_pin("pilot_owner_dispatch.py"),"_r200_prepare_dispatch","pilot_owner_dispatch.py")
    io=m.linked(t["io_request"])
    dispatch.exact(io.get("case"),dispatch.CASE,"exact pilot case before rendering")
    m.require("runtime_owner" not in io and all(io.get(k)==t[k] for k in ("purpose","nonce","role","scientific_source")),
              "precomputed acyclic I/O request with no PID fields")
    m.require(io.get("controller_source")==t["source_publication"],"distinct current controller publication")
    m.closed(t["owner_launch_template"],LAUNCH_KEYS,"job-independent owner launch")
    launch=t["owner_launch_template"]
    for key in ("purpose","nonce","role","node"):m.require(launch[key]==t[key],"same launch "+key)
    m.require(launch["schema"]=="r200_owned_pilot_launch_v1"
              and launch["bootstrap"]==pins["pilot_io/pilot_bootstrap.R"]
              and io.get("output_root")==launch["output_root"],"exact bootstrap and I/O output")
    root=m.absolute(t["root"])
    remote_fields=("ready_path","physical_path","release_path","acknowledgement_path","attempt_claim_path")
    for key in remote_fields:
        m.require(m.absolute(t[key]).is_relative_to(root),"fixed new remote path "+key)
    for key in ("canonical_ready_path","canonical_physical_path","spec_path","owner_launch_path",
                "resource_lock_path"):m.absolute(t[key])
    ctx=dict(t,case=io["case"],case_sha256=m.digest(io["case"]),
             source_map_sha256=m.digest(publication["files"]),
             controller_source=t["source_publication"],role_request=t["io_request"])
    price=boundary._price_and_funding(ctx)
    qualification=boundary._qualification(t["runtime_qualification"],ctx)
    result=m.linked(qualification["result"])
    m.require(result.get("startup_python")==t["startup_python"]
              and result.get("canonical_metadata_namespace")==t["metadata_namespace"],
              "new qualification covers this Python and canonical metadata deployment")
    namespace=m.linked(t["metadata_namespace"])
    m.require(namespace.get("schema")=="r200_canonical_metadata_namespace_v1"
              and namespace.get("status")=="QUALIFIED_CANONICAL_METADATA_NAMESPACE"
              and namespace.get("source_publication")==t["source_publication"]
              and namespace.get("same_bytes_without_old_JSON_rewrite") is True,
              "new canonical metadata namespace qualification, no old deployment inheritance")
    roots=namespace.get("canonical_roots")
    m.require(type(roots) is list and roots,"explicit canonical control roots")
    roots=[m.absolute(x) for x in roots]
    for key in ("canonical_ready_path","canonical_physical_path","spec_path","owner_launch_path"):
        m.require(any(m.absolute(t[key]).is_relative_to(p) for p in roots),"canonical qualified control path "+key)
    m.require(scope.get("resource_lock_path")==t["resource_lock_path"]
              and price["components"]["startup"]["wall_upper_seconds"]>=120,
              "pre-funded global permit path and complete 120-second startup price")
    m.require(launch["environment"].get("TZ")=="UTC"
              and all(launch["environment"].get(k)=="1" for k in boundary.THREAD_KEYS)
              and "SLURM_JOB_ID" not in launch["environment"]
              and "SLURMD_NODENAME" not in launch["environment"]
              and "LD_PRELOAD" not in launch["environment"]
              and "PYTHONPATH" not in launch["environment"],"qualified acyclic one-thread environment")
    return ctx,price,boundary,owner

def render_sbatch(template_pin,bootstrap_authority_pin,output_path):
    """Create only an ASCII script. Does not submit, claim or grant anything."""
    t=m.linked(template_pin);ctx,price,_,_=validate_template(t)
    a=m.linked(bootstrap_authority_pin);validate_bootstrap_authority(a,template_pin,t)
    seconds=price["whole_wall_seconds"];m.integer(seconds,"Slurm whole wall",1,28800)
    wall="%02d:%02d:%02d"%(seconds//3600,(seconds%3600)//60,seconds%60)
    worker=t["source_pins"]["owner/pilot_startup_worker.py"]["path"]
    command=[t["startup_python"]["path"],"-I","-B",worker,"--template",template_pin["path"],
      "--template-sha256",template_pin["sha256"],"--bootstrap-authority",bootstrap_authority_pin["path"],
      "--bootstrap-authority-sha256",bootstrap_authority_pin["sha256"]]
    rows=["#!/bin/bash","#SBATCH --account=128x24","#SBATCH --partition=128x24","#SBATCH --qos=normal",
      "#SBATCH --nodelist=node-13","#SBATCH --nodes=1","#SBATCH --ntasks=1","#SBATCH --cpus-per-task=1",
      "#SBATCH --hint=nomultithread","#SBATCH --mem="+str(price["memory_MiB"])+"M",
      "#SBATCH --time="+wall,"#SBATCH --no-requeue","#SBATCH --job-name="+t["purpose"],
      "set -eu","export TZ=UTC"]
    rows+=["export "+key+"=1" for key in ("OPENBLAS_NUM_THREADS","OMP_NUM_THREADS","MKL_NUM_THREADS",
                                        "VECLIB_MAXIMUM_THREADS","NUMEXPR_NUM_THREADS","BLIS_NUM_THREADS")]
    rows+=["exec "+shlex.join(command),""]
    path=m.physical(output_path);raw="\n".join(rows).encode("ascii")
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,"wb") as f:f.write(raw);f.flush();os.fsync(f.fileno())
    return dict(status="RENDERED_ONLY_NOT_SUBMITTED_NOT_RUNTIME_AUTHORITY",
      script=dict(path=str(path),sha256=hashlib.sha256(raw).hexdigest()),template=template_pin,
      bootstrap_authority=bootstrap_authority_pin,jobs_submitted=0)

def validate_bootstrap_authority(a,template_pin,t):
    m.closed(a,BOOT_KEYS,"Root metadata-only bootstrap authority")
    m.require(a["schema"]=="r200_metadata_bootstrap_authority_v1"
              and a["status"]=="ROOT_ADMITTED_R200_METADATA_BOOTSTRAP_ONLY"
              and a["template"]==template_pin and type(a["maximum_jobs"]) is int and a["maximum_jobs"]==1
              and type(a["maximum_calls"]) is int and a["maximum_calls"]==1
              and type(a["optimizer_invocations"]) is int and a["optimizer_invocations"]==0
              and a["scientific_target_data_read"] is False,"one metadata bootstrap only")
    for key in ("purpose","nonce","role","node","scope","ledger","price","runtime_qualification","source_publication"):
        m.require(a[key]==t[key],"same bootstrap "+key)
    m.require(t["issued_epoch"]<=a["issued_epoch"]<a["expires_epoch"]<=t["expires_epoch"],"fixed bootstrap interval")

def build_spec(template_pin,ready_pin):
    """Bind previously observed READY; this produces no peer PASS/Root authority."""
    t=m.linked(template_pin);ctx,price,boundary,_=validate_template(t);ready=m.linked(ready_pin)
    m.require(ready_pin["path"]==t["canonical_ready_path"]
              and ready.get("schema")=="r200_owned_ready_v1"
              and ready.get("status")=="READY_R200_OWNED_AWAIT_ROOT_RELEASE_NO_PAYLOAD",
              "explicit canonical immutable READY copy")
    for key in ("purpose","nonce","role","node","root","source_publication","scope","ledger","price","runtime_qualification"):
        m.require(ready[key]==t[key],"same READY "+key)
    now=time.time();m.require(0<=now-ready["created_epoch"]<120 and now<ready["expires_epoch"]
      and ready["resource_lock_path"]==t["resource_lock_path"]
      and ready["case_sha256"]==ctx["case_sha256"]
      and ready["source_map_sha256"]==ctx["source_map_sha256"],"new current exact READY only")
    m.integer(ready["resource_lock_fd"],"actual inherited permit descriptor",3)
    witness=m.linked(ready["physical_admission"])
    m.require(ready["physical_admission"]["path"]==t["canonical_physical_path"]
              and witness["owner"]==ready["owner"] and witness["job_id"]==ready["job_id"]
              and witness["node"]==t["node"] and 0<=now-witness["observed_epoch"]<90,
              "fresh canonical physical witness, not admission from metadata alone")
    launch=copy.deepcopy(t["owner_launch_template"]);launch["job_id"]=ready["job_id"]
    launch["environment"].update(SLURM_JOB_ID=ready["job_id"],SLURMD_NODENAME=t["node"])
    launch_pin=m.write_new(t["owner_launch_path"],launch)
    runtime_owner=dict(job_id=ready["job_id"],node=t["node"],uid=ready["uid"],
      parent_pid=ready["owner"]["pid"],parent_birth_ticks=ready["owner"]["start_ticks"],
      resource_lock_fd=ready["resource_lock_fd"],expires_epoch=t["expires_epoch"])
    spec=dict(schema="r200_owned_compute_spec_v1",purpose=t["purpose"],nonce=t["nonce"],
      role=t["role"],job_id=ready["job_id"],node=t["node"],uid=ready["uid"],affinity=witness["affinity"],
      root=t["root"],owner=ready["owner"],case=ctx["case"],case_sha256=ctx["case_sha256"],
      source_map_sha256=ctx["source_map_sha256"],owner_launch=launch_pin,
      source_publication=t["source_publication"],source_pins=t["source_pins"],runtime_owner=runtime_owner,
      scope=t["scope"],ledger=t["ledger"],input_manifest=t["input_manifest"],
      input_provenance=t["input_provenance"],price=t["price"],
      runtime_qualification=t["runtime_qualification"],acknowledgement_path=t["acknowledgement_path"],
      resource_lock_fd=ready["resource_lock_fd"],resource_lock_path=t["resource_lock_path"],
      attempt_claim_path=t["attempt_claim_path"],issued_epoch=now,expires_epoch=t["expires_epoch"],
      role_request=t["io_request"],io_request=t["io_request"],scientific_source=t["scientific_source"],
      controller_source=t["source_publication"],scientific_sources=t["scientific_sources"])
    m.closed(spec,boundary.SPEC_KEYS|{"io_request"},"exact new owner spec")
    pin=m.write_new(t["spec_path"],spec)
    return dict(status="PREPARED_SPEC_AWAIT_TWO_ACTUAL_PEERS_AND_ROOT_AUTHORITY",
                spec=pin,owner_launch=launch_pin,ready=ready_pin,grants_runtime=False)
