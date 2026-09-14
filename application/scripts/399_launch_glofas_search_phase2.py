#!/usr/bin/env python3
"""Capacity-aware Search Phase II scheduler with one thread per model."""

import argparse
import csv
import os
from pathlib import Path
import shlex
import subprocess
import sys
import time


THREAD_ENV = {
    "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
    "VECLIB_MAXIMUM_THREADS": "1", "NUMEXPR_NUM_THREADS": "1",
}


def read_jobs(root):
    with (root / "configs" / "job_manifest.csv").open(newline="") as handle:
        jobs = list(csv.DictReader(handle))
    if not jobs or len({row["job_id"] for row in jobs}) != len(jobs):
        raise RuntimeError("Search-II manifest must contain unique jobs")
    return jobs


def status_path(root, job_id, suffix):
    return root / "status" / f"{job_id}{suffix}"


def job_complete(root, job_id):
    return status_path(root, job_id, ".done").exists()


def unlink_if_exists(path):
    if path.exists():
        path.unlink()


def job_command(repo, root, job_id):
    q = shlex.quote
    return (
        "set -euo pipefail; "
        f"cd {q(str(repo))}; "
        "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 "
        "VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1; "
        f"Rscript application/scripts/396_run_glofas_search_phase2_worker.R --runtime_root {q(str(root))} --job_id {q(job_id)}; "
        f"Rscript application/scripts/397_score_glofas_search_phase2.R --runtime_root {q(str(root))} --job_id {q(job_id)}"
    )


def shell_join(parts):
    return " ".join(shlex.quote(str(part)) for part in parts)


def run_scheduler(repo, root, workers, capacity, poll):
    jobs = read_jobs(root)
    active = {}
    env = os.environ.copy()
    env.update(THREAD_ENV)
    scheduler_log = root / "logs" / "scheduler.log"
    with scheduler_log.open("a", buffering=1) as log:
        log.write(f"scheduler_start jobs={len(jobs)} workers={workers} capacity={capacity}\n")
        while True:
            for job_id, (proc, handle, _) in list(active.items()):
                code = proc.poll()
                if code is None:
                    continue
                handle.close()
                log.write(f"job_exit job_id={job_id} exit={code}\n")
                if code != 0 and not job_complete(root, job_id) and not status_path(root, job_id, ".failed").exists():
                    status_path(root, job_id, ".failed").write_text(f"scheduler_observed_exit={code}\n")
                unlink_if_exists(status_path(root, job_id, ".running"))
                active.pop(job_id)
            pending = [row for row in jobs if not job_complete(root, row["job_id"])
                       and row["job_id"] not in active and not status_path(root, row["job_id"], ".failed").exists()]
            used = sum(weight for _, _, weight in active.values())
            for row in pending:
                weight = int(float(row.get("memory_weight", "1") or 1))
                if len(active) >= workers or used + weight > capacity:
                    continue
                job_id = row["job_id"]
                log_path = root / "logs" / f"{job_id}.log"
                handle = log_path.open("a")
                proc = subprocess.Popen(["bash", "-lc", job_command(repo, root, job_id)], stdout=handle, stderr=subprocess.STDOUT, env=env)
                active[job_id] = (proc, handle, weight)
                used += weight
                log.write(f"job_start job_id={job_id} pid={proc.pid} weight={weight}\n")
            done = sum(job_complete(root, row["job_id"]) for row in jobs)
            failed = sum(status_path(root, row["job_id"], ".failed").exists() for row in jobs)
            log.write(f"health done={done} active={len(active)} failed={failed} pending={len(jobs)-done-len(active)-failed}\n")
            if not active and done + failed == len(jobs):
                break
            time.sleep(poll)
    return 0 if failed == 0 else 2


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--workers", type=int, default=20)
    parser.add_argument("--capacity", type=int, default=20, help="Weighted memory slots")
    parser.add_argument("--poll-seconds", type=int, default=15)
    parser.add_argument("--session-label", default="")
    parser.add_argument("--scheduler", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    root = Path(args.runtime_root).resolve()
    jobs = read_jobs(root)
    if args.dry_run:
        total_weight = sum(int(float(row.get("memory_weight", "1") or 1)) for row in jobs)
        print(f"jobs={len(jobs)} total_weight={total_weight} workers={args.workers} capacity={args.capacity}")
        return 0
    if args.scheduler:
        return run_scheduler(repo, root, args.workers, args.capacity, max(2, args.poll_seconds))
    if not shutil_which("tmux"):
        raise RuntimeError("tmux is required for detached Search-II launch")
    session = args.session_label or f"{root.name}_scheduler"
    command = [sys.executable, str(Path(__file__).resolve()), "--runtime-root", str(root),
               "--workers", str(args.workers), "--capacity", str(args.capacity),
               "--poll-seconds", str(args.poll_seconds), "--scheduler"]
    subprocess.run(["tmux", "new-session", "-d", "-s", session, shell_join(command)], check=True)
    print(f"session={session}\nruntime_root={root}\njobs={len(jobs)}")
    return 0


def shutil_which(command):
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = Path(directory) / command
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


if __name__ == "__main__":
    raise SystemExit(main())
