#!/usr/bin/env python3
"""Run the Part 3 dependency DAG with one thread per tmux worker."""

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
    "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
    "VECLIB_MAXIMUM_THREADS": "1", "NUMEXPR_NUM_THREADS": "1",
}


def shell_join(parts) -> str:
    return " ".join(shlex.quote(str(part)) for part in parts)


def read_manifest(path: Path):
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def session_name(prefix: str, job: str) -> str:
    raw = f"{prefix}_{job}".replace(".", "p")
    return raw[:78]


def tmux_alive(name: str) -> bool:
    return subprocess.run(["tmux", "has-session", "-t", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--workers", type=int, default=20)
    parser.add_argument("--poll-seconds", type=int, default=60)
    parser.add_argument("--session-prefix", default="glofas_p3_20260904")
    parser.add_argument("--background", action="store_true")
    args = parser.parse_args()
    runtime = Path(args.runtime_root).resolve()
    manifest = runtime / "configs" / "part3_quantile_forecast_job_manifest.csv"
    if not manifest.exists():
        raise SystemExit(f"Missing Part 3 job manifest: {manifest}")
    if args.workers < 1:
        raise SystemExit("workers must be positive")

    scheduler_session = (args.session_prefix + "_scheduler")[:78]
    if args.background:
        if tmux_alive(scheduler_session):
            print(f"scheduler already active: {scheduler_session}")
            return 0
        cmd = [sys.executable, str(Path(__file__).resolve()), "--runtime-root", str(runtime),
               "--workers", str(args.workers), "--poll-seconds", str(args.poll_seconds),
               "--session-prefix", args.session_prefix]
        log = runtime / "logs" / "part3_quantile_forecast_scheduler.log"
        shell = f"{shell_join(cmd)} >> {shlex.quote(str(log))} 2>&1"
        subprocess.run(["tmux", "new-session", "-d", "-s", scheduler_session, shell], check=True)
        print(f"scheduler_session={scheduler_session}")
        print(f"scheduler_log={log}")
        return 0

    rows = read_manifest(manifest)
    status_dir = runtime / "status"
    scripts_dir = runtime / "scripts"
    logs_dir = runtime / "logs"
    status_dir.mkdir(parents=True, exist_ok=True)
    scripts_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(THREAD_ENV)

    while True:
        done = {row["job_id"] for row in rows if (status_dir / f"{row['job_id']}.completed").exists()}
        failed = {row["job_id"] for row in rows if (status_dir / f"{row['job_id']}.failed").exists()}
        active = {row["job_id"] for row in rows if tmux_alive(session_name(args.session_prefix, row["job_id"]))}
        stale = [row["job_id"] for row in rows if (status_dir / f"{row['job_id']}.running").exists() and row["job_id"] not in active]
        if stale:
            raise SystemExit("Stale Part 3 running markers require audit: " + ", ".join(stale))
        if len(done) == len(rows):
            print(f"Part 3 scheduler finished: {len(done)}/{len(rows)} complete, 0 failed", flush=True)
            return 0
        capacity = args.workers - len(active)
        launched = 0
        if capacity > 0:
            for row in rows:
                job = row["job_id"]
                if job in done or job in failed or job in active:
                    continue
                deps = [x for x in row["dependencies"].split("|") if x]
                if any(dep in failed for dep in deps) or not all(dep in done for dep in deps):
                    continue
                command = json.loads(row["command_json"])
                wrapper = scripts_dir / f"{job}.sh"
                wrapper.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + "\n".join(f"export {k}={v}" for k, v in THREAD_ENV.items()) + "\n" + shell_join(command) + "\n", encoding="utf-8")
                wrapper.chmod(0o755)
                log = logs_dir / f"{job}.log"
                shell = f"{shlex.quote(str(wrapper))} >> {shlex.quote(str(log))} 2>&1"
                name = session_name(args.session_prefix, job)
                subprocess.run(["tmux", "new-session", "-d", "-s", name, shell], check=True, env=env)
                print(f"launched job={job} session={name}", flush=True)
                launched += 1
                if launched >= capacity:
                    break
        pending = len(rows) - len(done) - len(failed) - len(active)
        print(f"health done={len(done)} running={len(active) + launched} failed={len(failed)} pending={max(pending - launched, 0)} total={len(rows)}", flush=True)
        if failed and not active and launched == 0:
            raise SystemExit("Part 3 scheduler stopped after failures: " + ", ".join(sorted(failed)))
        time.sleep(max(args.poll_seconds, 1))


if __name__ == "__main__":
    raise SystemExit(main())
