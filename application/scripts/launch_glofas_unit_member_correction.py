#!/usr/bin/env python3
"""Freeze, preflight or execute the isolated 18-fit unit-member correction.

Each job occupies one assigned CPU; MQ inner parallelism is frozen to one.
No refitting happens without --execute after a clean, committed source freeze.
"""
from __future__ import annotations

import argparse
import csv
import fcntl
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import time

REPO = Path(__file__).resolve().parents[2]
RSCRIPT = "/data/jaguir26/local/opt/R/4.6.0/bin/Rscript"
THREAD_ENV = {key: "1" for key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS",
    "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS")}
CPU_POOL = tuple(range(48, 56))


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=REPO, text=True).strip()


def dependencies(job: dict[str, str]) -> list[str]:
    return [x for x in job["dependencies"].split("|") if x]


def validate_jobs(jobs: list[dict[str, str]]) -> None:
    ids = [x["run_id"] for x in jobs]
    if len(ids) != 18 or len(set(ids)) != 18:
        raise ValueError("Expected exactly 18 unique frozen fit units")
    allowed = set(ids)
    for job in jobs:
        if not re.fullmatch(r"[A-Za-z0-9_-]+", job["run_id"]):
            raise ValueError("Unsafe job identifier")
        if int(job["worker_slots"]) != 1 or job["target_schema"] != "glofas_unit_member_part4_v1":
            raise ValueError("Unsafe worker/target contract")
        if not set(dependencies(job)).issubset(allowed):
            raise ValueError("Unknown dependency")
    completed: set[str] = set()
    while len(completed) < len(jobs):
        ready = {x["run_id"] for x in jobs if set(dependencies(x)).issubset(completed)}
        new = ready - completed
        if not new:
            raise ValueError("Cyclic dependency graph")
        completed.update(new)


def artifact(path: Path) -> dict:
    return {"path": str(path.resolve()), "size_bytes": path.stat().st_size,
        "sha256": sha256(path)}


def assert_source_unchanged(frozen_head: str) -> None:
    if git("status", "--porcelain") or git("rev-parse", "HEAD") != frozen_head:
        raise RuntimeError("Source or HEAD changed after freeze; no new jobs will start")


def freeze(runtime: Path, tests: Path) -> None:
    if git("status", "--porcelain"):
        raise ValueError("Commit and review the complete source before freezing launch")
    if (runtime / "configs/launch_readiness.json").exists():
        raise ValueError("A launch freeze already exists; never overwrite it")
    receipt = json.loads(tests.read_text())
    if receipt.get("status") != "PASS" or receipt.get("git_head") != git("rev-parse", "HEAD"):
        raise ValueError("Tests receipt must pass on the current committed HEAD")
    preflight = json.loads((runtime / "PREFLIGHT.json").read_text())
    if preflight["new_completed_fit_units"] != 0 or preflight["runs_launched"]:
        raise ValueError("Preparation was not a fresh target")
    paths = set((REPO / "application/R").glob("*.R"))
    paths.update((runtime / "configs").rglob("*"))
    paths.update([REPO / "application/scripts/386_run_glofas_part4_latent_family_job.R",
        Path(__file__), REPO / "application/scripts/_glofas_unit_member_bootstrap.R",
        REPO / "application/scripts/prepare_glofas_unit_member_correction.R",
        runtime / "PREFLIGHT.json", runtime / "manifests/reused_source_manifest.csv", tests,
        runtime / "objects/part4_shared_design_truth_free.rds",
        runtime / "objects/part4_normal_driver_prior.rds",
        runtime / "objects/part4_scoring_panel_sidecar.rds",
        REPO / "application/config/glofas_unit_member_source_contract_v1.csv",
        Path(RSCRIPT)])
    for row in read_csv(runtime / "manifests/reused_source_manifest.csv"):
        source = Path(row["path"])
        if source.stat().st_size != int(row["size_bytes"]) or sha256(source) != row["sha256"]:
            raise ValueError(f"Reused frozen source changed: {source}")
    payload = {"status": "READY_FOR_PARENT_LAUNCH_REVIEW", "schema_version": "glofas_unit_member_launch_v1",
        "git_head": git("rev-parse", "HEAD"), "git_branch": git("branch", "--show-current"),
        "cpu_pool": CPU_POOL, "max_workers": 8, "joint_inner_workers": 1,
        "rscript": RSCRIPT, "thread_environment": THREAD_ENV,
        "initial_fit_units": 18, "artifacts": [artifact(p) for p in sorted(paths) if p.is_file()]}
    (runtime / "configs/launch_readiness.json").write_text(json.dumps(payload, indent=2) + "\n")


