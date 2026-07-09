"""Metadata-only tests for the PriceFM data-pipeline configuration."""

from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "application" / "config" / "pricefm_data_pipeline.yaml"


def load_pricefm():
    with open(CONFIG, "r") as f:
        return yaml.safe_load(f)["pricefm"]


def test_config_loads():
    cfg = load_pricefm()
    assert cfg["repo_id"] == "RunyaoYu/PriceFM"
    assert cfg["filename"] == "FINAL.csv"


def test_config_paths_are_article_local():
    cfg = load_pricefm()
    for key in ["raw_dir", "interim_dir", "processed_dir", "log_dir"]:
        path = Path(cfg[key])
        assert not path.is_absolute()
        assert str(path).startswith("application/")
    assert cfg["raw_dir"].startswith("application/data_local/pricefm/")
    assert cfg["interim_dir"].startswith("application/data_local/pricefm/")
    assert cfg["processed_dir"].startswith("application/data_local/pricefm/")


def test_config_regions_are_unique_and_expected():
    cfg = load_pricefm()
    assert len(cfg["regions"]) == 38
    assert len(cfg["regions"]) == len(set(cfg["regions"]))
    assert "DE_LU" in cfg["regions"]


def test_config_feature_sets_are_consistent():
    cfg = load_pricefm()
    features = cfg["features"]
    assert features["raw"] == ["generation", "load", "price", "solar", "wind"]
    assert features["label"] == "price"
    assert set(features["lag"]).issubset(set(features["raw"]))
    assert set(features["lead"]).issubset(set(features["raw"]))
    assert "generation" not in features["lag"]
    assert "generation" not in features["lead"]
    assert features["preserve_unused_raw_features"] is True


def test_config_split_boundaries_are_ordered_half_open():
    cfg = load_pricefm()
    assert cfg["split_time_col"] == "market_time"
    assert cfg["market_time_definition"] == "time_utc + 1 hour"
    for split in cfg["splits"]:
        train_start, train_end = split["train"]
        val_start, val_end = split["val"]
        test_start, test_end = split["test"]
        assert train_start < train_end
        assert train_end == val_start
        assert val_start < val_end
        assert val_end == test_start
        assert test_start < test_end


def test_config_pilot_target_is_de_lu_fold_1():
    cfg = load_pricefm()
    assert cfg["pilot"]["enabled"] is True
    assert cfg["pilot"]["region"] == "DE_LU"
    assert int(cfg["pilot"]["fold"]) == 1
    assert int(cfg["windows"]["lag_window"]) == 96
    assert int(cfg["windows"]["lead_window"]) == 96


def test_config_eda_region_feature_overview():
    cfg = load_pricefm()
    eda = cfg["eda"]["region_feature_overview"]
    assert eda["enabled"] is True
    assert eda["output_dir"].startswith("application/data_local/pricefm/")
    assert eda["time_index"] == "market_time"
    assert eda["aggregation"] == "daily"
    assert eda["summary_line"] in ["mean", "median"]
    assert eda["ribbon"] == [0.10, 0.90]
    assert eda["figure_format"] == "png"
