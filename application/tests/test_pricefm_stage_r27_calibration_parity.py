"""Tests for PriceFM Stage-R27 calibration/parity audit."""

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


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def truth_rows(split: str, y_scaled: float = 0.0) -> list[dict]:
    return [
        {"split": split, "origin_id": 0, "horizon": 1, "y_scaled": y_scaled},
        {"split": split, "origin_id": 0, "horizon": 2, "y_scaled": y_scaled},
        {"split": split, "origin_id": 1, "horizon": 1, "y_scaled": y_scaled},
        {"split": split, "origin_id": 1, "horizon": 2, "y_scaled": y_scaled},
    ]


def prediction_rows(method: str, split: str, pred: float) -> list[dict]:
    return [
        {"method_id": method, "split": split, "origin_id": 0, "horizon": 1, "tau": 0.5, "pred_scaled": pred},
        {"method_id": method, "split": split, "origin_id": 0, "horizon": 2, "tau": 0.5, "pred_scaled": pred},
        {"method_id": method, "split": split, "origin_id": 1, "horizon": 1, "tau": 0.5, "pred_scaled": pred},
        {"method_id": method, "split": split, "origin_id": 1, "horizon": 2, "tau": 0.5, "pred_scaled": pred},
    ]


def metric_row(root: Path, exp: str, method: str, val_aql: float, test_aql: float, qdesn: float, pricefm: float) -> dict:
    model = root / "runs" / exp / "cells" / "region=NO_4" / "fold=1" / "model"
    return {
        "experiment_id": exp,
        "region": "NO_4",
        "fold": 1,
        "stage_r25_arm": "alt_information_set_weighted",
        "method_id": method,
        "val_AQL": val_aql,
        "test_AQL": test_aql,
        "current_qdesn_AQL": qdesn,
        "current_pricefm_AQL": pricefm,
        "test_minus_current_qdesn": test_aql - qdesn,
        "test_minus_pricefm": test_aql - pricefm,
        "feature_policy": "target_only",
        "horizon_focus": "1-24",
        "horizon_weight_multiplier": 2.0,
        "lag_window": 96,
        "depth": 1,
        "units": "[8]",
        "feature_dim": 8,
        "state_output": "final_layer",
        "alpha": 0.4,
        "rho": 0.8,
        "input_scale": 0.3,
        "tau0": 0.001,
        "metric_summary": str(model / "metric_summary.csv"),
    }


def make_fixture(tmp_path: Path, calibratable: bool = True):
    closeout = tmp_path / "closeout"
    prep = tmp_path / "prep"
    out = tmp_path / "out"
    method = "qdesn_al_rhs_ns_exact_chunked"
    qdesn = 0.2
    pricefm = 0.1
    pred = 1.0 if calibratable else 0.2
    test_y = 0.0 if calibratable else 1.0
    uncal_val_aql = 0.5 * abs(pred)
    uncal_test_aql = 0.5 * abs(test_y - pred)
    rows = [
        metric_row(tmp_path, "exp1", method, uncal_val_aql, uncal_test_aql, qdesn, pricefm),
        metric_row(tmp_path, "exp2", method, 0.4, 0.4, qdesn, pricefm),
    ]
    write_json(closeout / "summary.json", {"status": "completed_negative_no_promotions"})
    write_csv(closeout / "pricefm_stage_r26_final_metric_rows.csv", rows)
    write_csv(closeout / "pricefm_stage_r26_final_validation_selected_case.csv", [rows[0]])
    write_csv(closeout / "pricefm_stage_r26_final_test_oracle_case.csv", [rows[0]])
    write_csv(prep / "pricefm_stage_r25_launch_manifest.csv", [{"experiment_id": "exp1"}, {"experiment_id": "exp2"}])

    for exp, p in [("exp1", pred), ("exp2", 0.8)]:
        cell = tmp_path / "runs" / exp / "cells" / "region=NO_4" / "fold=1"
        model = cell / "model"
        adapter = cell / "adapter"
        write_csv(model / "metric_summary.csv", [{"method_id": method, "split": "test", "unit": "scaled", "AQL": 0.5 * abs(p)}])
        preds = prediction_rows(method, "val", p) + prediction_rows(method, "test", p)
        write_csv(model / "model_predictions_scaled.csv", preds)
        write_csv(model / "predictions_with_naive_scaled.csv", preds)
        write_csv(model / "model_method_summary.csv", [{"method_id": method, "converged": True}])
        write_csv(model / "model_parameter_summary.csv", [{"method_id": method, "tau": 0.5}])
        write_csv(adapter / "rows_val.csv", truth_rows("val", 0.0))
        write_csv(adapter / "rows_test.csv", truth_rows("test", test_y if exp == "exp1" else 0.0))
        write_json(adapter / "adapter_manifest.json", {"ok": True})
        write_json(
            adapter / "feature_manifest.json",
            {
                "feature_policy": "target_only",
                "feature_dim": 8,
                "feature_names": ["intercept", "x1"],
                "feature_policy_manifest": {
                    "input_scope": "local_target_only",
                    "output_scope": "target_region_path",
                    "spatial_information_set": "local_only_not_pricefm_graph",
                    "lead_covariate_status": "realized_ex_post",
                    "graph": None,
                },
            },
        )
    return closeout, prep, out


