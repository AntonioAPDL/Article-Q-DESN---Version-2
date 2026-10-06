"""Focused tests for the PriceFM R101 recursive feature adapter."""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import pricefm_recursive_adapter as adapter  # noqa: E402


ADJACENCY = {"A": ["A", "B", "C"], "B": ["A", "B"], "C": ["A", "C"]}


def block(region: str, offset: float) -> dict:
    return {
        "X_lag": np.asarray([[1.0, 10.0], [2.0, 20.0]]) + offset,
        "lag_cols": [f"{region}-price", f"{region}-load"],
        "X_lead": np.asarray([[100.0], [200.0]]) + offset,
        "lead_cols": [f"{region}-load"],
    }


def blocks() -> dict:
    return {"A": block("A", 0), "B": block("B", 10), "C": block("C", 30)}


def test_contract_identity_separates_structure_from_tau0() -> None:
    spec = {
        "region": "A", "feature_policy": "target_only", "lag_window": 48,
        "depth": 2, "units": [8, 8], "alpha": 0.2, "rho": 0.9,
        "input_scale": 0.3, "state_output": "final_layer", "seed": 7,
        "spatial": {"graph_degree": 0}, "tau0": 0.01,
    }
    changed = dict(spec, tau0=0.04)
    assert adapter.spec_identities(spec)["structure_sha256"] == adapter.spec_identities(changed)["structure_sha256"]
    assert adapter.spec_identities(spec)["contract_sha256"] != adapter.spec_identities(changed)["contract_sha256"]


def test_graph_summary_mean_std_matches_manual_panel_snapshot() -> None:
    result = adapter.build_policy_features(
        "A", blocks(), "graph_summary_mean_std", {"graph_degree": 1},
        input_regions=["A", "B", "C"], adjacency=ADJACENCY,
    )
    neighbor_lag = np.stack([blocks()["B"]["X_lag"], blocks()["C"]["X_lag"]])
    np.testing.assert_allclose(result["X_lag"][:, :2], blocks()["A"]["X_lag"])
    np.testing.assert_allclose(result["X_lag"][:, 2:4], neighbor_lag.mean(axis=0))
    np.testing.assert_allclose(result["X_lag"][:, 4:6], neighbor_lag.std(axis=0, ddof=0))
    assert result["feature_policy_manifest"]["panel_snapshot_contract"] == "all_regions_pre_update_h_minus_1"


def test_graph_khop_is_target_first_and_input_order_stable() -> None:
    result = adapter.build_policy_features(
        "A", blocks(), "graph_khop", {"graph_degree": 1},
        input_regions=["C", "A", "B"], adjacency=ADJACENCY,
    )
    assert result["feature_policy_manifest"]["active_regions"] == ["A", "C", "B"]
    assert result["lag_cols"][:2] == ["A::A-price", "A::A-load"]
    assert result["lag_cols"][2:4] == ["C::C-price", "C::C-load"]


def test_neighbor_spread_summary_matches_direct_adapter_convention() -> None:
    spatial = {
        "graph_degree": 1,
        "neighbor_regions": ["B", "C"],
        "target_lag_features": ["price", "load"],
        "target_lead_features": ["load"],
        "neighbor_lag_features": ["price", "load"],
        "neighbor_lead_features": ["load"],
        "summary_stats": ["mean_diff", "sd", "min_diff", "max_diff"],
    }
    result = adapter.build_policy_features(
        "A", blocks(), "graph_neighbor_spread_summary", spatial,
        input_regions=["A", "B", "C"], adjacency=ADJACENCY,
    )
    target_load = blocks()["A"]["X_lag"][:, 1]
    neighbor_load = np.stack([blocks()["B"]["X_lag"][:, 1], blocks()["C"]["X_lag"][:, 1]])
    np.testing.assert_allclose(result["X_lag"][:, 2], neighbor_load.mean(axis=0) - target_load)
    np.testing.assert_allclose(result["X_lag"][:, 3], neighbor_load.std(axis=0, ddof=0))
    assert result["lag_cols"][:2] == ["A::A-price", "A::A-load"]
    assert result["lag_cols"][2] == "graph_neighbor_mean_diff::lag-load"


def test_panel_snapshot_requires_complete_aligned_finite_histories() -> None:
    adapter.validate_panel_snapshot({"A": [1, 2], "B": [3, 4]}, ["A", "B"])
    with pytest.raises(ValueError, match="exactly"):
        adapter.validate_panel_snapshot({"A": [1, 2]}, ["A", "B"])
    with pytest.raises(ValueError, match="aligned"):
        adapter.validate_panel_snapshot({"A": [1], "B": [2, 3]}, ["A", "B"])
    with pytest.raises(ValueError, match="finite"):
        adapter.validate_panel_snapshot({"A": [1, np.nan], "B": [2, 3]}, ["A", "B"])


def test_scaler_round_trip_is_exact_with_heterogeneous_columns() -> None:
    values = np.asarray([[10.0, -2.0], [14.0, 8.0]])
    center = np.asarray([12.0, 3.0])
    scale = np.asarray([2.0, 5.0])
    transformed = adapter.scale_values(values, center, scale)
    np.testing.assert_allclose(adapter.inverse_scale_values(transformed, center, scale), values)
    with pytest.raises(ValueError, match="positive"):
        adapter.scale_values(values, center, [2.0, 0.0])
