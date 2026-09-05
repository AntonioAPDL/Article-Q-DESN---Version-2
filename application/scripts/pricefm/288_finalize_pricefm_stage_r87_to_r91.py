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
R88_OUTPUT = DATA / "authoritative/pricefm_stage_r88_repaired_exal_surface_closeout_20260905"
R89_OUTPUT = DATA / "authoritative/pricefm_stage_r89_validation_family_selection_20260905"
R90_PREP = DATA / "authoritative/pricefm_stage_r90_scoring_only_test_prep_20260905"
OUTPUT = DATA / "authoritative/pricefm_stage_r91_test_audit_and_promotion_20260905"
RECOVERY_LOG = DATA / "logs/pricefm_stage_r87_to_r91_finalizer_recovery_20260905.log"
EXPECTED_PYTHON_ENVIRONMENT = {
    "python": "3.11.13",
    "numpy": "2.4.6",
    "pandas": "3.0.3",
    "scikit_learn": "1.8.0",
    "pyyaml": "6.0.3",
    "joblib": "1.5.3",
}


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


def python_executable(path: Path) -> Path:
    """Return an absolute executable path without dereferencing a venv symlink."""
    expanded = path.expanduser()
    return expanded.absolute() if not expanded.is_absolute() else expanded


def inspect_python_environment(python: Path) -> dict[str, str]:
    probe = (
        "import json,platform,sys,joblib,numpy,pandas,sklearn,yaml;"
        "print(json.dumps({'executable':sys.executable,'prefix':sys.prefix,"
        "'python':platform.python_version(),'numpy':numpy.__version__,"
        "'pandas':pandas.__version__,'scikit_learn':sklearn.__version__,"
        "'pyyaml':yaml.__version__,'joblib':joblib.__version__},sort_keys=True))"
    )
    result = subprocess.run(
        [str(python), "-c", probe], capture_output=True, text=True,
    )
    if result.returncode:
        raise RuntimeError(f"PriceFM Python environment probe failed: {result.stderr.strip()}")
    observed = json.loads(result.stdout.strip())
    mismatches = {
        name: {"expected": expected, "observed": observed.get(name)}
        for name, expected in EXPECTED_PYTHON_ENVIRONMENT.items()
        if observed.get(name) != expected
    }
    expected_prefix = str(python.parent.parent.absolute())
    if observed.get("prefix") != expected_prefix:
        mismatches["prefix"] = {
            "expected": expected_prefix, "observed": observed.get("prefix"),
        }
    if mismatches:
        raise RuntimeError(f"PriceFM Python environment mismatch: {mismatches}")
    return observed


def require_summary(path: Path, expected: dict[str, Any]) -> dict[str, Any]:
    observed = json.loads(path.read_text())
    mismatches = {
        name: {"expected": value, "observed": observed.get(name)}
        for name, value in expected.items() if observed.get(name) != value
    }
    if mismatches:
        raise RuntimeError(f"Unexpected materialized boundary in {path}: {mismatches}")
    return observed


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
    code_root = args.code_root.resolve(); python = python_executable(args.python_bin)
    if not python.is_file():
        raise FileNotFoundError(python)
    frozen_code_head = code_head(code_root)
    state_path = R90_GRID / "finalizer_state.json"
    log_path = RECOVERY_LOG
    log_path.parent.mkdir(parents=True, exist_ok=True)
    current_stage = "environment_preflight"
    test_opened = False
    environment: dict[str, str] | None = None
    try:
        environment = inspect_python_environment(python)
        atomic_json(state_path, {
            "status": "starting", "frozen_code_head": frozen_code_head,
            "python_environment": environment, "test_opened": False,
        })
        current_stage = "r87_completion_gate"
        wait_for_r87(args.poll_seconds, state_path, code_root, frozen_code_head)
        require_unchanged_head(code_root, frozen_code_head)
        stages = (
            ("r88", "282_closeout_pricefm_stage_r88_repaired_exal_surface.py"),
            ("r89", "283_select_pricefm_stage_r89_validation_family.py"),
            ("r90_prep", "284_prepare_pricefm_stage_r90_scoring_only_test_audit.py"),
        )
        for current_stage, stage in stages:
            require_unchanged_head(code_root, frozen_code_head)
            atomic_json(state_path, {
                "status": f"running_{current_stage}", "frozen_code_head": frozen_code_head,
                "python_environment": environment, "test_opened": False,
            })
            run_command([
                str(python), str(code_root / "application/scripts/pricefm" / stage), "--force",
            ], code_root, log_path)
            if current_stage == "r88":
                require_summary(R88_OUTPUT / "summary.json", {
                    "atoms": 294, "cases": 42, "eligible_exal_cases": 32,
                    "fallback_al_cases": 10, "test_opened": False,
                })
            elif current_stage == "r89":
                require_summary(R89_OUTPUT / "summary.json", {
                    "cases": 56, "selected_atoms": 392, "exal_selected_cases": 32,
                    "al_selected_cases": 24, "test_opened": False,
                })
            else:
                require_summary(R90_PREP / "summary.json", {
                    "cases": 56, "selected_atoms": 392, "model_refits_authorized": 0,
                    "test_opened": False,
                })

        launcher = code_root / "application/scripts/pricefm/286_launch_pricefm_stage_r90_scoring_only_test_audit.py"
        preflight = [
            str(python), str(launcher), "--code-root", str(code_root),
            "--workers", str(args.scoring_workers), "--preflight-only",
        ]
        current_stage = "r90_resource_preflight"
        while True:
            require_unchanged_head(code_root, frozen_code_head)
            atomic_json(state_path, {
                "status": "waiting_for_r90_resources", "frozen_code_head": frozen_code_head,
                "python_environment": environment, "test_opened": False,
            })
            if resource_preflight(preflight, code_root, log_path):
                break
            time.sleep(args.poll_seconds)

        current_stage = "r90_scoring_only_test_audit"
        require_unchanged_head(code_root, frozen_code_head)
        atomic_json(state_path, {
            "status": "running_r90_scoring_only_test_audit", "frozen_code_head": frozen_code_head,
            "python_environment": environment, "test_opened": True,
        })
        test_opened = True
        run_command([
            str(python), str(launcher), "--code-root", str(code_root),
            "--workers", str(args.scoring_workers), "--authorize",
        ], code_root, log_path)

        current_stage = "r91_closeout"
        require_unchanged_head(code_root, frozen_code_head)
        atomic_json(state_path, {
            "status": "running_r91_closeout", "frozen_code_head": frozen_code_head,
            "python_environment": environment, "test_opened": True,
        })
        run_command([
            str(python), str(code_root / "application/scripts/pricefm/287_closeout_pricefm_stage_r91_test_audit_and_promotion.py"),
            "--force",
        ], code_root, log_path)
        summary = json.loads((OUTPUT / "summary.json").read_text())
        atomic_json(state_path, {
            "status": "completed", "frozen_code_head": frozen_code_head,
            "python_environment": environment, "r91_summary": summary, "test_opened": True,
        })
        return summary
    except Exception as error:
        atomic_json(state_path, {
            "status": "failed", "failed_stage": current_stage,
            "error_type": type(error).__name__, "error": str(error),
            "frozen_code_head": frozen_code_head, "python_environment": environment,
            "test_opened": test_opened,
        })
        raise


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
