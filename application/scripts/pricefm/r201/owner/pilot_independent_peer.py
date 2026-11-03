"""Independently authored two-phase pilot/reference metadata peer.

Actual PASS requires applicable published source, accepted runtime qualification,
measured price/funding and fresh actual guarded observations. Pure metadata
inspection returns no admission. This module issues no Root authority or job.
"""
import hashlib
import importlib.util
import os
from pathlib import Path
import re
import time

_mp = Path(__file__).absolute().with_name("metadata.py")
if any(x.is_symlink() for x in (_mp, *_mp.parents)):
    raise ValueError("physical fixed metadata helper")
_raw = _mp.read_bytes()
if hashlib.sha256(_raw).hexdigest() != "6593a6bbb617375029bee0c692e510cd5621662eaf9fab46445eab433ff0762b":
    raise ValueError("exact independent peer metadata helper")
_ms = importlib.util.spec_from_file_location("_r200_peer_metadata", _mp)
m = importlib.util.module_from_spec(_ms)
exec(compile(_raw, str(_mp), "exec"), m.__dict__)

LIMITS = dict(beta_posterior_sd_rms=1e-4, covariance_whitened_rms=1e-4,
              elbo_relative=1e-8, predictor_rms=1e-6, rhs_joint_log_rates=1e-6,
              rhs_start_log_precision=1e-6, sigma_relative=1e-6)
CASE = dict(target="iq_NO_3_r134_283a8c333135aae3_t2.291521491921e-03_s1_al0.75",
            n=48576,p=417,tau=.75,tau0=.0022915214919211734,max_iter=300,
            seed=819509105,max_rhs_iter=20000,tol=1e-5,n_samp=20,n_samp_xi=20,
            maximum_pilot_attempts=1,maximum_optimizer_invocations=1,
            units="original_design_and_response",exact_optimizer_resume=False,
            prior=dict(family="rhs_ns",center="zero",shrink_intercept=False,
                       sigma_a=1.0,sigma_b=1.0,freeze_tau_iters=0,freeze_tau_warmup_iters=0),
            acceptance="finite AND(formal OR independent)",limits=LIMITS,
            both_RHS_starts=True,official_test_selection=False)
SPEC = {"schema","purpose","nonce","role","job_id","node","uid","affinity","root","owner",
        "case","case_sha256","source_map_sha256","owner_launch","source_publication","scope",
        "ledger","input_manifest","price","runtime_qualification","acknowledgement_path",
        "resource_lock_fd","resource_lock_path","attempt_claim_path","issued_epoch","expires_epoch",
        "role_request","scientific_source","controller_source","scientific_sources",
        "source_pins","runtime_owner","input_provenance"}
BUNDLE = {"schema","spec","source_publication","source_pins","source_observation_guard",
          "physical_admission","physical_observation_guard","owner_ready","ready_observation_guard",
          "accepted_bridge_request","proof_aliases"}
READY = {"schema","status","purpose","nonce","role","job_id","node","uid","owner",
         "resource_lock_fd","resource_lock_path","root","case_sha256","source_map_sha256",
         "source_publication","scope","ledger","price","runtime_qualification",
         "physical_admission","created_epoch","expires_epoch"}
BRIDGE = {"accepted","outer_accept_guard","result","accounting","independent_review",
          "full_return_manifest","finalization","bridge_validation","factor_state","baseline_certificate"}
IDENTITY = ("purpose","nonce","role","job_id","node")
FUNDING = ("source_publication","runtime_qualification","price","scope","ledger")

def _exact(a,b,label):
    m.require(type(a) is type(b),label+": exact type")
    if isinstance(b,dict):
        m.closed(a,b,label)
        for k in b:_exact(a[k],b[k],label+"."+k)
    elif isinstance(b,list):
        m.require(len(a)==len(b),label+": exact length")
        for x,y in zip(a,b):_exact(x,y,label)
    else:m.require(a==b,label+": exact value")

def _same(record,spec):
    for key in IDENTITY:m.require(record.get(key)==spec[key],"same current "+key)

def _fresh(record,key,now,seconds):
    m.finite(record.get(key),key)
    m.require(0<=now-record[key]<=seconds,"fresh actual "+key)

SCIENCE_HASHES = {
 "application/R/pricefm_r129_al_fixedpoint_certificate.R":"c573066109eef78cd19e8c60f2630ecad29d433ae9d95150d0a0fe4f7ee21571",
 "application/R/524_toy_fullstate_consumer.R":"0d17bb507281ca96f17a8ea2f8a60cebcba11ccee846ed666d3127321ad2df9a",
 "application/R/525_project_fullstate_consumer.R":"57566e90f15ec8c44c72800d79ba3c2979f78a9c4799a154cf542a7f627c11b2",
 "application/tests/r179_hb_toy.R":"662a48dbed4908b563ff9c24ea0e74fa35ee8cbe406ee1e973b40ed8ea77b190",
 "application/scripts/pricefm/r179_hb_bridge_or_pilot.R":"1f1d3e500ec8310f1d9724b61bdd72273b36feff53ba903d9a63b3d3a694b1f3"}
