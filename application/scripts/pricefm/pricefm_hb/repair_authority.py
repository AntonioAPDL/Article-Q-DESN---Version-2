"""Versioned prospective authority for one synthetic PriceFM projection study.

The expired522 allocation is historical evidence only. No old source, runtime,
clock, charge, admission or policy is patched. The frozen scientific R toy and
R157 ptrace/TSYNC guard are reused under a distinct reviewed R164 protocol.
Importing this module performs no admission, process observation or execution.
"""
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import resource
import signal
import socket
import stat
import subprocess
import sys
import time

from . import repair_readiness as rr

POLICY_SCHEMA = "r164_projection_toy_resource_policy_v1"
POOL_SCHEMA = "r164_projection_toy_global_contract_v1"
GRANT_SCHEMA = "r164_projection_toy_grant_v1"
POLICY_STATUS = "ROOT_ADMITTED_DISTINCT_PROSPECTIVE_SYNTHETIC_STUDY"
PURPOSE = "NEW_PROSPECTIVE_PRICEFM_SYNTHETIC_PROJECTION_TOY_ONLY"
OLD_POOL_SHA = "3ff288be9f645c44360b52f5aca04e49d9667d4b41c8974595ed42f101fbf5b4"
OLD_POLICY_SHA = "996cfe15a4d6742cf449fdd1a39d0ed1bf2e45d855edb7196490de9136947119"
NATIVE_ROOT = Path("/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r157_native_bootstrap_20261028")
PYTHON = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python")
LEGACY_LOCK = Path("/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021/r154_parallel_repair_20261026/resources/global_locks/muscat_cpu30.lock")
OLD_TOY = Path("/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_r157_parallel_implementation_20261028/local/ROOT_SYNTHETIC_EXECUTION_02/toy_grant.json")
OLD_TOY_SHA = "6f6c9d605b66e8180b1176f0f44f407fa32dd1b0c2da434aac1219e9b3fbf84b"
OLD_COSTS = [OLD_TOY.parent / "root_driver_accounting.json", OLD_TOY.parent / "toy_once/failure_accounting.json",
             OLD_TOY.parent.parent / "ROOT_SYNTHETIC_EXECUTION_01/root_driver_accounting.json"]
SOURCE_KIND = "R154_project_fullstate_consumer_pinned_CRAN111"
_ADMISSION_BUDGET = None


def need(value, message):
    if not value:
        raise rr.EvidenceError(message)


def finite(value):
    return type(value) in (float, int) and math.isfinite(value)


def identity(value):
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    return hashlib.sha256(raw).hexdigest()


def pin(path):
    path = rr.physical_path(path)
    before = path.stat()
    need(stat.S_ISREG(before.st_mode) and before.st_size <= 512 * 1024 ** 2, "bounded physical source/runtime file required")
    digest = hashlib.sha256()
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        need(rr._identity(os.fstat(fd)) == rr._identity(before), "source identity changed before open")
        with os.fdopen(os.dup(fd), "rb") as stream:
            for block in iter(lambda: stream.read(1024 ** 2), b""):
                if _ADMISSION_BUDGET is not None:
                    need(rr.Reader.cpu() + 10 < _ADMISSION_BUDGET["CPU"] and
                         time.time() + 10 < _ADMISSION_BUDGET["expires_epoch"],
                         "source/runtime proof exhausted whole-study admission reserve")
                digest.update(block)
        need(rr._identity(os.fstat(fd)) == rr._identity(before) == rr._identity(rr.physical_path(path).stat()),
             "source/runtime changed during hash")
    finally:
        os.close(fd)
    return dict(path=str(path), sha256=digest.hexdigest())


def verify(value):
    need(type(value) is dict and set(value) == {"path", "sha256"}, "exact immutable source/runtime pin required")
    need(pin(value["path"]) == value, "source/runtime pin differs: " + value["path"])
    return value


def read(value):
    need(type(value) is dict and set(value) == {"path", "sha256"} and
         Path(value["path"]).suffix == ".json", "only exact JSON metadata pins may be parsed")
    need(rr.physical_path(value["path"]).stat().st_size <= rr.MAX_JSON_BYTES, "metadata exceeds bounded JSON size")
    verify(value)
    return rr.Reader().read(value)


def atomic_json(path, value):
    path = rr.physical_path(path)
    need(path.parent.is_dir(), "authority/output parent directory must already exist")
    raw = rr.json_bytes(value)
    need(len(raw) <= rr.MAX_JSON_BYTES, "metadata output exceeds ceiling")
    temporary = path.with_name("." + path.name + ".pending." + str(os.getpid()) + "." + str(time.monotonic_ns()))
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(raw); stream.flush(); os.fsync(stream.fileno())
        os.link(temporary, path, follow_symlinks=False)
    finally:
        if temporary.exists(): temporary.unlink()
    directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try: os.fsync(directory_fd)
    finally: os.close(directory_fd)
    return dict(path=str(path), sha256=hashlib.sha256(raw).hexdigest())


def draft_policy(policy):
    value = dict(policy)
    value["status"] = "PROPOSED_DISTINCT_PROSPECTIVE_SYNTHETIC_STUDY"
    value.pop("root_authorization", None)
    return value


