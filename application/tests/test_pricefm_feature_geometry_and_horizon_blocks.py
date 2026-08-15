"""Tests for PriceFM feature-geometry and horizon-block diagnostics."""

from pathlib import Path
import importlib.util
import sys

import numpy as np
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


def test_feature_geometry_detects_duplicate_and_constant_columns():
    mod = load_script("23_audit_desn_feature_geometry.py")
    x = np.column_stack([
        np.ones(6),
        np.arange(6, dtype=float),
        np.arange(6, dtype=float),
        np.ones(6),
    ])
    out = mod.matrix_geometry(x, include_intercept=True)
    assert out["n_features"] == 4
    assert out["n_core_features"] == 3
    assert out["near_zero_var_count"] == 1
    assert out["high_corr_pair_count"] >= 1
    assert out["condition_number"] > 1.0


def test_feature_geometry_split_drift_is_zero_for_identical_stats():
    mod = load_script("23_audit_desn_feature_geometry.py")
    x = np.column_stack([np.ones(4), [0.0, 1.0, 2.0, 3.0], [1.0, 1.5, 2.5, 4.0]])
    stats = mod.split_stats(x, include_intercept=True)
    drift = mod.split_drift(stats, stats)
    assert np.isclose(drift["mean_abs_standardized_shift"], 0.0)
    assert np.isclose(drift["max_abs_standardized_shift"], 0.0)
    assert np.isclose(drift["median_scale_ratio"], 1.0)


def test_horizon_group_label_uses_24_step_blocks():
    mod = load_script("23_audit_desn_feature_geometry.py")
    assert mod.horizon_group_label(1) == "1-24"
    assert mod.horizon_group_label(24) == "1-24"
    assert mod.horizon_group_label(25) == "25-48"
    assert mod.horizon_group_label(96) == "73-96"


def make_horizon_metric(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def test_horizon_block_selection_uses_validation_not_test(tmp_path):
    mod = load_script("24_select_median_horizon_blocks.py")
    rows = []
    for exp, model_dir in [("exp_a", tmp_path / "a"), ("exp_b", tmp_path / "b")]:
        for split in ["val", "test"]:
            rows.append({
                "region": "DE_LU",
                "fold": 2,
                "experiment_id": exp,
                "method_id": "qdesn_exal_rhs_ns_exact_chunked",
                "model_dir": str(model_dir),
                "split": split,
                "unit": "original",
                "AQL": 1.0,
                "MAE": 2.0,
                "RMSE": 3.0,
                "stage": "unit",
                "priority": 0,
                "lag_window": 96,
                "feature_map": "window_reservoir_v1",
                "feature_dim": 80,
                "depth": 1,
                "units": "[80]",
                "alpha": "0.5",
                "rho": "0.9",
                "input_scale": "0.5",
                "tau0": 1.0e-3,
                "seed": 1,
            })
    metrics = pd.DataFrame(rows)
    make_horizon_metric(
        tmp_path / "a" / "metric_by_horizon_group.csv",
        [
            {"method_id": "qdesn_exal_rhs_ns_exact_chunked", "split": "val", "unit": "original", "horizon_group": "1-24", "AQL": 5.0, "MAE": 10.0, "RMSE": 11.0},
            {"method_id": "qdesn_exal_rhs_ns_exact_chunked", "split": "test", "unit": "original", "horizon_group": "1-24", "AQL": 1.0, "MAE": 2.0, "RMSE": 3.0},
        ],
    )
    make_horizon_metric(
        tmp_path / "b" / "metric_by_horizon_group.csv",
        [
            {"method_id": "qdesn_exal_rhs_ns_exact_chunked", "split": "val", "unit": "original", "horizon_group": "1-24", "AQL": 4.0, "MAE": 8.0, "RMSE": 9.0},
            {"method_id": "qdesn_exal_rhs_ns_exact_chunked", "split": "test", "unit": "original", "horizon_group": "1-24", "AQL": 9.0, "MAE": 18.0, "RMSE": 19.0},
        ],
    )
    horizon = mod.collect_candidate_horizon_rows(
        metrics,
        selection_split="val",
        audit_split="test",
        unit="original",
        blocks=["1-24"],
    )
    selected = mod.select_horizon_blocks(horizon, "AQL", ["1-24"])
    assert selected.shape[0] == 1
    assert selected["experiment_id"].iloc[0] == "exp_b"
    audit = mod.audit_selected_blocks(horizon, selected)
    assert np.isclose(audit["AQL"].iloc[0], 9.0)


def test_horizon_block_rejects_bad_blocks():
    mod = load_script("24_select_median_horizon_blocks.py")
    import pytest

    with pytest.raises(ValueError, match="duplicate"):
        mod.validate_blocks(["1-24", "1-24"])
    with pytest.raises(ValueError, match="invalid"):
        mod.validate_blocks(["24-1"])
