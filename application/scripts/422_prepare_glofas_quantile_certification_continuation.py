#!/usr/bin/env python3.11
"""Prepare exact iteration-400 GloFAS quantile certification continuations."""

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


ELIGIBLE_SOURCE_IDS = (
    "cert_part1_fit_independent_al_q0p05",
    "cert_part1_fit_independent_al_q0p95",
    "cert_part2_fit_independent_al_q0p05",
    "cert_part2_fit_independent_al_q0p95",
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


def truth(value: object) -> bool:
    return str(value).strip().lower() in ("true", "1", "yes")


def read_one_row(path: Path) -> dict[str, str]:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 1:
        raise RuntimeError(f"Expected one row in {path}; found {len(rows)}")
    return rows[0]


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


def audit_source(source: Path, expected_fit_count: int) -> list[dict[str, object]]:
    manifest_path = source / "configs/certification_job_manifest.json"
    contract_path = source / "configs/certification_contract.json"
    jobs = json.loads(manifest_path.read_text())
    contract = json.loads(contract_path.read_text())
    if sha256(manifest_path) != contract["manifest_sha256"]:
        raise RuntimeError("Source certification manifest hash mismatch")
    by_id = {str(job["job_id"]): job for job in jobs}
    audited: list[dict[str, object]] = []
    for source_id in ELIGIBLE_SOURCE_IDS:
        job = by_id.get(source_id)
        if not job or job.get("action") != "fit":
            raise RuntimeError(f"Missing expected source fit manifest row: {source_id}")
        if not (source / "status" / f"{source_id}.completed").is_file():
            raise RuntimeError(f"Source fit is not completed: {source_id}")
        if (source / "status" / f"{source_id}.certified").exists():
            raise RuntimeError(f"Source fit is already certified: {source_id}")
        execution_path = source / "logs" / f"{source_id}_execution_contract.csv"
        certificate_path = source / "tables" / f"{source_id}_certification.csv"
        execution = read_one_row(execution_path)
        certificate = read_one_row(certificate_path)
        fit_path = Path(execution["fit_path"]).resolve(strict=True)
        trace_path = (source / "traces" / f"{source_id}_cumulative_trace.csv").resolve(strict=True)
        if sha256(fit_path) != execution["fit_sha256"]:
            raise RuntimeError(f"Fit hash mismatch for {source_id}")
        if int(execution["segment_iterations"]) != 200 or int(execution["cumulative_iterations"]) != 400:
            raise RuntimeError(f"Source fit does not have the expected 200/400 iteration contract: {source_id}")
        if execution["prior_source_sha256"] != execution["prior_restart_sha256"]:
            raise RuntimeError(f"Source prior identity failed: {source_id}")
        if truth(execution["certified"]) or truth(certificate["certified"]):
            raise RuntimeError(f"Source fit unexpectedly reports certification: {source_id}")
        with trace_path.open(newline="") as handle:
            trace_rows = list(csv.DictReader(handle))
        observed_global = [int(float(row["global_iter"])) for row in trace_rows]
        if len(trace_rows) != 400 or observed_global != list(range(1, 401)):
            raise RuntimeError(f"Source cumulative trace is not exactly 1:400: {source_id}")
        audited.append({
            "source_job_id": source_id,
            "part": str(job["part"]),
            "model_family": str(job["model_family"]),
            "tau": str(job["tau"]),
            "source_fit_path": str(fit_path),
            "source_fit_sha256": sha256(fit_path),
            "source_cumulative_trace_path": str(trace_path),
            "source_cumulative_trace_sha256": sha256(trace_path),
            "source_execution_contract": str(execution_path.resolve()),
            "source_certificate": str(certificate_path.resolve()),
        })
    if len(audited) != expected_fit_count:
        raise RuntimeError(f"Expected {expected_fit_count} eligible fits; audited {len(audited)}")
    return audited


def terminal_gate_row(source: Path, row: dict[str, object], tolerance: float) -> dict[str, object]:
    progress = source / "traces" / f"{row['source_job_id']}_progress.csv"
    with progress.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 200:
        raise RuntimeError(f"Progress trace is not 200 rows: {progress}")
    final = rows[-1]
    fields = (
        "max_beta_change", "max_beta_relative_change", "max_alpha_change",
        "max_gamma_change", "max_gamma_relative_change", "max_sigma_change",
        "max_sigma_relative_change", "max_path_change", "max_latent_change",
        "max_rhs_change",
    )
    output: dict[str, object] = {
        "source_job_id": row["source_job_id"], "part": row["part"],
        "model_family": row["model_family"], "tau": row["tau"],
        "global_iter": int(float(final["global_iter"])), "tolerance": tolerance,
        "full_state_pass": final.get("full_state_pass", ""),
    }
    for field in fields:
        value = final.get(field, "")
        output[field] = value
        try:
            output[f"{field}_over_tolerance"] = float(value) / tolerance
        except (TypeError, ValueError):
            output[f"{field}_over_tolerance"] = ""
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--expected-fit-count", type=int, default=4)
    parser.add_argument("--seed", type=int, default=20260922)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    if args.workers < 1 or args.workers > args.expected_fit_count:
        raise SystemExit("Worker count must be between 1 and the expected fit count")

    repo = Path(__file__).resolve().parents[2]
    source = resolve(repo, args.source_root)
    runtime = resolve(repo, args.runtime_root)
    audited = audit_source(source, args.expected_fit_count)
    if args.validate_only:
        print(json.dumps({
            "source_root": str(source), "eligible_fits": len(audited),
            "source_iterations": 400, "status": "VALID",
        }, indent=2))
        return
    if runtime.exists() and any(runtime.iterdir()):
        raise SystemExit(f"Runtime already exists and is nonempty: {runtime}")
    for sub in (
        "configs", "source_objects", "source_traces", "objects", "forecasts",
        "scores", "traces", "coefficients", "tables", "logs", "status",
        "scripts", "manifests",
    ):
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
        fit_destination = runtime / "source_objects" / f"{row['source_job_id']}_fit.rds"
        trace_destination = runtime / "source_traces" / f"{row['source_job_id']}_cumulative_trace.csv"
        link_verified(Path(str(row["source_fit_path"])), fit_destination, imports, f"source_fit:{row['source_job_id']}")
        link_verified(Path(str(row["source_cumulative_trace_path"])), trace_destination, imports, f"source_trace:{row['source_job_id']}")
        row["imported_source_fit_path"] = str(fit_destination)
        row["imported_source_trace_path"] = str(trace_destination)

    with (runtime / "manifests/imported_dependencies.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(imports[0]))
        writer.writeheader()
        writer.writerows(imports)

    tolerance = 1.0e-4
    gate_rows = [terminal_gate_row(source, row, tolerance) for row in audited]
    with (runtime / "tables/source_terminal_gate_decomposition.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(gate_rows[0]))
        writer.writeheader()
        writer.writerows(gate_rows)

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
        part = str(row["part"])
        family = str(row["model_family"])
        tau = str(row["tau"])
        source_id = str(row["source_job_id"])
        fit_id = source_id.replace("cert_", "cert2_", 1)
        cache = runtime / "configs" / design_names[part]
        command = [
            "Rscript", "application/scripts/423_run_glofas_quantile_certification_continuation.R",
            "--runtime_root", str(runtime), "--job_id", fit_id, "--part", part,
            "--model_family", family, "--tau", tau,
            "--source_fit_path", row["imported_source_fit_path"],
            "--source_fit_sha256", row["source_fit_sha256"],
            "--source_cumulative_trace_path", row["imported_source_trace_path"],
            "--source_cumulative_trace_sha256", row["source_cumulative_trace_sha256"],
            "--expected_source_iterations", "400",
            "--design_cache", str(cache), "--design_cache_sha256", sha256(cache),
            "--max_iter", "200", "--min_iter", "200",
            "--convergence_tolerance", "1e-4", "--freeze_beta_warmup_iters", "20",
            "--min_beta_updates", "30", "--terminal_consecutive_passes", "3",
            "--progress_every", "1",
        ]
        jobs.append({
            "job_id": fit_id, "part": part, "action": "fit", "model_family": family,
            "tau": tau, "source_job_id": source_id,
            "source_fit_sha256": row["source_fit_sha256"],
            "source_cumulative_trace_sha256": row["source_cumulative_trace_sha256"],
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
            "tau": tau, "source_job_id": source_id,
            "source_fit_sha256": row["source_fit_sha256"],
            "source_cumulative_trace_sha256": row["source_cumulative_trace_sha256"],
            "dependencies": [fit_id], "required_certified_dependencies": [fit_id],
            "command": forecast_command,
        })

    if len(jobs) != 2 * args.expected_fit_count:
        raise RuntimeError("Continuation DAG does not have one fit and forecast per source")
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

    manifest_path = runtime / "configs/certification_continuation_job_manifest.json"
    manifest_path.write_text(json.dumps(jobs, indent=2) + "\n")
    with (runtime / "configs/certification_continuation_job_manifest.csv").open("w", newline="") as handle:
        fields = (
            "job_id", "part", "action", "model_family", "tau", "source_job_id",
            "source_fit_sha256", "source_cumulative_trace_sha256", "dependencies",
            "required_certified_dependencies", "script_path", "command_display",
        )
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for job in jobs:
            output = {field: job.get(field, "") for field in fields}
            output["dependencies"] = "|".join(job["dependencies"])
            output["required_certified_dependencies"] = "|".join(job["required_certified_dependencies"])
            writer.writerow(output)

    source_files = [
        repo / "application/R/glofas_quantile_integrity.R",
        repo / "application/R/glofas_quantile_certification_restart.R",
        repo / "application/R/glofas_part1_quantile_oracle_forecast.R",
        repo / "application/R/glofas_part3_quantile_bridge.R",
        repo / "application/scripts/381_run_glofas_dec25_final_refit_job.R",
        repo / "application/scripts/403_run_glofas_post_search2_support_job.R",
        repo / "application/scripts/422_prepare_glofas_quantile_certification_continuation.py",
        repo / "application/scripts/423_run_glofas_quantile_certification_continuation.R",
        repo / "application/scripts/424_launch_glofas_quantile_certification_continuation.py",
        repo / "application/scripts/425_check_glofas_quantile_certification_continuation.py",
    ]
    missing = [str(path) for path in source_files if not path.is_file()]
    if missing:
        raise RuntimeError(f"Missing continuation source files: {missing}")
    contract = {
        "schema_version": "glofas_quantile_certification_continuation_v1",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "git_head": git(repo, "rev-parse", "HEAD"),
        "git_status_at_prepare": git(repo, "status", "--short"),
        "source_runtime_root": str(source), "runtime_root": str(runtime),
        "workers": args.workers, "fit_jobs": args.expected_fit_count,
        "forecast_jobs": args.expected_fit_count,
        "manifest_sha256": sha256(manifest_path),
        "iteration_contract": {
            "source_iterations": 400, "continuation_iterations": 200,
            "cumulative_iterations": 600, "fixed_iterations": True,
            "beta_freeze": 20, "minimum_beta_updates": 30,
            "tolerance": tolerance, "terminal_consecutive_passes": 3,
        },
        "scientific_contract": {
            "cutoff": "2022-12-25", "forecast_start": "2022-12-26",
            "forecast_end": "2023-01-24", "horizon_days": 30,
            "response_scale": "log1p", "draws": 500,
        },
        "source_hashes": {str(path.relative_to(repo)): sha256(path) for path in source_files},
    }
    contract_path = runtime / "configs/certification_continuation_contract.json"
    contract_path.write_text(json.dumps(contract, indent=2, sort_keys=True) + "\n")
    print(json.dumps({
        "runtime_root": str(runtime), "fit_jobs": args.expected_fit_count,
        "forecast_jobs": args.expected_fit_count, "workers": args.workers,
        "manifest_sha256": contract["manifest_sha256"],
        "status": "PREPARED_NOT_LAUNCHED",
    }, indent=2))


if __name__ == "__main__":
    main()
