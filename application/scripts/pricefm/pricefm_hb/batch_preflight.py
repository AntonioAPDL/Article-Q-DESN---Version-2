"""Read-only HB scheduler preflight and fail-closed compute-placement policy.

Python/R payloads and their supervisors belong inside a Slurm allocation.
This client runs on Muscat and sends only fixed administrative commands.
It cannot submit jobs, install software or execute a user-supplied command.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import shlex
import stat
import time

MAX_BYTES = 1048576
COMMANDS = (
    ("association", ("sacctmgr", "-n", "-P", "show", "assoc", "user=jaguir26",
     "format=Cluster,Account,Partition,QOS,DefaultQOS,GrpTRES,MaxTRES,MaxJobs,MaxSubmit,MaxWall")),
    ("normal_qos", ("sacctmgr", "-n", "-P", "show", "qos", "normal",
     "format=Name,MaxTRESPU,MaxJobsPU,MaxSubmitPU,MaxWall")),
    ("partition", ("scontrol", "-o", "show", "partition", "128x24")),
    ("own_queue_ids_only", ("squeue", "-h", "-u", "jaguir26", "-o", "%i|%T")),
    ("R_modules", ("bash", "-lc", "module --terse avail r 2>&1")),
)
POLICY_URL = "https://hummingbird.ucsc.edu/getting-started/"
SUPERVISOR_SHA256 = "7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1"


def require(value, message):
    if not value:
        raise ValueError(message)


def bounded_bytes(path):
    path = Path(path).absolute()
    require(not any(p.is_symlink() for p in (path, *path.parents)), "symlink metadata path")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as handle:
        before = os.fstat(handle.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_uid == os.getuid()
                and before.st_nlink == 1 and before.st_size <= MAX_BYTES,
                "bounded single-link metadata required")
        raw = handle.read(MAX_BYTES + 1)
        after = os.fstat(handle.fileno())
    identity = lambda x: (x.st_dev, x.st_ino, x.st_size, x.st_mtime_ns, x.st_ctime_ns)
    require(identity(before) == identity(after) == identity(path.stat()), "metadata changed")
    return raw


def pin(path):
    path = Path(path).absolute()
    return {"path": str(path), "sha256": hashlib.sha256(bounded_bytes(path)).hexdigest()}


def strict_json(raw):
    def pairs(items):
        value = {}
        for key, item in items:
            require(key not in value, "duplicate JSON key")
            value[key] = item
        return value
    def invalid(value):
        raise ValueError("nonfinite JSON value: " + value)
    def finite_float(text):
        value = float(text)
        require(math.isfinite(value), "overflowed/nonfinite JSON float")
        return value
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid, parse_float=finite_float)


def read(value):
    require(type(value) is dict and set(value) == {"path", "sha256"}, "exact pin required")
    raw = bounded_bytes(value["path"])
    require(hashlib.sha256(raw).hexdigest() == value["sha256"], "metadata pin differs")
    return strict_json(raw)


def write(path, value):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump(value, handle, sort_keys=True, indent=2, allow_nan=False)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    parent = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(parent)
    finally:
        os.close(parent)


def site_ssh(site):
    require((site.get("host"), site.get("user"), site.get("account"), site.get("partition"), site.get("qos"))
            == ("hb.ucsc.edu", "jaguir26", "128x24", "128x24", "normal"), "unreviewed HB site")
    for name in ("known_hosts_file", "ssh_identity_file"):
        path = Path(site[name])
        require(path.is_absolute() and path.is_file() and not any(p.is_symlink() for p in (path, *path.parents)),
                "missing physical trust/identity path")
    return ["ssh", "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
            "-o", "UpdateHostKeys=no", "-o", "ControlMaster=no", "-o", "ControlPath=none",
            "-o", "IdentitiesOnly=yes", "-o", "IdentityAgent=none", "-o", "ForwardAgent=no",
            "-o", "ClearAllForwardings=yes", "-o", "PreferredAuthentications=publickey",
            "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no",
            "-o", "ConnectTimeout=10", "-o", "ConnectionAttempts=1",
            "-o", "UserKnownHostsFile=" + site["known_hosts_file"], "-i", site["ssh_identity_file"],
            "jaguir26@hb.ucsc.edu"]


def login_argv(site, label, command):
    require((label, tuple(command)) in COMMANDS, "login command outside fixed administrative allowlist")
    return site_ssh(site) + [shlex.join(command)]


def qualify_compute_policy(value):
    """Validate a proposed *future* placement, never grant admission."""
    require(value.get("placement") == "SLURM_COMPUTE", "all interpreted payloads require compute placement")
    require(all(type(value.get(k)) is int for k in ("nodes", "tasks", "cpus_per_task", "threads", "memory_MiB")),
            "resource counts must be exact integers")
    require(value.get("nodes") == value.get("tasks") == value.get("cpus_per_task") == 1,
            "one node/task/physical CPU only")
    require(value.get("threads") == 1 and value.get("memory_MiB") == 8192,
            "original one-thread/8GiB bound required")
    require(value.get("requeue") is False and value.get("login_fallback") is False,
            "no requeue or login fallback")
    require(type(value.get("wall_seconds")) is int and 0 < value["wall_seconds"] <= 1200,
            "bounded initial qualification wall")
    require(type(value.get("aggregate_CPU_seconds")) in (int, float)
            and 0 < value["aggregate_CPU_seconds"] <= 600, "bounded initial qualification CPU")
    require(value.get("scientific_data_access") is False
            and type(value.get("optimizer_invocations")) is int and value["optimizer_invocations"] == 0,
            "initial runtime qualification is metadata-only")
    return {"status": "VALID_PLACEMENT_POLICY_NOT_ADMISSION",
            "actual_runtime_parity_proven": False, "submission_authorized": False,
            "separate_source_bound_budget_ready_and_review_required": True}


def scope_check(scope_pin, output):
    scope = read(scope_pin)
    require(scope.get("status") == "PROSPECTIVE_PRICEFM_CONTINUATION_IMPLEMENTATION_SCOPE",
            "wrong prospective scope kind")
    require(scope["issued_epoch"] <= time.time() < scope["expires_epoch"], "scope expired/not issued")
    allowed = Path(scope["allowed_metadata_output_root"]).absolute()
    output = Path(output).absolute()
    require(output != allowed and output.is_relative_to(allowed), "output must be a child of scoped metadata root")
    require(not any(p.is_symlink() for p in (output, *output.parents)), "physical output path")
    return scope


def prepare(site_pin, scope_pin, output, supervisor_pin):
    require(os.sched_getaffinity(0) == {31}, "administrative CPU31 required")
    scope = scope_check(scope_pin, output)
    require(time.time() + 120 < scope["expires_epoch"], "complete finite preflight must fit scope")
    site = read(site_pin)
    output = Path(output).absolute()
    require(pin(supervisor_pin["path"]) == supervisor_pin
            and supervisor_pin["sha256"] == SUPERVISOR_SHA256, "original supervisor source differs")
    output.mkdir(mode=0o700, exist_ok=False)
    self_pin = pin(__file__)
    write(output / "INTENT.json", dict(status="READONLY_PREFLIGHT_INTENT_NOT_SUCCESS",
          source=self_pin, scope=scope_pin, site=site_pin, created_epoch=time.time(),
          operations=[x[0] for x in COMMANDS], remote_Python_or_R=False,
          job_submissions=0, remote_CPU_unknown_full_reservation_retained=True))
    plans = []
    for index, (label, command) in enumerate(COMMANDS):
        require(pin(__file__) == self_pin and pin(site_pin["path"]) == site_pin, "preflight binding drift")
        argv = login_argv(site, label, command)
        plan = dict(status="PREPARED_NATIVE_READONLY_OPERATION_NOT_EXECUTED", index=index,
                    label=label, command=list(command), argv=argv, source=self_pin,
                    scope=scope_pin, site=site_pin, output_root=str(output),
                    supervisor=supervisor_pin, CPU=4, wall=30, output_cap=MAX_BYTES,
                    one_shot=True, created_epoch=time.time())
        path = output / f"OP_{index}_PLAN.json"
        write(path, plan)
        plans.append(pin(path))
    result = dict(status="PREPARED_FIVE_NATIVE_OPERATIONS_NOT_EXECUTED", source=self_pin,
                  scope=scope_pin, site=site_pin, plans=plans, local_CPU_reservation=20,
                  remote_CPU_unknown_reservation=20, job_submissions=0)
    write(output / "PREPARED.json", result)
    return result


def execution_context():
    values = dict(line.split(":", 1) for line in Path("/proc/self/status").read_text().splitlines()
                  if ":" in line)
    require(values["NoNewPrivs"].strip() == "1" and values["Seccomp"].strip() == "2",
            "original guardian kernel context required")
    require(os.getpid() == os.getsid(0) == os.getpgrp() and os.sched_getaffinity(0) == {31},
            "exact isolated guardian command required")
    fields = Path("/proc/self/stat").read_text().rsplit(")", 1)[1].split()
    return {"pid": os.getpid(), "start_ticks": int(fields[19])}


def execute(plan_pin):
    plan = read(plan_pin)
    output = Path(plan["output_root"])
    scope = scope_check(plan["scope"], output)
    require(time.time() + plan["wall"] < scope["expires_epoch"], "operation must fit fixed deadline")
    require(plan["status"] == "PREPARED_NATIVE_READONLY_OPERATION_NOT_EXECUTED"
            and plan["source"] == pin(__file__), "operation source or role differs")
    require(plan["CPU"] == 4 and plan["wall"] == 30 and plan["output_cap"] == MAX_BYTES,
            "original operation bounds differ")
    require(type(plan["index"]) is int and 0 <= plan["index"] < len(COMMANDS), "operation index")
    label, command = COMMANDS[plan["index"]]
    require(plan["label"] == label and plan["command"] == list(command), "fixed operation differs")
    require(plan["argv"] == login_argv(read(plan["site"]), label, command), "SSH operation differs")
    require(plan["supervisor"]["sha256"] == SUPERVISOR_SHA256
            and pin(plan["supervisor"]["path"]) == plan["supervisor"], "original supervisor source drift")
    require(Path(plan_pin["path"]) == output / f'OP_{plan["index"]}_PLAN.json', "plan path binding")
    context = execution_context()
    write(output / f'OP_{plan["index"]}_EXECUTION_INTENT.json',
          dict(status="SPENT_EXECUTION_INTENT_NOT_SUCCESS", plan=plan_pin,
               identity=context, created_epoch=time.time()))
    # No coordinator subprocess or inner timeout: the original outer guardian
    # owns this same PID and all cancellation, output bounds and descendant drain.
    os.execvp(plan["argv"][0], plan["argv"])


def finalize(output):
    output = Path(output).absolute()
    prepared = read(pin(output / "PREPARED.json"))
    scope_check(prepared["scope"], output)
    require(prepared["status"] == "PREPARED_FIVE_NATIVE_OPERATIONS_NOT_EXECUTED"
            and prepared["source"] == pin(__file__), "prepared role/source drift")
    site = read(prepared["site"])
    require(len(prepared["plans"]) == len(COMMANDS), "all fixed operations required")
    guards = []
    rows = []
    for index, plan_pin in enumerate(prepared["plans"]):
        plan = read(plan_pin)
        label, command = COMMANDS[index]
        require(plan["index"] == index and plan["source"] == prepared["source"]
                and plan["scope"] == prepared["scope"] and plan["site"] == prepared["site"]
                and plan["output_root"] == str(output)
                and plan["label"] == label and plan["command"] == list(command)
                and plan["argv"] == login_argv(site, label, command)
                and plan["CPU"] == 4 and plan["wall"] == 30 and plan["output_cap"] == MAX_BYTES
                and plan["supervisor"]["sha256"] == SUPERVISOR_SHA256
                and pin(plan["supervisor"]["path"]) == plan["supervisor"], "complete operation binding")
        intent = read(pin(output / f"OP_{index}_EXECUTION_INTENT.json"))
        require(intent["plan"] == plan_pin, "one-shot execution intent binding")
        guard_pin = pin(output / f"OP_{index}_GUARD.json")
        guard = read(guard_pin)
        validate_operation_guard(guard)
        require(guard["session_id"] == intent["identity"]["pid"]
                and guard["leader_start_ticks"] == intent["identity"]["start_ticks"],
                "actual guardian/exec PID lifetime differs")
        require(len(guard["stdout"].encode()) <= MAX_BYTES
                and len(guard["stderr"].encode()) <= MAX_BYTES, "bounded output")
        guards.append(guard_pin)
        rows.append(dict(label=plan["label"], stdout=guard["stdout"], stderr=guard["stderr"]))
    queue = next(x for x in rows if x["label"] == "own_queue_ids_only")
    result = dict(status="PASS_NATIVE_READONLY_PREFLIGHT_NOT_ADMISSION",
        source=prepared["source"], scope=prepared["scope"], site=prepared["site"],
        observed_epoch=time.time(), operations=guards,
        own_queue_empty=not queue["stdout"].strip(),
        R_module_output_only_not_runtime_proof=True, empty_limit_fields_are_unknown_not_unlimited=True,
        all_Python_R_and_supervisors_compute_only=True, policy_url=POLICY_URL,
        source_bound_runtime_qualification_required=True, submission_authorized=False,
        remote_CPU_measured=False, remote_CPU_reservation_retained=20,
        new_models=0, job_submissions=0)
    write(output / "RESULT.json", result)
    return result


def validate_operation_guard(guard):
    numeric = lambda x: type(x) in (int, float) and math.isfinite(x)
    require(type(guard["returncode"]) is int and type(guard["command_returncode"]) is int
            and guard["returncode"] == guard["command_returncode"] == 0
            and guard["all_owned_descendants_reaped"] is True
            and guard["kernel_escape_filter"] is True
            and guard["independent_guardian"] is True
            and type(guard["CPU_limit"]) is int and guard["CPU_limit"] == 4
            and numeric(guard["aggregate_CPU_seconds"]) and 0 <= guard["aggregate_CPU_seconds"] < 4
            and numeric(guard["complete_lifecycle_wall_seconds"])
            and 0 <= guard["complete_lifecycle_wall_seconds"] <= 30
            and guard["cap_reason"] is None and guard["guardian_forced_monitor_stop"] is False
            and type(guard["stdout"]) is str and type(guard["stderr"]) is str,
            "actual native operation guardian did not pass")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--action", choices=("prepare", "execute", "finalize"), required=True)
    p.add_argument("--site")
    p.add_argument("--scope")
    p.add_argument("--output")
    p.add_argument("--supervisor")
    p.add_argument("--plan")
    p.add_argument("--plan-sha256")
    args = p.parse_args()
    inherited = resource.getrlimit(resource.RLIMIT_CPU)
    cap = min([8] + [x for x in inherited if x != resource.RLIM_INFINITY])
    require(cap > 0, "positive inherited CPU allowance required")
    resource.setrlimit(resource.RLIMIT_CPU, (cap, cap))
    if args.action == "prepare":
        require(all((args.site, args.scope, args.output, args.supervisor)), "prepare arguments required")
        result = prepare(pin(args.site), pin(args.scope), args.output, pin(args.supervisor))
    elif args.action == "execute":
        require(args.plan and args.plan_sha256, "exact plan and SHA required")
        execute({"path": str(Path(args.plan).absolute()), "sha256": args.plan_sha256})
        raise RuntimeError("exec unexpectedly returned")
    else:
        require(args.output, "finalize output required")
        result = finalize(args.output)
    print(json.dumps(result))
    return 0 if args.action == "prepare" or result["status"].startswith("PASS") else 2


if __name__ == "__main__":
    raise SystemExit(main())
