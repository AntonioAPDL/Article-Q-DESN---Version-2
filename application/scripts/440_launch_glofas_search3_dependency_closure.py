#!/usr/bin/env python3.11
"""Validate the final diagnostic gate, then launch the Search III dependency DAG."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def resolve(value: str | Path) -> Path:
    path = Path(value)
    return path.resolve() if path.is_absolute() else (repo_root() / path).resolve()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def truth(value: object) -> bool:
    return str(value).strip().lower() in {"true", "1", "yes"}


def read_one(path: Path) -> dict[str, str]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 1:
        raise RuntimeError(f"Expected one row in {path}; found {len(rows)}")
    return rows[0]


def verify_frozen_readiness(runtime: Path) -> tuple[dict[str, object], dict[str, object]]:
    closure_path = runtime / "configs/search3_dependency_closure_contract.json"
    readiness_path = runtime / "configs/search3_dependency_closure_readiness.json"
    closure = json.loads(closure_path.read_text(encoding="utf-8"))
    readiness = json.loads(readiness_path.read_text(encoding="utf-8"))
    if closure.get("schema_version") != "glofas_search3_dependency_closure_v1":
        raise RuntimeError("Unexpected Search III closure contract schema")
    for row in readiness.get("artifacts", []):
        path = Path(row["path"])
        if not path.is_file() or path.stat().st_size != int(row["size_bytes"]) or sha256(path) != row["sha256"]:
            raise RuntimeError(f"Frozen Search III closure artifact changed: {path}")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo_root(), text=True).strip()
    dirty = subprocess.check_output(
        ["git", "status", "--porcelain", "--untracked-files=no"], cwd=repo_root(), text=True
    ).strip()
    if head != closure["git_head"] or dirty:
        raise RuntimeError("Search III closure source is not at its clean prepared commit")
    return closure, readiness


def classify_final_gate(closure: dict[str, object]) -> dict[str, object]:
    gate = closure["final_part1_diagnostic_gate"]
    root = Path(gate["runtime_root"])
    subprocess.run(
        [sys.executable, "application/scripts/425_check_glofas_quantile_certification_continuation.py",
         "--runtime-root", str(root)],
        cwd=repo_root(), check=True, stdout=subprocess.DEVNULL,
    )
    summary_path = root / "tables/certification_continuation_health_summary_latest.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    allowed = {"COMPLETE_AND_CERTIFIED", "COMPLETE_WITH_UNCERTIFIED_FITS"}
    if summary.get("status") not in allowed:
        raise RuntimeError(f"Final Part 1 diagnostic is not classified: {summary.get('status')}")
    if not summary.get("manifest_hash_ok") or not summary.get("all_completed_artifacts_valid"):
        raise RuntimeError("Final Part 1 diagnostic artifacts failed verification")
    if int(summary.get("completed", 0)) != 1 or int(summary.get("left", 1)) != 0 or int(summary.get("failed", 0)):
        raise RuntimeError("Final Part 1 diagnostic did not complete exactly one clean fit")
    job_id = gate["job_id"]
    execution_path = root / f"logs/{job_id}_execution_contract.csv"
    execution = read_one(execution_path)
    fit_path = Path(execution["fit_path"])
    trace_path = Path(execution["cumulative_trace_path"])
    if int(execution["cumulative_iterations"]) != 800:
        raise RuntimeError("Final Part 1 diagnostic did not reach the hard stop of 800")
    if execution["prior_source_sha256"] != execution["prior_continuation_sha256"]:
        raise RuntimeError("Final Part 1 diagnostic changed its posterior target")
    if sha256(fit_path) != execution["fit_sha256"] or sha256(trace_path) != execution["cumulative_trace_sha256"]:
        raise RuntimeError("Final Part 1 diagnostic output hash mismatch")
    certified = (root / f"status/{job_id}.certified").is_file()
    if certified != truth(execution["certified"]):
        raise RuntimeError("Final Part 1 diagnostic certificate marker is inconsistent")
    return {
        "classified_utc": datetime.now(timezone.utc).isoformat(),
        "classification": "certified" if certified else "quarantined_after_hard_stop",
        "health_status": summary["status"],
        "health_summary": str(summary_path),
        "health_summary_sha256": sha256(summary_path),
        "execution_contract": str(execution_path),
        "execution_contract_sha256": sha256(execution_path),
        "fit_sha256": execution["fit_sha256"],
        "cumulative_trace_sha256": execution["cumulative_trace_sha256"],
        "posterior_target_unchanged": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--workers", type=int, required=True)
    parser.add_argument("--cpu-pool", required=True)
    parser.add_argument("--session-prefix", required=True)
    parser.add_argument("--background", action="store_true")
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--wait-for-gate", action="store_true")
    parser.add_argument("--poll-seconds", type=int, default=300)
    parser.add_argument("--watcher-child", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    runtime = resolve(args.runtime_root)
    closure, _ = verify_frozen_readiness(runtime)
    resources = closure["resource_contract"]
    if args.workers != int(resources["workers"]) or args.cpu_pool != resources["cpu_pool"]:
        raise RuntimeError("Launch resources differ from the frozen Search III closure contract")
    if args.poll_seconds < 10:
        raise RuntimeError("Gate polling must be at least 10 seconds")
    watcher_session = f"{args.session_prefix}_gate"
    if args.wait_for_gate and not args.watcher_child:
        exists = subprocess.run(
            ["tmux", "has-session", "-t", watcher_session], capture_output=True
        ).returncode == 0
        if exists:
            raise RuntimeError(f"Gate watcher already exists: {watcher_session}")
        command = [
            sys.executable, str(Path(__file__).resolve()),
            "--runtime-root", str(runtime), "--workers", str(args.workers),
            "--cpu-pool", args.cpu_pool, "--session-prefix", args.session_prefix,
            "--poll-seconds", str(args.poll_seconds), "--wait-for-gate", "--watcher-child",
        ]
        if args.background:
            command.append("--background")
        subprocess.run(
            ["tmux", "new-session", "-d", "-s", watcher_session, shlex.join(command)],
            check=True,
        )
        print(json.dumps({
            "runtime_root": str(runtime), "watcher_session": watcher_session,
            "state": "waiting_for_final_part1_gate",
        }, indent=2, sort_keys=True))
        return 0

    while True:
        try:
            classification = classify_final_gate(closure)
            break
        except RuntimeError as error:
            if not args.wait_for_gate or "not classified: RUNNING_OR_PENDING" not in str(error):
                raise
            heartbeat = {
                "checked_utc": datetime.now(timezone.utc).isoformat(),
                "state": "waiting_for_final_part1_gate", "detail": str(error),
            }
            (runtime / "status/search3_gate_watcher_health.json").write_text(
                json.dumps(heartbeat, indent=2, sort_keys=True) + "\n", encoding="utf-8"
            )
            time.sleep(args.poll_seconds)
    audit_path = runtime / "configs/final_part1_diagnostic_admission.json"
    audit_path.write_text(json.dumps(classification, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.validate_only:
        print(json.dumps(classification, indent=2, sort_keys=True))
        return 0
    command = [
        sys.executable, "application/scripts/405_launch_glofas_post_search2_dag.py",
        "--runtime-root", str(runtime), "--workers", str(args.workers),
        "--cpu-pool", args.cpu_pool, "--session-prefix", args.session_prefix,
    ]
    if args.background:
        command.append("--background")
    subprocess.run(command, cwd=repo_root(), check=True)
    (runtime / "status/search3_gate_watcher_launched").write_text(
        datetime.now(timezone.utc).isoformat() + "\n", encoding="utf-8"
    )
    print(json.dumps({
        "runtime_root": str(runtime), "gate_classification": classification["classification"],
        "launch_state": "submitted" if args.background else "completed",
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