def validate_policy(policy, *, now, metadata_reader=read):
    need(policy.get("schema") == POLICY_SCHEMA and policy.get("status") == POLICY_STATUS and
         policy.get("purpose") == PURPOSE, "new distinct admitted R164 policy required")
    study = policy.get("study_id")
    need(isinstance(study, str) and re.fullmatch(r"r164-projection-toy-[A-Za-z0-9_-]{8,100}", study), "new unique study identity required")
    need(finite(now) and all(finite(policy.get(k)) for k in ("created_epoch", "expires_epoch")) and
         policy["created_epoch"] <= now < policy["expires_epoch"] and
         0 < policy["expires_epoch"] - policy["created_epoch"] <= 7200,
         "new finite prospective policy window required")
    fixed = dict(max_new_numerical=1, host="muscat", science_cpus=[30], physical_guard_cpus=[30, 62],
                 max_workers=1, memory_GiB=8, SMT62_science_authorized=False,
                 CPU31_SMT63_reserved=True, maximum_new_attempts=1,
                 HB_profile_overlap_authorized=False,
                 maximum_combined_CPU_seconds=300, maximum_wall_seconds=1800,
                 old_pool_clock_inherited=False, old_costs_refunded=False,
                 old_claims_reopened=False, old_contracts_mutated=False,
                 allocation_relationship="DISTINCT_NEW_ALLOCATION_NO_OLD_FUNDS")
    need(all(policy.get(k) == v and type(policy.get(k)) is type(v) for k, v in fixed.items()), "new policy resource/history bounds differ")
    need(policy["prior_global_contract"]["sha256"] == OLD_POOL_SHA and
         policy["prior_resource_policy"]["sha256"] == OLD_POLICY_SHA,
         "relabelled or expiry-edited old authority is prohibited")
    need(policy.get("prior_failed_grant") == dict(path=str(OLD_TOY), sha256=OLD_TOY_SHA),
         "exact historical failed grant must remain pinned")
    old, old_resource = metadata_reader(policy["prior_global_contract"]), metadata_reader(policy["prior_resource_policy"])
    need(old.get("schema") == "r154_global_permits_v1" and old["expires_epoch"] == old_resource["expires_epoch"] and
         old["expires_epoch"] <= policy["created_epoch"], "old expired pool must remain unchanged historical evidence")
    need(policy.get("prior_clock") == {"created_epoch": old["created_epoch"], "expires_epoch": old["expires_epoch"]},
         "old clock identity changed")
    need(policy.get("lock", {}).get("path") == str(LEGACY_LOCK) and str(LEGACY_LOCK.parent) == old["lock_dir"] and
         type(policy["lock"].get("device")) is int and type(policy["lock"].get("inode")) is int and policy["lock"]["inode"] > 0,
         "same original physical permit lock device/inode required")
    for key in ("owner_admission_dir", "claim_registry_dir", "output_dir"):
        rr.physical_path(policy[key])
    need(Path(policy["owner_admission_dir"]) != Path(policy["claim_registry_dir"]) and
         not Path(policy["output_dir"]).is_relative_to(Path(policy["claim_registry_dir"])), "canonical authority directories overlap")
    authorization = metadata_reader(policy["root_authorization"])
    need(authorization.get("schema") == "r164_distinct_study_root_authorization_v1" and
         authorization.get("status") == "ROOT_REVIEWED_NEW_PROSPECTIVE_SYNTHETIC_STUDY" and
         authorization.get("study_id") == study and
         authorization.get("policy_draft_sha256") == identity(draft_policy(policy)) and
         authorization.get("source_bindings") == policy["execution_source_bindings"] and
         authorization.get("maximum_combined_CPU_seconds") == 300 and
         authorization.get("old_costs_refunded") is False and authorization.get("authorizes_production_fits") is False,
         "root source review/new distinct funding authority absent")
    return policy


