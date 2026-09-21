from __future__ import annotations

import importlib.util
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/371_audit_pricefm_stage_r110_driver_representation.py"
spec = importlib.util.spec_from_file_location("pricefm_r110_representation", SCRIPT)
diagnosis = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(diagnosis)


def rows(mode: str, fold: int, value: float) -> list[dict]:
    return [
        {
            "mode": mode,
            "region": region,
            "fold": fold,
            "AQL": value,
            "n_loss_atoms": 100,
            "posterior_paths": 500,
        }
        for region in diagnosis.REGIONS
    ]


def references(policy: str, fold: int, value: float) -> list[dict]:
    return [
        {
            "policy": policy,
            "region": region,
            "fold": fold,
            "AQL": value,
            "n_loss_atoms": 100,
        }
        for region in diagnosis.REGIONS
    ]


def test_selection_uses_fold1_and_confirmation_uses_folds2_3():
    metrics = pd.DataFrame(
        rows("raw_posterior_paths", 1, 9.0)
        + rows("raw_posterior_paths", 2, 8.0)
        + rows("raw_posterior_paths", 3, 8.0)
        + rows("analytic_median", 1, 7.0)
        + rows("analytic_median", 2, 8.0)
        + rows("analytic_median", 3, 8.0)
    )
    reference = pd.DataFrame(
        sum((references("self_rhs_neighbors", fold, 12.0) for fold in (1, 2, 3)), [])
        + sum((references("r97_direct_reference", fold, 7.5) for fold in (1, 2, 3)), [])
    )
    selected, gates = diagnosis.select_and_gate(metrics, reference)
    assert selected == "analytic_median"
    assert gates.passed.all()


def test_source_is_no_refit_test_closed_and_parallel():
    text = SCRIPT.read_text()
    assert '"model_fit_started": False' in text
    assert '"test_opened": False' in text
    assert '"registry_mutated": False' in text
    assert '"article_mutated": False' in text
    assert "ProcessPoolExecutor" in text
    assert "selection_uses_fold1_only" in text
    assert "source_manifest_sha256" in text
    assert "R110 analytic driver identity mismatch" in text


def test_valid_case_rejects_wrong_identity(monkeypatch, tmp_path):
    terminal = {
        "stage": "R110C",
        "status": "completed_r110_driver_representation_case",
        "mode": "analytic_median",
        "region": "BG",
        "fold": 1,
        "posterior_paths": 500,
        "model_fit_started": False,
        "test_opened": False,
    }
    monkeypatch.setattr(
        diagnosis.REPLAY,
        "verify_relative_terminal",
        lambda path, status: terminal,
    )
    assert diagnosis.valid_case(tmp_path, "analytic_median", "BG", 1)
    assert not diagnosis.valid_case(tmp_path, "analytic_quantile_curve", "BG", 1)
    assert not diagnosis.valid_case(tmp_path, "analytic_median", "EE", 1)
    assert not diagnosis.valid_case(tmp_path, "analytic_median", "BG", 2)
