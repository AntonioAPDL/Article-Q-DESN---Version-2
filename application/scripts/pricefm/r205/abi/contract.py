"""Closed ABI-control metadata and authenticated Common loader.

This module never imports FFI or loads a native artifact. Source/ASCII validation
does not acquire a context or manufacture an accepted ABI suite.
"""
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import stat
import sys
import time

ROOT=Path(__file__).absolute().parent.parent
COMMON_SHA="3090fb684b3c8796bc7754b036b5b4c3a1f92a92051f1ccc700e5d3d657900a7"
COMMON_NAME="_r203_control_contract"
STAGE="NATIVE_ABI_SUITE"
FILE_CAP=524288
CASES=(("pre_ack_live",False),("wrong_lifetime",False),("wrong_permit",False),
       ("late_transition",False),("repeat_transition",True),("real_ACK",True),
       ("live_rechecks",True),("noreplace_collision",True),("bounded_storage",True))
OP_KEYS={"operation","arguments","return_value","errno","first_error","started_epoch","finished_epoch","receipt"}
RESULT_KEYS={"schema","status","case_id","ordinal","descriptor","request","authority",
 "job_id","node","owner","child","runtime_map_sha256","control_map_sha256","native_role",
 "native_deadline_upper_bound_epoch","actual_native_expiry_epoch","expiry_derivation",
 "abi_probe","operations","observations","no_target_data","no_optimizer_or_fit"}
FRAME_KEYS={"schema","status","case_id","ordinal","descriptor","request","authority","job_id",
 "node","owner","child","runtime_map_sha256","control_map_sha256","native_library",
 "native_deadline_upper_bound_epoch","actual_native_expiry_epoch"}

def require(ok,why):
    if not ok:raise ValueError(why)

def closed(value,keys,label):
    require(type(value) is dict and set(value)==set(keys),"closed "+label)
    return value

def integer(value,low=0,high=2**63-1):
    require(type(value) is int and low<=value<=high,"bounded integer")
    return value

def epoch(value):
    require(type(value) in (int,float) and math.isfinite(value) and value>0,"finite epoch")
    return value

def strict_json(raw):
    def pairs(items):
        out={}
        for key,value in items:
            require(key not in out,"duplicate JSON key")
            out[key]=value
        return out
    def number(text):
        value=float(text);require(math.isfinite(value),"finite metadata number");return value
    return json.loads(raw,object_pairs_hook=pairs,parse_float=number,
      parse_constant=lambda _:(_ for _ in ()).throw(ValueError("nonfinite JSON")))

def physical(text):
    require(type(text) is str and text.startswith("/") and "\x00" not in text,"absolute physical path")
    path=Path(text)
    require(str(path)==text and ".." not in path.parts and
      not any(p.is_symlink() for p in (path,*path.parents)),"canonical nonsymlink path")
    return path

def captured(path,limit=2*1024**2):
    path=physical(str(path))
    with os.fdopen(os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK),"rb") as stream:
        a=os.fstat(stream.fileno())
        require(stat.S_ISREG(a.st_mode) and a.st_nlink==1 and a.st_uid in (0,os.getuid())
          and a.st_size<=limit,"bounded owned regular metadata/source")
        raw=stream.read(limit+1);b=os.fstat(stream.fileno())
    key=lambda s:(s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns,s.st_uid,s.st_nlink)
    require(len(raw)==a.st_size and key(a)==key(b)==key(path.stat()),"stable captured bytes")
    return raw

def pin(path,limit=2*1024**2):
    return {"path":str(physical(str(path))),"sha256":hashlib.sha256(captured(path,limit)).hexdigest()}

def linked(value):
    closed(value,{"path","sha256"},"pin")
    require(type(value["sha256"]) is str and re.fullmatch("[0-9a-f]{64}",value["sha256"]),"SHA256 pin")
    raw=captured(value["path"])
    require(hashlib.sha256(raw).hexdigest()==value["sha256"],"exact metadata pin")
    return strict_json(raw)

def common():
    path=ROOT/"common/contract.py";raw=captured(path)
    require(re.fullmatch("[0-9a-f]{64}",COMMON_SHA) is not None and
      hashlib.sha256(raw).hexdigest()==COMMON_SHA,"resolved exact Common source before interpretation")
    existing=sys.modules.get(COMMON_NAME)
    if existing is not None:
        require(existing.__file__==str(path) and
          getattr(existing,"_r203_source_sha256",None)==COMMON_SHA,"same authenticated Common module")
        return existing
    spec=importlib.util.spec_from_file_location(COMMON_NAME,path)
    module=importlib.util.module_from_spec(spec);sys.modules[COMMON_NAME]=module
    exec(compile(raw,str(path),"exec"),module.__dict__)
    module._r203_source_sha256=COMMON_SHA
    return module

def require_context(context):
    return common().require_context(context,STAGE)

