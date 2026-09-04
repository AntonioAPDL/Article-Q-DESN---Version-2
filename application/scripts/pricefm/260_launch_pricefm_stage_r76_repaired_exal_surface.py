#!/usr/bin/env python3
"""Launch or resume the gated atomic R76 repaired-exAL surface."""

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
TAG = "pricefm_stage_r76_repaired_exal_surface_20260902"
GRID = DATA / "experiment_grids" / TAG
MANIFEST = GRID / "task_manifest.csv"
GATE = DATA / "authoritative/pricefm_stage_r75b_large_n_gig_stability_gate_20260902/summary.json"
BINARY_SUFFIXES = {".rds", ".rda", ".RData", ".rdata"}
BLOCKED = (
    "test_access_authorized", "registry_mutation_authorized",
    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--gate-summary", type=Path, default=GATE)
    p.add_argument("--workers", type=int, default=20)
    p.add_argument("--cpu-list", default="")
    p.add_argument("--expected-tasks", type=int, default=294)
    p.add_argument("--minimum-free-gib", type=float, default=40.0)
    p.add_argument("--minimum-available-memory-gib", type=float, default=30.0)
    p.add_argument("--maximum-cpu-snapshot-percent", type=float, default=25.0)
    p.add_argument("--authorize", action="store_true")
    p.add_argument("--preflight-only", action="store_true")
    return p


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


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"true", "1", "yes", "y"}


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


def cpu_snapshot() -> dict[int, float]:
    usage = {cpu: 0.0 for cpu in range(os.cpu_count() or 0)}
    result = subprocess.run(
        ["ps", "-e", "-o", "psr=,pcpu="], text=True, capture_output=True, check=False
    )
    for line in result.stdout.splitlines():
        try:
            cpu, percent = line.split()
            usage[int(cpu)] += float(percent)
        except (ValueError, KeyError):
            continue
    return usage


def least_busy_cpus(count: int, maximum: float) -> list[int]:
    usage = cpu_snapshot()
    eligible = [cpu for cpu, value in sorted(usage.items(), key=lambda item: (item[1], item[0])) if value <= maximum]
    if len(eligible) < count:
        raise RuntimeError(f"Only {len(eligible)} CPUs satisfy the <= {maximum}% snapshot gate")
    return eligible[:count]


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
    gate = json.loads(args.gate_summary.read_text())
    if gate.get("r76_broad_launch_authorized") is not True or gate.get("test_opened") is not False:
        raise RuntimeError("R75B does not authorize the R76 broad launch")
    if len(manifest) != args.expected_tasks or manifest.task_id.duplicated().any():
        raise RuntimeError("R76 task count or identity contract failed")
    if manifest.case_id.nunique() != 42 or not manifest.groupby("case_id").tau.nunique().eq(7).all():
        raise RuntimeError("R76 must contain 42 complete seven-quantile cases")
    if not manifest.likelihood_family.eq("exal").all() or not manifest.selected_family_anchor.eq("exal").all():
        raise RuntimeError("R76 manifest must be exAL-only and exAL-anchor-only")
    for name in BLOCKED:
        if manifest[name].map(boolish).any():
            raise RuntimeError(f"R76 manifest authorizes forbidden action: {name}")
    if args.workers < 1 or len(cpus) < args.workers:
        raise RuntimeError("R76 requires one unique CPU per worker")
    for row in manifest.itertuples(index=False):
        task_path = Path(row.task_config)
        if not task_path.is_file() or sha256(task_path) != str(row.task_config_sha256):
            raise RuntimeError(f"Changed R76 task config: {row.task_id}")
        task = json.loads(task_path.read_text())
        if task.get("stage") != "R76" or task.get("selection_split") != "val":
            raise RuntimeError(f"R76 task firewall mismatch: {row.task_id}")
        for name, expected in (
            ("runtime_manifest", task["runtime_manifest_sha256"]),
            ("source_case_config", task["source_case_config_sha256"]),
            ("al_beta_path", task["al_beta_sha256"]),
            ("al_parameter_path", task["al_parameter_sha256"]),
            ("al_source_terminal", task["al_source_terminal_sha256"]),
        ):
            if sha256(Path(task[name])) != expected:
                raise RuntimeError(f"Changed R76 source: {task[name]}")
        adapter = Path(task["adapter_dir"])
        if any((adapter / name).exists() for name in ("X_test.csv", "y_test.csv", "rows_test.csv")):
            raise RuntimeError(f"R76 adapter contains test data: {adapter}")
    free = shutil.disk_usage(DATA).free / 1024**3
    memory = available_memory_gib()
    if free < args.minimum_free_gib or memory < args.minimum_available_memory_gib:
        raise RuntimeError(f"R76 resource gate failed: disk={free:.1f} GiB memory={memory:.1f} GiB")
    return {
        "tasks": int(len(manifest)), "cases": int(manifest.case_id.nunique()),
        "workers": int(args.workers), "cpu_ids": cpus[:args.workers],
        "one_process_per_cpu": True, "threads_per_process": 1,
        "free_disk_gib": round(free, 3), "available_memory_gib": round(memory, 3),
        "stability_gate_passed": True, "test_opened": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
    }


