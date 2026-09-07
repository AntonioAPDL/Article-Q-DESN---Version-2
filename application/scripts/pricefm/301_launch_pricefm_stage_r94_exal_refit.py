#!/usr/bin/env python3
"""Preflight or explicitly launch the atomic R94 exAL initialization repair."""

from __future__ import annotations

import argparse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time
from typing import Any

import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_region_frozen_contract import (
    binary_artifacts,
    quarantine_path,
    validate_git_identity,
    validate_no_test_adapter,
)


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r94_coherent_exal_refit_20260906"
MANIFEST = DATA / "experiment_grids" / TAG / "task_manifest.csv"
AUDIT = DATA / "authoritative/pricefm_stage_r94_exal_initialization_audit_20260906/summary.json"
APPROVAL_TOKEN = "RUN_PRICEFM_R94_COHERENT_EXAL_REFIT"
BINARY_SUFFIXES = {".rds", ".rda", ".RData", ".rdata"}
BLOCKED = (
    "test_access_authorized", "registry_mutation_authorized",
    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--audit-summary", type=Path, default=AUDIT)
    p.add_argument("--workers", type=int, default=7)
    p.add_argument("--cpu-list", default="")
    p.add_argument("--minimum-free-gib", type=float, default=40.0)
    p.add_argument("--minimum-available-memory-gib", type=float, default=20.0)
    p.add_argument("--maximum-cpu-snapshot-percent", type=float, default=20.0)
    p.add_argument("--preflight-only", action="store_true")
    p.add_argument("--approval-token", default="")
    p.add_argument("--poll-seconds", type=float, default=15.0)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"true", "1", "yes", "y"}


def write_json(path: Path, payload: Any) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def write_csv(path: Path, frame: pd.DataFrame) -> None:
    tmp = path.with_name(path.name + ".tmp")
    frame.to_csv(tmp, index=False)
    tmp.replace(path)


def parse_cpus(value: str) -> list[int]:
    cpus: list[int] = []
    for token in value.split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            low, high = map(int, token.split("-", 1))
            cpus.extend(range(low, high + 1))
        else:
            cpus.append(int(token))
    if not cpus or len(cpus) != len(set(cpus)):
        raise RuntimeError("CPU list must contain unique logical CPU IDs")
    if not set(cpus).issubset(set(range(os.cpu_count() or 0))):
        raise RuntimeError("CPU list contains an offline or out-of-range ID")
    return cpus


def available_memory_gib() -> float:
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0])
    return values["MemAvailable"] / 1024**2


def cpu_snapshot(interval: float = 0.75) -> dict[int, float]:
    def read() -> dict[int, tuple[int, int]]:
        result = {}
        for line in Path("/proc/stat").read_text().splitlines():
            fields = line.split()
            if not fields or not fields[0].startswith("cpu") or not fields[0][3:].isdigit():
                continue
            ticks = [int(value) for value in fields[1:]]
            result[int(fields[0][3:])] = (sum(ticks), ticks[3] + (ticks[4] if len(ticks) > 4 else 0))
        return result
    before = read()
    time.sleep(interval)
    after = read()
    return {
        cpu: 100 * (1 - (after[cpu][1] - idle) / (after[cpu][0] - total))
        for cpu, (total, idle) in before.items()
        if cpu in after and after[cpu][0] > total
    }


def least_busy_cpus(count: int, maximum: float) -> list[int]:
    usage = cpu_snapshot()
    eligible = [cpu for cpu, value in sorted(usage.items(), key=lambda item: (item[1], item[0])) if value <= maximum]
    if len(eligible) < count:
        raise RuntimeError(f"Only {len(eligible)} CPUs satisfy the <= {maximum}% snapshot gate")
    return eligible[:count]