REFERENCE_CASES={
 "LT":dict(target="LT_fold1_al0.90",n=90240,p=337,seed=710583720,tau="0.9",tau0="2.5682335211342966e-05"),
 "NO4_PRIMARY":dict(target="iq_NO_4_r134_20feba695ede3ad5_t9.653643731923e-05_s1_al0.50",n=48576,p=961,seed=1149227177,tau="0.5",tau0="9.653643731923241e-05"),
 "NO4_CONTROL":dict(target="iq_NO_4_r134_20feba695ede3ad5_t9.653643731923e-06_s1_al0.50",n=48576,p=961,seed=1149227177,tau="0.5",tau0="9.653643731923241e-06")}

def _science_binding(spec,request=None):
    science=spec["scientific_sources"]
    m.closed(science,SCIENCE_HASHES,"exact five original logical scientific files")
    for name,expected in SCIENCE_HASHES.items():
        m.descriptor(science[name])
        m.require(science[name]["sha256"]==expected,"unchanged original scientific bytes "+name)
    m.require(len({pin["path"] for pin in science.values()})==5,"unique physical original science aliases")
    source=spec["scientific_source"]
    m.closed(source,{"kind","head","branch"},"whole accepted scientific identity")
    m.require(type(source["kind"]) is str and source["kind"] and
              type(source["head"]) is str and re.fullmatch("[0-9a-f]{40}",source["head"]) and
              type(source["branch"]) is str and source["branch"].startswith("work/pricefm-"),
              "preserved complete accepted bridge scientific source")
    if request is not None:
        m.require(request.get("schema")=="r200_pilot_owned_io_request_v1"
                  and all(request.get(k)==spec[k] for k in ("purpose","nonce","role","scientific_source","controller_source")),
                  "same immutable I/O source and purpose identities")
        _exact(request.get("case"),CASE,"I/O request same fixed pilot case")
        pins=request.get("science_source_pins")
        m.require(type(pins) is list and len(pins)==5,"exact I/O physical science set")
        for pin in pins:m.descriptor(pin)
        m.require(len({pin["path"] for pin in pins})==5 and
                  sorted((pin["path"],pin["sha256"]) for pin in pins)==
                  sorted((pin["path"],pin["sha256"]) for pin in science.values()),
                  "I/O physical science pins exactly equal explicit old logical mapping")
        context=request.get("scientific_context")
        m.require(type(context) is dict and
                  context.get("fixedpoint_helper")==science["application/R/pricefm_r129_al_fixedpoint_certificate.R"]
                  and context.get("project_consumer")==science["application/R/525_project_fullstate_consumer.R"],
                  "actual helper and consumer retain their original logical identities")
    return {"status":"CONSISTENT_ORIGINAL_SCIENTIFIC_DESCRIPTORS_NOT_RUNTIME_AUTHORITY",
            "runtime_admitted":False}

def _reference_case(case):
    keys={"schema","case","target","n","p","seed","tau","tau0","protocol_sha256","precision_schedule",
          "units","prior","input_names","objective_mode","binary_layout","optimizer_updates","original_limits",
          "both_RHS_starts","original_failed_states_unchanged","target_construction"}
    m.closed(case,keys,"closed independent reference v2 case")
    m.require(case["schema"]=="r200_regional_reference_request_v2" and case["case"] in REFERENCE_CASES,
              "explicit corrected reference request version")
    for key,value in REFERENCE_CASES[case["case"]].items():_exact(case[key],value,"fixed reference "+key)
    _exact(case["binary_layout"],{"dtype":"IEEE754_binary64","endian":"little",
           "precision_matrix_order":"column_major","candidate_covariance_order":"column_major",
           "design_matrix_order":"row_major"},"independent exact original binary layouts")
    _exact(case["precision_schedule"],[80,120,160],"fixed independent precision schedule")
    _exact(case["original_limits"],LIMITS,"reference original limits")
    _exact(case["optimizer_updates"],0,"zero reference updates")
    _exact(case["both_RHS_starts"],True,"both original RHS starts")
    _exact(case["original_failed_states_unchanged"],True,"old failed states preserved")
    _exact(case["prior"],dict(family="rhs_ns",center="zero",shrink_intercept=False,sigma_a=1,
           sigma_b=1,freeze_tau_iters=0,freeze_tau_warmup_iters=0),"original reference prior")
    m.require(case["protocol_sha256"]=="720f7ba5ffb886866f807a4a7ae63c8a99acc56bf194688144dc5a19df022118"
              and case["units"]=="original_design_and_response","exact prior protocol and original units")
    m.require(case["objective_mode"] in {"GAUSSIAN_ONLY","EXPLICIT_IMPORTED_FULL_FACTORS"},"closed reference objective mode")
    wanted={"precision","rhs","candidate_beta","candidate_covariance"}
    if case["objective_mode"]=="EXPLICIT_IMPORTED_FULL_FACTORS":wanted|={"design","response","factor_snapshot"}
    m.closed(case["input_names"],wanted,"exact named reference input set")
    names=list(case["input_names"].values())
    m.require(all(type(x) is str and re.fullmatch("[A-Za-z][A-Za-z0-9_]{0,63}",x) for x in names)
              and len(set(names))==len(names),"one-to-one declared reference input names")
    target=case["target_construction"]
    m.closed(target,{"arithmetic","precision_rhs_identity","source_recipe_sha256","independent_error_bound_earned"},
             "exact reference construction question")
    m.require(target["arithmetic"]=="EXACT_EXISTING_OR_OWNED_RECONSTRUCTED_BINARY64"
              and target["independent_error_bound_earned"] is False,"no unearned full-target bound")
    m.closed(target["precision_rhs_identity"],{"precision_sha256","rhs_sha256"},"separate P and RHS identities")
    for digest in [target["source_recipe_sha256"],*target["precision_rhs_identity"].values()]:
        m.require(type(digest) is str and re.fullmatch("[0-9a-f]{64}",digest),"exact target/source byte identity")
    return {"status":"CONSISTENT_REFERENCE_CASE_NOT_EXECUTION_AUTHORITY","runtime_admitted":False}

