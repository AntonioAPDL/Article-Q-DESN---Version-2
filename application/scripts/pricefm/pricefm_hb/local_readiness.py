"""Read-only local PriceFM prerequisite evidence; never a numerical admission.

The pinned original physical-pair guard is invoked without changing its census,
resource floors or source. Runtime files are hashed as opaque bytes. This module
does not execute R, deserialize scientific payloads, acquire a permit or submit
work. A passing physical snapshot is deliberately insufficient for execution.
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
import socket
import stat
import time

SCHEMA = "r178_local_readiness_request_v1"
GUARD_SHA = "a72a485a9b73e80deee2b2a9836236caa026a0fb0cec69baec748ee200bff096"
CENSUS_SHA = "51dae5d0ecea153ac9d639141971627e9221c786a22a8533d6f5dfc7b1c3e6c0"
RUNTIME_SHA = "b365a26fe3c0ec89126193f75e66904f97907bcbf0e89a330cd837ea818fbb14"
MAX_JSON = 16 * 1024**2
MAX_FILE = 512 * 1024**2
MAX_TOTAL_RUNTIME = 1024**3
SHA = re.compile(r"[a-f0-9]{64}\Z")
ROOT = Path("/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers")
NATIVE = ROOT/"worktrees/pricefm_r157_native_bootstrap_20261028"
GUARD = NATIVE/"application/scripts/pricefm/525_owned_stage_guard.py"
CENSUS = ROOT/"pricefm_chat_continuation_20261021/r154_parallel_repair_20261026/resources/MUSCAT_PEER_CENSUS.json"
RUNTIME = ROOT/"pricefm_chat_continuation_20261021/r154_parallel_repair_20261026/certificates/MUSCAT_RUNTIME_BINDING_04.json"


class ReadinessError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ReadinessError(message)


def physical(path):
    path = Path(path)
    require(path.is_absolute() and ".." not in path.parts, "absolute canonical path required")
    require(not any(p.is_symlink() for p in (path, *path.parents)), "symlink path forbidden")
    return path


def fingerprint(s):
    return s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns


def read_bytes(path, *, maximum=MAX_FILE):
    path = physical(path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        require(stat.S_ISREG(before.st_mode) and before.st_size <= maximum, "bounded regular file required")
        with os.fdopen(os.dup(fd), "rb") as stream:
            value = stream.read(maximum + 1)
        require(len(value) == before.st_size and fingerprint(before) == fingerprint(os.fstat(fd)) == fingerprint(path.stat()),
                "file changed during observation")
    finally:
        os.close(fd)
    return value


def pin(path):
    return {"path": str(physical(path)), "sha256": hashlib.sha256(read_bytes(path)).hexdigest()}


def verify(binding, *, maximum=MAX_FILE):
    require(type(binding) is dict and set(binding) == {"path", "sha256"}, "exact immutable pin required")
    require(type(binding["sha256"]) is str and SHA.fullmatch(binding["sha256"]), "SHA256 required")
    raw = read_bytes(binding["path"], maximum=maximum)
    require(hashlib.sha256(raw).hexdigest() == binding["sha256"], "pinned bytes changed: " + binding["path"])
    return raw


def pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def read(binding):
    def bad(value):
        raise ReadinessError("nonfinite JSON value: " + value)
    require(Path(binding["path"]).suffix == ".json", "JSON metadata only")
    def floating(value):
        number = float(value)
        require(math.isfinite(number), "overflowed JSON float")
        return number
    result = json.loads(verify(binding, maximum=MAX_JSON), object_pairs_hook=pairs, parse_constant=bad, parse_float=floating)
    require(type(result) is dict, "metadata object required")
    return result


def save(path, value):
    path = physical(path)
    raw = (json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()
    require(len(raw) <= MAX_JSON, "metadata output too large")
    with path.open("xb") as f:
        f.write(raw); f.flush(); os.fsync(f.fileno())
    return {"path": str(path), "sha256": hashlib.sha256(raw).hexdigest()}


def validate_request(request, scope, *, now):
    require(request.get("schema") == SCHEMA and request.get("purpose") == "METADATA_PREREQUISITES_ONLY", "read-only purpose required")
    require(request.get("affinity") == [31] and request.get("signals") == 0 and request.get("optimizer_invocations") == 0,
            "metadata CPU31 with no signals or optimizer required")
    require(request.get("maximum_CPU_seconds") == 20 and request.get("maximum_wall_seconds") == 60,
            "fixed finite metadata bounds required")
    require(scope["issued_epoch"] <= now and now + 60 < scope["expires_epoch"], "fresh complete metadata window required")
    require(request.get("guard") == {"path": str(GUARD), "sha256": GUARD_SHA}, "original physical guard required")
    require(request.get("peer_census") == {"path": str(CENSUS), "sha256": CENSUS_SHA}, "unchanged sealed peer allowlist required")
    require(request.get("runtime_binding") == {"path": str(RUNTIME), "sha256": RUNTIME_SHA}, "original installed runtime binding required")
    require(request.get("numerical_admission") is False and request.get("new_peer_allowances") == [],
            "this producer cannot admit science or whitelist a peer")


def runtime_targets(binding):
    """Return only the exact recorded installed runtime files, not target data."""
    root = physical(binding["package_path"])
    result = {binding["actual_executable"]: binding["actual_executable_sha256"], binding["Rscript"]: binding["Rscript_sha256"]}
    for path, sha in binding["loaded_shared_object_sha256"].items():
        require(path not in result or result[path] == sha, "conflicting runtime pin")
        result[path] = sha
    for relative, sha in binding["package_files_sha256"].items():
        rel = Path(relative)
        require(not rel.is_absolute() and ".." not in rel.parts, "unsafe installed package relative path")
        path = str(root/rel)
        require(path not in result or result[path] == sha, "conflicting package pin")
        result[path] = sha
    require(1 <= len(result) <= 256, "bounded runtime closure required")
    return result


def audit_runtime(binding):
    files, total, failures = [], 0, []
    for path, sha in sorted(runtime_targets(binding).items()):
        try:
            size = physical(path).stat().st_size
            total += size
            require(total <= MAX_TOTAL_RUNTIME, "whole installed-runtime hash allowance exceeded")
            verify({"path": path, "sha256": sha})
            files.append({"path": path, "sha256": sha, "bytes": size})
        except (OSError, ReadinessError) as error:
            failures.append({"path": path, "error": str(error)})
    return {"status": "PINNED_INSTALLED_BYTES_MATCH" if not failures else "PINNED_INSTALLED_BYTES_DIFFER",
            "files": files, "failures": failures, "total_bytes": total,
            "opaque_runtime_hashes_only": True, "R_started": False, "numerical_parity_proved": False,
            "scientific_dependency_startup_proved": False}


def original_physical_check(guard_pin, census, disk_path):
    verify(guard_pin)
    spec = importlib.util.spec_from_file_location("r178_unchanged_physical_guard", guard_pin["path"])
    original = importlib.util.module_from_spec(spec); spec.loader.exec_module(original)
    try:
        result = original.physical_peer_guard(census, disk_path)
        return {"status": "ORIGINAL_STRICT_PHYSICAL_SNAPSHOT_PASS", "proof": result, "numerical_admission": False}
    except (original.GuardError, OSError) as error:
        return {"status": "BLOCKED_ORIGINAL_STRICT_PHYSICAL_GUARD", "error_type": type(error).__name__,
                "reason": str(error), "numerical_admission": False}


def capture(request_pin, output):
    require(os.sched_getaffinity(0) == {31}, "metadata CPU31 required")
    require(socket.gethostname().split(".")[0] == "muscat", "existing strict local route is Muscat-only")
    request = read(request_pin); scope = read(request["scope"])
    validate_request(request, scope, now=time.time())
    out = physical(output)
    require(str(out) == request["output_dir"] and not out.exists() and out.parent.is_dir(), "new exact output directory required")
    census = read(request["peer_census"]); runtime = read(request["runtime_binding"])
    out.mkdir(mode=0o700)
    save(out/"request_pin.json", request_pin)
    # This records availability even if the strict process check refuses admission.
    mem = {line.split(":", 1)[0]: int(line.split()[1])*1024 for line in Path("/proc/meminfo").read_text().splitlines()
           if line.startswith(("MemAvailable:", "MemTotal:"))}
    vfs = os.statvfs(out)
    physical_result = original_physical_check(request["guard"], census, out)
    runtime_result = audit_runtime(runtime)
    save(out/"PHYSICAL_OBSERVATION.json", physical_result)
    save(out/"INSTALLED_RUNTIME_BYTE_AUDIT.json", runtime_result)
    record = {"schema": "r178_local_prerequisite_evidence_v1", "status": "PREREQUISITES_OBSERVED_NOT_NUMERICAL_ADMISSION",
              "observed_epoch": time.time(), "request": request_pin, "scope": request["scope"],
              "source": pin(__file__), "guard": request["guard"], "peer_census": request["peer_census"],
              "runtime_binding": request["runtime_binding"], "physical": physical_result["status"],
              "physical_reason": physical_result.get("reason"), "runtime": runtime_result["status"],
              "MemAvailable_bytes": mem["MemAvailable"], "MemTotal_bytes": mem["MemTotal"],
              "disk_free_bytes": vfs.f_bavail*vfs.f_frsize, "peer_allowlist_changed": False,
              "physical_snapshot_is_instantaneous": True, "priority_drain_and_owner_admission_still_required": True,
              "R_started": False, "numerical_admission": False, "source_context_price_proved": False,
              "production_or_scientific_changes": 0}
    save(out/"READINESS_RESULT.json", record)
    return record


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--request", required=True); p.add_argument("--request-sha256", required=True); p.add_argument("--output", required=True)
    args = p.parse_args(argv)
    resource.setrlimit(resource.RLIMIT_CPU, (20,20))
    signal.alarm(60)
    result = capture({"path": args.request, "sha256": args.request_sha256}, args.output)
    u = resource.getrusage(resource.RUSAGE_SELF); c = resource.getrusage(resource.RUSAGE_CHILDREN)
    save(Path(args.output)/"CAPTURE_ACCOUNTING.json", {"status": "COMPLETE_METADATA_CAPTURE_ONLY", "SELF_plus_waited_CPU": u.ru_utime+u.ru_stime+c.ru_utime+c.ru_stime,
          "reservation20_retained": True, "numerical_admission": False, "no_R_array_or_fit_evaluation": True})
    print(json.dumps({k: result[k] for k in ("status", "physical", "physical_reason", "runtime", "numerical_admission")}, sort_keys=True))


if __name__ == "__main__":
    main()
