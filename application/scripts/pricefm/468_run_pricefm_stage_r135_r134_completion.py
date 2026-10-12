#!/usr/bin/env python3
"""R135: certify capped R134 medians, finish its DAG, and evaluate frozen winners."""

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
import time

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
TAG = 'pricefm_stage_r135_r134_fixedpoint_completion_20261012'
PARENT_TAG = 'pricefm_stage_r134_pure_qdesn_optimization_20261011'
OUT = DATA / 'campaigns' / TAG
PARENT_OUT = DATA / 'campaigns' / PARENT_TAG
PREP = DATA / 'launch_prep' / TAG
PARENT_PREP = DATA / 'launch_prep' / PARENT_TAG
PROTOCOL = ROOT / 'application/config' / (TAG + '.json')
ENTRY = Path(__file__).resolve()
AUDITOR = HERE / '466_audit_pricefm_stage_r135_r134_median.R'
FITTER = HERE / '467_fit_pricefm_stage_r135_certified_al.R'
HELPER = ROOT / 'application/R/pricefm_r129_al_fixedpoint_certificate.R'
PARENT_ENTRY = HERE / '464_run_pricefm_stage_r134_pure_optimization.py'
_OUTCOMES = {}


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


PARENT = module('pricefm_r135_parent', PARENT_ENTRY)


def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()


def source_identity():
    branch = git(ROOT, 'branch', '--show-current')
    if not branch.startswith('work/pricefm-r134-fixedpoint-recovery-'):
        raise RuntimeError('dedicated R134 fixed-point recovery branch required')
    if git(ROOT, 'status', '--porcelain'):
        raise RuntimeError('clean committed R135 source required')
    return dict(branch=branch, head=git(ROOT, 'rev-parse', 'HEAD'))


def setup(dependency):
    runtime = core.dependencies(dependency)
    global read, write, immutable, digest, seal, verified, verify_hashes
    from pricefm_r126_contract import read, write, immutable, digest, seal, verified, verify_hashes
    PARENT.setup(dependency)
    return runtime


def validate_protocol(protocol):
    if (protocol['tag'] != TAG or protocol['parent_tag'] != PARENT_TAG
            or protocol['maximum_workers'] != 30
            or protocol['expected_parent_task_counts']['uncertified_median'] != 14
            or protocol['expected_parent_task_counts']['pending_internal'] != 98):
        raise ValueError('R135 recovery geometry differs from the audited block')
    for key in ('package_mutation_authorized', 'screening_authorized', 'mcmc_authorized',
                'joint_authorized', 'exal_authorized', 'promotion_authorized',
                'registry_mutation_authorized', 'article_mutation_authorized',
                'priors_from_initializers', 'test_used_for_selection',
                'all_region_launch_authorized'):
        if protocol[key] is not False:
            raise ValueError('forbidden recovery expansion: ' + key)


def resources(protocol, allowance=0):
    mem = {line.split(':')[0]: int(line.split()[1]) for line in Path('/proc/meminfo').read_text().splitlines()}
    stat = os.statvfs(DATA)
    available = stat.f_bavail * stat.f_frsize / 2**30
    used = sum(path.stat().st_size for path in OUT.rglob('*') if path.is_file()) / 2**30
    if (mem['MemAvailable'] / 2**20 < protocol['minimum_free_memory_GiB']
            or available < protocol['minimum_free_disk_GiB'] + allowance
            or used + allowance > protocol['maximum_output_GiB']):
        raise RuntimeError('R135 resource reserve reached; completed evidence is preserved')
    return dict(available_memory_GiB=mem['MemAvailable'] / 2**20,
                free_disk_GiB=available, campaign_output_GiB=used)


def parent_task_inventory():
    return [read(path) for path in sorted((PARENT_OUT / 'tasks').glob('*.json'))]


def sealed_result(root, name):
    folder = root / 'tasks_done' / name
    if (folder / 'completed_evidence.json').is_file() and verified(folder):
        return read(folder / 'result.json')
    return None


def certificate_name(parent_name):
    return 'certificate__' + parent_name


