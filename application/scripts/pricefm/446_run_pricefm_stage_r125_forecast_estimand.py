#!/usr/bin/env python3
"""Bounded frozen-fit diagnostics; no official forecasts, fitting or promotion."""
from __future__ import annotations

import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import sys
import tempfile
import time

for key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
            "NUMEXPR_NUM_THREADS", "R_DATATABLE_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ[key] = "1"

import numpy as np
import pandas as pd
from pricefm_r124_covariance import GaussianSampler, POLICY
from pricefm_r125_cdf import forecast_diagnostic, origin_positions

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
TAG = 'pricefm_stage_r125_forecast_estimand_diagnosis_20261006'
PREDECESSOR = 'pricefm_stage_r124_covariance_preserving_replay_v2_20261006'
FROZEN_HEAD = '0924e857ba74a499a22712db0f99b6de711d7d01'
PROTOCOL = ROOT / 'application/config/pricefm_stage_r125_forecast_estimand_protocol_20261006.json'
TEMPLATE = HERE / '445_run_pricefm_stage_r124_covariance_replay.py'
loader = importlib.util.spec_from_file_location('r125_private_replay_scheduler', TEMPLATE)
V = importlib.util.module_from_spec(loader); loader.loader.exec_module(V)
read, write, immutable = V.read, V.write, V.immutable
ORIGINAL_RELEASE = V.release_valid
ORIGINAL_VALID_JOBS = V.validate_jobs
OPERATORS = tuple(read(PROTOCOL)['operators'])


def identity():
    branch = V.git('branch', '--show-current')
    if not branch.startswith('work/pricefm-r125-') or V.git('status', '--porcelain'):
        raise RuntimeError('clean committed dedicated R125 source required')
    return dict(head=V.git('rev-parse', 'HEAD'), branch=branch)


def protocol_valid(value):
    if value != read(PROTOCOL):
        raise ValueError('frozen R125 diagnostic protocol differs')
    for name in ('screening_authorized', 'fitting_authorized', 'mcmc_authorized', 'joint_authorized',
                 'official_validation_authorized', 'official_test_authorized',
                 'registry_mutation_authorized', 'article_mutation_authorized', 'all_region_launch_authorized'):
        if value[name] is not False: raise ValueError('R125 scope violation')
    return value


def release_valid(path, source):
    value = ORIGINAL_RELEASE(path, source)
    if 'application/tests/test_pricefm_stage_r125_forecast_estimand.py' not in value['outcomes'][0]['command']:
        raise RuntimeError('matching R125 diagnostic regression required')
    return value


def validate_jobs(jobs):
    ORIGINAL_VALID_JOBS(jobs)
    protocol = read(PROTOCOL)
    if set(j['candidate_id'] for j in jobs) != set(protocol['candidates']):
        raise ValueError('frozen candidate scope differs')
    for job in jobs:
        expected = origin_positions(job['complete_origin_count']).tolist()
        if (job['origin_positions'] != expected or job['operators'] != list(OPERATORS)
                or job['diagnostic_only'] is not True or job['oracle_publishable'] is not False):
            raise ValueError('origin/estimand diagnostic contract differs')


def predecessor(m):
    prep_path = DATA / 'launch_prep' / PREDECESSOR / 'preparation.json'
    prep = read(prep_path)
    if prep['source']['head'] != FROZEN_HEAD:
        raise RuntimeError('completed R124 executed source differs')
    for paths in ('source_sha256', 'parent_ledgers', 'configurations'):
        m.REC.verify_evidence({'evidence_sha256': prep[paths]})
    code_root = next(Path(p).parents[3] for p in prep['source_sha256'] if Path(p).name == TEMPLATE.name)
    if V.git('rev-parse', 'HEAD', root=code_root) != FROZEN_HEAD or V.git('status', '--porcelain', root=code_root):
        raise RuntimeError('R124 frozen executed checkout changed')
    campaign = DATA / 'campaigns' / PREDECESSOR
    ledger = campaign / 'completed_evidence.json'
    m.REC.verify_evidence(read(ledger))
    terminal = read(campaign / 'terminal.json')
    if terminal['panels_complete'] != 9 or terminal['panels_failed'] != 0 or terminal['models_refitted'] != 0:
        raise RuntimeError('complete R124 replay required')
    return prep, {str(prep_path): m.REC.digest(prep_path), str(ledger): m.REC.digest(ledger)}


