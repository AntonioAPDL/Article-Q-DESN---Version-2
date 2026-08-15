"""Naive PriceFM baselines for day-ahead DESN smoke runs."""

from __future__ import annotations

import numpy as np
import pandas as pd

from pricefm_metrics import normalize_quantiles


FREQ = pd.Timedelta(minutes=15)
STEPS_PER_DAY = 96


def _as_utc_indexed_series(series):
    s = series.copy()
    if not isinstance(s.index, pd.DatetimeIndex):
        raise ValueError("price series must use a DatetimeIndex")
    if s.index.tz is None:
        s.index = s.index.tz_localize("UTC")
    else:
        s.index = s.index.tz_convert("UTC")
    return s.sort_index()


def _anchor_ts(anchor):
    ts = pd.Timestamp(anchor)
    if ts.tzinfo is None:
        ts = ts.tz_localize("UTC")
    else:
        ts = ts.tz_convert("UTC")
    return ts


def make_naive_point_forecast(price_series, anchors, horizons, days):
    """Return point forecasts from averages of previous daily paths.

    Parameters
    ----------
    price_series:
        Scaled or original price series indexed by market time.
    anchors:
        Forecast anchor timestamps at 00:00 UTC.
    horizons:
        One-indexed delivery horizons.
    days:
        Positive integer number of previous daily paths to average.
    """
    s = _as_utc_indexed_series(price_series)
    horizons = np.asarray(horizons, dtype=int)
    if np.any(horizons < 1) or np.any(horizons > STEPS_PER_DAY):
        raise ValueError("horizons must be one-indexed values in 1:96")
    days = int(days)
    if days < 1:
        raise ValueError("days must be positive")

    out = np.full((len(anchors), len(horizons)), np.nan, dtype=float)
    for i, anchor in enumerate(anchors):
        a = _anchor_ts(anchor)
        for j, h in enumerate(horizons):
            offset = (int(h) - 1) * FREQ
            stamps = [a - pd.Timedelta(days=d) + offset for d in range(1, days + 1)]
            vals = []
            for stamp in stamps:
                if stamp in s.index:
                    vals.append(float(s.loc[stamp]))
            if len(vals) == days:
                out[i, j] = float(np.mean(vals))
    return out


def residual_quantile_offsets(y_true, point_pred, horizons, quantiles):
    qs = normalize_quantiles(quantiles)
    y = np.asarray(y_true, dtype=float)
    point = np.asarray(point_pred, dtype=float)
    horizons = np.asarray(horizons, dtype=int)
    if y.shape != point.shape:
        raise ValueError("y_true and point_pred shapes must match")
    if y.ndim != 2 or y.shape[1] != horizons.size:
        raise ValueError("y_true must be [origin, horizon]")
    offsets = np.full((horizons.size, qs.size), np.nan, dtype=float)
    resid = y - point
    for h_idx in range(horizons.size):
        vals = resid[:, h_idx]
        vals = vals[np.isfinite(vals)]
        if vals.size:
            offsets[h_idx, :] = np.quantile(vals, qs, method="linear")
    if not np.all(np.isfinite(offsets)):
        raise ValueError("could not estimate finite residual quantile offsets")
    return offsets


def apply_residual_quantile_offsets(point_pred, offsets):
    point = np.asarray(point_pred, dtype=float)
    off = np.asarray(offsets, dtype=float)
    if point.ndim != 2 or off.ndim != 2 or point.shape[1] != off.shape[0]:
        raise ValueError("point_pred must be [origin, horizon] and offsets [horizon, quantile]")
    return point[:, :, None] + off[None, :, :]


def make_naive_quantile_forecast(price_series, train_anchors, train_y, eval_anchors,
                                 horizons, quantiles, days):
    train_point = make_naive_point_forecast(price_series, train_anchors, horizons, days)
    offsets = residual_quantile_offsets(train_y, train_point, horizons, quantiles)
    eval_point = make_naive_point_forecast(price_series, eval_anchors, horizons, days)
    return apply_residual_quantile_offsets(eval_point, offsets)
