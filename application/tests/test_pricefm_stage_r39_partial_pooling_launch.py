"""Tests for PriceFM Stage-R39 partial-pooling launch preparation."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/164_prepare_pricefm_stage_r39_partial_pooling_launch.py"
if str(SCRIPT.parent) not in sys.path:
    sys.path.insert(0, str(SCRIPT.parent))


def load_module():
    spec = importlib.util.spec_from_file_location("stage_r39", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def source_grid():
    return {"pricefm_desn_experiment_grid": {
        "grid_id": "r36", "purpose": "old",
        "base": {"data_config": "a", "full_config": "b", "generated_root": "c", "run_root": "d"},
        "scope": {"splits": ["train", "val"]},
        "fixed": {
            "nested_validation": {"n_folds": 3},
            "qdesn_vb": {"horizon_readout": {"block_size": 24}},
            "artifact_hygiene": {"preserve_patterns": []},
        },
        "launch": {},
        "experiments": [{
            "id": "r36_aa", "stage": "r36", "target_label": "old",
            "candidate_family": "separate", "factor_changed": "old",
            "final_decision": "old", "candidate_source_final": "old",
            "nested_validation_rule": "old", "rationale": "old",
        }],
    }}


def test_build_grid_pre_registers_partial_pooling_and_quarantines_test(tmp_path):
    module = load_module()
    payload = module.build_grid(source_grid(), tmp_path, tmp_path / "grid", tmp_path / "runs", list(range(16, 27)), 11, True)
    grid = payload["pricefm_desn_experiment_grid"]
    assert grid["scope"]["splits"] == ["train", "val"]
    assert grid["fixed"]["nested_validation"]["n_folds"] == 5
    assert grid["fixed"]["nested_validation"]["practical_harm_margin_relative"] == 0.005
    pooling = grid["fixed"]["qdesn_vb"]["horizon_readout"]["partial_pooling"]
    assert pooling["weights"] == [0.0, 0.25, 0.5, 0.75, 1.0]
    assert grid["experiments"][0]["id"] == "r39_aa"


def test_cpu_parser_rejects_duplicates():
    module = load_module()
    with pytest.raises(ValueError, match="unique"):
        module.cpu_ids("1-3,3")
