#!/usr/bin/env python3
"""R138: structurally diverse DK_1 AL receivers and Normal recursive drivers."""
from __future__ import annotations

import argparse
import fcntl
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import shutil

for name in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS',
             'BLIS_NUM_THREADS', 'NUMEXPR_NUM_THREADS', 'R_DATATABLE_NUM_THREADS'):
    os.environ[name] = '1'
os.environ['PYTHONDONTWRITEBYTECODE'] = '1'

import numpy as np
import pandas as pd
import pricefm_r134_core as core

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
BASE_TAG = 'pricefm_stage_r138_dk1_diverse_driver_20261016'
REGION = 'DK_1'
TAG = BASE_TAG
OUT = DATA / 'campaigns' / TAG
PREP = DATA / 'launch_prep' / TAG
PARENT_R134_TAG = 'pricefm_stage_r134_pure_qdesn_optimization_20261011'
PARENT_R135_TAG = 'pricefm_stage_r135_r134_fixedpoint_completion_20261012'
PARENT_R134_OUT = DATA / 'campaigns' / PARENT_R134_TAG
PARENT_R134_PREP = DATA / 'launch_prep' / PARENT_R134_TAG
PARENT_R135_OUT = DATA / 'campaigns' / PARENT_R135_TAG
PARENT_R135_PREP = DATA / 'launch_prep' / PARENT_R135_TAG
PROTOCOL = ROOT / 'application/config/pricefm_stage_r138_dk1_diverse_driver_20261016.json'
ENTRY = Path(__file__).resolve()
_OUTCOMES = {}
RSCRIPT = Path('/data/jaguir26/local/opt/R/4.6.0/bin/Rscript')
R_LIBRARY_DIR = Path('/data/jaguir26/local/opt/R/4.6.0/lib64/R/lib')


def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()


def source_identity():
    branch = git(ROOT, 'branch', '--show-current')
    if not branch.startswith('work/pricefm-r138-') or git(ROOT, 'status', '--porcelain'):
        raise RuntimeError('clean committed dedicated R138 source required')
    return dict(branch=branch, head=git(ROOT, 'rev-parse', 'HEAD'))


def setup(dependency):
    runtime = core.dependencies(dependency)
    global read, write, immutable, digest, seal, verified, verify_hashes
    from pricefm_r126_contract import read, write, immutable, digest, seal, verified, verify_hashes
    return runtime


def validate_protocol(p):
    if (p['tag'] != BASE_TAG or p['region'] != REGION or p['paths'] != 500
            or p['maximum_workers'] != 30 or p['folds'] != [1, 2, 3]
            or p['quantiles'] != [.1, .25, .45, .5, .55, .75, .9]):
        raise ValueError('declared R138 geometry differs')
    if (p['al_max_iter'] != 300 or p['wave1_unique_receivers'] != 6
            or p['wave2_unique_receivers'] != 6 or p['driver_structures'] != 3):
        raise ValueError('R138 staged confirmation budget differs')
    for key in ('mcmc_authorized', 'joint_authorized', 'exal_authorized',
                'new_broad_screen_authorized',
                'registry_mutation_authorized', 'article_mutation_authorized',
                'promotion_authorized', 'all_region_launch_authorized', 'priors_from_initializers'):
        if p[key] is not False: raise ValueError('forbidden authority/model expansion: ' + key)


def resources(p, allowance=0):
    mem = {s.split(':')[0]: int(s.split()[1]) for s in Path('/proc/meminfo').read_text().splitlines()}
    stat = os.statvfs(DATA)
    available = stat.f_bavail * stat.f_frsize / 2**30
    used = sum(v.stat().st_size for v in OUT.rglob('*') if v.is_file()) / 2**30
    if (mem['MemAvailable'] / 2**20 < p['minimum_free_memory_GiB']
            or available < p['minimum_free_disk_GiB'] + allowance):
        raise RuntimeError('resource reserve reached; pending work preserved, own active work drains')
    return dict(available_memory_GiB=mem['MemAvailable'] / 2**20,
                free_disk_GiB=available, campaign_output_GiB=used)


def new_task(name, kind, **values):
    return dict(name=name, kind=kind, **values)


def unique_best_rhs(ranking):
    """Keep the best certified tau0 once per architecture, preserving rank order."""
    seen = set(); output = []
    for row in ranking:
        if row['candidate_id'] in seen:
            continue
        seen.add(row['candidate_id']); output.append(dict(row))
    return output


def _parent_rhs(candidate_id, tau0, split):
    matches = []
    for task_path in (PARENT_R134_OUT / 'tasks').glob(
            f'rhs_{REGION}_{candidate_id}_s{split}_t*.json'):
        task = read(task_path)
        if np.isclose(task['tau0'], tau0, rtol=1e-12, atol=0):
            matches.append((task_path, task))
    if len(matches) != 1:
        raise RuntimeError(f'expected one parent RHS task for {candidate_id}, split {split}, tau0 {tau0}')
    task_path, task = matches[0]; folder = PARENT_R134_OUT / 'tasks_done' / task['name']
    result = read(folder / 'result.json')
    if not verified(folder) or not result.get('certified', False):
        raise RuntimeError('parent RHS fit is not sealed and certified: ' + task['name'])
    return task_path, folder / 'fit', result


