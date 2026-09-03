#!/usr/bin/env python3
"""Prepare longer train-only stability probes for the repaired exAL mechanism."""

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
R75_TAG = "pricefm_stage_r75_large_n_gig_mechanism_probe_20260902"
R75_MANIFEST = DATA / "experiment_grids" / R75_TAG / "probe_manifest.csv"
R75_GATE = DATA / "authoritative/pricefm_stage_r75_large_n_gig_mechanism_gate_20260902/summary.json"
TAG = "pricefm_stage_r75b_large_n_gig_stability_probe_20260902"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r75b_large_n_gig_stability_prep_20260902"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r75-manifest", type=Path, default=R75_MANIFEST)
    p.add_argument("--r75-gate", type=Path, default=R75_GATE)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--max-iter", type=int, default=100)
    p.add_argument("--n-samp", type=int, default=20)
    p.add_argument("--n-samp-xi", type=int, default=30)
    p.add_argument("--structured-grid-size", type=int, default=81)
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def prepare(path: Path, force: bool) -> Path:
    path = path.resolve()
    if path.exists() and any(path.iterdir()):
        if not force:
            raise FileExistsError(path)
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)
    return path


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"true", "1", "yes", "y"}


def run(args: argparse.Namespace) -> dict[str, Any]:
    source = pd.read_csv(args.r75_manifest).sort_values(["region", "fold", "tau"])
    gate = json.loads(args.r75_gate.read_text())
    if len(source) != 9 or source.task_id.duplicated().any():
        raise RuntimeError("R75B requires the exact nine-cell R75 probe surface")
    if gate.get("r76_launch_prep_authorized") is not True or gate.get("test_opened") is not False:
        raise RuntimeError("R75 mechanism gate does not authorize stability preparation")
    if args.max_iter < 80 or args.n_samp < 20 or args.n_samp_xi < 20:
        raise RuntimeError("R75B stability budget is below the registered floor")
    if args.structured_grid_size < 81 or args.structured_grid_size % 2 != 1:
        raise RuntimeError("R75B requires an odd structured grid of at least 81 points")

    grid = prepare(args.grid_dir, args.force)
    output = prepare(args.output_dir, args.force)
    args.run_dir.mkdir(parents=True, exist_ok=True)
    tasks = grid / "tasks"
    tasks.mkdir()
    rows: list[dict[str, Any]] = []
    blocked = (
        "test_access_authorized", "registry_mutation_authorized",
        "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
    )
    for row in source.itertuples(index=False):
        old_task = Path(row.task_config)
        if sha256(old_task) != str(row.task_config_sha256):
            raise RuntimeError(f"Changed R75 task config: {old_task}")
        payload = json.loads(old_task.read_text())
        for name in blocked:
            if boolish(payload.get(name, False)):
                raise RuntimeError(f"R75 source authorizes forbidden action: {name}")
        for name, expected in (
            ("runtime_manifest", payload["runtime_manifest_sha256"]),
            ("al_beta_path", payload["al_beta_sha256"]),
            ("al_parameter_path", payload["al_parameter_sha256"]),
        ):
            if sha256(Path(payload[name])) != expected:
                raise RuntimeError(f"Changed R75B source: {payload[name]}")
        task_id = str(row.task_id).replace("__r75_probe", "__r75b_stability")
        task = dict(payload)
        task.update({
            "task_id": task_id,
            "output_dir": str((args.run_dir.resolve() / task_id)),
            "max_iter": int(args.max_iter),
            "n_samp": int(args.n_samp),
            "n_samp_xi": int(args.n_samp_xi),
            "structured_grid_size": int(args.structured_grid_size),
            "structured_span_sd": 6.0,
            "rhs_freeze_tau_iters": 50,
            "rhs_freeze_tau_warmup_iters": 50,
            "sigmagam_freeze_warmup_iters": 10,
            "postwarmup_damping": 0.2,
            "postwarmup_damping_iters": 30,
            "min_postwarmup_updates": 35,
            "selection_split": "train_stability_probe",
            "probe_phase": "late_iteration_stability",
            "launch_authorized": False,
        })
        task_path = tasks / f"{task_id}.json"
        write_json(task_path, task)
        item = dict(row._asdict())
        item.update(task)
        item.update({
            "task_config": str(task_path.resolve()),
            "task_config_sha256": sha256(task_path),
            "source_r75_task_config": str(old_task.resolve()),
            "source_r75_task_config_sha256": str(row.task_config_sha256),
        })
        rows.append(item)
    manifest = pd.DataFrame(rows).sort_values(["region", "fold", "tau"])
    manifest.to_csv(grid / "probe_manifest.csv", index=False)
    checks = pd.DataFrame([
        {"gate": "exact_nine_cell_surface", "passed": len(manifest) == 9, "observed": len(manifest)},
        {"gate": "production_temporal_schedule", "passed": bool(
            manifest.rhs_freeze_tau_iters.eq(50).all()
            and manifest.sigmagam_freeze_warmup_iters.eq(10).all()
            and manifest.postwarmup_damping_iters.eq(30).all()
            and manifest.min_postwarmup_updates.eq(35).all()
        ), "observed": "rhs50;sigmagam10;damping30;updates35"},
        {"gate": "late_iteration_budget", "passed": manifest.max_iter.ge(80).all(), "observed": int(manifest.max_iter.min())},
        {"gate": "source_hashes_verified", "passed": True, "observed": 9},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
        {"gate": "not_automatically_launched", "passed": not manifest.launch_authorized.map(boolish).any(), "observed": "blocked_by_prep"},
    ])
    if not checks.passed.all():
        raise RuntimeError("R75B preparation gates failed")
    checks.to_csv(output / "pricefm_stage_r75b_stability_prep_gates.csv", index=False)
    sources = [Path(__file__).resolve(), args.r75_manifest.resolve(), args.r75_gate.resolve()]
    sources.extend(Path(value) for value in manifest.source_r75_task_config)
    pd.DataFrame([
        {"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in dict.fromkeys(path.resolve() for path in sources)
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "prepared_longer_train_only_stability_probe_not_launched",
        "tasks": 9,
        "cases": int(manifest.case_id.nunique()),
        "max_iter": int(args.max_iter),
        "probe_rows": int(manifest.probe_rows.min()),
        "r76_broad_launch_authorized": False,
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    write_json(output / "summary.json", summary)
    if list(grid.rglob("*.yaml")) or list(grid.rglob("*.yml")):
        raise RuntimeError("R75B must not create launch YAML")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