def build_jobs(args, m, control):
    prep, hashes = predecessor(m)
    jobs = []
    for path in sorted(prep['configurations']):
        original = read(path)
        reference = Path(original['output_dir'])
        count = read(reference / 'terminal.json')['scored_origins']
        evidence = dict(original['input_sha256'])
        for folder in original['quantile_dirs'].values():
            for name in ('parameter_summary.json', 'vb_trace.csv', 'diagnostics.json'):
                evidence[str(Path(folder) / name)] = m.REC.digest(Path(folder) / name)
        for name in ('predictions.npz', 'completed_evidence.json', 'terminal.json'):
            evidence[str(reference / name)] = m.REC.digest(reference / name)
        m.REC.verify_evidence({'evidence_sha256': evidence})
        jobs.append(dict(original, tag=TAG, output_dir=str(args.output / 'cells' / original['job_id']),
            reference_cell=str(reference), complete_origin_count=count,
            origin_positions=origin_positions(count).tolist(), operators=list(OPERATORS),
            diagnostic_only=True, oracle_publishable=False, input_sha256=evidence,
            predecessor_sha256=hashes))
    validate_jobs(jobs)
    return jobs, hashes


def prepare(args):
    source = identity(); protocol_valid(read(PROTOCOL)); release_valid(args.validation_receipt, source)
    m, control = V.owner(args); ledgers = V.parent_freeze(args, m)
    jobs, hashes = build_jobs(args, m, control); ledgers.update(hashes)
    configs = {}
    for job in jobs:
        path = args.prep / 'jobs' / (job['job_id'] + '.json')
        immutable(path, job); configs[str(path)] = m.REC.digest(path)
    sources = [Path(__file__), HERE / 'pricefm_r125_cdf.py', HERE / 'pricefm_r125_report.py',
        HERE / 'pricefm_r125_release.py', HERE / 'pricefm_r125_comparison.py',
        TEMPLATE, HERE / 'pricefm_r124_covariance.py', PROTOCOL,
        ROOT / 'application/tests/test_pricefm_stage_r125_forecast_estimand.py',
        ROOT / 'tables/pricefm_r98_authoritative_registry.csv',
        ROOT / 'tables/pricefm_r98_article_projection_manifest.json']
    value = dict(tag=TAG, source=source, owner_head=V.OWNER_HEAD, protocol=read(PROTOCOL),
        source_sha256={str(p): m.REC.digest(p) for p in sources}, parent_ledgers=ledgers,
        configurations=configs, parent_prep_sha256=m.REC.digest(args.parent_prep / 'identity.json'),
        validation_receipt=str(args.validation_receipt), validation_sha256=m.REC.digest(args.validation_receipt),
        args={name: str(getattr(args, name)) for name in V.OWNER_FIELDS},
        official_test_opened=False, official_validation_opened=False, fit_count=0)
    immutable(args.prep / 'preparation.json', value)
    return dict(status='R125_DIAGNOSTIC_PREPARED', panels=9, scored_origin_combinations=108, model_refits=0)


def verified_cell(path, job, digest, *, smoke=False):
    path = Path(path)
    if not path.exists(): return None
    if not (path / 'completed_evidence.json').exists():
        raise RuntimeError('partial R125 evidence preserved, not overwritten')
    ledger = read(path / 'completed_evidence.json')['artifact_sha256']
    if set(ledger) != {'predictions.npz', 'metrics.json', 'forecast_contract.json', 'terminal.json'}:
        raise RuntimeError('complete diagnostic artifact ledger required')
    for name, wanted in ledger.items():
        if Path(name).name != name or digest(path / name) != wanted:
            raise RuntimeError('diagnostic output hash changed')
    value = read(path / 'terminal.json')
    if (value['status'] != ('R125_SMOKE_COMPLETE' if smoke else 'R125_DIAGNOSTIC_CELL_COMPLETE')
            or value['job_id'] != job['job_id'] or value['input_sha256'] != job['input_sha256']
            or value['scored_origins'] != (2 if smoke else 12) or value['model_refits'] != 0
            or value['sampler'] != POLICY or value['operators'] != list(OPERATORS)
            or value['diagnostic_only'] is not True or value['oracle_publishable'] is not False
            or value['official_test_opened'] is not False or value['official_validation_opened'] is not False):
        raise RuntimeError('diagnostic output identity differs')
    return value


