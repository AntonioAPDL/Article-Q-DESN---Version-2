"""Tests for the Stage-ZC graph-design diagnostic planner."""

from pathlib import Path
import importlib.util
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application" / "scripts" / "pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


def load_script(name):
    path = SCRIPT_DIR / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


stage_zc = load_script("91_diagnose_pricefm_stage_zc_graph_design.py")


def test_stage_zc_decision_recommends_revised_contract_after_direct_failure():
    block_norms = pd.DataFrame([
        {
            "split": "train",
            "input_block": "lag",
            "source_role": "target",
            "origin_norm_rms": 10.0,
        },
        {
            "split": "train",
            "input_block": "lag",
            "source_role": "neighbor",
            "origin_norm_rms": 18.0,
        },
        {
            "split": "train",
            "input_block": "lead",
            "source_role": "target",
            "origin_norm_rms": 8.0,
        },
        {
            "split": "train",
            "input_block": "lead",
            "source_role": "neighbor",
            "origin_norm_rms": 15.0,
        },
    ])
    correlations = pd.DataFrame([
        {
            "split": "train",
            "input_block": "lag",
            "source_feature": "price",
            "corr_same_laglead_flat": 0.4,
        }
    ])
    model_decomp = pd.DataFrame([
        {
            "comparison": "stage_zb_qdesn_al_vs_current_registry",
            "delta_AQL": 1.7,
        },
        {
            "comparison": "stage_zb_qdesn_al_vs_pricefm",
            "delta_AQL": 2.4,
        },
    ])

    out = stage_zc.decision_summary(pd.DataFrame(), block_norms, correlations, model_decomp)

    assert out["direct_recipe_promotable"] is False
    assert out["diagnostic_supports_revised_graph_contract"] is True
    assert out["recommended_next_contract"] == "graph_neighbor_spread_summary"


def test_stage_zc_health_detects_retained_binary_or_matrix_artifacts(tmp_path):
    cell = tmp_path / "cell"
    (cell / "adapter").mkdir(parents=True)
    (cell / "adapter" / "X_train.csv").write_text("1,2\n")
    (cell / "model").mkdir()
    (cell / "model" / "fit.rds").write_bytes(b"not really an rds")

    health = stage_zc.health_rows(cell, tmp_path / "out")

    assert bool(health["diagnostic_only"].iloc[0]) is True
    assert bool(health["fits_models"].iloc[0]) is False
    assert bool(health["writes_launch_configs"].iloc[0]) is False
    assert health["stage_zb_binary_or_matrix_artifacts"].iloc[0] == 2
    assert bool(health["run_clean"].iloc[0]) is False


def test_stage_zc_source_manifest_hashes_existing_files(tmp_path):
    path = tmp_path / "input.csv"
    path.write_text("a,b\n1,2\n")

    manifest = stage_zc.source_manifest([("unit", path)])

    assert manifest["label"].iloc[0] == "unit"
    assert bool(manifest["exists"].iloc[0]) is True
    assert manifest["size_bytes"].iloc[0] > 0
    assert len(manifest["sha256"].iloc[0]) == 64
