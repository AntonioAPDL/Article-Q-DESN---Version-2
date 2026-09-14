"""Contract tests for reusable region-frozen PriceFM workflows."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/pricefm_region_frozen_contract.py"


def load_script():
    spec = importlib.util.spec_from_file_location(SCRIPT.stem, SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_firewall_requires_both_explicit_false_fields():
    module = load_script()
    module.validate_pretest_firewall(
        {"test_opened": False, "test_access_authorized": False}, label="fixture"
    )
    for payload in (
        {"test_opened": False},
        {"test_access_authorized": False},
        {"test_opened": True, "test_access_authorized": False},
        {"test_opened": False, "test_access_authorized": True},
    ):
        with pytest.raises(RuntimeError, match="firewall"):
            module.validate_pretest_firewall(payload, label="fixture")


def test_content_task_id_is_stable_and_identity_sensitive():
    module = load_script()
    left = module.content_task_id("R94 SE_2", {"tau": 0.5, "fold": 1})
    reordered = module.content_task_id("R94 SE_2", {"fold": 1, "tau": 0.5})
    different = module.content_task_id("R94 SE_2", {"fold": 2, "tau": 0.5})
    assert left == reordered
    assert left != different
    assert left.startswith("r94_se_2_")


def test_nonempty_evidence_is_quarantined_not_deleted(tmp_path):
    module = load_script()
    evidence = tmp_path / "evidence"
    evidence.mkdir()
    (evidence / "terminal.json").write_text(json.dumps({"status": "partial"}))
    prepared, quarantined = module.prepare_empty_directory(
        evidence, quarantine_root=tmp_path / "quarantine",
        reason="fixture replacement", allow_quarantine=True,
    )
    assert prepared.is_dir() and not any(prepared.iterdir())
    assert quarantined is not None
    assert json.loads((quarantined / "terminal.json").read_text())["status"] == "partial"


def test_quantile_contract_rejects_missing_or_reordered_values():
    module = load_script()
    module.validate_quantiles(module.PAPER_QUANTILES)
    with pytest.raises(RuntimeError, match="must equal"):
        module.validate_quantiles(module.PAPER_QUANTILES[:-1])
    with pytest.raises(RuntimeError, match="must equal"):
        module.validate_quantiles(tuple(reversed(module.PAPER_QUANTILES)))
