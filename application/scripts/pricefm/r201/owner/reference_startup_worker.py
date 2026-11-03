"""Actual Slurm metadata startup and direct same-PID reference owner handoff."""
from __future__ import annotations
import argparse,copy,fcntl,hashlib,importlib.util,json,os,resource,stat,time
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
_cs=importlib.util.spec_from_file_location("_r201_startup_common",_cp)
c=importlib.util.module_from_spec(_cs);exec(compile(_craw,str(_cp),"exec"),c.__dict__)
m=c.m
_UNSAFE_HELD_FDS=[]
def source_witness(ctx,launch):
    """Actual source/RO observation, no review PASS or spec hash cycle."""
    c.job()
    rows=[]
    for relative,pin in sorted(ctx["source_pins"].items()):
        raw=m.source_bytes(pin);st=Path(pin["path"]).stat()
        rows.append(dict(relative=relative,path=pin["path"],sha256=pin["sha256"],bytes=len(raw),
          uid=st.st_uid,mode=stat.S_IMODE(st.st_mode),nlink=st.st_nlink))
    paths={p["path"] for p in ctx["source_pins"].values()}
    paths.update(p["path"] for p in launch["baseline_files"]);paths.add(launch["native_library"]["path"])
    c.readonly(paths)
    witness={key:ctx[key] for key in ("purpose","nonce","role","job_id","node","uid","owner","root",
      "case_sha256","source_map_sha256","source_publication","source_pins","scope")}
    witness.update(schema="r201_qualification_source_readonly_witness_v1",files=rows,
      readonly_files=[dict(path=path,mount_readonly=True,superblock_readonly=True) for path in sorted(paths)],
      observed_epoch=time.time())
    for key in ("quote","build_acceptance","deployment_acceptance"):
        if key in ctx:witness[key]=ctx[key]
    return witness

