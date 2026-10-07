"""R126 immutable artifacts, explicit clock/scaling and complete-cohort gates."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import tempfile

import numpy as np
import pandas as pd

LEVELS = np.array([.10, .25, .45, .50, .55, .75, .90])
OPERATORS = ('mean_feature', 'path_specific', 'normal_driver',
             'rearranged_path_mean', 'cdf_pool_clipped', 'cdf_pool_linear')


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(2**20), b''):
            h.update(block)
    return h.hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + '.tmp.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, sort_keys=True, indent=2, allow_nan=False)
            stream.write('\n')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def immutable(path, value):
    path = Path(path)
    if path.exists():
        if read(path) != value: raise RuntimeError('immutable contract changed: ' + str(path))
    else:
        write(path, value)


def verify_hashes(ledger):
    for path, expected in ledger.items():
        if digest(path) != expected: raise RuntimeError('evidence changed: ' + path)


def seal(folder, metadata):
    folder = Path(folder)
    hashes = {str(p.relative_to(folder)): digest(p) for p in sorted(folder.rglob('*'))
              if p.is_file() and p.name != 'completed_evidence.json'}
    immutable(folder / 'completed_evidence.json', dict(metadata=metadata, artifacts=hashes))


def verified(folder):
    folder = Path(folder)
    if not folder.exists(): return None
    value = read(folder / 'completed_evidence.json')
    for name, expected in value['artifacts'].items():
        path = (folder / name).resolve()
        if not path.is_relative_to(folder.resolve()) or digest(path) != expected:
            raise RuntimeError('sealed output changed: ' + name)
    return value['metadata']


def market_ns(values):
    return pd.DatetimeIndex(pd.to_datetime(values, utc=True)).as_unit('ns').asi8


def official_origins(protocol, fold):
    start, end = protocol['test_intervals_market'][fold - 1]
    result = pd.date_range(start, end, inclusive='left', tz='UTC', freq='D')
    if len(result) != protocol['test_origin_counts'][fold - 1]:
        raise ValueError('official fold calendar differs')
    return result


def training_origins(protocol, fold):
    return pd.date_range(pd.Timestamp(protocol['new_model_first_train_origin_market']),
        pd.Timestamp(protocol['train_end_market'][fold - 1], tz='UTC'), inclusive='left', freq='D')


def transform(arrays, scaler, arrays_type):
    return arrays_type(
        (arrays.price_history - scaler['price_mean']) / scaler['price_scale'],
        (arrays.exog_history - np.array(scaler['exog_mean'])) / np.array(scaler['exog_scale']),
        (arrays.exog_future - np.array(scaler['exog_mean'])) / np.array(scaler['exog_scale']),
        (arrays.response - scaler['price_mean']) / scaler['price_scale'],
        arrays.anchors, arrays.exog_names, arrays.source_manifest)


def inverse_price(value, inner, outer):
    return (value * inner['price_scale'] + inner['price_mean']) * outer['y_scale'] + outer['y_center']


def loss(truth, prediction):
    truth, prediction = np.asarray(truth), np.asarray(prediction)
    if prediction.shape != (*truth.shape, 7) or truth.ndim != 2 or truth.shape[1] != 96:
        raise ValueError('complete H96 seven-quantile geometry required')
    if not np.isfinite(truth).all() or not np.isfinite(prediction).all():
        raise ValueError('finite forecasts and outcomes required')
    error = truth[:, :, None] - prediction
    return np.maximum(LEVELS * error, (LEVELS - 1) * error)


def choose(cells, protocol):
    expected = set(protocol['eligible_candidates'] + protocol['diagnostic_candidates'])
    groups = {}
    for cell in cells:
        key = (cell['candidate_id'], cell['split'])
        if key in groups: raise ValueError('duplicate internal cell')
        groups[key] = cell
    if set(groups) != {(c, s) for c in expected for s in (1, 2, 3)}:
        raise ValueError('all nine complete internal cells required')
    scores = {c: float(np.mean([groups[c, s]['AQL'] for s in (1, 2, 3)])) for c in expected}
    if not all(np.isfinite(list(scores.values()))): raise ValueError('finite selection scores required')
    eligible = protocol['eligible_candidates']
    for c in eligible:
        if any(groups[c, s]['formal_certified'] is not True for s in (1, 2, 3)):
            raise ValueError('eligible candidate lacks formal certification')
    winner = min(eligible, key=lambda c: (scores[c], c))
    return winner, scores


def training_valid(contract, protocol, fold):
    expected_end = protocol['train_end_market'][fold - 1]
    if (contract['fold'] != fold or contract['train_end_market'] != expected_end
            or contract['first_origin_market'] != protocol['new_model_first_train_origin_market']
            or contract['full_training_window'] is not True or contract['test_opened'] is not False
            or contract['raw_sha256'] != protocol['raw_sha256']
            or len(contract['response_sha256']) != 64 or len(contract['scaler_sha256']) != 64):
        raise ValueError('full-fold training provenance differs')
    return contract
