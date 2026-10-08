#!/usr/bin/env python3
"""Frozen-fit R127 diagnostics: prepare, bounded smoke gate, replay, closeout."""
from __future__ import annotations

import argparse
import fcntl
import importlib.util
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

for name in ('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS',
             'BLIS_NUM_THREADS', 'NUMEXPR_NUM_THREADS', 'R_DATATABLE_NUM_THREADS'):
    os.environ[name] = '1'
os.environ['PYTHONDONTWRITEBYTECODE'] = '1'

import numpy as np
import pandas as pd

from pricefm_r126_contract import (digest, read, write, immutable, seal, verified,
    verify_hashes, inverse_price, transform, official_origins, market_ns)
from pricefm_r126_fullfold import raw_frame, arrays_from_raw
from pricefm_r125_cdf import origin_positions
from pricefm_r127_contract import shifted_windows, window_identity
from pricefm_r127_forecast import replay

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
TAG = 'pricefm_stage_r127_driver_diagnosis_20261008'
OUT = DATA / 'campaigns' / TAG
PREP = DATA / 'launch_prep' / TAG
PROTOCOL = ROOT / 'application/config/pricefm_stage_r127_driver_diagnosis_protocol_20261008.json'
PLAN = ROOT / 'local_trackers/pricefm_post_r126_oracle_driver_promotion_master_plan_20261008.md'


def parent_module():
    loader = importlib.util.spec_from_file_location('r127_readonly_parent', HERE / '447_run_pricefm_stage_r126_matched_comparison.py')
    module = importlib.util.module_from_spec(loader); loader.loader.exec_module(module)
    return module


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def identity():
    if not git('branch', '--show-current').startswith('work/pricefm-r127-') or git('status', '--porcelain'):
        raise RuntimeError('clean committed dedicated R127 worktree required')
    return dict(head=git('rev-parse', 'HEAD'), branch=git('branch', '--show-current'))


def task_schedule(jobs, protocol, official_protocol):
    rows = []
    def chunks(kind, positions, **values):
        size = protocol['official_chunk_origins' if kind == 'official' else 'internal_chunk_origins']
        pieces = [positions[:1]] + [positions[i:i + size] for i in range(1, len(positions), size)]
        for chunk, piece in enumerate(pieces):
            name = kind + '_' + '_'.join(str(values[k]) for k in sorted(values)) + f'_c{chunk:03d}'
            rows.append(dict(name=name, kind=kind, positions=list(map(int, piece)), smoke=chunk == 0, **values))
    for fold in (1, 2, 3):
        chunks('official', list(range(len(official_origins(official_protocol, fold)))), fold=fold)
    for job in jobs:
        for offset in protocol['internal_offsets_steps']:
            positions = (job['origin_positions'] if not offset else list(map(int,
                origin_positions(job['complete_origin_count'] - 1, protocol['internal_origins_per_offset_split']))))
            chunks('internal', positions, split=job['split'], offset=offset, seed=job['seed'])
    for seed in protocol['mc_repeat_seeds']:
        rows.append(dict(name=f'mc_s{protocol["mc_repeat_split"]}_{seed}', kind='mc', smoke=False,
            split=protocol['mc_repeat_split'], offset=0, seed=seed, positions=protocol['mc_repeat_positions']))
    return rows