def load_fixed(context,relative,name):
    context=require_context(context)
    require(relative in {"abi/native_abi.py","abi/contract.py"},"fixed ABI helper")
    record=context.control_sources[relative];path=ROOT/relative
    require(record["path"]==str(path),"fixed installed ABI source")
    raw=captured(path)
    require(hashlib.sha256(raw).hexdigest()==record["sha256"],"exact ABI helper bytes")
    old=sys.modules.get(name)
    if old is not None:
        require(old.__file__==str(path) and getattr(old,"_r203_source_sha256",None)==record["sha256"],
          "same fixed ABI helper instance")
        return old
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec)
    sys.modules[name]=module;exec(compile(raw,str(path),"exec"),module.__dict__)
    module._r203_source_sha256=record["sha256"]
    return module

def case_slots(case_id):
    require(case_id in {x[0] for x in CASES},"fixed case")
    names=["abi_"+case_id+".stdout","abi_"+case_id+".stderr","abi_"+case_id+".guard.json"]
    if case_id=="noreplace_collision":
        names+=["abi_noreplace_collision.partial","abi_noreplace_collision.final"]
    elif case_id=="bounded_storage":
        names+=["abi_bounded_storage.payload.partial","abi_bounded_storage.cap_probe.partial"]
    return names

def validate_policy_metadata(stage,storage_policy):
    """Pure descriptor checks; returns no context, grant or native evidence."""
    closed(stage,{"schema","native_library","native_abi","native_build_manifest","build_acceptance",
                  "deployment_acceptance","native_dependencies","subject_policy"},"ABI parameters")
    require(stage["schema"]=="r203_native_ABI_parameters_v1","ABI stage schema")
    policy=stage["subject_policy"]
    closed(policy,{"cases","founder","storage_slots"},"ABI subject policy")
    require(type(policy["cases"]) is list and len(policy["cases"])==9,"exact nine cases")
    for index,((case_id,handshake),row) in enumerate(zip(CASES,policy["cases"]),1):
        closed(row,{"case_id","ordinal","handshake","child_CPU_seconds","wall_seconds",
                    "native_deadline_rule"},"case policy")
        require(row["case_id"]==case_id and type(row["ordinal"]) is int and row["ordinal"]==index
          and type(row["handshake"]) is bool and row["handshake"] is handshake,"fixed order/handshake")
        integer(row["child_CPU_seconds"],1);integer(row["wall_seconds"],1)
        expected=({"kind":"PREP_READY_PLUS_SECONDS_WITH_FIXED_DESCRIPTOR_UPPER_BOUND",
                   "descriptor_window_seconds":30,"native_interval_seconds":2,"wait_margin_seconds":1}
                  if case_id=="late_transition" else {"kind":"STAGE_DEADLINE"})
        require(row["native_deadline_rule"]==expected,"fixed native expiry policy")
        if case_id=="late_transition":require(row["wall_seconds"]>=40,"late whole case wall")
    groups=policy["storage_slots"]
    require(set(groups)=={"founder","proof",*[x[0] for x in CASES]},"exact storage groups")
    rows={x["name"]:x for x in storage_policy["slots"]}
    expected_groups={"founder":["abi_founder_observation.json"]}
    expected_groups.update({case:case_slots(case) for case,_ in CASES})
    all_names=[]
    for group,names in expected_groups.items():
        item=groups[group]
        closed(item,{"slot_names","file_cap_bytes","slot_count","physical_reserved_bytes"},"slot group")
        require(item["slot_names"]==names and item["file_cap_bytes"]==FILE_CAP
          and type(item["slot_count"]) is int and item["slot_count"]==len(names)
          and item["physical_reserved_bytes"]==FILE_CAP*len(names),"fixed physical ABI slots")
        for name in names:require(rows[name]["maximum_bytes"]==FILE_CAP,"exact slot cap")
        all_names+=names
    require(len(all_names)==len(set(all_names))==32,"32 unique physical slots")
    require(rows["abi_bounded_storage.payload.partial"]["final_alias"]==
      "abi_bounded_storage.payload.final","sameinode native alias")
    require("abi_bounded_storage.payload.final" not in rows,"final alias not a second slot")
    proof=groups["proof"]
    closed(proof,{"slot_names","file_cap_bytes","slot_count","physical_reserved_bytes"},"proof group")
    require(len(proof["slot_names"])==len(set(proof["slot_names"]))==proof["slot_count"]
      and not(set(proof["slot_names"])&set(all_names)),"proof slots distinct")
    capacities=[rows[name]["maximum_bytes"] for name in proof["slot_names"]]
    require(proof["file_cap_bytes"]==max(capacities) and
      proof["physical_reserved_bytes"]==sum(capacities) and sum(capacities)>=32*1024**2,
      "heterogeneous exact common proof reservation")
    require(set(rows)==set(all_names)|set(proof["slot_names"]) and
      sum(x["maximum_bytes"] for x in rows.values())<=64*1024**2,"complete64MiB slot inventory")
    require("abi_case_catalog.json" in proof["slot_names"] and
      all("abi_descriptor_%02d.json"%n in proof["slot_names"] for n in range(1,10)),
      "fixed descriptor/catalog proof slots")
    return stage,policy

