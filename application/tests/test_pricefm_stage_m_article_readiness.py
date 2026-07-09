"""Tests for Stage-M PriceFM article-readiness tooling."""

import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace

import pandas as pd
import pytest


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


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def test_stage_m_decision_surface_summarizes_wins_and_information_sets(tmp_path):
    mod = load_script("68_summarize_pricefm_current_decision_surface.py")
    write_csv(tmp_path / "median.csv", [
        {"region": "A", "fold": 1, "selection_AQL": 10.0, "test_AQL": 9.0},
        {"region": "B", "fold": 1, "selection_AQL": 11.0, "test_AQL": 12.0},
    ])
    write_csv(tmp_path / "quantile.csv", [
        {
            "region": "A", "fold": 1, "best_local_method": "qdesn_al_rhs_ns_exact_chunked",
            "local_AQL": 8.0, "pricefm_AQL": 9.0, "delta_abs": -1.0,
            "feature_policy": "target_only", "input_scope": "local_target_only",
        },
        {
            "region": "B", "fold": 1, "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
            "local_AQL": 11.0, "pricefm_AQL": 10.0, "delta_abs": 1.0,
            "feature_policy": "graph_khop", "input_scope": "pricefm_graph_khop_degree1",
        },
    ])
    args = SimpleNamespace(
        median_registry_csv=str(tmp_path / "median.csv"),
        quantile_decision_registry_csv=str(tmp_path / "quantile.csv"),
        output_dir=str(tmp_path / "out"),
        expected_region_folds=2,
        make_figures=False,
    )

    summary = mod.summarize(args)
    surface = pd.read_csv(tmp_path / "out" / "current_decision_surface_table.csv")
    by_info = pd.read_csv(tmp_path / "out" / "aggregate_by_information_set.csv")

    assert summary["n_region_folds"] == 2
    assert summary["n_local_wins"] == 1
    assert set(surface["information_set"]) == {"target_only", "pricefm_graph_inputs"}
    assert set(by_info["information_set"]) == {"target_only", "pricefm_graph_inputs"}


def test_stage_m_decision_surface_rejects_duplicate_quantile_keys(tmp_path):
    mod = load_script("68_summarize_pricefm_current_decision_surface.py")
    write_csv(tmp_path / "median.csv", [
        {"region": "A", "fold": 1, "selection_AQL": 10.0, "test_AQL": 9.0},
    ])
    write_csv(tmp_path / "quantile.csv", [
        {"region": "A", "fold": 1, "local_AQL": 8.0, "pricefm_AQL": 9.0, "delta_abs": -1.0},
        {"region": "A", "fold": 1, "local_AQL": 8.1, "pricefm_AQL": 9.0, "delta_abs": -0.9},
    ])
    args = SimpleNamespace(
        median_registry_csv=str(tmp_path / "median.csv"),
        quantile_decision_registry_csv=str(tmp_path / "quantile.csv"),
        output_dir=str(tmp_path / "out"),
        expected_region_folds=1,
        make_figures=False,
    )

    with pytest.raises(ValueError, match="duplicate"):
        mod.summarize(args)


def test_stage_m_validation_test_alignment_labels_disagreements(tmp_path):
    mod = load_script("69_audit_pricefm_validation_test_alignment.py")
    write_csv(tmp_path / "median.csv", [
        {"region": "A", "fold": 1, "selected_method_id": "qdesn_al_rhs_ns_exact_chunked", "selection_AQL": 10.0, "test_AQL": 9.0},
        {"region": "B", "fold": 1, "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked", "selection_AQL": 11.0, "test_AQL": 12.0},
    ])
    write_csv(tmp_path / "diag.csv", [
        {
            "region": "A", "fold": 1, "experiment_id": "a", "method_id": "qdesn_al_rhs_ns_exact_chunked",
            "selection_AQL": 9.0, "test_AQL": 8.0,
            "current_selection_AQL": 10.0, "current_test_AQL": 9.0,
        },
        {
            "region": "B", "fold": 1, "experiment_id": "b", "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "selection_AQL": 12.0, "test_AQL": 10.0,
            "current_selection_AQL": 11.0, "current_test_AQL": 12.0,
        },
    ])
    args = SimpleNamespace(
        median_registry_csv=str(tmp_path / "median.csv"),
        diagnostic_source=["unit={}".format(tmp_path / "diag.csv")],
        output_dir=str(tmp_path / "out"),
        make_figures=False,
    )

    summary = mod.summarize(args)
    rows = pd.read_csv(tmp_path / "out" / "diagnostic_validation_test_rows.csv")
    mismatch = pd.read_csv(tmp_path / "out" / "validation_test_mismatch_cases.csv")

    assert summary["n_diagnostic_rows"] == 2
    assert summary["n_mismatch_rows"] == 1
    assert set(rows["alignment_label"]) == {"both_improved", "test_only"}
    assert set(mismatch["alignment_label"]) == {"test_only"}


