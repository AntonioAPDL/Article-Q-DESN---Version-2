"""Tests for PriceFM metric helpers."""

import sys
from pathlib import Path

import numpy as np
import pytest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "application" / "scripts" / "pricefm"))

from pricefm_metrics import (  # noqa: E402
    average_quantile_crossing_rate,
    average_quantile_loss,
    inverse_scale_y,
    mae,
    metric_dict,
    normalize_quantiles,
    rmse,
)


def test_quantiles_normalize_percent_inputs():
    assert np.allclose(normalize_quantiles([5, 25, 50]), [0.05, 0.25, 0.50])
    with pytest.raises(ValueError):
        normalize_quantiles([0.5, 0.25])


def test_aql_matches_hand_computation():
    y = np.array([[2.0]])
    pred = np.array([[[1.0, 3.0]]])
    qs = np.array([0.25, 0.75])
    expected = np.mean([0.25 * 1.0, (0.75 - 1.0) * -1.0])
    assert average_quantile_loss(y, pred, qs) == pytest.approx(expected)


def test_crossing_rate_and_point_metrics():
    y = np.array([[1.0, 2.0]])
    pred = np.array([
        [[0.0, 1.0, 2.0], [3.0, 2.0, 4.0]],
    ])
    assert average_quantile_crossing_rate(pred) == pytest.approx(1.0 / 4.0)
    assert mae(y, pred, [0.05, 0.25, 0.50]) == pytest.approx(1.5)
    assert rmse(y, pred, [0.05, 0.25, 0.50]) == pytest.approx(np.sqrt(2.5))
    out = metric_dict(y, pred, [0.05, 0.25, 0.50])
    assert set(out.keys()) == {"AQL", "AQCR", "MAE", "RMSE"}


def test_inverse_scaling_roundtrip_with_sklearn():
    sklearn = pytest.importorskip("sklearn.preprocessing")
    scaler = sklearn.RobustScaler()
    raw = np.array([[10.0], [20.0], [30.0]])
    scaler.fit(raw)
    scaled = scaler.transform(raw).reshape(3)
    assert np.allclose(inverse_scale_y(scaled, scaler), raw.reshape(3))
