"""Tests for the Stage-ZB graph-direct full-budget planner."""

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


stage_zb = load_script("90_prepare_pricefm_stage_zb_graph_direct_fullbudget.py")


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


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
                "ranking_split": "val",
                "audit_split": "test",
                "ranking_unit": "original",
                "ranking_metric": "AQL",
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


def make_stage_z_fixture(tmp_path, *, launch_ready=False):
    stage_z = tmp_path / "stage_z"
    output = tmp_path / "stage_zb"
    grid_config = tmp_path / "grid.yaml"
    template = make_template(tmp_path)
    write_json(stage_z / "summary.json", {
        "diagnostic_only": True,
        "fits_models": False,
        "writes_launch_configs": False,
        "launch_ready_rows": 0,
    })
    write_csv(stage_z / "stage_z_graph_adapter_contract.csv", [
        {
            "contract_id": "PL_fold3_graph_adapter",
            "region": "PL",
            "fold": 3,
            "current_AQL": 8.403226775374353,
            "pricefm_AQL": 7.690217805571597,
            "current_delta_vs_pricefm": 0.7130089698027566,
            "worst_horizon_group": "49-72",
            "requires_new_code": True,
            "launch_ready": launch_ready,
        },
        {
            "contract_id": "LV_fold1_graph_adapter",
            "region": "LV",
            "fold": 1,
            "current_AQL": 13.465938852704127,
            "pricefm_AQL": 12.946992353016546,
            "current_delta_vs_pricefm": 0.5189464996875817,
            "worst_horizon_group": "49-72",
            "requires_new_code": True,
            "launch_ready": False,
        },
    ])
    write_csv(stage_z / "stage_z_decision_gates.csv", [
        {"gate_id": "unit", "passed": True, "decision": "unit", "reason": "unit"}
    ])
    args = stage_zb.parser().parse_args([
        "--stage-z-dir", str(stage_z),
        "--template-grid-config", str(template),
        "--output-dir", str(output),
        "--grid-config", str(grid_config),
        "--generated-root", str(tmp_path / "generated"),
        "--run-root", str(tmp_path / "runs"),
    ])
    return args, output, grid_config


def test_stage_zb_writes_launchable_fullbudget_graph_direct_probe(tmp_path):
    args, output, grid_config = make_stage_z_fixture(tmp_path)
    summary = stage_zb.prepare(args)

    assert summary["fits_models"] is False
    assert summary["writes_launch_config"] is True
    assert summary["launch_ready_rows"] == 1
    assert summary["selected_region"] == "PL"
    assert summary["selected_fold"] == 3

    probe = pd.read_csv(output / "stage_zb_probe_manifest.csv")
    assert probe["feature_policy"].iloc[0] == "graph_neighbor_direct"
    assert probe["train_origin_limit"].iloc[0] == 3000
    assert probe["launch_ready"].astype(bool).sum() == 1
    assert probe["geometry_anchor"].iloc[0] == "stage_c_target_only_selected_pl_f3"
    assert probe["input_scale"].iloc[0] == 0.25

    gates = pd.read_csv(output / "stage_zb_decision_gates.csv")
    assert gates["passed"].astype(bool).all()

    grid = yaml.safe_load(grid_config.read_text())["pricefm_desn_experiment_grid"]
    exp = grid["experiments"][0]
    assert exp["feature_policy"] == "graph_neighbor_direct"
    assert exp["neighbor_regions"] == ["CZ", "DE_LU", "LT", "SE_4", "SK"]
    assert exp["input_scale"] == 0.25
    assert exp["seed"] == 20260603
    assert grid["fixed"]["train_origin_limit"] == 3000


def test_stage_zb_rejects_launch_ready_stage_z_graph_rows(tmp_path):
    args, _, _ = make_stage_z_fixture(tmp_path, launch_ready=True)
    with pytest.raises(ValueError, match="launch-ready"):
        stage_zb.prepare(args)
