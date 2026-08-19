#!/usr/bin/env python3

import argparse
import csv
import datetime as dt
import hashlib
import os
import pathlib
import shutil
import subprocess
import time


def parse_args():
    parser = argparse.ArgumentParser(description="Bounded scheduler for GloFAS fit recovery.")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--max-parallel", type=int, default=4)
    parser.add_argument("--max-load", type=float, default=58.0)
    parser.add_argument("--min-memory-gb", type=float, default=48.0)
    parser.add_argument("--min-disk-gb", type=float, default=120.0)
    parser.add_argument("--poll-seconds", type=int, default=60)
    parser.add_argument("--cores", default="3,7,11,15")
    parser.add_argument(
        "--retry-failed",
        action="store_true",
        help="Retry non-running candidates whose worker status is failed.",
    )
    return parser.parse_args()


def timestamp():
    return dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="seconds")


def is_true(value):
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def canonical_bool(value):
    normalized = str(value).strip().lower()
    if normalized in {"1", "true", "t", "yes", "y"}:
        return "true"
    if normalized in {"0", "false", "f", "no", "n", ""}:
        return "false"
    raise ValueError(f"Invalid boolean value: {value}")


def available_memory_gb():
    values = {}
    with open("/proc/meminfo", encoding="utf-8") as handle:
        for line in handle:
            key, value = line.split(":", 1)
            values[key] = float(value.strip().split()[0])
    return values["MemAvailable"] / 1024.0 / 1024.0


def atomic_csv(path, rows, fieldnames):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    os.replace(tmp, path)


def read_manifest(path):
    with open(path, newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    rows.sort(key=lambda row: int(float(row["priority"])))
    return rows


def sha256_file(path):
    digest = hashlib.sha256()
    with pathlib.Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_within(path, root, label):
    path = pathlib.Path(path).resolve()
    root = pathlib.Path(root).resolve()
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"{label} escapes its owned runtime root: {path}") from exc
    return path


def validate_manifest(rows, output_root, cores, max_parallel):
    if not rows:
        raise ValueError("The scheduler manifest is empty")
    required = {
        "candidate_id", "priority", "config_path", "config_sha256",
        "model_grid_path", "model_grid_sha256", "run_id", "run_dir",
        "log_path",
    }
    missing = required.difference(rows[0])
    if missing:
        raise ValueError(
            "The scheduler manifest lacks required columns: "
            + ", ".join(sorted(missing))
        )
    candidate_ids = [row["candidate_id"] for row in rows]
    run_ids = [row["run_id"] for row in rows]
    priorities = [int(float(row["priority"])) for row in rows]
    if any(not value or "/" in value or "\\" in value for value in candidate_ids):
        raise ValueError("Candidate IDs must be nonempty path-safe values")
    if len(candidate_ids) != len(set(candidate_ids)):
        raise ValueError("Candidate IDs must be unique")
    if len(run_ids) != len(set(run_ids)):
        raise ValueError("Run IDs must be unique")
    if len(priorities) != len(set(priorities)):
        raise ValueError("Manifest priorities must be unique")
    if len(cores) != len(set(cores)):
        raise ValueError("Declared scheduler cores must be unique")
    cpu_count = os.cpu_count() or 1
    if any(core < 0 or core >= cpu_count for core in cores):
        raise ValueError(f"Declared scheduler cores must lie in [0, {cpu_count - 1}]")
    if max_parallel < 1 or max_parallel > len(cores):
        raise ValueError(
            "max-parallel must be between one and the number of declared cores"
        )

    output_root = pathlib.Path(output_root).resolve()
    runs_root = output_root / "runs"
    logs_root = output_root / "logs"
    hash_cache = {}

    def cached_sha256(path):
        resolved = pathlib.Path(path).resolve()
        if resolved not in hash_cache:
            hash_cache[resolved] = sha256_file(resolved)
        return hash_cache[resolved]

    for row in rows:
        config_path = pathlib.Path(row["config_path"]).resolve()
        grid_path = pathlib.Path(row["model_grid_path"]).resolve()
        if not config_path.is_file() or not grid_path.is_file():
            raise ValueError(
                f"Prepared config/model grid is missing for {row['candidate_id']}"
            )
        if cached_sha256(config_path) != row["config_sha256"]:
            raise ValueError(f"Config hash changed for {row['candidate_id']}")
        if cached_sha256(grid_path) != row["model_grid_sha256"]:
            raise ValueError(f"Model-grid hash changed for {row['candidate_id']}")
        require_within(row["run_dir"], runs_root, "Run directory")
        require_within(row["log_path"], logs_root, "Log path")

        preflight_enabled = canonical_bool(
            row.get("reservoir_preflight_enabled", "false")
        ) == "true"
        if preflight_enabled:
            preflight_summary = row.get("reservoir_preflight_summary_path", "").strip()
            preflight_run_id = row.get("reservoir_preflight_run_id", "").strip()
            if not preflight_summary or not preflight_run_id:
                raise ValueError(
                    f"Reservoir preflight paths are incomplete for {row['candidate_id']}"
                )
            require_within(preflight_summary, runs_root, "Reservoir preflight summary")

        warm_path = row.get("warm_start_source_fit_object", "").strip()
        warm_hash = row.get("warm_start_source_sha256", "").strip()
        if bool(warm_path) != bool(warm_hash):
            raise ValueError(
                f"Warm-start path/hash must be supplied together for {row['candidate_id']}"
            )
        if warm_path:
            if not pathlib.Path(warm_path).is_file():
                raise ValueError(
                    f"Warm-start source is missing for {row['candidate_id']}"
                )
            if cached_sha256(warm_path) != warm_hash:
                raise ValueError(
                    f"Warm-start source hash changed for {row['candidate_id']}"
                )


