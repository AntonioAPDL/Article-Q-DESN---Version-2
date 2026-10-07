#!/usr/bin/env python3
"""Bounded automatic R126 replay -> freeze -> full-fold fit -> forecast DAG."""
from __future__ import annotations

import argparse
import fcntl
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import time
from types import SimpleNamespace

for name in ('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS',
             'BLIS_NUM_THREADS', 'NUMEXPR_NUM_THREADS', 'R_DATATABLE_NUM_THREADS'):
    os.environ[name] = '1'
os.environ['PYTHONDONTWRITEBYTECODE'] = '1'

import numpy as np
import pandas as pd

from pricefm_r126_contract import (digest, read, write, immutable, verify_hashes,
    seal, verified, choose, loss, inverse_price, transform, official_origins, OPERATORS)
from pricefm_r126_replay import forecast
from pricefm_r126_fullfold import (full_design, normal_fit, al_fit, raw_frame, arrays_from_raw)

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
TAG = 'pricefm_stage_r126_matched_comparison_20261007'
OUT = DATA / 'campaigns' / TAG
PREP = DATA / 'launch_prep' / TAG
PROTOCOL = ROOT / 'application/config/pricefm_stage_r126_matched_comparison_protocol_20261007.json'
PREVIOUS = 'pricefm_stage_r125_forecast_estimand_diagnosis_20261006'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def identity():
    branch = git('branch', '--show-current')
    if not branch.startswith('work/pricefm-r126-') or git('status', '--porcelain'):
        raise RuntimeError('clean committed dedicated R126 source required')
    return dict(head=git('rev-parse', 'HEAD'), branch=branch)


def runtime():
    loader = importlib.util.spec_from_file_location('r126_readonly_parent', HERE / '446_run_pricefm_stage_r125_forecast_estimand.py')
    module = importlib.util.module_from_spec(loader); loader.loader.exec_module(module)
    prior = read(DATA / 'launch_prep' / PREVIOUS / 'preparation.json')
    args = SimpleNamespace(**{k: Path(v) for k, v in prior['args'].items()})
    m, control = module.V.owner(args)
    verify_hashes(prior['source_sha256']); verify_hashes(prior['configurations'])
    module.V.parent_freeze(args, m)
    m.REC.verify_evidence(read(DATA / 'campaigns' / PREVIOUS / 'completed_evidence.json'))
    return m, control, [read(path) for path in sorted(prior['configurations'])]


def prepare(receipt):
    source = identity(); protocol = read(PROTOCOL); release = read(receipt)
    if (release['source_head'] != source['head'] or release['failures'] or release['errors']
            or release['skipped'] or release['r_suites'] != 4 or release['python_tests'] < 470):
        raise RuntimeError('matching R126 Python and pinned R release required')
    verify_hashes(release['evidence_sha256'])
    m, control, jobs = runtime()
    if digest(DATA / 'raw/FINAL.csv') != protocol['raw_sha256']:
        raise RuntimeError('raw dataset differs')
    sources = [Path(__file__), PROTOCOL, ROOT / 'application/tests/test_pricefm_stage_r126_matched_comparison.py',
        HERE / '448_fit_pricefm_stage_r126_al.R', HERE / '442_fit_pricefm_stage_r123_certified_normal.R',
        HERE / 'pricefm_stage_r67_cran111_adapter.R', HERE / 'pricefm_r126_release.py',
        HERE / '449_closeout_pricefm_stage_r126_matched_comparison.py']
    sources += list(HERE.glob('pricefm_r126_*.py'))
    hashes = {str(p): digest(p) for p in sources}
    input_hashes = {}
    for job in jobs: input_hashes.update(job['input_sha256'])
    value = dict(source=source, protocol=protocol, source_sha256=hashes,
        input_sha256=input_hashes, jobs=jobs, release_sha256=digest(receipt),
        release_path=str(receipt), raw_sha256=protocol['raw_sha256'],
        reused_internal_fits=72, new_full_fits_expected=24,
        new_screening=False, mcmc=False, joint=False, registry_mutated=False, article_mutated=False)
    immutable(PREP / 'preparation.json', value)
    immutable(PREP / 'reuse_inventory.json', dict(
        reusable_internal_fits=72, reused_forecast_origin_combinations=108,
        exact_full_window_matches_in_frozen_R123_R125=0,
        reason='parent fits have partial internal support; R98 has a different readout and lag specification',
        new_full_fits=24, old_fits_untouched=True,
        reuse_requires_same_source_target_training_response_scaler_specification_and_fold=True))
    return dict(status='R126_PREPARED', reused_fits=72, expected_new_fits=24,
                internal_origin_combinations=1302, reused_R125_origins=108)