def validate_grant(grant, pool, policy, *, now, metadata_reader=read):
    validate_policy(policy, now=now, metadata_reader=metadata_reader)
    need(pool.get("schema") == POOL_SCHEMA and pool.get("purpose") == PURPOSE and
         pool.get("study_id") == policy["study_id"] and pool.get("max_new_numerical") == 1 and
         pool.get("expires_epoch") == policy["expires_epoch"] and pool.get("created_epoch") == policy["created_epoch"] and
         pool.get("lock_dir") == str(LEGACY_LOCK.parent) and pool.get("old_pool_renewed") is False,
         "new global contract identity/resource window differs")
    need(grant.get("schema") == GRANT_SCHEMA and grant.get("purpose") == PURPOSE and
         grant.get("status") == "ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY" and
         grant.get("study_id") == policy["study_id"] == grant.get("scope_id"), "not the new R164 study grant")
    need(finite(grant.get("created_epoch")) and policy["created_epoch"] <= grant["created_epoch"] <= now,
         "new grant must be prospectively issued within its new policy")
    expected = dict(authorizes_toy_optimizer=True, authorizes_production_fits=False,
                    authorizes_production_acceptance=False, maximum_optimizer_invocations=8,
                    maximum_total_optimizer_iterations=30, maximum_n=128, maximum_p=32,
                    host="muscat", affinity=[30], cores=1, memory_GiB=8, permit_id="muscat_cpu30",
                    maximum_new_attempts=1, attempt_index=1, old_costs_refunded=False,
                    old_claims_reopened=False, old_pool_clock_inherited=False)
    need(all(grant.get(k) == v and type(grant.get(k)) is type(v) for k, v in expected.items()), "new grant synthetic/physical/history bounds changed")
    need(all(finite(grant.get(k)) and grant[k] > 0 for k in
             ("maximum_CPU_seconds", "maximum_combined_CPU_seconds", "maximum_wall_seconds", "stage_deadline_epoch")), "finite grant limits required")
    need(grant["maximum_CPU_seconds"] <= grant["maximum_combined_CPU_seconds"] - 10 <= 290 and
         grant["maximum_wall_seconds"] <= 1800, "new grant exceeds300CPU/1800wall or lacks finalization reserve")
    expiry = dt.datetime.fromisoformat(grant["expires_UTC"])
    need(expiry.tzinfo is not None, "timezone-aware exact stage expiry required")
    need(now + grant["maximum_wall_seconds"] <= expiry.timestamp() <= grant["stage_deadline_epoch"] <= policy["expires_epoch"],
         "whole new one-shot study cannot fit prospective window")
    need(grant.get("source") == dict(kind=SOURCE_KIND, branch="work/pricefm-r157-native-bootstrap-20261028", head=rr.NATIVE_HEAD),
         "unchanged frozen scientific source identity required")
    need(grant.get("output_dir") == policy["output_dir"] and
         grant.get("source_bindings") == policy["execution_source_bindings"], "exact output/source closure differs")
    need(type(grant.get("paid_history_pins")) is list and len(grant["paid_history_pins"]) >= 3, "all old paid history must be retained")
    history = {p["path"] for p in grant["paid_history_pins"]}
    need({str(p) for p in OLD_COSTS} <= history, "known paid failed attempts omitted")
    old_grant = metadata_reader(policy["prior_failed_grant"])
    need(all(value in grant["paid_history_pins"] for value in old_grant["paid_history_pins"]),
         "historical funding/charges/source proof chain omitted")
    for value in grant["paid_history_pins"]:
        metadata_reader(value)
    return grant


def validate_owner_admission(admission, grant, grant_pin, pool_pin, policy, policy_pin, *, now):
    expected = dict(schema="r164_distinct_study_owner_admission_v1", status="ROOT_ADMITTED_EXACT_NEW_STUDY_OWNER",
                    study_id=policy["study_id"], scope_id=grant["scope_id"], stage_grant=grant_pin,
                    global_contract=pool_pin, resource_policy=policy_pin, lock=policy["lock"],
                    science_cpus=[30], physical_guard_cpus=[30, 62], max_workers=1,
                    old_clock_renewed=False, authorizes_production_fits=False)
    need(all(admission.get(k) == v and type(admission.get(k)) is type(v) for k, v in expected.items()),
         "canonical new owner admission does not bind actual grant/policy/lock")
    need(finite(admission.get("started_epoch")) and finite(admission.get("expires_epoch")) and
         policy["created_epoch"] <= grant["created_epoch"] <= admission["started_epoch"] <= now <
         admission["expires_epoch"] == dt.datetime.fromisoformat(grant["expires_UTC"]).timestamp(),
         "owner admission clock differs")
    need("owner_admission_pin" not in grant and "owner_handoff" not in grant,
         "new owner protocol cannot be replaced by circular or expired old-policy handoff")
    return admission


def priority_ready(value, *, now=None, metadata_reader=read):
    now = time.time() if now is None else now
    proof = metadata_reader(value)
    need(proof.get("status") == "EE_LV_SUCCESS_AND_PHYSICAL_DRAIN_VERIFIED" and
         finite(proof.get("observed_epoch")) and 0 <= now - proof["observed_epoch"] <= 60,
         "fresh original EE/LV success and drain proof required")
    for key, expected in (("EE_exit", "COMPLETE_INITIAL_PREFIX"), ("LV_exit", "COMPLETE_DIAGNOSTIC")):
        need(metadata_reader(proof[key]).get("status") == expected, "priority exit failed")
    need(all(proof.get(k) is True for k in ("no_live_owned_numerical_lifetimes", "no_pending_refill", "shared_permit_physically_free")),
         "original priority lifetimes/refill/permit not proven drained")
    return proof


def _git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True, timeout=20).strip()


def load_native(grant):
    """Private namespace, after every executable source pin has been verified."""
    source = NATIVE_ROOT / "application/scripts/pricefm/527_native_runtime.py"
    spec = importlib.util.spec_from_file_location("r164_pinned_frozen_native_runtime", source)
    native = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(native)
    native.grant_compatibility(grant)
    return native


def execution_source_paths(config):
    paths = {str(NATIVE_ROOT / p) for p in (
        "application/scripts/pricefm/527_native_runtime.py", "application/scripts/pricefm/526_traced_bootstrap_guard.py",
        "application/scripts/pricefm/525_owned_stage_guard.py", "application/scripts/pricefm/527_project_bootstrap.R",
        "application/tests/526_native_metadata_wrapper.R", "application/tests/525_source_metadata_test.R",
        "application/tests/525_project_projection_toy_validation.R", "application/tests/525_finalize_projection_validation.py",
        "application/R/526_scientific_boundary.c", "application/R/524_toy_fullstate_consumer.R",
        "application/R/525_project_fullstate_consumer.R", "application/R/pricefm_r129_al_fixedpoint_certificate.R")}
    paths.update((str(NATIVE_ROOT / "application/config/pricefm/525_conditional_pilot_plan.json"),
                  config["original_manifest"]["path"], config["fixedpoint_helper_source"]["path"],
                  str(Path(__file__).resolve()), str(Path(rr.__file__).resolve())))
    return paths


