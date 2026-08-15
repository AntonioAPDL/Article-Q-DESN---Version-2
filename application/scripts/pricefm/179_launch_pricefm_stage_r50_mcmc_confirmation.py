#!/usr/bin/env python3
"""Launch or resume CPU-pinned Stage-R50 PriceFM MCMC chain jobs."""

from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, write_json

ARTIFACT = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT / "application/data_local/pricefm"
PREP = DATA / "authoritative/pricefm_stage_r50_mcmc_confirmation_launch_prep_20260809"
RUNNER = Path(__file__).with_name("178_run_pricefm_stage_r50_mcmc_chain.R")
R_BIN = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--prep-dir", type=Path, default=PREP)
    p.add_argument("--jobs", type=int, default=16)
    p.add_argument("--cpu-list", required=True)
    p.add_argument("--resume", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def cpus(value):
    out = [int(x.strip()) for x in value.split(",") if x.strip()]
    if len(out) != len(set(out)) or any(x < 0 for x in out):
        raise ValueError("CPU list must contain unique nonnegative IDs")
    return out


def launch_one(row, cpu, resume, force):
    out = Path(row.output_dir)
    summary = out / "job_summary.json"
    if resume and summary.exists() and json.loads(summary.read_text()).get("status") == "completed":
        return {"id": row.id, "status": "skipped_completed", "return_code": 0, "cpu_id": cpu, "elapsed_seconds": 0, "log": str(out / "chain.log")}
    out.mkdir(parents=True, exist_ok=True)
    log_path = out / "chain.log"
    cmd = ["taskset", "-c", str(cpu), str(R_BIN), str(RUNNER), "--config", row.config, "--force", str(bool(force)).lower()]
    env = os.environ.copy()
    env.update({"OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1", "VECLIB_MAXIMUM_THREADS": "1"})
    started = time.time()
    with log_path.open("w") as log:
        proc = subprocess.run(cmd, cwd=str(ARTIFACT), stdout=log, stderr=subprocess.STDOUT, env=env, check=False)
    return {"id": row.id, "status": "completed" if proc.returncode == 0 else "failed", "return_code": proc.returncode, "cpu_id": cpu, "elapsed_seconds": round(time.time() - started, 3), "log": str(log_path)}


def launch_lane(rows, cpu, resume, force):
    results = []
    for row in rows:
        result = launch_one(row, cpu, resume, force)
        results.append(result)
        print(json.dumps(result, sort_keys=True), flush=True)
        if result["status"] == "failed":
            break
    return results


def run(args):
    manifest = pd.read_csv(args.prep_dir / "pricefm_stage_r50_launch_manifest.csv")
    init_summary = json.loads((args.prep_dir / "initialization_summary.json").read_text())
    if not init_summary.get("launch_authorized"):
        raise RuntimeError("Design and initialization replay have not authorized launch")
    cpu_ids = cpus(args.cpu_list)
    jobs = min(args.jobs, len(cpu_ids))
    if jobs < 1:
        raise ValueError("At least one worker/CPU is required")
    rows = list(manifest.itertuples(index=False))
    lanes = [rows[i::jobs] for i in range(jobs)]
    results = []
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = [pool.submit(launch_lane, lane, cpu_ids[i], args.resume, args.force) for i, lane in enumerate(lanes)]
        for future in as_completed(futures):
            results.extend(future.result())
    status = pd.DataFrame(results).sort_values("id")
    status.to_csv(args.prep_dir / "launch_status.csv", index=False)
    summary = {"jobs": len(status), "completed": int(status.status.isin(["completed", "skipped_completed"]).sum()), "failed": int((status.status == "failed").sum()), "worker_count": jobs, "cpu_ids": cpu_ids[:jobs]}
    write_json(args.prep_dir / "launch_summary.json", summary)
    if summary["failed"]:
        raise RuntimeError(f"{summary['failed']} R50 jobs failed")
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