def prepare(dependency, release, reference=None):
    runtime = setup(dependency); p = read(PROTOCOL); validate_protocol(p); identity = source_identity()
    if git(dependency, 'rev-parse', 'HEAD') != p['dependency_head'] or git(dependency, 'status', '--porcelain'):
        raise RuntimeError('frozen dependency worktree differs')
    receipt = read(release)
    if receipt['source'] != identity or not receipt['passed']:
        raise RuntimeError('source-matched R138 launch-prep release required')
    if (PREP / 'preparation.json').is_file():
        prior = read(PREP / 'preparation.json')
        if prior['source'] != identity or prior['protocol'] != p:
            raise RuntimeError('existing R138 preparation belongs to another source')
        verify_hashes(prior['source_sha256']); verify_hashes(prior['input_sha256'])
        verify_hashes(prior['bank_sha256'])
        return dict(status='R138_ALREADY_PREPARED', wave1_receivers=len(prior['receiver_waves']['wave1']),
                    wave2_receivers=len(prior['receiver_waves']['wave2']), drivers=len(prior['drivers']))

    resources(p, p['maximum_workers'] * p['worker_storage_allowance_GiB'])
    r134_prep = read(PARENT_R134_PREP / 'preparation.json')
    r135_prep = read(PARENT_R135_PREP / 'preparation.json')
    r135_terminal = read(PARENT_R135_OUT / 'terminal.json')
    r135_choice = read(PARENT_R135_OUT / 'frozen_choices.json')[REGION]
    if (r134_prep['source']['head'] != p['parent_r134_source_head']
            or r135_prep['source']['head'] != p['parent_r135_source_head']
            or r135_terminal['status'] != 'R135_COMPLETE_NOT_PROMOTED'
            or r135_choice['candidate_id'] != 'r134_882f4990e3dd76a1'
            or not np.isclose(r135_choice['ranking'][0]['mean_AQL'], p['r135_internal_AQL'])):
        raise RuntimeError('frozen R134/R135 parent identity differs')
    if r134_prep['dependency_head'] != p['dependency_head'] or r135_prep['dependency_head'] != p['dependency_head']:
        raise RuntimeError('parent dependency differs')

    rhs_closeout_path = PARENT_R134_OUT / 'rhs_closeout.json'
    rhs_closeout = read(rhs_closeout_path)[REGION]
    unique = unique_best_rhs(rhs_closeout['ranking'])
    needed = p['wave1_unique_receivers'] + p['wave2_unique_receivers']
    if len(unique) < needed:
        raise RuntimeError('too few complete unique R134 RHS architectures')
    candidate_map = {row['candidate_id']: dict(row) for row in r134_prep['regional'][REGION]['candidates']}
    selected = unique[:needed]
    for row in selected:
        row.update(candidate_map[row['candidate_id']])
        row['design_role'] = 'R134_unique_RHS_rank_reuse'

    control_id = r135_choice['candidate_id']
    distinct_target = next(row for row in unique
        if row['candidate_id'] != control_id
        and candidate_map[row['candidate_id']]['spec']['feature_policy'] == 'target_only')
    graph = next(row for row in unique
        if candidate_map[row['candidate_id']]['spec']['feature_policy'].startswith('graph_'))
    drivers = []
    for role, row in (('R135_control', next(v for v in unique if v['candidate_id'] == control_id)),
                      ('best_distinct_target_only', distinct_target), ('best_graph', graph)):
        value = dict(row); value.update(candidate_map[row['candidate_id']]); value['driver_role'] = role
        drivers.append(value)
    if len({v['candidate_id'] for v in drivers}) != p['driver_structures']:
        raise RuntimeError('driver structures are not distinct')

    fit_inventory = {}; ledger = {}
    for row in {v['candidate_id']: v for v in [*selected, *drivers]}.values():
        tau0 = next(v['tau0'] for v in unique if v['candidate_id'] == row['candidate_id'])
        for split in (1, 2, 3):
            task_path, fit_path, result = _parent_rhs(row['candidate_id'], tau0, split)
            key = f"{row['candidate_id']}|{split}"
            fit_inventory[key] = dict(candidate_id=row['candidate_id'], tau0=tau0, split=split,
                task_path=str(task_path), fit_path=str(fit_path), parent_AQL=result['AQL'])
            for path in (task_path, fit_path / 'terminal.json', fit_path / 'beta_mean.bin',
                         fit_path / 'beta_cov.bin', fit_path.parent / 'result.json',
                         fit_path.parent / 'completed_evidence.json'):
                ledger[str(path)] = digest(path)

    features = sorted({v['spec']['feature_policy'] for v in [*selected, *drivers]})
    banks = {}; bank_hashes = {}
    for feature in features:
        path = PARENT_R134_OUT / 'training_banks' / REGION / (feature + '.npz')
        arrays = core.load_arrays(runtime, path)
        core.training_subset_valid(arrays, runtime.internal_splits(len(arrays.response)))
        banks[feature] = str(path); bank_hashes[str(path)] = digest(path)

    official = r134_prep['official_protocol']; control = r134_prep['control']
    if digest(DATA / 'raw/FINAL.csv') != official['raw_sha256']:
        raise RuntimeError('raw source changed')
    references = [v for v in r134_prep['references'] if v['region'] == REGION]
    if len(references) != 3 or {v['fold'] for v in references} != {1, 2, 3}:
        raise RuntimeError('complete DK_1 comparison references required')
    parent_paths = [PARENT_R134_PREP / 'preparation.json', PARENT_R135_PREP / 'preparation.json',
        PARENT_R134_OUT / 'blocked.json', rhs_closeout_path,
        PARENT_R135_OUT / 'frozen_choices.json', PARENT_R135_OUT / 'terminal.json',
        Path(control['cran_manifest'])]
    ledger.update({str(path): digest(path) for path in parent_paths})
    source_paths = [ENTRY, HERE / 'pricefm_r138_cross_driver.py',
        HERE / '472_fit_pricefm_stage_r138_certified_al_300.R', HERE / 'pricefm_r138_release.py',
        HERE / '473_launch_pricefm_stage_r138_after_r137.py',
        HERE / 'pricefm_r134_core.py', PROTOCOL,
        ROOT / 'application/tests/test_pricefm_stage_r138_dk1_diverse_driver.py',
        dependency / 'application/R/pricefm_recursive_normal_fit.R']
    source_paths += list((dependency / 'application/scripts/pricefm').glob('*.py'))
    source_paths += list((dependency / 'application/scripts/pricefm').glob('*.R'))
    source_paths += list((Path(control['normal_runtime']) / 'R').glob('*.R'))
    source_paths += list((Path(control['cran_library']) / 'exdqlm' / 'R').glob('*'))
    source_hashes = {str(path): digest(path) for path in source_paths if path.is_file()}
    prep = dict(source=identity, dependency=str(dependency), dependency_head=p['dependency_head'],
        protocol=p, official_protocol=official, template=r134_prep['template'], control=control,
        references=references, receiver_waves=dict(wave1=selected[:p['wave1_unique_receivers']],
            wave2=selected[p['wave1_unique_receivers']:]), drivers=drivers,
        parent_rhs=fit_inventory, training_banks=banks,
        source_sha256=source_hashes, input_sha256=ledger, bank_sha256=bank_hashes,
        release_path=str(release), release_sha256=digest(release),
        historical_ridge_reused=640, historical_rhs_structures_reused=30,
        new_ridge_fits=0, new_rhs_screen_fits=0, test_used_for_selection=False,
        official_development_test_seen_previously=True, raw_identity=r134_prep['raw_identity'])
    immutable(PREP / 'preparation.json', prep)
    return dict(status='R138_PREPARED', wave1_receivers=len(prep['receiver_waves']['wave1']),
        wave2_receivers=len(prep['receiver_waves']['wave2']), drivers=len(drivers),
        ridge_refits=0, rhs_screen_refits=0, test_used_for_selection=False)


