"""Truthful closed-EE / shared-permit handoff evidence for independent HB work.

The old source529 observer stays unchanged. Its global-lock-free flag can be
false while the old EE owner is dead and a newly admitted repair owns the same
permit. Root-side build checks actual process/FD/flock identities. A remote
worker validates a fresh, hash-bound controller receipt, not Muscat /proc.
"""
from __future__ import annotations
import errno
import fcntl
import hashlib
import os
from pathlib import Path
import re
import time
from . import policy as p, registry as r

SCHEMA = "r157_ee_closed_permit_handoff_v1"
STATUS = "EE_CLOSED_RELEASED_PERMIT_HANDOFF_VERIFIED"
OWNER_RECEIPT_SCHEMA = "r157_live_local_permit_owner_v1"
IDENTITY_KEYS = ("pid", "start_ticks", "boot_id", "cmdline_sha256")
OWNER_PHASES = {"BOOTSTRAP", "SCIENCE", "FINALIZATION", "TEST_OWNER",
                "TRACED_BOOTSTRAP", "SCIENTIFIC_FORK_DENIED"}


class HandoffError(ValueError):
    pass


def fresh(epoch, now, seconds=300):
    return p.finite_number(epoch) and 0 <= now - epoch <= seconds


def identity_equal(left, right):
    return isinstance(left, dict) and isinstance(right, dict) and all(left.get(k) == right.get(k) for k in IDENTITY_KEYS)


def same_kernel_lifetime(left, right):
    return isinstance(left, dict) and isinstance(right, dict) and all(left.get(k) == right.get(k) for k in ("pid", "start_ticks", "boot_id"))


def process_identity(pid):
    if type(pid) is not int or pid <= 0:
        raise HandoffError("positive exact process PID required")
    root = Path("/proc") / str(pid)
    try:
        raw = (root / "cmdline").read_bytes()
        fields = (root / "stat").read_text().rsplit(")", 1)[1].split()
        if len(raw) > 131072:
            raise HandoffError("oversized process command")
        if fields[0] == "Z":
            return None
        boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        executable = (root / "exe").stat()
        return {"pid": pid, "start_ticks": int(fields[19]), "boot_id": boot,
                "cmdline_sha256": hashlib.sha256(raw).hexdigest(),
                "argv": raw.decode(errors="replace").rstrip("\0").split("\0"),
                "state": fields[0], "executable": os.readlink(root / "exe"),
                "executable_device": executable.st_dev, "executable_inode": executable.st_ino}
    except (FileNotFoundError, ProcessLookupError):
        return None
    except (OSError, ValueError, IndexError) as exc:
        raise HandoffError("unreadable actual process lifetime") from exc


def _unit(unit):
    if (not isinstance(unit, dict) or not unit.get("Id") or not unit.get("InvocationID")
            or unit.get("Result") != "success" or str(unit.get("ExecMainStatus")) != "0"
            or str(unit.get("MainPID")) != "0" or unit.get("SubState") != "exited"
            or unit.get("RemainAfterExit") != "yes" or unit.get("Restart") != "no"
            or str(unit.get("NRestarts")) != "0"):
        raise HandoffError("exact retained successful exited EE invocation required")
    return {key: unit[key] for key in ("Id", "InvocationID")}


def _record(raw, name):
    record = raw.get("records", {}).get(name)
    if not isinstance(record, dict):
        raise HandoffError("missing EE record: " + name)
    value = p.pinned(record.get("pin"))
    if value != record.get("value"):
        raise HandoffError("EE snapshot differs from pinned record: " + name)
    return value, record["pin"]


