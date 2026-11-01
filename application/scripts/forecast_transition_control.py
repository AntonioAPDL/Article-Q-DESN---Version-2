#!/usr/bin/env python3.11
"""Finite, source-bound control for a later separately authorized campaign.

The shipped configuration cannot launch. Planning is read-only. A production
claim, dispatch, reconciliation or cancellation proof requires an external,
hash-pinned authorization, a qualified host, a current resource grant and a
single Muscat-owned local SQLite ledger. Remote lock files are not ownership.
This module never installs environments. Only an explicitly admitted dispatch
can connect or start its bounded supervisor. A timeout can signal only that
supervisor's verified child process group. An uncertain submission is never
retried; exact evidence is required for adoption or reassignment.
"""

from __future__ import annotations

import argparse
import contextlib
import csv
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import secrets
import shlex
import socket
import sqlite3
import subprocess
import sys
import re
import resource as posix_resource
import time
from typing import Any, Callable


class GateError(RuntimeError):
    """An explicit preflight, ownership or evidence gate did not pass."""


def require(ok: bool, message: str) -> None:
    if not ok:
        raise GateError(message)


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False, allow_nan=False).encode("utf-8")


def object_sha256(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def durable_json(path: Path, value: dict, max_bytes: int = 65536) -> str:
    """Create-only, fsynced publication; a partial receipt is retained on failure."""
    data = canonical(value) + b"\n"
    require(len(data) <= max_bytes and path.parent.is_dir() and not path.parent.is_symlink(),
            "bounded existing metadata directory")
    require(not path.exists() and not path.is_symlink(), "metadata receipt cannot be overwritten")
    partial = path.with_name(path.name + ".partial")
    descriptor = os.open(partial, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data); stream.flush(); os.fsync(stream.fileno())
    os.link(partial, path)
    directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory_fd)
        partial.unlink()
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)
    return file_sha256(path)


def file_sha256(path: Path | str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path | str) -> dict:
    with open(path, encoding="utf-8") as stream:
        value = json.load(stream, parse_constant=lambda value: (_ for _ in ()).throw(
            GateError("nonfinite JSON value: " + value)))
    require(isinstance(value, dict), "JSON document must be an object")
    return value


AUTHORIZATION_FIELDS = {
    "schema_version", "allow_launch", "source_commit", "source_tree", "source_manifest_sha256",
    "posterior_target_sha256", "input_manifest_sha256", "task_manifest_sha256", "config_sha256",
    "allowed_task_ids", "allowed_task_sha256", "allowed_hosts", "allowed_operations", "expires_utc",
    "approved_by", "budget", "qualified_hosts", "resource_receipt_sha256", "resource_grants",
    "approval_id", "scope", "coordinator_host", "master_grant_path", "master_grant_sha256",
}


def metadata_without_secrets(value: Any, *, authorization: bool = False) -> None:
    """Inspect only small dispatch JSON; never log values or inspect model evidence."""
    if authorization:
        require(isinstance(value, dict) and not set(value).difference(AUTHORIZATION_FIELDS),
                "unknown external authorization fields must be reviewed before transfer")
    forbidden = ("password", "access_token", "overleaf_token", "private_key", "cookie", "credential")
    if isinstance(value, dict):
        for key, item in value.items():
            normalized = str(key).lower().replace("-", "_").replace(" ", "_")
            require(not any(name in normalized for name in forbidden), "secret-bearing metadata field prohibited")
            metadata_without_secrets(item)
    elif isinstance(value, list):
        for item in value:
            metadata_without_secrets(item)
    elif isinstance(value, str):
        require(re.search(r"(?:^|\s)(?:olp_|gh[pousr]_|github_pat_|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)",
                          value) is None, "credential-like metadata value prohibited")


def valid_hash(value: Any, size: int = 64) -> bool:
    return isinstance(value, str) and len(value) == size and all(
        char in "0123456789abcdef" for char in value)


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def timestamp(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def parse_utc(value: str) -> dt.datetime:
    try:
        result = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (ValueError, TypeError) as error:
        raise GateError("invalid UTC expiry") from error
    require(result.tzinfo is not None, "expiry must include a timezone")
    return result.astimezone(dt.timezone.utc)


def positive_int(value: Any, label: str, allow_zero: bool = False) -> int:
    require(type(value) is int and value >= (0 if allow_zero else 1),
            label + " must be a finite integer")
    return value


IDENTITY_FIELDS = ("task_id", "source_commit", "source_tree", "source_manifest_sha256",
                   "posterior_target_sha256", "input_manifest_sha256",
                   "task_manifest_sha256", "rng_namespace")
HASH_FIELDS = ("source_manifest_sha256", "posterior_target_sha256",
               "input_manifest_sha256", "task_manifest_sha256")
ACTIVE_STATES = ("claimed", "intent", "submitted", "submission_ambiguous")
BUDGET_FIELDS = ("submissions", "cpu_seconds", "wall_seconds", "output_bytes", "metadata_bytes")
WORKFLOWS = {"integrated_quantile_forecast", "integrated_quantile_score", "glofas_family_transition"}
REQUEST_OPERATIONAL_FIELDS = {
    "allow_launch", "host", "routing_id", "output_root", "authorization_sha256",
    "authorization_path", "claim_ticket", "claim_ticket_path", "claim_ticket_sha256",
    "ledger_path", "controller_python", "task_manifest_sha256", "request_spec_sha256",
    "coordinator_source_root", "coordinator_request_path", "coordinator_ticket_path",
    "coordinator_authorization_path", "coordinator_source_manifest_path", "coordinator_ledger_path",
}


def request_spec_sha256(request: dict) -> str:
    """Pin statistical bounds before later claim/auth/routing fields are attached."""
    return object_sha256({key: value for key, value in request.items()
                          if key not in REQUEST_OPERATIONAL_FIELDS})


def argv_spec_sha256(argv: list[str]) -> str:
    """Nonce/auth digests are checked separately; avoid a manifest/hash cycle."""
    frozen = list(argv)
    for flag in ("--authorization-sha256", "--claim-ticket-sha256", "--request", "--claim-ticket", "--authorization"):
        require(frozen.count(flag) <= 1, "duplicate operational digest flag")
        if flag in frozen:
            index = frozen.index(flag)
            require(index + 1 < len(frozen), "missing operational digest")
            frozen[index + 1] = "<verified-external-digest>"
    return object_sha256(frozen)


def ssh_argv(profile: dict, command: str) -> list[str]:
    """A source-owned, nonsecret transport profile; never arbitrary SSH options."""
    allowed = {"endpoint", "user", "identity_file", "known_hosts_file", "known_hosts_sha256", "connect_timeout_seconds"}
    require(isinstance(profile, dict) and set(profile) == allowed, "exact SSH transport profile fields")
    require(profile["endpoint"] in {"muscat.be.ucsc.edu", "jerez.be.ucsc.edu", "hb.ucsc.edu"}, "source-approved SSH endpoint")
    require(re.fullmatch(r"[A-Za-z0-9_.-]+", profile["user"] or "") is not None, "safe SSH user")
    timeout = positive_int(profile["connect_timeout_seconds"], "SSH timeout")
    require(timeout <= 30, "bounded SSH timeout")
    result = ["ssh", "-F", "/dev/null", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
              "-o", "ForwardAgent=no", "-o", "ClearAllForwardings=yes", "-o", "ControlMaster=no",
              "-o", "ControlPath=none", "-o", "IdentityAgent=none", "-o", "IdentitiesOnly=yes",
              "-o", "ConnectionAttempts=1", "-o", "ConnectTimeout=" + str(timeout)]
    for field in ("identity_file", "known_hosts_file"):
        value = profile.get(field)
        if value is not None:
            require(isinstance(value, str) and Path(value).is_absolute() and "\n" not in value and "\r" not in value,
                    "absolute nonsecret SSH profile path")
            result.extend((["-i", value] if field == "identity_file" else ["-o", "UserKnownHostsFile=" + value]))
    if profile.get("known_hosts_file") is not None:
        require(valid_hash(profile.get("known_hosts_sha256")) and
                file_sha256(profile["known_hosts_file"]) == profile["known_hosts_sha256"], "strict SSH known-host snapshot")
    else:
        require(profile.get("known_hosts_sha256") is None, "no dangling host-trust digest")
    return [*result, profile["user"] + "@" + profile["endpoint"], command]


def clean_process_environment() -> dict[str, str]:
    keys = {"HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "TZ", "TMPDIR", "SLURM_JOB_ID",
            "SLURM_JOB_NODELIST", "SLURM_CPUS_PER_TASK", "SLURM_MEM_PER_NODE", "SLURM_JOB_CPUS_PER_NODE",
            "SLURM_PROCID", "SLURM_LOCALID", "SLURM_NTASKS", "SLURM_NODEID"}
    env = {key: value for key, value in os.environ.items() if key in keys}
    env.update(PATH="/usr/bin:/bin:/usr/local/bin", OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1",
        MKL_NUM_THREADS="1", BLIS_NUM_THREADS="1", VECLIB_MAXIMUM_THREADS="1", NUMEXPR_NUM_THREADS="1",
        OMP_DYNAMIC="FALSE", MKL_DYNAMIC="FALSE", R_PROFILE="/dev/null", R_PROFILE_USER="/dev/null",
        R_ENVIRON="/dev/null", R_ENVIRON_USER="/dev/null", R_LIBS="", R_LIBS_USER="", R_LIBS_SITE="",
        PYTHONNOUSERSITE="1", PYTHONDONTWRITEBYTECODE="1")
    return env


def numerical_backend_environment(backend: dict) -> dict[str, str]:
    require(isinstance(backend, dict) and set(backend) == {"backend", "library_path", "library_sha256"} and
            backend["backend"] in ("bundled_rblas", "openblas_pthread"), "explicit numerical backend schema/tag")
    path = Path(backend["library_path"])
    require(path.is_absolute() and path.is_file() and path.resolve() == path and not path.is_symlink() and
            valid_hash(backend["library_sha256"]) and file_sha256(path) == backend["library_sha256"],
            "executing-host nonsymlink numerical library identity")
    env = clean_process_environment()
    env["QDESN_NUMERICAL_BACKEND"] = backend["backend"]
    if backend["backend"] == "openblas_pthread":
        env.update(LD_PRELOAD=str(path), QDESN_BLAS_LIBRARY_PATH=str(path),
                   QDESN_BLAS_LIBRARY_SHA256=backend["library_sha256"])
    return env


def validate_task(task: dict) -> None:
    require(task.get("schema_version") == "forecast_transition_task_v1", "task schema")
    require(all(task.get(name) for name in IDENTITY_FIELDS), "complete immutable task identity")
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", task["task_id"]) is not None,
            "task ID must be a bounded safe directory component")
    require(valid_hash(task["source_commit"], 40) and valid_hash(task["source_tree"], 40),
            "source commit/tree must be full Git identities")
    require(all(valid_hash(task[name]) for name in HASH_FIELDS), "source/target/input/task hash")
    require(task.get("workflow") in WORKFLOWS, "authorized worker workflow")
    require(isinstance(task.get("routing_id"), str) and task["routing_id"], "routing identity")
    require(type(task.get("routing_revision")) is int and task["routing_revision"] >= 1,
            "positive routing revision")
    require(isinstance(task["rng_namespace"], str) and task["rng_namespace"], "scientific RNG namespace")
    keys = task.get("expected_output_keys")
    require(isinstance(keys, list) and keys and all(isinstance(key, str) and key for key in keys)
            and len(keys) == len(set(keys)), "unique expected output keys")
    require(task.get("expected_output_keys_sha256") == object_sha256(sorted(keys)),
            "expected output-key hash")
    require(valid_hash(task.get("dispatch_argv_sha256")), "frozen dispatch argv hash")
    require(valid_hash(task.get("request_spec_sha256")), "frozen full scientific request hash")
    require(isinstance(task.get("prerequisites", []), list), "explicit prerequisite list")
    for prerequisite in task.get("prerequisites", []):
        require(isinstance(prerequisite, dict) and isinstance(prerequisite.get("task_id"), str)
                and valid_hash(prerequisite.get("task_manifest_sha256"))
                and valid_hash(prerequisite.get("posterior_target_sha256")),
                "prerequisite exact task/target identities")


def validate_config(config: dict) -> None:
    require(config.get("schema_version") == "forecast_transition_multihost_v1", "control schema")
    require(config.get("coordinator_host") == "muscat" and
            config.get("ledger_mode") == "single_coordinator_local_sqlite", "one Muscat ledger")
    require(set(config.get("hosts", {})) == {"muscat", "jerez", "hummingbird"}, "three explicit hosts")
    require(config.get("production_authorization_required") is True, "external authorization required")
    for field in BUDGET_FIELDS:
        positive_int(config["production_budget"].get("max_" + field), field, allow_zero=True)
    require(config["hosts"]["hummingbird"].get("adapter") == "slurm", "Hummingbird is Slurm only")
    require(config["hosts"]["hummingbird"].get("aggregate_cpu_ceiling", 999) <= 72,
            "Hummingbird conservative 72 aggregate CPU ceiling")


def git_identity(root: Path) -> tuple[str, str, bool]:
    def git(*args: str) -> str:
        return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()
    return git("rev-parse", "HEAD"), git("rev-parse", "HEAD^{tree}"), not bool(
        git("status", "--porcelain", "--untracked-files=normal"))