def valid():
    prep = read(PREP / 'preparation.json')
    if source_identity() != prep['source']: raise RuntimeError('executed R138 source changed')
    if git(prep['dependency'], 'rev-parse', 'HEAD') != prep['dependency_head']:
        raise RuntimeError('frozen dependency changed')
    verify_hashes(prep['source_sha256']); verify_hashes(prep['input_sha256'])
    verify_hashes(prep['bank_sha256'])
    raw = (DATA / 'raw/FINAL.csv').stat()
    if (raw.st_size, raw.st_mtime_ns) != (prep['raw_identity']['bytes'], prep['raw_identity']['mtime_ns']):
        raise RuntimeError('raw source metadata changed; full content re-audit required')
    if digest(prep['release_path']) != prep['release_sha256']: raise RuntimeError('release changed')
    return prep


def bank(runtime, prep, task):
    path = Path(prep['training_banks'][task['spec']['feature_policy']])
    if digest(path) != prep['bank_sha256'][str(path)]: raise RuntimeError('train-only bank changed')
    return core.load_arrays(runtime, path)


def parent_rhs(prep, candidate_id, split):
    value = prep['parent_rhs'][f'{candidate_id}|{split}']
    path = Path(value['fit_path'])
    if digest(path / 'terminal.json') != prep['input_sha256'][str(path / 'terminal.json')]:
        raise RuntimeError('parent Normal RHS fit changed')
    return path


def scaled_internal(runtime, arrays, split):
    cell = runtime.internal_splits(len(arrays.response))[split - 1]
    scaled, scaler = runtime.standardize_from_training_origins(arrays, cell['train'])
    return scaled, scaler, cell


def scale_metrics(score, scaler):
    for key in ('AQL', 'late_AQL', 'median_MAE', 'width_80', 'mean_recursion_AQL'):
        if score.get(key) is not None: score[key] *= scaler['price_scale']
    return score


def normal_contract(prep, task, stats, output):
    dependency = Path(prep['dependency']); template = prep['template']
    helper = dependency / 'application/R/pricefm_recursive_normal_fit.R'
    entry = dependency / 'application/scripts/pricefm/442_fit_pricefm_stage_r123_certified_normal.R'
    source = [helper, entry, *[Path(prep['control']['normal_runtime']) / 'R' / n for n in
        ('priors_beta.R', 'qdesn_rhs_ns_prior.R')]]
    return dict(template, tag=TAG, fit_id=task['name'], candidate_id=task['candidate_id'], split=task['split'],
        output_dir=str(output), stats_dir=str(stats), tau0=task['tau0'],
        helper_path=str(helper), initial_fit_path=None, initial_fit_sha256=None,
        max_iter=prep['protocol']['normal_max_iter'], min_iter=prep['protocol']['normal_min_iter'],
        source_sha256={str(path): digest(path) for path in source},
        stats_terminal_sha256=digest(stats / 'terminal.json'),
        posterior_target_sha256=digest(stats / 'terminal.json') + f":tau0={task['tau0']:.17g}")


