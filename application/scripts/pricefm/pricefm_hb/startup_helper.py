"""Source-bound metadata startup proofs using the unchanged owned supervisor.

This adapter creates no child.  After finite validation and an exclusive intent
it execs the pinned existing supervisor in the same PID.  Its startup CPU and
process birth therefore remain in that supervisor's existing whole-lifecycle
accounting.  A Python helper result is never an R startup or numerical proof.
"""
from __future__ import annotations

import argparse
import errno
import hashlib
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

SUPERVISOR_SHA256 = "7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1"
ROLES = {"SYNTHETIC_OWNED_HELPER", "R_STARTUP_METADATA_ONLY"}
CASES = {"wait_and_escape", "orphan", "nonzero_helper", "cpu_boundary", "wall_boundary"}
THREAD_KEYS = {"OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
               "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "BLIS_NUM_THREADS"}
ENV_KEYS = THREAD_KEYS | {"PATH", "LANG", "LC_ALL", "TZ", "TMPDIR", "HOME", "R_HOME", "R_ARCH",
    "R_DOC_DIR", "R_INCLUDE_DIR", "R_SHARE_DIR", "R_LIBS_USER", "R_LIBS_SITE", "LD_LIBRARY_PATH",
    "SLURM_JOB_ID", "SLURMD_NODENAME", "SLURM_CPUS_PER_TASK"}


def require(value, message):
    if not value:
        raise ValueError(message)


def physical(path):
    path = Path(path)
    require(path.is_absolute() and ".." not in path.parts, "absolute canonical path required")
    require(not any(p.is_symlink() for p in (path, *path.parents)), "symlink path rejected")
    return path


def _fingerprint(item):
    return (item.st_dev, item.st_ino, item.st_uid, item.st_mode, item.st_nlink,
            item.st_size, item.st_mtime_ns, item.st_ctime_ns)


def read_pin(value, limit=16 * 1024**2):
    require(type(value) is dict and set(value) == {"path", "sha256"}, "strict pin required")
    require(type(value["sha256"]) is str and re.fullmatch("[0-9a-f]{64}", value["sha256"]),
            "SHA256 required")
    path = physical(value["path"])
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as handle:
        before = os.fstat(handle.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_uid in (0, os.getuid())
                and before.st_nlink == 1 and before.st_size <= limit, "bounded owned/system regular file required")
        data = handle.read(limit + 1)
        after = os.fstat(handle.fileno())
    require(_fingerprint(before) == _fingerprint(after) == _fingerprint(path.stat()),
            "pinned file changed during read")
    require(len(data) == before.st_size and hashlib.sha256(data).hexdigest() == value["sha256"],
            "pinned bytes differ")
    return data


def pin(path, limit=16 * 1024**2):
    path = physical(path)
    require(path.stat().st_size <= limit, "bounded pin input required")
    data = path.read_bytes()
    value = {"path": str(path), "sha256": hashlib.sha256(data).hexdigest()}
    read_pin(value, limit)
    return value


def strict_json(raw):
    def pairs(items):
        result = {}
        for key, item in items:
            require(key not in result, "duplicate JSON field")
            result[key] = item
        return result
    def bad(_):
        raise ValueError("nonfinite JSON value")
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=bad)


def read(value):
    return strict_json(read_pin(value))


def write_new(path, value):
    path = physical(path)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump(value, handle, sort_keys=True, indent=2, allow_nan=False)
        handle.write("\n"); handle.flush(); os.fsync(handle.fileno())
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def source_pins(role):
    here = Path(__file__).absolute().parent
    fixture = here / ("startup_helper_fixture.py" if role == "SYNTHETIC_OWNED_HELPER"
                      else "startup_helper_metadata_fixture.R")
    result = {"adapter": pin(Path(__file__).absolute()), "supervisor": pin(here / "profile_supervisor.py"),
              "fixture": pin(fixture)}
    require(result["supervisor"]["sha256"] == SUPERVISOR_SHA256,
            "only unchanged qualified supervisor source is supported")
    return result