def run_one(row: dict[str, Any], cpu: int, code_root: Path) -> dict[str, Any]:
    output = Path(row["output_dir"])
    output.mkdir(parents=True, exist_ok=True)
    log = output / "worker.log"
    if completion_state(output):
        return {**row, "cpu": cpu, "status": "skipped_completed", "returncode": 0,
                "elapsed_seconds": 0.0, "worker_log": str(log)}
    env = dict(os.environ)
    for name in (
        "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS",
        "BLIS_NUM_THREADS",
    ):
        env[name] = "1"
    command = [
        "taskset", "-c", str(cpu), "Rscript",
        str(code_root / "application/scripts/pricefm/259_run_pricefm_stage_r76_repaired_exal_component.R"),
        "--task-config", row["task_config"], "--code-root", str(code_root),
    ]
    started = time.time()
    with log.open("a") as handle:
        handle.write(
            f"START stage={row.get('stage', 'R76')} task={row['task_id']} "
            f"cpu={cpu} time={started}\n"
        )
        handle.write("COMMAND " + " ".join(command) + "\n")
        handle.flush()
        result = subprocess.run(command, cwd=code_root, env=env, stdout=handle, stderr=subprocess.STDOUT)
        handle.write(f"END returncode={result.returncode} time={time.time()}\n")
    state = completion_state(output)
    return {**row, "cpu": cpu, "status": state or "failed", "returncode": int(result.returncode),
            "elapsed_seconds": round(time.time() - started, 3), "worker_log": str(log)}


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = pd.read_csv(args.manifest).sort_values(["region", "fold", "tau"])
    cpus = parse_cpus(args.cpu_list) if args.cpu_list else least_busy_cpus(
        args.workers, args.maximum_cpu_snapshot_percent
    )
    audit = preflight(manifest, args, cpus)
    write_json(args.manifest.parent / "launch_preflight.json", audit)
    if args.preflight_only:
        return {"status": "preflight_passed_not_launched", **audit}
    if not args.authorize:
        raise RuntimeError("R76 launch requires explicit --authorize")
    rows = manifest.to_dict("records")
    statuses: list[dict[str, Any]] = []
    lock = threading.Lock()
    pool = ThreadPoolExecutor(max_workers=args.workers)
    pending: dict[Any, int] = {}
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
                    result = {"task_id": "launcher_exception", "cpu": cpu,
                              "status": "launcher_exception", "returncode": 1,
                              "error": repr(error)}
                with lock:
                    statuses.append(result)
                    frame = pd.DataFrame(statuses)
                    sort = [name for name in ("region", "fold", "tau") if name in frame]
                    write_csv(args.manifest.parent / "launch_status.csv", frame.sort_values(sort) if sort else frame)
                submit(cpu)
    finally:
        pool.shutdown(wait=True)
    frame = pd.DataFrame(statuses)
    completed = int(frame.status.isin(("completed", "skipped_completed")).sum())
    summary = {
        "status": "completed" if completed == len(manifest) else "completed_with_failures",
        "tasks": int(len(manifest)), "completed": completed,
        "failed": int(len(manifest) - completed), "workers": int(args.workers),
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