def prepare(dependency):
    runtime = setup(dependency)
    protocol = read(PROTOCOL); validate_protocol(protocol)
    identity = source_identity()
    if git(dependency, 'rev-parse', 'HEAD') != protocol['dependency_head'] or git(dependency, 'status', '--porcelain'):
        raise RuntimeError('frozen dependency worktree differs')
    parent_prep = read(PARENT_PREP / 'preparation.json')
    if parent_prep['source']['head'] != protocol['parent_source_head']:
        raise RuntimeError('R134 parent source differs from the audited campaign')
    if not (PARENT_OUT / 'blocked.json').is_file() or (PARENT_OUT / 'terminal.json').exists():
        raise RuntimeError('R134 parent is not the expected preserved blocked campaign')
    for path in Path('/proc').glob('[0-9]*/cmdline'):
        try:
            command = path.read_bytes().split(b'\0')
        except OSError:
            continue
        if str(PARENT_ENTRY).encode() in command and (b'controller' in command or b'worker' in command):
            raise RuntimeError('live R134 process detected; recovery preparation is not safe')
    if (PREP / 'preparation.json').is_file():
        prior = read(PREP / 'preparation.json')
        if prior['source'] != identity or prior['protocol'] != protocol:
            raise RuntimeError('existing R135 preparation belongs to another source')
        verify_hashes(prior['source_sha256']); verify_hashes(prior['parent_input_sha256'])
        return dict(status='R135_ALREADY_PREPARED', certificates=len(prior['certificate_tasks']),
                    pending_internal=len(prior['pending_internal_tasks']))

    resources(protocol, protocol['maximum_workers'] * protocol['worker_storage_allowance_GiB'])
    tasks = parent_task_inventory()
    counts = pd.Series([task['kind'] for task in tasks]).value_counts().to_dict()
    expected = protocol['expected_parent_task_counts']
    for kind in ('ridge', 'stats', 'rhs', 'internal_design'):
        if counts.get(kind, 0) != expected[kind]:
            raise RuntimeError(f'R134 {kind} inventory differs')
    completed_counts = {}
    for task in tasks:
        if sealed_result(PARENT_OUT, task['name']) is not None:
            completed_counts[task['kind']] = completed_counts.get(task['kind'], 0) + 1
    for kind in ('ridge', 'stats', 'rhs', 'internal_design', 'internal_al', 'internal_score'):
        if completed_counts.get(kind, 0) != expected[kind]:
            raise RuntimeError(f'R134 completed {kind} evidence differs')
    quantile = [task for task in tasks if task['kind'].startswith('internal_')]
    medians = [task for task in quantile if task['kind'] == 'internal_al' and task['tau'] == .5]
    uncertified = []
    for task in medians:
        result = sealed_result(PARENT_OUT, task['name'])
        if result is None or not result.get('certified', False):
            uncertified.append(task)
    pending = [task for task in quantile if sealed_result(PARENT_OUT, task['name']) is None]
    if len(uncertified) != expected['uncertified_median'] or len(pending) != expected['pending_internal']:
        raise RuntimeError('R134 blocked inventory changed after the health audit')
    if any(task['tau'] != .5 for task in uncertified):
        raise RuntimeError('only preserved median fits may enter fixed-point recovery')

    certificates = [dict(name=certificate_name(task['name']), kind='median_certificate',
        parent_name=task['name'], region=task['region'], split=task['split'], tau=.5,
        tau0=task['tau0'], design_name=task['design_name']) for task in uncertified]
    parent_hashes = {}
    for task in uncertified:
        fit = PARENT_OUT / 'tasks_done' / task['name'] / 'fit'
        design = PARENT_OUT / 'tasks_done' / task['design_name'] / 'design'
        contract = PARENT_OUT / 'contracts' / (task['name'] + '.json')
        for path in (fit / 'terminal.json', fit / 'beta_mean.bin', fit / 'beta_cov.bin',
                     design / 'terminal.json', design / 'design.json', design / 'X.bin',
                     design / 'y.bin', contract,
                     PARENT_OUT / 'tasks_done' / task['name'] / 'result.json',
                     PARENT_OUT / 'tasks_done' / task['name'] / 'completed_evidence.json'):
            parent_hashes[str(path)] = digest(path)
    source_paths = [ENTRY, AUDITOR, FITTER, HELPER, PROTOCOL, PARENT_ENTRY,
        HERE / 'pricefm_r134_core.py',
        ROOT / 'application/tests/test_pricefm_stage_r135_r134_completion.py']
    source_hashes = {str(path): digest(path) for path in source_paths}
    prep = dict(source=identity, parent_source=parent_prep['source'], dependency=str(dependency),
        dependency_head=protocol['dependency_head'], protocol=protocol, parent_preparation=str(PARENT_PREP / 'preparation.json'),
        parent_protocol=parent_prep['protocol'], official_protocol=parent_prep['official_protocol'],
        references=parent_prep['references'], certificate_tasks=certificates,
        pending_internal_tasks=pending, quantile_tasks=quantile,
        source_sha256=source_hashes, parent_input_sha256=parent_hashes,
        parent_blocked_sha256=digest(PARENT_OUT / 'blocked.json'),
        raw_identity=parent_prep['raw_identity'], test_used_for_selection=False,
        screening_repeated=False, ridge_reused=True, rhs_reused=True,
        fixedpoint_probe_summary=dict(cases=14, certified=14, model_refits=0))
    OUT.mkdir(parents=True, exist_ok=True)
    immutable(PREP / 'preparation.json', prep)
    return dict(status='R135_PREPARED', certificates=len(certificates), pending_internal=len(pending),
                completed_parent_internal=len(quantile) - len(pending), screening_repeated=False)


