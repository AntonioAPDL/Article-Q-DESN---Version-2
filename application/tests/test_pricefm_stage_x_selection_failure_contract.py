"""Tests for the Stage-X PriceFM selection-failure contract."""

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


stage_x = load_script("86_design_pricefm_stage_x_selection_failure_contract.py")


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(payload, f)


def surface_row(region, fold, local, pricefm, information_set="target_only"):
    return {
        "region": region,
        "fold": fold,
        "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
        "model_family": "qdesn_exal",
        "information_set": information_set,
        "local_AQL": local,
        "pricefm_AQL": pricefm,
        "delta_abs": local - pricefm,
        "delta_rel": (local - pricefm) / pricefm,
    }


def candidate_row(region, fold, exp_id, method_id, val, test, current, pricefm, *, source="unit"):
    vals = {
        "source_label": source,
        "experiment_id": exp_id,
        "region": region,
        "fold": fold,
        "method_id": method_id,
        "cell_dir": "unused",
        "metric_summary_path": "unused",
        "horizon_group_path": "unused",
        "feature_policy": "graph_khop",
        "lag_window": 96,
        "feature_dim": 120,
        "depth": 1,
        "units": "[120]",
        "alpha": 0.5,
        "rho": 0.9,
        "input_scale": 0.5,
        "projection_scale": 0.5,
        "seed": 1,
        "tau0": 0.001,
        "vb_max_iter": 100,
        "vb_min_iter": 50,
        "val_AQL": val,
        "val_MAE": 2 * val,
        "val_RMSE": 3 * val,
        "test_AQL": test,
        "test_MAE": 2 * test,
        "test_RMSE": 3 * test,
        "stage_m_surface_AQL": current,
        "current_median_test_AQL": current,
        "pricefm_AQL": pricefm,
        "test_delta_vs_current_median": test - current,
        "test_delta_vs_stage_m_surface": test - current,
        "test_delta_vs_pricefm": test - pricefm,
        "validation_metrics_complete": True,
        "test_metrics_complete": True,
        "horizon_rule_eligible": True,
        "val_horizon_groups_complete": True,
        "test_horizon_groups_complete": True,
        "candidate_key": f"{region}:{fold}:{exp_id}:{method_id}",
    }
    groups = {
        "1_24": val,
        "25_48": val + 0.1,
        "49_72": val + 0.2,
        "73_96": val + 0.3,
    }
    for group, aql in groups.items():
        vals[f"val_hg_{group}_AQL"] = aql
        vals[f"test_hg_{group}_AQL"] = test
    vals["val_horizon_mean_AQL"] = sum(groups.values()) / 4.0
    vals["val_horizon_max_AQL"] = max(groups.values())
    vals["val_horizon_min_AQL"] = min(groups.values())
    vals["val_horizon_range_AQL"] = max(groups.values()) - min(groups.values())
    vals["val_horizon_midlate_mean_AQL"] = (groups["25_48"] + groups["49_72"] + groups["73_96"]) / 3.0
    vals["test_horizon_mean_AQL"] = test
    vals["test_horizon_max_AQL"] = test
    vals["test_horizon_min_AQL"] = test
    vals["test_horizon_range_AQL"] = 0.0
    vals["test_horizon_midlate_mean_AQL"] = test
    return vals