def r_run(prep, entry, contract, task):
    path = OUT / 'contracts' / (task['name'] + '.json'); immutable(path, contract)
    log = OUT / 'fit_logs' / (task['name'] + '.log')
    if not RSCRIPT.is_file() or not R_LIBRARY_DIR.is_dir():
        raise RuntimeError('audited project R 4.6 runtime is unavailable')
    flag = '--config' if task['kind'] in ('al', 'internal_al') else '--contract'
    log.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env['LD_LIBRARY_PATH'] = str(R_LIBRARY_DIR) + ':' + env.get('LD_LIBRARY_PATH', '')
    env['PATH'] = str(RSCRIPT.parent) + ':' + env['PATH']
    with log.open('x') as stream:
        subprocess.run([str(RSCRIPT), str(entry), flag, str(path)], env=env,
            stdout=stream, stderr=subprocess.STDOUT, check=True)


def cross_internal_score(runtime, prep, task, normal, quantiles, observe):
    from pricefm_r127_contract import shifted_windows, window_identity, common_metrics
    from pricefm_r138_cross_driver import forecast
    receiver_arrays = bank(runtime, prep, task)
    driver_task = dict(task, spec=task['driver_spec'])
    driver_arrays = bank(runtime, prep, driver_task)
    receiver_scaled, receiver_scaler, receiver_cell = scaled_internal(
        runtime, receiver_arrays, task['split'])
    driver_scaled, driver_scaler, driver_cell = scaled_internal(
        runtime, driver_arrays, task['split'])
    if (not np.array_equal(receiver_cell['train'], driver_cell['train'])
            or not np.array_equal(receiver_cell['validation'], driver_cell['validation'])
            or not np.array_equal(receiver_arrays.anchors, driver_arrays.anchors)):
        raise RuntimeError('driver and receiver internal windows differ')
    idx = receiver_cell['validation']
    count = prep['protocol']['quantile_origins_per_clock']
    positions = np.unique(np.linspace(0, len(idx) - 2, count).round().astype(int))
    metrics = []; audits = []
    for offset in prep['protocol']['clock_offsets_steps']:
        receiver_window = shifted_windows(receiver_scaled, idx[positions], offset, idx)
        driver_window = shifted_windows(driver_scaled, idx[positions], offset, idx)
        begin = pd.to_datetime(receiver_arrays.anchors[idx[0]], utc=True)
        end = pd.to_datetime(receiver_arrays.anchors[idx[-1]], utc=True) + pd.Timedelta(days=1)
        window_identity(receiver_window, begin, end); window_identity(driver_window, begin, end)
        stable = idx[positions] * 96 + offset
        values, audit = forecast(runtime, receiver_window, task['spec'], receiver_scaler,
            driver_window, task['driver_spec'], driver_scaler, normal, quantiles, stable,
            runtime.BASE.deterministic_seed(prep['protocol']['forecast_seed'], task['candidate_id'],
                task['driver_candidate_id'], task['split'], 'clock', offset), observe=observe)
        metric = common_metrics(values['truth'], values['cdf_pool_clipped'])
        metric['crossing_rate'] = float(np.mean(np.diff(values['path_specific'], axis=2) < 0))
        metrics.append(metric); audits.append(audit)
    keys = ('AQL', 'median_MAE', 'coverage_80', 'width_80', 'crossing_rate')
    score = {key: float(np.mean([value[key] for value in metrics])) for key in keys}
    score.update(clock_metrics=metrics, origin_clock_pairs=4 * len(positions), forecast_audits=audits)
    return scale_metrics(score, receiver_scaler)


