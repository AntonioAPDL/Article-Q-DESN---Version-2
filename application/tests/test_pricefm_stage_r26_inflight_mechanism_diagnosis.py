"""Tests for PriceFM Stage-R26 in-flight mechanism diagnosis."""

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


def manifest_row(exp_id: str, region: str, fold: int, arm: str, spec: str) -> dict:
    return {
        "experiment_id": exp_id,
        "region": region,
        "fold": fold,
        "priority": 0,
        "target_quantile": 0.5,
        "stage": "stage_r25_post_r24_broad_horizon_weighted_screening",
        "stage_r22b_case_id": f"r22b_{region.lower()}_f{fold}",
        "stage_r25_arm": arm,
        "stage_r25_arm_rationale": "unit",
        "pricefm_gap_tier": "near_gap_le_1",
        "horizon_focus": "1-24",
        "horizon_weighting_enabled": True,
        "horizon_weighting_mode": "integer_frequency_replication",
        "horizon_weight_multiplier": 3.0,
        "feature_policy": "graph_summary_mean_std",
        "implemented_feature_policy": True,
        "lag_window": 96,
        "depth": 2,
        "units": "[96, 64]",
        "feature_dim": 64,
        "state_output": "final_layer",
        "alpha": 0.35,
        "rho": 0.82,
        "input_scale": 0.3,
        "tau0": 0.001,
        "seed": 1,
        "graph_degree": 1,
        "selection_is_validation_only": True,
        "selection_rule": "validation_AQL_only_within_case",
        "test_metrics_role": "audit_only_after_frozen_validation_selection",
        "launch_authorized_by_user": True,
        "launcher_invoked_by_prep": False,
        "fits_models_when_launched": True,
        "mutates_registry": False,
        "mutates_manuscript": False,
        "requires_stage_r26_closeout_gate": True,
        "requires_postfit_calibration_gate": True,
        "requires_full_quantile_gate": True,
        "case_specific_spec_key": spec,
    }


def arm_plan_row(region: str, fold: int, arm: str, qdesn: float, pricefm: float, r22_gap: float) -> dict:
    return {
        "stage_r22b_case_id": f"r22b_{region.lower()}_f{fold}",
        "region": region,
        "fold": fold,
        "pricefm_gap_tier": "near_gap_le_1",
        "horizon_focus": "1-24",
        "current_qdesn_AQL": qdesn,
        "current_pricefm_AQL": pricefm,
        "validation_selected_minus_current_qdesn": 0.5,
        "validation_selected_minus_pricefm": r22_gap,
        "selected_stage_r22c_experiment_id": "r22c_unit",
        "selected_stage_r22c_screening_arm": "horizon_weighted_readout_loss",
        "stage_r25_arm": arm,
        "stage_r25_arm_ordinal": 1,
        "stage_r25_arm_rationale": "unit",
        "feature_policy": "graph_summary_mean_std",
        "lag_window": 96,
        "depth": 2,
        "units": "[96, 64]",
        "feature_dim": 64,
        "state_output": "final_layer",
        "alpha": 0.35,
        "rho": 0.82,
        "input_scale": 0.3,
        "tau0": 0.001,
        "horizon_weighting_enabled": True,
        "horizon_weighting_mode": "integer_frequency_replication",
        "horizon_weighting_scope": "horizon_group",
        "horizon_weight_multiplier": 3.0,
        "horizon_weight_integer_scale": 2,
        "horizon_weight_max_expansion_factor": 6,
        "stage_r25_selection_rule": "validation_AQL_only_within_case",
        "stage_r25_test_metrics_role": "audit_only_after_frozen_validation_selection",
        "mutates_registry": False,
        "mutates_manuscript": False,
        "requires_stage_r26_closeout_gate": True,
        "requires_postfit_calibration_gate": True,
        "requires_full_quantile_gate": True,
        "case_specific_spec_key": f"{region}_{fold}_{arm}",
    }


def metric_rows(val_exal: float, test_exal: float, val_al: float, test_al: float) -> list[dict]:
    rows = []
    for method, val, test in [
        ("qdesn_exal_rhs_ns_exact_chunked", val_exal, test_exal),
        ("qdesn_al_rhs_ns_exact_chunked", val_al, test_al),
        ("normal_rhs_ns", val_exal + 1.0, test_exal + 1.0),
        ("naive1_prev_day", val_exal + 2.0, test_exal + 2.0),
    ]:
        for split, aql in [("val", val), ("test", test)]:
            rows.append(
                {
                    "method_id": method,
                    "split": split,
                    "unit": "original",
                    "AQL": aql,
                    "AQCR": 0.0,
                    "MAE": 2.0 * aql,
                    "RMSE": 3.0 * aql,
                }
            )
    return rows


