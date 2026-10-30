"""Finite, privately owned synthetic kernel proof matrix; never R or a fit.

Preparation writes proposed plans only. Execution additionally needs actual
independent per-plan and matrix reviews plus fresh root authorities. The driver
has6 SELF CPU seconds; six independently capped4CPU commands reserve24 more.
It signals only pidfds whose UID, birth and direct private ancestry were proved.
"""
import argparse
import ctypes
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys
import time

from . import startup_helper as h

CASE_ROWS = (
    ("wait_and_escape", "wait_and_escape", "SUCCESS", 15),
    ("orphan", "orphan", "SUCCESS", 15),
    ("aggregate_CPU", "cpu_boundary", "CPU_BOUNDARY", 12),
    ("wall", "wall_boundary", "WALL_BOUNDARY", 6),
    ("monitor_death", "wall_boundary", "MONITOR_DEATH", 15),
    ("guardian_death", "wall_boundary", "GUARDIAN_DEATH", 15),
)


def sources():
    return dict(h.source_pins("SYNTHETIC_OWNED_HELPER"), kernel_driver=h.pin(Path(__file__).absolute()))


def prepare(output, python):
    """Create no authority or PASS review, and run no child or syscall test."""
    output = h.physical(output); output.mkdir(mode=0o700)
    (output / "plans").mkdir(mode=0o700)
    python = h.pin(Path(python).resolve(strict=True))
    rows = []
    for label, case, expectation, wall in CASE_ROWS:
        nonce = __import__("hashlib").sha256((str(output) + "/" + label).encode()).hexdigest()[:32]
        src = h.source_pins("SYNTHETIC_OWNED_HELPER")
        plan = dict(schema="pricefm_startup_helper_plan_v1", role="SYNTHETIC_OWNED_HELPER",
            nonce=nonce, sources=src, limits=dict(CPU=4, wall=wall, output_cap=1048576), case=case,
            placement=dict(kind="ADMINISTRATIVE_SYNTHETIC", CPU=31, hostname=os.uname().nodename),
            environment=dict(**{key: "1" for key in h.THREAD_KEYS}, PATH="/usr/bin:/bin", LC_ALL="C"),
            supervisor_python=python, runtime=dict(kind="PYTHON_METADATA", executable=python), runtime_files=[],
            output_dir=str(output / (label + "_work")))
        plan["command"] = [python["path"], "-I", "-B", src["fixture"]["path"],
                           "--case", case, "--nonce", nonce]
        path = output / "plans" / (label + ".json"); h.write_new(path, plan)
        rows.append(dict(label=label, expectation=expectation, plan=h.pin(path), guard_CPU_cap=4))
    index = dict(status="PREPARED_SYNTHETIC_KERNEL_PLANS_NOT_AUTHORIZED_OR_EXECUTED", sources=sources(),
        cases=rows, case_CPU_reservation=24, driver_SELF_CPU_reservation=6, total_CPU_reservation=30,
        actual_R_or_model_execution=False,
        remaining_gates=["actual independent per-plan reviews", "fresh root per-plan authorities",
                         "actual matrix review", "fresh root matrix execution authority"])
    h.write_new(output / "PLAN_INDEX.json", index)
    return h.pin(output / "PLAN_INDEX.json")


def process_record(pid):
    root = Path("/proc") / str(pid)
    fields = (root / "stat").read_text().rsplit(")", 1)[1].split()
    return dict(pid=pid, uid=root.stat().st_uid, ppid=int(fields[1]), start_ticks=int(fields[19]),
                sid=int(fields[3]), pgid=int(fields[2]), state=fields[0])


def children(pid):
    result = set()
    tasks = list((Path("/proc") / str(pid) / "task").iterdir())
    h.require(len(tasks) <= 64, "bounded private thread inventory required")
    for task in tasks:
        try:
            raw = (task / "children").read_text()
        except FileNotFoundError:
            continue
        h.require(len(raw) <= 65536, "private child inventory too large")
        result.update(int(x) for x in raw.split())
    return result


def owned_descendants(driver_pid, earliest_birth):
    result = {}; pending = [(driver_pid, child) for child in children(driver_pid)]
    while pending:
        parent, pid = pending.pop()
        if pid in result:
            continue
        try:
            item = process_record(pid)
        except (FileNotFoundError, ProcessLookupError):
            continue
        # Reparenting can move a proved descendant directly to this subreaper.
        h.require(item["uid"] == os.getuid() and item["start_ticks"] >= earliest_birth
                  and item["ppid"] in {parent, driver_pid}, "private descendant provenance changed")
        result[pid] = item
        pending.extend((pid, child) for child in children(pid))
        h.require(len(result) <= 128, "private helper-count bound exceeded")
    return result


