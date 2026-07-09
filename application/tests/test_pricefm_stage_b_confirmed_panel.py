"""Tests for freezing seven-quantile Stage-B PriceFM confirmation panels."""

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
        cached_pricefm_root=str(tmp_path / "cached_pricefm"),
        pricefm_method="pricefm_phase1_pretraining",
        split="test",
        unit="original",
        metric="AQL",
        grid_id="unit_confirmed_panel",
        notes="unit test",
    )


def metric_row(region, fold, method, unit, aql):
    return {
        "region": region,
        "fold": fold,
        "method_id": method,
        "split": "test",
        "unit": unit,
        "AQL": aql,
        "AQCR": 0.0,
        "MAE": 2.0 * aql,
        "RMSE": 3.0 * aql,
    }


def horizon_row(region, fold, method, group, unit, aql):
    return {
        "region": region,
        "fold": fold,
        "method_id": method,
        "split": "test",
        "unit": unit,
        "horizon_group": group,
        "AQL": aql,
        "AQCR": 0.0,
        "MAE": 2.0 * aql,
        "RMSE": 3.0 * aql,
    }


def write_inputs(tmp_path, incomplete_status=False, bad_alignment=False):
    comparison = tmp_path / "comparison"
    comparison.mkdir()
    (tmp_path / "cached_pricefm").mkdir()
    pd.DataFrame([
        {
            "region": "WIN",
            "fold": 1,
            "experiment_id": "exp_win",
            "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "input_scope": "local_target_only",
            "spatial_information_set": "local_only_not_pricefm_graph",
        },
        {
            "region": "FI",
            "fold": 3,
            "experiment_id": "exp_fi",
            "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "input_scope": "local_target_only",
            "spatial_information_set": "local_only_not_pricefm_graph",
        },
    ]).to_csv(tmp_path / "registry.csv", index=False)
    pd.DataFrame([
        {"status": "completed", "dry_run": False, "run_pricefm": False, "n_region_folds": 2}
    ]).iloc[0].to_json(comparison / "summary.json", indent=2)
    status = []
    for region, fold in [("WIN", 1), ("FI", 3)]:
        status.append({
            "region": region,
            "fold": fold,
            "kind": "comparison",
            "status": "failed" if incomplete_status and region == "FI" else "completed",
            "return_code": 1 if incomplete_status and region == "FI" else 0,
        })
    pd.DataFrame(status).to_csv(comparison / "region_panel_comparison_status.csv", index=False)
    metrics = [
        metric_row("WIN", 1, "pricefm_phase1_pretraining", "original", 10.0),
        metric_row("WIN", 1, "qdesn_exal_rhs_ns_exact_chunked", "original", 8.0),
        metric_row("WIN", 1, "pricefm_phase1_pretraining", "scaled", 0.10),
        metric_row("WIN", 1, "qdesn_exal_rhs_ns_exact_chunked", "scaled", 0.08),
        metric_row("FI", 3, "pricefm_phase1_pretraining", "original", 7.0),
        metric_row("FI", 3, "qdesn_exal_rhs_ns_exact_chunked", "original", 8.0),
        metric_row("FI", 3, "pricefm_phase1_pretraining", "scaled", 0.07),
        metric_row("FI", 3, "qdesn_exal_rhs_ns_exact_chunked", "scaled", 0.08),
    ]
    pd.DataFrame(metrics).to_csv(comparison / "panel_metric.csv", index=False)
    pd.DataFrame([
        {"region": "WIN", "fold": 1, "best_method": "qdesn_exal_rhs_ns_exact_chunked", "best_AQL": 8.0, "pricefm_AQL": 10.0, "delta": -2.0, "rel_delta": -0.2},
        {"region": "FI", "fold": 3, "best_method": "qdesn_exal_rhs_ns_exact_chunked", "best_AQL": 8.0, "pricefm_AQL": 7.0, "delta": 1.0, "rel_delta": 1.0 / 7.0},
    ]).to_csv(comparison / "best_local_vs_pricefm_by_region_fold.csv", index=False)
    horizon = []
    for unit in ["original", "scaled"]:
        horizon.extend([
            horizon_row("WIN", 1, "pricefm_phase1_pretraining", "1-24", unit, 5.0 if unit == "original" else 0.05),
            horizon_row("WIN", 1, "qdesn_exal_rhs_ns_exact_chunked", "1-24", unit, 4.0 if unit == "original" else 0.04),
            horizon_row("WIN", 1, "pricefm_phase1_pretraining", "25-48", unit, 5.0 if unit == "original" else 0.05),
            horizon_row("WIN", 1, "qdesn_exal_rhs_ns_exact_chunked", "25-48", unit, 4.0 if unit == "original" else 0.04),
            horizon_row("FI", 3, "pricefm_phase1_pretraining", "1-24", unit, 3.0 if unit == "original" else 0.03),
            horizon_row("FI", 3, "qdesn_exal_rhs_ns_exact_chunked", "1-24", unit, 6.0 if unit == "original" else 0.06),
            horizon_row("FI", 3, "pricefm_phase1_pretraining", "25-48", unit, 4.0 if unit == "original" else 0.04),
            horizon_row("FI", 3, "qdesn_exal_rhs_ns_exact_chunked", "25-48", unit, 2.0 if unit == "original" else 0.02),
        ])
    pd.DataFrame(horizon).to_csv(comparison / "panel_horizon_group.csv", index=False)
    rows = []
    for region, fold in [("WIN", 1), ("FI", 3)]:
        for method in ["pricefm_phase1_pretraining", "qdesn_exal_rhs_ns_exact_chunked"]:
            rows.append({
                "region": region,
                "fold": fold,
                "method_id": method,
                "available_prediction_rows": 100,
                "available_unique_response_rows": 50,
                "aligned_prediction_rows": 99 if bad_alignment and region == "FI" else 100,
                "aligned_unique_response_rows": 50,
            })
    pd.DataFrame(rows).to_csv(comparison / "panel_row_alignment.csv", index=False)