def prepare(receipt, reference):
    protocol = read(PROTOCOL); source = identity(); release = read(receipt)
    if (release['source_head'] != source['head'] or release['failures'] or release['errors'] or release['skipped']
            or release['r_suites'] != 4 or release['python_tests'] < 510):
        raise RuntimeError('source-matched full Python and pinned R release required')
    verify_hashes(release['evidence_sha256'])
    if digest(PLAN) != protocol['planning_document_sha256']: raise RuntimeError('frozen planning baseline changed')
    if digest(reference) != protocol['reference_fold_metrics_sha256']: raise RuntimeError('comparison reference differs')
    if digest(DATA / 'raw/FINAL.csv') != protocol['parent_final_sha256']: raise RuntimeError('raw source differs')
    parent = DATA / 'campaigns' / protocol['parent_tag']
    terminal = read(parent / 'terminal.json')
    if (terminal['source']['head'] != protocol['parent_head'] or terminal['full_fits'] != 24
            or terminal['official_origins'] != 365 or terminal['official_test_used_for_selection']):
        raise RuntimeError('finished parent provenance differs')
    for fold in (1, 2, 3): verified(parent / f'official/fold={fold}')
    choice = read(parent / 'frozen_choice.json')
    if choice['candidate_id'] != protocol['candidate_id']:
        raise RuntimeError('R126 frozen candidate differs')
    if digest(parent / 'frozen_choice.json') != protocol['parent_choice_sha256']:
        raise RuntimeError('R126 frozen specification differs')
    fit_seals = {}
    for fold in (1, 2, 3):
        full = parent / f'full/fold={fold}'
        for folder in [full / 'design', full / 'normal',
                       *[full / f'al/tau={q:.2f}' for q in protocol['quantiles']]]:
            verified(folder)
            fit_seals[str(folder / 'completed_evidence.json')] = digest(folder / 'completed_evidence.json')
    prior = parent_module()
    m, control, all_jobs = prior.runtime()
    jobs = [j for j in all_jobs if j['candidate_id'] == protocol['candidate_id']]
    if sorted(j['split'] for j in jobs) != [1, 2, 3]: raise RuntimeError('three matching internal fits required')
    for job in jobs: verify_hashes(job['input_sha256'])
    official_protocol = read(HERE.parents[1] / 'config/pricefm_stage_r126_matched_comparison_protocol_20261007.json')
    inherited_changed = [name for name in git('diff', '--name-only', protocol['parent_head'], 'HEAD').splitlines()
        if name and subprocess.run(['git', 'cat-file', '-e', protocol['parent_head'] + ':' + name],
            cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0]
    if inherited_changed: raise RuntimeError('existing parent files must remain untouched: ' + str(inherited_changed))
    sources = [PROTOCOL, Path(__file__), ROOT / 'application/tests/test_pricefm_stage_r127_driver_diagnosis.py']
    sources += list(HERE.glob('pricefm_r127_*.py'))
    hashes = {str(p): digest(p) for p in sources}
    inputs = {str(p): digest(p) for p in [PLAN, reference, parent / 'terminal.json',
        parent / 'frozen_choice.json', DATA / 'raw/FINAL.csv',
        DATA / 'launch_prep' / protocol['parent_tag'] / 'preparation.json']}
    inputs.update(fit_seals)
    schedule = task_schedule(jobs, protocol, official_protocol)
    prep = dict(source=source, protocol=protocol, official_protocol=official_protocol, jobs=jobs, tasks=schedule,
        source_sha256=hashes, input_sha256=inputs, reference=str(reference), release=str(receipt),
        release_sha256=digest(receipt), parent=str(parent), choice=choice,
        reused_full_fits=24, reused_internal_fits=24, new_fits=0, official_origins=365,
        internal_primary_origins=144, internal_mc_origins=6,
        window_adapter='adjacent frozen windows; exact original scaler/float32 lineage retained',
        inner_target_only_affine_scaling_cancels_outer_scaling_algebraically=True,
        float32_outer_quantization_retained=True, internal_units='outer fold-1 scaled price, not EUR/MWh',
        internal_stationarity_scope='inherited partial-fit formal gates; not a new complete latent-factor certificate')
    immutable(PREP / 'preparation.json', prep)
    for task in schedule:
        immutable(OUT / 'tasks' / (task['name'] + '.json'), dict(task, source_head=source['head']))
    immutable(PREP / 'schedule.json', dict(tasks=schedule, task_count=len(schedule),
        smoke_tasks=sum(t['smoke'] for t in schedule), combined_workers=protocol['workers'], new_fits=0,
        zero_offset_outputs_reuse_R125=True, state_moments_require_replay_because_not_previously_saved=True))
    return dict(status='R127_PREPARED', tasks=len(schedule), new_fits=0)


def input_valid():
    prep = read(PREP / 'preparation.json')
    if identity() != prep['source'] or read(PROTOCOL) != prep['protocol']:
        raise RuntimeError('frozen R127 source/protocol differs')
    verify_hashes(prep['source_sha256']); verify_hashes(prep['input_sha256'])
    expected = {t['name']: dict(t, source_head=prep['source']['head']) for t in prep['tasks']}
    actual = {p.stem: read(p) for p in (OUT / 'tasks').glob('*.json')}
    if actual != expected: raise RuntimeError('scheduled tasks were removed or changed')
    if digest(prep['release']) != prep['release_sha256']: raise RuntimeError('release evidence changed')
    return prep


def execute(task, prep, observe):
    m, control, _ = parent_module().runtime(); protocol = prep['protocol']
    if task['kind'] == 'official':
        fold = task['fold']; full = Path(prep['parent']) / f'full/fold={fold}'
        verified(full / 'design')
        verified(full / 'normal')
        quantile_paths = {float(q): full / f'al/tau={q:.2f}' for q in protocol['quantiles']}
        for p in quantile_paths.values(): verified(p)
        scalers = read(full / 'design/scalers.json')
        positions = np.array(task['positions'])
        origins = official_origins(prep['official_protocol'], fold)[positions]
        arrays = arrays_from_raw(m.RT, raw_frame(DATA, prep['official_protocol']['test_intervals_market'][fold - 1][1]),
            origins, scalers['outer'], dict(raw_sha256=protocol['parent_final_sha256']))
        scaled = transform(arrays, scalers['inner'], m.RT.BASE.ExplicitArrays)
        values, audit = replay(m.RT, scaled, prep['choice']['spec'],
            {q: m.RT.load_quantile_fit(p) for q, p in quantile_paths.items()}, positions,
            2026100700 + fold, oracle_only=True, observe=observe)
        values = {k: inverse_price(v, scalers['inner'], scalers['outer']) for k, v in values.items()}
        verified(Path(prep['parent']) / f'official/fold={fold}')
        with np.load(Path(prep['parent']) / f'official/fold={fold}/predictions.npz', allow_pickle=False) as ref:
            np.testing.assert_array_equal(values['truth'], ref['truth'][positions])
            if not np.allclose(values['oracle'][:, 0], ref['cdf_pool_clipped'][positions, 0], rtol=2e-12, atol=1e-8):
                raise RuntimeError('same-fit oracle first-step differs from frozen causal control')
        values.update(positions=positions, anchors_ns=market_ns(origins))
        audit['units'] = 'EUR/MWh'
        return values, audit
    job = next(j for j in prep['jobs'] if j['split'] == task['split'])
    verify_hashes(job['input_sha256'])
    spec = m.RT.normalize_spec(dict(job['spec'], seed=job['source_reservoir_seed']))
    arrays = m.B._selection_arrays(control, spec)
    split = m.RT.internal_splits(len(arrays.response))[job['split'] - 1]
    scaled, scaler = m.RT.standardize_from_training_origins(arrays, split['train'])
    positions = np.array(task['positions']); indices = split['validation'][positions]
    shifted = shifted_windows(scaled, indices, task['offset'], split['validation'])
    cutoffs = window_identity(shifted, pd.to_datetime(arrays.anchors[split['validation'][0]], utc=True),
        pd.to_datetime(arrays.anchors[split['validation'][-1]], utc=True) + pd.Timedelta(days=1))
    cached = None
    if task['offset'] == 0 and task['kind'] == 'internal':
        with np.load(Path(job['output_dir']) / 'predictions.npz', allow_pickle=False) as reference:
            indexes = [job['origin_positions'].index(int(p)) for p in positions]
            cached = {key: (reference[old][indexes] - scaler['price_mean']) / scaler['price_scale']
                for key, old in [('stochastic', 'cdf_pool_clipped'), ('oracle', 'oracle_cdf_clipped')]}
    values, audit = replay(m.RT, shifted, spec,
        {float(q): m.RT.load_quantile_fit(Path(p)) for q, p in job['quantile_dirs'].items()},
        positions, task['seed'], m.RT.load_normal_fit(Path(job['normal_dir'])), observe=observe, cached=cached)
    for key in ('truth', 'stochastic', 'parameter_only', 'mean_driver', 'oracle', 'driver_mean'):
        values[key] = values[key] * scaler['price_scale'] + scaler['price_mean']
    values['driver_sd'] *= scaler['price_scale']
    values['median_variance_terms'] *= scaler['price_scale']**2
    if cached:
        with np.load(Path(job['output_dir']) / 'predictions.npz', allow_pickle=False) as reference:
            np.testing.assert_allclose(values['truth'], reference['truth'][indexes], rtol=2e-12, atol=1e-9)
    values.update(positions=positions, anchors_ns=market_ns(shifted.anchors))
    audit.update(training_cutoffs=cutoffs, units='outer fold-1 scaled price', offset_steps=task['offset'],
        cached_00_forecasts_reused=cached is not None)
    verify_hashes(job['input_sha256'])
    return values, audit


def worker(path, cpu):
    if not path.resolve().is_relative_to((OUT / 'tasks').resolve()): raise ValueError('task outside campaign')
    os.sched_setaffinity(0, {cpu}); prep = input_valid(); task = read(path)
    if task['source_head'] != prep['source']['head']: raise RuntimeError('task source differs')
    output = OUT / 'tasks_done' / task['name']
    if verified(output): return
    beat = lambda value: write(OUT / 'heartbeats' / (task['name'] + '.json'), dict(value, epoch=time.time()))
    started = time.time(); values, audit = execute(task, prep, beat)
    (OUT / 'staging').mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=task['name'] + '.', dir=OUT / 'staging'))
    np.savez_compressed(temporary / 'predictions.npz', **values)
    write(temporary / 'audit.json', audit)
    seal(temporary, dict(task=task, elapsed_seconds=time.time() - started, cpu=cpu))
    if output.exists(): raise RuntimeError('another writer created task output')
    output.parent.mkdir(parents=True, exist_ok=True); temporary.rename(output)


