"""Tests for compact PriceFM graph-summary adapter inputs."""

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
    x_lag = np.arange(12, dtype=float).reshape(2, 3, 2) + float(offset)
    x_lead = np.arange(8, dtype=float).reshape(2, 4, 1) + 10.0 + float(offset)
    y = np.arange(8, dtype=float).reshape(2, 4) + 100.0
    return {
        "path": Path("synthetic_{}.npz".format(region)),
        "manifest": {},
        "X_lag": x_lag,
        "X_lead": x_lead,
        "Y": y,
        "anchors": anchors,
        "lag_cols": ["load", "wind"],
        "lead_cols": ["calendar"],
    }


def install_synthetic_graph(monkeypatch, degree=1, mismatch_anchors=False):
    windows = {
        "A": synthetic_window("A", 0.0),
        "B": synthetic_window("B", 100.0),
        "C": synthetic_window("C", 300.0),
    }
    if mismatch_anchors:
        windows["C"] = copy.deepcopy(windows["C"])
        windows["C"]["anchors"] = np.asarray([
            "2024-01-01T00:15:00Z",
            "2024-01-01T01:15:00Z",
        ])

    def fake_pricefm_block(data_cfg):
        return {"regions": ["A", "B", "C"]}

    def fake_graph_scope_manifest(region, input_regions, graph_degree):
        active = [region] if int(graph_degree) == 0 else [region, "B", "C"]
        return {
            "target_region": region,
            "graph_degree": int(graph_degree),
            "active_regions": active,
            "neighbor_regions": active[1:],
            "graph_hash": "unit-graph",
        }

    def fake_load_window(data_cfg, fold, region, split):
        return copy.deepcopy(windows[region])

    monkeypatch.setattr(adapter, "pricefm_block", fake_pricefm_block)
    monkeypatch.setattr(adapter, "graph_scope_manifest", fake_graph_scope_manifest)
    monkeypatch.setattr(adapter, "load_window", fake_load_window)
    monkeypatch.setattr(adapter, "sha256_file", lambda path: "sha256:{}".format(Path(path).name))
    return windows, {
        "feature_policy": "graph_summary_mean",
        "adapter": {"spatial": {"graph_degree": int(degree)}},
    }


def test_graph_summary_mean_preserves_target_and_adds_neighbor_mean(monkeypatch):
    windows, smoke = install_synthetic_graph(monkeypatch, degree=1)
    out = adapter.load_feature_window({}, 1, "A", "train", smoke)

    expected_lag_mean = np.mean(
        np.stack([windows["B"]["X_lag"], windows["C"]["X_lag"]], axis=0),
        axis=0,
    )
    expected_lead_mean = np.mean(
        np.stack([windows["B"]["X_lead"], windows["C"]["X_lead"]], axis=0),
        axis=0,
    )
    assert out["X_lag"].shape == (2, 3, 4)
    assert out["X_lead"].shape == (2, 4, 2)
    np.testing.assert_allclose(out["X_lag"][:, :, :2], windows["A"]["X_lag"])
    np.testing.assert_allclose(out["X_lag"][:, :, 2:], expected_lag_mean)
    np.testing.assert_allclose(out["X_lead"][:, :, :1], windows["A"]["X_lead"])
    np.testing.assert_allclose(out["X_lead"][:, :, 1:], expected_lead_mean)
    assert out["lag_cols"] == [
        "load", "wind", "graph_neighbor_mean::load", "graph_neighbor_mean::wind"
    ]
    manifest = out["feature_policy_manifest"]
    assert manifest["feature_policy"] == "graph_summary_mean"
    assert manifest["spatial_information_set"] == "pricefm_released_graph_summary"
    assert manifest["neighbor_summary"]["target_region_preserved"] is True
    assert manifest["neighbor_summary"]["neighbor_regions"] == ["B", "C"]
    assert manifest["neighbor_summary"]["statistics"] == ["neighbor_mean"]


def test_graph_summary_mean_std_adds_neighbor_sd(monkeypatch):
    windows, smoke = install_synthetic_graph(monkeypatch, degree=1)
    smoke["feature_policy"] = "graph_summary_mean_std"
    out = adapter.load_feature_window({}, 1, "A", "train", smoke)

    neighbor_lag = np.stack([windows["B"]["X_lag"], windows["C"]["X_lag"]], axis=0)
    expected_sd = np.std(neighbor_lag, axis=0, ddof=0)
    assert out["X_lag"].shape == (2, 3, 6)
    np.testing.assert_allclose(out["X_lag"][:, :, :2], windows["A"]["X_lag"])
    np.testing.assert_allclose(out["X_lag"][:, :, 4:], expected_sd)
    assert out["feature_policy_manifest"]["neighbor_summary"]["statistics"] == [
        "neighbor_mean", "neighbor_sd"
    ]


def test_graph_summary_degree_zero_equals_target_only(monkeypatch):
    windows, smoke = install_synthetic_graph(monkeypatch, degree=0)
    smoke["feature_policy"] = "graph_summary_mean_std"
    out = adapter.load_feature_window({}, 1, "A", "train", smoke)

    np.testing.assert_allclose(out["X_lag"], windows["A"]["X_lag"])
    np.testing.assert_allclose(out["X_lead"], windows["A"]["X_lead"])
    assert out["lag_cols"] == windows["A"]["lag_cols"]
    assert out["feature_policy_manifest"]["neighbor_summary"]["n_neighbor_regions"] == 0
    assert out["feature_policy_manifest"]["neighbor_summary"]["degree_zero_equals_target_only"] is True


def test_graph_khop_still_raw_concatenates_regions(monkeypatch):
    windows, smoke = install_synthetic_graph(monkeypatch, degree=1)
    smoke["feature_policy"] = "graph_khop"
    out = adapter.load_feature_window({}, 1, "A", "train", smoke)

    assert out["X_lag"].shape == (2, 3, 6)
    np.testing.assert_allclose(out["X_lag"][:, :, :2], windows["A"]["X_lag"])
    np.testing.assert_allclose(out["X_lag"][:, :, 2:4], windows["B"]["X_lag"])
    np.testing.assert_allclose(out["X_lag"][:, :, 4:6], windows["C"]["X_lag"])
    assert out["feature_policy_manifest"]["input_scope"] == "pricefm_graph_khop"


def test_graph_summary_anchor_mismatch_fails(monkeypatch):
    _, smoke = install_synthetic_graph(monkeypatch, degree=1, mismatch_anchors=True)
    with pytest.raises(ValueError, match="Anchor mismatch"):
        adapter.load_feature_window({}, 1, "A", "train", smoke)
