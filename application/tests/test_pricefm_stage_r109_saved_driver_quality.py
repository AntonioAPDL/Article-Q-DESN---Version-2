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


def load_script(name: str):
    path = SCRIPTS / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


AUDIT = load_script("365_closeout_pricefm_stage_r109_saved_driver_quality.py")


def test_driver_scoring_keeps_point_and_probabilistic_metrics_separate() -> None:
    truth = np.asarray([[0.0] * 96, [2.0] * 96])
    offsets = np.asarray([-2.0, -1.0, -0.2, 0.0, 0.2, 1.0, 2.0])
    prediction = truth[..., None] + offsets
    center = truth + 0.5
    row, horizon = AUDIT.score_driver_arrays(
        "AT", 1, "normal_rhs_paths", truth, prediction, center,
        "saved_predictive_path_mean",
    )
    assert row["AQL"] > 0
    assert row["coverage_10_90"] == 1
    assert row["center_MAE"] == pytest.approx(0.5)
    assert row["center_RMSE"] == pytest.approx(0.5)
    assert row["center_bias"] == pytest.approx(0.5)
    assert len(horizon) == 96
    assert "center_AQL" not in row


def test_driver_scoring_rejects_incomplete_or_nonfinite_arrays() -> None:
    truth = np.zeros((2, 96))
    curves = np.zeros((2, 96, 7))
    center = np.zeros((2, 96))
    curves[0, 0, 0] = np.nan
    with pytest.raises(ValueError, match="incomplete or non-finite"):
        AUDIT.score_driver_arrays(
            "AT", 1, "normal_rhs_paths", truth, curves, center,
            "saved_predictive_path_mean",
        )


def test_published_artifact_record_uses_final_path(tmp_path: Path) -> None:
    temporary = tmp_path / "temporary.csv"
    temporary.write_text("value\n1\n")
    published = tmp_path / "final" / "result.csv"
    record = AUDIT.published_artifact_record("test", temporary, published)
    assert record["path"] == str(published.resolve())
    assert record["bytes"] == temporary.stat().st_size
    assert len(record["sha256"]) == 64


def test_selected_family_comes_from_executed_r108_case_terminal() -> None:
    terminal = {
        "status": "completed_recursive_driver_decomposition_case",
        "selection_split": "validation_only",
        "test_opened": False,
        "selected_family": "exal",
    }
    assert AUDIT.selected_family_from_r108_terminal(terminal) == "exal"
    terminal["test_opened"] = True
    with pytest.raises(RuntimeError, match="selection authority"):
        AUDIT.selected_family_from_r108_terminal(terminal)


def gate_fixture() -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    overall = pd.DataFrame([
        {"driver_method": "normal_rhs_paths", "folds": 27, "AQL": 20.0, "coverage_10_90": 0.70},
        {"driver_method": "normal_ridge_paths", "folds": 27, "AQL": 10.0, "coverage_10_90": 0.72},
        {"driver_method": "cached_pricefm_quantiles", "folds": 27, "AQL": 9.0, "coverage_10_90": 0.74},
    ])
    regions = []
    for region in AUDIT.REGIONS:
        regions.extend([
            {"region": region, "driver_method": "normal_rhs_paths", "AQL": 20.0},
            {"region": region, "driver_method": "normal_ridge_paths", "AQL": 10.0},
        ])
    horizons = []
    for horizon in range(1, 97):
        horizons.extend([
            {"driver_method": "normal_rhs_paths", "horizon": horizon, "AQL": 20.0, "n_origins": 27},
            {"driver_method": "normal_ridge_paths", "horizon": horizon, "AQL": 10.0, "n_origins": 27},
            {"driver_method": "cached_pricefm_quantiles", "horizon": horizon, "AQL": 9.0, "n_origins": 27},
        ])
    return overall, pd.DataFrame(regions), pd.DataFrame(horizons)


def test_candidate_gate_advances_only_complete_material_improvement() -> None:
    overall, regions, horizons = gate_fixture()
    gates = AUDIT.candidate_gates(overall, regions, horizons)
    ridge = gates[gates.candidate.eq("normal_ridge_paths")]
    rhs = gates[gates.candidate.eq("normal_rhs_paths")]
    assert ridge.all_gates_passed.all()
    assert not rhs.all_gates_passed.any()


def test_candidate_gate_rejects_regional_harm() -> None:
    overall, regions, horizons = gate_fixture()
    mask = regions.region.eq("EE") & regions.driver_method.eq("normal_ridge_paths")
    regions.loc[mask, "AQL"] = 23.0
    gates = AUDIT.candidate_gates(overall, regions, horizons)
    row = gates[
        gates.candidate.eq("normal_ridge_paths")
        & gates.gate.eq("maximum_region_aql_harm_at_most_10pct")
    ].iloc[0]
    assert not bool(row.passed)
    assert not bool(row.all_gates_passed)


def test_r109_contract_blocks_fitting_test_launch_and_mutation() -> None:
    source = (SCRIPTS / "365_closeout_pricefm_stage_r109_saved_driver_quality.py").read_text()
    assert ".fit(" not in source
    assert '"selection_split": "validation_only"' in source
    assert '"test_opened": False' in source
    assert '"model_fit_started": False' in source
    assert '"downstream_replay_started": False' in source
    assert '"registry_mutated": False' in source
    assert '"article_mutated": False' in source
    assert '"launch_yaml_written": False' in source
    assert "subprocess" not in source
    assert len(AUDIT.REGIONS) == 9
