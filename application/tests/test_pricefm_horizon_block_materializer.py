"""Tests for PriceFM horizon-block materialization and seed-grid prep."""

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


def write_cell(tmp_path, name, method_id, predictions):
    root = tmp_path / name
    model = root / "model"
    adapter = root / "adapter"
    model.mkdir(parents=True)
    adapter.mkdir(parents=True)
    rows = []
    for split in ["val", "test"]:
        for origin_id in [0, 1]:
            for horizon in [1, 2]:
                rows.append({
                    "split": split,
                    "origin_id": origin_id,
                    "horizon": horizon,
                    "origin_market_time": "2025-01-{:02d}T00:00:00+00:00".format(origin_id + 1),
                    "response_market_time": "2025-01-{:02d}T00:{:02d}:00+00:00".format(origin_id + 1, 15 * (horizon - 1)),
                    "y_scaled": float(origin_id + horizon),
                })
    rows = pd.DataFrame(rows)
    for split in ["val", "test"]:
        rows[rows["split"].eq(split)].to_csv(adapter / "rows_{}.csv".format(split), index=False)
    pred_rows = []
    for split in ["val", "test"]:
        for origin_id in [0, 1]:
            for horizon in [1, 2]:
                pred_rows.append({
                    "method_id": method_id,
                    "split": split,
                    "origin_id": origin_id,
                    "horizon": horizon,
                    "tau": 0.5,
                    "pred_scaled": float(predictions[horizon]),
                })
    pd.DataFrame(pred_rows).to_csv(model / "model_predictions_scaled.csv", index=False)
    return model


def selection_row(model_dir, block, experiment_id):
    return {
        "metric_role": "selection",
        "region": "DE_LU",
        "fold": 2,
        "horizon_group": block,
        "experiment_id": experiment_id,
        "method_id": "candidate_method",
        "model_dir": str(model_dir),
        "stage": "unit",
        "lag_window": 96,
        "feature_map": "window_reservoir_v1",
        "feature_dim": 80,
        "depth": 1,
        "units": "[80]",
        "alpha": 0.5,
        "rho": 0.9,
        "input_scale": 0.5,
        "tau0": 1.0e-3,
        "seed": 1,
    }


def test_horizon_block_materializer_combines_selected_blocks(tmp_path):
    mod = load_script("25_materialize_median_horizon_block_composite.py")
    model_a = write_cell(tmp_path, "cell_a", "candidate_method", {1: 1.0, 2: 99.0})
    model_b = write_cell(tmp_path, "cell_b", "candidate_method", {1: 99.0, 2: 2.0})
    selection = pd.DataFrame([
        selection_row(model_a, "1-1", "exp_a"),
        selection_row(model_b, "2-2", "exp_b"),
    ])

    composite, audit = mod.materialize(selection, "DE_LU", [2], ["val"], "composite")
    assert set(composite["horizon"]) == {1, 2}
    assert set(composite["source_experiment_id"]) == {"exp_a", "exp_b"}
    assert audit["n_horizons"].iloc[0] == 2
    metrics, by_h, by_g = mod.compute_metrics(composite, "composite", y_scalers={})
    assert set(metrics["unit"]) == {"scaled"}
    assert metrics["method_id"].iloc[0] == "composite"
    assert by_h.shape[0] == 2
    assert by_g.shape[0] == 1


def test_horizon_block_materializer_rejects_duplicate_blocks(tmp_path):
    mod = load_script("25_materialize_median_horizon_block_composite.py")
    model_a = write_cell(tmp_path, "cell_a", "candidate_method", {1: 1.0, 2: 2.0})
    selection = pd.DataFrame([
        selection_row(model_a, "1-1", "exp_a"),
        selection_row(model_a, "1-1", "exp_a_dup"),
    ])
    import pytest

    with pytest.raises(ValueError, match="Duplicate selected horizon blocks"):
        mod.materialize(selection, "DE_LU", [2], ["val"], "composite")


