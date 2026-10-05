"""Exclude validation origins preceding the end of any fitted target window."""
import numpy as np
import pandas as pd


def guarded_splits(anchors, splits, *, sample_step, horizon=96):
    times = pd.DatetimeIndex(pd.to_datetime(anchors, utc=True)).as_unit("ns")
    step = pd.Timedelta(sample_step)
    if (horizon != 96 or pd.isna(step) or step <= pd.Timedelta(0) or times.hasnans
            or not times.is_monotonic_increasing or not times.is_unique):
        raise ValueError("invalid target-window contract or explicit sample cadence")
    result, evidence = [], []
    for item in splits:
        train = np.asarray(item["train"], dtype=int)
        validation = np.asarray(item["validation"], dtype=int)
        if (not len(train) or not len(validation) or min(train.min(), validation.min()) < 0
                or max(train.max(), validation.max()) >= len(times)
                or len(np.unique(train)) != len(train) or len(np.unique(validation)) != len(validation)
                or np.intersect1d(train, validation).size):
            raise ValueError("invalid training/validation origin indices")
        last_target = times[train].max() + (horizon - 1) * step
        keep = np.asarray(times[validation] > last_target)
        clean = validation[keep]
        if not len(clean): raise ValueError("no temporally held-out validation origins")
        result.append(dict(item, train=train.copy(), validation=clean))
        evidence.append(dict(split=int(item["split"]), training_origins=len(train),
            original_validation_origins=len(validation), clean_validation_origins=len(clean),
            excluded_origin_indices=validation[~keep].tolist(),
            kept_local_validation_indices=np.flatnonzero(keep).tolist(),
            last_fitted_target_utc=last_target.isoformat(), first_scored_origin_utc=times[clean[0]].isoformat(),
            training_indices_unchanged=True, posterior_target_unchanged=True))
    return result, evidence


def regular_axis(values):
    axis = pd.DatetimeIndex(pd.to_datetime(values, utc=True)).as_unit("ns")
    if len(axis) < 96 or axis.hasnans or not axis.is_unique or not axis.is_monotonic_increasing:
        raise ValueError("invalid processed market-time axis")
    differences = np.diff(axis.asi8)
    if not np.all(differences == differences[0]) or differences[0] <= 0:
        raise ValueError("processed target rows do not have a constant positive cadence")
    return dict(rows=len(axis), first_utc=axis[0].isoformat(), last_utc=axis[-1].isoformat(),
        sample_step_ns=int(differences[0]), sample_step_minutes=float(differences[0] / 60e9))