def load_authorization(path: Path, expected_sha256: str, root: Path) -> tuple[dict, str]:
    resolved = path.resolve(strict=True)
    require(not resolved.is_relative_to(root.resolve()), "authorization must be external to research source")
    require(not path.is_symlink() and valid_hash(expected_sha256), "explicit authorization hash and regular path")
    require(file_sha256(resolved) == expected_sha256, "external authorization digest")
    authorization = read_json(resolved)
    metadata_without_secrets(authorization, authorization=True)
    require(authorization.get("schema_version") == "forecast_transition_authorization_v1",
            "authorization schema")
    if "master_grant_path" in authorization or "master_grant_sha256" in authorization:
        verify_master_derivation(authorization, resolved, root)
    return authorization, expected_sha256


def bounded_json(path: Path, digest: str | None = None) -> dict:
    require(path.is_absolute() and path.is_file() and path.resolve() == path and
            not any(item.is_symlink() for item in (path, *path.parents)) and path.stat().st_size <= 1024 ** 2,
            "bounded canonical regular derivation input")
    if digest is not None:
        require(valid_hash(digest) and file_sha256(path) == digest, "external master/template/grant digest")
    return read_json(path)


def verify_master_derivation(auth: dict, auth_path: Path, root: Path) -> None:
    """Only the sixteen frozen Muscat GFT templates may derive ready-wave authority."""
    require(isinstance(auth.get("master_grant_path"), str) and valid_hash(auth.get("master_grant_sha256")),
            "paired typed master grant path/hash")
    path = Path(auth["master_grant_path"])
    require(path.is_absolute() and not path.resolve().is_relative_to(root.resolve()), "external master grant required")
    master = bounded_json(path, auth["master_grant_sha256"])
    metadata_without_secrets(master)
    required = {"schema_version", "allow_launch", "authorize_derived_ready_wave_authorizations",
        "authorize_live_resource_observation", "approved_by", "expires_utc", "host", "logical_cpus",
        "max_workers", "templates", "task_budgets", "qualified_host", "budget", "state_root", "campaign_id",
        "resource_grant_path", "resource_grant_sha256", "source_commit", "source_tree", *HASH_FIELDS, "config_sha256"}
    require(required <= set(master), "complete typed campaign master required")
    require(master.get("schema_version") == "glofas_transition_campaign_master_v1" and
            master.get("allow_launch") is True and master.get("authorize_derived_ready_wave_authorizations") is True and
            master.get("authorize_live_resource_observation") is True and master.get("approved_by"),
            "master explicitly authorizes deterministic ready-task derivation")
    now = utc_now()
    require(parse_utc(master["expires_utc"]) >= parse_utc(auth["expires_utc"]) > now,
            "derived authority cannot outlive its active master")
    require(master.get("host") == "muscat" and master.get("logical_cpus") == [24, 25] and
            master.get("max_workers") in (1, 2) and auth.get("allow_launch") is True and
            auth.get("allowed_hosts") == ["muscat"] and
            set(auth.get("allowed_operations", [])) == {"claim", "dispatch", "record_terminal", "accept"},
            "master derivation is Muscat-only with four bounded operations")
    ids = {"gft-" + family + "-p" + tau for family in ("al", "exal")
           for tau in ("005", "020", "035", "050", "065", "080", "095")} | {"gft-mq-al", "gft-mq-exal"}
    require(set(master.get("templates", {})) == ids == set(master.get("task_budgets", {})) and
            len(auth.get("allowed_task_ids", [])) == 1 and auth["allowed_task_ids"][0] in ids,
            "one derived task from the exact sixteen-task master")
    tid = auth["allowed_task_ids"][0]
    for name in ("source_commit", "source_tree", *HASH_FIELDS, "config_sha256"):
        require(valid_hash(master.get(name), 40 if name in ("source_commit", "source_tree") else 64) and
                auth.get(name) == master[name], "derived master source/target/input/config mismatch: " + name)
    for field in BUDGET_FIELDS:
        key = "max_" + field
        require(positive_int(auth.get("budget", {}).get(key), key) <=
                positive_int(master.get("budget", {}).get(key), "master " + key), "derived budget exceeds master: " + field)
    require(auth.get("qualified_hosts") == {"muscat": master.get("qualified_host")},
            "derived qualification must equal the pinned master proof")
    grant = bounded_json(Path(master.get("resource_grant_path", "")), master.get("resource_grant_sha256"))
    require(grant.get("host") == "muscat" and grant.get("scope") == "forecast_transition" and
            grant.get("pricefm_grant") is False and grant.get("logical_cpus") == [24, 25] and
            parse_utc(grant["expires_utc"]) >= parse_utc(auth["expires_utc"]) and
            auth.get("resource_grants") == {grant.get("grant_id"): object_sha256(grant)},
            "derived resource grant differs from the pinned current-scope master grant")
    state = Path(master.get("state_root", ""))
    require(state.is_absolute() and not state.resolve().is_relative_to(root.resolve()) and
            auth_path == state / (tid + ".authorization.json"), "derived authorization must occupy its exact master state slot")
    task = bounded_json(state / (tid + ".task.json"))
    request = bounded_json(state / (tid + ".request.json"))
    budget = bounded_json(state / (tid + ".budget.json"))
    resource = bounded_json(state / (tid + ".resource.json"))
    validate_task(task)
    require(task["task_id"] == tid and auth.get("allowed_task_sha256") == {tid: object_sha256(task)} and
            all(task[name] == auth[name] for name in ("source_commit", "source_tree", *HASH_FIELDS)) and
            task["request_spec_sha256"] == request_spec_sha256(request), "derived task/request hash does not match master authority")
    require(budget.get("logical_cpus") in ([24], [25]) and
            budget == dict(master["task_budgets"][tid], logical_cpus=budget["logical_cpus"]) and
            resource.get("host") == "muscat" and
            auth.get("resource_receipt_sha256") == {"muscat": object_sha256(resource)},
            "derived worker/resource budget differs from the master task")
    prepared = Path(master["qualified_host"]["output_root"]).parent
    pins = master["templates"][tid]
    original_request = bounded_json(prepared / "requests" / (tid + ".template.json"), pins.get("request_sha256"))
    original_task = bounded_json(prepared / "control_tasks" / (tid + ".template.json"), pins.get("control_sha256"))
    prereqs = request.get("prerequisites", [])
    require([item.get("task_id") for item in prereqs] == [item["task_id"] for item in original_task.get("prerequisites", [])] and
            all(set(item) == {"task_id", "fit_path", "fit_sha256"} and
                Path(item["fit_path"]).is_absolute() and valid_hash(item["fit_sha256"]) for item in prereqs),
            "derived prerequisite IDs/compact-fit identities differ from the frozen template")
    route = master["campaign_id"] + "." + tid
    expected = dict(original_request, prerequisites=prereqs, routing_id=route, host="muscat",
        ledger_path=str(state / "ledger.sqlite"), controller_python=master["qualified_host"]["python_bin"],
        resource_budget={"max_threads": 1, "max_memory_mb": budget["memory_bytes"] // 1024 ** 2,
            "max_wall_seconds": budget["wall_seconds"], "max_output_bytes": budget["output_bytes"]})
    require(request == expected, "derived request changed a non-operational scientific template field")
    expected_task = dict(original_task); expected_task.pop("status", None)
    expected_task.update(routing_id=route, routing_revision=1, request_spec_sha256=request_spec_sha256(request),
                         dispatch_argv_sha256=task["dispatch_argv_sha256"])
    require(task == expected_task, "derived control task changed the frozen template")


def verify_file_manifest(root: Path, manifest: Path, expected_sha256: str,
                         *, source: bool = False) -> list[dict]:
    require(valid_hash(expected_sha256) and file_sha256(manifest) == expected_sha256,
            "source/input manifest hash")
    columns = {"path", "role", "mode", "sha256", "blob"} if source else {
        "relative_path", "size_bytes", "sha256", "role"}
    with manifest.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        require(set(reader.fieldnames or []) == columns, "exact source/input manifest columns")
        rows = list(reader)
    require(rows, "nonempty source/input manifest")
    seen = set()
    base = root.resolve(strict=True)
    for row in rows:
        relative = row["path" if source else "relative_path"]
        path = Path(relative)
        require(not path.is_absolute() and path.parts and ".." not in path.parts and relative not in seen,
                "unique bounded manifest path")
        seen.add(relative)
        actual = base / path
        require(not actual.is_symlink() and actual.resolve(strict=True).is_relative_to(base)
                and actual.is_file(), "no missing/symlinked manifest input")
        require(valid_hash(row["sha256"]) and file_sha256(actual) == row["sha256"], "manifest payload hash")
        require(row["role"], "explicit manifest role")
        if source:
            require(row["mode"] in ("100644", "100755"), "regular source mode")
            require(bool(actual.stat().st_mode & 0o111) == (row["mode"] == "100755"), "source executable mode")
            blob = subprocess.check_output(["git", "-C", str(base), "hash-object", "--", str(actual)], text=True).strip()
            require(row["blob"] == blob, "source Git blob identity")
        else:
            require(str(actual.stat().st_size) == row["size_bytes"], "manifest payload byte count")
    return rows


def verify_production_config(path: Path, source_root: Path, rows: list[dict], expected_sha256: str) -> None:
    """No external true-overlay may bypass the committed source no-launch lock."""
    relative = "application/config/forecast_transition_multihost_v1.json"
    expected_path = source_root.resolve(strict=True) / relative
    require(path.absolute() == expected_path and path.is_file() and not path.is_symlink(),
            "production config must be the exact regular source-root file")
    matches = [row for row in rows if row.get("path") == relative]
    require(len(matches) == 1, "production config must be a unique source-manifest member")
    row = matches[0]
    require(row.get("role") == "new_workflow" and row.get("mode") == "100644" and
            row.get("sha256") == expected_sha256 == file_sha256(path),
            "production config role/mode/source/auth digest")
    observed = subprocess.check_output(["git", "-C", str(source_root), "ls-tree", "HEAD", "--", relative],
                                        text=True).strip().split()
    require(observed == ["100644", "blob", row.get("blob"), relative],
            "production config must match the committed HEAD blob, not an uncommitted overlay")


def host_gates(config: dict, host: str, resource: dict | None = None) -> list[str]:
    """Host-specific plan; another unqualified site never blocks this site."""
    validate_config(config)
    require(host in config["hosts"], "unknown host")
    site = config["hosts"][host]
    reasons = []
    if config.get("launch_authorized") is not True:
        reasons.append("NO_LAUNCH_NOW: source configuration has launch_authorized=false")
    if site.get("qualified") is not True:
        reasons.append("HOST_UNQUALIFIED: source/runtime/accuracy/resource receipt missing")
    if not valid_hash(site.get("qualification_receipt_sha256")):
        reasons.append("QUALIFICATION_DIGEST_MISSING")
    if not isinstance(site.get("python_bin"), str) or not isinstance(site.get("rscript"), str):
        reasons.append("SOURCE_RUNTIME_PATH_UNRESOLVED")
    if not site.get("core_grants"):
        reasons.append("NO_CURRENT_SCOPE_CORE_GRANT: old PriceFM grants are not transferable")
    if resource is None:
        reasons.append("FRESH_RESOURCE_RECEIPT_REQUIRED")
    reasons.append("EXTERNAL_SOURCE_BOUND_AUTHORIZATION_AND_COMPLETE_TASK_BUDGET_REQUIRED")
    return reasons


def physical_allocation(site: dict, resource: dict, grant: dict, requested: list[int]) -> None:
    """Use measured (socket,core) IDs, never logical count/2 assumptions."""
    topology = resource.get("cpu_topology")
    require(isinstance(topology, list) and topology, "measured physical/sibling topology required")
    mapping = {}
    for row in topology:
        require(set(row) >= {"cpu", "socket", "core"} and
                all(type(row[name]) is int for name in ("cpu", "socket", "core")), "CPU topology row")
        require(row["cpu"] not in mapping, "duplicate topology logical CPU")
        mapping[row["cpu"]] = (row["socket"], row["core"])
    require(requested and len(requested) == len(set(requested)) and all(cpu in mapping for cpu in requested),
            "explicit known logical CPU selection")
    require(len({mapping[cpu] for cpu in requested}) == len(requested), "SMT siblings are one physical core")
    reserved = set(site.get("reserved_logical_cpus", [])) | set(resource.get("reserved_logical_cpus", []))
    require(all(cpu in mapping for cpu in reserved), "reserved topology must be known")
    reserved_physical = {mapping[cpu] for cpu in reserved}
    require(not ({mapping[cpu] for cpu in requested} & reserved_physical), "reserved core or its SMT sibling")
    released = grant.get("logical_cpus", [])
    require(set(requested) <= set(released), "requested cores not explicitly released to this scope")
    available_physical = set(mapping.values()) - reserved_physical
    require(len(available_physical) - len(requested) >= site["reserve_physical_cores"], "host-health core reserve")


