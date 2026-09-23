#!/usr/bin/env python3.11
"""Prepare a selective exact-state continuation for unresolved GloFAS quantile fits."""

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


SELECTED_SOURCES = (
    {
        "source_runtime": "continuation",
        "source_job_id": "cert2_part2_fit_independent_al_q0p05",
        "target_job_id": "cert3_part2_fit_independent_al_q0p05",
        "part": "part2", "model_family": "independent_al", "tau": "0.05",
        "source_iterations": 600,
    },
    {
        "source_runtime": "continuation",
        "source_job_id": "cert2_part2_fit_independent_al_q0p95",
        "target_job_id": "cert3_part2_fit_independent_al_q0p95",
        "part": "part2", "model_family": "independent_al", "tau": "0.95",
        "source_iterations": 600,
    },
    {
        "source_runtime": "restart",
        "source_job_id": "cert_part1_fit_joint_exal_all7",
        "target_job_id": "cert3_part1_fit_joint_exal_all7",
        "part": "part1", "model_family": "joint_exal", "tau": "all7",
        "source_iterations": 400,
    },
    {
        "source_runtime": "restart",
        "source_job_id": "cert_part2_fit_joint_exal_all7",
        "target_job_id": "cert3_part2_fit_joint_exal_all7",
        "part": "part2", "model_family": "joint_exal", "tau": "all7",
        "source_iterations": 400,
    },
)


_SHA256_CACHE: dict[tuple[int, int, int, int], str] = {}


def sha256(path: Path) -> str:
    stat = path.stat()
    key = (stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns)
    if key in _SHA256_CACHE:
        return _SHA256_CACHE[key]
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    value = digest.hexdigest()
    _SHA256_CACHE[key] = value
    return value


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


def runtime_schema(root: Path, kind: str) -> tuple[Path, Path, str]:
    if kind == "restart":
        return (
            root / "configs/certification_job_manifest.json",
            root / "configs/certification_contract.json",
            "prior_restart_sha256",
        )
    if kind == "continuation":
        return (
            root / "configs/certification_continuation_job_manifest.json",
            root / "configs/certification_continuation_contract.json",
            "prior_continuation_sha256",
        )
    raise RuntimeError(f"Unsupported source runtime kind: {kind}")


def link_verified(
    source: Path, destination: Path, rows: list[dict[str, object]], role: str
) -> None:
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


def audit_runtime(root: Path, kind: str) -> tuple[dict[str, dict], dict, Path, Path, str]:
    manifest_path, contract_path, prior_destination_field = runtime_schema(root, kind)
    if not manifest_path.is_file() or not contract_path.is_file():
        raise RuntimeError(f"Missing source manifest/contract under {root}")
    jobs = json.loads(manifest_path.read_text())
    contract = json.loads(contract_path.read_text())
    if sha256(manifest_path) != contract["manifest_sha256"]:
        raise RuntimeError(f"Source manifest hash mismatch: {root}")
    if str(contract.get("runtime_root")) != str(root.resolve()):
        raise RuntimeError(f"Source contract runtime root mismatch: {root}")
    return {str(job["job_id"]): job for job in jobs}, contract, manifest_path, contract_path, prior_destination_field