def completion_state(output: Path, task: dict[str, Any] | None = None) -> str | None:
    terminal_path = output / "terminal.json"
    if not terminal_path.is_file():
        return None
    terminal = json.loads(terminal_path.read_text())
    status = terminal.get("status")
    if (
        status not in {"completed", "completed_numerically_ineligible"}
        or terminal.get("test_loaded") is not False
        or terminal.get("test_opened") is not False
        or terminal.get("test_access_authorized") is not False
    ):
        return None
    if task is not None and (
        terminal.get("task_id") != task.get("task_id")
        or terminal.get("pipeline_contract_sha256") != task.get("pipeline_contract_sha256")
    ):
        return None
    hashes = terminal.get("artifact_sha256") or {}
    if not hashes:
        return None
    for name, expected in hashes.items():
        path = output / name
        if not path.is_file() or sha256(path) != expected:
            return None
    if binary_artifacts(output):
        return None
    if status == "completed" and terminal.get("numerical_gate_passed") is not True:
        return None
    if status == "completed_numerically_ineligible" and terminal.get("numerical_gate_passed") is not False:
        return None
    return str(status)


def preflight(manifest: pd.DataFrame, args: argparse.Namespace, cpus: list[int]) -> dict[str, Any]:
    audit = json.loads(args.audit_summary.read_text())
    if (
        audit.get("production_refit_preparation_authorized") is not True
        or audit.get("test_opened") is not False
        or audit.get("test_access_authorized") is not False
    ):
        raise RuntimeError("R94 audit does not authorize production refit preparation")
    control_path = args.manifest.parent / "launch_control.json"
    if not control_path.is_file():
        raise FileNotFoundError(control_path)
    control = json.loads(control_path.read_text())
    git = validate_git_identity(args.code_root, control["git_identity"], require_clean=True)
    if (
        len(manifest) != 7
        or manifest.task_id.duplicated().any()
        or set(manifest.tau.astype(float)) != {0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90}
        or not manifest.stage.eq("R94").all()
        or not manifest.likelihood_family.eq("exal").all()
    ):
        raise RuntimeError("R94 manifest must contain exactly seven unique exAL atoms")
    for name in BLOCKED:
        if manifest[name].map(boolish).any():
            raise RuntimeError(f"R94 manifest authorizes forbidden action: {name}")
    if manifest.launch_authorized.map(boolish).any():
        raise RuntimeError("R94 prep may not authorize its own launch")
    if args.workers < 1 or args.workers > 7 or len(cpus) < args.workers:
        raise RuntimeError("R94 requires between one and seven unique worker CPUs")
    for row in manifest.itertuples(index=False):
        task_path = Path(row.task_config)
        if not task_path.is_file() or sha256(task_path) != str(row.task_config_sha256):
            raise RuntimeError(f"Changed R94 task: {row.task_id}")
        task = json.loads(task_path.read_text())
        if (
            task.get("stage") != "R94"
            or task.get("selection_split") != "val"
            or task.get("likelihood_family") != "exal"
            or task.get("warm_start_mode") != "al_qbeta_rhs_latent_first"
            or task.get("launch_authorized") is not False
            or task.get("test_opened") is not False
            or any(task.get(name) is not False for name in BLOCKED)
        ):
            raise RuntimeError(f"R94 task firewall mismatch: {row.task_id}")
        for name, hash_name in (
            ("source_r93_task", "source_r93_task_sha256"),
            ("runtime_manifest", "runtime_manifest_sha256"),
            ("audit_summary", "audit_summary_sha256"),
            ("al_beta_path", "al_beta_sha256"),
            ("al_parameter_path", "al_parameter_sha256"),
            ("al_prediction_path", "al_prediction_sha256"),
            ("al_source_terminal", "al_source_terminal_sha256"),
            ("runner_script", "runner_script_sha256"),
        ):
            if sha256(Path(task[name])) != task[hash_name]:
                raise RuntimeError(f"Changed R94 source: {task[name]}")
        for record in task.get("adapter_files") or []:
            path = Path(record["path"])
            if not path.is_file() or sha256(path) != str(record["sha256"]):
                raise RuntimeError(f"Changed R94 adapter input: {path}")
        if len(task.get("adapter_files") or []) < 9:
            raise RuntimeError(f"R94 adapter provenance is incomplete: {row.task_id}")
        for record in task.get("adapter_scripts") or []:
            path = Path(record["path"])
            if not path.is_file() or sha256(path) != str(record["sha256"]):
                raise RuntimeError(f"Changed R94 adapter script: {path}")
        if len(task.get("adapter_scripts") or []) != 3:
            raise RuntimeError(f"R94 adapter-script provenance is incomplete: {row.task_id}")
        adapter = Path(task["adapter_dir"])
        validate_no_test_adapter(adapter)
    free = shutil.disk_usage(args.manifest.parent).free / 1024**3
    memory = available_memory_gib()
    if free < args.minimum_free_gib or memory < args.minimum_available_memory_gib:
        raise RuntimeError(f"R94 resource gate failed: disk={free:.1f} GiB memory={memory:.1f} GiB")
    return {
        "tasks": 7,
        "workers": args.workers,
        "cpu_ids": cpus[: args.workers],
        "one_process_per_cpu": True,
        "threads_per_process": 1,
        "free_disk_gib": round(free, 3),
        "available_memory_gib": round(memory, 3),
        "git_identity": git.to_dict(),
        "pipeline_contract_sha256": str(manifest.pipeline_contract_sha256.iloc[0]),
        "test_opened": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }


