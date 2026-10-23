#!/usr/bin/env python3
"""Bounded R150 B1 prefix with source-preserving benchmark reuse.

This adapter composes the immutable ADD numerical functions. It never changes
their globals, repeats their benchmark, fits a model, or launches AL.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import resource
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
TAG = "pricefm_stage_r150_bounded_admission_20261023"
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
CONFIG = ROOT/"application/config"/(TAG+".json")
PREP = DATA/"launch_prep"/TAG
OUT = DATA/"campaigns"/TAG
_PRODUCER = None
_PREP_CACHE = {}
_COMPLETE_CACHE = {}


def read(path):
    return json.loads(Path(path).read_text())


def digest(path):
    h=hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b""):
            h.update(chunk)
    return h.hexdigest()


def fingerprint(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",",":"),allow_nan=False).encode()).hexdigest()


def write(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_name(path.name+"."+uuid.uuid4().hex+".tmp")
    temporary.write_text(json.dumps(value,sort_keys=True,indent=2,allow_nan=False)+"\n")
    os.replace(temporary,path)


def immutable(path,value):
    if Path(path).exists():
        if read(path)!=value:raise RuntimeError("immutable bounded record differs: "+str(path))
    else:write(path,value)


def verify_hashes(ledger):
    for p,h in ledger.items():
        if digest(p)!=h:raise RuntimeError("pinned original artifact changed: "+p)


def git(root,*args):
    return subprocess.check_output(["git",*args],cwd=root,text=True).strip()


def producer():
    global _PRODUCER
    c=read(CONFIG)
    if digest(c["producer_entry"])!=c["producer_entry_sha256"]:
        raise RuntimeError("immutable ADD numerical adapter changed")
    if _PRODUCER is None:
        spec=importlib.util.spec_from_file_location("r150_bounded_immutable_ADD",c["producer_entry"])
        _PRODUCER=importlib.util.module_from_spec(spec);spec.loader.exec_module(_PRODUCER)
    return _PRODUCER


def source_identity():
    c=read(CONFIG)
    if git(ROOT,"branch","--show-current")!=c["required_branch"] or git(ROOT,"status","--porcelain"):
        raise RuntimeError("clean committed dedicated bounded-admission source required")
    return dict(head=git(ROOT,"rev-parse","HEAD"),branch=c["required_branch"])


def validate_config(c):
    if (c.get("tag")!=TAG or c.get("producer_head")!="add35d3ea5df7397122bedf6509799cce634538c"
        or c.get("required_branch")!="work/pricefm-r150-bounded-admission-20261023"
        or c.get("branch")!="B1" or c.get("new_benchmark_authorized") is not False
        or c.get("numerical_waves")!=["1","2","3"] or c.get("new_model_fits")!=0
        or c.get("new_geometries")!=0 or c.get("AL_authorized") is not False
        or c.get("official_evaluation_authorized") is not False
        or c.get("extra_seed_admission")!="atomic_qualified_set_with_shared_control_if_cumulative_projection_fits_original_budget"
        or c.get("absolute_compute_CPU_ceiling")!=32400):
        raise ValueError("bounded prefix scope or original finite budget changed")
    return c


def names_for(packages,mode,seeds):
    return producer().component_names(packages,mode,seeds)


def projected(names,prices):
    return sum(prices[n]["estimated_cpu_seconds"] for n in dict.fromkeys(names))


def prefix_contract(prep,pricing):
    """Guarantee the whole D plus worst possible locked nominee seed0 prefix."""
    p=producer();packages=prep["packages"];control=prep["control"];negative=prep["negative_control"]
    ids=[v["package_id"] for v in packages];prices=pricing["task_estimates"]
    D=names_for(ids,"D",[0]);scenarios=[]
    key=p.read(p.CONFIG)["audit_key"]
    # Enumerate every prospectively possible A, preserving its actual fixed B.
    by_id={v["package_id"]:v for v in packages}
    order=p.audit_permutation(packages,key)
    for a in ids:
        if a==control:continue
        excluded={by_id[v]["candidate_id"] for v in (control,negative,a)}
        b=next(v for v in order if by_id[v]["candidate_id"] not in excluded)
        seed0=names_for([control,a,b],"S",[0])
        scenarios.append(dict(A=a,B=b,additional_seed0_CPU_seconds=projected(seed0,prices)))
    worst=max(scenarios,key=lambda v:(v["additional_seed0_CPU_seconds"],v["A"]))
    D_cpu=projected(D,prices);total=D_cpu+worst["additional_seed0_CPU_seconds"]
    budget=pricing["benchmark_adjusted_available_CPU_seconds"]
    return dict(branch="B1",D_CPU_seconds=D_cpu,worst_seed0_nomination=worst,
        worst_prefix_CPU_seconds=total,original_available_CPU_seconds=budget,
        prefix_admitted=total<=budget,all_prospective_seed0_scenarios=scenarios,
        no_losses_used=True,extra_seeds_conditioned_on_remaining_original_budget=True)


def extra_admission(prefix_names,qualifiers,control,prices,budget,completed_charges=None):
    """All qualified nominees share control extras; never replace/drop a lead."""
    extras=names_for(([control]+list(qualifiers)) if qualifiers else [],"S",[1,2])
    charges=completed_charges or {}
    prefix_cpu=sum(charges[n]["charged_CPU_seconds"] if n in charges else prices[n]["estimated_cpu_seconds"]
                   for n in dict.fromkeys(prefix_names))
    extra_cpu=projected(extras,prices)
    fits=prefix_cpu+extra_cpu<=budget
    return dict(qualified=list(qualifiers),required_extra_components=extras,
        admitted_extra_components=extras if fits else [],unfunded_pending=extras if not fits else [],
        prefix_projected_CPU_seconds=prefix_cpu,extra_projected_CPU_seconds=extra_cpu,
        cumulative_projected_CPU_seconds=prefix_cpu+extra_cpu,original_available_CPU_seconds=budget,
        completed_prefix_CPU_charges=charges,
        atomic_qualified_set_admitted=fits,rule="entire qualified set plus shared C0; no cost-based lead replacement",
        status="ADMITTED_MATCHED_EXTRAS" if fits else "DEFERRED_UNFUNDED_MATCHED_EXTRAS")


def charge_observations(estimate,observed_totals,missing_attempts=0):
    """Observed CPU plus5s per attempt; unknown attempts keep frozen reservation."""
    good=[];missing=missing_attempts
    for value in observed_totals:
        if isinstance(value,bool) or not isinstance(value,(float,int)) or not math.isfinite(value) or value<0:
            missing+=1
        else:good.append(float(value))
    if not good and not missing:missing=1
    charge=sum(v+5. for v in good)+missing*estimate
    return dict(charged_CPU_seconds=charge,observed_CPU_seconds=sum(good),
        observed_attempts=len(good),unknown_or_malformed_attempts=missing,
        tail_allowance_CPU_seconds_per_observed_attempt=5.,frozen_component_CPU_seconds=estimate,
        retained_full_frozen_reservation=bool(missing),observed_overrun=charge>estimate,
        hard_CPU_quota=False,exact_exit_CPU_measurement=False)


def start_CPU_attempt(task,prep,receipt,policy_path):
    invocation=receipt["worker_invocation_id"]
    folder=OUT/"cpu_accounting"/task["name"]/invocation
    value=dict(source=prep["source"],task=task["name"],scientific_identity_sha256=task["scientific_identity_sha256"],
        policy_invocation_id=invocation,policy_receipt_path=str(policy_path),policy_receipt_sha256=digest(policy_path),
        prior_started_invocations=sorted(v.parent.name for v in folder.parent.glob("*/started.json")),
        preexisting_checkpoint_count=len(list((OUT/"checkpoints"/task["name"]).glob("*/completed_evidence.json"))))
    immutable(folder/"started.json",value)
    return folder,value


def finish_CPU_attempt(folder,started,completed):
    children=resource.getrusage(resource.RUSAGE_CHILDREN)
    process=time.process_time();child=children.ru_utime+children.ru_stime
    value=dict(started,completed_component=completed,observed_process_CPU_seconds=process,
        observed_terminated_children_CPU_seconds=child,observed_total_CPU_seconds=process+child,
        task_final_seal_sha256=digest(OUT/"tasks_done"/started["task"]/"completed_evidence.json") if completed else None,
        observation_point="after strict task validation" if completed else "after sealed cooperative checkpoint stop",
        post_observation_exit_allowance_CPU_seconds=5.,hard_CPU_quota=False,exact_exit_CPU_measurement=False)
    immutable(folder/"observed.json",value)
    immutable(folder/"observed.seal.json",dict(sha256=digest(folder/"observed.json"),source=started["source"]))


def completed_CPU_charge(name,prep=None):
    prep=prep or read_preparation();task=task_by_name(name,prep)
    estimate=prep["pricing"]["task_estimates"][name]["estimated_cpu_seconds"]
    if task["reuse"]:return dict(charged_CPU_seconds=0.,imported_original_component=True,
        observed_CPU_seconds=0.,observed_attempts=0,unknown_or_malformed_attempts=0,credit_eligible=False,
        charge_rule="previous-stage imported component; no current-stage numerical work")
    if not task_complete(name):raise RuntimeError("CPU release requires a strictly completed scientific component")
    totals=[];errors=[];missing=0;final_observations=0;referenced=set()
    attempts=list((OUT/"cpu_accounting"/name).glob("*/started.json"))
    present_invocations={v.parent.name for v in attempts}
    for started_path in attempts:
        try:
            started=read(started_path);folder=started_path.parent
            prior=started.get("prior_started_invocations",[])
            if not isinstance(prior,list) or any(not isinstance(v,str) or not v or "/" in v or v in (".","..") for v in prior):
                raise RuntimeError("invalid earlier invocation provenance")
            referenced.update(prior)
            observed=read(folder/"observed.json")
            if (started.get("source")!=prep["source"] or started.get("task")!=name
                or started.get("scientific_identity_sha256")!=task["scientific_identity_sha256"]
                or started.get("policy_invocation_id")!=folder.name
                or any(observed.get(k)!=v for k,v in started.items())
                or read(folder/"observed.seal.json")!={"sha256":digest(folder/"observed.json"),"source":prep["source"]}
                or observed.get("post_observation_exit_allowance_CPU_seconds")!=5.
                or observed.get("hard_CPU_quota") is not False or observed.get("exact_exit_CPU_measurement") is not False):
                raise RuntimeError("CPU receipt source/task/seal/policy identity differs")
            if started.get("preexisting_checkpoint_count",0) and not started.get("prior_started_invocations"):
                raise RuntimeError("preexisting checkpoint work has no earlier owned CPU attempt provenance")
            verify_hashes({started["policy_receipt_path"]:started["policy_receipt_sha256"]})
            policy=read(started["policy_receipt_path"])
            if (policy.get("task")!=name or policy.get("source_head")!=prep["source"]["head"]
                or policy.get("worker_invocation_id")!=started["policy_invocation_id"]):
                raise RuntimeError("CPU receipt policy task/source/invocation differs")
            if type(observed.get("completed_component")) is not bool:
                raise RuntimeError("CPU receipt lacks exact completion state")
            if observed["completed_component"] and observed["task_final_seal_sha256"]!=digest(OUT/"tasks_done"/name/"completed_evidence.json"):
                raise RuntimeError("CPU receipt final prediction seal differs")
            process=observed["observed_process_CPU_seconds"];child=observed["observed_terminated_children_CPU_seconds"]
            total=observed["observed_total_CPU_seconds"]
            if any(isinstance(v,bool) or not isinstance(v,(float,int)) or not math.isfinite(v) or v<0 for v in (process,child,total)):
                raise RuntimeError("invalid observed CPU amount")
            if not math.isclose(process+child,total,rel_tol=1e-12,abs_tol=1e-10):raise RuntimeError("CPU receipt total differs")
            totals.append(total)
            final_observations+=int(observed["completed_component"])
        except Exception as error:
            missing+=1;errors.append(dict(attempt=str(started_path),error=repr(error)))
    missing_prior=sorted(referenced-present_invocations)
    missing+=len(missing_prior)
    if missing_prior:errors.append(dict(missing_prior_invocations=missing_prior,error="referenced earlier CPU attempt metadata is missing"))
    if not final_observations:
        # Surviving partial observations cannot account for the final attempt.
        # Keep at least one complete frozen reservation in addition to them.
        missing=max(1,missing)
        errors.append(dict(error="no validated completed CPU receipt bound to the current final prediction seal"))
    result=charge_observations(estimate,totals,missing)
    result.update(receipt_errors=errors,credit_eligible=bool(totals) and not missing and bool(final_observations),
        missing_prior_invocations=missing_prior,verified_final_CPU_receipts=final_observations,
        completed_receipts_bound_to_final_prediction_seal=bool(final_observations),
        charge_rule="sum observed whole-process plus terminated-child CPU +5s per known attempt; frozen estimate per unknown attempt")
    return result


def build_preparation(identity):
    c=validate_config(read(CONFIG));p=producer()
    verify_hashes(c["benchmark_import_pins"])
    receipt=read(c["benchmark_import"])
    verify_hashes(receipt["immutable_file_sha256"])
    old=p.read_preparation()
    if old["source"]["head"]!=c["producer_head"] or git(p.ROOT,"rev-parse","HEAD")!=c["producer_head"] or git(p.ROOT,"status","--porcelain"):
        raise RuntimeError("original ADD producer source changed")
    if (receipt.get("status")!="PASS_IMMUTABLE_ORIGINAL_BENCHMARK_IMPORT"
        or receipt.get("new_benchmark_lease_authorized") is not False
        or receipt.get("original_benchmark_calls")!=18 or receipt.get("old_numerical_leases_absent")!=["1","2","3"]
        or receipt.get("original_science_source",{}).get("head")!=c["producer_head"]):
        raise RuntimeError("original benchmark import contract differs")
    if any((Path(receipt["original_runtime"])/("wave_"+w)/"lease.json").exists() for w in ("1","2","3")):
        raise RuntimeError("original numerical waves must remain unadmitted")
    verify_hashes(old["source_sha256"]);verify_hashes(old["input_sha256"])
    p.original().parent_manifest(check_all=True)
    benchmark=Path(receipt["original_benchmark"]["folder"])
    seal=p.verify_packet(benchmark,{"timings.json","branch.json"})
    pricing=read(benchmark/"branch.json");timings=read(benchmark/"timings.json")
    if (pricing["source"]!=old["source"] or len(timings["rows"])!=18
        or timings.get("no_new_candidate_AQL_computed") is not True
        or pricing.get("no_new_candidate_AQL_inspected") is not True
        or pricing["finite_three_wave_CPU_ceiling"]!=32400
        or seal["context"]!={"source":old["source"],"preparation_sha256":digest(p.PREP/"preparation.json")}):
        raise RuntimeError("imported benchmark scientific/source/budget identity differs")
    result=dict(old)
    result.update(source=identity,config_sha256=digest(CONFIG),status="R150_BOUNDED_PREFIX_PREPARED_NOT_PROMOTED",
        immutable_numerical_producer=old["source"],benchmark_import=receipt,
        benchmark_import_sha256=digest(c["benchmark_import"]),pricing=pricing)
    result["source_sha256"]=dict(old["source_sha256"])
    for pattern in ("application/scripts/pricefm/*r150*.py","application/config/*r150*.json",
                    "application/tests/*r150*.py","docs/implementation_notes/*r150*.md"):
        result["source_sha256"].update({str(f):digest(f) for f in ROOT.glob(pattern)})
    result["input_sha256"]=dict(old["input_sha256"])
    result["input_sha256"].update(receipt["immutable_file_sha256"])
    result["input_sha256"].update(c["benchmark_import_pins"])
    result["prefix_contract"]=prefix_contract(result,pricing)
    if not result["prefix_contract"]["prefix_admitted"]:
        raise RuntimeError("entire mandatory D+seed0 prefix does not fit original finite budget")
    return result


def prepare():
    if (PREP/"prepared.json").exists():return read_preparation()
    result=build_preparation(source_identity())
    immutable(PREP/"preparation.json",result)
    for task in result["tasks"]:immutable(OUT/"tasks"/(task["name"]+".json"),task)
    immutable(PREP/"prepared.json",dict(source=result["source"],sha256=digest(PREP/"preparation.json")))
    return result


def read_preparation():
    paths=[PREP/"preparation.json",PREP/"prepared.json",CONFIG]
    signature=tuple((str(f),f.stat().st_mtime_ns,f.stat().st_ctime_ns,f.stat().st_size) for f in paths)
    if _PREP_CACHE.get("signature")==signature:return _PREP_CACHE["value"]
    result=read(paths[0]);seal=read(paths[1]);validate_config(read(CONFIG))
    if (seal!={"source":result["source"],"sha256":digest(paths[0])}
        or result["config_sha256"]!=digest(CONFIG) or result["source"]["head"]!=git(ROOT,"rev-parse","HEAD")
        or result["new_model_fits"]!=0 or len(result["tasks"])!=312):
        raise RuntimeError("bounded preparation/source seal differs")
    _PREP_CACHE.update(signature=signature,value=result);return result


def task_by_name(name,prep=None):
    prep=prep or read_preparation();p=producer()
    task=next((t for t in prep["tasks"] if t["name"]==name),None)
    if task is None or task["scientific_identity_sha256"]!=fingerprint(p.task_identity(task)):
        raise RuntimeError("unknown or altered bounded task")
    return task


def task_complete(name):
    prep=read_preparation();task=task_by_name(name,prep);p=producer()
    if read(OUT/"tasks"/(name+".json"))!=task:raise RuntimeError("immutable task differs")
    if task["reuse"]:p.validate_reuse(task);return True
    folder=OUT/"tasks_done"/name
    if not folder.exists():return False
    files=[folder/f for f in ("result.json","predictions.npz","completed_evidence.json")]
    files += [Path(task["scaler_path"]),Path(task["bank"]["path"])] + [Path(v) for v in task["parent_input_sha256"]]
    signature=(fingerprint(task),tuple((str(f),f.stat().st_mtime_ns,f.stat().st_ctime_ns,f.stat().st_size) for f in files))
    if _COMPLETE_CACHE.get(name)==signature:return True
    seal=p.verify_packet(folder,{"result.json","predictions.npz"})
    if seal.get("context")!=p.context_identity(task,prep) or seal.get("certified") is not True:
        raise RuntimeError("bounded component producer/source context differs")
    result=read(folder/"result.json")
    if (result.get("scientific_identity_sha256")!=task["scientific_identity_sha256"]
        or result.get("new_model_fits")!=0 or result.get("posterior_updated") is not False
        or result.get("test_opened") is not False or result.get("units")!="EUR/MWh"
        or result.get("mode")!=task["mode"] or result.get("origin_clock_windows")!=4*len(task["daily_origin_positions"])
        or not result.get("numerical_threadpools") or any(v["num_threads"]!=1 for v in result["numerical_threadpools"])):
        raise RuntimeError("bounded result scope/policy differs")
    verify_hashes(task["parent_input_sha256"])
    verify_hashes({task["scaler_path"]:task["scaler_sha256"],task["bank"]["path"]:task["bank"]["sha256"]})
    p.validate_arrays(task,p.read_npz(folder/"predictions.npz",headers_only=True),read(task["scaler_path"]),semantic=False)
    _COMPLETE_CACHE[name]=signature;return True


def component_loss(package,mode,seed=0):
    p=producer();values=[]
    for name in names_for([package],mode,[seed]):
        if not task_complete(name):raise RuntimeError("required component incomplete: "+name)
        task=task_by_name(name)
        measured=p.validate_reuse(task) if task["reuse"] else read(OUT/"tasks_done"/name/"result.json")["metrics"]
        value=measured["AQL"]
        if not math.isfinite(value) or value<0:raise RuntimeError("invalid retained AQL")
        values.append(value)
    return sum(values)/3


def write_decision(name,value):
    immutable(OUT/"decisions"/(name+".json"),value)
    immutable(OUT/"decisions"/(name+".seal.json"),dict(sha256=digest(OUT/"decisions"/(name+".json")),source=read_preparation()["source"]))


def read_decision(name):
    path=OUT/"decisions"/(name+".json")
    if read(OUT/"decisions"/(name+".seal.json"))!={"sha256":digest(path),"source":read_preparation()["source"]}:
        raise RuntimeError("bounded immutable decision differs")
    return read(path)


def manifest_state():
    prep=read_preparation();ids=[v["package_id"] for v in prep["packages"]]
    names=names_for(ids,"D",[0])
    if not all(task_complete(n) for n in names):return "DETERMINISTIC_POOL",names,[],False
    if not (OUT/"decisions/nominees.seal.json").exists():return "NOMINATION_REQUIRED",names,[],False
    nominees=read_decision("nominees")["nominees"]
    if len(nominees)!=2 or len(set(nominees))!=2 or any(v not in ids or v==prep["control"] for v in nominees):
        raise RuntimeError("bounded nominee allocation differs")
    names=list(dict.fromkeys(names+names_for([prep["control"]]+nominees,"S",[0])))
    if not all(task_complete(n) for n in names):return "NOMINEE_SEED0",names,[],False
    if not (OUT/"decisions/extra_seeds.seal.json").exists():return "EXTRA_SEED_DECISION_REQUIRED",names,[],False
    extra=read_decision("extra_seeds")
    if any(v not in nominees for v in extra["qualified"]):raise RuntimeError("qualified set changed")
    names=list(dict.fromkeys(names+extra["required_extra_components"]))
    if extra["unfunded_pending"]:return "MATCHED_MC_UNFUNDED_PENDING",names,extra["unfunded_pending"],False
    if not all(task_complete(n) for n in names):return "MATCHED_FULL_MC",names,[],False
    return "READY_FOR_ASSESSMENT",names,[],True


def queue_state():
    prep=read_preparation();phase,names,unfunded,terminal=manifest_state()
    complete=[n for n in names if task_complete(n)];pending=[n for n in names if n not in complete]
    prices=prep["pricing"]["task_estimates"]
    ready=[dict(name=n,kind=task_by_name(n,prep)["kind"],**{k:prices[n][k] for k in
        ("estimated_cpu_seconds","estimated_wall_seconds","estimated_max_chunk_wall_seconds")})
        for n in pending if n not in unfunded]
    return dict(phase=phase,ready=ready,pending=pending,complete=complete,total=len(names),terminal=terminal,
        unfunded_pending=unfunded,scientific_complete=(OUT/"assessment.json").exists(),new_model_fits=0,
        resource_projection=prep["pricing"]["resource_projection"],benchmark_imported=True,promotion_authorized=False)


def advance():
    prep=read_preparation();p=producer();phase,names,_,_=manifest_state()
    if phase=="NOMINATION_REQUIRED":
        losses={v["package_id"]:component_loss(v["package_id"],"D") for v in prep["packages"]}
        rule=p.choose_nominees(prep["packages"],losses,prep["control"],prep["negative_control"],p.read(p.CONFIG)["audit_key"])
        if rule["audit_order"]!=prep["frozen_audit_permutation"]:raise RuntimeError("frozen audit order changed")
        write_decision("nominees",dict(nominees=[rule["A"],rule["B"]],rule=rule,nomination_losses=losses,source=prep["source"]))
    elif phase=="EXTRA_SEED_DECISION_REQUIRED":
        nominees=read_decision("nominees")["nominees"]
        control=component_loss(prep["control"],"S");gains={v:control-component_loss(v,"S") for v in nominees}
        trigger=.5*p.practical_margin(control);qualified=[v for v in nominees if gains[v]>=trigger]
        decision=extra_admission(names,qualified,prep["control"],prep["pricing"]["task_estimates"],
            prep["pricing"]["benchmark_adjusted_available_CPU_seconds"],
            completed_charges={n:completed_CPU_charge(n,prep) for n in names})
        decision.update(seed0_gains=gains,seed0_control_AQL=control,exploration_trigger=trigger,source=prep["source"])
        write_decision("extra_seeds",decision)
    return queue_state()


def guard(cpu,receipt_path,name):
    receipt=read(receipt_path);prep=read_preparation()
    if (receipt.get("schema_version")!=1 or receipt.get("stage")!="R150" or receipt.get("task")!=name or receipt.get("cpu")!=cpu
        or receipt.get("source_head")!=prep["source"]["head"] or receipt.get("lease_expires_epoch",0)<=time.time()
        or receipt.get("expected_affinity")!=[cpu] or receipt.get("expected_scheduler")!=5
        or receipt.get("numerical_threads")!=1 or receipt.get("io_class")!=3
        or not receipt.get("worker_invocation_id") or not receipt.get("worker_cgroup")
        or not receipt.get("unit") or not receipt.get("probe_id") or not receipt.get("actual_probe")):
        raise RuntimeError("bounded worker policy receipt differs")
    if cpu not in range(15,30) or os.sched_getaffinity(0)!={cpu} or os.sched_getscheduler(0)!=os.SCHED_IDLE:
        raise RuntimeError("bounded numeric worker requires one physical CPU15–29 and idle scheduling")
    if not subprocess.check_output(["ionice","-p",str(os.getpid())],text=True).startswith("idle"):
        raise RuntimeError("idle I/O required")
    paths={line.split(":",2)[2] for line in Path("/proc/self/cgroup").read_text().splitlines()}
    if receipt.get("worker_cgroup") not in paths or receipt.get("worker_invocation_id")!=os.environ.get("INVOCATION_ID"):
        raise RuntimeError("actual owned unit cgroup/invocation differs")
    proof=receipt.get("actual_probe",{});props=proof.get("properties",{});proc=proof.get("process",{})
    if (props.get("Id")!=receipt.get("unit") or props.get("InvocationID")!=receipt.get("worker_invocation_id")
        or props.get("ControlGroup")!=receipt.get("worker_cgroup") or proc.get("scheduler")!=5
        or proc.get("affinity")!=[cpu] or props.get("IOSchedulingClass")!="3"):
        raise RuntimeError("actual unit policy proof differs")
    for key in ("OPENBLAS_NUM_THREADS","OMP_NUM_THREADS","MKL_NUM_THREADS","BLIS_NUM_THREADS","NUMEXPR_NUM_THREADS","VECLIB_MAXIMUM_THREADS"):
        if os.environ.get(key)!="1":raise RuntimeError("single numerical thread environment required")
    verify_hashes(prep["source_sha256"]);source_identity();return receipt


def checkpoint(prep,task,descriptor,context,beat):
    import numpy as np
    p=producer();folder=OUT/"checkpoints"/task["name"]/descriptor["name"]
    identity=dict(context=p.context_identity(task,prep),descriptor=descriptor)
    if folder.exists():
        seal=p.verify_packet(folder,{"chunk.json","predictions.npz"})
        if seal.get("identity")!=identity or seal.get("certified") is not True:raise RuntimeError("checkpoint context differs")
        p.validate_arrays(task,p.read_npz(folder/"predictions.npz"),context["scaler"],descriptor)
        with np.load(folder/"predictions.npz",allow_pickle=False) as packet:return {k:packet[k] for k in packet.files}
    started=time.monotonic();cpu0=time.process_time();beat(dict(status="chunk_running",chunk=descriptor["name"]))
    prediction,truth,audit=p.predict(context,task,descriptor,beat)
    arrays=p.retained_arrays(context,task,descriptor,prediction,truth)
    p.validate_arrays(task,p.light(arrays),context["scaler"],descriptor)
    attempt=OUT/"attempts"/task["name"]/(descriptor["name"]+"."+uuid.uuid4().hex);attempt.mkdir(parents=True)
    np.savez_compressed(attempt/"predictions.npz",**arrays)
    write(attempt/"chunk.json",dict(identity=identity,sampler_audit=audit,numerical_threadpools=p.kernel().numerical_threadpools(),
        elapsed_seconds=time.monotonic()-started,cpu_seconds=time.process_time()-cpu0,new_model_fits=0,posterior_updated=False))
    write(attempt/"completed_evidence.json",dict(identity=identity,certified=True,
        artifacts={v:digest(attempt/v) for v in ("chunk.json","predictions.npz")}))
    folder.parent.mkdir(parents=True,exist_ok=True);os.rename(attempt,folder)
    beat(dict(status="chunk_sealed",chunk=descriptor["name"]));return arrays


def worker(name,cpu,policy_receipt):
    if name=="__benchmark__":raise RuntimeError("bounded successor forbids a new benchmark")
    receipt=guard(cpu,policy_receipt,name)
    prep=read_preparation();p=producer();task=task_by_name(name,prep)
    cpu_folder,cpu_started=start_CPU_attempt(task,prep,receipt,policy_receipt)
    import numpy as np
    if task_complete(name):
        finish_CPU_attempt(cpu_folder,cpu_started,True);return dict(status="already_complete",name=name)
    if name not in [t["name"] for t in queue_state()["ready"]]:raise RuntimeError("task is not funded/admitted")
    locks=OUT/"locks";locks.mkdir(parents=True,exist_ok=True)
    with (locks/(name+".lock")).open("w") as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        def beat(event):write(OUT/"heartbeats"/(name+".json"),dict(event,epoch=time.time(),pid=os.getpid(),cpu=cpu,task=name))
        beat(dict(status="context_loading"));context=p.numerical_context(prep,task);parts=[]
        for descriptor in p.chunks(task):
            if time.time()>=receipt["lease_expires_epoch"] or (Path(policy_receipt).parent/"stop_requests"/(name+".json")).exists():
                beat(dict(status="cooperative_checkpoint_stop"));finish_CPU_attempt(cpu_folder,cpu_started,False)
                return dict(status="deferred_at_checkpoint",name=name)
            parts.append(checkpoint(prep,task,descriptor,context,beat))
        arrays={k:np.ascontiguousarray(np.concatenate([v[k] for v in parts]),dtype="<i8" if k in p.INT_KEYS else "<f8") for k in p.array_shapes(1)}
        p.validate_arrays(task,p.light(arrays),context["scaler"]);verify_hashes(task["parent_input_sha256"])
        verify_hashes({task["bank"]["path"]:task["bank"]["sha256"],task["scaler_path"]:task["scaler_sha256"]})
        result=dict(name=name,source=prep["source"],certified=True,mode=task["mode"],
            scientific_identity_sha256=task["scientific_identity_sha256"],units="EUR/MWh",metrics=p.metrics(p.light(arrays)),
            origin_clock_windows=len(arrays["origin_positions"]),numerical_threadpools=p.kernel().numerical_threadpools(),
            new_model_fits=0,posterior_updated=False,test_opened=False,promotion_authorized=False)
        attempt=OUT/"attempts"/name/("final."+uuid.uuid4().hex);attempt.mkdir(parents=True)
        np.savez_compressed(attempt/"predictions.npz",**arrays);write(attempt/"result.json",result)
        write(attempt/"completed_evidence.json",dict(context=p.context_identity(task,prep),certified=True,
            artifacts={v:digest(attempt/v) for v in ("result.json","predictions.npz")}))
        target=OUT/"tasks_done"/name;target.parent.mkdir(parents=True,exist_ok=True)
        if target.exists():raise RuntimeError("existing unverified packet requires review")
        os.rename(attempt,target)
        if not task_complete(name):raise RuntimeError("sealed task failed strict completion")
        finish_CPU_attempt(cpu_folder,cpu_started,True)
        beat(dict(status="completed"));return result


def finalize():
    prep=read_preparation();p=producer();phase,names,unfunded,terminal=manifest_state()
    if not terminal or unfunded:raise RuntimeError("scientific stage incomplete: "+phase)
    verify_hashes(prep["source_sha256"]);verify_hashes(prep["input_sha256"])
    verification=[]
    for name in names:
        if not task_complete(name):raise RuntimeError("strict component missing")
        task=task_by_name(name,prep)
        arrays=p.imported_arrays(task) if task["reuse"] else p.read_npz(OUT/"tasks_done"/name/"predictions.npz")
        p.validate_arrays(task,arrays,read(task["scaler_path"]));measured=p.metrics(arrays)
        recorded=p.validate_reuse(task) if task["reuse"] else read(OUT/"tasks_done"/name/"result.json")["metrics"]
        if any(not math.isclose(measured[k],recorded[k],rel_tol=1e-11,abs_tol=1e-10) for k in measured):raise RuntimeError("independent metric differs")
        verification.append(dict(name=name,metrics=measured,imported=bool(task["reuse"])))
    extra=read_decision("extra_seeds");confirmed={}
    if extra["qualified"]:
        control=[component_loss(prep["control"],"S",s) for s in (0,1,2)]
        for nominee in extra["qualified"]:
            candidate=[component_loss(nominee,"S",s) for s in (0,1,2)]
            confirmed[nominee]=dict(p.confirm_gains(control,candidate),control_AQL_by_seed=control,candidate_AQL_by_seed=candidate)
    eligible={v:-confirmed[v]["mean_gain"] for v in confirmed if confirmed[v]["eligible_for_AL_proposal"]}
    lead=p.strongest(eligible) if eligible else None
    proposal=None
    if lead:
        package=next(v for v in prep["packages"] if v["package_id"]==lead)
        actual=next(v for v in prep["packages"] if v["package_id"]==prep["control"])
        proposal=dict(package_id=lead,new_candidate_fits_if_exact_identity_reused=0 if package["candidate_id"]==actual["candidate_id"] else 21,
            new_control_fits_authorized=False,forecast_components=18,paths=500,default_iterations=300,
            operator="cdf_pool_clipped",same_package_Normal_driver_and_AL_receiver=True,launched=False,separate_budget_required=True)
    result=dict(status="R150_BOUNDED_SCIENTIFICALLY_COMPLETE_NOT_PROMOTED",source=prep["source"],branch="B1",
        required_components=len(names),verified_components=len(verification),verification=verification,
        nominations=read_decision("nominees"),extra_seed_decision=extra,matched_three_seed_results=confirmed,
        conditional_AL_proposal=proposal,new_model_fits=0,new_benchmark_runs=0,official_test_opened=False,
        independent_confirmation=False,automatic_followon_admitted=False,
        disposition=("ONE_CONDITIONAL_AL_PROPOSAL_NOT_ADMITTED" if lead else
            "HOLD_ALGORITHMIC_STABILITY_UNRESOLVED" if any(v["practical_gain"] and v["algorithmic_stability_unresolved"] for v in confirmed.values())
            else "STOP_NO_QUALIFYING_STABLE_CONFIRMED_LEAD"))
    immutable(OUT/"assessment.json",result)
    immutable(OUT/"assessment_seal.json",dict(sha256=digest(OUT/"assessment.json"),source=prep["source"]))
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest="action",required=True)
    for name in ("prepare","status","advance","finalize"):sub.add_parser(name)
    w=sub.add_parser("worker");w.add_argument("--task",required=True);w.add_argument("--cpu",type=int,required=True);w.add_argument("--policy-receipt",type=Path,required=True)
    args=parser.parse_args()
    if args.action=="prepare":
        prep=prepare();result=dict(source=prep["source"],prefix_contract=prep["prefix_contract"],new_model_fits=0)
    elif args.action=="status":result=queue_state()
    elif args.action=="advance":result=advance()
    elif args.action=="finalize":result=finalize()
    else:result=worker(args.task,args.cpu,args.policy_receipt)
    print(json.dumps(result,sort_keys=True,indent=2,allow_nan=False))


if __name__=="__main__":main()