def inspect_spec_metadata(spec):
    role=spec.get("role")
    m.require(role in {"NO3_AL300_PILOT","LT_NO4_REFERENCE"},"separate supported role")
    key="io_request" if role=="NO3_AL300_PILOT" else "reference_request"
    m.closed(spec,SPEC|{key},"closed independently reviewed spec")
    m.require(spec["schema"]=="r200_owned_compute_spec_v1","new spec schema")
    m.require(type(spec["purpose"]) is str and re.fullmatch("[A-Za-z0-9_]{1,96}",spec["purpose"])
              and type(spec["nonce"]) is str and re.fullmatch("[0-9a-f]{32}",spec["nonce"]),"new purpose nonce")
    m.require(type(spec["job_id"]) is str and re.fullmatch("[1-9][0-9]{0,11}",spec["job_id"])
              and type(spec["node"]) is str and re.fullmatch("node-[0-9]{2}",spec["node"]),"exact job node")
    m.require(type(spec["uid"]) is int and spec["uid"]==os.getuid(),"current UID")
    m.closed(spec["owner"],{"pid","start_ticks","boot_id"},"owner")
    m.integer(spec["owner"]["pid"],"owner pid",2)
    m.integer(spec["owner"]["start_ticks"],"owner birth",1)
    m.require(type(spec["owner"]["boot_id"]) is str and
              re.fullmatch("[0-9a-f-]{36}",spec["owner"]["boot_id"]),"owner boot")
    m.require(type(spec["affinity"]) is list and len(spec["affinity"])==1,"one physical CPU")
    m.integer(spec["affinity"][0],"physical CPU",0)
    for k in ("root","acknowledgement_path","resource_lock_path","attempt_claim_path"):m.absolute(spec[k])
    m.integer(spec["resource_lock_fd"],"inherited resource lock fd",3)
    for k in ("issued_epoch","expires_epoch"):m.finite(spec[k],k)
    m.require(0<spec["expires_epoch"]-spec["issued_epoch"]<=28800,"fixed <=8h purpose")
    m.require(spec[key]==spec["role_request"],"one exact immutable role request")
    for k in (*FUNDING,"owner_launch","input_manifest","role_request","input_provenance"):m.descriptor(spec[k])
    m.require(spec["controller_source"]==spec["source_publication"],"controller publication identity")
    m.require(m.digest(spec["case"])==spec["case_sha256"],"case canonical identity")
    m.require(type(spec["source_pins"]) is dict and spec["source_pins"],"complete source pins")
    hashes={}
    for relative,pin in spec["source_pins"].items():
        m.require(type(relative) is str and not relative.startswith("/") and ".." not in Path(relative).parts,
                  "safe source member")
        m.descriptor(pin);hashes[relative]=pin["sha256"]
    m.require(m.digest(hashes)==spec["source_map_sha256"],"exact source map identity")
    expected=dict(job_id=spec["job_id"],node=spec["node"],uid=spec["uid"],
                  parent_pid=spec["owner"]["pid"],parent_birth_ticks=spec["owner"]["start_ticks"],
                  resource_lock_fd=spec["resource_lock_fd"],expires_epoch=spec["expires_epoch"])
    _exact(spec["runtime_owner"],expected,"runtime owner")
    if role=="NO3_AL300_PILOT":
        _exact(spec["case"],CASE,"one fixed NO3 case")
        _science_binding(spec)
    else:_reference_case(spec["case"])
    return {"status":"CONSISTENT_SPEC_METADATA_NOT_RUNTIME_OR_OPTIMIZER_AUTHORITY",
            "runtime_admitted":False,"can_release":False,"can_optimize":False}