def validate(plan_pin, authority_pin, review_pin, *, now=None, affinity=None, environ=None,
             hostname=None, completed=False):
    """Pure metadata gate; no intent, child, signal or output is created here."""
    now = time.time() if now is None else now
    affinity = os.sched_getaffinity(0) if affinity is None else affinity
    environ = os.environ if environ is None else environ
    hostname = os.uname().nodename if hostname is None else hostname
    plan, authority, review = read(plan_pin), read(authority_pin), read(review_pin)
    require(plan["schema"] == "pricefm_startup_helper_plan_v1" and plan["role"] in ROLES,
            "supported startup-only role required")
    role = plan["role"]
    require(type(plan["nonce"]) is str and re.fullmatch("[0-9a-f]{32}", plan["nonce"]), "nonce required")
    sources = source_pins(role)
    require(plan["sources"] == sources, "current complete source closure differs")
    require(review["status"] == "PASS_REVIEWED_STARTUP_HELPER_SOURCE_AND_PLAN"
            and review["plan"] == plan_pin and review["sources"] == sources,
            "actual independent exact-plan/source review required")
    require(authority["schema"] == "pricefm_startup_helper_authority_v1"
            and authority["status"] == "ROOT_AUTHORIZED_SOURCE_BOUND_STARTUP_HELPER_PROOF"
            and authority["plan"] == plan_pin and authority["source_review"] == review_pin
            and authority["role"] == role and authority["sources"] == sources,
            "fresh source-bound root startup authority required")
    require(type(authority["executions"]) is int and authority["executions"] == 1
            and authority["no_real_target_data_or_optimizer"] is True,
            "one metadata-only invocation required")
    scope = read(authority["root_scope"])
    allowed_scope = ("PROSPECTIVE_PRICEFM_CONTINUATION_IMPLEMENTATION_SCOPE" if role == "SYNTHETIC_OWNED_HELPER"
                     else "PROSPECTIVE_PRICEFM_STARTUP_COMPUTE_QUALIFICATION_SCOPE")
    require(scope["status"] == allowed_scope and type(scope["issued_epoch"]) in (int, float)
            and scope["issued_epoch"] <= authority["issued_epoch"], "purpose-specific prospective root scope required")
    require(type(authority["issued_epoch"]) in (int, float)
            and authority["issued_epoch"] <= now < authority["expires_epoch"] <= scope["expires_epoch"],
            "startup authority expired or outside root scope")
    if completed:
        require(time.time() < authority["expires_epoch"] <= scope["expires_epoch"],
                "finalization cannot extend the original startup authority or root deadline")
    limits = plan["limits"]
    require(type(limits) is dict and set(limits) == {"CPU", "wall", "output_cap"}
            and type(limits["CPU"]) is int and 2 <= limits["CPU"] <= 30
            and type(limits["wall"]) is int and 4 <= limits["wall"] <= 120
            and type(limits["output_cap"]) is int and 1024 <= limits["output_cap"] <= 1048576,
            "finite startup CPU/wall/output limits required")
    require(authority["limits"] == limits and review["limits"] == limits
            and now + limits["wall"] < authority["expires_epoch"], "funded complete lifecycle must fit")
    placement = plan["placement"]
    require(authority["placement"] == placement, "placement authority differs")
    if role == "SYNTHETIC_OWNED_HELPER":
        require(type(placement) is dict and set(placement) == {"kind", "CPU", "hostname"}
                and placement["kind"] == "ADMINISTRATIVE_SYNTHETIC" and placement["CPU"] == 31
                and plan["case"] in CASES, "synthetic own-helper placement required")
        if not completed:
            require(affinity == {31} and hostname == placement["hostname"], "actual administrative host/CPU differs")
    else:
        require(placement["kind"] == "SLURM_SINGLE_CPU_METADATA"
                and type(placement["job_id"]) is str and placement["job_id"].isdigit()
                and type(placement["node"]) is str and re.fullmatch(r"node-[0-9]+", placement["node"]),
                "R requires a separately bound Slurm compute placement")
        if not completed:
            require(hostname.split(".")[0] == placement["node"]
                    and environ.get("SLURMD_NODENAME") == placement["node"]
                    and environ.get("SLURM_JOB_ID") == placement["job_id"]
                    and environ.get("SLURM_CPUS_PER_TASK") == "1",
                    "actual Slurm compute host/job/one-CPU metadata differ; login and local R are unsupported")
        require(plan["runtime"]["version"] == "4.6.0", "only the proposed R4.6.0 metadata runtime is supported")
    if not completed:
        require(type(affinity) in (set, frozenset) and len(affinity) == 1, "one actual inherited CPU required")
    environment = plan["environment"]
    require(type(environment) is dict and set(environment) <= ENV_KEYS
            and THREAD_KEYS <= set(environment) and all(environment[k] == "1" for k in THREAD_KEYS),
            "exact allowlisted single-thread environment required")
    require(all(type(k) is str and type(v) is str and "\x00" not in v and len(v) <= 4096
                for k, v in environment.items()), "bounded environment strings required")
    require(environment.get("PATH") == "/usr/bin:/bin" and environment.get("LC_ALL") == "C",
            "reviewed helper PATH/locale required")
    runtime, python = plan["runtime"], plan["supervisor_python"]
    require(read_pin(python, 64 * 1024**2)[:4] == b"\x7fELF", "pinned native supervisor Python required")
    require(read_pin(runtime["executable"], 64 * 1024**2)[:4] == b"\x7fELF", "pinned native runtime required")
    require(type(plan["runtime_files"]) is list and len(plan["runtime_files"]) <= 2048,
            "bounded runtime/helper file closure required")
    total_bytes = 0
    for value in plan["runtime_files"]:
        total_bytes += len(read_pin(value, 64 * 1024**2))
        require(total_bytes <= 128 * 1024**2, "total startup runtime file closure exceeds bound")
    if role == "SYNTHETIC_OWNED_HELPER":
        require(runtime["kind"] == "PYTHON_METADATA" and runtime["executable"] == python,
                "synthetic fixture uses the exact pinned Python")
        command = [python["path"], "-I", "-B", sources["fixture"]["path"],
                   "--case", plan["case"], "--nonce", plan["nonce"]]
    else:
        require(runtime["kind"] == "NATIVE_R_METADATA" and environment.get("R_HOME") == runtime["R_home"],
                "exact native R_HOME binding required")
        require(environment.get("SLURM_JOB_ID") == placement["job_id"]
                and environment.get("SLURMD_NODENAME") == placement["node"]
                and environment.get("SLURM_CPUS_PER_TASK") == "1", "replacement R environment loses allocation identity")
        require(all(name in runtime for name in ("uname", "which")), "startup helper paths required")
        require(all(runtime[name] in plan["runtime_files"] for name in ("uname", "which")),
                "both startup helper binaries must be pinned")
        require(type(runtime["helper_aliases"]) is list and len(runtime["helper_aliases"]) == 2,
                "explicit which/uname logical aliases required")
        aliases = {x["logical_path"]: x["resolved_file"] for x in runtime["helper_aliases"]}
        require(set(aliases) == {"/usr/bin/which", "/usr/bin/uname"}
                and aliases["/usr/bin/which"] == runtime["which"]
                and aliases["/usr/bin/uname"] == runtime["uname"], "helper aliases differ")
        for alias, target in aliases.items():
            require(str(Path(alias).resolve(strict=True)) == target["path"], "helper logical alias changed")
        command = [runtime["executable"]["path"], "--vanilla", "--slave", "--no-save", "--no-restore",
                   "--file=" + sources["fixture"]["path"], "--args", plan["nonce"]]
    require(plan["command"] == command, "fixture argv differs")
    output = physical(plan["output_dir"])
    parent = physical(authority["allowed_output_parent"])
    require(output.parent == parent and parent.is_dir(), "exact output child parent required")
    if not completed:
        require(not output.exists(), "new create-only exact output child required")
    else:
        require(output.is_dir(), "completed output directory required")
    return dict(plan=plan, authority=authority, review=review, sources=sources,
                plan_pin=plan_pin, authority_pin=authority_pin, review_pin=review_pin)


