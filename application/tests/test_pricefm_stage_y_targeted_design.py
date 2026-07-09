"""Tests for the Stage-Y PriceFM targeted design planner."""

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


stage_y = load_script("87_prepare_pricefm_stage_y_targeted_design.py")


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(payload, f)


def failure_row(region, fold, mode, delta, information="target_only", horizon_range=5.0):
    return {
        "region": region,
        "fold": fold,
        "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
        "information_set": information,
        "current_AQL": 9.0 + delta,
        "pricefm_AQL": 9.0,
        "current_delta_vs_pricefm": delta,
        "worst_horizon_group": "49-72",
        "horizon_AQL_range": horizon_range,
        "test_regret_vs_oracle": 1.0 if mode == "candidate_family_falsified" else "",
        "validation_test_spearman": 0.1 if mode == "candidate_family_falsified" else "",
        "stage_w_oracle_delta_vs_current": 0.5 if mode == "candidate_family_falsified" else "",
        "stage_w_oracle_delta_vs_pricefm": 1.0 if mode == "candidate_family_falsified" else "",
        "primary_failure_mode": mode,
        "recommended_action": "unit",
    }


def make_stage_x_fixture(tmp_path, *, bad_summary=False):
    stage_x = tmp_path / "stage_x"
    output = tmp_path / "stage_y"
    write_json(stage_x / "summary.json", {
        "diagnostic_only": True,
        "fits_models": False,
        "writes_launch_configs": False,
        "stage_m_surface_changed": False,
        "selection_uses_test_metrics_any": False,
        "launch_new_fits_now": bool(bad_summary),
    })
    write_csv(stage_x / "stage_x_input_manifest.csv", [
        {"input_id": "unit", "kind": "csv", "role": "unit", "path": "unit", "sha256": "abc"}
    ])
    write_csv(stage_x / "stage_x_region_fold_failure_modes.csv", [
        failure_row("AA", 1, "candidate_family_falsified", 1.0),
        failure_row("BB", 1, "graph_information_gap", 0.5),
        failure_row("CC", 2, "late_horizon_failure", 0.4, information="pricefm_graph_inputs", horizon_range=8.0),
        failure_row("DD", 3, "current_qdesn_wins", -0.5, information="pricefm_graph_inputs"),
    ])
    write_csv(stage_x / "stage_x_selection_rule_audit.csv", [
        {
            "rule_id": "val_max_horizon_min",
            "selection_uses_test_metrics": False,
            "mean_test_delta_vs_pricefm": 1.0,
            "test_improved_vs_current_rows": 1,
            "test_improved_vs_pricefm_rows": 0,
        }
    ])
    write_csv(stage_x / "stage_x_recommended_actions.csv", [
        {"action": "launch_new_model_fits_now", "decision": False},
    ])
    write_csv(stage_x / "stage_x_horizon_failure_audit.csv", [
        {"region": "CC", "fold": 2, "source": "stage_u_surface", "worst_horizon_group": "49-72", "horizon_AQL_range": 8.0},
        {"region": "BB", "fold": 1, "source": "stage_u_surface", "worst_horizon_group": "49-72", "horizon_AQL_range": 7.0},
    ])
    write_csv(stage_x / "stage_x_candidate_evidence.csv", [
        {"region": "AA", "fold": 1, "experiment_id": "unit", "method_id": "qdesn", "test_metrics_role": "audit_only"}
    ])
    args = stage_y.parser().parse_args([
        "--stage-x-dir", str(stage_x),
        "--output-dir", str(output),
        "--max-proposed-future-experiments", "40",
    ])
    return args, output


def test_stage_y_writes_nonlaunch_design_manifest(tmp_path):
    args, output = make_stage_x_fixture(tmp_path)
    summary = stage_y.prepare(args)

    assert summary["diagnostic_only"] is True
    assert summary["fits_models"] is False
    assert summary["writes_launch_configs"] is False
    assert summary["launch_ready_rows"] == 0
    assert summary["launch_new_fits_now"] is False
    assert summary["future_experiment_budget_if_approved"] == 20

    design = pd.read_csv(output / "stage_y_design_manifest.csv")
    cost = pd.read_csv(output / "stage_y_cost_estimate.csv")
    decisions = pd.read_csv(output / "stage_y_decisions.csv")

    assert not design["launch_ready"].astype(bool).any()
    assert set(design["stage_y_lane"]) == {
        "exclude_falsified_stage_w_family",
        "graph_adapter_contract_design",
        "horizon_targeted_design",
        "no_action_current_qdesn_wins",
    }
    assert cost[cost["stage_y_lane"].eq("TOTAL")]["future_experiment_budget_if_approved"].iloc[0] == 20
    no_launch = decisions[decisions["decision_id"].eq("no_immediate_launch")]
    assert bool(no_launch["decision"].iloc[0]) is True
    assert (output / "stage_y_report.md").exists()


def test_stage_y_rejects_stage_x_immediate_launch_recommendation(tmp_path):
    args, _ = make_stage_x_fixture(tmp_path, bad_summary=True)
    with pytest.raises(ValueError, match="immediate new fits"):
        stage_y.prepare(args)
