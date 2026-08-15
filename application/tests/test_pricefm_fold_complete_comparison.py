"""Tests for fold-complete PriceFM/DESN comparison summaries."""

from pathlib import Path
import importlib.util
import sys

import pandas as pd
import yaml


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


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def make_comparison_dir(root, fold):
    path = root / "fold{}".format(fold)
    metric_rows = [
        {
            "method_id": "pricefm_phase1_pretraining",
            "split": "test",
            "unit": "original",
            "AQL": 10.0 + fold,
            "AQCR": 0.0,
            "MAE": 20.0 + fold,
            "RMSE": 30.0 + fold,
        },
        {
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "split": "test",
            "unit": "original",
            "AQL": 9.0 + fold,
            "AQCR": 0.0,
            "MAE": 18.0 + fold,
            "RMSE": 29.0 + fold,
        },
    ]
    write_csv(path / "pricefm_vs_desn_metric_summary.csv", metric_rows)
    horizon_rows = []
    group_rows = []
    for method in ["pricefm_phase1_pretraining", "qdesn_exal_rhs_ns_exact_chunked"]:
        for horizon in [1, 2]:
            horizon_rows.append({
                "method_id": method,
                "split": "test",
                "unit": "original",
                "horizon": horizon,
                "AQL": float(horizon + fold),
                "AQCR": 0.0,
                "MAE": float(horizon + fold + 1),
                "RMSE": float(horizon + fold + 2),
            })
        group_rows.append({
            "method_id": method,
            "split": "test",
            "unit": "original",
            "horizon_group": "1-24",
            "AQL": 1.0 + fold,
            "AQCR": 0.0,
            "MAE": 2.0 + fold,
            "RMSE": 3.0 + fold,
        })
    write_csv(path / "pricefm_vs_desn_metric_by_horizon.csv", horizon_rows)
    write_csv(path / "pricefm_vs_desn_metric_by_horizon_group.csv", group_rows)
    write_csv(
        path / "pricefm_vs_desn_row_alignment_audit.csv",
        [
            {
                "method_id": method,
                "available_prediction_rows": 100,
                "available_unique_response_rows": 50,
                "aligned_prediction_rows": 100,
                "aligned_unique_response_rows": 50,
            }
            for method in ["pricefm_phase1_pretraining", "qdesn_exal_rhs_ns_exact_chunked"]
        ],
    )
    return path


def test_fold_complete_summary_collects_and_ranks(tmp_path):
    mod = load_script("32_summarize_pricefm_fold_complete_comparison.py")
    fold_dirs = [(1, make_comparison_dir(tmp_path, 1)), (2, make_comparison_dir(tmp_path, 2))]
    payload = mod.collect_fold_outputs(fold_dirs)
    macro = mod.macro_metrics(payload["metric"])
    delta = mod.deltas_vs_baseline(payload["metric"], "pricefm_phase1_pretraining")
    winners = mod.fold_winners(payload["metric"])

    assert payload["metric"].shape[0] == 4
    assert macro.iloc[0]["method_id"] == "qdesn_exal_rhs_ns_exact_chunked"
    assert delta[delta["method_id"].eq("qdesn_exal_rhs_ns_exact_chunked")]["delta_AQL"].lt(0.0).all()
    assert winners["best_method_id"].eq("qdesn_exal_rhs_ns_exact_chunked").all()


def test_fold_complete_summary_reads_selected_specs(tmp_path):
    mod = load_script("32_summarize_pricefm_fold_complete_comparison.py")
    grid = {
        "pricefm_desn_experiment_grid": {
            "experiments": [
                {
                    "id": "fold1_tau0p1",
                    "lag_window": 96,
                    "depth": 1,
                    "units": [120],
                    "alpha": 0.5,
                    "rho": 0.9,
                    "input_scale": 0.5,
                    "projection_scale": 1.0,
                    "tau0": 0.001,
                    "seed": 20260601,
                }
            ]
        }
    }
    grid_path = tmp_path / "fold1.yaml"
    yaml.safe_dump(grid, grid_path.open("w"), sort_keys=False)
    reg_path = tmp_path / "registry.csv"
    write_csv(
        reg_path,
        [{
            "fold": 2,
            "experiment_id": "fold2",
            "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "lag_window": 96,
            "feature_dim": 120,
            "depth": 1,
            "units": "[120]",
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.25,
            "projection_scale": 1.0,
            "tau0": 0.001,
            "seed": 20260603,
            "selection_metric_value": 6.0,
            "test_AQL": 7.0,
        }],
    )
    specs = mod.selected_spec_summary(grid_path, reg_path)

    assert specs.shape[0] == 2
    assert set(specs["fold"]) == {1, 2}
    assert specs.loc[specs["fold"].eq(2), "selection_source"].iloc[0] == "folds23_validation_registry"
