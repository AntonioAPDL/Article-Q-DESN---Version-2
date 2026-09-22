from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import numpy as np
import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/383_audit_pricefm_stage_r111c_bg_residual_decomposition.py"
SPEC = importlib.util.spec_from_file_location("pricefm_r111c", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def test_pinball_loss_has_expected_geometry_and_values() -> None:
    truth = np.zeros((2, 96))
    prediction = np.ones((7, 2, 96))
    loss = MODULE.pinball_loss(truth, prediction)
    assert loss.shape == prediction.shape
    np.testing.assert_allclose(loss[:, 0, 0], 1.0 - MODULE.QUANTILES)


def test_alignment_rejects_missing_policy() -> None:
    truth = np.zeros((2, 96))
    predictions = {name: np.zeros((7, 2, 96)) for name in MODULE.POLICIES[:-1]}
    with pytest.raises(RuntimeError, match="incomplete"):
        MODULE.validate_alignment(truth, predictions, np.asarray(["a", "b"]), MODULE.QUANTILES)


def test_real_frozen_decomposition_is_complete_and_read_only(tmp_path: Path) -> None:
    summary = MODULE.run(ROOT, tmp_path)
    assert summary["status"] == "completed_bg_residual_decomposition"
    assert summary["folds_complete"] == 3
    # Frozen prediction tensors are stored as float32, so recomputed AQLs can
    # differ from the pre-serialization summaries below the sixth decimal.
    assert summary["r111b_AQL"] == pytest.approx(11.1121119526, abs=1e-5)
    assert summary["r97_AQL"] == pytest.approx(10.8271661756, abs=1e-5)
    assert summary["pricefm_AQL"] == pytest.approx(11.4928086378, abs=1e-5)
    assert summary["r110_AQL"] == pytest.approx(12.2152653262, abs=1e-5)
    assert summary["r111b_beats_pricefm_all_folds"] is True
    assert summary["r111b_beats_r97_fold_count"] == 1
    assert summary["short_horizon_gap_vs_r97"] < 0
    assert summary["all_late_blocks_worse_than_r97"] is True
    assert summary["all_quantiles_worse_than_r97"] is True
    assert summary["recommended_action"] == "stop_recursive_redesign_retain_R97"
    assert summary["model_fit_started"] is False
    assert summary["launch_started"] is False
    assert summary["test_opened"] is False
    assert summary["registry_mutated"] is False
    assert summary["article_mutated"] is False

    attribution = pd.read_csv(tmp_path / "pricefm_stage_r111c_gap_attribution.csv")
    for _, group in attribution.groupby("dimension"):
        assert group.contribution_AQL_points.sum() == pytest.approx(summary["r111b_minus_r97"], abs=1e-10)
    assert len(pd.read_csv(tmp_path / "pricefm_stage_r111c_policy_metrics.csv")) == 16
    assert len(pd.read_csv(tmp_path / "pricefm_stage_r111c_fold_block_quantile_gap.csv")) == 84
    assert json.loads((tmp_path / "decision.json").read_text())["article_classification"] == "diagnostic_only_no_promotion"


def test_script_has_no_fit_launch_or_mutation_path() -> None:
    text = SCRIPT.read_text()
    assert '"model_fit_started": False' in text
    assert '"launch_started": False' in text
    assert '"registry_mutated": False' in text
    assert '"article_mutated": False' in text
    assert "subprocess.run" not in text
    assert "ProcessPoolExecutor" not in text
