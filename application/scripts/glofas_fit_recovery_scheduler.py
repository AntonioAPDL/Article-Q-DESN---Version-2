#!/usr/bin/env python3

import argparse
import csv
import datetime as dt
import hashlib
import os
import pathlib
import re
import shutil
import subprocess
import sys
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
    parser.add_argument(
        "--state-file",
        default="",
        help="Optional scheduler-state CSV path inside output-root.",
    )
    parser.add_argument(
        "--calibration-jobs",
        type=int,
        default=0,
        help="Initially cap concurrency at this many jobs until calibration-iterations are observed.",
    )
    parser.add_argument("--calibration-iterations", type=int, default=10)
    parser.add_argument("--memory-reserve-gb", type=float, default=48.0)
    parser.add_argument(
        "--memory-safety-log",
        default="",
        help="Optional resource-calibration CSV path inside output-root.",
    )
    parser.add_argument("--cores", default="3,7,11,15")
    parser.add_argument(
        "--cpu-sets",
        default="",
        help="Optional semicolon-separated CPU sets, for example '0,4;1,5'.",
    )
    parser.add_argument(
        "--numerical-backend",
        choices=("bundled_rblas", "openblas_serial", "openblas_pthread"),
        default="bundled_rblas",
    )
    parser.add_argument("--backend-threads", type=int, default=1)
    parser.add_argument("--backend-library", default="")
    parser.add_argument("--backend-sha256", default="")
    parser.add_argument(
        "--reference-feature-cache-root",
        default="",
        help=(
            "Optional immutable reference-feature cache. The path must remain "
            "inside output-root and is shared only by semantically identical fits."
        ),
    )
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


def process_tree_snapshot():
    """Read parent links and resident memory once for all visible processes."""
    children = {}
    rss_kb = {}
    for entry in pathlib.Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            stat = (entry / "stat").read_text(encoding="utf-8").split()
            parent = int(stat[3])
            status = (entry / "status").read_text(encoding="utf-8")
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
            continue
        children.setdefault(parent, []).append(int(entry.name))
        match = re.search(r"^VmRSS:\s+(\d+)\s+kB$", status, flags=re.MULTILINE)
        rss_kb[int(entry.name)] = int(match.group(1)) if match else 0
    return children, rss_kb


def process_tree_rss_gb(root_pid, snapshot=None):
    """Return resident memory for a process and all descendants."""
    try:
        root_pid = int(root_pid)
    except (TypeError, ValueError):
        return 0.0
    children, rss_kb = snapshot if snapshot is not None else process_tree_snapshot()
    stack = [root_pid]
    seen = set()
    total = 0
    while stack:
        pid = stack.pop()
        if pid in seen:
            continue
        seen.add(pid)
        total += rss_kb.get(pid, 0)
        stack.extend(children.get(pid, []))
    return total / 1024.0 / 1024.0


def max_logged_iteration(path):
    path = pathlib.Path(path)
    if not path.exists():
        return 0
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return 0
    values = [int(value) for value in re.findall(r"\[latent-path VB\] iter=(\d+)\b", text)]
    return max(values, default=0)


