#!/usr/bin/env python3
"""Run the explicitly authorized bounded R75 real-data mechanism probes."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from typing import Any

import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r75_large_n_gig_mechanism_probe_20260902"
MANIFEST = DATA / "experiment_grids" / TAG / "probe_manifest.csv"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--workers", type=int, default=3)
    p.add_argument("--cpu-list", default="")
    p.add_argument("--authorize", action="store_true")
    p.add_argument("--preflight-only", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_cpus(value: str) -> list[int]:
    cpus = []
    for token in value.split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            low, high = map(int, token.split("-", 1))
            cpus.extend(range(low, high + 1))
        else:
            cpus.append(int(token))
    if len(cpus) != len(set(cpus)) or not set(cpus).issubset(set(range(os.cpu_count() or 0))):
        raise RuntimeError("Invalid or duplicate CPU list")
    return cpus


def least_busy(count: int) -> list[int]:
    usage = {cpu: 0.0 for cpu in range(os.cpu_count() or 0)}
    result = subprocess.run(["ps", "-e", "-o", "psr=,pcpu="], text=True, capture_output=True, check=False)
    for line in result.stdout.splitlines():
        try:
            cpu, value = line.split()
            usage[int(cpu)] += float(value)
        except (ValueError, KeyError):
            continue
    return [cpu for cpu, _ in sorted(usage.items(), key=lambda item: (item[1], item[0]))[:count]]


def preflight(manifest: pd.DataFrame, args: argparse.Namespace, cpus: list[int]) -> dict[str, Any]:
    if len(manifest) != 9 or manifest["task_id"].duplicated().any() or args.workers < 1:
        raise RuntimeError("Invalid R75 probe manifest or worker count")
    if len(cpus) < args.workers:
        raise RuntimeError("Insufficient CPU assignments")
    for row in manifest.itertuples(index=False):
        task = Path(row.task_config)
        if sha256(task) != str(row.task_config_sha256):
            raise RuntimeError(f"Changed task config: {task}")
        payload = json.loads(task.read_text())
        if payload.get("stage") != "R75_PROBE" or not payload.get("probe_only"):
            raise RuntimeError(f"Invalid R75 task contract: {task}")
        if any(payload.get(name) for name in (
            "test_access_authorized", "registry_mutation_authorized", "article_mutation_authorized",
            "joint_model_authorized", "mcmc_authorized",
        )):
            raise RuntimeError(f"R75 task firewall violation: {task}")
    return {"tasks": 9, "workers": args.workers, "cpu_ids": cpus[:args.workers], "test_opened": False}


def run_one(row: Any, cpu: int, code_root: Path) -> dict[str, Any]:
    output = Path(row.output_dir)
    terminal = output / "terminal.json"
    if terminal.is_file() and json.loads(terminal.read_text()).get("status") == "completed":
        return {**row._asdict(), "cpu": cpu, "status": "skipped_completed", "returncode": 0, "elapsed_seconds": 0.0}
    output.mkdir(parents=True, exist_ok=True)
    log = output / "worker.log"
    command = ["taskset", "-c", str(cpu), "Rscript",
               str(code_root / "application/scripts/pricefm/253_run_pricefm_stage_r75_exal_mechanism_probe.R"),
               "--task-config", row.task_config, "--code-root", str(code_root)]
    env = dict(os.environ)
    for name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS", "BLIS_NUM_THREADS"):
        env[name] = "1"
    started = time.time()
    with log.open("a") as handle:
        result = subprocess.run(command, cwd=code_root, env=env, stdout=handle, stderr=subprocess.STDOUT)
    payload = json.loads(terminal.read_text()) if terminal.is_file() else {}
    status = "completed" if result.returncode == 0 and payload.get("status") == "completed" else "failed"
    return {**row._asdict(), "cpu": cpu, "status": status, "returncode": result.returncode,
            "elapsed_seconds": round(time.time() - started, 3), "worker_log": str(log)}


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = pd.read_csv(args.manifest).sort_values(["region", "fold", "tau"])
    cpus = parse_cpus(args.cpu_list) if args.cpu_list else least_busy(args.workers)
    audit = preflight(manifest, args, cpus)
    preflight_path = args.manifest.parent / "probe_preflight.json"
    preflight_path.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
    if args.preflight_only:
        return {"status": "preflight_passed_no_probe", **audit}
    if not args.authorize:
        raise RuntimeError("R75 probes require --authorize")
    rows = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {
            pool.submit(run_one, row, cpus[index % args.workers], args.code_root.resolve()): row.task_id
            for index, row in enumerate(manifest.itertuples(index=False))
        }
        for future in as_completed(futures):
            rows.append(future.result())
            pd.DataFrame(rows).sort_values(["region", "fold", "tau"]).to_csv(
                args.manifest.parent / "probe_status.csv", index=False
            )
    frame = pd.DataFrame(rows)
    result = {"status": "completed" if frame.status.ne("failed").all() else "completed_with_failures",
              "tasks": len(frame), "completed": int(frame.status.isin(["completed", "skipped_completed"]).sum()),
              "failed": int(frame.status.eq("failed").sum()), "workers": args.workers,
              "cpu_ids": cpus[:args.workers], "test_opened": False}
    (args.manifest.parent / "probe_launch_summary.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    return result


def main() -> int:
    args = parser().parse_args()
    print(json.dumps(run(args), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
