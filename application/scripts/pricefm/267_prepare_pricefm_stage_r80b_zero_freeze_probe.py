#!/usr/bin/env python3
"""Prepare one diagnostic FR probe for the zero-freeze stability hypothesis."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
from typing import Any


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
SOURCE = DATA / "experiment_grids/pricefm_stage_r80_exal_diagnostic_replay_20260904/tasks/pricefm_joint_fr_f3__tau_0p25__exal__r80d.json"
TAG = "pricefm_stage_r80b_zero_freeze_probe_20260904"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r80b_zero_freeze_probe_prep_20260904"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-task", type=Path, default=SOURCE)
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


def run(args: argparse.Namespace) -> dict[str, Any]:
    source = json.loads(args.source_task.read_text())
    if source.get("stage") != "R80D" or source.get("case_id") != "pricefm_joint_fr_f3" or source.get("tau") != 0.25:
        raise RuntimeError("R80B requires the registered failed FR fold-3 tau-0.25 diagnostic")
    grid, output = reset(args.grid_dir, args.force), reset(args.output_dir, args.force)
    args.run_dir.mkdir(parents=True, exist_ok=True)
    source["task_id"] = "pricefm_joint_fr_f3__tau_0p25__exal__r80b_zero_freeze"
    source["method_id"] = "diagnostic_zero_freeze_not_scientific_fit"
    source["source_r80d_task"] = str(args.source_task.resolve())
    source["source_r80d_task_sha256"] = sha256(args.source_task)
    source["output_dir"] = str((args.run_dir.resolve() / source["task_id"]))
    source["sigmagam_freeze_warmup_iters"] = 0
    source["max_iter"] = 60
    source["min_postwarmup_updates"] = 35
    source["launch_authorized"] = False
    task = grid / "task.json"
    task.write_text(json.dumps(source, indent=2, sort_keys=True) + "\n")
    gates = {
        "status": "zero_freeze_probe_prepared_not_launched",
        "task_config": str(task.resolve()), "task_config_sha256": sha256(task),
        "changed_scientific_fields": [],
        "changed_diagnostic_schedule": {"sigmagam_freeze_warmup_iters": 0, "max_iter": 60},
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
    }
    (output / "summary.json").write_text(json.dumps(gates, indent=2, sort_keys=True) + "\n")
    return gates


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
