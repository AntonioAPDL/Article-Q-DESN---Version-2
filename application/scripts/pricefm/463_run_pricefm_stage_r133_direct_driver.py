#!/usr/bin/env python3
"""Run the source-gated R133 decoupled direct multi-horizon driver pilot."""
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
from pricefm_r133_direct_driver import (FAMILIES, LEVELS, augment_packet,
    average_quantile_loss, concatenate_packets, direct_quantiles, fit_direct_map,
    plot_report, replay_receiver, select_candidate, validate_protocol)

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
ENTRY = Path(__file__).resolve()
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
TAG = 'pricefm_stage_r133_direct_multihorizon_driver_20261011'
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
    if not branch.startswith('work/pricefm-r133-') or git(ROOT, 'status', '--porcelain'):
        raise RuntimeError('clean committed dedicated R133 source required')
    return dict(branch=branch, head=git(ROOT, 'rev-parse', 'HEAD'))


def setup(dependency, r128, r130, r132):
    global runtime, regional, r132_calibration, read, write, immutable, digest, seal
    global verified, verify_hashes, common_metrics, shifted_windows
    sys.path.insert(0, str(Path(dependency) / 'application/scripts/pricefm'))
    from pricefm_r126_contract import read, write, immutable, digest, seal, verified, verify_hashes
    from pricefm_r127_contract import common_metrics, shifted_windows
    import pricefm_r123_runtime as runtime
    regional = module('r133_frozen_regional_core',
        Path(r128) / 'application/scripts/pricefm/pricefm_r128_core.py')
    r132_calibration = module('r133_frozen_r132_calibration',
        Path(r132) / 'application/scripts/pricefm/pricefm_r132_calibration.py')


def load_preparation():
    return json.loads((PREP / 'preparation.json').read_text(encoding='utf-8'))


