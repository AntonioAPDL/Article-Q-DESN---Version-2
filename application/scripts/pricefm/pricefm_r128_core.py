"""Regional causal windows and stochastic screening, with frozen R127 helpers."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys

import numpy as np
import pandas as pd


def dependencies(root):
    here = Path(root) / 'application/scripts/pricefm'
    sys.path.insert(0, str(here))
    import pricefm_r123_runtime as runtime
    return runtime


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    sys.modules[name] = value
    spec.loader.exec_module(value)
    return value


def slice_arrays(runtime, arrays, indices):
    return runtime.subset_arrays(arrays, np.asarray(indices, dtype=int))


def read_frame(raw, regions, end):
    columns = ['time_utc'] + [f'{r}-{v}' for r in regions for v in ('price', 'load', 'solar', 'wind')]
    chunks = []
    boundary = pd.Timestamp(end, tz='UTC')
    for chunk in pd.read_csv(raw, usecols=columns, chunksize=20000):
        index = pd.DatetimeIndex(pd.to_datetime(chunk.pop('time_utc'), utc=True)) + pd.Timedelta(hours=1)
        chunk.index = index
        kept = chunk[index < boundary]
        if len(kept): chunks.append(kept)
        if index[-1] >= boundary: break
    frame = pd.concat(chunks)
    if not frame.index.is_unique or not np.all(np.diff(frame.index.as_unit('ns').asi8) == 15 * 60 * 10**9):
        raise ValueError('unique fixed-market quarter-hour grid required')
    if not np.isfinite(frame.to_numpy()).all(): raise ValueError('nonfinite regional input')
    return frame


def regional_arrays(runtime, frame, origins, spec):
    region = spec['region']; positions = frame.index.get_indexer(origins)
    if np.any(positions < 3120) or np.any(positions + 96 > len(frame)):
        raise ValueError('complete common history and response support required')
    names = ('load', 'solar', 'wind')
    x = frame[[f'{region}-{v}' for v in names]].to_numpy(dtype=float)
    labels = [f'{region}::{v}' for v in names]
    if spec['feature_policy'] == 'graph_summary_mean_std':
        neighbors = runtime.active_regions(spec)[1:]
        if not neighbors: raise ValueError('nonempty graph required')
        neighbor = np.stack([frame[[f'{r}-{v}' for v in names]].to_numpy(dtype=float) for r in neighbors])
        x = np.column_stack((x, neighbor.mean(axis=0), neighbor.std(axis=0)))
        labels += [f'neighbors::{kind}::{v}' for kind in ('mean', 'sd') for v in names]
    elif spec['feature_policy'] != 'target_only':
        raise ValueError('undeclared feature policy')
    y = frame[f'{region}-price'].to_numpy(dtype=float)
    return runtime.ExplicitArrays(
        np.stack([y[p - 3120:p] for p in positions]),
        np.stack([x[p - 3120:p] for p in positions]),
        np.stack([x[p:p + 96] for p in positions]),
        np.stack([y[p:p + 96] for p in positions]),
        np.array([v.isoformat() for v in origins]), tuple(labels),
        (dict(region=region, current_exogenous=True, future_neighbor_prices=False),))


def training_subset_valid(arrays, splits):
    anchors = pd.to_datetime(arrays.anchors, utc=True)
    if len(anchors) != 940 or anchors[0] != pd.Timestamp('2022-02-04', tz='UTC'):
        raise ValueError('fixed common training support differs')
    for split in splits:
        train, validation = split['train'], split['validation']
        if anchors[train[-1]] + pd.Timedelta(days=1) > anchors[validation[0]]:
            raise ValueError('training response overlaps validation')
    if anchors[-1] + pd.Timedelta(days=1) > pd.Timestamp('2024-09-01', tz='UTC'):
        raise ValueError('internal support crosses official training boundary')


def save_arrays(path, arrays):
    np.savez_compressed(path, **{k: getattr(arrays, k) for k in
        ('price_history', 'exog_history', 'exog_future', 'response', 'anchors')},
        exog_names=np.array(arrays.exog_names))


def load_arrays(runtime, path):
    with np.load(path, allow_pickle=False) as p:
        return runtime.ExplicitArrays(*(p[k] for k in
            ('price_history', 'exog_history', 'exog_future', 'response', 'anchors')),
            tuple(map(str, p['exog_names'])), (dict(path=str(path)),))


def normal_predictions(runtime, arrays, spec, fit, positions, seed, paths=500,
                       observe=lambda value: None):
    from pricefm_r124_covariance import GaussianSampler
    engine = runtime.BASE
    positions = np.asarray(positions, dtype=int)
    if len(positions) != len(arrays.response) or len(set(positions)) != len(positions):
        raise ValueError('unique origin identities required')
    sampler = GaussianSampler(); seed_for = engine.deterministic_seed
    beta = sampler(fit['beta_mean'], fit['beta_cov'], paths, seed_for(seed, 'normal_beta'))
    omega = 1 / np.random.default_rng(seed_for(seed, 'normal_sigma')).gamma(
        fit['omega_shape'], 1 / fit['omega_rate'], size=paths)
    # Ridge is conjugate NIG, unlike the mean-field RHS Normal fit.
    if fit['prior_type'] == 'scaled_ridge':
        mean_omega = fit['omega_rate'] / (fit['omega_shape'] - 1)
        beta = fit['beta_mean'] + (beta - fit['beta_mean']) * np.sqrt(omega / mean_omega)[:, None]
    reservoir, config, _ = runtime.make_reservoir(spec, len(runtime.input_names(spec, arrays.exog_names)))
    output = np.empty((len(positions), 96, 7))
    for origin, position in enumerate(positions):
        states = [np.repeat(s, paths, axis=0) for s in
                  engine.initialize_states(arrays, spec, reservoir, config, [origin])]
        generated = np.empty((paths, 96))
        for h in range(96):
            u = engine.explicit_input(arrays, spec, np.repeat(origin, paths), h, generated[:, :h])
            states = engine.reservoir_step(states, u, reservoir, config)
            z = engine.readout_rows(states, u, spec['readout'])
            noise = np.random.default_rng(seed_for(seed, 'innovation', int(position), h)).standard_normal(paths)
            generated[:, h] = np.einsum('sp,sp->s', z, beta) + np.sqrt(omega) * noise
            output[origin, h] = np.quantile(generated[:, h], runtime.QUANTILES)
            observe(dict(origin=int(position), origins_finished=origin, horizon_finished=h + 1))
    if not np.isfinite(output).all(): raise RuntimeError('nonfinite stochastic forecast')
    return output, dict(sampler=sampler.audit, paths=paths, teacher_forcing_between_origins=True,
        recursive_within_origin=True, parameters_fixed_within_path=True,
        ridge_beta_omega_coupling=fit['prior_type'] == 'scaled_ridge', future_target_access=False)


def internal_score(runtime, arrays, spec, fit, split, per_clock, seed, observe=lambda value: None,
                   paired_mean=False):
    from pricefm_r127_contract import shifted_windows, window_identity, common_metrics
    idx = split['validation']
    positions = np.unique(np.linspace(0, len(idx) - 2, per_clock).round().astype(int))
    metrics = []; old = []; audits = []
    for offset in (0, 24, 48, 72):
        shifted = shifted_windows(arrays, idx[positions], offset, idx)
        window_identity(shifted, pd.to_datetime(arrays.anchors[idx[0]], utc=True),
            pd.to_datetime(arrays.anchors[idx[-1]], utc=True) + pd.Timedelta(days=1))
        prediction, audit = normal_predictions(runtime, shifted, spec, fit, positions,
            runtime.BASE.deterministic_seed(seed, 'clock', offset), observe=observe)
        metrics.append(common_metrics(shifted.response, prediction)); audits.append(audit)
        if paired_mean:
            old.append(runtime.recursive_normal_score(shifted, spec, fit, np.arange(len(positions))))
    keys = ('AQL', 'median_MAE', 'coverage_80', 'width_80')
    return dict(**{k: float(np.mean([m[k] for m in metrics])) for k in keys},
        clock_metrics=metrics, mean_recursion_AQL=None if not old else float(np.mean([m['AQL'] for m in old])),
        origin_clock_pairs=4 * len(positions), sampler_audits=audits)


def regional_candidates(runtime, anchors, registry, region):
    templates = [dict(value) for value in anchors]
    row = registry[registry.region.eq(region) & registry.fold.eq(1)].iloc[0]
    base = dict(templates[0], region=region, depth=int(row.depth), units=json.loads(row.units),
        m_y=int(row.lag_window), m_x=4, alpha=float(row.alpha), rho=float(row.rho),
        input_scale=float(row.input_scale), input_fan_in=16, recurrent_sparsity=.05,
        interlayer_gain=.2, input_policy='coverage')
    templates.append(base)
    candidates = {}
    protected = None
    for template in templates:
        for feature in ('target_only', 'graph_summary_mean_std'):
            for policy in ('coverage', 'balanced'):
                spec = runtime.normalize_spec(dict(template, region=region, feature_policy=feature,
                    input_policy=policy, seed=2026092501))
                identity = fingerprint(spec)
                identifier = 'r128_' + identity[:16]
                candidates[identifier] = dict(candidate_id=identifier, spec=spec,
                    specification_sha256=identity)
                if template is base and feature == ('target_only' if row.feature_policy == 'target_only'
                                                     else 'graph_summary_mean_std') and policy == 'coverage':
                    protected = identifier
    if protected is None: raise RuntimeError('regional architecture anchor missing')
    return list(candidates.values()), protected, float(row.rhs_tau0)


def tau_center(p, n):
    r = p - 1; m0 = min(20, max(5, round(np.sqrt(r))))
    if r <= m0 or n <= 0: raise ValueError('invalid sparsity-reference dimension')
    return float(m0 / (r - m0) / np.sqrt(n))


def rank_groups(records, key):
    groups = {}
    for record in records:
        identity = tuple(record[k] for k in key)
        group = groups.setdefault(identity, {})
        if record['split'] in group: raise ValueError('duplicate split outcome')
        group[record['split']] = record
    valid = []; excluded = []
    for identity, group in groups.items():
        if set(group) != {1, 2, 3} or not all(r['certified'] for r in group.values()):
            excluded.append(dict(identity=list(identity), reason='incomplete_or_uncertified_three_split_group'))
            continue
        score = float(np.mean([r['AQL'] for r in group.values()]))
        if not np.isfinite(score): raise ValueError('nonfinite selection score')
        valid.append(dict(zip(key, identity), mean_AQL=score))
    return sorted(valid, key=lambda r: (r['mean_AQL'], tuple(str(r[k]) for k in key))), excluded


def benchmark_reference(path, expected_sha256):
    from pricefm_r126_contract import digest
    if digest(path) != expected_sha256: raise RuntimeError('frozen local PriceFM reference changed')
    table = pd.read_csv(path)[['region', 'fold', 'operational_pricefm_AQL']]
    if (len(table) != 114 or table.duplicated(['region', 'fold']).any()
            or table.region.nunique() != 38 or table.isna().any().any()
            or not np.isfinite(table.operational_pricefm_AQL).all()
            or any(set(group.fold) != {1, 2, 3} for _, group in table.groupby('region'))):
        raise ValueError('complete frozen 38-region three-fold PriceFM reference required')
    return table


def physical_cpus(count, sample_seconds=5):
    import time
    if not 1 <= count <= 15: raise ValueError('combined cap must be 1..15')
    def ticks():
        answer = {}
        for line in Path('/proc/stat').read_text().splitlines():
            w = line.split()
            if w[0].startswith('cpu') and w[0][3:].isdigit():
                v = list(map(int, w[1:9])); answer[int(w[0][3:])] = (sum(v), v[3] + v[4])
        return answer
    before = ticks(); time.sleep(sample_seconds); after = ticks(); groups = {}
    for cpu in os.sched_getaffinity(0):
        topology = Path(f'/sys/devices/system/cpu/cpu{cpu}/topology')
        key = ((topology / 'physical_package_id').read_text(), (topology / 'core_id').read_text())
        total = after[cpu][0] - before[cpu][0]; idle = after[cpu][1] - before[cpu][1]
        groups.setdefault(key, []).append((1 - idle / max(total, 1), cpu))
    idle = sorted((max(busy for busy, _ in siblings), min(c for _, c in siblings))
                  for siblings in groups.values() if max(busy for busy, _ in siblings) < .35)
    return [cpu for _, cpu in idle[:count]]