def input_valid():
    prep = read(PREP / 'preparation.json')
    if identity() != prep['source'] or read(PROTOCOL) != prep['protocol']:
        raise RuntimeError('executed source/protocol changed')
    verify_hashes(prep['source_sha256'])
    return prep


def make_task(name, **values):
    path = OUT / 'tasks' / (name + '.json')
    immutable(path, dict(name=name, source_head=read(PREP / 'preparation.json')['source']['head'], **values))
    return path


def worker(path, cpu):
    if not path.resolve().is_relative_to((OUT / 'tasks').resolve()):
        raise ValueError('worker task outside assigned campaign')
    os.sched_setaffinity(0, {cpu}); prep = input_valid(); task = read(path)
    if task['source_head'] != prep['source']['head']: raise RuntimeError('task source changed')
    output = OUT / 'tasks_done' / task['name']
    if verified(output): return
    m, control, jobs = runtime(); protocol = prep['protocol']
    beat = lambda value: write(OUT / 'heartbeats' / (task['name'] + '.json'), dict(value, epoch=time.time()))
    started = time.time(); kind = task['kind']
    if kind == 'internal':
        job = next(j for j in jobs if j['job_id'] == task['cell'])
        verify_hashes(job['input_sha256'])
        spec = m.RT.normalize_spec(dict(job['spec'], seed=job['source_reservoir_seed']))
        arrays = m.B._selection_arrays(control, spec)
        split = m.RT.internal_splits(len(arrays.response))[job['split'] - 1]
        scaled, scaler = m.RT.standardize_from_training_origins(arrays, split['train'])
        positions = np.array(task['positions']); selected = m.RT.subset_arrays(scaled, split['validation'][positions])
        values, audit = forecast(m.RT, selected, spec, m.RT.load_normal_fit(Path(job['normal_dir'])),
            {float(q): m.RT.load_quantile_fit(Path(p)) for q, p in job['quantile_dirs'].items()},
            positions, job['seed'], beat)
        values = {k: v * scaler['price_scale'] + scaler['price_mean'] for k, v in values.items()}
        with np.load(Path(job['reference_cell']) / 'predictions.npz', allow_pickle=False) as reference:
            for key in ('truth', 'mean_feature', 'path_specific', 'normal_driver'):
                if not np.allclose(values[key], reference[key][positions], rtol=2e-12, atol=1e-9):
                    raise RuntimeError('R124 causal control differs: ' + key)
        output.mkdir(parents=True); np.savez_compressed(output / 'predictions.npz', positions=positions, **values)
        write(output / 'audit.json', audit); verify_hashes(job['input_sha256'])
    else:
        choice = read(OUT / 'frozen_choice.json'); fold = task['fold']
        root = OUT / 'full' / f'fold={fold}'; design = root / 'design'; normal = root / 'normal'
        template = next(j for j in jobs if j['candidate_id'] == choice['candidate_id'] and j['split'] == 3)
        if kind == 'design':
            full_design(m.RT, DATA, design, choice, protocol, fold)
        elif kind == 'normal':
            normal_fit(normal, design, choice, protocol, template, OUT, ROOT)
        elif kind == 'al':
            parent = normal if task['parent_tau'] is None else root / f'al/tau={task["parent_tau"]:.2f}'
            al_fit(root / f'al/tau={task["tau"]:.2f}', design, parent,
                'normal_rhs' if task['parent_tau'] is None else 'quantile', choice,
                protocol, control, OUT, ROOT, fold, task['tau'])
        elif kind == 'official':
            verified(design); verified(normal)
            qs = {q: root / f'al/tau={q:.2f}' for q in protocol['quantiles']}
            for folder in qs.values(): verified(folder)
            frame = raw_frame(DATA, protocol['test_intervals_market'][fold - 1][1])
            positions = np.array(task['positions']); origins = official_origins(protocol, fold)[positions]
            scalers = read(design / 'scalers.json')
            arrays = arrays_from_raw(m.RT, frame, origins, scalers['outer'], dict(raw_sha256=prep['raw_sha256']))
            scaled = transform(arrays, scalers['inner'], m.RT.BASE.ExplicitArrays)
            values, audit = forecast(m.RT, scaled, m.RT.normalize_spec(choice['spec']),
                m.RT.load_normal_fit(normal), {q: m.RT.load_quantile_fit(p) for q, p in qs.items()},
                positions, 2026100700 + fold, beat)
            values = {k: inverse_price(v, scalers['inner'], scalers['outer']) for k, v in values.items()}
            output.mkdir(parents=True)
            np.savez_compressed(output / 'predictions.npz', positions=positions,
                                anchors_ns=origins.as_unit('ns').asi8, **values)
            write(output / 'audit.json', audit)
        else: raise ValueError('unknown worker stage')
        if not output.exists(): output.mkdir(parents=True)
    seal(output, dict(task=task, elapsed_seconds=time.time() - started, cpu=cpu))