def valid():
    prep = read(PREP / 'preparation.json')
    if source_identity() != prep['source']:
        raise RuntimeError('executed R135 source changed')
    if git(prep['dependency'], 'rev-parse', 'HEAD') != prep['dependency_head']:
        raise RuntimeError('frozen dependency changed')
    verify_hashes(prep['source_sha256']); verify_hashes(prep['parent_input_sha256'])
    if digest(PARENT_OUT / 'blocked.json') != prep['parent_blocked_sha256']:
        raise RuntimeError('R134 blocked state changed')
    raw = (DATA / 'raw/FINAL.csv').stat()
    if (raw.st_size, raw.st_mtime_ns) != (prep['raw_identity']['bytes'], prep['raw_identity']['mtime_ns']):
        raise RuntimeError('raw source metadata changed')
    return prep


def child_outcome(name):
    return sealed_result(OUT, name)


def outcome(name):
    if name in _OUTCOMES:
        return _OUTCOMES[name]
    value = child_outcome(name)
    if value is None:
        value = sealed_result(PARENT_OUT, name)
        if value is not None and not value.get('certified', True):
            certificate = child_outcome(certificate_name(name))
            if certificate and certificate.get('certified'):
                value = dict(value, certified=True, independent_fixedpoint_certified=True,
                             fixedpoint_certificate_task=certificate_name(name))
            else:
                value = None
    if value is not None:
        _OUTCOMES[name] = value
    return value


def task_folder(name):
    child = OUT / 'tasks_done' / name
    if child_outcome(name) is not None:
        return child
    parent = PARENT_OUT / 'tasks_done' / name
    value = sealed_result(PARENT_OUT, name)
    if value is not None and value.get('certified', True):
        return parent
    certificate = OUT / 'tasks_done' / certificate_name(name)
    if child_outcome(certificate.name) and (certificate / 'fit').is_dir():
        return certificate
    raise RuntimeError('no certified task folder for ' + name)


def run_r(prep, entry, contract, task):
    from pricefm_r126_fullfold import run_r
    path = OUT / 'contracts' / (task['name'] + '.json'); immutable(path, contract)
    log = OUT / 'fit_logs' / (task['name'] + '.log'); log.parent.mkdir(exist_ok=True)
    run_r(entry, '--config', path, log)