def pidfd_open(pid):
    """Require the Linux x86_64 pidfd API even on an older Python build."""
    h.require(sys.platform == "linux" and os.uname().machine == "x86_64", "Linux x86_64 pidfd proof required")
    libc = ctypes.CDLL(None, use_errno=True)
    libc.syscall.restype = ctypes.c_long
    result = libc.syscall(ctypes.c_long(434), ctypes.c_int(pid), ctypes.c_uint(0))
    if result < 0:
        error = ctypes.get_errno()
        raise OSError(error, "pidfd_open unavailable/failed; no numeric-PID signal fallback")
    return int(result)


def pidfd_kill(fd):
    h.require(sys.platform == "linux" and os.uname().machine == "x86_64", "Linux x86_64 pidfd proof required")
    libc = ctypes.CDLL(None, use_errno=True)
    libc.syscall.restype = ctypes.c_long
    result = libc.syscall(ctypes.c_long(424), ctypes.c_int(fd), ctypes.c_int(signal.SIGKILL),
                          ctypes.c_void_p(), ctypes.c_uint(0))
    if result < 0:
        error = ctypes.get_errno()
        raise OSError(error, "pidfd_send_signal failed; no numeric-PID signal fallback")


def self_pidfd_probe():
    """Authorized execute-only API probe, signal0 on this driver's own pidfd."""
    fd = pidfd_open(os.getpid())
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        libc.syscall.restype = ctypes.c_long
        result = libc.syscall(ctypes.c_long(424), ctypes.c_int(fd), ctypes.c_int(0),
                              ctypes.c_void_p(), ctypes.c_uint(0))
        if result < 0:
            raise OSError(ctypes.get_errno(), "self pidfd signal0 unavailable; no child cases launched")
    finally:
        os.close(fd)
    return dict(status="PASS_AUTHORIZED_SELF_PIDFD_API_ONLY", target_pid=os.getpid(), signal=0,
                no_child_or_termination_signal=True)


def kill_proved(item, allowed_parents):
    """A pidfd plus a repeated lifetime/UID/ancestry check prevents PID reuse."""
    h.require(item["pid"] > 1, "never signal a non-private PID")
    fd = pidfd_open(item["pid"])
    try:
        current = process_record(item["pid"])
        h.require((current["pid"], current["start_ticks"], current["uid"])
                  == (item["pid"], item["start_ticks"], os.getuid())
                  and current["ppid"] in allowed_parents, "stale or non-owned signal target")
        pidfd_kill(fd)
    finally:
        os.close(fd)


def reap_all(events, direct):
    while True:
        try:
            pid, code, usage = os.wait4(-1, os.WNOHANG)
        except ChildProcessError:
            return
        if pid == 0:
            return
        value = dict(pid=pid, returncode=os.waitstatus_to_exitcode(code),
                     CPU_seconds=usage.ru_utime + usage.ru_stime)
        events.append(value)
        if pid == direct.pid:
            direct.returncode = value["returncode"]


def drain_private(events, direct, earliest_birth, *, seconds=3):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        items = owned_descendants(os.getpid(), earliest_birth)
        if not items:
            reap_all(events, direct)
            return not children(os.getpid())
        for item in reversed(list(items.values())):
            if item["state"] == "Z":
                continue
            try:
                kill_proved(item, set(items) | {os.getpid()})
            except (FileNotFoundError, ProcessLookupError):
                pass
        reap_all(events, direct); time.sleep(.01)
    reap_all(events, direct)
    return not children(os.getpid())


