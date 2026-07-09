"""Tests for merging independent PriceFM quantile cells."""

from pathlib import Path
import importlib.util
import sys

import numpy as np
import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "application" / "scripts" / "pricefm"))

spec = importlib.util.spec_from_file_location(
    "pricefm_paper_quantile_summary",
    ROOT / "application" / "scripts" / "pricefm" / "15_summarize_paper_quantile_runs.py",
)
summary_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary_mod)


class IdentityScaler:
    def inverse_transform(self, values):
        return values


def make_rows(split):
    return pd.DataFrame({
        "split": [split, split],
        "origin_id": [1, 1],
        "horizon": [1, 2],
        "response_market_time": ["2026-01-01", "2026-01-01"],
        "y_scaled": [10.0, 20.0],
    })


def test_validate_prediction_coverage_requires_each_method_quantile():
    pred = pd.DataFrame({
        "method_id": ["m1", "m1", "m2"],
        "split": ["test", "test", "test"],
        "origin_id": [1, 1, 1],
        "horizon": [1, 1, 1],
        "tau": [0.10, 0.50, 0.10],
        "pred_scaled": [9.0, 10.0, 8.0],
    })
    with pytest.raises(ValueError, match="missing"):
        summary_mod.validate_prediction_coverage(pred, [0.10, 0.50])


def test_validate_prediction_coverage_rejects_duplicates():
    pred = pd.DataFrame({
        "method_id": ["m1", "m1"],
        "split": ["test", "test"],
        "origin_id": [1, 1],
        "horizon": [1, 1],
        "tau": [0.10, 0.10],
        "pred_scaled": [9.0, 9.0],
    })
    with pytest.raises(ValueError, match="duplicate"):
        summary_mod.validate_prediction_coverage(pred, [0.10])


def test_resolve_row_scope_filters_override_mismatches():
    full = {
        "scope": {
            "regions": ["DE_LU"],
            "folds": [2],
        }
    }
    assert summary_mod.resolve_row_scope(full, region_override="DE_LU", fold_override=2) == ("DE_LU", 2)
    assert summary_mod.resolve_row_scope(full, region_override="DE_LU", fold_override=3) is None
    assert summary_mod.resolve_row_scope(full, region_override="FR", fold_override=2) is None


def test_resolve_row_scope_requires_explicit_multifold_without_override():
    full = {
        "scope": {
            "regions": ["DE_LU"],
            "folds": [2, 3],
        }
    }
    with pytest.raises(ValueError, match="multiple folds"):
        summary_mod.resolve_row_scope(full)
    assert summary_mod.resolve_row_scope(full, region_override="DE_LU", fold_override=3) == ("DE_LU", 3)


def test_method_metrics_from_merged_single_quantile_predictions():
    rows = {"test": make_rows("test"), "val": make_rows("val")}
    pred_rows = []
    for split in ("val", "test"):
        for tau, values in [(0.10, [8.0, 18.0]), (0.50, [10.0, 19.0]), (0.90, [12.0, 22.0])]:
            for row, value in zip(rows[split].itertuples(index=False), values):
                pred_rows.append({
                    "method_id": "method_a",
                    "split": split,
                    "origin_id": row.origin_id,
                    "horizon": row.horizon,
                    "tau": tau,
                    "pred_scaled": value,
                })
    pred = pd.DataFrame(pred_rows)
    coverage = summary_mod.validate_prediction_coverage(pred, [0.10, 0.50, 0.90])
    assert coverage["status"].tolist() == ["passed"]

    metrics, horizon_metrics, horizon_group = summary_mod.method_metrics(
        rows,
        pred,
        horizons=[1, 2],
        quantiles=[0.10, 0.50, 0.90],
        y_scaler=IdentityScaler(),
    )
    test_orig = metrics[(metrics["split"] == "test") & (metrics["unit"] == "original")]
    assert test_orig.shape[0] == 1
    assert test_orig["MAE"].iloc[0] == pytest.approx(0.5)
    assert test_orig["RMSE"].iloc[0] == pytest.approx(np.sqrt(0.5))
    assert test_orig["AQL"].iloc[0] > 0.0
    assert horizon_metrics["horizon"].nunique() == 2
    assert set(horizon_group["horizon_group"]) == {"1-24"}


def test_complete_summary_payload_records_complete_status(tmp_path):
    payload = {
        "grid": {"grid_id": "unit_grid"},
        "cells": pd.DataFrame({"complete": [True, True, True]}),
    }
    report = tmp_path / "paper_quantile_report.md"
    out = summary_mod.complete_summary_payload(tmp_path, payload, report)
    assert out["status"] == "complete"
    assert out["grid_id"] == "unit_grid"
    assert out["completed_cells"] == 3
    assert out["total_cells"] == 3
    assert out["metrics"].endswith("paper_quantile_metric_summary.csv")


