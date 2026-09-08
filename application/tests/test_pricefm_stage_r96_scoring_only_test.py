"""Focused tests for the frozen R96 SE_2 scoring-only test audit."""

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
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_beta_loader_sorts_and_rejects_noncontiguous_indices(tmp_path):
    module = load("312_run_pricefm_stage_r96_scoring_only_fold.py")
    path = tmp_path / "beta.csv"
    pd.DataFrame({"feature_index": [2, 1], "beta_mean": [20.0, 10.0]}).to_csv(
        path, index=False
    )
    assert module.load_beta(path).tolist() == [10.0, 20.0]
    pd.DataFrame({"feature_index": [1, 3], "beta_mean": [10.0, 30.0]}).to_csv(
        path, index=False
    )
    with pytest.raises(RuntimeError, match="Non-contiguous"):
        module.load_beta(path)


def test_validation_replay_is_key_aligned_and_fail_closed():
    module = load("312_run_pricefm_stage_r96_scoring_only_fold.py")
    rows = pd.DataFrame({"origin_id": [1, 1], "horizon": [1, 2]})
    frozen = pd.DataFrame({
        "split": ["val", "val"], "origin_id": [1, 1], "horizon": [2, 1],
        "tau": [0.5, 0.5], "pred_scaled": [2.0, 1.0],
    })
    replay = module.validation_replay(
        rows, frozen, np.array([1.0, 2.0]), 0.5, 1e-10
    )
    assert replay["passed"] is True
    assert replay["maximum_absolute_difference"] == 0.0
    frozen.loc[frozen.horizon.eq(2), "pred_scaled"] = 2.1
    replay = module.validation_replay(
        rows, frozen, np.array([1.0, 2.0]), 0.5, 1e-10
    )
    assert replay["passed"] is False


def _gate_fixture(module):
    cases = pd.DataFrame({
        "case_id": ["f1", "f2"], "region": ["SE_2", "SE_2"],
        "fold": [1, 2], "candidate_test_AQL": [2.0, 3.0],
        "validation_replay_pass": [True, True],
        "model_refitted": [False, False],
        "selection_changed_after_test": [False, False],
    })
    quantiles = pd.DataFrame([
        {"region": "SE_2", "fold": fold, "tau": tau, "candidate_test_AQL": value}
        for fold, value in ((1, 2.0), (2, 3.0)) for tau in module.TAUS
    ])
    horizons = pd.DataFrame([
        {
            "region": "SE_2", "fold": fold, "horizon_group": block,
            "candidate_test_AQL": value,
        }
        for fold, value in ((1, 2.0), (2, 3.0)) for block in module.BLOCKS
    ])
    references = pd.DataFrame({
        "region": ["SE_2", "SE_2"], "fold": [1, 2],
        "authoritative_qdesn_test_AQL": [2.5, 2.5],
        "cached_pricefm_test_AQL": [2.2, 3.5],
    })
    return cases, quantiles, horizons, references


def test_promotion_gate_requires_both_comparators_and_complete_surfaces():
    module = load("314_closeout_pricefm_stage_r96_scoring_only_test.py")
    cases, quantiles, horizons, references = _gate_fixture(module)
    decisions = module.apply_promotion_gates(cases, quantiles, horizons, references)
    assert decisions.promotion_eligible.tolist() == [True, False]
    assert decisions.beats_authoritative_qdesn.tolist() == [True, False]
    assert decisions.beats_cached_pricefm.tolist() == [True, True]

    incomplete = quantiles.loc[~((quantiles.fold == 1) & np.isclose(quantiles.tau, 0.9))]
    decisions = module.apply_promotion_gates(cases, incomplete, horizons, references)
    assert not bool(decisions.loc[decisions.fold.eq(1), "promotion_eligible"].iloc[0])


def test_generated_data_config_opens_only_preregistered_test_folds(tmp_path, monkeypatch):
    module = load("311_prepare_pricefm_stage_r96_scoring_only_test.py")
    monkeypatch.setattr(module, "ARTIFACT_REPO", tmp_path)
    source = {"pricefm": {
        "raw_dir": "raw", "interim_dir": "interim", "external_repo_dir": "external",
        "log_dir": "logs", "processed_dir": "processed",
        "windows": {"lag_window": 96, "lead_window": 96},
        "splits": [
            {"fold": fold, "train": ["a", "b"], "val": ["b", "c"], "test": ["c", "d"]}
            for fold in (1, 2, 3)
        ],
    }}
    generated = module.make_test_data_config(source, tmp_path / "processed_r96", 240)
    spec = generated["pricefm"]
    assert spec["windows"]["lag_window"] == 240
    assert [item["fold"] for item in spec["splits"]] == [1, 2, 3]
    assert all(set(item) == {"fold", "train", "val", "test"} for item in spec["splits"])
    assert Path(spec["processed_dir"]).is_absolute()


def test_launcher_keeps_hashed_launch_summary_stable_after_closeout():
    text = (SCRIPTS / "313_launch_pricefm_stage_r96_scoring_only_test.py").read_text()
    assert 'args.manifest.parent / "closeout_status.json"' in text
    assert 'result["closeout"] = closeout' in text
    assert 'return result' in text


def test_r96_static_firewalls_require_scoring_token_and_forbid_model_fit():
    prep = (SCRIPTS / "311_prepare_pricefm_stage_r96_scoring_only_test.py").read_text()
    worker = (SCRIPTS / "312_run_pricefm_stage_r96_scoring_only_fold.py").read_text()
    launcher = (SCRIPTS / "313_launch_pricefm_stage_r96_scoring_only_test.py").read_text()
    closeout = (SCRIPTS / "314_closeout_pricefm_stage_r96_scoring_only_test.py").read_text()
    assert 'APPROVAL_TOKEN = "RUN_PRICEFM_R96_SCORING_ONLY_TEST"' in launcher
    assert '"model_fitted": False' in worker
    assert "validation_replay" in worker
    assert "model_refit_authorized" in prep
    assert "candidate_test_AQL < decisions.authoritative_qdesn_test_AQL" in closeout
    assert "candidate_test_AQL < decisions.cached_pricefm_test_AQL" in closeout
    assert "registry_mutated" in closeout and "article_mutated" in closeout