def validate_priority_plan(plan, *, now, metadata_reader=read):
    need(plan.get("schema") == "r164_priority_drain_observation_plan_v1" and
         plan.get("status") == "ROOT_ADMITTED_METADATA_PRIORITY_DRAIN_CAPTURE_ONLY" and
         plan.get("maximum_combined_CPU_seconds") == 20 and plan.get("maximum_wall_seconds") == 60 and
         plan.get("affinity") == [31] and plan.get("actual_target_inputs") is False and
         plan.get("optimizer_invocations") == 0 and plan.get("old_scope_renewed") is False,
         "new distinct20CPU/60wall zero-numerical metadata plan required")
    policy = metadata_reader(plan["resource_policy"])
    validate_policy(policy, now=now, metadata_reader=metadata_reader)
    need(plan.get("study_id") == policy["study_id"] and plan.get("original_lock_identity") == policy["lock"] and
         plan.get("old_global_contract") == policy["prior_global_contract"], "metadata plan new study/original lock differs")
    expiry = dt.datetime.fromisoformat(plan["expires_UTC"])
    need(expiry.tzinfo is not None and now + 60 <= expiry.timestamp() <= policy["expires_epoch"], "new metadata whole calendar unavailable")
    scope = metadata_reader(plan["administrative_scope"])
    need(scope.get("maximum_CPU_seconds") == 20 and scope.get("maximum_wall_seconds") == 60 and
         scope.get("admin_cpu") == 31 and scope.get("new_numerical_calls") == 0 and
         scope["issued_epoch"] <= now and expiry.timestamp() <= scope["expires_epoch"],
         "separately funded new administrative capture scope required")
    return policy


def capture_priority(plan_pin, output):
    """Reobserve unchanged historical callers under a genuinely new metadata scope."""
    started = time.monotonic()
    plan = read(plan_pin)
    need(os.sched_getaffinity(0) == {31} and os.path.realpath("/proc/self/exe") == os.path.realpath(PYTHON) and
         sys.dont_write_bytecode and not {"numpy", "scipy", "pandas"}.intersection(sys.modules), "pinned metadata-only Python/CPU31 required")
    policy = validate_priority_plan(plan, now=time.time())
    need(pin(Path(__file__).resolve()) in policy["execution_source_bindings"] and
         pin(Path(rr.__file__).resolve()) in policy["execution_source_bindings"], "metadata producer differs from reviewed new policy source")
    need(_git(NATIVE_ROOT, "rev-parse", "HEAD") == rr.NATIVE_HEAD and not _git(NATIVE_ROOT, "status", "--porcelain"),
         "frozen native observer source changed")
    supplied = {x["path"]: x for x in plan["source_bindings"]}
    need(len(supplied) == len(plan["source_bindings"]) <= 64, "bounded unique observer source closure required")
    for value in supplied.values():
        need(Path(value["path"]).suffix == ".py" and rr.physical_path(value["path"]).stat().st_size <= rr.MAX_JSON_BYTES,
             "observer closure must contain bounded Python source only")
        verify(value)
    source = NATIVE_ROOT / "application/scripts/pricefm/527_observe_priority_drain.py"
    required = {str(source), str(NATIVE_ROOT / "application/scripts/pricefm/526_traced_bootstrap_guard.py"),
                str(NATIVE_ROOT / "application/scripts/pricefm/525_owned_stage_guard.py"), str(Path(__file__).resolve()), str(Path(rr.__file__).resolve())}
    need(required <= set(supplied), "complete versioned observer/bootstrap/physical-guard source pins required")
    spec = importlib.util.spec_from_file_location("r164_frozen_priority_metadata", source)
    observer = importlib.util.module_from_spec(spec); spec.loader.exec_module(observer)
    need(set(plan["observers"]) == set(observer.NAMES), "exact original EE/LV/successor observer set required")
    for role, value in plan["observers"].items():
        need(Path(value["entry_pin"]["path"]).name == observer.NAMES[role], "observer role/source differs")
        verify(value["entry_pin"]); read(value["authority_pin"])
        if role == "successor": read(value["preparation_pin"])
        need(all(supplied.get(p["path"]) == p for p in observer.metadata_import_closure(value["entry_pin"]["path"])),
             "observer top-level metadata import closure differs")
    out = rr.physical_path(output)
    need(str(out) == plan["output_dir"] and not out.exists() and out.parent.is_dir(), "new exact metadata output required")
    out.mkdir(mode=0o700); success = False
    try:
        atomic_json(out / "capture_plan_pin.json", plan_pin)
        rows = {}
        with (out / "private_metadata.lock").open("x+") as stream:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            for role in ("EE", "LV", "successor"):
                rows[role] = observer.run_observer(role, plan["observers"][role], plan, out, stream.fileno())
        proof = observer.validate_observations(rows, plan, time.time())
        old_pool = read(policy["prior_global_contract"])
        original_lock = observer.probe_original_lock(old_pool, policy["lock"])
        physical_path = NATIVE_ROOT / "application/scripts/pricefm/525_owned_stage_guard.py"
        spec = importlib.util.spec_from_file_location("r164_frozen_physical_pair_metadata", physical_path)
        physical = importlib.util.module_from_spec(spec); spec.loader.exec_module(physical)
        census = read(plan["physical_peer_census"])
        need(finite(census.get("observed_epoch")) and 0 <= time.time() - census["observed_epoch"] <= 60,
             "fresh review-bound physical-peer census required")
        try:
            pair = physical.physical_peer_guard(census, out)
        except BaseException as error:
            atomic_json(out / "physical_peer_failure.json", dict(status="BLOCKED_CURRENT_PHYSICAL_PEER_GUARD",
                observed_epoch=time.time(), original_guard_source=supplied[str(physical_path)],
                peer_census_pin=plan["physical_peer_census"], error_type=type(error).__name__, error=str(error),
                no_claim_or_optimizer=True))
            raise
        need(rr.Reader.cpu() < 18 and time.monotonic() - started < 58, "metadata capture finalization reserve exhausted")
        proof.update(schema="r164_fresh_priority_drain_v1", status="EE_LV_SUCCESS_AND_PHYSICAL_DRAIN_VERIFIED",
            observed_epoch=time.time(), shared_permit_physically_free=True, original_lock_probe=original_lock,
            current_physical_pair_guard=pair, capture_plan_pin=plan_pin, old_scope_renewed=False,
            source_bindings=plan["source_bindings"], observer_pins={k: pin(out / (k + ".stdout.json")) for k in rows},
            optimizer_invocations=0, actual_target_inputs=False, requires_capture_accounting_review=True)
        result = atomic_json(out / "priority_drain.json", proof)
        success = True
        return result
    finally:
        atomic_json(out / "capture_accounting.json", dict(status="COMPLETE_METADATA_ONLY_AWAIT_ROOT_REAP_ACCOUNTING" if success else "FAILED_COST_RETAINED",
            whole_combined_CPU_seconds=rr.Reader.cpu(), whole_wall_seconds=time.monotonic() - started,
            old_costs_refunded=False, optimizer_invocations=0, actual_target_inputs=False, capture_plan_pin=plan_pin))