def make_fixture(tmp_path, *, bad_stage_v=False):
    root = tmp_path / "fixture"
    out = tmp_path / "out"
    write_csv(root / "stage_m.csv", [
        surface_row("AA", 1, 9.0, 7.0, "target_only"),
        surface_row("BB", 2, 9.0, 7.0, "pricefm_graph_inputs"),
    ])
    write_json(root / "stage_u_summary.json", {
        "hard_parity_failures": 0,
        "recommended_next_stage": "horizon_aware_validation_contract_after_parity",
    })
    write_csv(root / "stage_u_row_parity.csv", [
        {"region": "AA", "fold": 1, "parity_status": "pass", "spatial_information_set": "local_only", "n_active_regions": 1},
        {"region": "BB", "fold": 2, "parity_status": "warn", "spatial_information_set": "graph", "n_active_regions": 4},
    ])
    write_csv(root / "stage_u_horizon.csv", [
        {"region": "AA", "fold": 1, "worst_horizon_group": "49-72", "horizon_AQL_range": 8.0},
        {"region": "BB", "fold": 2, "worst_horizon_group": "73-96", "horizon_AQL_range": 2.0},
    ])
    write_json(root / "stage_v_summary.json", {
        "fits_models": False,
        "writes_launch_configs": False,
        "selection_uses_test_metrics_any": bad_stage_v,
    })
    method = "qdesn_exal_rhs_ns_exact_chunked"
    write_csv(root / "stage_v_candidates.csv", [
        candidate_row("AA", 1, "aa_low_val_bad_test", method, 5.0, 10.0, 9.0, 7.0),
        candidate_row("AA", 1, "aa_stable_better", method, 5.2, 8.0, 9.0, 7.0),
        candidate_row("BB", 2, "bb_good", method, 4.0, 8.5, 9.0, 7.0),
    ])
    write_csv(root / "stage_v_rule_audit.csv", [
        {"rule_id": "val_mean_min", "selection_uses_test_metrics": False},
    ])
    write_json(root / "stage_w_summary.json", {
        "run_clean": True,
        "stage_m_surface_changed": False,
        "priority1_recommended": False,
        "test_oracle_beats_pricefm": 0,
    })
    write_csv(root / "stage_w_qdesn.csv", [
        {
            "region": "AA",
            "fold": 1,
            "experiment_id": "aa_stagew",
            "method_id": method,
            "val_AQL": 4.0,
            "test_AQL": 9.5,
            "local_AQL": 9.0,
            "pricefm_AQL": 7.0,
            "candidate_family": "graph_information_conversion",
        }
    ])
    write_csv(root / "stage_w_transfer.csv", [
        {
            "region": "AA",
            "fold": 1,
            "validation_selected_test_AQL": 9.5,
            "test_oracle_test_AQL": 8.5,
            "test_regret_vs_oracle": 1.0,
            "validation_test_spearman": 0.1,
        }
    ])
    write_csv(root / "stage_w_oracle.csv", [
        {
            "region": "AA",
            "fold": 1,
            "test_AQL": 9.5,
            "delta_vs_current_AQL": 0.5,
            "delta_vs_pricefm_AQL": 2.5,
        }
    ])
    write_csv(root / "stage_w_horizon.csv", [
        {
            "region": "AA",
            "fold": 1,
            "horizon_group": "49-72",
            "validation_test_regret_vs_oracle": 1.5,
        }
    ])
    args = stage_x.parser().parse_args([
        "--stage-m-surface-csv", str(root / "stage_m.csv"),
        "--stage-u-summary-json", str(root / "stage_u_summary.json"),
        "--stage-u-row-parity-csv", str(root / "stage_u_row_parity.csv"),
        "--stage-u-horizon-csv", str(root / "stage_u_horizon.csv"),
        "--stage-v-summary-json", str(root / "stage_v_summary.json"),
        "--stage-v-candidate-universe-csv", str(root / "stage_v_candidates.csv"),
        "--stage-v-rule-audit-csv", str(root / "stage_v_rule_audit.csv"),
        "--stage-w-summary-json", str(root / "stage_w_summary.json"),
        "--stage-w-qdesn-metrics-csv", str(root / "stage_w_qdesn.csv"),
        "--stage-w-validation-transfer-csv", str(root / "stage_w_transfer.csv"),
        "--stage-w-test-oracle-csv", str(root / "stage_w_oracle.csv"),
        "--stage-w-horizon-gap-csv", str(root / "stage_w_horizon.csv"),
        "--output-dir", str(out),
        "--expected-stage-m-rows", "2",
    ])
    return args, out


def test_stage_x_outputs_validation_only_contract(tmp_path):
    args, out = make_fixture(tmp_path)
    summary = stage_x.design(args)
    assert summary["diagnostic_only"] is True
    assert summary["fits_models"] is False
    assert summary["writes_launch_configs"] is False
    assert summary["selection_uses_test_metrics_any"] is False
    assert summary["launch_new_fits_now"] is False

    rule_audit = pd.read_csv(out / "stage_x_selection_rule_audit.csv")
    failure = pd.read_csv(out / "stage_x_region_fold_failure_modes.csv")
    recommended = pd.read_csv(out / "stage_x_recommended_actions.csv")

    assert not rule_audit["selection_uses_test_metrics"].astype(bool).any()
    assert set(failure["primary_failure_mode"]).issuperset({"candidate_family_falsified", "pricefm_far_ahead"})
    assert recommended[recommended["action"].eq("launch_new_model_fits_now")]["decision"].iloc[0] == False
    assert (out / "stage_x_report.md").exists()


def test_stage_x_rejects_test_using_upstream_selection(tmp_path):
    args, _ = make_fixture(tmp_path, bad_stage_v=True)
    with pytest.raises(ValueError, match="selection rules"):
        stage_x.design(args)
