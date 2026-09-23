#!/usr/bin/env python3.11
"""Launch a hash-chained, bounded Part 4 joint continuation controller."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shlex
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def completed_value(path: Path, key: str) -> str:
    values = {}
    for line in path.read_text().splitlines():
        if "=" in line:
            name, value = line.split("=", 1)
            values[name] = value
    return values.get(key, "")


def prepare(repo: Path, source: Path, output: Path, likelihood: str, source_job: str,
            max_cumulative: int, batch_size: int,
            resume_fit_path: Path | None = None,
            resume_trace_path: Path | None = None) -> dict[str, object]:
    expected_completed = source / "status" / f"{source_job}.completed"
    if not expected_completed.exists():
        raise RuntimeError(f"Source joint fit is not completed: {source_job}")
    if (resume_fit_path is None) != (resume_trace_path is None):
        raise RuntimeError("A continuation resume requires both fit and trace paths")
    source_fit = (resume_fit_path or source / "objects" / f"{source_job}_fit_side.rds").resolve()
    design = source / "objects/part4_shared_design_truth_free.rds"
    sidecar = source / "objects/part4_scoring_panel_sidecar.rds"
    trace = (resume_trace_path or source / "traces" / f"{source_job}_trace.csv").resolve()
    for path in (source_fit, design, sidecar, trace, source / "configs/part4_model_manifest.csv"):
        path.resolve(strict=True)
    with trace.open() as handle:
        initial_outer = max(0, sum(1 for _ in handle) - 1)
    if initial_outer >= max_cumulative:
        raise RuntimeError("Source already meets or exceeds the continuation safety ceiling")
    for sub in ("objects", "predictions", "scores", "traces", "coefficients", "logs", "status", "manifests"):
        (output / sub).mkdir(parents=True, exist_ok=True)
    contract = {
        "schema_version": "glofas_part4_joint_bounded_continuation_v2",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_runtime_root": str(source), "output_runtime_root": str(output),
        "likelihood": likelihood, "source_job_id": source_job,
        "source_fit_path": str(source_fit), "source_fit_sha256": sha256(source_fit),
        "source_trace_path": str(trace), "source_trace_sha256": sha256(trace),
        "resume_from_external_checkpoint": resume_fit_path is not None,
        "design_sha256": sha256(design), "scoring_sidecar_sha256": sha256(sidecar),
        "initial_outer_iterations": initial_outer,
        "batch_size": batch_size, "max_cumulative_outer_iterations": max_cumulative,
        "outer_tolerance": 1e-3, "rhs_tolerance": 1e-3,
        "terminal_consecutive_passes": 3, "rhs_freeze_outer_iterations": 5,
        "source_hashes": {
            "application/R/latent_path_vb_joint.R": sha256(repo / "application/R/latent_path_vb_joint.R"),
            "application/scripts/389_continue_glofas_part4_joint_fit.R": sha256(repo / "application/scripts/389_continue_glofas_part4_joint_fit.R"),
        },
    }
    contract_path = output / "manifests" / f"part4_joint_{likelihood}_controller_contract.json"
    contract_path.write_text(json.dumps(contract, indent=2, sort_keys=True) + "\n")
    contract["contract_path"] = str(contract_path)
    contract["contract_sha256"] = sha256(contract_path)
    return contract


def run(repo: Path, contract_path: Path, expected_contract_hash: str) -> int:
    if sha256(contract_path) != expected_contract_hash:
        raise RuntimeError("Part 4 continuation controller contract hash mismatch")
    contract = json.loads(contract_path.read_text())
    for relative, expected in contract["source_hashes"].items():
        if sha256(repo / relative) != expected:
            raise RuntimeError(f"Source changed after continuation preparation: {relative}")
    source = Path(contract["source_runtime_root"])
    output = Path(contract["output_runtime_root"])
    likelihood = str(contract["likelihood"])
    source_job = str(contract["source_job_id"])
    current_fit = Path(contract["source_fit_path"])
    current_hash = str(contract["source_fit_sha256"])
    cumulative = int(contract["initial_outer_iterations"])
    batch_size = int(contract["batch_size"])
    ceiling = int(contract["max_cumulative_outer_iterations"])
    controller_status = output / "status" / f"part4_joint_{likelihood}_controller"
    (controller_status.with_suffix(".running")).write_text(datetime.now(timezone.utc).isoformat() + "\n")
    env = os.environ.copy()
    env.update({key: "1" for key in (
        "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS",
    )})
    batch = 0
    converged = False
    while cumulative < ceiling and not converged:
        batch += 1
        additional = min(batch_size, ceiling - cumulative)
        output_job = f"part4_joint_{likelihood}_continuation_b{batch:02d}"
        command = [
            "Rscript", "application/scripts/389_continue_glofas_part4_joint_fit.R",
            "--source_runtime_root", str(source), "--output_runtime_root", str(output),
            "--source_job_id", source_job, "--source_fit_path", str(current_fit),
            "--output_job_id", output_job, "--likelihood", likelihood,
            "--expected_source_fit_sha256", current_hash,
            "--expected_design_sha256", str(contract["design_sha256"]),
            "--expected_scoring_sidecar_sha256", str(contract["scoring_sidecar_sha256"]),
            "--additional_outer_max_iter", str(additional), "--inner_max_iter", "30",
            "--inner_min_iter", "10", "--outer_tol", str(contract["outer_tolerance"]),
            "--n_draws", "500", "--joint_rhs_freeze_outer_iters", "5",
            "--joint_rhs_min_tau_updates", "1", "--joint_rhs_tol", str(contract["rhs_tolerance"]),
            "--terminal_consecutive_passes", str(contract["terminal_consecutive_passes"]),
            "--allow_rhs_schedule_rebase", "false",
        ]
        log_path = output / "logs" / f"{output_job}.log"
        with log_path.open("a") as log:
            log.write(f"COMMAND={shlex.join(command)}\n")
            log.flush()
            rc = subprocess.call(command, cwd=repo, env=env, stdout=log, stderr=subprocess.STDOUT)
        completed = output / "status" / f"{output_job}.completed"
        if rc != 0 or not completed.exists():
            (controller_status.with_suffix(".running")).unlink(missing_ok=True)
            (controller_status.with_suffix(".failed")).write_text(f"batch={batch}\nexit_code={rc}\n")
            return 1
        current_fit = output / "objects" / f"{output_job}_fit_side.rds"
        current_hash = sha256(current_fit)
        cumulative += additional
        converged = completed_value(completed, "converged").strip().lower() == "true"
        health = {
            "checked_at_utc": datetime.now(timezone.utc).isoformat(), "likelihood": likelihood,
            "completed_batches": batch, "cumulative_outer_iterations": cumulative,
            "converged": converged, "latest_fit_path": str(current_fit),
            "latest_fit_sha256": current_hash, "safety_ceiling": ceiling,
        }
        (output / "status" / f"part4_joint_{likelihood}_controller_health.json").write_text(
            json.dumps(health, indent=2, sort_keys=True) + "\n"
        )
    (controller_status.with_suffix(".running")).unlink(missing_ok=True)
    terminal = controller_status.with_suffix(".completed" if converged else ".ceiling_reached")
    terminal.write_text(json.dumps({"converged": converged, "cumulative_outer_iterations": cumulative,
                                    "latest_fit_path": str(current_fit), "latest_fit_sha256": current_hash}, indent=2) + "\n")
    return 0 if converged else 3


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-runtime-root", required=True)
    parser.add_argument("--output-runtime-root", required=True)
    parser.add_argument("--likelihood", choices=("al", "exal"), required=True)
    parser.add_argument("--source-job-id", required=True)
    parser.add_argument("--session-label", required=True)
    parser.add_argument("--batch-size", type=int, default=5)
    parser.add_argument("--max-cumulative-outer-iterations", type=int, default=20)
    parser.add_argument("--resume-fit-path", default="")
    parser.add_argument("--resume-trace-path", default="")
    parser.add_argument("--run-contract", default="")
    parser.add_argument("--expected-contract-sha256", default="")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    if args.run_contract:
        raise SystemExit(run(repo, Path(args.run_contract).resolve(), args.expected_contract_sha256))
    source = (repo / args.source_runtime_root).resolve() if not Path(args.source_runtime_root).is_absolute() else Path(args.source_runtime_root).resolve()
    output = (repo / args.output_runtime_root).resolve() if not Path(args.output_runtime_root).is_absolute() else Path(args.output_runtime_root).resolve()
    resume_fit = Path(args.resume_fit_path).resolve() if args.resume_fit_path else None
    resume_trace = Path(args.resume_trace_path).resolve() if args.resume_trace_path else None
    contract = prepare(
        repo, source, output, args.likelihood, args.source_job_id,
        args.max_cumulative_outer_iterations, args.batch_size,
        resume_fit_path=resume_fit, resume_trace_path=resume_trace,
    )
    if subprocess.run(["tmux", "has-session", "-t", args.session_label], capture_output=True).returncode == 0:
        raise SystemExit(f"tmux session already exists: {args.session_label}")
    command = [sys.executable, str(Path(__file__).resolve()),
               "--source-runtime-root", str(source), "--output-runtime-root", str(output),
               "--likelihood", args.likelihood, "--source-job-id", args.source_job_id,
               "--session-label", args.session_label,
               "--run-contract", contract["contract_path"],
               "--expected-contract-sha256", contract["contract_sha256"]]
    subprocess.check_call(["tmux", "new-session", "-d", "-s", args.session_label, shlex.join(command)])
    print(json.dumps({"session": args.session_label, **contract}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
