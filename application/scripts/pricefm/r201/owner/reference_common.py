"""Fixed-source common support for the new Python reference owner, not a grant."""
from __future__ import annotations
import hashlib,importlib.util,os,stat,sys,time
from pathlib import Path
ROOT=Path(__file__).absolute().parent.parent
_METADATA_SHA="6593a6bbb617375029bee0c692e510cd5621662eaf9fab46445eab433ff0762b"
def _initial_metadata():
    p=ROOT/"owner/metadata.py";raw=p.read_bytes()
    if p.is_symlink() or hashlib.sha256(raw).hexdigest()!=_METADATA_SHA:
        raise ValueError("unchanged metadata source")
    spec=importlib.util.spec_from_file_location("_r201_reference_metadata",p)
    module=importlib.util.module_from_spec(spec);sys.modules[spec.name]=module
    exec(compile(raw,str(p),"exec"),module.__dict__);return module
m=_initial_metadata()
INITIAL="INITIAL_NATIVE_REFERENCE_QUALIFICATION"
PRODUCTION="LT_NO4_REFERENCE"
ROLES={INITIAL,PRODUCTION}
TRACE_SHA="914d7d369d68579b7149c5130e3bba5d59f3b8f09a5bf691e1557ccbcd40c963"
BASE_HELPER_SHA="8db25c433166a43b213a20a4117a3350ae36f004e30b37c0ca35d1970f7154f8"
LAUNCH_KEYS={"schema","purpose","nonce","role","job_id","node","bootstrap","native_executable",
 "native_library","native_build_manifest","native_abi","native_build_acceptance",
 "native_deployment_acceptance","traced_guard","baseline_files","environment","bootstrap_exec_allowlist",
 "stdout_path","stderr_path","owned_tree_path","owned_guard_path","output_root"}
THREAD_KEYS=("OPENBLAS_NUM_THREADS","OMP_NUM_THREADS","MKL_NUM_THREADS",
             "VECLIB_MAXIMUM_THREADS","NUMEXPR_NUM_THREADS","BLIS_NUM_THREADS")
def load(relative,pins=None,*,local_metadata=False):
    m.require(type(relative) is str and not Path(relative).is_absolute() and ".." not in Path(relative).parts,
              "fixed relative source member")
    path=ROOT/relative
    if pins is None:
        m.require(relative=="owner/pilot_compute_owner.py","only unchanged helper has built-in source pin")
        descriptor={"path":str(path),"sha256":BASE_HELPER_SHA}
    else:
        m.require(relative in pins,"fixed member in exact source map")
        expected=m.descriptor(pins[relative])
        if local_metadata:
            descriptor={"path":str(path),"sha256":expected["sha256"]}
        else:
            m.require(expected["path"]==str(path),"actual fixed installed sibling")
            descriptor=expected
    raw=m.source_bytes(descriptor)
    spec=importlib.util.spec_from_file_location("_r201_fixed_"+relative.replace("/","_").replace(".","_"),path)
    module=importlib.util.module_from_spec(spec);sys.modules[spec.name]=module
    exec(compile(raw,str(path),"exec"),module.__dict__)
    return module
def job():
    return load("owner/pilot_compute_owner.py")._job()
def physical(spec,price,*,initial_reservation=False):
    # Original tracer retains owner tree while allocating its next temporary.
    # The fixed32MiB initial transient budget is in reserved_filesystem_bytes;
    # after allocation callbacks retain mandatory headroom plus next16MiB.
    current=price if initial_reservation else dict(price,mandatory_headroom_bytes=price["mandatory_headroom_bytes"]+16*1024**2)
    return load("owner/pilot_compute_owner.py")._kernel_physical(spec,current,initial_reservation=initial_reservation)
def proc(pid):
    raw=(Path("/proc")/str(pid)/"stat").read_text();end=raw.rfind(")")
    m.require(end>0,"complete proc lifetime");fields=raw[end+2:].split()
    return {"pid":pid,"start_ticks":int(fields[19])}
def identity():
    return dict(proc(os.getpid()),boot_id=Path("/proc/sys/kernel/random/boot_id").read_text().strip())
