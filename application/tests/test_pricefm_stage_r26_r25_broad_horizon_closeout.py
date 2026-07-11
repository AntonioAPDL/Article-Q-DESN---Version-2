"""Tests for PriceFM Stage-R26 final closeout over completed Stage-R25."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pandas as pd


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


def write_csv(path: Path, rows: list[dict], columns: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows, columns=columns).to_csv(path, index=False)


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def method_row(exp_id: str, method: str, val: float, test: float, qdesn: float, pricefm: float) -> dict:
    q_gap = test - qdesn
    p_gap = test - pricefm
    return {
        "experiment_id": exp_id,
        "region": "NO_4",
        "fold": 1,
        "stage_r25_arm": "alt_information_set_weighted",
        "method_id": method,
        "val_AQL": val,
        "val_MAE": 2 * val,
        "val_RMSE": 3 * val,
        "test_AQL": test,
        "test_MAE": 2 * test,
        "test_RMSE": 3 * test,
        "current_qdesn_AQL": qdesn,
        "current_pricefm_AQL": pricefm,
        "r22d_validation_selected_minus_pricefm": 0.6,
        "test_minus_current_qdesn": q_gap,
        "test_minus_pricefm": p_gap,
        "test_minus_r22d_validation_selected": p_gap - 0.6,
        "beats_current_qdesn_on_test": q_gap < 0,
        "beats_pricefm_on_test": p_gap < 0,
        "beats_both_on_test": q_gap < 0 and p_gap < 0,
        "improves_over_r22d_validation_selected": p_gap < 0.6,
        "metric_summary": f"runs/{exp_id}/metric_summary.csv",
    }


def make_fixture(tmp_path: Path, selected_beats_both: bool = False):
    diag = tmp_path / "diag"
    grid = tmp_path / "grid"
    runs = tmp_path / "runs"
    logs = tmp_path / "logs"
    out = tmp_path / "out"

    qdesn = 2.0 if not selected_beats_both else 1.1
    pricefm = 1.5 if not selected_beats_both else 1.0
    selected_test = 1.7 if not selected_beats_both else 0.9
    rows = [
        method_row("exp1", "qdesn_al_rhs_ns_exact_chunked", 1.0, selected_test, qdesn, pricefm),
        method_row("exp1", "qdesn_exal_rhs_ns_exact_chunked", 1.2, selected_test + 0.1, qdesn, pricefm),
        method_row("exp2", "qdesn_al_rhs_ns_exact_chunked", 1.4, 1.8, qdesn, pricefm),
        method_row("exp2", "qdesn_exal_rhs_ns_exact_chunked", 1.5, 1.9, qdesn, pricefm),
    ]
    selected = [rows[0] | {"case_selected_by": "validation_AQL_only_across_completed_stage_r25_candidates"}]
    oracle = [rows[0] | {"case_oracle_by": "test_AQL_audit_only_across_completed_stage_r25_candidates"}]

    write_json(
        diag / "summary.json",
        {
            "stage": "pricefm_stage_r26_inflight_mechanism_diagnosis",
            "r25_run_state": "completed_cleanly",
            "n_completed_experiments": 2,
            "n_metric_rows": 4,
        },
    )
    write_csv(diag / "pricefm_stage_r26_r25_health.csv", [{"check": "r25_run_state", "value": "completed_cleanly"}])
    write_csv(
        diag / "pricefm_stage_r26_case_progress.csv",
        [{"region": "NO_4", "fold": 1, "planned_experiments": 2, "started_experiments": 2, "completed_experiments": 2, "remaining_experiments": 0, "case_status": "complete"}],
    )
    write_csv(diag / "pricefm_stage_r26_partial_metric_rows.csv", rows)
    write_csv(diag / "pricefm_stage_r26_partial_validation_selected_case.csv", selected)
    write_csv(diag / "pricefm_stage_r26_partial_test_oracle_case.csv", oracle)
    write_csv(
        diag / "pricefm_stage_r26_arm_mechanism_summary.csv",
        [{"stage_r25_arm": "alt_information_set_weighted", "best_test_minus_pricefm": selected[0]["test_minus_pricefm"], "beats_pricefm": int(selected_beats_both), "beats_both": int(selected_beats_both)}],
    )
    write_csv(
        diag / "pricefm_stage_r26_horizon_mechanism_summary.csv",
        [{"horizon_group": "1-24", "cases": 1, "beats_best_naive": 1, "beats_best_normal": 1}],
    )
    write_csv(
        diag / "pricefm_stage_r26_failure_decomposition_map.csv",
        [{"region": "NO_4", "fold": 1, "partial_diagnosis": "promotion_candidate" if selected_beats_both else "internal_qdesn_improvement_but_pricefm_gap_remains"}],
    )
    write_csv(diag / "pricefm_stage_r26_diagnosis_gates.csv", [{"gate": "unit", "passed": True, "detail": "ok"}])
    write_csv(
        diag / "source_manifest.csv",
        [],
        columns=["label", "kind", "path", "exists", "size_bytes", "sha256"],
    )

    write_json(grid / "grid_summary.json", {"grid_id": "unit", "n_experiments": 2})
    write_json(grid / "launch_summary.json", {"grid_id": "unit", "n_selected_experiments": 2, "dry_run": False})
    write_csv(
        grid / "launch_status.csv",
        [
            {"id": "exp1", "kind": "experiment", "status": "completed", "return_code": 0},
            {"id": "exp2", "kind": "experiment", "status": "completed", "return_code": 0},
            {"id": "window1", "kind": "window_build", "status": "completed", "return_code": 0},
        ],
    )
    logs.mkdir(parents=True)
    (logs / "unit.exit").write_text("0\n")
    (logs / "unit.time.log").write_text("Elapsed (wall clock) time (h:mm:ss or m:ss): 00:01:00\n")

    for exp in ["exp1", "exp2"]:
        model = runs / exp / "cells" / "region=NO_4" / "fold=1" / "model"
        write_csv(model / "metric_summary.csv", [{"method_id": "qdesn_al_rhs_ns_exact_chunked", "split": "test", "unit": "original", "AQL": 1.0}])
        write_csv(model / "metric_by_horizon_group.csv", [{"method_id": "qdesn_al_rhs_ns_exact_chunked", "split": "test", "unit": "original", "horizon_group": "1-24", "AQL": 1.0}])
        write_csv(model / "training_weight_summary.csv", [{"enabled": True}])
        write_csv(model / "model_predictions_scaled.csv", [{"method_id": "qdesn_al_rhs_ns_exact_chunked", "split": "val", "origin_id": "o1", "horizon": 1, "tau": 0.5, "pred_scaled": 0.0}])
        write_csv(model / "predictions_with_naive_scaled.csv", [{"method_id": "naive1_prev_day", "split": "val", "origin_id": "o1", "horizon": 1, "tau": 0.5, "pred_scaled": 0.0}])
        write_csv(runs / exp / "cell_status.csv", [{"status": "completed", "elapsed_seconds": 1}])

    return diag, grid, runs, logs, out


def parse_args(mod, fixture):
    diag, grid, runs, logs, out = fixture
    return mod.parser().parse_args(
        [
            "--stage-r26-diagnosis-dir",
            str(diag),
            "--stage-r25-grid-root",
            str(grid),
            "--stage-r25-run-root",
            str(runs),
            "--stage-r25-log-root",
            str(logs),
            "--run-tag",
            "unit",
            "--output-dir",
            str(out),
            "--expected-experiments",
            "2",
            "--expected-cases",
            "1",
            "--expected-window-builds",
            "1",
            "--expected-method-rows",
            "4",
            "--force",
            "true",
        ]
    )


def test_final_closeout_blocks_negative_r25_from_promotion_and_plans_r27(tmp_path):
    fixture = make_fixture(tmp_path, selected_beats_both=False)
    mod = load_script("151_closeout_pricefm_stage_r26_r25_broad_horizon.py")
    summary = mod.run(parse_args(mod, fixture))
    out = fixture[-1]

    assert summary["status"] == "completed_negative_no_promotions"
    assert summary["r25_run_state"] == "completed_cleanly"
    assert summary["n_promotion_queue_rows"] == 0
    assert summary["n_mcmc_gate_rows"] == 0
    assert summary["n_model_prediction_files"] == 2

    promotions = pd.read_csv(out / "pricefm_stage_r26_final_full_quantile_promotion_queue.csv")
    mcmc = pd.read_csv(out / "pricefm_stage_r26_final_mcmc_confirmation_gate.csv")
    plan = pd.read_csv(out / "pricefm_stage_r26_r27_pivot_plan.csv")
    gates = pd.read_csv(out / "pricefm_stage_r26_final_closeout_gates.csv")

    assert promotions.empty
    assert mcmc.empty
    assert "stage_r27_prediction_artifact_calibration_audit" in set(plan["stage"])
    assert "mcmc_confirmation_hold" in set(plan["stage"])
    assert gates["passed"].all()
    assert (out / "pricefm_stage_r26_r25_broad_horizon_final_closeout_report.md").exists()


def test_final_closeout_opens_queue_only_for_validation_selected_beat_both(tmp_path):
    fixture = make_fixture(tmp_path, selected_beats_both=True)
    mod = load_script("151_closeout_pricefm_stage_r26_r25_broad_horizon.py")
    summary = mod.run(parse_args(mod, fixture))
    out = fixture[-1]

    assert summary["status"] == "completed_with_promotion_candidates_pending_confirmation"
    assert summary["n_promotion_queue_rows"] == 1
    assert summary["n_mcmc_gate_rows"] == 1

    promotions = pd.read_csv(out / "pricefm_stage_r26_final_full_quantile_promotion_queue.csv")
    mcmc = pd.read_csv(out / "pricefm_stage_r26_final_mcmc_confirmation_gate.csv")
    assert promotions.iloc[0]["test_minus_current_qdesn"] < 0
    assert promotions.iloc[0]["test_minus_pricefm"] < 0
    assert mcmc.iloc[0]["mcmc_gate_status"] == "blocked_until_full_quantile_confirmation_design"


def test_final_closeout_fails_when_completion_artifact_missing(tmp_path):
    fixture = make_fixture(tmp_path, selected_beats_both=False)
    runs = fixture[2]
    (runs / "exp2" / "cells" / "region=NO_4" / "fold=1" / "model" / "model_predictions_scaled.csv").unlink()
    mod = load_script("151_closeout_pricefm_stage_r26_r25_broad_horizon.py")

    try:
        mod.run(parse_args(mod, fixture))
    except RuntimeError as exc:
        assert "r25_completion_checks_passed" in str(exc)
    else:
        raise AssertionError("expected missing prediction artifact to fail final closeout")