def policy(context):
    context=require_context(context)
    return validate_policy_metadata(context.parameters["stage"],
                                    context.parameters["common"]["storage_policy"])

def descriptor(context,case):
    context=require_context(context)
    now=time.time();deadline=(now+30 if case["case_id"]=="late_transition"
                             else context.stage_deadline_epoch)
    require(deadline+1<context.stage_deadline_epoch if case["case_id"]=="late_transition"
            else deadline==context.stage_deadline_epoch,"native upper bound fits fixed authority")
    return dict(schema="r203_control_subject_descriptor_v1",request=context.request_pin,
      authority=context.authority_pin,stage_claim=context.stage_claim_pin,
      case_id=case["case_id"],ordinal=case["ordinal"],owner=context.owner,
      job_id=context.job_id,node=context.node,root=str(context.root),permit_fd=context.permit_fd,
      native_deadline_epoch=deadline,issued_epoch=now,expires_epoch=context.stage_deadline_epoch)

def native_expiry_metadata(case_id,ready_epoch,ready_monotonic,upper,stage_deadline):
    """Pure bounded clock derivation; never a grant or actual native result."""
    epoch(ready_epoch);epoch(ready_monotonic);epoch(upper);epoch(stage_deadline)
    require(case_id in {x[0] for x in CASES} and upper<=stage_deadline,"fixed case/root expiry")
    if case_id=="late_transition":
        expiry=ready_epoch+2
        require(expiry+1<upper and expiry+1<stage_deadline,
          "INCONCLUSIVE late preparation window missed; no renewal")
        return expiry,dict(kind="PREP_READY_PLUS_SECONDS_WITH_FIXED_DESCRIPTOR_UPPER_BOUND",
          ready_epoch=ready_epoch,ready_monotonic=ready_monotonic,native_interval_seconds=2,
          wait_margin_seconds=1,descriptor_upper_bound_epoch=upper)
    require(upper==stage_deadline and ready_epoch<stage_deadline,"unchanged fullstage deadline")
    return stage_deadline,dict(kind="STAGE_DEADLINE",stage_deadline_epoch=stage_deadline)

def actual_identity():
    root=Path("/proc/self");text=(root/"stat").read_text();tail=text[text.rindex(")")+2:].split()
    status=dict(line.split(":",1) for line in (root/"status").read_text().splitlines() if ":" in line)
    return {"pid":os.getpid(),"start_ticks":int(tail[19]),"ppid":os.getppid(),
      "tracer_pid":int(status["TracerPid"]),"uid":os.getuid(),
      "boot_id":Path("/proc/sys/kernel/random/boot_id").read_text().strip()}

def ready_frame(context,descriptor_pin,expiry):
    context=require_context(context);stage,_=policy(context)
    return dict(schema="r203_ABI_subject_ready_v1",status="READY_BEFORE_REAL_NATIVE_TRANSITION_NOT_ACK",
      case_id=context.case_id,ordinal=context.ordinal,descriptor=descriptor_pin,
      request=context.request_pin,authority=context.authority_pin,job_id=context.job_id,node=context.node,
      owner=context.owner,child=actual_identity(),runtime_map_sha256=context.runtime_map_sha256,
      control_map_sha256=context.control_map_sha256,native_library=stage["native_library"],
      native_deadline_upper_bound_epoch=context.native_deadline_epoch,actual_native_expiry_epoch=expiry)

def operation_shape(row):
    closed(row,OP_KEYS,"actual native operation")
    require(type(row["operation"]) is str and type(row["arguments"]) is dict
      and type(row["return_value"]) is int and type(row["errno"]) is int,"typed actual native result")
    epoch(row["started_epoch"]);epoch(row["finished_epoch"])
    require(row["finished_epoch"]>=row["started_epoch"] and
      row["return_value"] in (0,-1),"ordered native return")
    if row["return_value"]==-1:
        require(row["errno"]==1 and type(row["first_error"]) is str and row["first_error"],
          "actual EPERM and first error")
    else:require(row["first_error"] is None,"success errno unspecified, no fabricated error")
    return row

def raw_result_shape(result):
    closed(result,RESULT_KEYS,"raw native subject result")
    require(result["schema"]=="r203_ABI_subject_raw_result_v1" and
      result["status"]=="RAW_NATIVE_SUBJECT_FACTS_NOT_ACCEPTED","raw facts only")
    integer(result["ordinal"],1,9)
    require(CASES[result["ordinal"]-1][0]==result["case_id"],"fixed case ordinal")
    require(type(result["operations"]) is list and result["operations"],"actual operations")
    for row in result["operations"]:operation_shape(row)
    require(result["no_target_data"] is True and result["no_optimizer_or_fit"] is True,
      "no scientific authority")
    return result
