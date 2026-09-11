#!/usr/bin/env python3
"""Run the prepared Part 4 DAG only after an explicit operator approval token."""

import argparse
import csv
import hashlib
import os
import shlex
import subprocess
import sys
import time
from pathlib import Path


THREAD_ENV = {
    "OMP_NUM_THREADS": "1",
    "OMP_THREAD_LIMIT": "1",
    "OPENBLAS_NUM_THREADS": "1",
    "GOTO_NUM_THREADS": "1",
    "MKL_NUM_THREADS": "1",
    "BLIS_NUM_THREADS": "1",
    "VECLIB_MAXIMUM_THREADS": "1",
    "NUMEXPR_NUM_THREADS": "1",
}
OPENBLAS_CANDIDATES = (
    "/lib64/libopenblas.so",
    "/usr/lib64/libopenblas.so",
)
APPROVAL_TOKEN = "RUN_GLOFAS_PART4_LATENT_FAMILY"


def repo_root():
    return Path(__file__).resolve().parents[2]


def resolve(path):
    candidate = Path(path)
    return candidate.resolve() if candidate.is_absolute() else (repo_root() / candidate).resolve()


def read_manifest(path):
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def dependencies(row):
    return [item for item in row.get("dependencies", "").split("|") if item]


def session_name(prefix, job_id):
    raw = f"{prefix}_{job_id}".replace(".", "p")
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:12]
    stem_limit = 96 - len(digest) - 1
    return f"{raw[:stem_limit]}_{digest}"