def authority(grant_pin, output, *, now=None):
    global _ADMISSION_BUDGET
    now = time.time() if now is None else now
    need(os.sched_getaffinity(0) == {31} and os.path.realpath("/proc/self/exe") == os.path.realpath(PYTHON),
         "pinned administrative interpreter on CPU31 required")
    need(socket.gethostname().split(".")[0] == "muscat", "new study is Muscat-only")
    grant = read(grant_pin); pool_pin = grant["global_contract"]; pool = read(pool_pin)
    policy_pin = pool["resource_policy"]; policy = read(policy_pin)
    validate_grant(grant, pool, policy, now=now)
    _ADMISSION_BUDGET = dict(CPU=grant["maximum_combined_CPU_seconds"],
                             expires_epoch=dt.datetime.fromisoformat(grant["expires_UTC"]).timestamp())
    need(grant.get("resource_policy") == policy_pin, "grant/pool new policy differs")
    lock = rr.physical_path(LEGACY_LOCK).stat()
    need(policy["lock"] == dict(path=str(LEGACY_LOCK), device=lock.st_dev, inode=lock.st_ino), "original lock inode/device changed")
    adapter_root = Path(__file__).resolve().parents[4]
    adapter = grant["execution_adapter_source"]
    need(adapter == dict(kind="R164_distinct_prospective_projection_authority", branch=_git(adapter_root, "branch", "--show-current"),
                         head=_git(adapter_root, "rev-parse", "HEAD")) and
         adapter["branch"].startswith("work/pricefm-r164-") and not _git(adapter_root, "status", "--porcelain"),
         "new adapter must be exactly published/reviewed clean feature source")
    need(_git(NATIVE_ROOT, "rev-parse", "HEAD") == rr.NATIVE_HEAD and not _git(NATIVE_ROOT, "status", "--porcelain"),
         "frozen native source HEAD/worktree changed")
    cfg_path = NATIVE_ROOT / "application/config/pricefm/525_conditional_pilot_plan.json"
    cfg = read(pin(cfg_path))
    need(cfg["caps"] == {"AL": 300, "Normal": 2000} and cfg["original_manifest"]["sha256"] == rr.MANIFEST_SHA256,
         "unchanged frozen scientific plan/caps required")
    required = execution_source_paths(cfg)
    bindings = grant["source_bindings"]
    need(0 < len(bindings) <= 64 and len({p["path"] for p in bindings}) == len(bindings) and required <= {p["path"] for p in bindings},
         "complete frozen scientific/guard/new-adapter source closure required")
    for value in bindings:
        need(Path(value["path"]).suffix.lower() in (".py", ".r", ".c", ".json"), "payload cannot be an execution source")
        need(rr.physical_path(value["path"]).stat().st_size <= rr.MAX_JSON_BYTES, "execution source exceeds bounded metadata size")
        verify(value)
    need(grant["actual_R_runtime_binding"] == cfg["actual_R_runtime_binding"] and
         grant["expected_stock_body_sha256"] == cfg["expected_stock_body_sha256"], "actual runtime/stock body differs")
    runtime = read(grant["actual_R_runtime_binding"])
    verify(dict(path=runtime["actual_executable"], sha256=runtime["actual_executable_sha256"]))
    verify(dict(path=runtime["Rscript"], sha256=runtime["Rscript_sha256"]))
    for path, digest in runtime["loaded_shared_object_sha256"].items(): verify(dict(path=path, sha256=digest))
    for relative, digest in runtime["package_files_sha256"].items():
        verify(dict(path=str(Path(runtime["package_path"]) / relative), sha256=digest))
    native = load_native(grant)
    need(grant["bootstrap_exec_allowlist"] == native.exec_allowlist(runtime) and
         grant["cran_library"] == str(Path(runtime["package_path"]).parent), "native bootstrap/package closure differs")
    now = time.time()
    need(now + grant["maximum_wall_seconds"] <= dt.datetime.fromisoformat(grant["expires_UTC"]).timestamp(),
         "source/runtime verification consumed the complete stage calendar")
    publication = read(grant["source_publication_readback"])
    need(publication.get("status") == "ROOT_VERIFIED_FRESH_GIT_REMOTE_READBACK" and
         publication.get("native_head") == rr.NATIVE_HEAD and publication.get("execution_adapter_source") == adapter and
         finite(publication.get("observed_epoch")) and 0 <= now - publication["observed_epoch"] <= 600,
         "fresh exact native/adapter remote publication readback required")
    admission_pin = pin(Path(policy["owner_admission_dir"]) / (grant["scope_id"] + ".json"))
    validate_owner_admission(read(admission_pin), grant, grant_pin, pool_pin, policy, policy_pin, now=now)
    priority_ready(grant["priority_drain_pin"], now=now)
    sequencing = read(grant["additional_experiment_sequencing_pin"])
    need(sequencing.get("status") == "ROOT_VERIFIED_ADDITIONAL_EXPERIMENTS_SEQUENCED" and
         sequencing.get("HB_profile_jobs_active") == [] and sequencing.get("HB_profile_jobs_pending") == [] and
         sequencing.get("other_new_local_numerical_workers") == 0 and
         sequencing.get("baseline_continues_unchanged") is True and
         finite(sequencing.get("observed_epoch")) and 0 <= now - sequencing["observed_epoch"] <= 60,
         "additional local toy and HB profile experiments must be sequenced with fresh proof")
    out = rr.physical_path(output)
    need(str(out) == policy["output_dir"] and not out.exists() and out.parent.is_dir(), "exact new study output required")
    census = read(pool["peer_census"])
    need(finite(census.get("observed_epoch")) and 0 <= now - census["observed_epoch"] <= 60,
         "fresh hash-bound physical-peer census required")
    return grant, pool, policy, runtime, native, out, admission_pin, census


