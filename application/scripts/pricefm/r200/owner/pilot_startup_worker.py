"""One direct-Slurm metadata startup, READY and same-PID scientific-owner handoff.
Import is inert; the actual Slurm/cgroup gate precedes supplied record access.
No submission/requeue, R/target read, peer PASS or authority is generated here.
"""
from __future__ import annotations
import argparse,fcntl,hashlib,importlib.util,json,os,re,resource,stat,time
from pathlib import Path
_MSHA="6593a6bbb617375029bee0c692e510cd5621662eaf9fab46445eab433ff0762b"
_mp=Path(__file__).absolute().with_name("metadata.py");_raw=_mp.read_bytes()
if _mp.is_symlink() or hashlib.sha256(_raw).hexdigest()!=_MSHA:raise ValueError("fixed metadata source")
_ms=importlib.util.spec_from_file_location("_r200_startup_metadata",_mp)
m=importlib.util.module_from_spec(_ms);exec(compile(_raw,str(_mp),"exec"),m.__dict__)
_UNSAFE_HELD_FDS=[]

def _actual_job():
    job=os.environ.get("SLURM_JOB_ID","");node=os.uname().nodename.split(".")[0]
    m.require(re.fullmatch("[1-9][0-9]{0,11}",job or "") is not None
      and node=="node-13" and os.environ.get("SLURMD_NODENAME")==node
      and os.environ.get("SLURM_CPUS_PER_TASK")=="1" and os.environ.get("TZ")=="UTC",
      "actual one-core fixed-node Slurm startup before supplied record access")
    group=Path("/proc/self/cgroup").read_text()
    m.require(re.search(r"(?:^|/)job_"+re.escape(job)+r"(?:/|$)",group,re.MULTILINE) is not None,
              "actual Slurm kernel cgroup, never environment-only identity")
    status=dict(x.split(":",1) for x in Path("/proc/self/status").read_text().splitlines() if ":" in x)
    m.require(int(status["TracerPid"].strip())==0,"direct owned startup outside administrative H")
    return job,node

