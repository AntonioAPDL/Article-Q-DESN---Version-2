"""Tests for PriceFM Stage-R24 mechanism wiring."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pandas as pd
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application" / "scripts" / "pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


def load_script(name: str):
    path = SCRIPT_DIR / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def write_yaml(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(payload, sort_keys=False))


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def minimal_data_config() -> dict:
    return {
        "pricefm": {
            "repo_id": "unit",
            "filename": "unit.csv",
            "raw_dir": "application/data_local/pricefm/raw",
            "interim_dir": "application/data_local/pricefm/interim",
            "processed_dir": "application/data_local/pricefm/processed",
            "time_col": "time",
            "timezone": "UTC",
            "frequency": "15min",
            "observed_start_utc": "2020-01-01T00:00:00Z",
            "observed_end_utc": "2020-01-02T00:00:00Z",
            "expected_rows": 1,
            "expected_columns": 1,
            "split_time_col": "market_time",
            "market_time_definition": "unit",
            "regions": ["NO_4"],
            "features": {"label": "price", "raw": ["price", "load"], "lag": ["price"], "lead": ["load"]},
            "splits": [{"fold": 1}],
            "scaling": {},
            "windows": {"lag_window": 96, "lead_window": 96},
            "pilot": {"region": "NO_4", "fold": 1},
        }
    }


def minimal_full_config(data_path: Path) -> dict:
    return {
        "pricefm_desn_full": {
            "data_config": str(data_path),
            "package_path": "/tmp/pkg",
            "scope": {
                "regions": ["NO_4"],
                "folds": [1],
                "splits": ["train", "val", "test"],
                "quantiles": [0.5],
                "horizons": "all",
            },
            "adapter": {"feature_map": "window_reservoir_v1", "feature_dim": 64, "seed": 1},
            "run": {"output_dir": "application/data_local/pricefm/runs/unit", "nd_predictive": 10, "seed": 1},
            "rhs_ns": {"tau0": 0.001, "shrink_intercept": False},
            "normal": {"omega_prior": {}, "vb_control": {}},
            "qdesn_vb": {"likelihoods": ["al", "exal"], "max_iter": 5, "min_iter_elbo": 2, "tol": 1e-4, "tol_par": 1e-4, "n_samp_xi": 5},
            "exact_equivalence": {"enabled": False},
        }
    }


def test_experiment_grid_writes_horizon_weighting_training_block(tmp_path, monkeypatch):
    prep = load_script("12_prepare_desn_experiment_grid.py")
    data_path = tmp_path / "data.yaml"
    full_path = tmp_path / "full.yaml"
    write_yaml(data_path, minimal_data_config())
    write_yaml(full_path, minimal_full_config(data_path))
    monkeypatch.setattr(prep, "repo_path", lambda path: Path(path) if Path(path).is_absolute() else tmp_path / path)

    grid = {
        "grid_id": "unit_grid",
        "base": {
            "data_config": str(data_path),
            "full_config": str(full_path),
            "generated_root": str(tmp_path / "generated"),
            "run_root": str(tmp_path / "runs"),
        },
        "scope": {"regions": ["NO_4"], "folds": [1], "quantiles": [0.5], "horizons": "all", "ranking_split": "val", "ranking_unit": "original", "ranking_metric": "AQL"},
        "fixed": {
            "lead_window": 96,
            "train_origin_limit": 100,
            "train_origin_selection": "tail",
            "feature_map": "window_reservoir_v1",
            "include_intercept": True,
            "row_chunk_size": 512,
            "qdesn_likelihoods": ["exal"],
            "exact_equivalence_train_rows": 10,
        },
        "experiments": [
            {
                "id": "weighted",
                "stage": "unit",
                "priority": 0,
                "regions": ["NO_4"],
                "folds": [1],
                "lag_window": 96,
                "feature_dim": 64,
                "units": [96, 64],
                "depth": 2,
                "alpha": 0.35,
                "rho": 0.82,
                "input_scale": 0.3,
                "tau0": 0.001,
                "seed": 11,
                "horizon_weighting_enabled": True,
                "horizon_focus": "25-48",
                "horizon_weight_multiplier": 2.5,
                "horizon_weighting": {"integer_scale": 2, "max_expansion_factor": 6},
            }
        ],
        "experiment_blocks": [],
    }
    rows = prep.prepare_grid(grid, grid["base"]["generated_root"], write=True)
    full_config = yaml.safe_load((tmp_path / rows[0]["full_config"]).read_text())["pricefm_desn_full"]
    weighting = full_config["training"]["horizon_weighting"]
    assert weighting["enabled"] is True
    assert weighting["focus"] == "25-48"
    assert weighting["multiplier"] == 2.5
    assert weighting["integer_scale"] == 2
    assert full_config["qdesn_vb"]["likelihoods"] == ["exal"]


def test_r_model_source_contains_horizon_weighting_and_likelihood_hooks():
    text = (SCRIPT_DIR / "08_run_desn_model_smoke.R").read_text()
    assert "build_horizon_weighting" in text
    assert "integer_frequency_replication" in text
    assert "X_q_train" in text
    assert "qdesn_likelihoods" in text
    assert 'if ("al" %in% qdesn_likelihoods)' in text
    assert 'if ("exal" %in% qdesn_likelihoods)' in text
    assert "training_weight_summary.csv" in text


def make_postfit_fixture(tmp_path: Path):
    model = tmp_path / "run" / "cells" / "region=NO_4" / "fold=1" / "model"
    adapter = tmp_path / "run" / "cells" / "region=NO_4" / "fold=1" / "adapter"
    pred_rows = []
    row_val = []
    row_test = []
    for split, row_store in [("val", row_val), ("test", row_test)]:
        for origin in range(4):
            for horizon in [1, 25]:
                y = float(origin + horizon / 100.0)
                row_store.append({"split": split, "origin_id": origin, "horizon": horizon, "y_scaled": y})
                pred_rows.append(
                    {
                        "method_id": "qdesn_exal_rhs_ns_exact_chunked",
                        "split": split,
                        "origin_id": origin,
                        "horizon": horizon,
                        "tau": 0.5,
                        "pred_scaled": y + 1.0,
                    }
                )
    write_csv(model / "predictions_with_naive_scaled.csv", pred_rows)
    write_csv(model / "metric_summary.csv", [{"method_id": "qdesn_exal_rhs_ns_exact_chunked", "split": "val", "unit": "scaled", "AQL": 0.5}])
    write_csv(adapter / "rows_val.csv", row_val)
    write_csv(adapter / "rows_test.csv", row_test)
    manifest = tmp_path / "manifest.csv"
    write_csv(
        manifest,
        [
            {
                "stage_r22b_case_id": "case_no4_f1",
                "stage_r22b_candidate_id": "postfit_shift",
                "region": "NO_4",
                "fold": 1,
                "screening_arm": "postfit_calibration",
                "candidate_family": "case_specific_postfit_quantile_shift",
                "calibration_rule": "horizon_block_quantile_shift_on_validation",
                "uses_existing_predictions": True,
                "requires_new_fit": False,
                "existing_prediction_path": str(model / "predictions_with_naive_scaled.csv"),
                "existing_metric_summary_path": str(model / "metric_summary.csv"),
                "source_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            }
        ],
    )
    return manifest


def test_stage_r24_postfit_calibration_materializes_validation_only_shift(tmp_path):
    manifest = make_postfit_fixture(tmp_path)
    out = tmp_path / "out"
    mod = load_script("148_materialize_pricefm_stage_r24_postfit_calibration.py")
    summary = mod.run(
        mod.parser().parse_args(
            [
                "--candidate-manifest",
                str(manifest),
                "--output-dir",
                str(out),
                "--allow-missing-scalers",
                "true",
                "--primary-unit",
                "scaled",
                "--force",
                "true",
            ]
        )
    )
    assert summary["status"] == "completed_with_materialized_postfit_candidates"
    assert summary["n_ready_rows"] == 1
    params = pd.read_csv(out / "pricefm_stage_r24_postfit_calibration_params.csv")
    assert set(params["horizon_group"]) == {"1-24", "25-48"}
    assert params["uses_test_for_calibration"].map(lambda x: str(x).lower() == "false").all()
    metrics = pd.read_csv(out / "pricefm_stage_r24_postfit_metric_summary.csv")
    val = metrics[(metrics["split"] == "val") & (metrics["unit"] == "scaled")].iloc[0]
    test = metrics[(metrics["split"] == "test") & (metrics["unit"] == "scaled")].iloc[0]
    assert val["AQL"] < 1.0e-12
    assert test["AQL"] < 1.0e-12
    gates = pd.read_csv(out / "pricefm_stage_r24_no_launch_gates.csv")
    assert gates["passed"].map(bool).all()
    assert not list(out.glob("*.yaml"))
