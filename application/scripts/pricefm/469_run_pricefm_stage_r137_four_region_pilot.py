#!/usr/bin/env python3
"""R137: isolated R135-style pure-QDESN optimization for one declared region."""
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
BASE_TAG = 'pricefm_stage_r137_four_region_pilot_20261015'
ALLOWED_REGIONS = ('SK', 'HU', 'IT_NORD', 'EE')
REGION = os.environ.get('PRICEFM_R137_REGION', '')
if REGION not in ALLOWED_REGIONS:
    raise RuntimeError('PRICEFM_R137_REGION must be one of ' + ','.join(ALLOWED_REGIONS))
TAG = BASE_TAG + '__' + REGION
OUT = DATA / 'campaigns' / TAG
PREP = DATA / 'launch_prep' / TAG
PROTOCOL = ROOT / 'application/config/pricefm_stage_r137_four_region_pilot_20261015.json'
ENTRY = Path(__file__).resolve()
_OUTCOMES = {}
RSCRIPT = Path('/data/jaguir26/local/opt/R/4.6.0/bin/Rscript')
R_LIBRARY_DIR = Path('/data/jaguir26/local/opt/R/4.6.0/lib64/R/lib')


def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()


def source_identity():
    branch = git(ROOT, 'branch', '--show-current')
    if not branch.startswith('work/pricefm-r137-') or git(ROOT, 'status', '--porcelain'):
        raise RuntimeError('clean committed dedicated R137 source required')
    return dict(branch=branch, head=git(ROOT, 'rev-parse', 'HEAD'))


def setup(dependency):
    runtime = core.dependencies(dependency)
    global read, write, immutable, digest, seal, verified, verify_hashes
    from pricefm_r126_contract import read, write, immutable, digest, seal, verified, verify_hashes
    return runtime


def validate_protocol(p):
    if (p['tag'] != BASE_TAG or p['regions'] != list(ALLOWED_REGIONS) or p['paths'] != 500
            or p['maximum_workers_per_region'] != 15 or p['folds'] != [1, 2, 3]
            or p['quantiles'] != [.1, .25, .45, .5, .55, .75, .9]):
        raise ValueError('declared R137 geometry differs')
    if p['al_max_iter'] != 300 or p['minimum_free_disk_GiB'] > 20:
        raise ValueError('R137 requires the declared 300-iteration budget and no campaign-size cap')
    if (p['broad_candidate_draws'] < p['broad_candidates_per_region']
            or p['broad_candidates_per_region'] < 512
            or p['rhs_shortlist_structures'] > 30
            or p['quantile_finalists'] > 3):
        raise ValueError('R137 screening budget is outside its audited bounds')
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
            or available < p['minimum_free_disk_GiB'] + allowance):
        raise RuntimeError('resource reserve reached; pending work preserved, own active work drains')
    return dict(available_memory_GiB=mem['MemAvailable'] / 2**20,
                free_disk_GiB=available, campaign_output_GiB=used)


def new_task(name, kind, **values):
    return dict(name=name, kind=kind, **values)


def add_r135_basin_controls(runtime, proposed, protected, region, protocol):
    """Add the exact successful R135 basin as controls, never as presumed winners."""
    values = protocol['r135_common_basin']
    candidates = {v['specification_sha256']: dict(v) for v in proposed}
    protected = set(protected)
    for feature_policy in ('target_only', 'graph_summary_mean_std'):
        for input_policy in ('coverage', 'balanced'):
            spec = runtime.normalize_spec(dict(
                region=region,
                depth=len(values['units']),
                units=values['units'],
                m_y=values['m_y'],
                m_x=values['m_x'],
                feature_policy=feature_policy,
                input_policy=input_policy,
                alpha=values['alpha'],
                rho=values['rho'],
                input_scale=values['input_scale'],
                input_fan_in=values['input_fan_in'],
                recurrent_sparsity=values['recurrent_sparsity'],
                interlayer_gain=values['interlayer_gain'],
                calendar='none',
                readout='pure_all_layers',
                seed=protocol['reservoir_seed'],
            ))
            identity = core.fingerprint(spec)
            if identity not in candidates:
                candidates[identity] = dict(
                    candidate_id='r137_' + identity[:16],
                    spec=spec,
                    specification_sha256=identity,
                    design_role='r135_basin_control',
                )
            protected.add(candidates[identity]['candidate_id'])
    rows = sorted(candidates.values(), key=lambda value: value['candidate_id'])
    return rows, sorted(protected)


