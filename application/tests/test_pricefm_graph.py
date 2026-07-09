"""Tests for PriceFM graph-neighbor helper semantics."""

from pathlib import Path
import sys

import pytest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "application" / "scripts" / "pricefm"))

from pricefm_graph import (  # noqa: E402
    get_k_hop_regions,
    graph_active_regions_for_policy,
    graph_adj_matrix,
    graph_hash,
    graph_policy_requires_neighbor_windows,
    graph_scope_manifest,
    graph_scope_manifest_for_policy,
)


REGIONS = [
    "AT", "BE", "BG", "CZ", "DE_LU", "DK_1", "DK_2", "EE", "ES", "FI",
    "FR", "GR", "HR", "HU", "IT_CALA", "IT_CNOR", "IT_CSUD", "IT_NORD",
    "IT_SARD", "IT_SICI", "IT_SUD", "LT", "LV", "NL", "NO_1", "NO_2",
    "NO_3", "NO_4", "NO_5", "PL", "PT", "RO", "SE_1", "SE_2", "SE_3",
    "SE_4", "SI", "SK",
]


def test_graph_hash_is_stable_sha256_payload():
    assert len(graph_hash()) == 64
    assert graph_hash() == graph_hash(graph_adj_matrix())


def test_k_hop_regions_follow_pricefm_ordering():
    out = get_k_hop_regions("DE_LU", REGIONS, degree=1)
    assert out == [
        "DE_LU", "AT", "BE", "CZ", "DK_1", "DK_2",
        "FR", "NL", "NO_2", "PL", "SE_4",
    ]


def test_degree_zero_is_target_only():
    assert get_k_hop_regions("EE", REGIONS, degree=0) == ["EE"]


def test_graph_scope_manifest_records_contract():
    manifest = graph_scope_manifest("NO_4", REGIONS, degree=1)
    assert manifest["graph_source"] == "PriceFM.graph_adj_matrix"
    assert manifest["graph_degree"] == 1
    assert manifest["target_region"] == "NO_4"
    assert manifest["active_regions"] == ["NO_4", "FI", "NO_3", "SE_1", "SE_2"]
    assert manifest["n_input_regions"] == 38
    assert manifest["n_active_regions"] == 5


def test_k_hop_regions_fail_on_invalid_scope():
    with pytest.raises(ValueError, match="graph_degree"):
        get_k_hop_regions("DE_LU", REGIONS, degree=-1)
    with pytest.raises(ValueError, match="must be in input_regions"):
        get_k_hop_regions("DE_LU", ["AT", "BE"], degree=1)


def test_graph_neighbor_direct_scope_can_be_narrowed_explicitly():
    spatial = {
        "graph_degree": 1,
        "neighbor_regions": ["DE_LU", "LT"],
        "max_neighbor_regions": 1,
    }
    out = graph_active_regions_for_policy(
        "PL",
        REGIONS,
        "graph_neighbor_direct",
        spatial=spatial,
    )
    assert out == ["PL", "DE_LU"]
    manifest = graph_scope_manifest_for_policy(
        "PL",
        REGIONS,
        "graph_neighbor_direct",
        spatial=spatial,
    )
    assert manifest["feature_policy"] == "graph_neighbor_direct"
    assert manifest["neighbor_regions"] == ["DE_LU"]
    assert manifest["n_neighbor_regions"] == 1


def test_graph_neighbor_direct_rejects_out_of_scope_neighbor():
    with pytest.raises(ValueError, match="neighbor_regions"):
        graph_active_regions_for_policy(
            "PL",
            REGIONS,
            "graph_neighbor_direct",
            spatial={"graph_degree": 1, "neighbor_regions": ["RO"]},
        )


def test_graph_policy_requires_neighbor_windows_includes_summary_and_direct():
    assert graph_policy_requires_neighbor_windows("target_only") is False
    assert graph_policy_requires_neighbor_windows("graph_khop") is True
    assert graph_policy_requires_neighbor_windows("graph_summary_mean") is True
    assert graph_policy_requires_neighbor_windows("graph_neighbor_direct") is True
    assert graph_policy_requires_neighbor_windows("graph_neighbor_spread_summary") is True


def test_graph_neighbor_spread_summary_scope_can_be_narrowed_like_direct():
    spatial = {
        "graph_degree": 1,
        "neighbor_regions": ["DE_LU", "LT"],
        "max_neighbor_regions": 1,
    }
    out = graph_active_regions_for_policy(
        "PL",
        REGIONS,
        "graph_neighbor_spread_summary",
        spatial=spatial,
    )
    assert out == ["PL", "DE_LU"]
    manifest = graph_scope_manifest_for_policy(
        "PL",
        REGIONS,
        "graph_neighbor_spread_summary",
        spatial=spatial,
    )
    assert manifest["feature_policy"] == "graph_neighbor_spread_summary"
    assert manifest["neighbor_regions"] == ["DE_LU"]
    assert manifest["n_neighbor_regions"] == 1
