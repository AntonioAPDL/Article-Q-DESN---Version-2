from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
sys.path.insert(0, str(SCRIPTS))

from pricefm_r120_engine import ExplicitArrays, feature_names, normalize_spec
from pricefm_r121_engine import (
    ALPHAS, INPUT_FAN_INS, INPUT_SCALES, M_X, M_Y, POLICIES, RHOS,
    SPARSITIES, bridge_decision, candidate_manifest, fold1_gate,
    manifest_row, normal_gate, select_anchors, select_bridge_panel,
    subset_arrays, tau_center,
)


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec); assert spec and spec.loader
    spec.loader.exec_module(module); return module


RUNNER = _load("pricefm_r121_runner_test", "418_run_pricefm_stage_r121_targeted_dense_refinement.py")
CLOSEOUT = _load("pricefm_r121_closeout_test", "419_closeout_pricefm_stage_r121_targeted_dense_refinement.py")


def _spec(index: int, depth: int = 1, policy: str = "graph_summary_mean") -> dict:
    units = {1: [192], 2: [128, 128], 3: [96, 64, 48]}[depth]
    return normalize_spec({"region": "BG", "feature_policy": policy, "calendar": "none",
        "readout": "pure_all_layers", "m_y": M_Y[index % len(M_Y)], "m_x": 0,
        "units": units, "alpha": ALPHAS[index % len(ALPHAS)], "rho": RHOS[index % len(RHOS)],
        "input_scale": INPUT_SCALES[index % len(INPUT_SCALES)],
        "input_fan_in": INPUT_FAN_INS[index % len(INPUT_FAN_INS)],
        "recurrent_sparsity": SPARSITIES[index % len(SPARSITIES)], "seed": 2026092501})


def _complete_frame(count: int = 20) -> pd.DataFrame:
    rows = []
    for index in range(count):
        depth = 3 if index == 4 else 2 if index in (3, 5) else 1
        policy = POLICIES[index % len(POLICIES)]
        row = manifest_row(_spec(index, depth, policy), "fixture")
        row.update({"rhs_rank": index + 1, "tau0": 1e-4 * (index + 1), "multiplier": 1,
                    "mean_AQL": 1 + index / 10, "mean_late_AQL": 1.1 + index / 10,
                    "worst_AQL": 1.2 + index / 10, "mean_coverage": .7})
        rows.append(row)
    return pd.DataFrame(rows).drop_duplicates("candidate_id").reset_index(drop=True)


def test_bridge_panel_is_six_complete_diverse_candidates():
    panel = select_bridge_panel(_complete_frame())
    assert len(panel) == 6
    assert not panel.candidate_id.duplicated().any()
    assert panel.bridge_reason.iloc[0] == "rhs_winner"
    assert panel.depth.astype(int).isin((2, 3)).any()


def test_anchor_and_candidate_design_is_bounded_unique_and_complete():
    complete = _complete_frame()
    bridge = select_bridge_panel(complete)
    anchors = select_anchors(complete, bridge)
    manifest, summary = candidate_manifest(anchors, maximum=1200)
    assert 100 <= len(manifest) <= 1200
    assert summary["candidate_count"] == len(manifest)
    assert not manifest.semantic_sha256.duplicated().any()
    assert set(M_Y).issubset(set(manifest.m_y.astype(int)))
    assert set(M_X).issubset(set(manifest.m_x.astype(int)))
    assert set(POLICIES).issubset(set(manifest.feature_policy))
    assert set(manifest.depth.astype(int)) == {1, 2, 3}
    assert not manifest.test_access_authorized.astype(bool).any()
    assert manifest.readout.eq("pure_all_layers").all()


def test_candidate_design_is_deterministic():
    complete = _complete_frame(); anchors = select_anchors(complete, select_bridge_panel(complete))
    first, one = candidate_manifest(anchors, maximum=300)
    second, two = candidate_manifest(anchors, maximum=300)
    assert first.semantic_sha256.tolist() == second.semantic_sha256.tolist()
    assert one == two


def test_tau_center_uses_nonintercept_rhs_dimension():
    observed = tau_center(193, 1000)
    m0 = round(np.sqrt(192))
    assert observed == pytest.approx((m0 / (192 - m0)) / np.sqrt(1000))
    with pytest.raises(ValueError): tau_center(5, 100)