def run(template_pin,bootstrap_authority_pin):
    job,node=c.job()  # Actual job/cgroup gate BEFORE supplied records.
    t=m.linked(template_pin)
    prep=c.load("owner/reference_job_prepare.py",t.get("source_pins",{}))
    ctx,price=prep.validate_template(t,on_compute=True)
    bootstrap=m.linked(bootstrap_authority_pin);prep.validate_bootstrap_authority(bootstrap,template_pin,t)
    now=time.time()
    m.require(bootstrap["issued_epoch"]<=now<bootstrap["expires_epoch"]
      and now+price["whole_wall_seconds"]<t["expires_epoch"],"current complete funded schedule")
    for key in c.THREAD_KEYS:m.require(os.environ.get(key)=="1","actual single-thread startup")
    m.require(str(Path("/proc/self/exe").resolve())==t["startup_python"]["path"],"actual declared Python ELF")
    root=m.physical(t["root"]);st=root.stat()
    m.require(stat.S_ISDIR(st.st_mode) and st.st_uid==os.getuid()
      and stat.S_IMODE(st.st_mode)==0o700,"new prepaid private runtime namespace")
    affinity=os.sched_getaffinity(0);m.require(affinity,"actual job affinity")
    os.sched_setaffinity(0,{min(affinity)})  # Only this new job's own process.
    identity=c.identity()
    ctx.update(job_id=job,node=node,uid=os.getuid(),owner=identity,affinity=sorted(os.sched_getaffinity(0)))
    launch=copy.deepcopy(t["owner_launch_template"]);launch["job_id"]=job
    launch["environment"].update(SLURM_JOB_ID=job,SLURMD_NODENAME=node)
    review_like={"source_pins":ctx["source_pins"],"source_map_sha256":ctx["source_map_sha256"]}
    c.validate_launch(ctx,review_like,price,launch)  # Actual identity now exists; no invented job fields.
    physical=c.physical(ctx,price,initial_reservation=True)
    fd=os.open(m.physical(t["resource_lock_path"]),os.O_RDWR|os.O_NOFOLLOW|os.O_CLOEXEC)
    lock=os.fstat(fd)
    m.require(stat.S_ISREG(lock.st_mode) and lock.st_uid==os.getuid() and lock.st_nlink==1,
      "prequalified owned permit inode")
    fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);os.set_inheritable(fd,True)
    m.require("FLOCK" in Path("/proc/self/fdinfo/"+str(fd)).read_text()
      and "WRITE" in Path("/proc/self/fdinfo/"+str(fd)).read_text(),"actual same-inode exclusive FLOCK")
    resource.setrlimit(resource.RLIMIT_CPU,(price["owner_CPU_seconds"],price["owner_CPU_seconds"]))
    resource.setrlimit(resource.RLIMIT_FSIZE,(16*1024**2,16*1024**2))
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    claim=m.write_new(root/"STARTUP_SPENT.json",dict(schema="r201_metadata_startup_claim_v1",
      status="SPENT_SINGLE_STARTUP_NO_RETRY",template=template_pin,bootstrap_authority=bootstrap_authority_pin,
      purpose=t["purpose"],nonce=t["nonce"],job_id=job,node=node,owner=identity,created_epoch=now))
    handed=False
    try:
        if t["role"]==c.INITIAL:
            m.write_new(t["source_witness_path"],source_witness(ctx,launch))
        witness=dict(physical,schema="r200_actual_physical_core_witness_v1",owner=identity,
          scope=t["scope"],filesystem_mandatory_headroom_bytes=price["mandatory_headroom_bytes"])
        remote=m.write_new(t["physical_path"],witness)
        logical=dict(path=t["canonical_physical_path"],sha256=remote["sha256"])
        created=time.time();expiry=min(t["expires_epoch"],created+120)
        ready={key:ctx[key] for key in ("purpose","nonce","role","job_id","node","uid","owner","root",
          "case_sha256","source_map_sha256","source_publication","scope","ledger")}
        initial=t["role"]==c.INITIAL
        ready.update(schema="r201_qualification_ready_v1" if initial else "r200_owned_ready_v1",
          status="READY_R201_INITIAL_QUALIFICATION_AWAIT_ROOT_NO_PAYLOAD" if initial
            else "READY_R200_OWNED_AWAIT_ROOT_RELEASE_NO_PAYLOAD",
          resource_lock_fd=fd,resource_lock_path=t["resource_lock_path"],physical_admission=logical,
          created_epoch=created,expires_epoch=expiry)
        for key in (("quote","build_acceptance","deployment_acceptance") if initial else ("price","runtime_qualification")):
            ready[key]=t[key]
        remote_ready=m.write_new(t["ready_path"],ready)
        canonical_ready=dict(path=t["canonical_ready_path"],sha256=remote_ready["sha256"])
        release_path=m.physical(t["release_path"])
        deadline=time.monotonic()+max(0,min(expiry,bootstrap["expires_epoch"])-time.time())
        while not release_path.exists() and time.monotonic()<deadline:time.sleep(.1)
        m.require(release_path.exists() and time.time()<min(expiry,bootstrap["expires_epoch"]),
          "fixed120second READY interval exhausted; no automatic retry")
        release=m.strict_json(m.read_regular(release_path,limit=65536,expected_uid=os.getuid()))
        m.closed(release,{"schema","status","template","ready","spec","authority","source_review",
          "issued_epoch","expires_epoch"},"single immutable Root release notice")
        m.require(release["schema"]=="r201_reference_startup_root_release_v1"
          and release["status"]=="ROOT_RELEASE_R201_REFERENCE_READY_OWNER"
          and release["template"]==template_pin and release["ready"]==canonical_ready
          and created<=release["issued_epoch"]<=time.time()<release["expires_epoch"]<=expiry,
          "current exact READY release; no metadata grant substitute")
        spec=m.linked(release["spec"])
        m.require(release["spec"]["path"]==t["spec_path"] and spec["owner"]==identity
          and spec["job_id"]==job and spec["node"]==node and spec["resource_lock_fd"]==fd
          and spec["resource_lock_path"]==t["resource_lock_path"]
          and time.time()-physical["observed_epoch"]<90,"same PID/birth/permit/fresh physical proof")
        handed=True
        result=c.load("owner/reference_compute_owner.py",ctx["source_pins"]).run(
          release["spec"],release["authority"],release["source_review"])  # Direct same-PID call.
        fcntl.flock(fd,fcntl.LOCK_UN);os.close(fd)
        return result
    except BaseException as error:
        failure=root/"STARTUP_FAILED_SPENT.json"
        if not failure.exists():
            m.write_new(failure,dict(status="FAILED_STARTUP_OR_HANDOFF_FEES_AND_PARTIALS_RETAINED",
              template=template_pin,claim=claim,owner=identity,job_id=job,node=node,
              error=type(error).__name__+": "+str(error),automatic_retry=False))
        if handed:_UNSAFE_HELD_FDS.append(fd)
        else:fcntl.flock(fd,fcntl.LOCK_UN);os.close(fd)
        raise

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ("template","bootstrap-authority"):
        p.add_argument("--"+name,required=True);p.add_argument("--"+name+"-sha256",required=True)
    a=p.parse_args()
    print(json.dumps(run(dict(path=a.template,sha256=a.template_sha256),
      dict(path=a.bootstrap_authority,sha256=a.bootstrap_authority_sha256)),sort_keys=True))
    return 0
if __name__=="__main__":raise SystemExit(main())
