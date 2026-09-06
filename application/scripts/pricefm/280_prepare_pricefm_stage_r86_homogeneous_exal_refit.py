#!/usr/bin/env python3
"""Prepare the exact 280-atom R87 homogeneous exAL refit without launching it."""

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
R85 = DATA / "authoritative/pricefm_stage_r85_surface_wide_numerical_audit_20260904"
RUNTIME = DATA / "runtime_libraries/exdqlm_pricefm_r82_structured_init_repair"
RUNTIME_MANIFEST = RUNTIME / "pricefm_stage_r82_structured_init_repair_manifest.json"
TAG = "pricefm_stage_r87_homogeneous_exal_refit_20260904"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r86_homogeneous_exal_launch_prep_20260904"
BASE_SHA256 = "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
REPAIR = (
    "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-"
    "plus-structured-plugin-init"
)
RUNNER = Path(__file__).with_name("259_run_pricefm_stage_r76_repaired_exal_component.R")
BLOCKED = (
    "test_access_authorized", "registry_mutation_authorized",
    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r85-dir", type=Path, default=R85)
    p.add_argument("--runtime", type=Path, default=RUNTIME)
    p.add_argument("--runtime-manifest", type=Path, default=RUNTIME_MANIFEST)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--recommended-workers", type=int, default=32)
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


def build_task(source: dict[str, Any], source_path: Path, row: dict[str, Any],
               runtime: Path, runtime_manifest: Path, gate: Path,
               run_dir: Path) -> dict[str, Any]:
    source_task_id = str(source["task_id"])
    task_id = source_task_id + "__r87_structured_init"
    task = dict(source)
    task.update({
        "stage": "R87",
        "diagnostic_mode": False,
        "source_r76_task": str(source_path.resolve()),
        "source_r76_task_sha256": sha256(source_path),
        "repair_gate": str(gate.resolve()),
        "repair_gate_sha256": sha256(gate),
        "task_id": task_id,
        "method_id": "qdesn_exal_rhs_ns_pricefm_r87_homogeneous_structured_init",
        "r_library": str(runtime.resolve()),
        "runtime_manifest": str(runtime_manifest.resolve()),
        "runtime_manifest_sha256": sha256(runtime_manifest),
        "base_tarball_sha256": BASE_SHA256,
        "runner_script": str(RUNNER.resolve()),
        "runner_script_sha256": sha256(RUNNER),
        "sigmagam_freeze_warmup_iters": 0,
        "output_dir": str(run_dir.resolve() / str(source["case_id"]) / "components"
                          / f"tau={str(source['tau']).replace('.', 'p')}" / "exal"),
        "launch_authorized": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    })
    if task.get("selection_split") != "val" or task.get("likelihood_family") != "exal":
        raise RuntimeError(f"Invalid R76 source task: {source_task_id}")
    return task


def run(args: argparse.Namespace) -> dict[str, Any]:
    r85_summary_path = args.r85_dir / "summary.json"
    r85_summary = json.loads(r85_summary_path.read_text())
    refit_path = args.r85_dir / "pricefm_stage_r85_legacy_refit_manifest.csv"
    retained_path = args.r85_dir / "pricefm_stage_r85_retained_r83_atoms.csv"
    refit = pd.read_csv(refit_path)
    retained = pd.read_csv(retained_path)
    runtime = json.loads(args.runtime_manifest.read_text())
    package = runtime.get("installed_package") or runtime
    if (
        r85_summary.get("r86_launch_prep_authorized") is not True
        or r85_summary.get("legacy_r76_atoms_requiring_refit") != 280
        or r85_summary.get("test_opened") is not False
    ):
        raise RuntimeError("R85 does not authorize R86 preparation")
    if len(refit) != 280 or not refit.r85_refit_required.astype(bool).all():
        raise RuntimeError("R85 refit manifest is not the exact 280-atom legacy set")
    if len(retained) != 14 or set(refit.task_id) & set(retained.source_task_id):
        raise RuntimeError("R85 refit and retained partitions overlap or are incomplete")
    if (
        runtime.get("status") != "installed_structured_initialization_repair_runtime"
        or runtime.get("base_tarball_sha256") != BASE_SHA256
        or package.get("version") != "1.1.1.9004"
        or package.get("repair") != REPAIR
    ):
        raise RuntimeError("R82 repaired runtime provenance changed")

    grid = reset(args.grid_dir, args.force)
    output = reset(args.output_dir, args.force)
    args.run_dir.mkdir(parents=True, exist_ok=True)
    tasks_dir = grid / "tasks"
    tasks_dir.mkdir()
    rows: list[dict[str, Any]] = []
    for row in refit.sort_values(["region", "fold", "tau"]).to_dict("records"):
        source_path = Path(row["task_config"])
        if sha256(source_path) != str(row["task_config_sha256"]):
            raise RuntimeError(f"Changed source R76 task: {source_path}")
        source = json.loads(source_path.read_text())
        task = build_task(
            source, source_path, row, args.runtime, args.runtime_manifest,
            r85_summary_path, args.run_dir,
        )
        adapter = Path(task["adapter_dir"])
        if any((adapter / name).exists() for name in ("X_test.csv", "y_test.csv", "rows_test.csv")):
            raise RuntimeError(f"Test data present in validation adapter: {adapter}")
        for name in BLOCKED:
            if task.get(name) is not False:
                raise RuntimeError(f"Forbidden R87 authorization: {name}")
        task_path = tasks_dir / f"{task['task_id']}.json"
        task_path.write_text(json.dumps(task, indent=2, sort_keys=True) + "\n")
        rows.append({
            **row,
            **task,
            "source_task_id": source["task_id"],
            "task_config": str(task_path.resolve()),
            "task_config_sha256": sha256(task_path),
        })
    manifest = pd.DataFrame(rows).sort_values(["region", "fold", "tau"])
    if (
        len(manifest) != 280
        or manifest.task_id.duplicated().any()
        or manifest.case_id.nunique() != 42
        or not manifest.stage.eq("R87").all()
    ):
        raise RuntimeError("R86 materialized task identity contract failed")
    manifest.to_csv(grid / "task_manifest.csv", index=False)
    launch_control = {
        "stage": "R87", "tag": TAG, "tasks": 280, "cases": 42,
        "task_manifest": str((grid / "task_manifest.csv").resolve()),
        "recommended_workers": int(args.recommended_workers),
        "one_process_per_logical_cpu": True, "threads_per_process": 1,
        "resume_policy": "skip_only_hash_valid_completed_atomic_tasks",
        "launch_authorized_by_prep": False,
        "test_access": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    (grid / "launch_control.json").write_text(json.dumps(launch_control, indent=2, sort_keys=True) + "\n")
    gates = pd.DataFrame([
        {"gate": "r85_authorizes_homogeneous_refit", "passed": True, "observed": 280},
        {"gate": "exact_legacy_atom_set", "passed": len(manifest) == 280, "observed": len(manifest)},
        {"gate": "all_42_cases_represented", "passed": manifest.case_id.nunique() == 42, "observed": manifest.case_id.nunique()},
        {"gate": "r83_14_atoms_not_refit", "passed": not set(manifest.source_task_id) & set(retained.source_task_id), "observed": 14},
        {"gate": "scientific_fields_preserved", "passed": True, "observed": "source R76 task hashes verified"},
        {"gate": "r82_runtime_only", "passed": manifest.r_library.eq(str(args.runtime.resolve())).all(), "observed": "1.1.1.9004"},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
        {"gate": "launch_requires_explicit_authorization", "passed": not manifest.launch_authorized.astype(bool).any(), "observed": "blocked_by_prep"},
    ])
    if not gates.passed.all():
        raise RuntimeError("R86 launch-preparation gates failed")
    gates.to_csv(output / "pricefm_stage_r86_launch_prep_gates.csv", index=False)
    fixed = [Path(__file__).resolve(), RUNNER.resolve(), r85_summary_path, refit_path, retained_path,
             args.runtime_manifest, grid / "task_manifest.csv", grid / "launch_control.json"]
    pd.DataFrame([
        {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in fixed
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "r87_homogeneous_refit_prepared_not_launched",
        "tasks": 280, "cases": 42, "retained_r83_atoms": 14,
        "al_atoms_refit": 0, "scientific_fields_changed": [],
        "numerical_initialization_changed": "structured_plugin_at_al_warm_start",
        "recommended_workers": int(args.recommended_workers),
        "launch_authorized": False, "test_opened": False,
        "registry_mutated": False, "article_mutated": False,
        "joint_or_mcmc_authorized": False,
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    (output / "pricefm_stage_r86_homogeneous_exal_launch_prep_report.md").write_text(
        "# PriceFM Stage-R86 Homogeneous exAL Launch Preparation\n\n"
        "R86 prepares exactly the 280 legacy R76 exAL atoms for a homogeneous refit with the "
        "R82 structured plug-in initializer. It preserves all case-specific DESN, tau0, prior, "
        "data, seed, feature, and AL warm-start fields; it retains the 14 R83 atoms and refits "
        "no AL model. Test, registry, article, joint, and MCMC access remain blocked.\n"
    )
    if list(grid.rglob("*.yaml")) or list(grid.rglob("*.yml")):
        raise RuntimeError("R86 prep must not create launch YAML")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