def _closed_ee(raw, *, historical=False):
    if (raw.get("status") != "READ_ONLY_SOURCE_BOUND_MATCHED_SEED_OBSERVATION"
            or raw.get("complete_components") != 12 or raw.get("required_components") != 12
            or raw.get("remaining_components") != 0 or raw.get("new_fits") != 0
            or raw.get("new_forecasts") != 0 or raw.get("runtime_writes") != 0
            or raw.get("signals") != 0):
        raise HandoffError("complete read-only twelve-component EE observation required")
    if historical and (raw.get("same_original_flock_free") is not True
            or raw.get("scientifically_complete_and_physically_drained") is not True):
        raise HandoffError("historical actual original-lock release absent")
    unit = _unit(raw.get("actual_unit"))
    processes = raw.get("processes", [])
    if ({x.get("role") for x in processes} != {"guardian.json", "payload_identity.json"}
            or len(processes) != 2 or any(x.get("live_exact_lifetime") is not False for x in processes)):
        raise HandoffError("old EE guardian/payload not both recorded dead")
    identities = {x["role"]: x.get("recorded") for x in processes}
    if any(not isinstance(v, dict) or any(k not in v for k in IDENTITY_KEYS) for v in identities.values()):
        raise HandoffError("exact original EE process identities required")
    assessment, assessment_pin = _record(raw, "assessment.json")
    seal, seal_pin = _record(raw, "assessment_seal.json")
    exit_value, exit_pin = _record(raw, "exit_receipt.json")
    supervisor, supervisor_pin = _record(raw, "supervisor_exit_receipt.json")
    claim, claim_pin = _record(raw, "claim.json")
    matched, matched_pin = _record(raw, "full_matched_set.json")
    names = assessment.get("required_task_names", [])
    qualified = assessment.get("qualified_from_unchanged_initial_S0")
    if qualified not in (["r134_5c42f007409acfb3"], ["r134_984fd326bd5fd13e"]):
        raise HandoffError("original fixed qualified EE nominee differs")
    expected = ["EE_{}_s{}_S_seed{}".format(package, split, seed)
                for package in ["C0"] + qualified for seed in (1, 2) for split in (1, 2, 3)]
    if (names != expected or len(names) != 12 or seal.get("assessment") != assessment_pin
            or assessment.get("status") != "COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT_NOT_PROMOTED"
            or assessment.get("AL_proposal_admitted") is not False
            or assessment.get("automatic_followon") is not False
            or assessment.get("new_fits") != 0 or assessment.get("official_origins") != 0
            or assessment.get("all_new_components_independently_revalidated") is not True
            or matched.get("components") != 12 or matched.get("required_task_names") != names
            or claim.get("required_tasks") != names or claim.get("permit_id") != "muscat_cpu30"
            or any(claim.get("unit", {}).get(k) != unit[k] for k in unit)):
        raise HandoffError("unchanged matched EE assessment/seal/claim mismatch")
    if (exit_value.get("status") != "COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT"
            or supervisor.get("status") != "PAYLOAD_EXITED" or supervisor.get("child_exit_code") != 0
            or not identity_equal(exit_value.get("process"), identities["payload_identity.json"])
            or not identity_equal(exit_value.get("supervisor"), identities["guardian.json"])
            or not identity_equal(supervisor.get("payload"), identities["payload_identity.json"])
            or not identity_equal(supervisor.get("parent"), identities["guardian.json"])
            or not p.finite_number(exit_value.get("epoch")) or not p.finite_number(supervisor.get("epoch"))
            or not exit_value["epoch"] <= supervisor["epoch"] <= raw.get("epoch", -1)):
        raise HandoffError("EE payload/supervisor success or exact lifecycle differs")
    return {"unit": unit, "processes": identities, "required_task_names": names,
            "assessment": assessment_pin, "assessment_seal": seal_pin,
            "payload_exit": exit_pin, "supervisor_exit": supervisor_pin,
            "claim": claim_pin, "full_matched_set": matched_pin,
            "scientific_source": raw.get("source"), "authority": raw.get("authority")}


def _lock_identity(path):
    st = r.no_links(path).stat()
    return {"path": str(Path(path).absolute()), "device": st.st_dev, "inode": st.st_ino}


