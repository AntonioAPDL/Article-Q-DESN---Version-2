#!/usr/bin/env python3
"""Launch or resume CPU-pinned Stage-R57 PriceFM joint VB cases."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import subprocess
import threading

import pandas as pd

from pricefm_common import parse_bool, write_json


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, required=True)
    p.add_argument("--runner", type=Path, required=True)
    p.add_argument("--cpu-list", required=True, help="Comma-separated logical CPU identifiers")
    p.add_argument("--workers", type=int, default=16)
    p.add_argument("--resume", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    p.add_argument("--case-limit", type=int, default=0)
    p.add_argument(
        "--stop-file", type=Path, default=None,
        help="Gracefully stop dispatching new cases when this sentinel exists",
    )
    return p


def parse_cpus(value: str) -> list[int]:
    cpus = [int(item.strip()) for item in value.split(",") if item.strip()]
    if not cpus or len(cpus) != len(set(cpus)) or any(cpu < 0 for cpu in cpus):
        raise ValueError("--cpu-list must contain unique nonnegative CPU identifiers")
    return cpus


def completed_summary(output_dir: Path) -> bool:
    path = output_dir / "job_summary.json"
    if not path.is_file():
        return False
    try:
        payload = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return False
    return payload.get("status") == "completed" and (output_dir / "metric_summary.csv").is_file()


def atomic_status(path: Path, rows: list[dict]) -> None:
    frame = pd.DataFrame(rows).sort_values(["region", "fold"]).reset_index(drop=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    frame.to_csv(tmp, index=False)
    os.replace(tmp, path)


def launch_one(row: dict, cpu: int, runner: Path, resume: bool, force: bool) -> dict:
    output = Path(row["output_dir"])
    if resume and completed_summary(output) and not force:
        return {**row, "cpu": cpu, "status": "skipped_completed", "returncode": 0}
    output.mkdir(parents=True, exist_ok=True)
    log_path = output / "worker.log"
    env = os.environ.copy()
    for name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS"):
        env[name] = "1"
    command = [
        "taskset", "-c", str(cpu), "Rscript", str(runner.resolve()),
        "--config", str(Path(row["config"]).resolve()),
        "--resume", str(bool(resume)).lower(),
        "--force", str(bool(force)).lower(),
    ]
    with log_path.open("a") as handle:
        handle.write("COMMAND " + " ".join(command) + "\n")
        handle.flush()
        proc = subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT, env=env, check=False)
    return {
        **row, "cpu": cpu,
        "status": "completed" if proc.returncode == 0 and completed_summary(output) else "failed",
        "returncode": int(proc.returncode), "worker_log": str(log_path),
    }


def launch_lane(
    rows: list[dict], cpu: int, runner: Path, resume: bool, force: bool,
    callback, stop_file: Path | None = None,
) -> list[dict]:
    results = []
    for index, row in enumerate(rows):
        if stop_file is not None and stop_file.is_file():
            for pending in rows[index:]:
                result = {
                    **pending, "cpu": cpu, "status": "not_launched_stop_requested",
                    "returncode": "", "worker_log": "",
                }
                results.append(result)
                callback(result)
            break
        result = launch_one(row, cpu, runner, resume, force)
        results.append(result)
        callback(result)
    return results


def run(args: argparse.Namespace) -> dict:
    cpus = parse_cpus(args.cpu_list)
    workers = min(int(args.workers), len(cpus))
    if workers < 1:
        raise ValueError("workers must be positive")
    manifest = pd.read_csv(args.manifest)
    required = {"case_id", "region", "fold", "config", "output_dir"}
    missing = sorted(required - set(manifest.columns))
    if missing:
        raise RuntimeError(f"Launch manifest missing columns: {missing}")
    if manifest.duplicated(["case_id"]).any():
        raise RuntimeError("Launch manifest case IDs must be unique")
    if args.case_limit > 0:
        manifest = manifest.head(args.case_limit)
    rows = manifest.to_dict("records")
    lanes = [[] for _ in range(workers)]
    for index, row in enumerate(rows):
        lanes[index % workers].append(row)
    status_path = args.manifest.parent / "launch_status.csv"
    summary_path = args.manifest.parent / "launch_summary.json"
    lock = threading.Lock()
    status_rows: dict[str, dict] = {}
    if status_path.is_file() and args.resume and not args.force:
        for row in pd.read_csv(status_path).to_dict("records"):
            status_rows[str(row["case_id"])] = row

    def record(result: dict) -> None:
        with lock:
            status_rows[str(result["case_id"])] = result
            atomic_status(status_path, list(status_rows.values()))
            statuses = [str(row["status"]) for row in status_rows.values()]
            write_json(summary_path, {
                "status": "running",
                "manifest_cases": len(rows),
                "reported_cases": len(statuses),
                "completed_or_skipped": sum(value in {"completed", "skipped_completed"} for value in statuses),
                "failed": sum(value == "failed" for value in statuses),
                "workers": workers,
                "cpu_ids": cpus[:workers],
                "registry_mutation_authorized": False,
                "article_mutation_authorized": False,
            })

    results = []
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [
            pool.submit(
                launch_lane, lane, cpus[index], args.runner, args.resume, args.force,
                record, args.stop_file,
            )
            for index, lane in enumerate(lanes) if lane
        ]
        for future in as_completed(futures):
            results.extend(future.result())
    failed = sum(row["status"] == "failed" for row in results)
    not_launched = sum(row["status"] == "not_launched_stop_requested" for row in results)
    summary = {
        "status": (
            "completed" if failed == 0 and not_launched == 0 and len(results) == len(rows)
            else "stopped_before_completion" if not_launched > 0 and failed == 0
            else "completed_with_failures"
        ),
        "manifest_cases": len(rows),
        "completed_or_skipped": sum(row["status"] in {"completed", "skipped_completed"} for row in results),
        "failed": failed,
        "not_launched_stop_requested": not_launched,
        "workers": workers,
        "cpu_ids": cpus[:workers],
        "one_process_per_cpu": True,
        "numerical_threads_per_process": 1,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    write_json(summary_path, summary)
    if failed:
        raise RuntimeError(f"Stage-R57 completed with {failed} failed cases")
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
