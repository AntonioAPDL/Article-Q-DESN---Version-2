"""Tests for the PriceFM Stage-R35 read-only failure decomposition."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application" / "scripts" / "pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


def load_script():
    path = SCRIPT_DIR / "160_audit_pricefm_stage_r35_failure_decomposition.py"
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def write_csv(path: Path, rows, columns=None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows, columns=columns).to_csv(path, index=False)


def make_model_artifacts(root: Path, experiment_id: str, region: str, fold: int, method: str, bias: float) -> Path:
    model = root / experiment_id / "cells" / f"region={region}" / f"fold={fold}" / "model"
    adapter = model.parent / "adapter"
    model.mkdir(parents=True, exist_ok=True)
    write_csv(
        model / "metric_summary.csv",
        [{"method_id": method, "split": "test", "unit": "original", "AQL": 1.0}],
    )
    horizon_rows = []
    for group_index, group in enumerate(["1-24", "25-48", "49-72", "73-96"]):
        horizon_rows.extend(
            [
                {"method_id": method, "split": "val", "unit": "original", "horizon_group": group, "AQL": 1.0 + group_index * 0.1},
                {"method_id": method, "split": "test", "unit": "original", "horizon_group": group, "AQL": 1.2 + group_index * 0.1},
            ]
        )
    write_csv(model / "metric_by_horizon_group.csv", horizon_rows)
    prediction_rows = []
    for split in ["val", "test"]:
        truth_rows = []
        for origin in range(3):
            for horizon in [1, 25, 49, 73]:
                y = origin * 0.1 + horizon * 0.001
                truth_rows.append(
                    {
                        "split": split,
                        "origin_id": origin,
                        "horizon": horizon,
                        "origin_market_time": f"2025-0{1 if split == 'val' else 5}-01T00:00:00+00:00",
                        "response_market_time": f"2025-0{4 if split == 'val' else 8}-30T23:45:00+00:00",
                        "y_scaled": y,
                    }
                )
                prediction_rows.append(
                    {
                        "method_id": method,
                        "split": split,
                        "origin_id": origin,
                        "horizon": horizon,
                        "tau": 0.5,
                        "pred_scaled": y + bias,
                    }
                )
        write_csv(adapter / f"rows_{split}.csv", truth_rows)
    train_rows = []
    for origin in range(3):
        for horizon in [1, 25, 49, 73]:
            train_rows.append(
                {
                    "split": "train",
                    "origin_id": origin,
                    "horizon": horizon,
                    "origin_market_time": "2024-01-01T00:00:00+00:00",
                    "response_market_time": "2024-12-31T23:45:00+00:00",
                    "y_scaled": origin * 0.1,
                }
            )
    write_csv(adapter / "rows_train.csv", train_rows)
    write_csv(model / "model_predictions_scaled.csv", prediction_rows)
    return model / "metric_summary.csv"


def make_fixture(tmp_path: Path, with_promotion: bool = False):
    mod = load_script()
    r34 = tmp_path / "r34"
    r21 = tmp_path / "r21"
    r23 = tmp_path / "r23"
    r27 = tmp_path / "r27"
    r28 = tmp_path / "r28"
    full = tmp_path / "full"
    runs = tmp_path / "runs"
    src = tmp_path / "src"
    out = tmp_path / "out"
    history = tmp_path / "history"

    cases = [
        {"region": "AA", "fold": 1, "pricefm": 1.0, "qdesn": 1.4, "tests": [1.3, 1.2]},
        {"region": "BB", "fold": 2, "pricefm": 2.0, "qdesn": 2.5, "tests": [3.6, 3.4]},
    ]
    metrics = []
    selected = []
    oracle = []
    for case_index, case in enumerate(cases):
        selected_metric_path = None
        for arm in range(2):
            experiment_id = f"r33_{case['region'].lower()}_f{case['fold']}_arm{arm}"
            method_path = make_model_artifacts(
                runs,
                experiment_id,
                case["region"],
                case["fold"],
                "qdesn_al_rhs_ns_exact_chunked",
                bias=0.05 + case_index * 0.03,
            )
            if arm == 0:
                selected_metric_path = method_path
            for method_index, method in enumerate(
                ["qdesn_al_rhs_ns_exact_chunked", "qdesn_exal_rhs_ns_exact_chunked"]
            ):
                test = case["tests"][arm] + method_index * 0.05
                val = 0.8 + case_index + arm * 0.2 + method_index * 0.05
                metrics.append(
                    {
                        "experiment_id": experiment_id,
                        "region": case["region"],
                        "fold": case["fold"],
                        "method_id": method,
                        "val_AQL": val,
                        "test_AQL": test,
                        "test_minus_current_qdesn": test - case["qdesn"],
                        "test_minus_pricefm": test - case["pricefm"],
                        "beats_current_qdesn_on_test": test < case["qdesn"],
                        "beats_pricefm_on_test": False,
                        "lag_window": 96 + arm * 4,
                        "depth": 2 + arm,
                        "n_per_layer": 48 + arm * 16,
                        "tau0": 0.0001 + arm * 0.0004,
                        "alpha": 0.2,
                        "rho": 0.95,
                        "input_scale": 0.2,
                        "state_output": "final_layer",
                        "readout_interaction": "horizon_block",
                    }
                )
        selected.append(
            {
                **metrics[-4],
                "target_quantile": 0.5,
                "horizon_focus": "1-24",
                "current_qdesn_AQL": case["qdesn"],
                "current_pricefm_AQL": case["pricefm"],
                "metric_summary_path": str(selected_metric_path),
                "selection_is_validation_only": True,
                "selected_by": "validation_AQL_only",
            }
        )
        oracle_row = metrics[-2].copy()
        oracle.append(oracle_row)

    write_json(
        r34 / "summary.json",
        {
            "status": "completed_cleanly",
            "run_complete": True,
            "metric_summaries": 4,
            "validation_selected_beats_both": 0,
        },
    )
    write_csv(r34 / mod.R34_METRICS, metrics)
    write_csv(r34 / mod.R34_SELECTED, selected)
    write_csv(r34 / mod.R34_ORACLE, oracle)
    promotion_rows = [selected[0]] if with_promotion else []
    write_csv(r34 / mod.R34_PROMOTION, promotion_rows, columns=list(selected[0]))
    write_csv(r34 / mod.R34_MCMC, [], columns=["experiment_id"])
    write_csv(
        r34 / mod.R34_GATES,
        [
            {"gate": "r33_complete", "passed": True},
            {"gate": "validation_selection_frozen", "passed": True},
            {"gate": "dual_reference_winner_exists", "passed": False},
        ],
    )
    write_csv(
        r21 / mod.R21_ATLAS,
        [
            {
                "region": case["region"],
                "fold": case["fold"],
                "stage_r21_primary_failure_pattern": "horizon_localized_loss",
                "stage_r21_recommended_mechanism": "horizon_aware_loss_readout_calibration",
                "stage_r15_information_set_parity_flag": True,
                "worst_horizon_group_r21": "1-24",
            }
            for case in cases
        ],
    )
    write_csv(
        r23 / mod.R23_CAPABILITY,
        [{"mechanism": "new_likelihood", "effective_status": "not_supported"}],
    )
    write_json(
        r27 / "summary.json",
        {"status": "completed_read_only_calibration_parity_audit", "n_full_surface_calibrated_pricefm_wins": 0},
    )
    write_csv(
        r27 / mod.R27_DIAGNOSIS,
        [{"diagnosis_area": "calibration_full_surface", "evidence": "0 wins", "interpretation": "insufficient", "decision": "pivot"}],
    )
    write_json(r28 / "summary.json", {"status": "completed_main_launch_path_ready"})
    write_csv(
        r28 / mod.R28_CAPABILITY,
        [{"mechanism": "new_likelihood_or_loss_family", "current_support": "blocked", "runner_consumes_it": False}],
    )
    full_horizon_rows = []
    for case in cases:
        for group in ["1-24", "25-48", "49-72", "73-96"]:
            full_horizon_rows.append(
                {
                    "region": case["region"],
                    "fold": case["fold"],
                    "horizon_group": group,
                    "horizon_delta_AQL_qdesn_minus_pricefm": 0.2,
                }
            )
    write_csv(full / mod.FULL_HORIZON, full_horizon_rows)

    src.mkdir(parents=True, exist_ok=True)
    (src / "08_run_desn_model_smoke.R").write_text(
        'setdiff(qdesn_likelihoods, c("al", "exal"))\ntrain_index_qdesn <- rep(seq_len(nrow(X_train)), times = horizon_weighting$frequency)\n'
    )
    (src / "pricefm_desn_adapter.py").write_text("append_readout_interactions readout_interaction\n")
    (src / "12_prepare_desn_experiment_grid.py").write_text("readout_interaction\n")
    (src / "13_run_desn_experiment_grid.py").write_text("experiment_jobs\n")
    write_json(history / "r27.json", {"best_test_minus_pricefm": 0.3})
    write_json(history / "r34.json", {"validation_selected_beats_both": 0})

    args = mod.parser().parse_args(
        [
            "--stage-r34-dir",
            str(r34),
            "--stage-r21-dir",
            str(r21),
            "--stage-r23-dir",
            str(r23),
            "--stage-r27-dir",
            str(r27),
            "--stage-r28-dir",
            str(r28),
            "--full-surface-dir",
            str(full),
            "--output-dir",
            str(out),
            "--source-model-runner",
            str(src / "08_run_desn_model_smoke.R"),
            "--source-adapter-builder",
            str(src / "pricefm_desn_adapter.py"),
            "--source-grid-materializer",
            str(src / "12_prepare_desn_experiment_grid.py"),
            "--source-grid-launcher",
            str(src / "13_run_desn_experiment_grid.py"),
            "--history-summary",
            f"r27={history / 'r27.json'}",
            "--history-summary",
            f"r34={history / 'r34.json'}",
            "--expected-experiments",
            "4",
            "--expected-method-rows",
            "8",
            "--expected-cases",
            "2",
        ]
    )
    return mod, args, out


def test_stage_r35_blocks_same_family_and_builds_case_specific_queues(tmp_path):
    mod, args, out = make_fixture(tmp_path)
    summary = mod.run(args)

    assert summary["status"] == "completed_read_only_new_mechanism_required"
    assert summary["validation_selected_pricefm_wins"] == 0
    assert summary["test_oracle_pricefm_wins"] == 0
    assert not summary["new_expensive_launch_authorized"]
    queue = pd.read_csv(out / mod.OUT_QUEUE)
    assert set(queue["specification_scope"]) == {"case_specific_not_shared"}
    assert queue.loc[queue["region"].eq("AA"), "protect_current_qdesn"].map(mod.boolish).all()
    assert queue.loc[queue["region"].eq("BB"), "stage_r35_queue"].iloc[0] == "priority3_far_gap_hold"
    capability = pd.read_csv(out / mod.OUT_CAPABILITY).set_index("mechanism")
    assert not mod.boolish(capability.loc["new_likelihood_or_direct_quantile_loss", "currently_consumed"])
    protocol = pd.read_csv(out / mod.OUT_PROTOCOL).set_index("gate")
    assert not mod.boolish(protocol.loc["implement_consumed_new_mechanism", "passed_now"])
    assert not list(out.glob("*.yaml"))
    assert not list(out.glob("*.yml"))


def test_stage_r35_refuses_a_nonempty_promotion_queue(tmp_path):
    mod, args, out = make_fixture(tmp_path, with_promotion=True)
    with pytest.raises(ValueError, match="r34_queue_not_empty"):
        mod.run(args)
    assert not out.exists()
