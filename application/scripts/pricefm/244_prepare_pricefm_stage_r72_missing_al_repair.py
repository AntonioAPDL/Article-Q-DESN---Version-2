#!/usr/bin/env python3
"""Prepare the missing-only Stage-R72 PriceFM AL repair campaign."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
from typing import Any

import pandas as pd
import yaml


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R69B_GRID = DATA / "experiment_grids/pricefm_stage_r69b_bounded_cran111_independent_vb_20260831"
R71 = DATA / "authoritative/pricefm_stage_r71_r70_closeout_20260901"
RUNTIME = DATA / "runtime_libraries/exdqlm_pricefm_r72_spd_repair"
RUNTIME_MANIFEST = RUNTIME / "pricefm_stage_r72_spd_repair_manifest.json"
TAG = "pricefm_stage_r72_missing_al_repair_20260901"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r72_missing_al_repair_prep_20260901"
METHOD = "qdesn_al_rhs_ns_pricefm_r72_spd_repair"
BASE_SHA256 = "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
BLOCKED = (
    "test_access_authorized", "registry_mutation_authorized",
    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
)


def parse_bool(value: str | bool) -> bool:
    if isinstance(value, bool):
        return value
    lowered = str(value).lower()
    if lowered in {"true", "1", "yes"}:
        return True
    if lowered in {"false", "0", "no"}:
        return False
    raise argparse.ArgumentTypeError(value)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r69b-manifest", type=Path, default=R69B_GRID / "case_manifest.csv")
    p.add_argument("--r71-dir", type=Path, default=R71)
    p.add_argument("--runtime-manifest", type=Path, default=RUNTIME_MANIFEST)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-tasks", type=int, default=142)
    p.add_argument("--recommended-workers", type=int, default=20)
    p.add_argument("--rhs-init-tau", type=float, default=1.0)
    p.add_argument("--rhs-freeze-iters", type=int, default=50)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"true", "1", "yes", "y"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def prepare_dir(path: Path, force: bool) -> Path:
    path = path.resolve()
    if path.exists() and any(path.iterdir()):
        if not force:
            raise FileExistsError(path)
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)
    return path


def tau_slug(tau: float) -> str:
    return f"{tau:.12f}".rstrip("0").rstrip(".").replace(".", "p")


def load_runtime(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text())
    package = payload.get("installed_package") or {}
    if (
        payload.get("status") != "installed_pricefm_local_spd_repair"
        or payload.get("base_tarball_sha256") != BASE_SHA256
        or package.get("version") != "1.1.1.9001"
        or package.get("repository") != "PriceFM-local"
    ):
        raise RuntimeError("R72 repair runtime manifest is invalid")
    return payload


def run(args: argparse.Namespace) -> dict[str, Any]:
    if args.rhs_init_tau <= 0 or args.rhs_freeze_iters < 0:
        raise RuntimeError("R72 RHS initialization schedule is invalid")
    r69b = pd.read_csv(args.r69b_manifest)
    salvage_path = args.r71_dir / "pricefm_stage_r71_atomic_fit_salvage_ledger.csv"
    summary_path = args.r71_dir / "pricefm_stage_r71_closeout_summary.json"
    salvage = pd.read_csv(salvage_path)
    r71_summary = json.loads(summary_path.read_text())
    runtime = load_runtime(args.runtime_manifest)
    if r71_summary.get("status") != "r70_frozen_closed_out_no_promotion":
        raise RuntimeError("R71 is not a frozen no-promotion closeout")
    source = salvage[
        salvage["likelihood_family"].eq("al")
        & salvage["disposition"].isin((
            "missing_requires_r72_refit", "invalid_requires_r72_refit"
        ))
    ].copy()
    if len(source) != args.expected_tasks:
        raise RuntimeError(f"Expected {args.expected_tasks} missing AL atoms, observed {len(source)}")
    if source.duplicated(["case_id", "tau"]).any():
        raise RuntimeError("R71 missing-AL queue is not unique")
    by_case = r69b.set_index("case_id")
    if not set(source.case_id).issubset(set(by_case.index)):
        raise RuntimeError("R71 contains cases outside R69B")
    for name in BLOCKED:
        if r69b[name].map(boolish).any():
            raise RuntimeError(f"R69B source authorizes forbidden action: {name}")

    grid = prepare_dir(args.grid_dir, args.force)
    output = prepare_dir(args.output_dir, args.force)
    args.run_dir.mkdir(parents=True, exist_ok=True)
    tasks_dir = grid / "tasks"
    tasks_dir.mkdir()
    rows: list[dict[str, Any]] = []
    for missing in source.sort_values(["region", "fold", "tau"]).itertuples(index=False):
        anchor = by_case.loc[missing.case_id]
        source_config = Path(anchor.config)
        if sha256(source_config) != str(anchor.config_sha256):
            raise RuntimeError(f"R69B source config hash changed: {missing.case_id}")
        config = yaml.safe_load(source_config.read_text())
        smoke = config["pricefm_desn_smoke"]
        if smoke.get("splits") != ["train", "val"]:
            raise RuntimeError(f"Non-validation-only source config: {source_config}")
        adapter = Path(anchor.adapter_dir)
        required_adapter = [
            adapter / "X_train.csv", adapter / "y_train.csv",
            adapter / "X_val.csv", adapter / "rows_val.csv",
        ]
        if not all(path.is_file() for path in required_adapter):
            raise RuntimeError(f"Incomplete R70 adapter: {adapter}")
        if any((adapter / name).exists() for name in ("X_test.csv", "y_test.csv", "rows_test.csv")):
            raise RuntimeError(f"Test files present in R72 adapter: {adapter}")
        tau = float(missing.tau)
        task_id = f"{missing.case_id}__tau_{tau_slug(tau)}__al"
        task_output = args.run_dir.resolve() / missing.case_id / "components" / f"tau={tau_slug(tau)}" / "al"
        qcfg = smoke.get("qdesn_vb") or {}
        task = {
            "stage": "R72", "task_id": task_id, "case_id": missing.case_id,
            "region": missing.region, "fold": int(missing.fold), "tau": tau,
            "likelihood_family": "al", "method_id": METHOD,
            "source_case_config": str(source_config.resolve()),
            "source_case_config_sha256": str(anchor.config_sha256),
            "adapter_dir": str(adapter.resolve()), "output_dir": str(task_output),
            "r_library": str(Path(runtime["library"]).resolve()),
            "runtime_manifest": str(args.runtime_manifest.resolve()),
            "runtime_manifest_sha256": sha256(args.runtime_manifest),
            "base_tarball_sha256": BASE_SHA256,
            "repair_patch_sha256": runtime["patch_sha256"],
            "max_iter": max(150, int(qcfg.get("max_iter", 150))),
            "tol": float(qcfg.get("tol", 1e-4)),
            "n_samp": max(200, int(qcfg.get("n_samp", 200))),
            "n_samp_xi": max(200, int(qcfg.get("n_samp_xi", 200))),
            "rhs_tau0": float(anchor.rhs_tau0), "rhs_init_tau": args.rhs_init_tau,
            "rhs_freeze_tau_iters": args.rhs_freeze_iters,
            "rhs_freeze_tau_warmup_iters": args.rhs_freeze_iters,
            "seed": 20260901 + int(missing.fold) * 1000 + int(round(tau * 100)),
            "selection_split": "val", "selection_is_validation_only": True,
            "exal_mechanism_gate_passed": False,
            "launch_authorized": False,
            "test_access_authorized": False, "registry_mutation_authorized": False,
            "article_mutation_authorized": False, "joint_model_authorized": False,
            "mcmc_authorized": False,
        }
        task_path = tasks_dir / f"{task_id}.json"
        write_json(task_path, task)
        rows.append({
            **task,
            "task_config": str(task_path.resolve()),
            "task_config_sha256": sha256(task_path),
            "feature_policy": anchor.feature_policy,
            "depth_D": int(anchor.depth_D), "units_json": anchor.units_json,
            "lag_window": int(anchor.lag_window), "alpha": float(anchor.alpha),
            "rho": float(anchor.rho), "input_scale": float(anchor.input_scale),
            "source_r70_disposition": missing.disposition,
        })
    manifest = pd.DataFrame(rows)
    manifest.to_csv(grid / "task_manifest.csv", index=False)
    launch_control = {
        "stage": "R72", "tag": TAG, "task_manifest": str((grid / "task_manifest.csv").resolve()),
        "tasks": len(manifest), "recommended_workers": args.recommended_workers,
        "one_process_per_logical_cpu": True, "threads_per_process": 1,
        "resume_policy": "skip_only_hash_valid_completed_atomic_tasks",
        "launch_authorized_by_prep": False, "test_access": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "joint_model_authorized": False, "mcmc_authorized": False,
    }
    write_json(grid / "launch_control.json", launch_control)
    gates = pd.DataFrame([
        {"gate": "exact_missing_al_count", "passed": len(manifest) == args.expected_tasks, "observed": len(manifest)},
        {"gate": "no_exal_tasks", "passed": manifest.likelihood_family.eq("al").all(), "observed": "+".join(sorted(manifest.likelihood_family.unique()))},
        {"gate": "task_ids_unique", "passed": not manifest.task_id.duplicated().any(), "observed": manifest.task_id.nunique()},
        {"gate": "case_specs_preserved", "passed": True, "observed": "R69B config hashes verified"},
        {"gate": "rhs_schedule_materialized", "passed": bool((manifest.rhs_init_tau == args.rhs_init_tau).all() and (manifest.rhs_freeze_tau_iters == args.rhs_freeze_iters).all()), "observed": f"init_tau={args.rhs_init_tau};freeze={args.rhs_freeze_iters}"},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
        {"gate": "launch_not_automatic", "passed": not manifest.launch_authorized.map(boolish).any(), "observed": "blocked_by_prep"},
    ])
    if not gates.passed.all():
        raise RuntimeError("R72 launch-prep gates failed")
    gates.to_csv(output / "pricefm_stage_r72_launch_prep_gates.csv", index=False)
    sources = [Path(__file__).resolve(), args.r69b_manifest.resolve(), salvage_path.resolve(),
               summary_path.resolve(), args.runtime_manifest.resolve(), grid / "task_manifest.csv"]
    pd.DataFrame([
        {"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in sources
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "prepared_missing_only_al_repair_not_launched",
        "tasks": int(len(manifest)), "cases": int(manifest.case_id.nunique()),
        "likelihoods": ["al"], "existing_r70_al_atoms_reused": 250,
        "r70_exal_atoms_quarantined": 250, "exal_tasks": 0,
        "rhs_init_tau": args.rhs_init_tau, "rhs_freeze_iters": args.rhs_freeze_iters,
        "test_opened": False, "launch_authorized": False,
        "registry_mutated": False, "article_mutated": False,
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r72_launch_prep_report.md").write_text(
        "# PriceFM Stage-R72 Missing-AL Repair Prep\n\n"
        f"Prepared {len(manifest)} atomic AL tasks across {manifest.case_id.nunique()} cases. "
        "Each task preserves its R69B case-specific DESN and tau0 anchor, uses explicit "
        f"RHS init_tau={args.rhs_init_tau:g} and a {args.rhs_freeze_iters}-iteration tau warm-up, and reads train/validation only. "
        "The 250 existing R70 AL atoms are reused; all structured-exAL atoms remain blocked.\n"
    )
    if list(grid.rglob("*.yaml")) or list(grid.rglob("*.yml")):
        raise RuntimeError("R72 prep must not create YAML")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
