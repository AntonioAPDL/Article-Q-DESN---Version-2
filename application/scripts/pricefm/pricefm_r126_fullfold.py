"""Full permitted BG training windows, fixed priors and nested AL initialization."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess

import numpy as np
import pandas as pd
from sklearn.preprocessing import RobustScaler

from pricefm_r126_contract import (digest, read, write, immutable, seal, verified,
                                  transform, training_valid, market_ns, training_origins)

RSCRIPT = '/data/jaguir26/local/opt/R/4.6.0/bin/Rscript'


def raw_frame(data, end=None):
    frame = pd.read_csv(Path(data) / 'raw/FINAL.csv',
                        usecols=['time_utc', 'BG-price', 'BG-load', 'BG-solar', 'BG-wind'])
    frame.index = pd.DatetimeIndex(pd.to_datetime(frame.pop('time_utc'), utc=True)) + pd.Timedelta(hours=1)
    if not frame.index.is_unique or not np.all(np.diff(market_ns(frame.index)) == 15 * 60 * 10**9):
        raise ValueError('raw fixed market clock is not a unique quarter-hour grid')
    if end is not None: frame = frame[frame.index < pd.Timestamp(end, tz='UTC')]
    return frame


def arrays_from_raw(runtime, frame, origins, outer, source):
    index = frame.index; pos = index.get_indexer(origins)
    if np.any(pos < 3120) or np.any(pos + 96 > len(frame)):
        raise ValueError('missing required pre-origin history or response support')
    raw = frame[['BG-price', 'BG-load', 'BG-solar', 'BG-wind']].to_numpy(dtype=float)
    scaled = np.column_stack(((raw[:, 0] - outer['y_center']) / outer['y_scale'],
                             (raw[:, 1:] - np.array(outer['x_center'])) / np.array(outer['x_scale'])))
    scaled = scaled.astype('float32').astype('float64')
    history = np.stack([scaled[p - 3120:p] for p in pos])
    future = np.stack([scaled[p:p + 96] for p in pos])
    return runtime.BASE.ExplicitArrays(history[:, :, 0], history[:, :, 1:], future[:, :, 1:],
        future[:, :, 0], np.array([v.isoformat() for v in origins]),
        ('BG::load', 'BG::solar', 'BG::wind'), (source,))


def full_design(runtime, data, folder, choice, protocol, fold):
    folder = Path(folder)
    if verified(folder):
        return training_valid(read(folder / 'training.json'), protocol, fold)
    if folder.exists(): raise RuntimeError('partial training evidence must not be overwritten')
    frame = raw_frame(data, protocol['train_end_market'][fold - 1])
    train = frame[frame.index >= pd.Timestamp('2022-01-01', tz='UTC')]
    sx = RobustScaler().fit(train[['BG-load', 'BG-solar', 'BG-wind']].to_numpy())
    sy = RobustScaler().fit(train[['BG-price']].to_numpy())
    outer = dict(x_center=sx.center_.tolist(), x_scale=sx.scale_.tolist(),
                 y_center=float(sy.center_[0]), y_scale=float(sy.scale_[0]))
    origins = training_origins(protocol, fold)
    source = dict(raw_sha256=protocol['raw_sha256'], region='BG', fold=fold,
                  train_end_market=protocol['train_end_market'][fold - 1])
    arrays = arrays_from_raw(runtime, frame, origins, outer, source)
    scaled, inner = runtime.standardize_from_training_origins(arrays, np.arange(len(origins)))
    spec = runtime.normalize_spec(choice['spec'])
    X, y, audit = runtime.teacher_forced_design(scaled, spec)
    folder.mkdir(parents=True)
    np.asarray(X, dtype='<f8').tofile(folder / 'X.bin')
    np.asarray(y, dtype='<f8').tofile(folder / 'y.bin')
    scalers = dict(inner=inner, outer=outer, fit_on='permitted_train_only')
    write(folder / 'scalers.json', scalers)
    features = runtime.feature_names(spec, runtime.input_names(spec, arrays.exog_names))
    metadata = dict(n=len(y), p=X.shape[1], feature_names=features,
                    depth=spec['depth'], test_opened=False, audit=audit)
    write(folder / 'design.json', metadata)
    write(folder / 'terminal.json', dict(status='completed_r126_quantile_design', test_opened=False,
        files={name: digest(folder / name) for name in ('X.bin', 'y.bin', 'design.json', 'scalers.json')}))
    runtime.write_stats_packet(folder / 'stats', dict(n=len(y), p=X.shape[1],
        XtX=X.T @ X, Xty=X.T @ y, yty=float(y @ y)), dict(fold=fold, full_training_window=True))
    contract = dict(source, full_training_window=True, test_opened=False,
        first_origin_market=origins[0].isoformat(), origin_count=len(origins),
        last_origin_market=origins[-1].isoformat(), response_rows=len(y),
        response_sha256=digest(folder / 'y.bin'), scaler_sha256=digest(folder / 'scalers.json'),
        specification_sha256=choice['specification_sha256'])
    training_valid(contract, protocol, fold)
    immutable(folder / 'training.json', contract); seal(folder, contract)
    return contract


def run_r(entry, flag, contract, log):
    env = dict(os.environ)
    env['LD_LIBRARY_PATH'] = '/data/jaguir26/local/opt/R/4.6.0/lib64/R/lib:' + env.get('LD_LIBRARY_PATH', '')
    env['PATH'] = '/data/jaguir26/local/opt/R/4.6.0/bin:' + env['PATH']
    log = Path(log); log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('x') as stream:
        subprocess.run([RSCRIPT, str(entry), flag, str(contract)], env=env,
                       stdout=stream, stderr=subprocess.STDOUT, check=True)


def normal_fit(folder, design, choice, protocol, template_job, output, code):
    folder = Path(folder)
    if verified(folder): return read(folder / 'terminal.json')
    template = read(read(Path(template_job['normal_dir']) / 'terminal.json')['contract_path'])
    stats = Path(design) / 'stats'
    contract = dict(template, tag=protocol['tag'], fold=int(folder.parent.name[-1]),
        candidate_id=choice['candidate_id'], fit_id=folder.parent.name + '_normal',
        output_dir=str(folder), stats_dir=str(stats), split=int(folder.parent.name[-1]),
        selection_scope='frozen_spec_full_outer_training_only',
        max_iter=protocol['normal_max_iter'], min_iter=protocol['normal_min_iter'],
        initial_fit_path=None, initial_fit_sha256=None, tau0=choice['tau0'],
        stats_terminal_sha256=digest(stats / 'terminal.json'),
        posterior_target_sha256=digest(stats / 'terminal.json') + ':tau0=' + format(choice['tau0'], '.17g'))
    path = Path(output) / 'contracts' / (folder.parent.name + '_normal.json')
    immutable(path, contract)
    entry = Path(code) / 'application/scripts/pricefm/442_fit_pricefm_stage_r123_certified_normal.R'
    run_r(entry, '--contract', path, Path(output) / 'logs' / (folder.parent.name + '_normal.log'))
    terminal = read(folder / 'terminal.json')
    if not terminal['full_variational_certified']:
        raise RuntimeError('Normal full-fit stationarity gate failed; test scoring withheld')
    seal(folder, dict(kind='normal', posterior_target_sha256=contract['posterior_target_sha256']))
    return terminal


def al_fit(folder, design, parent, parent_type, choice, protocol, control, output, code, fold, tau):
    folder = Path(folder)
    if verified(folder): return read(folder / 'terminal.json')
    adapter = Path(code) / 'application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R'
    manifest = Path(control['cran_manifest'])
    name = f'fold={fold}_al_{tau:.2f}'
    contract = dict(stage='R126_full_outer', tag=protocol['tag'], fold=fold, family='al',
        tau=tau, tau0=choice['tau0'], output_dir=str(folder), design_dir=str(design),
        parent_dir=str(parent), parent_type=parent_type, parent_terminal_sha256=digest(Path(parent) / 'terminal.json'),
        cran_library=control['cran_library'], cran_manifest=str(manifest), cran_manifest_sha256=digest(manifest),
        cran_adapter=str(adapter), cran_adapter_sha256=digest(adapter),
        design_terminal_sha256=digest(Path(design) / 'terminal.json'),
        max_iter=protocol['al_max_iter'], tol=protocol['al_tol'],
        n_samp=protocol['al_n_samp'], n_samp_xi=protocol['al_n_samp_xi'],
        seed=2026092501 + 1000 + fold * 100 + round(tau * 100),
        test_opened=False, prior_center_from_initializer=False,
        posterior_target_sha256=digest(Path(design) / 'terminal.json') + f':tau={tau:.2f}:tau0={choice["tau0"]:.17g}')
    path = Path(output) / 'contracts' / (name + '.json'); immutable(path, contract)
    run_r(Path(code) / 'application/scripts/pricefm/448_fit_pricefm_stage_r126_al.R',
          '--config', path, Path(output) / 'logs' / (name + '.log'))
    terminal = read(folder / 'terminal.json')
    if not terminal['formal_converged'] or not terminal['finite_core']:
        raise RuntimeError('AL full-fit convergence gate failed; no test ranking or automatic budget inflation')
    seal(folder, dict(kind='al', posterior_target_sha256=contract['posterior_target_sha256']))
    return terminal