def prepare(dependency, release, reference=None):
    runtime = setup(dependency); p = read(PROTOCOL); validate_protocol(p)
    p = dict(p, tag=TAG, regions=[REGION], maximum_workers=p['maximum_workers_per_region'])
    identity = source_identity()
    if git(dependency, 'rev-parse', 'HEAD') != p['dependency_head'] or git(dependency, 'status', '--porcelain'):
        raise RuntimeError('frozen dependency worktree differs')
    receipt = read(release)
    if receipt['source'] != identity or not receipt['passed']:
        raise RuntimeError('source-matched launch-prep release required')
    if (PREP / 'preparation.json').is_file():
        prior = read(PREP / 'preparation.json')
        if (prior['source'] != identity or prior['dependency_head'] != p['dependency_head']
                or prior['protocol'] != p):
            raise RuntimeError('existing R137 preparation belongs to a different immutable source')
        verify_hashes(prior['source_sha256']); verify_hashes(prior['input_sha256'])
        verify_hashes(prior['bank_sha256'])
        return dict(status='R137_ALREADY_PREPARED', first_stage_tasks=len(prior['tasks']),
            regional_candidates={r: len(v['candidates']) for r, v in prior['regional'].items()},
            all_region_launch=False, test_used_for_selection=False)
    resources(p, p['maximum_workers'] * p['worker_storage_allowance_GiB'])
    dep_here = dependency / 'application/scripts/pricefm'
    parent = DATA / 'campaigns' / p['bg_parent_tag']
    parent_prep = DATA / 'launch_prep' / p['bg_parent_tag']
    selection = read(parent / 'rhs/closeout/selection.json')
    manifest = pd.read_csv(parent / 'rhs/manifest.csv')
    candidates = pd.read_csv(parent_prep / 'candidate_manifest.csv')
    control = read(parent_prep / 'launch_control.json')
    official = read(dependency / 'application/config/pricefm_stage_r126_matched_comparison_protocol_20261007.json')
    if digest(DATA / 'raw/FINAL.csv') != official['raw_sha256']: raise RuntimeError('raw source changed')
    ledger = {str(path): digest(path) for path in (
        parent / 'rhs/closeout/selection.json', parent / 'rhs/manifest.csv',
        parent_prep / 'candidate_manifest.csv', parent_prep / 'launch_control.json',
        Path(control['cran_manifest']))}
    template = read(manifest.iloc[0].contract_path)
    anchors = {}; tasks = []
    for group in selection['ranking']:
        rows = manifest[manifest.candidate_id.eq(group['candidate_id']) &
            np.isclose(manifest.tau0, group['tau0'], rtol=1e-12, atol=0)]
        if len(rows) != 3 or set(rows.split) != {1, 2, 3}: raise RuntimeError('certified reuse group incomplete')
        candidate = candidates[candidates.candidate_id.eq(group['candidate_id'])].iloc[0]
        spec = runtime.normalize_spec(dict(__import__('json').loads(candidate.spec_json),
            seed=p['reservoir_seed']))
        anchors[group['candidate_id']] = spec
    if len(anchors) != 17: raise RuntimeError('frozen R123 architecture inventory differs')
    registry_path = dependency / 'tables/pricefm_r98_authoritative_registry.csv'
    registry = pd.read_csv(registry_path); ledger[str(registry_path)] = digest(registry_path)
    local_path = reference or DATA / 'benchmarks/pricefm_operational_public_architecture_fullshot_20260812/closeout/decision_registry.csv'
    local = core.benchmark_reference(local_path, p['local_pricefm_reference_sha256'])
    ledger[str(local_path)] = digest(local_path)
    regional = {}; bank_ledger = {}; design_audit = {}
    baseline = sorted(anchors.values(), key=lambda s: core.fingerprint(s))
    for region in p['regions']:
        proposed, protected, old_tau = core.balanced_candidates(runtime, baseline, registry, region,
            p['broad_candidate_draws'], p['candidate_seed'] + p['region_seed_offsets'][region])
        proposed, protected = add_r135_basin_controls(runtime, proposed, protected, region, p)
        exogenous_dimensions = {}
        for feature in p['feature_policies']:
            spec = next(v['spec'] for v in proposed if v['spec']['feature_policy'] == feature)
            frame = core.read_frame(DATA / 'raw/FINAL.csv', runtime.active_regions(spec), '2024-09-01')
            origins = pd.date_range('2022-02-04', '2024-09-01', inclusive='left', tz='UTC', freq='D')
            arrays = core.regional_arrays(runtime, frame, origins, spec)
            core.training_subset_valid(arrays, runtime.internal_splits(len(arrays.response)))
            path = OUT / 'training_banks' / region / (feature + '.npz'); path.parent.mkdir(parents=True, exist_ok=True)
            if path.exists():
                prior = core.load_arrays(runtime, path)
                for name in ('price_history', 'exog_history', 'exog_future', 'response', 'anchors'):
                    if not np.array_equal(getattr(prior, name), getattr(arrays, name)):
                        raise RuntimeError('partial preparation bank differs: ' + str(path))
                if prior.exog_names != arrays.exog_names:
                    raise RuntimeError('partial preparation bank labels differ: ' + str(path))
            else:
                core.save_arrays(path, arrays)
            bank_ledger[str(path)] = digest(path)
            exogenous_dimensions[feature] = len(arrays.exog_names)

        admissible = []
        for candidate in proposed:
            spec = candidate['spec']
            channels = exogenous_dimensions[spec['feature_policy']]
            dimension = spec['m_y'] + (spec['m_x'] + 1) * channels
            mandatory = runtime.mandatory_rows(candidate['spec'], dimension)
            if candidate['spec']['input_fan_in'] > dimension or len(mandatory) > candidate['spec']['units'][0]:
                continue
            admissible.append(candidate)
        controls = [v for v in admissible if v['candidate_id'] in protected]
        broad = [v for v in admissible if v['candidate_id'] not in protected]
        variants = controls + broad[:p['broad_candidates_per_region']]
        if len(variants) < p['broad_candidates_per_region'] or not set(protected).issubset(
                {v['candidate_id'] for v in variants}):
                raise RuntimeError('admissible R137 design lost breadth or a frozen control')
        regional[region] = dict(candidates=variants, protected_candidates=protected,
            protected_tau0=old_tau)
        design_audit[region] = dict(proposed=len(proposed), admissible=len(admissible), retained=len(variants),
            controls=len(controls), factor_counts={name: pd.Series([str(v['spec'][name]) for v in variants]).value_counts().to_dict()
                for name in ('m_y', 'm_x', 'depth', 'feature_policy', 'input_policy', 'alpha', 'rho',
                             'input_scale', 'input_fan_in', 'recurrent_sparsity', 'interlayer_gain')})
        tasks += [new_task(region + '_' + v['candidate_id'], 'ridge', region=region, **v) for v in variants]
    source_paths = list(HERE.glob('*r134*')) + list(HERE.glob('*r137*')) + [PROTOCOL,
        ROOT / 'application/tests/test_pricefm_stage_r137_four_region_pilot.py']
    source_paths += list(dep_here.glob('*.py')) + list(dep_here.glob('*.R'))
    source_paths += [dependency / 'application/R/pricefm_recursive_normal_fit.R']
    runtime_path = Path(control['normal_runtime'])
    source_paths += list((runtime_path / 'R').glob('*.R'))
    source_paths += list((Path(control['cran_library']) / 'exdqlm/R').glob('*'))
    sources = {str(path): digest(path) for path in source_paths if path.is_file()}
    references = registry[registry.region.isin(p['regions'])][['region', 'fold', 'qdesn_AQL', 'pricefm_AQL']]
    references = references.merge(local, on=['region', 'fold'], validate='one_to_one')
    if len(references) != 3 or references.isna().any().any(): raise RuntimeError('complete matching references required')
    prep = dict(source=identity, dependency=str(dependency), dependency_head=p['dependency_head'],
        protocol=p, official_protocol=official, template=template, control=control,
        regional=regional, tasks=tasks, references=references.to_dict('records'), design_audit=design_audit,
        source_sha256=sources, input_sha256=ledger, bank_sha256=bank_ledger,
        release_path=str(release), release_sha256=digest(release),
        historical_fits_used_for_selection=0, test_used_for_selection=False,
        official_development_test_seen_previously=True,
        raw_identity=dict(bytes=(DATA / 'raw/FINAL.csv').stat().st_size,
            mtime_ns=(DATA / 'raw/FINAL.csv').stat().st_mtime_ns,
            sha256=official['raw_sha256']))
    immutable(PREP / 'preparation.json', prep)
    return dict(status='R137_PREPARED', first_stage_tasks=len(tasks), historical_fits_used_for_selection=0,
        regional_candidates={r: len(v['candidates']) for r, v in regional.items()},
        all_region_launch=False, test_used_for_selection=False)


