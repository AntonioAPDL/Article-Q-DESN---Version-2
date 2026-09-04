#!/usr/bin/env python3
"""Prepare zero-freeze controls for both SE_4 transient-overflow failures."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil

import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R80_GRID = DATA / "experiment_grids/pricefm_stage_r80_exal_diagnostic_replay_20260904"
TAG = "pricefm_stage_r80c_zero_freeze_controls_20260904"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r80c_zero_freeze_controls_prep_20260904"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r80-manifest", type=Path, default=R80_GRID / "diagnostic_manifest.csv")
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
    source = pd.read_csv(args.r80_manifest)
    selected = source[source.case_id.eq("pricefm_joint_se_4_f1")].sort_values("tau")
    if len(selected) != 2 or set(selected.tau) != {0.25, 0.75}:
        raise RuntimeError("R80C requires both SE_4 fold-1 diagnostic controls")
    grid, output = reset(args.grid_dir, args.force), reset(args.output_dir, args.force)
    args.run_dir.mkdir(parents=True, exist_ok=True)
    (grid / "tasks").mkdir()
    rows = []
    for row in selected.itertuples(index=False):
        source_path = Path(row.task_config)
        if sha256(source_path) != row.task_config_sha256:
            raise RuntimeError(f"Changed R80 diagnostic source: {source_path}")
        task = json.loads(source_path.read_text())
        task["source_r80d_task"] = str(source_path.resolve())
        task["source_r80d_task_sha256"] = sha256(source_path)
        task["task_id"] += "__zero_freeze_control"
        task["method_id"] = "diagnostic_zero_freeze_control_not_scientific_fit"
        task["sigmagam_freeze_warmup_iters"] = 0
        task["max_iter"] = 60
        task["min_postwarmup_updates"] = 35
        task["output_dir"] = str(args.run_dir.resolve() / task["task_id"])
        task["launch_authorized"] = False
        path = grid / "tasks" / f"{task['task_id']}.json"
        path.write_text(json.dumps(task, indent=2, sort_keys=True) + "\n")
        rows.append({
            "task_id": task["task_id"], "source_task_id": row.task_id,
            "diagnostic_class": "zero_freeze_transient_overflow_control",
            "case_id": task["case_id"], "region": task["region"], "fold": task["fold"],
            "tau": task["tau"], "output_dir": task["output_dir"],
            "task_config": str(path.resolve()), "task_config_sha256": sha256(path),
            "selection_split": "val", "launch_authorized": False,
            "test_access_authorized": False, "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        })
    manifest = pd.DataFrame(rows)
    manifest.to_csv(grid / "diagnostic_manifest.csv", index=False)
    summary = {"status": "two_zero_freeze_controls_prepared_not_launched",
               "diagnostic_atoms": 2, "scientific_retry_atoms": 0,
               "test_opened": False, "registry_mutated": False, "article_mutated": False}
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