def probe_lock(lock):
    """Never create/write the lock; briefly test the exact existing inode."""
    if _lock_identity(lock["path"]) != lock:
        raise HandoffError("shared permit lock inode/device changed")
    fd = os.open(lock["path"], os.O_RDWR | getattr(os, "O_NOFOLLOW", 0))
    try:
        st = os.fstat(fd)
        if (st.st_dev, st.st_ino) != (lock["device"], lock["inode"]):
            raise HandoffError("permit inode raced during observation")
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                return False
            raise HandoffError("permit ownership cannot be inspected") from exc
        fcntl.flock(fd, fcntl.LOCK_UN)
        return True
    finally:
        os.close(fd)


def _held_fd(pid, fd, lock):
    if type(fd) is not int or fd < 0:
        raise HandoffError("exact held descriptor required")
    procfd = Path("/proc") / str(pid) / "fd" / str(fd)
    try:
        st = procfd.stat()  # Deliberately follow only this kernel-owned FD link.
        info = (procfd.parent.parent / "fdinfo" / str(fd)).read_text()
    except OSError as exc:
        raise HandoffError("held owner descriptor is unreadable") from exc
    if (st.st_dev, st.st_ino) != (lock["device"], lock["inode"]) or len(info) > 65536:
        raise HandoffError("held descriptor differs from original permit")
    expected = (os.major(st.st_dev), os.minor(st.st_dev), st.st_ino)
    matches = []
    for line in info.splitlines():
        found = re.fullmatch(r"lock:\s*\d+:\s+FLOCK\s+ADVISORY\s+WRITE\s+(\d+)\s+([0-9a-fA-F]+):([0-9a-fA-F]+):(\d+)\s+0\s+EOF", line)
        if found:
            fields = found.groups()
            if (int(fields[1], 16), int(fields[2], 16), int(fields[3])) == expected:
                matches.append({"holder_pid": int(fields[0]), "fdinfo": line})
    if len(matches) != 1 or matches[0]["holder_pid"] != pid:
        raise HandoffError("descriptor does not prove this exact process owns the flock")
    return matches[0]


def observe_current_permit(packet, owner_receipt_pin=None, *, policy_pin=None, now=None):
    """Controller-only live observation; no remote or supplied booleans substitute."""
    p.owner()
    now = time.time() if now is None else now
    p.validate_policy(packet, now=now)
    lock = packet["local_permit"]["lock"]
    free = probe_lock(lock)
    if free:
        return {"status": "FREE", "observed_epoch": now, "lock": lock,
                "actual_original_lock_free": True, "approved_owner": None}
    if owner_receipt_pin is None or policy_pin is None:
        raise HandoffError("occupied original permit has no admitted exact successor")
    owner = p.pinned(owner_receipt_pin)
    if (owner.get("schema") != OWNER_RECEIPT_SCHEMA or owner.get("status") != "LIVE_EXACT_LOCAL_PERMIT_OWNER"
            or not fresh(owner.get("observed_epoch"), now, 60)
            or owner.get("permit_lock") != lock or owner.get("cross_host_policy") != policy_pin
            or owner.get("CPU_accounting_complete_so_far") is not True
            or owner.get("unowned_helpers") != [] or owner.get("host") != p.OWNER
            or owner.get("phase") not in OWNER_PHASES):
        raise HandoffError("missing/stale/incomplete successor receipt")
    admission_pin = owner.get("owner_admission")
    admission = p.pinned(admission_pin)
    p.validate_owner_admission(admission, packet, policy_pin, now=now)
    expected_path = str(Path(packet["owner_admission_dir"]) / (admission["scope_id"] + ".json"))
    if admission_pin["path"] != expected_path or owner.get("scope_id") != admission["scope_id"]:
        raise HandoffError("owner admission not in canonical policy namespace")
    identity = owner.get("process", {})
    actual = process_identity(identity.get("pid"))
    if (not identity_equal(identity, actual) or actual is None
            or any(identity.get(k) != actual.get(k) for k in ("executable", "executable_device", "executable_inode"))
            or admission["owner_source"]["path"] not in actual["argv"]):
        raise HandoffError("approved successor process was replaced or source argv differs")
    held = _held_fd(identity["pid"], owner.get("held_fd"), lock)
    return {"status": "APPROVED_SUCCESSOR", "observed_epoch": now, "lock": lock,
            "actual_original_lock_free": False,
            "approved_owner": {"scope_id": owner["scope_id"], "process": actual,
                               "owner_source": admission["owner_source"], "admission": admission_pin,
                               "receipt": owner_receipt_pin, "held_fd": owner["held_fd"],
                               "held_flock": held, "expires_epoch": admission["expires_epoch"]}}


