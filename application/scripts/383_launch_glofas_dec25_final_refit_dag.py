#!/usr/bin/env python3
"""Launch the Dec25 Part 2/3 final-refit DAG in tmux after operator approval."""

from __future__ import annotations

import argparse
import csv
import json
import os
import shlex
import subprocess
import sys
import time
from pathlib import Path


THREAD_ENV = {
    "OMP_NUM_THREADS": "1",
    "OPENBLAS_NUM_THREADS": "1",
    "MKL_NUM_THREADS": "1",
    "VECLIB_MAXIMUM_THREADS": "1",
    "NUMEXPR_NUM_THREADS": "1",
}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def resolve(path: str) -> Path:
    p = Path(path)
    return p.resolve() if p.is_absolute() else (repo_root() / p).resolve()


def shell_join(parts) -> str:
    return " ".join(shlex.quote(str(part)) for part in parts)


def read_manifest(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def session_name(prefix: str, job_id: str) -> str:
    return f"{prefix}_{job_id}".replace(".", "p")[:78]


def tmux_alive(name: str) -> bool:
    return subprocess.run(["tmux", "has-session", "-t", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def deps(row: dict) -> list[str]:
    return [dep for dep in row.get("dependencies", "").split("|") if dep]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--workers", type=int, default=20)
    parser.add_argument("--poll-seconds", type=int, default=60)
    parser.add_argument("--session-prefix", default="glofas_dec25_final_jerez_20260905")
    parser.add_argument("--background", action="store_true")
    args = parser.parse_args()

    if args.workers < 1 or args.workers > 20:
        raise SystemExit("workers must be in 1..20 for this workflow")
    runtime = resolve(args.runtime_root)
    manifest = runtime / "tables" / "final_dec25_job_manifest.csv"
    if not manifest.exists():
        raise SystemExit(f"missing Dec25 job manifest: {manifest}")
    scheduler_session = session_name(args.session_prefix, "scheduler")
    if args.background:
        if tmux_alive(scheduler_session):
            print(f"scheduler already active: {scheduler_session}")
            return 0
        cmd = [
            sys.executable, str(Path(__file__).resolve()),
            "--runtime-root", str(runtime),
            "--workers", str(args.workers),
            "--poll-seconds", str(args.poll_seconds),
            "--session-prefix", args.session_prefix,
        ]
        log = runtime / "logs" / "final_dec25_scheduler.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["tmux", "new-session", "-d", "-s", scheduler_session, f"{shell_join(cmd)} >> {shlex.quote(str(log))} 2>&1"], check=True)
        print(f"scheduler_session={scheduler_session}")
        print(f"scheduler_log={log}")
        return 0

    rows = read_manifest(manifest)
    status_dir = runtime / "status"
    scripts_dir = runtime / "scripts"
    logs_dir = runtime / "logs"
    for path in (status_dir, scripts_dir, logs_dir):
        path.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(THREAD_ENV)

    while True:
        completed = {row["job_id"] for row in rows if (status_dir / f"{row['job_id']}.completed").exists()}
        failed = {row["job_id"] for row in rows if (status_dir / f"{row['job_id']}.failed").exists()}
        active = {row["job_id"] for row in rows if tmux_alive(session_name(args.session_prefix, row["job_id"]))}
        stale = [
            row["job_id"] for row in rows
            if (status_dir / f"{row['job_id']}.running").exists() and row["job_id"] not in active
        ]
        if stale:
            raise SystemExit("Stale running markers require audit: " + ", ".join(stale))
        if failed:
            raise SystemExit("Dec25 DAG has failed jobs: " + ", ".join(sorted(failed)))
        if len(completed) == len(rows):
            print(f"Dec25 DAG complete: {len(completed)}/{len(rows)} jobs, failures=0", flush=True)
            return 0
        capacity = args.workers - len(active)
        launched = 0
        if capacity > 0:
            for row in rows:
                job_id = row["job_id"]
                if job_id in completed or job_id in active:
                    continue
                dependencies = deps(row)
                if not all(dep in completed for dep in dependencies):
                    continue
                command = json.loads(row["command_json"])
                wrapper = scripts_dir / f"{job_id}.sh"
                wrapper.write_text(
                    "#!/usr/bin/env bash\nset -euo pipefail\n"
                    + "\n".join(f"export {key}={value}" for key, value in THREAD_ENV.items())
                    + "\n"
                    + shell_join(command)
                    + "\n",
                    encoding="utf-8",
                )
                wrapper.chmod(0o755)
                log = logs_dir / f"{job_id}.log"
                subprocess.run(
                    ["tmux", "new-session", "-d", "-s", session_name(args.session_prefix, job_id), f"{shlex.quote(str(wrapper))} >> {shlex.quote(str(log))} 2>&1"],
                    check=True,
                    env=env,
                )
                print(f"launched job={job_id} session={session_name(args.session_prefix, job_id)}", flush=True)
                launched += 1
                if launched >= capacity:
                    break
        pending = len(rows) - len(completed) - len(active) - launched
        print(f"health completed={len(completed)} running={len(active) + launched} failed={len(failed)} pending={max(pending, 0)} total={len(rows)}", flush=True)
        time.sleep(max(args.poll_seconds, 1))


if __name__ == "__main__":
    raise SystemExit(main())
