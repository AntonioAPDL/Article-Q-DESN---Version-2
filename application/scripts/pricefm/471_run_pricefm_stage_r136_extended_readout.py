#!/usr/bin/env python3
"""R136: training-only extended-readout optimization and frozen evaluation."""
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
import pricefm_r136_core as core

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
TAG = 'pricefm_stage_r136_extended_readout_20261013'
PARENT_TAG = 'pricefm_stage_r134_pure_qdesn_optimization_20261011'
OUT = DATA / 'campaigns' / TAG
PREP = DATA / 'launch_prep' / TAG
PROTOCOL = ROOT / 'application/config' / (TAG + '.json')
ENTRY = Path(__file__).resolve()
_OUTCOMES = {}


def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()


def source_identity():
    branch = git(ROOT, 'branch', '--show-current')
    if not branch.startswith('work/pricefm-r136-') or git(ROOT, 'status', '--porcelain'):
        raise RuntimeError('clean committed dedicated R136 source required')
    return dict(branch=branch, head=git(ROOT, 'rev-parse', 'HEAD'))


def setup(dependency):
    runtime = core.dependencies(dependency)
    global read, write, immutable, digest, seal, verified, verify_hashes
    from pricefm_r126_contract import read, write, immutable, digest, seal, verified, verify_hashes
    return runtime


def validate_protocol(p):
    if (p['tag'] != TAG or p['regions'] != ['BG', 'HR', 'DK_1'] or p['paths'] != 500
            or p['maximum_workers'] != 30 or p['folds'] != [1, 2, 3]
            or p['quantiles'] != [.1, .25, .45, .5, .55, .75, .9]):
        raise ValueError('declared R136 geometry differs')
    if (p['broad_candidate_draws'] < p['broad_candidates_per_region']
            or p['broad_candidates_per_region'] < 128
            or p['rhs_shortlist_structures'] > 12
            or p['quantile_finalists'] != 1
            or p['maximum_rhs_readout_dimension'] > p['maximum_ridge_readout_dimension']):
        raise ValueError('R136 screening budget is outside its audited bounds')
    for key in ('mcmc_authorized', 'joint_authorized', 'exal_authorized',
                'registry_mutation_authorized', 'article_mutation_authorized',
                'promotion_authorized', 'all_region_launch_authorized', 'priors_from_initializers'):
        if p[key] is not False: raise ValueError('forbidden authority/model expansion: ' + key)


def resources(p, allowance=0):
    mem = {s.split(':')[0]: int(s.split()[1]) for s in Path('/proc/meminfo').read_text().splitlines()}
    stat = os.statvfs(DATA)
    available = stat.f_bavail * stat.f_frsize / 2**30
    used = sum(v.stat().st_size for v in OUT.rglob('*') if v.is_file()) / 2**30
    if (mem['MemAvailable'] / 2**20 < p['minimum_free_memory_GiB']
            or available < p['minimum_free_disk_GiB'] + allowance
            or used + allowance > p['maximum_output_GiB']):
        raise RuntimeError('resource reserve reached; pending work preserved, own active work drains')
    return dict(available_memory_GiB=mem['MemAvailable'] / 2**20,
                free_disk_GiB=available, campaign_output_GiB=used)


def new_task(name, kind, **values):
    return dict(name=name, kind=kind, **values)