def forecast(m, control, job, maximum_origins=None, observe=lambda value: None):
    spec = m.RT.normalize_spec(dict(job['spec'], seed=job['source_reservoir_seed']))
    arrays = m.B._selection_arrays(control, spec)
    split = m.RT.internal_splits(len(arrays.response))[job['split'] - 1]
    scaled, scaler = m.RT.standardize_from_training_origins(arrays, split['train'])
    positions = np.array(job['origin_positions'][:maximum_origins] if maximum_origins else job['origin_positions'])
    indices = split['validation'][positions]
    selected = m.RT.subset_arrays(scaled, indices)
    normal = m.RT.load_normal_fit(Path(job['normal_dir']))
    quantiles = {float(q): m.RT.load_quantile_fit(Path(p)) for q, p in job['quantile_dirs'].items()}
    sampler = GaussianSampler()
    values, diagnostic = forecast_diagnostic(m.RT, selected, spec, normal, quantiles, positions,
        job['seed'], sampler, observe=observe, iterations=read(PROTOCOL)['cdf_bisection_iterations'])
    converted = {name: value * scaler['price_scale'] + scaler['price_mean'] for name, value in values.items()}
    with np.load(Path(job['reference_cell']) / 'predictions.npz', allow_pickle=False) as prior:
        if not np.array_equal(prior['origin_indices'][positions], indices):
            raise RuntimeError('R124 matched internal-origin support differs')
        for name in ('truth', 'mean_feature', 'path_specific', 'normal_driver'):
            if not np.allclose(converted[name], prior[name][positions], rtol=2e-12, atol=1e-9):
                raise RuntimeError('paired original forecast reconstruction differs: ' + name)
    metrics = {name: m.RT.prediction_metrics(converted['truth'], converted[name]) for name in OPERATORS}
    converted.update(origin_indices=indices, original_local_positions=positions,
        origin_utc=np.asarray([str(v) for v in selected.anchors], dtype='U40'))
    metadata = dict(stage='R125', diagnostic_only=True, oracle_publishable=False,
        units='outer_fold1_training_scaled_price', scaler=scaler, training_origins=len(split['train']),
        scored_origins=len(indices), horizon_steps=96, step_minutes=15, posterior_paths=500,
        sampler_audit=sampler.audit, source_reservoir_seed=job['source_reservoir_seed'],
        fit_labels=job['fit_labels'], full_variational_stationarity_certified=False,
        future_target_lags='generated_normal_paths_only_except_explicit_oracle_diagnostics',
        teacher_forcing_between_origins=True, original_local_positions=positions.tolist(),
        paired_R124_forecasts_reproduced=True, diagnostic=diagnostic, operators=list(OPERATORS))
    return converted, metrics, metadata


def cell(args, *, smoke=False):
    m, control = V.owner(args); prep, jobs = V.verify_preparation(args, m)
    job = read(args.config)
    if str(args.config) not in prep['configurations'] or job not in jobs:
        raise RuntimeError('diagnostic worker outside manifest')
    m.REC.verify_evidence({'evidence_sha256': job['input_sha256']})
    output = args.output / 'smoke' / job['job_id'] if smoke else Path(job['output_dir'])
    output.parent.mkdir(parents=True, exist_ok=True)
    with (args.output / (job['job_id'] + ('_smoke' if smoke else '') + '.lock')).open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if output.exists(): return verified_cell(output, job, m.REC.digest, smoke=smoke)
        temporary = Path(tempfile.mkdtemp(prefix=job['job_id'] + '.tmp.', dir=output.parent))
        heartbeat = args.output / 'heartbeats' / (job['job_id'] + ('_smoke' if smoke else '') + '.json')
        start = time.time()
        values, metrics, metadata = forecast(m, control, job, 2 if smoke else None,
            lambda value: write(heartbeat, dict(value, at_epoch=time.time())))
        np.savez_compressed(temporary / 'predictions.npz', **values)
        write(temporary / 'metrics.json', metrics)
        write(temporary / 'forecast_contract.json', dict(job=job, **metadata))
        m.REC.verify_evidence({'evidence_sha256': job['input_sha256']})
        terminal = dict(metadata, status='R125_SMOKE_COMPLETE' if smoke else 'R125_DIAGNOSTIC_CELL_COMPLETE',
            tag=TAG, job_id=job['job_id'], candidate_id=job['candidate_id'], split=job['split'], tau0=job['tau0'],
            source=prep['source'], input_sha256=job['input_sha256'], model_refits=0, sampler=POLICY,
            official_test_opened=False, official_validation_opened=False, elapsed_seconds=time.time() - start)
        write(temporary / 'terminal.json', terminal)
        immutable(temporary / 'completed_evidence.json', {'artifact_sha256': {
            name: m.REC.digest(temporary / name) for name in
            ('predictions.npz', 'metrics.json', 'forecast_contract.json', 'terminal.json')}})
        if output.exists(): raise RuntimeError('diagnostic output installed by another writer')
        temporary.rename(output)
        return verified_cell(output, job, m.REC.digest, smoke=smoke)