def verify(runtime: Path) -> dict:
    payload = json.loads((runtime / "configs/launch_readiness.json").read_text())
    if payload.get("schema_version") != "glofas_unit_member_launch_v1" or payload.get("status") != "READY_FOR_PARENT_LAUNCH_REVIEW":
        raise ValueError("Invalid launch-readiness schema or status")
    assert_source_unchanged(payload["git_head"])
    for row in payload["artifacts"]:
        path = Path(row["path"])
        if path.stat().st_size != row["size_bytes"] or sha256(path) != row["sha256"]:
            raise ValueError(f"Frozen artifact changed: {path}")
    if list(payload["cpu_pool"]) != list(CPU_POOL) or payload["joint_inner_workers"] != 1:
        raise ValueError("Resource contract changed")
    return payload


def execute(runtime: Path, poll: float = 10) -> None:
    frozen = verify(runtime)
    if not shutil.which("taskset") or not shutil.which("nice"):
        raise ValueError("taskset and nice are required")
    if not set(CPU_POOL).issubset(os.sched_getaffinity(0)):
        raise ValueError("The reserved CPU pool is not available in this process affinity")
    jobs = read_csv(runtime / "configs/part4_model_manifest.csv")
    validate_jobs(jobs)
    active: dict[str, tuple[subprocess.Popen, int, object]] = {}
    failed = False
    while True:
        for job_id, (proc, cpu, log) in list(active.items()):
            code = proc.poll()
            if code is None:
                continue
            log.close()
            del active[job_id]
            if code != 0 or not (runtime / "status" / (job_id + ".completed")).exists():
                failed = True
        if failed:
            if not active:
                raise RuntimeError("A fit failed; no further jobs launched. Inspect retained evidence.")
            time.sleep(poll)
            continue
        completed = {x["run_id"] for x in jobs
            if (runtime / "status" / (x["run_id"] + ".completed")).exists()}
        if len(completed) == 18:
            (runtime / "status/ALL_INITIAL_FITS_EXITED").write_text(
                "18/18 process completions; convergence and scientific promotion remain separate gates.\n")
            return
        used = {v[1] for v in active.values()}
        for row in jobs:
            job_id = row["run_id"]
            if len(active) >= 8:
                break
            if job_id in completed or job_id in active or not set(dependencies(row)).issubset(completed):
                continue
            if (runtime / "status" / (job_id + ".failed")).exists() or (runtime / "status" / (job_id + ".running")).exists():
                raise RuntimeError("Stale/failed marker requires explicit investigation, not automatic resume")
            cpu = next(c for c in CPU_POOL if c not in used)
            assert_source_unchanged(frozen["git_head"])
            used.add(cpu)
            env = os.environ.copy()
            env.update(THREAD_ENV)
            log = (runtime / "logs" / (job_id + ".log")).open("x")
            command = ["nice", "-n", "10", "taskset", "-c", str(cpu), RSCRIPT,
                "application/scripts/386_run_glofas_part4_latent_family_job.R",
                "--runtime_root", str(runtime), "--job_id", job_id]
            proc = subprocess.Popen(command, cwd=REPO, env=env, stdout=log, stderr=subprocess.STDOUT)
            active[job_id] = (proc, cpu, log)
            print(json.dumps({"job": job_id, "pid": proc.pid, "cpu": cpu}), flush=True)
        if not active:
            raise RuntimeError("No runnable jobs remain before 18 completions")
        time.sleep(poll)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", required=True, type=Path)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--freeze", action="store_true")
    mode.add_argument("--preflight", action="store_true")
    mode.add_argument("--execute", action="store_true")
    parser.add_argument("--tests-receipt", type=Path)
    args = parser.parse_args()
    runtime = args.runtime_root.resolve()
    validate_jobs(read_csv(runtime / "configs/part4_model_manifest.csv"))
    if args.freeze:
        if args.tests_receipt is None:
            parser.error("--freeze requires --tests-receipt")
        freeze(runtime, args.tests_receipt.resolve())
    elif args.preflight:
        verify(runtime)
        print("PREFLIGHT_PASS_NO_LAUNCH")
    else:
        with (runtime / "scheduler.lock").open("a") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            execute(runtime)


if __name__ == "__main__":
    main()
