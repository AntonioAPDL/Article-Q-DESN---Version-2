"""Prospective cross-host policy, preserving the original local permit.

This module creates no job, claim, scientific grant or source mutation. The sole
Muscat controller may publish an explicitly admitted new packet; the old R154
packet, expiry and charges remain immutable. Policy is capacity, not science.
"""
from __future__ import annotations
import datetime as dt
import math
from pathlib import Path
import re
import socket
import time
import uuid
from . import registry as r

SCHEMA = "r157_cross_host_resource_policy_v1"
OWNER_SCHEMA = "r157_local_permit_owner_admission_v1"
OWNER = "muscat.be.ucsc.edu"
ADMITTED = "ADMITTED_CROSS_HOST_EXECUTION"
DRAFT = "PROPOSED_NOT_ADMITTED"
SHA = re.compile(r"[0-9a-f]{64}\Z")
STEPS = (1, 2, 4, 8, 16, 24, 48, 72)
MAX_METADATA = 16 * 1024**2


class PolicyError(ValueError):
    pass


LOCAL_STAGE_STATUSES = {
    "ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY",
    "ROOT_ADMITTED_REAL_ZERO_OPTIMIZER_BRIDGE_ONLY",
    "ROOT_ADMITTED_NEW_INITIALIZATION_PILOT_ONLY",
    "ROOT_ADMITTED_R157_PERMIT_HANDOFF_TEST",
    "ROOT_ADMITTED_R157_SYNTHETIC_PROJECT_PROOF",
}


def owner():
    if socket.getfqdn() != OWNER:
        raise PolicyError("only canonical Muscat may publish cross-host policy")


def pin(path):
    path = r.no_links(path)
    if not path.is_absolute() or not path.is_file():
        raise PolicyError("absolute regular evidence file required")
    return {"path": str(path), "sha256": r.digest(path)}


def pinned(value, *, parse=True, check_files=True):
    if (not isinstance(value, dict) or set(value) != {"path", "sha256"}
            or not isinstance(value["path"], str) or not Path(value["path"]).is_absolute()
            or ".." in Path(value["path"]).parts
            or not isinstance(value["sha256"], str) or not SHA.fullmatch(value["sha256"])):
        raise PolicyError("exact absolute path/SHA256 evidence pin required")
    if not check_files:
        return value
    path = r.no_links(value["path"])
    if not path.is_file() or r.digest(path) != value["sha256"]:
        raise PolicyError("missing or changed pinned evidence: " + str(path))
    if not parse:
        return path
    if path.stat().st_size > MAX_METADATA or path.suffix != ".json":
        raise PolicyError("bounded JSON metadata required")
    return r.read(path)


def finite_number(value):
    return type(value) in (int, float) and math.isfinite(value)


def source_pins(values, *, check_files=True):
    if not isinstance(values, list) or not values:
        raise PolicyError("complete nonempty source pin list required")
    paths = []
    for value in values:
        pinned(value, parse=False, check_files=check_files)
        paths.append(value["path"])
    if len(paths) != len(set(paths)):
        raise PolicyError("duplicate source paths")
    return values


