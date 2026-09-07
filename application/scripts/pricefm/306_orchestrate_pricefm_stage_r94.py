#!/usr/bin/env python3
"""Run R94 repair through validation family freeze and stop before test access."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PYTHON = DATA / "venv/bin/python"
TAG = "pricefm_stage_r94_coherent_exal_refit_20260906"
GRID = DATA / "experiment_grids" / TAG
RUN_ROOT = DATA / "runs" / TAG
ADAPTER = RUN_ROOT / "r94_se2_region_frozen/adapter"
AUDIT = DATA / "authoritative/pricefm_stage_r94_exal_initialization_audit_20260906"
PREP = DATA / "authoritative/pricefm_stage_r94_coherent_exal_launch_prep_20260906"
CLOSEOUT = DATA / "authoritative/pricefm_stage_r94_validation_family_closeout_20260907"
STATE = DATA / "authoritative/pricefm_stage_r94_controller_20260907"
APPROVAL_TOKEN = "RUN_PRICEFM_R94_THROUGH_VALIDATION_FREEZE"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--code-root", type=Path, required=True)
    value.add_argument("--approval-token", required=True)
    value.add_argument("--workers", type=int, default=7)
    value.add_argument("--cpu-list", default="")
    value.add_argument("--state-dir", type=Path, default=STATE)
    value.add_argument("--resume", action="store_true")
    return value


def atomic_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f"{path.name}.tmp.{os.getpid()}")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


class Controller:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.root = args.code_root.resolve()
        self.state_dir = args.state_dir.resolve()
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.state_path = self.state_dir / "controller_state.json"
        self.log_path = self.state_dir / "controller.log"
        self.lock = (self.state_dir / "controller.lock").open("a+")
        try:
            fcntl.flock(self.lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            self.lock.close()
            raise RuntimeError("another R94 controller owns this pipeline") from error
        self.state: dict[str, Any] = {
            "stage": "R94", "controller_pid": os.getpid(), "phase": "starting",
            "test_opened": False, "test_access_authorized": False,
            "registry_mutated": False, "article_mutated": False,
        }
        atomic_json(self.state_path, self.state)

    def close(self) -> None:
        fcntl.flock(self.lock.fileno(), fcntl.LOCK_UN)
        self.lock.close()

    def phase(self, name: str, **details: Any) -> None:
        self.state.update(phase=name, **details)
        atomic_json(self.state_path, self.state)

    def command(self, label: str, command: list[str]) -> None:
        self.phase(label, command=command)
        with self.log_path.open("a") as handle:
            handle.write(f"START {label}: {' '.join(map(str, command))}\n")
            result = subprocess.run(
                list(map(str, command)), cwd=self.root, stdout=handle,
                stderr=subprocess.STDOUT, text=True,
            )
            handle.write(f"END {label}: returncode={result.returncode}\n")
        if result.returncode != 0:
            raise RuntimeError(f"R94 controller command failed: {label}")

    def run(self) -> dict[str, Any]:
        if self.args.approval_token != APPROVAL_TOKEN:
            raise RuntimeError(f"R94 controller requires --approval-token {APPROVAL_TOKEN}")
        if self.args.workers < 1 or self.args.workers > 7:
            raise RuntimeError("R94 controller requires one to seven workers")
        self.command("refresh_audit", [
            PYTHON, self.root / "application/scripts/pricefm/297_audit_pricefm_stage_r94_exal_initialization.py",
            "--require-complete", "--force",
        ])
        self.command("refresh_runtime_probe", [
            PYTHON, self.root / "application/scripts/pricefm/298_materialize_pricefm_stage_r94_exal_runtime.py",
        ])
        adapter_command = [
            PYTHON, self.root / "application/scripts/pricefm/302_materialize_pricefm_stage_r94_adapter.py",
        ]
        if ADAPTER.exists() and any(ADAPTER.iterdir()):
            adapter_command.append("--quarantine-existing")
        self.command("materialize_adapter", adapter_command)
        prep_command = [
            PYTHON, self.root / "application/scripts/pricefm/300_prepare_pricefm_stage_r94_exal_refit.py",
            "--code-root", self.root, "--adapter-dir", ADAPTER,
        ]
        if (GRID.exists() and any(GRID.iterdir())) or (PREP.exists() and any(PREP.iterdir())):
            prep_command.append("--quarantine-existing")
        self.command("prepare_tasks", prep_command)
        launch_base = [
            PYTHON, self.root / "application/scripts/pricefm/301_launch_pricefm_stage_r94_exal_refit.py",
            "--code-root", self.root, "--workers", str(self.args.workers),
        ]
        if self.args.cpu_list:
            launch_base.extend(["--cpu-list", self.args.cpu_list])
        self.command("launch_preflight", [*launch_base, "--preflight-only"])
        self.command("launch_atoms", [
            *launch_base, "--approval-token", "RUN_PRICEFM_R94_COHERENT_EXAL_REFIT",
        ])
        closeout_command = [
            PYTHON, self.root / "application/scripts/pricefm/303_closeout_pricefm_stage_r94_validation_family.py",
        ]
        if CLOSEOUT.exists() and any(CLOSEOUT.iterdir()):
            closeout_command.append("--quarantine-existing")
        self.command("validation_closeout", closeout_command)
        summary = json.loads((CLOSEOUT / "summary.json").read_text())
        if summary.get("test_opened") is not False or summary.get("test_access_authorized") is not False:
            raise RuntimeError("R94 closeout violated the test firewall")
        final = {
            "status": "completed_validation_family_frozen_stopped_before_test",
            "selected_family": summary["selected_family"],
            "selected_validation_AQL_original": summary["selected_validation_AQL_original"],
            "closeout": str(CLOSEOUT / "summary.json"),
            "test_opened": False,
            "test_access_authorized": False,
            "registry_mutated": False,
            "article_mutated": False,
            "joint_or_mcmc_authorized": False,
        }
        self.state.update(final, phase="stopped_before_allfold_and_test")
        atomic_json(self.state_path, self.state)
        return final


def main() -> int:
    controller = Controller(parser().parse_args())
    try:
        result = controller.run()
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except Exception as error:
        controller.phase("failed_closed", error=repr(error))
        raise
    finally:
        controller.close()


if __name__ == "__main__":
    raise SystemExit(main())
