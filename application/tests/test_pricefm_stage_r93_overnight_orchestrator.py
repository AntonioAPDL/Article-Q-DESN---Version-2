"""Focused tests for the fail-closed R93 overnight controller."""

from __future__ import annotations

import csv
import importlib.util
from pathlib import Path
import sys

import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
SCRIPT = SCRIPTS / "296_orchestrate_pricefm_stage_r93_overnight.py"


def load_script():
    spec = importlib.util.spec_from_file_location(SCRIPT.stem, SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_cpu_parser_requires_unique_one_core_assignments():
    module = load_script()
    assert module.parse_cpu_list("20,22-25") == [20, 22, 23, 24, 25]
    with pytest.raises(ValueError, match="unique"):
        module.parse_cpu_list("20,20")
    with pytest.raises(ValueError, match="nonnegative"):
        module.parse_cpu_list("-1")


def test_grid_counts_uses_experiment_rows_only(tmp_path):
    module = load_script()
    path = tmp_path / "launch_status.csv"
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["id", "kind", "status"])
        writer.writeheader()
        writer.writerows([
            {"id": "data", "kind": "data_preparation", "status": "completed"},
            {"id": "a", "kind": "experiment", "status": "completed"},
            {"id": "b", "kind": "experiment", "status": "skipped_complete"},
            {"id": "c", "kind": "experiment", "status": "failed"},
        ])
    assert module.Controller.grid_counts(tmp_path) == {
        "completed": 1, "skipped_complete": 1, "failed": 1,
    }


def test_controller_contract_stops_before_test_and_downstream_mutations():
    text = SCRIPT.read_text()
    assert 'APPROVAL_TOKEN = "RUN_PRICEFM_R93_VALIDATION_LADDER"' in text
    assert '"status": "completed_waiting_for_test_audit_authorization"' in text
    assert '"phase": "stopped_before_test_audit"' in text
    assert '"test_opened": False' in text
    assert '"registry_mutated": False' in text
    assert '"article_mutated": False' in text
    assert '"joint_or_mcmc_authorized": False' in text
    assert "wait_for_resources" in text
    assert "quarantine_partial" in text
    assert '"OMP_NUM_THREADS": "1"' in text
