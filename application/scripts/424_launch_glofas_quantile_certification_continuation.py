#!/usr/bin/env python3.11
"""Dependency-gated launcher for exact GloFAS certification continuations."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def state(root: Path, job_id: str) -> str:
    for value in ("failed", "completed", "blocked", "running"):
        if (root / "status" / f"{job_id}.{value}").exists():
            return value
    return "pending"


def certified(root: Path, job_id: str) -> bool:
    return (root / "status" / f"{job_id}.certified").is_file()


def verify_contract(repo: Path, root: Path) -> tuple[list[dict[str, object]], dict[str, object]]:
    manifest_path = root / "configs/certification_continuation_job_manifest.json"
    contract_path = root / "configs/certification_continuation_contract.json"
    jobs = json.loads(manifest_path.read_text())
    contract = json.loads(contract_path.read_text())
    if sha256(manifest_path) != contract["manifest_sha256"]:
        raise RuntimeError("Continuation manifest hash does not match the frozen contract")
    for relative, expected in contract["source_hashes"].items():
        observed = sha256(repo / relative)
        if observed != expected:
            raise RuntimeError(f"Source hash mismatch for {relative}: {observed} != {expected}")
    fit_jobs = sum(job["action"] == "fit" for job in jobs)
    forecast_jobs = sum(job["action"] == "forecast" for job in jobs)
    if fit_jobs != int(contract["fit_jobs"]) or forecast_jobs != int(contract["forecast_jobs"]):
        raise RuntimeError("Continuation manifest job counts do not match the contract")
    if len(jobs) != fit_jobs + forecast_jobs or fit_jobs < 1:
        raise RuntimeError("Continuation manifest has an invalid job topology")
    return jobs, contract


def health(root: Path, jobs: list[dict[str, object]], active: dict[str, subprocess.Popen]) -> dict[str, object]:
    states = {str(job["job_id"]): state(root, str(job["job_id"])) for job in jobs}
    counts = {
        key: sum(value == key for value in states.values())
        for key in ("completed", "running", "failed", "blocked", "pending")
    }
    fit_jobs = [job for job in jobs if job["action"] == "fit"]
    payload = {
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "total": len(jobs), **counts,
        "left": counts["running"] + counts["pending"],
        "fit_completed": sum(states[str(job["job_id"])] == "completed" for job in fit_jobs),
        "fit_certified": sum(certified(root, str(job["job_id"])) for job in fit_jobs),
        "active_pids": {job_id: process.pid for job_id, process in active.items()},
        "states": states,
    }
    (root / "status/scheduler_health.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    return payload


def run_scheduler(repo: Path, root: Path, workers: int, poll_seconds: int) -> int:
    jobs, _ = verify_contract(repo, root)
    active: dict[str, subprocess.Popen] = {}
    log_handles: dict[str, object] = {}
    env = os.environ.copy()
    env.update({key: "1" for key in (
        "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS",
    )})
    (root / "status/scheduler.started").write_text(datetime.now(timezone.utc).isoformat() + "\n")
    try:
        while True:
            for job_id, process in list(active.items()):
                return_code = process.poll()
                if return_code is None:
                    continue
                log_handles.pop(job_id).close()
                active.pop(job_id)
                if return_code != 0 or state(root, job_id) != "completed":
                    marker = root / "status" / f"{job_id}.failed"
                    if not marker.exists():
                        marker.write_text(f"scheduler_exit_code={return_code}\n")

            snapshot = health(root, jobs, active)
            if snapshot["failed"]:
                (root / "status/scheduler.failed").write_text(json.dumps(snapshot, indent=2) + "\n")
                return 1

            states = snapshot["states"]
            for job in jobs:
                if job["action"] != "forecast" or states[str(job["job_id"])] != "pending":
                    continue
                required = [str(value) for value in job.get("required_certified_dependencies", [])]
                if required and all(states.get(dep) == "completed" for dep in required) and not all(certified(root, dep) for dep in required):
                    (root / "status" / f"{job['job_id']}.blocked").write_text(
                        "blocked_reason=source_fit_completed_without_terminal_certificate\n"
                    )

            snapshot = health(root, jobs, active)
            if snapshot["completed"] + snapshot["blocked"] == len(jobs):
                marker = "scheduler.completed" if snapshot["blocked"] == 0 else "scheduler.complete_with_uncertified"
                (root / "status" / marker).write_text(json.dumps(snapshot, indent=2) + "\n")
                return 0

            states = snapshot["states"]
            ready: list[dict[str, object]] = []
            for job in jobs:
                job_id = str(job["job_id"])
                if states[job_id] != "pending":
                    continue
                dependencies = [str(value) for value in job.get("dependencies", [])]
                required = [str(value) for value in job.get("required_certified_dependencies", [])]
                if all(states.get(dep) == "completed" for dep in dependencies) and all(certified(root, dep) for dep in required):
                    ready.append(job)
            while ready and len(active) < workers:
                job = ready.pop(0)
                job_id = str(job["job_id"])
                handle = (root / "logs" / f"{job_id}.log").open("a")
                process = subprocess.Popen(
                    [str(job["script_path"])], cwd=repo, env=env,
                    stdout=handle, stderr=subprocess.STDOUT,
                )
                active[job_id] = process
                log_handles[job_id] = handle

            if not active and not ready:
                snapshot = health(root, jobs, active)
                pending = [job_id for job_id, value in snapshot["states"].items() if value == "pending"]
                if pending:
                    (root / "status/scheduler.failed").write_text(f"dependency_deadlock={pending}\n")
                    return 2
            time.sleep(poll_seconds)
    finally:
        for handle in log_handles.values():
            handle.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--workers", type=int, required=True)
    parser.add_argument("--poll-seconds", type=int, default=20)
    parser.add_argument("--session-label", default="glofas_quantile_certification_continuation_20260922")
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    root = Path(args.runtime_root).resolve() if Path(args.runtime_root).is_absolute() else (repo / args.runtime_root).resolve()
    _, contract = verify_contract(repo, root)
    if args.workers != int(contract["workers"]):
        raise SystemExit(f"Worker count {args.workers} does not match frozen contract {contract['workers']}")
    if not args.run:
        exists = subprocess.run(["tmux", "has-session", "-t", args.session_label], capture_output=True).returncode == 0
        if exists:
            raise SystemExit(f"tmux session already exists: {args.session_label}")
        command = [
            sys.executable, str(Path(__file__).resolve()), "--runtime-root", str(root),
            "--workers", str(args.workers), "--poll-seconds", str(args.poll_seconds),
            "--session-label", args.session_label, "--run",
        ]
        subprocess.check_call(["tmux", "new-session", "-d", "-s", args.session_label, shlex.join(command)])
        print(json.dumps({"session": args.session_label, "runtime_root": str(root), "workers": args.workers}, indent=2))
        return
    raise SystemExit(run_scheduler(repo, root, args.workers, args.poll_seconds))


if __name__ == "__main__":
    main()
