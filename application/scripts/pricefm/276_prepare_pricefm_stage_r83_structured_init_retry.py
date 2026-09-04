#!/usr/bin/env python3
"""Prepare R83 repaired exAL retries for only the 14 failed R76 atoms."""

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
R82_GATE = DATA / "authoritative/pricefm_stage_r82_structured_init_repair_gate_20260904"
RUNTIME = DATA / "runtime_libraries/exdqlm_pricefm_r82_structured_init_repair"
RUNTIME_MANIFEST = RUNTIME / "pricefm_stage_r82_structured_init_repair_manifest.json"
TAG = "pricefm_stage_r83_structured_init_failed_atom_retry_20260904"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r83_structured_init_retry_prep_20260904"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r76-manifest", type=Path, default=R76 / "task_manifest.csv")
    p.add_argument("--r76-status", type=Path, default=R76 / "launch_status.csv")
    p.add_argument("--repair-gate", type=Path, default=R82_GATE / "summary.json")
    p.add_argument("--runtime", type=Path, default=RUNTIME)
    p.add_argument("--runtime-manifest", type=Path, default=RUNTIME_MANIFEST)
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
    if gate.get("r83_retry_authorized") is not True or gate.get("r83_retry_atoms") != 14:
        raise RuntimeError("R82 gate does not authorize the bounded R83 retry")
    runtime = json.loads(args.runtime_manifest.read_text())
    if runtime.get("status") != "installed_structured_initialization_repair_runtime":
        raise RuntimeError("R83 runtime is not installed")
    manifest = pd.read_csv(args.r76_manifest)
    status = pd.read_csv(args.r76_status)
    failed_ids = set(status.loc[status.status.eq("failed"), "task_id"])
    selected = manifest[manifest.task_id.isin(failed_ids)].sort_values(["region", "fold", "tau"])
    if len(selected) != 14 or selected.case_id.nunique() != 11:
        raise RuntimeError("R83 must contain exactly the 14 failed R76 atoms across 11 cases")

    grid, output = reset(args.grid_dir, args.force), reset(args.output_dir, args.force)
    args.run_dir.mkdir(parents=True, exist_ok=True)
    (grid / "tasks").mkdir()
    rows = []
    for row in selected.to_dict("records"):
        old = Path(row["task_config"])
        if sha256(old) != row["task_config_sha256"]:
            raise RuntimeError(f"Changed R76 task: {old}")
        task = json.loads(old.read_text())
        source_task_id = task["task_id"]
        task.update(
            stage="R83",
            diagnostic_mode=False,
            source_r76_task=str(old.resolve()),
            source_r76_task_sha256=sha256(old),
            repair_gate=str(args.repair_gate.resolve()),
            repair_gate_sha256=sha256(args.repair_gate),
            task_id=source_task_id + "__r83_structured_init",
            method_id="qdesn_exal_rhs_ns_pricefm_r83_structured_init_repair",
            r_library=str(args.runtime.resolve()),
            runtime_manifest=str(args.runtime_manifest.resolve()),
            runtime_manifest_sha256=sha256(args.runtime_manifest),
            sigmagam_freeze_warmup_iters=0,
            launch_authorized=False,
        )
        task["output_dir"] = str(args.run_dir.resolve() / task["task_id"])
        path = grid / "tasks" / f"{task['task_id']}.json"
        path.write_text(json.dumps(task, indent=2, sort_keys=True) + "\n")
        row.update(
            stage="R83",
            task_id=task["task_id"],
            source_task_id=source_task_id,
            output_dir=task["output_dir"],
            r_library=task["r_library"],
            runtime_manifest=task["runtime_manifest"],
            runtime_manifest_sha256=task["runtime_manifest_sha256"],
            method_id=task["method_id"],
            sigmagam_freeze_warmup_iters=0,
            task_config=str(path.resolve()),
            task_config_sha256=sha256(path),
            launch_authorized=False,
        )
        rows.append(row)
    retry = pd.DataFrame(rows)
    retry.to_csv(grid / "retry_manifest.csv", index=False)
    summary = {
        "status": "bounded_r83_retry_prepared_not_launched",
        "tasks": 14,
        "cases": 11,
        "successful_r76_atoms_refit": 0,
        "changed_scientific_fields": [],
        "changed_numerical_initialization": "structured_plugin_at_al_warm_start",
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
