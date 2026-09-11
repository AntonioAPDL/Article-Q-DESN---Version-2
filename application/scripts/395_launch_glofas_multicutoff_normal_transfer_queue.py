#!/usr/bin/env python3
"""Prepare and run leakage-safe Normal transfer fits sequentially by cutoff."""

import argparse
import csv
import json
import os
import re
import shlex
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


APPROVAL_TOKEN = "RUN_GLOFAS_MULTICUTOFF_NORMAL_QUEUE"
PART4_APPROVAL_TOKEN = "RUN_GLOFAS_PART4_LATENT_FAMILY"
THREAD_ENV = {
    "OMP_NUM_THREADS": "1",
    "OMP_THREAD_LIMIT": "1",
    "OPENBLAS_NUM_THREADS": "1",
    "GOTO_NUM_THREADS": "1",
    "MKL_NUM_THREADS": "1",
    "BLIS_NUM_THREADS": "1",
    "VECLIB_MAXIMUM_THREADS": "1",
    "NUMEXPR_NUM_THREADS": "1",
}


def repo_root():
    return Path(__file__).resolve().parents[2]


def resolve(path):
    candidate = Path(path)
    return candidate.resolve() if candidate.is_absolute() else (repo_root() / candidate).resolve()


def parse_cutoffs(value):
    values = [item.strip() for item in str(value).split(",") if item.strip()]
    if not values:
        raise ValueError("at least one cutoff is required")
    if len(values) != len(set(values)):
        raise ValueError("cutoffs must be unique")
    if any(re.fullmatch(r"\d{4}-\d{2}-\d{2}", item) is None for item in values):
        raise ValueError("cutoffs must use YYYY-MM-DD")
    return sorted(values)


def run_label(prefix, cutoff, suffix):
    return f"{prefix}_cutoff{cutoff.replace('-', '')}_{suffix}"


def build_plan(cutoffs, runtime_parent, prefix, suffix):
    return [
        {
            "sequence": index,
            "cutoff_date": cutoff,
            "run_label": run_label(prefix, cutoff, suffix),
            "runtime_root": str(runtime_parent / run_label(prefix, cutoff, suffix)),
            "status": "pending",
        }
        for index, cutoff in enumerate(cutoffs, start=1)
    ]


