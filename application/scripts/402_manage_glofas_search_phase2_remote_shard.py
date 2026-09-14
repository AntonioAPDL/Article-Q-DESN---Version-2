#!/usr/bin/env python3
"""Prepare, verify, finalize, and import a remote Search-II execution shard."""

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from datetime import datetime, timezone


INPUT_DIRS = ("configs", "model_inputs", "scoring_inputs")
OUTPUT_DIRS = (
    "forecasts", "fits", "scores", "traces", "coefficients", "warm_starts",
    "diagnostics", "status", "logs", "tables", "reports",
)
JOB_OUTPUT_PATTERNS = {
    "forecasts": ("{job}_forecast.csv",),
    "fits": ("{job}_summary.csv",),
    "scores": ("{job}_summary.csv", "{job}_detail.csv"),
    "traces": ("{job}_trace.csv",),
    "coefficients": ("{job}_top50.csv", "{job}_activity.csv"),
    "warm_starts": ("{job}_warm_start.rds",),
    "status": ("{job}.model_done", "{job}.done"),
    "logs": ("{job}.log",),
}
HOLD_TEXT = "DISTRIBUTION_HOLD_JEREZ_20260914\n"


def now_utc():
    return datetime.now(timezone.utc).isoformat()


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_csv(path):
    with Path(path).open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path, rows, fieldnames=None):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = list(rows)
    if fieldnames is None:
        if not rows:
            raise ValueError(f"Cannot infer columns for empty table: {path}")
        fieldnames = list(rows[0])
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def read_job_ids(path):
    ids = [line.strip() for line in Path(path).read_text().splitlines() if line.strip()]
    if not ids or len(ids) != len(set(ids)):
        raise RuntimeError("Job-ID file must contain a non-empty unique list")
    return ids


def ensure_empty_destination(path):
    path = Path(path)
    if path.exists() and any(path.iterdir()):
        raise RuntimeError(f"Destination exists and is non-empty: {path}")
    path.mkdir(parents=True, exist_ok=True)


def copy(path_from, path_to):
    path_to = Path(path_to)
    path_to.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path_from, path_to)


def manifest_rows(root, excluded=()):
    root = Path(root)
    excluded = {str(Path(item)) for item in excluded}
    rows = []
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        rel = str(path.relative_to(root))
        if rel in excluded:
            continue
        rows.append({"relative_path": rel, "bytes": path.stat().st_size, "sha256": sha256_file(path)})
    return rows


def rewrite_run_manifest(source, destination, destination_repo, source_root, job_count, source_host, execution_host):
    lines = Path(source).read_text().splitlines()
    replaced = False
    out = []
    for line in lines:
        if line.startswith("repo_root:"):
            out.append(f"repo_root: {destination_repo}")
            replaced = True
        else:
            out.append(line)
    if not replaced:
        raise RuntimeError("run_manifest.yaml is missing repo_root")
    out.extend([
        "distributed_execution:",
        f"  source_host: {source_host}",
        f"  execution_host: {execution_host}",
        f"  source_runtime_root: {source_root}",
        f"  execution_runtime_root: {destination}",
        f"  assigned_job_count: {job_count}",
        "  assignment_policy: disjoint_job_id_manifest",
        "  final_aggregation_host: muscat.be.ucsc.edu",
    ])
    return "\n".join(out) + "\n"


def yaml_scalar(path, key):
    prefix = f"{key}:"
    for line in Path(path).read_text().splitlines():
        if line.startswith(prefix):
            return line.split(":", 1)[1].strip().strip("'\"")
    raise RuntimeError(f"Missing {key} in {path}")


