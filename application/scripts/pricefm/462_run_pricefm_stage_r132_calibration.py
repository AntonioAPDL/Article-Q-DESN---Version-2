#!/usr/bin/env python3
"""Source-gated R132 internal calibration and frozen-receiver replay."""
from __future__ import annotations

import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

for key in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS',
            'BLIS_NUM_THREADS', 'NUMEXPR_NUM_THREADS', 'R_DATATABLE_NUM_THREADS'):
    os.environ[key] = '1'
os.environ['PYTHONDONTWRITEBYTECODE'] = '1'
sys.dont_write_bytecode = True

import numpy as np
import pandas as pd
from pricefm_r132_calibration import (CANDIDATES, validate_protocol, fit_calibration,
    internal_packet, select_candidate, calibrated_receiver_replay, plot_report)

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
ENTRY = Path(__file__).resolve()
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
TAG = 'pricefm_stage_r132_stochastic_driver_calibration_20261011'
OUT = DATA / 'campaigns' / TAG
PREP = DATA / 'launch_prep' / TAG
PROTOCOL = ROOT / 'application/config' / (TAG + '.json')


def git(path, *args):
    return subprocess.check_output(['git', '-C', str(path), *args], text=True).strip()


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec); sys.modules[name] = value
    spec.loader.exec_module(value)
    return value


def identity():
    branch = git(ROOT, 'branch', '--show-current')
    if not branch.startswith('work/pricefm-r132-') or git(ROOT, 'status', '--porcelain'):
        raise RuntimeError('clean committed dedicated R132 source required')
    return dict(branch=branch, head=git(ROOT, 'rev-parse', 'HEAD'))


def setup(dependency, r128):
    global runtime, regional, read, write, immutable, digest, seal, verified, verify_hashes, common_metrics
    sys.path.insert(0, str(Path(dependency) / 'application/scripts/pricefm'))
    from pricefm_r126_contract import read, write, immutable, digest, seal, verified, verify_hashes
    from pricefm_r127_contract import common_metrics
    import pricefm_r123_runtime as runtime
    regional = module('r132_frozen_regional_core',
        Path(r128) / 'application/scripts/pricefm/pricefm_r128_core.py')