def run_case(row, run_dir, *, driver_birth):
    plan = h.read(row["plan"]); label = row["label"]
    expected = next(x for x in CASE_ROWS if x[0] == label)
    h.require(row["expectation"] == expected[2] and plan["case"] == expected[1]
              and plan["limits"] == dict(CPU=4, wall=expected[3], output_cap=1048576),
              "case identity/caps changed")
    h.require(not children(os.getpid()), "next case cannot overlap any private predecessor")
    argv = [plan["supervisor_python"]["path"], "-I", "-B", plan["sources"]["adapter"]["path"],
            "launch", "--plan", row["plan"]["path"], "--authority", row["authority"]["path"],
            "--review", row["review"]["path"], "--cpu", "4", "--wall", str(plan["limits"]["wall"])]
    stdout = run_dir / (label + ".guard.json"); stderr = run_dir / (label + ".stderr")
    events = []; action = None; begin = time.monotonic()
    with stdout.open("xb") as out, stderr.open("xb") as err:
        child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=out, stderr=err, close_fds=True)
        guardian = process_record(child.pid)
        h.require(guardian["ppid"] == os.getpid() and guardian["uid"] == os.getuid(), "new direct child ownership required")
        deadline = begin + plan["limits"]["wall"] + 4
        try:
            while time.monotonic() < deadline:
                if expected[2] in {"MONITOR_DEATH", "GUARDIAN_DEATH"} and action is None:
                    try:
                        monitors = children(child.pid)
                        if len(monitors) == 1:
                            monitor = process_record(next(iter(monitors)))
                            leaders = children(monitor["pid"])
                            helper_started = any(children(leader) for leader in leaders)
                            if leaders and helper_started:
                                target = monitor if expected[2] == "MONITOR_DEATH" else guardian
                                kill_proved(target, {child.pid} if expected[2] == "MONITOR_DEATH" else {os.getpid()})
                                action = dict(injected_owned_death=expected[2], target=target,
                                              monotonic=time.monotonic(), method="PIDFD_EXACT_UID_BIRTH_PRIVATE_PARENT")
                    except (FileNotFoundError, ProcessLookupError):
                        pass
                reap_all(events, child)
                if child.returncode is not None and not children(os.getpid()):
                    break
                time.sleep(.01)
            h.require(child.returncode is not None and not children(os.getpid()), "private kernel case did not finish/drain")
        finally:
            if children(os.getpid()):
                h.require(drain_private(events, child, driver_birth), "private cleanup could not prove complete drain")
        out.flush(); os.fsync(out.fileno()); err.flush(); os.fsync(err.fileno())
    raw = stdout.read_bytes(); guard = h.strict_json(raw) if raw else None
    result = dict(label=label, expectation=expected[2], actual_process_returncode=child.returncode,
                  guard=h.pin(stdout), stderr=h.pin(stderr), original_guard_result=guard,
                  all_private_descendants_reaped=True, reaped=events, injected_action=action,
                  complete_driver_case_wall_seconds=time.monotonic() - begin)
    if expected[2] == "SUCCESS":
        h.require(child.returncode == 0 and stderr.read_bytes() == b"", "positive helper command failed")
        proof = h.finalize(row["plan"], row["authority"], row["review"], h.pin(stdout))
        h.require(proof["status"] == "PASS_SYNTHETIC_OWNED_HELPER_CASE_NOT_R_STARTUP", "wrong positive proof role")
        result["actual_finalized_synthetic_proof"] = h.pin(Path(plan["output_dir"]) / "startup_proof.json")
    elif expected[2] in {"CPU_BOUNDARY", "WALL_BOUNDARY"}:
        reason = "AGGREGATE_CPU_BOUNDARY" if expected[2] == "CPU_BOUNDARY" else "WALL_BOUNDARY"
        h.require(child.returncode == 124 and guard["returncode"] == 124
                  and guard["cap_reason"] == reason and guard["all_owned_descendants_reaped"] is True,
                  "expected finite boundary and complete drain were not proved")
        h.require(guard["aggregate_CPU_seconds"] < 4 and len(guard["reaped"]) >= 2,
                  "failed boundary needs actual complete helper drain/accounting")
        if expected[2] == "CPU_BOUNDARY":
            startup = h.strict_json(guard["stdout"])
            h.require(startup["case"] == "cpu_boundary" and startup["inherited_CPU_limits"] == [4, 4]
                      and any(item["pid"] == startup["helper_pid"] and item["CPU_seconds"] > .1
                              for item in guard["reaped"]),
                      "actual burning-helper CPU and inherited hard limit were not proved")
    elif expected[2] == "MONITOR_DEATH":
        h.require(action is not None and child.returncode == 125 and guard["returncode"] == 125
                  and guard["all_owned_descendants_reaped"] is True, "outer guardian failed to drain a dead monitor")
    else:
        h.require(action is not None and child.returncode == -signal.SIGKILL and guard is None
                  and len(events) >= 2, "monitor did not independently drain after guardian loss")
    result["test_expectation_met"] = True
    # Deliberate guard failures remain failures; this is only a kernel test.
    result["is_R_startup_or_production_acceptance"] = False
    h.write_new(run_dir / (label + ".case.json"), result)
    return result


