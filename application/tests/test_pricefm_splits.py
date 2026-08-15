"""Data-present tests for PriceFM split and scaler artifacts."""

import csv
import json
import os
from pathlib import Path

import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "application" / "config" / "pricefm_data_pipeline.yaml"
EXPECTED_ROWS = {
    (1, "train"): 93504,
    (1, "val"): 11712,
    (1, "test"): 11520,
    (2, "train"): 105216,
    (2, "val"): 11520,
    (2, "test"): 11808,
    (3, "train"): 116736,
    (3, "val"): 11808,
    (3, "test"): 11712,
}


def cfg():
    with open(CONFIG, "r") as f:
        return yaml.safe_load(f)["pricefm"]


def require_data_path(path):
    if path.exists():
        return
    if os.environ.get("PRICEFM_REQUIRE_DATA") == "1":
        pytest.fail("Required PriceFM artifact is missing: {}".format(path))
    pytest.skip("Local PriceFM data artifact is absent: {}".format(path))


def split_registry_rows():
    c = cfg()
    registry = ROOT / c["processed_dir"] / "splits" / "split_registry.csv"
    require_data_path(registry)
    with open(registry, "r") as f:
        return list(csv.DictReader(f))


def test_split_no_overlap_half_open():
    rows = split_registry_rows()
    by_fold = {}
    for row in rows:
        by_fold.setdefault(int(row["fold"]), {})[row["split"]] = row
    for fold, parts in by_fold.items():
        assert parts["train"]["end"] == parts["val"]["start"]
        assert parts["val"]["end"] == parts["test"]["start"]
        assert parts["train"]["mode"] == "half_open"
        assert parts["val"]["mode"] == "half_open"
        assert parts["test"]["mode"] == "half_open"


def test_split_expected_row_counts():
    rows = split_registry_rows()
    observed = {(int(row["fold"]), row["split"]): int(row["n_rows"]) for row in rows}
    assert observed == EXPECTED_ROWS


def test_split_registry_records_market_time_convention():
    c = cfg()
    rows = split_registry_rows()
    assert all(row["time_index"] == c["split_time_col"] for row in rows)
    assert all(row["market_time_definition"] == c["market_time_definition"] for row in rows)


def test_scalers_fitted_on_train_only():
    c = cfg()
    manifest = ROOT / c["processed_dir"] / "scalers" / "fold_1" / "scaling_manifest.json"
    require_data_path(manifest)
    with open(manifest, "r") as f:
        payload = json.load(f)
    assert payload["fit_on"] == "training split only"
    assert payload["fold"] == 1
    assert payload["scaling_mode"] == c["scaling"]["mode"]


def test_scaler_manifest_records_training_split_only():
    c = cfg()
    manifest = ROOT / c["processed_dir"] / "scalers" / "fold_1" / "scaling_manifest.json"
    require_data_path(manifest)
    with open(manifest, "r") as f:
        payload = json.load(f)
    assert payload["raw_split_dir"].endswith("processed/splits/fold_1")
    assert payload["scaled_split_dir"].endswith("processed/splits_scaled/fold_1")
    assert payload["x_features"] == c["features"]["lead"]
