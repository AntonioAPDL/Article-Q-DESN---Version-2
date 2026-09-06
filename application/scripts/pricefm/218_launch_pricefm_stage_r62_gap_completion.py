#!/usr/bin/env python3
"""Launch the explicitly authorized Stage-R62 exact-gap completion campaign."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import csv
import json
import os
from pathlib import Path
import subprocess
import threading
import time

import pandas as pd

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
MANIFEST = DATA / "experiment_grids/pricefm_stage_r62_gap_completion_20260827/launch_manifest.csv"
PYTHON = DATA / "venv/bin/python"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--python-bin", type=Path, default=PYTHON)
    p.add_argument("--workers", type=int, default=1)
    p.add_argument("--cpu-list", required=True)
    p.add_argument("--authorize", type=parse_bool, default=False)
    return p


def parse_cpus(value: str) -> list[int]:
    out = []
    for token in str(value).split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            lo, hi = token.split("-", 1)
            out.extend(range(int(lo), int(hi) + 1))
        else:
            out.append(int(token))
    if len(out) != len(set(out)):
        raise ValueError("CPU list contains duplicates")
    return out


def complete(output: Path) -> bool:
    path = output / "metric_summary.csv"
    if not path.is_file():
        return False
    frame = pd.read_csv(path)
    methods = set(frame.loc[
        frame.split.astype(str).eq("val") & frame.unit.astype(str).eq("original"), "method_id"
    ].astype(str))
    return {"qdesn_al_rhs_ns_exact_chunked", "qdesn_exal_rhs_ns_exact_chunked"}.issubset(methods)


def fit_artifacts_complete(output: Path) -> bool:
    return all((output / name).is_file() for name in (
        "model_predictions_scaled.csv", "model_method_summary.csv", "run_manifest.json",
    ))


def run_one(row: dict, cpu: int, code_root: Path, python_bin: Path) -> dict:
    output = Path(row["output_dir"])
    log = output.parent.parent.parent / "worker.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    if complete(output):
        return {**row, "cpu": cpu, "status": "skipped_complete", "returncode": 0, "elapsed_seconds": 0, "worker_log": str(log)}
    env = dict(os.environ)
    for key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS"):
        env[key] = "1"
    commands = []
    if not fit_artifacts_complete(output):
        commands.append([
            "taskset", "-c", str(cpu), "Rscript",
            str(code_root / "application/scripts/pricefm/08_run_desn_model_smoke.R"),
            "--smoke-config", row["config"], "--force", "false",
        ])
    commands.append([
        "taskset", "-c", str(cpu), str(python_bin),
        str(code_root / "application/scripts/pricefm/09_summarize_desn_model_smoke.py"),
        "--smoke-config", row["config"], "--run-dir", row["output_dir"],
    ])
    started = time.time()
    returncode = 0
    with log.open("a") as handle:
        handle.write(f"START case={row['case_id']} cpu={cpu}\n")
        handle.flush()
        for command in commands:
            handle.write("COMMAND " + " ".join(command) + "\n")
            handle.flush()
            result = subprocess.run(command, cwd=code_root, env=env, stdout=handle, stderr=subprocess.STDOUT)
            returncode = result.returncode
            if returncode:
                break
        handle.write(f"END returncode={returncode}\n")
    status = "completed" if returncode == 0 and complete(output) else "failed"
    return {**row, "cpu": cpu, "status": status, "returncode": returncode, "elapsed_seconds": round(time.time() - started, 3), "worker_log": str(log)}


def write_status(path: Path, rows: list[dict], lock: threading.Lock) -> None:
    with lock:
        pd.DataFrame(rows).sort_values("case_id").to_csv(path, index=False)


def run(args: argparse.Namespace) -> dict:
    if not args.authorize:
        raise RuntimeError("Production launch requires --authorize true")
    code_root = args.code_root.resolve()
    manifest = pd.read_csv(args.manifest)
    if manifest.launch_authorized.map(lambda value: str(value).lower() == "true").any():
        raise RuntimeError("Prepared manifest must remain declaratively launch-blocked")
    if manifest.test_access_authorized.map(lambda value: str(value).lower() == "true").any():
        raise RuntimeError("Test access is forbidden")
    cpus = parse_cpus(args.cpu_list)
    workers = int(args.workers)
    if workers < 1 or len(cpus) < workers:
        raise RuntimeError("Need at least one unique CPU per worker")
    status_path = args.manifest.parent / "launch_status.csv"
    results = []
    lock = threading.Lock()
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {
            # Preserve the virtualenv symlink so Python discovers pyvenv.cfg.
            pool.submit(run_one, row, cpus[index % workers], code_root, args.python_bin.absolute()): row["case_id"]
            for index, row in enumerate(manifest.to_dict("records"))
        }
        for future in as_completed(futures):
            results.append(future.result())
            write_status(status_path, results, lock)
    counts = pd.Series([row["status"] for row in results]).value_counts().to_dict()
    summary = {
        "status": "completed" if not counts.get("failed", 0) else "completed_with_failures",
        "manifest_cases": len(manifest), "workers": workers, "cpu_ids": cpus[:workers],
        "one_process_per_cpu": True, "numerical_threads_per_process": 1,
        "status_counts": counts, "test_opened": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
    }
    write_json(args.manifest.parent / "launch_summary.json", summary)
    if counts.get("failed", 0):
        raise RuntimeError(f"Stage-R62 gap completion failures: {counts}")
    return summary


def main() -> int:
    args = parser().parse_args()
    print(json.dumps(run(args), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