def held_lock(fd, expected, native):
    actual = native.legacy.verify_held_flock(fd)
    need(actual["device"] == expected["device"] and actual["inode"] == expected["inode"], "held original flock identity differs")
    return actual


def finalize(core_pin, grant_pin, guard_pin, native, output):
    """New protocol finalizer; original scientific pass criteria are unchanged."""
    core, grant, guard = read(core_pin), read(grant_pin), read(guard_pin)
    need(grant["schema"] == GRANT_SCHEMA and grant.get("status") == "ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY" and
         grant.get("authorizes_toy_optimizer") is True and grant["authorizes_production_fits"] is False and
         grant["authorizes_production_acceptance"] is False and
         all(type(grant.get(k)) is int and grant[k] == v for k, v in
             (("maximum_optimizer_invocations", 8), ("maximum_total_optimizer_iterations", 30), ("maximum_n", 128), ("maximum_p", 32))),
         "synthetic new-protocol grant required")
    read(grant["actual_R_runtime_binding"])
    native.require_completed(guard); native.grant_compatibility(grant)
    need(core.get("schema") == "r154_project_adapter_validation_core_v1" and
         core.get("status") == "NUMERICAL_PASS_AWAIT_OWNED_GUARD_REAP_PROOF" and
         core.get("root_grant_pin") == grant_pin and core.get("source") == grant["source"] and
         core.get("actual_R_runtime_binding") == grant["actual_R_runtime_binding"] == guard.get("actual_R_runtime_binding"),
         "core source/runtime/admission differs")
    need(guard.get("root_grant_sha256") == grant_pin["sha256"] and guard.get("source") == grant["source"] and
         guard.get("execution_adapter_source") == grant["execution_adapter_source"] and
         guard.get("validation_core_pin") == core_pin and guard.get("validation_kind") == "synthetic_project_projection_only" and
         guard.get("launcher") == "pinned_native_ELF_no_Rscript_shell_wrapper", "exact new owned numerical run unproved")
    for value in grant["source_bindings"]: verify(value)
    for key, name in (("entrypoint_pin", "525_project_projection_toy_validation.R"), ("wrapper_entrypoint_pin", "527_project_bootstrap.R")):
        need(guard.get(key) in grant["source_bindings"] and Path(guard[key]["path"]).name == name, "actual scientific entrypoint unbound")
    for key in ("toy_default_and_import_parity_pass", "checkpoint_all_factors_schedules_RNG_IO_verified",
                "stock_AST_exactly_preserved", "no_production_data_used", "production_gate_unchanged_and_rejects_synthetic"):
        need(core.get(key) is True, "scientific parity/checkpoint criterion failed: " + key)
    need(all(type(core.get(k)) is int and core[k] == v for k, v in
             (("toy_optimizer_invocations", 8), ("total_toy_optimizer_iterations", 30), ("maximum_n", 128), ("maximum_p", 32),
              ("production_fit_invocations", 0), ("production_passflags_written", 0))) and
         core.get("stock_body_sha256") == grant["expected_stock_body_sha256"], "scientific shape/call/AST scope changed")
    groups = core.get("checkpoints", [])
    need(isinstance(groups, list) and [x.get("count") for x in groups] == [4, 4, 1, 4], "exact checkpoint inventory omitted")
    for group in groups:
        need(str(group.get("label", "")).startswith("synthetic_NONCANDIDATE_") and
             [x.get("completed_sweep") for x in group["entries"]] == list(range(1, group["count"] + 1)), "checkpoint sequence/origin differs")
        for item in group["entries"]:
            need(Path(item["state_pin"]["path"]).is_relative_to(Path(core_pin["path"]).parent), "checkpoint outside synthetic output")
            verify(item["state_pin"])
    result = dict(core, schema="r164_project_adapter_validation_v1", status="PASS_SYNTHETIC_PROJECT_ADAPTER_VALIDATION_ONLY",
                  execution_adapter_source=grant["execution_adapter_source"], validation_core_pin=core_pin,
                  owned_guard_receipt_pin=guard_pin, resource_accounting_required_before_production=True,
                  numerical_production_admission=False, old_clock_renewed=False)
    return atomic_json(output, result)