def resources(protocol):
    mem = {line.split(':')[0]: int(line.split()[1]) for line in Path('/proc/meminfo').read_text().splitlines()}
    stat = os.statvfs(DATA)
    used = sum(p.stat().st_size for p in OUT.rglob('*') if p.is_file())
    if (mem['MemAvailable'] * 1024 < protocol['minimum_free_memory_GiB'] * 2**30
            or stat.f_bavail * stat.f_frsize < protocol['minimum_free_disk_GiB'] * 2**30
            or used > protocol['maximum_campaign_output_GiB'] * 2**30):
        raise RuntimeError('resource reserve reached; drain own workers and retain pending tasks')
    return dict(available_memory_GiB=mem['MemAvailable'] / 2**20,
        free_disk_GiB=stat.f_bavail * stat.f_frsize / 2**30, output_bytes=used)


def cpu_pool(count):
    if not 1 <= count <= 15: raise ValueError('worker count must be between 1 and 15')
    def ticks():
        result = {}
        for line in Path('/proc/stat').read_text().splitlines():
            w = line.split()
            if w[0].startswith('cpu') and w[0][3:].isdigit():
                v = list(map(int, w[1:9])); result[int(w[0][3:])] = (sum(v), v[3] + v[4])
        return result
    before = ticks(); time.sleep(5); after = ticks(); groups = {}
    for cpu in os.sched_getaffinity(0):
        base = Path(f'/sys/devices/system/cpu/cpu{cpu}/topology')
        key = ((base / 'physical_package_id').read_text(), (base / 'core_id').read_text())
        total = after[cpu][0] - before[cpu][0]; idle = after[cpu][1] - before[cpu][1]
        groups.setdefault(key, []).append((1 - idle / max(total, 1), cpu))
    available = sorted((max(v[0] for v in siblings), min(siblings)[1])
        for siblings in groups.values() if max(v[0] for v in siblings) < .35)
    selected = [cpu for _, cpu in available[:count]]
    if not selected: raise RuntimeError('no sufficiently idle physical cores; nothing launched')
    return selected


