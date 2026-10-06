from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))


def load_script():
    path = SCRIPTS / "349_plot_pricefm_stage_r103_be_diagnostics.py"
    spec = importlib.util.spec_from_file_location(path.stem, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PLOT = load_script()


def toy_surface(offset: float = 0.0) -> dict:
    truth = np.asarray([[1.0, 2.0], [3.0, 4.0]])
    quantiles = PLOT.QUANTILES
    prediction = np.repeat(truth[..., None], len(quantiles), axis=-1) + offset
    prediction += (quantiles - 0.5).reshape(1, 1, -1)
    truth96 = np.tile(truth, (1, 48))
    prediction96 = np.tile(prediction, (1, 48, 1))
    return {
        "method": "r103",
        "fold": 1,
        "split": "validation",
        "anchors": np.asarray(["2024-01-01", "2024-01-02"]),
        "truth": truth96,
        "prediction": prediction96,
        "quantiles": quantiles,
    }


def test_pinball_metrics_and_horizon_geometry() -> None:
    surface = toy_surface()
    metrics = PLOT.surface_metrics(surface)
    expected = np.mean(np.abs((PLOT.QUANTILES - 0.5) * (PLOT.QUANTILES - (PLOT.QUANTILES < 0.5))))
    assert metrics["AQL"] > 0
    assert metrics["median_MAE"] == 0
    assert metrics["AQCR"] == 0
    assert metrics["coverage_10_90"] == 1
    horizon = PLOT.horizon_aql(surface)
    assert horizon.shape == (96,)
    np.testing.assert_allclose(horizon, horizon[0])


def test_surface_validation_rejects_wrong_quantiles_and_geometry() -> None:
    surface = toy_surface()
    broken = dict(surface)
    broken["quantiles"] = np.asarray([0.1, 0.5, 0.9])
    broken["prediction"] = broken["prediction"][..., :3]
    try:
        PLOT.validate_surface(broken)
    except ValueError as error:
        assert "quantile grid" in str(error)
    else:
        raise AssertionError("unexpected quantiles must fail")
    broken = dict(surface)
    broken["prediction"] = broken["prediction"][:, :-1]
    try:
        PLOT.validate_surface(broken)
    except ValueError as error:
        assert "geometry" in str(error)
    else:
        raise AssertionError("unexpected geometry must fail")


def test_alignment_gate_rejects_different_truth_or_anchors() -> None:
    first = toy_surface()
    second = toy_surface()
    PLOT.strict_anchor_alignment([first, second])
    numeric = toy_surface()
    numeric["anchors"] = PLOT.anchor_nanoseconds(numeric["anchors"])
    PLOT.strict_anchor_alignment([first, numeric])
    second = toy_surface()
    second["truth"] = second["truth"].copy()
    second["truth"][0, 0] += 1.0
    try:
        PLOT.strict_anchor_alignment([first, second])
    except ValueError as error:
        assert "responses" in str(error)
    else:
        raise AssertionError("different truth must fail")
    second = toy_surface()
    second["anchors"] = np.asarray(["x", "y"])
    try:
        PLOT.strict_anchor_alignment([first, second])
    except ValueError as error:
        assert "anchors" in str(error)
    else:
        raise AssertionError("different anchors must fail")


def test_midpoint_origin_rule_is_deterministic() -> None:
    assert PLOT.representative_origin_index(1) == 0
    assert PLOT.representative_origin_index(2) == 0
    assert PLOT.representative_origin_index(3) == 1


def test_long_table_requires_complete_horizon_rectangle() -> None:
    import pandas as pd

    frame = pd.DataFrame({
        "origin_id": np.repeat([0, 1], 96),
        "horizon": np.tile(np.arange(1, 97), 2),
        "value": np.arange(192),
    })
    matrix = PLOT._matrix_from_long(frame, "value")
    assert matrix.shape == (2, 96)
    try:
        PLOT._matrix_from_long(frame.iloc[:-1], "value")
    except ValueError as error:
        assert "rectangle" in str(error)
    else:
        raise AssertionError("incomplete long table must fail")
