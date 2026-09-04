#!/usr/bin/env python3
"""Prepare a four-arm FR warm-up ladder to locate a stable structured schedule."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil

import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
SOURCE = DATA / "experiment_grids/pricefm_stage_r80_exal_diagnostic_replay_20260904/tasks/pricefm_joint_fr_f3__tau_0p25__exal__r80d.json"
TAG = "pricefm_stage_r80d_warmup_ladder_20260904"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r80d_warmup_ladder_prep_20260904"
WARMUPS = (1, 2, 3, 5)


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


def run(args: argparse.Namespace) -> dict:
    base = json.loads(args.source_task.read_text())
    if base.get("case_id") != "pricefm_joint_fr_f3" or base.get("tau") != 0.25:
        raise RuntimeError("R80D ladder requires the frozen FR fold-3 tau-0.25 failure")
    grid, output = reset(args.grid_dir, args.force), reset(args.output_dir, args.force)
    args.run_dir.mkdir(parents=True, exist_ok=True)
    (grid / "tasks").mkdir()
    rows = []
    for warmup in WARMUPS:
        task = dict(base)
        task["source_r80d_task"] = str(args.source_task.resolve())
        task["source_r80d_task_sha256"] = sha256(args.source_task)
        task["task_id"] = f"pricefm_joint_fr_f3__tau_0p25__exal__r80d_warmup_{warmup}"
        task["method_id"] = "diagnostic_warmup_ladder_not_scientific_fit"
        task["sigmagam_freeze_warmup_iters"] = warmup
        task["max_iter"] = 20
        task["min_postwarmup_updates"] = 10
        task["output_dir"] = str(args.run_dir.resolve() / task["task_id"])
        task["launch_authorized"] = False
        path = grid / "tasks" / f"{task['task_id']}.json"
        path.write_text(json.dumps(task, indent=2, sort_keys=True) + "\n")
        rows.append({
            "task_id": task["task_id"], "source_task_id": base["task_id"],
            "diagnostic_class": "warmup_ladder", "case_id": task["case_id"],
            "region": task["region"], "fold": task["fold"], "tau": task["tau"],
            "warmup_iters": warmup, "output_dir": task["output_dir"],
            "task_config": str(path.resolve()), "task_config_sha256": sha256(path),
            "selection_split": "val", "launch_authorized": False,
            "test_access_authorized": False, "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        })
    pd.DataFrame(rows).to_csv(grid / "diagnostic_manifest.csv", index=False)
    summary = {"status": "four_arm_warmup_ladder_prepared_not_launched",
               "diagnostic_atoms": 4, "warmup_iters": list(WARMUPS),
               "max_iter": 20, "test_opened": False,
               "registry_mutated": False, "article_mutated": False}
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
