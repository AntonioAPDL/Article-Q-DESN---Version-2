"""Tests for direct neighbor-augmented PriceFM DESN adapter inputs."""

import copy
import sys
from pathlib import Path

import numpy as np
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application" / "scripts" / "pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import pricefm_desn_adapter as adapter  # noqa: E402


def synthetic_window(region, offset=0.0):
    anchors = np.asarray([
        "2024-01-01T00:00:00Z",
        "2024-01-01T01:00:00Z",
    ])
    x_lag = np.arange(16, dtype=float).reshape(2, 2, 4) + float(offset)
    x_lead = np.arange(12, dtype=float).reshape(2, 2, 3) + 100.0 + float(offset)
    y = np.arange(4, dtype=float).reshape(2, 2) + 1000.0
    return {
        "path": Path("synthetic_{}.npz".format(region)),
        "manifest": {},
        "X_lag": x_lag,
        "X_lead": x_lead,
        "Y": y,
        "anchors": anchors,
        "lag_cols": [
            "{}-price".format(region),
            "{}-load".format(region),
            "{}-solar".format(region),
            "{}-wind".format(region),
        ],
        "lead_cols": [
            "{}-load".format(region),
            "{}-solar".format(region),
            "{}-wind".format(region),
        ],
    }


def install_synthetic_direct_graph(monkeypatch):
    windows = {
        "A": synthetic_window("A", 0.0),
        "B": synthetic_window("B", 100.0),
        "C": synthetic_window("C", 300.0),
    }

    def fake_pricefm_block(data_cfg):
        return {"regions": ["A", "B", "C"]}

    def fake_graph_scope_manifest_for_policy(region, input_regions, feature_policy, spatial=None):
        active = [region, "B", "C"]
        spatial = dict(spatial or {})
        if "neighbor_regions" in spatial:
            active = [region] + [str(x) for x in spatial["neighbor_regions"]]
        if "max_neighbor_regions" in spatial:
            active = [active[0]] + active[1:1 + int(spatial["max_neighbor_regions"])]
        return {
            "target_region": region,
            "feature_policy": feature_policy,
            "graph_degree": int(spatial.get("graph_degree", 1)),
            "active_regions": active,
            "neighbor_regions": active[1:],
            "n_active_regions": len(active),
            "n_neighbor_regions": max(0, len(active) - 1),
            "graph_hash": "unit-graph",
            "graph_source": "unit",
        }

    def fake_load_window(data_cfg, fold, region, split):
        return copy.deepcopy(windows[region])

    monkeypatch.setattr(adapter, "pricefm_block", fake_pricefm_block)
    monkeypatch.setattr(adapter, "graph_scope_manifest_for_policy", fake_graph_scope_manifest_for_policy)
    monkeypatch.setattr(adapter, "load_window", fake_load_window)
    monkeypatch.setattr(adapter, "sha256_file", lambda path: "sha256:{}".format(Path(path).name))
    smoke = {
        "feature_policy": "graph_neighbor_direct",
        "adapter": {
            "spatial": {
                "graph_degree": 1,
                "neighbor_regions": ["B"],
                "target_lag_features": ["price", "load"],
                "target_lead_features": ["load"],
                "neighbor_lag_features": ["price", "wind"],
                "neighbor_lead_features": ["wind"],
            }
        },
    }
    return windows, smoke


def test_graph_neighbor_direct_selects_neighbor_features_and_records_contract(monkeypatch):
    windows, smoke = install_synthetic_direct_graph(monkeypatch)
    out = adapter.load_feature_window({}, 1, "A", "train", smoke)

    assert out["X_lag"].shape == (2, 2, 4)
    assert out["X_lead"].shape == (2, 2, 2)
    np.testing.assert_allclose(out["X_lag"][:, :, :2], windows["A"]["X_lag"][:, :, [0, 1]])
    np.testing.assert_allclose(out["X_lag"][:, :, 2:], windows["B"]["X_lag"][:, :, [0, 3]])
    np.testing.assert_allclose(out["X_lead"][:, :, :1], windows["A"]["X_lead"][:, :, [0]])
    np.testing.assert_allclose(out["X_lead"][:, :, 1:], windows["B"]["X_lead"][:, :, [2]])

    assert out["lag_cols"] == [
        "A::A-price",
        "A::A-load",
        "B::B-price",
        "B::B-wind",
    ]
    manifest = out["feature_policy_manifest"]
    assert manifest["feature_policy"] == "graph_neighbor_direct"
    assert manifest["spatial_information_set"] == "pricefm_neighbor_augmented_direct"
    assert manifest["graph"]["active_regions"] == ["A", "B"]
    assert manifest["neighbor_direct"]["neighbor_regions"] == ["B"]
    assert manifest["neighbor_direct"]["lag_feature_count"] == 4
    assert manifest["leakage_contract"]["response_source"] == "target_region_Y_only"
    assert manifest["leakage_contract"]["neighbor_response_used_as_input"] is False
    assert len(manifest["feature_provenance"]) == 6
    assert {row["source_role"] for row in manifest["feature_provenance"]} == {"target", "neighbor"}


def test_graph_neighbor_direct_respects_max_neighbor_regions(monkeypatch):
    _, smoke = install_synthetic_direct_graph(monkeypatch)
    smoke["adapter"]["spatial"].pop("neighbor_regions")
    smoke["adapter"]["spatial"]["max_neighbor_regions"] = 1
    out = adapter.load_feature_window({}, 1, "A", "train", smoke)
    assert out["feature_policy_manifest"]["graph"]["active_regions"] == ["A", "B"]


def test_graph_neighbor_direct_unknown_feature_fails(monkeypatch):
    _, smoke = install_synthetic_direct_graph(monkeypatch)
    smoke["adapter"]["spatial"]["neighbor_lag_features"] = ["hydro"]
    with pytest.raises(ValueError, match="neighbor_lag_features"):
        adapter.load_feature_window({}, 1, "A", "train", smoke)