def legacy_view(contract_pin, resource_pin):
    contract = pinned(contract_pin)
    resource = pinned(resource_pin)
    if (contract.get("schema") != "r154_global_permits_v1"
            or contract.get("max_new_numerical") != 1
            or contract.get("new_numerical_concurrency_above_one_authorized") is not False
            or contract.get("nonrenewing") is not True
            or contract.get("jerez_numerical_allocation") is not None
            or contract.get("SMT62_science_authorized") is not False
            or contract.get("all_original_allocation_clocks_ceilings_and_lock_identity_preserved") is not True
            or contract.get("evidence", {}).get("resource_policy") != resource_pin
            or contract.get("permits") != [{"cpu": 30, "host": "muscat", "id": "muscat_cpu30",
                                            "science": ["EE", "LV", "CERTIFICATE_REFERENCE"], "sequential": True}]):
        raise PolicyError("original local permit contract differs")
    if (resource.get("schema") != "r154_resource_policy_v1"
            or resource.get("max_new_numerical_workers") != 1
            or resource.get("nonrenewing") is not True
            or resource.get("physical_CPU_allocation", {}).get("cpu") != 30
            or resource["physical_CPU_allocation"].get("SMT62_additional_worker") is not False
            or resource.get("expires_epoch") != contract.get("expires_epoch")
            or resource.get("created_epoch") != contract.get("created_epoch")
            or resource.get("Jerez_new_predictive_or_repair_worker_admitted") is not False):
        raise PolicyError("original local resource policy differs")
    if (not finite_number(contract.get("created_epoch")) or not finite_number(contract.get("expires_epoch"))
            or contract["created_epoch"] >= contract["expires_epoch"]):
        raise PolicyError("original finite local clock invalid")
    lock = Path(contract["lock_dir"]) / "muscat_cpu30.lock"
    st = r.no_links(lock).stat()
    return {"contract": contract, "resource": resource,
            "lock": {"path": str(lock), "device": st.st_dev, "inode": st.st_ino}}


def build_policy(legacy_contract_pin, legacy_resource_pin, execution_sources,
                 approved_owner_sources, *, scope_id=None, expires_epoch,
                 owner_admission_dir, historical_EE_release=None, now=None):
    """Build a draft only. Root must separately admit the reviewed exact bytes."""
    owner()
    now = time.time() if now is None else now
    old = legacy_view(legacy_contract_pin, legacy_resource_pin)
    source_pins(execution_sources)
    if approved_owner_sources:
        source_pins(approved_owner_sources)
    directory = r.no_links(owner_admission_dir)
    if not directory.is_absolute():
        raise PolicyError("absolute new owner-admission directory required")
    policy = {"schema": SCHEMA, "status": DRAFT, "controller": OWNER,
              "scope_id": scope_id or ("r157-policy-" + uuid.uuid4().hex),
              "created_epoch": now, "expires_epoch": expires_epoch,
              "legacy_contract": legacy_contract_pin, "legacy_resource_policy": legacy_resource_pin,
              "legacy_created_epoch": old["contract"]["created_epoch"],
              "legacy_expires_epoch": old["contract"]["expires_epoch"],
              "local_permit": {"id": "muscat_cpu30", "host": OWNER, "science_cpus": [30],
                               "physical_guard_cpus": [30, 62], "max_workers": 1,
                               "expires_epoch": old["contract"]["expires_epoch"], "lock": old["lock"]},
              "HB_max_workers": 1, "HB_total_CPU_ceiling": 72,
              "Jerez_extra_workers": 0, "max_additional_numerical_workers": 2,
              "old_contracts_or_charges_mutated": False, "old_scope_renewed": False,
              "numerical_grant_created": False, "execution_sources": execution_sources,
              "approved_owner_sources": approved_owner_sources,
              "historical_EE_release": historical_EE_release,
              "owner_admission_dir": str(directory), "scale_amendments": [],
              "scientific_rules_changed": False, "baseline_allocations_changed": False,
              "authorization": None}
    validate_policy(policy, now=now, require_admitted=False)
    return policy


def admit_policy(draft, authorization_pin, *, now=None):
    """Pure root-side adoption; callers publish create-only after source review."""
    owner()
    now = time.time() if now is None else now
    validate_policy(draft, now=now, require_admitted=False)
    if draft["status"] != DRAFT:
        raise PolicyError("only a new draft may be admitted")
    evidence = pinned(authorization_pin)
    if (evidence.get("status") != "ROOT_REVIEWED_CROSS_HOST_IMPLEMENTATION_AUTHORIZATION"
            or evidence.get("controller") != OWNER or evidence.get("policy_draft_sha256") != r.identity(draft)
            or evidence.get("user_requested_implementation") is not True
            or evidence.get("old_local_clock_and_charges_preserved") is not True):
        raise PolicyError("reviewed exact policy adoption evidence required")
    result = dict(draft, status=ADMITTED, authorization=authorization_pin)
    validate_policy(result, now=now)
    return result


