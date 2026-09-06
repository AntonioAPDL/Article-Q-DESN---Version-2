#!/usr/bin/env python3
"""Prepare three bounded diagnostics for the R82 structured initialization repair."""

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
RUNTIME = DATA / "runtime_libraries/exdqlm_pricefm_r82_structured_init_repair"
RUNTIME_MANIFEST = RUNTIME / "pricefm_stage_r82_structured_init_repair_manifest.json"
TAG = "pricefm_stage_r82_structured_init_diagnostics_20260904"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r82_structured_init_diagnostics_prep_20260904"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r80-manifest", type=Path, default=R80_GRID / "diagnostic_manifest.csv")
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
    runtime = json.loads(args.runtime_manifest.read_text())
    if (
        runtime.get("status") != "installed_structured_initialization_repair_runtime"
        or runtime.get("version") != "1.1.1.9004"
        or runtime.get("base_tarball_sha256")
        != "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
    ):
        raise RuntimeError("R82 structured initialization runtime is not installed and pinned")
    source = pd.read_csv(args.r80_manifest).sort_values(["case_id", "tau"])
    expected = {("pricefm_joint_fr_f3", 0.25), ("pricefm_joint_se_4_f1", 0.25),
                ("pricefm_joint_se_4_f1", 0.75)}
    observed = set(zip(source.case_id.astype(str), source.tau.astype(float)))
    if len(source) != 3 or observed != expected:
        raise RuntimeError("R82 requires the exact three registered R80 failure controls")

    grid, output = reset(args.grid_dir, args.force), reset(args.output_dir, args.force)
    args.run_dir.mkdir(parents=True, exist_ok=True)
    (grid / "tasks").mkdir()
    rows = []
    for row in source.to_dict("records"):
        source_path = Path(row["task_config"])
        if sha256(source_path) != row["task_config_sha256"]:
            raise RuntimeError(f"Changed R80 diagnostic source: {source_path}")
        task = json.loads(source_path.read_text())
        source_task_id = task["task_id"]
        task.update(
            stage="R82D",
            diagnostic_mode=True,
            task_id=source_task_id + "__r82_structured_init",
            method_id="diagnostic_r82_structured_init_not_scientific_fit",
            source_r80d_task=str(source_path.resolve()),
            source_r80d_task_sha256=sha256(source_path),
            r_library=str(args.runtime.resolve()),
            runtime_manifest=str(args.runtime_manifest.resolve()),
            runtime_manifest_sha256=sha256(args.runtime_manifest),
            sigmagam_freeze_warmup_iters=0,
            max_iter=60,
            min_postwarmup_updates=35,
            launch_authorized=False,
        )
        task["output_dir"] = str(args.run_dir.resolve() / task["task_id"])
        task_path = grid / "tasks" / f"{task['task_id']}.json"
        task_path.write_text(json.dumps(task, indent=2, sort_keys=True) + "\n")
        rows.append({
            "task_id": task["task_id"],
            "source_task_id": source_task_id,
            "diagnostic_class": "structured_plugin_initialization_control",
            "case_id": task["case_id"],
            "region": task["region"],
            "fold": task["fold"],
            "tau": task["tau"],
            "output_dir": task["output_dir"],
            "task_config": str(task_path.resolve()),
            "task_config_sha256": sha256(task_path),
            "selection_split": "val",
            "launch_authorized": False,
            "test_access_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        })
    manifest = pd.DataFrame(rows)
    manifest.to_csv(grid / "diagnostic_manifest.csv", index=False)
    summary = {
        "status": "r82_structured_init_diagnostics_prepared_not_launched",
        "diagnostic_atoms": 3,
        "changed_scientific_fields": [],
        "changed_numerical_initialization": "structured_plugin_at_al_warm_start",
        "sigmagam_freeze_warmup_iters": 0,
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
