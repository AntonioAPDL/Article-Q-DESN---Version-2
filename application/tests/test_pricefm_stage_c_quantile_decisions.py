"""Tests for freezing Stage-C paper-quantile comparison decisions."""

from pathlib import Path
import importlib.util
import sys
from types import SimpleNamespace

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


def args(tmp_path):
    return SimpleNamespace(
        comparison_dir=str(tmp_path / "comparison"),
        output_dir=str(tmp_path / "out"),
        registry_csv=str(tmp_path / "registry.csv"),
        pricefm_method="pricefm_phase1_pretraining",
        split="test",
        unit="original",
        metric="AQL",
        close_rel_threshold=0.05,
        grid_id="unit_stage_c_decisions",
        notes="unit",
    )


def write_inputs(tmp_path, *, bad_status=False, bad_alignment=False, missing_pricefm=False):
    comparison = tmp_path / "comparison"
    comparison.mkdir()
    (comparison / "summary.json").write_text('{"status": "completed"}\n')

    regions = [("WIN", 1), ("CLOSE", 1), ("LOSS", 1)]
    pd.DataFrame([
        {
            "region": region,
            "fold": fold,
            "kind": "comparison",
            "status": "failed" if bad_status and region == "WIN" else "completed",
            "return_code": 1 if bad_status and region == "WIN" else 0,
        }
        for region, fold in regions
    ]).to_csv(comparison / "region_panel_comparison_status.csv", index=False)

    methods = ["qdesn_exal_rhs_ns_exact_chunked"]
    if not missing_pricefm:
        methods.append("pricefm_phase1_pretraining")
    alignment_rows = []
    for region, fold in regions:
        for method in methods:
            aligned = 9 if bad_alignment and region == "WIN" and method.startswith("qdesn") else 10
            alignment_rows.append({
                "region": region,
                "fold": fold,
                "method_id": method,
                "available_prediction_rows": 10,
                "available_unique_response_rows": 5,
                "aligned_prediction_rows": aligned,
                "aligned_unique_response_rows": 5,
            })
    pd.DataFrame(alignment_rows).to_csv(comparison / "panel_row_alignment.csv", index=False)

    local_aql = {"WIN": 8.0, "CLOSE": 10.2, "LOSS": 12.0}
    pricefm_aql = {"WIN": 10.0, "CLOSE": 10.0, "LOSS": 10.0}
    metric_rows = []
    horizon_rows = []
    for region, fold in regions:
        metric_rows.append({
            "region": region,
            "fold": fold,
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "split": "test",
            "unit": "original",
            "AQL": local_aql[region],
            "AQCR": 0.0,
            "MAE": 2.0 * local_aql[region],
            "RMSE": 3.0 * local_aql[region],
        })
        if not missing_pricefm:
            metric_rows.append({
                "region": region,
                "fold": fold,
                "method_id": "pricefm_phase1_pretraining",
                "split": "test",
                "unit": "original",
                "AQL": pricefm_aql[region],
                "AQCR": 0.0,
                "MAE": 2.0 * pricefm_aql[region],
                "RMSE": 3.0 * pricefm_aql[region],
            })
        for method, value in [
            ("qdesn_exal_rhs_ns_exact_chunked", local_aql[region]),
            ("pricefm_phase1_pretraining", pricefm_aql[region]),
        ]:
            if missing_pricefm and method == "pricefm_phase1_pretraining":
                continue
            horizon_rows.append({
                "region": region,
                "fold": fold,
                "method_id": method,
                "split": "test",
                "unit": "original",
                "horizon_group": "1-24",
                "AQL": value,
            })
    pd.DataFrame(metric_rows).to_csv(comparison / "panel_metric.csv", index=False)
    pd.DataFrame(horizon_rows).to_csv(comparison / "panel_horizon_group.csv", index=False)

    pd.DataFrame([
        {
            "region": region,
            "fold": fold,
            "experiment_id": f"exp_{region.lower()}",
            "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "selected_on_split": "val",
            "selection_metric": "AQL",
            "feature_policy": "graph_khop" if region == "WIN" else "target_only",
            "input_scope": "local_target_only",
            "output_scope": "target_region_path",
            "lead_covariate_status": "realized_ex_post",
            "spatial_information_set": "local_only_not_pricefm_graph",
            "graph_degree": 2 if region == "WIN" else "",
            "graph_source": "",
            "graph_hash": "",
        }
        for region, fold in regions
    ]).to_csv(tmp_path / "registry.csv", index=False)


def test_stage_c_quantile_decisions_split_promoted_close_and_fallback(tmp_path):
    mod = load_script("53_freeze_pricefm_stage_c_quantile_decisions.py")
    write_inputs(tmp_path)

    summary = mod.freeze(args(tmp_path))
    out = tmp_path / "out"
    decisions = pd.read_csv(out / "stage_c_quantile_decision_registry.csv")
    promoted = pd.read_csv(out / "stage_c_quantile_promoted_local_registry.csv")
    close = pd.read_csv(out / "stage_c_quantile_close_registry.csv")
    fallback = pd.read_csv(out / "stage_c_quantile_pricefm_fallback_registry.csv")

    assert summary["n_evaluated"] == 3
    assert summary["n_promoted_local"] == 1
    assert summary["n_close_to_pricefm"] == 1
    assert summary["n_pricefm_fallback"] == 1
    assert set(promoted["region"]) == {"WIN"}
    assert set(close["region"]) == {"CLOSE"}
    assert set(fallback["region"]) == {"LOSS"}
    labels = dict(zip(decisions["region"], decisions["stage_c_quantile_decision"]))
    assert labels["WIN"] == "stage_c_confirmed_local_win"
    assert labels["CLOSE"] == "stage_c_local_close_to_pricefm"
    assert labels["LOSS"] == "stage_c_pricefm_fallback"
    win = decisions[decisions["region"].eq("WIN")].iloc[0]
    assert win["feature_policy"] == "graph_khop"
    assert win["graph_degree"] == 2
    assert win["input_scope"] == "pricefm_graph_khop_degree2"
    assert win["spatial_information_set"] == "pricefm_released_graph_khop"
    assert len(str(win["graph_hash"])) == 64
    assert "stage_c_quantile_decision_report.md" in summary["outputs"]["report"]


def test_stage_c_quantile_decisions_rejects_incomplete_status(tmp_path):
    mod = load_script("53_freeze_pricefm_stage_c_quantile_decisions.py")
    write_inputs(tmp_path, bad_status=True)

    try:
        mod.freeze(args(tmp_path))
    except ValueError as exc:
        assert "not fully completed" in str(exc)
    else:
        raise AssertionError("incomplete comparison status should fail")


def test_stage_c_quantile_decisions_rejects_bad_row_alignment(tmp_path):
    mod = load_script("53_freeze_pricefm_stage_c_quantile_decisions.py")
    write_inputs(tmp_path, bad_alignment=True)

    try:
        mod.freeze(args(tmp_path))
    except ValueError as exc:
        assert "row alignment is imperfect" in str(exc)
    else:
        raise AssertionError("bad row alignment should fail")


def test_stage_c_quantile_decisions_rejects_missing_pricefm_baseline(tmp_path):
    mod = load_script("53_freeze_pricefm_stage_c_quantile_decisions.py")
    write_inputs(tmp_path, missing_pricefm=True)

    try:
        mod.freeze(args(tmp_path))
    except ValueError as exc:
        assert "missing PriceFM method" in str(exc)
    else:
        raise AssertionError("missing PriceFM baseline should fail")
