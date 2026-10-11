#!/usr/bin/env python3
"""Source-gated, fit-free seasonal-driver validation on Jerez."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import shutil
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
from pricefm_r131_seasonal import (validate_protocol, validate_cached, first_step_check,
    choose_physical_cpus, replay, closeout, MODES, CACHED)

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
ENTRY = Path(__file__).resolve()
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
TAG = 'pricefm_stage_r131_causal_seasonal_drivers_20261011'
OUT = DATA / 'campaigns' / TAG
PREP = DATA / 'launch_prep' / TAG
PROTOCOL = ROOT / 'application/config' / (TAG + '.json')
PLAN = ROOT / 'local_trackers/pricefm_stage_r131_causal_seasonal_master_plan_20261011.md'


def git(path, *args):
    return subprocess.check_output(['git', '-C', str(path), *args], text=True).strip()


def identity():
    branch = git(ROOT, 'branch', '--show-current')
    if not branch.startswith('work/pricefm-r131-') or git(ROOT, 'status', '--porcelain'):
        raise RuntimeError('committed clean dedicated R131 source required')
    return dict(branch=branch, head=git(ROOT, 'rev-parse', 'HEAD'))


def setup(dependency, r128=None):
    global runtime, core, read, write, immutable, digest, seal, verified, verify_hashes
    sys.path.insert(0, str(Path(dependency) / 'application/scripts/pricefm'))
    from pricefm_r126_contract import read, write, immutable, digest, seal, verified, verify_hashes
    import pricefm_r123_runtime as runtime
    if r128:
        spec = importlib.util.spec_from_file_location('r131_frozen_regional_core',
            Path(r128) / 'application/scripts/pricefm/pricefm_r128_core.py')
        core = importlib.util.module_from_spec(spec); spec.loader.exec_module(core)


def release(parent, dependency):
    setup(dependency)
    source = identity()
    path = DATA / 'runtime_audits' / TAG / ('release_' + os.uname().nodename + '_' + source['head'][:12])
    path.mkdir(parents=True, exist_ok=False)
    junit = path / 'pytest.xml'
    env = dict(os.environ, PRICEFM_R131_DEPENDENCY=str(dependency), PRICEFM_R131_PARENT=str(parent))
    with (path / 'pytest.log').open('w') as log:
        result = subprocess.run([sys.executable, '-B', '-m', 'pytest', '-q',
            str(ROOT / 'application/tests/test_pricefm_stage_r131_seasonal.py'),
            str(Path(dependency) / 'application/tests/test_pricefm_stage_r127_driver_diagnosis.py'),
            '-p', 'no:cacheprovider', '--junitxml=' + str(junit)],
            env=env, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    suites = ET.parse(junit).getroot().findall('testsuite')
    totals = {k: sum(int(s.get(k, '0')) for s in suites) for k in ('tests', 'failures', 'errors', 'skipped')}
    value = dict(source=source, **totals, passed=result.returncode == 0
        and totals['tests'] >= 55 and sum(totals[k] for k in ('failures', 'errors', 'skipped')) == 0)
    write(path / 'validation.json', value)
    if not value['passed']:
        raise RuntimeError('release failed; inspect ' + str(path))
    return dict(path=str(path / 'validation.json'), **value)


def ledger_folder(ledger, folder):
    verified(folder)
    receipt = folder / 'completed_evidence.json'
    ledger[str(receipt)] = digest(receipt)
    ledger.update({str(folder / k): h for k, h in read(receipt)['artifacts'].items()})


def preparation(parent, receipt, muscat_receipt):
    p = json.loads(PROTOCOL.read_text()); validate_protocol(p); source = identity()
    parent_prep_path = DATA / 'launch_prep' / p['parent_tag'] / 'preparation.json'
    previous = json.loads(parent_prep_path.read_text())
    setup(previous['dependency'], previous['r128_source'])
    if (git(parent, 'rev-parse', 'HEAD') != p['parent_head'] or git(parent, 'status', '--porcelain')
            or previous['source']['head'] != p['parent_head']):
        raise RuntimeError('frozen R130 source differs')
    parent_out = DATA / 'campaigns' / p['parent_tag']
    manifest_path = parent_out / 'frozen_handoff_manifest.json'
    if digest(manifest_path) != p['parent_manifest_sha256']:
        raise RuntimeError('frozen R130 completion manifest changed')
    manifest = read(manifest_path)
    if digest(parent_prep_path) != '5863a9b2632517b15302c9d31131fca3c500c37289341f94c3f27b2945208faa':
        raise RuntimeError('frozen R130 preparation changed')
    for key in ('source_sha256', 'input_sha256', 'output_sha256'):
        verify_hashes(manifest[key])
    terminal = read(parent_out / 'terminal.json')
    if terminal['status'] != 'R130_COMPLETE_NOT_PROMOTED' or terminal['tasks'] != 120:
        raise RuntimeError('completed R130 required')
    for release_path in (receipt, muscat_receipt):
        release = read(release_path)
        if release['source'] != source or not release['passed']:
            raise RuntimeError('matching release on both hosts required')
    verify_hashes(previous['source_sha256']); verify_hashes(previous['input_sha256'])
    if digest(DATA / 'raw/FINAL.csv') != previous['raw_sha256']:
        raise RuntimeError('protected raw source changed')
    ledger = dict(previous['input_sha256'])
    ledger.update(manifest['output_sha256'])
    for path in (parent_prep_path, manifest_path, parent_out / 'terminal.json', Path(receipt), Path(muscat_receipt), PLAN):
        ledger[str(path)] = digest(path)
    ledger_folder(ledger, parent_out / 'closeout')
    for task in previous['tasks']:
        ledger_folder(ledger, parent_out / 'tasks_done' / task['name'])
    own = [ENTRY, HERE / 'pricefm_r131_seasonal.py', PROTOCOL,
        ROOT / 'application/tests/test_pricefm_stage_r131_seasonal.py',
        ROOT / 'application/notes' / (TAG + '.md')]
    sources = dict(previous['source_sha256'])
    sources.update({str(f): digest(f) for f in own})
    if len(previous['cells']) != 6 or len(previous['tasks']) != 120:
        raise RuntimeError('bounded parent cells or task schedule changed')
    for cell in previous['cells']:
        if len(cell['grid']) != 48 or len(cell['quantile_dirs']) != 7:
            raise RuntimeError('full matched receiver/cohort required')
    value = dict(source=source, protocol=p, parent_source=str(parent),
        dependency=previous['dependency'], r128_source=previous['r128_source'],
        parent_out=str(parent_out), source_sha256=sources, input_sha256=ledger,
        cells=previous['cells'], tasks=previous['tasks'], new_fits=0, diagnostic_origins=288,
        raw_sha256=previous['raw_sha256'], official_test_reforecast=False)
    immutable(PREP / 'preparation.json', value)
    for task in value['tasks']:
        immutable(OUT / 'tasks' / (task['name'] + '.json'), task)
    return dict(status='R131_PREPARED', tasks=120, smoke_tasks=24, new_fits=0, origins=288)


def valid(prep, full=False):
    if identity() != prep['source'] or read(PROTOCOL) != prep['protocol']:
        raise RuntimeError('executed source or protocol changed')
    if git(prep['parent_source'], 'rev-parse', 'HEAD') != prep['protocol']['parent_head']:
        raise RuntimeError('frozen R130 head changed')
    verify_hashes(prep['source_sha256'])
    if full:
        verify_hashes(prep['input_sha256'])
    for task in prep['tasks']:
        if read(OUT / 'tasks' / (task['name'] + '.json')) != task:
            raise RuntimeError('immutable task schedule changed')


def worker(name, cpu):
    prep = json.loads((PREP / 'preparation.json').read_text())
    setup(prep['dependency'], prep['r128_source']); valid(prep)
    os.sched_setaffinity(0, {cpu})
    task = read(OUT / 'tasks' / (name + '.json'))
    dest = OUT / 'tasks_done' / name
    if dest.exists():
        verified(dest); return
    cell = next(c for c in prep['cells'] if (c['region'], c['fold']) == (task['region'], task['fold']))
    verify_hashes({cell['bank']: prep['input_sha256'][cell['bank']]})
    arrays = runtime.subset_arrays(core.load_arrays(runtime, Path(cell['bank'])), task['bank_indices'])
    parent_folder = Path(prep['parent_out']) / 'tasks_done' / name
    verified(parent_folder)
    with np.load(parent_folder / 'predictions.npz', allow_pickle=False) as data:
        cached = {k: data[k] for k in data.files}
    validate_cached(cached, arrays, task, cell['scaler'])
    quantiles = {float(q): runtime.load_quantile_fit(Path(folder)) for q, folder in cell['quantile_dirs'].items()}
    seed = runtime.BASE.deterministic_seed(2026101001, task['region'], task['fold'], 'validation')
    beat = lambda v: write(OUT / 'heartbeats' / (name + '.json'), dict(v, epoch=time.time(), cpu=cpu))
    start = time.time()
    values, audit = replay(runtime, arrays, cell['spec'], quantiles, task['positions'], seed, observe=beat)
    scaler = cell['scaler']
    for key in (*MODES, 'seasonal_driver'):
        values[key] = values[key] * scaler['price_scale'] + scaler['price_mean']
    values.update({k: cached[k] for k in (*CACHED, 'truth', 'positions', 'bank_indices', 'anchors_ns')})
    values.update(normal_driver_mean=cached['driver_mean'][:, :, 0], normal_driver_sd=cached['driver_sd'][:, :, 0])
    first = first_step_check(values)
    smoke_difference = None
    if task['smoke']:
        from pricefm_r127_forecast import replay as parent_replay
        original, _ = parent_replay(runtime, arrays, cell['spec'], quantiles, task['positions'], seed,
            runtime.load_normal_fit(Path(cell['normal_dir'])), observe=beat)
        original_prediction = original['stochastic'] * scaler['price_scale'] + scaler['price_mean']
        smoke_difference = float(np.max(abs(original_prediction - cached['stochastic'])))
        if smoke_difference > 1e-8:
            raise RuntimeError('frozen complete H96 stochastic replay differs')
        np.testing.assert_allclose(original['driver_mean'][:, :, 0] * scaler['price_scale'] + scaler['price_mean'],
            cached['driver_mean'][:, :, 0], rtol=2e-12, atol=1e-8)
        np.testing.assert_allclose(original['driver_sd'][:, :, 0] * scaler['price_scale'],
            cached['driver_sd'][:, :, 0], rtol=2e-12, atol=1e-8)
    if not all(np.isfinite(v).all() for v in values.values()):
        raise RuntimeError('nonfinite saved task')
    audit.update(first_step_difference=first, stochastic_smoke_difference=smoke_difference,
        region=task['region'], fold=task['fold'], test_opened=False,
        fitted_response_end=cell['train_end'], validation_end_exclusive=cell['test_start'], units='EUR/MWh')
    (OUT / 'staging').mkdir(exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix=name + '.', dir=OUT / 'staging'))
    np.savez_compressed(tmp / 'predictions.npz', **values); write(tmp / 'audit.json', audit)
    seal(tmp, dict(task=task, source=prep['source'], elapsed_seconds=time.time() - start,
        first_step_difference=first, stochastic_smoke_difference=smoke_difference))
    dest.parent.mkdir(exist_ok=True)
    if dest.exists():
        raise RuntimeError('duplicate task writer')
    tmp.rename(dest)


def resources(p):
    memory = {s.split(':')[0]: int(s.split()[1]) * 1024 for s in Path('/proc/meminfo').read_text().splitlines()}
    available = memory['MemAvailable'] / 2**30
    disk = shutil.disk_usage(DATA).free / 2**30
    used = sum(f.stat().st_size for f in OUT.rglob('*') if f.is_file()) / 2**30
    if (available < p['minimum_free_memory_GiB'] or disk < p['minimum_free_disk_GiB'] + .5
            or used > p['maximum_campaign_output_GiB']):
        raise RuntimeError('RAM/disk reserve reached; drain own children and retain pending')
    return dict(available_memory_GiB=available, free_disk_GiB=disk, campaign_GiB=used)


def physical_cpus(count):
    def ticks():
        result = {}
        for line in Path('/proc/stat').read_text().splitlines():
            words = line.split()
            if words[0].startswith('cpu') and words[0][3:].isdigit():
                values = list(map(int, words[1:9]))
                result[int(words[0][3:])] = (sum(values), values[3] + values[4])
        return result
    before = ticks(); time.sleep(5); after = ticks()
    topology, busy = {}, {}
    for cpu in after:
        path = Path(f'/sys/devices/system/cpu/cpu{cpu}/topology')
        topology[cpu] = ((path / 'physical_package_id').read_text().strip(), (path / 'core_id').read_text().strip())
        total = after[cpu][0] - before[cpu][0]; idle = after[cpu][1] - before[cpu][1]
        busy[cpu] = 1 - idle / max(total, 1)
    cpus = choose_physical_cpus(os.sched_getaffinity(0), topology, busy, count)
    return cpus, dict(total_physical_cores=len(set(topology.values())),
        selected=[dict(cpu=c, package=topology[c][0], core=topology[c][1]) for c in cpus],
        utilization={str(c): v for c, v in busy.items()}, sample_seconds=5, reserved_core_groups=2)


def batch(tasks, cpus, prep, stage):
    waiting = []
    for task in tasks:
        folder = OUT / 'tasks_done' / task['name']
        if folder.exists():
            metadata = verified(folder)
            if metadata['source'] != prep['source']:
                raise RuntimeError('completed task source differs')
        else:
            waiting.append(task)
    running = {}; free = list(cpus); failed = []; resource_error = None
    while waiting or running:
        try:
            res = resources(prep['protocol'])
        except RuntimeError as error:
            resource_error = str(error); res = {}
        while waiting and free and not failed and not resource_error:
            task = waiting.pop(0); cpu = free.pop(0)
            log = (OUT / 'worker_logs' / (task['name'] + '.log')).open('a')
            process = subprocess.Popen([sys.executable, '-B', str(ENTRY), 'worker', '--name', task['name'],
                '--cpu', str(cpu)], stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            running[task['name']] = (process, cpu, log)
        for name, (process, cpu, log) in list(running.items()):
            code = process.poll()
            if code is None:
                continue
            log.close(); free.append(cpu); del running[name]
            if code:
                failed.append(dict(task=name, exit_code=code))
            else:
                try:
                    metadata = verified(OUT / 'tasks_done' / name)
                    if metadata['source'] != prep['source'] or metadata['first_step_difference'] > 1e-8:
                        raise RuntimeError('source or first-step check failed')
                except Exception as error:
                    failed.append(dict(task=name, error=str(error)))
        write(OUT / 'progress.json', dict(stage=stage, active=len(running), pending=len(waiting),
            completed=sum((OUT / 'tasks_done' / t['name'] / 'completed_evidence.json').exists() for t in prep['tasks']),
            total=120, failures=failed, resource_error=resource_error, resources=res, epoch=time.time()))
        if not running and (failed or resource_error):
            raise RuntimeError(str(failed or resource_error))
        if waiting or running:
            time.sleep(5)


def ensure_no_live_workers():
    for file in Path('/proc').glob('[0-9]*/cmdline'):
        try:
            parts = file.read_bytes().split(b'\0')
        except OSError:
            continue
        if str(ENTRY).encode() in parts and b'worker' in parts:
            raise RuntimeError('live own worker; no duplicate admissions')


def controller(workers):
    prep = json.loads((PREP / 'preparation.json').read_text())
    setup(prep['dependency'], prep['r128_source']); valid(prep, full=True)
    ensure_no_live_workers()
    with (OUT / 'controller.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if (OUT / 'terminal.json').exists():
            verified(OUT / 'closeout'); return
        if (OUT / 'staging').exists() and list((OUT / 'staging').iterdir()):
            raise RuntimeError('unsealed partial task requires inspection; no automatic deletion')
        cpus, capacity = physical_cpus(workers); resources(prep['protocol'])
        (OUT / 'worker_logs').mkdir(exist_ok=True)
        write(OUT / 'controller_identity.json', dict(pid=os.getpid(), cpus=cpus, capacity=capacity,
            source=prep['source'], host=os.uname().nodename, epoch=time.time()))
        try:
            batch([t for t in prep['tasks'] if t['smoke']], cpus, prep, 'first_origin_smoke')
            immutable(OUT / 'smoke_gate.json', dict(passed=True, tasks=24, source=prep['source']))
            batch([t for t in prep['tasks'] if not t['smoke']], cpus, prep, 'seasonal_controls')
            valid(prep, full=True)
            from pricefm_r127_contract import common_metrics
            closeout(OUT, prep, verified, read, write, seal, common_metrics)
            hashes = dict(prep['input_sha256']); hashes.update(prep['source_sha256'])
            for task in prep['tasks']:
                ledger_folder(hashes, OUT / 'tasks_done' / task['name'])
            ledger_folder(hashes, OUT / 'closeout')
            write(OUT / 'frozen_handoff_manifest.json', dict(source=prep['source'], sha256=hashes,
                preparation_sha256=digest(PREP / 'preparation.json'), raw_sha256=prep['raw_sha256']))
            write(OUT / 'terminal.json', dict(status='R131_COMPLETE_NOT_PROMOTED', source=prep['source'],
                tasks=120, failures=0, pending=0, diagnostic_origins=288, new_fits=0))
        except Exception as error:
            write(OUT / 'blocked.json', dict(error=str(error), source=prep['source'], epoch=time.time(),
                parent_untouched=True, automatic_correction=False)); raise


def launch(workers):
    prep = json.loads((PREP / 'preparation.json').read_text())
    setup(prep['dependency'], prep['r128_source']); valid(prep, full=True)
    if not 1 <= workers <= 30:
        raise ValueError('maximum physical workers is 30')
    if (OUT / 'launch_receipt.json').exists():
        raise RuntimeError('prior launch receipt exists; inspect before resuming')
    resources(prep['protocol']); ensure_no_live_workers()
    command = [sys.executable, '-B', str(ENTRY), 'controller', '--workers', str(workers)]
    with (OUT / 'controller.log').open('a') as log:
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=log,
            stderr=subprocess.STDOUT, start_new_session=True, close_fds=True)
    receipt = dict(pid=process.pid, command=command, source=prep['source'], host=os.uname().nodename,
        worker_cap=workers, numerical_threads=1, epoch=time.time())
    immutable(OUT / 'launch_receipt.json', receipt)
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('release', 'prepare', 'launch', 'controller', 'worker'))
    for name in ('parent', 'dependency', 'release', 'muscat-release'):
        parser.add_argument('--' + name, type=Path)
    parser.add_argument('--workers', type=int, default=30)
    parser.add_argument('--name'); parser.add_argument('--cpu', type=int)
    args = parser.parse_args()
    if args.action == 'release':
        print(release(args.parent, args.dependency), flush=True)
    elif args.action == 'prepare':
        print(preparation(args.parent, args.release, args.muscat_release), flush=True)
    elif args.action == 'launch':
        print(launch(args.workers), flush=True)
    elif args.action == 'controller':
        controller(args.workers)
    else:
        worker(args.name, args.cpu)