def batch(paths, cpus, protocol, stage):
    pending = [p for p in paths if not verified(OUT / 'tasks_done' / p.stem)]
    active = {}; failures = []; resource_error = None
    while pending or active:
        for cpu in cpus:
            if cpu in active or not pending or failures or resource_error: continue
            try: resources(protocol)
            except RuntimeError as error: resource_error = str(error); break
            path = pending.pop(0); logs = OUT / 'worker_logs'; logs.mkdir(exist_ok=True)
            stream = (logs / (path.stem + '.log')).open('a')
            proc = subprocess.Popen([sys.executable, '-B', str(Path(__file__)), 'worker',
                '--task', str(path), '--cpu', str(cpu)], stdout=stream, stderr=subprocess.STDOUT)
            active[cpu] = (proc, path, stream)
            write(OUT / 'launched' / (path.stem + '.json'), dict(pid=proc.pid, cpu=cpu, epoch=time.time()))
        for cpu, (proc, path, stream) in list(active.items()):
            if proc.poll() is None: continue
            stream.close(); del active[cpu]
            if proc.returncode != 0:
                failures.append(dict(task=path.stem, returncode=proc.returncode))
        total = len(list((OUT / 'tasks').glob('*.json')))
        completed = len(list((OUT / 'tasks_done').glob('*/completed_evidence.json')))
        write(OUT / 'progress.json', dict(stage=stage, active=len(active), pending=len(pending),
            campaign_pending=total - completed - len(active), completed=completed, total=total,
            failed=failures, resource_error=resource_error, cpus=cpus, epoch=time.time()))
        if (failures or resource_error) and not active:
            raise RuntimeError('R127 gate blocked; no automatic retry or parent changes: ' + str((failures, resource_error)))
        if active: time.sleep(2)


