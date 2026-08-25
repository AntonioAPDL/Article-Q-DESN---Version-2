#!/usr/bin/env python3

import argparse
import csv
import datetime as dt
import hashlib
import os
import pathlib
import shutil
import subprocess
import time


def parse_args():
    parser = argparse.ArgumentParser(
        description="Finish a GloFAS p50 structural campaign after selective replay."
    )
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--poll-seconds", type=int, default=120)
    parser.add_argument("--timeout-hours", type=float, default=72.0)
    return parser.parse_args()


def timestamp():
    return dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="seconds")


def atomic_csv(path, row):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(row))
        writer.writeheader()
        writer.writerow(row)
    os.replace(str(temporary), str(path))


def read_single_row(path):
    path = pathlib.Path(path)
    if not path.is_file():
        return {}
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 1:
        raise ValueError(f"Expected exactly one row in {path}, found {len(rows)}")
    return rows[0]


def canonical_bool(value):
    normalized = str(value).strip().lower()
    if normalized in {"1", "true", "t", "yes", "y"}:
        return True
    if normalized in {"0", "false", "f", "no", "n", ""}:
        return False
    raise ValueError(f"Invalid boolean value: {value}")


def sha256_file(path):
    digest = hashlib.sha256()
    with pathlib.Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_owned_output_root(output_root, repo_root):
    output_root = pathlib.Path(output_root).resolve()
    owned_root = (pathlib.Path(repo_root) / "local_trackers" / "runtime_configs").resolve()
    try:
        output_root.relative_to(owned_root)
    except ValueError as exc:
        raise ValueError(
            f"Output root is outside the task-owned runtime tree: {output_root}"
        ) from exc
    required = ["runtime_manifest.csv", "screening_space_snapshot.yaml"]
    missing = [name for name in required if not (output_root / name).is_file()]
    if missing:
        raise ValueError(
            "Output root lacks required campaign evidence: " + ", ".join(missing)
        )
    return output_root


def run_logged(command, repo_root, log_path):
    with pathlib.Path(log_path).open("a", encoding="utf-8") as handle:
        handle.write(f"[{timestamp()}] {' '.join(command)}\n")
        handle.flush()
        subprocess.run(
            command,
            cwd=str(repo_root),
            stdout=handle,
            stderr=subprocess.STDOUT,
            check=True,
        )


def closeout_action(decision):
    if canonical_bool(decision.get("cold_confirmation_warranted", "false")):
        return "await_cold_confirmation_without_cleanup"
    if canonical_bool(decision.get("full7_warranted", "false")):
        return "await_full7_decision_without_cleanup"
    if canonical_bool(decision.get("article_update_warranted", "false")):
        return "await_article_integration_without_cleanup"
    return "strict_closeout_and_cleanup_nonprotected"


def main():
    args = parse_args()
    if args.poll_seconds < 5:
        raise ValueError("--poll-seconds must be at least 5")
    if args.timeout_hours <= 0:
        raise ValueError("--timeout-hours must be positive")

    repo_root = pathlib.Path(__file__).resolve().parents[2]
    output_root = require_owned_output_root(args.output_root, repo_root)
    resume_status_path = output_root / "resume_orchestration_status.csv"
    status_path = output_root / "post_resume_closeout_status.csv"
    log_path = output_root / "post_resume_closeout.log"
    started = time.time()
    disk_before = shutil.disk_usage(str(output_root)).free
    atomic_csv(status_path, {
        "status": "waiting_for_resume",
        "timestamp": timestamp(),
        "action": "wait",
        "disk_free_gb_before": f"{disk_before / (1024.0 ** 3):.6f}",
        "disk_free_gb_after": "",
        "finalization_sha256": "",
        "mechanism_decision_sha256": "",
        "message": "",
    })

    try:
        while True:
            resume = read_single_row(resume_status_path)
            status = resume.get("status", "")
            if status == "completed":
                break
            if status == "failed":
                raise RuntimeError(
                    "Selective replay failed; forensic closeout is available and cleanup remains blocked."
                )
            if (time.time() - started) / 3600.0 > args.timeout_hours:
                raise RuntimeError("Timed out waiting for selective replay to finish.")
            time.sleep(args.poll_seconds)

        atomic_csv(status_path, {
            "status": "auditing",
            "timestamp": timestamp(),
            "action": "strict_finalize_then_audit",
            "disk_free_gb_before": f"{disk_before / (1024.0 ** 3):.6f}",
            "disk_free_gb_after": "",
            "finalization_sha256": "",
            "mechanism_decision_sha256": "",
            "message": "",
        })
        output_arg = str(output_root)
        run_logged([
            "Rscript", "application/scripts/glofas_constrained_median_screen_finalize.R",
            "--output_root", output_arg, "--mode", "strict", "--cleanup", "false",
        ], repo_root, log_path)
        run_logged([
            "Rscript", "application/scripts/glofas_reservoir_preflight_policy_audit.R",
            "--output_root", output_arg,
        ], repo_root, log_path)
        run_logged([
            "Rscript", "application/scripts/glofas_p50_structural_closeout_audit.R",
            "--output_root", output_arg,
        ], repo_root, log_path)

        decision_path = (
            output_root / "structural_closeout_audit" / "tables" / "mechanism_decision.csv"
        )
        decision = read_single_row(decision_path)
        action = closeout_action(decision)
        if action == "strict_closeout_and_cleanup_nonprotected":
            run_logged([
                "Rscript", "application/scripts/glofas_constrained_median_screen_finalize.R",
                "--output_root", output_arg, "--mode", "strict", "--cleanup", "true",
            ], repo_root, log_path)

        finalization_path = output_root / "finalization_status.csv"
        disk_after = shutil.disk_usage(str(output_root)).free
        atomic_csv(status_path, {
            "status": "completed",
            "timestamp": timestamp(),
            "action": action,
            "disk_free_gb_before": f"{disk_before / (1024.0 ** 3):.6f}",
            "disk_free_gb_after": f"{disk_after / (1024.0 ** 3):.6f}",
            "finalization_sha256": sha256_file(finalization_path),
            "mechanism_decision_sha256": sha256_file(decision_path),
            "message": "No full7 fit or article update was launched automatically.",
        })
    except Exception as exc:
        disk_after = shutil.disk_usage(str(output_root)).free
        atomic_csv(status_path, {
            "status": "failed",
            "timestamp": timestamp(),
            "action": "manual_review_required_no_cleanup",
            "disk_free_gb_before": f"{disk_before / (1024.0 ** 3):.6f}",
            "disk_free_gb_after": f"{disk_after / (1024.0 ** 3):.6f}",
            "finalization_sha256": "",
            "mechanism_decision_sha256": "",
            "message": str(exc),
        })
        raise


if __name__ == "__main__":
    main()