def prepare(dependency, release, reference=None):
    runtime = setup(dependency); p = read(PROTOCOL); validate_protocol(p)
    identity = source_identity()
    if reference is not None:
        raise ValueError('R136 references are frozen by the R134 preparation; overrides are forbidden')
    if git(dependency, 'rev-parse', 'HEAD') != p['dependency_head'] or git(dependency, 'status', '--porcelain'):
        raise RuntimeError('frozen dependency worktree differs')
    receipt = read(release)
    if receipt['source'] != identity or not receipt['passed']:
        raise RuntimeError('source-matched launch-prep release required')
    if (PREP / 'preparation.json').is_file():
        prior = read(PREP / 'preparation.json')
        if (prior['source'] != identity or prior['dependency_head'] != p['dependency_head']
                or prior['protocol'] != p):
            raise RuntimeError('existing R136 preparation belongs to a different immutable source')
        verify_hashes(prior['source_sha256']); verify_hashes(prior['input_sha256'])
        verify_hashes(prior['bank_sha256'])
        return dict(status='R136_ALREADY_PREPARED', first_stage_tasks=len(prior['tasks']),
            regional_candidates={r: len(v['candidates']) for r, v in prior['regional'].items()},
            all_region_launch=False, test_used_for_selection=False)
    resources(p, p['maximum_workers'] * p['worker_storage_allowance_GiB'])
    dep_here = dependency / 'application/scripts/pricefm'
    parent = DATA / 'campaigns' / PARENT_TAG
    parent_prep_path = DATA / 'launch_prep' / PARENT_TAG / 'preparation.json'
    ridge_path = parent / 'ridge_closeout.json'; rhs_path = parent / 'rhs_closeout.json'
    parent_prep = read(parent_prep_path); ridge = read(ridge_path); rhs = read(rhs_path)
    if (parent_prep['source']['head'] != p['parent_source_head']
            or parent_prep['protocol']['tag'] != PARENT_TAG):
        raise RuntimeError('R136 parent preparation identity differs')
    if set(ridge) != set(p['regions']) or set(rhs) != set(p['regions']):
        raise RuntimeError('R136 requires complete R134 regional closeouts')
    official = parent_prep['official_protocol']; control = parent_prep['control']
    if digest(DATA / 'raw/FINAL.csv') != official['raw_sha256']:
        raise RuntimeError('raw source changed')
    ledger = {str(path): digest(path) for path in (
        parent_prep_path, ridge_path, rhs_path, Path(control['cran_manifest']))}
    regional = {}; tasks = []; design_audit = {}; bank_ledger = {}
    for region in p['regions']:
        exogenous_dimensions = {}
        for feature in p['feature_policies']:
            path = parent / 'training_banks' / region / (feature + '.npz')
            expected = parent_prep['bank_sha256'].get(str(path))
            if expected is None or digest(path) != expected:
                raise RuntimeError('R134 training bank is missing or changed: ' + str(path))
            bank_ledger[str(path)] = expected
            with np.load(path, allow_pickle=False) as packet:
                exogenous_dimensions[feature] = len(packet['exog_names'])
        proposed, protected, generation = core.targeted_extended_candidates(
            runtime, parent_prep['regional'][region]['candidates'], ridge[region]['ranking'],
            rhs[region]['finalists'], region, exogenous_dimensions, p['parent_seed_structures'],
            p['broad_candidate_draws'], p['broad_candidates_per_region'],
            p['candidate_seed'] + p['regions'].index(region), p['maximum_ridge_readout_dimension'])
        admissible = []
        for candidate in proposed:
            spec = candidate['spec']; channels = exogenous_dimensions[spec['feature_policy']]
            dimension = core.input_dimension(spec, channels)
            mandatory = runtime.mandatory_rows(spec, dimension)
            if spec['input_fan_in'] > dimension or len(mandatory) > spec['units'][0]:
                continue
            admissible.append(candidate)
        controls = [row for row in admissible if row['candidate_id'] in protected]
        local = [row for row in admissible if row['candidate_id'] not in protected]
        variants = controls + local[:max(0, p['broad_candidates_per_region'] - len(controls))]
        if len(variants) < p['broad_candidates_per_region'] or not set(protected).issubset(
                {row['candidate_id'] for row in variants}):
            raise RuntimeError('admissible R136 design lost breadth or a paired parent control')
        parent_rhs_ids = {row['candidate_id'] for row in rhs[region]['finalists']}
        mandatory_rhs_controls = [row['candidate_id'] for row in variants
            if row.get('parent_candidate_id') in parent_rhs_ids
            and row['readout_dimension'] <= p['maximum_rhs_readout_dimension']]
        if not mandatory_rhs_controls:
            raise RuntimeError('R136 lost the dimension-admissible paired R134 RHS control')
        regional[region] = dict(candidates=variants, protected_candidates=protected,
            mandatory_rhs_controls=mandatory_rhs_controls)
        design_audit[region] = dict(generation=generation, proposed=len(proposed),
            admissible=len(admissible), retained=len(variants), controls=len(controls),
            rhs_dimension_eligible=sum(row['readout_dimension'] <= p['maximum_rhs_readout_dimension']
                                       for row in variants),
            readout_dimension=dict(min=min(row['readout_dimension'] for row in variants),
                median=float(np.median([row['readout_dimension'] for row in variants])),
                max=max(row['readout_dimension'] for row in variants)),
            factor_counts={name: pd.Series([str(row['spec'][name]) for row in variants]).value_counts().to_dict()
                for name in ('m_y', 'm_x', 'depth', 'feature_policy', 'input_policy', 'alpha', 'rho',
                             'input_scale', 'input_fan_in', 'recurrent_sparsity', 'interlayer_gain')})
        tasks += [new_task(region + '_' + row['candidate_id'], 'ridge', region=region, **row)
                  for row in variants]
    source_paths = list(HERE.glob('*r136*')) + [PROTOCOL,
        ROOT / 'application/tests/test_pricefm_stage_r136_extended_readout.py',
        ROOT / 'application/R/pricefm_r129_al_fixedpoint_certificate.R']
    source_paths += list(dep_here.glob('*.py')) + list(dep_here.glob('*.R'))
    source_paths += [dependency / 'application/R/pricefm_recursive_normal_fit.R']
    runtime_path = Path(control['normal_runtime'])
    source_paths += list((runtime_path / 'R').glob('*.R'))
    source_paths += list((Path(control['cran_library']) / 'exdqlm/R').glob('*'))
    sources = {str(path): digest(path) for path in source_paths if path.is_file()}
    references = parent_prep['references']
    if len(references) != 9 or any(any(value is None for value in row.values()) for row in references):
        raise RuntimeError('complete matching references required')
    prep = dict(source=identity, dependency=str(dependency), dependency_head=p['dependency_head'],
        protocol=p, official_protocol=official, template=parent_prep['template'], control=control,
        regional=regional, tasks=tasks, references=references, design_audit=design_audit,
        source_sha256=sources, input_sha256=ledger, bank_sha256=bank_ledger,
        release_path=str(release), release_sha256=digest(release),
        parent_source=parent_prep['source'], parent_training_rankings_used_for_candidate_design=True,
        historical_fits_used_for_direct_R136_selection=0, test_used_for_selection=False,
        official_development_test_seen_previously=True,
        raw_identity=dict(bytes=(DATA / 'raw/FINAL.csv').stat().st_size,
            mtime_ns=(DATA / 'raw/FINAL.csv').stat().st_mtime_ns,
            sha256=official['raw_sha256']))
    immutable(PREP / 'preparation.json', prep)
    return dict(status='R136_PREPARED', first_stage_tasks=len(tasks),
        historical_fits_used_for_direct_R136_selection=0,
        regional_candidates={r: len(v['candidates']) for r, v in regional.items()},
        all_region_launch=False, test_used_for_selection=False)