def execute(runtime, prep, task, output, beat):
    p = prep['protocol']; dep = Path(prep['dependency']); seed = p['forecast_seed']
    if task['kind'] in ('internal_design', 'design'):
        spec = task['spec']
        if task['kind'] == 'internal_design':
            arrays = bank(runtime, prep, task)
            scaled, scaler, cell = scaled_internal(runtime, arrays, task['split'])
            scaled = core.slice_arrays(runtime, scaled, cell['train'])
            boundary = str(pd.to_datetime(arrays.anchors[cell['validation'][0]], utc=True))
            identity = dict(region=task['region'], split=task['split'], selection_stage='inner_training_only')
        else:
            official = prep['official_protocol']; fold = task['fold']
            from pricefm_r126_contract import training_origins
            frame = core.read_frame(DATA / 'raw/FINAL.csv', runtime.active_regions(spec), official['train_end_market'][fold - 1])
            arrays = core.regional_arrays(runtime, frame, training_origins(official, fold), spec)
            scaled, scaler = runtime.standardize_from_training_origins(arrays, np.arange(len(arrays.response)))
            boundary = official['train_end_market'][fold - 1]
            identity = dict(region=task['region'], fold=fold, selection_stage='official_refit_after_freeze')
        X, y, audit = runtime.teacher_forced_design(scaled, spec)
        folder = output / 'design'; folder.mkdir()
        np.asarray(X, dtype='<f8').tofile(folder / 'X.bin'); np.asarray(y, dtype='<f8').tofile(folder / 'y.bin')
        write(folder / 'scaler.json', scaler)
        write(folder / 'design.json', dict(n=len(y), p=X.shape[1], feature_names=runtime.feature_names(
            spec, runtime.input_names(spec, arrays.exog_names)), **identity,
            response_end_exclusive=boundary, test_opened=False,
            source_specification_sha256=task['specification_sha256'], audit=audit))
        write(folder / 'terminal.json', dict(status='completed_r138_quantile_design', test_opened=False,
            files={name: digest(folder / name) for name in ('X.bin', 'y.bin', 'scaler.json', 'design.json')}))
        runtime.write_stats_packet(output / 'stats', dict(n=len(y), p=X.shape[1], XtX=X.T @ X,
            Xty=X.T @ y, yty=float(y @ y)), dict(**identity, test_opened=False))
        return dict(certified=True, n=len(y), p=X.shape[1], train_only=True)
    if task['kind'] == 'normal_full':
        stats = OUT / 'tasks_done' / task['design_name'] / 'stats'
        contract = normal_contract(prep, dict(task, split=task['fold']), stats, output / 'fit')
        r_run(prep, dep / 'application/scripts/pricefm/442_fit_pricefm_stage_r123_certified_normal.R', contract, task)
        terminal = read(output / 'fit/terminal.json')
        return dict(certified=terminal['full_variational_certified'], fold=task['fold'])
    if task['kind'] in ('al', 'internal_al'):
        design = OUT / 'tasks_done' / task['design_name'] / 'design'
        parent = (Path(task['parent_external']) if task.get('parent_external')
                  else OUT / 'tasks_done' / task['parent_name'] / 'fit')
        adapter = dep / 'application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R'
        manifest = Path(prep['control']['cran_manifest'])
        stage_index = task.get('fold', task.get('split'))
        fixedpoint = ROOT / 'application/R/pricefm_r129_al_fixedpoint_certificate.R'
        contract = dict(stage='R138', model_stage='R138', tag=TAG, family='al', fold=stage_index,
            tau=task['tau'], tau0=task['tau0'],
            output_dir=str(output / 'fit'), design_dir=str(design), parent_dir=str(parent), parent_type=task['parent_type'],
            parent_terminal_sha256=digest(parent / 'terminal.json'),
            cran_library=prep['control']['cran_library'], cran_manifest=str(manifest), cran_manifest_sha256=digest(manifest),
            cran_adapter=str(adapter), cran_adapter_sha256=digest(adapter),
            fixedpoint_helper=str(fixedpoint), fixedpoint_helper_sha256=digest(fixedpoint),
            certificate_limits=p['certificate_limits'], max_rhs_iter=p['max_rhs_iter'],
            design_terminal_sha256=digest(design / 'terminal.json'),
            max_iter=p['al_max_iter'], tol=p['al_tol'], n_samp=p['al_n_samp'], n_samp_xi=p['al_n_samp'],
            seed=runtime.BASE.deterministic_seed(seed, task['region'], stage_index, task['tau'], task['candidate_id']) % (2**31 - 1),
            test_opened=False, prior_center_from_initializer=False,
            posterior_target_sha256=digest(design / 'terminal.json') + f":tau={task['tau']}:tau0={task['tau0']:.17g}")
        r_run(prep, HERE / '472_fit_pricefm_stage_r138_certified_al_300.R', contract, task)
        terminal = read(output / 'fit/terminal.json')
        return dict(certified=terminal['computationally_certified'] and terminal['finite_core'],
            **({'fold': task['fold']} if 'fold' in task else {'split': task['split']}), tau=task['tau'])
    if task['kind'] == 'internal_score':
        normal = runtime.load_normal_fit(parent_rhs(prep, task['driver_candidate_id'], task['split']))
        quantiles = {float(q): runtime.load_quantile_fit(OUT / 'tasks_done' / name / 'fit')
                     for q, name in task['al_names'].items()}
        score = cross_internal_score(runtime, prep, task, normal, quantiles, beat)
        return dict(certified=True, candidate_id=task['candidate_id'], tau0=task['tau0'],
            driver_candidate_id=task['driver_candidate_id'], split=task['split'], **score)
    if task['kind'] == 'forecast':
        from pricefm_r126_contract import official_origins, market_ns
        from pricefm_r138_cross_driver import forecast
        from pricefm_r127_contract import common_metrics
        fold = task['fold']; design = OUT / 'tasks_done' / task['design_name'] / 'design'
        scaler = read(design / 'scaler.json'); official = prep['official_protocol']
        driver_design = OUT / 'tasks_done' / task['driver_design_name'] / 'design'
        driver_scaler = read(driver_design / 'scaler.json')
        origins = official_origins(official, fold)[task['positions']]
        frame = core.read_frame(DATA / 'raw/FINAL.csv', runtime.active_regions(task['spec']),
            official['test_intervals_market'][fold - 1][1])
        arrays = core.regional_arrays(runtime, frame, origins, task['spec'])
        driver_frame = core.read_frame(DATA / 'raw/FINAL.csv', runtime.active_regions(task['driver_spec']),
            official['test_intervals_market'][fold - 1][1])
        driver_arrays = core.regional_arrays(runtime, driver_frame, origins, task['driver_spec'])
        from pricefm_r126_contract import transform
        scaled = transform(arrays, scaler, runtime.ExplicitArrays)
        driver_scaled = transform(driver_arrays, driver_scaler, runtime.ExplicitArrays)
        normal = runtime.load_normal_fit(OUT / 'tasks_done' / task['driver_normal_name'] / 'fit')
        quantiles = {float(q): runtime.load_quantile_fit(OUT / 'tasks_done' / name / 'fit')
                     for q, name in task['al_names'].items()}
        values, audit = forecast(runtime, scaled, task['spec'], scaler,
            driver_scaled, task['driver_spec'], driver_scaler, normal, quantiles, task['positions'],
            runtime.BASE.deterministic_seed(seed, task['region'], fold, 'official'), observe=beat)
        for key in values: values[key] = values[key] * scaler['price_scale'] + scaler['price_mean']
        values['truth'] = arrays.response  # Exact raw prices, not an inverse-rounded copy.
        np.savez_compressed(output / 'predictions.npz', **values,
            anchors_ns=market_ns(origins), positions=np.asarray(task['positions']))
        return dict(certified=True, metrics={key: common_metrics(values['truth'], value)
            for key, value in values.items() if key != 'truth'}, audit=audit, origins=len(origins))
    raise ValueError('unknown task')