def release(dependency, r128, r130, r131, r132):
    source = identity(); target = DATA / 'runtime_audits' / TAG / (
        'release_' + socket.gethostname() + '_' + source['head'][:12])
    target.mkdir(parents=True, exist_ok=False)
    junit = target / 'pytest.xml'; env = dict(os.environ)
    env.update(PRICEFM_R133_DEPENDENCY=str(dependency), PRICEFM_R133_R128=str(r128),
        PRICEFM_R133_R130=str(r130), PRICEFM_R133_R131=str(r131), PRICEFM_R133_R132=str(r132),
        PRICEFM_R132_DEPENDENCY=str(dependency), PRICEFM_R132_R128=str(r128),
        PRICEFM_R132_R131=str(r131), PRICEFM_R131_DEPENDENCY=str(dependency))
    tests = [ROOT / 'application/tests/test_pricefm_stage_r133_direct_driver.py',
        Path(r132) / 'application/tests/test_pricefm_stage_r132_calibration.py',
        Path(r131) / 'application/tests/test_pricefm_stage_r131_seasonal.py',
        Path(dependency) / 'application/tests/test_pricefm_stage_r127_driver_diagnosis.py']
    with (target / 'pytest.log').open('w') as log:
        result = subprocess.run([sys.executable, '-B', '-m', 'pytest', '-q', *map(str, tests),
            '-p', 'no:cacheprovider', '--junitxml=' + str(junit)], cwd=ROOT, env=env,
            stdout=log, stderr=subprocess.STDOUT)
    suites = ET.parse(junit).getroot().findall('testsuite')
    totals = {key: sum(int(s.get(key, '0')) for s in suites)
              for key in ('tests', 'failures', 'errors', 'skipped')}
    receipt = dict(source=source, **totals, passed=result.returncode == 0
        and totals['tests'] >= 100 and sum(totals[k] for k in ('failures', 'errors', 'skipped')) == 0,
        dependency_heads=dict(r127=git(dependency, 'rev-parse', 'HEAD'),
            r128=git(r128, 'rev-parse', 'HEAD'), r130=git(r130, 'rev-parse', 'HEAD'),
            r131=git(r131, 'rev-parse', 'HEAD'), r132=git(r132, 'rev-parse', 'HEAD')))
    (target / 'validation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if not receipt['passed']:
        raise RuntimeError('R133 release failed: ' + str(target / 'pytest.log'))
    return dict(path=str(target / 'validation.json'), **receipt)


def _dependency_check(path, expected, key):
    if git(path, 'rev-parse', 'HEAD') != expected or git(path, 'status', '--porcelain'):
        raise RuntimeError('frozen dependency differs: ' + key)


def preparation(r132, r131, r130, r128, dependency, release_path):
    setup(dependency, r128, r130, r132); protocol = read(PROTOCOL); validate_protocol(protocol)
    source = identity()
    for path, key in ((r132, 'r132_head'), (r131, 'r131_head'), (r130, 'r130_head'),
                      (r128, 'r128_head'), (dependency, 'r127_head')):
        _dependency_check(path, protocol[key], key)
    receipt = read(release_path)
    if receipt['source'] != source or not receipt['passed']:
        raise RuntimeError('source-matched R133 release required')
    r128_out = DATA / 'campaigns/pricefm_stage_r128_stochastic_regional_pilots_20261008'
    r130_out = DATA / 'campaigns/pricefm_stage_r130_forecast_error_attribution_20261010'
    r132_out = DATA / 'campaigns/pricefm_stage_r132_stochastic_driver_calibration_20261011'
    r132_prep = DATA / 'launch_prep/pricefm_stage_r132_stochastic_driver_calibration_20261011/preparation.json'
    if read(r132_out / 'terminal.json')['status'] != 'R132_COMPLETE_NOT_PROMOTED':
        raise RuntimeError('R132 must be frozen complete')
    verified(r132_out / 'closeout'); parent = read(r132_prep)
    if parent['source']['head'] != protocol['r132_head']:
        raise RuntimeError('R132 lineage differs')
    inputs = {}; source_paths = [ENTRY, HERE / 'pricefm_r133_direct_driver.py', PROTOCOL,
        ROOT / 'application/notes/pricefm_stage_r133_direct_multihorizon_driver_20261011.md',
        ROOT / 'application/tests/test_pricefm_stage_r133_direct_driver.py']
    for path in (r132_prep, r132_out / 'terminal.json', r132_out / 'frozen_handoff_manifest.json'):
        inputs[str(path)] = digest(path)
    internal = []
    for cell in parent['internal_cells']:
        item = dict(cell); name = f"internal_{item['region']}_s{item['split']}"
        internal.append(dict(name=name, kind='internal', **item))
        for path in (Path(item['bank']), Path(item['fit']) / 'terminal.json',
                     Path(item['fit']) / 'beta_mean.bin', Path(item['fit']) / 'beta_cov.bin'):
            inputs[str(path)] = digest(path)
    heldout_cells = parent['heldout_cells']; heldout = []
    for task in parent['heldout_parent_tasks']:
        heldout.append(dict(name='heldout_' + task['name'], parent_name=task['name'],
            kind='heldout', region=task['region'], fold=task['fold'], offset=task['offset'],
            bank_indices=task['bank_indices'], positions=task['positions'], smoke=task['smoke']))
    for cell in heldout_cells:
        for path in (Path(cell['bank']), Path(cell['normal_dir']) / 'terminal.json',
                     Path(cell['normal_dir']) / 'beta_mean.bin', Path(cell['normal_dir']) / 'beta_cov.bin'):
            inputs[str(path)] = digest(path)
        for folder in cell['quantile_dirs'].values():
            for name in ('terminal.json', 'beta_mean.bin', 'beta_cov.bin'):
                path = Path(folder) / name; inputs[str(path)] = digest(path)
    for task in parent['heldout_parent_tasks']:
        path = r130_out / 'tasks_done' / task['name'] / 'predictions.npz'
        inputs[str(path)] = digest(path)
    prep = dict(source=source, protocol=protocol, dependency=str(dependency),
        r128_source=str(r128), r130_source=str(r130), r131_source=str(r131),
        r132_source=str(r132), r128_out=str(r128_out), r130_out=str(r130_out),
        r132_out=str(r132_out), release=str(release_path), release_sha256=digest(release_path),
        source_sha256={str(path): digest(path) for path in source_paths}, input_sha256=inputs,
        internal_cells=parent['internal_cells'], heldout_cells=heldout_cells,
        internal_tasks=internal, heldout_tasks=heldout, official_test_reforecast=False,
        normal_or_quantile_refits=0, direct_maps_to_fit=2)
    immutable(PREP / 'preparation.json', prep)
    for task in [*internal, *heldout]:
        immutable(OUT / 'tasks' / (task['name'] + '.json'), task)
    return dict(status='R133_PREPARED', internal_tasks=len(internal),
        heldout_tasks=len(heldout), direct_maps=2, maximum_workers=protocol['maximum_workers'])


def valid(prep, full=False):
    if identity() != prep['source'] or read(PROTOCOL) != prep['protocol']:
        raise RuntimeError('R133 source or protocol changed')
    verify_hashes(prep['source_sha256'])
    if full: verify_hashes(prep['input_sha256'])
    for path, key in ((prep['r132_source'], 'r132_head'), (prep['r131_source'], 'r131_head'),
                      (prep['r130_source'], 'r130_head'), (prep['r128_source'], 'r128_head'),
                      (prep['dependency'], 'r127_head')):
        if git(path, 'rev-parse', 'HEAD') != prep['protocol'][key]:
            raise RuntimeError('frozen dependency head changed: ' + key)


def resources(protocol, allowance=0.):
    memory = {row.split(':')[0]: int(row.split()[1]) * 1024
              for row in Path('/proc/meminfo').read_text().splitlines()}
    free = shutil.disk_usage(DATA).free / 2**30
    used = sum(path.stat().st_size for path in OUT.rglob('*') if path.is_file()) / 2**30
    if (memory['MemAvailable'] / 2**30 < protocol['minimum_free_memory_GiB']
            or free < protocol['minimum_free_disk_GiB'] + allowance
            or used + allowance > protocol['maximum_campaign_output_GiB']):
        raise RuntimeError('R133 resource reserve reached; completed evidence retained')
    return dict(available_memory_GiB=memory['MemAvailable'] / 2**30,
        free_disk_GiB=free, campaign_GiB=used)


def _internal_packet(prep, task, observe):
    arrays = regional.load_arrays(runtime, Path(task['bank']))
    split = runtime.internal_splits(len(arrays.response))[task['split'] - 1]
    scaled, _ = runtime.standardize_from_training_origins(arrays, split['train'])
    fit = runtime.load_normal_fit(Path(task['fit'])); idx = split['validation']
    selected = np.unique(np.linspace(0, len(idx) - 2,
        prep['protocol']['origins_per_clock']).round().astype(int))
    identity_map = dict(mode='identity', global_bias=0., hour_effect=[0.] * 24,
        lead_block_effect=[0.] * 4, lead_block_scale=[1.] * 4)
    packets = []
    base_seed = runtime.BASE.deterministic_seed(2026100801, task['region'], task['split'])
    for offset in prep['protocol']['origin_offsets_steps']:
        shifted = shifted_windows(scaled, idx[selected], offset, idx)
        packet, _ = r132_calibration.normal_driver_paths(runtime, shifted, task['spec'], fit,
            selected, runtime.BASE.deterministic_seed(base_seed, 'clock', offset), identity_map,
            price_scale=1., observe=observe)
        packets.append(augment_packet(shifted, packet, prep['protocol']['history_lags']))
    return concatenate_packets(packets)


def worker(name, cpu):
    prep = load_preparation(); setup(prep['dependency'], prep['r128_source'],
        prep['r130_source'], prep['r132_source']); valid(prep)
    os.sched_setaffinity(0, {cpu}); task = read(OUT / 'tasks' / (name + '.json'))
    destination = OUT / 'tasks_done' / name
    if destination.exists(): verified(destination); return
    beat = lambda value: write(OUT / 'heartbeats' / (name + '.json'),
        dict(value, cpu=cpu, epoch=time.time()))
    start = time.time(); (OUT / 'staging').mkdir(exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix=name + '.', dir=OUT / 'staging'))
    if task['kind'] == 'internal':
        packet = _internal_packet(prep, task, beat)
        np.savez_compressed(tmp / 'driver.npz', **packet)
        result = dict(certified=True, region=task['region'], split=task['split'],
            baseline_AQL=average_quantile_loss(packet['truth'], packet['prediction']),
            response_standardized_on_training_only=True, fitting_performed=False)
    elif task['kind'] == 'heldout':
        cell = next(value for value in prep['heldout_cells']
                    if (value['region'], value['fold']) == (task['region'], task['fold']))
        arrays = runtime.subset_arrays(regional.load_arrays(runtime, Path(cell['bank'])),
                                       task['bank_indices'])
        model = read(OUT / 'maps' / (task['region'] + '_final.json'))
        normal = runtime.load_normal_fit(Path(cell['normal_dir']))
        quantiles = {float(q): runtime.load_quantile_fit(Path(folder))
                     for q, folder in cell['quantile_dirs'].items()}
        seed = runtime.BASE.deterministic_seed(2026101001, task['region'], task['fold'], 'validation')
        values, audit = replay_receiver(runtime, arrays, cell['spec'], quantiles, normal,
            task['positions'], seed, model, observe=beat)
        scaler = cell['scaler']
        values['direct'] = values['direct'] * scaler['price_scale'] + scaler['price_mean']
        for key in ('baseline_driver_mean', 'direct_driver_mean'):
            values[key] = values[key] * scaler['price_scale'] + scaler['price_mean']
        for key in ('baseline_driver_sd', 'direct_driver_sd'):
            values[key] = values[key] * scaler['price_scale']
        parent = Path(prep['r130_out']) / 'tasks_done' / task['parent_name'] / 'predictions.npz'
        with np.load(parent, allow_pickle=False) as cached:
            for key in ('stochastic', 'truth', 'positions', 'bank_indices', 'anchors_ns'):
                values[key] = cached[key]
        first = float(np.max(abs(values['direct'][:, 0] - values['stochastic'][:, 0])))
        if first > 1e-8: raise RuntimeError('R133 first-step receiver identity failed')
        np.savez_compressed(tmp / 'predictions.npz', **values)
        result = dict(certified=True, region=task['region'], fold=task['fold'],
            first_step_difference=first, direct_family=model['family'], fitting_performed=False,
            official_test_opened=False, audit=audit)
    else:
        raise ValueError('unknown R133 task kind')
    write(tmp / 'result.json', result)
    seal(tmp, dict(source=prep['source'], task_sha256=digest(OUT / 'tasks' / (name + '.json')),
        task=task, elapsed_seconds=time.time() - start, certified=True))
    destination.parent.mkdir(exist_ok=True)
    if destination.exists(): raise RuntimeError('duplicate R133 task writer')
    tmp.rename(destination)


