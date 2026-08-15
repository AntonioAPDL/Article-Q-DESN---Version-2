"""Tests for PriceFM region-panel median grid preparation."""

from pathlib import Path
import importlib.util
import sys

import pandas as pd
import yaml


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


def score_frame():
    return pd.DataFrame([
        {
            "region": "DE_LU", "phase1_AQL": 5.0, "phase1_MAE": 10.0,
            "phase1_RMSE": 20.0, "median": 100.0, "spread_p99_p01": 500.0,
            "negative_rate": 0.04, "zero_rate": 0.0, "min": -10.0,
            "p01": -1.0, "p99": 499.0, "max": 600.0, "tail_range": 610.0,
        },
        {
            "region": "EE", "phase1_AQL": 15.0, "phase1_MAE": 20.0,
            "phase1_RMSE": 30.0, "median": 90.0, "spread_p99_p01": 480.0,
            "negative_rate": 0.01, "zero_rate": 0.0, "min": -1.0,
            "p01": 0.0, "p99": 480.0, "max": 700.0, "tail_range": 701.0,
        },
        {
            "region": "HU", "phase1_AQL": 7.0, "phase1_MAE": 15.0,
            "phase1_RMSE": 25.0, "median": 110.0, "spread_p99_p01": 590.0,
            "negative_rate": 0.02, "zero_rate": 0.0, "min": -20.0,
            "p01": -2.0, "p99": 588.0, "max": 800.0, "tail_range": 820.0,
        },
        {
            "region": "NO_4", "phase1_AQL": 3.0, "phase1_MAE": 7.0,
            "phase1_RMSE": 10.0, "median": 15.0, "spread_p99_p01": 100.0,
            "negative_rate": 0.02, "zero_rate": 0.0, "min": -5.0,
            "p01": -1.0, "p99": 99.0, "max": 150.0, "tail_range": 155.0,
        },
        {
            "region": "SE_2", "phase1_AQL": 4.0, "phase1_MAE": 8.0,
            "phase1_RMSE": 11.0, "median": 20.0, "spread_p99_p01": 200.0,
            "negative_rate": 0.06, "zero_rate": 0.0, "min": -5.0,
            "p01": -1.0, "p99": 199.0, "max": 250.0, "tail_range": 255.0,
        },
        {
            "region": "IT_SICI", "phase1_AQL": 4.5, "phase1_MAE": 9.0,
            "phase1_RMSE": 12.0, "median": 130.0, "spread_p99_p01": 550.0,
            "negative_rate": 0.0, "zero_rate": 0.0, "min": 0.0,
            "p01": 10.0, "p99": 560.0, "max": 900.0, "tail_range": 900.0,
        },
    ])


def test_region_panel_selection_is_role_based_and_deduplicated():
    mod = load_script("33_prepare_pricefm_region_panel_median_grid.py")
    panel = mod.select_region_panel(score_frame(), required_regions=["DE_LU"], panel_size=6)

    assert panel["region"].tolist() == ["DE_LU", "EE", "HU", "NO_4", "SE_2", "IT_SICI"]
    assert panel["selection_role"].tolist() == [
        "anchor_required",
        "hardest_phase1_aql",
        "widest_price_spread",
        "narrowest_price_spread",
        "highest_negative_price_rate",
        "highest_median_price",
    ]


def test_region_panel_grid_has_bounded_cell_count(tmp_path):
    mod = load_script("33_prepare_pricefm_region_panel_median_grid.py")
    template_path = (
        ROOT
        / "application"
        / "config"
        / "pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml"
    )
    template = yaml.safe_load(template_path.read_text())
    panel = mod.select_region_panel(score_frame(), required_regions=["DE_LU"], panel_size=6)
    payload = mod.build_grid(
        template,
        "unit_region_panel",
        tmp_path / "generated",
        tmp_path / "runs",
        panel,
        [1, 2, 3],
    )
    cell_summary = mod.planned_cell_summary(panel, payload)
    grid = payload["pricefm_desn_experiment_grid"]

    assert grid["scope"]["regions"] == ["DE_LU", "EE", "HU", "NO_4", "SE_2", "IT_SICI"]
    assert grid["scope"]["folds"] == [1, 2, 3]
    assert grid["scope"]["quantiles"] == [0.50]
    assert len(grid["experiments"]) == 6
    assert int(cell_summary["n_cells"].sum()) == 108
    assert set(cell_summary["priority"]) == {0, 1}
    assert grid["fixed"]["shrink_intercept"] is False
    assert grid["fixed"]["qdesn_likelihoods"] == ["al", "exal"]