def execute(grant_pin, output):
    started = time.monotonic()
    grant, pool, policy, runtime, native, out, admission_pin, census = authority(grant_pin, output)
    guard = native.traced
    lock_fd = os.open(LEGACY_LOCK, os.O_RDWR | os.O_NOFOLLOW)
    claim_started = False
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        lock_proof = held_lock(lock_fd, policy["lock"], native)
        priority_ready(grant["priority_drain_pin"])
        sequencing = read(grant["additional_experiment_sequencing_pin"])
        need(0 <= time.time() - sequencing["observed_epoch"] <= 60 and sequencing["HB_profile_jobs_active"] == [] and
             sequencing["HB_profile_jobs_pending"] == [], "HB profile sequencing proof stale or an experiment remains")
        peer = lambda owned: native.physical_peer_guard(census, out.parent, owned)
        peer([])
        need(time.time() + grant["maximum_wall_seconds"] <= dt.datetime.fromisoformat(grant["expires_UTC"]).timestamp(),
             "source/peer checks consumed unpriced whole-study window")
        claim = dict(schema="r164_distinct_study_claim_v1", study_id=policy["study_id"], stage_grant=grant_pin,
                     global_contract=grant["global_contract"], old_costs_refunded=False, original_lock=lock_proof,
                     numerical_production_admission=False, observed_epoch=time.time())
        atomic_json(Path(policy["claim_registry_dir"]) / (policy["study_id"] + ".json"), claim)
        claim_started = True
        out.mkdir(mode=0o700)
        atomic_json(out / "claim.json", claim)
        os.sched_setaffinity(0, {30}); os.setpriority(os.PRIO_PROCESS, 0, 10)
        subprocess.run(["ionice", "-c", "3", "-p", str(os.getpid())], check=True, capture_output=True, timeout=10)
        env = native.native_environment(dict(os.environ, R154_PROJECT_PROJECTION_TOY_ROOT_ADMITTED="1",
            R154_GLOBAL_PERMIT_LOCK_FD=str(lock_fd), R157_PROJECT_ROOT=str(NATIVE_ROOT), R157_PROJECT_KIND="toy"), runtime, grant["boundary_library_pin"])
        target = out / "projection"
        command = native.native_command(runtime, NATIVE_ROOT, "toy", [NATIVE_ROOT, Path(grant_pin["path"]), grant_pin["sha256"], target])
        def limits():
            resource.setrlimit(resource.RLIMIT_AS, (8 * 1024 ** 3,) * 2)
            resource.setrlimit(resource.RLIMIT_FSIZE, (16 * 1024 ** 2,) * 2)
            resource.setrlimit(resource.RLIMIT_CPU, (int(grant["maximum_CPU_seconds"]),) * 2)
        capture_count, last_capture = [0], [None, 0.]
        def owner_capture(fd, phase, proof):
            need(proof.get("kernel_trace_owned") is True and proof.get("all_helpers_owned") is True and
                 proof.get("state") != "UNREAPED_BLOCKED", "blocked/unowned trace cannot become an approved owner")
            signature = (phase, proof.get("state"))
            if signature == last_capture[0] and time.monotonic() - last_capture[1] < 10:
                return
            validate_owner_admission(read(admission_pin), grant, grant_pin, grant["global_contract"], policy,
                                     grant["resource_policy"], now=time.time())
            capture_count[0] += 1
            atomic_json(out / ("owner_%04d.json" % capture_count[0]), dict(schema="r164_live_new_study_owner_v1",
                admission=admission_pin, grant=grant_pin, lock=held_lock(fd, policy["lock"], native),
                phase=phase, kernel_trace_proof=proof, exact_owner=native.traced.identity(os.getpid()), epoch=time.time()))
            last_capture[:] = [signature, time.monotonic()]
        with (out / "stdout.log").open("x") as stdout, (out / "stderr.log").open("x") as stderr:
            result = guard.run_traced(command, env=env, stdout=stdout, stderr=stderr, lock_fd=lock_fd,
                affinity={30}, wall_seconds=grant["maximum_wall_seconds"] - (time.monotonic() - started) - 10,
                maximum_combined_CPU_seconds=grant["maximum_combined_CPU_seconds"] - 10,
                absolute_deadline_UTC=grant["expires_UTC"], peer_callback=peer,
                bootstrap_exec_allowlist=grant["bootstrap_exec_allowlist"], owner_path=out / "owner.json",
                scope=grant["scope_id"], source=grant["source"], authority_pin=grant_pin, preexec_fn=limits,
                interval_seconds=.05, peer_interval_seconds=10, owner_capture_callback=owner_capture)
        result.update(source=grant["source"], execution_adapter_source=grant["execution_adapter_source"],
            root_grant_sha256=grant_pin["sha256"], actual_R_runtime_binding=grant["actual_R_runtime_binding"],
            launcher="pinned_native_ELF_no_Rscript_shell_wrapper", validation_kind="synthetic_project_projection_only",
            entrypoint_pin=pin(NATIVE_ROOT / "application/tests/525_project_projection_toy_validation.R"),
            wrapper_entrypoint_pin=pin(NATIVE_ROOT / "application/scripts/pricefm/527_project_bootstrap.R"),
            validation_core_pin=pin(target / "validation_core.json") if (target / "validation_core.json").is_file() else None)
        guard_pin = atomic_json(out / "owned_guard_receipt.json", result)
        need(native.completed(result), "numerical attempt failed or ownership incomplete; claim and all costs retained")
        held_lock(lock_fd, policy["lock"], native)
        need(sum(guard.cpu()) + 5 <= grant["maximum_combined_CPU_seconds"], "finalizer CPU reserve unavailable")
        validation = finalize(pin(target / "validation_core.json"), grant_pin, guard_pin, native, out / "validation.json")
        used_cpu, used_wall = sum(guard.cpu()), time.monotonic() - started
        accepted = used_cpu <= grant["maximum_combined_CPU_seconds"] and used_wall <= grant["maximum_wall_seconds"] and time.time() < dt.datetime.fromisoformat(grant["expires_UTC"]).timestamp()
        atomic_json(out / "resource_accounting.json", dict(status="COMPLETE_AWAIT_OUTER_REAP_ACCOUNTING" if accepted else "OVERRUN_RETAINED_NOT_ACCEPTED",
            schema="r164_new_study_resource_accounting_v1", root_grant_pin=grant_pin, whole_process_CPU_seconds=used_cpu,
            whole_wall_seconds=used_wall, maximum_combined_CPU_seconds=grant["maximum_combined_CPU_seconds"],
            maximum_wall_seconds=grant["maximum_wall_seconds"], old_costs_refunded=False, production_fits=0,
            validation=validation, numerical_production_admission=False,
            outer_root_driver_reap_and_full_parent_finalization_charge_required=True))
        need(accepted, "whole new-study accounting overrun; no production eligibility")
        return validation
    except BaseException as error:
        if claim_started:
            value = dict(status="FAILED_COST_RETAINED_NO_RETRY", whole_process_CPU_seconds=sum(guard.cpu()),
                whole_wall_seconds=time.monotonic() - started, old_costs_refunded=False, production_fits=0,
                error_type=type(error).__name__, error=str(error), root_grant_pin=grant_pin)
            destination = out / "failure_accounting.json" if out.is_dir() else Path(policy["claim_registry_dir"]) / (policy["study_id"] + "_failure.json")
            if not destination.exists(): atomic_json(destination, value)
        raise
    finally:
        os.close(lock_fd)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--root-grant")
    mode.add_argument("--priority-plan")
    parser.add_argument("--root-grant-sha256")
    parser.add_argument("--priority-plan-sha256")
    parser.add_argument("--output", required=True)
    parser.add_argument("--check-authority", action="store_true")
    args = parser.parse_args(argv)
    if args.priority_plan:
        need(args.priority_plan_sha256 and not args.check_authority, "exact metadata plan pin required; numerical check mode forbidden")
        resource.setrlimit(resource.RLIMIT_CPU, (20, 20))
        def expired(signum, frame): raise TimeoutError("new metadata producer60wall elapsed")
        signal.signal(signal.SIGALRM, expired); signal.setitimer(signal.ITIMER_REAL, 60)
        result = capture_priority(dict(path=str(rr.physical_path(args.priority_plan)), sha256=args.priority_plan_sha256), args.output)
        print(json.dumps(dict(status="PASS_NEW_METADATA_CAPTURE_ONLY_AWAIT_ROOT_REAP_ACCOUNTING", priority_drain=result), sort_keys=True))
        return
    need(args.root_grant_sha256, "exact new root grant pin required")
    value = dict(path=str(rr.physical_path(args.root_grant)), sha256=args.root_grant_sha256)
    if args.check_authority:
        grant, pool, policy, runtime, native, out, admission, census = authority(value, args.output)
        native.physical_peer_guard(census, out.parent, [])
        print("PASS R164 new-study authority and current physical-peer check only; no claim/lock/optimizer")
    else:
        print(json.dumps(dict(status="PASS_SYNTHETIC_PROJECTION_ONLY", validation=execute(value, args.output)), sort_keys=True))


if __name__ == "__main__":
    main()
