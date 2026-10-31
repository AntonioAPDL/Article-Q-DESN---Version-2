"""Fresh R-only native frontend reusing exact accepted compute-source evidence.

All fourteen r176 compute files remain unchanged.  This frontend is published
and reviewed separately, binds its own source in every action, and permits
only a new R role/namespace/authority.  It never manufactures an inventory
journal or revives a failed role.  Interrupted submits can be acknowledged for
known-job cancellation only, including the JOB-before-SUBMITTED write window.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import resource
import signal
import stat
import sys
import time

from . import startup_helper as h

BASE_FRONTEND_SHA256 = "176e860df0eda95c071d1ef4e7559b2d0cccdb309a67b6134fd64881ccd4673b"
ROLE = "EXACT_R46_STARTUP_METADATA"
MODE = "FRESH_R_ONLY_WITH_EXACT_ACCEPTED_KERNEL_REUSE"


def _load_base():
    path = Path(__file__).absolute().with_name("startup_batch_stop.py")
    raw = h.read_pin({"path": str(path), "sha256": BASE_FRONTEND_SHA256})
    spec = importlib.util.spec_from_file_location("pricefm_hb._r180_native_protocol_base", path)
    base = importlib.util.module_from_spec(spec)
    # Existing per-action identity functions bind this separately published
    # frontend, while every compute source remains its original staged file.
    base.__file__ = str(Path(__file__).absolute())
    exec(compile(raw, str(path), "exec"), base.__dict__)
    return base


_base = _load_base()
NAMES = _base.NAMES
ROLES = (ROLE,)
ACTION_ENVELOPE = _base.ACTION_ENVELOPE
NATIVE_CONTROL_TOTAL = sum((x["local_CPU"] + x["remote_unknown_fee"]) * x["maximum_calls"]
                           for x in ACTION_ENVELOPE.values()) + 16
assert NATIVE_CONTROL_TOTAL == 128


def __getattr__(name):
    return getattr(_base, name)


def _passing_guard(value, CPU, wall):
    h.require(type(value.get("returncode")) is type(value.get("command_returncode")) is int
              and value["returncode"] == value["command_returncode"] == 0 and value.get("cap_reason") is None,
              "actual passing original outer guard required")
    h.require(type(value.get("CPU_limit")) is int and value["CPU_limit"] == CPU
              and type(value.get("aggregate_CPU_seconds")) in (int,float)
              and math.isfinite(value["aggregate_CPU_seconds"]) and 0 <= value["aggregate_CPU_seconds"] < CPU
              and type(value.get("complete_lifecycle_wall_seconds")) in (int,float)
              and math.isfinite(value["complete_lifecycle_wall_seconds"])
              and 0 <= value["complete_lifecycle_wall_seconds"] <= wall
              and value.get("guardian_forced_monitor_stop") is False
              and all(value.get(x) is True for x in ("all_owned_descendants_reaped", "independent_guardian",
                  "kernel_escape_filter", "orphan_subreaper", "guardian_included_in_CPU",
                  "inherited_waited_history_included_once")), "original guard limits/drain proof required")


def canonical_identity(config):
    keys = ("scope", "site", "native_control_budget", "registry", "remote_namespace", "node", "cached_python",
            "cached_python_sha256", "source_dir", "publication", "source_review", "frontend_source",
            "accepted_inventory", "reuse_review", "canonical_state_root", "placement_proof",
            "carrier", "carrier_manifest")
    return {key:config[key] for key in keys}


def validate_scope(scope, *, now):
    # The unchanged worker checks this protocol-version status literal.  The
    # explicit mode/roles below NARROW actual authority to one fresh R job.
    h.require(scope.get("status") == "PROSPECTIVE_TWO_ROLE_HB_RUNTIME_QUALIFICATION_SCOPE"
              and scope.get("mode") == MODE and scope.get("roles") == [ROLE]
              and type(scope.get("maximum_jobs")) is int and scope["maximum_jobs"] == 1
              and type(scope.get("compute_CPU_reservation")) is int and scope["compute_CPU_reservation"] == 600
              and scope.get("max_concurrent_jobs") == 1 and scope.get("old_roles_reopened") is False
              and scope.get("automatic_retries") is False
              and scope["issued_epoch"] <= now < scope["expires_epoch"]
              and scope["issued_epoch"] < scope["fixed_latest_submit_epoch"]
                  <= scope["expires_epoch"]-1200, "fresh narrowed R-only scope required")


def validate_placement(config, scope):
    root = h.physical(config["canonical_state_root"])
    prefix = Path("/home/jaguir26/.local/state/pricefm")
    h.require(root.is_relative_to(prefix) and root != prefix and root.name.startswith("r180_"),
              "private persistent home state root required; tmp/data substitution forbidden")
    info = root.stat()
    h.require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid() and info.st_mode & 0o077 == 0,
              "private owned canonical state root required")
    proof = h.read(config["placement_proof"])
    h.require(proof.get("same_original_H4_caps_and_stopped_rules") is True
              and proof.get("both_probe_fees_retained") is True
              and proof.get("no_hard_latency_guarantee_or_job_admission") is True,
              "actual unchanged-limit placement evidence required")
    rows = [r for r in proof.get("rows",[]) if r.get("label") == "home"]
    h.require(len(rows) == 1 and rows[0]["root"] == str(root) and rows[0]["device"] == info.st_dev
              and rows[0]["returncode"] == 0 and rows[0]["files"] == 8,
              "exact successful owned home probe device/root required")
    guard = h.read(rows[0]["guard"]); _passing_guard(guard,4,90)
    probe = h.strict_json(guard["stdout"])
    h.require(probe.get("status") == "OBSERVED_OWNED_METADATA_FSYNC_READBACK_NOT_LATENCY_GUARANTEE"
              and probe.get("root") == str(root) and probe.get("device") == info.st_dev
              and len(probe.get("rows",[])) == 8 and probe.get("new_jobs_or_scientific_calls") == 0,
              "actual passing probe payload/root/device required")
    allowed = h.physical(scope["allowed_metadata_output_root"])
    h.require(allowed.parent == root and allowed != root and allowed.name.startswith("R_only_")
              and allowed.is_dir(), "a new private child, not the probe directory, is required")
    allowed_info = allowed.stat()
    h.require(allowed_info.st_uid == os.getuid() and allowed_info.st_mode & 0o077 == 0
              and allowed_info.st_dev == info.st_dev, "canonical child ownership/device differs")
    registry = h.physical(config["registry"])
    h.require(registry.is_relative_to(allowed) and registry != allowed,
              "new exact child canonical registry required")


def inspect_accepted_component(config, hashes):
    """Verify existing completed evidence; returns no new job/role authority."""
    accepted = h.read(config["accepted_inventory"])
    h.require(accepted.get("status") == "ACCEPTED_COMPLETE_STARTUP_BATCH_METADATA_ROLE"
              and accepted.get("role") == "COMPUTE_RUNTIME_INVENTORY"
              and accepted.get("kernel_matrix_pass") is True
              and accepted.get("primary_charge_counted_once") is True,
              "original completed accepted kernel record required")
    result = h.read(accepted["result"]); manifest = h.read(accepted["full_return_manifest"])
    h.require(result.get("status") == "INVENTORY_COMPLETE_KERNEL_PASS_NO_R" and result.get("error") is None
              and result.get("role") == "COMPUTE_RUNTIME_INVENTORY"
              and result.get("job_id") == accepted["job_id"] and result.get("scope_id") == accepted["scope_id"]
              and result.get("node") == config["node"] == "node-13"
              and result.get("new_models") == result.get("optimizer_invocations") == 0,
              "accepted component result/job/node differs")
    h.require(set(result["sources"]) == set(NAMES)
              and {name:x["sha256"] for name,x in result["sources"].items()} == hashes,
              "all fourteen accepted compute-source hashes must remain unchanged")
    old_root=Path(config["accepted_inventory"]["path"]).parent
    old_packet=h.read(h.pin(old_root/"PACKET.json"))
    old_spec=h.read(dict(path=str(old_root/"packet/SPEC.json"),sha256=result["spec_sha256"]))
    h.require(old_packet.get("role") == "COMPUTE_RUNTIME_INVENTORY"
              and old_packet.get("scope_id") == accepted["scope_id"]
              and old_packet.get("spec_sha256") == result["spec_sha256"]
              and old_packet.get("sources") == result["sources"] == old_spec.get("sources")
              and old_spec.get("cached_python") == config["cached_python"]
              and old_spec.get("cached_python_sha256") == config["cached_python_sha256"]
              and old_spec.get("node") == config["node"],
              "original SPEC and cached Python/node context must remain exact")
    outcome = result["outcome"]
    h.require(outcome.get("status") == "PASS_COMPUTE_OWNED_HELPER_KERNEL_MATRIX_NOT_R"
              and outcome.get("error") is None and outcome.get("all_private_descendants_reaped") is True
              and outcome.get("R_startup_proved") is False and outcome.get("numerical_parity_proved") is False,
              "actual accepted six-case component evidence required")
    from .startup_helper_kernel_tests import CASE_ROWS
    cases = outcome.get("case_results",[])
    h.require(len(cases) == 6 and {(r["label"],r["expected"]) for r in cases}
              == {(label,expected) for label,case,expected,wall in CASE_ROWS}
              and all(r.get("test_expectation_met") is True and r.get("all_private_descendants_reaped") is True
                      for r in cases), "all six exact completed cases required")
    h.require(manifest.get("schema") == "pricefm_startup_batch_return_manifest_v1"
              and manifest.get("job_id") == accepted["job_id"] and manifest.get("scope_id") == accepted["scope_id"]
              and manifest.get("new_models") == 0, "original complete return manifest required")
    parent = Path(accepted["full_return_manifest"]["path"]).parent
    seen = set(); total = 0; returned = {}
    for row in manifest["files"]:
        relative = _base.safe_relative(row["relative"])
        h.require(str(relative) not in seen, "duplicate returned evidence path")
        seen.add(str(relative)); raw = h.read_pin({"path":str(parent/relative),"sha256":row["sha256"]},32*1024**2)
        h.require(len(raw) == row["bytes"], "old returned evidence size differs")
        returned[str(relative)] = dict(path=str(parent/relative),sha256=row["sha256"])
        total += len(raw)
    h.require(len(seen) <= 4096 and total <= 32*1024**2 and "RESULT.json" in seen
              and {"kernel/KERNEL_MATRIX_RESULT.json","INVENTORY.json"} <= seen,
              "bounded original complete return required")
    h.require(returned["RESULT.json"] == accepted["result"]
              and h.read(returned["kernel/KERNEL_MATRIX_RESULT.json"]) == outcome,
              "original result and kernel evidence must match their manifest")
    inventory=h.read(returned["INVENTORY.json"])
    h.require(inventory.get("status") == "COMPUTE_RUNTIME_FACTS_NO_R"
              and inventory.get("job_id") == accepted["job_id"] and inventory.get("node") == config["node"]
              and inventory["python"]["sha256"] == config["cached_python_sha256"],
              "original actual compute runtime inventory required")
    account = h.read(accepted["accounting"])
    h.require(account.get("complete") is True and account.get("terminal") is True
              and account.get("job_id") == accepted["job_id"] and account.get("primary_charge_counted_once") is True
              and account.get("canonical_primary_CPU_seconds") == accepted["canonical_primary_CPU_seconds"],
              "old canonical complete accounting required")
    prior_review = h.read(accepted["independent_review"])
    h.require(prior_review.get("status") == "PASS_REVIEWED_STARTUP_BATCH_ROLE"
              and prior_review.get("role") == "COMPUTE_RUNTIME_INVENTORY"
              and prior_review.get("job_id") == accepted["job_id"]
              and prior_review.get("result") == accepted["result"]
              and prior_review.get("return_manifest") == accepted["full_return_manifest"]
              and prior_review.get("accounting") == accepted["accounting"],
              "original actual accepted component review required")
    guard = h.read(accepted["actual_accept_action_guard"]); _passing_guard(guard,5,180)
    candidate = h.strict_json(guard["stdout"])
    expected = dict(candidate,status="ACCEPTED_COMPLETE_STARTUP_BATCH_METADATA_ROLE",
                    actual_accept_action_guard=accepted["actual_accept_action_guard"])
    h.require(expected == accepted, "original accepted record is not the actually guarded result")
    return accepted


def validate_kernel_reuse(config, scope, hashes):
    accepted = inspect_accepted_component(config,hashes)
    review = h.read(config["reuse_review"])
    h.require(review.get("status") == "PASS_REVIEWED_ACCEPTED_KERNEL_REUSE_FOR_FRESH_R_SCOPE"
              and review.get("accepted_inventory") == config["accepted_inventory"]
              and review.get("accepted_result") == accepted["result"]
              and review.get("full_return_manifest") == accepted["full_return_manifest"]
              and review.get("actual_accept_action_guard") == accepted["actual_accept_action_guard"]
              and review.get("source_files") == hashes and review.get("frontend_source") == config["frontend_source"]
              and review.get("scope") == config["scope"] and review.get("node") == "node-13"
              and review.get("fresh_R_role_required") is True and review.get("old_failed_R_role_reopened") is False,
              "new independent exact cross-context component reuse review required")
    return accepted


def load_config(path):
    h.require(os.sched_getaffinity(0) == {31}, "administrative CPU31 required")
    config = h.read(h.pin(path))
    h.require(config.get("schema") == "pricefm_native_R_only_config_v1", "native R-only config required")
    scope = h.read(config["scope"]); validate_scope(scope,now=time.time())
    h.require(config["frontend_source"] == h.pin(Path(__file__).absolute()), "exact new frontend source required")
    budget = h.read(config["native_control_budget"])
    h.require(budget.get("status") == "PROSPECTIVE_ONE_R_JOB_NATIVE_CONTROL_BUDGET"
              and budget.get("combined_native_control_CPU_ceiling") == 128
              and budget.get("expires_epoch") == scope["expires_epoch"], "fully priced one-role128 native envelope required")
    validate_placement(config,scope)
    auth_pin = config["canonical_authority"]
    h.require(auth_pin["path"] == str(Path(scope["allowed_metadata_output_root"])/"CANONICAL_NATIVE_R_ONLY_AUTHORITY.json"),
              "exact new R-only canonical authority path required")
    authority = h.read(auth_pin)
    h.require(authority.get("status") == "ROOT_AUTHORIZED_CANONICAL_NATIVE_R_ONLY_CONFIG"
              and authority.get("binding") == canonical_identity(config) and authority.get("roles") == [ROLE]
              and authority.get("maximum_jobs") == authority.get("max_concurrent_jobs") == 1
              and scope["issued_epoch"] <= authority["issued_epoch"] <= time.time() < authority["expires_epoch"] <= scope["expires_epoch"],
              "fresh one-job source/context/namespace authority required")
    _base.safe_path(config["remote_namespace"])
    h.require(config["remote_namespace"].startswith("/mnt/beegfs/home/jaguir26/pricefm_r180_")
              and config["node"] == "node-13", "new distinct R-only namespace/node required")
    h.require(re.fullmatch(r"/mnt/beegfs/home/jaguir26/pricefm_[A-Za-z0-9_/-]+/runtime/venv/bin/python",config["cached_python"]),
              "previously verified cached compute Python required")
    hashes = {name:_base.digest(Path(config["source_dir"])/name) for name in NAMES}
    publication = h.read(config["publication"]); review = h.read(config["source_review"])
    h.require(publication.get("status") == "PASS_NATIVE_R_ONLY_FRONTEND_SOURCE_PUBLICATION"
              and re.fullmatch("[0-9a-f]{40}",publication["commit"])
              and publication.get("source_files") == hashes and publication.get("frontend_source") == config["frontend_source"],
              "actual new frontend and unchanged compute-source publication/readback required")
    h.require(review.get("status") == "PASS_REVIEWED_NATIVE_R_ONLY_FRONTEND_SOURCE"
              and review.get("source_files") == hashes and review.get("frontend_source") == config["frontend_source"],
              "actual independent new frontend source review required")
    validate_kernel_reuse(config,scope,hashes)
    return config,scope,_base.site_config(config["site"]),hashes


def started_action(registry,role,action,config,hashes):
    h.require(role == ROLE, "R-only action required")
    index = len(list(registry.glob("control_*.started.json")))
    path = registry/("control_%04d.started.json"%index)
    h.write_new(path,dict(status="ACTION_STARTED_NOT_SUCCESS",role=role,action=action,
        created_epoch=time.time(),command_pid=os.getpid(),command_birth_ticks=h.process_birth_ticks(),
        source_sha256=config["frontend_source"]["sha256"],frontend_source=config["frontend_source"],
        frontend_publication=config["publication"],frontend_source_review=config["source_review"],
        compute_source_files=hashes,limits=_base.action_limits(action)))
    return path


def submission_argv(config,site,p):
    return ["sbatch","--parsable","--export=NONE","--propagate=NONE","--mail-type=NONE",
        "--account="+site["account"],"--partition="+site["partition"],"--qos="+site["qos"],
        "--nodelist="+config["node"],"--nodes=1","--ntasks=1","--cpus-per-task=1","--hint=nomultithread",
        "--mem=8192M","--time=00:20:00","--no-requeue","--job-name="+p["scope_id"],
        "--chdir="+p["remote_root"],"--output="+p["remote_root"]+"/slurm-%j.out",
        "--error="+p["remote_root"]+"/slurm-%j.err",p["remote_root"]+"/job.sbatch"]


def acknowledge_failed_previous(registry,role,guard_path,*,config,site):
    pending = sorted(x for x in registry.glob("control_*.started.json")
        if not x.with_name(x.name.replace(".started.json",".validated.json")).exists()
        and not x.with_name(x.name.replace(".started.json",".failed_ack.json")).exists())
    h.require(len(pending) == 1, "one exact failed prior action required")
    started = pending[0];start = h.read(h.pin(started));root = registry/role
    h.require(role == ROLE and start["role"] == role
              and start["source_sha256"] == config["frontend_source"]["sha256"] == _base.digest(Path(__file__).absolute())
              and start.get("frontend_source") == config["frontend_source"]
              and start.get("frontend_publication") == config["publication"]
              and start.get("frontend_source_review") == config["source_review"]
              and start.get("compute_source_files")
                  == {name:_base.digest(Path(config["source_dir"])/name) for name in NAMES},
              "exact failed role/frontend and compute-source identity required")
    history = _base.records(root);p = _base.packet(root)
    submitted = [x for x in history if x["state"] == "SUBMITTED"]
    job_pin = h.pin(root/"JOB.json");known = h.read(job_pin)
    h.require(type(known.get("job_id")) is str and re.fullmatch(r"[1-9][0-9]*",known["job_id"])
              and known.get("scope_id") == p["scope_id"], "exact known canonical JOB required")
    if submitted:
        final = submitted[-1]
        h.require(final["job"] == job_pin and final["job_id"] == known["job_id"], "canonical submitted job pin differs")
        binding = dict(kind="COMPLETED_SUBMITTED_JOURNAL",submitted=final)
    else:
        intent_record = history[-1]
        failed_tail = None
        if intent_record["state"] == "ACTION_FAILED_RETAINED":
            h.require(intent_record.get("action") == "submit" and len(history) >= 2,
                      "only an exact interrupted-submit exception tail is recoverable")
            failed_tail = intent_record;intent_record = history[-2]
        h.require(start["action"] == "submit" and intent_record["state"] == "SUBMISSION_INTENT",
                  "interrupted submit requires exact pre-submission journal")
        intent_pin = h.pin(root/"submit.intent.json");intent = h.read(intent_pin)
        h.require(intent.get("status") == "INTENT_NOT_SUCCESS" and intent.get("operation") == "submit"
                  and start["created_epoch"] <= intent["epoch"] <= intent_record["epoch"]
                  and intent_record.get("whole_compute_CPU_reservation") == 600
                  and intent_record.get("wall_seconds") == 1200 and intent_record.get("automatic_retry") is False,
                  "exact durable submit/start intent required")
        reply = known.get("submission",{})
        h.require(reply.get("argv") == submission_argv(config,site,p) and type(reply.get("returncode")) is int
                  and reply["returncode"] == 0 and type(reply.get("stderr")) is str
                  and _base.parse_job_id(reply.get("stdout")) == known["job_id"],
                  "exact source/namespace-bound native submission reply required")
        binding = dict(kind="INTERRUPTED_SUBMIT_OBSERVED_COMPLETE_JOB_NOT_SUBMIT_SUCCESS",submit_intent=intent_pin,
                       submission_journal=intent_record,retained_submit_exception_tail=failed_tail,
                       no_final_SUBMITTED_record=True)
    gp = h.pin(guard_path);guard = h.read(gp);witness = guard.get("owned_stop_witness",{})
    sid = guard.get("session_id",witness.get("session_id"));birth = guard.get("leader_start_ticks",witness.get("leader_start_ticks"))
    h.require(type(guard.get("returncode")) is int and guard["returncode"] != 0
              and guard.get("independent_guardian") is True and guard.get("all_owned_descendants_reaped") is True
              and guard.get("CPU_limit",start["limits"]["local_CPU"]) == start["limits"]["local_CPU"]
              and sid == start["command_pid"] and birth == start["command_birth_ticks"],
              "actual failed/drained outer guard PID/birth required; no success inferred")
    value = dict(status="FAILED_ACTION_ACKNOWLEDGED_FOR_KNOWN_JOB_CANCELLATION_ONLY",started=h.pin(started),
        failed_guard=gp,known_job=job_pin,job_binding=binding,no_successor_compute_authority=True,
        no_job_submission_success_claim=True,old_fees_retained=True)
    spent = root/"ROLE_FAILED_SPENT.json"
    # Publish the quarantine FIRST. Interruption before the ack can never
    # reopen submission/release/acceptance through an ack-without-spent gap.
    if spent.exists():
        h.require(h.read(h.pin(spent)) == value, "foreign or inconsistent failed-role quarantine")
    else:
        h.write_new(spent,value)
    h.write_new(started.with_name(started.name.replace(".started.json",".failed_ack.json")),value)
    return value


def submit(config,scope,site,root):
    h.require(scope["issued_epoch"] <= time.time() < scope["fixed_latest_submit_epoch"],
              "fixed new R-only submission cutoff expired")
    return _base.submit(config,scope,site,root)


def accepted_runtime_context(config):
    accepted=h.read(config["accepted_inventory"])
    manifest=h.read(accepted["full_return_manifest"])
    rows=[r for r in manifest["files"] if r["relative"] == "INVENTORY.json"]
    h.require(len(rows) == 1, "one original runtime inventory required")
    path=Path(accepted["full_return_manifest"]["path"]).parent/"INVENTORY.json"
    return h.read(dict(path=str(path),sha256=rows[0]["sha256"]))


def validate_current_runtime_context(config,ready):
    old=accepted_runtime_context(config);current=ready["inventory"]
    fields=("node","hostname","uname","python","python_version","libc","helpers","cpus_per_task")
    h.require(all(current.get(key) == old.get(key) for key in fields)
              and current.get("node") == config["node"] == "node-13"
              and current.get("cpus_per_task") == 1 and len(current.get("affinity",[])) == 1
              and current["python"]["sha256"] == config["cached_python_sha256"],
              "fresh R READY kernel/libc/Python/helper context differs from accepted component")


def ready(config,site,root):
    value=_base.ready(site,root)
    validate_current_runtime_context(config,value)
    return value


def release(config,site,root,bundle):
    validate_current_runtime_context(config,h.read(h.pin(root/"READY.json")))
    return _base.release(site,root,bundle)


def prepare(config,scope,role,hashes,registry):
    h.require(role == ROLE and not (registry/"COMPUTE_RUNTIME_INVENTORY").exists(),
              "fresh R-only registry without fabricated inventory journal required")
    accepted = validate_kernel_reuse(config,scope,hashes)
    root = registry/role;root.mkdir(mode=0o700)
    packet = root/"packet";packet.mkdir(mode=0o700);(packet/"package").mkdir();(packet/"package/pricefm_hb").mkdir()
    token = hashlib.sha256((str(root)+str(time.time_ns())).encode()).hexdigest()[:20]
    scope_id = "r180-R46-"+token;remote = config["remote_namespace"]+"/"+scope_id
    uploads=[];sources={}
    for name in NAMES:
        source=Path(config["source_dir"])/name;target=packet/"package/pricefm_hb"/name
        with target.open("xb") as out:out.write(source.read_bytes())
        relative="package/pricefm_hb/"+name
        uploads.append(dict(local=str(target),relative=relative,sha256=hashes[name],bytes=target.stat().st_size))
        sources[name]=dict(path=remote+"/"+relative,sha256=hashes[name])
    raw=h.read_pin(config["scope"]);(packet/"Q_SCOPE.json").write_bytes(raw)
    uploads.append(dict(local=str(packet/"Q_SCOPE.json"),relative="Q_SCOPE.json",sha256=config["scope"]["sha256"],bytes=len(raw)))
    spec=dict(schema="pricefm_startup_batch_spec_v1",role=ROLE,scope_id=scope_id,remote_root=remote,
        scope=dict(path=remote+"/Q_SCOPE.json",sha256=config["scope"]["sha256"]),
        source_commit=h.read(config["publication"])["commit"],sources=sources,
        native_frontend_source=config["frontend_source"],accepted_inventory_reference=config["accepted_inventory"],
        accepted_inventory_reuse_review=config["reuse_review"],accepted_inventory=accepted,
        cached_python=config["cached_python"],cached_python_sha256=config["cached_python_sha256"],node=config["node"],nonce=token,
        expires_epoch=scope["expires_epoch"],release_wait_seconds=300,
        component_CPU_caps=dict(shell_srun=30,worker=30,kernel_or_R_guard=30,launch_reserve=30),
        aggregate_CPU_reservation=600,wall_seconds=1200,memory_MiB=8192,threads=1,
        maximum_return_bytes=32*1024**2,maximum_return_files=4096,new_models=0)
    for label in ("carrier","carrier_manifest"):
        value=config[label];raw=h.read_pin(value,128*1024**2)
        filename="carrier.tar.gz" if label=="carrier" else "carrier_manifest.json"
        path=packet/filename;path.write_bytes(raw);spec[label]=dict(path=remote+"/"+filename,sha256=value["sha256"])
        uploads.append(dict(local=str(path),relative=filename,sha256=value["sha256"],bytes=len(raw)))
    h.write_new(packet/"SPEC.json",spec);spec_sha=_base.digest(packet/"SPEC.json")
    body=("#!/bin/bash\nset -euo pipefail\numask 077\nulimit -c 0\nulimit -t 30\nexport PATH=/usr/bin:/bin\n"
        +"\n".join("export "+key+"=1" for key in sorted(h.THREAD_KEYS))+"\n"
        +"exec /usr/bin/srun --ntasks=1 --cpus-per-task=1 --cpu-bind=threads --kill-on-bad-exit=1 --propagate=CPU --export=ALL "
        +_base.shlex.join([config["cached_python"],"-I","-B",remote+"/package/pricefm_hb/startup_batch_stop_worker.py",
                           "--spec",remote+"/SPEC.json","--sha256",spec_sha])+"\n")
    with (packet/"job.sbatch").open("x") as out:out.write(body)
    for name in ("SPEC.json","job.sbatch"):
        path=packet/name;uploads.append(dict(local=str(path),relative=name,sha256=_base.digest(path),bytes=path.stat().st_size))
    manifest=dict(scope_id=scope_id,role=ROLE,remote_root=remote,spec_sha256=spec_sha,uploads=uploads,sources=sources,
        source_publication=config["publication"],source_review=config["source_review"],
        frontend_source=config["frontend_source"],accepted_inventory_reference=config["accepted_inventory"],
        accepted_inventory_reuse_review=config["reuse_review"])
    h.write_new(root/"PACKET.json",manifest);_base.append(root,"PREPARED",packet=h.pin(root/"PACKET.json"))
    return manifest


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action",choices=("prepare","stage","submit","ready","release","observe","collect","accept","cancel","retire_failed","finalize"))
    parser.add_argument("--config",required=True);parser.add_argument("--role",choices=ROLES,required=True)
    for name in ("bundle","actual-review","previous-guard","failed-guard"):parser.add_argument("--"+name)
    args=parser.parse_args();config,scope,site,hashes=load_config(args.config)
    if args.action != "finalize":
        _base.require_outer_context()
        h.require(resource.getrlimit(resource.RLIMIT_CPU)[1] == _base.action_limits(args.action)["local_CPU"],
                  "same original per-action hard CPU cap required")
    else:
        resource.setrlimit(resource.RLIMIT_CPU,(2,2));signal.alarm(15)
    with _base.canonical(config) as registry:
        if args.failed_guard:
            h.require(args.action in {"cancel","observe","collect","retire_failed","finalize"},
                      "failure acknowledgement cannot release or submit")
            acknowledge_failed_previous(registry,args.role,args.failed_guard,config=config,site=site)
        previous=_base.finish_previous(registry,args.previous_guard)
        if args.action == "finalize":print(json.dumps(previous,sort_keys=True));return
        root=registry/args.role
        h.require(args.action not in {"prepare","stage","submit","release","accept"}
                  or not (root/"ROLE_FAILED_SPENT.json").exists(), "failed R role stays spent; no retry or successor release")
        started=started_action(registry,args.role,args.action,config,hashes)
        try:
            if args.action == "prepare":value=prepare(config,scope,args.role,hashes,registry)
            elif args.action == "stage":value=_base.stage(config,site,registry,root)
            elif args.action == "submit":value=submit(config,scope,site,root)
            elif args.action == "ready":value=ready(config,site,root)
            elif args.action == "release":value=release(config,site,root,args.bundle)
            elif args.action == "observe":value=_base.observe(site,root)
            elif args.action == "collect":value=_base.collect(site,root)
            elif args.action == "accept":value=_base.accept(config,site,root,args.actual_review)
            elif args.action == "cancel":value=_base.cancel(site,root)
            else:value=_base.retire_failed(config,site,root,args.actual_review)
        except BaseException as error:
            if root.is_dir():_base.append(root,"ACTION_FAILED_RETAINED",action=args.action,error=type(error).__name__+": "+str(error))
            raise
        _base.pending_action(started,value)
    print(json.dumps(value,sort_keys=True))


if __name__ == "__main__":
    main()