def launch(plan_pin, authority_pin, review_pin, *, CLI_CPU, CLI_wall, execute=os.execve):
    ctx = validate(plan_pin, authority_pin, review_pin)
    plan = ctx["plan"]; limits = plan["limits"]
    require((CLI_CPU, CLI_wall) == (limits["CPU"], limits["wall"]), "CLI limits differ from funded plan")
    output = physical(plan["output_dir"]); output.mkdir(mode=0o700)
    directory = os.open(output.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
    write_new(output / "execution_intent.json", dict(status="INTENT_NOT_SUCCESS", created_epoch=time.time(),
        plan=plan_pin, authority=authority_pin, source_review=review_pin, sources=ctx["sources"],
        process_pid=os.getpid(), process_birth_ticks=process_birth_ticks(),
        wrapper_SELF_CPU_seconds=sum(resource.getrusage(resource.RUSAGE_SELF)[:2]),
        no_child_created_by_adapter=True))
    argv = [plan["supervisor_python"]["path"], "-I", "-B", ctx["sources"]["supervisor"]["path"],
            "--cpu", str(limits["CPU"]), "--wall", str(limits["wall"]),
            "--output-cap", str(limits["output_cap"]), "--", *plan["command"]]
    execute(argv[0], argv, plan["environment"])
    raise RuntimeError("exec unexpectedly returned")


def process_birth_ticks():
    return int(Path("/proc/self/stat").read_text().rsplit(")", 1)[1].split()[19])


def finalize(plan_pin, authority_pin, review_pin, guard_pin):
    """Inspect completed artifacts only; a failed original guard stays failed."""
    plan = read(plan_pin)
    output = physical(plan["output_dir"])
    intent_pin = pin(output / "execution_intent.json"); intent = read(intent_pin)
    ctx = validate(plan_pin, authority_pin, review_pin, now=intent["created_epoch"], completed=True)
    authority = ctx["authority"]
    require(intent["plan"] == plan_pin and intent["authority"] == authority_pin
            and intent["source_review"] == review_pin and intent["sources"] == plan["sources"], "actual one-shot intent required")
    guard = read(guard_pin); limits = plan["limits"]
    require(type(guard["returncode"]) is type(guard["command_returncode"]) is int
            and guard["returncode"] == guard["command_returncode"] == 0 and guard["cap_reason"] is None,
            "actual original guardian command must pass")
    flags = ("all_owned_descendants_reaped", "kernel_escape_filter", "orphan_subreaper",
             "guardian_included_in_CPU", "independent_guardian", "guardian_nondumpable",
             "inherited_waited_history_included_once")
    require(all(guard.get(name) is True for name in flags)
            and guard.get("guardian_forced_monitor_stop") is False, "complete original guardian guarantees required")
    require(type(guard["CPU_limit"]) is int and guard["CPU_limit"] == limits["CPU"]
            and type(guard["aggregate_CPU_seconds"]) in (int, float)
            and math.isfinite(guard["aggregate_CPU_seconds"]) and 0 <= guard["aggregate_CPU_seconds"] < limits["CPU"]
            and type(guard["complete_lifecycle_wall_seconds"]) in (int, float)
            and math.isfinite(guard["complete_lifecycle_wall_seconds"])
            and 0 <= guard["complete_lifecycle_wall_seconds"] <= limits["wall"], "whole lifecycle limits exceeded")
    require(intent["created_epoch"] + guard["complete_lifecycle_wall_seconds"] < authority["expires_epoch"],
            "actual original lifecycle does not fit original startup authority")
    require(guard["bootstrap_anchor"]["guardian_pid"] == intent["process_pid"]
            and guard["bootstrap_anchor"]["guardian_birth_ticks"] == intent["process_birth_ticks"],
            "adapter exec PID/birth not conserved in original guard")
    require(guard["stderr"] == "", "startup warnings/errors are not a clean metadata proof")
    require(type(guard["reaped"]) is list and guard["reaped"]
            and all(type(x["returncode"]) is int and x["returncode"] == 0 for x in guard["reaped"]),
            "a failed adopted helper cannot become startup success")
    fixture = strict_json(guard["stdout"])
    require(fixture["nonce"] == plan["nonce"] and fixture["role"] == plan["role"]
            and type(fixture["models"]) is type(fixture["optimizer_invocations"]) is int
            and fixture["models"] == fixture["optimizer_invocations"] == 0
            and fixture["scientific_data_read"] is False, "exact metadata-only fixture handshake required")
    if plan["role"] == "SYNTHETIC_OWNED_HELPER":
        require(plan["case"] in {"wait_and_escape", "orphan"}
                and fixture["status"] == "PASS_SYNTHETIC_OWNED_HELPER_FIXTURE"
                and fixture["case"] == plan["case"], "synthetic case is not a successful R proof")
        if plan["case"] == "wait_and_escape":
            require(type(fixture["helper_wait_status"]) is int and fixture["helper_wait_status"] == 0
                    and type(fixture["escape_operations_denied"]) is int and fixture["escape_operations_denied"] == 3
                    and fixture["deliberate_nonzero_helper_status_observed"] == 7,
                    "helper wait or escape assertion failed")
        else:
            require(len(guard["reaped"]) >= 2 and fixture["intentionally_unwaited_private_helper"] is True,
                    "orphan proof needs actual adopted helper reap")
        status = "PASS_SYNTHETIC_OWNED_HELPER_CASE_NOT_R_STARTUP"
    else:
        runtime = plan["runtime"]
        require(fixture["status"] == "PASS_R_STARTUP_METADATA_FIXTURE" and fixture["R_version"] == runtime["version"]
                and fixture["R_home"] == runtime["R_home"] and fixture["default_utils_loaded"] is True
                and fixture["uname_path"] == runtime["uname"]["path"] and fixture["uname_result"] == "Linux",
                "actual native R/default utils/uname metadata proof required")
        require(fixture["hostname"].split(".")[0] == plan["placement"]["node"]
                and fixture["SLURM_JOB_ID"] == plan["placement"]["job_id"]
                and fixture["SLURMD_NODENAME"] == plan["placement"]["node"],
                "R fixture compute-host/job handshake differs")
        status = "PASS_R_METADATA_STARTUP_UNDER_OWNED_HELPER_GUARD"
    result = dict(status=status, plan=plan_pin, authority=authority_pin, source_review=review_pin,
        execution_intent=intent_pin, original_guard=guard_pin, fixture=fixture,
        source_closure=plan["sources"], whole_lifecycle_CPU_seconds=guard["aggregate_CPU_seconds"],
        whole_lifecycle_wall_seconds=guard["complete_lifecycle_wall_seconds"],
        R_startup_proved=plan["role"] == "R_STARTUP_METADATA_ONLY", numerical_parity_proved=False,
        real_target_bridge_proved=False, production_ready=False, old_scope_fee_refund=False)
    write_new(output / "startup_proof.json", result)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("launch", "finalize"))
    parser.add_argument("--plan", required=True); parser.add_argument("--authority", required=True)
    parser.add_argument("--review", required=True); parser.add_argument("--guard")
    parser.add_argument("--cpu", type=int, required=True); parser.add_argument("--wall", type=int, required=True)
    args = parser.parse_args(argv)
    require(2 <= args.cpu <= 30 and 4 <= args.wall <= 120, "bounded CLI lifecycle required")
    old = resource.getrlimit(resource.RLIMIT_CPU)
    cap = args.cpu if old[1] == resource.RLIM_INFINITY else min(args.cpu, old[1])
    resource.setrlimit(resource.RLIMIT_CPU, (cap, cap)); resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    lifetime = time.clock_gettime(time.CLOCK_BOOTTIME) - process_birth_ticks() / os.sysconf("SC_CLK_TCK")
    require(lifetime < args.wall, "wrapper lifecycle already exhausted")
    signal.setitimer(signal.ITIMER_REAL, args.wall - lifetime)
    pp, ap, rp = pin(args.plan), pin(args.authority), pin(args.review)
    if args.action == "launch":
        launch(pp, ap, rp, CLI_CPU=args.cpu, CLI_wall=args.wall)
    else:
        require(args.guard is not None, "completed original guard path required")
        print(json.dumps(finalize(pp, ap, rp, pin(args.guard)), sort_keys=True))


if __name__ == "__main__":
    main()