def worker(name, cpu):
    prep = read(PREP / 'preparation.json'); runtime = setup(Path(prep['dependency'])); prep = valid()
    os.sched_setaffinity(0, {cpu})
    task = read(OUT / 'tasks' / (name + '.json'))
    output = OUT / 'tasks_done' / name
    if verified(output): return
    # Preserve interrupted evidence, then retry at the canonical task path.
    if output.exists():
        interrupted = OUT / 'interrupted_attempts' / f'{name}.{int(time.time())}.{os.getpid()}'
        interrupted.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(output), interrupted)
    output.mkdir(parents=True)
    beat = lambda value: write(OUT / 'heartbeats' / (name + '.json'), dict(value, epoch=time.time()))
    start = time.time(); beat(dict(status='running', kind=task['kind']))
    result = execute(runtime, prep, task, output, beat)
    write(output / 'result.json', result)
    seal(output, dict(task_sha256=digest(OUT / 'tasks' / (name + '.json')),
        source_head=prep['source']['head'], elapsed_seconds=time.time() - start,
        certified=result.get('certified', True)))


def register(tasks):
    for task in tasks: immutable(OUT / 'tasks' / (task['name'] + '.json'), task)


def outcome(name):
    if name in _OUTCOMES: return _OUTCOMES[name]
    folder = OUT / 'tasks_done' / name
    if (folder / 'completed_evidence.json').is_file() and verified(folder):
        _OUTCOMES[name] = read(folder / 'result.json')
        return _OUTCOMES[name]
    return None


def batch(tasks, cpus, prep, stage):
    register(tasks); pending = [t for t in tasks if outcome(t['name']) is None]
    active = {}; failures = []; resource_error = None
    while pending or active:
        for cpu in cpus:
            if cpu in active or not pending or failures or resource_error: continue
            ready = next((t for t in pending if all(outcome(v) and outcome(v).get('certified', True)
                        for v in t.get('depends', []))), None)
            if ready is None: continue
            allowance = sum(prep['protocol']['task_storage_allowance_GiB'][t['kind']]
                            for _, t, _ in active.values())
            allowance += prep['protocol']['task_storage_allowance_GiB'][ready['kind']]
            try: resources(prep['protocol'], allowance)
            except RuntimeError as error: resource_error = str(error); break
            pending.remove(ready)
            log = OUT / 'worker_logs' / (ready['name'] + '.log'); log.parent.mkdir(exist_ok=True)
            stream = log.open('a')
            proc = subprocess.Popen([sys.executable, '-B', str(ENTRY), 'worker',
                '--name', ready['name'], '--cpu', str(cpu)],
                stdout=stream, stderr=subprocess.STDOUT)
            active[cpu] = (proc, ready, stream)
            write(OUT / 'launched' / (ready['name'] + '.json'), dict(pid=proc.pid, cpu=cpu, epoch=time.time()))
        for cpu, (proc, task, stream) in list(active.items()):
            if proc.poll() is None: continue
            stream.close(); del active[cpu]
            if proc.returncode: failures.append(dict(task=task['name'], returncode=proc.returncode))
        write(OUT / 'progress.json', dict(stage=stage, active=len(active), pending=len(pending),
            completed=sum(outcome(t['name']) is not None for t in tasks), stage_total=len(tasks),
            failures=failures, resource_error=resource_error, cpus=cpus, epoch=time.time()))
        if not active and (pending or failures or resource_error):
            raise RuntimeError('R138 queue withheld dependent work: ' + str((failures, resource_error, [t['name'] for t in pending])))
        if active: time.sleep(3)


def quantile_tasks(prep, receivers, wave):
    tasks = []
    for candidate in receivers:
        base = {key: value for key, value in candidate.items()
                if key not in ('mean_AQL', 'worst_split_AQL', 'split_AQL')}
        tau0 = base['tau0']
        for split in (1, 2, 3):
            stem = f"{wave}_{REGION}_{candidate['candidate_id']}_t{tau0:.12e}_s{split}"
            design = stem + '_design'
            tasks.append(new_task(design, 'internal_design', region=REGION, split=split,
                wave=wave, **base))
            al_names = {}
            for level, parent in ((.5, None), (.45, .5), (.55, .5), (.25, .45),
                                  (.75, .55), (.1, .25), (.9, .75)):
                name = stem + f'_al{level:.2f}'; al_names[str(level)] = name
                if parent is None:
                    dependencies = [design]; parent_name = None
                    external = str(parent_rhs(prep, candidate['candidate_id'], split))
                else:
                    parent_name = al_names[str(parent)]; dependencies = [design, parent_name]; external = None
                tasks.append(new_task(name, 'internal_al', region=REGION, split=split,
                    tau=level, design_name=design, parent_name=parent_name,
                    parent_external=external,
                    parent_type='normal_rhs' if parent is None else 'quantile',
                    depends=dependencies, wave=wave, **base))
            for driver in prep['drivers']:
                score_name = stem + '_driver_' + driver['candidate_id'] + '_score'
                tasks.append(new_task(score_name, 'internal_score', region=REGION, split=split,
                    al_names=al_names, driver_candidate_id=driver['candidate_id'],
                    driver_spec=driver['spec'], driver_specification_sha256=driver['specification_sha256'],
                    depends=list(al_names.values()), wave=wave, **base))
    return tasks


