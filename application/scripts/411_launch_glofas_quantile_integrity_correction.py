#!/usr/bin/env python3.11
"""Dependency-aware launcher for the minimal GloFAS quantile correction DAG."""

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
    for value in ("failed", "completed", "running"):
        if (root / "status" / f"{job_id}.{value}").exists():
            return value
    return "pending"


def health(root: Path, jobs: list[dict[str, object]], active: dict[str, subprocess.Popen]) -> dict[str, object]:
    states = {job["job_id"]: state(root, str(job["job_id"])) for job in jobs}
    counts = {key: sum(value == key for value in states.values()) for key in ("completed", "running", "failed", "pending")}
    payload = {
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "total": len(jobs), **counts, "left": len(jobs) - counts["completed"],
        "active_pids": {job_id: proc.pid for job_id, proc in active.items()},
        "states": states,
    }
    (root / "status/scheduler_health.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    return payload


def verify_contract(repo: Path, root: Path) -> tuple[list[dict[str, object]], dict[str, object]]:
    manifest_path = root / "configs/correction_job_manifest.json"
    contract_path = root / "configs/correction_contract.json"
    jobs = json.loads(manifest_path.read_text())
    contract = json.loads(contract_path.read_text())
    if sha256(manifest_path) != contract["manifest_sha256"]:
        raise RuntimeError("Correction manifest hash does not match the frozen contract")
    for relative, expected in contract["source_hashes"].items():
        observed = sha256(repo / relative)
        if observed != expected:
            raise RuntimeError(f"Source hash mismatch for {relative}: {observed} != {expected}")
    if len(jobs) != 38 or sum(job["action"] == "fit" for job in jobs) != 19:
        raise RuntimeError("Correction manifest does not contain the required 19 fits and 19 forecasts")
    return jobs, contract


def run_scheduler(repo: Path, root: Path, workers: int, poll_seconds: int) -> int:
    jobs, _ = verify_contract(repo, root)
    active: dict[str, subprocess.Popen] = {}
    logs: dict[str, object] = {}
    env = os.environ.copy()
    env.update({key: "1" for key in (
        "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS",
    )})
    (root / "status/scheduler.started").write_text(datetime.now(timezone.utc).isoformat() + "\n")
    try:
        while True:
            for job_id, proc in list(active.items()):
                rc = proc.poll()
                if rc is None:
                    continue
                logs.pop(job_id).close()
                active.pop(job_id)
                if rc != 0 or state(root, job_id) != "completed":
                    marker = root / "status" / f"{job_id}.failed"
                    if not marker.exists():
                        marker.write_text(f"scheduler_exit_code={rc}\n")

            snapshot = health(root, jobs, active)
            if snapshot["failed"]:
                (root / "status/scheduler.failed").write_text(json.dumps(snapshot, indent=2) + "\n")
                return 1
            if snapshot["completed"] == len(jobs):
                (root / "status/scheduler.completed").write_text(datetime.now(timezone.utc).isoformat() + "\n")
                return 0

            states = snapshot["states"]
            ready = [job for job in jobs if states[job["job_id"]] == "pending" and
                     all(states.get(dep) == "completed" for dep in job["dependencies"])]
            while ready and len(active) < workers:
                job = ready.pop(0)
                job_id = str(job["job_id"])
                log_handle = (root / "logs" / f"{job_id}.log").open("a")
                proc = subprocess.Popen(
                    [str(job["script_path"])], cwd=repo, env=env,
                    stdout=log_handle, stderr=subprocess.STDOUT,
                )
                active[job_id] = proc
                logs[job_id] = log_handle

            if not active and not ready:
                blocked = [job["job_id"] for job in jobs if states[job["job_id"]] == "pending"]
                (root / "status/scheduler.failed").write_text(f"dependency_deadlock={blocked}\n")
                return 2
            time.sleep(poll_seconds)
    finally:
        for handle in logs.values():
            handle.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--workers", type=int, default=30)
    parser.add_argument("--poll-seconds", type=int, default=20)
    parser.add_argument("--session-label", default="glofas_quantile_integrity_correction_20260920")
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    root = (repo / args.runtime_root).resolve() if not Path(args.runtime_root).is_absolute() else Path(args.runtime_root).resolve()
    if args.workers < 1 or args.workers > 30:
        raise SystemExit("The correction contract permits 1-30 one-thread workers")
    _, contract = verify_contract(repo, root)
    if args.workers != int(contract["workers"]):
        raise SystemExit(
            f"Worker count {args.workers} does not match frozen contract {contract['workers']}"
        )
    if not args.run:
        existing = subprocess.run(["tmux", "has-session", "-t", args.session_label], capture_output=True).returncode == 0
        if existing:
            raise SystemExit(f"tmux session already exists: {args.session_label}")
        command = [sys.executable, str(Path(__file__).resolve()), "--runtime-root", str(root),
                   "--workers", str(args.workers), "--poll-seconds", str(args.poll_seconds),
                   "--session-label", args.session_label, "--run"]
        subprocess.check_call(["tmux", "new-session", "-d", "-s", args.session_label, shlex.join(command)])
        print(json.dumps({"session": args.session_label, "runtime_root": str(root), "workers": args.workers}, indent=2))
        return
    raise SystemExit(run_scheduler(repo, root, args.workers, args.poll_seconds))


if __name__ == "__main__":
    main()