def test_stage_b_confirmed_panel_freezes_wins_and_exceptions(tmp_path):
    mod = load_script("49_freeze_pricefm_stage_b_confirmed_panel.py")
    write_inputs(tmp_path)

    summary = mod.freeze(args(tmp_path))

    out = tmp_path / "out"
    evaluated = pd.read_csv(out / "evaluated_stage_b_panel.csv")
    confirmed = pd.read_csv(out / "confirmed_stage_b_panel.csv")
    exceptions = pd.read_csv(out / "stage_b_exceptions.csv")
    horizon = pd.read_csv(out / "horizon_group_diagnostics.csv")

    assert summary["n_evaluated"] == 2
    assert summary["n_confirmed"] == 1
    assert summary["n_exceptions"] == 1
    assert set(confirmed["region"]) == {"WIN"}
    fi = evaluated[evaluated["region"].eq("FI")].iloc[0]
    assert fi["promotion_label"] == "evaluated_loss"
    assert fi["exception_label"] == "needs_short_horizon_rescue"
    assert fi["worst_horizon_group"] == "1-24"
    assert exceptions["region"].tolist() == ["FI"]
    assert set(horizon["horizon_group"]) == {"1-24", "25-48"}
    report = (out / "stage_b_confirmed_panel_report.md").read_text()
    assert "Median-only" in report


def test_stage_b_confirmed_panel_rejects_incomplete_status(tmp_path):
    mod = load_script("49_freeze_pricefm_stage_b_confirmed_panel.py")
    write_inputs(tmp_path, incomplete_status=True)

    try:
        mod.freeze(args(tmp_path))
    except ValueError as exc:
        assert "not fully completed" in str(exc)
    else:
        raise AssertionError("expected incomplete comparison status to fail")


def test_stage_b_confirmed_panel_rejects_imperfect_row_alignment(tmp_path):
    mod = load_script("49_freeze_pricefm_stage_b_confirmed_panel.py")
    write_inputs(tmp_path, bad_alignment=True)

    try:
        mod.freeze(args(tmp_path))
    except ValueError as exc:
        assert "row alignment is imperfect" in str(exc)
    else:
        raise AssertionError("expected imperfect row alignment to fail")
