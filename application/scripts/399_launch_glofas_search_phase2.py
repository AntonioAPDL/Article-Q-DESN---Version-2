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


def job_command(repo, root, job_id, rscript="Rscript"):
    q = shlex.quote
    return (
        "set -euo pipefail; "
        f"cd {q(str(repo))}; "
        "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 "
        "VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1; "
        f"{q(str(rscript))} application/scripts/396_run_glofas_search_phase2_worker.R --runtime_root {q(str(root))} --job_id {q(job_id)}; "
        f"{q(str(rscript))} application/scripts/397_score_glofas_search_phase2.R --runtime_root {q(str(root))} --job_id {q(job_id)}"
    )


def group_command(repo, root, design_group_id, rscript="Rscript"):
    q = shlex.quote
    return (
        "set -euo pipefail; "
        f"cd {q(str(repo))}; "
        "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 "
        "VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1; "
        f"{q(str(rscript))} application/scripts/401_run_glofas_search_phase2_rhs_group.R "
        f"--runtime_root {q(str(root))} --design_group_id {q(design_group_id)}"
    )


def build_units(jobs, group_rhs_design=False):
    units = []
    grouped = {}
    for row in jobs:
        group_id = row.get("design_group_id", "")
        if group_rhs_design and row.get("method") == "rhs" and group_id:
            grouped.setdefault(group_id, []).append(row)
        else:
            units.append({"unit_id": row["job_id"], "jobs": [row], "grouped": False})
    for group_id, rows in grouped.items():
        units.append({"unit_id": group_id, "jobs": rows, "grouped": True})
    for unit in units:
        unit["memory_weight"] = max(int(float(row.get("memory_weight", "1") or 1)) for row in unit["jobs"])
    return units


def unit_terminal(root, unit):
    return all(job_complete(root, row["job_id"]) or status_path(root, row["job_id"], ".failed").exists()
               for row in unit["jobs"])


def shell_join(parts):
    return " ".join(shlex.quote(str(part)) for part in parts)


def run_scheduler(repo, root, workers, capacity, poll, group_rhs_design=False, rscript="Rscript"):
    jobs = read_jobs(root)
    units = build_units(jobs, group_rhs_design=group_rhs_design)
    active = {}
    env = os.environ.copy()
    env.update(THREAD_ENV)
    scheduler_log = root / "logs" / "scheduler.log"
    with scheduler_log.open("a", buffering=1) as log:
        log.write(f"scheduler_start jobs={len(jobs)} units={len(units)} workers={workers} capacity={capacity} group_rhs_design={group_rhs_design}\n")
        while True:
            for unit_id, (proc, handle, _, unit) in list(active.items()):
                code = proc.poll()
                if code is None:
                    continue
                handle.close()
                log.write(f"unit_exit unit_id={unit_id} exit={code}\n")
                if code != 0:
                    for row in unit["jobs"]:
                        job_id = row["job_id"]
                        if not job_complete(root, job_id) and not status_path(root, job_id, ".failed").exists():
                            status_path(root, job_id, ".failed").write_text(f"scheduler_observed_exit={code}\n")
                        unlink_if_exists(status_path(root, job_id, ".running"))
                active.pop(unit_id)
            pending = [unit for unit in units if not unit_terminal(root, unit) and unit["unit_id"] not in active]
            used = sum(item[2] for item in active.values())
            for unit in pending:
                weight = unit["memory_weight"]
                if len(active) >= workers or used + weight > capacity:
                    continue
                unit_id = unit["unit_id"]
                log_path = root / "logs" / f"{unit_id}.log"
                handle = log_path.open("a")
                command = (group_command(repo, root, unit_id, rscript) if unit["grouped"]
                           else job_command(repo, root, unit_id, rscript))
                proc = subprocess.Popen(["bash", "-lc", command], stdout=handle, stderr=subprocess.STDOUT, env=env)
                active[unit_id] = (proc, handle, weight, unit)
                used += weight
                log.write(f"unit_start unit_id={unit_id} jobs={len(unit['jobs'])} pid={proc.pid} weight={weight}\n")
            done = sum(job_complete(root, row["job_id"]) for row in jobs)
            failed = sum(status_path(root, row["job_id"], ".failed").exists() for row in jobs)
            active_jobs = sum(len(item[3]["jobs"]) for item in active.values())
            pending_jobs = len(jobs) - done - failed - active_jobs
            log.write(
                f"health done={done} active_units={len(active)} active_jobs={active_jobs} "
                f"failed={failed} pending_jobs={pending_jobs}\n"
            )
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
    parser.add_argument("--rscript", default="Rscript",
                        help="Exact Rscript executable used by every worker")
    parser.add_argument("--group-rhs-design", action="store_true",
                        help="Run RHS jobs sharing an architecture/fold sequentially with one rebuilt design")
    parser.add_argument("--scheduler", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    root = Path(args.runtime_root).resolve()
    rscript = shutil_which(args.rscript)
    if rscript is None:
        raise RuntimeError(f"Rscript executable is unavailable: {args.rscript}")
    jobs = read_jobs(root)
    units = build_units(jobs, group_rhs_design=args.group_rhs_design)
    if args.dry_run:
        total_weight = sum(unit["memory_weight"] for unit in units)
        print(
            f"jobs={len(jobs)} units={len(units)} total_weight={total_weight} "
            f"workers={args.workers} capacity={args.capacity} rscript={rscript}"
        )
        return 0
    if args.scheduler:
        return run_scheduler(repo, root, args.workers, args.capacity, max(2, args.poll_seconds),
                             group_rhs_design=args.group_rhs_design, rscript=rscript)
    if not shutil_which("tmux"):
        raise RuntimeError("tmux is required for detached Search-II launch")
    session = args.session_label or f"{root.name}_scheduler"
    command = [sys.executable, str(Path(__file__).resolve()), "--runtime-root", str(root),
               "--workers", str(args.workers), "--capacity", str(args.capacity),
               "--poll-seconds", str(args.poll_seconds), "--rscript", rscript, "--scheduler"]
    if args.group_rhs_design:
        command.append("--group-rhs-design")
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
