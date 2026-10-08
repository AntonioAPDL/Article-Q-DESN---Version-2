#!/usr/bin/env python3.11
"""Retire a Part 4 controller only after its active checkpoint is complete."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import signal
import time
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command_line(pid: int) -> str:
    return Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode()


def validate_controller(pid: int, pgid: int, contract_path: Path, contract_hash: str) -> None:
    if sha256(contract_path) != contract_hash:
        raise RuntimeError("Controller contract hash mismatch")
    if os.getpgid(pid) != pgid:
        raise RuntimeError("Controller process group does not match the frozen handoff")
    command = command_line(pid)
    required = (
        "413_launch_glofas_part4_joint_continuation.py",
        str(contract_path),
        contract_hash,
    )
    if not all(value in command for value in required):
        raise RuntimeError("Controller command line does not match the frozen handoff")


def terminate_group(pgid: int, timeout_seconds: int = 15) -> None:
    try:
        os.killpg(pgid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            os.killpg(pgid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.25)
    try:
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--controller-pid", type=int, required=True)
    parser.add_argument("--expected-process-group", type=int, required=True)
    parser.add_argument("--job-id", required=True)
    parser.add_argument("--controller-contract", required=True)
    parser.add_argument("--expected-contract-sha256", required=True)
    parser.add_argument("--poll-seconds", type=float, default=0.5)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()

    root = Path(args.runtime_root).resolve()
    contract_path = Path(args.controller_contract).resolve()
    validate_controller(
        args.controller_pid,
        args.expected_process_group,
        contract_path,
        args.expected_contract_sha256,
    )
    completed = root / "status" / f"{args.job_id}.completed"
    failed = root / "status" / f"{args.job_id}.failed"
    fit_path = root / "objects" / f"{args.job_id}_fit_side.rds"
    trace_path = root / "traces" / f"{args.job_id}_trace.csv"
    guard_running = root / "status" / f"{args.job_id}.checkpoint_guard_running"
    guard_terminal = root / "status" / f"{args.job_id}.checkpoint_handoff.json"
    if args.validate_only:
        print(json.dumps({
            "status": "VALID",
            "controller_pid": args.controller_pid,
            "process_group": args.expected_process_group,
            "job_id": args.job_id,
        }, indent=2, sort_keys=True))
        return

    guard_running.write_text(datetime.now(timezone.utc).isoformat() + "\n")
    while not completed.exists() and not failed.exists():
        try:
            validate_controller(
                args.controller_pid,
                args.expected_process_group,
                contract_path,
                args.expected_contract_sha256,
            )
        except (FileNotFoundError, ProcessLookupError) as error:
            guard_running.unlink(missing_ok=True)
            raise RuntimeError("Controller disappeared before checkpoint completion") from error
        time.sleep(args.poll_seconds)

    checkpoint_complete = completed.exists()
    if checkpoint_complete:
        fit_path.resolve(strict=True)
        trace_path.resolve(strict=True)
    time.sleep(2.0)
    terminate_group(args.expected_process_group)

    interrupted = []
    for marker in sorted((root / "status").glob("part4_joint_exal_continuation_b*.running")):
        if marker.name == f"{args.job_id}.running":
            continue
        interrupted.append(marker.name.removesuffix(".running"))
        marker.unlink(missing_ok=True)
        marker.with_suffix(".interrupted_by_checkpoint_guard").write_text(
            "reason=old_controller_retired_after_valid_checkpoint\n"
        )
    (root / "status/part4_joint_exal_controller.running").unlink(missing_ok=True)
    (root / "status/part4_joint_exal_controller.superseded_after_checkpoint").write_text(
        f"checkpoint_job_id={args.job_id}\n"
    )
    payload = {
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "checkpoint_completed": checkpoint_complete,
        "checkpoint_job_id": args.job_id,
        "controller_pid": args.controller_pid,
        "retired_process_group": args.expected_process_group,
        "interrupted_unpromotable_jobs": interrupted,
        "fit_path": str(fit_path) if checkpoint_complete else None,
        "fit_sha256": sha256(fit_path) if checkpoint_complete else None,
        "trace_path": str(trace_path) if checkpoint_complete else None,
        "trace_sha256": sha256(trace_path) if checkpoint_complete else None,
        "ready_for_corrected_resume": checkpoint_complete,
    }
    guard_running.unlink(missing_ok=True)
    guard_terminal.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print(json.dumps(payload, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