def rank_quantile_pairs(tasks):
    results = [outcome(t['name']) for t in tasks if t['kind'] == 'internal_score']
    return core.rank_groups(results, ['candidate_id', 'tau0', 'driver_candidate_id'])


def frozen_choice(prep, tasks, wave2_ran):
    ranking, excluded = rank_quantile_pairs(tasks)
    if not ranking:
        raise RuntimeError('no complete certified receiver-driver pair')
    winner = ranking[0]
    candidates = prep['receiver_waves']['wave1'] + prep['receiver_waves']['wave2']
    receiver = next(v for v in candidates if v['candidate_id'] == winner['candidate_id'])
    driver = next(v for v in prep['drivers'] if v['candidate_id'] == winner['driver_candidate_id'])
    choice = dict(receiver=receiver, driver=driver, tau0=winner['tau0'], ranking=ranking,
        excluded=excluded, wave2_ran=wave2_ran,
        selected_on='fold1_train_internal_only_three_split_seven_quantile_AL_AQL',
        selected_before_official_test=True)
    immutable(OUT / 'frozen_choice.json', choice)
    return choice


def full_tasks(prep, choice):
    from pricefm_r126_contract import official_origins
    tasks = []; receiver = choice['receiver']; driver = choice['driver']; tau0 = choice['tau0']
    receiver_base = {k: receiver[k] for k in ('candidate_id', 'spec', 'specification_sha256')}
    receiver_base['tau0'] = tau0
    for fold in (1, 2, 3):
        prefix = f'{REGION}_fold{fold}'
        design = prefix + '_receiver_design'; normal = prefix + '_receiver_normal'
        tasks.append(new_task(design, 'design', region=REGION, fold=fold, **receiver_base))
        tasks.append(new_task(normal, 'normal_full', region=REGION, fold=fold,
            design_name=design, depends=[design], **receiver_base))
        if driver['candidate_id'] == receiver['candidate_id'] and np.isclose(driver['tau0'], tau0):
            driver_design = design; driver_normal = normal
        else:
            driver_design = prefix + '_driver_design'; driver_normal = prefix + '_driver_normal'
            driver_base = dict(candidate_id=driver['candidate_id'], spec=driver['spec'],
                specification_sha256=driver['specification_sha256'], tau0=driver['tau0'])
            tasks.append(new_task(driver_design, 'design', region=REGION, fold=fold, **driver_base))
            tasks.append(new_task(driver_normal, 'normal_full', region=REGION, fold=fold,
                design_name=driver_design, depends=[driver_design], **driver_base))
        al_names = {}
        for level, parent in ((.5, None), (.45, .5), (.55, .5), (.25, .45),
                              (.75, .55), (.1, .25), (.9, .75)):
            name = prefix + f'_al{level:.2f}'; al_names[str(level)] = name
            parent_name = normal if parent is None else al_names[str(parent)]
            tasks.append(new_task(name, 'al', region=REGION, fold=fold, tau=level,
                design_name=design, parent_name=parent_name,
                parent_type='normal_rhs' if parent is None else 'quantile',
                depends=[parent_name], **receiver_base))
        n = len(official_origins(prep['official_protocol'], fold))
        size = prep['protocol']['official_chunk_origins']
        for start in range(0, n, size):
            tasks.append(new_task(prefix + f'_forecast{start:03d}', 'forecast', region=REGION,
                fold=fold, positions=list(range(start, min(start + size, n))),
                design_name=design, driver_design_name=driver_design,
                driver_normal_name=driver_normal, driver_candidate_id=driver['candidate_id'],
                driver_spec=driver['spec'], driver_specification_sha256=driver['specification_sha256'],
                al_names=al_names, depends=[*al_names.values(), driver_normal], **receiver_base))
    return tasks


def closeout(prep, tasks):
    from pricefm_r127_contract import common_metrics
    metrics = []
    for fold in (1, 2, 3):
        selected = sorted((t for t in tasks if t['kind'] == 'forecast' and t['fold'] == fold),
                          key=lambda t: t['positions'][0])
        packets = []
        for task in selected:
            with np.load(OUT / 'tasks_done' / task['name'] / 'predictions.npz', allow_pickle=False) as packet:
                packets.append({k: packet[k] for k in packet.files})
        values = {k: np.concatenate([v[k] for v in packets]) for k in packets[0]}
        expected = prep['official_protocol']['test_origin_counts'][fold - 1]
        if not np.array_equal(values['positions'], np.arange(expected)):
            raise RuntimeError('incomplete fold forecast cohort')
        reference = next(r for r in prep['references'] if r['fold'] == fold)
        for key in ('cdf_pool_clipped', 'mean_feature', 'path_specific', 'normal_driver'):
            metrics.append(dict(region=REGION, fold=fold, operator=key,
                **common_metrics(values['truth'], values[key]), **{k: reference[k] for k in
                    ('qdesn_AQL', 'pricefm_AQL', 'operational_pricefm_AQL')}))
    output = OUT / 'closeout'; output.mkdir(exist_ok=True)
    pd.DataFrame(metrics).to_csv(output / 'fold_comparison.csv', index=False)
    pd.DataFrame(metrics).groupby(['region', 'operator'], as_index=False).mean(numeric_only=True).to_csv(
        output / 'region_comparison.csv', index=False)
    choice = read(OUT / 'frozen_choice.json')
    write(output / 'interpretation.json', dict(primary_operator='cdf_pool_clipped',
        authority_replaced=False, all_region_rollout_authorized=False,
        inference='independent_AL_VB_receiver_with_separately_selected_Normal_RHS_VB_driver',
        test_seen_before=True, confirmatory_claim=False,
        selection='three_inner_rolling_splits_then_structurally_diverse_seven_quantile_AL_confirmation',
        receiver_candidate_id=choice['receiver']['candidate_id'],
        driver_candidate_id=choice['driver']['candidate_id'], wave2_ran=choice['wave2_ran'],
        conditions_for_next_decision='review complete DK_1 three-fold result before any wider rollout'))
    seal(output, dict(source=prep['source'], complete_regions=1, complete_folds=3))
    write(OUT / 'terminal.json', dict(status='R138_DK1_COMPLETE_NOT_PROMOTED', regions=1,
        complete_folds=3, official_origin_region_pairs=sum(prep['official_protocol']['test_origin_counts']),
        historical_ridge_reused=640, historical_rhs_structures_reused=30,
        test_used_for_selection=False, authority_replaced=False, source=prep['source']))