def execute(matrix_pin, authority_pin, review_pin):
    matrix, authority, review = h.read(matrix_pin), h.read(authority_pin), h.read(review_pin)
    h.require(matrix["schema"] == "pricefm_startup_helper_kernel_matrix_v1"
              and matrix["sources"] == sources(), "current kernel matrix source closure differs")
    h.require(review["status"] == "PASS_REVIEWED_STARTUP_HELPER_KERNEL_MATRIX"
              and review["matrix"] == matrix_pin and review["sources"] == sources(), "actual matrix source review required")
    h.require(authority["status"] == "ROOT_AUTHORIZED_ONESHOT_SYNTHETIC_HELPER_KERNEL_MATRIX"
              and authority["matrix"] == matrix_pin and authority["source_review"] == review_pin
              and authority["sources"] == sources() and type(authority["executions"]) is int
              and authority["executions"] == 1 and authority["CPU_reservation"] == 30
              and authority["driver_SELF_CPU_cap"] == 6 and authority["case_CPU_caps"] == [4] * 6,
              "fresh exact30CPU matrix authority required")
    now = time.time(); scope = h.read(authority["root_scope"])
    h.require(authority["issued_epoch"] <= now and now + 180 < authority["expires_epoch"] <= scope["expires_epoch"],
              "finite matrix lifetime must fit root authority")
    h.require(os.sched_getaffinity(0) == {31} and not children(os.getpid()), "private administrative driver only")
    prior = resource.getrusage(resource.RUSAGE_CHILDREN)
    h.require(prior.ru_utime == prior.ru_stime == 0,
              "fresh kernel driver cannot inherit unfunded waited-child CPU history")
    h.require(len(matrix["cases"]) == 6 and [x["label"] for x in matrix["cases"]] == [x[0] for x in CASE_ROWS],
              "complete ordered six-case matrix required")
    for row in matrix["cases"]:
        h.require(h.read(row["plan"])["role"] == "SYNTHETIC_OWNED_HELPER", "kernel matrix cannot run R or scientific payload")
        h.read(row["authority"]); h.read(row["review"])
    run_dir = h.physical(matrix["run_dir"])
    h.require(run_dir.parent == h.physical(authority["allowed_output_parent"]), "exact private run parent required")
    run_dir.mkdir(mode=0o700)
    h.write_new(run_dir / "EXECUTION_INTENT.json", dict(status="INTENT_NOT_SUCCESS", matrix=matrix_pin,
        authority=authority_pin, source_review=review_pin, sources=sources(), issued_epoch=now))
    driver = process_record(os.getpid()); rows = []; error = None; probe = None
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        h.require(libc.prctl(36, 1, 0, 0, 0) == 0 and libc.prctl(4, 0, 0, 0, 0) == 0,
                  "private driver subreaper/nondumpable unavailable")
        probe = self_pidfd_probe()
        for row in matrix["cases"]:
            rows.append(run_case(row, run_dir, driver_birth=driver["start_ticks"]))
    except BaseException as exc:
        error = type(exc).__name__ + ": " + str(exc)
    own, waited = resource.getrusage(resource.RUSAGE_SELF), resource.getrusage(resource.RUSAGE_CHILDREN)
    total = own.ru_utime + own.ru_stime + waited.ru_utime + waited.ru_stime
    okay = error is None and len(rows) == 6 and not children(os.getpid()) and total < 30
    result = dict(status="PASS_SYNTHETIC_HELPER_KERNEL_MATRIX_NOT_R" if okay else "FAILED_SYNTHETIC_HELPER_KERNEL_MATRIX",
        matrix=matrix_pin, authority=authority_pin, source_review=review_pin, case_results=rows, error=error,
        SELF_CPU_seconds=own.ru_utime + own.ru_stime, waited_CPU_seconds=waited.ru_utime + waited.ru_stime,
        aggregate_CPU_seconds_including_driver_and_waited_history=total, CPU_reservation_retained=30,
        all_private_descendants_reaped=not children(os.getpid()), R_startup_proved=False,
        authorized_self_pidfd_API_probe=probe,
        numerical_parity_proved=False, production_ready=False, automatic_retry=False,
        limits=["Exact synthetic source and single monitor/guardian loss only; no simultaneous loss of driver, guardian and monitor proof",
                "Actual R4.6 default-utils/popen fixture and full numerical/target bridge gates remain separate",
                "Deliberate CPU/wall/death guard failures remain failed guard receipts, not runtime successes"])
    h.write_new(run_dir / "KERNEL_MATRIX_RESULT.json", result)
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__); p.add_argument("action", choices=("prepare", "execute"))
    p.add_argument("--output"); p.add_argument("--python"); p.add_argument("--matrix")
    p.add_argument("--authority"); p.add_argument("--review"); a = p.parse_args()
    cap = 2 if a.action == "prepare" else 6
    resource.setrlimit(resource.RLIMIT_CPU, (cap, cap)); resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    signal.alarm(30 if a.action == "prepare" else 180)
    if a.action == "prepare":
        h.require(a.output is not None and a.python is not None, "preparation output/Python required")
        print(json.dumps(prepare(a.output, a.python), sort_keys=True))
    else:
        h.require(a.matrix and a.authority and a.review, "actual matrix/authority/review paths required")
        result = execute(h.pin(a.matrix), h.pin(a.authority), h.pin(a.review))
        print(json.dumps(dict(status=result["status"], matrix_result=str(Path(h.read(h.pin(a.matrix))["run_dir"]) / "KERNEL_MATRIX_RESULT.json"))))
        raise SystemExit(0 if result["status"].startswith("PASS_") else 1)


if __name__ == "__main__":
    main()
