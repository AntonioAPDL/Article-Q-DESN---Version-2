"""Pure source preparation, never job submission or authority creation."""
from __future__ import annotations
import hashlib,importlib.util,os,stat,sys
from pathlib import Path
_CONTROL_ROOT=Path(__file__).absolute().parent.parent
_COMMON_SHA="3090fb684b3c8796bc7754b036b5b4c3a1f92a92051f1ccc700e5d3d657900a7"
def _common():
    name="_r203_control_contract";path=_CONTROL_ROOT/"common/contract.py"
    if name in sys.modules:
        module=sys.modules[name]
        if getattr(module,"_r203_source_sha256",None)!=_COMMON_SHA or Path(module.__file__).absolute()!=path:
            raise ValueError("same authenticated Common source/module instance")
        return module
    if any(p.is_symlink() for p in (path,*path.parents)):raise ValueError("physical Common source")
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        before=os.fstat(fd)
        if not(stat.S_ISREG(before.st_mode) and before.st_nlink==1 and before.st_uid==os.getuid() and 0<before.st_size<=1024**2):
            raise ValueError("owned bounded Common source")
        raw=b""
        while len(raw)<=1024**2:
            block=os.read(fd,min(65536,1024**2+1-len(raw)))
            if not block:break
            raw+=block
        after=os.fstat(fd)
    finally:os.close(fd)
    key=lambda v:(v.st_dev,v.st_ino,v.st_size,v.st_mtime_ns,v.st_ctime_ns,v.st_mode,v.st_uid,v.st_nlink)
    if key(before)!=key(after) or key(after)!=key(path.lstat()) or len(raw)!=before.st_size or hashlib.sha256(raw).hexdigest()!=_COMMON_SHA:
        raise ValueError("authenticated captured Common bytes before interpretation")
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);sys.modules[name]=module
    exec(compile(raw,str(path),"exec"),module.__dict__);module._r203_source_sha256=_COMMON_SHA
    return module
c=_common()
m=c.m

import shlex,json,re
def render_bootstrap_script(startup_python,stage_owner,canonical_template_path,environment,exec_allowlist,output_path):
    for pin in (startup_python,stage_owner):m.descriptor(pin)
    m.absolute(canonical_template_path)
    m.require(Path(stage_owner["path"]).parts[-2:]==("common","stage_owner.py"),"fixed stage-owner source")
    c.validate_environment(environment)
    tools=[(path,sha) for path,sha in exec_allowlist.items() if Path(path).name=="sha256sum"]
    m.require(len(tools)==1,"one reviewed native startup hash tool")
    tool,toolsha=tools[0];m.descriptor({"path":tool,"sha256":toolsha})
    rows=['#!/bin/bash -p', 'set -eu', 'for r203_key in ${!A@} ${!B@} ${!C@} ${!D@} ${!E@} ${!F@} ${!G@} ${!H@} ${!I@} ${!J@} ${!K@} ${!L@} ${!M@} ${!N@} ${!O@} ${!P@} ${!Q@} ${!R@} ${!S@} ${!T@} ${!U@} ${!V@} ${!W@} ${!X@} ${!Y@} ${!Z@} ${!a@} ${!b@} ${!c@} ${!d@} ${!e@} ${!f@} ${!g@} ${!h@} ${!i@} ${!j@} ${!k@} ${!l@} ${!m@} ${!n@} ${!o@} ${!p@} ${!q@} ${!r@} ${!s@} ${!t@} ${!u@} ${!v@} ${!w@} ${!x@} ${!y@} ${!z@} ${!_@}; do', '  case "$r203_key" in SLURM_JOB_ID|SLURMD_NODENAME) ;; *) export -n "$r203_key" 2>/dev/null || :; unset "$r203_key" 2>/dev/null || : ;; esac', 'done']
    for key,value in sorted(environment.items()):
        m.require(type(key) is str and re.fullmatch("[A-Z][A-Z0-9_]*",key) and type(value) is str,"safe fixed environment")
        rows.append("export "+key+"="+shlex.quote(value))
    for pin in (startup_python,stage_owner):
        rows.append('test "$('+shlex.quote(tool)+" "+shlex.quote(pin["path"])+')" = '+shlex.quote(pin["sha256"]+"  "+pin["path"]))
    command=[startup_python["path"],"-I","-B",stage_owner["path"],canonical_template_path]
    rows+=["exec "+shlex.join(command),""]
    raw=chr(10).join(rows).encode("ascii");path=m.physical(output_path)
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,"wb") as f:f.write(raw);f.flush();os.fsync(f.fileno())
    return {"status":"RENDERED_R203_SOURCE_ONLY_NOT_SUBMITTED","script":{"path":str(path),"sha256":hashlib.sha256(m.read_regular(path,limit=65536,expected_uid=os.getuid())).hexdigest()},"jobs_submitted":0,
      "template_path":canonical_template_path,"template_SHA_absent_to_avoid_cycle":True}
def prepare(template_pin,output_root):
    t=m.linked(template_pin);checked=c.inspect_template_metadata(t)
    root=m.physical(output_root);m.require(root!=m.absolute(t["output_root"]),"cannot precreate future actual owner namespace")
    root.mkdir(mode=0o700);profile=checked["profile"]
    raw=m.read_regular(profile["job_script"]["path"],limit=65536,expected_sha=profile["job_script"]["sha256"],expected_uid=os.getuid())
    command=[t["parameters"]["common"]["startup_python"]["path"],"-I","-B",t["control_sources"]["common/stage_owner.py"]["path"],template_pin["path"]]
    m.require(raw.startswith(b"#!/bin/bash -p\n") and b"export -n" in raw and b"unset" in raw
      and ("exec "+shlex.join(command)).encode() in raw and template_pin["sha256"].encode() not in raw,
      "fixed reviewed PATH-only command with no admission/script hash cycle")
    result={"schema":"r203_prepared_stage_source_v1","status":"PREPARED_METADATA_ONLY_NO_JOB_OR_AUTHORITY",
      "template":template_pin,"script":profile["job_script"],"rendered_sbatch_argv":profile["rendered_sbatch_argv"],
      "runtime_admitted":False,"jobs_submitted":0}
    return m.write_new(root/"PREPARED.json",result)