def test_region_pricefm_reference_is_labeled_context_only(tmp_path):
    ref = tmp_path / "phase1_pretraining.csv"
    ref.write_text(
        "target_country,AQL,RMSE,MAE\n"
        "DE_LU,5.5,12.0,8.0\n"
        "FR,6.0,13.0,9.0\n"
    )
    loaded = summary_mod.load_reference(str(ref), "DE_LU")
    assert loaded.shape[0] == 1
    assert loaded["method_id"].iloc[0] == "pricefm_phase1_pretraining_reference"
    assert loaded["reference_scope"].iloc[0] == "region_level_external_csv"
    assert loaded["benchmark_role"].iloc[0] == "context_only_not_fold_aligned"


def test_region_panel_quantile_summary_wrapper_dry_run(tmp_path):
    spec = importlib.util.spec_from_file_location(
        "pricefm_region_panel_summary",
        ROOT / "application" / "scripts" / "pricefm" / "35_summarize_pricefm_region_panel_quantiles.py",
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    registry = tmp_path / "registry.csv"
    pd.DataFrame([
        {"region": "DE_LU", "fold": 1},
        {"region": "EE", "fold": 2},
    ]).to_csv(registry, index=False)
    scope = mod.registry_scope(registry, regions=["DE_LU"], folds=[1])
    assert scope.shape[0] == 1
    cmd = mod.command_for_row("grid.yaml", tmp_path / "out", "DE_LU", 1, True)
    assert "--region" in cmd
    assert "DE_LU" in cmd
    assert "--fold" in cmd
    assert "1" in cmd

    args = type("Args", (), {
        "registry_csv": str(registry),
        "grid_config": "grid.yaml",
        "output_root": str(tmp_path / "out"),
        "regions": "DE_LU",
        "folds": "1",
        "require_complete": True,
        "dry_run": True,
        "panel_label": "graph/local selected DESN/Q-DESN",
        "panel_description": "graph/local selected DESN/Q-DESN paper-quantile cells",
    })()
    summary = mod.summarize_panel(args)
    assert summary["status"] == "planned"
    status = pd.read_csv(tmp_path / "out" / "region_panel_quantile_summary_status.csv")
    assert status.shape[0] == 1
    assert status.loc[0, "status"] == "planned"
    report = (tmp_path / "out" / "region_panel_quantile_summary_report.md").read_text()
    assert "graph/local selected DESN/Q-DESN" in report


def test_region_panel_quantile_collector_accepts_existing_scope_columns(tmp_path):
    spec = importlib.util.spec_from_file_location(
        "pricefm_region_panel_summary",
        ROOT / "application" / "scripts" / "pricefm" / "35_summarize_pricefm_region_panel_quantiles.py",
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    registry = tmp_path / "registry.csv"
    pd.DataFrame([{"region": "DE_LU", "fold": 1}]).to_csv(registry, index=False)
    out_dir = tmp_path / "out" / "region=DE_LU" / "fold=1"
    out_dir.mkdir(parents=True)
    pd.DataFrame([
        {
            "region": "DE_LU",
            "fold": 1,
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "split": "test",
            "unit": "original",
            "AQL": 1.25,
        }
    ]).to_csv(out_dir / "paper_quantile_metric_summary.csv", index=False)
    pd.DataFrame([
        {"region": "DE_LU", "fold": 1, "status": "completed"}
    ]).to_csv(out_dir / "quantile_cell_status.csv", index=False)
    pd.DataFrame([
        {"region": "DE_LU", "fold": 1, "tau": 0.5, "max_rss_kb": 123}
    ]).to_csv(out_dir / "quantile_cell_runtime.csv", index=False)

    panel = mod.collect_panel_outputs(tmp_path / "out", mod.registry_scope(registry))

    assert panel["metric"].shape[0] == 1
    assert panel["metric"].columns[:2].tolist() == ["region", "fold"]
    assert panel["metric"].loc[0, "region"] == "DE_LU"
    assert int(panel["metric"].loc[0, "fold"]) == 1
    assert panel["status"].shape[0] == 1
    assert panel["runtime"].shape[0] == 1


def test_region_panel_quantile_collector_rejects_scope_mismatch(tmp_path):
    spec = importlib.util.spec_from_file_location(
        "pricefm_region_panel_summary",
        ROOT / "application" / "scripts" / "pricefm" / "35_summarize_pricefm_region_panel_quantiles.py",
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    registry = tmp_path / "registry.csv"
    pd.DataFrame([{"region": "DE_LU", "fold": 1}]).to_csv(registry, index=False)
    out_dir = tmp_path / "out" / "region=DE_LU" / "fold=1"
    out_dir.mkdir(parents=True)
    pd.DataFrame([
        {"region": "EE", "fold": 1, "method_id": "m", "split": "test", "unit": "original", "AQL": 1.0}
    ]).to_csv(out_dir / "paper_quantile_metric_summary.csv", index=False)

    with pytest.raises(ValueError, match="region values"):
        mod.collect_panel_outputs(tmp_path / "out", mod.registry_scope(registry))