def capture_owner_receipt(policy_pin, owner_admission_pin, held_fd, *, phase,
                          CPU_accounting_complete_so_far, unowned_helpers, now=None):
    """Called by the actual lock-acquiring supervisor, not an outside observer.

    Caller writes the returned value to a new receipt path and gives its exact
    pin to the controller. This does not acquire a permit or admit a model.
    """
    p.owner()
    now = time.time() if now is None else now
    packet = p.pinned(policy_pin)
    admission = p.pinned(owner_admission_pin)
    p.validate_owner_admission(admission, packet, policy_pin, now=now)
    if (owner_admission_pin["path"] != str(Path(packet["owner_admission_dir"]) / (admission["scope_id"] + ".json"))
            or phase not in OWNER_PHASES
            or CPU_accounting_complete_so_far is not True or unowned_helpers != []):
        raise HandoffError("exact canonical admitted and fully accounted owner required")
    identity = process_identity(os.getpid())
    if admission["owner_source"]["path"] not in identity["argv"]:
        raise HandoffError("only exact source-entry supervisor may issue its owner receipt")
    _held_fd(os.getpid(), held_fd, packet["local_permit"]["lock"])
    return {"schema": OWNER_RECEIPT_SCHEMA, "status": "LIVE_EXACT_LOCAL_PERMIT_OWNER",
            "host": p.OWNER, "observed_epoch": now, "scope_id": admission["scope_id"],
            "cross_host_policy": policy_pin, "owner_admission": owner_admission_pin,
            "permit_lock": packet["local_permit"]["lock"], "held_fd": held_fd,
            "process": identity, "phase": phase,
            "CPU_accounting_complete_so_far": True, "unowned_helpers": []}


def build_handoff_receipt(raw529_pin, historical_free529_pin, delivered_report_pin,
                          policy_pin, owner_receipt_pin=None, *, now=None):
    p.owner()
    if os.sched_getaffinity(0) != {31}:
        raise HandoffError("live handoff observation belongs on administrativeCPU31")
    now = time.time() if now is None else now
    packet = p.pinned(policy_pin)
    p.validate_policy(packet, now=now)
    if packet.get("historical_EE_release") != historical_free529_pin:
        raise HandoffError("historical EE release not pinned by adopted policy")
    raw = p.pinned(raw529_pin)
    history = p.pinned(historical_free529_pin)
    if not fresh(raw.get("epoch"), now):
        raise HandoffError("fresh raw source529 observation required")
    old = _closed_ee(history, historical=True)
    current = _closed_ee(raw)
    if current != old or history["epoch"] > raw["epoch"]:
        raise HandoffError("completed EE source/assessment/invocation identity changed")
    for identity in old["processes"].values():
        if same_kernel_lifetime(identity, process_identity(identity["pid"])):
            raise HandoffError("original EE exact lifetime is still alive")
    p.pinned(delivered_report_pin, parse=False)
    permit = observe_current_permit(packet, owner_receipt_pin, policy_pin=policy_pin, now=now)
    result = {"schema": SCHEMA, "status": STATUS, "controller": p.OWNER,
              "observed_epoch": now, "policy": policy_pin,
              "policy_identity_sha256": r.identity(packet),
              "historical_original_release": historical_free529_pin,
              "raw_source529": raw529_pin,
              "raw_source529_lock_free": raw["same_original_flock_free"],
              "raw_source529_global_drained": raw["scientifically_complete_and_physically_drained"],
              "old_EE_closed": True, "old_EE_exact_lifetimes_live": [],
              "required_components": 12, "complete_components": 12,
              "closure": current, "delivered_report": delivered_report_pin,
              "current_permit": permit, "owner_receipt": owner_receipt_pin,
              "scope": "old_EE_owner_closure_and_exact_current_permit_handoff",
              "original_observer_or_grant_mutated": False, "new_fits": 0,
              "new_forecasts": 0, "signals": 0}
    validate_handoff_receipt(result, packet, now=now)
    return result


