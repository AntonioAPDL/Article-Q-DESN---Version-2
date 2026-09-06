"""Tests for deterministic PriceFM R92 article-asset generation."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/290_build_pricefm_stage_r92_article_assets.py"
R92 = (
    ROOT
    / "application/data_local/pricefm/authoritative/pricefm_stage_r92_selective_promotion_20260905"
)
CONTEXT = ROOT / "tables/pricefm_paper_aligned_main_comparison.csv"


def load_script():
    spec = importlib.util.spec_from_file_location("pricefm_r92_article", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_builder(module, source: Path, context: Path, destination: Path):
    return module.run(
        SimpleNamespace(r92_dir=source, context_csv=context, table_dir=destination)
    )


def test_r92_article_assets_archive_context_and_publish_matched_metrics(tmp_path):
    if not R92.is_dir():
        pytest.skip("Materialized PriceFM R92 evidence is not available")
    module = load_script()
    context = tmp_path / "context.csv"
    shutil.copy2(CONTEXT, context)
    tables = tmp_path / "tables"
    result = run_builder(module, R92, context, tables)

    assert result["status"] == "completed"
    assert result["context_rows_preserved"] == 14
    assert result["promotion_rows"] == 12
    assert np.isclose(result["qdesn"]["AQL"], 6.823677420470439, atol=1e-12)
    assert np.isclose(result["qdesn"]["AQCR_percent"], 2.579293032015585, atol=1e-12)
    assert np.isclose(result["qdesn"]["MAE"], 16.721997707630997, atol=1e-12)
    assert np.isclose(result["qdesn"]["RMSE"], 25.449231419703835, atol=1e-12)

    original = pd.read_csv(context, dtype=str, keep_default_na=False)
    generated = pd.read_csv(
        tables / "pricefm_paper_aligned_main_comparison.csv",
        dtype=str,
        keep_default_na=False,
    )
    pd.testing.assert_frame_equal(
        original[original.panel.eq("paper_table_ii")].reset_index(drop=True),
        generated[generated.panel.eq("paper_table_ii")].reset_index(drop=True),
    )
    original_pricefm = original[original.model_family.eq("pricefm_phase1_released_checkpoint")]
    generated_pricefm = generated[generated.model_family.eq("pricefm_phase1_released_checkpoint")]
    pd.testing.assert_frame_equal(
        original_pricefm.reset_index(drop=True), generated_pricefm.reset_index(drop=True)
    )

    promotions = pd.read_csv(tables / "pricefm_r91_selective_promotions.csv")
    assert len(promotions) == 12
    assert promotions.iloc[0]["region"] == "IT_NORD"
    assert int(promotions.iloc[0]["fold"]) == 3
    assert np.isclose(promotions.iloc[-1]["AQL_gain"], 0.00010492623488733699, atol=1e-12)
    promotion_tex = (tables / "pricefm_r91_selective_promotions.tex").read_text()
    assert "0.000105" in promotion_tex
    assert "Selected Q--DESN AQL" in promotion_tex
    assert "Updated Q--DESN AQL" not in promotion_tex
    assert not (tables / "pricefm_paper_aligned_main_comparison.tex").exists()
    current_outputs = (
        tables / "pricefm_paper_aligned_current_outputs.tex"
    ).read_text()
    assert "PricefmPaperAlignedMainComparisonTable" not in current_outputs

    manifest_path = tables / "pricefm_paper_aligned_main_comparison_manifest.json"
    manifest = json.loads(manifest_path.read_text())
    assert manifest["protected_context"]["rows"] == 14
    assert manifest["applicability"]["cross_panel_comparison"] == "context_only_not_head_to_head"
    assert manifest["published_comparison"] == {
        "external_table_rows": 0,
        "overall_and_fold_table": "tables/pricefm_full_main_summary.tex",
        "horizon_table": "tables/pricefm_full_horizon_diagnostic_summary.tex",
    }
    assert len(manifest["outputs"]) == 4
    assert all(Path(row["path"]).parent == Path("tables") for row in manifest["outputs"])
    assert Path(manifest["generator"]["path"]).name == SCRIPT.name
    for row in manifest["outputs"]:
        path = tables / Path(row["path"]).name
        assert path.is_file()
        assert digest(path) == row["sha256"]
        assert path.stat().st_size == row["bytes"]

    first_hashes = {
        path.name: digest(path)
        for path in tables.iterdir()
        if path.is_file()
    }
    run_builder(
        module,
        R92,
        tables / "pricefm_paper_aligned_main_comparison.csv",
        tables,
    )
    second_hashes = {
        path.name: digest(path)
        for path in tables.iterdir()
        if path.is_file()
    }
    assert first_hashes == second_hashes


def test_r92_article_assets_reject_modified_table_ii_context(tmp_path):
    if not R92.is_dir():
        pytest.skip("Materialized PriceFM R92 evidence is not available")
    module = load_script()
    frame = pd.read_csv(CONTEXT, dtype=str, keep_default_na=False)
    row = frame.index[frame.model.eq("PriceFM")][0]
    frame.loc[row, "AQL"] = "5.81"
    context = tmp_path / "modified_context.csv"
    frame.to_csv(context, index=False, lineterminator="\n")
    with pytest.raises(RuntimeError, match="Table II context changed"):
        run_builder(module, R92, context, tmp_path / "tables")


def test_r92_article_assets_reject_mixed_direct_metric_generations(tmp_path):
    if not R92.is_dir():
        pytest.skip("Materialized PriceFM R92 evidence is not available")
    module = load_script()
    frame = pd.read_csv(CONTEXT, dtype=str, keep_default_na=False)
    summary = json.loads((R92 / "summary.json").read_text())
    row = frame.index[frame.model_family.eq("qdesn_case_specific")][0]
    frame.loc[row, "AQL"] = str(summary["historical_direct_comparison_metrics"]["qdesn"]["AQL"])
    context = tmp_path / "mixed_context.csv"
    frame.to_csv(context, index=False, lineterminator="\n")
    with pytest.raises(RuntimeError, match="mixes or changes metric generations"):
        run_builder(module, R92, context, tmp_path / "tables")


def test_r92_article_assets_reject_cross_file_key_mismatch():
    if not R92.is_dir():
        pytest.skip("Materialized PriceFM R92 evidence is not available")
    module = load_script()
    registry = pd.read_csv(R92 / "pricefm_full_surface_decision_registry.csv")
    promoted = pd.read_csv(R92 / "pricefm_stage_r92_promoted_case_metrics.csv")
    ledger = pd.read_csv(R92 / "pricefm_stage_r92_promotion_ledger.csv")
    promoted.loc[0, "region"] = "FAKE_REGION"
    with pytest.raises(RuntimeError, match="promotion set changed"):
        module.verify_r92_relations(registry, promoted, ledger)


def test_r92_article_assets_reject_tampered_container(tmp_path):
    if not R92.is_dir():
        pytest.skip("Materialized PriceFM R92 evidence is not available")
    module = load_script()
    source = tmp_path / "tampered_r92"
    shutil.copytree(R92, source)
    ledger_path = source / "pricefm_stage_r92_promotion_ledger.csv"
    ledger = pd.read_csv(ledger_path)
    ledger.loc[0, "AQL_gain"] = float(ledger.loc[0, "AQL_gain"]) + 1.0
    ledger.to_csv(ledger_path, index=False, lineterminator="\n")
    with pytest.raises(RuntimeError, match="promotion_ledger hash changed"):
        run_builder(module, source, CONTEXT, tmp_path / "tables")


def test_r92_article_assets_reject_manifest_path_escape():
    if not R92.is_dir():
        pytest.skip("Materialized PriceFM R92 evidence is not available")
    module = load_script()
    manifest = pd.read_csv(R92 / "source_manifest.csv")
    manifest.loc[0, "source_root"] = "article_repository"
    manifest.loc[0, "path"] = "../../outside"
    with pytest.raises(RuntimeError, match="escapes its declared root"):
        module.verify_source_manifest(manifest)
