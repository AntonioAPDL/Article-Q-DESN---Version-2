"""Tests for the Stage-ZC graph spread-summary full-budget planner."""

from pathlib import Path
import importlib.util
import json
import sys

import pandas as pd
import pytest
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


stage_zc_full = load_script("93_prepare_pricefm_stage_zc_graph_spread_fullbudget.py")


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(payload, f)


def write_yaml(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def make_template(tmp_path):
    data_config = tmp_path / "pricefm.yaml"
    write_yaml(data_config, {
        "pricefm": {
            "regions": [
                "AT", "BE", "BG", "CZ", "DE_LU", "DK_1", "DK_2", "EE", "ES", "FI",
                "FR", "GR", "HR", "HU", "IT_CALA", "IT_CNOR", "IT_CSUD", "IT_NORD",
                "IT_SARD", "IT_SICI", "IT_SUD", "LT", "LV", "NL", "NO_1", "NO_2",
                "NO_3", "NO_4", "NO_5", "PL", "PT", "RO", "SE_1", "SE_2", "SE_3",
                "SE_4", "SI", "SK",
            ],
            "processed_dir": str(tmp_path / "processed"),
            "windows": {"lag_window": 96, "lead_window": 96},
        }
    })
    template = tmp_path / "template.yaml"
    write_yaml(template, {
        "pricefm_desn_experiment_grid": {
            "grid_id": "unit_template",
            "base": {
                "data_config": str(data_config),
                "full_config": (
                    "application/config/"
                    "pricefm_desn_model_median_de_lu_fold1_authoritative_reservoir_corrected_20260602.yaml"
                ),
                "generated_root": str(tmp_path / "old_generated"),
                "run_root": str(tmp_path / "old_runs"),
            },
            "scope": {
                "regions": ["DE_LU"],
                "folds": [1],
                "quantiles": [0.5],
                "horizons": "all",
            },
            "fixed": {
                "lead_window": 96,
                "feature_map": "window_reservoir_v1",
                "include_intercept": True,
                "shrink_intercept": False,
                "train_origin_limit": 3000,
                "train_origin_selection": "tail",
                "row_chunk_size": 512,
                "projection_scale": 1.0,
                "default_jobs": 1,
                "qdesn_likelihoods": ["al", "exal"],
            },
            "launch": {},
            "experiments": [],
            "experiment_blocks": [],
        }
    })
    return template


def make_fixture(tmp_path, *, nonzero_return=False, bad_policy=False, with_binary=False):
    stage_zc = tmp_path / "stage_zc"
    smoke_grid = tmp_path / "smoke_grid"
    smoke_run = tmp_path / "smoke_run"
    exp = smoke_run / "smoke_exp" / "cells" / "region=PL" / "fold=3"
    adapter = exp / "adapter"
    model = exp / "model"
    output = tmp_path / "stage_zc_fullbudget"
    grid_config = tmp_path / "grid.yaml"
    template = make_template(tmp_path)
    write_json(stage_zc / "summary.json", {
        "diagnostic_only": True,
        "fits_models": False,
        "writes_launch_configs": False,
        "diagnostic_supports_revised_graph_contract": True,
        "recommended_next_contract": "graph_neighbor_spread_summary",
    })
    write_csv(smoke_grid / "launch_status.csv", [
        {"id": "window", "kind": "window_build", "status": "completed", "return_code": 0},
        {
            "id": "smoke_exp",
            "kind": "experiment",
            "status": "completed",
            "return_code": 1 if nonzero_return else 0,
        },
    ])
    write_csv(model / "metric_summary.csv", [
        {"method_id": "qdesn_al_rhs_ns_exact_chunked", "split": "test", "unit": "original", "AQL": 1.0, "MAE": 2.0, "RMSE": 3.0},
        {"method_id": "naive3_prev7_avg", "split": "test", "unit": "original", "AQL": 2.0, "MAE": 4.0, "RMSE": 5.0},
    ])
    write_json(adapter / "feature_manifest.json", {
        "feature_policy": "target_only" if bad_policy else "graph_neighbor_spread_summary",
    })
    write_csv(adapter / "feature_provenance.csv", [
        {
            "feature_policy": "graph_neighbor_spread_summary",
            "source_region": "PL",
            "source_role": "target",
            "input_block": "lag",
            "source_column": "PL-price",
            "source_feature": "price",
            "within_block_position": 1,
        },
        {
            "feature_policy": "graph_neighbor_spread_summary",
            "source_region": "graph_neighbor_summary",
            "source_role": "neighbor_summary",
            "input_block": "lag",
            "source_column": "graph_neighbor_mean_diff::lag-price",
            "source_feature": "price",
            "within_block_position": 2,
        },
    ])
    if with_binary:
        (model / "fit.rds").write_text("binary placeholder")
    args = stage_zc_full.parser().parse_args([
        "--stage-zc-dir", str(stage_zc),
        "--smoke-grid-root", str(smoke_grid),
        "--smoke-run-root", str(smoke_run),
        "--template-grid-config", str(template),
        "--output-dir", str(output),
        "--grid-config", str(grid_config),
        "--generated-root", str(tmp_path / "generated"),
        "--run-root", str(tmp_path / "runs"),
    ])
    return args, output, grid_config


def test_stage_zc_fullbudget_writes_launchable_graph_spread_probe(tmp_path):
    args, output, grid_config = make_fixture(tmp_path)
    summary = stage_zc_full.prepare(args)

    assert summary["status"] == "prepared"
    assert summary["feature_policy"] == "graph_neighbor_spread_summary"
    assert summary["train_origin_limit"] == 3000
    assert summary["launch_ready_rows"] == 1

    manifest = pd.read_csv(output / "stage_zc_fullbudget_probe_manifest.csv")
    assert manifest["feature_policy"].iloc[0] == "graph_neighbor_spread_summary"
    assert manifest["train_origin_limit"].iloc[0] == 3000
    assert manifest["launch_ready"].astype(bool).all()

    grid = yaml.safe_load(grid_config.read_text())["pricefm_desn_experiment_grid"]
    exp = grid["experiments"][0]
    assert exp["feature_policy"] == "graph_neighbor_spread_summary"
    assert exp["neighbor_regions"] == ["CZ", "DE_LU", "LT", "SE_4", "SK"]
    assert exp["summary_stats"] == ["mean_diff", "sd", "min_diff", "max_diff"]
    assert grid["fixed"]["train_origin_limit"] == 3000


def test_stage_zc_fullbudget_refuses_failed_smoke(tmp_path):
    args, _, _ = make_fixture(tmp_path, nonzero_return=True)
    with pytest.raises(ValueError, match="nonzero"):
        stage_zc_full.prepare(args)


def test_stage_zc_fullbudget_refuses_wrong_smoke_policy(tmp_path):
    args, _, _ = make_fixture(tmp_path, bad_policy=True)
    with pytest.raises(ValueError, match="wrong feature policy"):
        stage_zc_full.prepare(args)


def test_stage_zc_fullbudget_refuses_binary_smoke_artifacts(tmp_path):
    args, _, _ = make_fixture(tmp_path, with_binary=True)
    with pytest.raises(ValueError, match="binary fit artifacts"):
        stage_zc_full.prepare(args)
