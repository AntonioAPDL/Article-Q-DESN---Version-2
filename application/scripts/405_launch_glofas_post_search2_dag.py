#!/usr/bin/env python3
"""Launch the post-Search-II GloFAS DAG with dependency and thread guards."""

import argparse
import csv
import hashlib
import json
import os
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


THREAD_ENV = {name: "1" for name in (
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS")}


def repo_root():
    return Path(__file__).resolve().parents[2]


def resolve(path):
    p = Path(path)
    return p.resolve() if p.is_absolute() else (repo_root() / p).resolve()


def rows(path):
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def session(prefix, job):
    digest = hashlib.sha1(job.encode()).hexdigest()[:10]
    return f"{prefix}_{job[:42]}_{digest}".replace(".", "p")


def alive(name):
    return subprocess.run(["tmux", "has-session", "-t", name], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


def deps(row):
    return [value for value in row.get("dependencies", "").split("|") if value]


def shell_join(parts):
    return " ".join(shlex.quote(str(part)) for part in parts)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_output(*args):
    return subprocess.check_output(
        ["git", *args], cwd=str(repo_root()), universal_newlines=True
    ).strip()


def resolve_recorded(path):
    value = Path(path)
    return value.resolve() if value.is_absolute() else (repo_root() / value).resolve()


def verify_launch_readiness(runtime):
    path = runtime / "configs" / "launch_readiness.json"
    if not path.is_file():
        raise SystemExit(f"missing launch readiness contract: {path}")
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("status") != "ready":
        raise SystemExit("launch readiness status is not ready")
    if payload.get("git_head") != git_output("rev-parse", "HEAD"):
        raise SystemExit("current Git HEAD differs from launch readiness")
    if git_output("status", "--porcelain", "--untracked-files=no"):
        raise SystemExit("tracked worktree must be clean at production launch")
    for row in payload.get("artifacts", []):
        artifact = resolve_recorded(row["path"])
        if not artifact.is_file():
            raise SystemExit(f"frozen launch artifact is missing: {artifact}")
        if artifact.stat().st_size != int(row["size_bytes"]):
            raise SystemExit(f"frozen launch artifact size changed: {artifact}")
        if sha256(artifact) != row["sha256"]:
            raise SystemExit(f"frozen launch artifact hash changed: {artifact}")
    engine = payload.get("engine") or {}
    engine_path = Path(engine.get("path", ""))
    if not engine_path.is_dir():
        raise SystemExit("pinned engine path is unavailable at launch")
    engine_head = subprocess.check_output(
        ["git", "-C", str(engine_path), "rev-parse", "HEAD"], universal_newlines=True
    ).strip()
    engine_dirty = subprocess.check_output(
        ["git", "-C", str(engine_path), "status", "--porcelain", "--untracked-files=no"],
        universal_newlines=True,
    ).strip()
    if engine_head != engine.get("head") or engine_dirty:
        raise SystemExit("pinned engine state changed after preparation")
    return path, payload


def marker_conflicts(runtime, jobs):
    status = runtime / "status"
    conflicts = []
    for row in jobs:
        job = row["job_id"]
        states = [suffix for suffix in ("completed", "failed", "running")
                  if (status / f"{job}.{suffix}").exists()]
        if len(states) > 1:
            conflicts.append(f"{job}:{','.join(states)}")
    return conflicts


def dynamic_contract_artifacts(runtime):
    candidates = [
        runtime / "configs" / "recovery_contract.json",
        runtime / "configs" / "recovery_artifact_manifest.csv",
    ]
    execution = json.loads(
        (runtime / "configs" / "post_search2_execution_contract.json").read_text(encoding="utf-8")
    )
    part4 = resolve_recorded(execution["part4_runtime_root"])
    candidates.extend([
        part4 / "configs" / "part4_model_manifest.csv",
        part4 / "configs" / "part4_launch_metadata.json",
        part4 / "objects" / "part4_normal_driver_prior.rds",
    ])
    return [path for path in candidates if path.is_file()]


def launch_contract_payload(runtime, readiness_path, readiness, manifest, workers, session_prefix):
    dynamic = dynamic_contract_artifacts(runtime)
    return {
        "schema_version": "glofas_post_search2_launch_contract_v1",
        "launched_utc": datetime.now(timezone.utc).isoformat(),
        "hostname": subprocess.check_output(["hostname", "-f"], universal_newlines=True).strip(),
        "git_head": git_output("rev-parse", "HEAD"),
        "git_branch": git_output("rev-parse", "--abbrev-ref", "HEAD"),
        "runtime_root": str(runtime),
        "workers": workers,
        "session_prefix": session_prefix,
        "thread_environment": THREAD_ENV,
        "readiness_path": str(readiness_path),
        "readiness_sha256": sha256(readiness_path),
        "job_manifest": str(manifest),
        "job_manifest_sha256": sha256(manifest),
        "engine": readiness.get("engine"),
        "dynamic_artifacts": [
            {"path": str(path), "size_bytes": path.stat().st_size, "sha256": sha256(path)}
            for path in dynamic
        ],
    }


def verify_existing_launch_contract(path, expected):
    existing = json.loads(path.read_text(encoding="utf-8"))
    for key in ("git_head", "runtime_root", "workers", "session_prefix", "readiness_sha256", "job_manifest_sha256"):
        if existing.get(key) != expected.get(key):
            raise SystemExit(f"launch contract mismatch for {key}")
    for row in existing.get("dynamic_artifacts", []):
        artifact = Path(row["path"])
        if not artifact.is_file() or artifact.stat().st_size != int(row["size_bytes"]) or sha256(artifact) != row["sha256"]:
            raise SystemExit(f"launch dynamic artifact changed: {artifact}")
    return existing


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--workers", type=int, default=5)
    parser.add_argument("--poll-seconds", type=int, default=60)
    parser.add_argument("--session-prefix", default="glofas_post_search2_20260916")
    parser.add_argument("--background", action="store_true")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--scheduler-child", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not 1 <= args.workers <= 20: raise SystemExit("workers must be in 1..20")
    runtime = resolve(args.runtime_root)
    manifest = runtime / "tables" / "post_search2_job_manifest.csv"
    if not manifest.exists(): raise SystemExit(f"missing manifest: {manifest}")
    readiness_path, readiness = verify_launch_readiness(runtime)
    jobs = rows(manifest)
    conflicts = marker_conflicts(runtime, jobs)
    if conflicts:
        raise SystemExit("conflicting status markers: " + ", ".join(conflicts))
    prelaunch_failed = [
        row["job_id"] for row in jobs
        if (runtime / "status" / f"{row['job_id']}.failed").exists()
    ]
    prelaunch_running = [
        row["job_id"] for row in jobs
        if (runtime / "status" / f"{row['job_id']}.running").exists()
    ]
    if prelaunch_failed:
        raise SystemExit("failed jobs block launch: " + ", ".join(sorted(prelaunch_failed)))
    if prelaunch_running and not args.scheduler_child:
        raise SystemExit("running markers block a new launcher: " + ", ".join(sorted(prelaunch_running)))
    launch_contract = runtime / "configs" / "post_search2_launch_contract.json"
    expected_launch = launch_contract_payload(
        runtime, readiness_path, readiness, manifest, args.workers, args.session_prefix
    )
    if args.scheduler_child:
        if not launch_contract.is_file():
            raise SystemExit("scheduler child requires an existing launch contract")
        verify_existing_launch_contract(launch_contract, expected_launch)
    elif launch_contract.exists():
        if not args.resume:
            raise SystemExit("launch contract already exists; use --resume after auditing prior execution")
        verify_existing_launch_contract(launch_contract, expected_launch)
    else:
        launch_contract.write_text(json.dumps(expected_launch, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    scheduler = session(args.session_prefix, "scheduler")
    if args.background:
        if alive(scheduler):
            print(f"scheduler_already_active={scheduler}")
            return 0
        command = [sys.executable, str(Path(__file__).resolve()), "--runtime-root", str(runtime),
                   "--workers", str(args.workers), "--poll-seconds", str(args.poll_seconds),
                   "--session-prefix", args.session_prefix, "--scheduler-child"]
        log = runtime / "logs" / "post_search2_scheduler.log"
        subprocess.run(["tmux", "new-session", "-d", "-s", scheduler,
                        f"cd {shlex.quote(str(repo_root()))} && {shell_join(command)} >> {shlex.quote(str(log))} 2>&1"], check=True)
        print(f"scheduler_session={scheduler}")
        print(f"scheduler_log={log}")
        return 0

    status = runtime / "status"
    scripts = runtime / "scripts"
    logs = runtime / "logs"
    for directory in (status, scripts, logs): directory.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy(); env.update(THREAD_ENV)
    while True:
        done = {row["job_id"] for row in jobs if (status / f"{row['job_id']}.completed").exists()}
        failed = {row["job_id"] for row in jobs if (status / f"{row['job_id']}.failed").exists()}
        active = {row["job_id"] for row in jobs if alive(session(args.session_prefix, row["job_id"]))}
        stale = [row["job_id"] for row in jobs if (status / f"{row['job_id']}.running").exists() and row["job_id"] not in active]
        if failed: raise SystemExit("failed jobs: " + ", ".join(sorted(failed)))
        if stale: raise SystemExit("stale running markers: " + ", ".join(sorted(stale)))
        if len(done) == len(jobs):
            print(f"POST_SEARCH2_DAG_COMPLETE jobs={len(done)} failures=0", flush=True)
            return 0
        capacity = args.workers - len(active)
        launched = 0
        for row in jobs:
            if launched >= capacity: break
            job = row["job_id"]
            if job in done or job in active or not all(dep in done for dep in deps(row)): continue
            command = json.loads(row["command_json"])
            wrapper = scripts / f"{job}.sh"
            run = status / f"{job}.running"; complete = status / f"{job}.completed"; fail = status / f"{job}.failed"
            wrapper.write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\n"
                + "\n".join(f"export {key}={value}" for key, value in THREAD_ENV.items()) + "\n"
                + f"test ! -e {shlex.quote(str(fail))}\n"
                + f"test $(sha256sum {shlex.quote(str(launch_contract))} | awk '{{print $1}}') = {shlex.quote(sha256(launch_contract))}\n"
                + f"printf 'pid=%s\\nstarted=%s\\n' \"$$\" \"$(date -Is)\" > {shlex.quote(str(run))}\n"
                + f"trap 'rc=$?; rm -f {shlex.quote(str(run))}; if [ $rc -ne 0 ]; then printf \"exit_code=%s\\nfailed=%s\\n\" \"$rc\" \"$(date -Is)\" > {shlex.quote(str(fail))}; fi; exit $rc' EXIT\n"
                + f"cd {shlex.quote(str(repo_root()))}\n" + shell_join(command) + "\n"
                + f"printf 'completed=%s\\n' \"$(date -Is)\" > {shlex.quote(str(complete))}\n",
                encoding="utf-8")
            wrapper.chmod(0o755)
            log = logs / f"{job}.log"
            subprocess.run(["tmux", "new-session", "-d", "-s", session(args.session_prefix, job),
                            f"{shlex.quote(str(wrapper))} >> {shlex.quote(str(log))} 2>&1"], check=True, env=env)
            print(f"launched job={job} session={session(args.session_prefix, job)}", flush=True)
            launched += 1
        print(f"health completed={len(done)} running={len(active)+launched} pending={len(jobs)-len(done)-len(active)-launched} total={len(jobs)}", flush=True)
        time.sleep(max(1, args.poll_seconds))


if __name__ == "__main__":
    raise SystemExit(main())