def test_pure_readout_excludes_direct_input_columns():
    spec = _spec(0, depth=3)
    names = feature_names(spec, ["x"])
    assert names[0] == "intercept"
    assert not any(name.startswith("input::") for name in names)
    assert all(any(name.startswith(f"layer{layer}::") for name in names) for layer in (1, 2, 3))


def test_subset_arrays_preserves_provenance_and_rows():
    arrays = ExplicitArrays(np.arange(20).reshape(4, 5), np.zeros((4, 5, 2)), np.ones((4, 3, 2)),
                            np.arange(12).reshape(4, 3), np.asarray(list("abcd")), ("source",), ({"x": "y"},))
    result = subset_arrays(arrays, [1, 3])
    assert result.response.shape == (2, 3)
    assert result.anchors.tolist() == ["b", "d"]
    assert result.source_manifest == ({"x": "y"},)


def test_bridge_gate_pass_and_failure_are_predeclared():
    passing = pd.DataFrame({"candidate_id": list("abcdef"), "normal_AQL": [1, 2, 3, 4, 5, 6],
        "al_AQL": [1.1, 2.2, 3.1, 4.2, 5.1, 6.2], "family_eligible": [True] * 6,
        "invalid_quantiles": [0] * 6})
    assert bridge_decision(passing)["passed"] is True
    failing = passing.copy(); failing.loc[:2, "family_eligible"] = False
    assert bridge_decision(failing)["status"] == "NORMAL_PROXY_NOT_VALIDATED"


def test_normal_and_fold1_harm_guards():
    control = {"mean_AQL": 10, "mean_late_AQL": 12, "worst_AQL": 14}
    assert normal_gate({"mean_AQL": 9.8, "mean_late_AQL": 12.1, "worst_AQL": 14.2}, control)["passed"]
    assert not normal_gate({"mean_AQL": 10, "mean_late_AQL": 12, "worst_AQL": 14}, control)["passed"]
    assert fold1_gate({"AQL": 17, "late_AQL": 20, "interval_80_coverage": .5,
                       "interval_80_width": 60}, 20.1882, 55.5)["passed"]


def test_quantile_atom_firewalls_and_exact_cran_contract_are_present():
    text = (SCRIPTS / "420_fit_pricefm_stage_r121_quantile_atom.R").read_text()
    assert 'identical(config$family, "al")' in text
    assert 'expected_version = "1.1.1"' in text
    assert "prior_center_from_initializer = FALSE" in text
    assert "exal_authorized" in text


def test_runner_is_training_only_and_has_terminal_stop_rules():
    text = (SCRIPTS / "418_run_pricefm_stage_r121_targeted_dense_refinement.py").read_text()
    assert "NORMAL_PROXY_NOT_VALIDATED" in text
    assert "NO_NORMAL_REFINEMENT_GAIN" in text
    assert "FOLD1_DEVELOPMENT_GATE_FAILED" in text
    assert 'load_windows(Path(control["runtime_processed"]), 1, "train", spec)' in text
    assert "registry_mutated" in text and "article_mutated" in text
    assert "exal" not in RUNNER.parser().get_default("mode")


def test_circular_bootstrap_is_deterministic_and_not_iid():
    values = np.linspace(-1, 1, 25)
    first = CLOSEOUT._circular_interval(values, seed=11, replicates=100)
    second = CLOSEOUT._circular_interval(values, seed=11, replicates=100)
    assert first == second
    assert first["block_length"] > 1


def test_cpu_parser_rejects_duplicates_and_physical_contract_is_explicit():
    assert RUNNER._parse_cpus("1,3,5") == [1, 3, 5]
    with pytest.raises(ValueError): RUNNER._parse_cpus("1,1")
    source = (SCRIPTS / "418_run_pricefm_stage_r121_targeted_dense_refinement.py").read_text()
    assert "distinct_physical" in source
    assert "OMP_NUM_THREADS" in source


def test_no_launch_yaml_registry_article_joint_or_mcmc_surface():
    for filename in ("417_prepare_pricefm_stage_r121_targeted_dense_refinement.py",
                     "418_run_pricefm_stage_r121_targeted_dense_refinement.py",
                     "419_closeout_pricefm_stage_r121_targeted_dense_refinement.py"):
        text = (SCRIPTS / filename).read_text().lower()
        assert "launch.yaml" not in text
        assert "joint_model_authorized\": true" not in text
        assert "mcmc_authorized\": true" not in text