def _healthy(pin,cpu,spec=None,status=None,now=None):
    g=m.linked(pin)
    m.require(type(g.get("returncode")) is int and type(g.get("command_returncode")) is int
              and g["returncode"]==g["command_returncode"]==0
              and type(g.get("CPU_limit")) is int and g["CPU_limit"]==cpu
              and g.get("cap_reason") is None and g.get("guardian_forced_monitor_stop") is False,
              "actual healthy original whole guard")
    for name in ("aggregate_CPU_seconds","complete_lifecycle_wall_seconds"):m.finite(g.get(name),name)
    m.require(0<=g["aggregate_CPU_seconds"]<cpu and 0<=g["complete_lifecycle_wall_seconds"]<=180,
              "finite inclusive actual guard accounting")
    m.require(all(g.get(k) is True for k in ("all_owned_descendants_reaped","independent_guardian",
              "kernel_escape_filter","orphan_subreaper","guardian_included_in_CPU",
              "inherited_waited_history_included_once")),"whole original guard ownership")
    candidate=m.strict_json(g["stdout"])
    if spec is not None:
        _same(candidate,spec)
        m.require(candidate.get("status")==status and candidate.get("spec")==m.pin_file(Path(spec["_spec_path"])),
                  "actual current observed kind/spec")
        m.require(g.get("session_id")==candidate.get("command_pid") and
                  g.get("leader_start_ticks")==candidate.get("command_birth_ticks"),"actual stdout PID/birth")
        _fresh(candidate,"observed_epoch",now,60)
    return g,candidate

def _price_channels(price):
    required={"startup","namespace","import","optimizer","certification","checkpoint","return","independent_peer","closure"}
    m.closed(price.get("components"),required,"all price components")
    component_keys={"covered","CPU_upper_seconds","wall_upper_seconds",
                    "compute_CPU_upper_seconds","administrative_CPU_upper_seconds",
                    "remote_unknown_CPU_reservation"}
    totals={"compute_CPU_reservation":0,"administrative_CPU_reservation":0,
            "remote_unknown_CPU_reservation":0}
    mapping={"compute_CPU_upper_seconds":"compute_CPU_reservation",
             "administrative_CPU_upper_seconds":"administrative_CPU_reservation",
             "remote_unknown_CPU_reservation":"remote_unknown_CPU_reservation"}
    for component in price["components"].values():
        m.closed(component,component_keys,"closed fully partitioned component")
        m.require(component["covered"] is True,"every price component covered")
        for key in component_keys-{"covered"}:m.integer(component[key],key,0)
        m.require(sum(component[key] for key in mapping)==component["CPU_upper_seconds"],
                  "component channels sum once to inclusive CPU")
        for key,total in mapping.items():totals[total]+=component[key]
    for key in ("whole_CPU_seconds","whole_wall_seconds","memory_MiB","child_CPU_seconds",
                "owner_CPU_seconds","owner_wall_seconds","reserved_filesystem_bytes","mandatory_headroom_bytes"):
        m.integer(price.get(key),key,1)
    for key in totals:
        m.integer(price.get(key),key,1 if key=="compute_CPU_reservation" else 0)
        m.require(totals[key]<=price[key],"component channel fits exact funded "+key)
    m.require(sum(price[key] for key in totals)<=price["whole_CPU_seconds"]
              and sum(v["wall_upper_seconds"] for v in price["components"].values())<=price["whole_wall_seconds"]
              and price["child_CPU_seconds"]<=price["owner_CPU_seconds"]<=price["compute_CPU_reservation"]
              and price["owner_wall_seconds"]<=price["whole_wall_seconds"],
              "complete funded channels distinct from primary Slurm CPU")
    return {"status":"CONSISTENT_ACCOUNTING_DESCRIPTORS_NOT_EXECUTION_AUTHORITY",
            "runtime_admitted":False,"can_release":False,"funded_channels":{key:price[key] for key in totals}}