def certificate_contract(prep, task, output):
    parent_task = next(value for value in prep['quantile_tasks'] if value['name'] == task['parent_name'])
    fit = PARENT_OUT / 'tasks_done' / task['parent_name'] / 'fit'
    design = PARENT_OUT / 'tasks_done' / parent_task['design_name'] / 'design'
    old = read(PARENT_OUT / 'contracts' / (task['parent_name'] + '.json'))
    protected = [design / 'X.bin', design / 'y.bin', design / 'design.json', design / 'terminal.json',
                 fit / 'beta_mean.bin', fit / 'beta_cov.bin', fit / 'terminal.json']
    return dict(stage='R135', action='r134_saved_median_certificate', test_opened=False,
        no_model_fit=True, output_dir=str(output / 'audit'), design_dir=str(design),
        parent_fit_dir=str(fit), helper=str(HELPER), helper_sha256=digest(HELPER),
        cran_library=old['cran_library'], input_sha256={str(path): digest(path) for path in protected},
        posterior_target_sha256=old['posterior_target_sha256'], tau0=task['tau0'],
        max_rhs_iter=prep['protocol']['max_rhs_iter'], limits=prep['protocol']['certificate_limits'])


def certify_median(prep, task, output):
    contract = certificate_contract(prep, task, output)
    run_r(prep, AUDITOR, contract, task)
    audit = read(output / 'audit/certificate.json')
    parent = PARENT_OUT / 'tasks_done' / task['parent_name'] / 'fit'
    fit = output / 'fit'; fit.mkdir()
    for name in ('beta_mean.bin', 'beta_cov.bin', 'vb_trace.csv'):
        shutil.copyfile(parent / name, fit / name)
    terminal = read(parent / 'terminal.json')
    terminal.update(status='r135_derived_r134_AL_fixedpoint_from_frozen_median',
        independent_fixedpoint_certified=audit['certified'], computationally_certified=audit['certified'],
        original_formal_converged=False, original_terminal_sha256=digest(parent / 'terminal.json'),
        certification=audit['certification'], no_new_AL_fit=True, test_opened=False,
        recovery_source=prep['source'], recovery_parent=task['parent_name'])
    write(fit / 'terminal.json', terminal)
    shutil.copyfile(output / 'audit/certificate.json', fit / 'fixedpoint_certificate.json')
    return dict(certified=audit['certified'], parent_name=task['parent_name'],
        original_formal_converged=False, no_new_AL_fit=True,
        posterior_target_sha256=audit['posterior_target_sha256'])


def al_contract(runtime, prep, task, output):
    design = task_folder(task['design_name']) / 'design'
    parent = task_folder(task['parent_name']) / 'fit'
    dependency = Path(prep['dependency'])
    adapter = dependency / 'application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R'
    manifest = Path(read(prep['parent_preparation'])['control']['cran_manifest'])
    index = task.get('fold', task.get('split'))
    return dict(stage='R135', model_stage='R134', tag=TAG, family='al', fold=index,
        tau=task['tau'], tau0=task['tau0'], output_dir=str(output / 'fit'),
        design_dir=str(design), parent_dir=str(parent), parent_type=task['parent_type'],
        parent_terminal_sha256=digest(parent / 'terminal.json'), cran_library=str(manifest.parent),
        cran_manifest=str(manifest), cran_manifest_sha256=digest(manifest),
        cran_adapter=str(adapter), cran_adapter_sha256=digest(adapter),
        fixedpoint_helper=str(HELPER), fixedpoint_helper_sha256=digest(HELPER),
        design_terminal_sha256=digest(design / 'terminal.json'), max_iter=1000,
        tol=prep['parent_protocol']['al_tol'], n_samp=prep['parent_protocol']['al_n_samp'],
        n_samp_xi=prep['parent_protocol']['al_n_samp'], max_rhs_iter=prep['protocol']['max_rhs_iter'],
        certificate_limits=prep['protocol']['certificate_limits'],
        seed=runtime.BASE.deterministic_seed(prep['parent_protocol']['forecast_seed'], task['region'],
            index, task['tau'], task['candidate_id']) % (2**31 - 1), test_opened=False,
        prior_center_from_initializer=False,
        posterior_target_sha256=digest(design / 'terminal.json') +
            f":tau={task['tau']}:tau0={task['tau0']:.17g}")


