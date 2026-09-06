#!/usr/bin/env python3
"""Launch/resume the gated Stage-R72 missing-only AL repair campaign."""

from __future__ import annotations

import argparse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import threading
import time
from typing import Any

import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r72_missing_al_repair_20260901"
GRID = DATA / "experiment_grids" / TAG
MANIFEST = GRID / "task_manifest.csv"
GATE = DATA / "authoritative/pricefm_stage_r72_rhs_schedule_gate_20260901/summary.json"
PYTHON = DATA / "venv/bin/python"
BINARY_SUFFIXES = {".rds", ".rda", ".RData", ".rdata"}
BLOCKED = (
    "test_access_authorized", "registry_mutation_authorized",
    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
)


def parse_bool(value: str | bool) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).lower() in {"true", "1", "yes"}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--gate-summary", type=Path, default=GATE)
    p.add_argument("--workers", type=int, default=20)
    p.add_argument("--cpu-list", default="")
    p.add_argument("--expected-tasks", type=int, default=142)
    p.add_argument("--minimum-free-gib", type=float, default=50.0)
    p.add_argument("--minimum-available-memory-gib", type=float, default=40.0)
    p.add_argument("--authorize", type=parse_bool, default=False)
    p.add_argument("--preflight-only", type=parse_bool, default=False)
    return p


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"true", "1", "yes", "y"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


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
    for token in str(value).split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            low, high = token.split("-", 1)
            cpus.extend(range(int(low), int(high) + 1))
        else:
            cpus.append(int(token))
    if not cpus or len(cpus) != len(set(cpus)):
        raise ValueError("CPU list must contain unique logical CPU IDs")
    if not set(cpus).issubset(set(range(os.cpu_count() or 0))):
        raise ValueError("CPU list contains offline/out-of-range IDs")
    return cpus


def available_memory_gib() -> float:
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0])
    return values["MemAvailable"] / 1024**2


def cpu_usage_snapshot() -> dict[int, float]:
    result = subprocess.run(
        ["ps", "-e", "-o", "psr=,pcpu="], text=True, capture_output=True, check=False
    )
    usage = {cpu: 0.0 for cpu in range(os.cpu_count() or 0)}
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) != 2:
            continue
        try:
            cpu, percent = int(fields[0]), float(fields[1])
        except ValueError:
            continue
        if cpu in usage:
            usage[cpu] += percent
    return usage


def least_busy_cpus(count: int, maximum_snapshot_percent: float = 25.0) -> list[int]:
    usage = cpu_usage_snapshot()
    idle = [cpu for cpu, value in sorted(usage.items(), key=lambda item: (item[1], item[0])) if value <= maximum_snapshot_percent]
    if len(idle) < count:
        raise RuntimeError(f"Only {len(idle)} CPUs meet the <= {maximum_snapshot_percent}% snapshot gate")
    return idle[:count]


def completion_state(output: Path) -> str | None:
    terminal_path = output / "terminal.json"
    if not terminal_path.is_file():
        return None
    terminal = json.loads(terminal_path.read_text())
    if terminal.get("status") != "completed" or terminal.get("test_loaded") is not False:
        return None
    hashes = terminal.get("artifact_sha256") or {}
    if not hashes:
        return None
    for name, expected in hashes.items():
        path = output / name
        if not path.is_file() or sha256(path) != expected:
            return None
    if any(path.suffix in BINARY_SUFFIXES for path in output.rglob("*") if path.is_file()):
        return None
    return "completed"


def preflight(manifest: pd.DataFrame, args: argparse.Namespace, cpus: list[int]) -> dict[str, Any]:
    if not args.authorize:
        raise RuntimeError("R72 production launch requires --authorize true")
    gate = json.loads(args.gate_summary.read_text())
    if gate.get("al_repair_launch_gate_passed") is not True or gate.get("exal_launch_gate_passed") is not False:
        raise RuntimeError("R72 AL-only mechanism gate is not in the required state")
    if len(manifest) != args.expected_tasks or manifest.task_id.duplicated().any():
        raise RuntimeError("R72 task count/identity contract failed")
    if set(manifest.likelihood_family) != {"al"}:
        raise RuntimeError("R72 production manifest must be AL-only")
    selected_init = float(gate["selected_rhs_init_tau"])
    selected_freeze = int(gate["selected_rhs_freeze_iters"])
    if not (
        pd.to_numeric(manifest.rhs_init_tau).eq(selected_init).all()
        and pd.to_numeric(manifest.rhs_freeze_tau_iters).eq(selected_freeze).all()
    ):
        raise RuntimeError("R72 manifest does not match the selected RHS schedule gate")
    for name in BLOCKED:
        if manifest[name].map(boolish).any():
            raise RuntimeError(f"R72 manifest authorizes forbidden action: {name}")
    if args.workers < 1 or len(cpus) < args.workers:
        raise RuntimeError("R72 needs one unique logical CPU per worker")
    for row in manifest.itertuples(index=False):
        task = Path(row.task_config)
        if not task.is_file() or sha256(task) != row.task_config_sha256:
            raise RuntimeError(f"R72 task config hash mismatch: {row.task_id}")
        payload = json.loads(task.read_text())
        if payload.get("selection_split") != "val" or payload.get("likelihood_family") != "al":
            raise RuntimeError(f"R72 task firewall mismatch: {row.task_id}")
    free = shutil.disk_usage(DATA).free / 1024**3
    memory = available_memory_gib()
    if free < args.minimum_free_gib or memory < args.minimum_available_memory_gib:
        raise RuntimeError(f"R72 resource gate failed: free={free:.1f} GiB memory={memory:.1f} GiB")
    return {
        "tasks": int(len(manifest)), "workers": args.workers,
        "cpu_ids": cpus[:args.workers], "one_process_per_cpu": True,
        "threads_per_process": 1, "free_disk_gib": round(free, 3),
        "available_memory_gib": round(memory, 3),
        "al_gate_passed": True, "exal_blocked": True,
        "test_access": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }


