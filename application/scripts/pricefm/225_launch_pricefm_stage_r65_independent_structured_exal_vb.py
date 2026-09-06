#!/usr/bin/env python3
"""Launch the explicitly authorized R65 case-grouped VB campaign."""

from __future__ import annotations

import argparse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
import json
import os
from pathlib import Path
import shutil
import subprocess
import threading
import time

import pandas as pd

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r65_independent_structured_exal_vb_20260829"
MANIFEST = DATA / "experiment_grids" / TAG / "case_manifest.csv"
PYTHON = DATA / "venv/bin/python"
METHODS = {
    "qdesn_al_rhs_ns_exact_chunked_r65_parity",
    "qdesn_exal_rhs_ns_exact_chunked_structured_r65",
}
TAUS = {0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--python-bin", type=Path, default=PYTHON)
    p.add_argument("--workers", type=int, default=20)
    p.add_argument("--cpu-list", required=True)
    p.add_argument("--expected-cases", type=int, default=114)
    p.add_argument("--minimum-free-gib", type=float, default=150.0)
    p.add_argument("--minimum-available-memory-gib", type=float, default=100.0)
    p.add_argument("--authorize", type=parse_bool, default=False)
    return p


def parse_cpus(value: str) -> list[int]:
    cpus = []
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
        raise ValueError("CPU list must contain unique CPU IDs")
    online = set(range(os.cpu_count() or 0))
    if not set(cpus).issubset(online):
        raise ValueError(f"CPU list is outside online CPUs: {sorted(set(cpus) - online)}")
    return cpus


def available_memory_gib() -> float:
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0])
    return values["MemAvailable"] / 1024**2


def preflight(manifest: pd.DataFrame, args: argparse.Namespace, cpus: list[int]) -> dict:
    if not args.authorize:
        raise RuntimeError("Production R65 launch requires --authorize true")
    if len(manifest) != args.expected_cases or manifest.duplicated(["region", "fold"]).any():
        raise RuntimeError(f"Expected {args.expected_cases} unique R65 cases")
    blocked = [
        "launch_authorized",
        "test_access_authorized",
        "registry_mutation_authorized",
        "article_mutation_authorized",
        "joint_model_authorized",
        "mcmc_authorized",
    ]
    for column in blocked:
        if manifest[column].map(lambda value: str(value).lower() == "true").any():
            raise RuntimeError(f"Prepared manifest must keep {column} declaratively false")
    if args.workers < 20:
        raise RuntimeError("The authorized R65 production launch requires at least 20 workers")
    if len(cpus) < args.workers:
        raise RuntimeError("Need one unique logical CPU per worker")
    usage = shutil.disk_usage(DATA)
    free_gib = usage.free / 1024**3
    memory_gib = available_memory_gib()
    if free_gib < args.minimum_free_gib:
        raise RuntimeError(f"Only {free_gib:.1f} GiB free; R65 requires {args.minimum_free_gib:.1f} GiB")
    if memory_gib < args.minimum_available_memory_gib:
        raise RuntimeError(
            f"Only {memory_gib:.1f} GiB available memory; R65 requires {args.minimum_available_memory_gib:.1f} GiB"
        )
    return {
        "manifest_cases": len(manifest),
        "workers": args.workers,
        "cpu_ids": cpus[: args.workers],
        "free_disk_gib": round(free_gib, 3),
        "available_memory_gib": round(memory_gib, 3),
        "one_process_per_cpu": True,
        "numerical_threads_per_process": 1,
        "test_access": False,
    }


def completion_state(output: Path) -> str | None:
    required = [
        output / "r65_case_fit_summary.json",
        output / "run_manifest.json",
        output / "r65_component_status.csv",
        output / "model_predictions_scaled.csv",
        output / "model_method_summary.csv",
        output / "metric_summary.csv",
    ]
    if not all(path.is_file() for path in required):
        return None
    summary = json.loads((output / "r65_case_fit_summary.json").read_text())
    if int(summary.get("terminal_components", -1)) != 7 or bool(summary.get("test_loaded")):
        return None
    predictions = pd.read_csv(output / "model_predictions_scaled.csv", usecols=["method_id", "split", "tau"])
    if set(predictions.method_id.astype(str)) != METHODS or set(predictions.split.astype(str)) != {"val"}:
        return None
    for method, group in predictions.groupby("method_id"):
        if {round(float(value), 12) for value in group.tau.unique()} != TAUS:
            return None
    metrics = pd.read_csv(output / "metric_summary.csv")
    selected = metrics[
        metrics.method_id.astype(str).isin(METHODS)
        & metrics.split.astype(str).eq("val")
        & metrics.unit.astype(str).eq("original")
    ]
    if set(selected.method_id.astype(str)) != METHODS or len(selected) != 2:
        return None
    return "completed" if int(summary.get("eligible_components", -1)) == 7 else "completed_with_quarantine"


