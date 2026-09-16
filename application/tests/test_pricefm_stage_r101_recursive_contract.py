"""Focused tests for the read-only R101 recursive contract compiler."""

from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))


def load_module():
    path = SCRIPTS / "334_prepare_pricefm_recursive_contract.py"
    spec = importlib.util.spec_from_file_location("pricefm_r101_contract", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


R101 = load_module()


def base_spec(region: str) -> dict:
    spec = {
        "region": region, "feature_policy": "target_only", "lag_window": 48,
        "depth": 1, "units": [8], "alpha": 0.2, "rho": 0.9,
        "input_scale": 0.3, "state_output": "final_layer", "seed": 11,
        "spatial": {"graph_degree": 0}, "tau0": 0.01,
        "source_stage": "R98", "source_role": "frozen_authority_anchor",
        "selection_split": "validation_only", "test_used_for_selection": False,
    }
    spec.update(R101.spec_identities(spec))
    return spec


def test_two_panel_contract_counts_structure_and_tau_separately(monkeypatch, tmp_path: Path) -> None:
    regions = list(R101.graph_adj_matrix())
    r98 = [base_spec(region) for region in regions]
    targets = regions[:17]
    r100 = {}
    for index, region in enumerate(targets):
        spec = dict(r98[index])
        spec["spatial"] = dict(spec["spatial"])
        spec["source_stage"] = "R100"
        spec["source_role"] = "R100_targeted_novel_search"
        if index < 10:
            spec["units"] = [9]
        elif index == 10:
            spec["tau0"] = 0.04
        spec.update(R101.spec_identities(spec))
        r100[region] = spec
    audit = pd.DataFrame({
        "region": targets,
        "rhs_experiments": [90] * 17,
        "eligible_rhs_experiments": [1] * 17,
        "retained_files": [540] * 17,
        "retained_hash_failures": [0] * 17,
    })
    registry = tmp_path / "registry.csv"
    registry.write_text("fixture\n")
    monkeypatch.setattr(R101, "audit_r100_campaign", lambda *args, **kwargs: (audit, []))
    fold_rows = []
    for region in regions:
        for fold in (1, 2, 3):
            fold_rows.append({"region": region, "fold": fold, "test_opened": False})
    monkeypatch.setattr(R101, "load_r98_specs", lambda *args, **kwargs: (r98, [], fold_rows))
    monkeypatch.setattr(R101, "load_r100_specs", lambda *args, **kwargs: (r100, []))
    args = argparse.Namespace(
        artifact_repo=tmp_path, r98_registry=registry, r100_campaign=tmp_path,
        r100_prep=tmp_path, output_dir=tmp_path / "out", write=False, force=False,
    )
    bundle = R101.build_contract(args)
    assert bundle["summary"]["unique_structures"] == 48
    assert bundle["summary"]["unique_full_contracts"] == 49
    assert bundle["summary"]["r100_structural_replacements"] == 10
    assert bundle["summary"]["r100_full_contract_replacements"] == 11
    assert not bundle["primary"].test_scoring_authorized.any()


def test_materialization_writes_no_launch_yaml(monkeypatch, tmp_path: Path) -> None:
    frame = pd.DataFrame([{"region": "AT", "units": [8], "spatial": {"graph_degree": 0}}])
    bundle = {
        "summary": {"stage": "R101", "status": "fixture"},
        "control": frame, "primary": frame, "fold_provenance": frame,
        "unique_structures": frame,
        "unique_contracts": frame, "audit": frame,
        "gates": pd.DataFrame([{"gate": "fixture", "passed": True, "observed": 1}]),
        "sources": pd.DataFrame([{"role": "fixture", "path": "/fixture", "sha256": "a" * 64}]),
    }
    summary = R101.materialize(bundle, tmp_path / "out")
    assert summary["stage"] == "R101"
    assert not list((tmp_path / "out").glob("*.yaml"))
    assert not list((tmp_path / "out").glob("*.yml"))
    assert (tmp_path / "out/pricefm_stage_r101_recursive_contract_closeout.md").is_file()


def test_source_keeps_forbidden_actions_blocked() -> None:
    source = (SCRIPTS / "334_prepare_pricefm_recursive_contract.py").read_text()
    assert '"launch_yaml_written": False' in source
    assert '"model_fit_started": False' in source
    assert '"registry_mutation_authorized": False' in source
    assert '"article_mutation_authorized": False' in source
    assert "subprocess" not in source
