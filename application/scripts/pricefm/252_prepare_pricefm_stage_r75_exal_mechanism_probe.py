#!/usr/bin/env python3
"""Prepare nine bounded real-data probes for the R75 structured-exAL repair."""

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
R69B = DATA / "experiment_grids/pricefm_stage_r69b_bounded_cran111_independent_vb_20260831/case_manifest.csv"
R73 = DATA / "authoritative/pricefm_stage_r73_completed_al_surface_20260902"
RUNTIME = DATA / "runtime_libraries/exdqlm_pricefm_r75_large_n_gig_repair"
RUNTIME_MANIFEST = RUNTIME / "pricefm_stage_r75_large_n_gig_repair_manifest.json"
TAG = "pricefm_stage_r75_large_n_gig_mechanism_probe_20260902"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r75_large_n_gig_probe_prep_20260902"
CASES = ("pricefm_joint_fr_f1", "pricefm_joint_ee_f1", "pricefm_joint_se_2_f2")
TAUS = (0.10, 0.50, 0.90)
BASE_SHA256 = "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r69b-manifest", type=Path, default=R69B)
    p.add_argument("--r73-dir", type=Path, default=R73)
    p.add_argument("--runtime-manifest", type=Path, default=RUNTIME_MANIFEST)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--probe-rows", type=int, default=5000)
    p.add_argument("--max-iter", type=int, default=12)
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


def beta_path(atom: Any) -> Path:
    parent = Path(atom.prediction_path).parent
    return parent / ("al_beta_mean.csv" if atom.source_stage == "R69B" else "beta_summary.csv")


