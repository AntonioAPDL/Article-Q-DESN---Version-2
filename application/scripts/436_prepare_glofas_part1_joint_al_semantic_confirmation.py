#!/usr/bin/env python3.11
"""Prepare one exact-state Part 1 joint-AL semantic-convergence confirmation."""

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


SOURCE_JOB = "cert_part1_fit_joint_al_all7"
TARGET_JOB = "semantic_part1_fit_joint_al_all7"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


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


def validate_trace(path: Path) -> None:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    observed = [int(float(row["global_iter"])) for row in rows]
    if len(rows) != 400 or observed != list(range(1, 401)):
        raise RuntimeError("Part 1 source cumulative trace is not exactly 1:400")


def validate_rds_checkpoint(repo: Path, fit_path: Path) -> None:
    expression = """
x <- readRDS(commandArgs(TRUE)[1])
stopifnot(
  identical(as.integer(x$iterations_completed), 400L),
  isTRUE(x$checkpoint_state$complete_local_state),
  identical(tolower(as.character(x$model_family)), 'joint_al'),
  length(x$tau) == 7L,
  !is.null(x$v_mean), !is.null(x$v_inv_mean),
  identical(dim(x$v_mean), dim(x$v_inv_mean)),
  ncol(x$v_mean) == 7L
)
cat('EXACT_PART1_CHECKPOINT_OK\n')
"""
    subprocess.run(
        ["Rscript", "-e", expression, str(fit_path)], cwd=repo, check=True,
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
        raise SystemExit("The representative confirmation contract requires exactly one worker")

    repo = Path(__file__).resolve().parents[2]
    source_root = Path(args.source_root).resolve()
    runtime = Path(args.runtime_root).resolve()
    source_fit = source_root / f"objects/{SOURCE_JOB}_fit.rds"
    source_trace = source_root / f"traces/{SOURCE_JOB}_cumulative_trace.csv"
    source_contract = source_root / f"logs/{SOURCE_JOB}_execution_contract.csv"
    design_cache = source_root / "configs/part1_post_search2_design_cache.rds"
    completed = source_root / f"status/{SOURCE_JOB}.completed"
    for path in (source_fit, source_trace, source_contract, design_cache, completed):
        if not path.is_file():
            raise RuntimeError(f"Missing representative-confirmation input: {path}")

    execution = read_one(source_contract)
    if execution["fit_sha256"].lower() != sha256(source_fit):
        raise RuntimeError("Part 1 source fit hash does not match its execution contract")
    if int(execution["cumulative_iterations"]) != 400:
        raise RuntimeError("Part 1 source is not the expected 400-iteration checkpoint")
    if execution["certified"].lower() not in ("false", "0"):
        raise RuntimeError("Part 1 source is already certified; confirmation is unnecessary")
    if execution["prior_source_sha256"] != execution["prior_restart_sha256"]:
        raise RuntimeError("Part 1 source prior identity check failed")
    validate_trace(source_trace)
    validate_rds_checkpoint(repo, source_fit)
    if args.validate_only:
        print(json.dumps({
            "source_fit": str(source_fit), "source_fit_sha256": sha256(source_fit),
            "source_iterations": 400, "status": "VALID_EXACT_CHECKPOINT",
        }, indent=2))
        return

    if runtime.exists() and any(runtime.iterdir()):
        raise SystemExit(f"Runtime already exists and is nonempty: {runtime}")
    for sub in (
        "configs", "source_objects", "objects", "scores", "traces", "coefficients",
        "tables", "logs", "status", "scripts", "manifests",
    ):
        (runtime / sub).mkdir(parents=True, exist_ok=True)

    imports = []
    imported_fit = runtime / f"source_objects/{SOURCE_JOB}_fit.rds"
    imported_trace = runtime / f"source_objects/{SOURCE_JOB}_cumulative_trace.csv"
    imported_design = runtime / "configs/part1_post_search2_design_cache.rds"
    for role, source, destination in (
        ("source_fit", source_fit, imported_fit),
        ("source_cumulative_trace", source_trace, imported_trace),
        ("design_cache", design_cache, imported_design),
        ("source_execution_contract", source_contract, runtime / f"source_objects/{SOURCE_JOB}_execution_contract.csv"),
    ):
        row = link_verified(source, destination)
        row["role"] = role
        imports.append(row)
    with (runtime / "manifests/imported_dependencies.csv").open("w", newline="") as handle:
        fields = ("role", "source_path", "destination_path", "bytes", "sha256", "hardlinked")
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(imports)

    command = [
        "Rscript", "application/scripts/423_run_glofas_quantile_certification_continuation.R",
        "--runtime_root", str(runtime), "--job_id", TARGET_JOB,
        "--part", "part1", "--model_family", "joint_al", "--tau", "all7",
        "--source_fit_path", str(imported_fit), "--source_fit_sha256", sha256(imported_fit),
        "--source_cumulative_trace_path", str(imported_trace),
        "--source_cumulative_trace_sha256", sha256(imported_trace),
        "--expected_source_iterations", "400",
        "--design_cache", str(imported_design), "--design_cache_sha256", sha256(imported_design),
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
        "model_family": "joint_al", "tau": "all7",
        "source_job_id": SOURCE_JOB, "source_fit_sha256": sha256(imported_fit),
        "source_cumulative_trace_sha256": sha256(imported_trace),
        "expected_source_iterations": 400, "expected_cumulative_iterations": 600,
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
    contract = {
        "schema_version": "glofas_part1_joint_al_semantic_confirmation_v1",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "git_head": subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip(),
        "git_status_at_prepare": subprocess.check_output(["git", "-C", str(repo), "status", "--short"], text=True).strip(),
        "runtime_root": str(runtime), "workers": 1, "fit_jobs": 1, "forecast_jobs": 0,
        "manifest_sha256": sha256(manifest_path),
        "iteration_contract": {
            "source_iterations": 400, "continuation_iterations": 200,
            "fixed_iterations": True, "beta_freeze": 20,
            "minimum_beta_updates": 30, "tolerance": 1.0e-4,
            "terminal_consecutive_passes": 3,
        },
        "scientific_contract": {
            "role": "representative_same_target_confirmation_not_geometry_selection",
            "cutoff": "2022-12-25", "response_scale": "log1p",
            "search3_reference_geometry": "search3_ref_001_search2_ref_008_retained",
            "posterior_target_changed": False, "forecast_authorized": False,
        },
        "source_hashes": {str(path.relative_to(repo)): sha256(path) for path in source_files},
    }
    contract_path = runtime / "configs/certification_continuation_contract.json"
    contract_path.write_text(json.dumps(contract, indent=2, sort_keys=True) + "\n")
    (runtime / "status/prepared_not_launched").write_text(datetime.now(timezone.utc).isoformat() + "\n")
    print(json.dumps({
        "runtime_root": str(runtime), "fit_jobs": 1, "forecast_jobs": 0,
        "manifest_sha256": contract["manifest_sha256"],
        "status": "PREPARED_NOT_LAUNCHED",
    }, indent=2))


if __name__ == "__main__":
    main()