def write_plan(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(path)


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def read_model_manifest(runtime):
    path = runtime / "configs" / "part4_model_manifest.csv"
    if not path.is_file():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def validate_prepared_runtime(runtime, cutoff):
    rows = read_model_manifest(runtime)
    if len(rows) != 2:
        raise RuntimeError(f"expected two prepared jobs at {runtime}, found {len(rows)}")
    expected_families = {"normal_ridge_diagnostic", "normal_rhs_vb_diagnostic"}
    if {row.get("part4_family", "") for row in rows} != expected_families:
        raise RuntimeError(f"unexpected model families at {runtime}")
    cutoff_path = runtime / "configs" / "cutoff.csv"
    with cutoff_path.open(newline="", encoding="utf-8") as handle:
        cutoff_rows = list(csv.DictReader(handle))
    if len(cutoff_rows) != 1 or cutoff_rows[0].get("origin_date") != cutoff:
        raise RuntimeError(f"prepared cutoff mismatch at {runtime}")
    failed = list((runtime / "status").glob("*.failed")) if (runtime / "status").exists() else []
    if failed:
        raise RuntimeError(f"failed markers require audit at {runtime}")


def tmux_alive(name):
    return subprocess.run(
        ["tmux", "has-session", "-t", name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0


def shell_join(parts):
    return " ".join(shlex.quote(str(part)) for part in parts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-parent", required=True)
    parser.add_argument("--anchor-manifest", required=True)
    parser.add_argument(
        "--base-config",
        default="application/config/glofas_latent_path_al_vb_dec25_main.yaml",
    )
    parser.add_argument("--cutoffs", required=True)
    parser.add_argument("--runtime-parent", default="local_trackers/runtime_configs")
    parser.add_argument("--queue-root", required=True)
    parser.add_argument("--run-prefix", default="glofas_normal_transfer")
    parser.add_argument("--run-suffix", default="winner_spec_20260911")
    parser.add_argument("--poll-seconds", type=int, default=30)
    parser.add_argument("--max-iter", type=int, default=100)
    parser.add_argument("--min-iter", type=int, default=30)
    parser.add_argument("--tol", type=float, default=0.01)
    parser.add_argument("--freeze-beta-warmup-iters", type=int, default=20)
    parser.add_argument("--min-beta-updates", type=int, default=10)
    parser.add_argument("--n-draws", type=int, default=500)
    parser.add_argument("--blas-library", default="auto")
    parser.add_argument("--session-name", default="glofas_multicutoff_normal_transfer_overnight")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--approval-token", default="")
    parser.add_argument("--background", action="store_true")
    args = parser.parse_args()

    if not args.execute or args.approval_token != APPROVAL_TOKEN:
        raise SystemExit(
            "Launch blocked. Supply --execute --approval-token " + APPROVAL_TOKEN
        )
    if args.poll_seconds < 1:
        raise SystemExit("poll-seconds must be positive")
    try:
        cutoffs = parse_cutoffs(args.cutoffs)
    except ValueError as error:
        raise SystemExit(str(error))

    bundle_parent = resolve(args.bundle_parent)
    anchor_manifest = resolve(args.anchor_manifest)
    base_config = resolve(args.base_config)
    runtime_parent = resolve(args.runtime_parent)
    queue_root = resolve(args.queue_root)
    for path, label in (
        (bundle_parent, "bundle parent"),
        (anchor_manifest, "anchor manifest"),
        (base_config, "base config"),
    ):
        if not path.exists():
            raise SystemExit(f"missing {label}: {path}")
    for cutoff in cutoffs:
        if not (bundle_parent / f"cutoff_date={cutoff}").is_dir():
            raise SystemExit(f"missing cutoff bundle: {cutoff}")

    runtime_parent.mkdir(parents=True, exist_ok=True)
    queue_root.mkdir(parents=True, exist_ok=True)
    plan = build_plan(cutoffs, runtime_parent, args.run_prefix, args.run_suffix)
    plan_path = queue_root / "queue_manifest.csv"
    write_plan(plan_path, plan)

    command = [
        sys.executable,
        str(Path(__file__).resolve()),
        "--bundle-parent", str(bundle_parent),
        "--anchor-manifest", str(anchor_manifest),
        "--base-config", str(base_config),
        "--cutoffs", ",".join(cutoffs),
        "--runtime-parent", str(runtime_parent),
        "--queue-root", str(queue_root),
        "--run-prefix", args.run_prefix,
        "--run-suffix", args.run_suffix,
        "--poll-seconds", str(args.poll_seconds),
        "--max-iter", str(args.max_iter),
        "--min-iter", str(args.min_iter),
        "--tol", str(args.tol),
        "--freeze-beta-warmup-iters", str(args.freeze_beta_warmup_iters),
        "--min-beta-updates", str(args.min_beta_updates),
        "--n-draws", str(args.n_draws),
        "--blas-library", args.blas_library,
        "--session-name", args.session_name,
        "--execute",
        "--approval-token", APPROVAL_TOKEN,
    ]
    env = os.environ.copy()
    env.update(THREAD_ENV)
    if args.background:
        if tmux_alive(args.session_name):
            print(f"queue_session_already_active={args.session_name}")
            return 0
        log_path = queue_root / "queue.log"
        subprocess.run(
            [
                "tmux", "new-session", "-d", "-s", args.session_name,
                f"{shell_join(command)} >> {shlex.quote(str(log_path))} 2>&1",
            ],
            check=True,
            env=env,
        )
        print(f"queue_session={args.session_name}")
        print(f"queue_log={log_path}")
        print(f"queue_manifest={plan_path}")
        return 0

    running_marker = queue_root / "queue.running"
    completed_marker = queue_root / "queue.completed"
    failed_marker = queue_root / "queue.failed"
    running_marker.write_text(
        f"started_at={datetime.now(timezone.utc).isoformat()}\n", encoding="utf-8"
    )
    metadata = {
        "cutoffs": cutoffs,
        "model_concurrency": 1,
        "cross_cutoff_fitted_state_transfer": False,
        "ridge_initialization": "cold_within_cutoff",
        "rhs_initialization": "exact_same_cutoff_ridge_dependency",
        "max_iter": args.max_iter,
        "min_iter": args.min_iter,
        "tol": args.tol,
        "freeze_beta_warmup_iters": args.freeze_beta_warmup_iters,
        "min_beta_updates": args.min_beta_updates,
        "n_draws": args.n_draws,
    }
    write_json(queue_root / "queue_contract.json", metadata)

    try:
        for row in plan:
            cutoff = row["cutoff_date"]
            runtime = Path(row["runtime_root"])
            row["status"] = "preparing"
            write_plan(plan_path, plan)
            if not read_model_manifest(runtime):
                prepare = [
                    "Rscript",
                    str(repo_root() / "application/scripts/393_prepare_glofas_multicutoff_normal_transfer.R"),
                    "--bundle_root", str(bundle_parent / f"cutoff_date={cutoff}"),
                    "--cutoff_date", cutoff,
                    "--anchor_manifest", str(anchor_manifest),
                    "--base_config", str(base_config),
                    "--run_label", row["run_label"],
                    "--runtime_root", str(runtime),
                    "--max_iter", str(args.max_iter),
                    "--min_iter", str(args.min_iter),
                    "--tol", str(args.tol),
                    "--freeze_beta_warmup_iters", str(args.freeze_beta_warmup_iters),
                    "--min_beta_updates", str(args.min_beta_updates),
                    "--n_draws", str(args.n_draws),
                ]
                subprocess.run(prepare, check=True, cwd=repo_root(), env=env)
            validate_prepared_runtime(runtime, cutoff)

            row["status"] = "running"
            write_plan(plan_path, plan)
            scheduler = [
                sys.executable,
                str(repo_root() / "application/scripts/387_launch_glofas_part4_latent_family_dag.py"),
                "--runtime-root", str(runtime),
                "--workers", "1",
                "--expected-jobs", "2",
                "--poll-seconds", str(args.poll_seconds),
                "--session-prefix", f"glofas_transfer_{cutoff.replace('-', '')}_normal",
                "--blas-library", args.blas_library,
                "--execute",
                "--approval-token", PART4_APPROVAL_TOKEN,
            ]
            subprocess.run(scheduler, check=True, cwd=repo_root(), env=env)

            checker = [
                sys.executable,
                str(repo_root() / "application/scripts/388_check_glofas_part4_latent_family_dag.py"),
                "--runtime-root", str(runtime),
            ]
            subprocess.run(checker, check=True, cwd=repo_root(), env=env)
            completed = list((runtime / "status").glob("*.completed"))
            if len(completed) != 2:
                raise RuntimeError(f"cutoff {cutoff} did not finish both models")

            plot = [
                "Rscript",
                str(repo_root() / "application/scripts/394_plot_glofas_multicutoff_normal_transfer.R"),
                "--runtime_root", str(runtime),
            ]
            subprocess.run(plot, check=True, cwd=repo_root(), env=env)
            row["status"] = "completed"
            write_plan(plan_path, plan)

        if running_marker.exists():
            running_marker.unlink()
        completed_marker.write_text(
            f"completed_at={datetime.now(timezone.utc).isoformat()}\n", encoding="utf-8"
        )
        print(f"MULTICUTOFF_NORMAL_QUEUE_COMPLETE cutoffs={len(plan)} models={2 * len(plan)}")
        return 0
    except Exception as error:
        if running_marker.exists():
            running_marker.unlink()
        failed_marker.write_text(
            f"failed_at={datetime.now(timezone.utc).isoformat()}\nerror={error}\n",
            encoding="utf-8",
        )
        raise


if __name__ == "__main__":
    sys.exit(main())