def complete(task):
    folder = OUT / 'tasks_done' / task['name']
    if (folder / 'completed_evidence.json').exists(): verified(folder); return True
    return False


def cpu_pool(count, busy_limit=.35):
    if not 1 <= count <= 30: raise ValueError('R133 worker count must be 1..30')
    def ticks():
        answer = {}
        for line in Path('/proc/stat').read_text().splitlines():
            words = line.split()
            if words[0].startswith('cpu') and words[0][3:].isdigit():
                values = list(map(int, words[1:9])); answer[int(words[0][3:])] = (sum(values), values[3] + values[4])
        return answer
    before = ticks(); time.sleep(2); after = ticks(); rows = []
    for cpu in os.sched_getaffinity(0):
        total = after[cpu][0] - before[cpu][0]; idle = after[cpu][1] - before[cpu][1]
        topology = Path(f'/sys/devices/system/cpu/cpu{cpu}/topology')
        physical = ((topology / 'physical_package_id').read_text().strip(),
                    (topology / 'core_id').read_text().strip())
        rows.append((1 - idle / max(total, 1), cpu, physical))
    selected, used = [], set()
    for busy, cpu, physical in sorted(rows):
        if busy < busy_limit and physical not in used:
            selected.append(cpu); used.add(physical)
        if len(selected) == count: break
    if not selected: raise RuntimeError('no sufficiently idle physical core')
    return selected