def audit_source(
    roots: dict[str, Path], selection: dict[str, object]
) -> dict[str, object]:
    kind = str(selection["source_runtime"])
    root = roots[kind]
    jobs, contract, manifest_path, contract_path, prior_destination_field = audit_runtime(root, kind)
    source_id = str(selection["source_job_id"])
    source_iterations = int(selection["source_iterations"])
    job = jobs.get(source_id)
    if not job or job.get("action") != "fit":
        raise RuntimeError(f"Missing source fit manifest row: {source_id}")
    for field in ("part", "model_family", "tau"):
        if str(job.get(field)) != str(selection[field]):
            raise RuntimeError(f"Source selection mismatch for {source_id}: {field}")
    if not (root / "status" / f"{source_id}.completed").is_file():
        raise RuntimeError(f"Source fit is not completed: {source_id}")
    if (root / "status" / f"{source_id}.certified").exists():
        raise RuntimeError(f"Source fit is already certified: {source_id}")

    execution_path = root / "logs" / f"{source_id}_execution_contract.csv"
    certificate_path = root / "tables" / f"{source_id}_certification.csv"
    execution = read_one_row(execution_path)
    certificate = read_one_row(certificate_path)
    fit_path = Path(execution["fit_path"]).resolve(strict=True)
    trace_path = Path(execution["cumulative_trace_path"]).resolve(strict=True)
    if sha256(fit_path) != execution["fit_sha256"]:
        raise RuntimeError(f"Fit hash mismatch for {source_id}")
    trace_hash = sha256(trace_path)
    recorded_trace_hash = execution.get("cumulative_trace_sha256", "")
    if recorded_trace_hash and trace_hash != recorded_trace_hash:
        raise RuntimeError(f"Cumulative-trace hash mismatch for {source_id}")
    if int(execution["cumulative_iterations"]) != source_iterations:
        raise RuntimeError(f"Unexpected source-iteration count for {source_id}")
    if int(execution["segment_iterations"]) != 200:
        raise RuntimeError(f"Last source segment was not exactly 200 iterations: {source_id}")
    if execution["prior_source_sha256"] != execution[prior_destination_field]:
        raise RuntimeError(f"Source prior identity failed: {source_id}")
    if truth(execution["certified"]) or truth(certificate["certified"]):
        raise RuntimeError(f"Source fit unexpectedly reports certification: {source_id}")
    with trace_path.open(newline="") as handle:
        trace_rows = list(csv.DictReader(handle))
    observed_global = [int(float(row["global_iter"])) for row in trace_rows]
    if len(trace_rows) != source_iterations or observed_global != list(range(1, source_iterations + 1)):
        raise RuntimeError(f"Source cumulative trace is not exactly 1:N: {source_id}")

    output = dict(selection)
    output.update({
        "source_runtime_root": str(root),
        "source_manifest_path": str(manifest_path.resolve()),
        "source_manifest_sha256": sha256(manifest_path),
        "source_contract_path": str(contract_path.resolve()),
        "source_contract_sha256": sha256(contract_path),
        "source_execution_contract": str(execution_path.resolve()),
        "source_execution_contract_sha256": sha256(execution_path),
        "source_certificate": str(certificate_path.resolve()),
        "source_certificate_sha256": sha256(certificate_path),
        "source_fit_path": str(fit_path),
        "source_fit_sha256": sha256(fit_path),
        "source_cumulative_trace_path": str(trace_path),
        "source_cumulative_trace_sha256": trace_hash,
        "source_prior_sha256": execution["prior_source_sha256"],
        "source_restart_kind": execution["restart_kind"],
        "source_certified": False,
        "expected_cumulative_iterations": source_iterations + 200,
    })
    if output["source_restart_kind"] != "exact_local_state_available":
        raise RuntimeError(f"Source lacks exact local state: {source_id}")
    return output