def run_one(row: dict[str, Any], cpu: int, code_root: Path) -> dict[str, Any]:
    output = Path(row["output_dir"])
    output.mkdir(parents=True, exist_ok=True)
    log = output / "worker.log"
    if completion_state(output):
        return {**row, "cpu": cpu, "status": "skipped_completed", "returncode": 0,
                "elapsed_seconds": 0.0, "worker_log": str(log)}
    env = dict(os.environ)
    for key in (
        "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS",
        "RCPP_PARALLEL_NUM_THREADS", "BLIS_NUM_THREADS",
    ):
        env[key] = "1"
    command = [
        "taskset", "-c", str(cpu), "Rscript",
        str(code_root / "application/scripts/pricefm/243_run_pricefm_stage_r72_repair_component.R"),
        "--task-config", row["task_config"],
    ]
    started = time.time()
    with log.open("a") as handle:
        handle.write(f"START stage=R72 task={row['task_id']} cpu={cpu} time={started}\n")
        handle.write("COMMAND " + " ".join(command) + "\n")
        handle.flush()
        result = subprocess.run(command, cwd=code_root, env=env, stdout=handle, stderr=subprocess.STDOUT)
        handle.write(f"END returncode={result.returncode} time={time.time()}\n")
    state = completion_state(output)
    return {
        **row, "cpu": cpu, "status": state or "failed",
        "returncode": int(result.returncode), "elapsed_seconds": round(time.time() - started, 3),
        "worker_log": str(log),
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = pd.read_csv(args.manifest)
    cpus = parse_cpus(args.cpu_list) if args.cpu_list else least_busy_cpus(args.workers)
    audit = preflight(manifest, args, cpus)
    write_json(args.manifest.parent / "launch_preflight.json", audit)
    if args.preflight_only:
        return {"status": "preflight_passed_not_launched", **audit}
    rows = manifest.to_dict("records")
    status_rows: list[dict[str, Any]] = []
    lock = threading.Lock()
    pool = ThreadPoolExecutor(max_workers=args.workers)
    pending = {}
    iterator = iter(rows)

    def submit(cpu: int) -> bool:
        try:
            row = next(iterator)
        except StopIteration:
            return False
        pending[pool.submit(run_one, row, cpu, args.code_root.resolve())] = cpu
        return True

    for cpu in cpus[:args.workers]:
        submit(cpu)
    try:
        while pending:
            done, _ = wait(pending, return_when=FIRST_COMPLETED)
            for future in done:
                cpu = pending.pop(future)
                try:
                    result = future.result()
                except Exception as error:
                    result = {"task_id": "launcher_exception", "cpu": cpu, "status": "launcher_exception",
                              "returncode": 1, "error": repr(error)}
                with lock:
                    status_rows.append(result)
                    write_csv(args.manifest.parent / "launch_status.csv", pd.DataFrame(status_rows))
                submit(cpu)
    finally:
        pool.shutdown(wait=True)
    status = pd.DataFrame(status_rows)
    completed = int(status.status.isin(("completed", "skipped_completed")).sum())
    summary = {
        "status": "completed" if completed == len(manifest) else "completed_with_failures",
        "tasks": int(len(manifest)), "completed": completed,
        "failed": int(len(manifest) - completed), "workers": args.workers,
        "cpu_ids": cpus[:args.workers], "test_opened": False,
        "registry_mutated": False, "article_mutated": False,
    }
    write_json(args.manifest.parent / "launch_summary.json", summary)
    return summary


def main() -> int:
    result = run(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result.get("status") in {"preflight_passed_not_launched", "completed"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