def fit_al(runtime, prep, task, output):
    contract = al_contract(runtime, prep, task, output)
    run_r(prep, FITTER, contract, task)
    terminal = read(output / 'fit/terminal.json')
    return dict(certified=terminal['computationally_certified'],
        **({'fold': task['fold']} if 'fold' in task else {'split': task['split']}),
        tau=task['tau'], formal_converged=terminal['formal_converged'],
        independent_fixedpoint_certified=terminal['independent_fixedpoint_certified'])


def score_internal(runtime, prep, task, output, beat):
    parent_prep = read(prep['parent_preparation'])
    arrays = PARENT.bank(runtime, parent_prep, task)
    scaled, scaler, cell = PARENT.scaled_internal(runtime, arrays, task['split'])
    normal = runtime.load_normal_fit(task_folder(task['rhs_name']) / 'fit')
    quantiles = {float(q): runtime.load_quantile_fit(task_folder(name) / 'fit')
                 for q, name in task['al_names'].items()}
    score = core.quantile_internal_score(runtime, scaled, task['spec'], normal, quantiles, cell,
        prep['parent_protocol']['quantile_origins_per_clock'], runtime.BASE.deterministic_seed(
            prep['parent_protocol']['forecast_seed'], task['region'], task['candidate_id'],
            task['tau0'], task['split']), observe=beat)
    return dict(certified=True, candidate_id=task['candidate_id'], tau0=task['tau0'],
        split=task['split'], **PARENT.scale_metrics(score, scaler))


def execute(runtime, prep, task, output, beat):
    if task['kind'] == 'median_certificate':
        return certify_median(prep, task, output)
    if task['kind'] in ('internal_al', 'al'):
        return fit_al(runtime, prep, task, output)
    if task['kind'] == 'internal_score':
        return score_internal(runtime, prep, task, output, beat)
    PARENT.OUT = OUT
    return PARENT.execute(runtime, read(prep['parent_preparation']), task, output, beat)


def worker(name, cpu):
    prep = read(PREP / 'preparation.json'); runtime = setup(Path(prep['dependency'])); prep = valid()
    os.sched_setaffinity(0, {cpu})
    task = read(OUT / 'tasks' / (name + '.json')); output = OUT / 'tasks_done' / name
    if child_outcome(name) is not None:
        return
    if output.exists():
        interrupted = OUT / 'interrupted_attempts' / f'{name}.{int(time.time())}.{os.getpid()}'
        interrupted.parent.mkdir(parents=True, exist_ok=True); shutil.move(str(output), interrupted)
    output.mkdir(parents=True)
    beat = lambda value: write(OUT / 'heartbeats' / (name + '.json'), dict(value, epoch=time.time()))
    start = time.time(); beat(dict(status='running', kind=task['kind']))
    result = execute(runtime, prep, task, output, beat)
    write(output / 'result.json', result)
    seal(output, dict(task_sha256=digest(OUT / 'tasks' / (name + '.json')),
        source_head=prep['source']['head'], elapsed_seconds=time.time() - start,
        certified=result.get('certified', True)))


def register(tasks):
    for task in tasks:
        immutable(OUT / 'tasks' / (task['name'] + '.json'), task)