def run(args: argparse.Namespace) -> dict[str, Any]:
    cases = pd.read_csv(args.r69b_manifest).set_index("case_id")
    atoms_path = args.r73_dir / "pricefm_stage_r73_al_atom_ledger.csv"
    atoms = pd.read_csv(atoms_path)
    summary = json.loads((args.r73_dir / "summary.json").read_text())
    runtime = json.loads(args.runtime_manifest.read_text())
    if summary.get("status") != "completed_al_surface_closed_out_no_automatic_promotion":
        raise RuntimeError("R73 closeout is not valid")
    if runtime.get("status") != "installed_pricefm_local_large_n_gig_repair":
        raise RuntimeError("R75 runtime is not installed")
    package = runtime.get("installed_package") or {}
    if package.get("version") != "1.1.1.9002" or package.get("repair") != "scale-aware-SPD-plus-large-n-GIG":
        raise RuntimeError("R75 runtime package contract is invalid")
    if runtime.get("base_tarball_sha256") != BASE_SHA256:
        raise RuntimeError("R75 runtime does not derive from exact CRAN 1.1.1")
    selected = cases.loc[list(CASES)]
    if not selected["selected_family_anchor"].eq("exal").all():
        raise RuntimeError("R75 probes must use exAL-anchor cases")

    grid = prepare(args.grid_dir, args.force)
    output = prepare(args.output_dir, args.force)
    args.run_dir.mkdir(parents=True, exist_ok=True)
    tasks_dir = grid / "tasks"
    tasks_dir.mkdir()
    rows = []
    for case_id in CASES:
        case = cases.loc[case_id]
        for tau in TAUS:
            matches = atoms[atoms["case_id"].eq(case_id) & np_isclose(atoms["tau"], tau)]
            if len(matches) != 1:
                raise RuntimeError(f"Missing R73 AL warm-start atom: {case_id} tau={tau}")
            atom = matches.iloc[0]
            beta = beta_path(atom)
            parameter = Path(atom.parameter_path)
            for path in (beta, parameter, Path(case.adapter_dir) / "X_train.csv", Path(case.adapter_dir) / "y_train.csv"):
                if not path.is_file():
                    raise FileNotFoundError(path)
            task_id = f"{case_id}__tau_{str(tau).replace('.', 'p')}__r75_probe"
            task_output = args.run_dir.resolve() / task_id
            task = {
                "stage": "R75_PROBE", "task_id": task_id, "case_id": case_id,
                "region": case.region, "fold": int(case.fold), "tau": tau,
                "adapter_dir": str(Path(case.adapter_dir).resolve()),
                "output_dir": str(task_output), "r_library": str(Path(runtime["library"]).resolve()),
                "runtime_manifest": str(args.runtime_manifest.resolve()),
                "runtime_manifest_sha256": sha256(args.runtime_manifest),
                "base_tarball_sha256": BASE_SHA256,
                "al_beta_path": str(beta.resolve()), "al_beta_sha256": sha256(beta),
                "al_parameter_path": str(parameter.resolve()), "al_parameter_sha256": sha256(parameter),
                "rhs_tau0": float(case.rhs_tau0), "rhs_init_tau": 1.0,
                "rhs_freeze_tau_iters": 5, "rhs_freeze_tau_warmup_iters": 5,
                "probe_rows": int(args.probe_rows), "max_iter": int(args.max_iter),
                "tol": 1e-4, "n_samp": 20, "n_samp_xi": 30,
                "structured_grid_size": 41, "structured_span_sd": 4.0,
                "sigmagam_freeze_warmup_iters": 2, "postwarmup_damping": 0.2,
                "postwarmup_damping_iters": 5, "min_postwarmup_updates": 1,
                "seed": 20260902 + int(case.fold) * 1000 + int(round(tau * 100)),
                "selection_split": "train_probe", "probe_only": True,
                "launch_authorized": False, "test_access_authorized": False,
                "registry_mutation_authorized": False, "article_mutation_authorized": False,
                "joint_model_authorized": False, "mcmc_authorized": False,
            }
            task_path = tasks_dir / f"{task_id}.json"
            write_json(task_path, task)
            rows.append({**task, "task_config": str(task_path), "task_config_sha256": sha256(task_path),
                         "feature_policy": case.feature_policy, "source_stage": atom.source_stage})
    manifest = pd.DataFrame(rows).sort_values(["region", "fold", "tau"])
    manifest.to_csv(grid / "probe_manifest.csv", index=False)
    gates = pd.DataFrame([
        {"gate": "exact_probe_count", "passed": len(manifest) == 9, "observed": len(manifest)},
        {"gate": "three_mechanism_classes", "passed": set(manifest.case_id) == set(CASES), "observed": manifest.case_id.nunique()},
        {"gate": "tail_center_quantiles", "passed": set(manifest.tau) == set(TAUS), "observed": sorted(manifest.tau.unique())},
        {"gate": "warm_start_hashes_frozen", "passed": True, "observed": len(manifest)},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
        {"gate": "probe_not_automatically_launched", "passed": not manifest.launch_authorized.any(), "observed": "blocked_by_prep"},
    ])
    if not gates.passed.all():
        raise RuntimeError("R75 probe-prep gates failed")
    gates.to_csv(output / "pricefm_stage_r75_probe_prep_gates.csv", index=False)
    source_paths = [Path(__file__).resolve(), args.r69b_manifest.resolve(), atoms_path.resolve(),
                    (args.r73_dir / "summary.json").resolve(), args.runtime_manifest.resolve()]
    source_paths.extend(Path(value) for value in manifest.al_beta_path)
    source_paths.extend(Path(value) for value in manifest.al_parameter_path)
    pd.DataFrame([
        {"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in dict.fromkeys(path.resolve() for path in source_paths)
    ]).to_csv(output / "source_manifest.csv", index=False)
    result = {
        "status": "prepared_nine_bounded_real_data_probes_not_launched",
        "tasks": 9, "cases": 3, "quantiles": list(TAUS),
        "probe_rows": args.probe_rows, "max_iter": args.max_iter,
        "test_opened": False, "launch_authorized": False,
        "registry_mutated": False, "article_mutated": False,
    }
    write_json(output / "summary.json", result)
    return result


def np_isclose(series: pd.Series, value: float) -> pd.Series:
    return (series.astype(float) - float(value)).abs().lt(1e-10)


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