def release(dependency, r128, r131):
    source = identity()
    target = DATA / 'runtime_audits' / TAG / ('release_' + socket.gethostname() + '_' + source['head'][:12])
    target.mkdir(parents=True, exist_ok=False)
    junit = target / 'pytest.xml'; env = dict(os.environ)
    env.update(PRICEFM_R132_DEPENDENCY=str(dependency), PRICEFM_R132_R128=str(r128),
        PRICEFM_R132_R131=str(r131), PRICEFM_R131_DEPENDENCY=str(dependency))
    tests = [ROOT / 'application/tests/test_pricefm_stage_r132_calibration.py',
        Path(r131) / 'application/tests/test_pricefm_stage_r131_seasonal.py',
        Path(dependency) / 'application/tests/test_pricefm_stage_r127_driver_diagnosis.py']
    with (target / 'pytest.log').open('w') as log:
        result = subprocess.run([sys.executable, '-B', '-m', 'pytest', '-q',
            *map(str, tests), '-p', 'no:cacheprovider', '--junitxml=' + str(junit)],
            cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
    suites = ET.parse(junit).getroot().findall('testsuite')
    totals = {key: sum(int(s.get(key, '0')) for s in suites)
              for key in ('tests', 'failures', 'errors', 'skipped')}
    receipt = dict(source=source, **totals, passed=result.returncode == 0
        and totals['tests'] >= 80 and sum(totals[k] for k in ('failures', 'errors', 'skipped')) == 0,
        dependency_heads=dict(r127=git(dependency, 'rev-parse', 'HEAD'),
            r128=git(r128, 'rev-parse', 'HEAD'), r131=git(r131, 'rev-parse', 'HEAD')))
    (target / 'validation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if not receipt['passed']:
        raise RuntimeError('R132 release failed: ' + str(target / 'pytest.log'))
    return dict(path=str(target / 'validation.json'), **receipt)


def resources(protocol, allowance=0.):
    memory = {row.split(':')[0]: int(row.split()[1]) * 1024
              for row in Path('/proc/meminfo').read_text().splitlines()}
    free = shutil.disk_usage(DATA).free / 2**30
    used = sum(path.stat().st_size for path in OUT.rglob('*') if path.is_file()) / 2**30
    if (memory['MemAvailable'] / 2**30 < protocol['minimum_free_memory_GiB']
            or free < protocol['minimum_free_disk_GiB'] + allowance
            or used + allowance > protocol['maximum_campaign_output_GiB']):
        raise RuntimeError('R132 resource reserve reached; completed evidence retained')
    return dict(available_memory_GiB=memory['MemAvailable'] / 2**30,
        free_disk_GiB=free, campaign_GiB=used)


def _rhs_fit(r128_out, choice, region, split):
    matches = []
    for path in (r128_out / 'tasks').glob('*.json'):
        task = json.loads(path.read_text())
        if (task.get('kind') == 'rhs' and task.get('region') == region
                and task.get('candidate_id') == choice['candidate_id']
                and int(task.get('split')) == split
                and np.isclose(float(task.get('tau0')), float(choice['tau0']), rtol=1e-12, atol=0)):
            matches.append((task, path))
    if len(matches) != 1:
        raise RuntimeError(f'exact R128 winning internal fit not unique: {region} split {split}')
    task, contract = matches[0]; folder = r128_out / 'tasks_done' / task['name']
    metadata = verified(folder)
    if not metadata.get('certified', False):
        raise RuntimeError('uncertified R128 internal fit: ' + task['name'])
    return task, contract, folder / 'fit'


def preparation(r131, r130, r128, dependency, release_path):
    setup(dependency, r128); protocol = read(PROTOCOL); validate_protocol(protocol); source = identity()
    for path, key in ((r131, 'r131_head'), (r130, 'r130_head'),
                      (r128, 'r128_head'), (dependency, 'r127_head')):
        if git(path, 'rev-parse', 'HEAD') != protocol[key] or git(path, 'status', '--porcelain'):
            raise RuntimeError('frozen dependency differs: ' + key)
    receipt = read(release_path)
    if receipt['source'] != source or not receipt['passed']:
        raise RuntimeError('source-matched R132 release required')
    r128_out = DATA / 'campaigns/pricefm_stage_r128_stochastic_regional_pilots_20261008'
    r130_out = DATA / 'campaigns/pricefm_stage_r130_forecast_error_attribution_20261010'
    r131_out = DATA / 'campaigns/pricefm_stage_r131_causal_seasonal_drivers_20261011'
    r131_prep = DATA / 'launch_prep/pricefm_stage_r131_causal_seasonal_drivers_20261011/preparation.json'
    for folder in (r130_out / 'closeout', r131_out / 'closeout'):
        verified(folder)
    # R128's internal Normal selection completed and was frozen before its
    # later quantile queue stopped. R132 uses only that sealed internal phase.
    r128_interruption = read(r128_out / 'blocked.json')
    if (not r128_interruption.get('existing_evidence_preserved')
            or r128_interruption.get('source', {}).get('head') != protocol['r128_head']
            or not (r128_out / 'frozen_choices.json').is_file()):
        raise RuntimeError('R128 sealed internal phase is unavailable')
    if read(r130_out / 'terminal.json')['status'] != 'R130_COMPLETE_NOT_PROMOTED':
        raise RuntimeError('R130 is not frozen complete')
    if read(r131_out / 'terminal.json')['status'] != 'R131_COMPLETE_NOT_PROMOTED':
        raise RuntimeError('R131 is not frozen complete')
    choices = read(r128_out / 'frozen_choices.json'); parent = read(r131_prep)
    if (Path(parent['parent_out']) != r130_out or parent['source']['head'] != protocol['r131_head']
            or parent['protocol']['parent_head'] != protocol['r130_head']):
        raise RuntimeError('R131 copied R130 lineage differs')
    inputs = {}; cells = []; tasks = []
    for path in (r128_out / 'frozen_choices.json', r128_out / 'blocked.json',
                 r131_prep, r130_out / 'terminal.json',
                 r131_out / 'terminal.json'):
        inputs[str(path)] = digest(path)
    for region in protocol['regions']:
        choice = choices[region]
        for split in protocol['internal_splits']:
            task, contract, fit = _rhs_fit(r128_out, choice, region, split)
            bank = r128_out / 'training_banks' / region / (choice['spec']['feature_policy'] + '.npz')
            for path in (contract, bank, fit / 'terminal.json', fit / 'beta_mean.bin', fit / 'beta_cov.bin'):
                inputs[str(path)] = digest(path)
            cell = dict(region=region, split=split, spec=choice['spec'], tau0=choice['tau0'],
                candidate_id=choice['candidate_id'], bank=str(bank), fit=str(fit),
                r128_task=task['name'])
            cells.append(cell)
            tasks.append(dict(name=f'internal_{region}_s{split}_identity', kind='internal',
                candidate='identity', map=None, **cell))
    heldout = []
    for cell in parent['cells']:
        item = dict(cell)
        for path in (Path(item['bank']), Path(item['normal_dir']) / 'terminal.json',
                     Path(item['normal_dir']) / 'beta_mean.bin', Path(item['normal_dir']) / 'beta_cov.bin'):
            inputs[str(path)] = digest(path)
        for folder in item['quantile_dirs'].values():
            for name in ('terminal.json', 'beta_mean.bin', 'beta_cov.bin'):
                path = Path(folder) / name; inputs[str(path)] = digest(path)
        heldout.append(item)
    for task in parent['tasks']:
        path = r130_out / 'tasks_done' / task['name'] / 'predictions.npz'
        inputs[str(path)] = digest(path)
    source_paths = [ENTRY, HERE / 'pricefm_r132_calibration.py', PROTOCOL,
        ROOT / 'application/notes/pricefm_stage_r132_stochastic_driver_calibration_20261011.md',
        ROOT / 'application/tests/test_pricefm_stage_r132_calibration.py',
        r128 / 'application/scripts/pricefm/pricefm_r128_core.py',
        dependency / 'application/scripts/pricefm/pricefm_r127_forecast.py',
        dependency / 'application/scripts/pricefm/pricefm_r127_contract.py']
    prep = dict(source=source, protocol=protocol, dependency=str(dependency), r128_source=str(r128),
        r130_source=str(r130), r131_source=str(r131), r128_out=str(r128_out),
        r130_out=str(r130_out), r131_out=str(r131_out), release=str(release_path),
        release_sha256=digest(release_path), source_sha256={str(p): digest(p) for p in source_paths},
        input_sha256=inputs, internal_cells=cells, heldout_cells=heldout,
        internal_tasks=tasks, heldout_parent_tasks=parent['tasks'],
        r128_dependency_scope='sealed_internal_Normal_selection_before_later_quantile_queue_interruption',
        official_test_reforecast=False, new_fits=0, selection_uses_r130_or_r131=False)
    immutable(PREP / 'preparation.json', prep)
    for task in tasks:
        immutable(OUT / 'tasks' / (task['name'] + '.json'), task)
    return dict(status='R132_PREPARED', internal_tasks=len(tasks), heldout_tasks=len(parent['tasks']),
        new_fits=0, maximum_workers=protocol['maximum_workers'])


def valid(prep, full=False):
    if identity() != prep['source'] or read(PROTOCOL) != prep['protocol']:
        raise RuntimeError('R132 source or protocol changed')
    verify_hashes(prep['source_sha256'])
    if full:
        verify_hashes(prep['input_sha256'])
    for path, key in ((prep['r131_source'], 'r131_head'), (prep['r130_source'], 'r130_head'),
                      (prep['r128_source'], 'r128_head'), (prep['dependency'], 'r127_head')):
        if git(path, 'rev-parse', 'HEAD') != prep['protocol'][key]:
            raise RuntimeError('frozen dependency head changed: ' + key)


def _load_internal(prep, region, split):
    name = f'internal_{region}_s{split}_identity'
    folder = OUT / 'tasks_done' / name; verified(folder)
    with np.load(folder / 'driver.npz', allow_pickle=False) as values:
        return {key: values[key] for key in values.files}


def worker(name, cpu):
    prep = read(PREP / 'preparation.json'); setup(prep['dependency'], prep['r128_source']); valid(prep)
    os.sched_setaffinity(0, {cpu}); task = read(OUT / 'tasks' / (name + '.json'))
    scheduled = list(prep['internal_tasks'])
    for schedule in ('forward_tasks.json', 'heldout_tasks.json'):
        path = OUT / schedule
        if path.exists(): scheduled.extend(read(path))
    if task not in scheduled:
        raise RuntimeError('task is absent from the immutable R132 schedule')
    destination = OUT / 'tasks_done' / name
    if destination.exists():
        verified(destination); return
    beat = lambda value: write(OUT / 'heartbeats' / (name + '.json'), dict(value, cpu=cpu, epoch=time.time()))
    start = time.time(); tmp_parent = OUT / 'staging'; tmp_parent.mkdir(exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix=name + '.', dir=tmp_parent))
    if task['kind'] == 'internal':
        arrays = regional.load_arrays(runtime, Path(task['bank']))
        split = runtime.internal_splits(len(arrays.response))[task['split'] - 1]
        scaled, scaler = runtime.standardize_from_training_origins(arrays, split['train'])
        fit = runtime.load_normal_fit(Path(task['fit']))
        calibration = fit_calibration([dict(truth=np.zeros((1, 96)), driver_mean=np.zeros((1, 96)),
            driver_sd=np.ones((1, 96)), anchor_clock=np.zeros(1))], 'identity', prep['protocol'], []) \
            if task['map'] is None else read(task['map'])
        packet = internal_packet(runtime, regional, scaled, task['spec'], fit, split,
            prep['protocol']['origins_per_clock'],
            runtime.BASE.deterministic_seed(2026100801, task['region'], task['split']),
            calibration, scaler['price_scale'], observe=beat)
        for key in ('prediction', 'driver_mean', 'truth'):
            packet[key] = packet[key] * scaler['price_scale'] + scaler['price_mean']
        packet['driver_sd'] *= scaler['price_scale']
        np.savez_compressed(tmp / 'driver.npz', **packet)
        result = dict(certified=True, region=task['region'], split=task['split'],
            candidate=task['candidate'], **common_metrics(packet['truth'], packet['prediction']),
            validation_response_starts_after_training=True, fitting_performed=False)
    elif task['kind'] == 'heldout':
        cell = next(c for c in prep['heldout_cells']
                    if (c['region'], c['fold']) == (task['region'], task['fold']))
        arrays = runtime.subset_arrays(regional.load_arrays(runtime, Path(cell['bank'])), task['bank_indices'])
        calibration = read(task['map']); normal = runtime.load_normal_fit(Path(cell['normal_dir']))
        quantiles = {float(q): runtime.load_quantile_fit(Path(folder))
                     for q, folder in cell['quantile_dirs'].items()}
        seed = runtime.BASE.deterministic_seed(2026101001, task['region'], task['fold'], 'validation')
        values, audit = calibrated_receiver_replay(runtime, arrays, cell['spec'], quantiles,
            normal, task['positions'], seed, calibration, cell['scaler']['price_scale'], observe=beat)
        for key in ('calibrated', 'driver_mean'):
            values[key] = values[key] * cell['scaler']['price_scale'] + cell['scaler']['price_mean']
        values['driver_sd'] *= cell['scaler']['price_scale']
        parent = Path(prep['r130_out']) / 'tasks_done' / task['parent_name'] / 'predictions.npz'
        with np.load(parent, allow_pickle=False) as cached:
            for key in ('stochastic', 'truth', 'positions', 'bank_indices', 'anchors_ns'):
                values[key] = cached[key]
        expected = arrays.response * cell['scaler']['price_scale'] + cell['scaler']['price_mean']
        np.testing.assert_array_equal(values['truth'], expected)
        first = float(np.max(abs(values['calibrated'][:, 0] - values['stochastic'][:, 0])))
        if first > 1e-8:
            raise RuntimeError('R132 first-step receiver identity failed')
        np.savez_compressed(tmp / 'predictions.npz', **values)
        result = dict(certified=True, region=task['region'], fold=task['fold'],
            first_step_difference=first, calibration_mode=calibration['mode'],
            fitting_performed=False, official_test_opened=False, audit=audit)
    else:
        raise ValueError('unknown R132 task kind')
    write(tmp / 'result.json', result)
    seal(tmp, dict(source=prep['source'], task_sha256=digest(OUT / 'tasks' / (name + '.json')),
        task=task, elapsed_seconds=time.time() - start,
        certified=result['certified']))
    destination.parent.mkdir(exist_ok=True)
    if destination.exists():
        raise RuntimeError('duplicate R132 task writer')
    tmp.rename(destination)


def register(tasks):
    for task in tasks:
        immutable(OUT / 'tasks' / (task['name'] + '.json'), task)


def complete(task):
    folder = OUT / 'tasks_done' / task['name']
    if (folder / 'completed_evidence.json').exists():
        verified(folder); return True
    return False


def cpu_pool(count):
    scheduler = module('r132_frozen_scheduler',
        Path(read(PREP / 'preparation.json')['dependency']) /
        'application/scripts/pricefm/450_run_pricefm_stage_r127_driver_diagnosis.py')
    return scheduler.cpu_pool(count)


def batch(tasks, cpus, prep, stage):
    register(tasks); pending = [task for task in tasks if not complete(task)]
    active = {}; free = list(cpus); failures = []; resource_error = None
    while pending or active:
        try:
            snapshot = resources(prep['protocol'], .02 * (len(active) + 1))
        except RuntimeError as error:
            resource_error = str(error); snapshot = {}
        while pending and free and not failures and not resource_error:
            task = pending.pop(0); cpu = free.pop(0)
            stream = (OUT / 'worker_logs' / (task['name'] + '.log')).open('a')
            process = subprocess.Popen([sys.executable, '-B', str(ENTRY), 'worker',
                '--name', task['name'], '--cpu', str(cpu)], stdout=stream,
                stderr=subprocess.STDOUT, start_new_session=True)
            active[task['name']] = (process, cpu, stream)
        for name, (process, cpu, stream) in list(active.items()):
            code = process.poll()
            if code is None: continue
            stream.close(); free.append(cpu); del active[name]
            if code: failures.append(dict(task=name, exit_code=code))
        write(OUT / 'progress.json', dict(stage=stage, active=len(active), pending=len(pending),
            completed=sum(complete(task) for task in tasks), stage_total=len(tasks), failures=failures,
            resource_error=resource_error, resources=snapshot, epoch=time.time()))
        if not active and (failures or resource_error):
            raise RuntimeError(str(failures or resource_error))
        if pending or active: time.sleep(3)


def forward_tasks(prep):
    tasks = []
    for region in prep['protocol']['regions']:
        for split in prep['protocol']['forward_evaluation_splits']:
            training = list(range(1, split))
            packets = [_load_internal(prep, region, value) for value in training]
            for candidate in CANDIDATES[1:]:
                calibration = fit_calibration(packets, candidate, prep['protocol'], training)
                path = OUT / 'maps' / f'{region}_eval{split}_{candidate}.json'
                immutable(path, calibration)
                cell = next(c for c in prep['internal_cells']
                            if c['region'] == region and c['split'] == split)
                tasks.append(dict(name=f'internal_{region}_s{split}_{candidate}', kind='internal',
                    candidate=candidate, map=str(path), **cell))
    return tasks


def choose_maps(prep, evaluations):
    decisions = {}; rows = []
    by_name = {task['name']: task for task in [*prep['internal_tasks'], *evaluations]}
    for region in prep['protocol']['regions']:
        for split in prep['protocol']['forward_evaluation_splits']:
            for candidate in CANDIDATES:
                task = by_name[f'internal_{region}_s{split}_{candidate}']
                result = read(OUT / 'tasks_done' / task['name'] / 'result.json')
                rows.append({key: result[key] for key in ('region', 'split', 'candidate', 'AQL',
                    'median_MAE', 'coverage_80', 'width_80')})
        decision = select_candidate([r for r in rows if r['region'] == region], prep['protocol'])
        packets = [_load_internal(prep, region, split) for split in prep['protocol']['internal_splits']]
        calibration = fit_calibration(packets, decision['selected'], prep['protocol'],
            prep['protocol']['internal_splits'])
        map_path = OUT / 'maps' / f'{region}_final.json'; immutable(map_path, calibration)
        decision.update(map=str(map_path), map_sha256=digest(map_path), region=region)
        decisions[region] = decision
    immutable(OUT / 'internal_selection.json', decisions)
    pd.DataFrame(rows).to_csv(OUT / 'internal_forward_metrics.csv', index=False)
    return decisions, rows


def heldout_tasks(prep, decisions):
    tasks = []
    for parent in prep['heldout_parent_tasks']:
        tasks.append(dict(name='heldout_' + parent['name'], kind='heldout', parent_name=parent['name'],
            region=parent['region'], fold=parent['fold'], offset=parent['offset'],
            bank_indices=parent['bank_indices'], positions=parent['positions'], smoke=parent['smoke'],
            map=decisions[parent['region']]['map']))
    return tasks


def closeout(prep, rows, decisions, tasks):
    path = OUT / 'closeout'
    if path.exists():
        verified(path); return read(path / 'interpretation.json')
    metrics = []; driver_rows = []
    for cell in prep['heldout_cells']:
        selected = [task for task in tasks
                    if (task['region'], task['fold']) == (cell['region'], cell['fold'])]
        packets = []
        for task in selected:
            folder = OUT / 'tasks_done' / task['name']; verified(folder)
            with np.load(folder / 'predictions.npz', allow_pickle=False) as values:
                packets.append({key: values[key] for key in values.files})
        values = {key: np.concatenate([packet[key] for packet in packets]) for key in packets[0]}
        order = np.argsort(values['bank_indices']); values = {key: value[order] for key, value in values.items()}
        for offset in prep['protocol']['origin_offsets_steps']:
            idx = [i for i, row in enumerate(cell['grid']) if row['offset'] == offset]
            for operator in ('stochastic', 'calibrated'):
                metrics.append(dict(region=cell['region'], fold=cell['fold'], offset_steps=offset,
                    operator=operator, **common_metrics(values['truth'][idx], values[operator][idx])))
        for operator, mean in (('stochastic', None), ('calibrated', values['driver_mean'])):
            if mean is None:
                parent_packets = []
                for task in selected:
                    with np.load(Path(prep['r130_out']) / 'tasks_done' / task['parent_name'] /
                                 'predictions.npz', allow_pickle=False) as cached:
                        parent_packets.append(cached['driver_mean'][:, :, 0])
                mean = np.concatenate(parent_packets)[order]
            error = mean - values['truth']
            for lead in range(96):
                driver_rows.append(dict(region=cell['region'], fold=cell['fold'], operator=operator,
                    lead_step=lead + 1, bias=float(error[:, lead].mean()),
                    MAE=float(abs(error[:, lead]).mean()),
                    RMSE=float(np.sqrt(np.mean(error[:, lead] ** 2)))))
    heldout = pd.DataFrame(metrics); driver = pd.DataFrame(driver_rows); internal = pd.DataFrame(rows)
    summary = heldout.groupby(['region', 'operator'], as_index=False).mean(numeric_only=True)
    findings = []
    for region in prep['protocol']['regions']:
        part = summary[summary.region == region].set_index('operator')
        baseline, calibrated = part.loc['stochastic', 'AQL'], part.loc['calibrated', 'AQL']
        findings.append(dict(region=region, selected=decisions[region]['selected'],
            baseline_AQL=float(baseline), calibrated_AQL=float(calibrated),
            improvement_pct=float(100 * (baseline - calibrated) / baseline)))
    nonidentity = any(decisions[r]['selected'] != 'identity' for r in prep['protocol']['regions'])
    aggregate_improved = np.mean([f['calibrated_AQL'] for f in findings]) < np.mean([f['baseline_AQL'] for f in findings])
    additional_pilot = bool(nonidentity and aggregate_improved
        and all(f['improvement_pct'] > -1 for f in findings))
    interpretation = dict(status='R132_COMPLETE_NOT_PROMOTED', source=prep['source'],
        internal_selection_only=True, official_test_reforecast=False, new_fits=0,
        findings=findings, additional_region_pilot_supported=additional_pilot,
        all_region_rollout_authorized=False, authority_unchanged=True,
        decision=('bounded additional-region pilot may be planned' if additional_pilot else
                  'retain stochastic Normal driver; calibration does not justify expansion'))
    path.mkdir(); internal.to_csv(path / 'internal_forward_metrics.csv', index=False)
    heldout.to_csv(path / 'heldout_receiver_metrics.csv', index=False)
    summary.to_csv(path / 'region_summary.csv', index=False)
    driver.to_csv(path / 'driver_error_metrics.csv', index=False)
    write(path / 'interpretation.json', interpretation)
    plot_report(path / 'pricefm_r132_stochastic_driver_calibration.pdf', internal, heldout,
        driver, decisions)
    seal(path, dict(source=prep['source'], internal_rows=len(internal), heldout_rows=len(heldout)))
    return interpretation


def controller(workers):
    prep = read(PREP / 'preparation.json'); setup(prep['dependency'], prep['r128_source']); valid(prep, full=True)
    if not 1 <= workers <= prep['protocol']['maximum_workers']:
        raise ValueError('R132 worker cap exceeded')
    with (OUT / 'controller.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if (OUT / 'terminal.json').exists():
            verified(OUT / 'closeout'); return
        if (OUT / 'staging').exists() and list((OUT / 'staging').iterdir()):
            raise RuntimeError('unsealed R132 partial task requires inspection')
        cpus = cpu_pool(workers); resources(prep['protocol'])
        (OUT / 'worker_logs').mkdir(exist_ok=True)
        write(OUT / 'controller_identity.json', dict(pid=os.getpid(), host=socket.gethostname(),
            cpus=cpus, source=prep['source'], epoch=time.time()))
        try:
            batch(prep['internal_tasks'], cpus[:6], prep, 'internal_baseline_replay')
            evaluations = forward_tasks(prep)
            immutable(OUT / 'forward_tasks.json', evaluations)
            batch(evaluations, cpus[:min(len(cpus), 12)], prep, 'forward_internal_calibration')
            decisions, rows = choose_maps(prep, evaluations)
            heldout = heldout_tasks(prep, decisions); register(heldout)
            immutable(OUT / 'heldout_tasks.json', heldout)
            smoke = [task for task in heldout if task['smoke']]
            batch(smoke, cpus[:min(len(cpus), len(smoke))], prep, 'heldout_first_origin_smoke')
            immutable(OUT / 'smoke_gate.json', dict(passed=True, tasks=len(smoke), source=prep['source']))
            batch(heldout, cpus, prep, 'heldout_calibrated_receiver_replay')
            valid(prep, full=True); result = closeout(prep, rows, decisions, heldout)
            hashes = dict(prep['source_sha256']); hashes.update(prep['input_sha256'])
            for task in [*prep['internal_tasks'], *evaluations, *heldout]:
                folder = OUT / 'tasks_done' / task['name']; verified(folder)
                for file in folder.rglob('*'):
                    if file.is_file(): hashes[str(file)] = digest(file)
            for file in (OUT / 'closeout').rglob('*'):
                if file.is_file(): hashes[str(file)] = digest(file)
            for file in [*(OUT / 'maps').glob('*.json'), OUT / 'internal_selection.json',
                         OUT / 'internal_forward_metrics.csv', OUT / 'smoke_gate.json',
                         OUT / 'forward_tasks.json', OUT / 'heldout_tasks.json']:
                if file.is_file(): hashes[str(file)] = digest(file)
            verify_hashes(hashes)
            write(OUT / 'frozen_handoff_manifest.json', dict(source=prep['source'], sha256=hashes,
                preparation_sha256=digest(PREP / 'preparation.json')))
            write(OUT / 'terminal.json', dict(status=result['status'], source=prep['source'],
                internal_tasks=18, heldout_tasks=len(heldout), failures=0, pending=0, new_fits=0))
        except Exception as error:
            write(OUT / 'blocked.json', dict(error=str(error), source=prep['source'],
                epoch=time.time(), automatic_patch=False, predecessor_untouched=True))
            raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('release', 'prepare', 'controller', 'worker'))
    for name in ('r131', 'r130', 'r128', 'dependency', 'release'):
        parser.add_argument('--' + name, type=Path)
    parser.add_argument('--workers', type=int, default=30); parser.add_argument('--name')
    parser.add_argument('--cpu', type=int)
    args = parser.parse_args()
    if args.action == 'release':
        print(release(args.dependency, args.r128, args.r131), flush=True)
    elif args.action == 'prepare':
        print(preparation(args.r131, args.r130, args.r128, args.dependency, args.release), flush=True)
    elif args.action == 'controller':
        controller(args.workers)
    else:
        worker(args.name, args.cpu)