def same(record,spec):
    for key in ("purpose","nonce","role","job_id","node"):
        m.require(record.get(key)==spec[key],"same exact current "+key)
def price_for(spec):
    m.require(spec["role"] in ROLES,"closed reference role")
    return m.linked(spec["quote"] if spec["role"]==INITIAL else spec["price"])
def readonly(paths):
    # Real mount AND backing superblock, not chmod or read-only bind aliases.
    mounts=[]
    for line in Path("/proc/self/mountinfo").read_text().splitlines():
        fields=line.split()
        if len(fields)>6 and "-" in fields:
            index=fields.index("-")
            mounts.append((Path(fields[4].replace("\\040"," ").replace("\\134","\\")),
                           set(fields[5].split(",")),set(fields[index+3].split(","))))
    for text in paths:
        path=m.physical(text)
        covers=[x for x in mounts if path==x[0] or path.is_relative_to(x[0])]
        m.require(covers,"current source/runtime backing mount")
        _,options,superoptions=max(covers,key=lambda x:len(x[0].parts))
        m.require("ro" in options and "ro" in superoptions,
                  "actual immutable read-only backing, no writable alias")
def validate_launch(spec,review,price,launch):
    m.closed(launch,LAUNCH_KEYS,"closed new Python reference launch")
    m.require(launch["schema"]=="r201_owned_reference_launch_v1" and spec["role"] in ROLES,
              "new closed Python launch")
    same(launch,spec)
    m.require(launch["bootstrap"]==review["source_pins"]["native_python/python_bootstrap.py"],
              "fixed six-argument Python bootstrap")
    m.require(launch["traced_guard"]["sha256"]==TRACE_SHA,"unchanged original tracer")
    for key in ("native_executable","native_library","native_build_manifest","native_abi",
                "native_build_acceptance","native_deployment_acceptance","traced_guard"):
        m.descriptor(launch[key])
    for item in launch["baseline_files"]:m.descriptor(item)
    m.require(launch["native_executable"] in launch["baseline_files"]
              and launch["native_library"] in launch["baseline_files"]
              and launch["traced_guard"] in launch["baseline_files"],
              "complete Python ELF/library/tracer baseline")
    executable=str(Path("/proc/self/exe").resolve(strict=True))
    m.require(launch["native_executable"]["path"]==executable,"actual parent and child Python ELF")
    if spec["role"]==INITIAL:
        m.require(launch["native_build_acceptance"]==spec["build_acceptance"] and
                  launch["native_deployment_acceptance"]==spec["deployment_acceptance"],
                  "same initial source build/deployment prerequisites")
    else:
        boundary=load("owner/compute_boundary.py",review["source_pins"])
        qualified=boundary._qualification(spec["runtime_qualification"],spec)
        result=m.linked(qualified["result"])
        m.require(result.get("native_build_acceptance")==launch["native_build_acceptance"]
                  and result.get("native_deployment_acceptance")==launch["native_deployment_acceptance"],
                  "genuine production qualification covers new native build/deployment")
    contract=load("qualification/qualification_contract.py",review["source_pins"])
    contract.validate_native_prerequisites(spec,launch,review)
    allpaths=[p["path"] for p in review["source_pins"].values()]
    allpaths += [p["path"] for p in launch["baseline_files"]]
    allpaths += [launch["native_library"]["path"],launch["native_executable"]["path"]]
    readonly(allpaths)
    for p in launch["baseline_files"]:
        m.read_regular(p["path"],limit=64*1024**2,expected_sha=p["sha256"],expected_uid=os.getuid())
    env=launch["environment"]
    m.require(type(env) is dict and env.get("TZ")=="UTC" and
              env.get("SLURM_JOB_ID")==spec["job_id"] and env.get("SLURMD_NODENAME")==spec["node"]
              and all(env.get(key)=="1" for key in THREAD_KEYS) and
              not any(key in env for key in ("LD_PRELOAD","PYTHONPATH","PYTHONSTARTUP")),
              "fixed actual one-thread Python environment")
    for key in ("stdout_path","stderr_path","owned_tree_path","owned_guard_path","output_root"):
        path=m.absolute(launch[key])
        m.require(path.is_relative_to(m.absolute(spec["root"])),"new private output path")
    return launch