def tmux_alive(name):
    return subprocess.run(
        ["tmux", "has-session", "-t", name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0


def shell_join(parts):
    return " ".join(shlex.quote(str(part)) for part in parts)


def resolve_blas_library(value):
    requested = str(value or "auto")
    if requested.lower() == "auto":
        candidates = [Path(path) for path in OPENBLAS_CANDIDATES]
    elif requested.lower() in {"none", "bundled"}:
        return None
    else:
        candidates = [Path(requested)]
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    raise SystemExit(
        "optimized BLAS library is required but unavailable; checked: "
        + ", ".join(str(path) for path in candidates)
    )


def runtime_env(blas_library):
    env = os.environ.copy()
    env.update(THREAD_ENV)
    if blas_library is not None:
        digest = hashlib.sha256()
        with blas_library.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
        existing = env.get("LD_PRELOAD", "").strip()
        env["LD_PRELOAD"] = str(blas_library) + ((":" + existing) if existing else "")
        env["QDESN_NUMERICAL_BACKEND"] = "openblas_serial"
        env["QDESN_BLAS_LIBRARY_PATH"] = str(blas_library)
        env["QDESN_BLAS_LIBRARY_SHA256"] = digest.hexdigest()
    else:
        env["QDESN_NUMERICAL_BACKEND"] = "bundled_rblas"
        env.pop("QDESN_BLAS_LIBRARY_PATH", None)
        env.pop("QDESN_BLAS_LIBRARY_SHA256", None)
    return env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--workers", type=int, default=18)
    parser.add_argument("--expected-jobs", type=int, default=18)
    parser.add_argument("--poll-seconds", type=int, default=60)
    parser.add_argument("--session-prefix", default="glofas_part4_latent")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--approval-token", default="")
    parser.add_argument("--background", action="store_true")
    parser.add_argument("--blas-library", default="auto")
    args = parser.parse_args()
    if not args.execute or args.approval_token != APPROVAL_TOKEN:
        raise SystemExit(
            "Launch blocked. Supply --execute --approval-token " + APPROVAL_TOKEN +
            " only after explicit scientific approval."
        )
    if args.workers < 1 or args.workers > 18:
        raise SystemExit("workers must be in 1..18; each model worker is single-threaded")
    runtime = resolve(args.runtime_root)
    blas_library = resolve_blas_library(args.blas_library)
    env = runtime_env(blas_library)
    manifest_path = runtime / "configs" / "part4_model_manifest.csv"
    if not manifest_path.exists():
        raise SystemExit(f"missing Part 4 manifest: {manifest_path}")
    scheduler_session = session_name(args.session_prefix, "scheduler")
    if args.background:
        if tmux_alive(scheduler_session):
            print(f"scheduler already active: {scheduler_session}")
            return 0
        command = [
            sys.executable, str(Path(__file__).resolve()),
            "--runtime-root", str(runtime), "--workers", str(args.workers),
            "--expected-jobs", str(args.expected_jobs),
            "--poll-seconds", str(args.poll_seconds), "--session-prefix", args.session_prefix,
            "--blas-library", str(blas_library) if blas_library is not None else "none",
            "--execute", "--approval-token", APPROVAL_TOKEN,
        ]
        log = runtime / "logs" / "part4_scheduler.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["tmux", "new-session", "-d", "-s", scheduler_session,
             f"{shell_join(command)} >> {shlex.quote(str(log))} 2>&1"],
            check=True,
            env=env,
        )
        print(f"scheduler_session={scheduler_session}")
        print(f"scheduler_log={log}")
        return 0

    rows = read_manifest(manifest_path)
    if args.expected_jobs < 1:
        raise SystemExit("expected-jobs must be positive")
    if len(rows) != args.expected_jobs:
        raise SystemExit(
            f"expected {args.expected_jobs} Part 4 model jobs, found {len(rows)}"
        )
    status_dir = runtime / "status"
    scripts_dir = runtime / "scripts"
    logs_dir = runtime / "logs"
    for directory in (status_dir, scripts_dir, logs_dir):
        directory.mkdir(parents=True, exist_ok=True)
    print(f"numerical_backend={env['QDESN_NUMERICAL_BACKEND']}", flush=True)
    print(f"blas_library={env.get('QDESN_BLAS_LIBRARY_PATH', '')}", flush=True)
    print(f"blas_sha256={env.get('QDESN_BLAS_LIBRARY_SHA256', '')}", flush=True)

    while True:
        completed = {row["run_id"] for row in rows if (status_dir / f"{row['run_id']}.completed").exists()}
        failed = {row["run_id"] for row in rows if (status_dir / f"{row['run_id']}.failed").exists()}
        active = {row["run_id"] for row in rows if tmux_alive(session_name(args.session_prefix, row["run_id"]))}
        stale = [row["run_id"] for row in rows
                 if (status_dir / f"{row['run_id']}.running").exists() and row["run_id"] not in active]
        if stale:
            raise SystemExit("stale Part 4 running markers require audit: " + ", ".join(stale))
        if failed:
            raise SystemExit("Part 4 failed jobs require audit: " + ", ".join(sorted(failed)))
        if len(completed) == len(rows):
            print("Part 4 DAG complete: 18/18, failed=0", flush=True)
            return 0
        capacity = args.workers - len(active)
        launched = 0
        for row in rows:
            if launched >= capacity:
                break
            job_id = row["run_id"]
            if job_id in completed or job_id in active:
                continue
            if not all(dep in completed for dep in dependencies(row)):
                continue
            wrapper = scripts_dir / f"{job_id}.sh"
            command = [
                "Rscript", str(repo_root() / "application/scripts/386_run_glofas_part4_latent_family_job.R"),
                "--runtime_root", str(runtime), "--job_id", job_id,
            ]
            wrapper.write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\n" +
                "\n".join(f"export {key}={value}" for key, value in THREAD_ENV.items()) +
                "\n" + f"export QDESN_NUMERICAL_BACKEND={shlex.quote(env['QDESN_NUMERICAL_BACKEND'])}" +
                ("\n" + f"export QDESN_BLAS_LIBRARY_PATH={shlex.quote(env['QDESN_BLAS_LIBRARY_PATH'])}" if blas_library is not None else "") +
                ("\n" + f"export QDESN_BLAS_LIBRARY_SHA256={shlex.quote(env['QDESN_BLAS_LIBRARY_SHA256'])}" if blas_library is not None else "") +
                ("\n" + f"export LD_PRELOAD={shlex.quote(env['LD_PRELOAD'])}" if blas_library is not None else "") +
                "\n" + shell_join(command) + "\n",
                encoding="utf-8",
            )
            wrapper.chmod(0o755)
            log = logs_dir / f"{job_id}.log"
            subprocess.run(
                ["tmux", "new-session", "-d", "-s", session_name(args.session_prefix, job_id),
                 f"{shlex.quote(str(wrapper))} >> {shlex.quote(str(log))} 2>&1"],
                check=True,
                env=env,
            )
            launched += 1
            print(f"launched job={job_id} dependencies={row.get('dependencies', '')}", flush=True)
        pending = len(rows) - len(completed) - len(active) - launched
        print(
            f"health completed={len(completed)} running={len(active) + launched} "
            f"failed={len(failed)} pending={max(pending, 0)} total={len(rows)}",
            flush=True,
        )
        time.sleep(max(args.poll_seconds, 1))


if __name__ == "__main__":
    raise SystemExit(main())
