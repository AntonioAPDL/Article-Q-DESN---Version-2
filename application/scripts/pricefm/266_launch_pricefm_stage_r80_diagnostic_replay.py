#!/usr/bin/env python3
"""Launch a bounded R80/R82 diagnostic replay with explicit authorization."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
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
TAG = "pricefm_stage_r80_exal_diagnostic_replay_20260904"
GRID = DATA / "experiment_grids" / TAG
MANIFEST = GRID / "diagnostic_manifest.csv"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--cpu-list", default="")
    p.add_argument("--preflight-only", action="store_true")
    p.add_argument("--authorize-diagnostic", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return digest


def cpus(value: str, count: int) -> list[int]:
    if value:
        result = [int(v.strip()) for v in value.split(",") if v.strip()]
    else:
        used = {}
        proc = subprocess.run(["ps", "-e", "-o", "psr=,pcpu="], text=True, capture_output=True)
        for line in proc.stdout.splitlines():
            try:
                cpu, usage = line.split()
                used[int(cpu)] = used.get(int(cpu), 0) + float(usage)
            except ValueError:
                pass
        result = [i for i in sorted(range(os.cpu_count() or 0), key=lambda x: (used.get(x, 0), x))[:count]]
    if len(result) < count or len(result) != len(set(result)):
        raise RuntimeError("R80 requires one unique logical CPU per diagnostic atom")
    return result[:count]


def preflight(frame: pd.DataFrame, cpu_ids: list[int]) -> dict[str, Any]:
    if not 1 <= len(frame) <= 4 or not set(frame.tau).issubset({0.25, 0.75}):
        raise RuntimeError("R80 diagnostic manifest contract failed")
    for row in frame.itertuples(index=False):
        path = Path(row.task_config)
        if sha256(path) != row.task_config_sha256:
            raise RuntimeError(f"Changed R80 task: {path}")
        task = json.loads(path.read_text())
        if task.get("stage") not in {"R80D", "R82D"} or task.get("diagnostic_mode") is not True:
            raise RuntimeError("R80 diagnostic task role is invalid")
        if task.get("selection_split") != "val" or any(task.get(k) is True for k in (
            "test_access_authorized", "registry_mutation_authorized", "article_mutation_authorized",
            "joint_model_authorized", "mcmc_authorized")):
            raise RuntimeError("R80 firewall violation")
        adapter = Path(task["adapter_dir"])
        if any((adapter / name).exists() for name in ("X_test.csv", "y_test.csv", "rows_test.csv")):
            raise RuntimeError("R80 adapter contains test data")
    return {"status": "preflight_passed_not_launched", "diagnostic_atoms": int(len(frame)),
            "cpu_ids": cpu_ids, "test_opened": False, "registry_mutated": False,
            "article_mutated": False}


def run_one(row: dict[str, Any], cpu: int, code_root: Path) -> dict[str, Any]:
    output = Path(row["output_dir"])
    output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    for name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
        env[name] = "1"
    command = ["taskset", "-c", str(cpu), "Rscript",
               str(code_root / "application/scripts/pricefm/259_run_pricefm_stage_r76_repaired_exal_component.R"),
               "--task-config", row["task_config"], "--code-root", str(code_root)]
    started = time.time()
    log = output / "worker.log"
    with log.open("w") as handle:
        handle.write("COMMAND " + " ".join(command) + "\n")
        handle.flush()
        result = subprocess.run(command, cwd=code_root, env=env, stdout=handle, stderr=subprocess.STDOUT)
    terminal = json.loads((output / "terminal.json").read_text()) if (output / "terminal.json").is_file() else {}
    return {**row, "cpu": cpu, "returncode": result.returncode,
            "terminal_status": terminal.get("status", "missing"),
            "diagnostics_written": (output / "failure_diagnostics.json").is_file(),
            "fit_exception_written": (output / "fit_exception.json").is_file(),
            "elapsed_seconds": round(time.time() - started, 3)}


def run(args: argparse.Namespace) -> dict[str, Any]:
    frame = pd.read_csv(args.manifest)
    cpu_ids = cpus(args.cpu_list, len(frame))
    result = preflight(frame, cpu_ids)
    (args.manifest.parent / "diagnostic_preflight.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    if args.preflight_only:
        return result
    if not args.authorize_diagnostic:
        raise RuntimeError("R80 requires explicit --authorize-diagnostic")
    with ThreadPoolExecutor(max_workers=len(frame)) as pool:
        futures = [pool.submit(run_one, row, cpu, args.code_root.resolve())
                   for row, cpu in zip(frame.to_dict("records"), cpu_ids)]
        rows = [future.result() for future in futures]
    status = pd.DataFrame(rows)
    status.to_csv(args.manifest.parent / "diagnostic_status.csv", index=False)
    summary = {"status": "diagnostic_replay_finished", "diagnostic_atoms": int(len(frame)),
               "completed_scientific_fits": int((status.terminal_status == "completed").sum()),
               "failed_as_expected": int((status.terminal_status == "failed").sum()),
               "diagnostic_files": int(status.diagnostics_written.sum()),
               "test_opened": False, "registry_mutated": False, "article_mutated": False}
    (args.manifest.parent / "diagnostic_summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
