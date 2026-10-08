"""Read-only parent reuse and causally aligned shifted diagnostic windows."""
from dataclasses import replace

import numpy as np
import pandas as pd

from pricefm_r126_contract import market_ns, LEVELS


def shifted_windows(arrays, indices, offset, validation_indices):
    idx = np.asarray(indices, dtype=int)
    allowed = set(map(int, validation_indices))
    if offset not in (0, 24, 48, 72) or not len(idx) or len(set(idx)) != len(idx):
        raise ValueError('unique diagnostic indices and supported offset required')
    if any(int(i) not in allowed or (offset and int(i + 1) not in allowed) for i in idx):
        raise ValueError('all shifted response steps must remain inside internal validation')
    anchors = market_ns(arrays.anchors)
    if offset and np.any(anchors[idx + 1] - anchors[idx] != 86400 * 10**9):
        raise ValueError('adjacent daily windows required')
    lag = arrays.price_history.shape[1]
    if arrays.response.shape[1] != 96 or arrays.exog_future.shape[1] != 96:
        raise ValueError('complete quarter-hour H96 windows required')
    if not offset:
        return replace(arrays, price_history=arrays.price_history[idx],
            exog_history=arrays.exog_history[idx], exog_future=arrays.exog_future[idx],
            response=arrays.response[idx], anchors=arrays.anchors[idx])
    price = np.concatenate((arrays.price_history[idx], arrays.response[idx]), axis=1)
    exog = np.concatenate((arrays.exog_history[idx], arrays.exog_future[idx]), axis=1)
    future_y = np.concatenate((arrays.response[idx], arrays.response[idx + 1]), axis=1)
    future_x = np.concatenate((arrays.exog_future[idx], arrays.exog_future[idx + 1]), axis=1)
    return replace(arrays, price_history=price[:, offset:offset + lag],
        exog_history=exog[:, offset:offset + lag], response=future_y[:, offset:offset + 96],
        exog_future=future_x[:, offset:offset + 96],
        anchors=np.array([str(t) for t in pd.to_datetime(anchors[idx], utc=True)
                          + pd.Timedelta(minutes=15 * offset)]))


def window_identity(arrays, training_end, validation_end):
    start = pd.to_datetime(market_ns(arrays.anchors), utc=True)
    if np.any(start < pd.Timestamp(training_end)) or np.any(
            start + pd.Timedelta(days=1) > pd.Timestamp(validation_end)):
        raise ValueError('diagnostic windows overlap fitted responses or leave validation')
    return dict(first_origin=str(start.min()), last_origin=str(start.max()),
                train_response_end=str(training_end), validation_end=str(validation_end))


def common_metrics(truth, prediction):
    from pricefm_r126_contract import loss
    costs = loss(truth, prediction)
    return dict(AQL=float(costs.mean()), median_MAE=float(np.mean(abs(truth - prediction[:, :, 3]))),
        coverage_80=float(np.mean((truth >= prediction[:, :, 0]) & (truth <= prediction[:, :, -1]))),
        width_80=float(np.mean(prediction[:, :, -1] - prediction[:, :, 0])),
        exceedance=[float(np.mean(truth > prediction[:, :, i])) for i in range(len(LEVELS))])


def variance_terms(z, mean, covariance, factor=None):
    """Exact law of total variance under independent receiver beta and empirical z."""
    z = np.asarray(z)
    if factor is None:
        from pricefm_r124_covariance import covariance_factor
        factor = covariance_factor(covariance)[0]
    coefficient = float(np.mean(np.sum((z @ factor)**2, axis=1)))
    state = float(np.var(z @ mean))
    return coefficient, state, coefficient + state