def cpu_pool(count):
    # Pick distinct physical cores using a fresh one-second utilization sample.
    def ticks():
        result = {}
        for line in Path('/proc/stat').read_text().splitlines():
            words = line.split()
            if words[0].startswith('cpu') and words[0][3:].isdigit():
                values = list(map(int, words[1:9])); result[int(words[0][3:])] = (sum(values), values[3] + values[4])
        return result
    before = ticks(); time.sleep(1); after = ticks(); rows = []
    for cpu in os.sched_getaffinity(0):
        total = after[cpu][0] - before[cpu][0]; idle = after[cpu][1] - before[cpu][1]
        base = Path(f'/sys/devices/system/cpu/cpu{cpu}/topology')
        physical = ((base / 'physical_package_id').read_text(), (base / 'core_id').read_text())
        rows.append((1 - idle / max(total, 1), cpu, physical))
    selected = []; used = set()
    for busy, cpu, physical in sorted(rows):
        if busy < .35 and physical not in used:
            selected.append(cpu); used.add(physical)
        if len(selected) == count: break
    if not selected: raise RuntimeError('no sufficiently idle physical core available')
    return selected


def reserves(protocol):
    mem = {line.split(':')[0]: int(line.split()[1]) for line in Path('/proc/meminfo').read_text().splitlines()}
    stat = os.statvfs(DATA)
    if (mem['MemAvailable'] * 1024 < protocol['minimum_free_memory_GiB'] * 2**30
            or stat.f_bavail * stat.f_frsize < protocol['minimum_free_disk_GiB'] * 2**30):
        raise RuntimeError('resource reserve gate reached; pending tasks retained')


def batch(paths, cpus, protocol):
    def parent_complete(name):
        folder = OUT / 'tasks_done' / name
        return (folder / 'completed_evidence.json').is_file() and bool(verified(folder))
    pending = [p for p in paths if not verified(OUT / 'tasks_done' / p.stem)]
    active = {}; failures = []
    while pending or active:
        for cpu in cpus:
            if cpu in active or not pending or failures: continue
            ready = next((p for p in pending if all(
                parent_complete(parent) for parent in read(p).get('dependencies', []))), None)
            if ready is None: continue
            try: reserves(protocol)
            except RuntimeError as error:
                failures.append(dict(resource_gate=str(error)))
                break
            path = ready; pending.remove(path); log = OUT / 'worker_logs' / (path.stem + '.log')
            log.parent.mkdir(parents=True, exist_ok=True)
            stream = log.open('a')
            proc = subprocess.Popen([sys.executable, '-B', str(Path(__file__)), 'worker',
                '--task', str(path), '--cpu', str(cpu)], stdout=stream, stderr=subprocess.STDOUT)
            active[cpu] = (proc, path, stream)
            write(OUT / 'launched' / (path.stem + '.json'), dict(pid=proc.pid, cpu=cpu, epoch=time.time()))
        for cpu, (proc, path, stream) in list(active.items()):
            if proc.poll() is None: continue
            stream.close(); del active[cpu]
            if proc.returncode != 0: failures.append(dict(task=path.stem, returncode=proc.returncode))
        write(OUT / 'progress.json', dict(active=len(active), pending=len(pending), failed=failures,
                                        allocated_worker_cpus=cpus, epoch=time.time()))
        if failures and not active:
            raise RuntimeError('task failure; partial evidence retained: ' + str(failures))
        if pending and not active and not any(all(parent_complete(parent)
                for parent in read(p).get('dependencies', [])) for p in pending):
            raise RuntimeError('dependency graph has missing or cyclic parent tasks')
        time.sleep(2)