def validate_policy(packet, *, now=None, require_admitted=True, check_files=True):
    now = time.time() if now is None else now
    if (not isinstance(packet, dict) or packet.get("schema") != SCHEMA
            or packet.get("controller") != OWNER
            or packet.get("status") not in ({ADMITTED} if require_admitted else {ADMITTED, DRAFT})
            or not re.fullmatch(r"[A-Za-z0-9_-]{8,160}", str(packet.get("scope_id", "")))):
        raise PolicyError("explicit source-bound cross-host policy required")
    if (not finite_number(now) or not finite_number(packet.get("created_epoch"))
            or not finite_number(packet.get("expires_epoch"))
            or not packet["created_epoch"] <= now < packet["expires_epoch"]
            or packet["expires_epoch"] - packet["created_epoch"] > 86400):
        raise PolicyError("finite cross-host policy clock expired or invalid")
    if not check_files:
        pinned(packet.get("legacy_contract"), check_files=False)
        pinned(packet.get("legacy_resource_policy"), check_files=False)
    old = legacy_view(packet["legacy_contract"], packet["legacy_resource_policy"]) if check_files else None
    local = packet.get("local_permit", {})
    if (local.get("id") != "muscat_cpu30" or local.get("host") != OWNER
            or local.get("science_cpus") != [30] or local.get("physical_guard_cpus") != [30, 62]
            or local.get("max_workers") != 1
            or local.get("expires_epoch") != packet.get("legacy_expires_epoch")
            or not finite_number(local.get("expires_epoch"))
            or packet.get("Jerez_extra_workers") != 0
            or packet.get("HB_total_CPU_ceiling") != 72):
        raise PolicyError("original local assignment or conservative HB ceiling changed")
    lock = local.get("lock", {})
    if (not Path(lock.get("path", "")).is_absolute() or type(lock.get("device")) is not int
            or type(lock.get("inode")) is not int or lock["inode"] <= 0):
        raise PolicyError("exact original permit lock identity required")
    if old and (packet["legacy_created_epoch"] != old["contract"]["created_epoch"]
                or packet["legacy_expires_epoch"] != old["contract"]["expires_epoch"]
                or lock != old["lock"]):
        raise PolicyError("old permit clock or lock identity altered")
    for key in ("old_contracts_or_charges_mutated", "old_scope_renewed", "numerical_grant_created",
                "scientific_rules_changed", "baseline_allocations_changed"):
        if packet.get(key) is not False:
            raise PolicyError("policy cannot mutate or inherit scientific authority: " + key)
    source_pins(packet.get("execution_sources"), check_files=check_files)
    if not isinstance(packet.get("approved_owner_sources"), list):
        raise PolicyError("explicit approved-owner source list required")
    if packet["approved_owner_sources"]:
        source_pins(packet["approved_owner_sources"], check_files=check_files)
    if not Path(packet.get("owner_admission_dir", "")).is_absolute():
        raise PolicyError("canonical owner-admission directory absent")
    workers = 1
    amendments = packet.get("scale_amendments")
    if not isinstance(amendments, list):
        raise PolicyError("scale amendment list required")
    for record in amendments:
        if (record.get("from") != workers or type(record.get("to")) is not int
                or record["to"] not in STEPS or record["to"] <= workers
                or STEPS.index(record["to"]) != STEPS.index(workers) + 1
                or record.get("local_assignment_changed") is not False):
            raise PolicyError("HB scaling requires one measured prospective step")
        if check_files:
            evidence = pinned(record["evidence"])
            if (evidence.get("status") != "ROOT_ACCEPTED_MEASURED_HB_SCALE_STAGE"
                    or evidence.get("from") != workers or evidence.get("to") != record["to"]
                    or evidence.get("exact_outputs_validated") is not True
                    or evidence.get("all_regional_caps_preserved") is not True
                    or evidence.get("no_new_candidate_selection") is not True):
                raise PolicyError("measured scale evidence absent")
        else:
            pinned(record["evidence"], check_files=False)
        workers = record["to"]
    if (packet.get("HB_max_workers") != workers
            or packet.get("max_additional_numerical_workers") != 1 + workers):
        raise PolicyError("aggregate extra concurrency differs from declared matrix")
    if packet["status"] == ADMITTED:
        evidence = pinned(packet.get("authorization"), check_files=check_files)
        draft = dict(packet, status=DRAFT, authorization=None)
        if check_files and (evidence.get("status") != "ROOT_REVIEWED_CROSS_HOST_IMPLEMENTATION_AUTHORIZATION"
                or evidence.get("controller") != OWNER or evidence.get("policy_draft_sha256") != r.identity(draft)
                or evidence.get("user_requested_implementation") is not True
                or evidence.get("old_local_clock_and_charges_preserved") is not True):
            raise PolicyError("adopted policy lacks its exact reviewed draft")
        pinned(packet.get("historical_EE_release"), check_files=check_files)
    elif packet.get("authorization") is not None:
        raise PolicyError("draft cannot carry adopted authority")
    elif packet.get("historical_EE_release") is not None:
        pinned(packet["historical_EE_release"], check_files=check_files)
    return packet