def _price_runtime(spec):
    price=m.linked(spec["price"])
    m.require(price.get("status")=="ACCEPTED_MEASURED_R200_WHOLE_CONTEXT_PRICE"
              and all(price.get(k)==spec[k] for k in ("case_sha256","source_map_sha256","role")),
              "applicable independently measured whole price")
    _price_channels(price)
    measurement=m.linked(price["measurement"]);review=m.linked(price["independent_review"])
    m.require(measurement.get("status")=="COMPLETE_R200_WHOLE_CONTEXT_MEASUREMENT"
              and all(measurement.get(k)==spec[k] for k in ("case_sha256","source_map_sha256"))
              and review.get("status")=="PASS_REVIEWED_R200_WHOLE_CONTEXT_PRICE"
              and review.get("measurement")==price["measurement"],"actual whole measurement and independent price")
    qualification=m.linked(spec["runtime_qualification"])
    m.require(qualification.get("schema")=="r200_actual_runtime_qualification_v1"
              and qualification.get("status")=="ACCEPTED_QUALIFIED_R200_RUNTIME"
              and all(qualification.get(k)==spec[k] for k in ("source_map_sha256","role","node"))
              and qualification.get("all_required_build_ABI_boundary_tests_passed") is True,
              "actual applicable new build/ABI/native qualification")
    _,candidate=_healthy(qualification["actual_accept_guard"],5)
    m.require(dict(candidate,status=qualification["status"],actual_accept_guard=qualification["actual_accept_guard"])
              ==qualification,"actual qualification accepted candidate")
    qr=m.linked(qualification["result"]);qa=m.linked(qualification["accounting"]);qp=m.linked(qualification["independent_review"])
    m.require(qr.get("source_map_sha256")==spec["source_map_sha256"]
              and qr.get("job_id")==qa.get("job_id")==qualification.get("job_id")
              and qa.get("terminal") is True and qa.get("complete") is True and qa.get("primary_charge_counted_once") is True
              and qp.get("status")=="PASS_REVIEWED_R200_RUNTIME_QUALIFICATION"
              and qp.get("result")==qualification["result"] and qp.get("accounting")==qualification["accounting"],
              "complete independently accepted qualification return/accounting")
    scope=m.linked(spec["scope"]);ledger=m.linked(spec["ledger"])
    m.require(scope.get("schema")=="r200_compute_runtime_scope_v1" and
              all(scope.get(k)==spec[k] for k in ("purpose","nonce","role","price","input_manifest","expires_epoch"))
              and type(scope.get("compute_CPU_reservation")) is int
              and scope["compute_CPU_reservation"]==price["compute_CPU_reservation"]
              and scope.get("remote_namespace")==spec["root"]
              and type(scope.get("maximum_jobs")) is int and scope["maximum_jobs"]==1
              and scope.get("automatic_retry") is False and scope.get("requeue") is False,
              "new one-attempt funded compute purpose")
    roles=ledger.get("compute_roles")
    matches=[x for x in roles if x.get("scope")==spec["scope"]] if type(roles) is list else []
    m.require(len(matches)==1 and type(matches[0].get("compute_CPU_reservation")) is int
              and matches[0]["compute_CPU_reservation"]==price["compute_CPU_reservation"],
              "one exact primary-compute charged role in whole current ledger")
    m.integer(scope.get("new_administrative_CPU_reservation"),"new complete administrative funding",0)
    m.require(scope["new_administrative_CPU_reservation"]>=price["administrative_CPU_reservation"]+
              price["remote_unknown_CPU_reservation"],"admin plus remote fees separately funded once")
    rows=ledger.get("scopes")
    administrative=[row for row in rows if row.get("scope")==spec["scope"]] if type(rows) is list else []
    m.require(len(administrative)==1 and
              type(administrative[0].get("administrative_CPU_reservation")) is int and
              administrative[0]["administrative_CPU_reservation"]==scope["new_administrative_CPU_reservation"],
              "one exact administrative fee row without converting it into primary compute")
    return price

