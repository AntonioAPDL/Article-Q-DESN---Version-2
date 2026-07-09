"""Tests for PriceFM Stage-N manuscript asset export."""

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


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(__import__("json").dumps(payload))


def make_stage_m_fixture(tmp_path, fatal=False):
    article_dir = tmp_path / "article"
    audit_dir = tmp_path / "audit"
    fig_dir = tmp_path / "figures"
    fig_dir.mkdir()
    for name in [
        "stage_m_aql_delta_by_region_fold.png",
        "stage_m_local_wins_by_fold.png",
        "stage_m_current_validation_vs_test.png",
        "stage_m_rescue_validation_test_deltas.png",
    ]:
        (fig_dir / name).write_bytes(b"fake-png")

    write_json(article_dir / "summary.json", {
        "n_region_folds": 2,
        "n_local_wins": 1,
        "n_pricefm_wins": 1,
        "mean_delta_abs": -0.25,
        "comparison_scope": "fold_aligned_pricefm_phase1_selected_region_folds",
    })
    write_csv(article_dir / "article_table_region_fold_decisions.csv", [
        {
            "region": "A", "fold": 1, "best_local_method": "qdesn_al_rhs_ns_exact_chunked",
            "information_set": "target_only", "local_AQL": 8.0, "pricefm_AQL": 9.0,
            "delta_abs": -1.0, "delta_rel": -1.0 / 9.0, "decision_label": "local_beats_pricefm",
        },
        {
            "region": "B", "fold": 2, "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
            "information_set": "pricefm_graph_inputs", "local_AQL": 10.5,
            "pricefm_AQL": 10.0, "delta_abs": 0.5, "delta_rel": 0.05,
            "decision_label": "pricefm_better",
        },
    ])
    write_csv(article_dir / "article_table_fold_summary.csv", [
        {
            "fold": 1, "n_region_folds": 1, "n_local_wins": 1, "win_rate": 1.0,
            "mean_local_AQL": 8.0, "mean_pricefm_AQL": 9.0, "mean_delta_abs": -1.0,
        },
        {
            "fold": 2, "n_region_folds": 1, "n_local_wins": 0, "win_rate": 0.0,
            "mean_local_AQL": 10.5, "mean_pricefm_AQL": 10.0, "mean_delta_abs": 0.5,
        },
    ])
    write_csv(article_dir / "article_table_method_information_set_summary.csv", [
        {
            "summary_type": "method_family", "group": "qdesn_al", "n_region_folds": 1,
            "n_local_wins": 1, "win_rate": 1.0, "mean_delta_abs": -1.0,
            "median_delta_abs": -1.0,
        },
        {
            "summary_type": "information_set", "group": "pricefm_graph_inputs",
            "n_region_folds": 1, "n_local_wins": 0, "win_rate": 0.0,
            "mean_delta_abs": 0.5, "median_delta_abs": 0.5,
        },
    ])
    write_csv(article_dir / "article_table_validation_test_alignment.csv", [
        {
            "source_label": "unit_source", "n_rows": 2, "n_region_folds": 2,
            "n_validation_improved": 1, "n_test_improved": 1, "n_disagree": 1,
            "validation_win_rate": 0.5, "test_win_rate": 0.5,
            "disagree_rate": 0.5, "mean_val_delta": -0.1, "mean_test_delta": 0.2,
        },
    ])
    write_csv(article_dir / "article_figure_index.csv", [
        {"figure_group": "decision_surface", "figure_path": str(fig_dir / "stage_m_aql_delta_by_region_fold.png"), "filename": "stage_m_aql_delta_by_region_fold.png"},
        {"figure_group": "decision_surface", "figure_path": str(fig_dir / "stage_m_local_wins_by_fold.png"), "filename": "stage_m_local_wins_by_fold.png"},
        {"figure_group": "validation_alignment", "figure_path": str(fig_dir / "stage_m_current_validation_vs_test.png"), "filename": "stage_m_current_validation_vs_test.png"},
        {"figure_group": "validation_alignment", "figure_path": str(fig_dir / "stage_m_rescue_validation_test_deltas.png"), "filename": "stage_m_rescue_validation_test_deltas.png"},
    ])
    write_json(audit_dir / "summary.json", {
        "n_fatal_failures": 1 if fatal else 0,
        "n_regions": 2,
        "n_folds": 2,
        "n_graph_input_rows": 1,
        "n_target_only_rows": 1,
    })
    write_csv(audit_dir / "comparability_checks.csv", [
        {
            "check_id": "unit", "severity": "fatal",
            "status": "fail" if fatal else "pass", "observed": "unit",
            "detail": "unit check",
        },
    ])
    return article_dir, audit_dir


def test_stage_n_manuscript_export_writes_tracked_style_assets(tmp_path):
    mod = load_script("72_build_pricefm_manuscript_assets.py")
    article_dir, audit_dir = make_stage_m_fixture(tmp_path)
    args = SimpleNamespace(
        article_dir=str(article_dir),
        audit_dir=str(audit_dir),
        table_dir=str(tmp_path / "tables"),
        figure_dir=str(tmp_path / "article_figures"),
    )

    summary = mod.build(args)

    assert summary["n_region_folds"] == 2
    assert summary["n_local_wins"] == 1
    outputs = tmp_path / "tables" / "pricefm_stage_m_current_outputs.tex"
    assert outputs.exists()
    text = outputs.read_text()
    assert "\\PricefmStageMRegionFolds" in text
    assert "pricefm_stage_m_aql_delta_by_region_fold.png" in text
    assert (tmp_path / "tables" / "pricefm_stage_m_fold_summary.tex").exists()
    assert (tmp_path / "tables" / "pricefm_stage_m_article_asset_manifest.json").exists()
    assert len(list((tmp_path / "article_figures").glob("*.png"))) == 4


def test_stage_n_manuscript_export_stops_on_fatal_audit(tmp_path):
    mod = load_script("72_build_pricefm_manuscript_assets.py")
    article_dir, audit_dir = make_stage_m_fixture(tmp_path, fatal=True)
    args = SimpleNamespace(
        article_dir=str(article_dir),
        audit_dir=str(audit_dir),
        table_dir=str(tmp_path / "tables"),
        figure_dir=str(tmp_path / "article_figures"),
    )

    with pytest.raises(ValueError, match="fatal"):
        mod.build(args)
