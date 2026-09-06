#!/usr/bin/env python3
"""Prepare the validation-only R76 repaired-exAL surface without launching it."""

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
R69B = DATA / "experiment_grids/pricefm_stage_r69b_bounded_cran111_independent_vb_20260831/case_manifest.csv"
R73 = DATA / "authoritative/pricefm_stage_r73_completed_al_surface_20260902"
R75_RUNTIME = DATA / "runtime_libraries/exdqlm_pricefm_r75_large_n_gig_repair"
R75_RUNTIME_MANIFEST = R75_RUNTIME / "pricefm_stage_r75_large_n_gig_repair_manifest.json"
R75B_GATE = DATA / "authoritative/pricefm_stage_r75b_large_n_gig_stability_gate_20260902/summary.json"
TAG = "pricefm_stage_r76_repaired_exal_surface_20260902"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r76_repaired_exal_launch_prep_20260902"
BASE_SHA256 = "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
BLOCKED = (
    "test_access_authorized", "registry_mutation_authorized",
    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r69b-manifest", type=Path, default=R69B)
    p.add_argument("--r73-dir", type=Path, default=R73)
    p.add_argument("--runtime-manifest", type=Path, default=R75_RUNTIME_MANIFEST)
    p.add_argument("--stability-gate", type=Path, default=R75B_GATE)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-cases", type=int, default=42)
    p.add_argument("--expected-tasks", type=int, default=294)
    p.add_argument("--recommended-workers", type=int, default=20)
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


def tau_slug(tau: float) -> str:
    return f"{tau:.12f}".rstrip("0").rstrip(".").replace(".", "p")


def beta_path(atom: Any) -> Path:
    parent = Path(atom.prediction_path).parent
    return parent / ("al_beta_mean.csv" if atom.source_stage == "R69B" else "beta_summary.csv")


def run(args: argparse.Namespace) -> dict[str, Any]:
    cases = pd.read_csv(args.r69b_manifest)
    atoms_path = args.r73_dir / "pricefm_stage_r73_al_atom_ledger.csv"
    atoms = pd.read_csv(atoms_path)
    r73_summary_path = args.r73_dir / "summary.json"
    r73_summary = json.loads(r73_summary_path.read_text())
    runtime = json.loads(args.runtime_manifest.read_text())
    stability = json.loads(args.stability_gate.read_text())
    selected = cases[cases.selected_family_anchor.eq("exal")].sort_values(["region", "fold"])
    if r73_summary.get("al_atoms") != 392 or len(atoms) != 392:
        raise RuntimeError("R76 requires the complete 392-atom R73 AL surface")
    if len(selected) != args.expected_cases:
        raise RuntimeError(f"Expected {args.expected_cases} exAL-anchor cases, observed {len(selected)}")
    if stability.get("r76_broad_launch_authorized") is not True or stability.get("test_opened") is not False:
        raise RuntimeError("R75B stability gate does not authorize R76 preparation")
    package = runtime.get("installed_package") or {}
    if (
        runtime.get("status") != "installed_pricefm_local_large_n_gig_repair"
        or runtime.get("base_tarball_sha256") != BASE_SHA256
        or package.get("version") != "1.1.1.9002"
        or package.get("repository") != "PriceFM-local"
        or package.get("repair") != "scale-aware-SPD-plus-large-n-GIG"
    ):
        raise RuntimeError("R76 runtime provenance is invalid")
    for name in BLOCKED:
        if cases[name].map(boolish).any():
            raise RuntimeError(f"R69B source authorizes forbidden action: {name}")

    grid = prepare(args.grid_dir, args.force)
    output = prepare(args.output_dir, args.force)
    args.run_dir.mkdir(parents=True, exist_ok=True)
    tasks_dir = grid / "tasks"
    tasks_dir.mkdir()
    rows: list[dict[str, Any]] = []
    for case in selected.itertuples(index=False):
        source_config = Path(case.config)
        if sha256(source_config) != str(case.config_sha256):
            raise RuntimeError(f"Changed R69B case config: {case.case_id}")
        config = yaml.safe_load(source_config.read_text())["pricefm_desn_smoke"]
        if config.get("splits") != ["train", "val"]:
            raise RuntimeError(f"Non-validation-only R69B config: {case.case_id}")
        adapter = Path(case.adapter_dir)
        required_adapter = ["X_train.csv", "y_train.csv", "X_val.csv", "y_val.csv", "rows_val.csv"]
        if not all((adapter / name).is_file() for name in required_adapter):
            raise RuntimeError(f"Incomplete R76 adapter: {adapter}")
        if any((adapter / name).exists() for name in ("X_test.csv", "y_test.csv", "rows_test.csv")):
            raise RuntimeError(f"Test data present in R76 adapter: {adapter}")
        qcfg = config.get("qdesn_vb") or {}
        profile = qcfg.get("sigmagam") or {}
        case_atoms = atoms[atoms.case_id.eq(case.case_id)].sort_values("tau")
        if len(case_atoms) != 7:
            raise RuntimeError(f"Incomplete R73 AL warm-start surface: {case.case_id}")
        for tau in QUANTILES:
            matches = case_atoms[(case_atoms.tau.astype(float) - tau).abs().lt(1e-10)]
            if len(matches) != 1:
                raise RuntimeError(f"Missing AL warm start: {case.case_id} tau={tau}")
            atom = next(matches.itertuples(index=False))
            beta = beta_path(atom)
            parameter = Path(atom.parameter_path)
            if not beta.is_file() or not parameter.is_file():
                raise FileNotFoundError(beta if not beta.is_file() else parameter)
            task_id = f"{case.case_id}__tau_{tau_slug(tau)}__exal"
            task_output = args.run_dir.resolve() / case.case_id / "components" / f"tau={tau_slug(tau)}" / "exal"
            task = {
                "stage": "R76",
                "task_id": task_id,
                "case_id": case.case_id,
                "region": case.region,
                "fold": int(case.fold),
                "tau": tau,
                "likelihood_family": "exal",
                "method_id": "qdesn_exal_rhs_ns_pricefm_r76_large_n_gig_repair",
                "package_authority": "exact_CRAN_exdqlm_1.1.1_plus_PriceFM_local_numerical_repairs",
                "source_case_config": str(source_config.resolve()),
                "source_case_config_sha256": str(case.config_sha256),
                "adapter_dir": str(adapter.resolve()),
                "output_dir": str(task_output),
                "r_library": str(Path(runtime["library"]).resolve()),
                "runtime_manifest": str(args.runtime_manifest.resolve()),
                "runtime_manifest_sha256": sha256(args.runtime_manifest),
                "base_tarball_sha256": BASE_SHA256,
                "al_beta_path": str(beta.resolve()),
                "al_beta_sha256": sha256(beta),
                "al_parameter_path": str(parameter.resolve()),
                "al_parameter_sha256": sha256(parameter),
                "al_source_stage": atom.source_stage,
                "al_source_terminal": str(Path(atom.terminal_path).resolve()),
                "al_source_terminal_sha256": str(atom.terminal_sha256),
                "rhs_tau0": float(case.rhs_tau0),
                "rhs_init_tau": 1.0,
                "rhs_freeze_tau_iters": 50,
                "rhs_freeze_tau_warmup_iters": 50,
                "max_iter": max(150, int(qcfg.get("max_iter", 150))),
                "tol": float(qcfg.get("tol", 1e-4)),
                "n_samp": max(200, int(qcfg.get("n_samp", 200))),
                "n_samp_xi": max(200, int(qcfg.get("n_samp_xi", 200))),
                "structured_grid_size": max(151, int(profile.get("structured_grid_size", 151))),
                "structured_span_sd": max(6.0, float(profile.get("structured_span_sd", 6.0))),
                "sigmagam_freeze_warmup_iters": 10,
                "postwarmup_damping": 0.2,
                "postwarmup_damping_iters": 30,
                "min_postwarmup_updates": 35,
                "seed": 20260902 + int(case.fold) * 1000 + int(round(tau * 100)),
                "selection_split": "val",
                "selection_is_validation_only": True,
                "launch_authorized": False,
                "test_access_authorized": False,
                "registry_mutation_authorized": False,
                "article_mutation_authorized": False,
                "joint_model_authorized": False,
                "mcmc_authorized": False,
            }
            task_path = tasks_dir / f"{task_id}.json"
            write_json(task_path, task)
            rows.append({
                **task,
                "task_config": str(task_path.resolve()),
                "task_config_sha256": sha256(task_path),
                "selected_family_anchor": case.selected_family_anchor,
                "feature_policy": case.feature_policy,
                "depth_D": int(case.depth_D),
                "units_json": case.units_json,
                "lag_window": int(case.lag_window),
                "alpha": float(case.alpha),
                "rho": float(case.rho),
                "input_scale": float(case.input_scale),
            })
    manifest = pd.DataFrame(rows).sort_values(["region", "fold", "tau"])
    manifest.to_csv(grid / "task_manifest.csv", index=False)
    launch_control = {
        "stage": "R76",
        "tag": TAG,
        "task_manifest": str((grid / "task_manifest.csv").resolve()),
        "tasks": int(len(manifest)),
        "cases": int(manifest.case_id.nunique()),
        "recommended_workers": int(args.recommended_workers),
        "one_process_per_logical_cpu": True,
        "threads_per_process": 1,
        "resume_policy": "skip_only_hash_valid_completed_atomic_tasks",
        "launch_authorized_by_prep": False,
        "test_access": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    write_json(grid / "launch_control.json", launch_control)
    checks = pd.DataFrame([
        {"gate": "exact_exal_anchor_cases", "passed": manifest.case_id.nunique() == args.expected_cases, "observed": manifest.case_id.nunique()},
        {"gate": "exact_atomic_task_count", "passed": len(manifest) == args.expected_tasks, "observed": len(manifest)},
        {"gate": "seven_quantiles_per_case", "passed": manifest.groupby("case_id").tau.nunique().eq(7).all(), "observed": manifest.groupby("case_id").tau.nunique().value_counts().to_dict()},
        {"gate": "exal_only_no_al_refits", "passed": manifest.likelihood_family.eq("exal").all(), "observed": manifest.likelihood_family.value_counts().to_dict()},
        {"gate": "case_specific_specs_and_tau0_preserved", "passed": True, "observed": "R69B config hashes verified"},
        {"gate": "al_warm_starts_hash_frozen", "passed": True, "observed": len(manifest)},
        {"gate": "r75b_stability_gate_passed", "passed": True, "observed": stability.get("status")},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
        {"gate": "launch_requires_explicit_authorization", "passed": not manifest.launch_authorized.map(boolish).any(), "observed": "blocked_by_prep"},
    ])
    if not checks.passed.all():
        raise RuntimeError("R76 launch-preparation gates failed")
    checks.to_csv(output / "pricefm_stage_r76_launch_prep_gates.csv", index=False)
    sources = [Path(__file__).resolve(), args.r69b_manifest.resolve(), atoms_path.resolve(),
               r73_summary_path.resolve(), args.runtime_manifest.resolve(), args.stability_gate.resolve(),
               grid / "task_manifest.csv", grid / "launch_control.json"]
    pd.DataFrame([
        {"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in sources
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "prepared_repaired_exal_surface_not_launched",
        "cases": int(manifest.case_id.nunique()),
        "tasks": int(len(manifest)),
        "quantiles_per_case": 7,
        "al_atoms_reused": int(len(manifest)),
        "al_atoms_refit": 0,
        "exal_atoms_to_fit": int(len(manifest)),
        "recommended_workers": int(args.recommended_workers),
        "test_opened": False,
        "launch_authorized": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r76_launch_prep_report.md").write_text(
        "# PriceFM Stage-R76 Repaired-exAL Launch Preparation\n\n"
        f"Prepared {len(manifest)} independent exAL VB atoms for the {manifest.case_id.nunique()} "
        "historical exAL-anchor cases. Each case retains its R69B DESN and tau0 specification; "
        "each quantile reuses a hash-frozen R73 AL fit as initialization. No AL model is refit. "
        "Selection remains validation-only and all downstream mutation gates remain closed.\n"
    )
    if list(grid.rglob("*.yaml")) or list(grid.rglob("*.yml")):
        raise RuntimeError("R76 launch prep must not create YAML")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
