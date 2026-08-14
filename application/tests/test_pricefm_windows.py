"""Data-present tests for PriceFM pilot rolling-window artifacts."""

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
    pytest.skip("Local PriceFM data artifact is absent: {}".format(path))


def manifest_for(split, mode):
    c = cfg()
    fold = int(c["pilot"]["fold"])
    region = c["pilot"]["region"]
    stem = "{}_L{}_H{}_{}.manifest.json".format(
        split,
        int(c["windows"]["lag_window"]),
        int(c["windows"]["lead_window"]),
        mode,
    )
    path = ROOT / c["processed_dir"] / "windows" / "fold_{}".format(fold) / "region={}".format(region) / stem
    require_data_path(path)
    with open(path, "r") as f:
        return json.load(f)


def test_window_shapes_L96_H96():
    c = cfg()
    payload = manifest_for("train", c["windows"]["train_boundary_mode"])
    assert payload["X_lag_shape"][1:] == [96, len(c["features"]["lag"])]
    assert payload["X_lead_shape"][1:] == [96, len(c["features"]["lead"])]
    assert payload["Y_shape"][1:] == [96]


def test_window_anchor_times_are_midnight_utc():
    c = cfg()
    payload = manifest_for("train", c["windows"]["train_boundary_mode"])
    assert payload["time_index"] == "market_time"
    assert payload["target_start"].endswith("01")
    assert payload["market_time_definition"] == c["market_time_definition"]


def test_window_lead_targets_inside_split():
    c = cfg()
    train = manifest_for("train", c["windows"]["train_boundary_mode"])
    val = manifest_for("val", c["windows"]["validation_boundary_mode"])
    test = manifest_for("test", c["windows"]["test_boundary_mode"])
    assert train["target_start"] == c["splits"][0]["train"][0]
    assert train["target_end"] == c["splits"][0]["train"][1]
    assert val["target_start"] == c["splits"][0]["val"][0]
    assert val["target_end"] == c["splits"][0]["val"][1]
    assert test["target_start"] == c["splits"][0]["test"][0]
    assert test["target_end"] == c["splits"][0]["test"][1]


def test_operational_windows_have_valid_lag_history():
    c = cfg()
    val = manifest_for("val", c["windows"]["validation_boundary_mode"])
    test = manifest_for("test", c["windows"]["test_boundary_mode"])
    assert val["context"] == "train+val"
    assert test["context"] == "train+val+test"
    assert val["context_start"] < val["target_start"]
    assert test["context_start"] < test["target_start"]


def test_window_manifest_records_context_and_target_bounds():
    c = cfg()
    payload = manifest_for("test", c["windows"]["test_boundary_mode"])
    for key in ["context_start", "context_end", "target_start", "target_end"]:
        assert key in payload
        assert payload[key]
    assert payload["region"] == c["pilot"]["region"]
    assert int(payload["fold"]) == int(c["pilot"]["fold"])