def process_observation(pid: int) -> dict[str, Any]:
    stat = Path(f"/proc/{pid}/stat")
    status = Path(f"/proc/{pid}/status")
    if not stat.is_file():
        return {"process_alive": False}
    fields = stat.read_text().split()
    rss_kib = None
    if status.is_file():
        for line in status.read_text().splitlines():
            if line.startswith("VmRSS:"):
                rss_kib = int(line.split()[1])
                break
    return {
        "process_alive": True,
        "cpu_time_ticks": int(fields[13]) + int(fields[14]),
        "resident_memory_kib": rss_kib,
    }


def run_one(
    row: dict[str, Any], cpu: int, code_root: Path,
    update_state, poll_seconds: float,
) -> dict[str, Any]:
    output = Path(row["output_dir"])
    task = json.loads(Path(row["task_config"]).read_text())
    prior_state = completion_state(output, task)
    if prior_state:
        skipped = "skipped_completed" if prior_state == "completed" else "skipped_numerically_ineligible"
        update_state(row["task_id"], {
            "status": skipped, "cpu": cpu, "pid": None,
            "process_alive": False, "elapsed_seconds": 0.0,
        })
        return {**row, "cpu": cpu, "status": skipped, "returncode": 0, "elapsed_seconds": 0.0}
    if output.exists() and any(output.iterdir()):
        quarantine = quarantine_path(
            output, output.parents[3] / "quarantine",
            f"invalid_partial_{row['task_id']}",
        )
    else:
        quarantine = None
    output.mkdir(parents=True, exist_ok=True)
    log = output / "worker.log"
    env = dict(os.environ)
    for name in (
        "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS",
        "BLIS_NUM_THREADS",
    ):
        env[name] = "1"
    command = [
        "taskset", "-c", str(cpu), "Rscript", str(code_root / "application/scripts/pricefm/299_run_pricefm_stage_r94_exal_component.R"),
        "--task-config", row["task_config"], "--code-root", str(code_root),
    ]
    started = time.time()
    with log.open("a") as handle:
        handle.write(f"START task={row['task_id']} cpu={cpu} time={started}\n")
        process = subprocess.Popen(command, cwd=code_root, env=env, stdout=handle, stderr=subprocess.STDOUT)
        update_state(row["task_id"], {
            "status": "running", "cpu": cpu, "pid": process.pid,
            "started_at_epoch": started, "elapsed_seconds": 0.0,
            "worker_log": str(log), **process_observation(process.pid),
        })
        while process.poll() is None:
            time.sleep(max(0.1, poll_seconds))
            log_stat = log.stat()
            update_state(row["task_id"], {
                "status": "running", "cpu": cpu, "pid": process.pid,
                "elapsed_seconds": round(time.time() - started, 3),
                "worker_log_bytes": log_stat.st_size,
                "worker_log_mtime": log_stat.st_mtime,
                **process_observation(process.pid),
            })
        handle.write(f"END returncode={process.returncode} time={time.time()}\n")
    status = completion_state(output, task) or "failed"
    update_state(row["task_id"], {
        "status": status, "cpu": cpu, "pid": process.pid,
        "process_alive": False, "returncode": int(process.returncode),
        "elapsed_seconds": round(time.time() - started, 3),
    })
    return {
        **row,
        "cpu": cpu,
        "status": status,
        "returncode": int(process.returncode),
        "elapsed_seconds": round(time.time() - started, 3),
        "worker_log": str(log),
        "quarantined_partial": str(quarantine) if quarantine else None,
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = pd.read_csv(args.manifest).sort_values("tau")
    cpus = parse_cpus(args.cpu_list) if args.cpu_list else least_busy_cpus(args.workers, args.maximum_cpu_snapshot_percent)
    audit = preflight(manifest, args, cpus)
    write_json(args.manifest.parent / "launch_preflight.json", audit)
    if args.preflight_only:
        return {"status": "preflight_passed_not_launched", **audit}
    if args.approval_token != APPROVAL_TOKEN:
        raise RuntimeError(f"R94 launch requires --approval-token {APPROVAL_TOKEN}")
    lock_path = args.manifest.parent / "launcher.lock"
    lock_handle = lock_path.open("a+")
    try:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        lock_handle.close()
        raise RuntimeError("another R94 launcher owns this manifest") from error
    rows = iter(manifest.to_dict("records"))
    statuses: list[dict[str, Any]] = []
    pending: dict[Any, int] = {}
    state_lock = threading.Lock()
    task_state = {
        str(row.task_id): {
            "status": "queued", "tau": float(row.tau), "cpu": None, "pid": None,
        }
        for row in manifest.itertuples(index=False)
    }

    def update_state(task_id: str, updates: dict[str, Any]) -> None:
        with state_lock:
            task_state[task_id].update(updates)
            counts = pd.Series([item["status"] for item in task_state.values()]).value_counts().to_dict()
            write_json(args.manifest.parent / "scheduler_state.json", {
                "stage": "R94", "launcher_pid": os.getpid(), "updated_at_epoch": time.time(),
                "counts": {str(key): int(value) for key, value in counts.items()},
                "tasks": task_state, "test_opened": False,
                "test_access_authorized": False,
            })

    update_state(next(iter(task_state)), {})
    try:
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            def submit(cpu: int) -> None:
                try:
                    row = next(rows)
                except StopIteration:
                    return
                pending[pool.submit(
                    run_one, row, cpu, args.code_root.resolve(), update_state, args.poll_seconds
                )] = (cpu, str(row["task_id"]))

            for cpu in cpus[: args.workers]:
                submit(cpu)
            while pending:
                done, _ = wait(pending, return_when=FIRST_COMPLETED)
                for future in done:
                    cpu, task_id = pending.pop(future)
                    try:
                        statuses.append(future.result())
                    except Exception as error:
                        statuses.append({
                            "task_id": task_id, "cpu": cpu, "status": "failed",
                            "error": repr(error),
                        })
                        update_state(task_id, {"status": "failed", "error": repr(error)})
                    write_csv(args.manifest.parent / "launch_status.csv", pd.DataFrame(statuses))
                    submit(cpu)
    finally:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
        lock_handle.close()
    frame = pd.DataFrame(statuses)
    completed = int(frame.status.isin(("completed", "skipped_completed")).sum())
    ineligible = int(frame.status.isin((
        "completed_numerically_ineligible", "skipped_numerically_ineligible",
    )).sum())
    terminal = completed + ineligible
    summary = {
        "status": (
            "completed" if completed == 7 else
            "completed_with_numerically_ineligible_atoms" if terminal == 7 else
            "completed_with_failures"
        ),
        "tasks": 7,
        "completed": completed,
        "numerically_ineligible": ineligible,
        "terminal": terminal,
        "failed": 7 - terminal,
        "workers": args.workers,
        "cpu_ids": cpus[: args.workers],
        "test_opened": False,
        "test_access_authorized": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    write_json(args.manifest.parent / "launch_summary.json", summary)
    return summary


def main() -> int:
    result = run(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] in {
        "preflight_passed_not_launched", "completed",
        "completed_with_numerically_ineligible_atoms",
    } else 1


if __name__ == "__main__":
    raise SystemExit(main())