def hb_concurrency(packet, *, now=None):
    """Pure extraction after the caller hash-validates the policy proof bytes."""
    validate_policy(packet, now=now, check_files=False)
    return packet["HB_max_workers"]


def build_scale_amendment(previous_pin, evidence_pin, *, scope_id, expires_epoch, now=None):
    """New prospective resource packet; no claimed grant or old clock changes."""
    owner()
    now = time.time() if now is None else now
    previous = pinned(previous_pin)
    validate_policy(previous, now=now)
    if scope_id != previous["scope_id"] or expires_epoch != previous["expires_epoch"]:
        raise PolicyError("capacity amendment cannot renew the existing policy scope/clock")
    evidence = pinned(evidence_pin)
    workers = previous["HB_max_workers"]
    index = STEPS.index(workers)
    if index + 1 >= len(STEPS):
        raise PolicyError("conservative HB ceiling already reached")
    target = STEPS[index + 1]
    if (evidence.get("status") != "ROOT_ACCEPTED_MEASURED_HB_SCALE_STAGE"
            or evidence.get("from") != workers or evidence.get("to") != target
            or evidence.get("exact_outputs_validated") is not True
            or evidence.get("all_regional_caps_preserved") is not True
            or evidence.get("no_new_candidate_selection") is not True):
        raise PolicyError("complete measured prior stage and prospectively priced next trial required")
    result = dict(previous, status=DRAFT, authorization=None, previous_policy=previous_pin,
                  amended_epoch=now,
                  HB_max_workers=target, max_additional_numerical_workers=1 + target,
                  scale_amendments=previous["scale_amendments"] + [
                      {"from": workers, "to": target, "evidence": evidence_pin,
                       "local_assignment_changed": False}])
    validate_policy(result, now=now, require_admitted=False)
    return result


