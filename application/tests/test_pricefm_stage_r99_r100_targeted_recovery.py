"""Focused tests for the PriceFM R99/R100 targeted recovery campaign."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))


def load(name: str):
    path = SCRIPTS / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


R99 = load("331_audit_pricefm_stage_r99_targeted_recovery.py")
R100 = load("332_prepare_pricefm_stage_r100_targeted_normal_screen.py")
RUNNER = load("333_orchestrate_pricefm_stage_r100_targeted_normal_screen.py")


def test_r99_target_partition_and_train_only_neighbor_ranking() -> None:
    assert len(R99.TARGETS) == 17
    assert len(set(R99.TARGETS)) == 17
    assert set(R99.NORDIC_CONTROLS).isdisjoint(R99.TARGETS)
    times = pd.date_range("2022-01-01", periods=24, freq="15min", tz="UTC")
    values = np.arange(24, dtype=float) ** 2
    frame = pd.DataFrame({"time_utc": times})
    for region in R99.graph_adj_matrix():
        frame[f"{region}-price"] = values if region != "GR" else values[::-1]
    ranked = R99._neighbor_signal(frame)
    assert ranked.region.nunique() == 17
    assert ranked.selection_cutoff_exclusive.eq("2024-09-01").all()
    assert ranked.groupby("region").top3_change_neighbor.sum().le(3).all()


def test_r100_candidate_bank_is_bounded_spatial_and_deterministic() -> None:
    neighbors = pd.DataFrame({
        "region": ["SK", "SK", "SK"], "neighbor": ["HU", "CZ", "PL"],
        "change_rank": [1, 2, 3],
    })
    current = {
        "region": "SK", "feature_policy": "graph_khop", "lag_window": 96,
        "depth": 1, "units": [64], "alpha": .25, "rho": .90,
        "input_scale": .15, "state_output": "final_layer", "seed": 2026090601,
        "tau0": 1e-4, "spatial": {"graph_degree": 1, "neighbor_regions": ["CZ", "HU", "PL"]},
        "source_selected_atom_manifest": "/fixture/selected.csv",
        "source_selected_atom_manifest_sha256": "a" * 64,
        "source_feature_manifest": "/fixture/feature.json",
        "source_feature_manifest_sha256": "b" * 64,
        "observed_readout_features": 176,
    }
    legacy = R100._load_legacy()
    first = R100.build_candidates("SK", current, neighbors, legacy)
    second = R100.build_candidates("SK", current, neighbors, legacy)
    assert len(first) == 240
    assert first.semantic_fingerprint.is_unique
    assert first.candidate_id.tolist() == second.candidate_id.tolist()
    assert first.feature_policy.value_counts().to_dict() == R100.QUOTAS
    assert (first.candidate_role == "R98_frozen_control").sum() == 1
    assert first.test_access_authorized.eq(False).all()
    spread = first[first.feature_policy == "graph_neighbor_spread_summary"]
    assert len(spread) == 84
    assert spread.spatial.map(lambda x: set(x["neighbor_regions"]).issubset({"HU", "CZ", "PL"})).all()
    assert set(first.lag_window).issubset({96, 168, 240})
    assert first.depth.max() == 3


def test_r100_tau_and_cpu_contracts() -> None:
    assert RUNNER.parse_cpus("0-24,32-56") == list(range(25)) + list(range(32, 57))
    with pytest.raises(RuntimeError):
        RUNNER.parse_cpus("0,0")
    assert RUNNER.tau_reference(1e-4, 176, 176) == pytest.approx(1e-4)
    assert RUNNER.tau_reference(1e-4, 176, 704) == pytest.approx(5e-5)
    with pytest.raises(ValueError):
        RUNNER.tau_reference(0, 176, 176)


def test_r100_requires_two_siblings_on_25_physical_cores(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(RUNNER, "physical_core", lambda cpu: (0, cpu % 25))
    cpus = list(range(25)) + list(range(25, 50))
    assert len(RUNNER.validate_physical_pairing(cpus)) == 25
    with pytest.raises(RuntimeError):
        RUNNER.validate_physical_pairing(cpus[:-1])


def test_r100_launch_code_keeps_forbidden_surfaces_blocked() -> None:
    prep = (SCRIPTS / "332_prepare_pricefm_stage_r100_targeted_normal_screen.py").read_text()
    runner = (SCRIPTS / "333_orchestrate_pricefm_stage_r100_targeted_normal_screen.py").read_text()
    assert '"test_scoring_authorized": False' in prep
    assert '"quantile_fit_authorized": False' in prep
    assert '"joint_fit_authorized": False' in prep
    assert '"mcmc_authorized": False' in prep
    assert '"registry_mutated": False' in runner
    assert '"article_mutated": False' in runner
    assert "RUN_PRICEFM_R100_TARGETED_NORMAL_RECOVERY" in runner
    assert "ensure_runtime_capacity()" in runner