def horizon_rows(method: str, aql: float) -> list[dict]:
    rows = []
    for horizon in ["1-24", "25-48"]:
        for mid, value in [
            (method, aql),
            ("normal_rhs_ns", aql + 0.5),
            ("naive1_prev_day", aql + 1.0),
        ]:
            rows.append(
                {
                    "method_id": mid,
                    "split": "test",
                    "unit": "original",
                    "horizon_group": horizon,
                    "AQL": value,
                    "AQCR": 0.0,
                    "MAE": 2.0 * value,
                    "RMSE": 3.0 * value,
                }
            )
    return rows


def make_fixture(tmp_path: Path):
    r21 = tmp_path / "r21"
    r22d = tmp_path / "r22d"
    r23 = tmp_path / "r23"
    r24 = tmp_path / "r24"
    prep = tmp_path / "prep"
    grid = tmp_path / "grid"
    run = tmp_path / "runs"
    logs = tmp_path / "logs"
    out = tmp_path / "out"
    manifest = [
        manifest_row("r25_no4_f1_base", "NO_4", 1, "true_weight_base", "base"),
        manifest_row("r25_no4_f1_alt", "NO_4", 1, "alt_information_set_weighted", "alt"),
        manifest_row("r25_no4_f1_pending", "NO_4", 1, "long_lag_weighted", "pending"),
    ]
    write_csv(prep / "pricefm_stage_r25_launch_manifest.csv", manifest)
    write_csv(
        prep / "pricefm_stage_r25_arm_plan.csv",
        [
            arm_plan_row("NO_4", 1, "true_weight_base", qdesn=2.0, pricefm=1.5, r22_gap=0.9),
            arm_plan_row("NO_4", 1, "alt_information_set_weighted", qdesn=2.0, pricefm=1.5, r22_gap=0.9),
            arm_plan_row("NO_4", 1, "long_lag_weighted", qdesn=2.0, pricefm=1.5, r22_gap=0.9),
        ],
    )
    write_csv(prep / "pricefm_stage_r25_case_plan.csv", [{"stage_r22b_case_id": "r22b_no_4_f1", "region": "NO_4", "fold": 1}])
    write_json(prep / "summary.json", {"stage": "pricefm_stage_r25_post_r24_broad_launch_prep", "grid_id": "unit_r25"})
    write_csv(
        r21 / "pricefm_stage_r21_failure_atlas.csv",
        [
            {
                "region": "NO_4",
                "fold": 1,
                "stage_r21_primary_failure_pattern": "horizon_localized_loss",
                "stage_r21_recommended_mechanism": "horizon_aware_loss_readout_calibration",
                "failure_mode": "validation_selection_penalty",
                "worst_horizon_group_r21": "1-24",
                "early_1_24_delta_AQL_qdesn_minus_pricefm": 0.4,
                "best_overall_gap_bucket": "near_gap",
            }
        ],
    )
    write_csv(
        r22d / "pricefm_stage_r22d_case_summary.csv",
        [
            {
                "stage_r22b_case_id": "r22b_no_4_f1",
                "region": "NO_4",
                "fold": 1,
                "validation_selected_minus_pricefm": 0.9,
                "test_oracle_minus_pricefm": 0.8,
                "validation_selected_beats_both": False,
                "test_oracle_beats_both": False,
            }
        ],
    )
    write_csv(r22d / "pricefm_stage_r22d_metric_rows.csv", [{"region": "NO_4", "fold": 1}])
    write_csv(r22d / "pricefm_stage_r22d_horizon_group_diagnostics.csv", [{"region": "NO_4", "fold": 1}])
    write_csv(
        r23 / "pricefm_stage_r23_case_next_mechanism_queue.csv",
        [
            {
                "stage_r22b_case_id": "r22b_no_4_f1",
                "region": "NO_4",
                "fold": 1,
                "recommended_stage_r23_queue": "true_weighted_loss_or_horizon_specific_readout_after_runner_support",
                "expensive_launch_readiness": "ready_after_r24",
                "ready_postfit_candidates": 0,
                "blocked_postfit_candidates": 1,
            }
        ],
    )
    write_csv(r23 / "pricefm_stage_r23_runner_capability_matrix.csv", [{"mechanism": "horizon_weighting", "effective_status": "ready"}])
    write_csv(r23 / "pricefm_stage_r23_expensive_path_bounds_recommendation.csv", [{"axis_group": "reservoir_size"}])
    write_csv(r24 / "pricefm_stage_r24_postfit_readiness.csv", [{"readiness_status": "blocked_missing_prediction_paths"}])
    write_csv(r24 / "pricefm_stage_r24_postfit_candidate_gate.csv", [{"gate": "unit", "passed": True}])
    for exp_id, vals in {
        "r25_no4_f1_base": (1.2, 1.9, 1.3, 2.1),
        "r25_no4_f1_alt": (1.0, 1.7, 1.4, 1.85),
    }.items():
        exp = run / exp_id
        write_csv(
            exp / "cell_status.csv",
            [{"region": "NO_4", "fold": 1, "status": "completed", "elapsed_seconds": 10, "message": "ok"}],
        )
        model = exp / "cells" / "region=NO_4" / "fold=1" / "model"
        write_csv(model / "metric_summary.csv", metric_rows(*vals))
        write_csv(model / "metric_by_horizon_group.csv", horizon_rows("qdesn_exal_rhs_ns_exact_chunked", vals[1]))
        write_csv(model / "training_weight_summary.csv", [{"enabled": True, "mode": "integer_frequency_replication"}])
    grid.mkdir(parents=True)
    logs.mkdir(parents=True)
    return r21, r22d, r23, r24, prep, grid, run, logs, out


