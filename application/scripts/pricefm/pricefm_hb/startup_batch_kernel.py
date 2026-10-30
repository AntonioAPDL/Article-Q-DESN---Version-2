"""NEW compute-host qualification of six owned synthetic helper mechanisms.

This is not a retry/relabel of the failed Muscat administrative matrix. It
uses the fresh Q job/READY/release, actual allocated CPU and unchanged guard,
borrowing only the frozen driver's low-level pidfd/ancestry/drain functions.
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


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("--context", required=True)
    parser.add_argument("--sha256", required=True); args = parser.parse_args()
    resource.setrlimit(resource.RLIMIT_CPU, (6, 6)); resource.setrlimit(resource.RLIMIT_CORE, (0, 0)); signal.alarm(180)
    sys.path.insert(0, str(Path(__file__).absolute().parents[1]))
    from pricefm_hb import startup_batch_worker as w
    context = json.loads(w.read_exact(dict(path=args.context, sha256=args.sha256)))
    spec, scope, h, k, job = w.bootstrap(context["spec"])
    h.require(spec["role"] == "COMPUTE_RUNTIME_INVENTORY", "fresh Q compute kernel role required")
    release = w.validate_release(spec, context["spec"], context["ready"], context["release"])
    h.require(release["kernel_matrix_CPU_reservation"] == 30 and release["kernel_case_caps"] == [4] * 6
              and release["kernel_driver_SELF_cap"] == 6, "source-context30CPU kernel grant required")
    prior = resource.getrusage(resource.RUSAGE_CHILDREN)
    h.require(prior.ru_utime == prior.ru_stime == 0 and not k.children(os.getpid()), "fresh private compute driver required")
    root = Path(spec["remote_root"]) / "result/kernel"; root.mkdir(mode=0o700)
    h.write_new(root / "EXECUTION_INTENT.json", dict(status="NEW_Q_COMPUTE_KERNEL_INTENT_NOT_PASS",
        context=dict(path=args.context, sha256=args.sha256), job_id=job, node=spec["node"],
        scope=spec["scope"], old_Muscat_scope_reopened=False, sources=spec["sources"]))
    rows = []; error = None; probe = None; driver = k.process_record(os.getpid())
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        h.require(libc.prctl(36, 1, 0, 0, 0) == 0 and libc.prctl(4, 0, 0, 0, 0) == 0,
                  "private compute subreaper/nondumpable unavailable")
        probe = k.self_pidfd_probe()
        ready = json.loads(w.read_exact(context["ready"]))
        for label, case, expected, wall in k.CASE_ROWS:
            h.require(not k.children(os.getpid()), "compute cases cannot overlap")
            nonce = __import__("hashlib").sha256((spec["scope_id"] + "/" + label).encode()).hexdigest()[:32]
            command = [ready["inventory"]["python"]["path"], "-I", "-B", spec["sources"]["profile_supervisor.py"]["path"],
                "--cpu", "4", "--wall", str(wall), "--output-cap", "1048576", "--",
                ready["inventory"]["python"]["path"], "-I", "-B", spec["sources"]["startup_helper_fixture.py"]["path"],
                "--case", case, "--nonce", nonce]
            stdout = root / (label + ".guard.json"); stderr = root / (label + ".stderr")
            events = []; action = None; begin = time.monotonic()
            with stdout.open("xb") as out, stderr.open("xb") as err:
                child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=out, stderr=err, close_fds=True, preexec_fn=lambda: None)
                identity = k.process_record(child.pid)
                h.require(identity["ppid"] == os.getpid() and identity["uid"] == os.getuid(), "private direct guardian required")
                try:
                    while time.monotonic() - begin < wall + 4:
                        if expected in {"MONITOR_DEATH", "GUARDIAN_DEATH"} and action is None:
                            try:
                                monitors = k.children(child.pid)
                                if len(monitors) == 1:
                                    monitor = k.process_record(next(iter(monitors)))
                                    leaders = k.children(monitor["pid"])
                                    if any(k.children(leader) for leader in leaders):
                                        target = monitor if expected == "MONITOR_DEATH" else identity
                                        k.kill_proved(target, {child.pid} if expected == "MONITOR_DEATH" else {os.getpid()})
                                        action = dict(kind=expected, exact_owned_target=target, signal_method="PIDFD_UID_BIRTH_PRIVATE_PARENT")
                            except (FileNotFoundError, ProcessLookupError):
                                pass
                        k.reap_all(events, child)
                        if child.returncode is not None and not k.children(os.getpid()): break
                        time.sleep(.01)
                    h.require(child.returncode is not None and not k.children(os.getpid()), "compute case did not finish/drain")
                finally:
                    if k.children(os.getpid()):
                        h.require(k.drain_private(events, child, driver["start_ticks"]), "compute private cleanup incomplete")
                out.flush(); os.fsync(out.fileno()); err.flush(); os.fsync(err.fileno())
            raw = stdout.read_bytes(); guard = h.strict_json(raw) if raw else None
            if expected == "SUCCESS":
                h.require(child.returncode == 0 and guard["returncode"] == guard["command_returncode"] == 0
                    and guard["cap_reason"] is None and guard["CPU_limit"] == 4
                    and guard["aggregate_CPU_seconds"] < 4 and guard["complete_lifecycle_wall_seconds"] <= wall
                    and all(guard.get(x) is True for x in ("all_owned_descendants_reaped", "kernel_escape_filter",
                        "orphan_subreaper", "independent_guardian", "guardian_included_in_CPU"))
                    and guard["stderr"] == "", "actual positive compute helper guard must pass")
                fixture = h.strict_json(guard["stdout"])
                h.require(fixture["status"] == "PASS_SYNTHETIC_OWNED_HELPER_FIXTURE" and fixture["nonce"] == nonce
                    and fixture["case"] == case and fixture["models"] == fixture["optimizer_invocations"] == 0
                    and fixture["scientific_data_read"] is False, "actual source-bound synthetic handshake differs")
                if case == "wait_and_escape":
                    h.require(fixture["helper_wait_status"] == 0 and fixture["escape_operations_denied"] == 3
                        and fixture["deliberate_nonzero_helper_status_observed"] == 7, "wait/escape/helper-status proof failed")
                else:
                    h.require(len(guard["reaped"]) >= 2 and fixture["intentionally_unwaited_private_helper"] is True
                        and all(x["returncode"] == 0 for x in guard["reaped"]), "actual orphan adoption/reap proof failed")
            elif expected in {"CPU_BOUNDARY", "WALL_BOUNDARY"}:
                reason = "AGGREGATE_CPU_BOUNDARY" if expected == "CPU_BOUNDARY" else "WALL_BOUNDARY"
                h.require(child.returncode == 124 and guard["returncode"] == 124 and guard["cap_reason"] == reason
                    and guard["all_owned_descendants_reaped"] is True and guard["aggregate_CPU_seconds"] < 4
                    and len(guard["reaped"]) >= 2, "exact finite negative boundary/drain proof failed")
                if expected == "CPU_BOUNDARY":
                    startup = h.strict_json(guard["stdout"])
                    h.require(startup["inherited_CPU_limits"] == [4, 4] and any(x["pid"] == startup["helper_pid"]
                        and x["CPU_seconds"] > .1 for x in guard["reaped"]), "burning-helper accounting/inherited-limit proof failed")
            elif expected == "MONITOR_DEATH":
                h.require(action is not None and child.returncode == 125 and guard["returncode"] == 125
                    and guard["all_owned_descendants_reaped"] is True, "guardian failed to drain after monitor death")
            else:
                h.require(action is not None and child.returncode == -signal.SIGKILL and guard is None and len(events) >= 2,
                    "monitor failed to drain after guardian death")
            row = dict(label=label, expected=expected, guard=pin_dict(stdout), stderr=pin_dict(stderr),
                actual_guard_returncode=None if guard is None else guard["returncode"], actual_process_returncode=child.returncode,
                injection=action, reaped=events, all_private_descendants_reaped=True, test_expectation_met=True,
                deliberate_guard_failures_remain_failed=True, R_startup_proved=False)
            h.write_new(root / (label + ".case.json"), row); rows.append(row)
    except BaseException as exc:
        error = type(exc).__name__ + ": " + str(exc)
    own, waited = resource.getrusage(resource.RUSAGE_SELF), resource.getrusage(resource.RUSAGE_CHILDREN)
    total = own.ru_utime + own.ru_stime + waited.ru_utime + waited.ru_stime
    okay = error is None and len(rows) == 6 and not k.children(os.getpid()) and total < 30
    result = dict(status="PASS_COMPUTE_OWNED_HELPER_KERNEL_MATRIX_NOT_R" if okay else "FAILED_COMPUTE_OWNED_HELPER_KERNEL_MATRIX",
        job_id=job, node=spec["node"], context=dict(path=args.context, sha256=args.sha256),
        actual_self_pidfd_probe=probe, case_results=rows, error=error, all_private_descendants_reaped=not k.children(os.getpid()),
        SELF_CPU_seconds=own.ru_utime + own.ru_stime, waited_CPU_seconds=waited.ru_utime + waited.ru_stime,
        aggregate_CPU_seconds=total, retained_component_CPU=30, old_Muscat_failed_attempt_unchanged=True,
        R_startup_proved=False, numerical_parity_proved=False, production_ready=False,
        no_simultaneous_driver_guardian_monitor_loss_claim=True)
    h.write_new(root / "KERNEL_MATRIX_RESULT.json", result)
    raise SystemExit(0 if okay else 1)


def pin_dict(path):
    return dict(path=str(path), sha256=__import__("hashlib").sha256(Path(path).read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