def valid():
    prep = read(PREP / 'preparation.json')
    if source_identity() != prep['source']: raise RuntimeError('executed R136 source changed')
    if git(prep['dependency'], 'rev-parse', 'HEAD') != prep['dependency_head']:
        raise RuntimeError('frozen dependency changed')
    verify_hashes(prep['source_sha256'])
    raw = (DATA / 'raw/FINAL.csv').stat()
    if (raw.st_size, raw.st_mtime_ns) != (prep['raw_identity']['bytes'], prep['raw_identity']['mtime_ns']):
        raise RuntimeError('raw source metadata changed; full content re-audit required')
    if digest(prep['release_path']) != prep['release_sha256']: raise RuntimeError('release changed')
    return prep


def bank(runtime, prep, task):
    path = DATA / 'campaigns' / PARENT_TAG / 'training_banks' / task['region'] / (
        task['spec']['feature_policy'] + '.npz')
    if digest(path) != prep['bank_sha256'][str(path)]: raise RuntimeError('train-only bank changed')
    return core.load_arrays(runtime, path)


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
    from pricefm_r126_fullfold import run_r
    path = OUT / 'contracts' / (task['name'] + '.json'); immutable(path, contract)
    log = OUT / 'fit_logs' / (task['name'] + '.log')
    run_r(entry, '--config' if task['kind'] in ('al', 'internal_al') else '--contract', path, log)