def _bridge(spec,bundle):
    if spec["role"]!="NO3_AL300_PILOT":
        m.require(bundle["accepted_bridge_request"] is None,"reference is not pilot bridge reuse")
        provenance=m.linked(spec["input_provenance"])
        m.require(provenance.get("status")=="ACCEPTED_ACTUAL_R200_REFERENCE_INPUT_EXPORT"
                  and provenance.get("case_sha256")==spec["case_sha256"]
                  and provenance.get("input_manifest")==spec["input_manifest"]
                  and provenance.get("complete_original_failed_provenance_verified") is True
                  and provenance.get("native_owned_export_and_accounting_independently_reviewed") is True,
                  "actual independently accepted complete original reference export closure")
        for name in ("actual_export_guard","independent_review","accounting"):m.descriptor(provenance.get(name))
        _,candidate=_healthy(provenance["actual_export_guard"],5)
        m.require(candidate==provenance.get("actual_export_candidate"),"actual owned reference export candidate")
        review=m.linked(provenance["independent_review"]);account=m.linked(provenance["accounting"])
        m.require(review.get("status")=="PASS_REVIEWED_R200_REFERENCE_INPUT_EXPORT"
                  and review.get("input_manifest")==spec["input_manifest"] and review.get("accounting")==provenance["accounting"]
                  and account.get("complete") is True and account.get("terminal") is True,
                  "actual reference export reviewed and accounted")
        return
    m.require(bundle["accepted_bridge_request"]==spec["input_provenance"],"same admitted complete bridge mapping")
    proofs=m.linked(bundle["accepted_bridge_request"]);m.closed(proofs,BRIDGE,"complete ten bridge records")
    aliases=bundle["proof_aliases"];m.require(type(aliases) is list and 1<=len(aliases)<=128,"bounded exact proof aliases")
    table={}
    for row in aliases:
        m.closed(row,{"logical","physical","bytes","uid"},"bridge proof alias")
        m.descriptor(row["logical"]);m.descriptor(row["physical"]);m.integer(row["bytes"],"proof bytes",1,16*1024**2)
        m.require(row["uid"]==spec["uid"] and type(row["uid"]) is int
                  and row["logical"]["sha256"]==row["physical"]["sha256"]
                  and row["logical"]["path"] not in table,"unique exact same-byte proof alias")
        table[row["logical"]["path"]]=row
    def read(name):
        pin=proofs[name];m.descriptor(pin);row=table.get(pin["path"])
        m.require(row is not None and row["logical"]==pin and Path(pin["path"]).suffix==".json","exact original JSON proof")
        return m.strict_json(m.read_regular(row["physical"]["path"],limit=4*1024**2,
             expected_sha=pin["sha256"],expected_uid=row["uid"],expected_bytes=row["bytes"]))
    accepted=read("accepted");guard=read("outer_accept_guard")
    m.require(accepted.get("status")=="ACCEPTED_COMPLETE_FROZEN525_NUMERICAL_ROLE"
              and accepted.get("role")=="ZERO_UPDATE_BRIDGE"
              and accepted.get("exact_NO3_zero_update_bridge_proved") is True
              and accepted.get("production_admission") is False
              and type(accepted.get("pilot_fits")) is int and accepted["pilot_fits"]==0
              and accepted.get("actual_accept_action_guard")==proofs["outer_accept_guard"],
              "actual complete accepted zero-update bridge")
    # Reconcile the original guard locally through exact aliases, not dispatcher policy.
    flags=("all_owned_descendants_reaped","independent_guardian","kernel_escape_filter","orphan_subreaper",
           "guardian_included_in_CPU","inherited_waited_history_included_once")
    m.require(type(guard.get("returncode")) is int and type(guard.get("command_returncode")) is int
              and guard["returncode"]==guard["command_returncode"]==0 and guard.get("CPU_limit")==5
              and type(guard.get("CPU_limit")) is int and guard.get("cap_reason") is None
              and guard.get("guardian_forced_monitor_stop") is False and all(guard.get(k) is True for k in flags),
              "actual healthy original bridge accept guard")
    m.require(dict(m.strict_json(guard["stdout"]),status=accepted["status"],
              actual_accept_action_guard=proofs["outer_accept_guard"])==accepted,"guarded actual accepted bridge")
    for k in ("result","accounting","independent_review","full_return_manifest"):
        m.require(accepted.get(k)==proofs[k],"exact accepted bridge link")
    result,account,peer,manifest=(read(x) for x in ("result","accounting","independent_review","full_return_manifest"))
    m.require(result.get("status")=="PASS_COMPLETE_FROZEN525_NUMERICAL_WORKER"
              and result.get("job_id")==account.get("job_id")==peer.get("job_id")==accepted.get("job_id")
              and account.get("terminal") is True and account.get("complete") is True
              and account.get("primary_charge_counted_once") is True
              and peer.get("status")=="PASS_REVIEWED_COMPLETE_FROZEN525_NUMERICAL_ROLE"
              and peer.get("result")==proofs["result"] and peer.get("accounting")==proofs["accounting"]
              and peer.get("return_manifest")==proofs["full_return_manifest"]
              and manifest.get("complete_success") is True,"complete independently reviewed bridge")
    outcome=result.get("outcome",{})
    m.require(outcome.get("status")=="PASS_HB_EXACT_NO3_ZERO_UPDATE_BRIDGE"
              and outcome.get("current_TSYNC_and_parent_ACK") is True,"actual owned zero-update computation")
    bridge=read("bridge_validation")
    m.require(bridge.get("schema")=="r154_conditional_state_bridge_v1"
              and bridge.get("status")=="VERIFIED_ZERO_OPTIMIZER_CONDITIONAL_STATE_BRIDGE"
              and bridge.get("source")==spec["scientific_source"] and bridge.get("target_name")==CASE["target"]
              and type(bridge.get("optimizer_updates")) is int and bridge["optimizer_updates"]==0
              and bridge.get("factor_state")==proofs["factor_state"]
              and bridge.get("baseline_certificate_pin")==proofs["baseline_certificate"]
              and bridge.get("original_failed_state_modified") is False
              and bridge.get("production_acceptance_authority") is False
              and all(bridge.get(k) is True for k in ("full_state_factors_verified","explicit_factor_elbo_verified",
              "original_seven_certificate_computed","rhs_unit_and_dispersed_verified","source_recipe_reproduced")),
              "whole unchanged scientific bridge and original failed state")
    final=read("finalization")
    m.require(final.get("status")=="PRIOR_ACTION_GUARD_VALIDATED" and final.get("action")=="accept"
              and final.get("guard")==proofs["outer_accept_guard"],"original healthy acceptance finalized")
    rows=manifest.get("files");m.require(type(rows) is list and len(rows)==len({x.get("relative") for x in rows}),
                                      "complete unique retained return inventory")
    for name,relative in (("factor_state","numerical/bridge/full_state.rds"),
                          ("baseline_certificate","numerical/bridge/baseline_certificate.json")):
        found=[x for x in rows if x.get("relative")==relative]
        m.require(len(found)==1 and found[0].get("sha256")==proofs[name]["sha256"]
                  and type(found[0].get("bytes")) is int and 0<found[0]["bytes"]<=16*1024**2,
                  "exact immutable factor/certificate descriptors")