def test_seed_grid_prep_deduplicates_geometries_and_scopes_folds():
    mod = load_script("26_prepare_median_seed_robustness_grid.py")
    baseline = pd.DataFrame([
        {
            "region": "DE_LU",
            "fold": 2,
            "experiment_id": "retained",
            "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "feature_map": "window_reservoir_v1",
            "lag_window": 72,
            "depth": 1,
            "units": "[120]",
            "alpha": "0.5",
            "rho": "0.9",
            "input_scale": "0.5",
            "projection_scale": 1.0,
            "tau0": 1.0e-3,
            "feature_dim": 120,
        }
    ])
    horizon = pd.DataFrame([
        {
            "region": "DE_LU",
            "fold": 2,
            "horizon_group": "1-24",
            "experiment_id": "same_geom",
            "method_id": "qdesn_al_rhs_ns_exact_chunked",
            "feature_map": "window_reservoir_v1",
            "lag_window": 72,
            "depth": 1,
            "units": "[120]",
            "alpha": "0.5",
            "rho": "0.9",
            "input_scale": "0.5",
            "projection_scale": 1.0,
            "tau0": 1.0e-3,
            "feature_dim": 120,
        }
    ])
    geoms = mod.collect_geometries(baseline, horizon, "DE_LU", [2])
    assert len(geoms) == 1
    assert "horizon_block" in geoms[0]["source_role"]
    experiments = mod.build_experiments(geoms, [20260601, 20260602])
    assert len(experiments) == 2
    assert all(exp["regions"] == ["DE_LU"] for exp in experiments)
    assert all(exp["folds"] == [2] for exp in experiments)
    assert {exp["seed"] for exp in experiments} == {20260601, 20260602}


def test_seed_robustness_summary_reports_mean_sd_and_worst():
    mod = load_script("27_summarize_median_seed_robustness.py")
    rows = []
    for seed, val, test in [(1, 5.0, 7.0), (2, 6.0, 8.0)]:
        for split, metric in [("val", val), ("test", test)]:
            rows.append({
                "region": "DE_LU",
                "fold": 2,
                "method_id": "qdesn_exal_rhs_ns_exact_chunked",
                "stage": "seed_robustness",
                "lag_window": 72,
                "feature_map": "window_reservoir_v1",
                "feature_dim": 120,
                "projection_scale": 1.0,
                "depth": 1,
                "units": "[120]",
                "alpha": "0.5",
                "rho": "0.9",
                "input_scale": "0.5",
                "tau0": 1.0e-3,
                "seed": seed,
                "split": split,
                "unit": "original",
                "AQL": metric,
            })
    out = mod.summarize_seed_robustness(
        pd.DataFrame(rows),
        selection_split="val",
        audit_split="test",
        unit="original",
        metric="AQL",
        methods=["qdesn_exal_rhs_ns_exact_chunked"],
    )
    assert out.shape[0] == 1
    row = out.iloc[0]
    assert row["n_seeds_completed"] == 2
    assert np.isclose(row["selection_mean_AQL"], 5.5)
    assert np.isclose(row["selection_worst_AQL"], 6.0)
    assert np.isclose(row["audit_worst_AQL"], 8.0)


def test_followup_grid_includes_p2_retests_and_fold3_surface():
    mod = load_script("28_prepare_median_folds23_followup_grid.py")
    registry = pd.DataFrame([
        {
            "region": "DE_LU",
            "fold": 2,
            "experiment_id": "fold2_prior",
            "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 1,
            "units": "[120]",
            "alpha": "0.5",
            "rho": "0.9",
            "input_scale": "0.25",
            "projection_scale": 1.0,
            "tau0": 1.0e-3,
            "feature_dim": 120,
            "state_output": "final_layer",
        },
        {
            "region": "DE_LU",
            "fold": 3,
            "experiment_id": "fold3_prior",
            "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 1,
            "units": "[80]",
            "alpha": "0.5",
            "rho": "0.97",
            "input_scale": "0.35",
            "projection_scale": 1.0,
            "tau0": 1.0e-3,
            "feature_dim": 80,
            "state_output": "final_layer",
        },
    ])
    geoms = mod.collect_geometries(registry, "DE_LU")
    assert len(geoms) == 25
    assert sum(int(g["fold"]) == 2 for g in geoms) == 1
    assert sum(int(g["fold"]) == 3 for g in geoms) == 24
    fold3_prior = [
        g for g in geoms
        if int(g["fold"]) == 3
        and int(g["depth"]) == 1
        and g["units"] == [80]
        and np.isclose(float(g["alpha"]), 0.5)
        and np.isclose(float(g["rho"]), 0.97)
        and np.isclose(float(g["input_scale"]), 0.35)
    ]
    assert len(fold3_prior) == 1
    assert "prior_p2_retest" in fold3_prior[0]["source_role"]
    assert "fold3_local_refine" in fold3_prior[0]["source_role"]

    experiments = mod.build_experiments(geoms, [20260601, 20260602])
    assert len(experiments) == 50
    assert len({exp["id"] for exp in experiments}) == 50
    assert sum(exp["folds"] == [2] for exp in experiments) == 2
    assert sum(exp["folds"] == [3] for exp in experiments) == 48
    assert {tuple(exp["units"]) for exp in experiments if exp["folds"] == [3]} == {
        (80,), (80, 80),
    }