def batch(tasks, cpus, prep, stage):
    pending = [task for task in tasks if not complete(task)]; active = {}; free = list(cpus)
    failures = []; resource_error = None
    while pending or active:
        try: snapshot = resources(prep['protocol'], .02 * (len(active) + 1))
        except RuntimeError as error: resource_error = str(error); snapshot = {}
        while pending and free and not failures and not resource_error:
            task = pending.pop(0); cpu = free.pop(0)
            stream = (OUT / 'worker_logs' / (task['name'] + '.log')).open('a')
            process = subprocess.Popen([sys.executable, '-B', str(ENTRY), 'worker', '--name',
                task['name'], '--cpu', str(cpu)], stdout=stream, stderr=subprocess.STDOUT,
                start_new_session=True)
            active[task['name']] = (process, cpu, stream)
        for name, (process, cpu, stream) in list(active.items()):
            code = process.poll()
            if code is None: continue
            stream.close(); free.append(cpu); del active[name]
            if code: failures.append(dict(task=name, exit_code=code))
        write(OUT / 'progress.json', dict(stage=stage, active=len(active), pending=len(pending),
            completed=sum(complete(task) for task in tasks), stage_total=len(tasks),
            failures=failures, resource_error=resource_error, resources=snapshot, epoch=time.time()))
        if not active and (failures or resource_error): raise RuntimeError(str(failures or resource_error))
        if pending or active: time.sleep(3)