def _observations(spec_pin,bundle_pin,now):
    spec=m.linked(spec_pin);inspect_spec_metadata(spec)
    m.require(spec["issued_epoch"]<=now<spec["expires_epoch"],"current unchanged finite compute window")
    bundle=m.linked(bundle_pin);m.closed(bundle,BUNDLE,"closed current actual observation bundle")
    m.require(bundle["schema"]=="r200_peer_observation_bundle_v1" and bundle["spec"]==spec_pin
              and bundle["source_publication"]==spec["source_publication"]
              and bundle["source_pins"]==spec["source_pins"],"same exact current observed purpose")
    if spec["role"]=="NO3_AL300_PILOT":_science_binding(spec,m.linked(spec["io_request"]))
    price=_price_runtime(spec);pub=m.linked(spec["source_publication"])
    m.require(pub.get("schema")=="r200_source_publication_v1"
              and pub.get("status")=="PASS_PUBLISHED_R200_SOURCE_PREPARATION"
              and type(pub.get("commit")) is str and re.fullmatch("[0-9a-f]{40}",pub["commit"])
              and pub.get("remote_readback")==pub["commit"]
              and type(pub.get("branch")) is str and pub["branch"].startswith("work/pricefm-")
              and pub.get("files")=={k:v["sha256"] for k,v in spec["source_pins"].items()},
              "actually readback published new controller source map")
    observed=dict(spec,_spec_path=spec_pin["path"])
    _,source=_healthy(bundle["source_observation_guard"],8,observed,
                        "CAPTURED_R200_SOURCE_PHYSICAL_METADATA",now)
    files=source.get("files");m.require(type(files) is list and len(files)==len(spec["source_pins"]),"complete source capture")
    captured={}
    for row in files:
        m.closed(row,{"relative","path","sha256","bytes","uid","mode","nlink"},"captured actual source")
        m.integer(row["bytes"],"actual source bytes",1,1024**2);m.integer(row["mode"],"actual source mode",0,0o177777)
        m.require(row["relative"] not in captured and row["uid"]==spec["uid"] and type(row["uid"]) is int
                  and type(row["nlink"]) is int and row["nlink"]==1 and row["mode"]&0o022==0,
                  "unique single-link owned non-writable actual source")
        captured[row["relative"]]={"path":row["path"],"sha256":row["sha256"]}
    m.require(captured==spec["source_pins"],"all installed source paths and hashes equal review/publication")
    _,physical=_healthy(bundle["physical_observation_guard"],8,observed,"CAPTURED_R200_PHYSICAL_METADATA",now)
    m.require(physical.get("witness")==bundle["physical_admission"],"actual current physical witness pin")
    witness=m.linked(bundle["physical_admission"])
    m.closed(witness,{"schema","job_id","node","owner","affinity","online_thread_siblings","effective_job_cpus",
              "cgroup_memory_limit_bytes","filesystem_available_bytes","filesystem_mandatory_headroom_bytes",
              "scope","observed_epoch"},"actual physical witness")
    m.require(witness["schema"]=="r200_actual_physical_core_witness_v1"
              and all(witness[k]==spec[k] for k in ("job_id","node","owner","affinity","scope")),"actual job/owner/core identity")
    _fresh(witness,"observed_epoch",now,90)
    siblings=witness["online_thread_siblings"];effective=witness["effective_job_cpus"]
    m.require(type(siblings) is list and type(effective) is list and siblings
              and all(type(x) is int and x>=0 for x in siblings+effective)
              and len(set(siblings))==len(siblings) and len(set(effective))==len(effective)
              and spec["affinity"][0] in siblings and set(siblings)<=set(effective),
              "all online SMT siblings owned by exact effective Slurm allocation")
    for name in ("cgroup_memory_limit_bytes","filesystem_available_bytes","filesystem_mandatory_headroom_bytes"):
        m.integer(witness[name],name,1)
    m.require(witness["cgroup_memory_limit_bytes"]<=price["memory_MiB"]*1024**2
              and witness["filesystem_mandatory_headroom_bytes"]>=price["mandatory_headroom_bytes"]
              and witness["filesystem_available_bytes"]>=price["reserved_filesystem_bytes"]+
                  witness["filesystem_mandatory_headroom_bytes"],"actual priced memory and disk plus headroom")
    _bridge(spec,bundle)
    return spec,bundle,price

