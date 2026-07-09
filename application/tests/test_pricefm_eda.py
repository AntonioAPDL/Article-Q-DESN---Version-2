"""Data-present tests for PriceFM exploratory region figures."""

import csv
import json
import os
from pathlib import Path

import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "application" / "config" / "pricefm_data_pipeline.yaml"


def cfg():
    with open(CONFIG, "r") as f:
        return yaml.safe_load(f)["pricefm"]


def require_data_path(path):
    if path.exists():
        return
    if os.environ.get("PRICEFM_REQUIRE_DATA") == "1":
        pytest.fail("Required PriceFM artifact is missing: {}".format(path))
    pytest.skip("Local PriceFM EDA artifact is absent: {}".format(path))


def test_region_feature_overview_manifest():
    c = cfg()
    eda = c["eda"]["region_feature_overview"]
    manifest_path = ROOT / eda["output_dir"] / "region_feature_overview_manifest.json"
    require_data_path(manifest_path)
    with open(manifest_path, "r") as f:
        manifest = json.load(f)
    assert manifest["n_regions"] == 38
    assert manifest["features"] == c["features"]["raw"]
    assert manifest["time_index"] == c["split_time_col"]
    assert manifest["market_time_definition"] == c["market_time_definition"]


def test_region_feature_overview_index_has_all_regions():
    c = cfg()
    eda = c["eda"]["region_feature_overview"]
    index_path = ROOT / eda["output_dir"] / "region_feature_overview_index.csv"
    require_data_path(index_path)
    with open(index_path, "r") as f:
        rows = list(csv.DictReader(f))
    assert len(rows) == 38
    assert sorted(row["region"] for row in rows) == sorted(c["regions"])


def test_region_feature_overview_files_exist_and_are_nonempty():
    c = cfg()
    eda = c["eda"]["region_feature_overview"]
    index_path = ROOT / eda["output_dir"] / "region_feature_overview_index.csv"
    require_data_path(index_path)
    with open(index_path, "r") as f:
        rows = list(csv.DictReader(f))
    for row in rows:
        fig_path = Path(row["figure"])
        require_data_path(fig_path)
        assert fig_path.suffix == ".{}".format(eda["figure_format"])
        assert fig_path.stat().st_size > 10000