def prepare(args):
    source = Path(args.source_runtime_root).resolve()
    staging = Path(args.staging_root).resolve()
    destination = Path(args.destination_runtime_root)
    ensure_empty_destination(staging)
    for directory in INPUT_DIRS + OUTPUT_DIRS + ("control",):
        (staging / directory).mkdir(parents=True, exist_ok=True)

    full_manifest_path = source / "configs" / "job_manifest.csv"
    run_manifest = source / "configs" / "run_manifest.yaml"
    if yaml_scalar(run_manifest, "git_head") != args.expected_head:
        raise RuntimeError("Source runtime HEAD does not match --expected-head")
    full_jobs = read_csv(full_manifest_path)
    if not full_jobs or len(full_jobs) != len({row["job_id"] for row in full_jobs}):
        raise RuntimeError("Source job manifest is empty or contains duplicate job IDs")
    by_id = {row["job_id"]: row for row in full_jobs}
    selected_ids = read_job_ids(args.job_id_file)
    missing = sorted(set(selected_ids) - set(by_id))
    if missing:
        raise RuntimeError(f"Unknown selected job IDs: {missing[:5]}")

    selected = []
    for job_id in selected_ids:
        status = source / "status"
        forbidden = [status / f"{job_id}{suffix}" for suffix in (".running", ".model_done", ".done")]
        if any(path.exists() for path in forbidden):
            raise RuntimeError(f"Selected job is already active or complete: {job_id}")
        failed = status / f"{job_id}.failed"
        if failed.exists() and failed.read_text() != HOLD_TEXT:
            raise RuntimeError(f"Selected job has a real failure marker: {job_id}")
        selected.append(dict(by_id[job_id]))

    used_candidates = {row["candidate_id"] for row in selected}
    candidates = [row for row in read_csv(source / "configs" / "candidate_manifest.csv")
                  if row["candidate_id"] in used_candidates]
    write_csv(staging / "configs" / "candidate_manifest.csv", candidates)

    packet_pairs = {(row["target"], row["fold_id"]) for row in selected}
    model_registry = []
    for row in read_csv(source / "configs" / "model_packet_registry.csv"):
        if (row["target"], row["fold_id"]) not in packet_pairs:
            continue
        src = Path(row["model_packet_path"])
        if sha256_file(src) != row["model_packet_sha256"]:
            raise RuntimeError(f"Model packet hash mismatch: {src}")
        dst = staging / "model_inputs" / src.name
        copy(src, dst)
        row = dict(row)
        row["model_packet_path"] = str(destination / "model_inputs" / src.name)
        model_registry.append(row)
    write_csv(staging / "configs" / "model_packet_registry.csv", model_registry)

    scoring_registry = []
    for row in read_csv(source / "configs" / "scoring_packet_registry.csv"):
        if (row["target"], row["fold_id"]) not in packet_pairs:
            continue
        src = Path(row["scoring_packet_path"])
        if sha256_file(src) != row["scoring_packet_sha256"]:
            raise RuntimeError(f"Scoring packet hash mismatch: {src}")
        dst = staging / "scoring_inputs" / src.name
        copy(src, dst)
        row = dict(row)
        row["scoring_packet_path"] = str(destination / "scoring_inputs" / src.name)
        scoring_registry.append(row)
    write_csv(staging / "configs" / "scoring_packet_registry.csv", scoring_registry)

    packet_path = {(row["target"], row["fold_id"]): row["model_packet_path"] for row in model_registry}
    for row in selected:
        row["model_packet_path"] = packet_path[(row["target"], row["fold_id"])]
    write_csv(staging / "configs" / "job_manifest.csv", selected)

    text = rewrite_run_manifest(
        run_manifest, destination, args.destination_repo_root, source, len(selected),
        args.source_host, args.execution_host,
    )
    (staging / "configs" / "run_manifest.yaml").write_text(text)
    for name in ("git_state.txt", "session_info.txt"):
        src = source / "configs" / name
        if src.exists():
            copy(src, staging / "configs" / f"source_{name}")

    assignment = [{
        "job_id": row["job_id"], "candidate_id": row["candidate_id"],
        "target": row["target"], "fold_id": row["fold_id"],
        "memory_weight": row["memory_weight"], "execution_host": args.execution_host,
    } for row in selected]
    write_csv(staging / "control" / "execution_assignment.csv", assignment)
    metadata = {
        "created_at_utc": now_utc(), "source_host": args.source_host,
        "execution_host": args.execution_host, "source_runtime_root": str(source),
        "execution_runtime_root": str(destination), "destination_repo_root": args.destination_repo_root,
        "numerical_source_head": args.expected_head, "full_job_count": len(full_jobs),
        "assigned_job_count": len(selected), "full_job_manifest_sha256": sha256_file(full_manifest_path),
        "assignment_sha256": sha256_file(staging / "control" / "execution_assignment.csv"),
    }
    (staging / "control" / "shard_metadata.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    copy(Path(__file__).resolve(), staging / "control" / "remote_shard_manager.py")
    payload_path = staging / "control" / "payload_manifest.csv"
    rows = manifest_rows(staging, excluded=("control/payload_manifest.csv",))
    write_csv(payload_path, rows, ("relative_path", "bytes", "sha256"))
    print(json.dumps({**metadata, "payload_files": len(rows), "payload_sha256": sha256_file(payload_path)}, indent=2))


def git_output(repo, *args):
    result = subprocess.run(["git", "-C", str(repo), *args], universal_newlines=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or f"git {' '.join(args)} failed")
    return result.stdout.strip()


def verify(args):
    root = Path(args.runtime_root).resolve()
    repo = Path(args.repo_root).resolve()
    metadata = json.loads((root / "control" / "shard_metadata.json").read_text())
    expected_head = args.expected_head or metadata["numerical_source_head"]
    actual_head = git_output(repo, "rev-parse", "HEAD")
    if actual_head != expected_head:
        raise RuntimeError(f"Execution HEAD mismatch: {actual_head} != {expected_head}")
    if git_output(repo, "status", "--porcelain", "--untracked-files=normal"):
        raise RuntimeError("Execution worktree must be clean")
    upstream = git_output(repo, "rev-parse", "@{upstream}")
    if upstream != actual_head:
        raise RuntimeError(f"Execution branch is not synchronized with upstream: {actual_head} != {upstream}")

    rscript = args.expected_rscript or "Rscript"
    r_path = shutil.which(rscript)
    if r_path is None:
        raise RuntimeError(f"Required Rscript is unavailable: {rscript}")
    r_result = subprocess.run([r_path, "--version"], universal_newlines=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    r_version = r_result.stdout.strip().splitlines()[0] if r_result.stdout.strip() else ""
    if r_result.returncode or (args.expected_r_version and args.expected_r_version not in r_version):
        raise RuntimeError(f"R version mismatch: {r_path} reported {r_version}")

    payload = read_csv(root / "control" / "payload_manifest.csv")
    bad = []
    for row in payload:
        path = root / row["relative_path"]
        if not path.is_file() or path.stat().st_size != int(row["bytes"]) or sha256_file(path) != row["sha256"]:
            bad.append(row["relative_path"])
    if bad:
        raise RuntimeError(f"Payload verification failed for {len(bad)} files: {bad[:5]}")
    jobs = read_csv(root / "configs" / "job_manifest.csv")
    if args.expected_jobs is not None and len(jobs) != args.expected_jobs:
        raise RuntimeError(f"Expected {args.expected_jobs} jobs, found {len(jobs)}")
    if len(jobs) != len({row["job_id"] for row in jobs}):
        raise RuntimeError("Remote shard job IDs are not unique")
    destination = Path(metadata["execution_runtime_root"])
    for row in jobs:
        packet = Path(row["model_packet_path"])
        if destination not in packet.parents or not packet.is_file() or sha256_file(packet) != row["model_packet_sha256"]:
            raise RuntimeError(f"Relocated model packet failed: {row['job_id']}")
    status_files = [path for path in (root / "status").iterdir() if path.is_file()]
    if status_files:
        raise RuntimeError("Remote shard must have no pre-existing status markers at preflight")
    report = {
        "verified_at_utc": now_utc(), "status": "REMOTE_SHARD_PREFLIGHT_PASSED",
        "repo_head": actual_head, "job_count": len(jobs), "payload_file_count": len(payload),
        "payload_manifest_sha256": sha256_file(root / "control" / "payload_manifest.csv"),
        "rscript": r_path, "r_version": r_version,
    }
    (root / "control" / "preflight_report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, indent=2))


def finalize(args):
    root = Path(args.runtime_root).resolve()
    jobs = read_csv(root / "configs" / "job_manifest.csv")
    failed = [row["job_id"] for row in jobs if (root / "status" / f"{row['job_id']}.failed").exists()]
    running = [row["job_id"] for row in jobs if (root / "status" / f"{row['job_id']}.running").exists()]
    incomplete = [row["job_id"] for row in jobs if not (root / "status" / f"{row['job_id']}.done").exists()]
    if failed or running or incomplete:
        raise RuntimeError(f"Shard is not complete: failed={len(failed)} running={len(running)} incomplete={len(incomplete)}")
    files = set()
    for row in jobs:
        job = row["job_id"]
        required = (("forecasts", f"{job}_forecast.csv"), ("fits", f"{job}_summary.csv"),
                    ("scores", f"{job}_summary.csv"), ("scores", f"{job}_detail.csv"),
                    ("status", f"{job}.model_done"), ("status", f"{job}.done"))
        for directory, name in required:
            path = root / directory / name
            if not path.is_file():
                raise RuntimeError(f"Missing required result: {path}")
            files.add(path)
        for directory, patterns in JOB_OUTPUT_PATTERNS.items():
            for pattern in patterns:
                path = root / directory / pattern.format(job=job)
                if path.is_file():
                    files.add(path)
    rows = [{"relative_path": str(path.relative_to(root)), "bytes": path.stat().st_size,
             "sha256": sha256_file(path)} for path in sorted(files)]
    manifest = root / "control" / "result_manifest.csv"
    write_csv(manifest, rows, ("relative_path", "bytes", "sha256"))
    summary = {
        "finalized_at_utc": now_utc(), "status": "REMOTE_SHARD_READY_FOR_IMPORT",
        "job_count": len(jobs), "result_file_count": len(rows),
        "result_bytes": sum(int(row["bytes"]) for row in rows),
        "result_manifest_sha256": sha256_file(manifest),
    }
    (root / "control" / "result_summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, indent=2))


def import_results(args):
    shard = Path(args.shard_runtime_root).resolve()
    central = Path(args.central_runtime_root).resolve()
    rows = read_csv(shard / "control" / "result_manifest.csv")
    result_summary = json.loads((shard / "control" / "result_summary.json").read_text())
    if sha256_file(shard / "control" / "result_manifest.csv") != result_summary["result_manifest_sha256"]:
        raise RuntimeError("Remote result-manifest hash does not match its sealed summary")
    for row in rows:
        src = shard / row["relative_path"]
        if not src.is_file() or src.stat().st_size != int(row["bytes"]) or sha256_file(src) != row["sha256"]:
            raise RuntimeError(f"Remote result verification failed: {row['relative_path']}")
    jobs = read_csv(shard / "configs" / "job_manifest.csv")
    selected = {row["job_id"] for row in jobs}
    for job in selected:
        for suffix in (".running", ".model_done", ".done"):
            if (central / "status" / f"{job}{suffix}").exists():
                raise RuntimeError(f"Central runtime already owns selected job: {job}{suffix}")
        failed = central / "status" / f"{job}.failed"
        if failed.exists() and failed.read_text() != HOLD_TEXT:
            raise RuntimeError(f"Central runtime has a real failure for selected job: {job}")
    for job in selected:
        failed = central / "status" / f"{job}.failed"
        if failed.exists() and failed.read_text() == HOLD_TEXT:
            failed.unlink()
    for row in rows:
        src = shard / row["relative_path"]
        dst = central / row["relative_path"]
        if dst.exists():
            raise RuntimeError(f"Refusing to overwrite central result: {dst}")
        copy(src, dst)
    audit = central / "reports" / "remote_shards" / shard.name
    audit.mkdir(parents=True, exist_ok=False)
    for name in ("shard_metadata.json", "payload_manifest.csv", "preflight_report.json",
                 "result_manifest.csv", "result_summary.json", "execution_assignment.csv"):
        src = shard / "control" / name
        if src.exists():
            copy(src, audit / name)
    summary = {"imported_at_utc": now_utc(), "status": "REMOTE_SHARD_IMPORTED",
               "job_count": len(selected), "result_file_count": len(rows)}
    (audit / "import_summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, indent=2))


def parser():
    top = argparse.ArgumentParser()
    sub = top.add_subparsers(dest="command")
    p = sub.add_parser("prepare")
    p.add_argument("--source-runtime-root", required=True)
    p.add_argument("--staging-root", required=True)
    p.add_argument("--destination-runtime-root", required=True)
    p.add_argument("--destination-repo-root", required=True)
    p.add_argument("--job-id-file", required=True)
    p.add_argument("--expected-head", required=True)
    p.add_argument("--source-host", default="muscat.be.ucsc.edu")
    p.add_argument("--execution-host", default="jerez.be.ucsc.edu")
    p.set_defaults(function=prepare)
    p = sub.add_parser("verify")
    p.add_argument("--runtime-root", required=True)
    p.add_argument("--repo-root", required=True)
    p.add_argument("--expected-head", default="")
    p.add_argument("--expected-jobs", type=int)
    p.add_argument("--expected-rscript", default="")
    p.add_argument("--expected-r-version", default="")
    p.set_defaults(function=verify)
    p = sub.add_parser("finalize")
    p.add_argument("--runtime-root", required=True)
    p.set_defaults(function=finalize)
    p = sub.add_parser("import-results")
    p.add_argument("--shard-runtime-root", required=True)
    p.add_argument("--central-runtime-root", required=True)
    p.set_defaults(function=import_results)
    return top


def main():
    command_parser = parser()
    args = command_parser.parse_args()
    if not getattr(args, "command", None):
        command_parser.error("a command is required")
    args.function(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