def execute(runtime, prep, task, output, beat):
    p = prep['protocol']; dep = Path(prep['dependency']); seed = p['forecast_seed']
    if task['kind'] == 'ridge':
        arrays = bank(runtime, prep, task); records = []
        for split in (1, 2, 3):
            scaled, scaler, cell = scaled_internal(runtime, arrays, split)
            stats, audit = runtime.teacher_forced_statistics(scaled, task['spec'], {'train': cell['train']})
            fit = runtime.fit_scaled_ridge(stats['train'])
            result = scale_metrics(core.ridge_internal_score(runtime, scaled, task['spec'], fit, cell,
                p['ridge_origins_per_clock']), scaler)
            records.append(dict(candidate_id=task['candidate_id'], split=split, certified=True, **result))
        return dict(region=task['region'], candidate_id=task['candidate_id'], records=records,
            units='EUR/MWh', heavy_statistics_retained=False)
    if task['kind'] == 'stats':
        arrays = bank(runtime, prep, task)
        scaled, scaler, cell = scaled_internal(runtime, arrays, task['split'])
        stats, audit = runtime.teacher_forced_statistics(scaled, task['spec'], {'train': cell['train']})
        runtime.write_stats_packet(output / 'stats', stats['train'], dict(region=task['region'],
            candidate_id=task['candidate_id'], split=task['split'], test_opened=False))
        write(output / 'scaler.json', scaler)
        return dict(certified=True, split=task['split'], n=stats['train']['n'], p=stats['train']['p'],
            train_only=True, audit=audit)
    if task['kind'] == 'rhs':
        stats = OUT / 'tasks_done' / task['stats_name'] / 'stats'
        contract = normal_contract(prep, task, stats, output / 'fit')
        r_run(prep, dep / 'application/scripts/pricefm/442_fit_pricefm_stage_r123_certified_normal.R', contract, task)
        terminal = read(output / 'fit/terminal.json')
        result = dict(candidate_id=task['candidate_id'], tau0=task['tau0'], split=task['split'],
                      certified=terminal['full_variational_certified'])
        if result['certified']:
            arrays = bank(runtime, prep, task); scaled, scaler, cell = scaled_internal(runtime, arrays, task['split'])
            fit = runtime.load_normal_fit(output / 'fit')
            result.update(scale_metrics(core.internal_score(runtime, scaled, task['spec'], fit, cell,
                p['rhs_origins_per_clock'], runtime.BASE.deterministic_seed(seed, task['region'], task['split']),
                observe=beat, paths=p['rhs_screen_paths']), scaler))
        return result
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
        write(folder / 'terminal.json', dict(status='completed_r136_quantile_design', test_opened=False,
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
        parent = OUT / 'tasks_done' / task['parent_name'] / 'fit'
        adapter = dep / 'application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R'
        manifest = Path(prep['control']['cran_manifest'])
        stage_index = task.get('fold', task.get('split'))
        helper = ROOT / 'application/R/pricefm_r129_al_fixedpoint_certificate.R'
        contract = dict(stage='R136', tag=TAG, family='al', fold=stage_index, tau=task['tau'], tau0=task['tau0'],
            output_dir=str(output / 'fit'), design_dir=str(design), parent_dir=str(parent), parent_type=task['parent_type'],
            parent_terminal_sha256=digest(parent / 'terminal.json'),
            cran_library=prep['control']['cran_library'], cran_manifest=str(manifest), cran_manifest_sha256=digest(manifest),
            cran_adapter=str(adapter), cran_adapter_sha256=digest(adapter), design_terminal_sha256=digest(design / 'terminal.json'),
            max_iter=p['al_max_iter'], tol=p['al_tol'], n_samp=p['al_n_samp'], n_samp_xi=p['al_n_samp'],
            max_rhs_iter=p['max_rhs_iter'], certificate_limits=p['certificate_limits'],
            fixedpoint_helper=str(helper), fixedpoint_helper_sha256=digest(helper),
            seed=runtime.BASE.deterministic_seed(seed, task['region'], stage_index, task['tau'], task['candidate_id']) % (2**31 - 1),
            test_opened=False, prior_center_from_initializer=False,
            posterior_target_sha256=digest(design / 'terminal.json') + f":tau={task['tau']}:tau0={task['tau0']:.17g}")
        r_run(prep, HERE / '470_fit_pricefm_stage_r136_certified_al.R', contract, task)
        terminal = read(output / 'fit/terminal.json')
        return dict(certified=terminal['computationally_certified'],
            **({'fold': task['fold']} if 'fold' in task else {'split': task['split']}), tau=task['tau'])
    if task['kind'] == 'internal_score':
        arrays = bank(runtime, prep, task)
        scaled, scaler, cell = scaled_internal(runtime, arrays, task['split'])
        normal = runtime.load_normal_fit(OUT / 'tasks_done' / task['rhs_name'] / 'fit')
        quantiles = {float(q): runtime.load_quantile_fit(OUT / 'tasks_done' / name / 'fit')
                     for q, name in task['al_names'].items()}
        score = core.quantile_internal_score(runtime, scaled, task['spec'], normal, quantiles, cell,
            p['quantile_origins_per_clock'], runtime.BASE.deterministic_seed(
                seed, task['region'], task['candidate_id'], task['tau0'], task['split']), observe=beat)
        return dict(certified=True, candidate_id=task['candidate_id'], tau0=task['tau0'],
            split=task['split'], **scale_metrics(score, scaler))
    if task['kind'] == 'forecast':
        from pricefm_r126_contract import official_origins, market_ns
        from pricefm_r126_replay import forecast
        from pricefm_r127_contract import common_metrics
        fold = task['fold']; design = OUT / 'tasks_done' / task['design_name'] / 'design'
        scaler = read(design / 'scaler.json'); official = prep['official_protocol']
        origins = official_origins(official, fold)[task['positions']]
        frame = core.read_frame(DATA / 'raw/FINAL.csv', runtime.active_regions(task['spec']),
            official['test_intervals_market'][fold - 1][1])
        arrays = core.regional_arrays(runtime, frame, origins, task['spec'])
        from pricefm_r126_contract import transform
        scaled = transform(arrays, scaler, runtime.ExplicitArrays)
        normal = runtime.load_normal_fit(OUT / 'tasks_done' / task['normal_name'] / 'fit')
        quantiles = {float(q): runtime.load_quantile_fit(OUT / 'tasks_done' / name / 'fit')
                     for q, name in task['al_names'].items()}
        values, audit = forecast(runtime, scaled, task['spec'], normal, quantiles, task['positions'],
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
            proc = subprocess.Popen([sys.executable, '-B', str(ENTRY), 'worker', '--name', ready['name'], '--cpu', str(cpu)],
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
            raise RuntimeError('R136 queue withheld dependent work: ' + str((failures, resource_error, [t['name'] for t in pending])))
        if active: time.sleep(3)


def rhs_tasks(prep):
    tasks = []; p = prep['protocol']; ranks = {}
    for region, values in prep['regional'].items():
        records = [r for t in prep['tasks'] if t['kind'] == 'ridge' and t['region'] == region
                   for r in outcome(t['name'])['records']]
        ranking, excluded = core.rank_groups(records, ['candidate_id'])
        candidate_by_id = {row['candidate_id']: row for row in values['candidates']}
        eligible = [row for row in ranking if candidate_by_id[row['candidate_id']]['readout_dimension']
                    <= p['maximum_rhs_readout_dimension']]
        dimension_excluded = [dict(candidate_id=row['candidate_id'],
            readout_dimension=candidate_by_id[row['candidate_id']]['readout_dimension'],
            reason='above_declared_RHS_and_quantile_dimension_cap') for row in ranking
            if candidate_by_id[row['candidate_id']]['readout_dimension'] > p['maximum_rhs_readout_dimension']]
        selected = [row['candidate_id'] for row in eligible[:p['rhs_shortlist_structures']]]
        for protected in values['mandatory_rhs_controls']:
            if protected not in selected: selected.append(protected)
        if len(selected) < p['rhs_shortlist_structures']:
            raise RuntimeError('too few dimension-admissible R136 RHS candidates for ' + region)
        ranks[region] = dict(ranking=ranking, excluded=excluded,
            dimension_excluded=dimension_excluded, shortlist=selected,
            maximum_rhs_readout_dimension=p['maximum_rhs_readout_dimension'])
        for candidate in values['candidates']:
            if candidate['candidate_id'] not in selected: continue
            p_dim = candidate['readout_dimension']
            center = core.tau_center(p_dim, 506 * 96)
            taus = [center * m for m in p['tau_multipliers']]
            for split in (1, 2, 3):
                stats_name = f"stats_{region}_{candidate['candidate_id']}_s{split}"
                tasks.append(new_task(stats_name, 'stats', region=region, split=split,
                    depends=[region + '_' + candidate['candidate_id']], **candidate))
            for tau0 in sorted(set(taus)):
                for split in (1, 2, 3):
                    name = f"rhs_{region}_{candidate['candidate_id']}_s{split}_t{tau0:.12e}"
                    tasks.append(new_task(name, 'rhs', region=region, split=split, tau0=tau0,
                        stats_name=f"stats_{region}_{candidate['candidate_id']}_s{split}",
                        depends=[f"stats_{region}_{candidate['candidate_id']}_s{split}"], **candidate))
    immutable(OUT / 'ridge_closeout.json', ranks)
    return tasks


def quantile_tasks(prep, rhs):
    tasks = []; finalists = {}; p = prep['protocol']
    for region in p['regions']:
        fits = [t for t in rhs if t['kind'] == 'rhs' and t['region'] == region]
        results = [outcome(t['name']) for t in fits]
        ranking, excluded = core.rank_groups(results, ['candidate_id', 'tau0'])
        if len(ranking) < p['quantile_finalists']:
            raise RuntimeError('too few certified RHS finalists for ' + region)
        selected = ranking[:p['quantile_finalists']]
        finalists[region] = dict(ranking=ranking, excluded=excluded, finalists=selected)
        for selected_fit in selected:
            candidate = next(v for v in prep['regional'][region]['candidates']
                if v['candidate_id'] == selected_fit['candidate_id'])
            tau0 = selected_fit['tau0']
            for split in (1, 2, 3):
                stem = f"iq_{region}_{candidate['candidate_id']}_t{tau0:.12e}_s{split}"
                design = stem + '_design'
                rhs_name = next(t['name'] for t in fits if t['candidate_id'] == candidate['candidate_id']
                    and t['split'] == split and np.isclose(t['tau0'], tau0, rtol=1e-12, atol=0))
                tasks.append(new_task(design, 'internal_design', region=region, split=split,
                    depends=[rhs_name], tau0=tau0, **candidate))
                al_names = {}
                for level, parent in ((.5, None), (.45, .5), (.55, .5), (.25, .45),
                                      (.75, .55), (.1, .25), (.9, .75)):
                    name = stem + f'_al{level:.2f}'; al_names[str(level)] = name
                    parent_name = rhs_name if parent is None else al_names[str(parent)]
                    tasks.append(new_task(name, 'internal_al', region=region, split=split, tau=level,
                        tau0=tau0, design_name=design, parent_name=parent_name,
                        parent_type='normal_rhs' if parent is None else 'quantile',
                        depends=[design, parent_name], **candidate))
                tasks.append(new_task(stem + '_score', 'internal_score', region=region, split=split,
                    tau0=tau0, rhs_name=rhs_name, al_names=al_names,
                    depends=list(al_names.values()), **candidate))
    immutable(OUT / 'rhs_closeout.json', finalists)
    return tasks


def frozen_choices(prep, tasks):
    choices = {}
    for region in prep['protocol']['regions']:
        results = [outcome(t['name']) for t in tasks if t['kind'] == 'internal_score' and t['region'] == region]
        ranking, excluded = core.rank_groups(results, ['candidate_id', 'tau0'])
        if not ranking: raise RuntimeError('no complete certified seven-quantile finalist for ' + region)
        winner = ranking[0]; candidate = next(v for v in prep['regional'][region]['candidates']
                                              if v['candidate_id'] == winner['candidate_id'])
        choices[region] = dict(candidate, tau0=winner['tau0'], ranking=ranking, excluded=excluded,
            selected_on='fold1_train_internal_only_seven_quantile_AL_AQL', selected_before_test=True)
    immutable(OUT / 'frozen_choices.json', choices)
    return choices


def full_tasks(prep, choices):
    from pricefm_r126_contract import official_origins
    tasks = []
    for region, choice in choices.items():
        base = {k: choice[k] for k in ('candidate_id', 'spec', 'specification_sha256', 'tau0')}
        for fold in (1, 2, 3):
            prefix = f'{region}_fold{fold}'; design = prefix + '_design'; normal = prefix + '_normal'
            tasks.append(new_task(design, 'design', region=region, fold=fold, **base))
            tasks.append(new_task(normal, 'normal_full', region=region, fold=fold, design_name=design, depends=[design], **base))
            al_names = {}
            for tau, parent in ((.5, None), (.45, .5), (.55, .5), (.25, .45), (.75, .55), (.1, .25), (.9, .75)):
                name = prefix + f'_al{tau:.2f}'; al_names[str(tau)] = name
                parent_name = normal if parent is None else al_names[str(parent)]
                tasks.append(new_task(name, 'al', region=region, fold=fold, tau=tau, design_name=design,
                    parent_name=parent_name, parent_type='normal_rhs' if parent is None else 'quantile', depends=[parent_name], **base))
            n = len(official_origins(prep['official_protocol'], fold)); size = prep['protocol']['official_chunk_origins']
            for start in range(0, n, size):
                tasks.append(new_task(prefix + f'_forecast{start:03d}', 'forecast', region=region, fold=fold,
                    positions=list(range(start, min(start + size, n))), design_name=design, normal_name=normal,
                    al_names=al_names, depends=list(al_names.values()), **base))
    return tasks


def closeout(prep, tasks):
    from pricefm_r127_contract import common_metrics
    metrics = []
    for region in prep['protocol']['regions']:
        for fold in (1, 2, 3):
            selected = sorted((t for t in tasks if t['kind'] == 'forecast' and t['region'] == region and t['fold'] == fold),
                              key=lambda t: t['positions'][0])
            packets = []
            for task in selected:
                with np.load(OUT / 'tasks_done' / task['name'] / 'predictions.npz', allow_pickle=False) as packet:
                    packets.append({k: packet[k] for k in packet.files})
            values = {k: np.concatenate([v[k] for v in packets]) for k in packets[0]}
            expected = prep['official_protocol']['test_origin_counts'][fold - 1]
            if not np.array_equal(values['positions'], np.arange(expected)): raise RuntimeError('incomplete fold forecast cohort')
            reference = next(r for r in prep['references'] if r['region'] == region and r['fold'] == fold)
            for key in ('cdf_pool_clipped', 'mean_feature', 'path_specific', 'normal_driver'):
                metrics.append(dict(region=region, fold=fold, operator=key,
                    **common_metrics(values['truth'], values[key]), **{k: reference[k] for k in
                        ('qdesn_AQL', 'pricefm_AQL', 'operational_pricefm_AQL')}))
    output = OUT / 'closeout'; output.mkdir(exist_ok=True)
    pd.DataFrame(metrics).to_csv(output / 'fold_comparison.csv', index=False)
    pd.DataFrame(metrics).groupby(['region', 'operator'], as_index=False).mean(numeric_only=True).to_csv(
        output / 'region_comparison.csv', index=False)
    write(output / 'interpretation.json', dict(primary_operator='cdf_pool_clipped',
        authority_replaced=False, all_region_rollout_authorized=False,
        inference='independent_AL_VB_with_stochastic_Normal_RHS_VB_driver_not_MCMC_or_joint',
        readout='intercept_plus_full_explicit_input_plus_all_reservoir_layers',
        test_seen_before=True, confirmatory_claim=False,
        old_R98_exAL_vs_new_AL_difference_deliberate=True,
        selection='three_inner_rolling_splits_then_seven_quantile_AL_finalist_confirmation',
        conditions_for_next_decision='compare_complete_three-region three-fold cohort before any wider rollout'))
    regions = len(prep['protocol']['regions'])
    seal(output, dict(source=prep['source'], complete_regions=regions, complete_folds=3 * regions))
    write(OUT / 'terminal.json', dict(status='R136_COMPLETE_NOT_PROMOTED', regions=regions,
        full_fits=8 * 3 * regions,
        official_origin_region_pairs=sum(prep['official_protocol']['test_origin_counts']) * regions,
        historical_fits_used_for_direct_R136_selection=0,
        parent_training_rankings_used_for_candidate_design=True,
        test_used_for_selection=False, source=prep['source']))


def controller(workers):
    OUT.mkdir(parents=True, exist_ok=True)
    prep = read(PREP / 'preparation.json'); setup(Path(prep['dependency'])); prep = valid()
    if not 1 <= workers <= 30: raise ValueError('combined worker cap 30')
    if os.getenv(prep['protocol']['launch_approval_environment']) != 'true':
        raise RuntimeError('explicit R136 launch approval environment is required')
    with (OUT / 'controller.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for path in Path('/proc').glob('[0-9]*/cmdline'):
            try: command = path.read_bytes().split(b'\0')
            except OSError: continue
            if str(ENTRY).encode() in command and b'worker' in command:
                raise RuntimeError('live own worker detected; do not duplicate interrupted controller')
        verify_hashes(prep['input_sha256']); verify_hashes(prep['bank_sha256'])
        cpus = core.physical_cpus(workers)
        if not cpus: raise RuntimeError('no idle physical cores')
        resources(prep['protocol'], len(cpus) * prep['protocol']['worker_storage_allowance_GiB'])
        write(OUT / 'controller_identity.json', dict(pid=os.getpid(), host=socket.gethostname(),
            source=prep['source'], cpus=cpus, requested_workers=workers, epoch=time.time()))
        try:
            initial = prep['tasks']
            smoke = [next(t for t in initial if t['region'] == r) for r in prep['protocol']['regions']]
            batch(smoke, cpus[:len(smoke)], prep, 'compact_ridge_smoke_gate')
            immutable(OUT / 'smoke_gate.json', dict(passed=True, tasks=[t['name'] for t in smoke], source=prep['source']))
            batch(initial, cpus, prep, 'targeted_extended_readout_Ridge_screen')
            rhs = rhs_tasks(prep); batch(rhs, cpus, prep, 'dimension_bounded_extended_Normal_RHS')
            quantile = quantile_tasks(prep, rhs)
            batch(quantile, cpus, prep, 'training_only_seven_quantile_AL_finalists')
            choices = frozen_choices(prep, quantile)
            full = full_tasks(prep, choices); batch(full, cpus, prep, 'full_folds_nested_AL_and_forecast')
            valid(); verify_hashes(prep['input_sha256'])
            if digest(DATA / 'raw/FINAL.csv') != prep['raw_identity']['sha256']:
                raise RuntimeError('raw source content changed before closeout')
            for task in [*initial, *rhs, *quantile, *full]: verified(OUT / 'tasks_done' / task['name'])
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
    parser.add_argument('--workers', type=int, default=30); parser.add_argument('--name'); parser.add_argument('--cpu', type=int)
    args = parser.parse_args()
    if args.action == 'prepare': print(prepare(args.dependency, args.release, args.reference), flush=True)
    else:
        prep = __import__('json').loads((PREP / 'preparation.json').read_text())
        setup(Path(prep['dependency']))
        if args.action == 'controller': controller(args.workers)
        else: worker(args.name, args.cpu)
