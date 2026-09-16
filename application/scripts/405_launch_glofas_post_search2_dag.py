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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--workers", type=int, default=5)
    parser.add_argument("--poll-seconds", type=int, default=60)
    parser.add_argument("--session-prefix", default="glofas_post_search2_20260916")
    parser.add_argument("--background", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.workers <= 20: raise SystemExit("workers must be in 1..20")
    runtime = resolve(args.runtime_root)
    manifest = runtime / "tables" / "post_search2_job_manifest.csv"
    if not manifest.exists(): raise SystemExit(f"missing manifest: {manifest}")
    scheduler = session(args.session_prefix, "scheduler")
    if args.background:
        if alive(scheduler):
            print(f"scheduler_already_active={scheduler}")
            return 0
        command = [sys.executable, str(Path(__file__).resolve()), "--runtime-root", str(runtime),
                   "--workers", str(args.workers), "--poll-seconds", str(args.poll_seconds),
                   "--session-prefix", args.session_prefix]
        log = runtime / "logs" / "post_search2_scheduler.log"
        subprocess.run(["tmux", "new-session", "-d", "-s", scheduler,
                        f"cd {shlex.quote(str(repo_root()))} && {shell_join(command)} >> {shlex.quote(str(log))} 2>&1"], check=True)
        print(f"scheduler_session={scheduler}")
        print(f"scheduler_log={log}")
        return 0

    jobs = rows(manifest)
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
                + f"rm -f {shlex.quote(str(fail))}\n"
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
