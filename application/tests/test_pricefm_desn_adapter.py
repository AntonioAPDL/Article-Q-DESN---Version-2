"""Tests for the PriceFM DESN direct-horizon adapter."""

import copy
import json
import os
import sys
from pathlib import Path

import numpy as np
import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "application" / "scripts" / "pricefm"))

from pricefm_desn_adapter import (  # noqa: E402
    build_adapter,
    load_smoke_config,
    make_design_chunked,
    normalize_reservoir_config,
    sha256_json,
)


SMOKE_CONFIG = ROOT / "application" / "config" / "pricefm_desn_model_smoke.yaml"


def synthetic_window(n_origins=3, lag_window=4, lead_window=5, lag_dim=2, lead_dim=3):
    rng = np.random.default_rng(20260601)
    return {
        "path": Path("synthetic_window.npz"),
        "manifest": {},
        "X_lag": rng.normal(size=(n_origins, lag_window, lag_dim)),
        "X_lead": rng.normal(size=(n_origins, lead_window, lead_dim)),
        "Y": rng.normal(size=(n_origins, lead_window)),
        "anchors": np.asarray([
            "2024-01-01T{:02d}:00:00Z".format(i) for i in range(n_origins)
        ]),
        "lag_cols": ["lag_{}".format(i) for i in range(lag_dim)],
        "lead_cols": ["lead_{}".format(i) for i in range(lead_dim)],
    }


def require_window_data():
    cfg = load_smoke_config(SMOKE_CONFIG)
    path = ROOT / "application" / "data_local" / "pricefm" / "processed" / "windows" / "fold_1" / "region=DE_LU" / "train_L96_H96_contained_half_open.npz"
    if path.exists():
        return
    if os.environ.get("PRICEFM_REQUIRE_DATA") == "1":
        pytest.fail("Required PriceFM window artifact is missing: {}".format(path))
    pytest.skip("Local PriceFM window artifact is absent: {}".format(path))


def write_temp_config(tmp_path):
    with open(SMOKE_CONFIG, "r") as f:
        payload = yaml.safe_load(f)
    cfg = copy.deepcopy(payload)
    cfg["pricefm_desn_smoke"]["adapter"]["output_dir"] = str(tmp_path / "adapter")
    cfg_path = tmp_path / "smoke.yaml"
    with open(cfg_path, "w") as f:
        yaml.safe_dump(cfg, f, sort_keys=False)
    return cfg_path


def test_smoke_config_records_expected_scope():
    cfg = load_smoke_config(SMOKE_CONFIG)
    assert cfg["region"] == "DE_LU"
    assert int(cfg["fold"]) == 1
    assert cfg["horizons"] == [1, 24, 48, 72, 96]
    assert cfg["quantiles"] == [0.05, 0.25, 0.50]
    assert cfg["adapter"]["feature_map"] == "window_desn_v1"


def test_adapter_builds_reproducible_stacked_rows(tmp_path):
    require_window_data()
    cfg_path = write_temp_config(tmp_path)
    first = build_adapter(str(cfg_path), force=True)
    adapter_dir = tmp_path / "adapter"
    with open(adapter_dir / "adapter_manifest.json", "r") as f:
        manifest = json.load(f)
    assert manifest["layout"] == "stacked_origin_by_horizon"
    assert manifest["splits"]["train"]["n_rows"] == 4865
    assert manifest["splits"]["val"]["n_rows"] == 610
    assert manifest["splits"]["test"]["n_rows"] == 600
    assert manifest["splits"]["train"]["n_features"] == 31

    second = build_adapter(str(cfg_path), force=True)
    assert first["splits"]["train"]["X_sha256"] == second["splits"]["train"]["X_sha256"]
    assert first["row_manifest_sha256"] == second["row_manifest_sha256"]


def test_adapter_can_cap_train_origins_before_building_design(tmp_path):
    require_window_data()
    cfg_path = write_temp_config(tmp_path)
    with open(cfg_path, "r") as f:
        cfg = yaml.safe_load(f)
    cfg["pricefm_desn_smoke"]["training"] = {
        "train_origin_limit": 2,
        "train_origin_selection": "tail",
    }
    cfg["pricefm_desn_smoke"]["adapter"]["row_chunk_size"] = 3
    with open(cfg_path, "w") as f:
        yaml.safe_dump(cfg, f, sort_keys=False)

    manifest = build_adapter(str(cfg_path), force=True)
    assert manifest["train_origin_subset"]["requested"] == 2
    assert manifest["train_origin_subset"]["selected"] == 2
    assert manifest["train_origin_subset"]["selection"] == "tail"
    assert manifest["splits"]["train"]["n_rows"] == 2 * len(cfg["pricefm_desn_smoke"]["horizons"])
    assert manifest["splits"]["train"]["n_features"] == 31
    assert manifest["feature_manifest"]["projection_scale"] == 1.0
    assert manifest["splits"]["train"]["activation_summary"]["count"] > 0


def test_adapter_records_projection_scale_and_activation_summary(tmp_path):
    require_window_data()
    cfg_path = write_temp_config(tmp_path)
    with open(cfg_path, "r") as f:
        cfg = yaml.safe_load(f)
    cfg["pricefm_desn_smoke"]["training"] = {
        "train_origin_limit": 2,
        "train_origin_selection": "tail",
    }
    cfg["pricefm_desn_smoke"]["adapter"]["projection_scale"] = 2.0
    with open(cfg_path, "w") as f:
        yaml.safe_dump(cfg, f, sort_keys=False)

    manifest = build_adapter(str(cfg_path), force=True)
    assert manifest["feature_manifest"]["projection_scale"] == 2.0
    summary = manifest["splits"]["train"]["activation_summary"]
    assert set(["mean", "sd", "frac_abs_gt_2", "frac_abs_gt_4"]).issubset(summary)
    assert summary["sd"] >= 0.0