def load_internal(region, split):
    folder = OUT / 'tasks_done' / f'internal_{region}_s{split}'; verified(folder)
    with np.load(folder / 'driver.npz', allow_pickle=False) as values:
        return {key: values[key] for key in values.files}


def freeze_maps(prep):
    rows = []; decisions = {}; (OUT / 'maps').mkdir(exist_ok=True)
    for region in prep['protocol']['regions']:
        packets = {split: load_internal(region, split) for split in prep['protocol']['internal_splits']}
        candidates = {'identity': dict(family='identity', ridge_penalty=None)}
        for family in FAMILIES[1:]:
            for penalty in prep['protocol']['ridge_penalties']:
                key = family + '_l' + str(penalty).replace('.', 'p')
                candidates[key] = dict(family=family, ridge_penalty=penalty)
        for split in prep['protocol']['forward_evaluation_splits']:
            training = list(range(1, split))
            for candidate_id, candidate in candidates.items():
                model = fit_direct_map([packets[value] for value in training],
                    candidate['family'], candidate['ridge_penalty'], prep['protocol'], training)
                prediction = direct_quantiles(packets[split], model)
                metrics = common_metrics(packets[split]['truth'], prediction)
                rows.append(dict(region=region, split=split, candidate_id=candidate_id,
                    family=candidate['family'], ridge_penalty=candidate['ridge_penalty'],
                    feature_dimension=model['feature_dimension'],
                    scale_enabled=candidate['family'].endswith('_scale'), **metrics))
        decision = select_candidate([row for row in rows if row['region'] == region], prep['protocol'])
        candidate = candidates[decision['selected']]
        model = fit_direct_map(list(packets.values()), candidate['family'],
            candidate['ridge_penalty'], prep['protocol'], prep['protocol']['internal_splits'])
        path = OUT / 'maps' / (region + '_final.json'); immutable(path, model)
        decision.update(region=region, model=str(path), model_sha256=digest(path))
        decisions[region] = decision
    immutable(OUT / 'internal_selection.json', decisions)
    pd.DataFrame(rows).to_csv(OUT / 'internal_forward_metrics.csv', index=False)
    return decisions, rows


def _combine(tasks):
    packets = []
    for task in tasks:
        folder = OUT / 'tasks_done' / task['name']; verified(folder)
        with np.load(folder / 'predictions.npz', allow_pickle=False) as values:
            packets.append({key: values[key] for key in values.files})
    values = {key: np.concatenate([packet[key] for packet in packets]) for key in packets[0]}
    order = np.argsort(values['bank_indices'])
    return {key: value[order] for key, value in values.items()}


def closeout(prep, rows, decisions):
    target = OUT / 'closeout'
    if target.exists(): verified(target); return read(target / 'interpretation.json')
    metrics = []; driver_rows = []
    for cell in prep['heldout_cells']:
        tasks = [task for task in prep['heldout_tasks']
                 if (task['region'], task['fold']) == (cell['region'], cell['fold'])]
        values = _combine(tasks)
        for offset in prep['protocol']['origin_offsets_steps']:
            idx = [i for i, row in enumerate(cell['grid']) if row['offset'] == offset]
            for operator in ('stochastic', 'direct'):
                metrics.append(dict(region=cell['region'], fold=cell['fold'], offset_steps=offset,
                    operator=operator, **common_metrics(values['truth'][idx], values[operator][idx])))
        for operator, mean in (('stochastic', values['baseline_driver_mean']),
                               ('direct', values['direct_driver_mean'])):
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
        part = summary[summary.region.eq(region)].set_index('operator')
        base, direct = part.loc['stochastic', 'AQL'], part.loc['direct', 'AQL']
        findings.append(dict(region=region, selected=decisions[region]['selected'],
            baseline_AQL=float(base), direct_AQL=float(direct),
            improvement_pct=float(100 * (base - direct) / base)))
    supported = bool(any(decisions[r]['selected'] != 'identity' for r in decisions)
        and np.mean([f['direct_AQL'] for f in findings]) < np.mean([f['baseline_AQL'] for f in findings])
        and all(f['improvement_pct'] > -1 for f in findings))
    interpretation = dict(status='R133_COMPLETE_NOT_PROMOTED', source=prep['source'],
        findings=findings, forward_internal_selection_only=True,
        additional_region_pilot_supported=supported, all_region_rollout_authorized=False,
        authority_unchanged=True, official_test_reforecast=False,
        decision=('bounded additional-region pilot may be planned' if supported else
                  'retain frozen stochastic Normal driver; no expansion justified'))
    target.mkdir(); internal.to_csv(target / 'internal_forward_metrics.csv', index=False)
    heldout.to_csv(target / 'heldout_receiver_metrics.csv', index=False)
    summary.to_csv(target / 'region_summary.csv', index=False)
    driver.to_csv(target / 'driver_error_metrics.csv', index=False)
    write(target / 'interpretation.json', interpretation)
    plot_report(target / 'pricefm_r133_direct_multihorizon_driver.pdf', internal, heldout,
        driver, decisions)
    seal(target, dict(source=prep['source'], internal_rows=len(internal), heldout_rows=len(heldout)))
    return interpretation


