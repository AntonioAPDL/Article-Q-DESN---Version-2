"""Fixed compute-only low-level binding; no top-level FFI/native import."""
import errno
import hashlib
import importlib.util
import os
from pathlib import Path
import re
import sys
import time

ROOT=Path(__file__).absolute().parent.parent
ABI_CONTRACT_SHA="0d6ae35a0b2d20af4ff1f9db8d511d9564bbc686e3c9434bca3f71c6c6d06c7d"
def contract():
    path=ROOT/"abi/contract.py"
    raw=path.read_bytes()
    if (not re.fullmatch("[0-9a-f]{64}",ABI_CONTRACT_SHA) or
        any(p.is_symlink() for p in (path,*path.parents)) or
        hashlib.sha256(raw).hexdigest()!=ABI_CONTRACT_SHA):
        raise ValueError("fixed authenticated ABI metadata contract")
    name="_r203_abi_contract";old=sys.modules.get(name)
    if old is not None:
        if old.__file__!=str(path) or getattr(old,"_r203_source_sha256",None)!=ABI_CONTRACT_SHA:
            raise ValueError("same ABI contract module")
        return old
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec)
    sys.modules[name]=module;exec(compile(raw,str(path),"exec"),module.__dict__)
    module._r203_source_sha256=ABI_CONTRACT_SHA
    return module

def readonly(path):
    c=contract();path=c.physical(str(path));rows=[]
    for text in Path("/proc/self/mountinfo").read_text().splitlines():
        parts=text.split();cut=parts.index("-");point=parts[4]
        for old,new in ((r"\040"," "),(r"\011","\t"),(r"\012","\n"),(r"\134","\\")):
            point=point.replace(old,new)
        mount=Path(point)
        if path.is_relative_to(mount):
            rows.append((len(mount.parts),set(parts[5].split(",")),set(parts[cut+3].split(","))))
    c.require(rows,"actual source/runtime mount")
    _,options,super_options=max(rows,key=lambda r:r[0])
    c.require("ro" in options and "ro" in super_options,"RO mount AND backing superblock")

def _typed_library(context):
    c=contract();context=c.require_context(context);stage,_=c.policy(context)
    c.require(os.uname().sysname=="Linux" and os.uname().machine=="x86_64","fixed Linux ABI")
    build=c.linked(stage["build_acceptance"]);deployment=c.linked(stage["deployment_acceptance"])
    c.require(build.get("schema")=="r201_owned_native_build_acceptance_v1" and
      build.get("status")=="ACCEPTED_SOURCE_BUILD_ONLY_NOT_RUNTIME" and
      deployment.get("schema")=="r201_readonly_namespace_acceptance_v1" and
      deployment.get("status")=="ACCEPTED_READONLY_NAMESPACE_ONLY_NOT_RUNTIME" and
      build.get("source_map_sha256")==deployment.get("source_map_sha256")==context.runtime_map_sha256 and
      all(build[k]==stage[k] for k in ("native_library","native_abi","native_build_manifest")) and
      deployment.get("build_acceptance")==stage["build_acceptance"],"actual accepted samepath build/deploy")
    manifest=c.linked(stage["native_build_manifest"]);abi=c.linked(stage["native_abi"])
    c.require(manifest["output_library"]==stage["native_library"] and manifest["abi"]==stage["native_abi"]
      and manifest["source"]==context.runtime_sources["native_python/r201_native_boundary.c"] and
      manifest["header"]==context.runtime_sources["native_python/r201_native_boundary.h"] and
      manifest["dependencies"]==stage["native_dependencies"],"unchanged exact artifact/manifest/dependency closure")
    c.require(abi["schema"]=="r201_native_python_boundary_abi_v1" and abi["version"]==1 and
      abi["platform"]=="linux-x86_64" and abi["roles"]==
      {"INITIAL_NATIVE_REFERENCE_QUALIFICATION":1,"LT_NO4_REFERENCE":2},"actual ABI descriptor")
    for record in [stage["native_library"],*stage["native_dependencies"]]:
        path=c.physical(record["path"]);readonly(path)
        raw=c.captured(path,64*1024**2)
        c.require(hashlib.sha256(raw).hexdigest()==record["sha256"],"actual immutable native/dependency bytes")
    # FFI import and actual native loading are BELOW the genuine compute context,
    # accepted artifacts, exact bytes and present immutable backing gates.
    import ctypes
    class Receipt(ctypes.Structure):
        _fields_=[("abi_version",ctypes.c_uint32),("state",ctypes.c_uint32),
          ("role",ctypes.c_uint32),("uid",ctypes.c_uint32),("child_pid",ctypes.c_int64),
          ("owner_pid",ctypes.c_int64),("child_start_ticks",ctypes.c_uint64),
          ("owner_start_ticks",ctypes.c_uint64),("permit_device",ctypes.c_uint64),
          ("permit_inode",ctypes.c_uint64),("expires_epoch",ctypes.c_double),
          ("boot_id",ctypes.c_char*37),("job_id",ctypes.c_char*21),
          ("node",ctypes.c_char*256),("cgroup",ctypes.c_char*8192)]
    lib=ctypes.CDLL(stage["native_library"]["path"],mode=os.RTLD_LOCAL|os.RTLD_NOW,use_errno=True)
    signatures={
      "r201_prepare_v1":([ctypes.c_int64,ctypes.c_uint64,ctypes.c_int,ctypes.c_int,ctypes.c_double],ctypes.c_int),
      "r201_scientific_boundary_v1":([],ctypes.c_int),
      "r201_validate_live_v1":([],ctypes.c_int),
      "r201_receipt_v1":([ctypes.POINTER(Receipt)],ctypes.c_int),
      "r201_receipt_size_v1":([],ctypes.c_uint64),
      "r201_last_error_v1":([],ctypes.c_char_p),
      "r201_rename_noreplace_v1":([ctypes.c_int,ctypes.c_char_p,ctypes.c_char_p],ctypes.c_int)}
    c.require(set(abi["symbols"])==set(signatures),"exact native exports")
    for name,(args,result) in signatures.items():
        function=getattr(lib,name);function.argtypes=args;function.restype=result
    actual=lib.r201_receipt_size_v1();expected=ctypes.sizeof(Receipt)
    c.require(type(actual) is int and actual==expected,"actual exported receipt ABI size")
    return ctypes,Receipt,lib,dict(native_library=stage["native_library"],native_abi=stage["native_abi"],
      expected_receipt_bytes=expected,actual_receipt_bytes=actual,actual_export_names=sorted(signatures))