def selection(prep):
    rows = []
    for job in prep['jobs']:
        count = job['complete_origin_count']; blocks = []
        prior = Path(job['output_dir'])
        with np.load(prior / 'predictions.npz', allow_pickle=False) as packet:
            blocks.append({k: packet[k] for k in ('original_local_positions', 'truth', *OPERATORS)})
            blocks[-1]['positions'] = blocks[-1].pop('original_local_positions')
        for path in sorted((OUT / 'tasks').glob(job['job_id'] + '_*.json')):
            target = OUT / 'tasks_done' / path.stem; verified(target)
            with np.load(target / 'predictions.npz', allow_pickle=False) as packet:
                blocks.append({k: packet[k] for k in ('positions', 'truth', *OPERATORS)})
        positions = np.concatenate([b['positions'] for b in blocks]); order = np.argsort(positions)
        if not np.array_equal(positions[order], np.arange(count)): raise RuntimeError('incomplete internal origin support')
        values = {k: np.concatenate([b[k] for b in blocks])[order] for k in ('truth', *OPERATORS)}
        target = OUT / 'internal' / job['job_id']
        if not target.exists():
            target.mkdir(parents=True); np.savez_compressed(target / 'predictions.npz', positions=positions[order], **values)
            write(target / 'metrics.json', {k: float(loss(values['truth'], values[k]).mean()) for k in OPERATORS})
            seal(target, dict(origins=count, reused_origins=12, model_refits=0))
        verified(target)
        rows.append(dict(candidate_id=job['candidate_id'], split=job['split'], origins=count,
            AQL=float(loss(values['truth'], values['cdf_pool_clipped']).mean()),
            formal_certified=all(r['formal_converged'] for r in job['fit_labels'])))
    winner, scores = choose(rows, prep['protocol'])
    job = next(j for j in prep['jobs'] if j['candidate_id'] == winner)
    spec = dict(job['spec'], seed=job['source_reservoir_seed'])
    payload = dict(spec=spec, tau0=job['tau0'], operator=prep['protocol']['selection_operator'])
    import hashlib, json
    choice = dict(payload, candidate_id=winner, scores=scores, cells=rows,
        specification_sha256=hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest(),
        selection_uses_test=False, selection_support='940_outer_fold1_train_origins_only',
        deployment_eligibility='formal_certified_A_C_only_B_uncertified_diagnostic',
        freeze_epoch=time.time())
    if not (OUT / 'frozen_choice.json').exists(): immutable(OUT / 'frozen_choice.json', choice)
    else:
        prior = read(OUT / 'frozen_choice.json'); choice['freeze_epoch'] = prior['freeze_epoch']
        immutable(OUT / 'frozen_choice.json', choice)
    pd.DataFrame(rows).to_csv(OUT / 'internal_selection_metrics.csv', index=False)
    return choice