def memory_safe_parallel_jobs(
    max_parallel,
    available_gb,
    campaign_rss_gb,
    memory_reserve_gb,
    peak_per_fit_gb,
    calibration_ready,
    calibration_target,
):
    if calibration_ready and peak_per_fit_gb > 0:
        pre_campaign_available = available_gb + campaign_rss_gb
        safe = max(1, int((pre_campaign_available - memory_reserve_gb) // peak_per_fit_gb))
    elif calibration_ready:
        safe = max_parallel
    else:
        safe = max(1, calibration_target)
    limit = min(max_parallel, safe)
    if not calibration_ready:
        limit = min(limit, max(1, calibration_target))
    return safe, limit


def parse_cpu_list(value):
    values = []
    for token in str(value or "").split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            lower, upper = (int(part) for part in token.split("-", 1))
            if lower > upper:
                raise ValueError(f"Invalid CPU range: {token}")
            values.extend(range(lower, upper + 1))
        else:
            values.append(int(token))
    if len(values) != len(set(values)):
        raise ValueError("CPU lists must not contain duplicates")
    return values


def discover_physical_cpus():
    output = subprocess.check_output(
        ["lscpu", "-p=CPU,CORE,SOCKET,NODE,ONLINE"],
        universal_newlines=True,
    )
    allowed = set(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None
    first_thread = {}
    for line in output.splitlines():
        if not line or line.startswith("#"):
            continue
        cpu, core, socket, node, online = line.split(",")
        cpu = int(cpu)
        if online.strip().upper() != "Y" or (allowed is not None and cpu not in allowed):
            continue
        key = (int(socket), int(node), int(core))
        first_thread[key] = min(cpu, first_thread.get(key, cpu))
    if not first_thread:
        raise ValueError("No online physical CPUs are available to the scheduler")
    by_socket = {}
    for (socket, node, core), cpu in sorted(first_thread.items()):
        by_socket.setdefault((socket, node), []).append(cpu)
    ordered = []
    while any(by_socket.values()):
        for key in sorted(by_socket):
            if by_socket[key]:
                ordered.append(by_socket[key].pop(0))
    return ordered


def build_cpu_sets(cores, cpu_sets, threads_per_fit):
    if threads_per_fit < 1:
        raise ValueError("backend-threads must be positive")
    if cpu_sets:
        allocations = [parse_cpu_list(value) for value in cpu_sets.split(";") if value.strip()]
    else:
        cpu_ids = discover_physical_cpus() if str(cores).strip().lower() == "auto" else parse_cpu_list(cores)
        allocations = [
            cpu_ids[index:index + threads_per_fit]
            for index in range(0, len(cpu_ids), threads_per_fit)
        ]
        allocations = [allocation for allocation in allocations if len(allocation) == threads_per_fit]
    if not allocations or any(len(allocation) < threads_per_fit for allocation in allocations):
        raise ValueError("Insufficient CPU sets for the requested backend thread count")
    flat = [cpu for allocation in allocations for cpu in allocation]
    if len(flat) != len(set(flat)):
        raise ValueError("Scheduler CPU sets must be disjoint")
    cpu_count = os.cpu_count() or 1
    if any(cpu < 0 or cpu >= cpu_count for cpu in flat):
        raise ValueError(f"Scheduler CPU IDs must lie in [0, {cpu_count - 1}]")
    return allocations


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


def read_csv_rows(path):
    path = pathlib.Path(path)
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


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


def resolve_reference_feature_cache_root(path, output_root):
    if not str(path or "").strip():
        return ""
    return str(require_within(path, output_root, "Reference feature cache"))


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

        checkpoint_path = row.get("checkpoint_path", "").strip()
        checkpoint_resume = canonical_bool(
            row.get("checkpoint_resume_enabled", "false")
        ) == "true"
        if checkpoint_resume and not checkpoint_path:
            raise ValueError(
                f"Checkpoint resume is enabled without a path for {row['candidate_id']}"
            )
        if checkpoint_path:
            require_within(
                checkpoint_path,
                pathlib.Path(row["run_dir"]).resolve(),
                "Checkpoint path",
            )

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

        certificate_path = row.get(
            "warm_start_numerical_certificate", ""
        ).strip()
        certificate_hash = row.get(
            "warm_start_numerical_certificate_sha256", ""
        ).strip()
        if bool(certificate_path) != bool(certificate_hash):
            raise ValueError(
                "Numerical warm-start certificate path/hash must be supplied "
                f"together for {row['candidate_id']}"
            )
        if certificate_path:
            certificate_path = require_within(
                certificate_path,
                output_root,
                "Numerical warm-start certificate",
            )
            if not certificate_path.is_file():
                raise ValueError(
                    f"Numerical warm-start certificate is missing for {row['candidate_id']}"
                )
            if cached_sha256(certificate_path) != certificate_hash:
                raise ValueError(
                    "Numerical warm-start certificate hash changed for "
                    f"{row['candidate_id']}"
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


def checkpoint_valid(row):
    path_text = row.get("checkpoint_path", "").strip()
    if not path_text:
        return False
    path = pathlib.Path(path_text)
    hash_path = pathlib.Path(str(path) + ".sha256")
    if not path.is_file() or not hash_path.is_file():
        return False
    expected = hash_path.read_text(encoding="utf-8").strip().lower()
    return bool(expected) and sha256_file(path).lower() == expected


def checkpoint_resume_requested(row):
    return (
        is_true(row.get("checkpoint_resume_enabled", "false"))
        and checkpoint_valid(row)
    )


def reconcile_existing_candidate(row, output_root, previous, retry_failed=False):
    """Classify one manifest row before scheduling any work."""
    candidate_id = row["candidate_id"]
    state = {
        "candidate_id": candidate_id,
        "priority": row["priority"],
        "status": "excluded_from_failed_retry" if retry_failed else "pending",
        "core": "",
        "cpu_set": "",
        "numerical_backend": "",
        "backend_threads": "",
        "backend_manifest_path": "",
        "reference_feature_cache_root": "",
        "resume_checkpoint": "false",
        "pid": "",
        "started_at": "",
        "finished_at": "",
        "return_code": "",
        "run_id": row["run_id"],
        "log_path": row["log_path"],
    }
    marker = pathlib.Path(row["run_dir"]) / ".fit_recovery_complete"
    rejected_marker = pathlib.Path(row["run_dir"]) / ".reservoir_preflight_rejected"
    if marker.exists():
        state["status"] = "completed_existing"
        return state
    if rejected_marker.exists():
        state["status"] = "rejected_existing"
        return state

    worker = read_last_csv(pathlib.Path(output_root) / "status" / f"{candidate_id}.csv")
    pid = worker.get("pid", "") or previous.get("pid", "")
    if worker.get("status") == "running" and pid_alive(pid):
        prior_cpu_set = previous.get("cpu_set", "") or previous.get("core", "")
        state.update({
            "status": "running_external",
            "core": previous.get("core", ""),
            "cpu_set": prior_cpu_set,
            "numerical_backend": previous.get("numerical_backend", ""),
            "backend_threads": previous.get("backend_threads", ""),
            "backend_manifest_path": previous.get("backend_manifest_path", ""),
            "reference_feature_cache_root": previous.get(
                "reference_feature_cache_root", ""
            ),
            "pid": pid,
            "started_at": previous.get("started_at", ""),
        })
    elif worker.get("status") == "failed":
        if retry_failed:
            state["status"] = "pending"
        else:
            state.update({
                "status": "failed_existing",
                "pid": pid,
                "finished_at": worker.get("timestamp", ""),
                "return_code": worker.get("exit_code", ""),
            })
    elif checkpoint_resume_requested(row):
        state["status"] = "pending"
        state["resume_checkpoint"] = "true"
    return state


def main():
    args = parse_args()
    if args.calibration_jobs < 0:
        raise ValueError("calibration-jobs must be nonnegative")
    if args.calibration_iterations < 1:
        raise ValueError("calibration-iterations must be positive")
    if args.memory_reserve_gb < 0:
        raise ValueError("memory-reserve-gb must be nonnegative")
    repo_root = pathlib.Path(__file__).resolve().parents[2]
    output_root = pathlib.Path(args.output_root).resolve()
    reference_feature_cache_root = resolve_reference_feature_cache_root(
        args.reference_feature_cache_root,
        output_root,
    )
    manifest = read_manifest(args.manifest)
    cpu_sets = build_cpu_sets(args.cores, args.cpu_sets, args.backend_threads)
    if args.max_parallel > len(cpu_sets):
        raise ValueError("max-parallel exceeds the number of disjoint CPU sets")
    cores = [cpu for allocation in cpu_sets for cpu in allocation]
    validate_manifest(manifest, output_root, cores, args.max_parallel)
    if args.numerical_backend != "bundled_rblas":
        if not args.backend_library or not args.backend_sha256:
            raise ValueError("OpenBLAS scheduling requires --backend-library and --backend-sha256")
    output_root.mkdir(parents=True, exist_ok=True)
    (output_root / "logs").mkdir(exist_ok=True)
    state_path = pathlib.Path(args.state_file).resolve() if args.state_file else output_root / "scheduler_state.csv"
    require_within(state_path, output_root, "Scheduler state")
    memory_safety_path = (
        pathlib.Path(args.memory_safety_log).resolve()
        if args.memory_safety_log
        else output_root / "status" / "scheduler_memory_safety.csv"
    )
    require_within(memory_safety_path, output_root, "Memory-safety log")
    stop_path = output_root / "STOP"
    previous_states = {
        row["candidate_id"]: row
        for row in read_manifest(state_path)
    } if state_path.exists() else {}
    active = {}
    calibration_target = min(args.calibration_jobs, len(manifest))
    calibration_ids = [row["candidate_id"] for row in manifest[:calibration_target]]
    peak_rss_gb = {candidate_id: 0.0 for candidate_id in calibration_ids}
    resource_rows = read_csv_rows(memory_safety_path)
    states = {
        row["candidate_id"]: reconcile_existing_candidate(
            row,
            output_root,
            previous_states.get(row["candidate_id"], {}),
            retry_failed=args.retry_failed,
        )
        for row in manifest
    }

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
                resumable = checkpoint_resume_requested(row)
                state["status"] = "pending" if resumable else "failed_stale"
                state["resume_checkpoint"] = "true" if resumable else "false"
                state["finished_at"] = timestamp()
                state["return_code"] = "worker_pid_not_alive"

        active_rss = {}
        active_iterations = {}
        process_snapshot = process_tree_snapshot() if active else ({}, {})
        for candidate_id, item in active.items():
            rss = process_tree_rss_gb(item["process"].pid, process_snapshot)
            active_rss[candidate_id] = rss
            active_iterations[candidate_id] = max_logged_iteration(states[candidate_id]["log_path"])
            if candidate_id in peak_rss_gb:
                peak_rss_gb[candidate_id] = max(peak_rss_gb[candidate_id], rss)

        calibration_ready = calibration_target == 0
        if calibration_target:
            calibration_ready = all(
                states[candidate_id]["status"] in {
                    "completed", "completed_existing", "failed", "failed_existing",
                    "rejected", "rejected_existing",
                }
                or active_iterations.get(candidate_id, 0) >= args.calibration_iterations
                for candidate_id in calibration_ids
            )
        observed_peaks = [value for value in peak_rss_gb.values() if value > 0]
        peak_per_fit = max(observed_peaks, default=0.0)
        available_gb = available_memory_gb()
        campaign_rss_gb = sum(active_rss.values())
        memory_safe_jobs, current_parallel_limit = memory_safe_parallel_jobs(
            args.max_parallel,
            available_gb,
            campaign_rss_gb,
            args.memory_reserve_gb,
            peak_per_fit,
            calibration_ready,
            calibration_target,
        )
        resource_rows.append({
            "timestamp": timestamp(),
            "available_memory_gb": f"{available_gb:.6f}",
            "campaign_active_rss_gb": f"{campaign_rss_gb:.6f}",
            "calibration_jobs": str(calibration_target),
            "calibration_iterations": str(args.calibration_iterations),
            "calibration_ready": canonical_bool(calibration_ready),
            "measured_peak_rss_per_fit_gb": f"{peak_per_fit:.6f}",
            "memory_reserve_gb": f"{args.memory_reserve_gb:.6f}",
            "memory_safe_jobs": str(memory_safe_jobs),
            "parallel_limit": str(current_parallel_limit),
            "active_jobs": str(len(active)),
        })
        atomic_csv(memory_safety_path, resource_rows, list(resource_rows[0].keys()))

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
        memory_gb = available_gb
        disk_gb = shutil.disk_usage(output_root).free / (1024.0 ** 3)
        occupied_sets = {x["cpu_set"] for x in active.values()}
        occupied_sets.update(
            state["cpu_set"]
            for state in states.values()
            if state["status"] == "running_external" and state["cpu_set"]
        )
        free_cpu_sets = [
            allocation for allocation in cpu_sets
            if ",".join(str(cpu) for cpu in allocation) not in occupied_sets
        ]
        resources_ok = (
            load < args.max_load
            and memory_gb >= args.min_memory_gb
            and disk_gb >= args.min_disk_gb
        )
        while (
            pending
            and free_cpu_sets
            and len(active) + external_count < current_parallel_limit
            and resources_ok
        ):
            row = pending.pop(0)
            cpu_set = free_cpu_sets.pop(0)
            cpu_set_text = ",".join(str(cpu) for cpu in cpu_set)
            candidate_id = row["candidate_id"]
            log_path = pathlib.Path(row["log_path"])
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_handle = log_path.open("a", encoding="utf-8")
            backend_manifest_path = output_root / "status" / f"{candidate_id}_backend.json"
            command = [
                sys.executable,
                str(repo_root / "application/scripts/glofas_numerical_backend_exec.py"),
                "--backend", args.numerical_backend,
                "--threads", str(args.backend_threads),
                "--cpu-set", cpu_set_text,
                "--manifest", str(backend_manifest_path),
            ]
            if args.backend_library:
                command.extend(["--library", args.backend_library])
            if args.backend_sha256:
                command.extend(["--sha256", args.backend_sha256])
            command.extend([
                "--", "bash", str(repo_root / "application/scripts/glofas_fit_recovery_run_candidate.sh"),
                candidate_id, row["config_path"], row["run_id"], str(output_root),
            ])
            env = os.environ.copy()
            env.update({
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
                "QDESN_REFERENCE_FEATURE_CACHE_ROOT": reference_feature_cache_root,
                "QDESN_CHECKPOINT_RESUME": canonical_bool(
                    checkpoint_resume_requested(row)
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
                "core": str(cpu_set[0]),
                "cpu_set": cpu_set_text,
                "numerical_backend": args.numerical_backend,
                "backend_threads": str(args.backend_threads),
                "backend_manifest_path": str(backend_manifest_path),
                "reference_feature_cache_root": reference_feature_cache_root,
                "resume_checkpoint": canonical_bool(
                    checkpoint_resume_requested(row)
                ),
                "pid": str(process.pid),
                "started_at": timestamp(),
            })
            active[candidate_id] = {
                "process": process,
                "cpu_set": cpu_set_text,
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