def batch(tasks, cpus, prep, stage):
    register(tasks); pending = [task for task in tasks if child_outcome(task['name']) is None]
    active = {}; failures = []; resource_error = None
    while pending or active:
        for cpu in cpus:
            if cpu in active or not pending or failures or resource_error:
                continue
            ready = next((task for task in pending if all(outcome(name) and outcome(name).get('certified', True)
                         for name in task.get('depends', []))), None)
            if ready is None:
                continue
            allowance = sum(prep['protocol']['task_storage_allowance_GiB'][task['kind']]
                            for _, task, _ in active.values())
            allowance += prep['protocol']['task_storage_allowance_GiB'][ready['kind']]
            try:
                resources(prep['protocol'], allowance)
            except RuntimeError as error:
                resource_error = str(error); break
            pending.remove(ready)
            log = OUT / 'worker_logs' / (ready['name'] + '.log'); log.parent.mkdir(exist_ok=True)
            stream = log.open('a')
            proc = subprocess.Popen([sys.executable, '-B', str(ENTRY), 'worker', '--name', ready['name'],
                '--cpu', str(cpu)], stdout=stream, stderr=subprocess.STDOUT)
            active[cpu] = (proc, ready, stream)
            write(OUT / 'launched' / (ready['name'] + '.json'),
                  dict(pid=proc.pid, cpu=cpu, epoch=time.time()))
        for cpu, (proc, task, stream) in list(active.items()):
            if proc.poll() is None:
                continue
            stream.close(); del active[cpu]
            if proc.returncode:
                failures.append(dict(task=task['name'], returncode=proc.returncode))
        completed = sum(child_outcome(task['name']) is not None for task in tasks)
        write(OUT / 'progress.json', dict(stage=stage, active=len(active), pending=len(pending),
            completed=completed, stage_total=len(tasks), failures=failures,
            resource_error=resource_error, cpus=cpus, epoch=time.time()))
        if not active and (pending or failures or resource_error):
            raise RuntimeError('R135 queue withheld dependent work: ' +
                str((failures, resource_error, [task['name'] for task in pending])))
        if active:
            time.sleep(3)


def frozen_choices(prep):
    choices = {}
    parent_prep = read(prep['parent_preparation'])
    for region in prep['parent_protocol']['regions']:
        tasks = [task for task in prep['quantile_tasks']
                 if task['kind'] == 'internal_score' and task['region'] == region]
        results = [outcome(task['name']) for task in tasks]
        ranking, excluded = core.rank_groups(results, ['candidate_id', 'tau0'])
        if not ranking:
            raise RuntimeError('no complete certified R134 finalist for ' + region)
        winner = ranking[0]
        candidate = next(value for value in parent_prep['regional'][region]['candidates']
                         if value['candidate_id'] == winner['candidate_id'])
        choices[region] = dict(candidate, tau0=winner['tau0'], ranking=ranking,
            excluded=excluded, selected_on='three_inner_training_only_seven_quantile_AL_AQL',
            selected_before_test=True)
    immutable(OUT / 'frozen_choices.json', choices)
    return choices


def closeout(prep, tasks):
    from pricefm_r127_contract import common_metrics
    metrics = []
    for region in prep['parent_protocol']['regions']:
        for fold in (1, 2, 3):
            selected = sorted((task for task in tasks if task['kind'] == 'forecast'
                              and task['region'] == region and task['fold'] == fold),
                              key=lambda task: task['positions'][0])
            packets = []
            for task in selected:
                with np.load(OUT / 'tasks_done' / task['name'] / 'predictions.npz', allow_pickle=False) as packet:
                    packets.append({key: packet[key] for key in packet.files})
            values = {key: np.concatenate([packet[key] for packet in packets]) for key in packets[0]}
            expected = prep['official_protocol']['test_origin_counts'][fold - 1]
            if not np.array_equal(values['positions'], np.arange(expected)):
                raise RuntimeError('incomplete official fold forecast cohort')
            reference = next(value for value in prep['references']
                             if value['region'] == region and value['fold'] == fold)
            for operator in ('cdf_pool_clipped', 'mean_feature', 'path_specific', 'normal_driver'):
                metrics.append(dict(region=region, fold=fold, operator=operator,
                    **common_metrics(values['truth'], values[operator]), **{key: reference[key] for key in
                    ('qdesn_AQL', 'pricefm_AQL', 'operational_pricefm_AQL')}))
    folder = OUT / 'closeout'; folder.mkdir(exist_ok=True)
    table = pd.DataFrame(metrics); table.to_csv(folder / 'fold_comparison.csv', index=False)
    table.groupby(['region', 'operator'], as_index=False).mean(numeric_only=True).to_csv(
        folder / 'region_comparison.csv', index=False)
    write(folder / 'interpretation.json', dict(primary_operator='cdf_pool_clipped',
        authority_replaced=False, promotion_authorized=False, all_region_rollout_authorized=False,
        parent_campaign=PARENT_TAG, recovery='independent_same_state_fixedpoint_certification',
        inference='independent_AL_VB_with_stochastic_Normal_RHS_VB_driver_not_MCMC_or_joint',
        selection='three_inner_training_splits_only_before_official_test',
        decision='complete_three_region_evidence_for_review_not_automatic_promotion'))
    seal(folder, dict(source=prep['source'], parent_source=prep['parent_source'],
        complete_regions=3, complete_folds=9))
    write(OUT / 'terminal.json', dict(status='R135_COMPLETE_NOT_PROMOTED', regions=3,
        recovered_medians=14, repeated_screening=0, official_folds=9,
        source=prep['source'], parent_source=prep['parent_source']))


