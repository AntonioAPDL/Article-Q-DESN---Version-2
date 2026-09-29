from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
sys.path.insert(0, str(SCRIPTS))

from pricefm_common import sha256_file
from pricefm_r122_engine import (
    BASINS, FAN_INS, M_X, M_Y, POLICIES, SOURCE_WINDOW,
    candidate_universe, factor_coverage, fit_manifest, mandatory_identities,
    selected_panel, stage0_proxy_decision,
)


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec); assert spec and spec.loader
    spec.loader.exec_module(module); return module


PREP_CAL = _load("pricefm_r122_prepare_cal_test", "421_prepare_pricefm_stage_r122_stage0_calibration.py")
RUN_CAL = _load("pricefm_r122_run_cal_test", "422_run_pricefm_stage_r122_stage0_calibration.py")
PREP_LONG = _load("pricefm_r122_prepare_long_test", "423_prepare_pricefm_stage_r122_long_memory.py")


@pytest.fixture(scope="module")
def universe_and_panel():
    universe = candidate_universe(); panel = selected_panel(universe)
    return universe, panel


def test_r122_universe_and_exact_balanced_panel(universe_and_panel):
    universe, panel = universe_and_panel
    assert len(universe) == 11 * 4 * 5 * 4 * 6 == 5280
    assert len(panel) == 3199
    assert mandatory_identities(universe).issubset(set(panel.structural_sha256))
    assert not panel.structural_sha256.duplicated().any()
    coverage = factor_coverage(panel)
    assert all(group["count"].max() - group["count"].min() <= 1 for _, group in coverage.groupby("factor"))


def test_r122_surface_is_the_frozen_long_memory_question(universe_and_panel):
    universe, panel = universe_and_panel
    assert sorted(universe.m_y.unique()) == list(M_Y)
    assert sorted(universe.m_x.unique()) == list(M_X)
    assert set(universe.basin) == set(BASINS)
    assert set(universe.feature_policy) == set(POLICIES)
    assert sorted(universe.input_fan_in.unique()) == list(FAN_INS)
    assert panel.source_window.eq(SOURCE_WINDOW).all()
    assert panel.readout.eq("pure_all_layers").all()
    assert panel.calendar.eq("none").all()
    assert not panel.test_access_authorized.astype(bool).any()


def test_structural_hash_excludes_seed_and_fit_hash_includes_seed(universe_and_panel):
    _, panel = universe_and_panel
    fits = fit_manifest(panel.head(3))
    assert len(fits) == 6
    assert fits.groupby("structural_sha256").reservoir_seed.nunique().eq(2).all()
    assert fits.fit_sha256.nunique() == 6
    assert fits.groupby("structural_sha256").canonical_seed.sum().eq(1).all()


def test_selected_panel_is_deterministic(universe_and_panel):
    universe, panel = universe_and_panel
    repeated = selected_panel(universe.sample(frac=1, random_state=7).reset_index(drop=True))
    assert panel.structural_sha256.tolist() == repeated.structural_sha256.tolist()


def test_stage0_proxy_requires_candidate_a_and_a_lower_ranked_complete_family():
    normal = pd.DataFrame([
        {"candidate_id": "A", "mean_AQL": 1.0, "mean_late_AQL": 1.1, "worst_AQL": 1.2},
        {"candidate_id": "B", "mean_AQL": 1.1, "mean_late_AQL": 1.2, "worst_AQL": 1.3},
        {"candidate_id": "C", "mean_AQL": 1.2, "mean_late_AQL": 1.3, "worst_AQL": 1.4},
    ])
    rows = [{"candidate_id": candidate, "split": split, "eligible": True,
             "AQL": value, "late_AQL": value * 1.1}
            for candidate, value in (("A", 1.0), ("C", 1.01)) for split in (1, 2, 3)]
    passed = stage0_proxy_decision(normal, pd.DataFrame(rows))
    assert passed["passed"] is True
    incomplete = pd.DataFrame([row for row in rows if not (row["candidate_id"] == "A" and row["split"] == 2)])
    failed = stage0_proxy_decision(normal, incomplete)
    assert failed["status"] == "R122_STAGE0_REPAIR_REQUIRED"
    assert failed["checks"]["candidate_a_complete"] is False