def resource_admission(config: dict, host: str, resource: dict, grant: dict,
                       budget: dict, now: dt.datetime) -> None:
    site = config["hosts"][host]
    require(resource.get("host") == host and grant.get("host") == host, "resource/grant host")
    require(grant.get("scope") == "forecast_transition" and grant.get("pricefm_grant") is False,
            "new task-scope grant; no inherited PriceFM authority")
    if site.get("core_grants"):
        require(grant.get("grant_id") in site["core_grants"], "grant explicitly admitted by optional source constraint")
    require(parse_utc(grant["expires_utc"]) > now, "resource grant expired")
    require(parse_utc(resource["expires_utc"]) > now, "resource observation expired")
    workers = positive_int(budget.get("workers"), "workers")
    cpus = positive_int(budget.get("cpus"), "cpus")
    memory = positive_int(budget.get("memory_bytes"), "memory_bytes")
    measured_rss = positive_int(resource.get("measured_peak_worker_rss_bytes"), "measured worker peak RSS")
    require(memory >= workers * measured_rss, "memory request below measured worker RSS")
    require(workers <= min(site["hard_max_workers"], grant["max_workers"]), "finite worker ceiling")
    for field in ("cpu_seconds", "wall_seconds", "output_bytes"):
        positive_int(budget.get(field), field)
    positive_int(budget.get("metadata_bytes"), "metadata_bytes")
    require(budget.get("log_bytes") == budget["output_bytes"] and
            budget.get("total_output_bytes") == 2 * budget["output_bytes"] + budget["metadata_bytes"],
            "explicit artifact B plus merged-log B plus metadata reservation")
    require(budget["cpu_seconds"] >= cpus * budget["wall_seconds"], "full finite CPU charge reservation")
    require(memory <= grant["max_memory_bytes"] and
            budget["output_bytes"] <= grant.get("max_artifact_bytes", 0) and
            budget["log_bytes"] <= grant.get("max_log_bytes", 0) and
            2 * budget["output_bytes"] <= grant["max_output_bytes"] and
            budget["metadata_bytes"] <= grant.get("max_metadata_bytes", 0),
            "grant memory/artifact/log/total-output budget")
    if host == "hummingbird":
        required = ("compute_node_runtime_proof", "cpu_boundary_proof", "closed_accounting_receipt")
        require(all(resource.get(name) is True for name in required), "Hummingbird compute/CPU/accounting qualification")
        limits = [72, site["aggregate_cpu_ceiling"], grant["max_cpus"]]
        for name in ("account_cpu_limit", "qos_cpu_limit", "partition_cpu_limit", "group_cpu_limit"):
            limits.append(positive_int(resource.get(name), name))
        require(cpus + resource.get("other_allocated_cpus", 0) <= min(limits), "strictest aggregate Slurm CPU limit")
        require(cpus <= site["node_physical_cpu_ceiling"] and
                memory <= site["node_ram_ceiling_gib"] * 1024 ** 3,
                "single task node CPU/memory ceiling")
        require(all(resource.get(name) for name in ("partition", "account", "qos")), "explicit Slurm partition/account/QoS")
        require(budget["wall_seconds"] <= positive_int(resource.get("wall_time_limit_seconds"), "wall time limit"),
                "stricter Slurm wall-time limit")
        require(memory <= positive_int(resource.get("available_memory_bytes"), "available Slurm memory"),
                "scheduler-visible memory admission")
        require(resource.get("quota_verified") is True and resource.get("free_disk_bytes", 0) >= budget["total_output_bytes"],
                "verified scratch quota/output admission")
    else:
        requested = budget.get("logical_cpus")
        require(isinstance(requested, list) and len(requested) == cpus, "CPU affinity equals requested CPU charge")
        physical_allocation(site, resource, grant, requested)
        require(resource.get("available_memory_bytes", 0) - memory >= site["min_available_ram_gib"] * 1024 ** 3,
                "retain RAM safety reserve")
        require(resource.get("free_disk_bytes", 0) - budget["total_output_bytes"] >= site["min_available_disk_gib"] * 1024 ** 3,
                "retain disk floor after bounded outputs")


class Authority:
    """Source-bound authority; callers cannot promote a plan by claiming idle CPUs."""
    def __init__(self, config: dict, config_sha256: str, authorization: dict,
                 authorization_sha256: str, source: tuple[str, str, bool],
                 now: Callable[[], dt.datetime] = utc_now):
        self.config, self.config_sha256 = config, config_sha256
        self.authorization, self.sha256 = authorization, authorization_sha256
        self.source, self.now = source, now
        validate_config(config)

    def qualification(self, host: str, source_commit: str, source_manifest_sha256: str) -> dict:
        site = self.config["hosts"][host]
        receipt = self.authorization.get("qualified_hosts", {}).get(host, {})
        body = {key: value for key, value in receipt.items() if key != "receipt_sha256"}
        require(valid_hash(receipt.get("receipt_sha256")) and
                receipt["receipt_sha256"] == object_sha256(body), "canonical external qualification receipt hash")
        if site.get("qualification_receipt_sha256") is not None:
            require(receipt["receipt_sha256"] == site["qualification_receipt_sha256"],
                    "optional source qualification pin")
        require(receipt.get("source_commit") == source_commit and
                receipt.get("source_manifest_sha256") == source_manifest_sha256 and
                receipt.get("runtime_parity") is True and receipt.get("accuracy_pass") is True and
                all(valid_hash(receipt.get(name)) for name in ("runtime_receipt_sha256", "accuracy_receipt_sha256",
                                                               "resource_receipt_sha256")) and
                parse_utc(receipt["expires_utc"]) > self.now(), "exact host qualification evidence/expiry")
        require(all(isinstance(site.get(name), str) and Path(site[name]).is_absolute() and
                    receipt.get(name) == site[name] for name in ("python_bin", "rscript")),
                "source-owned qualified Python/R runtime paths required")
        backend = receipt.get("numerical_backend", {})
        require(isinstance(backend, dict) and set(backend) == {"backend", "library_path", "library_sha256"} and
                backend.get("backend") in self.config.get("allowed_numerical_backends", []) and
                isinstance(backend.get("library_path"), str) and Path(backend["library_path"]).is_absolute() and
                valid_hash(backend.get("library_sha256")), "source/auth-qualified numerical backend required")
        if host != "muscat":
            require(receipt.get("compute_to_coordinator_verified") is True and
                    valid_hash(receipt.get("coordinator_connectivity_receipt_sha256")),
                    "remote compute-to-coordinator network/auth verifier is not qualified")
        if host == "hummingbird":
            require(all(valid_hash(receipt.get(name)) for name in
                        ("cpu_boundary_receipt_sha256", "accounting_receipt_sha256")),
                    "Hummingbird CPU-boundary/accounting evidence required")
        output_root = receipt.get("output_root")
        require(isinstance(output_root, str) and Path(output_root).is_absolute() and
                ".." not in Path(output_root).parts and len(Path(output_root).parts) >= 3 and
                output_root not in ("/", "/data", "/home", "/tmp", "/var/tmp") and
                not set(Path(output_root).parts).intersection({".ssh", ".git", ".codex"}),
                "qualification needs an exact task-scope output root")
        metadata_root = receipt.get("metadata_root")
        require(isinstance(metadata_root, str) and Path(metadata_root).is_absolute() and
                ".." not in Path(metadata_root).parts and len(Path(metadata_root).parts) >= 3 and
                metadata_root not in ("/", "/data", "/home", "/tmp", "/var/tmp"),
                "qualification needs an exact task-scope metadata root")
        return receipt

    def check(self, operation: str, task: dict, host: str) -> None:
        validate_task(task)
        auth = self.authorization
        require(self.config.get("launch_authorized") is True, "NO_LAUNCH_NOW")
        require(auth.get("schema_version") == "forecast_transition_authorization_v1" and
                auth.get("allow_launch") is True, "explicit external launch authorization")
        require(valid_hash(self.sha256) and auth.get("approved_by"), "authorization identity/approver")
        require(parse_utc(auth["expires_utc"]) > self.now(), "launch authorization expired")
        require(auth.get("config_sha256") == self.config_sha256, "source configuration hash")
        require(self.source == (task["source_commit"], task["source_tree"], True), "exact clean source commit/tree")
        for name in ("source_commit", "source_tree", *HASH_FIELDS):
            require(auth.get(name) == task[name], "authorization identity mismatch: " + name)
        require(task["task_id"] in auth.get("allowed_task_ids", []) and
                host in auth.get("allowed_hosts", []) and
                operation in auth.get("allowed_operations", []), "operation/task/host not authorized")
        require(auth.get("allowed_task_sha256", {}).get(task["task_id"]) == object_sha256(task),
                "source-bound complete task record hash")
        self.qualification(host, task["source_commit"], task["source_manifest_sha256"])


def local_ledger_path(path: Path) -> None:
    """Reject obvious shared/network ledgers; coordinator topology is not a distributed lock."""
    resolved = path.parent.resolve(strict=True)
    if Path("/proc/mounts").exists():
        candidates = []
        for line in Path("/proc/mounts").read_text().splitlines():
            fields = line.split()
            if len(fields) >= 3:
                mount = Path(fields[1].replace("\\040", " "))
                if resolved == mount or mount in resolved.parents:
                    candidates.append((len(str(mount)), fields[2]))
        require(candidates and max(candidates)[1] not in {"nfs", "nfs4", "cifs", "smbfs", "sshfs", "fuse.sshfs"},
                "central ledger must be on coordinator-local storage")
    require(not path.is_symlink(), "ledger must not be a symlink")


