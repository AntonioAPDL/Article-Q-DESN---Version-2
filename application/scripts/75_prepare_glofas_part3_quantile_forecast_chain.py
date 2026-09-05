#!/usr/bin/env python3
"""Prepare the frozen Part 3 Normal/quantile fixed-origin forecast DAG."""

import argparse
import csv
import hashlib
import json
import shlex
from pathlib import Path


TAUS = ("0.05", "0.20", "0.35", "0.50", "0.65", "0.80", "0.95")


def slug(tau: str) -> str:
    return "q" + tau.replace(".", "p")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def shell_join(parts) -> str:
    return " ".join(shlex.quote(str(part)) for part in parts)


def read_csv(path: Path):
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--max-iter", type=int, default=100)
    parser.add_argument("--min-iter", type=int, default=30)
    parser.add_argument("--tol", type=float, default=0.01)
    parser.add_argument("--horizon-days", type=int, default=30)
    parser.add_argument("--normal-draws", type=int, default=500)
    parser.add_argument("--forecast-backend", choices=("auto", "cpp", "r"), default="auto")
    args = parser.parse_args()

    repo = Path(args.repo_root).resolve()
    runtime = Path(args.runtime_root).resolve()
    certificate_path = runtime / "configs" / "part3_preflight_certificate.csv"
    inventory_path = runtime / "configs" / "part3_normal_fit_inventory.csv"
    if not certificate_path.exists() or not inventory_path.exists():
        raise SystemExit("Run 72_prepare_glofas_part3_quantile_forecast_runtime.R first.")
    certificate = read_csv(certificate_path)
    inventory = {row["model_family"]: row for row in read_csv(inventory_path)}
    if len(certificate) != 1 or certificate[0]["status"] != "ready_for_part3_quantile_forecast_chain":
        raise SystemExit("Part 3 preflight certificate is invalid.")
    design_cache = Path(certificate[0]["design_cache"])
    design_sha = certificate[0]["design_cache_sha256"]
    if not design_cache.exists() or sha256(design_cache) != design_sha:
        raise SystemExit("Part 3 design-cache hash does not match its certificate.")
    for family in ("normal_ridge_joint", "normal_rhs_vb_joint"):
        row = inventory.get(family)
        if not row or sha256(Path(row["fit_path"])) != row["fit_sha256"]:
            raise SystemExit(f"Normal prerequisite failed validation: {family}")
    if args.min_iter < 1 or args.max_iter < args.min_iter or args.tol <= 0:
        raise SystemExit("Invalid Part 3 VB controls.")

    rows = []

    def add(job_id, phase, dependencies, command):
        rows.append({
            "job_id": job_id,
            "phase": phase,
            "dependencies": "|".join(dependencies),
            "status": "pending",
            "worker_slots": "1",
            "command_json": json.dumps(command),
            "command": shell_join(command),
        })

    normal_script = str(repo / "application/scripts/73_run_glofas_part3_normal_forecast.R")
    for family, method in (("normal_ridge_joint", "ridge"), ("normal_rhs_vb_joint", "rhs")):
        job = family.replace("_joint", "") + "_forecast"
        inv = inventory[family]
        add(job, "normal_forecast", [], [
            "Rscript", normal_script,
            "--runtime_root", str(runtime),
            "--design_cache", str(design_cache),
            "--design_cache_sha256", design_sha,
            "--fit_path", inv["fit_path"],
            "--fit_sha256", inv["fit_sha256"],
            "--method", method,
            "--job_id", job,
            "--horizon_days", str(args.horizon_days),
            "--n_draws", str(args.normal_draws),
            "--seed", "20260904" if method == "ridge" else "20260905",
            "--backend", args.forecast_backend,
        ])

    fit_script = str(repo / "application/scripts/74_run_glofas_part3_quantile_fit_forecast.R")
    fit_path = lambda job: str(runtime / "objects" / f"{job}_fit.rds")
    al_parent = {
        "0.50": "normal_rhs_forecast",
        "0.35": "independent_al_q0p50", "0.20": "independent_al_q0p35", "0.05": "independent_al_q0p20",
        "0.65": "independent_al_q0p50", "0.80": "independent_al_q0p65", "0.95": "independent_al_q0p80",
    }
    for tau in ("0.50", "0.35", "0.65", "0.20", "0.80", "0.05", "0.95"):
        job = f"independent_al_{slug(tau)}"
        parent = al_parent[tau]
        init_path = inventory["normal_rhs_vb_joint"]["fit_path"] if tau == "0.50" else fit_path(parent)
        add(job, "independent_al_fit_forecast", [parent], [
            "Rscript", fit_script,
            "--runtime_root", str(runtime), "--design_cache", str(design_cache),
            "--design_cache_sha256", design_sha, "--job_id", job,
            "--likelihood", "AL", "--fit_structure", "independent", "--tau", tau,
            "--init_fit_paths", init_path, "--max_iter", str(args.max_iter),
            "--min_iter", str(args.min_iter), "--tol", str(args.tol),
            "--tau0_reference", "1", "--tau0_discrepancy", "0.001",
            "--slab_s2", "1", "--a_zeta", "2", "--b_zeta", "4",
            "--rhs_vb_inner", "5", "--progress_every", "1",
            "--horizon_days", str(args.horizon_days), "--backend", args.forecast_backend,
        ])

    for tau in TAUS:
        parent = f"independent_al_{slug(tau)}"
        job = f"independent_exal_{slug(tau)}"
        add(job, "independent_exal_fit_forecast", [parent], [
            "Rscript", fit_script,
            "--runtime_root", str(runtime), "--design_cache", str(design_cache),
            "--design_cache_sha256", design_sha, "--job_id", job,
            "--likelihood", "exAL", "--fit_structure", "independent", "--tau", tau,
            "--init_fit_paths", fit_path(parent), "--max_iter", str(args.max_iter),
            "--min_iter", str(args.min_iter), "--tol", str(args.tol),
            "--tau0_reference", "1", "--tau0_discrepancy", "0.001",
            "--slab_s2", "1", "--a_zeta", "2", "--b_zeta", "4",
            "--rhs_vb_inner", "5", "--progress_every", "1",
            "--horizon_days", str(args.horizon_days), "--backend", args.forecast_backend,
        ])

    tau_arg = "|".join(TAUS)
    al_jobs = [f"independent_al_{slug(tau)}" for tau in TAUS]
    exal_jobs = [f"independent_exal_{slug(tau)}" for tau in TAUS]
    for likelihood, dependencies in (("AL", al_jobs), ("exAL", exal_jobs)):
        job = f"joint_{likelihood.lower()}"
        add(job, f"joint_{likelihood.lower()}_fit_forecast", dependencies, [
            "Rscript", fit_script,
            "--runtime_root", str(runtime), "--design_cache", str(design_cache),
            "--design_cache_sha256", design_sha, "--job_id", job,
            "--likelihood", likelihood, "--fit_structure", "joint", "--tau", tau_arg,
            "--init_fit_paths", "|".join(fit_path(dep) for dep in dependencies),
            "--max_iter", str(args.max_iter), "--min_iter", str(args.min_iter), "--tol", str(args.tol),
            "--tau0_reference", "1", "--tau0_discrepancy", "0.001",
            "--slab_s2", "1", "--a_zeta", "2", "--b_zeta", "4",
            "--rhs_vb_inner", "5", "--progress_every", "1",
            "--horizon_days", str(args.horizon_days), "--backend", args.forecast_backend,
        ])

    manifest_path = runtime / "configs" / "part3_quantile_forecast_job_manifest.csv"
    write_csv(manifest_path, rows)
    metadata = {
        "schema_version": "glofas_part3_quantile_forecast_chain_v1",
        "repo_root": str(repo), "runtime_root": str(runtime),
        "design_cache": str(design_cache), "design_cache_sha256": design_sha,
        "jobs": len(rows), "normal_forecasts": 2, "quantile_fits_and_forecasts": 16,
        "max_iter": args.max_iter, "min_iter": args.min_iter, "tol": args.tol,
        "horizon_days": args.horizon_days, "normal_draws": args.normal_draws,
        "forecast_backend": args.forecast_backend,
        "scientific_scope": "part3_historical_bridge_fixed_origin_diagnostic_no_synthesis",
    }
    metadata_path = runtime / "configs" / "part3_quantile_forecast_chain_metadata.json"
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"manifest={manifest_path}")
    print(f"manifest_sha256={sha256(manifest_path)}")
    print(f"jobs={len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
