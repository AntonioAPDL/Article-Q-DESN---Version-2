#!/usr/bin/env python3.11
"""Prepare the minimal 19-fit/19-forecast GloFAS quantile correction DAG."""

from __future__ import annotations

import argparse
import csv
import errno
import hashlib
import json
import os
import shlex
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

TAUS = (0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)


def qslug(tau: float) -> str:
    return f"q{tau:.2f}".replace(".", "p")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def link_verified(source: Path, destination: Path, imports: list[dict[str, object]], role: str) -> None:
    source = source.resolve(strict=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        if os.path.samefile(source, destination) or sha256(source) == sha256(destination):
            return
        raise RuntimeError(f"Refusing to replace nonidentical import: {destination}")
    try:
        os.link(source, destination)
    except OSError as error:
        if error.errno != errno.EXDEV:
            raise
        shutil.copy2(source, destination)
    imports.append({
        "role": role,
        "source_path": str(source),
        "destination_path": str(destination.resolve()),
        "bytes": source.stat().st_size,
        "sha256": sha256(source),
        "hardlinked": os.stat(source).st_ino == os.stat(destination).st_ino,
    })


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--part4-root", required=True)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--workers", type=int, default=30)
    parser.add_argument("--seed", type=int, default=20260920)
    args = parser.parse_args()

    if args.workers < 1 or args.workers > 30:
        raise SystemExit("The correction contract permits 1-30 one-thread workers")

    repo = Path(__file__).resolve().parents[2]
    source = (repo / args.source_root).resolve() if not Path(args.source_root).is_absolute() else Path(args.source_root).resolve()
    part4 = (repo / args.part4_root).resolve() if not Path(args.part4_root).is_absolute() else Path(args.part4_root).resolve()
    runtime = (repo / args.runtime_root).resolve() if not Path(args.runtime_root).is_absolute() else Path(args.runtime_root).resolve()
    if runtime.exists() and any(runtime.iterdir()):
        raise SystemExit(f"Correction runtime already exists and is nonempty: {runtime}")
    for sub in ("configs", "objects", "forecasts", "scores", "traces", "coefficients", "tables", "logs", "status", "figures", "scripts", "manifests"):
        (runtime / sub).mkdir(parents=True, exist_ok=True)

    counts = {
        suffix: len(list((source / "status").glob(f"*.{suffix}")))
        for suffix in ("completed", "failed", "running", "pending")
    }
    if counts != {"completed": 133, "failed": 0, "running": 0, "pending": 0}:
        raise SystemExit(f"Source r8 is not the expected clean 133/133 authority: {counts}")

    imports: list[dict[str, object]] = []
    config_imports = {
        "part1_post_search2_design_cache.rds": "part1_design_cache",
        "part2_final_dec25_design_cache.rds": "part2_design_cache",
        "part3_final_dec25_design_cache.rds": "part3_design_cache",
        "part123_base_config_frozen.yaml": "base_config",
        "full_data_rhs_calibration.csv": "rhs_calibration",
    }
    for name, role in config_imports.items():
        link_verified(source / "configs" / name, runtime / "configs" / name, imports, role)
    selected = repo / "local_trackers/glofas_search_phase2_selected_components_20260916.csv"
    link_verified(selected, runtime / "configs/post_search2_selected_components.csv", imports, "selected_components")
    for part in ("part1", "part2", "part3"):
        link_verified(
            source / "objects" / f"{part}_normal_rhs_driver_bank.rds",
            runtime / "objects" / f"{part}_normal_rhs_driver_bank.rds",
            imports,
            f"{part}_normal_rhs_driver_bank",
        )

    seed_ids: list[str] = []
    for part in ("part1", "part2"):
        for family in ("independent_al", "independent_exal"):
            for tau in TAUS:
                old_id = f"{part}_fit_{family}_{qslug(tau)}"
                seed_id = f"seed_{old_id}"
                link_verified(
                    source / "objects" / f"{old_id}_fit.rds",
                    runtime / "objects" / f"{seed_id}_fit.rds",
                    imports,
                    f"initializer:{old_id}",
                )
                seed_ids.append(seed_id)
    for tau in TAUS:
        old_id = f"part3_fit_independent_al_{qslug(tau)}"
        seed_id = f"seed_{old_id}"
        link_verified(
            source / "objects" / f"{old_id}_fit.rds",
            runtime / "objects" / f"{seed_id}_fit.rds",
            imports,
            f"initializer:{old_id}",
        )
        seed_ids.append(seed_id)

    with (runtime / "manifests/imported_dependencies.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(imports[0]))
        writer.writeheader()
        writer.writerows(imports)

    base_config = runtime / "configs/part123_base_config_frozen.yaml"
    calibration = runtime / "configs/full_data_rhs_calibration.csv"
    selected_components = runtime / "configs/post_search2_selected_components.csv"
    jobs: list[dict[str, object]] = []

    common_controls = [
        "--max_iter", "200", "--min_iter", "200", "--tol", "1e-4",
        "--freeze_beta_warmup_iters", "20", "--min_beta_updates", "30",
        "--fixed_iterations", "true", "--full_state_convergence", "true",
        "--convergence_tolerance", "1e-4", "--terminal_consecutive_passes", "3",
    ]
    common_381 = [
        "Rscript", "application/scripts/381_run_glofas_dec25_final_refit_job.R",
        "--runtime_root", str(runtime), "--base_config", str(base_config),
        "--selected_components", str(selected_components), "--calibration_path", str(calibration),
        "--origin_date", "2022-12-25", "--horizon_days", "30",
        "--normal_draws", "500", "--seed", str(args.seed), "--forecast_backend", "cpp",
    ]
    common_403 = [
        "Rscript", "application/scripts/403_run_glofas_post_search2_support_job.R",
        "--runtime_root", str(runtime), "--base_config", str(base_config),
        "--selected_components", str(selected_components), "--calibration_path", str(calibration),
        "--part2_runtime_root", str(runtime), "--part3_runtime_root", str(runtime),
        "--part4_runtime_root", str(part4), "--n_draws", "500", "--seed", str(args.seed),
        "--forecast_backend", "cpp",
    ]

    def add_job(job_id: str, lane: str, action: str, family: str, tau: str,
                reason: str, dependencies: list[str], command: list[str]) -> None:
        jobs.append({
            "job_id": job_id, "lane": lane, "action": action,
            "model_family": family, "tau": tau, "reason": reason,
            "dependencies": dependencies, "command": command,
        })

    corrected_independent: dict[tuple[str, float], str] = {}
    for part in ("part1", "part2"):
        for tau in TAUS:
            slug = qslug(tau)
            job_id = f"corr_{part}_fit_independent_al_{slug}"
            corrected_independent[(part, tau)] = job_id
            seed_id = f"seed_{part}_fit_independent_al_{slug}"
            if part == "part1":
                command = common_403 + [
                    "--job_id", job_id, "--job_type", "part1_fit",
                    "--model_family", "independent_al", "--tau", f"{tau:.2f}",
                    "--likelihood", "AL", "--fit_structure", "independent",
                    "--init_fit_job_ids", seed_id,
                ] + common_controls
            else:
                command = common_381 + [
                    "--part", part, "--job_id", job_id, "--job_type", "fit",
                    "--model_family", "independent_al", "--tau", f"{tau:.2f}",
                    "--likelihood", "AL", "--fit_structure", "independent",
                    "--init_fit_job_ids", seed_id,
                    "--normal_driver_bank_path", str(runtime / f"objects/{part}_normal_rhs_driver_bank.rds"),
                ] + common_controls
            add_job(job_id, part, "fit", "independent_al", f"{tau:.2f}",
                    "exact200_same_target_restart", [], command)

    for part in ("part1", "part2"):
        al_id = f"corr_{part}_fit_joint_al_all7"
        al_deps = [corrected_independent[(part, tau)] for tau in TAUS]
        exal_id = f"corr_{part}_fit_joint_exal_all7"
        exal_seeds = [f"seed_{part}_fit_independent_exal_{qslug(tau)}" for tau in TAUS]
        if part == "part1":
            al_cmd = common_403 + [
                "--job_id", al_id, "--job_type", "part1_fit", "--model_family", "joint_al",
                "--tau", "all7", "--likelihood", "AL", "--fit_structure", "joint",
                "--init_fit_job_ids", "|".join(al_deps),
            ] + common_controls
            exal_cmd = common_403 + [
                "--job_id", exal_id, "--job_type", "part1_fit", "--model_family", "joint_exal",
                "--tau", "all7", "--likelihood", "exAL", "--fit_structure", "joint",
                "--init_fit_job_ids", "|".join(exal_seeds),
            ] + common_controls
        else:
            al_cmd = common_381 + [
                "--part", part, "--job_id", al_id, "--job_type", "fit", "--model_family", "joint_al",
                "--tau", "all7", "--likelihood", "AL", "--fit_structure", "joint",
                "--init_fit_job_ids", "|".join(al_deps),
                "--normal_driver_bank_path", str(runtime / f"objects/{part}_normal_rhs_driver_bank.rds"),
            ] + common_controls
            exal_cmd = common_381 + [
                "--part", part, "--job_id", exal_id, "--job_type", "fit", "--model_family", "joint_exal",
                "--tau", "all7", "--likelihood", "exAL", "--fit_structure", "joint",
                "--init_fit_job_ids", "|".join(exal_seeds),
                "--normal_driver_bank_path", str(runtime / f"objects/{part}_normal_rhs_driver_bank.rds"),
            ] + common_controls
        add_job(al_id, part, "fit", "joint_al", "all7", "refit_corrected_tau_keyed_initializer", al_deps, al_cmd)
        add_job(exal_id, part, "fit", "joint_exal", "all7", "refit_corrected_exal_kernel", [], exal_cmd)

    part3_id = "corr_part3_fit_joint_al_all7"
    part3_seeds = [f"seed_part3_fit_independent_al_{qslug(tau)}" for tau in TAUS]
    part3_cmd = common_381 + [
        "--part", "part3", "--job_id", part3_id, "--job_type", "fit", "--model_family", "joint_al",
        "--tau", "all7", "--likelihood", "AL", "--fit_structure", "joint",
        "--init_fit_job_ids", "|".join(part3_seeds),
        "--normal_driver_bank_path", str(runtime / "objects/part3_normal_rhs_driver_bank.rds"),
    ] + common_controls
    add_job(part3_id, "part3", "fit", "joint_al", "all7", "refit_corrected_tau_keyed_initializer", [], part3_cmd)

    fit_jobs = [job for job in jobs if job["action"] == "fit"]
    for fit_job in fit_jobs:
        fit_id = str(fit_job["job_id"])
        part = str(fit_job["lane"])
        family = str(fit_job["model_family"])
        tau = str(fit_job["tau"])
        forecast_id = fit_id.replace("_fit_", "_forecast_", 1)
        if part == "part1":
            command = common_403 + [
                "--job_id", forecast_id, "--job_type", "part1_forecast",
                "--model_family", family, "--tau", tau, "--fit_job_id", fit_id,
                "--normal_driver_bank_path", str(runtime / "objects/part1_normal_rhs_driver_bank.rds"),
            ]
        else:
            command = common_381 + [
                "--part", part, "--job_id", forecast_id, "--job_type", "forecast",
                "--model_family", family, "--tau", tau, "--fit_job_id", fit_id,
                "--normal_driver_bank_path", str(runtime / f"objects/{part}_normal_rhs_driver_bank.rds"),
            ]
        add_job(forecast_id, part, "forecast", family, tau,
                "forecast_bound_to_corrected_fit_sha256", [fit_id], command)

    if len([job for job in jobs if job["action"] == "fit"]) != 19 or len(jobs) != 38:
        raise RuntimeError("Correction DAG must contain exactly 19 fits and 19 forecasts")

    for job in jobs:
        script = runtime / "scripts" / f"{job['job_id']}.sh"
        command = shlex.join([str(item) for item in job["command"]])
        script.write_text(
            "#!/usr/bin/env bash\nset -euo pipefail\n"
            "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 "
            "VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1\n"
            f"cd {shlex.quote(str(repo))}\nexec {command}\n"
        )
        script.chmod(0o755)
        job["script_path"] = str(script)
        job["command_display"] = command

    manifest_json = runtime / "configs/correction_job_manifest.json"
    manifest_json.write_text(json.dumps(jobs, indent=2) + "\n")
    manifest_csv = runtime / "configs/correction_job_manifest.csv"
    with manifest_csv.open("w", newline="") as handle:
        fields = ["job_id", "lane", "action", "model_family", "tau", "reason", "dependencies", "script_path", "command_display"]
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for job in jobs:
            row = {field: job.get(field, "") for field in fields}
            row["dependencies"] = "|".join(job["dependencies"])
            writer.writerow(row)

    source_files = [
        repo / "application/R/glofas_quantile_integrity.R",
        repo / "application/R/glofas_part1_quantile_oracle_forecast.R",
        repo / "application/R/glofas_part3_quantile_bridge.R",
        repo / "application/scripts/381_run_glofas_dec25_final_refit_job.R",
        repo / "application/scripts/403_run_glofas_post_search2_support_job.R",
        repo / "application/scripts/410_prepare_glofas_quantile_integrity_correction.py",
        repo / "application/scripts/411_launch_glofas_quantile_integrity_correction.py",
    ]
    contract = {
        "schema_version": "glofas_quantile_integrity_correction_v2",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "git_head": git(repo, "rev-parse", "HEAD"),
        "git_status_at_prepare": git(repo, "status", "--short"),
        "source_r8_root": str(source),
        "source_r8_health": counts,
        "runtime_root": str(runtime),
        "workers": args.workers,
        "execution_contract": {
            "worker_ceiling": args.workers,
            "threads_per_worker": 1,
            "dependency_aware": True,
        },
        "fit_jobs": 19,
        "forecast_jobs": 19,
        "iteration_contract": {"max_iter": 200, "min_iter": 200, "beta_freeze": 20, "terminal_passes": 3, "tolerance": 1e-4},
        "scientific_contract": {"cutoff": "2022-12-25", "horizon_days": 30, "response_scale": "log1p", "draws": 500},
        "manifest_sha256": sha256(manifest_json),
        "source_hashes": {str(path.relative_to(repo)): sha256(path) for path in source_files},
    }
    (runtime / "configs/correction_contract.json").write_text(json.dumps(contract, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"runtime_root": str(runtime), "fit_jobs": 19, "forecast_jobs": 19,
                      "workers": args.workers, "manifest_sha256": contract["manifest_sha256"]}, indent=2))


if __name__ == "__main__":
    main()
