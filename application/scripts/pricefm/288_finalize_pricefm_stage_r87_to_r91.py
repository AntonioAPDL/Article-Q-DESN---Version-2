#!/usr/bin/env python3
"""Wait for R87 and execute the pre-registered R88-R91 closeout chain."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
from typing import Any


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R87_GRID = DATA / "experiment_grids/pricefm_stage_r87_homogeneous_exal_refit_20260904"
R90_GRID = DATA / "experiment_grids/pricefm_stage_r90_scoring_only_test_audit_20260905"
OUTPUT = DATA / "authoritative/pricefm_stage_r91_test_audit_and_promotion_20260905"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--python-bin", type=Path, default=DATA / "venv/bin/python")
    p.add_argument("--poll-seconds", type=int, default=300)
    p.add_argument("--scoring-workers", type=int, default=20)
    p.add_argument("--authorize-test-audit", action="store_true")
    return p


def atomic_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def run_command(command: list[str], cwd: Path, log_path: Path) -> None:
    with log_path.open("a") as handle:
        handle.write("COMMAND " + " ".join(command) + "\n")
        handle.flush()
        result = subprocess.run(command, cwd=cwd, stdout=handle, stderr=subprocess.STDOUT)
        handle.write(f"RETURN_CODE {result.returncode}\n")
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(command)}")


def code_head(code_root: Path) -> str:
    return subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=code_root, check=True,
        capture_output=True, text=True,
    ).stdout.strip()


def require_unchanged_head(code_root: Path, expected: str) -> None:
    observed = code_head(code_root)
    if observed != expected:
        raise RuntimeError(f"Finalizer code HEAD changed: expected {expected}, observed {observed}")


def resource_preflight(command: list[str], cwd: Path, log_path: Path) -> bool:
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    combined = (result.stdout or "") + (result.stderr or "")
    with log_path.open("a") as handle:
        handle.write("COMMAND " + " ".join(command) + "\n")
        handle.write(combined)
        handle.write(f"RETURN_CODE {result.returncode}\n")
    if result.returncode == 0:
        return True
    if ("CPUs satisfy the" in combined or "resource gate failed" in combined):
        return False
    raise RuntimeError(f"R90 scientific preflight failed: {combined.strip()}")


def wait_for_r87(
    poll_seconds: int, state_path: Path, code_root: Path, frozen_code_head: str,
) -> dict[str, Any]:
    summary_path = R87_GRID / "launch_summary.json"
    while True:
        require_unchanged_head(code_root, frozen_code_head)
        summary = json.loads(summary_path.read_text()) if summary_path.is_file() else None
        status_path = R87_GRID / "launch_status.csv"
        completed = 0
        if status_path.is_file():
            import pandas as pd
            frame = pd.read_csv(status_path)
            completed = int(frame.status.isin(("completed", "skipped_completed")).sum())
        atomic_json(state_path, {
            "status": "waiting_for_r87", "r87_completed": completed,
            "r87_remaining": 280 - completed, "r87_launch_summary": summary,
            "frozen_code_head": frozen_code_head, "test_opened": False,
        })
        if summary is not None:
            if summary.get("status") != "completed" or summary.get("completed") != 280 or summary.get("failed") != 0:
                raise RuntimeError(f"R87 ended without a clean 280/280 completion: {summary}")
            return summary
        time.sleep(poll_seconds)


def run(args: argparse.Namespace) -> dict[str, Any]:
    if not args.authorize_test_audit:
        raise RuntimeError("R88-R91 finalization requires explicit --authorize-test-audit")
    code_root = args.code_root.resolve(); python = args.python_bin.resolve()
    if not python.is_file():
        raise FileNotFoundError(python)
    frozen_code_head = code_head(code_root)
    state_path = R90_GRID / "finalizer_state.json"
    log_path = DATA / "logs/pricefm_stage_r87_to_r91_finalizer_20260905.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    atomic_json(state_path, {
        "status": "starting", "frozen_code_head": frozen_code_head, "test_opened": False,
    })
    wait_for_r87(args.poll_seconds, state_path, code_root, frozen_code_head)
    require_unchanged_head(code_root, frozen_code_head)
    stages = (
        "282_closeout_pricefm_stage_r88_repaired_exal_surface.py",
        "283_select_pricefm_stage_r89_validation_family.py",
        "284_prepare_pricefm_stage_r90_scoring_only_test_audit.py",
    )
    for stage in stages:
        require_unchanged_head(code_root, frozen_code_head)
        atomic_json(state_path, {
            "status": f"running_{stage[:3]}", "frozen_code_head": frozen_code_head,
            "test_opened": False,
        })
        run_command([
            str(python), str(code_root / "application/scripts/pricefm" / stage), "--force",
        ], code_root, log_path)

    launcher = code_root / "application/scripts/pricefm/286_launch_pricefm_stage_r90_scoring_only_test_audit.py"
    preflight = [
        str(python), str(launcher), "--code-root", str(code_root),
        "--workers", str(args.scoring_workers), "--preflight-only",
    ]
    while True:
        require_unchanged_head(code_root, frozen_code_head)
        atomic_json(state_path, {
            "status": "waiting_for_r90_resources", "frozen_code_head": frozen_code_head,
            "test_opened": False,
        })
        try:
            if resource_preflight(preflight, code_root, log_path):
                break
        except RuntimeError:
            atomic_json(state_path, {"status": "failed_r90_scientific_preflight", "test_opened": False})
            raise
        time.sleep(args.poll_seconds)
    require_unchanged_head(code_root, frozen_code_head)
    atomic_json(state_path, {
        "status": "running_r90_scoring_only_test_audit", "frozen_code_head": frozen_code_head,
        "test_opened": True,
    })
    run_command([
        str(python), str(launcher), "--code-root", str(code_root),
        "--workers", str(args.scoring_workers), "--authorize",
    ], code_root, log_path)
    require_unchanged_head(code_root, frozen_code_head)
    atomic_json(state_path, {
        "status": "running_r91_closeout", "frozen_code_head": frozen_code_head,
        "test_opened": True,
    })
    run_command([
        str(python), str(code_root / "application/scripts/pricefm/287_closeout_pricefm_stage_r91_test_audit_and_promotion.py"),
        "--force",
    ], code_root, log_path)
    summary = json.loads((OUTPUT / "summary.json").read_text())
    atomic_json(state_path, {
        "status": "completed", "frozen_code_head": frozen_code_head,
        "r91_summary": summary, "test_opened": True,
    })
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
