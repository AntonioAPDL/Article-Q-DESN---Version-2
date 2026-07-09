"""Tests for freezing Stage-B median decisions into promotion/rescue queues."""

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
        registry_dir=str(tmp_path / "registry"),
        closeout_dir=str(tmp_path / "closeout"),
        comparison_dir=str(tmp_path / "comparison"),
        output_dir=str(tmp_path / "out"),
        grid_id="unit_stage_b",
        qdesn_methods="qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked",
        pricefm_method="pricefm_phase1_pretraining",
        split="test",
        unit="original",
        metric="AQL",
        candidate_source="unit_decision_registry",
    )


def selected_row(region, fold, triage):
    return {
        "region": region,
        "fold": fold,
        "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "experiment_id": f"exp_{region.lower()}_{fold}",
        "selection_metric_value": 5.0,
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "feature_map": "window_reservoir_v1",
        "lag_window": 96,
        "depth": 1,
        "units": "[120]",
        "alpha": 0.5,
        "rho": 0.9,
        "input_scale": 0.5,
        "projection_scale": 1.0,
        "tau0": 1.0e-3,
        "seed": 20260616,
        "stage_b_region_triage": triage,
    }


def write_inputs(tmp_path):
    registry_dir = tmp_path / "registry"
    closeout_dir = tmp_path / "closeout"
    comparison_dir = tmp_path / "comparison"
    registry_dir.mkdir()
    closeout_dir.mkdir()
    comparison_dir.mkdir()
    rows = []
    region_triage = {
        "READY": "local_strong",
        "CONFLICT": "local_fail_rescue",
        "RESCUE": "local_promising",
    }
    for region, triage in region_triage.items():
        for fold in [1, 2]:
            rows.append(selected_row(region, fold, triage))
    selected = pd.DataFrame(rows)
    selected.to_csv(registry_dir / "median_selection_registry.csv", index=False)
    selected.to_csv(closeout_dir / "stage_b_selection_registry_with_triage.csv", index=False)
    pd.DataFrame([
        {"region": "READY", "n_folds": 2, "stage_b_triage": "local_strong"},
        {"region": "CONFLICT", "n_folds": 2, "stage_b_triage": "local_fail_rescue"},
        {"region": "RESCUE", "n_folds": 2, "stage_b_triage": "local_promising"},
    ]).to_csv(closeout_dir / "stage_b_region_summary.csv", index=False)

    metric_rows = []
    for region in region_triage:
        for fold in [1, 2]:
            qdesn_aql = 8.0
            pricefm_aql = 9.0
            if region == "RESCUE" and fold == 2:
                qdesn_aql = 10.0
                pricefm_aql = 9.0
            metric_rows.extend([
                {
                    "region": region,
                    "fold": fold,
                    "method_id": "qdesn_exal_rhs_ns_exact_chunked",
                    "split": "test",
                    "unit": "original",
                    "AQL": qdesn_aql,
                    "MAE": 2 * qdesn_aql,
                    "RMSE": 3 * qdesn_aql,
                },
                {
                    "region": region,
                    "fold": fold,
                    "method_id": "pricefm_phase1_pretraining",
                    "split": "test",
                    "unit": "original",
                    "AQL": pricefm_aql,
                    "MAE": 2 * pricefm_aql,
                    "RMSE": 3 * pricefm_aql,
                },
            ])
    pd.DataFrame(metric_rows).to_csv(comparison_dir / "panel_metric.csv", index=False)
    pd.DataFrame([
        {
            "region": region,
            "fold": fold,
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "split": "test",
            "unit": "original",
            "AQL": 8.0,
            "AQCR": 0.0,
            "MAE": 16.0,
            "RMSE": 24.0,
            "pricefm_phase1_AQL": 9.0,
            "delta_abs": -1.0,
            "delta_rel": -1.0 / 9.0,
            "decision_label": "local_beats_pricefm",
        }
        for region in region_triage
        for fold in [1, 2]
    ]).to_csv(comparison_dir / "selected_competitiveness_flags.csv", index=False)
    pd.DataFrame([
        {
            "region": region,
            "fold": fold,
            "kind": kind,
            "status": "completed",
            "return_code": 0,
        }
        for region in region_triage
        for fold in [1, 2]
        for kind in ["pricefm_phase1", "comparison"]
    ]).to_csv(comparison_dir / "region_panel_comparison_status.csv", index=False)


def test_stage_b_decision_registry_splits_promotion_conflict_and_rescue(tmp_path):
    mod = load_script("48_freeze_pricefm_stage_b_decision_registry.py")
    write_inputs(tmp_path)

    summary = mod.freeze(args(tmp_path))

    out = tmp_path / "out"
    regions = pd.read_csv(out / "stage_b_region_decisions.csv")
    promotion = pd.read_csv(out / "stage_b_promotion_ready_registry.csv")
    conflict = pd.read_csv(out / "stage_b_conflict_confirm_registry.csv")
    rescue = pd.read_csv(out / "stage_b_rescue_needed_registry.csv")
    rescue_scope = pd.read_csv(out / "stage_b_rescue_scope.csv")
    decisions = dict(zip(regions["region"], regions["final_decision"]))

    assert summary["n_region_folds"] == 6
    assert decisions["READY"] == "paper_quantile_ready"
    assert decisions["CONFLICT"] == "paper_quantile_ready_with_naive_conflict"
    assert decisions["RESCUE"] == "median_rescue_needed"
    assert set(promotion["region"]) == {"READY", "CONFLICT"}
    assert set(conflict["region"]) == {"CONFLICT"}
    assert set(rescue["region"]) == {"RESCUE"}
    assert set(rescue_scope["recommended_action"]) == {
        "confirm_rescued_region_fold_or_seed_robustness",
        "retest_graph_geometry_validation",
    }
    registry = pd.read_csv(out / "stage_b_decision_registry.csv")
    assert "pricefm_phase1_AQL" in registry.columns
    assert "selected_vs_pricefm_pricefm_phase1_AQL" in registry.columns
    assert "stage_b_decision_report.md" in summary["outputs"]["report"]


def test_stage_b_decision_registry_rejects_incomplete_comparison_status():
    mod = load_script("48_freeze_pricefm_stage_b_decision_registry.py")
    status = pd.DataFrame([
        {"region": "A", "fold": 1, "status": "completed", "return_code": 0},
        {"region": "A", "fold": 1, "status": "failed", "return_code": 1},
    ])

    try:
        mod.validate_comparison_status(status)
    except ValueError as exc:
        assert "not fully completed" in str(exc)
    else:
        raise AssertionError("Expected incomplete comparison status to fail.")
