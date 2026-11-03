"""Owned bounded full-reference return; source tests cannot mint a native handle."""
from __future__ import annotations
import hashlib,importlib.util,json,os,stat,sys,time
from pathlib import Path
_p=Path(__file__).absolute().with_name("reference_common.py")
# Authenticate one captured fixed-source byte string BEFORE interpretation.
_COMMON_SHA="e9e35192e82bf0669cdbce20614cfc68e195ecd3c4c2655d479b8267544fc870"
if any(v.is_symlink() for v in (_p,*_p.parents)):
    raise ValueError("fixed common source requires physical nonsymlink path")
_cfd=os.open(_p,os.O_RDONLY|os.O_NONBLOCK|os.O_NOFOLLOW)
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
if (_cstate(_cbefore)!=_cstate(_cafter) or _cstate(_cafter)!=_cstate(_p.lstat())
        or len(_craw)!=_cbefore.st_size or hashlib.sha256(_craw).hexdigest()!=_COMMON_SHA):
    raise ValueError("exact captured common source SHA and physical lifetime")
_s=importlib.util.spec_from_file_location("_r201_return_common",_p)
c=importlib.util.module_from_spec(_s);sys.modules[_s.name]=c
exec(compile(_craw,str(_p),"exec"),c.__dict__)
m=c.m
FILE_LIMIT=16*1024**2
USEFUL_LIMIT=64*1024**2
MIN_PROOF_RETURN=16*1024**2
MIN_PROOF_STORAGE=64*1024**2
def plan(spec,price):
    """Descriptor planning only. Does not reserve, write or admit execution."""
    m.require(spec.get("role") in c.ROLES,"closed return role")
    proof=m.integer(price.get("return_proof_reservation_bytes"),"complete useful proof reserve",
                    MIN_PROOF_RETURN,USEFUL_LIMIT-1)
    storage=m.integer(price.get("proof_storage_reservation_bytes"),"physical proof reserve",
                      MIN_PROOF_STORAGE,2**63-1)
    if spec["role"]==c.INITIAL:names=["qualification_summary.json"]
    else:
        p=m.integer(spec.get("case",{}).get("p"),"fixed full covariance dimension",1,1024)
        names=["reference_covariance_rows_%04d.json"%i for i in range((p+31)//32)]
        names.append("reference_summary.json")
    physical=len(names)*FILE_LIMIT+storage+2*FILE_LIMIT
    m.require(type(price.get("reserved_filesystem_bytes")) is int and
              price["reserved_filesystem_bytes"]>=physical,"whole price covers physical payload and proof reservations")
    return {"schema":"r201_reference_return_plan_v1","role":spec["role"],"names":names,
       "maximum_file_bytes":FILE_LIMIT,"maximum_useful_bytes":USEFUL_LIMIT,
       "payload_maximum_useful_bytes":USEFUL_LIMIT-proof,"proof_return_reserved_bytes":proof,
       "physical_payload_reservation_bytes":len(names)*FILE_LIMIT,
       "physical_proof_reservation_bytes":storage,"physical_owner_tree_extra_reservation_bytes":2*FILE_LIMIT,"physical_total_bytes":physical}
def inspect_parts(result,expected):
    """Only a descriptor/byte-count check; no ownership or filesystem authority."""
    m.require(type(result) is dict and result.get("schema")=="r200_reference_owned_return_parts_v1",
              "fixed complete owned result parts schema")
    records=result.get("records");m.require(type(records) is list and len(records)==len(expected["names"]),
                                          "complete exact return record count")
    byname={};total=0
    for row in records:
        m.closed(row,{"relative_path","sha256","bytes","payload"},"complete encoded part")
        name=row["relative_path"];m.require(type(name) is str and name in expected["names"] and name not in byname,
                                            "exact unique closed return name")
        m.require(type(row["payload"]) is bytes,"owned raw bytes, never JSON-serialize the whole result")
        m.integer(row["bytes"],"part bytes",1,FILE_LIMIT)
        m.require(len(row["payload"])==row["bytes"] and hashlib.sha256(row["payload"]).hexdigest()==row["sha256"],
                  "actual bounded encoded bytes and SHA")
        byname[name]=row;total+=row["bytes"]
    m.require(set(byname)==set(expected["names"]) and type(result.get("total_bytes")) is int
              and result["total_bytes"]==total<=expected["payload_maximum_useful_bytes"],
              "full useful return includes reserved proof/manifest room")
    return [byname[name] for name in expected["names"]]
def _proof_layout(spec,launch):
    root=Path(spec["root"]);out=Path(launch["output_root"])
    return [("stdout",Path(launch["stdout_path"]),FILE_LIMIT),
      ("stderr",Path(launch["stderr_path"]),FILE_LIMIT),
      ("guard",Path(launch["owned_guard_path"]),8*1024**2),
      ("candidate",root/"OWNER_CANDIDATE.json",4*1024**2),
      ("failure",root/"OWNER_FAILED_SPENT.json",4*1024**2),
      ("inventory",root/"RETAINED_INVENTORY.json",4*1024**2),
      ("ack",Path(spec["acknowledgement_path"]),4*1024**2),
      ("reservation",root/"RETURN_RESERVATION.json",4*1024**2),
      ("manifest",out/"r201_manifest.partial",4*1024**2)]

def _consume(slot,raw):
    m.require(type(raw) is bytes and 0<len(raw)<slot["max_bytes"],"complete proof fits prepaid physical slot")
    fd=os.open(slot["path"],os.O_RDWR|os.O_NOFOLLOW)
    try:
        st=os.fstat(fd)
        m.require((st.st_dev,st.st_ino)==(slot["dev"],slot["ino"]) and st.st_uid==os.getuid()
          and st.st_nlink==1 and stat.S_ISREG(st.st_mode) and st.st_size==slot["max_bytes"]
          and os.pread(fd,min(64,st.st_size),0)==bytes(min(64,st.st_size)),
          "fresh unused same-inode proof slot; failed partials never reused")
        done=0
        while done<len(raw):
            n=os.write(fd,raw[done:]);m.require(n>0 and done+n<len(raw)+1,"counted proof write");done+=n
        os.ftruncate(fd,done);os.fsync(fd)
    finally:os.close(fd)
    return m.pin_file(slot["path"])

def reserve_for_owner(spec,price,launch):
    c.job();m.require(spec["owner"]==c.identity(),"actual current parent owns reservations")
    p=plan(spec,price);out=m.physical(launch["output_root"]);out.mkdir(mode=0o700)
    st=out.stat();m.require(stat.S_IMODE(st.st_mode)==0o700 and st.st_uid==os.getuid(),"private owned return directory")
    slots=[("payload",out/("r201_payload_%04d.partial"%i),FILE_LIMIT,name)
           for i,name in enumerate(p["names"])]
    slots += [(key,path,bound,None) for key,path,bound in _proof_layout(spec,launch)]
    extra=p["physical_proof_reservation_bytes"]-sum(b for _,_,b in _proof_layout(spec,launch));i=0
    m.require(extra>=0,"proof storage covers exact fixed slots")
    while extra:
        bound=min(FILE_LIMIT,extra);slots.append(("unused",out/("r201_proof_extra_%04d.reserve"%i),bound,None));extra-=bound;i+=1
    rows=[]
    for key,path,bound,final in slots:
        path=m.physical(str(path));fd=os.open(path,os.O_RDWR|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
        try:
            os.posix_fallocate(fd,0,bound);os.fsync(fd);state=os.fstat(fd)
            m.require(state.st_uid==os.getuid() and state.st_nlink==1 and stat.S_ISREG(state.st_mode)
              and stat.S_IMODE(state.st_mode)==0o600 and state.st_size==bound,"physical single-link reserved slot")
            rows.append({"key":key,"path":str(path),"partial":path.name,"final":final,"max_bytes":bound,
                         "dev":state.st_dev,"ino":state.st_ino})
        finally:os.close(fd)
    receipt={"schema":"r201_physical_return_reservation_v1","status":"PHYSICAL_SLOTS_RESERVED_BEFORE_CHILD",
      "purpose":spec["purpose"],"nonce":spec["nonce"],"role":spec["role"],"owner":spec["owner"],
      "job_id":spec["job_id"],"node":spec["node"],"output_root":str(out),"directory_dev":st.st_dev,
      "directory_ino":st.st_ino,"plan":p,"slots":rows,"created_epoch":time.time(),"no_retry_or_cleanup":True}
    return _consume(next(r for r in rows if r["key"]=="reservation"),m.canonical(receipt)+b"\n")

def write_parent_proof(spec,key,value):
    c.job();m.require(spec["owner"]==c.identity(),"actual fixed parent proof writer")
    reserved=m.linked(m.pin_file(Path(spec["root"])/"RETURN_RESERVATION.json"))
    m.require(key in {"guard","candidate","failure","inventory","ack"},"closed owner proof slot")
    return _consume(next(row for row in reserved["slots"] if row["key"]==key),m.canonical(value)+b"\n")

def retained_inventory(spec,launch):
    c.job();reserved=m.linked(m.pin_file(Path(spec["root"])/"RETURN_RESERVATION.json"));rows=[]
    allowed={Path(r["path"]) for r in reserved["slots"]}
    allowed.update(Path(launch["output_root"])/name for name in reserved["plan"]["names"])
    allowed.add(Path(launch["output_root"])/"REFERENCE_RETURN_MANIFEST.json")
    # Enumerate only this exact owned purpose, never an unrelated server census.
    for parent in {Path(spec["root"]),Path(launch["output_root"])}:
        for path in parent.iterdir():
            st=path.lstat()
            if stat.S_ISDIR(st.st_mode):continue
            m.require(not path.is_symlink() and stat.S_ISREG(st.st_mode) and st.st_uid==os.getuid()
                      and st.st_nlink==1 and st.st_size<=FILE_LIMIT,"bounded retained owned file")
            rows.append({"path":str(path),"bytes":st.st_size,"dev":st.st_dev,"ino":st.st_ino,
                         "reserved_slot":path in allowed})
    return {"schema":"r201_retained_owned_inventory_v1","rows":sorted(rows,key=lambda r:r["path"]),
            "complete_owned_root_and_output_observation":True,"later_candidate_and_accounting_pending":True,"no_deletion":True,"created_epoch":time.time()}

def _context(specpin,authoritypin,reviewpin,ackpin):
    c.job()
    spec=m.linked(specpin);review=m.linked(reviewpin)
    if spec.get("role")==c.INITIAL:
        gate=c.load("qualification/qualification_boundary.py",review["source_pins"])
    else:
        m.require(spec.get("role")==c.PRODUCTION,"closed actual return role")
        gate=c.load("owner/compute_boundary.py",review["source_pins"])
    owned=gate.acquire(specpin,authoritypin,reviewpin,ackpin);owned.verify_live()
    native=c.load("native_python/native_contract.py",review["source_pins"]).reacquire(specpin,reviewpin)
    native.verify_live()
    return spec,review,owned,native
def write_parts(spec_pin,authority_pin,review_pin,ack_pin,result):
    """Fixed child entry after actual native ACK and role boundary acquisition."""
    spec,review,owned,native=_context(spec_pin,authority_pin,review_pin,ack_pin)
    launch=m.linked(spec["owner_launch"]);price=c.price_for(spec);expected=plan(spec,price)
    records=inspect_parts(result,expected)
    reserved=m.linked(m.pin_file(Path(spec["root"])/"RETURN_RESERVATION.json"))
    m.require(reserved.get("status")=="PHYSICAL_SLOTS_RESERVED_BEFORE_CHILD"
              and reserved.get("owner")==spec["owner"] and reserved.get("plan")==expected
              and all(reserved.get(k)==spec[k] for k in ("purpose","nonce","role","job_id","node"))
              and reserved.get("output_root")==launch["output_root"],"same actual pre-fork reservation")
    out=m.physical(launch["output_root"]);directory=os.open(out,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
    try:
        st=os.fstat(directory)
        m.require((st.st_dev,st.st_ino)==(reserved["directory_dev"],reserved["directory_ino"])
                  and st.st_uid==os.getuid() and stat.S_IMODE(st.st_mode)==0o700,"same owned directory inode")
        slotmap={row["final"]:row for row in reserved["slots"] if row["final"] is not None}
        completed=[]
        for row in records:
            owned.verify_live();native.verify_live();slot=slotmap[row["relative_path"]]
            fd=os.open(slot["partial"],os.O_RDWR|os.O_NOFOLLOW,dir_fd=directory)
            try:
                before=os.fstat(fd)
                m.require((before.st_dev,before.st_ino)==(slot["dev"],slot["ino"])
                          and before.st_nlink==1 and before.st_uid==os.getuid()
                          and before.st_size==slot["max_bytes"],"same complete physically reserved next write")
                view=memoryview(row["payload"]);written=0
                while written<len(view):
                    count=os.write(fd,view[written:])
                    m.require(count>0 and written+count<=slot["max_bytes"],"bounded complete serialization")
                    written+=count
                os.ftruncate(fd,written)  # Finalize exact complete serialization length, not partial cleanup.
                os.fsync(fd)
                os.lseek(fd,0,os.SEEK_SET);digest=hashlib.sha256()
                for block in iter(lambda:os.read(fd,65536),b""):digest.update(block)
                m.require(digest.hexdigest()==row["sha256"],"actual completed bytes before atomic commit")
            finally:os.close(fd)
            native.commit_noreplace(directory,slot["partial"],row["relative_path"])
            completed.append({"relative_path":row["relative_path"],"bytes":row["bytes"],"sha256":row["sha256"]})
        manifest={"schema":"r201_complete_reference_payload_manifest_v1","purpose":spec["purpose"],"nonce":spec["nonce"],
          "role":spec["role"],"job_id":spec["job_id"],"node":spec["node"],"records":completed,
          "payload_total_bytes":sum(r["bytes"] for r in completed),"proof_reservation_bytes":expected["proof_return_reserved_bytes"],
          "whole_useful_limit_bytes":USEFUL_LIMIT,"accounting_and_independent_acceptance_pending":True,
          "scientific_acceptance":False,"automatic_dependent_release":False}
        encoded=m.canonical(manifest)+b"\n"
        m.require(len(encoded)<=expected["proof_return_reserved_bytes"] and len(encoded)<=FILE_LIMIT,"manifest inside proof reserve")
        # Create-only small metadata; incomplete writes are retained and cannot be accepted.
        manifestslot=next(row for row in reserved["slots"] if row["key"]=="manifest")
        _consume(manifestslot,encoded)
        native.commit_noreplace(directory,"r201_manifest.partial","REFERENCE_RETURN_MANIFEST.json")
        manifestpin=m.pin_file(out/"REFERENCE_RETURN_MANIFEST.json")
        owned.verify_live();native.verify_live()
        return {"status":"OWNED_REFERENCE_PARTS_COMMITTED_AWAIT_PARENT_ACCOUNTING_AND_PEER",
                "manifest":manifestpin,"records":completed,"payload_total_bytes":manifest["payload_total_bytes"],
                "scientific_acceptance":False,"production_acceptance":False,"automatic_dependent_release":False}
    finally:os.close(directory)
def verify_parent_return(spec,price,launch):
    """Owned parent validates full committed bytes; it does not accept science."""
    c.job();expected=plan(spec,price);out=m.physical(launch["output_root"])
    manifest=m.linked(m.pin_file(out/"REFERENCE_RETURN_MANIFEST.json"))
    rows=manifest.get("records");m.require(type(rows) is list and len(rows)==len(expected["names"]) and {r["relative_path"] for r in rows}==set(expected["names"]),
                                         "complete fixed covariance/result set")
    total=0
    for row in rows:
        m.closed(row,{"relative_path","bytes","sha256"},"closed committed record")
        m.integer(row["bytes"],"committed file size",1,FILE_LIMIT)
        raw=m.read_regular(out/row["relative_path"],limit=FILE_LIMIT,expected_sha=row["sha256"],
                           expected_uid=os.getuid(),expected_bytes=row["bytes"])
        total+=len(raw)
    m.require(total==manifest["payload_total_bytes"]<=expected["payload_maximum_useful_bytes"],"payload leaves all proof reserve")
    return {"manifest":m.pin_file(out/"REFERENCE_RETURN_MANIFEST.json"),"payload_bytes":total,
            "remaining_useful_proof_budget_bytes":expected["proof_return_reserved_bytes"],
            "final_accounting_independent_review_and_full_useful_inventory_pending":True}