class Ledger:
    def __init__(self, path: Path, authority: Authority, *, coordinator_hostname: str | None = None):
        require((coordinator_hostname or socket.gethostname()).split(".")[0].lower() == "muscat",
                "ledger may only be opened by the Muscat coordinator")
        local_ledger_path(path)
        self.path, self.authority = path, authority
        self.db = sqlite3.connect(path, timeout=30, isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.execute("PRAGMA journal_mode=DELETE")
        self.db.executescript("""
          CREATE TABLE IF NOT EXISTS tasks(task_id TEXT PRIMARY KEY, task_sha TEXT NOT NULL,
            spec TEXT NOT NULL, current_route TEXT NOT NULL, revision INTEGER NOT NULL);
          CREATE TABLE IF NOT EXISTS routes(routing_id TEXT PRIMARY KEY, task_id TEXT NOT NULL,
            revision INTEGER NOT NULL, host TEXT NOT NULL, receipt TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS attempts(nonce TEXT PRIMARY KEY, task_id TEXT NOT NULL,
            routing_id TEXT NOT NULL, host TEXT NOT NULL, owner TEXT NOT NULL, state TEXT NOT NULL,
            ticket TEXT NOT NULL, budget TEXT NOT NULL, auth_sha TEXT NOT NULL,
            intent_path TEXT, intent_sha TEXT, job_id TEXT, terminal_receipt TEXT, output_manifest_sha TEXT,
            FOREIGN KEY(task_id) REFERENCES tasks(task_id));
          CREATE UNIQUE INDEX IF NOT EXISTS one_active_owner ON attempts(task_id)
            WHERE state IN ('claimed','intent','submitted','submission_ambiguous');
          CREATE TABLE IF NOT EXISTS events(sequence INTEGER PRIMARY KEY AUTOINCREMENT,
            at_utc TEXT NOT NULL, task_id TEXT NOT NULL, nonce TEXT, kind TEXT NOT NULL, receipt TEXT NOT NULL);
        """)

    @contextlib.contextmanager
    def transaction(self):
        self.db.execute("BEGIN IMMEDIATE")
        try:
            yield
            self.db.execute("COMMIT")
        except BaseException:
            self.db.execute("ROLLBACK")
            raise

    def close(self) -> None:
        self.db.close()

    def event(self, task_id: str, nonce: str | None, kind: str, receipt: dict) -> None:
        self.db.execute("INSERT INTO events(at_utc,task_id,nonce,kind,receipt) VALUES(?,?,?,?,?)",
                        (timestamp(self.authority.now()), task_id, nonce, kind, canonical(receipt).decode()))

    def row(self, nonce: str) -> sqlite3.Row:
        row = self.db.execute("SELECT * FROM attempts WHERE nonce=?", (nonce,)).fetchone()
        require(row is not None, "unknown claim nonce")
        return row

    def task(self, task_id: str) -> dict:
        row = self.db.execute("SELECT spec FROM tasks WHERE task_id=?", (task_id,)).fetchone()
        require(row is not None, "unknown task")
        return json.loads(row[0])

    def attempts(self, task_id: str | None = None) -> list[dict]:
        """Read-only operator/cohort view; no lease expiry or implicit retries."""
        rows = (self.db.execute("SELECT * FROM attempts ORDER BY rowid").fetchall() if task_id is None else
                self.db.execute("SELECT * FROM attempts WHERE task_id=? ORDER BY rowid", (task_id,)).fetchall())
        result = []
        for row in rows:
            item = dict(row)
            for field in ("ticket", "budget", "terminal_receipt"):
                if item.get(field) is not None:
                    item[field] = json.loads(item[field])
            result.append(item)
        return result

    @staticmethod
    def accepted_output_readonly(db: sqlite3.Connection, task_id: str) -> dict:
        """Revalidate an accepted producer packet, not an untrusted done marker."""
        record = db.execute("SELECT spec FROM tasks WHERE task_id=?", (task_id,)).fetchone()
        require(record is not None, "unknown accepted producer task")
        task = json.loads(record[0])
        rows = db.execute("SELECT * FROM attempts WHERE task_id=? AND state='accepted'", (task_id,)).fetchall()
        require(len(rows) == 1, "exactly one accepted producer packet required")
        row = rows[0]; root = Path(json.loads(row["ticket"])["output_root"])
        sidecar = Path(str(root) + ".output_manifest.json")
        require(root.is_dir() and not any(path.is_symlink() for path in (root, *root.parents)) and
                sidecar.is_file() and not sidecar.is_symlink(), "retained accepted producer namespace/sidecar required")
        manifest = read_json(sidecar)
        require(object_sha256(manifest) == row["output_manifest_sha"] and
                manifest.get("claim_nonce") == row["nonce"] and manifest.get("routing_id") == row["routing_id"] and
                all(manifest.get(name) == task[name] for name in IDENTITY_FIELDS), "accepted producer manifest changed")
        artifacts = manifest.get("artifacts", manifest.get("shards", []))
        paths = []
        for artifact in artifacts:
            relative = Path(artifact.get("relative_path", "")); path = root / relative
            require(relative.parts and not relative.is_absolute() and ".." not in relative.parts and
                    path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(root) and
                    path.stat().st_size == artifact.get("bytes") and file_sha256(path) == artifact.get("sha256"),
                    "accepted prerequisite artifact changed")
            paths.append(relative.as_posix())
        require(len(paths) == len(set(paths)) and sorted(paths) == sorted(
                path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file()),
                "accepted prerequisite artifact membership changed")
        return {"task_id": task_id, "claim_nonce": row["nonce"], "output_root": str(root),
                "output_manifest_sha256": row["output_manifest_sha"], "manifest": manifest,
                "artifacts": [dict(artifact, path=str(root / artifact["relative_path"])) for artifact in artifacts]}

    def accepted_output(self, task_id: str) -> dict:
        return self.accepted_output_readonly(self.db, task_id)

    def prerequisites(self, task: dict) -> None:
        for required in task.get("prerequisites", []):
            row = self.db.execute("SELECT spec FROM tasks WHERE task_id=?", (required["task_id"],)).fetchone()
            require(row is not None, "missing exact prerequisite task")
            spec = json.loads(row[0])
            require(all(spec[name] == required[name] for name in ("task_manifest_sha256", "posterior_target_sha256")),
                    "mixed-target or stale prerequisite")
            accepted = self.db.execute("SELECT nonce FROM attempts WHERE task_id=? AND state='accepted'",
                                       (required["task_id"],)).fetchall()
            require(len(accepted) == 1, "prerequisite requires exactly one accepted output, not a status marker")

    def claim(self, task: dict, host: str, owner: str, resource: dict, grant: dict, budget: dict) -> dict:
        self.authority.check("claim", task, host)
        require(self.authority.authorization.get("resource_receipt_sha256", {}).get(host) == object_sha256(resource),
                "fresh resource receipt is not bound by external authorization")
        require(self.authority.authorization.get("resource_grants", {}).get(grant.get("grant_id")) == object_sha256(grant),
                "new-scope resource grant is not bound by external authorization")
        resource_admission(self.authority.config, host, resource, grant, budget, self.authority.now())
        require(isinstance(owner, str) and owner, "named owner")
        with self.transaction():
            previous = self.db.execute("SELECT * FROM tasks WHERE task_id=?", (task["task_id"],)).fetchone()
            if previous is None:
                self.db.execute("INSERT INTO tasks VALUES(?,?,?,?,?)", (task["task_id"], object_sha256(task),
                    canonical(task).decode(), task["routing_id"], task["routing_revision"]))
                self.db.execute("INSERT INTO routes VALUES(?,?,?,?,?)", (task["routing_id"], task["task_id"],
                    task["routing_revision"], host, canonical({"initial": True}).decode()))
            else:
                require(previous["task_sha"] == object_sha256(task), "immutable task definition changed")
            self.prerequisites(task)
            # Metadata is reserved at claim time, including abandoned claims.
            # Otherwise repeated pre-intent failure could evade the byte cap.
            metadata_spent = sum(json.loads(item[0])["metadata_bytes"] for item in
                self.db.execute("SELECT budget FROM attempts").fetchall())
            for limits in (self.authority.config["production_budget"], self.authority.authorization.get("budget", {})):
                ceiling = positive_int(limits.get("max_metadata_bytes"), "finite metadata ceiling")
                require(metadata_spent + budget["metadata_bytes"] <= ceiling,
                        "finite cumulative metadata_bytes budget at claim")
            prior = self.db.execute("SELECT * FROM attempts WHERE task_id=?", (task["task_id"],)).fetchall()
            require(not any(row["state"] in ACTIVE_STATES or row["state"] == "accepted" for row in prior),
                    "task already has an active owner or accepted result")
            require(not prior or all(row["state"] == "reconciled" for row in prior),
                    "failure/ambiguous submission requires explicit termination reconciliation and reassignment")
            route = self.db.execute("SELECT * FROM routes WHERE routing_id=(SELECT current_route FROM tasks WHERE task_id=?)",
                                    (task["task_id"],)).fetchone()
            require(route["host"] == host, "current immutable routing assignment differs")
            active = self.db.execute("SELECT budget FROM attempts WHERE host=? AND state IN ('claimed','intent','submitted','submission_ambiguous')",
                                     (host,)).fetchall()
            used_cpus = sum(json.loads(row[0])["cpus"] for row in active)
            used_workers = sum(json.loads(row[0])["workers"] for row in active)
            require(used_workers + budget["workers"] <= min(grant["max_workers"], self.authority.config["hosts"][host]["hard_max_workers"]),
                    "aggregate active worker budget")
            require(used_cpus + budget["cpus"] <= grant["max_cpus"], "aggregate grant CPU budget")
            require(sum(json.loads(row[0])["memory_bytes"] for row in active) + budget["memory_bytes"]
                    <= grant["max_memory_bytes"], "aggregate grant memory budget")
            require(sum(2 * json.loads(row[0])["output_bytes"] for row in active) + 2 * budget["output_bytes"]
                    <= grant["max_output_bytes"], "aggregate grant artifact/log output budget")
            require(sum(json.loads(row[0])["metadata_bytes"] for row in active) + budget["metadata_bytes"]
                    <= grant["max_metadata_bytes"], "aggregate grant metadata budget")
            if host != "hummingbird":
                total_memory = budget["memory_bytes"] + sum(json.loads(row[0])["memory_bytes"] for row in active)
                total_output = budget["total_output_bytes"] + sum(json.loads(row[0])["total_output_bytes"] for row in active)
                site = self.authority.config["hosts"][host]
                require(resource["available_memory_bytes"] - total_memory >= site["min_available_ram_gib"] * 1024 ** 3,
                        "aggregate active/ambiguous RAM reservations retain safety reserve")
                require(resource["free_disk_bytes"] - total_output >= site["min_available_disk_gib"] * 1024 ** 3,
                        "aggregate active/ambiguous output reservations retain disk floor")
            if host == "hummingbird":
                require(used_cpus + budget["cpus"] + resource.get("other_allocated_cpus", 0) <= min(
                    72, resource["account_cpu_limit"], resource["qos_cpu_limit"],
                    resource["partition_cpu_limit"], resource["group_cpu_limit"]), "aggregate active Slurm ceiling")
            else:
                used = set(cpu for row in active for cpu in json.loads(row[0])["logical_cpus"])
                require(not used.intersection(budget["logical_cpus"]), "logical CPU already claimed")
                combined = dict(budget, logical_cpus=sorted(used | set(budget["logical_cpus"])))
                physical_allocation(self.authority.config["hosts"][host], resource, grant, combined["logical_cpus"])
            nonce = secrets.token_hex(24)
            qualified_root = Path(self.authority.qualification(host, task["source_commit"],
                                  task["source_manifest_sha256"])["output_root"])
            if host == "muscat":
                require(qualified_root.is_dir() and not any(path.is_symlink() for path in
                        (qualified_root, *qualified_root.parents)), "existing nonsymlink qualified output root")
            issued_output_root = str(qualified_root / task["task_id"] / nonce)
            ticket = {"schema_version": "forecast_transition_claim_ticket_v1", "claim_nonce": nonce,
                      "routing_id": route["routing_id"], "host": host, "owner": owner,
                      "issued_utc": timestamp(self.authority.now()), "authorization_sha256": self.authority.sha256,
                      "task_sha256": object_sha256(task), **{name: task[name] for name in IDENTITY_FIELDS}}
            ticket["output_root"] = issued_output_root
            ticket["ticket_sha256"] = object_sha256(ticket)
            self.db.execute("INSERT INTO attempts(nonce,task_id,routing_id,host,owner,state,ticket,budget,auth_sha) VALUES(?,?,?,?,?,?,?,?,?)",
                            (nonce, task["task_id"], route["routing_id"], host, owner, "claimed", canonical(ticket).decode(),
                             canonical(budget).decode(), self.authority.sha256))
            self.event(task["task_id"], nonce, "claimed", {"ticket": ticket, "grant_id": grant["grant_id"],
                        "resource_sha256": object_sha256(resource), "grant_sha256": object_sha256(grant)})
        return ticket

    def prepare_intent(self, nonce: str, directory: Path, command: list[str], metadata: list[dict] | None = None) -> Path:
        row = self.row(nonce)
        task = self.task(row["task_id"])
        self.authority.check("dispatch", task, row["host"])
        require(row["state"] == "claimed", "dispatch intent may be created exactly once")
        require(command and all(isinstance(part, str) and part for part in command), "explicit argv")
        require(argv_spec_sha256(command) == task["dispatch_argv_sha256"], "frozen source-bound dispatch argv")
        budget = json.loads(row["budget"])
        charge = {"submissions": 1, **{field: budget[field] for field in BUDGET_FIELDS if field != "submissions"}}
        charge["artifact_bytes"] = budget["output_bytes"]
        charge["log_bytes"] = budget["log_bytes"]
        charge["output_bytes"] = 2 * budget["output_bytes"]
        require(directory.is_dir() and not directory.is_symlink(), "existing private intent directory")
        path = directory / (nonce + ".intent.json")
        with self.transaction():
            require(self.row(nonce)["state"] == "claimed", "claim state changed")
            intents = self.db.execute("SELECT budget FROM attempts WHERE intent_path IS NOT NULL").fetchall()
            spent = {field: (len(intents) if field == "submissions" else
                            sum((2 * json.loads(item[0])["output_bytes"] if field == "output_bytes" else
                                 json.loads(item[0])[field]) for item in intents)) for field in BUDGET_FIELDS}
            spent["metadata_bytes"] = sum(json.loads(item[0])["metadata_bytes"] for item in
                self.db.execute("SELECT budget FROM attempts WHERE nonce<>?", (nonce,)).fetchall())
            for field in BUDGET_FIELDS:
                source_limit = self.authority.config["production_budget"]["max_" + field]
                auth_limit = self.authority.authorization.get("budget", {}).get("max_" + field, 0)
                positive_int(auth_limit, "authorization max_" + field)
                require(spent[field] + charge[field] <= min(source_limit, auth_limit), "finite cumulative " + field + " budget")
            created = self.authority.now()
            intent = {"schema_version": "forecast_transition_dispatch_intent_v1", "ticket": json.loads(row["ticket"]),
                      "argv": command, "metadata": metadata or [], "charge": charge,
                      "created_utc": timestamp(created),
                      "deadline_utc": timestamp(created + dt.timedelta(seconds=budget["wall_seconds"]))}
            # Exclusive creation plus file and directory fsync precede submission.
            # An orphan file after a crash is retained and blocks blind retry.
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            try:
                with os.fdopen(descriptor, "wb") as stream:
                    stream.write(canonical(intent) + b"\n")
                    stream.flush()
                    os.fsync(stream.fileno())
                directory_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
                try:
                    os.fsync(directory_fd)
                finally:
                    os.close(directory_fd)
            except BaseException:
                # Never erase a possibly durable admission receipt.
                raise
            self.db.execute("UPDATE attempts SET state='intent',intent_path=?,intent_sha=? WHERE nonce=?",
                            (str(path), file_sha256(path), nonce))
            self.event(task["task_id"], nonce, "dispatch_intent_fsynced", {"path": str(path), "sha256": file_sha256(path), "charge": charge})
        return path

    def dispatch(self, nonce: str, submit: Callable[[dict], dict]) -> dict:
        row = self.row(nonce)
        task = self.task(row["task_id"])
        self.authority.check("dispatch", task, row["host"])
        require(row["state"] == "intent", "submission is not retryable")
        require(file_sha256(row["intent_path"]) == row["intent_sha"], "durable dispatch intent changed")
        intent = read_json(row["intent_path"])
        # Mark uncertain BEFORE external side effects. A crash/lost reply does
        # not turn this into a fresh claim or refundable budget.
        with self.transaction():
            require(self.row(nonce)["state"] == "intent", "submission state changed")
            self.db.execute("UPDATE attempts SET state='submission_ambiguous' WHERE nonce=?", (nonce,))
            self.event(task["task_id"], nonce, "submission_started", {"intent_sha256": file_sha256(row["intent_path"])})
        try:
            receipt = submit(intent)
            require(isinstance(receipt, dict) and isinstance(receipt.get("job_id"), str) and receipt["job_id"],
                    "unparseable submission response")
            require(receipt.get("host") == row["host"] and receipt.get("claim_nonce") == nonce,
                    "submission response host/claim identity")
        except BaseException as error:
            with self.transaction():
                self.event(task["task_id"], nonce, "submission_ambiguous", {"error": str(error), "retry_allowed": False})
            raise GateError("SUBMISSION_AMBIGUOUS: reconcile exact process/Slurm accounting; do not retry") from error
        with self.transaction():
            self.db.execute("UPDATE attempts SET state='submitted',job_id=? WHERE nonce=?", (receipt["job_id"], nonce))
            self.event(task["task_id"], nonce, "submitted", receipt)
        return receipt

    def terminal(self, nonce: str, receipt: dict) -> None:
        row = self.row(nonce)
        task = self.task(row["task_id"])
        self.authority.check("record_terminal", task, row["host"])
        require(row["state"] == "submitted", "terminal state needs reconciled submission identity")
        require(receipt.get("claim_nonce") == nonce and receipt.get("host") == row["host"] and
                receipt.get("owner_terminated") is True and receipt.get("accounting_complete") is True and
                receipt.get("job_id") == row["job_id"] and type(receipt.get("exit_code")) is int,
                "exact terminal owner/accounting receipt")
        with self.transaction():
            self.db.execute("UPDATE attempts SET state=?,terminal_receipt=? WHERE nonce=?",
                            ("succeeded" if receipt["exit_code"] == 0 else "failed", canonical(receipt).decode(), nonce))
            self.event(task["task_id"], nonce, "terminal", receipt)

    def abandon_preintent(self, nonce: str, receipt: dict) -> None:
        """Release only a never-submitted claim; preserve its full forensic record."""
        row = self.row(nonce); task = self.task(row["task_id"])
        self.authority.check("abandon_preintent", task, row["host"])
        require(receipt.get("claim_nonce") == nonce and receipt.get("host") == row["host"] and
                receipt.get("no_submission") is True and valid_hash(receipt.get("evidence_sha256")),
                "reviewed exact pre-intent non-submission proof")
        with self.transaction():
            row = self.row(nonce)
            events = self.db.execute("SELECT kind FROM events WHERE nonce=?", (nonce,)).fetchall()
            require(row["state"] == "claimed" and row["intent_path"] is None and row["job_id"] is None and
                    not any(item[0] in ("dispatch_intent_fsynced", "submission_started", "submitted") for item in events),
                    "only a claim with no durable intent or submission can be abandoned")
            self.db.execute("UPDATE attempts SET state='abandoned_preintent',terminal_receipt=? WHERE nonce=?",
                            (canonical(receipt).decode(), nonce))
            self.event(task["task_id"], nonce, "abandoned_preintent_no_refund", receipt)

    def adopt_ambiguous(self, nonce: str, submission: dict, terminal: dict) -> None:
        """Adopt the same nonce from independently verified terminal/accounting evidence."""
        row = self.row(nonce); task = self.task(row["task_id"])
        self.authority.check("adopt_ambiguous", task, row["host"])
        require(row["state"] == "submission_ambiguous" and row["intent_path"] and
                file_sha256(row["intent_path"]) == row["intent_sha"], "exact unresolved durable submission")
        require(submission.get("claim_nonce") == nonce and submission.get("host") == row["host"] and
                isinstance(submission.get("job_id"), str) and submission["job_id"] and
                submission.get("matching_jobs") == 1 and submission.get("owner_terminated") is True and
                submission.get("accounting_complete") is True and submission.get("no_orphans") is True and
                valid_hash(submission.get("evidence_sha256")) and
                submission.get("terminal_receipt_sha256") == object_sha256(terminal),
                "one exact terminated owner with independently bound terminal/accounting proof")
        require(terminal.get("claim_nonce") == nonce and terminal.get("host") == row["host"] and
                terminal.get("job_id") == submission["job_id"] and terminal.get("owner_terminated") is True and
                terminal.get("accounting_complete") is True and type(terminal.get("exit_code")) is int,
                "adopted terminal receipt identity")
        intent = read_json(row["intent_path"])
        require(terminal.get("worker_argv_sha256") == object_sha256(intent["argv"]) and
                terminal.get("identity") == {name: task[name] for name in IDENTITY_FIELDS},
                "adopted receipt must bind the original source/target/input and executed command")
        with self.transaction():
            require(self.row(nonce)["state"] == "submission_ambiguous", "ambiguous owner changed")
            self.db.execute("UPDATE attempts SET job_id=?,state=?,terminal_receipt=? WHERE nonce=?",
                            (submission["job_id"], "succeeded" if terminal["exit_code"] == 0 else "failed",
                             canonical(terminal).decode(), nonce))
            self.event(task["task_id"], nonce, "ambiguous_submission_adopted_no_retry_no_refund",
                       {"submission": submission, "terminal": terminal})

    def close_supervised(self, nonce: str, body: dict, proof: dict) -> None:
        """Use a durable worker receipt plus independent owner/accounting proof."""
        row = self.row(nonce); task = self.task(row["task_id"])
        self.authority.check("record_terminal", task, row["host"])
        require(row["state"] in ("submitted", "submission_ambiguous") and row["intent_path"], "closeout ownership state")
        intent = read_json(row["intent_path"])
        require(body.get("schema_version") == "forecast_transition_supervisor_receipt_v1" and
                body.get("phase") == "terminal" and body.get("worker_terminated") is True and
                body.get("claim_nonce") == nonce and body.get("host") == row["host"] and
                body.get("routing_id") == row["routing_id"] and
                body.get("identity") == {name: task[name] for name in IDENTITY_FIELDS} and
                body.get("worker_argv_sha256") == object_sha256(intent["argv"]) and
                type(body.get("exit_code")) is int, "durable terminal source/command/owner receipt")
        require(body.get("dispatch_created_utc") == intent["created_utc"] and
                body.get("deadline_utc") == intent["deadline_utc"] and
                type(body.get("dispatch_elapsed_seconds")) in (int, float) and
                math.isfinite(body["dispatch_elapsed_seconds"]) and
                0 <= body["dispatch_elapsed_seconds"] <= json.loads(row["budget"])["wall_seconds"] and
                parse_utc(body["utc"]) <= parse_utc(intent["deadline_utc"]),
                "complete supervised task exceeded its centrally charged wall deadline")
        require(proof.get("claim_nonce") == nonce and proof.get("host") == row["host"] and
                proof.get("job_id") == body.get("job_id") and proof.get("owner_terminated") is True and
                proof.get("accounting_complete") is True and proof.get("no_orphans") is True and
                proof.get("supervisor_receipt_sha256") == object_sha256(body) and
                valid_hash(proof.get("evidence_sha256")), "independent terminal accounting/liveness proof")
        if row["host"] == "hummingbird":
            require(proof.get("slurm_steps_complete") is True and proof.get("allocation_cpus") == json.loads(row["budget"])["cpus"],
                    "complete primary/batch/step accounting required, not a worker's self-declaration")
        terminal = dict(body, owner_terminated=True, accounting_complete=True, evidence_sha256=proof["evidence_sha256"])
        if row["state"] == "submission_ambiguous":
            adoption = dict(proof, matching_jobs=proof.get("matching_jobs"), terminal_receipt_sha256=object_sha256(terminal))
            self.adopt_ambiguous(nonce, adoption, terminal)
        else:
            require(body["job_id"] == row["job_id"], "terminal job differs from accepted submission")
            self.terminal(nonce, terminal)

    def reconcile_reassign(self, nonce: str, receipt: dict, new_routing_id: str, host: str, revision: int) -> None:
        row = self.row(nonce)
        task = self.task(row["task_id"])
        self.authority.check("reassign", task, row["host"])
        self.authority.check("reassign", task, host)
        require(row["state"] in ("failed", "submission_ambiguous", "cancelled", "abandoned_preintent"),
                "reassignment is not a lease timeout")
        require(receipt.get("claim_nonce") == nonce and receipt.get("owner_terminated") is True and
                receipt.get("host") == row["host"] and
                (not row["job_id"] or receipt.get("job_id") == row["job_id"]) and
                receipt.get("accounting_complete") is True and receipt.get("no_orphans") is True and
                valid_hash(receipt.get("evidence_sha256")), "verified old-owner termination/accounting required")
        require(isinstance(new_routing_id, str) and new_routing_id and new_routing_id != row["routing_id"],
                "new immutable routing identity required")
        with self.transaction():
            current = self.db.execute("SELECT revision FROM tasks WHERE task_id=?", (task["task_id"],)).fetchone()[0]
            require(type(revision) is int and revision > current, "strictly increasing routing revision")
            self.db.execute("INSERT INTO routes VALUES(?,?,?,?,?)", (new_routing_id, task["task_id"], revision, host, canonical(receipt).decode()))
            self.db.execute("UPDATE attempts SET state='reconciled' WHERE nonce=?", (nonce,))
            self.db.execute("UPDATE tasks SET current_route=?,revision=? WHERE task_id=?", (new_routing_id, revision, task["task_id"]))
            self.event(task["task_id"], nonce, "reconciled_reassignment", {"receipt": receipt, "new_routing_id": new_routing_id, "host": host, "revision": revision})

    def accept(self, nonce: str, output_manifest: dict, output_root: Path) -> str:
        row = self.row(nonce)
        task = self.task(row["task_id"])
        self.authority.check("accept", task, row["host"])
        require(row["state"] == "succeeded", "acceptance needs successful terminal/accounting receipt")
        require(output_manifest.get("schema_version") == "forecast_transition_output_v1", "output schema")
        require(output_manifest.get("claim_nonce") == nonce and output_manifest.get("routing_id") == row["routing_id"],
                "stale owner/routing output")
        require(all(output_manifest.get(name) == task[name] for name in IDENTITY_FIELDS), "mixed output identity/target/RNG")
        require(output_manifest.get("expected_output_keys_sha256") == task["expected_output_keys_sha256"], "output key hash")
        shards = output_manifest.get("shards")
        require(isinstance(shards, list), "complete shard manifest required")
        keys = [shard.get("key") for shard in shards]
        require(len(keys) == len(set(keys)) and sorted(keys) == sorted(task["expected_output_keys"]),
                "missing, extra or duplicate output shard keys")
        require(output_manifest.get("numerical_gates_pass") is True, "finite values and numerical accuracy gates required")
        root = output_root.resolve(strict=True)
        issued_output_root = Path(json.loads(row["ticket"])["output_root"])
        require(output_root.absolute() == issued_output_root and root == issued_output_root and
                not any(path.is_symlink() for path in (output_root, *output_root.parents)),
                "accepted output must be the exact ticket-bound nonsymlink directory")
        for shard in shards:
            require(shard.get("posterior_target_sha256") == task["posterior_target_sha256"], "mixed-target shard")
        artifacts = output_manifest.get("artifacts", shards)
        require(isinstance(artifacts, list) and artifacts, "complete artifact inventory")
        paths = []
        for shard in artifacts:
            path = Path(shard.get("relative_path", ""))
            require(not path.is_absolute() and path.parts and ".." not in path.parts, "bounded relative output path")
            actual = root / path
            require(not actual.is_symlink() and actual.resolve(strict=True).is_relative_to(root), "no symlink/path escape")
            require(actual.is_file() and valid_hash(shard.get("sha256")) and file_sha256(actual) == shard["sha256"], "output file digest")
            require(actual.stat().st_size == shard.get("bytes"), "output byte count")
            if actual.suffix == ".csv":
                with actual.open(newline="", encoding="utf-8") as stream:
                    reader = csv.DictReader(stream)
                    if "integration_status" in (reader.fieldnames or []):
                        statuses = [line["integration_status"] for line in reader]
                        require(statuses and all(value == "PASS_PREDECLARED_DKW_QUANTILE_ACCURACY_GATE" for value in statuses),
                                "integration REVIEW/FAIL cannot be accepted as passed")
            paths.append(path.as_posix())
        require(len(paths) == len(set(paths)), "one artifact cannot masquerade as multiple shards")
        require(all(shard.get("relative_path") in paths for shard in shards), "every numerical shard has an inventoried artifact")
        index = {item["relative_path"]: item for item in artifacts}
        require(all(shard.get("sha256") == index[shard["relative_path"]].get("sha256") and
                    shard.get("bytes") == index[shard["relative_path"]].get("bytes") for shard in shards),
                "numerical member/artifact hash and size bindings differ")
        require(sorted(paths) == sorted(path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file()),
                "exact accepted artifact membership")
        require(sum((root / path).stat().st_size for path in paths) <= json.loads(row["budget"])["output_bytes"], "bounded accepted output bytes")
        digest = object_sha256(output_manifest)
        with self.transaction():
            require(self.row(nonce)["state"] == "succeeded", "result already accepted or superseded")
            self.db.execute("UPDATE attempts SET state='accepted',output_manifest_sha=? WHERE nonce=?", (digest, nonce))
            self.event(task["task_id"], nonce, "accepted", {"manifest_sha256": digest, "keys": keys})
        return digest


def slurm_script(task: dict, ticket: dict, budget: dict, resource: dict,
                 worker_script: str, request_path: str, source_root: str, rscript: str,
                 worker_options: list[str] | None = None, worker_log: str | None = None,
                 metadata_log: str = "/dev/null", command_override: list[str] | None = None) -> str:
    """Render only a compute-node script; no Python/application runs on login."""
    require(ticket.get("host") == "hummingbird" and ticket.get("task_id") == task["task_id"], "Slurm ticket identity")
    require(1 <= budget["cpus"] <= 24 and budget["memory_bytes"] > 0, "finite per-node Slurm request")
    for name in ("partition", "account", "qos"):
        require(isinstance(resource.get(name), str) and resource[name] and
                all(char.isalnum() or char in "_-" for char in resource[name]), "safe Slurm " + name)
    seconds = budget["wall_seconds"]
    require(type(seconds) is int and seconds > 0, "finite Slurm wall time")
    walltime = f"{seconds // 3600:02d}:{(seconds // 60) % 60:02d}:{seconds % 60:02d}"
    memory_mib = math.ceil(budget["memory_bytes"] / 1024 ** 2)
    mode = {"integrated_quantile_forecast": ["--mode", "run"],
            "integrated_quantile_score": ["--mode", "score"], "glofas_family_transition": []}[task["workflow"]]
    argv = [rscript, worker_script, *mode, "--request", request_path, *(worker_options or [])]
    if command_override is not None:
        require(len(command_override) > 3 and command_override[1] == str(Path(source_root) /
            "application/scripts/forecast_transition_control.py") and command_override[2] == "supervise",
            "Slurm override must be the source-owned compute supervisor")
        argv = command_override
    require("\n" not in metadata_log and "\r" not in metadata_log and Path(metadata_log).is_absolute(),
            "bounded Slurm metadata log path")
    redirect = []
    if worker_log is not None:
        require("\n" not in worker_log and "\r" not in worker_log and Path(worker_log).is_absolute(),
                "bounded compute-owned merged log")
        redirect = ["set -o noclobber", "exec > " + shlex.quote(worker_log) + " 2>&1"]
    return "\n".join(["#!/usr/bin/env bash",
        "#SBATCH --job-name=qdesn-" + ticket["claim_nonce"], "#SBATCH --no-requeue",
        f"#SBATCH --partition={resource['partition']}", f"#SBATCH --account={resource['account']}",
        f"#SBATCH --qos={resource['qos']}", "#SBATCH --nodes=1", "#SBATCH --ntasks=1",
        f"#SBATCH --cpus-per-task={budget['cpus']}", f"#SBATCH --mem={memory_mib}M", f"#SBATCH --time={walltime}",
        "#SBATCH --output=" + shlex.quote(metadata_log), "#SBATCH --error=" + shlex.quote(metadata_log),
        "set -euo pipefail",
        "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1",
        "test -n \"${SLURM_JOB_ID:-}\"", "test -n \"${SLURM_JOB_NODELIST:-}\"",
        "ulimit -f " + str(budget["output_bytes"] // 1024),
        "ulimit -S -f " + str(min(64, budget["output_bytes"] // 1024)),
        "printf '%s\\n' 'qualified compute dispatch started'", *redirect,
        "cd " + shlex.quote(source_root), "exec srun --exclusive " + shlex.join(argv), ""])


PROCESS_IDENTITY_FIELDS = ("host", "boot_id", "pid", "start_ticks", "uid", "cwd", "cmdline", "runtime_root")


def cancellation_proof(expected: dict, observed: dict, authority: Authority, task: dict) -> dict:
    """Dry-run only: a proof is not a kill command or permission for broad pkill."""
    authority.check("cancel", task, expected.get("host", ""))
    require(all(name in expected and name in observed and expected[name] == observed[name]
                for name in PROCESS_IDENTITY_FIELDS), "exact live process/boot/start/cwd/runtime identity")
    require(expected.get("task_id") == observed.get("task_id") == task["task_id"], "owned process task identity")
    require(type(expected["pid"]) is int and expected["pid"] > 1, "bounded process ID")
    require(expected.get("admission_stopped") is True and observed.get("admission_stopped") is True,
            "stop admission before contemplating cancellation")
    return {"schema_version": "forecast_transition_cancellation_proof_v1", "dry_run": True,
            "identity_sha256": object_sha256(expected), "signals_sent": 0,
            "processes_stopped": 0, "task_id": task["task_id"]}


def verify_claim_readonly(ledger_path: Path, ticket: dict, request: dict,
                          authority: Authority, *, coordinator_hostname: str | None = None) -> dict:
    """Remote workers must query this on Muscat, never copy the ledger or ticket alone."""
    require((coordinator_hostname or socket.gethostname()).split(".")[0].lower() == "muscat",
            "claim verifier must run on Muscat coordinator")
    local_ledger_path(ledger_path)
    require(ledger_path.is_file(), "existing central ledger required")
    nonce = ticket.get("claim_nonce")
    require(isinstance(nonce, str) and nonce, "claim nonce required")
    db = sqlite3.connect(ledger_path.resolve().as_uri() + "?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    try:
        row = db.execute("SELECT * FROM attempts WHERE nonce=?", (nonce,)).fetchone()
        require(row is not None and row["state"] in ("submitted", "submission_ambiguous") and row["intent_path"],
                "claim is not a submitted active central owner")
        require(json.loads(row["ticket"]) == ticket, "fabricated or altered claim ticket")
        task_row = db.execute("SELECT spec,current_route FROM tasks WHERE task_id=?", (row["task_id"],)).fetchone()
        task = json.loads(task_row["spec"])
        authority.check("dispatch", task, row["host"])
        require(task_row["current_route"] == row["routing_id"] == request.get("routing_id"), "stale routing revision")
        require(request.get("host") == row["host"] and
                all(request.get(name) == task[name] for name in IDENTITY_FIELDS), "request/claim scientific identity")
        require(request.get("authorization_sha256") == row["auth_sha"] == authority.sha256,
                "request/claim external authorization identity")
        require(request.get("output_root") == ticket.get("output_root"), "request output path differs from claim ticket")
        require(request_spec_sha256(request) == task["request_spec_sha256"], "scientific request/bounds changed")
        recorded_budget = json.loads(row["budget"])
        requested_budget = request.get("resource_budget")
        require(isinstance(requested_budget, dict) and
                type(requested_budget.get("max_memory_mb")) is int and
                requested_budget.get("max_threads") == recorded_budget["cpus"] and
                requested_budget.get("max_memory_mb") * 1024 ** 2 == recorded_budget["memory_bytes"] and
                requested_budget.get("max_wall_seconds") == recorded_budget["wall_seconds"] and
                requested_budget.get("max_output_bytes") == recorded_budget["output_bytes"],
                "worker budget differs from centrally reserved CPU/memory/wall/output bounds")
        require(file_sha256(row["intent_path"]) == row["intent_sha"], "submitted dispatch intent changed")
        intent = read_json(row["intent_path"])
        supervisors = [item for item in intent.get("metadata", []) if item.get("role") == "supervision"]
        require(len(supervisors) == 1 and valid_hash(supervisors[0].get("sha256")),
                "active claim lacks one immutable supervision specification")
        qualification = authority.qualification(row["host"], task["source_commit"], task["source_manifest_sha256"])
        prerequisites = []
        for expected in task.get("prerequisites", []):
            accepted = Ledger.accepted_output_readonly(db, expected["task_id"])
            require(all(accepted["manifest"][name] == expected[name] for name in
                        ("task_manifest_sha256", "posterior_target_sha256")), "accepted prerequisite target changed")
            prerequisites.append({**expected, "output_manifest_sha256": accepted["output_manifest_sha256"],
                "identity": {name: accepted["manifest"][name] for name in IDENTITY_FIELDS},
                "artifacts": [{name: artifact[name] for name in ("relative_path", "sha256", "bytes")}
                              for artifact in accepted["artifacts"]]})
        return {"schema_version": "forecast_transition_claim_verification_v1", "verified": True,
                "claim_nonce": nonce, "task_id": task["task_id"], "routing_id": row["routing_id"],
                "host": row["host"], "job_id": row["job_id"], "resource_budget": recorded_budget,
                "output_root": ticket["output_root"],
                "metadata_root": qualification["metadata_root"],
                "numerical_backend": qualification["numerical_backend"],
                "worker_argv_sha256": object_sha256(intent["argv"]),
                "supervision_spec_sha256": supervisors[0]["sha256"],
                "dispatch_created_utc": intent["created_utc"], "deadline_utc": intent["deadline_utc"],
                "accepted_prerequisites": prerequisites,
                "ledger_mutations": 0}
    finally:
        db.close()


def worker_argv(config: dict, host: str, task: dict, request: dict,
                request_path: Path, ticket_path: Path, auth_path: Path,
                ledger_path: Path, source_manifest: Path, source_root: Path,
                ticket_digest: str | None = None) -> list[str]:
    """Only source-owned forecast, transition and scoring workers; no supplied shell."""
    require(host in config["hosts"] and task["workflow"] in config["worker_scripts"], "known worker/site")
    score_mode = request.get("mode", "score")
    if task["workflow"] == "integrated_quantile_score":
        require(score_mode in ("score", "aggregate"), "explicit scoring/aggregation mode")
    mode = {"integrated_quantile_forecast": ["--mode", "run"],
            "integrated_quantile_score": ["--mode", score_mode], "glofas_family_transition": []}[task["workflow"]]
    return [config["hosts"][host]["rscript"], str(source_root / config["worker_scripts"][task["workflow"]]),
            *mode, "--request", str(request_path), "--authorization", str(auth_path),
            "--authorization-sha256", request["authorization_sha256"], "--claim-ticket", str(ticket_path),
            "--claim-ticket-sha256", ticket_digest or file_sha256(ticket_path), "--ledger", str(ledger_path),
            "--source-manifest", str(source_manifest), "--python", config["hosts"][host]["python_bin"]]


def process_identity(pid: int, source_root: Path) -> dict:
    stat = Path(f"/proc/{pid}/stat").read_text()
    # comm may contain whitespace or parentheses; fields after its last ')'
    # begin at Linux field 3, so starttime (22) is index 19 here.
    start = int(stat.rsplit(") ", 1)[1].split()[19])
    actual = socket.gethostname().split(".")[0].lower()
    host = actual if actual in ("muscat", "jerez") else ("hummingbird" if os.environ.get("SLURM_JOB_ID") else actual)
    return {"host": host, "hostname": actual, "pid": pid, "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
            "start_ticks": start, "cwd": str(source_root), "uid": os.getuid()}


def supervision_argv(config: dict, host: str, source_root: Path, worker: list[str], spec: dict) -> list[str]:
    """One source-owned supervisor, never an arbitrary callback executable."""
    python = config["hosts"][host].get("python_bin")
    require(isinstance(python, str) and Path(python).is_absolute(), "qualified source-owned Python runtime unavailable")
    required = ("--request", "--authorization", "--authorization-sha256", "--claim-ticket",
                "--claim-ticket-sha256", "--ledger", "--source-manifest")
    flags = []
    controller_flag = {"--claim-ticket": "--ticket", "--claim-ticket-sha256": "--ticket-sha256"}
    for flag in required:
        require(worker.count(flag) == 1 and worker.index(flag) + 1 < len(worker), "supervisor worker context: " + flag)
        flags.extend([controller_flag.get(flag, flag), worker[worker.index(flag) + 1]])
    return [python, str(source_root / "application/scripts/forecast_transition_control.py"), "supervise", *flags,
            "--source-root", str(source_root), "--supervision-spec", spec["remote_path"],
            "--supervision-spec-sha256", spec["sha256"]]


def supervised_child(spec: dict, verified: dict, *, runner: Callable = subprocess.Popen,
                     identity: Callable = process_identity) -> dict:
    """Wait for one admitted child and durably retain its terminal evidence.

    Production CLI verifies source/auth/claim first. Tests inject a child and
    identity function; no scientific process is needed for this lifecycle test.
    """
    require(spec.get("schema_version") == "forecast_transition_supervision_v1" and verified.get("verified") is True,
            "verified source-owned supervision context")
    require(spec.get("claim_nonce") == verified.get("claim_nonce") and spec.get("task_id") == verified.get("task_id") and
            spec.get("routing_id") == verified.get("routing_id") and spec.get("host") == verified.get("host"),
            "supervisor claim/routing identity")
    require(object_sha256(spec["worker_argv"]) == verified.get("worker_argv_sha256") and
            spec["budget"] == verified["resource_budget"], "supervisor command/budget differs from durable intent")
    budget = spec["budget"]; root = Path(spec["source_root"])
    require(budget["wall_seconds"] >= 60, "supervised wall budget must include at least60 seconds for startup and closure")
    created = parse_utc(verified["dispatch_created_utc"]); deadline_utc = parse_utc(verified["deadline_utc"])
    require((deadline_utc - created).total_seconds() == budget["wall_seconds"], "centrally charged wall deadline")
    remaining = (deadline_utc - utc_now()).total_seconds()
    require(remaining > 30, "charged wall deadline leaves no bounded startup/termination/receipt grace")
    deadline = time.monotonic() + remaining
    own = identity(os.getpid(), root)
    require(own["host"] == spec["host"], "actual supervisor host")
    metadata_root = Path(verified["metadata_root"])
    nonce = spec["claim_nonce"]
    paths = {name: Path(spec[name]) for name in ("started_path", "terminal_path", "log_path")}
    require(all(path.parent == metadata_root and path.name.startswith(nonce + ".") for path in paths.values()),
            "supervisor receipt/log namespace")
    job_id = (str(os.environ["SLURM_JOB_ID"]) if spec["host"] == "hummingbird" else
              "pid:" + str(own["pid"]) + ":" + own["boot_id"] + ":" + str(own["start_ticks"]))
    started_at = time.monotonic()
    usage_before = posix_resource.getrusage(posix_resource.RUSAGE_CHILDREN)
    def limits():
        if spec["host"] != "hummingbird":
            os.sched_setaffinity(0, set(budget["logical_cpus"]))
        posix_resource.setrlimit(posix_resource.RLIMIT_AS, (budget["memory_bytes"], budget["memory_bytes"]))
        posix_resource.setrlimit(posix_resource.RLIMIT_CPU, (budget["cpu_seconds"], budget["cpu_seconds"]))
        posix_resource.setrlimit(posix_resource.RLIMIT_FSIZE, (budget["output_bytes"], budget["output_bytes"]))
    require(spec.get("numerical_backend") == verified.get("numerical_backend"), "supervisor numerical backend differs from qualification")
    env = numerical_backend_environment(verified["numerical_backend"])
    with paths["log_path"].open("xb") as log:
        child = runner(spec["worker_argv"], cwd=root, env=env, stdin=subprocess.DEVNULL,
                       stdout=log, stderr=subprocess.STDOUT, start_new_session=True, preexec_fn=limits)
        child_identity = identity(child.pid, root)
        base = {"schema_version": "forecast_transition_supervisor_receipt_v1", "claim_nonce": nonce,
                "task_id": spec["task_id"], "routing_id": spec["routing_id"], "host": spec["host"],
                "job_id": job_id, "supervisor_identity": own, "child_identity": child_identity,
                "worker_argv_sha256": verified["worker_argv_sha256"], "budget": budget,
                "identity": spec["identity"]}
        durable_json(paths["started_path"], dict(base, phase="started", utc=timestamp(utc_now())))
        timed_out = False
        try:
            work_seconds = deadline - time.monotonic() - 30
            require(work_seconds > 0, "startup exhausted the charged worker wall allowance")
            code = child.wait(timeout=work_seconds)
        except subprocess.TimeoutExpired:
            timed_out = True
            require(identity(child.pid, root) == child_identity and os.getpgid(child.pid) == child.pid,
                    "timeout may signal only the exact owned child process group")
            os.killpg(child.pid, 15)
            try:
                child.wait(timeout=max(0, min(15, deadline - time.monotonic() - 15)))
            except subprocess.TimeoutExpired:
                require(identity(child.pid, root) == child_identity and os.getpgid(child.pid) == child.pid,
                        "timeout hard-stop ownership identity changed")
                os.killpg(child.pid, 9)
                child.wait(timeout=max(0, min(5, deadline - time.monotonic() - 10)))
            code = 124
    usage_after = posix_resource.getrusage(posix_resource.RUSAGE_CHILDREN)
    receipt = dict(base, phase="terminal", exit_code=int(code), timed_out=timed_out,
        worker_terminated=True, supervisor_exit_pending=True,
        accounting_complete=spec["host"] != "hummingbird", utc=timestamp(utc_now()),
        dispatch_created_utc=verified["dispatch_created_utc"], deadline_utc=verified["deadline_utc"],
        dispatch_elapsed_seconds=(utc_now()-created).total_seconds(),
        elapsed_seconds=time.monotonic() - started_at,
        child_cpu_seconds=(usage_after.ru_utime + usage_after.ru_stime - usage_before.ru_utime - usage_before.ru_stime),
        child_maxrss_kib=usage_after.ru_maxrss,
        cpu_scope="reaped_child_primary_usage_not_added_to_Slurm_parent_and_step_records",
        log_bytes=paths["log_path"].stat().st_size, log_sha256=file_sha256(paths["log_path"]))
    require(receipt["log_bytes"] <= budget["log_bytes"], "merged log exceeded its reserved capacity")
    require(time.monotonic() <= deadline and 0 <= receipt["dispatch_elapsed_seconds"] <= budget["wall_seconds"],
            "supervisor terminal must fit the complete charged dispatch wall budget")
    durable_json(paths["terminal_path"], receipt)
    return receipt


def verification_context(args: argparse.Namespace, config: dict) -> tuple[dict, Authority, dict]:
    require(all((args.ledger, args.ticket, args.ticket_sha256, args.request,
                 args.authorization, args.authorization_sha256, args.source_root, args.source_manifest)),
            "all external authority/ledger/source/ticket paths and hashes are required")
    ticket = pinned_json(args.ticket, args.ticket_sha256, "claim ticket")
    request = read_json(args.request)
    authorization, auth_sha = load_authorization(args.authorization, args.authorization_sha256, args.source_root)
    rows = verify_file_manifest(args.source_root, args.source_manifest, request.get("source_manifest_sha256"), source=True)
    verify_production_config(args.config, args.source_root, rows, authorization.get("config_sha256"))
    authority = Authority(config, file_sha256(args.config), authorization, auth_sha, git_identity(args.source_root))
    verified = (verify_claim_readonly(args.ledger, ticket, request, authority)
                if args.command == "verify-claim" or request.get("host") == "muscat" else verify_claim_remote(args, request, authority))
    return request, authority, verified


def pinned_json(path: Path | None, digest: str | None, label: str) -> dict:
    require(path is not None and path.is_file() and not path.is_symlink() and valid_hash(digest)
            and file_sha256(path) == digest, "exact regular " + label + " file/hash")
    return read_json(path)


def closeout_cli(args: argparse.Namespace, config: dict) -> dict:
    """Explicit, source-bound closeout; never retry, invent proof or edit SQL."""
    require(args.execute and args.ledger and args.ledger.is_file() and args.nonce and
            args.authorization and args.authorization_sha256 and args.source_root and args.source_manifest,
            "closeout requires --execute, an existing ledger, exact nonce/source and external authorization")
    auth, digest = load_authorization(args.authorization, args.authorization_sha256, args.source_root)
    rows = verify_file_manifest(args.source_root, args.source_manifest, auth.get("source_manifest_sha256"), source=True)
    verify_production_config(args.config, args.source_root, rows, auth.get("config_sha256"))
    authority = Authority(config, file_sha256(args.config), auth, digest, git_identity(args.source_root))
    ledger = Ledger(args.ledger, authority)
    try:
        row = ledger.row(args.nonce)
        if args.command == "accept":
            require(args.output_root is not None, "exact claimed output root required")
            body = pinned_json(args.completion, args.completion_sha256, "completion envelope")
            result = {"output_manifest_sha256": ledger.accept(args.nonce, body, args.output_root)}
        else:
            proof = pinned_json(args.proof, args.proof_sha256, "independent closeout proof")
            if args.command == "abandon-preintent":
                ledger.abandon_preintent(args.nonce, proof)
            elif args.command == "close-supervised":
                body = pinned_json(args.terminal_receipt, args.terminal_receipt_sha256, "durable terminal receipt")
                ledger.close_supervised(args.nonce, body, proof)
            elif args.command == "reassign":
                require(args.new_routing_id and args.new_host and args.routing_revision,
                        "reviewed reassignment needs a new route, host and increasing revision")
                ledger.reconcile_reassign(args.nonce, proof, args.new_routing_id, args.new_host, args.routing_revision)
            result = {}
        result.update(task_id=row["task_id"], claim_nonce=args.nonce, state=ledger.row(args.nonce)["state"])
        return result
    finally:
        ledger.close()


def qualified_submitter(host: str, argv: list[str], source_root: Path, budget: dict,
                        resource: dict, log_dir: Path, task: dict, ticket: dict,
                        config: dict, authority: Authority,
                        metadata: list[dict] | None = None) -> Callable[[dict], dict]:
    """Real adapters, called only inside Ledger.dispatch after all admission gates.

    This factory does not launch. Unit tests mock Popen/run and proc inspection.
    SSH carries shell scripts/arguments only, never credentials or environments.
    """
    require(host in ("muscat", "jerez", "hummingbird"), "explicit adapter host")
    require(config is authority.config, "adapter must use admitted source configuration")
    authority.check("dispatch", task, host)
    require(config["hosts"][host]["adapter"] == {
        "muscat": "local", "jerez": "ssh_local", "hummingbird": "slurm"}[host], "site adapter identity")
    records = metadata or []
    specs = [item for item in records if item.get("role") == "supervision"]
    require(len(specs) == 1, "one durable source-owned supervision specification required")
    spec_record = specs[0]
    require(file_sha256(spec_record["local_path"]) == spec_record["sha256"], "supervision specification changed")
    launch = supervision_argv(config, host, source_root, argv, spec_record)
    def submit(intent: dict) -> dict:
        authority.check("dispatch", task, host)
        require(intent["argv"] == argv and intent["ticket"]["claim_nonce"] == ticket["claim_nonce"],
                "adapter differs from fsynced intent")
        nonce = ticket["claim_nonce"]
        receipt = {"host": host, "claim_nonce": nonce}
        require(intent.get("metadata") == records, "exact durable supervision metadata inventory")
        if host != "muscat":
            approved_root = Path(authority.authorization["qualified_hosts"][host]["metadata_root"])
            require(approved_root.is_absolute() and str(approved_root) not in ("/", "/tmp", "/home", "/data"),
                    "exact qualified metadata directory")
            lines = ["set -euo pipefail", "test -d " + shlex.quote(str(approved_root)), "umask 077", "set -o noclobber"]
            require(len(records) == 4, "only request, claim ticket, authorization and supervision metadata transfer")
            require({item.get("role") for item in records} == {"request", "claim_ticket", "authorization", "supervision"}, "metadata allowlist")
            for item in records:
                local = Path(item["local_path"])
                remote = Path(item["remote_path"])
                require(local.is_file() and not local.is_symlink() and local.stat().st_size <= 1024 ** 2,
                        "bounded regular metadata source")
                require(remote.parent == approved_root and nonce in remote.name and
                        file_sha256(local) == item["sha256"], "source-bound metadata path/hash")
                payload = local.read_text(encoding="utf-8")
                metadata_without_secrets(read_json(local), authorization=item["role"] == "authorization")
                lines.extend(["test ! -e " + shlex.quote(str(remote)),
                    "printf '%s' " + shlex.quote(payload) + " > " + shlex.quote(str(remote)),
                    "test \"$(sha256sum " + shlex.quote(str(remote)) + " | cut -d ' ' -f1)\" = " + shlex.quote(item["sha256"])])
            subprocess.run(ssh_argv(config["hosts"][host]["ssh_profile"], "bash -s"),
                           input="\n".join(lines) + "\n", text=True, capture_output=True, check=True, timeout=60)
        if host == "muscat":
            require(source_root.is_dir() and log_dir.is_dir(), "existing owned local directories")
            cpus = set(budget["logical_cpus"])
            def limits():
                os.sched_setaffinity(0, cpus)
                posix_resource.setrlimit(posix_resource.RLIMIT_AS, (budget["memory_bytes"], budget["memory_bytes"]))
                posix_resource.setrlimit(posix_resource.RLIMIT_CPU, (budget["cpu_seconds"], budget["cpu_seconds"]))
                posix_resource.setrlimit(posix_resource.RLIMIT_FSIZE, (min(65536, budget["output_bytes"]), budget["output_bytes"]))
            env = clean_process_environment()
            log_path = log_dir / (nonce + ".supervisor.log")
            with log_path.open("xb") as stream:
                process = subprocess.Popen(launch, cwd=source_root, env=env,
                    stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT,
                    start_new_session=True, preexec_fn=limits)
            identity = process_identity(process.pid, source_root)
            receipt.update(job_id="pid:" + str(process.pid) + ":" + identity["boot_id"] + ":" + str(identity["start_ticks"]),
                           process_identity=identity, log_path=str(log_path))
        elif host == "jerez":
            cpu_list = ",".join(str(cpu) for cpu in budget["logical_cpus"])
            command = ["/usr/bin/taskset", "--cpu-list", cpu_list, *launch]
            log_path = log_dir / (nonce + ".supervisor.log")
            script = "\n".join(["set -euo pipefail", "test \"$(hostname -s)\" = jerez",
                "test \"$(git -C " + shlex.quote(str(source_root)) + " rev-parse HEAD)\" = " + shlex.quote(task["source_commit"]),
                "test \"$(git -C " + shlex.quote(str(source_root)) + " rev-parse 'HEAD^{tree}')\" = " + shlex.quote(task["source_tree"]),
                "test -z \"$(git -C " + shlex.quote(str(source_root)) + " status --porcelain --untracked-files=normal)\"",
                "cd " + shlex.quote(str(source_root)), "umask 077", "set -o noclobber",
                "ulimit -v " + str(math.ceil(budget["memory_bytes"] / 1024)), "ulimit -t " + str(budget["cpu_seconds"]),
                "ulimit -f " + str(budget["output_bytes"] // 1024),
                "ulimit -S -f " + str(min(64, budget["output_bytes"] // 1024)),
                "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 BLIS_NUM_THREADS=1",
                "nohup " + shlex.join(command) + " > " + shlex.quote(str(log_path)) + " 2>&1 < /dev/null &",
                "worker_pid=$!", "boot_id=$(cat /proc/sys/kernel/random/boot_id)",
                "worker_stat=$(cat /proc/\"$worker_pid\"/stat)", "worker_tail=${worker_stat##*) }",
                "read -ra worker_fields <<< \"$worker_tail\"",
                "printf '%s %s %s\\n' \"$worker_pid\" \"$boot_id\" \"${worker_fields[19]}\"", ""])
            result = subprocess.run(ssh_argv(config["hosts"][host]["ssh_profile"], "bash -s"),
                                    input=script, text=True, capture_output=True, check=True, timeout=60)
            match = re.fullmatch(r"([1-9][0-9]*) ([a-f0-9-]+) ([0-9]+)\s*", result.stdout)
            require(match is not None, "unparseable Jerez process receipt")
            receipt.update(job_id="pid:" + ":".join(match.groups()), remote_stdout=result.stdout)
        else:
            base_script = config["worker_scripts"][task["workflow"]]
            # worker_argv places the exact source-owned script at argv[1].
            require(argv[1] == str(source_root / base_script), "frozen Slurm worker path")
            request_index = argv.index("--request")
            options = argv[request_index + 2:]
            script = slurm_script(task, ticket, budget, resource, argv[1], argv[request_index + 1], str(source_root), argv[0], options,
                None, str(log_dir / (nonce + ".scheduler.log")), launch)
            if task["workflow"] == "integrated_quantile_score" and "--mode" in argv:
                script = script.replace(" --mode score --request ", " --mode " + argv[argv.index("--mode") + 1] + " --request ", 1)
            result = subprocess.run(ssh_argv(config["hosts"][host]["ssh_profile"], "sbatch --parsable"),
                                    input=script, text=True, capture_output=True, check=True, timeout=60)
            match = re.fullmatch(r"([1-9][0-9]*)(?:;([A-Za-z0-9_.-]+))?\s*", result.stdout)
            require(match is not None, "unparseable Slurm submission receipt")
            receipt.update(job_id=match.group(1), cluster=match.group(2), batch_script_sha256=hashlib.sha256(script.encode()).hexdigest())
        return receipt
    return submit


def verify_claim_remote(args: argparse.Namespace, request: dict, authority: Authority) -> dict:
    """Compute-node callback; no ledger copied and no login-node science."""
    host = request.get("host")
    require(host in ("jerez", "hummingbird"), "remote verifier host")
    actual_host = socket.gethostname().split(".")[0].lower()
    require(host != "jerez" or actual_host == "jerez", "actual Jerez hostname does not match routed claim")
    auth = authority.authorization
    require(authority.config.get("launch_authorized") is True and auth.get("allow_launch") is True,
            "NO_LAUNCH_NOW")
    require(auth.get("config_sha256") == authority.config_sha256 and
            authority.source == (request.get("source_commit"), request.get("source_tree"), True),
            "exact clean remote source/config identity")
    require(all(auth.get(name) == request.get(name) for name in ("source_commit", "source_tree", *HASH_FIELDS)),
            "remote source/target/input/task authorization")
    require(host in auth.get("allowed_hosts", []) and request.get("task_id") in auth.get("allowed_task_ids", []) and
            "dispatch" in auth.get("allowed_operations", []) and parse_utc(auth["expires_utc"]) > authority.now(),
            "remote authorization task/host/operation/expiry")
    if host == "hummingbird":
        require(bool(os.environ.get("SLURM_JOB_ID")) and bool(os.environ.get("SLURM_JOB_NODELIST")) and
                actual_host not in ("muscat", "jerez", "hummingbird"),
                "Hummingbird verifier must execute in a compute allocation")
    authority.qualification(host, request["source_commit"], request["source_manifest_sha256"])
    names = ("source_root", "request_path", "ticket_path", "authorization_path", "source_manifest_path", "ledger_path")
    paths = {name: request.get("coordinator_" + name) for name in names}
    require(all(isinstance(value, str) and Path(value).is_absolute() for value in paths.values()), "six frozen coordinator paths")
    require(str(args.ledger) == paths["ledger_path"], "central ledger path mismatch")
    command = [authority.config["coordinator_python_bin"], str(Path(paths["source_root"]) / "application/scripts/forecast_transition_control.py"),
        "verify-claim", "--ledger", paths["ledger_path"], "--ticket", paths["ticket_path"],
        "--ticket-sha256", args.ticket_sha256, "--request", paths["request_path"],
        "--authorization", paths["authorization_path"], "--authorization-sha256", args.authorization_sha256,
        "--source-root", paths["source_root"], "--source-manifest", paths["source_manifest_path"]]
    result = subprocess.run(ssh_argv(authority.config["coordinator_ssh_profile"], shlex.join(command)),
                            text=True, capture_output=True, check=True, timeout=60)
    observed = json.loads(result.stdout)
    require(observed.get("verified") is True and observed.get("task_id") == request["task_id"]
            and observed.get("host") == host, "central verification receipt mismatch")
    return observed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", default="plan",
                        choices=("plan", "dry-run", "preflight", "dispatch", "verify-claim", "verify-claim-remote", "supervise",
                                 "close-supervised", "abandon-preintent", "accept", "reassign"))
    parser.add_argument("--config", type=Path, default=Path(__file__).resolve().parents[1] / "config/forecast_transition_multihost_v1.json")
    parser.add_argument("--host", choices=("muscat", "jerez", "hummingbird"))
    parser.add_argument("--task", type=Path)
    parser.add_argument("--ledger", type=Path)
    parser.add_argument("--ticket", type=Path)
    parser.add_argument("--ticket-sha256")
    parser.add_argument("--request", type=Path)
    parser.add_argument("--authorization", type=Path)
    parser.add_argument("--authorization-sha256")
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--source-manifest", type=Path)
    parser.add_argument("--resource-receipt", type=Path)
    parser.add_argument("--grant", type=Path)
    parser.add_argument("--budget", type=Path)
    parser.add_argument("--owner")
    parser.add_argument("--intent-directory", type=Path)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--supervision-spec", type=Path)
    parser.add_argument("--supervision-spec-sha256")
    parser.add_argument("--nonce")
    parser.add_argument("--proof", type=Path)
    parser.add_argument("--proof-sha256")
    parser.add_argument("--terminal-receipt", type=Path)
    parser.add_argument("--terminal-receipt-sha256")
    parser.add_argument("--completion", type=Path)
    parser.add_argument("--completion-sha256")
    parser.add_argument("--output-root", type=Path)
    parser.add_argument("--new-routing-id")
    parser.add_argument("--new-host", choices=("muscat", "jerez", "hummingbird"))
    parser.add_argument("--routing-revision", type=int)
    args = parser.parse_args(argv)
    config = read_json(args.config)
    validate_config(config)
    if args.command in ("close-supervised", "abandon-preintent", "accept", "reassign"):
        print(json.dumps(closeout_cli(args, config), sort_keys=True))
        return 0
    if args.command in ("verify-claim", "verify-claim-remote", "supervise"):
        request, authority, receipt = verification_context(args, config)
        if args.command == "supervise":
            require(args.supervision_spec and valid_hash(args.supervision_spec_sha256) and
                    file_sha256(args.supervision_spec) == args.supervision_spec_sha256 == receipt["supervision_spec_sha256"],
                    "source-owned supervisor specification must match the coordinator intent")
            spec = read_json(args.supervision_spec)
            require(spec.get("request_sha256") == file_sha256(args.request) and
                    spec.get("identity") == {name: request[name] for name in IDENTITY_FIELDS},
                    "supervisor request/source/target/input identity changed")
            terminal = supervised_child(spec, receipt)
            print(json.dumps({"phase": "terminal_receipt_published", "claim_nonce": receipt["claim_nonce"],
                              "exit_code": terminal["exit_code"]}, sort_keys=True))
            return 0 if terminal["exit_code"] == 0 else 1
        print(json.dumps(receipt, sort_keys=True))
        return 0
    if args.command == "dispatch" and args.execute:
        require(all((args.task, args.host, args.request, args.ticket, args.ledger, args.authorization,
                     args.authorization_sha256, args.source_root, args.source_manifest,
                     args.resource_receipt, args.grant, args.budget, args.owner, args.intent_directory)),
                "dispatch requires exact source/request/authority/resource/grant/budget/ledger paths")
        task = read_json(args.task)
        request = read_json(args.request)
        authorization, auth_sha = load_authorization(args.authorization, args.authorization_sha256, args.source_root)
        rows = verify_file_manifest(args.source_root, args.source_manifest, task["source_manifest_sha256"], source=True)
        verify_production_config(args.config, args.source_root, rows, authorization.get("config_sha256"))
        auth = Authority(config, file_sha256(args.config), authorization, auth_sha, git_identity(args.source_root))
        auth.check("claim", task, args.host)
        require(request_spec_sha256(request) == task["request_spec_sha256"], "frozen request before admission")
        require(request.get("authorization_sha256") in (None, "", auth_sha), "request external authority hash")
        require(not args.ticket.exists(), "claim ticket output is create-only")
        resource = read_json(args.resource_receipt)
        grant = read_json(args.grant)
        budget = read_json(args.budget)
        ledger = Ledger(args.ledger, auth)
        try:
            ticket = ledger.claim(task, args.host, args.owner, resource, grant, budget)
            with args.ticket.open("xb") as stream:
                stream.write(canonical(ticket) + b"\n"); stream.flush(); os.fsync(stream.fileno())
            envelope_path = args.intent_directory / (ticket["claim_nonce"] + ".request.json")
            execution_source = args.source_root
            execution_manifest = args.source_manifest
            execution_request, execution_ticket, execution_authorization = envelope_path, args.ticket, args.authorization
            execution_log = args.intent_directory
            metadata = []
            envelope = dict(request, allow_launch=True, authorization_sha256=auth_sha, output_root=ticket["output_root"], claim_ticket_path=str(args.ticket),
                claim_ticket_sha256=file_sha256(args.ticket), host=args.host, routing_id=ticket["routing_id"])
            if args.host != "muscat":
                qualified = authorization["qualified_hosts"][args.host]
                execution_source = Path(qualified["source_root"])
                execution_log = Path(qualified["metadata_root"])
                require(execution_source.is_absolute() and execution_log.is_absolute(), "qualified existing remote roots")
                execution_manifest = execution_source / args.source_manifest.relative_to(args.source_root)
                execution_request = execution_log / envelope_path.name
                execution_ticket = execution_log / (ticket["claim_nonce"] + ".ticket.json")
                execution_authorization = execution_log / (ticket["claim_nonce"] + ".authorization.json")
                envelope.update(claim_ticket_path=str(execution_ticket), coordinator_source_root=str(args.source_root),
                    coordinator_request_path=str(envelope_path), coordinator_ticket_path=str(args.ticket),
                    coordinator_authorization_path=str(args.authorization), coordinator_source_manifest_path=str(args.source_manifest),
                    coordinator_ledger_path=str(args.ledger), ledger_path=str(args.ledger))
            require(envelope.get("source_manifest_path") in (None, str(execution_manifest)),
                    "prepared source-manifest path must match qualified execution source")
            with envelope_path.open("xb") as stream:
                stream.write(canonical(envelope) + b"\n"); stream.flush(); os.fsync(stream.fileno())
            argv = worker_argv(config, args.host, task, envelope, execution_request, execution_ticket, execution_authorization,
                               args.ledger, execution_manifest, execution_source, file_sha256(args.ticket))
            supervision_path = args.intent_directory / (ticket["claim_nonce"] + ".supervision.json")
            execution_supervision = execution_log / supervision_path.name
            supervision = {"schema_version": "forecast_transition_supervision_v1", "task_id": task["task_id"],
                "routing_id": ticket["routing_id"], "claim_nonce": ticket["claim_nonce"], "host": args.host,
                "source_root": str(execution_source), "worker_argv": argv, "budget": budget,
                "numerical_backend": auth.qualification(args.host, task["source_commit"], task["source_manifest_sha256"])["numerical_backend"],
                "identity": {name: envelope[name] for name in IDENTITY_FIELDS},
                "request_sha256": file_sha256(envelope_path),
                "started_path": str(execution_log / (ticket["claim_nonce"] + ".started.json")),
                "terminal_path": str(execution_log / (ticket["claim_nonce"] + ".terminal.json")),
                "log_path": str(execution_log / (ticket["claim_nonce"] + ".stdout.log"))}
            durable_json(supervision_path, supervision, max_bytes=1024 ** 2)
            metadata = [{"role": role, "local_path": str(local), "remote_path": str(remote), "sha256": file_sha256(local)}
                for role, local, remote in (("request", envelope_path, execution_request),
                    ("claim_ticket", args.ticket, execution_ticket), ("authorization", args.authorization, execution_authorization),
                    ("supervision", supervision_path, execution_supervision))]
            require(2 * sum(Path(record["local_path"]).stat().st_size for record in metadata) + 4 * 65536 <= budget["metadata_bytes"],
                    "frozen metadata plus durable receipts exceed administrative byte reserve")
            ledger.prepare_intent(ticket["claim_nonce"], args.intent_directory, argv, metadata)
            result = ledger.dispatch(ticket["claim_nonce"], qualified_submitter(args.host, argv, execution_source,
                budget, resource, execution_log, task, ticket, config, auth, metadata))
            print(json.dumps(result, sort_keys=True))
        finally:
            ledger.close()
        return 0
    task = read_json(args.task) if args.task else None
    if task:
        validate_task(task)
    hosts = [args.host] if args.host else list(config["hosts"])
    result = {"schema_version": "forecast_transition_dry_run_v1", "production_actions": 0,
              "ledger_created": False, "launch_authorized": config["launch_authorized"],
              "config_sha256": file_sha256(args.config), "hosts": {host: {
                  "adapter": config["hosts"][host]["adapter"], "gates": host_gates(config, host),
                  "ready": False, "initial_worker_cap": config["hosts"][host]["initial_max_workers"]}
                  for host in hosts}}
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except GateError as error:
        print("FORECAST_TRANSITION_GATE_FAILED: " + str(error), file=sys.stderr)
        raise SystemExit(2)