def source_physical(spec_pin,bundle_pin,output_path,now=None):
    now=time.time() if now is None else now;m.finite(now,"now")
    spec,bundle,_=_observations(spec_pin,bundle_pin,now)
    m.require(bundle["owner_ready"] is None and bundle["ready_observation_guard"] is None,
              "source phase precedes actual owner READY")
    result=dict(schema="r200_compute_source_review_v1",status="PASS_REVIEWED_R200_COMPUTE_SOURCE_PHYSICAL",
                spec=spec_pin,**{k:spec[k] for k in IDENTITY},
                case_sha256=spec["case_sha256"],source_map_sha256=spec["source_map_sha256"],
                source_publication=spec["source_publication"],controller_source=spec["controller_source"],
                source_pins=spec["source_pins"],runtime_qualification=spec["runtime_qualification"],
                physical_admission=bundle["physical_admission"],
                independent_program=m.pin_file(Path(__file__)),issued_epoch=now,
                expires_epoch=min(spec["expires_epoch"],now+60))
    return m.write_new(Path(m.absolute(str(output_path))),result)

def owner_release(spec_pin,source_review_pin,bundle_pin,output_path,now=None):
    now=time.time() if now is None else now;m.finite(now,"now")
    spec,bundle,_=_observations(spec_pin,bundle_pin,now);review=m.linked(source_review_pin)
    _same(review,spec)
    m.require(review.get("schema")=="r200_compute_source_review_v1"
              and review.get("status")=="PASS_REVIEWED_R200_COMPUTE_SOURCE_PHYSICAL"
              and review.get("spec")==spec_pin and review.get("source_pins")==spec["source_pins"]
              and review.get("source_map_sha256")==spec["source_map_sha256"]
              and review.get("physical_admission")==bundle["physical_admission"]
              and review.get("controller_source")==spec["controller_source"]
              and review.get("independent_program")==m.pin_file(Path(__file__))
              and review.get("issued_epoch")<=now<review.get("expires_epoch"),"same actual first independent phase")
    m.descriptor(bundle["owner_ready"]);m.descriptor(bundle["ready_observation_guard"])
    _,observed=_healthy(bundle["ready_observation_guard"],8,dict(spec,_spec_path=spec_pin["path"]),
                         "CAPTURED_R200_OWNED_READY_METADATA",now)
    m.require(observed.get("ready")==bundle["owner_ready"],"actual guarded owner READY")
    ready=m.linked(bundle["owner_ready"]);m.closed(ready,READY,"actual closed READY")
    m.require(ready["schema"]=="r200_owned_ready_v1"
              and ready["status"]=="READY_R200_OWNED_AWAIT_ROOT_RELEASE_NO_PAYLOAD"
              and all(ready[k]==spec[k] for k in (*IDENTITY,"uid","owner","root","case_sha256","source_map_sha256",
                 *FUNDING,"resource_lock_fd","resource_lock_path"))
              and ready["physical_admission"]==bundle["physical_admission"],"same current actual job/owner READY")
    _fresh(ready,"created_epoch",now,120)
    m.require(type(ready["expires_epoch"]) in (int,float) and
              ready["created_epoch"]<ready["expires_epoch"]<=min(spec["expires_epoch"],ready["created_epoch"]+120)
              and now<ready["expires_epoch"],"fixed READY lifetime no renewal")
    result=dict(schema="r200_owner_release_review_v1",status="PASS_REVIEWED_R200_OWNER_RELEASE",
                spec=spec_pin,source_review=source_review_pin,**{k:spec[k] for k in IDENTITY},
                case_sha256=spec["case_sha256"],source_map_sha256=spec["source_map_sha256"],
                owner_ready=bundle["owner_ready"],physical_admission=bundle["physical_admission"],
                price=spec["price"],scope=spec["scope"],ledger=spec["ledger"],
                independent_program=m.pin_file(Path(__file__)),issued_epoch=now,
                expires_epoch=min(spec["expires_epoch"],ready["expires_epoch"],review["expires_epoch"]))
    return m.write_new(Path(m.absolute(str(output_path))),result)
