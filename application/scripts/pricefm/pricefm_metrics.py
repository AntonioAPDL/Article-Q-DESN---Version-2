"""PriceFM metric helpers used by the DESN smoke workflow."""

from __future__ import annotations

import numpy as np


def normalize_quantiles(quantiles):
    qs = np.asarray(quantiles, dtype=float)
    if qs.ndim != 1 or qs.size == 0:
        raise ValueError("quantiles must be a nonempty one-dimensional array")
    if np.nanmax(qs) > 1.0:
        qs = qs / 100.0
    if not np.all(np.isfinite(qs)):
        raise ValueError("quantiles must be finite")
    if np.any((qs <= 0.0) | (qs >= 1.0)):
        raise ValueError("quantiles must be in (0, 1)")
    if np.any(np.diff(qs) <= 0):
        raise ValueError("quantiles must be strictly increasing")
    return qs


def _as_true_pred(y_true, y_pred):
    yt = np.asarray(y_true, dtype=float)
    yp = np.asarray(y_pred, dtype=float)
    if yp.ndim != yt.ndim + 1:
        raise ValueError("y_pred must have one more dimension than y_true")
    if yp.shape[:-1] != yt.shape:
        raise ValueError("y_pred leading dimensions must match y_true")
    if not np.all(np.isfinite(yt)):
        raise ValueError("y_true contains nonfinite values")
    if not np.all(np.isfinite(yp)):
        raise ValueError("y_pred contains nonfinite values")
    return yt, yp


def average_quantile_loss(y_true, y_pred, quantiles):
    qs = normalize_quantiles(quantiles)
    yt, yp = _as_true_pred(y_true, y_pred)
    if yp.shape[-1] != qs.size:
        raise ValueError("last dimension of y_pred must match quantiles")
    err = yt[..., None] - yp
    q = qs.reshape((1,) * yt.ndim + (qs.size,))
    return float(np.maximum(q * err, (q - 1.0) * err).mean())


def average_quantile_crossing_rate(y_pred):
    yp = np.asarray(y_pred, dtype=float)
    if yp.ndim < 1:
        raise ValueError("y_pred must be at least one-dimensional")
    if not np.all(np.isfinite(yp)):
        raise ValueError("y_pred contains nonfinite values")
    if yp.shape[-1] < 2:
        return 0.0
    return float((yp[..., :-1] > yp[..., 1:]).mean())


def median_index(quantiles):
    qs = normalize_quantiles(quantiles)
    return int(np.argmin(np.abs(qs - 0.5)))


def mae(y_true, y_pred, quantiles):
    yt, yp = _as_true_pred(y_true, y_pred)
    mid = median_index(quantiles)
    return float(np.mean(np.abs(yt - yp[..., mid])))


def rmse(y_true, y_pred, quantiles):
    yt, yp = _as_true_pred(y_true, y_pred)
    mid = median_index(quantiles)
    return float(np.sqrt(np.mean((yt - yp[..., mid]) ** 2)))


def inverse_scale_y(values, y_scaler):
    arr = np.asarray(values, dtype=float)
    shape = arr.shape
    inv = y_scaler.inverse_transform(arr.reshape(-1, 1)).reshape(shape)
    return inv


def metric_dict(y_true, y_pred, quantiles):
    return {
        "AQL": average_quantile_loss(y_true, y_pred, quantiles),
        "AQCR": average_quantile_crossing_rate(y_pred),
        "MAE": mae(y_true, y_pred, quantiles),
        "RMSE": rmse(y_true, y_pred, quantiles),
    }