def parse_args(mod, fixture):
    r21, r22d, r23, r24, prep, grid, run, logs, out = fixture
    return mod.parser().parse_args(
        [
            "--stage-r21-dir",
            str(r21),
            "--stage-r22d-dir",
            str(r22d),
            "--stage-r23-dir",
            str(r23),
            "--stage-r24-dir",
            str(r24),
            "--stage-r25-prep-dir",
            str(prep),
            "--stage-r25-grid-root",
            str(grid),
            "--stage-r25-run-root",
            str(run),
            "--stage-r25-log-root",
            str(logs),
            "--run-tag",
            "unit_r25",
            "--output-dir",
            str(out),
            "--expected-experiments",
            "3",
            "--expected-cases",
            "1",
            "--force",
            "true",
        ]
    )


def test_stage_r26_inflight_diagnosis_keeps_internal_improvement_out_of_mcmc_gate(tmp_path):
    fixture = make_fixture(tmp_path)
    mod = load_script("150_audit_pricefm_stage_r26_inflight_mechanism_diagnosis.py")
    summary = mod.run(parse_args(mod, fixture))
    out = fixture[-1]

    assert summary["status"] == "completed_read_only_inflight_diagnosis"
    assert summary["r25_run_state"] == "still_running_or_waiting_for_exit"
    assert summary["n_completed_experiments"] == 2
    assert summary["n_remaining_experiments"] == 1
    assert summary["n_rows_beating_current_qdesn"] == 3
    assert summary["n_rows_beating_pricefm"] == 0
    assert summary["n_rows_beating_both"] == 0
    assert summary["n_mcmc_gate_rows"] == 0

    failure = pd.read_csv(out / "pricefm_stage_r26_failure_decomposition_map.csv")
    assert failure.iloc[0]["partial_diagnosis"] == "internal_qdesn_improvement_but_pricefm_gap_remains"
    assert failure.iloc[0]["registry_article_gate_status"] == "blocked_no_beat_both_candidate"
    assert (out / "pricefm_stage_r26_inflight_mechanism_diagnosis_report.md").exists()


def test_stage_r26_refuses_registry_mutating_manifest(tmp_path):
    fixture = make_fixture(tmp_path)
    prep = fixture[4]
    manifest = pd.read_csv(prep / "pricefm_stage_r25_launch_manifest.csv")
    manifest.loc[0, "mutates_registry"] = True
    manifest.to_csv(prep / "pricefm_stage_r25_launch_manifest.csv", index=False)
    mod = load_script("150_audit_pricefm_stage_r26_inflight_mechanism_diagnosis.py")

    try:
        mod.run(parse_args(mod, fixture))
    except RuntimeError as exc:
        assert "registry_manuscript_blocked" in str(exc)
    else:
        raise AssertionError("expected registry mutation gate failure")


def test_stage_r26_completed_run_path_accepts_exit_zero(tmp_path):
    fixture = make_fixture(tmp_path)
    run = fixture[6]
    logs = fixture[7]
    exp = run / "r25_no4_f1_pending"
    write_csv(
        exp / "cell_status.csv",
        [{"region": "NO_4", "fold": 1, "status": "completed", "elapsed_seconds": 10, "message": "ok"}],
    )
    model = exp / "cells" / "region=NO_4" / "fold=1" / "model"
    write_csv(model / "metric_summary.csv", metric_rows(1.5, 1.95, 1.6, 2.05))
    write_csv(model / "metric_by_horizon_group.csv", horizon_rows("qdesn_exal_rhs_ns_exact_chunked", 1.95))
    write_csv(model / "training_weight_summary.csv", [{"enabled": True, "mode": "integer_frequency_replication"}])
    write_json(fixture[5] / "launch_summary.json", {"dry_run": False, "n_selected_experiments": 3})
    (logs / "unit_r25.exit").write_text("0\n")

    mod = load_script("150_audit_pricefm_stage_r26_inflight_mechanism_diagnosis.py")
    summary = mod.run(parse_args(mod, fixture))

    assert summary["r25_run_state"] == "completed_cleanly"
    assert summary["n_completed_experiments"] == 3
    assert summary["n_remaining_experiments"] == 0