def controller():
    prep = input_valid(); protocol = prep['protocol']; OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / 'controller.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for path in Path('/proc').glob('[0-9]*/cmdline'):
            try: command = path.read_bytes().replace(b'\0', b' ').decode()
            except (OSError, UnicodeError): continue
            if str(OUT) in command and any(name in command for name in
                ('447_run_pricefm_stage_r126_matched_comparison.py worker',
                 '448_fit_pricefm_stage_r126_al.R', '442_fit_pricefm_stage_r123_certified_normal.R')):
                raise RuntimeError('existing task-owned worker detected; do not duplicate an interrupted controller')
        prior_allocation = OUT / 'allocation.json'
        cpus = read(prior_allocation)['cpus'] if prior_allocation.exists() else cpu_pool(protocol['workers'])
        if not set(cpus).issubset(os.sched_getaffinity(0)):
            raise RuntimeError('saved CPU allocation is no longer permitted')
        reserves(protocol)
        immutable(prior_allocation, dict(cpus=cpus, thread_limit=1, maximum_workers=15))
        paths = []
        for job in prep['jobs']:
            missing = sorted(set(range(job['complete_origin_count'])) - set(job['origin_positions']))
            for i in range(0, len(missing), protocol['chunk_origins']):
                paths.append(make_task(job['job_id'] + f'_{i:04d}', kind='internal', cell=job['job_id'],
                                       positions=missing[i:i + protocol['chunk_origins']]))
        write(OUT / 'stage.json', dict(stage='full_internal_replay', total_tasks=len(paths)))
        batch(paths, cpus, protocol); choice = selection(prep)
        paths = []
        parents = {.5: None, .45: .5, .55: .5, .25: .45, .75: .55, .1: .25, .9: .75}
        for f in (1, 2, 3):
            paths.append(make_task(f'design_fold={f}', kind='design', fold=f))
            paths.append(make_task(f'normal_fold={f}', kind='normal', fold=f, dependencies=[f'design_fold={f}']))
            for tau in (.50, .45, .55, .25, .75, .10, .90):
                parent = parents[tau]
                dependency = f'normal_fold={f}' if parent is None else f'al_fold={f}_q{parent:.2f}'
                paths.append(make_task(f'al_fold={f}_q{tau:.2f}', kind='al', fold=f,
                                      tau=tau, parent_tau=parent, dependencies=[dependency]))
        write(OUT / 'stage.json', dict(stage='full_training_dependency_DAG', frozen_candidate=choice['candidate_id'],
                                      model_fits=24, independent_fold_progression=True))
        batch(paths, cpus, protocol)
        paths = []
        for f, count in enumerate(protocol['test_origin_counts'], 1):
            for i in range(0, count, protocol['chunk_origins']):
                paths.append(make_task(f'official_fold={f}_{i:04d}', kind='official', fold=f,
                                       positions=list(range(i, min(i + protocol['chunk_origins'], count)))))
        write(OUT / 'stage.json', dict(stage='frozen_official_forecasts', selection_closed=True))
        batch(paths, cpus, protocol)
        for f, count in enumerate(protocol['test_origin_counts'], 1):
            blocks = []
            for path in sorted((OUT / 'tasks').glob(f'official_fold={f}_*.json')):
                target = OUT / 'tasks_done' / path.stem; verified(target)
                with np.load(target / 'predictions.npz', allow_pickle=False) as packet:
                    blocks.append({k: packet[k] for k in packet.files})
            positions = np.concatenate([b['positions'] for b in blocks]); order = np.argsort(positions)
            if not np.array_equal(positions[order], np.arange(count)): raise RuntimeError('official cohort incomplete')
            target = OUT / 'official' / f'fold={f}'
            if not target.exists():
                target.mkdir(parents=True)
                np.savez_compressed(target / 'predictions.npz', **{
                    k: np.concatenate([b[k] for b in blocks])[order] for k in blocks[0]})
                seal(target, dict(fold=f, origins=count, choice_sha256=digest(OUT / 'frozen_choice.json')))
            verified(target)
        verify_hashes(prep['input_sha256'])
        timings = {}
        for f in (1, 2, 3):
            root = OUT / 'full' / f'fold={f}'
            timings[str(f)] = dict(normal_train_seconds=read(root / 'normal/terminal.json')['train_seconds'],
                AL_train_seconds=sum(read(root / f'al/tau={q:.2f}/terminal.json')['train_seconds']
                                     for q in protocol['quantiles']),
                forecast_task_seconds=sum(verified(OUT / 'tasks_done' / p.stem)['elapsed_seconds']
                    for p in (OUT / 'tasks').glob(f'official_fold={f}_*.json')))
        immutable(OUT / 'timing.json', dict(folds=timings, times_are_sum_of_task_seconds_not_wall_time=True,
            forecast_scope='500_paths_all_six_declared_operators', inherited_screening_cost_excluded=True))
        immutable(OUT / 'terminal.json', dict(status='R126_FULL_FITS_AND_OFFICIAL_FORECASTS_COMPLETE',
            source=prep['source'], internal_origins=1302, reused_internal_fits=72, full_fits=24,
            official_origins=365, official_test_used_for_selection=False,
            comparison_pending_on_muscat=True, promotion_authorized=False, all_region_launch_authorized=False))
        write(OUT / 'stage.json', dict(stage='awaiting_readonly_reference_comparison_on_muscat'))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('mode', choices=['prepare', 'controller', 'worker'])
    p.add_argument('--receipt', type=Path); p.add_argument('--task', type=Path); p.add_argument('--cpu', type=int)
    args = p.parse_args()
    try:
        if args.mode == 'prepare': print(prepare(args.receipt), flush=True)
        elif args.mode == 'worker': worker(args.task, args.cpu)
        else: controller()
    except Exception as error:
        if args.mode == 'controller': write(OUT / 'blocked.json', dict(error=str(error), epoch=time.time(),
            evidence_preserved=True, test_ranking_withheld=True))
        raise
