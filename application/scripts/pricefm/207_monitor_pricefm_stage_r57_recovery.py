#!/usr/bin/env python3
"""Monitor Stage-R57 and repair terminal cases without launching or refitting."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

import pandas as pd

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
GRID = DATA / "experiment_grids/pricefm_stage_r57_joint_vb_20260824"
AUTHORITY = DATA / "authoritative/pricefm_stage_r57_joint_authority_freeze_20260824"
REPAIR = DATA / "authoritative/pricefm_stage_r57_joint_vb_postfit_repair_20260824"
AUDIT = DATA / "authoritative/pricefm_stage_r58_joint_recovery_audit_20260824"
OUTPUT = DATA / "authoritative/pricefm_stage_r57_r58_recovery_monitor_20260824"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=GRID / "launch_manifest.csv")
    p.add_argument(
        "--authority", type=Path,
        default=AUTHORITY / "pricefm_stage_r57_joint_case_authority.csv",
    )
    p.add_argument("--repair-output-dir", type=Path, default=REPAIR)
    p.add_argument("--audit-output-dir", type=Path, default=AUDIT)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--python-bin", type=Path, default=Path(sys.executable))
    p.add_argument(
        "--repair-script", type=Path,
        default=Path(__file__).with_name("205_repair_pricefm_stage_r57_joint_vb_postfit.py"),
    )
    p.add_argument(
        "--audit-script", type=Path,
        default=Path(__file__).with_name("206_audit_pricefm_stage_r58_joint_recovery.py"),
    )
    p.add_argument("--expected-cases", type=int, default=114)
    p.add_argument("--repair-workers", type=int, default=2)
    p.add_argument("--poll-seconds", type=float, default=900.0)
    p.add_argument("--max-polls", type=int, default=0, help="Zero means monitor until complete")
    p.add_argument("--cleanup-heavy", type=parse_bool, default=True)
    return p


def run_json_command(command: list[str]) -> dict:
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(
            f"Command exited {result.returncode}: {' '.join(command)}\n{result.stdout}{result.stderr}"
        )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"Command did not emit one JSON object: {' '.join(command)}") from error


def append_event(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as handle:
        handle.write(json.dumps(payload, sort_keys=True) + "\n")


def commands(args: argparse.Namespace) -> tuple[list[str], list[str]]:
    repair = [
        str(args.python_bin), str(args.repair_script),
        "--manifest", str(args.manifest),
        "--output-dir", str(args.repair_output_dir),
        "--python-bin", str(args.python_bin),
        "--cleanup-heavy", str(bool(args.cleanup_heavy)).lower(),
        "--workers", str(args.repair_workers),
        "--require-original-metrics", "true",
        "--force", "false",
    ]
    audit = [
        str(args.python_bin), str(args.audit_script),
        "--authority", str(args.authority),
        "--manifest", str(args.manifest),
        "--output-dir", str(args.audit_output_dir),
        "--expected-cases", str(args.expected_cases),
        "--force", "true",
    ]
    return repair, audit


def run(args: argparse.Namespace) -> dict:
    if args.expected_cases < 1 or args.repair_workers < 1:
        raise ValueError("expected cases and repair workers must be positive")
    if args.poll_seconds < 0 or args.max_polls < 0:
        raise ValueError("poll seconds and max polls must be nonnegative")
    manifest = pd.read_csv(args.manifest)
    if len(manifest) != args.expected_cases:
        raise RuntimeError("Recovery monitor manifest does not match the expected surface")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    events = args.output_dir / "monitor_events.jsonl"
    repair_command, audit_command = commands(args)
    poll = 0
    consecutive_errors = 0
    while True:
        poll += 1
        try:
            repair = run_json_command(repair_command)
            audit = run_json_command(audit_command)
            consecutive_errors = 0
            payload = {
                "status": "monitoring" if audit.get("postfit_complete") != args.expected_cases else "completed",
                "poll": poll, "expected_cases": args.expected_cases,
                "postfit_complete": int(audit.get("postfit_complete", 0)),
                "remaining_cases": int(audit.get("remaining_cases", args.expected_cases)),
                "repair_failures": int(repair.get("repair_failures", 0)),
                "audit_status": audit.get("status", "missing"),
                "models_refit": 0, "test_opened": False,
                "mcmc_launch_authorized": False,
                "registry_mutation_authorized": False,
                "article_mutation_authorized": False,
            }
            append_event(events, payload)
            write_json(args.output_dir / "summary.json", payload)
            if (
                payload["postfit_complete"] == args.expected_cases
                and audit.get("status") == "full_surface_ready_for_scoring_contract_freeze"
            ):
                return payload
        except Exception as error:
            consecutive_errors += 1
            payload = {
                "status": "monitor_error_retrying", "poll": poll,
                "consecutive_errors": consecutive_errors, "error": str(error),
                "models_refit": 0, "test_opened": False,
            }
            append_event(events, payload)
            write_json(args.output_dir / "summary.json", payload)
            if consecutive_errors >= 3:
                raise RuntimeError("Recovery monitor stopped after three consecutive errors") from error
        if args.max_polls and poll >= args.max_polls:
            payload["status"] = "stopped_at_poll_limit"
            write_json(args.output_dir / "summary.json", payload)
            return payload
        time.sleep(args.poll_seconds)


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
