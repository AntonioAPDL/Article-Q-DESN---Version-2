"""Tests for the Stage-Z PriceFM design contracts."""

from pathlib import Path
import importlib.util
import json
import sys

import pandas as pd
import pytest


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


stage_z = load_script("88_prepare_pricefm_stage_z_design_contracts.py")


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(payload, f)


def design_row(region, fold, mode, lane, delta, future_budget, *, launch_ready=False):
    return {
        "region": region,
        "fold": fold,
        "stage_x_failure_mode": mode,
        "stage_x_recommended_action": "unit",
        "stage_y_lane": lane,
        "stage_y_priority": 1,
        "launch_ready": launch_ready,
        "fits_models_now": False,
        "writes_launch_config_now": False,
        "requires_new_code": lane == "graph_adapter_contract_design",
        "requires_manual_approval": lane in (
            "graph_adapter_contract_design",
            "horizon_targeted_design",
        ),
        "future_experiments_per_row_if_approved": future_budget,
        "future_experiment_budget_if_approved": future_budget,
        "current_AQL": 9.0 + delta,
        "pricefm_AQL": 9.0,
        "current_delta_vs_pricefm": delta,
        "information_set": "target_only",
        "worst_horizon_group": "49-72",
        "horizon_AQL_range": 3.0,
        "horizon_rank": 1,
        "blocked_by": "unit reason",
        "rationale": "unit rationale",
    }


def make_stage_y_fixture(tmp_path, *, launch_ready=False):
    stage_y = tmp_path / "stage_y"
    output = tmp_path / "stage_z"
    write_json(stage_y / "summary.json", {
        "diagnostic_only": True,
        "fits_models": False,
        "writes_launch_configs": False,
        "stage_m_surface_changed": False,
        "launch_ready_rows": 1 if launch_ready else 0,
        "launch_new_fits_now": False,
    })
    write_csv(stage_y / "stage_y_input_manifest.csv", [
        {"input_id": "unit", "kind": "csv", "role": "unit", "path": "unit", "sha256": "abc"}
    ])
    write_csv(stage_y / "stage_y_lane_contract.csv", [
        {"stage_y_lane": "horizon_targeted_design", "launch_ready": False},
        {"stage_y_lane": "graph_adapter_contract_design", "launch_ready": False},
    ])
    write_csv(stage_y / "stage_y_design_manifest.csv", [
        design_row(
            "RO", 3, "late_horizon_failure", "horizon_targeted_design",
            0.4331, 8, launch_ready=launch_ready,
        ),
        design_row(
            "PL", 3, "graph_information_gap", "graph_adapter_contract_design",
            0.7130, 12,
        ),
        design_row(
            "LT", 1, "candidate_family_falsified",
            "exclude_falsified_stage_w_family", 1.9, 0,
        ),
        design_row("BE", 3, "minor_underperformance", "monitor_no_large_launch", 0.2, 0),
        design_row("EE", 1, "current_qdesn_wins", "no_action_current_qdesn_wins", -1.0, 0),
        design_row("HU", 2, "pricefm_far_ahead", "defer_model_class_change", 1.4, 0),
    ])
    write_csv(stage_y / "stage_y_cost_estimate.csv", [
        {"stage_y_lane": "TOTAL", "n_rows": 6, "launch_ready_rows": 0, "future_experiment_budget_if_approved": 20}
    ])
    write_csv(stage_y / "stage_y_decisions.csv", [
        {"decision_id": "launch_ready_rows", "decision": False, "reason": "unit"}
    ])
    write_csv(stage_y / "stage_y_analysis_by_point.csv", [
        {"point": "unit", "diagnosis": "unit", "decision": "unit"}
    ])
    args = stage_z.parser().parse_args([
        "--stage-y-dir", str(stage_y),
        "--output-dir", str(output),
    ])
    return args, output


def test_stage_z_writes_nonlaunch_contracts(tmp_path):
    args, output = make_stage_y_fixture(tmp_path)
    summary = stage_z.prepare(args)

    assert summary["diagnostic_only"] is True
    assert summary["fits_models"] is False
    assert summary["writes_launch_configs"] is False
    assert summary["launch_ready_rows"] == 0
    assert summary["horizon_contract_rows"] == 1
    assert summary["graph_adapter_contract_rows"] == 1
    assert summary["blocked_or_monitor_rows"] == 4

    horizon = pd.read_csv(output / "stage_z_horizon_contract.csv")
    graph = pd.read_csv(output / "stage_z_graph_adapter_contract.csv")
    blocked = pd.read_csv(output / "stage_z_blocked_rows.csv")
    gates = pd.read_csv(output / "stage_z_decision_gates.csv")

    assert horizon["primary_selection_rule"].iloc[0] == "val_max_horizon_min"
    assert bool(horizon["launch_ready"].iloc[0]) is False
    assert bool(graph["requires_new_code"].iloc[0]) is True
    assert bool(graph["launch_ready"].iloc[0]) is False
    assert set(blocked["row_status"]) == {
        "blocked_stage_w_family",
        "monitor_not_launch_ready",
        "blocked_current_qdesn_wins",
        "blocked_model_class_change",
    }
    assert gates["passed"].astype(bool).all()
    assert (output / "stage_z_report.md").exists()


def test_stage_z_rejects_launch_ready_stage_y(tmp_path):
    args, _ = make_stage_y_fixture(tmp_path, launch_ready=True)
    with pytest.raises(ValueError, match="zero launch-ready rows"):
        stage_z.prepare(args)