def validate_handoff_receipt(receipt, packet, now=None, check_live=False):
    """Validate controller evidence; check_live=False never reads foreign /proc.

    A remote caller must first hash-validate the original receipt/policy bytes
    through its immutable release/proof store. This pure mode does not claim a
    second live observation of Muscat. Root's build always uses the live path.
    """
    now = time.time() if now is None else now
    p.validate_policy(packet, now=now, check_files=check_live)
    if (receipt.get("schema") != SCHEMA or receipt.get("status") != STATUS
            or receipt.get("controller") != p.OWNER or not fresh(receipt.get("observed_epoch"), now)
            or receipt.get("policy_identity_sha256") != r.identity(packet)
            or receipt.get("historical_original_release") != packet.get("historical_EE_release")
            or receipt.get("required_components") != 12 or receipt.get("complete_components") != 12
            or receipt.get("old_EE_closed") is not True or receipt.get("old_EE_exact_lifetimes_live") != []
            or receipt.get("scope") != "old_EE_owner_closure_and_exact_current_permit_handoff"
            or receipt.get("original_observer_or_grant_mutated") is not False
            or any(receipt.get(k) != 0 for k in ("new_fits", "new_forecasts", "signals"))
            or type(receipt.get("raw_source529_lock_free")) is not bool
            or type(receipt.get("raw_source529_global_drained")) is not bool):
        raise HandoffError("fresh exact closed-EE handoff proof required")
    for key in ("policy", "historical_original_release", "raw_source529", "delivered_report"):
        p.pinned(receipt.get(key), parse=False, check_files=check_live)
    closure = receipt.get("closure", {})
    if len(closure.get("required_task_names", [])) != 12 or len(set(closure["required_task_names"])) != 12:
        raise HandoffError("complete unique EE component names absent")
    for key in ("assessment", "assessment_seal", "payload_exit", "supervisor_exit", "claim", "full_matched_set"):
        p.pinned(closure.get(key), check_files=check_live)
    if set(closure.get("processes", {})) != {"guardian.json", "payload_identity.json"}:
        raise HandoffError("exact old EE lifetimes absent from receipt")
    permit = receipt.get("current_permit", {})
    if (permit.get("lock") != packet["local_permit"]["lock"]
            or not fresh(permit.get("observed_epoch"), now)
            or permit.get("status") not in {"FREE", "APPROVED_SUCCESSOR"}):
        raise HandoffError("fresh original-permit observation required")
    if permit["status"] == "FREE":
        if permit.get("actual_original_lock_free") is not True or permit.get("approved_owner") is not None:
            raise HandoffError("free-permit statement inconsistent")
    else:
        owner = permit.get("approved_owner", {})
        if (permit.get("actual_original_lock_free") is not False
                or not owner.get("process") or owner.get("owner_source") not in packet["approved_owner_sources"]
                or not p.finite_number(owner.get("expires_epoch"))
                or not now < owner["expires_epoch"] <= packet["legacy_expires_epoch"]):
            raise HandoffError("approved successor source/clock missing")
        for key in ("admission", "receipt", "owner_source"):
            p.pinned(owner.get(key), parse=False, check_files=check_live)
    if check_live:
        current = observe_current_permit(packet, receipt.get("owner_receipt"), policy_pin=receipt["policy"], now=now)
        before = permit["approved_owner"]
        after = current["approved_owner"]
        if (current["status"] != permit["status"] or
                (before is not None and (after is None
                 or not identity_equal(before["process"], after["process"])
                 or any(before[k] != after[k] for k in ("scope_id", "owner_source", "admission", "receipt", "held_fd", "expires_epoch"))))):
            raise HandoffError("permit ownership changed since proof")
        for identity in closure["processes"].values():
            if same_kernel_lifetime(identity, process_identity(identity["pid"])):
                raise HandoffError("old EE lifetime unexpectedly live")
    return receipt