def valid():
    prep = read(PREP / 'preparation.json')
    if source_identity() != prep['source']: raise RuntimeError('executed R137 source changed')
    if git(prep['dependency'], 'rev-parse', 'HEAD') != prep['dependency_head']:
        raise RuntimeError('frozen dependency changed')
    verify_hashes(prep['source_sha256'])
    raw = (DATA / 'raw/FINAL.csv').stat()
    if (raw.st_size, raw.st_mtime_ns) != (prep['raw_identity']['bytes'], prep['raw_identity']['mtime_ns']):
        raise RuntimeError('raw source metadata changed; full content re-audit required')
    if digest(prep['release_path']) != prep['release_sha256']: raise RuntimeError('release changed')
    return prep


def bank(runtime, prep, task):
    path = OUT / 'training_banks' / task['region'] / (task['spec']['feature_policy'] + '.npz')
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
        write(folder / 'terminal.json', dict(status='completed_r137_quantile_design', test_opened=False,
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
        fixedpoint = ROOT / 'application/R/pricefm_r129_al_fixedpoint_certificate.R'
        contract = dict(stage='R137', model_stage='R137', tag=TAG, family='al', fold=stage_index,
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
        r_run(prep, HERE / '470_fit_pricefm_stage_r137_certified_al_300.R', contract, task)
        terminal = read(output / 'fit/terminal.json')
        return dict(certified=terminal['computationally_certified'] and terminal['finite_core'],
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
            proc = subprocess.Popen([sys.executable, '-B', str(ENTRY), 'worker', '--region', REGION,
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
            raise RuntimeError('R137 queue withheld dependent work: ' + str((failures, resource_error, [t['name'] for t in pending])))
        if active: time.sleep(3)


def rhs_tasks(prep):
    tasks = []; p = prep['protocol']; ranks = {}
    for region, values in prep['regional'].items():
        records = [r for t in prep['tasks'] if t['kind'] == 'ridge' and t['region'] == region
                   for r in outcome(t['name'])['records']]
        ranking, excluded = core.rank_groups(records, ['candidate_id'])
        selected = [r['candidate_id'] for r in ranking[:p['rhs_shortlist_structures']]]
        for protected in values['protected_candidates']:
            if protected not in selected: selected.append(protected)
        ranks[region] = dict(ranking=ranking, excluded=excluded, shortlist=selected)
        for candidate in values['candidates']:
            if candidate['candidate_id'] not in selected: continue
            p_dim = 1 + sum(candidate['spec']['units'])
            center = core.tau_center(p_dim, 506 * 96)
            taus = [center * m for m in p['tau_multipliers']]
            if candidate['candidate_id'] in values['protected_candidates']: taus.append(values['protected_tau0'])
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
        test_seen_before=True, confirmatory_claim=False,
        old_R98_exAL_vs_new_AL_difference_deliberate=True,
        selection='three_inner_rolling_splits_then_seven_quantile_AL_finalist_confirmation',
        conditions_for_next_decision='compare_complete_four-region three-fold cohort before any wider rollout'))
    regions = len(prep['protocol']['regions'])
    seal(output, dict(source=prep['source'], complete_regions=regions, complete_folds=3 * regions))
    write(OUT / 'terminal.json', dict(status='R137_REGION_COMPLETE_NOT_PROMOTED', regions=regions,
        full_fits=8 * 3 * regions,
        official_origin_region_pairs=sum(prep['official_protocol']['test_origin_counts']) * regions,
        historical_fits_used_for_selection=0, test_used_for_selection=False, source=prep['source']))


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
    if not 1 <= workers <= prep['protocol']['maximum_workers_per_region']:
        raise ValueError('per-region worker cap exceeded')
    with (OUT / 'controller.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for path in Path('/proc').glob('[0-9]*/cmdline'):
            try: command = path.read_bytes().split(b'\0')
            except OSError: continue
            if (str(ENTRY).encode() in command and b'worker' in command and b'--region' in command
                    and REGION.encode() in command):
                raise RuntimeError('live own worker detected; do not duplicate interrupted controller')
        verify_hashes(prep['input_sha256']); verify_hashes(prep['bank_sha256'])
        cpus = declared_cpus(cpu_list, workers)
        if not cpus: raise RuntimeError('no idle physical cores')
        resources(prep['protocol'], len(cpus) * prep['protocol']['worker_storage_allowance_GiB'])
        write(OUT / 'controller_identity.json', dict(pid=os.getpid(), host=socket.gethostname(),
            source=prep['source'], cpus=cpus, requested_workers=workers, epoch=time.time()))
        try:
            initial = prep['tasks']
            smoke = [next(t for t in initial if t['region'] == r) for r in prep['protocol']['regions']]
            batch(smoke, cpus[:len(smoke)], prep, 'compact_ridge_smoke_gate')
            immutable(OUT / 'smoke_gate.json', dict(passed=True, tasks=[t['name'] for t in smoke], source=prep['source']))
            batch(initial, cpus, prep, 'balanced_regional_Ridge_screen')
            rhs = rhs_tasks(prep); batch(rhs, cpus, prep, 'regional_Normal_RHS')
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
    parser.add_argument('--workers', type=int, default=15); parser.add_argument('--cpus')
    parser.add_argument('--region', choices=ALLOWED_REGIONS); parser.add_argument('--name'); parser.add_argument('--cpu', type=int)
    args = parser.parse_args()
    if args.action == 'prepare': print(prepare(args.dependency, args.release, args.reference), flush=True)
    else:
        prep = __import__('json').loads((PREP / 'preparation.json').read_text())
        setup(Path(prep['dependency']))
        if args.region != REGION: raise RuntimeError('command-line region does not match PRICEFM_R137_REGION')
        if args.action == 'controller': controller(args.workers, args.cpus)
        else: worker(args.name, args.cpu)