def controller(workers):
    prep = load_preparation(); setup(prep['dependency'], prep['r128_source'],
        prep['r130_source'], prep['r132_source']); valid(prep, full=True)
    with (OUT / 'controller.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if (OUT / 'terminal.json').exists(): verified(OUT / 'closeout'); return
        if (OUT / 'staging').exists() and list((OUT / 'staging').iterdir()):
            raise RuntimeError('unsealed R133 partial task requires inspection')
        cpus = cpu_pool(workers); resources(prep['protocol']); (OUT / 'worker_logs').mkdir(exist_ok=True)
        write(OUT / 'controller_identity.json', dict(pid=os.getpid(), host=socket.gethostname(),
            cpus=cpus, source=prep['source'], epoch=time.time()))
        try:
            batch(prep['internal_tasks'], cpus[:6], prep, 'internal_baseline_packets')
            decisions, rows = freeze_maps(prep)
            smoke = [task for task in prep['heldout_tasks'] if task['smoke']]
            batch(smoke, cpus[:min(len(cpus), len(smoke))], prep, 'heldout_smoke')
            immutable(OUT / 'smoke_gate.json', dict(passed=True, tasks=len(smoke), source=prep['source']))
            batch(prep['heldout_tasks'], cpus, prep, 'heldout_direct_receiver_replay')
            valid(prep, full=True); result = closeout(prep, rows, decisions)
            hashes = dict(prep['source_sha256']); hashes.update(prep['input_sha256'])
            for task in [*prep['internal_tasks'], *prep['heldout_tasks']]:
                folder = OUT / 'tasks_done' / task['name']; verified(folder)
                for file in folder.rglob('*'):
                    if file.is_file(): hashes[str(file)] = digest(file)
            for folder in (OUT / 'maps', OUT / 'closeout'):
                for file in folder.rglob('*'):
                    if file.is_file(): hashes[str(file)] = digest(file)
            for file in (OUT / 'internal_selection.json', OUT / 'internal_forward_metrics.csv',
                         OUT / 'smoke_gate.json'):
                hashes[str(file)] = digest(file)
            verify_hashes(hashes)
            write(OUT / 'frozen_handoff_manifest.json', dict(source=prep['source'], sha256=hashes,
                preparation_sha256=digest(PREP / 'preparation.json')))
            write(OUT / 'terminal.json', dict(status=result['status'], source=prep['source'],
                internal_tasks=len(prep['internal_tasks']), heldout_tasks=len(prep['heldout_tasks']),
                failures=0, pending=0, normal_or_quantile_refits=0, direct_maps=2))
        except Exception as error:
            write(OUT / 'blocked.json', dict(error=str(error), source=prep['source'],
                epoch=time.time(), automatic_patch=False, predecessor_untouched=True))
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('release', 'prepare', 'controller', 'worker'))
    for name in ('r132', 'r131', 'r130', 'r128', 'dependency', 'release'):
        parser.add_argument('--' + name, type=Path)
    parser.add_argument('--workers', type=int, default=30); parser.add_argument('--name')
    parser.add_argument('--cpu', type=int)
    args = parser.parse_args()
    if args.action == 'release':
        print(release(args.dependency, args.r128, args.r130, args.r131, args.r132), flush=True)
    elif args.action == 'prepare':
        print(preparation(args.r132, args.r131, args.r130, args.r128, args.dependency,
                          args.release), flush=True)
    elif args.action == 'controller': controller(args.workers)
    else: worker(args.name, args.cpu)


if __name__ == '__main__':
    main()
