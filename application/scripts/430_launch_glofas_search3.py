#!/usr/bin/env python3
"""Capacity-aware one-thread scheduler for one Search III stage."""

from __future__ import annotations

import argparse
import csv
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import time


THREAD_ENV = {
    "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
    "VECLIB_MAXIMUM_THREADS": "1", "NUMEXPR_NUM_THREADS": "1",
}


def read_jobs(root: Path):
    with (root / "configs" / "job_manifest.csv").open(newline="") as handle:
        jobs = list(csv.DictReader(handle))
    if not jobs or len({row["job_id"] for row in jobs}) != len(jobs):
        raise RuntimeError("Search III stage manifest must contain unique jobs")
    return jobs


def status(root: Path, job_id: str, suffix: str) -> Path:
    return root / "status" / f"{job_id}{suffix}"


def command(repo: Path, root: Path, job_id: str, rscript: str) -> str:
    q = shlex.quote
    return (
        "set -euo pipefail; "
        f"cd {q(str(repo))}; "
        "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 "
        "VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1; "
        f"{q(rscript)} application/scripts/428_run_glofas_search3_worker.R "
        f"--runtime_root {q(str(root))} --job_id {q(job_id)}; "
        f"{q(rscript)} application/scripts/429_score_glofas_search3.R "
        f"--runtime_root {q(str(root))} --job_id {q(job_id)}"
    )


def run_scheduler(repo: Path, root: Path, workers: int, capacity: int, poll: int, rscript: str) -> int:
    jobs = read_jobs(root)
    active = {}
    env = os.environ.copy(); env.update(THREAD_ENV)
    with (root / "logs" / "scheduler.log").open("a", buffering=1) as log:
        log.write(f"scheduler_start jobs={len(jobs)} workers={workers} capacity={capacity}\n")
        while True:
            for job_id, (proc, handle, weight) in list(active.items()):
                code = proc.poll()
                if code is None:
                    continue
                handle.close(); active.pop(job_id)
                log.write(f"job_exit job_id={job_id} exit={code}\n")
                if code and not status(root, job_id, ".done").exists():
                    status(root, job_id, ".failed").write_text(f"scheduler_observed_exit={code}\n")
                    status(root, job_id, ".running").unlink(missing_ok=True)
            done = {row["job_id"] for row in jobs if status(root, row["job_id"], ".done").exists()}
            failed = {row["job_id"] for row in jobs if status(root, row["job_id"], ".failed").exists()}
            used = sum(item[2] for item in active.values())
            for row in jobs:
                job_id = row["job_id"]
                if job_id in done or job_id in failed or job_id in active:
                    continue
                weight = int(float(row.get("memory_weight", "1") or 1))
                if len(active) >= workers or used + weight > capacity:
                    continue
                handle = (root / "logs" / f"{job_id}.log").open("a")
                proc = subprocess.Popen(["bash", "-lc", command(repo, root, job_id, rscript)], stdout=handle, stderr=subprocess.STDOUT, env=env)
                active[job_id] = (proc, handle, weight); used += weight
                log.write(f"job_start job_id={job_id} pid={proc.pid} weight={weight}\n")
            pending = len(jobs) - len(done) - len(failed) - len(active)
            log.write(f"health done={len(done)} running={len(active)} failed={len(failed)} pending={pending}\n")
            if not active and len(done) + len(failed) == len(jobs):
                return 0 if not failed else 2
            time.sleep(max(2, poll))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--workers", type=int, default=20)
    parser.add_argument("--capacity", type=int, default=28)
    parser.add_argument("--poll-seconds", type=int, default=15)
    parser.add_argument("--session-label", default="")
    parser.add_argument("--rscript", default="Rscript")
    parser.add_argument("--scheduler", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    root = Path(args.runtime_root).resolve()
    rscript = shutil.which(args.rscript)
    if rscript is None:
        raise RuntimeError(f"Rscript executable is unavailable: {args.rscript}")
    jobs = read_jobs(root)
    if args.dry_run:
        print(f"jobs={len(jobs)} workers={args.workers} capacity={args.capacity} rscript={rscript}")
        return 0
    if args.scheduler:
        return run_scheduler(repo, root, args.workers, args.capacity, args.poll_seconds, rscript)
    if shutil.which("tmux") is None:
        raise RuntimeError("tmux is required for detached Search III launch")
    session = args.session_label or f"{root.name}_scheduler"
    cmd = [sys.executable, str(Path(__file__).resolve()), "--runtime-root", str(root),
           "--workers", str(args.workers), "--capacity", str(args.capacity),
           "--poll-seconds", str(args.poll_seconds), "--rscript", rscript, "--scheduler"]
    subprocess.run(["tmux", "new-session", "-d", "-s", session, shlex.join(cmd)], check=True)
    print(f"session={session}\nruntime_root={root}\njobs={len(jobs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