def test_stage_m_article_tables_package_outputs(tmp_path):
    mod = load_script("70_build_pricefm_article_tables.py")
    decision_dir = tmp_path / "decision"
    alignment_dir = tmp_path / "alignment"
    split_dir = tmp_path / "split"
    write_csv(decision_dir / "current_decision_surface_table.csv", [
        {
            "region": "A", "fold": 1, "best_local_method": "qdesn_al_rhs_ns_exact_chunked",
            "information_set": "target_only", "local_AQL": 8.0, "pricefm_AQL": 9.0,
            "delta_abs": -1.0, "delta_rel": -0.1, "decision_label": "local_beats_pricefm",
        },
    ])
    write_csv(decision_dir / "aggregate_by_fold.csv", [
        {
            "fold": 1, "n_region_folds": 1, "n_local_wins": 1, "win_rate": 1.0,
            "mean_local_AQL": 8.0, "mean_pricefm_AQL": 9.0, "mean_delta_abs": -1.0,
        },
    ])
    write_csv(decision_dir / "aggregate_by_method_family.csv", [
        {
            "model_family": "qdesn_al", "n_region_folds": 1, "n_local_wins": 1,
            "win_rate": 1.0, "mean_delta_abs": -1.0, "median_delta_abs": -1.0,
        },
    ])
    write_csv(decision_dir / "aggregate_by_information_set.csv", [
        {
            "information_set": "target_only", "n_region_folds": 1, "n_local_wins": 1,
            "win_rate": 1.0, "mean_delta_abs": -1.0, "median_delta_abs": -1.0,
        },
    ])
    write_csv(alignment_dir / "diagnostic_source_summary.csv", [
        {
            "source_label": "unit", "n_rows": 1, "n_region_folds": 1,
            "n_validation_improved": 1, "n_test_improved": 1, "n_disagree": 0,
            "validation_win_rate": 1.0, "test_win_rate": 1.0, "disagree_rate": 0.0,
            "mean_val_delta": -1.0, "mean_test_delta": -1.0,
        },
    ])
    write_csv(split_dir / "split_response_contrasts.csv", [
        {"region": "A", "fold": 1, "contrast": "val_minus_train", "mean_delta": -0.1, "sd_ratio": 0.9, "median_delta": -0.2},
    ])
    args = SimpleNamespace(
        decision_dir=str(decision_dir),
        alignment_dir=str(alignment_dir),
        split_diagnostics_dir=str(split_dir),
        output_dir=str(tmp_path / "article"),
    )

    summary = mod.build(args)

    assert summary["n_region_folds"] == 1
    assert summary["comparison_scope"] == "fold_aligned_pricefm_phase1_selected_region_folds"
    assert (tmp_path / "article" / "article_comparability_guardrails.csv").exists()
    assert (tmp_path / "article" / "article_table_region_fold_decisions.csv").exists()
    report = tmp_path / "article" / "pricefm_stage_m_article_tables_report.md"
    assert report.exists()
    assert "Comparability Contract" in report.read_text()


def test_stage_m_comparability_audit_records_scope_and_claim_guardrails(tmp_path):
    mod = load_script("71_audit_pricefm_stage_m_comparability.py")
    decision_dir = tmp_path / "decision"
    article_dir = tmp_path / "article"
    write_csv(decision_dir / "current_decision_surface_table.csv", [
        {
            "region": "A", "fold": 1, "best_local_method": "qdesn_al_rhs_ns_exact_chunked",
            "information_set": "target_only", "local_AQL": 8.0, "pricefm_AQL": 9.0,
            "delta_abs": -1.0, "delta_rel": -1.0 / 9.0,
            "decision_label": "local_beats_pricefm",
            "spatial_information_set": "local_only_not_pricefm_graph",
            "experiment_id": "stagec_a",
        },
        {
            "region": "B", "fold": 1, "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
            "information_set": "pricefm_graph_inputs", "local_AQL": 10.3,
            "pricefm_AQL": 10.0, "delta_abs": 0.3, "delta_rel": 0.03,
            "decision_label": "local_close_to_pricefm",
            "spatial_information_set": "pricefm_released_graph_khop",
            "experiment_id": "stagef_b",
        },
    ])
    write_csv(article_dir / "article_table_region_fold_decisions.csv", [
        {
            "region": "A", "fold": 1, "best_local_method": "qdesn_al_rhs_ns_exact_chunked",
            "information_set": "target_only", "local_AQL": 8.0, "pricefm_AQL": 9.0,
            "delta_abs": -1.0, "delta_rel": -1.0 / 9.0,
            "decision_label": "local_beats_pricefm",
        },
        {
            "region": "B", "fold": 1, "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
            "information_set": "pricefm_graph_inputs", "local_AQL": 10.3,
            "pricefm_AQL": 10.0, "delta_abs": 0.3, "delta_rel": 0.03,
            "decision_label": "local_close_to_pricefm",
        },
    ])
    write_csv(article_dir / "article_comparability_guardrails.csv", [
        {
            "topic": "scope", "status": "comparable_with_scope_limits",
            "article_language": "scoped", "avoid_language": "overall",
        },
    ])
    write_csv(tmp_path / "quantile.csv", [
        {"region": "A", "fold": 1},
        {"region": "B", "fold": 1},
    ])
    args = SimpleNamespace(
        decision_dir=str(decision_dir),
        article_dir=str(article_dir),
        quantile_registry_csv=str(tmp_path / "quantile.csv"),
        output_dir=str(tmp_path / "audit"),
        expected_region_folds=2,
    )

    summary = mod.audit(args)

    checks = pd.read_csv(tmp_path / "audit" / "comparability_checks.csv")
    claims = pd.read_csv(tmp_path / "audit" / "article_claim_guardrails.csv")
    report = tmp_path / "audit" / "pricefm_stage_m_comparability_audit_report.md"
    assert summary["n_fatal_failures"] == 0
    assert set(checks["status"]) == {"pass"}
    assert "Q-DESN outperforms PriceFM overall." in set(claims["forbidden_wording"])
    assert "Comparability Scope" in report.read_text()
