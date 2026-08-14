"""Data-present tests for PriceFM raw/interim audit artifacts."""

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


def test_raw_file_exists():
    c = cfg()
    path = ROOT / c["raw_dir"] / c["filename"]
    require_data_path(path)
    assert path.stat().st_size > 0


def test_raw_sha256_matches_manifest():
    c = cfg()
    manifest_path = ROOT / c["raw_dir"] / "download_manifest.json"
    require_data_path(manifest_path)
    with open(manifest_path, "r") as f:
        manifest = json.load(f)
    assert manifest["sha256_local"] == c["source"]["hf_sha256_expected"]


def test_raw_manifest_records_hf_revision_and_github_commit():
    c = cfg()
    manifest_path = ROOT / c["raw_dir"] / "download_manifest.json"
    require_data_path(manifest_path)
    with open(manifest_path, "r") as f:
        manifest = json.load(f)
    assert manifest["dataset_revision"]
    assert manifest["github_commit"]
    assert manifest["dataset_repo_id"] == c["repo_id"]


def test_parquet_time_range():
    c = cfg()
    audit_path = ROOT / c["interim_dir"] / "audit_time.json"
    require_data_path(audit_path)
    with open(audit_path, "r") as f:
        audit = json.load(f)
    assert audit["min_time"] == c["observed_start_utc"]
    assert audit["max_time"] == c["observed_end_utc"]
    assert audit["market_time_definition"] == c["market_time_definition"]


def test_parquet_timestamp_count_140257():
    c = cfg()
    audit_path = ROOT / c["interim_dir"] / "audit_time.json"
    require_data_path(audit_path)
    with open(audit_path, "r") as f:
        audit = json.load(f)
    assert audit["n_rows"] == int(c["expected_rows"])
    assert audit["expected_rows"] == int(c["expected_rows"])


def test_parquet_column_count_191():
    c = cfg()
    audit_path = ROOT / c["interim_dir"] / "audit_time.json"
    require_data_path(audit_path)
    with open(audit_path, "r") as f:
        audit = json.load(f)
    assert audit["n_columns"] == int(c["expected_columns"])
    assert audit["expected_columns"] == int(c["expected_columns"])


def test_no_duplicate_timestamps():
    c = cfg()
    audit_path = ROOT / c["interim_dir"] / "audit_time.json"
    require_data_path(audit_path)
    with open(audit_path, "r") as f:
        audit = json.load(f)
    assert audit["n_duplicate_timestamps"] == 0
    assert audit["index_is_unique"] is True


def test_no_missing_15min_timestamps():
    c = cfg()
    audit_path = ROOT / c["interim_dir"] / "audit_time.json"
    require_data_path(audit_path)
    with open(audit_path, "r") as f:
        audit = json.load(f)
    assert audit["n_missing_expected_timestamps"] == 0
    assert audit["n_extra_timestamps"] == 0


def test_expected_raw_region_feature_columns():
    c = cfg()
    manifest_path = ROOT / c["interim_dir"] / "schema_manifest.json"
    require_data_path(manifest_path)
    with open(manifest_path, "r") as f:
        manifest = json.load(f)
    assert manifest["missing_expected_columns"] == []
    assert manifest["raw_features"] == c["features"]["raw"]


def test_default_model_features_are_available():
    c = cfg()
    manifest_path = ROOT / c["interim_dir"] / "schema_manifest.json"
    require_data_path(manifest_path)
    with open(manifest_path, "r") as f:
        manifest = json.load(f)
    assert manifest["default_model_lag_features"] == c["features"]["lag"]
    assert manifest["default_model_lead_features"] == c["features"]["lead"]