def controller(workers):
    if not 1 <= workers <= 15: raise ValueError('combined worker cap is 15')
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / 'controller.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        prep = input_valid(); cpus = cpu_pool(min(workers, prep['protocol']['workers']))
        for path in Path('/proc').glob('[0-9]*/cmdline'):
            try: command = path.read_bytes().replace(b'\0', b' ').decode()
            except (OSError, UnicodeError): continue
            if str(Path(__file__)) + ' worker' in command:
                raise RuntimeError('existing R127 worker detected; do not duplicate an interrupted controller')
        resources(prep['protocol'])
        write(OUT / 'controller_identity.json', dict(pid=os.getpid(), host=socket.gethostname(),
            source=prep['source'], cpus=cpus, requested_workers=workers, epoch=time.time()))
        paths = sorted((OUT / 'tasks').glob('*.json'))
        try:
            batch([p for p in paths if read(p)['smoke']], cpus, prep['protocol'], 'smoke_gate')
            smoke = {str(OUT / 'tasks_done' / p.stem / 'completed_evidence.json'):
                digest(OUT / 'tasks_done' / p.stem / 'completed_evidence.json') for p in paths if read(p)['smoke']}
            immutable(OUT / 'smoke_gate.json', dict(source=prep['source'], task_seals=smoke, passed=True))
            batch([p for p in paths if not read(p)['smoke']], cpus, prep['protocol'], 'diagnostic_replay')
            input_valid()
            from pricefm_r127_report import closeout
            closeout(OUT, prep)
        except Exception as error:
            write(OUT / 'blocked.json', dict(error=str(error), epoch=time.time(), parent_untouched=True))
            raise


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('action', choices=('prepare', 'controller', 'worker'))
    p.add_argument('--receipt', type=Path); p.add_argument('--reference', type=Path)
    p.add_argument('--workers', type=int, default=15); p.add_argument('--task', type=Path); p.add_argument('--cpu', type=int)
    args = p.parse_args()
    if args.action == 'prepare': print(prepare(args.receipt, args.reference), flush=True)
    elif args.action == 'controller': controller(args.workers)
    else: worker(args.task, args.cpu)