def stage_b_scores():
    rows = []
    for region, aql, spread, neg in [
        ("PT", 5.8, 277.0, 0.013),
        ("BG", 9.1, 547.0, 0.007),
        ("ES", 5.7, 278.0, 0.024),
        ("FR", 5.6, 579.0, 0.029),
        ("FI", 6.7, 463.0, 0.049),
        ("IT_NORD", 4.6, 579.0, 0.000),
        ("AT", 6.2, 556.0, 0.022),
        ("PL", 7.0, 348.0, 0.016),
        ("DE_LU", 5.5, 500.0, 0.020),
    ]:
        rows.append({
            "region": region,
            "phase1_AQL": aql,
            "phase1_MAE": 2.5 * aql,
            "phase1_RMSE": 4.0 * aql,
            "median": 100.0,
            "spread_p99_p01": spread,
            "tail_range": spread + 500.0,
            "negative_rate": neg,
            "zero_rate": 0.0,
            "min": -10.0,
            "p01": 1.0,
            "p99": spread + 1.0,
            "max": spread + 490.0,
        })
    return pd.DataFrame(rows)


def stage_b_regions():
    return [
        "AT", "BE", "BG", "CZ", "DE_LU", "DK_1", "DK_2", "EE", "ES",
        "FI", "FR", "GR", "HR", "HU", "IT_CALA", "IT_CNOR", "IT_CSUD",
        "IT_NORD", "IT_SARD", "IT_SICI", "IT_SUD", "LT", "LV", "NL",
        "NO_1", "NO_2", "NO_3", "NO_4", "NO_5", "PL", "PT", "RO",
        "SE_1", "SE_2", "SE_3", "SE_4", "SI", "SK",
    ]


def test_stage_b_region_manifest_is_uncovered_and_graph_aware():
    mod = load_script("46_prepare_pricefm_stage_b_region_batch.py")
    candidate_regions = ["PT", "BG", "ES", "FR", "FI", "IT_NORD", "AT", "PL"]
    manifest = mod.build_region_manifest(
        stage_b_scores(),
        candidate_regions,
        stage_b_regions(),
        covered={"DE_LU", "EE", "HU", "IT_SICI", "NO_4", "SE_2"},
        allow_covered=False,
    )

    assert manifest["region"].tolist() == candidate_regions
    assert not manifest["already_covered"].any()
    assert manifest.loc[manifest["region"].eq("PT"), "degree1_n"].iloc[0] == 2
    assert manifest.loc[manifest["region"].eq("AT"), "degree1_n"].iloc[0] == 6
    assert manifest.loc[manifest["region"].eq("PL"), "selection_role"].iloc[0] == "high_graph_degree_hard_region"


def test_stage_b_region_manifest_rejects_covered_regions():
    mod = load_script("46_prepare_pricefm_stage_b_region_batch.py")
    import pytest

    with pytest.raises(ValueError, match="already covered"):
        mod.build_region_manifest(
            stage_b_scores(),
            ["DE_LU", "PT"],
            stage_b_regions(),
            covered={"DE_LU"},
            allow_covered=False,
        )


def test_stage_b_grid_is_local_first_and_bounded(tmp_path):
    mod = load_script("46_prepare_pricefm_stage_b_region_batch.py")
    template_path = ROOT / "application" / "config" / "pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
    template = yaml.safe_load(template_path.read_text())
    candidate_regions = ["PT", "BG", "ES", "FR", "FI", "IT_NORD", "AT", "PL"]
    manifest = mod.build_region_manifest(
        stage_b_scores(),
        candidate_regions,
        stage_b_regions(),
        covered={"DE_LU", "EE", "HU", "IT_SICI", "NO_4", "SE_2"},
        allow_covered=False,
    )
    payload = mod.build_grid(
        template,
        "unit_stage_b",
        tmp_path / "generated",
        tmp_path / "runs",
        manifest,
        [1, 2, 3],
    )
    grid = payload["pricefm_desn_experiment_grid"]
    cell_summary = mod.planned_cell_summary(manifest, payload)

    assert grid["scope"]["regions"] == candidate_regions
    assert grid["scope"]["folds"] == [1, 2, 3]
    assert grid["fixed"]["feature_policy"] == "target_only"
    assert len(grid["experiments"]) == 6
    assert {exp["feature_policy"] for exp in grid["experiments"]} == {"target_only"}
    assert {exp["spatial_information_set"] for exp in grid["experiments"]} == {"local_only_not_pricefm_graph"}
    assert cell_summary[cell_summary["priority"].eq(0)]["n_cells"].sum() == 72
    assert cell_summary["n_cells"].sum() == 144