def _source_contract(root: Path, candidate: str, split: int, tau: float, eligible: bool) -> Path:
    quantiles = root / "al_internal" / candidate / f"split={split}" / "quantiles"
    contract_path = quantiles / "contracts" / f"tau={tau:.2f}.json"
    output = quantiles / "al" / f"tau={tau:.2f}"
    output.mkdir(parents=True, exist_ok=True); contract_path.parent.mkdir(parents=True, exist_ok=True)
    (output / "terminal.json").write_text(json.dumps({"status": "completed_r121_quantile_atom"}))
    (output / "diagnostics.json").write_text(json.dumps({"external_gate_passed": eligible}))
    contract = {"candidate_id": candidate, "split": split, "tau": tau,
                "atom_id": f"{candidate}_{split}_{tau}", "output_dir": str(output),
                "posterior_target_sha256": f"target-{candidate}-{split}-{tau}"}
    contract_path.write_text(json.dumps(contract)); return contract_path


def test_calibration_panel_contains_geometry_controls_and_actual_failures(tmp_path):
    source = tmp_path / "campaign"; imported = source / "imported_screening"; imported.mkdir(parents=True)
    pd.DataFrame({"candidate_id": ["A", "B", "C"], "mean_AQL": [1, 2, 3]}).to_csv(
        imported / "unique_normal_shortlist.csv", index=False)
    for candidate in ("A", "B", "C"):
        _source_contract(source, candidate, 3, .50, candidate != "B")
    _source_contract(source, "A", 2, .10, False)
    result = PREP_CAL.calibration_sources(source)
    assert len(result) == 4
    assert len(result[(result.split == 3) & (result.tau == .5)]) == 3
    assert (~result.source_external_gate_passed).sum() == 2


def test_calibration_contract_changes_computation_not_target(tmp_path):
    source = tmp_path / "source.json"
    source.write_text(json.dumps({"candidate_id": "A", "split": 3, "tau": .5,
                                  "atom_id": "old", "tag": "R121B", "max_iter": 500,
                                  "output_dir": "/old", "posterior_target_sha256": "same",
                                  "test_access_authorized": False}))
    contract = PREP_CAL._contract(source, sha256_file(source), 750, tmp_path / "campaign")
    assert contract["max_iter"] == 750
    assert contract["posterior_target_sha256"] == "same"
    assert contract["calibration_only"] is True
    assert contract["score_access_authorized"] is False
    assert contract["selection_authorized"] is False


def test_calibration_runner_repeats_the_whole_panel_at_a_common_cap():
    source = (SCRIPTS / "422_run_pricefm_stage_r122_stage0_calibration.py").read_text()
    assert "first.external_gate_passed.all()" in source
    assert "_cap(prep, campaign, control, manifest, 1000" in source
    assert '"candidate_specific_retries": False' in source
    assert "score_opened" in source


def test_r122_preparation_is_explicitly_launch_blocked_before_stage0_passes():
    source = (SCRIPTS / "423_prepare_pricefm_stage_r122_long_memory.py").read_text()
    assert '"launch_authorized": False' in source
    assert '"stage0_launch_blocked"' in source
    assert "candidate_universe.csv" in source
    assert "fit_manifest.csv" in source
    assert "data_L3120.yaml" in source


def test_no_article_registry_joint_exal_mcmc_or_launch_yaml_surface():
    for filename in (
        "421_prepare_pricefm_stage_r122_stage0_calibration.py",
        "422_run_pricefm_stage_r122_stage0_calibration.py",
        "423_prepare_pricefm_stage_r122_long_memory.py",
    ):
        source = (SCRIPTS / filename).read_text().lower()
        assert "launch.yaml" not in source
        assert 'registry_mutation_authorized": true' not in source
        assert 'article_mutation_authorized": true' not in source
        assert 'joint_model_authorized": true' not in source
        assert 'mcmc_authorized": true' not in source
        assert 'exal_authorized": true' not in source