def validate_owner_admission(value, packet, policy_pin, *, now=None, check_files=True):
    now = time.time() if now is None else now
    validate_policy(packet, now=now, check_files=check_files)
    if (value.get("schema") != OWNER_SCHEMA or value.get("status") != "ROOT_ADMITTED_EXACT_LOCAL_PERMIT_OWNER"
            or value.get("controller") != OWNER or value.get("cross_host_policy") != policy_pin
            or value.get("permit_id") != "muscat_cpu30" or value.get("science_cpus") != [30]
            or value.get("max_workers") != 1 or value.get("old_clock_renewed") is not False
            or not re.fullmatch(r"[A-Za-z0-9_-]{8,160}", str(value.get("scope_id", "")))
            or not finite_number(value.get("started_epoch"))
            or not finite_number(value.get("expires_epoch"))
            or not value["started_epoch"] <= now < value["expires_epoch"] <= packet["legacy_expires_epoch"]
            or value.get("owner_source") not in packet["approved_owner_sources"]):
        raise PolicyError("current successor is not exactly admitted on the old permit")
    pinned(value["owner_source"], parse=False, check_files=check_files)
    stage = pinned(value["stage_grant"], check_files=check_files)
    if check_files:
        if stage.get("status") == "ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY":
            expected = {"schema": "r157_projection_toy_grant_v1", "authorizes_toy_optimizer": True,
                        "authorizes_production_fits": False, "authorizes_production_acceptance": False,
                        "maximum_optimizer_invocations": 8, "maximum_total_optimizer_iterations": 30,
                        "maximum_n": 128, "maximum_p": 32, "memory_GiB": 8,
                        "maximum_new_attempts": 1, "attempt_index": 1, "old_costs_refunded": False}
            if (any(stage.get(k) != v or type(stage.get(k)) is not type(v) for k, v in expected.items())
                    or any(not finite_number(stage.get(k)) for k in
                           ("maximum_CPU_seconds", "maximum_combined_CPU_seconds", "maximum_wall_seconds"))
                    or not 0 < stage["maximum_CPU_seconds"] <= stage["maximum_combined_CPU_seconds"] - 10 <= 290
                    or not 0 < stage["maximum_wall_seconds"] <= 1800):
                raise PolicyError("toy handoff must retain exact synthetic shape/call/CPU/no-production bounds")
        expiry = stage.get("expires_epoch")
        if expiry is None and isinstance(stage.get("expires_UTC"), str):
            parsed = dt.datetime.fromisoformat(stage["expires_UTC"].replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                raise PolicyError("timezone-aware owner stage expiry required")
            expiry = parsed.timestamp()
        if (stage.get("status") not in LOCAL_STAGE_STATUSES
                or stage.get("host") not in ("muscat", OWNER) or stage.get("affinity") != [30]
                or stage.get("cores") != 1 or stage.get("permit_id") != "muscat_cpu30"
                or stage.get("global_contract") != packet["legacy_contract"]
                or value["owner_source"] not in stage.get("source_bindings", [])
                or not finite_number(expiry) or value["expires_epoch"] > expiry):
            raise PolicyError("successor stage identity/resource/clock differs")
    return value


def build_owner_admission(policy_pin, stage_grant_pin, owner_source, *, scope_id,
                          started_epoch, expires_epoch, now=None):
    """Root-reviewed envelope around an existing exact stage grant, no fit grant."""
    owner()
    now = time.time() if now is None else now
    packet = pinned(policy_pin)
    validate_policy(packet, now=now)
    stage = pinned(stage_grant_pin)
    if (stage.get("host") not in ("muscat", OWNER) or stage.get("affinity") != [30]
            or stage.get("cores") != 1 or stage.get("permit_id") != "muscat_cpu30"
            or stage.get("global_contract") != packet["legacy_contract"]
            or owner_source not in stage.get("source_bindings", [])):
        raise PolicyError("local stage does not bind original permit and exact owner source")
    result = {"schema": OWNER_SCHEMA, "status": "ROOT_ADMITTED_EXACT_LOCAL_PERMIT_OWNER",
              "controller": OWNER, "scope_id": scope_id,
              "cross_host_policy": policy_pin, "permit_id": "muscat_cpu30",
              "science_cpus": [30], "max_workers": 1, "started_epoch": started_epoch,
              "expires_epoch": expires_epoch, "owner_source": owner_source,
              "stage_grant": stage_grant_pin, "old_clock_renewed": False}
    validate_owner_admission(result, packet, policy_pin, now=now)
    return result
