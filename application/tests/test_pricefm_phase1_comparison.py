"""Tests for local PriceFM Phase-I prediction/comparison helpers."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

import numpy as np
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


def test_phase1_graph_gate_is_target_one_hot():
    mod = load_script("17_run_pricefm_phase1_predictions.py")
    gate = mod.graph_gate(["AT", "DE_LU", "FR"], ["DE_LU"], 4)
    assert gate.shape == (4, 3)
    assert np.all(gate[:, 0] == 0.0)
    assert np.all(gate[:, 1] == 1.0)
    assert np.all(gate[:, 2] == 0.0)


def test_phase1_predictions_long_records_all_quantiles_and_horizons():
    mod = load_script("17_run_pricefm_phase1_predictions.py")
    y = np.arange(6, dtype=float).reshape(2, 3)
    pred = np.zeros((2, 3, 2), dtype=float)
    anchors = np.array(["2025-01-01T00:00:00+00:00", "2025-01-02T00:00:00+00:00"])
    out = mod.predictions_long("m", "test", y, pred, anchors, [0.1, 0.9])
    assert out.shape[0] == 12
    assert set(out["tau"]) == {0.1, 0.9}
    assert set(out["horizon"]) == {1, 2, 3}
    assert out["origin_id"].nunique() == 2
    assert out.loc[out["horizon"].eq(2), "response_market_time"].iloc[0].endswith("00:15:00+00:00")


def test_phase1_metric_arrays_have_expected_shape():
    mod = load_script("17_run_pricefm_phase1_predictions.py")
    y = np.arange(6, dtype=float).reshape(2, 3)
    pred = np.repeat(y[:, :, None], 2, axis=2)
    anchors = np.array(["2025-01-01T00:00:00+00:00", "2025-01-02T00:00:00+00:00"])
    long = mod.predictions_long("m", "test", y, pred, anchors, [0.1, 0.9])
    y_arr, p_arr, horizons = mod.pivot_metric_arrays(long, [0.1, 0.9])
    assert y_arr.shape == (2, 3)
    assert p_arr.shape == (2, 3, 2)
    assert horizons == [1, 2, 3]


def toy_predictions(method_id, origins):
    rows = []
    for origin in origins:
        for horizon in [1, 2]:
            for tau in [0.1, 0.9]:
                rows.append({
                    "method_id": method_id,
                    "split": "test",
                    "origin_market_time": origin,
                    "response_market_time": origin,
                    "horizon": horizon,
                    "tau": tau,
                    "pred_scaled": 0.0,
                    "y_scaled": 0.0,
                })
    return pd.DataFrame(rows)


def test_comparison_alignment_uses_common_prediction_rows():
    mod = load_script("18_compare_pricefm_phase1_desn_quantiles.py")
    pricefm = toy_predictions("pricefm_phase1_pretraining", ["a", "b"])
    desn = toy_predictions("qdesn_exal_rhs_ns_exact_chunked", ["b", "c"])
    aligned, audit = mod.align_predictions(
        pricefm,
        desn,
        ["pricefm_phase1_pretraining", "qdesn_exal_rhs_ns_exact_chunked"],
    )
    assert set(aligned["origin_market_time"]) == {"b"}
    assert aligned.shape[0] == 8
    assert set(audit["aligned_unique_response_rows"]) == {2}


def test_comparison_normalizes_time_columns_to_utc_iso():
    mod = load_script("18_compare_pricefm_phase1_desn_quantiles.py")
    frame = pd.DataFrame({
        "origin_market_time": ["2025-01-01 00:00:00+00:00"],
        "response_market_time": ["2025-01-01 00:15:00+00:00"],
    })
    out = mod.normalize_time_cols(frame)
    assert out["origin_market_time"].iloc[0] == "2025-01-01T00:00:00+00:00"
    assert out["response_market_time"].iloc[0] == "2025-01-01T00:15:00+00:00"


def test_comparison_quantile_parser_supports_median_only_and_percent_inputs():
    mod = load_script("18_compare_pricefm_phase1_desn_quantiles.py")
    assert mod.parse_quantiles("0.5") == [0.5]
    assert mod.parse_quantiles("10,50,90") == [0.1, 0.5, 0.9]


def test_fold_comparison_parser_requires_folds():
    mod = load_script("19_summarize_pricefm_phase1_desn_fold_comparisons.py")
    assert mod.parse_folds("1,2, 3") == [1, 2, 3]
    try:
        mod.parse_folds("")
    except ValueError as err:
        assert "At least one fold" in str(err)
    else:
        raise AssertionError("empty fold list should fail")


def test_fold_comparison_macro_and_pricefm_deltas():
    mod = load_script("19_summarize_pricefm_phase1_desn_fold_comparisons.py")
    frame = pd.DataFrame({
        "fold": [1, 1, 2, 2],
        "method_id": [
            "pricefm_phase1_pretraining",
            "qdesn_exal_rhs_ns_exact_chunked",
            "pricefm_phase1_pretraining",
            "qdesn_exal_rhs_ns_exact_chunked",
        ],
        "AQL": [5.0, 4.5, 6.0, 6.6],
        "AQCR": [0.0, 0.1, 0.0, 0.2],
        "MAE": [10.0, 9.0, 12.0, 13.2],
        "RMSE": [20.0, 18.0, 24.0, 26.4],
    })
    macro = mod.macro_metrics(frame)
    qdesn = macro[macro["method_id"].eq("qdesn_exal_rhs_ns_exact_chunked")].iloc[0]
    assert np.isclose(qdesn["AQL_mean"], 5.55)
    delta = mod.deltas_vs_baseline(frame, "pricefm_phase1_pretraining")
    qdesn_fold1 = delta[
        delta["fold"].eq(1)
        & delta["method_id"].eq("qdesn_exal_rhs_ns_exact_chunked")
    ].iloc[0]
    assert np.isclose(qdesn_fold1["delta_AQL"], -0.5)
    assert np.isclose(qdesn_fold1["ratio_AQL"], 0.9)


def test_region_panel_phase1_comparison_wrapper_dry_run(tmp_path):
    mod = load_script("36_compare_pricefm_region_panel_quantiles.py")
    registry = tmp_path / "registry.csv"
    pd.DataFrame([
        {"region": "DE_LU", "fold": 1},
        {"region": "EE", "fold": 2},
    ]).to_csv(registry, index=False)
    scope = mod.registry_scope(registry, regions=["DE_LU"], folds=[1])
    assert scope.shape[0] == 1
    args = type("Args", (), {
        "registry_csv": str(registry),
        "config": "application/config/pricefm_data_pipeline.yaml",
        "pricefm_root": str(tmp_path / "pricefm"),
        "desn_root": str(tmp_path / "desn"),
        "output_root": str(tmp_path / "comparison"),
        "regions": "DE_LU",
        "folds": "1",
        "split": "test",
        "methods": "pricefm_phase1_pretraining,qdesn_exal_rhs_ns_exact_chunked",
        "quantiles": "0.5",
        "run_pricefm": True,
        "dry_run": True,
        "desn_panel_label": "Graph/local selected DESN/Q-DESN",
        "desn_panel_description": "graph/local selected DESN/Q-DESN quantile outputs",
        "comparison_note": "Graph/local candidate panel, not PriceFM Phase-II.",
    })()
    summary = mod.compare_panel(args)
    assert summary["status"] == "planned"
    status = pd.read_csv(tmp_path / "comparison" / "region_panel_comparison_status.csv")
    assert set(status["kind"]) == {"pricefm_phase1", "comparison"}
    assert status["status"].eq("planned").all()
    report = (tmp_path / "comparison" / "pricefm_region_panel_quantile_comparison_report.md").read_text()
    assert "Graph/local selected DESN/Q-DESN" in report
    assert "Graph/local candidate panel" in report
    compare_cmd = status[status["kind"].eq("comparison")]["command"].iloc[0]
    assert "--quantiles 0.5" in compare_cmd


def test_region_panel_phase1_collector_accepts_existing_scope_columns(tmp_path):
    mod = load_script("36_compare_pricefm_region_panel_quantiles.py")
    registry = tmp_path / "registry.csv"
    pd.DataFrame([{"region": "DE_LU", "fold": 1}]).to_csv(registry, index=False)
    out_dir = tmp_path / "comparison" / "region=DE_LU" / "fold=1"
    out_dir.mkdir(parents=True)
    pd.DataFrame([
        {
            "region": "DE_LU",
            "fold": 1,
            "method_id": "pricefm_phase1_pretraining",
            "split": "test",
            "unit": "original",
            "AQL": 1.5,
        },
        {
            "region": "DE_LU",
            "fold": 1,
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "split": "test",
            "unit": "original",
            "AQL": 1.0,
        },
    ]).to_csv(out_dir / "pricefm_vs_desn_metric_summary.csv", index=False)
    pd.DataFrame([
        {"region": "DE_LU", "fold": 1, "method_id": "pricefm_phase1_pretraining", "horizon": 1, "AQL": 1.5}
    ]).to_csv(out_dir / "pricefm_vs_desn_metric_by_horizon.csv", index=False)
    pd.DataFrame([
        {"region": "DE_LU", "fold": 1, "method_id": "pricefm_phase1_pretraining", "horizon_group": "short", "AQL": 1.5}
    ]).to_csv(out_dir / "pricefm_vs_desn_metric_by_horizon_group.csv", index=False)
    pd.DataFrame([
        {"region": "DE_LU", "fold": 1, "method_id": "pricefm_phase1_pretraining", "aligned_rows": 4}
    ]).to_csv(out_dir / "pricefm_vs_desn_row_alignment_audit.csv", index=False)

    panel = mod.collect_panel_outputs(tmp_path / "comparison", mod.registry_scope(registry))
    flags = mod.delta_flags(panel["metric"])

    assert panel["metric"].shape[0] == 2
    assert panel["metric"].columns[:2].tolist() == ["region", "fold"]
    assert panel["horizon"].shape[0] == 1
    assert panel["horizon_group"].shape[0] == 1
    assert panel["row_alignment"].shape[0] == 1
    assert flags.loc[0, "decision_label"] == "local_beats_pricefm"


def test_region_panel_phase1_collector_rejects_scope_mismatch(tmp_path):
    mod = load_script("36_compare_pricefm_region_panel_quantiles.py")
    registry = tmp_path / "registry.csv"
    pd.DataFrame([{"region": "DE_LU", "fold": 1}]).to_csv(registry, index=False)
    out_dir = tmp_path / "comparison" / "region=DE_LU" / "fold=1"
    out_dir.mkdir(parents=True)
    pd.DataFrame([
        {"region": "DE_LU", "fold": 2, "method_id": "m", "split": "test", "unit": "original", "AQL": 1.0}
    ]).to_csv(out_dir / "pricefm_vs_desn_metric_summary.csv", index=False)

    try:
        mod.collect_panel_outputs(tmp_path / "comparison", mod.registry_scope(registry))
    except ValueError as err:
        assert "fold values" in str(err)
    else:
        raise AssertionError("mismatched fold should fail")


def test_region_panel_phase1_flags_use_relative_thresholds():
    mod = load_script("36_compare_pricefm_region_panel_quantiles.py")
    metric = pd.DataFrame([
        {"region": "A", "fold": 1, "method_id": "pricefm_phase1_pretraining", "split": "test", "unit": "original", "AQL": 100.0},
        {"region": "A", "fold": 1, "method_id": "local", "split": "test", "unit": "original", "AQL": 104.0},
        {"region": "B", "fold": 1, "method_id": "pricefm_phase1_pretraining", "split": "test", "unit": "original", "AQL": 10.0},
        {"region": "B", "fold": 1, "method_id": "local", "split": "test", "unit": "original", "AQL": 11.0},
        {"region": "C", "fold": 1, "method_id": "pricefm_phase1_pretraining", "split": "test", "unit": "original", "AQL": 10.0},
        {"region": "C", "fold": 1, "method_id": "local", "split": "test", "unit": "original", "AQL": 9.0},
    ])
    flags = mod.delta_flags(metric)
    labels = {(row.region, row.decision_label) for row in flags.itertuples(index=False)}
    assert ("A", "local_close_to_pricefm") in labels
    assert ("B", "local_lags_pricefm") in labels
    assert ("C", "local_beats_pricefm") in labels
