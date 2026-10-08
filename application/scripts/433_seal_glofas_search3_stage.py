#!/usr/bin/env python3
"""Validate and hash a completed Search III Ridge stage without changing it."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time


RECOVERY_ALLOWED_PATHS = {
    "application/R/glofas_search3_runtime_contract.R",
    "application/scripts/427_prepare_glofas_search3.R",
    "application/scripts/431_check_glofas_search3.R",
    "application/scripts/432_run_glofas_search3_campaign.py",
    "application/scripts/433_seal_glofas_search3_stage.py",
    "application/tests/run_tests.R",
    "application/tests/test_glofas_search3_runtime_contract.R",
    "application/tests/test_glofas_search3_scheduler.py",
    "application/tests/test_glofas_search3_stage_seal.py",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def parse_key_value(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args], text=True, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout.strip()


def validate_source_transition(repo: Path, from_head: str) -> dict[str, str]:
    status = git(repo, "status", "--porcelain", "--untracked-files=normal")
    if status:
        raise RuntimeError("Source transition requires a clean worktree")
    to_head = git(repo, "rev-parse", "HEAD")
    divergence = git(repo, "rev-list", "--left-right", "--count", "@{upstream}...HEAD").split()
    if divergence != ["0", "0"]:
        raise RuntimeError(f"Source transition requires a synchronized branch: {divergence}")
    changed = sorted(filter(None, git(repo, "diff", "--name-only", f"{from_head}..{to_head}").splitlines()))
    unexpected = sorted(set(changed) - RECOVERY_ALLOWED_PATHS)
    if unexpected:
        raise RuntimeError(f"Recovery commit changes non-orchestration paths: {unexpected}")
    if not changed:
        raise RuntimeError("Recovery source transition has no changed paths")
    changed_text = ";".join(changed)
    return {
        "from_head": from_head,
        "to_head": to_head,
        "classification": "orchestration_only",
        "changed_paths": changed_text,
        "changed_paths_sha256": sha256_text("\n".join(changed)),
    }


def expected_paths(stage: Path, job_id: str) -> dict[str, Path]:
    return {
        "forecast": stage / "forecasts" / f"{job_id}_forecast.csv",
        "fit_summary": stage / "fits" / f"{job_id}_summary.csv",
        "score_summary": stage / "scores" / f"{job_id}_summary.csv",
        "score_detail": stage / "scores" / f"{job_id}_detail.csv",
        "warm_start": stage / "warm_starts" / f"{job_id}_warm_start.rds",
        "model_done": stage / "status" / f"{job_id}.model_done",
        "done": stage / "status" / f"{job_id}.done",
        "log": stage / "logs" / f"{job_id}.log",
        "coefficient_top50": stage / "coefficients" / f"{job_id}_top50.csv",
        "coefficient_activity": stage / "coefficients" / f"{job_id}_activity.csv",
    }


def validate_stage(stage: Path, expected_jobs: int) -> dict[str, object]:
    manifest_path = stage / "configs" / "job_manifest.csv"
    jobs = read_csv(manifest_path)
    if len(jobs) != expected_jobs:
        raise RuntimeError(f"Expected {expected_jobs} jobs, found {len(jobs)}")
    ids = [row["job_id"] for row in jobs]
    if len(set(ids)) != len(ids):
        raise RuntimeError("Duplicate Search III job IDs")
    key_fields = ("target", "candidate_id", "fold_id")
    keys = [tuple(row[field] for field in key_fields) for row in jobs]
    if len(set(keys)) != len(keys):
        raise RuntimeError("Duplicate Search III target/candidate/fold keys")
    if set(row.get("method") for row in jobs) != {"ridge"}:
        raise RuntimeError("Ridge stage seal encountered a non-Ridge job")

    candidate_counts: dict[str, set[str]] = {}
    fold_counts: dict[str, set[str]] = {}
    for row in jobs:
        candidate_counts.setdefault(row["target"], set()).add(row["candidate_id"])
        fold_counts.setdefault(row["target"], set()).add(row["fold_id"])
    if {key: len(value) for key, value in candidate_counts.items()} != {"reference": 40, "discrepancy": 40}:
        raise RuntimeError(f"Unexpected candidate coverage: {candidate_counts}")
    if any(len(value) != 12 for value in fold_counts.values()):
        raise RuntimeError(f"Unexpected fold coverage: {fold_counts}")

    missing: list[str] = []
    bad: list[str] = []
    for row in jobs:
        job_id = row["job_id"]
        paths = expected_paths(stage, job_id)
        for role, path in paths.items():
            if not path.is_file():
                missing.append(f"{job_id}:{role}")
        if any(not path.is_file() for path in paths.values()):
            continue
        fit = read_csv(paths["fit_summary"])
        scores = read_csv(paths["score_summary"])
        if not fit or {item.get("job_id") for item in fit} != {job_id}:
            bad.append(f"{job_id}:fit_job_id")
        if {item.get("job_id") for item in scores} != {job_id}:
            bad.append(f"{job_id}:score_job_id")
        if {item.get("score_window") for item in scores} != {"primary_28", "secondary_30"}:
            bad.append(f"{job_id}:score_windows")
        done = parse_key_value(paths["done"])
        if done.get("score_sha256") != sha256(paths["score_summary"]):
            bad.append(f"{job_id}:score_hash")
        model_done = parse_key_value(paths["model_done"])
        if model_done.get("forecast_sha256") != sha256(paths["forecast"]):
            bad.append(f"{job_id}:forecast_hash")
    if missing or bad:
        raise RuntimeError(f"Stage validation failed: missing={missing[:10]} bad={bad[:10]}")
    failed = list((stage / "status").glob("*.failed"))
    running = list((stage / "status").glob("*.running"))
    if failed or running:
        raise RuntimeError(f"Stage has failed/running markers: {len(failed)}/{len(running)}")
    return {
        "jobs": len(jobs),
        "targets": {key: len(value) for key, value in candidate_counts.items()},
        "folds_per_target": {key: len(value) for key, value in fold_counts.items()},
        "done": len(list((stage / "status").glob("*.done"))),
        "model_done": len(list((stage / "status").glob("*.model_done"))),
        "failed": len(failed),
        "running": len(running),
    }


def inventory(stage: Path) -> list[dict[str, object]]:
    rows = []
    for path in sorted(item for item in stage.rglob("*") if item.is_file()):
        if "tables" in path.relative_to(stage).parts or "reports" in path.relative_to(stage).parts:
            continue
        rows.append({
            "relative_path": str(path.relative_to(stage)),
            "size_bytes": path.stat().st_size,
            "sha256": sha256(path),
        })
    return rows


def atomic_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", newline="", dir=path.parent, delete=False) as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader(); writer.writerows(rows)
        tmp = Path(handle.name)
    tmp.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--campaign-root", required=True)
    parser.add_argument("--stage", default="ridge_a")
    parser.add_argument("--expected-jobs", type=int, default=960)
    parser.add_argument("--from-head", required=True)
    parser.add_argument("--seal-label", default="ridge_a_preaggregation_seal_20260924")
    parser.add_argument("--write-source-transition", action="store_true")
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[2]
    campaign = Path(args.campaign_root).resolve()
    stage = campaign / "stages" / args.stage
    transition = validate_source_transition(repo, args.from_head)
    health = validate_stage(stage, args.expected_jobs)
    files = inventory(stage)

    seal_root = campaign / "provenance" / args.seal_label
    if seal_root.exists() and any(seal_root.iterdir()):
        raise RuntimeError(f"Seal destination already exists and is nonempty: {seal_root}")
    seal_root.mkdir(parents=True, exist_ok=True)
    manifest = seal_root / "artifact_manifest.csv"
    atomic_csv(manifest, files, ["relative_path", "size_bytes", "sha256"])
    summary = {
        "created_at": time.strftime("%Y-%m-%d %H:%M:%S %Z"),
        "classification": "complete_scientific_stage_pending_aggregation",
        "stage": args.stage,
        "stage_root": str(stage),
        "health": health,
        "artifact_count": len(files),
        "artifact_bytes": sum(int(row["size_bytes"]) for row in files),
        "artifact_manifest": str(manifest),
        "artifact_manifest_sha256": sha256(manifest),
        "source_transition": transition,
    }
    (seal_root / "seal_summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    (seal_root / "README.md").write_text(
        "# Search III Ridge-A Preaggregation Seal\n\n"
        f"Jobs: {health['jobs']}/{args.expected_jobs}; failed: {health['failed']}; running: {health['running']}.\n\n"
        f"Artifacts: {len(files)}; bytes: {summary['artifact_bytes']}.\n\n"
        f"Manifest SHA256: `{summary['artifact_manifest_sha256']}`.\n\n"
        "This seal covers immutable preaggregation evidence. Derived tables are intentionally excluded.\n"
    )
    if args.write_source_transition:
        transition_path = campaign / "configs" / "source_transition_registry.csv"
        if transition_path.exists():
            existing = read_csv(transition_path)
            if existing != [transition]:
                raise RuntimeError("Existing source transition differs from the validated transition")
        else:
            atomic_csv(transition_path, [transition], list(transition))
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