def read_last_csv(path):
    path = pathlib.Path(path)
    if not path.exists():
        return {}
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    return rows[-1] if rows else {}


def pid_alive(pid_text):
    try:
        pid = int(pid_text)
    except (TypeError, ValueError):
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def main():
    args = parse_args()
    repo_root = pathlib.Path(__file__).resolve().parents[2]
    output_root = pathlib.Path(args.output_root).resolve()
    manifest = read_manifest(args.manifest)
    cores = [int(value) for value in args.cores.split(",") if value.strip()]
    validate_manifest(manifest, output_root, cores, args.max_parallel)
    output_root.mkdir(parents=True, exist_ok=True)
    (output_root / "logs").mkdir(exist_ok=True)
    state_path = output_root / "scheduler_state.csv"
    stop_path = output_root / "STOP"
    previous_states = {
        row["candidate_id"]: row
        for row in read_manifest(state_path)
    } if state_path.exists() else {}
    active = {}
    states = {
        row["candidate_id"]: {
            "candidate_id": row["candidate_id"],
            "priority": row["priority"],
            "status": "pending",
            "core": "",
            "pid": "",
            "started_at": "",
            "finished_at": "",
            "return_code": "",
            "run_id": row["run_id"],
            "log_path": row["log_path"],
        }
        for row in manifest
    }

    for row in manifest:
        candidate_id = row["candidate_id"]
        marker = pathlib.Path(row["run_dir"]) / ".fit_recovery_complete"
        rejected_marker = pathlib.Path(row["run_dir"]) / ".reservoir_preflight_rejected"
        if marker.exists():
            states[candidate_id]["status"] = "completed_existing"
            continue
        if rejected_marker.exists():
            states[candidate_id]["status"] = "rejected_existing"
            continue
        worker = read_last_csv(output_root / "status" / f"{candidate_id}.csv")
        previous = previous_states.get(candidate_id, {})
        pid = worker.get("pid", "") or previous.get("pid", "")
        if worker.get("status") == "running" and pid_alive(pid):
            states[candidate_id].update({
                "status": "running_external",
                "core": previous.get("core", ""),
                "pid": pid,
                "started_at": previous.get("started_at", ""),
            })
        elif worker.get("status") == "failed":
            if args.retry_failed:
                states[candidate_id]["status"] = "pending"
            else:
                states[candidate_id].update({
                    "status": "failed_existing",
                    "pid": pid,
                    "finished_at": worker.get("timestamp", ""),
                    "return_code": worker.get("exit_code", ""),
                })

    fields = list(next(iter(states.values())).keys())
    while True:
        for candidate_id, item in list(active.items()):
            return_code = item["process"].poll()
            if return_code is None:
                continue
            item["log_handle"].close()
            state = states[candidate_id]
            row = next(row for row in manifest if row["candidate_id"] == candidate_id)
            rejected_marker = pathlib.Path(row["run_dir"]) / ".reservoir_preflight_rejected"
            state["status"] = (
                "rejected" if return_code == 0 and rejected_marker.exists()
                else "completed" if return_code == 0
                else "failed"
            )
            state["finished_at"] = timestamp()
            state["return_code"] = str(return_code)
            del active[candidate_id]

        for candidate_id, state in states.items():
            if state["status"] != "running_external":
                continue
            row = next(row for row in manifest if row["candidate_id"] == candidate_id)
            marker = pathlib.Path(row["run_dir"]) / ".fit_recovery_complete"
            rejected_marker = pathlib.Path(row["run_dir"]) / ".reservoir_preflight_rejected"
            worker = read_last_csv(output_root / "status" / f"{candidate_id}.csv")
            if marker.exists():
                state["status"] = "completed_existing"
                state["finished_at"] = worker.get("timestamp", timestamp())
                state["return_code"] = "0"
            elif rejected_marker.exists():
                state["status"] = "rejected_existing"
                state["finished_at"] = worker.get("timestamp", timestamp())
                state["return_code"] = "0"
            elif worker.get("status") == "failed":
                state["status"] = "failed_existing"
                state["finished_at"] = worker.get("timestamp", timestamp())
                state["return_code"] = worker.get("exit_code", "")
            elif not pid_alive(state["pid"]):
                state["status"] = "failed_stale"
                state["finished_at"] = timestamp()
                state["return_code"] = "worker_pid_not_alive"

        pending = [
            row for row in manifest
            if states[row["candidate_id"]]["status"] == "pending"
        ]
        external_count = sum(
            state["status"] == "running_external"
            for state in states.values()
        )
        if not pending and not active and external_count == 0:
            atomic_csv(state_path, list(states.values()), fields)
            break
        if stop_path.exists():
            for row in pending:
                states[row["candidate_id"]]["status"] = "stopped_before_launch"
            atomic_csv(state_path, list(states.values()), fields)
            break

        load = os.getloadavg()[0]
        memory_gb = available_memory_gb()
        disk_gb = shutil.disk_usage(output_root).free / (1024.0 ** 3)
        occupied_cores = {x["core"] for x in active.values()}
        occupied_cores.update(
            int(state["core"])
            for state in states.values()
            if state["status"] == "running_external" and str(state["core"]).isdigit()
        )
        free_cores = [core for core in cores if core not in occupied_cores]
        resources_ok = (
            load < args.max_load
            and memory_gb >= args.min_memory_gb
            and disk_gb >= args.min_disk_gb
        )
        while (
            pending
            and free_cores
            and len(active) + external_count < args.max_parallel
            and resources_ok
        ):
            row = pending.pop(0)
            core = free_cores.pop(0)
            candidate_id = row["candidate_id"]
            log_path = pathlib.Path(row["log_path"])
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_handle = log_path.open("a", encoding="utf-8")
            command = [
                "taskset", "-c", str(core),
                "bash", str(repo_root / "application/scripts/glofas_fit_recovery_run_candidate.sh"),
                candidate_id, row["config_path"], row["run_id"], str(output_root),
            ]
            env = os.environ.copy()
            env.update({
                "OMP_NUM_THREADS": "1",
                "OPENBLAS_NUM_THREADS": "1",
                "MKL_NUM_THREADS": "1",
                "VECLIB_MAXIMUM_THREADS": "1",
                "NUMEXPR_NUM_THREADS": "1",
                "GLOFAS_RESERVOIR_PREFLIGHT_ENABLED": canonical_bool(
                    row.get("reservoir_preflight_enabled", "false")
                ),
                "GLOFAS_RESERVOIR_PREFLIGHT_TARGET": row.get("reservoir_preflight_target", "reservoir"),
                "GLOFAS_RESERVOIR_PREFLIGHT_REJECT_DECISION": row.get("reservoir_preflight_reject_decision", "reject"),
                "GLOFAS_RESERVOIR_PREFLIGHT_RUN_ID": row.get("reservoir_preflight_run_id", ""),
                "GLOFAS_RESERVOIR_PREFLIGHT_SUMMARY_PATH": row.get("reservoir_preflight_summary_path", ""),
                "GLOFAS_RESERVOIR_PREFLIGHT_MAX_CORR_FEATURES_FULL": row.get("reservoir_preflight_max_corr_features_full", "5000"),
                "GLOFAS_RESERVOIR_PREFLIGHT_CORR_BLOCK_SIZE": row.get("reservoir_preflight_corr_block_size", "512"),
                "GLOFAS_RESERVOIR_PREFLIGHT_SPECTRAL_RADIUS_EXACT_MAX_N": row.get("reservoir_preflight_spectral_radius_exact_max_n", "512"),
                "GLOFAS_RESERVOIR_PREFLIGHT_CHEAP_VALIDATION": canonical_bool(
                    row.get("reservoir_preflight_cheap_validation", "false")
                ),
            })
            process = subprocess.Popen(
                command,
                cwd=repo_root,
                stdout=log_handle,
                stderr=subprocess.STDOUT,
                env=env,
            )
            states[candidate_id].update({
                "status": "running",
                "core": str(core),
                "pid": str(process.pid),
                "started_at": timestamp(),
            })
            active[candidate_id] = {
                "process": process,
                "core": core,
                "log_handle": log_handle,
            }
            load = os.getloadavg()[0]
            memory_gb = available_memory_gb()
            disk_gb = shutil.disk_usage(output_root).free / (1024.0 ** 3)
            resources_ok = (
                load < args.max_load
                and memory_gb >= args.min_memory_gb
                and disk_gb >= args.min_disk_gb
            )

        atomic_csv(state_path, list(states.values()), fields)
        time.sleep(args.poll_seconds)


if __name__ == "__main__":
    main()