def test_chunked_adapter_preserves_flat_direct_feature_map(tmp_path):
    require_window_data()
    cfg_path = write_temp_config(tmp_path)
    with open(cfg_path, "r") as f:
        cfg = yaml.safe_load(f)
    smoke = cfg["pricefm_desn_smoke"]
    smoke["training"] = {
        "train_origin_limit": 2,
        "train_origin_selection": "tail",
    }
    smoke["adapter"]["feature_map"] = "flat_direct"
    smoke["adapter"]["row_chunk_size"] = 3
    with open(cfg_path, "w") as f:
        yaml.safe_dump(cfg, f, sort_keys=False)

    manifest = build_adapter(str(cfg_path), force=True)
    n_horizons = len(smoke["horizons"])
    expected_features = 1 + 96 * 4 + 96 * 3 + 3 + n_horizons
    assert manifest["splits"]["train"]["n_rows"] == 2 * n_horizons
    assert manifest["splits"]["train"]["n_features"] == expected_features


def test_reservoir_feature_map_is_reproducible_and_records_states():
    window = synthetic_window()
    horizons = [1, 3]
    cfg = normalize_reservoir_config({
        "depth": 1,
        "units": [5],
        "alpha": 0.7,
        "rho": 0.9,
        "input_scale": 0.5,
        "recurrent_sparsity": 0.5,
    }, feature_dim=5)
    first = make_design_chunked(
        window, "train", horizons, horizons, "window_reservoir_v1",
        feature_dim=5, seed=123, row_chunk_size=2,
        reservoir_config=cfg,
    )
    second = make_design_chunked(
        window, "train", horizons, horizons, "window_reservoir_v1",
        feature_dim=5, seed=123, row_chunk_size=3,
        reservoir_config=cfg,
    )
    X1, y1, rows1, reservoir, summary = first
    X2, y2, rows2, reservoir2, summary2 = second
    expected_features = 1 + 5 + 3 + 3 + len(horizons)
    assert X1.shape == (window["Y"].shape[0] * len(horizons), expected_features)
    assert np.allclose(X1, X2)
    assert np.allclose(y1, y2)
    assert rows1 == rows2
    assert reservoir["sha256"] == reservoir2["sha256"]
    assert summary["count"] > 0
    assert summary2["sd"] >= 0.0


def test_reservoir_feature_map_supports_stacked_layers():
    window = synthetic_window()
    horizons = [2, 5]
    cfg = normalize_reservoir_config({
        "depth": 2,
        "units": [4, 3],
        "alpha": [0.5, 0.7],
        "rho": [0.8, 0.9],
        "input_scale": [0.25, 0.5],
        "recurrent_sparsity": [0.75, 0.5],
    }, feature_dim=3)
    X, _, _, reservoir, _ = make_design_chunked(
        window, "val", horizons, horizons, "window_reservoir_v1",
        feature_dim=3, seed=456, row_chunk_size=4,
        reservoir_config=cfg,
    )
    expected_features = 1 + 3 + 3 + 3 + len(horizons)
    assert X.shape[1] == expected_features
    assert reservoir["config"]["depth"] == 2
    assert len(reservoir["layers"]) == 2


def test_reservoir_dynamic_controls_change_states_even_when_matrices_match():
    window = synthetic_window(n_origins=4, lag_window=8)
    horizons = [1, 4]
    base = normalize_reservoir_config({
        "depth": 1,
        "units": [6],
        "alpha": 0.2,
        "rho": 0.9,
        "input_scale": 0.5,
        "recurrent_sparsity": 0.5,
    }, feature_dim=6)
    fast = normalize_reservoir_config({
        "depth": 1,
        "units": [6],
        "alpha": 0.9,
        "rho": 0.9,
        "input_scale": 0.5,
        "recurrent_sparsity": 0.5,
    }, feature_dim=6)
    X_base, _, _, reservoir_base, _ = make_design_chunked(
        window, "train", horizons, horizons, "window_reservoir_v1",
        feature_dim=6, seed=789, row_chunk_size=3,
        reservoir_config=base,
    )
    X_fast, _, _, reservoir_fast, _ = make_design_chunked(
        window, "train", horizons, horizons, "window_reservoir_v1",
        feature_dim=6, seed=789, row_chunk_size=3,
        reservoir_config=fast,
    )
    assert reservoir_base["sha256"] == reservoir_fast["sha256"]
    assert sha256_json(base) != sha256_json(fast)
    assert not np.allclose(X_base, X_fast)


def test_reservoir_feature_map_rejects_invalid_controls():
    with pytest.raises(ValueError, match="alpha"):
        normalize_reservoir_config({"depth": 1, "units": [4], "alpha": 1.5}, feature_dim=4)
    with pytest.raises(ValueError, match="rho"):
        normalize_reservoir_config({"depth": 1, "units": [4], "rho": -0.1}, feature_dim=4)
    with pytest.raises(ValueError, match="state_output"):
        normalize_reservoir_config({"depth": 1, "units": [4], "state_output": "unknown"}, feature_dim=4)
