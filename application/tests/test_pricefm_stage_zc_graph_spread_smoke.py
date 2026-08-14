"""Tests for the Stage-ZC graph spread-summary smoke planner."""

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


stage_zc_smoke = load_script("92_prepare_pricefm_stage_zc_graph_spread_smoke.py")


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(payload, f)


def write_yaml(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


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


def make_args(tmp_path, *, recommended=True):
    stage_zc = tmp_path / "stage_zc"
    output = tmp_path / "stage_zc_smoke"
    grid_config = tmp_path / "grid.yaml"
    template = make_template(tmp_path)
    write_json(stage_zc / "summary.json", {
        "diagnostic_only": True,
        "fits_models": False,
        "writes_launch_configs": False,
        "diagnostic_supports_revised_graph_contract": recommended,
        "recommended_next_contract": (
            "graph_neighbor_spread_summary" if recommended else "stop_after_diagnostics"
        ),
    })
    return stage_zc_smoke.parser().parse_args([
        "--stage-zc-dir", str(stage_zc),
        "--template-grid-config", str(template),
        "--output-dir", str(output),
        "--grid-config", str(grid_config),
        "--generated-root", str(tmp_path / "generated"),
        "--run-root", str(tmp_path / "runs"),
    ]), output, grid_config


def test_stage_zc_smoke_writes_one_launchable_spread_summary_cell(tmp_path):
    args, output, grid_config = make_args(tmp_path)
    summary = stage_zc_smoke.prepare(args)

    assert summary["status"] == "prepared"
    assert summary["feature_policy"] == "graph_neighbor_spread_summary"
    assert summary["launch_ready_rows"] == 1

    manifest = pd.read_csv(output / "stage_zc_smoke_manifest.csv")
    assert manifest["feature_policy"].iloc[0] == "graph_neighbor_spread_summary"
    assert manifest["train_origin_limit"].iloc[0] == 50

    grid = yaml.safe_load(grid_config.read_text())["pricefm_desn_experiment_grid"]
    exp = grid["experiments"][0]
    assert exp["feature_policy"] == "graph_neighbor_spread_summary"
    assert exp["neighbor_regions"] == ["CZ", "DE_LU", "LT", "SE_4", "SK"]
    assert exp["summary_stats"] == ["mean_diff", "sd", "min_diff", "max_diff"]
    assert grid["fixed"]["train_origin_limit"] == 50


def test_stage_zc_smoke_refuses_without_diagnostic_recommendation(tmp_path):
    args, _, _ = make_args(tmp_path, recommended=False)
    with pytest.raises(ValueError, match="did not recommend"):
        stage_zc_smoke.prepare(args)
