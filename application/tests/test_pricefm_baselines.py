"""Tests for PriceFM naive baseline helpers."""

import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "application" / "scripts" / "pricefm"))

from pricefm_baselines import (  # noqa: E402
    apply_residual_quantile_offsets,
    make_naive_point_forecast,
    make_naive_quantile_forecast,
    residual_quantile_offsets,
)


def test_naive_point_forecast_uses_previous_days_only():
    idx = pd.date_range("2025-01-01", periods=10 * 96, freq="15min", tz="UTC")
    price = pd.Series(np.arange(len(idx), dtype=float), index=idx)
    anchor = pd.Timestamp("2025-01-08", tz="UTC")
    pred = make_naive_point_forecast(price, [anchor], [1, 24], days=1)
    assert pred[0, 0] == price.loc[anchor - pd.Timedelta(days=1)]
    assert pred[0, 1] == price.loc[anchor - pd.Timedelta(days=1) + pd.Timedelta(minutes=23 * 15)]
    avg = make_naive_point_forecast(price, [anchor], [1], days=3)
    expected = np.mean([price.loc[anchor - pd.Timedelta(days=d)] for d in (1, 2, 3)])
    assert avg[0, 0] == pytest.approx(expected)


def test_residual_offsets_are_monotone_and_apply_by_horizon():
    y = np.array([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])
    point = np.array([[0.0, 1.0], [2.0, 1.0], [4.0, 5.0]])
    offsets = residual_quantile_offsets(y, point, [1, 2], [0.05, 0.25, 0.50])
    assert np.all(np.diff(offsets, axis=1) >= 0)
    pred = apply_residual_quantile_offsets(point, offsets)
    assert pred.shape == (3, 2, 3)


def test_naive_quantile_forecast_is_deterministic():
    idx = pd.date_range("2025-01-01", periods=12 * 96, freq="15min", tz="UTC")
    price = pd.Series(np.sin(np.arange(len(idx)) / 10.0), index=idx)
    train_anchors = [pd.Timestamp("2025-01-08", tz="UTC"), pd.Timestamp("2025-01-09", tz="UTC")]
    train_y = np.column_stack([
        [price.loc[a] for a in train_anchors],
        [price.loc[a + pd.Timedelta(minutes=15)] for a in train_anchors],
    ])
    eval_anchors = [pd.Timestamp("2025-01-10", tz="UTC")]
    p1 = make_naive_quantile_forecast(price, train_anchors, train_y, eval_anchors, [1, 2], [0.05, 0.5], days=1)
    p2 = make_naive_quantile_forecast(price, train_anchors, train_y, eval_anchors, [1, 2], [0.05, 0.5], days=1)
    assert np.allclose(p1, p2)
