"""Tests for Stage-Q PriceFM near-miss refinement closeout."""

from pathlib import Path
import importlib.util
import sys

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


stage_q_closeout = load_script("77_closeout_pricefm_stage_q_nearmiss_refinement.py")


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def metric_rows(q_val, q_test, normal_test=11.0, naive_test=13.0):
    return [
        {
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "split": "val",
            "unit": "original",
            "AQL": q_val,
            "AQCR": 0.0,
            "MAE": 2.0 * q_val,
            "RMSE": 3.0 * q_val,
        },
        {
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "split": "test",
            "unit": "original",
            "AQL": q_test,
            "AQCR": 0.0,
            "MAE": 2.0 * q_test,
            "RMSE": 3.0 * q_test,
        },
        {
            "method_id": "normal_rhs_ns",
            "split": "val",
            "unit": "original",
            "AQL": normal_test,
            "AQCR": 0.0,
            "MAE": 2.0 * normal_test,
            "RMSE": 3.0 * normal_test,
        },
        {
            "method_id": "normal_rhs_ns",
            "split": "test",
            "unit": "original",
            "AQL": normal_test,
            "AQCR": 0.0,
            "MAE": 2.0 * normal_test,
            "RMSE": 3.0 * normal_test,
        },
        {
            "method_id": "naive1_prev_day",
            "split": "val",
            "unit": "original",
            "AQL": naive_test,
            "AQCR": 0.0,
            "MAE": 2.0 * naive_test,
            "RMSE": 3.0 * naive_test,
        },
        {
            "method_id": "naive1_prev_day",
            "split": "test",
            "unit": "original",
            "AQL": naive_test,
            "AQCR": 0.0,
            "MAE": 2.0 * naive_test,
            "RMSE": 3.0 * naive_test,
        },
    ]


def write_cell(run_root, exp_id, region, fold, q_val, q_test):
    model = run_root / exp_id / "cells" / f"region={region}" / f"fold={fold}" / "model"
    write_csv(model / "metric_summary.csv", metric_rows(q_val, q_test))
    write_csv(
        model / "metric_by_horizon_group.csv",
        [
            {
                "method_id": "qdesn_exal_rhs_ns_exact_chunked",
                "split": "test",
                "unit": "original",
                "horizon_group": "1-24",
                "AQL": q_test - 0.2,
                "AQCR": 0.0,
                "MAE": 2.0 * (q_test - 0.2),
                "RMSE": 3.0 * (q_test - 0.2),
            },
            {
                "method_id": "qdesn_exal_rhs_ns_exact_chunked",
                "split": "test",
                "unit": "original",
                "horizon_group": "25-96",
                "AQL": q_test + 0.2,
                "AQCR": 0.0,
                "MAE": 2.0 * (q_test + 0.2),
                "RMSE": 3.0 * (q_test + 0.2),
            },
        ],
    )
    write_csv(
        model / "metric_by_horizon.csv",
        [
            {
                "method_id": "qdesn_exal_rhs_ns_exact_chunked",
                "split": "test",
                "unit": "original",
                "horizon": 1,
                "AQL": q_test,
                "AQCR": 0.0,
                "MAE": 2.0 * q_test,
                "RMSE": 3.0 * q_test,
            }
        ],
    )
    log_dir = run_root / exp_id / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    (log_dir / "cell.log").write_text("completed cleanly\n")


def test_stage_q_closeout_separates_validation_and_test_oracle(tmp_path):
    plan = tmp_path / "plan"
    grid = tmp_path / "grid"
    run = tmp_path / "runs"
    out = tmp_path / "out"

    manifest = [
        {
            "region": "NL",
            "fold": 3,
            "experiment_id": "exp_val",
            "priority": 0,
            "stage_q_decision": "near_miss_refine",
            "candidate_family": "alpha",
            "factor_changed": "alpha",
            "lag_window": 96,
            "units": "[120]",
            "alpha": 0.25,
            "rho": 0.9,
            "input_scale": 0.2,
            "graph_degree": 1,
            "stage_p_AQL": 6.5,
            "pricefm_AQL": 6.4,
            "stage_p_delta_abs": 0.1,
        },
        {
            "region": "NL",
            "fold": 3,
            "experiment_id": "exp_test",
            "priority": 0,
            "stage_q_decision": "near_miss_refine",
            "candidate_family": "rho",
            "factor_changed": "rho",
            "lag_window": 96,
            "units": "[120]",
            "alpha": 0.35,
            "rho": 0.75,
            "input_scale": 0.2,
            "graph_degree": 1,
            "stage_p_AQL": 6.5,
            "pricefm_AQL": 6.4,
            "stage_p_delta_abs": 0.1,
        },
    ]
    decisions = [
        {
            "region": "NL",
            "fold": 3,
            "AQL": 6.5,
            "pricefm_phase1_AQL": 6.4,
            "selection_AQL": 6.8,
            "stage_q_decision": "near_miss_refine",
            "stage_q_priority": 0,
            "stage_q_action": "launch_stage_q_priority0_median_refinement",
            "experiment_id": "stagep",
            "stage_p_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "decision_label": "local_close_to_pricefm",
        }
    ]
    launch = [
        {
            "id": "exp_val",
            "kind": "experiment",
            "priority": 0,
            "stage": "stage_q_nearmiss_median_refinement",
            "status": "completed",
            "return_code": 0,
        },
        {
            "id": "exp_test",
            "kind": "experiment",
            "priority": 0,
            "stage": "stage_q_nearmiss_median_refinement",
            "status": "completed",
            "return_code": 0,
        },
    ]
    write_csv(plan / "stage_q_median_refinement_manifest.csv", manifest)
    write_csv(plan / "stage_q_stage_p_closeout_decisions.csv", decisions)
    write_csv(grid / "launch_status.csv", launch)
    write_cell(run, "exp_val", "NL", 3, q_val=6.7, q_test=8.1)
    write_cell(run, "exp_test", "NL", 3, q_val=7.2, q_test=7.0)

    args = stage_q_closeout.parser().parse_args([
        "--plan-dir", str(plan),
        "--run-root", str(run),
        "--grid-root", str(grid),
        "--output-dir", str(out),
        "--scan-logs", "true",
    ])
    summary = stage_q_closeout.closeout(args)

    assert summary["run_clean"] is True
    assert summary["no_stage_q_promotions_recommended"] is True
    assert summary["stage_m_surface_changed"] is False

    closeout = pd.read_csv(out / "stage_q_priority0_closeout_summary.csv")
    assert closeout.loc[0, "experiment_id"] == "exp_val"
    assert closeout.loc[0, "oracle_experiment_id"] == "exp_test"
    assert closeout.loc[0, "closeout_decision"] == "do_not_promote_stage_q"
    assert closeout.loc[0, "validation_selected_test_regret"] > 0

    transfer = pd.read_csv(out / "stage_q_selection_transfer_diagnostics.csv")
    assert transfer.loc[0, "same_candidate"] == False
    assert abs(transfer.loc[0, "validation_selected_test_regret"] - 1.1) < 1.0e-12

    horizon = pd.read_csv(out / "stage_q_selected_horizon_group_diagnostics.csv")
    assert set(horizon["selection_view"]) == {"validation_selected", "test_oracle_audit_only"}

    health = pd.read_csv(out / "stage_q_priority0_health.csv")
    assert bool(health.loc[0, "run_clean"]) is True
    assert int(health.loc[0, "binary_fit_artifacts"]) == 0