def closeout(args):
    m, control = V.owner(args); prep, jobs = V.verify_preparation(args, m)
    if (args.output / 'completed_evidence.json').exists():
        m.REC.verify_evidence(read(args.output / 'completed_evidence.json'))
        V.parent_freeze(args, m)
        return read(args.output / 'terminal.json')
    from pricefm_r123_dependency_queue import process_identity, same_process
    scores, origins, traces = [], [], []
    for job in jobs:
        receipt = args.output / 'launched' / (job['job_id'] + '.json')
        if receipt.exists():
            record = read(receipt); current = process_identity(record['pid'])
            if same_process(record, current) and current['state'] != 'Z':
                raise RuntimeError('diagnostic worker still writing')
        path = Path(job['output_dir']); terminal = verified_cell(path, job, m.REC.digest)
        if terminal is None or terminal['source'] != prep['source']:
            raise RuntimeError('complete nine-cell diagnostic source required')
        m.REC.verify_evidence({'evidence_sha256': job['input_sha256']})
        with np.load(path / 'predictions.npz', allow_pickle=False) as arrays:
            saved = read(path / 'metrics.json')
            if arrays['original_local_positions'].tolist() != job['origin_positions']:
                raise RuntimeError('diagnostic origin-selection rule changed')
            for name in OPERATORS:
                metric = m.RT.prediction_metrics(arrays['truth'], arrays[name])
                if any(not math.isfinite(v) or abs(v - saved[name][k]) > 1e-12 for k, v in metric.items()):
                    raise RuntimeError('diagnostic metric reconstruction differs')
                scores.append(dict(candidate_id=job['candidate_id'], split=job['split'], operator=name,
                    units='outer_fold1_training_scaled_price', diagnostic_only=True, **metric))
                error = arrays['truth'][:, :, None] - arrays[name]
                loss = np.maximum(np.array(m.RT.QUANTILES) * error, (np.array(m.RT.QUANTILES) - 1) * error)
                for i in range(12):
                    origins.append(dict(candidate_id=job['candidate_id'], split=job['split'], operator=name,
                        origin_index=int(arrays['origin_indices'][i]), anchor=str(arrays['origin_utc'][i]),
                        AQL=float(loss[i].mean()), early_AQL=float(loss[i, :24].mean()), late_AQL=float(loss[i, 72:].mean())))
        for q, folder in job['quantile_dirs'].items():
            trace = pd.read_csv(Path(folder) / 'vb_trace.csv'); fit = read(Path(folder) / 'terminal.json')
            tail = trace.tail(25)
            traces.append(dict(candidate_id=job['candidate_id'], split=job['split'], tau=float(q),
                formal_converged=fit['formal_converged'], iterations=fit['iterations'],
                full_state_available=False, exact_optimizer_resumption_possible=False,
                raw_ELBO_final=float(trace.elbo.iloc[-1]), raw_ELBO_tail_range=float(tail.elbo.max() - tail.elbo.min()),
                maximum_absolute_delta_state=float(tail.delta_state.abs().max()),
                maximum_absolute_delta_sigma=float(tail.delta_sigma.abs().max())))
    frame = pd.DataFrame(scores); origin_frame = pd.DataFrame(origins)
    frame.to_csv(args.output / 'operator_cell_metrics.csv', index=False)
    origin_frame.to_csv(args.output / 'paired_origin_metrics.csv', index=False)
    pd.DataFrame(traces).to_csv(args.output / 'saved_fit_trace_audit.csv', index=False)
    registry = ROOT / 'tables/pricefm_r98_authoritative_registry.csv'
    projection = read(ROOT / 'tables/pricefm_r98_article_projection_manifest.json')
    if m.REC.digest(registry) != projection['frozen_inputs']['pricefm_stage_r98_authoritative_registry.csv']:
        raise RuntimeError('current main article authority does not match frozen projection')
    reference = pd.read_csv(registry); reference = reference[reference.region.eq('BG')]
    if len(reference) != 3 or set(reference.fold) != {1, 2, 3}:
        raise RuntimeError('complete BG historical reference required')
    reference[['region', 'fold', 'qdesn_AQL', 'pricefm_AQL']].to_csv(args.output / 'historical_OFFICIAL_context_NOT_matched_to_internal.csv', index=False)
    requirements = dict(status='UNRESOLVED_NO_MATCHED_NEW_OFFICIAL_FORECASTS',
        current_authority='main_R98_region_frozen_QDESN', comparator='cached_PriceFM_Phase_I',
        new_evidence='R125_outer_fold1_training_internal_only', direct_comparison_valid=False,
        promotion_authorized=False, all_region_launch_authorized=False, official_test_opened=False,
        mean_AQL_rule='compare_prespecified_mean_across_all_regions_and_folds_not_per_case_dual_gate',
        oracle_eligible=False, CDF_tail_conventions_are_diagnostics_only=True,
        required_next_steps=['resolve or document capped B full-state gap',
            'freeze one deployable forecast operator using training-only development',
            'fit frozen spec on all three full BG training windows (3 Normal + 21 AL), not partial internal fits',
            'match origins, all 7 levels, 96 quarter-hour horizons, currency scaler and actual cached references',
            'report historical-test exposure: retrospective comparison, not pristine confirmation',
            'no test-driven retuning or fold-wise model switching',
            'full all-region promotion requires completed aligned whole-cohort scores and coordinator integration'],
        background_full_fit_auto_launch=False)
    immutable(args.output / 'promotion_and_comparison_requirements.json', requirements)
    from pricefm_r125_report import report
    report(args.output, jobs, frame, origin_frame, pd.DataFrame(traces), reference, requirements)
    V.parent_freeze(args, m)
    terminal = dict(status='R125_DIAGNOSTIC_COMPLETE_PROMOTION_BLOCKED', tag=TAG, source=prep['source'],
        panels_complete=9, panels_failed=0, active_workers=0, scored_origin_combinations=108,
        model_refits=0, official_test_opened=False, official_validation_opened=False,
        promising_vs_authority='UNRESOLVED_UNMATCHED_WINDOWS', promising_vs_pricefm='UNRESOLVED_UNMATCHED_WINDOWS',
        article_promotion_authorized=False, all_region_launch_authorized=False,
        integration_status='NOT_READY_FOR_INTEGRATION')
    immutable(args.output / 'terminal.json', terminal)
    if sum(p.stat().st_size for p in args.output.rglob('*') if p.is_file()) > 100 * 2**20:
        raise RuntimeError('bounded diagnostic storage exceeded')
    ledger = {str(p): m.REC.digest(p) for p in sorted(args.output.rglob('*')) if p.is_file()
        and p.name not in ('completed_evidence.json', 'controller.lock', 'controller.log', 'blocked.json')
        and not p.name.endswith('.lock') and '.tmp.' not in str(p)}
    immutable(args.output / 'completed_evidence.json', {'evidence_sha256': ledger})
    return terminal


# Process-local reuse preserves the tested R124 scheduler and frozen source.
V.TAG = TAG; V.PROTOCOL = PROTOCOL; V.__file__ = __file__
V.own_identity = identity; V.protocol_valid = protocol_valid; V.release_valid = release_valid
V.validate_jobs = validate_jobs; V.prepare = prepare; V.verified_cell = verified_cell
V.forecast = forecast; V.cell = cell; V.closeout = closeout

if __name__ == '__main__':
    args = V.parser().parse_args()
    try:
        result = (prepare(args) if args.mode == 'prepare' else cell(args, smoke=args.mode == 'smoke')
            if args.mode in ('cell', 'smoke') else V.controller(args) if args.mode == 'controller' else closeout(args))
        print(json.dumps(result, sort_keys=True), flush=True)
    except Exception as error:
        if args.output.resolve() == DATA / 'campaigns' / TAG:
            target = 'failed_' + args.config.stem + '.json' if args.mode in ('cell', 'smoke') and args.config else 'blocked.json'
            write(args.output / target, dict(error_type=type(error).__name__, error=str(error), mode=args.mode,
                at_epoch=time.time(), model_refits=0, existing_evidence_preserved=True))
        raise