def terminal_gate_row(row: dict[str, object], tolerance: float) -> dict[str, object]:
    source = Path(str(row["source_runtime_root"]))
    progress = source / "traces" / f"{row['source_job_id']}_progress.csv"
    with progress.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 200:
        raise RuntimeError(f"Last-segment progress trace is not 200 rows: {progress}")
    final = rows[-1]
    if int(float(final["global_iter"])) != int(row["source_iterations"]):
        raise RuntimeError(f"Terminal progress iteration mismatch: {progress}")
    fields = (
        "max_beta_change", "max_beta_relative_change", "max_alpha_change",
        "max_gamma_change", "max_gamma_relative_change", "max_sigma_change",
        "max_sigma_relative_change", "max_path_change", "max_latent_change",
        "max_rhs_change",
    )
    output: dict[str, object] = {
        "source_job_id": row["source_job_id"], "target_job_id": row["target_job_id"],
        "part": row["part"], "model_family": row["model_family"], "tau": row["tau"],
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


def assert_shared_inputs(restart: Path, continuation: Path, names: tuple[str, ...]) -> None:
    for relative in names:
        left = restart / relative
        right = continuation / relative
        if not left.is_file() or not right.is_file() or sha256(left) != sha256(right):
            raise RuntimeError(f"Source runtimes disagree on shared input: {relative}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--restart-root", required=True)
    parser.add_argument("--continuation-root", required=True)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--seed", type=int, default=20260922)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    if args.workers < 1 or args.workers > len(SELECTED_SOURCES):
        raise SystemExit(f"Worker count must be between 1 and {len(SELECTED_SOURCES)}")

    repo = Path(__file__).resolve().parents[2]
    roots = {
        "restart": resolve(repo, args.restart_root),
        "continuation": resolve(repo, args.continuation_root),
    }
    runtime = resolve(repo, args.runtime_root)
    audited = [audit_source(roots, selection) for selection in SELECTED_SOURCES]
    if len({str(row["target_job_id"]) for row in audited}) != len(audited):
        raise RuntimeError("Target job IDs are not unique")

    shared_names = (
        "configs/part1_post_search2_design_cache.rds",
        "configs/part2_final_dec25_design_cache.rds",
        "configs/part3_final_dec25_design_cache.rds",
        "configs/part123_base_config_frozen.yaml",
        "configs/full_data_rhs_calibration.csv",
        "configs/post_search2_selected_components.csv",
        "objects/part1_normal_rhs_driver_bank.rds",
        "objects/part2_normal_rhs_driver_bank.rds",
        "objects/part3_normal_rhs_driver_bank.rds",
    )
    assert_shared_inputs(roots["restart"], roots["continuation"], shared_names)
    if args.validate_only:
        print(json.dumps({
            "source_roots": {key: str(value) for key, value in roots.items()},
            "selected_fits": len(audited),
            "source_iteration_counts": {
                str(count): sum(int(row["source_iterations"]) == count for row in audited)
                for count in sorted({int(row["source_iterations"]) for row in audited})
            },
            "target_job_ids": [row["target_job_id"] for row in audited],
            "status": "VALID",
        }, indent=2))
        return

    if runtime.exists() and any(runtime.iterdir()):
        raise SystemExit(f"Runtime already exists and is nonempty: {runtime}")
    for sub in (
        "configs", "source_contracts", "source_objects", "source_traces", "objects",
        "forecasts", "scores", "traces", "coefficients", "tables", "logs",
        "status", "scripts", "manifests",
    ):
        (runtime / sub).mkdir(parents=True, exist_ok=True)

    imports: list[dict[str, object]] = []
    canonical = roots["continuation"]
    for relative in shared_names:
        link_verified(canonical / relative, runtime / relative, imports, f"shared:{relative}")
    for kind, source_root in roots.items():
        manifest_path, contract_path, _ = runtime_schema(source_root, kind)
        link_verified(manifest_path, runtime / "source_contracts" / f"{kind}_{manifest_path.name}", imports, f"source_manifest:{kind}")
        link_verified(contract_path, runtime / "source_contracts" / f"{kind}_{contract_path.name}", imports, f"source_contract:{kind}")
    for row in audited:
        source_id = str(row["source_job_id"])
        fit_destination = runtime / "source_objects" / f"{source_id}_fit.rds"
        trace_destination = runtime / "source_traces" / f"{source_id}_cumulative_trace.csv"
        execution_destination = runtime / "source_contracts" / f"{source_id}_execution_contract.csv"
        certificate_destination = runtime / "source_contracts" / f"{source_id}_certification.csv"
        link_verified(Path(str(row["source_fit_path"])), fit_destination, imports, f"source_fit:{source_id}")
        link_verified(Path(str(row["source_cumulative_trace_path"])), trace_destination, imports, f"source_trace:{source_id}")
        link_verified(Path(str(row["source_execution_contract"])), execution_destination, imports, f"source_execution:{source_id}")
        link_verified(Path(str(row["source_certificate"])), certificate_destination, imports, f"source_certificate:{source_id}")
        row["imported_source_fit_path"] = str(fit_destination.resolve())
        row["imported_source_trace_path"] = str(trace_destination.resolve())

    with (runtime / "manifests/imported_dependencies.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(imports[0]))
        writer.writeheader()
        writer.writerows(imports)
    with (runtime / "tables/source_selection.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(audited[0]))
        writer.writeheader()
        writer.writerows(audited)

    tolerance = 1.0e-4
    gate_rows = [terminal_gate_row(row, tolerance) for row in audited]
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
    selection_path = runtime / "configs/post_search2_selected_components.csv"
    calibration = runtime / "configs/full_data_rhs_calibration.csv"
    jobs: list[dict[str, object]] = []
    for row in audited:
        part = str(row["part"])
        family = str(row["model_family"])
        tau = str(row["tau"])
        source_id = str(row["source_job_id"])
        fit_id = str(row["target_job_id"])
        source_iterations = int(row["source_iterations"])
        cumulative_iterations = int(row["expected_cumulative_iterations"])
        cache = runtime / "configs" / design_names[part]
        command = [
            "Rscript", "application/scripts/423_run_glofas_quantile_certification_continuation.R",
            "--runtime_root", str(runtime), "--job_id", fit_id, "--part", part,
            "--model_family", family, "--tau", tau,
            "--source_fit_path", row["imported_source_fit_path"],
            "--source_fit_sha256", row["source_fit_sha256"],
            "--source_cumulative_trace_path", row["imported_source_trace_path"],
            "--source_cumulative_trace_sha256", row["source_cumulative_trace_sha256"],
            "--expected_source_iterations", str(source_iterations),
            "--design_cache", str(cache), "--design_cache_sha256", sha256(cache),
            "--max_iter", "200", "--min_iter", "200", "--convergence_tolerance", "1e-4",
            "--freeze_beta_warmup_iters", "20", "--min_beta_updates", "30",
            "--terminal_consecutive_passes", "3", "--progress_every", "1",
        ]
        jobs.append({
            "job_id": fit_id, "part": part, "action": "fit", "model_family": family,
            "tau": tau, "source_job_id": source_id,
            "source_runtime": row["source_runtime"],
            "source_fit_sha256": row["source_fit_sha256"],
            "source_cumulative_trace_sha256": row["source_cumulative_trace_sha256"],
            "expected_source_iterations": source_iterations,
            "expected_cumulative_iterations": cumulative_iterations,
            "dependencies": [], "required_certified_dependencies": [], "command": command,
        })
        forecast_id = fit_id.replace("_fit_", "_forecast_", 1)
        if part == "part1":
            forecast_command = [
                "Rscript", "application/scripts/403_run_glofas_post_search2_support_job.R",
                "--runtime_root", str(runtime), "--job_id", forecast_id,
                "--job_type", "part1_forecast", "--base_config", str(base_config),
                "--selected_components", str(selection_path), "--calibration_path", str(calibration),
                "--model_family", family, "--tau", tau, "--fit_job_id", fit_id,
                "--normal_driver_bank_path", str(runtime / "objects/part1_normal_rhs_driver_bank.rds"),
                "--n_draws", "500", "--seed", str(args.seed), "--forecast_backend", "cpp",
            ]
        else:
            forecast_command = [
                "Rscript", "application/scripts/381_run_glofas_dec25_final_refit_job.R",
                "--runtime_root", str(runtime), "--part", part, "--job_id", forecast_id,
                "--job_type", "forecast", "--base_config", str(base_config),
                "--selected_components", str(selection_path), "--calibration_path", str(calibration),
                "--model_family", family, "--tau", tau, "--fit_job_id", fit_id,
                "--normal_driver_bank_path", str(runtime / f"objects/{part}_normal_rhs_driver_bank.rds"),
                "--origin_date", "2022-12-25", "--horizon_days", "30",
                "--normal_draws", "500", "--seed", str(args.seed), "--forecast_backend", "cpp",
            ]
        jobs.append({
            "job_id": forecast_id, "part": part, "action": "forecast", "model_family": family,
            "tau": tau, "source_job_id": source_id, "source_runtime": row["source_runtime"],
            "source_fit_sha256": row["source_fit_sha256"],
            "source_cumulative_trace_sha256": row["source_cumulative_trace_sha256"],
            "expected_source_iterations": source_iterations,
            "expected_cumulative_iterations": cumulative_iterations,
            "dependencies": [fit_id], "required_certified_dependencies": [fit_id],
            "command": forecast_command,
        })

    if len(jobs) != 2 * len(SELECTED_SOURCES):
        raise RuntimeError("Selective DAG does not have one fit and forecast per source")
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
    fields = (
        "job_id", "part", "action", "model_family", "tau", "source_job_id",
        "source_runtime", "source_fit_sha256", "source_cumulative_trace_sha256",
        "expected_source_iterations", "expected_cumulative_iterations", "dependencies",
        "required_certified_dependencies", "script_path", "command_display",
    )
    with (runtime / "configs/certification_continuation_job_manifest.csv").open("w", newline="") as handle:
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
        repo / "application/scripts/423_run_glofas_quantile_certification_continuation.R",
        repo / "application/scripts/424_launch_glofas_quantile_certification_continuation.py",
        repo / "application/scripts/425_check_glofas_quantile_certification_continuation.py",
        repo / "application/scripts/426_prepare_glofas_quantile_selective_continuation.py",
    ]
    missing = [str(path) for path in source_files if not path.is_file()]
    if missing:
        raise RuntimeError(f"Missing selective-continuation source files: {missing}")
    contract = {
        "schema_version": "glofas_quantile_selective_continuation_v1",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "git_head": git(repo, "rev-parse", "HEAD"),
        "git_status_at_prepare": git(repo, "status", "--short"),
        "source_runtime_roots": {key: str(value) for key, value in roots.items()},
        "runtime_root": str(runtime), "workers": args.workers,
        "fit_jobs": len(SELECTED_SOURCES), "forecast_jobs": len(SELECTED_SOURCES),
        "manifest_sha256": sha256(manifest_path),
        "iteration_contract": {
            "source_iterations_by_job": {
                str(row["target_job_id"]): int(row["source_iterations"]) for row in audited
            },
            "continuation_iterations": 200, "fixed_iterations": True,
            "beta_freeze": 20, "minimum_beta_updates": 30,
            "tolerance": tolerance, "terminal_consecutive_passes": 3,
        },
        "selection_contract": {
            "selected_fit_jobs": [str(row["target_job_id"]) for row in audited],
            "deferred_families": ["part1_joint_al", "part2_joint_al", "part3_joint_al"],
            "reason": "Continue only near-threshold or demonstrably contracting unresolved fits.",
        },
        "scientific_contract": {
            "cutoff": "2022-12-25", "forecast_start": "2022-12-26",
            "forecast_end": "2023-01-24", "horizon_days": 30,
            "response_scale": "log1p", "draws": 500,
            "future_truth_used_for_inputs": False,
        },
        "source_hashes": {str(path.relative_to(repo)): sha256(path) for path in source_files},
    }
    contract_path = runtime / "configs/certification_continuation_contract.json"
    contract_path.write_text(json.dumps(contract, indent=2, sort_keys=True) + "\n")
    print(json.dumps({
        "runtime_root": str(runtime), "fit_jobs": len(SELECTED_SOURCES),
        "forecast_jobs": len(SELECTED_SOURCES), "workers": args.workers,
        "manifest_sha256": contract["manifest_sha256"],
        "status": "PREPARED_NOT_LAUNCHED",
    }, indent=2))


if __name__ == "__main__":
    main()