def run(template_pin,bootstrap_authority_pin):
    job,node=_actual_job()  # Must remain the first executable statement.
    t=m.linked(template_pin)
    pp=t.get("source_pins",{}).get("owner/pilot_job_prepare.py")
    m.require(pp is not None and pp["path"]==str(Path(__file__).absolute().with_name("pilot_job_prepare.py")),
              "same fixed reviewed preparation sibling")
    raw=m.source_bytes(pp);ls=importlib.util.spec_from_file_location("_r200_startup_prepare",pp["path"])
    prep=importlib.util.module_from_spec(ls);exec(compile(raw,pp["path"],"exec"),prep.__dict__)
    ctx,price,boundary,owner=prep.validate_template(t,on_compute=True)
    bootstrap=m.linked(bootstrap_authority_pin);prep.validate_bootstrap_authority(bootstrap,template_pin,t)
    now=time.time();m.require(bootstrap["issued_epoch"]<=now<bootstrap["expires_epoch"]
      and now+price["whole_wall_seconds"]<t["expires_epoch"],"current funded complete schedule")
    for key in boundary.THREAD_KEYS:m.require(os.environ.get(key)=="1","current one-thread startup")
    executable=m.physical(t["startup_python"]["path"])
    m.require(os.path.realpath(os.sys.executable)==str(executable),"qualified actual Python executable")
    m.read_regular(executable,limit=64*1024**2,expected_sha=t["startup_python"]["sha256"],expected_uid=os.getuid())
    root=m.physical(t["root"]);st=root.stat()
    m.require(stat.S_ISDIR(st.st_mode) and st.st_uid==os.getuid() and stat.S_IMODE(st.st_mode)==0o700,
              "prepaid private new runtime namespace")
    affinity=os.sched_getaffinity(0);m.require(affinity,"actual allocated CPU set")
    os.sched_setaffinity(0,{min(affinity)})  # Only this fresh job, never a production process.
    me=boundary._proc(os.getpid());identity=dict(pid=os.getpid(),start_ticks=me["start_ticks"],
      boot_id=Path("/proc/sys/kernel/random/boot_id").read_text().strip())
    ctx=dict(ctx,job_id=job,node=node,uid=os.getuid(),affinity=sorted(os.sched_getaffinity(0)),owner=identity)
    launch=dict(t["owner_launch_template"],job_id=job)
    # Qualified immutable code/runtime backing; no mounts or privilege changes.
    owner._readonly_execution_sources(ctx,launch,m.linked(t["io_request"]))
    physical=owner._kernel_physical(ctx,price,initial_reservation=True)
    fd=os.open(m.physical(t["resource_lock_path"]),os.O_RDWR|os.O_NOFOLLOW|os.O_CLOEXEC)
    lock=os.fstat(fd);m.require(stat.S_ISREG(lock.st_mode) and lock.st_uid==os.getuid()
      and lock.st_nlink==1,"prequalified owned same-inode permit")
    fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);os.set_inheritable(fd,True)
    m.require("FLOCK" in Path("/proc/self/fdinfo/"+str(fd)).read_text()
      and "WRITE" in Path("/proc/self/fdinfo/"+str(fd)).read_text(),"actual exclusive kernel permit")
    resource.setrlimit(resource.RLIMIT_CPU,(price["owner_CPU_seconds"],price["owner_CPU_seconds"]))
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    claim=m.write_new(root/"STARTUP_SPENT.json",dict(schema="r200_metadata_startup_claim_v1",
      status="SPENT_SINGLE_STARTUP_NO_RETRY",template=template_pin,bootstrap_authority=bootstrap_authority_pin,
      purpose=t["purpose"],nonce=t["nonce"],job_id=job,node=node,owner=identity,created_epoch=now))
    handed=False
    try:
        witness=dict(physical,schema="r200_actual_physical_core_witness_v1",owner=identity,
          scope=t["scope"],filesystem_mandatory_headroom_bytes=price["mandatory_headroom_bytes"])
        remote_witness=m.write_new(t["physical_path"],witness)
        logical_witness=dict(path=t["canonical_physical_path"],sha256=remote_witness["sha256"])
        created=time.time();expiry=min(t["expires_epoch"],created+120)
        m.require(created<bootstrap["expires_epoch"],"metadata bootstrap still current before READY")
        ready=dict(schema="r200_owned_ready_v1",status="READY_R200_OWNED_AWAIT_ROOT_RELEASE_NO_PAYLOAD",
          purpose=t["purpose"],nonce=t["nonce"],role=t["role"],job_id=job,node=node,uid=os.getuid(),
          owner=identity,resource_lock_fd=fd,resource_lock_path=t["resource_lock_path"],root=t["root"],
          case_sha256=ctx["case_sha256"],source_map_sha256=ctx["source_map_sha256"],
          source_publication=t["source_publication"],scope=t["scope"],ledger=t["ledger"],
          price=t["price"],runtime_qualification=t["runtime_qualification"],
          physical_admission=logical_witness,created_epoch=created,expires_epoch=expiry)
        remote_ready=m.write_new(t["ready_path"],ready)
        canonical_ready=dict(path=t["canonical_ready_path"],sha256=remote_ready["sha256"])
        # Root must copy identical READY/physical bytes to the canonical namespace,
        # run BOTH peers, publish full authority, then atomically publish this one
        # create-only release notice. No malformed record is retried.
        release_path=m.physical(t["release_path"]);deadline=time.monotonic()+max(0,min(expiry,bootstrap["expires_epoch"])-time.time())
        while not release_path.exists() and time.monotonic()<deadline:time.sleep(.1)
        m.require(release_path.exists() and time.time()<min(expiry,bootstrap["expires_epoch"]),"fixed READY wait exhausted; no retry")
        release=m.strict_json(m.read_regular(release_path,limit=65536,expected_uid=os.getuid()))
        m.closed(release,{"schema","status","template","ready","spec","authority","source_review",
                         "issued_epoch","expires_epoch"},"one Root release notice")
        m.require(release["schema"]=="r200_startup_root_release_v1"
          and release["status"]=="ROOT_RELEASE_R200_READY_OWNER"
          and release["template"]==template_pin and release["ready"]==canonical_ready
          and created<=release["issued_epoch"]<=time.time()<release["expires_epoch"]<=expiry,
          "exact current READY release selection")
        spec=m.linked(release["spec"])
        m.require(release["spec"]["path"]==t["spec_path"] and spec["owner"]==identity
          and spec["job_id"]==job and spec["node"]==node and spec["resource_lock_fd"]==fd
          and spec["resource_lock_path"]==t["resource_lock_path"]
          and time.time()-physical["observed_epoch"]<90,"same fresh owner/core/permit and physical snapshot")
        # owner.run independently verifies both peer records and full Root authority.
        # Direct function call preserves the exact READY PID/start/held FD.
        handed=True
        result=owner.run(release["spec"],release["authority"],release["source_review"])
        fcntl.flock(fd,fcntl.LOCK_UN);os.close(fd)
        return result
    except BaseException as error:
        path=root/"STARTUP_FAILED_SPENT.json"
        if not path.exists():
            m.write_new(path,dict(status="FAILED_STARTUP_OR_HANDOFF_FEES_AND_PARTIALS_RETAINED",
              template=template_pin,claim=claim,owner=identity,job_id=job,node=node,
              error=type(error).__name__+": "+str(error),automatic_retry=False))
        if handed:_UNSAFE_HELD_FDS.append(fd)
        else:fcntl.flock(fd,fcntl.LOCK_UN);os.close(fd)
        raise

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--template",required=True);p.add_argument("--template-sha256",required=True)
    p.add_argument("--bootstrap-authority",required=True);p.add_argument("--bootstrap-authority-sha256",required=True)
    a=p.parse_args()
    result=run(dict(path=a.template,sha256=a.template_sha256),
               dict(path=a.bootstrap_authority,sha256=a.bootstrap_authority_sha256))
    print(json.dumps(result,sort_keys=True));return 0
if __name__=="__main__":raise SystemExit(main())
