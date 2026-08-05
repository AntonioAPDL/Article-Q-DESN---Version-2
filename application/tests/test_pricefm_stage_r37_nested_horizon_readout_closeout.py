"""Tests for the PriceFM Stage-R37 nested horizon-readout closeout."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/162_closeout_pricefm_stage_r37_nested_horizon_readout.py"
if str(SCRIPT.parent) not in sys.path:
    sys.path.insert(0, str(SCRIPT.parent))


def load_module():
    spec = importlib.util.spec_from_file_location("stage_r37", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def fixture(tmp_path: Path):
    prep, grid, runs, r34, output = [tmp_path / x for x in ["prep", "grid", "runs", "r34", "output"]]
    cases = [
        ("AA", 1, [-0.02, -0.01, -0.03], True, 4.0, 3.8, 4.1),
        ("BB", 2, [-0.02, 0.001, -0.01], True, 5.0, 4.8, 5.1),
        ("CC", 3, [-0.02, -0.01, -0.03], False, 6.0, 5.8, 6.1),
    ]
    manifest = []
    status = []
    anchors = []
    for region, fold, deltas, converged, shared_outer, separate_outer, anchor in cases:
        eid = f"r36_{region}_{fold}"
        manifest.append({
            "experiment_id": eid, "region": region, "fold": fold,
            "protect_current_qdesn": region == "AA",
            "selection_rule": "nested_temporal_validation_AQL_only_within_case",
        })
        status.append({"id": eid, "kind": "experiment", "status": "completed", "return_code": 0})
        anchors.append({"region": region, "fold": fold, "val_AQL": anchor})
        model = runs / eid / "cells" / f"region={region}" / f"fold={fold}" / "model"
        inner = []
        for inner_fold, delta in enumerate(deltas, 1):
            inner += [
                {"inner_fold": inner_fold, "method_id": "qdesn_al_rhs_ns_exact_chunked", "readout_mode": "shared_static", "converged": True, "AQL_scaled": 0.1},
                {"inner_fold": inner_fold, "method_id": "qdesn_al_rhs_ns_exact_chunked_horizon_separate", "readout_mode": "separate_horizon_block", "converged": converged if inner_fold == 1 else True, "AQL_scaled": 0.1 + delta},
            ]
        write_csv(model / "nested_validation_metrics.csv", inner)
        write_csv(model / "metric_summary.csv", [
            {"method_id": "qdesn_al_rhs_ns_exact_chunked", "split": "val", "unit": "original", "AQL": shared_outer},
            {"method_id": "qdesn_al_rhs_ns_exact_chunked_horizon_separate", "split": "val", "unit": "original", "AQL": separate_outer},
        ])
        horizons = []
        for method, value in [("qdesn_al_rhs_ns_exact_chunked", shared_outer), ("qdesn_al_rhs_ns_exact_chunked_horizon_separate", separate_outer)]:
            for group in ["1-24", "25-48", "49-72", "73-96"]:
                horizons.append({"method_id": method, "split": "val", "unit": "original", "horizon_group": group, "AQL": value})
        write_csv(model / "metric_by_horizon_group.csv", horizons)
        write_csv(model / "model_method_summary.csv", [{"method_id": "qdesn_al_rhs_ns_exact_chunked"}])
    write_csv(prep / "pricefm_stage_r36_launch_manifest.csv", manifest)
    write_csv(prep / "pricefm_stage_r36_selection_protocol.csv", [
        {"gate": "inner_selection", "rule": "minimum median inner-fold scaled AQL within region/fold"},
        {"gate": "stability", "rule": "separate readout cannot lose materially in the worst inner fold"},
    ])
    (prep / "summary.json").write_text("{}\n")
    write_csv(grid / "launch_status.csv", status)
    (grid / "launch_summary.json").write_text("{}\n")
    write_csv(r34 / "pricefm_stage_r34_validation_selected_cases.csv", anchors)
    return prep, grid, runs, r34, output


def args(module, paths):
    prep, grid, runs, r34, output = paths
    return module.parser().parse_args([
        "--stage-r36-prep-dir", str(prep), "--grid-root", str(grid),
        "--run-root", str(runs), "--stage-r34-dir", str(r34),
        "--output-dir", str(output), "--expected-cases", "3",
        "--expected-harm-guards", "1", "--force", "true",
    ])


def test_r37_applies_strict_case_specific_gates(tmp_path):
    module = load_module()
    paths = fixture(tmp_path)
    summary = module.run(args(module, paths))
    assert summary["full_quantile_candidates"] == 1
    assert summary["test_inspected"] is False
    cases = pd.read_csv(paths[-1] / "pricefm_stage_r37_case_closeout.csv").set_index("region")
    assert cases.loc["AA", "decision"] == "eligible_for_fresh_full_quantile_confirmation"
    assert cases.loc["BB", "decision"] == "blocked_strict_worst_fold_harm"
    assert cases.loc["CC", "decision"] == "blocked_inner_nonconvergence"
    queue = pd.read_csv(paths[-1] / "pricefm_stage_r37_full_quantile_confirmation_queue.csv")
    assert queue["region"].tolist() == ["AA"]
    sensitivity = pd.read_csv(paths[-1] / "pricefm_stage_r37_harm_tolerance_sensitivity.csv")
    assert sensitivity.groupby("diagnostic_tolerance_scaled_AQL").size().to_dict() == {0.0: 3, 0.00025: 3, 0.001: 3}


def test_r37_rejects_test_visible_outer_metrics(tmp_path):
    module = load_module()
    paths = fixture(tmp_path)
    metric = next(paths[2].glob("*/cells/*/*/model/metric_summary.csv"))
    frame = pd.read_csv(metric)
    frame.loc[len(frame)] = ["qdesn_al_rhs_ns_exact_chunked", "test", "original", 1.0]
    frame.to_csv(metric, index=False)
    try:
        module.run(args(module, paths))
    except ValueError as exc:
        assert "test quarantine violated" in str(exc)
    else:
        raise AssertionError("Expected test-visible R36 metrics to fail closed")


def test_r37_refuses_incomplete_launch(tmp_path):
    module = load_module()
    paths = fixture(tmp_path)
    status_path = paths[1] / "launch_status.csv"
    status = pd.read_csv(status_path)
    status.loc[0, ["status", "return_code"]] = ["failed", 1]
    status.to_csv(status_path, index=False)
    try:
        module.run(args(module, paths))
    except RuntimeError as exc:
        assert "R36 is incomplete" in str(exc)
    else:
        raise AssertionError("Expected incomplete R36 launch to fail closed")
