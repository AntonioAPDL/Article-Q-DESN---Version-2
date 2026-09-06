#!/usr/bin/env python3
"""Prepare zero-freeze retries for only the 14 failed R76 exAL atoms."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil

import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R76 = DATA / "experiment_grids/pricefm_stage_r76_repaired_exal_surface_20260902"
GATE = DATA / "authoritative/pricefm_stage_r80_zero_freeze_repair_gate_20260904/summary.json"
TAG = "pricefm_stage_r81_zero_freeze_failed_atom_retry_20260904"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r81_zero_freeze_retry_prep_20260904"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r76-manifest", type=Path, default=R76 / "task_manifest.csv")
    p.add_argument("--r76-status", type=Path, default=R76 / "launch_status.csv")
    p.add_argument("--repair-gate", type=Path, default=GATE)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def reset(path: Path, force: bool) -> Path:
    path = path.resolve()
    if path.exists() and any(path.iterdir()):
        if not force:
            raise FileExistsError(path)
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)
    return path


def run(args: argparse.Namespace) -> dict:
    gate = json.loads(args.repair_gate.read_text())
    if gate.get("r81_retry_authorized") is not True or gate.get("r81_retry_atoms") != 14:
        raise RuntimeError("R80 gate does not authorize the bounded R81 retry")
    manifest = pd.read_csv(args.r76_manifest)
    status = pd.read_csv(args.r76_status)
    failed_ids = set(status.loc[status.status.eq("failed"), "task_id"])
    selected = manifest[manifest.task_id.isin(failed_ids)].sort_values(["region", "fold", "tau"])
    if len(selected) != 14 or selected.case_id.nunique() != 11:
        raise RuntimeError("R81 must contain exactly the 14 failed R76 atoms across 11 cases")
    grid, output = reset(args.grid_dir, args.force), reset(args.output_dir, args.force)
    args.run_dir.mkdir(parents=True, exist_ok=True)
    (grid / "tasks").mkdir()
    rows = []
    for row in selected.to_dict("records"):
        old = Path(row["task_config"])
        if sha256(old) != row["task_config_sha256"]:
            raise RuntimeError(f"Changed R76 source task: {old}")
        task = json.loads(old.read_text())
        source_id = task["task_id"]
        task["source_r76_task"] = str(old.resolve())
        task["source_r76_task_sha256"] = sha256(old)
        task["task_id"] = source_id + "__r81_zero_freeze"
        task["method_id"] = "qdesn_exal_rhs_ns_pricefm_r81_zero_freeze_repair"
        task["sigmagam_freeze_warmup_iters"] = 0
        task["output_dir"] = str(args.run_dir.resolve() / task["task_id"])
        task["launch_authorized"] = False
        path = grid / "tasks" / f"{task['task_id']}.json"
        path.write_text(json.dumps(task, indent=2, sort_keys=True) + "\n")
        row.update(task_id=task["task_id"], source_task_id=source_id,
                   output_dir=task["output_dir"], task_config=str(path.resolve()),
                   task_config_sha256=sha256(path), sigmagam_freeze_warmup_iters=0,
                   launch_authorized=False)
        rows.append(row)
    retry = pd.DataFrame(rows)
    retry.to_csv(grid / "retry_manifest.csv", index=False)
    summary = {"status": "bounded_14_atom_retry_prepared_not_launched",
               "tasks": 14, "cases": 11, "successful_r76_atoms_refit": 0,
               "test_opened": False, "registry_mutated": False, "article_mutated": False}
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
