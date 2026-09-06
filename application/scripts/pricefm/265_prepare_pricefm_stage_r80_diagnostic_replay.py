#!/usr/bin/env python3
"""Prepare three representative R80 diagnostic replays without launching."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
from typing import Any

import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R76_GRID = DATA / "experiment_grids/pricefm_stage_r76_repaired_exal_surface_20260902"
R79 = DATA / "authoritative/pricefm_stage_r79_exal_numerical_repair_gate_20260904"
RUNTIME = DATA / "runtime_libraries/exdqlm_pricefm_r80_failure_diagnostics/pricefm_stage_r80_failure_diagnostics_manifest.json"
TAG = "pricefm_stage_r80_exal_diagnostic_replay_20260904"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r80_exal_diagnostic_replay_prep_20260904"
TARGETS = {
    "pricefm_joint_fr_f3__tau_0p25__exal": "explicit_gamma_grid_failure",
    "pricefm_joint_se_4_f1__tau_0p25__exal": "unresolved_lower_quantile",
    "pricefm_joint_se_4_f1__tau_0p75__exal": "unresolved_upper_quantile",
}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r76-manifest", type=Path, default=R76_GRID / "task_manifest.csv")
    p.add_argument("--r76-status", type=Path, default=R76_GRID / "launch_status.csv")
    p.add_argument("--r79-dir", type=Path, default=R79)
    p.add_argument("--runtime-manifest", type=Path, default=RUNTIME)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def reset(path: Path, force: bool) -> Path:
    path = path.resolve()
    if path.exists() and any(path.iterdir()):
        if not force:
            raise FileExistsError(path)
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)
    return path


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = pd.read_csv(args.r76_manifest)
    status = pd.read_csv(args.r76_status).set_index("task_id")
    r79_summary = json.loads((args.r79_dir / "summary.json").read_text())
    runtime = json.loads(args.runtime_manifest.read_text())
    if r79_summary.get("status") != "numerical_repair_not_identified_retry_blocked":
        raise RuntimeError("R80 diagnostic replay requires the frozen blocked R79 gate")
    if runtime.get("status") != "installed_diagnostic_runtime" or runtime.get("version") != "1.1.1.9003":
        raise RuntimeError("R80 diagnostic runtime is unavailable")
    selected = manifest[manifest.task_id.isin(TARGETS)].copy()
    if len(selected) != 3 or not selected.task_id.map(lambda x: status.loc[x, "status"] == "failed").all():
        raise RuntimeError("R80 targets must be three frozen R76 failures")
    grid, output = reset(args.grid_dir, args.force), reset(args.output_dir, args.force)
    args.run_dir.mkdir(parents=True, exist_ok=True)
    (grid / "tasks").mkdir()
    rows = []
    for row in selected.sort_values(["region", "fold", "tau"]).to_dict("records"):
        source_task = Path(row["task_config"])
        if sha256(source_task) != row["task_config_sha256"]:
            raise RuntimeError(f"Changed R76 task: {source_task}")
        task = json.loads(source_task.read_text())
        source_id = task["task_id"]
        task["stage"] = "R80D"
        task["diagnostic_mode"] = True
        task["source_r76_task"] = str(source_task.resolve())
        task["source_r76_task_sha256"] = sha256(source_task)
        task["task_id"] = source_id + "__r80d"
        task["method_id"] = "diagnostic_only_not_scientific_fit"
        task["output_dir"] = str((args.run_dir.resolve() / task["task_id"]))
        task["r_library"] = str(Path(runtime["library"]).resolve())
        task["runtime_manifest"] = str(args.runtime_manifest.resolve())
        task["runtime_manifest_sha256"] = sha256(args.runtime_manifest)
        task["launch_authorized"] = False
        task_path = grid / "tasks" / f"{task['task_id']}.json"
        task_path.write_text(json.dumps(task, indent=2, sort_keys=True) + "\n")
        rows.append({
            "task_id": task["task_id"], "source_task_id": source_id,
            "diagnostic_class": TARGETS[source_id], "case_id": task["case_id"],
            "region": task["region"], "fold": task["fold"], "tau": task["tau"],
            "output_dir": task["output_dir"], "task_config": str(task_path.resolve()),
            "task_config_sha256": sha256(task_path), "selection_split": "val",
            "launch_authorized": False, "test_access_authorized": False,
            "registry_mutation_authorized": False, "article_mutation_authorized": False,
        })
    replay = pd.DataFrame(rows)
    replay.to_csv(grid / "diagnostic_manifest.csv", index=False)
    gates = pd.DataFrame([
        {"gate": "three_representative_failed_atoms", "passed": len(replay) == 3, "observed": len(replay)},
        {"gate": "both_failure_quantiles_represented", "passed": set(replay.tau) == {0.25, 0.75}, "observed": sorted(replay.tau.unique())},
        {"gate": "diagnostic_runtime_only", "passed": True, "observed": runtime["version"]},
        {"gate": "scientific_retry_not_authorized", "passed": not replay.launch_authorized.any(), "observed": "blocked"},
        {"gate": "test_registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    gates.to_csv(output / "pricefm_stage_r80_diagnostic_replay_gates.csv", index=False)
    sources = [Path(__file__).resolve(), args.r76_manifest.resolve(), args.r76_status.resolve(),
               (args.r79_dir / "summary.json").resolve(), args.runtime_manifest.resolve(),
               grid / "diagnostic_manifest.csv"]
    pd.DataFrame([{"path": str(p), "sha256": sha256(p), "bytes": p.stat().st_size}
                  for p in sources]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "three_atom_diagnostic_replay_prepared_not_launched",
        "diagnostic_atoms": 3, "scientific_retry_atoms": 0,
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