def parse_args(mod, fixture):
    closeout, prep, out = fixture
    return mod.parser().parse_args(
        [
            "--stage-r26-closeout-dir",
            str(closeout),
            "--stage-r25-prep-dir",
            str(prep),
            "--output-dir",
            str(out),
            "--expected-candidate-rows",
            "2",
            "--primary-unit",
            "scaled",
            "--force",
            "true",
        ]
    )


def test_stage_r27_validation_only_calibration_can_open_beat_both_audit_gate(tmp_path):
    fixture = make_fixture(tmp_path, calibratable=True)
    mod = load_script("152_audit_pricefm_stage_r27_calibration_parity.py")
    summary = mod.run(parse_args(mod, fixture))
    out = fixture[-1]

    assert summary["n_candidate_rows"] == 2
    assert summary["n_r26_selected_calibrated_beat_both"] == 1
    assert summary["n_full_surface_calibrated_beat_both"] == 1
    assert summary["baseline_replay_max_abs_AQL_diff"] <= 1.0e-8

    params = pd.read_csv(out / "pricefm_stage_r27_calibration_params.csv")
    case = pd.read_csv(out / "pricefm_stage_r27_case_calibration_selection.csv")
    gates = pd.read_csv(out / "pricefm_stage_r27_no_launch_gates.csv")
    assert params["uses_validation_only"].all()
    assert not params["uses_test_for_calibration"].any()
    assert gates["passed"].all()
    r26 = case[case["selection_scope"].eq("r26_selected_only_calibrated")]
    assert r26.iloc[0]["beats_both_on_test"]
    assert r26.iloc[0]["promotion_gate_status"] == "candidate_pending_full_quantile_mcmc_reproducibility_confirmation"


def test_stage_r27_negative_calibration_keeps_mcmc_and_article_blocked(tmp_path):
    fixture = make_fixture(tmp_path, calibratable=False)
    mod = load_script("152_audit_pricefm_stage_r27_calibration_parity.py")
    summary = mod.run(parse_args(mod, fixture))
    out = fixture[-1]

    assert summary["n_r26_selected_calibrated_beat_both"] == 0
    assert summary["n_full_surface_calibrated_beat_both"] == 0

    plan = pd.read_csv(out / "pricefm_stage_r27_next_action_plan.csv")
    assert plan.loc[plan["action"].eq("keep_mcmc_registry_article_blocked"), "allowed_next"].iloc[0] == False
    assert plan.loc[plan["action"].eq("if_no_calibrated_beat_both_pivot_to_objective_or_model_family"), "allowed_next"].iloc[0] == True


def test_stage_r27_refuses_missing_prediction_artifact(tmp_path):
    fixture = make_fixture(tmp_path, calibratable=True)
    missing = tmp_path / "runs" / "exp2" / "cells" / "region=NO_4" / "fold=1" / "model" / "model_predictions_scaled.csv"
    missing.unlink()
    mod = load_script("152_audit_pricefm_stage_r27_calibration_parity.py")

    try:
        mod.run(parse_args(mod, fixture))
    except RuntimeError as exc:
        assert "all_artifacts_ready" in str(exc)
    else:
        raise AssertionError("expected missing prediction artifact to fail Stage-R27 gates")
