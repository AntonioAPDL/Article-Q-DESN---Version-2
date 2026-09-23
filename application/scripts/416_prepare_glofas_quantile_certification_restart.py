#!/usr/bin/env python3.11
"""Prepare the minimal nine-fit GloFAS quantile certification-restart DAG."""

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


UNRESOLVED = (
    ("part1", "independent_al", "0.05", "corr_part1_fit_independent_al_q0p05"),
    ("part1", "independent_al", "0.95", "corr_part1_fit_independent_al_q0p95"),
    ("part2", "independent_al", "0.05", "corr_part2_fit_independent_al_q0p05"),
    ("part2", "independent_al", "0.95", "corr_part2_fit_independent_al_q0p95"),
    ("part1", "joint_al", "all7", "corr_part1_fit_joint_al_all7"),
    ("part1", "joint_exal", "all7", "corr_part1_fit_joint_exal_all7"),
    ("part2", "joint_al", "all7", "corr_part2_fit_joint_al_all7"),
    ("part2", "joint_exal", "all7", "corr_part2_fit_joint_exal_all7"),
    ("part3", "joint_al", "all7", "corr_part3_fit_joint_al_all7"),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def resolve(repo: Path, value: str) -> Path:
    path = Path(value)
    return path.resolve() if path.is_absolute() else (repo / path).resolve()


def link_verified(source: Path, destination: Path, rows: list[dict[str, object]], role: str) -> None:
    source = source.resolve(strict=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        if sha256(source) != sha256(destination):
            raise RuntimeError(f"Refusing to replace nonidentical import: {destination}")
    else:
        try:
            os.link(source, destination)
        except OSError as error:
            if error.errno != errno.EXDEV:
                raise
            shutil.copy2(source, destination)
    rows.append({
        "role": role,
        "source_path": str(source),
        "destination_path": str(destination.resolve()),
        "bytes": source.stat().st_size,
        "sha256": sha256(source),
        "hardlinked": os.stat(source).st_ino == os.stat(destination).st_ino,
    })


def read_one_row(path: Path) -> dict[str, str]:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 1:
        raise RuntimeError(f"Expected one row in {path}; found {len(rows)}")
    return rows[0]


def audit_source(source: Path) -> list[dict[str, str]]:
    status = source / "status"
    manifest_path = source / "configs/correction_job_manifest.json"
    source_jobs = json.loads(manifest_path.read_text())
    if len(source_jobs) != 38:
        raise RuntimeError(f"Correction source manifest has {len(source_jobs)} jobs, not 38")
    counts = {suffix: 0 for suffix in ("completed", "failed", "running", "pending")}
    for job in source_jobs:
        job_id = str(job["job_id"])
        if (status / f"{job_id}.failed").exists():
            counts["failed"] += 1
        elif (status / f"{job_id}.completed").exists():
            counts["completed"] += 1
        elif (status / f"{job_id}.running").exists():
            counts["running"] += 1
        else:
            counts["pending"] += 1
    if counts != {"completed": 38, "failed": 0, "running": 0, "pending": 0}:
        raise RuntimeError(f"Correction source is not the expected clean 38/38 runtime: {counts}")
    audited: list[dict[str, str]] = []
    for part, family, tau, source_id in UNRESOLVED:
        fit_path = source / "objects" / f"{source_id}_fit.rds"
        contract_path = source / "logs" / f"{source_id}_execution_contract.csv"
        if not fit_path.is_file() or not contract_path.is_file():
            raise RuntimeError(f"Missing source fit or contract for {source_id}")
        row = read_one_row(contract_path)
        expected_hash = row.get("fit_sha256", "").lower()
        observed_hash = sha256(fit_path)
        if expected_hash != observed_hash:
            raise RuntimeError(f"Source fit hash mismatch for {source_id}")
        if row.get("terminal_certificate_passed", "").lower() not in ("false", "0"):
            raise RuntimeError(f"Source fit {source_id} is not an uncertified fit")
        if int(row.get("iterations", "0")) != 200:
            raise RuntimeError(f"Source fit {source_id} is not a 200-iteration fit")
        audited.append({
            "part": part, "model_family": family, "tau": tau,
            "source_job_id": source_id, "source_fit_path": str(fit_path.resolve()),
            "source_fit_sha256": observed_hash,
        })
    return audited


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--workers", type=int, default=9)
    parser.add_argument("--seed", type=int, default=20260921)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    if args.workers < 1 or args.workers > 9:
        raise SystemExit("Certification restart permits 1-9 one-thread workers")

    repo = Path(__file__).resolve().parents[2]
    source = resolve(repo, args.source_root)
    runtime = resolve(repo, args.runtime_root)
    audited = audit_source(source)
    if args.validate_only:
        print(json.dumps({"source_root": str(source), "audited_uncertified_fits": len(audited), "status": "VALID"}, indent=2))
        return
    if runtime.exists() and any(runtime.iterdir()):
        raise SystemExit(f"Runtime already exists and is nonempty: {runtime}")
    for sub in ("configs", "source_objects", "objects", "forecasts", "scores", "traces", "coefficients", "tables", "logs", "status", "scripts", "manifests"):
        (runtime / sub).mkdir(parents=True, exist_ok=True)

    imports: list[dict[str, object]] = []
    config_names = (
        "part1_post_search2_design_cache.rds", "part2_final_dec25_design_cache.rds",
        "part3_final_dec25_design_cache.rds", "part123_base_config_frozen.yaml",
        "full_data_rhs_calibration.csv", "post_search2_selected_components.csv",
    )
    for name in config_names:
        link_verified(source / "configs" / name, runtime / "configs" / name, imports, f"config:{name}")
    for part in ("part1", "part2", "part3"):
        name = f"{part}_normal_rhs_driver_bank.rds"
        link_verified(source / "objects" / name, runtime / "objects" / name, imports, f"driver_bank:{part}")
    for row in audited:
        destination = runtime / "source_objects" / f"{row['source_job_id']}_fit.rds"
        link_verified(Path(row["source_fit_path"]), destination, imports, f"source_fit:{row['source_job_id']}")
        row["imported_source_fit_path"] = str(destination)

    with (runtime / "manifests/imported_dependencies.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(imports[0]))
        writer.writeheader()
        writer.writerows(imports)

    design_names = {
        "part1": "part1_post_search2_design_cache.rds",
        "part2": "part2_final_dec25_design_cache.rds",
        "part3": "part3_final_dec25_design_cache.rds",
    }
    base_config = runtime / "configs/part123_base_config_frozen.yaml"
    selection = runtime / "configs/post_search2_selected_components.csv"
    calibration = runtime / "configs/full_data_rhs_calibration.csv"
    jobs: list[dict[str, object]] = []
    for row in audited:
        part, family, tau, source_id = row["part"], row["model_family"], row["tau"], row["source_job_id"]
        fit_id = source_id.replace("corr_", "cert_", 1)
        cache = runtime / "configs" / design_names[part]
        command = [
            "Rscript", "application/scripts/417_run_glofas_quantile_certification_restart.R",
            "--runtime_root", str(runtime), "--job_id", fit_id, "--part", part,
            "--model_family", family, "--tau", tau,
            "--source_fit_path", row["imported_source_fit_path"],
            "--source_fit_sha256", row["source_fit_sha256"],
            "--design_cache", str(cache), "--design_cache_sha256", sha256(cache),
            "--max_iter", "200", "--min_iter", "200", "--convergence_tolerance", "1e-4",
            "--freeze_beta_warmup_iters", "20", "--min_beta_updates", "30",
            "--terminal_consecutive_passes", "3", "--progress_every", "1",
        ]
        jobs.append({
            "job_id": fit_id, "part": part, "action": "fit", "model_family": family,
            "tau": tau, "source_job_id": source_id, "source_fit_sha256": row["source_fit_sha256"],
            "dependencies": [], "required_certified_dependencies": [], "command": command,
        })

        forecast_id = fit_id.replace("_fit_", "_forecast_", 1)
        if part == "part1":
            forecast_command = [
                "Rscript", "application/scripts/403_run_glofas_post_search2_support_job.R",
                "--runtime_root", str(runtime), "--job_id", forecast_id,
                "--job_type", "part1_forecast", "--base_config", str(base_config),
                "--selected_components", str(selection), "--calibration_path", str(calibration),
                "--model_family", family, "--tau", tau, "--fit_job_id", fit_id,
                "--normal_driver_bank_path", str(runtime / "objects/part1_normal_rhs_driver_bank.rds"),
                "--n_draws", "500", "--seed", str(args.seed), "--forecast_backend", "cpp",
            ]
        else:
            forecast_command = [
                "Rscript", "application/scripts/381_run_glofas_dec25_final_refit_job.R",
                "--runtime_root", str(runtime), "--part", part, "--job_id", forecast_id,
                "--job_type", "forecast", "--base_config", str(base_config),
                "--selected_components", str(selection), "--calibration_path", str(calibration),
                "--model_family", family, "--tau", tau, "--fit_job_id", fit_id,
                "--normal_driver_bank_path", str(runtime / f"objects/{part}_normal_rhs_driver_bank.rds"),
                "--origin_date", "2022-12-25", "--horizon_days", "30",
                "--normal_draws", "500", "--seed", str(args.seed), "--forecast_backend", "cpp",
            ]
        jobs.append({
            "job_id": forecast_id, "part": part, "action": "forecast", "model_family": family,
            "tau": tau, "source_job_id": source_id, "source_fit_sha256": row["source_fit_sha256"],
            "dependencies": [fit_id], "required_certified_dependencies": [fit_id],
            "command": forecast_command,
        })

    if len(jobs) != 18 or sum(job["action"] == "fit" for job in jobs) != 9:
        raise RuntimeError("Certification DAG must contain exactly nine fits and nine forecasts")
    for job in jobs:
        script = runtime / "scripts" / f"{job['job_id']}.sh"
        command_display = shlex.join([str(item) for item in job["command"]])
        script.write_text(
            "#!/usr/bin/env bash\nset -euo pipefail\n"
            "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 "
            "VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1\n"
            f"cd {shlex.quote(str(repo))}\nexec {command_display}\n"
        )
        script.chmod(0o755)
        job["script_path"] = str(script)
        job["command_display"] = command_display

    manifest_path = runtime / "configs/certification_job_manifest.json"
    manifest_path.write_text(json.dumps(jobs, indent=2) + "\n")
    with (runtime / "configs/certification_job_manifest.csv").open("w", newline="") as handle:
        fields = ("job_id", "part", "action", "model_family", "tau", "source_job_id",
                  "source_fit_sha256", "dependencies", "required_certified_dependencies",
                  "script_path", "command_display")
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for job in jobs:
            out = {field: job.get(field, "") for field in fields}
            out["dependencies"] = "|".join(job["dependencies"])
            out["required_certified_dependencies"] = "|".join(job["required_certified_dependencies"])
            writer.writerow(out)

    source_files = [
        repo / "application/R/glofas_quantile_integrity.R",
        repo / "application/R/glofas_quantile_certification_restart.R",
        repo / "application/R/glofas_part1_quantile_oracle_forecast.R",
        repo / "application/R/glofas_part3_quantile_bridge.R",
        repo / "application/scripts/381_run_glofas_dec25_final_refit_job.R",
        repo / "application/scripts/403_run_glofas_post_search2_support_job.R",
        repo / "application/scripts/416_prepare_glofas_quantile_certification_restart.py",
        repo / "application/scripts/417_run_glofas_quantile_certification_restart.R",
        repo / "application/scripts/418_launch_glofas_quantile_certification_restart.py",
        repo / "application/scripts/419_check_glofas_quantile_certification_restart.py",
    ]
    missing_sources = [str(path) for path in source_files if not path.is_file()]
    if missing_sources:
        raise RuntimeError(f"Missing certification source files: {missing_sources}")
    contract = {
        "schema_version": "glofas_quantile_certification_restart_v1",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "git_head": git(repo, "rev-parse", "HEAD"),
        "git_status_at_prepare": git(repo, "status", "--short"),
        "source_runtime_root": str(source), "runtime_root": str(runtime),
        "workers": args.workers, "fit_jobs": 9, "forecast_jobs": 9,
        "manifest_sha256": sha256(manifest_path),
        "iteration_contract": {
            "source_iterations": 200, "restart_iterations": 200, "cumulative_iterations": 400,
            "fixed_iterations": True, "beta_freeze": 20, "minimum_beta_updates": 30,
            "tolerance": 1e-4, "terminal_consecutive_passes": 3,
        },
        "scientific_contract": {
            "cutoff": "2022-12-25", "forecast_start": "2022-12-26",
            "forecast_end": "2023-01-24", "horizon_days": 30,
            "response_scale": "log1p", "draws": 500,
        },
        "source_hashes": {str(path.relative_to(repo)): sha256(path) for path in source_files},
    }
    (runtime / "configs/certification_contract.json").write_text(json.dumps(contract, indent=2, sort_keys=True) + "\n")
    print(json.dumps({
        "runtime_root": str(runtime), "fit_jobs": 9, "forecast_jobs": 9,
        "workers": args.workers, "manifest_sha256": contract["manifest_sha256"],
        "status": "PREPARED_NOT_LAUNCHED",
    }, indent=2))


if __name__ == "__main__":
    main()