def run_one(row: dict, cpu: int, code_root: Path, python_bin: Path) -> dict:
    output = Path(row["output_dir"])
    case_root = output.parent
    log = case_root / "worker.log"
    case_root.mkdir(parents=True, exist_ok=True)
    existing = completion_state(output)
    if existing:
        return {
            **row,
            "cpu": cpu,
            "status": f"skipped_{existing}",
            "returncode": 0,
            "elapsed_seconds": 0.0,
            "worker_log": str(log),
        }

    env = dict(os.environ)
    for key in (
        "OMP_NUM_THREADS",
        "OPENBLAS_NUM_THREADS",
        "MKL_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS",
        "NUMEXPR_NUM_THREADS",
        "RCPP_PARALLEL_NUM_THREADS",
        "BLIS_NUM_THREADS",
    ):
        env[key] = "1"
    commands = [
        [
            "taskset",
            "-c",
            str(cpu),
            "Rscript",
            str(code_root / "application/scripts/pricefm/224_run_pricefm_stage_r65_independent_structured_exal_vb_case.R"),
            "--case-config",
            row["config"],
            "--force",
            "false",
        ],
        [
            "taskset",
            "-c",
            str(cpu),
            str(python_bin),
            str(code_root / "application/scripts/pricefm/09_summarize_desn_model_smoke.py"),
            "--smoke-config",
            row["config"],
            "--run-dir",
            row["output_dir"],
        ],
    ]
    started = time.time()
    returncode = 0
    with log.open("a") as handle:
        handle.write(f"START stage=R65 case={row['case_id']} cpu={cpu} time={time.time()}\n")
        handle.flush()
        for command in commands:
            handle.write("COMMAND " + " ".join(command) + "\n")
            handle.flush()
            result = subprocess.run(
                command,
                cwd=code_root,
                env=env,
                stdout=handle,
                stderr=subprocess.STDOUT,
            )
            returncode = int(result.returncode)
            if returncode:
                break
        state = completion_state(output)
        handle.write(f"END returncode={returncode} state={state} time={time.time()}\n")
    status = state if returncode == 0 and state else "failed"
    return {
        **row,
        "cpu": cpu,
        "status": status,
        "returncode": returncode,
        "elapsed_seconds": round(time.time() - started, 3),
        "worker_log": str(log),
    }


def write_status(path: Path, rows: list[dict], lock: threading.Lock) -> None:
    with lock:
        frame = pd.DataFrame(rows).sort_values(["region", "fold"])
        temp = path.with_suffix(path.suffix + ".tmp")
        frame.to_csv(temp, index=False)
        temp.replace(path)


def run(args: argparse.Namespace) -> dict:
    code_root = args.code_root.resolve()
    manifest_path = args.manifest.resolve()
    manifest = pd.read_csv(manifest_path)
    cpus = parse_cpus(args.cpu_list)
    audit = preflight(manifest, args, cpus)
    status_path = manifest_path.parent / "launch_status.csv"
    write_json(manifest_path.parent / "launch_preflight.json", audit)
    results = []
    lock = threading.Lock()
    pending_rows = iter(manifest.to_dict("records"))
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {}

        def submit_next(cpu: int) -> bool:
            try:
                row = next(pending_rows)
            except StopIteration:
                return False
            future = pool.submit(
                run_one,
                row,
                cpu,
                code_root,
                args.python_bin.absolute(),
            )
            futures[future] = (row, cpu)
            return True

        for cpu in cpus[: args.workers]:
            submit_next(cpu)

        while futures:
            done, _ = wait(futures, return_when=FIRST_COMPLETED)
            for future in done:
                row, cpu = futures.pop(future)
                try:
                    results.append(future.result())
                except Exception as exc:
                    results.append({
                        **row,
                        "cpu": cpu,
                        "status": "launcher_exception",
                        "returncode": 99,
                        "error": repr(exc),
                    })
                write_status(status_path, results, lock)
                submit_next(cpu)

    counts = pd.Series([row["status"] for row in results]).value_counts().sort_index().to_dict()
    failures = sum(count for status, count in counts.items() if status in {"failed", "launcher_exception"})
    result = {
        "status": "completed" if not failures else "completed_with_failures",
        **audit,
        "status_counts": counts,
        "test_opened": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    write_json(manifest_path.parent / "launch_summary.json", result)
    if failures:
        raise RuntimeError(f"R65 completed with {failures} failed case jobs: {counts}")
    return result


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
