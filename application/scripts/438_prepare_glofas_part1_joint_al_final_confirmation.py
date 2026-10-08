#!/usr/bin/env python3.11
"""Prepare the single hard-stop Part 1 joint-AL continuation from 600 to 800."""

from __future__ import annotations

import argparse
import csv
import errno
import hashlib
import json
import math
import os
import shlex
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path


SOURCE_JOB = "semantic_part1_fit_joint_al_all7"
TARGET_JOB = "semantic_final_part1_fit_joint_al_all7"
SOURCE_ITERATIONS = 600
TARGET_ITERATIONS = 800
TOLERANCE = 1.0e-4


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def truth(value: object) -> bool:
    return str(value).strip().lower() in ("true", "1", "yes")


def read_one(path: Path) -> dict[str, str]:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 1:
        raise RuntimeError(f"Expected one row in {path}; found {len(rows)}")
    return rows[0]


def link_verified(source: Path, destination: Path) -> dict[str, object]:
    source = source.resolve(strict=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        if sha256(source) != sha256(destination):
            raise RuntimeError(f"Refusing to replace a nonidentical import: {destination}")
    else:
        try:
            os.link(source, destination)
        except OSError as error:
            if error.errno != errno.EXDEV:
                raise
            shutil.copy2(source, destination)
    return {
        "source_path": str(source),
        "destination_path": str(destination.resolve()),
        "bytes": source.stat().st_size,
        "sha256": sha256(source),
        "hardlinked": os.stat(source).st_ino == os.stat(destination).st_ino,
    }


def log_slope(rows: list[dict[str, str]], field: str) -> float:
    points = [(float(row["iter"]), math.log(float(row[field]))) for row in rows]
    mean_x = sum(point[0] for point in points) / len(points)
    mean_y = sum(point[1] for point in points) / len(points)
    denominator = sum((point[0] - mean_x) ** 2 for point in points)
    return sum((x - mean_x) * (y - mean_y) for x, y in points) / denominator


def projected_updates(current: float, slope: float, tolerance: float = TOLERANCE) -> int:
    if current <= tolerance:
        return 0
    if not math.isfinite(slope) or slope >= 0:
        return 10**9
    return max(0, math.ceil(math.log(tolerance / current) / slope))


def diagnose_progress(path: Path) -> dict[str, object]:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 200:
        raise RuntimeError("Source progress trace must contain exactly 200 continuation rows")
    if [int(float(row["global_iter"])) for row in rows] != list(range(401, 601)):
        raise RuntimeError("Source progress trace is not the exact global sequence 401:600")
    released = [row for row in rows if truth(row["beta_updated"])]
    if len(released) != 180:
        raise RuntimeError("Source continuation must contain exactly 180 released beta updates")
    recent = released[-40:]
    final = rows[-1]
    rhs_slope = log_slope(recent, "max_rhs_change")
    latent_slope = log_slope(recent, "max_latent_change")
    rhs_updates = projected_updates(float(final["max_rhs_change"]), rhs_slope)
    latent_updates = projected_updates(float(final["max_latent_change"]), latent_slope)
    recent20 = released[-20:]
    decreasing = lambda field: all(
        float(right[field]) < float(left[field]) for left, right in zip(recent20, recent20[1:])
    )
    monitor_nondecreasing = all(
        float(right["monitor"]) >= float(left["monitor"])
        for left, right in zip(recent20, recent20[1:])
    )
    authorization = all((
        float(final["max_beta_relative_change"]) <= TOLERANCE,
        float(final["max_path_change"]) <= TOLERANCE,
        float(final["max_latent_change"]) <= 1.1 * TOLERANCE,
        float(final["max_rhs_change"]) <= 5.0 * TOLERANCE,
        decreasing("max_latent_change"), decreasing("max_rhs_change"),
        monitor_nondecreasing,
        max(rhs_updates, latent_updates) + 20 + 3 <= 200,
    ))
    return {
        "source_iterations": SOURCE_ITERATIONS,
        "terminal_beta_change": float(final["max_beta_relative_change"]),
        "terminal_path_change": float(final["max_path_change"]),
        "terminal_latent_change": float(final["max_latent_change"]),
        "terminal_rhs_change": float(final["max_rhs_change"]),
        "terminal_monitor": float(final["monitor"]),
        "recent40_latent_log_slope": latent_slope,
        "recent40_rhs_log_slope": rhs_slope,
        "projected_released_updates_to_latent_tolerance": latent_updates,
        "projected_released_updates_to_rhs_tolerance": rhs_updates,
        "recent20_latent_strictly_decreasing": decreasing("max_latent_change"),
        "recent20_rhs_strictly_decreasing": decreasing("max_rhs_change"),
        "recent20_monitor_nondecreasing": monitor_nondecreasing,
        "final_continuation_authorized": authorization,
    }


def validate_checkpoint(fit_path: Path) -> None:
    expression = """
x <- readRDS(commandArgs(TRUE)[1])
stopifnot(
  identical(as.integer(x$iterations_completed), 600L),
  isTRUE(x$checkpoint_state$complete_local_state),
  identical(tolower(as.character(x$model_family)), 'joint_al'),
  length(x$tau) == 7L,
  !isTRUE(x$converged),
  identical(x$stopping_reason, 'completed_fixed_iterations_without_terminal_certificate'),
  !is.null(x$v_mean), !is.null(x$v_inv_mean),
  identical(dim(x$v_mean), dim(x$v_inv_mean)), ncol(x$v_mean) == 7L
)
cat('EXACT_PART1_600_CHECKPOINT_OK\n')
"""
    subprocess.run(
        ["Rscript", "-e", expression, str(fit_path)], check=True,
        env={**os.environ, **{key: "1" for key in (
            "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
            "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS",
        )}},
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--workers", type=int, default=1)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    if args.workers != 1:
        raise SystemExit("The final confirmation requires exactly one worker")

    repo = Path(__file__).resolve().parents[2]
    source_root = Path(args.source_root).resolve()
    runtime = Path(args.runtime_root).resolve()
    source_fit = source_root / f"objects/{SOURCE_JOB}_fit.rds"
    source_trace = source_root / f"traces/{SOURCE_JOB}_cumulative_trace.csv"
    source_progress = source_root / f"traces/{SOURCE_JOB}_progress.csv"
    source_execution = source_root / f"logs/{SOURCE_JOB}_execution_contract.csv"
    source_certificate = source_root / f"tables/{SOURCE_JOB}_certification.csv"
    design_cache = source_root / "configs/part1_post_search2_design_cache.rds"
    source_manifest = source_root / "configs/certification_continuation_job_manifest.json"
    source_contract = source_root / "configs/certification_continuation_contract.json"
    required = (
        source_fit, source_trace, source_progress, source_execution, source_certificate,
        design_cache, source_manifest, source_contract,
        source_root / f"status/{SOURCE_JOB}.completed",
    )
    for path in required:
        if not path.is_file():
            raise RuntimeError(f"Missing final-confirmation input: {path}")
    if (source_root / f"status/{SOURCE_JOB}.certified").exists():
        raise RuntimeError("The 600-iteration source is already certified")

    execution = read_one(source_execution)
    certificate = read_one(source_certificate)
    if sha256(source_fit) != execution["fit_sha256"]:
        raise RuntimeError("Source fit hash does not match its execution contract")
    if sha256(source_trace) != execution["cumulative_trace_sha256"]:
        raise RuntimeError("Source trace hash does not match its execution contract")
    if int(execution["cumulative_iterations"]) != SOURCE_ITERATIONS:
        raise RuntimeError("Source execution does not end at iteration 600")
    if truth(execution["certified"]) or truth(certificate["certified"]):
        raise RuntimeError("Source certification state is inconsistent")
    if execution["prior_source_sha256"] != execution["prior_continuation_sha256"]:
        raise RuntimeError("Source continuation changed the prior signature")
    contract = json.loads(source_contract.read_text())
    if sha256(source_manifest) != contract["manifest_sha256"]:
        raise RuntimeError("Source runtime manifest hash mismatch")
    with source_trace.open(newline="") as handle:
        trace_rows = list(csv.DictReader(handle))
    if len(trace_rows) != SOURCE_ITERATIONS or [int(float(row["global_iter"])) for row in trace_rows] != list(range(1, 601)):
        raise RuntimeError("Source cumulative trace is not exactly 1:600")
    validate_checkpoint(source_fit)
    diagnosis = diagnose_progress(source_progress)
    if not diagnosis["final_continuation_authorized"]:
        raise RuntimeError("The bounded 600-to-800 continuation authorization gate failed")
    if args.validate_only:
        print(json.dumps({**diagnosis, "source_fit_sha256": sha256(source_fit), "status": "VALID_FINAL_CONTINUATION"}, indent=2))
        return

    if runtime.exists() and any(runtime.iterdir()):
        raise SystemExit(f"Runtime already exists and is nonempty: {runtime}")
    for sub in (
        "configs", "source_objects", "objects", "scores", "traces", "coefficients",
        "tables", "reports", "logs", "status", "scripts", "manifests",
    ):
        (runtime / sub).mkdir(parents=True, exist_ok=True)

    imports = []
    destinations = {
        "source_fit": runtime / f"source_objects/{SOURCE_JOB}_fit.rds",
        "source_cumulative_trace": runtime / f"source_objects/{SOURCE_JOB}_cumulative_trace.csv",
        "source_progress_trace": runtime / f"source_objects/{SOURCE_JOB}_progress.csv",
        "source_execution_contract": runtime / f"source_objects/{SOURCE_JOB}_execution_contract.csv",
        "source_certificate": runtime / f"source_objects/{SOURCE_JOB}_certification.csv",
        "design_cache": runtime / "configs/part1_post_search2_design_cache.rds",
    }
    sources = {
        "source_fit": source_fit, "source_cumulative_trace": source_trace,
        "source_progress_trace": source_progress, "source_execution_contract": source_execution,
        "source_certificate": source_certificate, "design_cache": design_cache,
    }
    for role, source in sources.items():
        row = link_verified(source, destinations[role])
        row["role"] = role
        imports.append(row)
    with (runtime / "manifests/imported_dependencies.csv").open("w", newline="") as handle:
        fields = ("role", "source_path", "destination_path", "bytes", "sha256", "hardlinked")
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(imports)
    with (runtime / "tables/source_600_diagnosis.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(diagnosis))
        writer.writeheader()
        writer.writerow(diagnosis)

    command = [
        "Rscript", "application/scripts/423_run_glofas_quantile_certification_continuation.R",
        "--runtime_root", str(runtime), "--job_id", TARGET_JOB,
        "--part", "part1", "--model_family", "joint_al", "--tau", "all7",
        "--source_fit_path", str(destinations["source_fit"]),
        "--source_fit_sha256", sha256(destinations["source_fit"]),
        "--source_cumulative_trace_path", str(destinations["source_cumulative_trace"]),
        "--source_cumulative_trace_sha256", sha256(destinations["source_cumulative_trace"]),
        "--expected_source_iterations", str(SOURCE_ITERATIONS),
        "--design_cache", str(destinations["design_cache"]),
        "--design_cache_sha256", sha256(destinations["design_cache"]),
        "--max_iter", "200", "--min_iter", "200", "--convergence_tolerance", "1e-4",
        "--freeze_beta_warmup_iters", "20", "--min_beta_updates", "30",
        "--terminal_consecutive_passes", "3", "--progress_every", "1",
    ]
    script_path = runtime / f"scripts/{TARGET_JOB}.sh"
    script_path.write_text(
        "#!/usr/bin/env bash\nset -euo pipefail\n"
        "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 "
        "VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1\n"
        f"cd {shlex.quote(str(repo))}\nexec {shlex.join(command)}\n"
    )
    script_path.chmod(0o755)
    job = {
        "job_id": TARGET_JOB, "part": "part1", "action": "fit",
        "model_family": "joint_al", "tau": "all7", "source_job_id": SOURCE_JOB,
        "source_fit_sha256": sha256(destinations["source_fit"]),
        "source_cumulative_trace_sha256": sha256(destinations["source_cumulative_trace"]),
        "expected_source_iterations": SOURCE_ITERATIONS,
        "expected_cumulative_iterations": TARGET_ITERATIONS,
        "dependencies": [], "required_certified_dependencies": [],
        "script_path": str(script_path), "command_display": shlex.join(command),
    }
    manifest_path = runtime / "configs/certification_continuation_job_manifest.json"
    manifest_path.write_text(json.dumps([job], indent=2) + "\n")

    source_files = [
        repo / "application/R/glofas_quantile_integrity.R",
        repo / "application/R/glofas_quantile_certification_restart.R",
        repo / "application/R/glofas_part1_quantile_oracle_forecast.R",
        repo / "application/scripts/423_run_glofas_quantile_certification_continuation.R",
        repo / "application/scripts/424_launch_glofas_quantile_certification_continuation.py",
        repo / "application/scripts/425_check_glofas_quantile_certification_continuation.py",
        Path(__file__).resolve(),
    ]
    final_contract = {
        "schema_version": "glofas_part1_joint_al_final_confirmation_v1",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "git_head": subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip(),
        "git_status_at_prepare": subprocess.check_output(["git", "-C", str(repo), "status", "--short"], text=True).strip(),
        "runtime_root": str(runtime), "workers": 1, "fit_jobs": 1, "forecast_jobs": 0,
        "manifest_sha256": sha256(manifest_path),
        "iteration_contract": {
            "source_iterations": SOURCE_ITERATIONS, "continuation_iterations": 200,
            "cumulative_iterations": TARGET_ITERATIONS, "fixed_iterations": True,
            "beta_freeze": 20, "minimum_beta_updates": 30,
            "tolerance": TOLERANCE, "terminal_consecutive_passes": 3,
        },
        "decision_contract": {
            "authorization": diagnosis,
            "hard_stop_cumulative_iterations": TARGET_ITERATIONS,
            "if_uncertified": "quarantine_part1_joint_al_no_further_continuation",
            "forecast_authorized": False,
            "posterior_target_changed": False,
        },
        "scientific_contract": {
            "role": "final_same_target_confirmation_not_geometry_selection",
            "cutoff": "2022-12-25", "response_scale": "log1p",
            "search3_reference_geometry": "search3_ref_001_search2_ref_008_retained",
        },
        "source_hashes": {str(path.relative_to(repo)): sha256(path) for path in source_files},
    }
    contract_path = runtime / "configs/certification_continuation_contract.json"
    contract_path.write_text(json.dumps(final_contract, indent=2, sort_keys=True) + "\n")
    report = [
        "# Part 1 Joint-AL Final Confirmation Decision", "",
        "The 600-iteration fit completed without certification. A single final exact-state",
        "200-iteration continuation is authorized because coefficient, path, latent and RHS",
        "changes contract monotonically and the fitted objective is monotone over the terminal",
        "window. The posterior target and prior signature are unchanged.", "",
        f"Projected released updates to RHS tolerance: `{diagnosis['projected_released_updates_to_rhs_tolerance']}`.",
        f"Projected released updates to latent tolerance: `{diagnosis['projected_released_updates_to_latent_tolerance']}`.", "",
        "This is a hard-stop experiment. Failure to certify by cumulative iteration 800",
        "quarantines Part 1 joint AL and does not authorize another continuation.",
    ]
    (runtime / "reports/final_confirmation_decision.md").write_text("\n".join(report) + "\n")
    (runtime / "status/prepared_not_launched").write_text(datetime.now(timezone.utc).isoformat() + "\n")
    print(json.dumps({
        "runtime_root": str(runtime), "fit_jobs": 1, "forecast_jobs": 0,
        "source_iterations": SOURCE_ITERATIONS, "target_iterations": TARGET_ITERATIONS,
        "manifest_sha256": final_contract["manifest_sha256"],
        "status": "PREPARED_NOT_LAUNCHED",
    }, indent=2))


if __name__ == "__main__":
    main()