def declared_cpus(value, workers):
    if value:
        cpus = [int(item) for item in value.split(',') if item.strip()]
    else:
        cpus = core.physical_cpus(workers)
    if len(cpus) != workers or len(set(cpus)) != workers:
        raise ValueError('declared CPU list must contain exactly one unique CPU per worker')
    allowed = os.sched_getaffinity(0)
    if any(cpu not in allowed for cpu in cpus):
        raise ValueError('declared CPU is outside the controller affinity mask')
    topology = {}
    for line in subprocess.check_output(['lscpu', '-p=CPU,CORE,SOCKET'], text=True).splitlines():
        if line.startswith('#') or not line.strip(): continue
        cpu, core_id, socket_id = map(int, line.split(','))
        topology[cpu] = (socket_id, core_id)
    if any(cpu not in topology for cpu in cpus) or len({topology[cpu] for cpu in cpus}) != workers:
        raise ValueError('declared CPUs must represent distinct physical cores')
    return cpus


def controller(workers, cpu_list=None):
    prep = read(PREP / 'preparation.json'); setup(Path(prep['dependency'])); prep = valid()
    if not 1 <= workers <= prep['protocol']['maximum_workers']:
        raise ValueError('worker cap exceeded')
    with (OUT / 'controller.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for path in Path('/proc').glob('[0-9]*/cmdline'):
            try: command = path.read_bytes().split(b'\0')
            except OSError: continue
            if str(ENTRY).encode() in command and b'worker' in command:
                raise RuntimeError('live own worker detected; do not duplicate interrupted controller')
        verify_hashes(prep['input_sha256']); verify_hashes(prep['bank_sha256'])
        cpus = declared_cpus(cpu_list, workers)
        if not cpus: raise RuntimeError('no idle physical cores')
        resources(prep['protocol'], len(cpus) * prep['protocol']['worker_storage_allowance_GiB'])
        write(OUT / 'controller_identity.json', dict(pid=os.getpid(), host=socket.gethostname(),
            source=prep['source'], cpus=cpus, requested_workers=workers, epoch=time.time()))
        try:
            wave1 = quantile_tasks(prep, prep['receiver_waves']['wave1'], 'wave1')
            batch(wave1, cpus, prep, 'wave1_diverse_receiver_driver_confirmation')
            ranking, excluded = rank_quantile_pairs(wave1)
            if not ranking:
                raise RuntimeError('wave 1 has no complete receiver-driver pair')
            wave2_ran = ranking[0]['mean_AQL'] >= prep['protocol']['r135_internal_AQL']
            immutable(OUT / 'wave1_gate.json', dict(best=ranking[0], excluded=excluded,
                r135_internal_AQL=prep['protocol']['r135_internal_AQL'],
                strict_improvement=not wave2_ran, wave2_required=wave2_ran,
                test_used_for_gate=False, source=prep['source']))
            wave2 = []
            if wave2_ran:
                wave2 = quantile_tasks(prep, prep['receiver_waves']['wave2'], 'wave2')
                batch(wave2, cpus, prep, 'wave2_conditional_diverse_receiver_driver_confirmation')
            selection_tasks = [*wave1, *wave2]
            choice = frozen_choice(prep, selection_tasks, wave2_ran)
            full = full_tasks(prep, choice)
            batch(full, cpus, prep, 'frozen_DK1_full_folds_nested_AL_and_forecast')
            valid(); verify_hashes(prep['input_sha256'])
            if digest(DATA / 'raw/FINAL.csv') != prep['raw_identity']['sha256']:
                raise RuntimeError('raw source content changed before closeout')
            for task in [*selection_tasks, *full]:
                if not verified(OUT / 'tasks_done' / task['name']):
                    raise RuntimeError('unsealed completed task: ' + task['name'])
            closeout(prep, full)
        except Exception as error:
            write(OUT / 'blocked.json', dict(error=str(error), epoch=time.time(), source=prep['source'],
                no_automatic_budget_change=True, existing_evidence_preserved=True))
            raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'controller', 'worker'))
    parser.add_argument('--dependency', type=Path); parser.add_argument('--release', type=Path)
    parser.add_argument('--reference', type=Path)
    parser.add_argument('--workers', type=int, default=30); parser.add_argument('--cpus')
    parser.add_argument('--name'); parser.add_argument('--cpu', type=int)
    args = parser.parse_args()
    if args.action == 'prepare': print(prepare(args.dependency, args.release, args.reference), flush=True)
    else:
        prep = __import__('json').loads((PREP / 'preparation.json').read_text())
        setup(Path(prep['dependency']))
        if args.action == 'controller': controller(args.workers, args.cpus)
        else: worker(args.name, args.cpu)