class Native:
    """A fixed source-gated binding, never a substitute for Root context."""
    def __init__(self,context):
        c=contract();self.context=c.require_context(context)
        self.ctypes,self.Receipt,self.lib,self.probe=_typed_library(context)
        self.operations=[];self.failed=False;self.prepared=False;self.earned=False;self.expiry=None

    def _invoke(self,name,args,declared,receipt=None):
        c=contract();c.require_context(self.context)
        c.require(not self.failed,"failed native singleton is never reused")
        self.ctypes.set_errno(0);started=time.time()
        rc=getattr(self.lib,name)(*args);observed_errno=self.ctypes.get_errno()
        finished=time.time();first=None
        if rc==-1:
            error=self.lib.r201_last_error_v1()
            first=error.decode("ascii") if error is not None else None
            self.failed=True
        c.require(type(rc) is int and rc in (0,-1),"actual typed native return")
        decoded=None
        if rc==0 and receipt is not None:
            decoded={}
            for key,_ in self.Receipt._fields_:
                value=getattr(receipt,key)
                decoded[key]=value.decode("ascii") if isinstance(value,bytes) else value
        row=dict(operation=name,arguments=declared,return_value=rc,errno=observed_errno,
          first_error=first,started_epoch=started,finished_epoch=finished,receipt=decoded)
        c.operation_shape(row);self.operations.append(row)
        return row

    def prepare(self,expiry,founder_parent=None):
        c=contract();ctx=c.require_context(self.context)
        c.require(not self.prepared and not self.operations,"one prepare per fresh native image")
        c.epoch(expiry);c.require(time.time()<expiry<=ctx.stage_deadline_epoch,"live finite native expiry")
        owner=ctx.owner;permit=ctx.permit_fd
        if founder_parent is not None:
            c.require(getattr(ctx,"case_id",None) is None and founder_parent["pid"]==os.getppid(),
              "founder uses actual parent only")
            owner=founder_parent
        case=getattr(ctx,"case_id",None)
        if case=="wrong_lifetime":
            owner=dict(owner,start_ticks=owner["start_ticks"]+1)
        if case=="wrong_permit":
            permit=2147483647
            try:os.fstat(permit)
            except OSError as exc:c.require(exc.errno==errno.EBADF,"real unavailable wrong native argument")
            else:raise ValueError("fixed wrong native argument unexpectedly open")
        declared=dict(owner_pid=owner["pid"],owner_start_ticks=owner["start_ticks"],
          permit_fd=permit,role=1,expires_epoch=expiry)
        row=self._invoke("r201_prepare_v1",[owner["pid"],owner["start_ticks"],permit,1,expiry],declared)
        self.prepared=True;self.expiry=expiry
        return row

    def boundary(self):
        row=self._invoke("r201_scientific_boundary_v1",[],{})
        if row["return_value"]==0:self.earned=True
        return row

    def live(self):
        return self._invoke("r201_validate_live_v1",[],{})

    def receipt(self):
        value=self.Receipt()
        row=self._invoke("r201_receipt_v1",[self.ctypes.byref(value)],{},receipt=value)
        if row["return_value"]==0:
            c=contract();ctx=self.context;actual=c.actual_identity();held=os.fstat(ctx.permit_fd)
            r=row["receipt"]
            c.require(r["abi_version"]==1 and r["state"]==3 and r["role"]==1 and
              r["uid"]==os.getuid() and r["child_pid"]==actual["pid"] and
              r["child_start_ticks"]==actual["start_ticks"] and
              r["owner_pid"]==ctx.owner["pid"] and r["owner_start_ticks"]==ctx.owner["start_ticks"] and
              r["permit_device"]==held.st_dev and r["permit_inode"]==held.st_ino and
              r["expires_epoch"]==self.expiry and r["boot_id"]==ctx.owner["boot_id"] and
              r["job_id"]==ctx.job_id and r["node"].split(".")[0]==ctx.node,"actual earned native receipt identity")
        return row

    def rename(self,dirfd,source,final):
        c=contract();c.require(self.earned,"actual earned state before native rename")
        for name in (source,final):
            c.require(type(name) is str and re.fullmatch("[A-Za-z0-9_.-]{1,128}",name)
              and name not in (".",".."),"fixed native basename")
        return self._invoke("r201_rename_noreplace_v1",[dirfd,source.encode("ascii"),final.encode("ascii")],
          dict(directory_fd=dirfd,source=source,final=final))
