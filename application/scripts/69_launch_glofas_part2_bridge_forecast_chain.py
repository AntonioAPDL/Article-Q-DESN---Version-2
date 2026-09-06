#!/usr/bin/env python3
"""Manifest-gated tmux scheduler for the Part 2 bridge forecast chain."""

from __future__ import annotations

import argparse
import csv
import os
import shlex
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def resolve(path: str) -> Path:
    p = Path(path)
    return p if p.is_absolute() else repo_root() / p


def read_manifest(root: Path) -> list[dict]:
    with (root / "tables" / "part2_bridge_forecast_job_manifest.csv").open(newline="") as f:
        return list(csv.DictReader(f))


def deps(job: dict) -> list[str]:
    return [x for x in job.get("dependencies", "").split("|") if x]


def tmux_sessions() -> set[str]:
    try:
        out = subprocess.check_output(["tmux", "list-sessions", "-F", "#{session_name}"], text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return set()
    return {line.strip() for line in out.splitlines() if line.strip()}


def status(job: dict, sessions: set[str]) -> str:
    if resolve(job["status_failed_path"]).exists():
        return "failed"
    if resolve(job["status_done_path"]).exists():
        return "completed"
    if job["tmux_session"] in sessions:
        return "running"
    if resolve(job["status_running_path"]).exists():
        return "stale_running"
    return "not_started"


def done_ids(jobs: list[dict]) -> set[str]:
    return {j["job_id"] for j in jobs if resolve(j["status_done_path"]).exists()}


def touch_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def run_health(root: Path) -> None:
    try:
        root_arg = str(root.relative_to(repo_root()))
    except ValueError:
        root_arg = str(root)
    subprocess.run(
        [
            "python3",
            "application/scripts/68_check_glofas_part2_bridge_forecast_chain.py",
            "--runtime_root",
            root_arg,
            "--write",
        ],
        cwd=repo_root(),
        check=False,
    )


def launch_job(job: dict) -> None:
    running_path = resolve(job["status_running_path"])
    done_path = resolve(job["status_done_path"])
    failed_path = resolve(job["status_failed_path"])
    log_path = resolve(job["log_path"])
    script_path = log_path.with_suffix(".sh")
    log_path.parent.mkdir(parents=True, exist_ok=True)
    text = (
        f"job_id={job['job_id']}\n"
        f"session={job['tmux_session']}\n"
        f"started_utc={datetime.now(timezone.utc).isoformat()}\n"
        f"command={job['command']}\n"
    )
    touch_text(running_path, text)
    script = f"""
set -o pipefail
cd {shlex.quote(str(repo_root()))}
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
echo "started_utc={datetime.now(timezone.utc).isoformat()}"
echo "job_id={job['job_id']}"
echo "command={job['command']}"
{job['command']}
rc=$?
rm -f {shlex.quote(str(running_path))}
if [ "$rc" -eq 0 ]; then
  printf 'job_id=%s\\ncompleted_utc=%s\\n' {shlex.quote(job['job_id'])} "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > {shlex.quote(str(done_path))}
else
  printf 'job_id=%s\\nfailed_utc=%s\\nexit_code=%s\\n' {shlex.quote(job['job_id'])} "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rc" > {shlex.quote(str(failed_path))}
fi
exit "$rc"
"""
    script_path.write_text("#!/usr/bin/env bash\n" + script)
    os.chmod(script_path, 0o755)
    tmux_cmd = f"/bin/bash {shlex.quote(str(script_path))} 2>&1 | tee -a {shlex.quote(str(log_path))}"
    subprocess.run(
        [
            "tmux",
            "new-session",
            "-d",
            "-s",
            job["tmux_session"],
            tmux_cmd,
        ],
        check=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime_root", required=True)
    parser.add_argument("--workers", type=int, default=20)
    parser.add_argument("--poll_seconds", type=int, default=300)
    args = parser.parse_args()
    root = resolve(args.runtime_root).resolve()
    workers = max(1, int(args.workers))
    poll = max(10, int(args.poll_seconds))
    scheduler_log = root / "logs" / "scheduler_events.log"
    scheduler_log.parent.mkdir(parents=True, exist_ok=True)

    while True:
        jobs = read_manifest(root)
        sessions = tmux_sessions()
        states = {job["job_id"]: status(job, sessions) for job in jobs}
        failed = [jid for jid, st in states.items() if st == "failed"]
        completed = [jid for jid, st in states.items() if st == "completed"]
        running = [jid for jid, st in states.items() if st == "running"]
        stale = [jid for jid, st in states.items() if st == "stale_running"]
        done = done_ids(jobs)
        if failed:
            run_health(root)
            msg = f"{datetime.now(timezone.utc).isoformat()} scheduler_stop_failed jobs={','.join(failed)}\n"
            scheduler_log.open("a").write(msg)
            print(msg, end="")
            return 2
        if stale:
            run_health(root)
            msg = f"{datetime.now(timezone.utc).isoformat()} scheduler_stop_stale_running jobs={','.join(stale)}\n"
            scheduler_log.open("a").write(msg)
            print(msg, end="")
            return 3
        if len(completed) == len(jobs):
            run_health(root)
            msg = f"{datetime.now(timezone.utc).isoformat()} scheduler_complete jobs={len(jobs)}\n"
            scheduler_log.open("a").write(msg)
            print(msg, end="")
            return 0

        capacity = max(0, workers - len(running))
        launchable = [
            job
            for job in jobs
            if states[job["job_id"]] == "not_started" and all(dep in done for dep in deps(job))
        ]
        launched = []
        for job in launchable[:capacity]:
            launch_job(job)
            launched.append(job["job_id"])
        run_health(root)
        msg = (
            f"{datetime.now(timezone.utc).isoformat()} scheduler_poll "
            f"completed={len(completed)}/{len(jobs)} running={len(running) + len(launched)} "
            f"launched={','.join(launched) if launched else 'none'}\n"
        )
        scheduler_log.open("a").write(msg)
        print(msg, end="", flush=True)
        time.sleep(poll)


if __name__ == "__main__":
    raise SystemExit(main())