def controller(workers):
    prep = read(PREP / 'preparation.json'); setup(Path(prep['dependency'])); prep = valid()
    if os.environ.get(prep['protocol']['launch_approval_environment']) != 'true':
        raise RuntimeError('explicit R135 launch approval environment is required')
    if not 1 <= workers <= prep['protocol']['maximum_workers']:
        raise ValueError('R135 worker count outside the audited bound')
    with (OUT / 'controller.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for path in Path('/proc').glob('[0-9]*/cmdline'):
            try:
                command = path.read_bytes().split(b'\0')
            except OSError:
                continue
            if str(ENTRY).encode() in command and b'worker' in command:
                raise RuntimeError('live R135 worker detected; refusing duplicate controller')
        cpus = core.physical_cpus(workers)
        if len(cpus) < workers:
            raise RuntimeError(f'only {len(cpus)} idle physical cores available; requested {workers}')
        resources(prep['protocol'], len(cpus) * prep['protocol']['worker_storage_allowance_GiB'])
        write(OUT / 'controller_identity.json', dict(pid=os.getpid(), host=socket.gethostname(),
            source=prep['source'], parent_source=prep['parent_source'], cpus=cpus,
            requested_workers=workers, epoch=time.time()))
        try:
            batch(prep['certificate_tasks'], cpus, prep, 'r134_median_fixedpoint_certification')
            if not all(outcome(task['parent_name']) and outcome(task['parent_name'])['certified']
                       for task in prep['certificate_tasks']):
                raise RuntimeError('not every R134 median passed independent fixed-point certification')
            batch(prep['pending_internal_tasks'], cpus, prep, 'r134_remaining_internal_quantile_DAG')
            choices = frozen_choices(prep)
            PARENT.OUT = OUT
            full = PARENT.full_tasks(read(prep['parent_preparation']), choices)
            batch(full, cpus, prep, 'r134_frozen_winner_official_refit_and_forecast')
            valid(); verify_hashes(prep['parent_input_sha256'])
            for task in [*prep['certificate_tasks'], *prep['pending_internal_tasks'], *full]:
                verified(OUT / 'tasks_done' / task['name'])
            closeout(prep, full)
        except Exception as error:
            write(OUT / 'blocked.json', dict(error=str(error), epoch=time.time(), source=prep['source'],
                parent_source=prep['parent_source'], no_automatic_budget_change=True,
                existing_evidence_preserved=True))
            raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'controller', 'worker'))
    parser.add_argument('--dependency', type=Path); parser.add_argument('--workers', type=int, default=30)
    parser.add_argument('--name'); parser.add_argument('--cpu', type=int)
    args = parser.parse_args()
    if args.action == 'prepare':
        print(prepare(args.dependency), flush=True)
    else:
        prep = json.loads((PREP / 'preparation.json').read_text()); setup(Path(prep['dependency']))
        if args.action == 'controller':
            controller(args.workers)
        else:
            worker(args.name, args.cpu)
