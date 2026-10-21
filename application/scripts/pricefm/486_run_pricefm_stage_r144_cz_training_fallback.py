#!/usr/bin/env python3
"""Complete CZ with a predetermined train-only fallback after R143 drains."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time

import numpy as np

for variable in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS',
                 'BLIS_NUM_THREADS', 'NUMEXPR_NUM_THREADS', 'R_DATATABLE_NUM_THREADS'):
    os.environ[variable] = '1'
os.environ['PYTHONDONTWRITEBYTECODE'] = '1'

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
CONFIG = ROOT / 'application/config/pricefm_stage_r144_cz_training_fallback_20261020.json'


def read(path):
    return json.loads(Path(path).read_text())


def sha256(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def atomic_json(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f'.tmp.{os.getpid()}')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    os.replace(temporary, path)


def immutable_json(path, value):
    path = Path(path)
    if path.exists():
        if read(path) != value:
            raise RuntimeError('immutable JSON differs: ' + str(path))
        return
    atomic_json(path, value)


def git(root, *arguments):
    return subprocess.check_output(['git', *arguments], cwd=root, text=True).strip()


def source_identity(root=ROOT):
    identity = {'branch': git(root, 'branch', '--show-current'),
                'head': git(root, 'rev-parse', 'HEAD')}
    if not identity['branch'].startswith('work/pricefm-r144-cz-training-fallback-'):
        raise RuntimeError('dedicated R144 source branch required')
    if git(root, 'status', '--porcelain'):
        raise RuntimeError('clean committed R144 source worktree required')
    return identity


def campaign(config):
    return DATA / 'campaigns' / config['tag']


def preparation_root(config):
    return DATA / 'launch_prep' / config['tag']


def source_campaign(config):
    return DATA / 'campaigns' / f"{config['source_tag']}__{config['region']}"


def source_preparation(config):
    return DATA / 'launch_prep' / f"{config['source_tag']}__{config['region']}" / 'preparation.json'


def predecessor_terminal(config):
    return DATA / 'launch_prep' / config['predecessor_tag'] / 'jerez/terminal.json'


def host_health(config):
    memory = {line.split(':')[0]: int(line.split()[1])
              for line in Path('/proc/meminfo').read_text().splitlines()}
    stat = os.statvfs(DATA)
    state = {
        'available_memory_GiB': memory['MemAvailable'] / 2**20,
        'free_disk_GiB': stat.f_bavail * stat.f_frsize / 2**30,
        'memory_floor_GiB': config['minimum_available_memory_GiB'],
        'disk_floor_GiB': config['minimum_free_disk_GiB'],
    }
    state['healthy'] = (state['available_memory_GiB'] >= state['memory_floor_GiB']
                        and state['free_disk_GiB'] >= state['disk_floor_GiB'])
    return state


def physical_topology():
    topology = {}
    for line in subprocess.check_output(['lscpu', '-p=CPU,CORE,SOCKET'], text=True).splitlines():
        if line.startswith('#') or not line.strip():
            continue
        cpu, core, package = map(int, line.split(','))
        topology[cpu] = (package, core)
    return topology


def command_lines():
    values = []
    for path in Path('/proc').glob('[0-9]*/cmdline'):
        try:
            command = path.read_bytes().replace(b'\0', b' ').decode(errors='replace')
        except OSError:
            continue
        values.append((int(path.parent.name), command))
    return values


def tree_hashes(folder):
    folder = Path(folder)
    return {str(path.relative_to(folder)): sha256(path)
            for path in sorted(folder.rglob('*')) if path.is_file()}


def hardlink_tree(source, destination):
    source, destination = Path(source), Path(destination)
    expected = tree_hashes(source)
    if destination.exists():
        if tree_hashes(destination) != expected:
            raise RuntimeError('existing hard-link destination differs: ' + str(destination))
        return
    temporary = destination.with_name(destination.name + f'.import.{os.getpid()}')
    if temporary.exists():
        shutil.rmtree(temporary)
    temporary.mkdir(parents=True)
    try:
        for path in sorted(source.rglob('*')):
            if path.is_symlink():
                raise RuntimeError('symbolic link found in frozen evidence: ' + str(path))
            relative = path.relative_to(source); target = temporary / relative
            if path.is_dir():
                target.mkdir(exist_ok=True)
            elif path.is_file():
                target.parent.mkdir(parents=True, exist_ok=True)
                os.link(path, target)
        if tree_hashes(temporary) != expected:
            raise RuntimeError('hard-link import changed evidence: ' + str(source))
        os.replace(temporary, destination)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def load_engine(config):
    os.environ['PRICEFM_R141_REGION'] = config['region']
    path = Path(config['source_worktree']) / 'application/scripts/pricefm/480_run_pricefm_stage_r141_region.py'
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location('pricefm_r141_frozen_engine', path)
    engine = importlib.util.module_from_spec(spec); spec.loader.exec_module(engine)
    engine.TAG = config['tag']
    engine.OUT = campaign(config)
    engine.PREP = preparation_root(config)
    engine.ENTRY = ENTRY
    engine.source_identity = source_identity
    return engine


def assert_contract(config, require_host=True):
    forbidden = ('test_data_access_authorized', 'posterior_target_changes_authorized',
                 'certificate_limit_changes_authorized', 'registry_mutation_authorized',
                 'article_mutation_authorized', 'promotion_authorized')
    fallback = config['fallback_candidate']
    if (config['tag'] != 'pricefm_stage_r144_cz_training_fallback_20261020'
            or config['region'] != 'CZ' or config['fallback_rank'] != 3
            or fallback['candidate_id'] != 'r134_56a8ee2629e2b168'
            or not np.isclose(fallback['tau0'], 0.00018443953471560665, rtol=1e-14, atol=0)
            or config['maximum_workers'] != 15 or config['al_max_iter'] != 300
            or any(config[key] is not False for key in forbidden)):
        raise ValueError('R144 bounded fallback contract differs')
    if require_host and socket.gethostname().split('.')[0].lower() != config['host']:
        raise RuntimeError('R144 numerical work is restricted to Jerez')
    topology = physical_topology()
    cpus = config['cpus']
    if (len(cpus) != 15 or len(cpus) != len(set(cpus))
            or any(cpu not in os.sched_getaffinity(0) for cpu in cpus)
            or len({topology[cpu] for cpu in cpus}) != len(cpus)):
        raise RuntimeError('R144 requires 15 distinct allowed physical cores')
    for worktree_key, branch_key, head_key in (
            ('source_worktree', 'source_branch', 'source_head'),
            ('predecessor_worktree', 'predecessor_branch', 'predecessor_head')):
        worktree = Path(config[worktree_key])
        if (git(worktree, 'branch', '--show-current') != config[branch_key]
                or git(worktree, 'rev-parse', 'HEAD') != config[head_key]
                or git(worktree, 'status', '--porcelain')):
            raise RuntimeError('frozen predecessor worktree differs: ' + str(worktree))
    for relative, expected in config['frozen_source_sha256'].items():
        if sha256(Path(config['source_worktree']) / relative) != expected:
            raise RuntimeError('frozen R141 source differs: ' + relative)
    predecessor_files = {
        'application/config/pricefm_stage_r143_cz_quarantine_queue_recovery_20261020.json':
            config['predecessor_config_sha256'],
        'application/scripts/pricefm/485_run_pricefm_stage_r143_cz_quarantine_queue.py':
            config['predecessor_controller_sha256'],
    }
    for relative, expected in predecessor_files.items():
        if sha256(Path(config['predecessor_worktree']) / relative) != expected:
            raise RuntimeError('frozen R143 source differs: ' + relative)
    state = host_health(config)
    if not state['healthy']:
        raise RuntimeError('Jerez resource reserve is crossed: ' + str(state))


def slot_b_idle(config):
    source_entry = str(Path(config['source_worktree']) /
                       'application/scripts/pricefm/480_run_pricefm_stage_r141_region.py')
    cpu_text = ','.join(map(str, config['cpus']))
    conflicts = []
    for pid, command in command_lines():
        if (source_entry in command and ' controller ' in command and
                (f'--cpus {cpu_text}' in command or '--region CZ' in command)):
            conflicts.append((pid, command))
        if '484_run_pricefm_stage_r142_certified_al_rescue.py run' in command:
            conflicts.append((pid, command))
    return conflicts


def predecessor_state(config):
    path = predecessor_terminal(config)
    if not path.is_file():
        return {'ready': False, 'status': 'R143_STILL_RUNNING_OR_NOT_STARTED'}
    value = read(path); status = value.get('status')
    if status != config['predecessor_terminal_status']:
        raise RuntimeError('R143 did not finish cleanly: ' + str(value))
    return {'ready': True, 'status': status, 'terminal_sha256': sha256(path)}


def fallback_audit(config, require_idle=False, require_clean_source=True):
    assert_contract(config)
    identity = source_identity() if require_clean_source else {
        'branch': git(ROOT, 'branch', '--show-current'), 'head': git(ROOT, 'rev-parse', 'HEAD')}
    prep_path = source_preparation(config); rhs_path = source_campaign(config) / 'rhs_closeout.json'
    if sha256(prep_path) != config['source_preparation_sha256']:
        raise RuntimeError('frozen R141 CZ preparation differs')
    if sha256(rhs_path) != config['source_rhs_closeout_sha256']:
        raise RuntimeError('frozen R141 CZ RHS ranking differs')
    source_prep = read(prep_path); ranking = read(rhs_path)['CZ']['ranking']
    row = ranking[config['fallback_rank'] - 1]; expected = config['fallback_candidate']
    for key in ('candidate_id', 'mean_AQL'):
        if row[key] != expected[key]:
            raise RuntimeError('frozen fallback ranking row differs: ' + key)
    if not np.isclose(row['tau0'], expected['tau0'], rtol=1e-14, atol=0):
        raise RuntimeError('frozen fallback tau0 differs')
    if row['split_AQL'] != expected['split_AQL']:
        raise RuntimeError('frozen fallback split scores differ')
    candidate = next((value for value in source_prep['regional']['CZ']['candidates']
                      if value['candidate_id'] == expected['candidate_id']), None)
    if candidate is None or candidate['specification_sha256'] != expected['specification_sha256']:
        raise RuntimeError('frozen fallback candidate identity differs')
    if candidate['spec'] != expected['spec']:
        raise RuntimeError('frozen fallback candidate specification differs')
    source = source_campaign(config); prerequisites = []
    for name, expected_task in config['prerequisites'].items():
        task_path = source / 'tasks' / (name + '.json')
        done = source / 'tasks_done' / name
        if (sha256(task_path) != expected_task['task_sha256']
                or sha256(done / 'completed_evidence.json') != expected_task['completed_evidence_sha256']):
            raise RuntimeError('frozen prerequisite hash differs: ' + name)
        task = read(task_path); result = read(done / 'result.json')
        if task['kind'] != expected_task['kind'] or result.get('certified') is not True:
            raise RuntimeError('fallback prerequisite is not certified: ' + name)
        if task['candidate_id'] != expected['candidate_id']:
            raise RuntimeError('fallback prerequisite candidate differs: ' + name)
        if task['kind'] == 'stats' and result.get('train_only') is not True:
            raise RuntimeError('fallback statistics are not train-only: ' + name)
        if task['kind'] == 'rhs' and not np.isclose(task['tau0'], expected['tau0'], rtol=1e-14, atol=0):
            raise RuntimeError('fallback RHS tau0 differs: ' + name)
        prerequisites.append({'task': name, 'task_sha256': sha256(task_path),
                              'completed_evidence_sha256': sha256(done / 'completed_evidence.json')})
    conflicts = slot_b_idle(config) if require_idle else []
    if conflicts:
        raise RuntimeError('Jerez slot B is still occupied: ' + str(conflicts))
    return {
        'status': 'R144_AUDIT_PASS', 'passed': True, 'source': identity,
        'frozen_r141_source': {'branch': config['source_branch'], 'head': config['source_head']},
        'predecessor': predecessor_state(config),
        'fallback_rank': config['fallback_rank'], 'fallback_candidate': expected,
        'prerequisites': prerequisites, 'health': host_health(config),
        'test_used_for_selection': False, 'posterior_target_changes': 0,
        'certificate_limit_changes': 0, 'official_test_opened': False,
    }


def release(config):
    path = preparation_root(config) / 'release/jerez/validation.json'
    if path.is_file():
        value = read(path)
        if not value.get('passed') or value.get('source') != source_identity():
            raise RuntimeError('existing R144 release receipt differs')
        return value
    report = fallback_audit(config, require_idle=False)
    report['tests_required_before_launch'] = [
        'application/tests/test_pricefm_stage_r144_cz_training_fallback.py',
        'application/tests/test_pricefm_stage_r141_recovery_rollout.py',
        'application/tests/test_pricefm_stage_r143_cz_quarantine_queue.py',
    ]
    immutable_json(path, report)
    return report


def prepare(config):
    report = fallback_audit(config, require_idle=True); receipt = release(config)
    destination = campaign(config); prep_root = preparation_root(config)
    engine = load_engine(config)
    source_prep = read(source_preparation(config)); engine.setup(Path(source_prep['dependency']))
    prep_path = prep_root / 'preparation.json'
    if prep_path.is_file():
        prep = engine.valid()
        return {'status': 'R144_ALREADY_PREPARED', 'source': prep['source'],
                'imported_prerequisites': len(config['prerequisites'])}
    candidate = next(value for value in source_prep['regional']['CZ']['candidates']
                     if value['candidate_id'] == config['fallback_candidate']['candidate_id'])
    protocol = dict(source_prep['protocol'])
    protocol.update(tag=config['tag'], regions=['CZ'], maximum_workers=config['maximum_workers'],
                    maximum_workers_per_region=config['maximum_workers'], quantile_finalists=1,
                    al_max_iter=config['al_max_iter'],
                    minimum_free_disk_GiB=config['minimum_free_disk_GiB'])
    bank_matches = [Path(path) for path in source_prep['bank_sha256']
                    if Path(path).name == candidate['spec']['feature_policy'] + '.npz']
    if len(bank_matches) != 1:
        raise RuntimeError('frozen fallback does not have exactly one matching training bank')
    source_bank = bank_matches[0]
    target_bank = destination / 'training_banks/CZ' / source_bank.name
    target_bank.parent.mkdir(parents=True, exist_ok=True)
    if target_bank.exists():
        if sha256(target_bank) != sha256(source_bank):
            raise RuntimeError('existing R144 training bank differs')
    else:
        os.link(source_bank, target_bank)
    imported = []
    for name in config['prerequisites']:
        source_task = source_campaign(config) / 'tasks' / (name + '.json')
        target_task = destination / 'tasks' / (name + '.json')
        target_task.parent.mkdir(parents=True, exist_ok=True)
        if target_task.exists():
            if sha256(target_task) != sha256(source_task):
                raise RuntimeError('existing imported task differs: ' + name)
        else:
            os.link(source_task, target_task)
        source_done = source_campaign(config) / 'tasks_done' / name
        target_done = destination / 'tasks_done' / name
        target_done.parent.mkdir(parents=True, exist_ok=True)
        hardlink_tree(source_done, target_done)
        imported.append({'name': name, 'source': str(source_done),
                         'source_evidence_sha256': sha256(source_done / 'completed_evidence.json'),
                         'destination': str(target_done)})
    identity = source_identity()
    source_paths = [CONFIG, ENTRY,
        ROOT / 'application/scripts/pricefm/487_closeout_pricefm_stage_r144_all_region.py',
        ROOT / 'application/tests/test_pricefm_stage_r144_cz_training_fallback.py',
        ROOT / 'docs/implementation_notes/pricefm_stage_r144_cz_training_fallback_20261020.md']
    sources = dict(source_prep['source_sha256'])
    sources.update({str(path): sha256(path) for path in source_paths})
    release_path = preparation_root(config) / 'release/jerez/validation.json'
    prep = {
        'source': identity, 'dependency': source_prep['dependency'],
        'dependency_head': source_prep['dependency_head'], 'protocol': protocol,
        'official_protocol': source_prep['official_protocol'], 'template': source_prep['template'],
        'control': source_prep['control'],
        'regional': {'CZ': {'candidates': [candidate],
                            'protected_candidates': [candidate['candidate_id']],
                            'protected_tau0': config['fallback_candidate']['tau0']}},
        'tasks': [], 'references': source_prep['references'],
        'design_audit': {'CZ': {'retained': 1, 'selection': 'predetermined_training_only_RHS_rank_3'}},
        'source_sha256': sources, 'input_sha256': source_prep['input_sha256'],
        'bank_sha256': {str(target_bank): sha256(target_bank)},
        'release_path': str(release_path), 'release_sha256': sha256(release_path),
        'historical_fits_used_for_selection': 0, 'training_only_prerequisite_fits_reused': 6,
        'test_used_for_selection': False, 'official_development_test_seen_previously': True,
        'raw_identity': source_prep['raw_identity'],
        'fallback_selection': {'rank': config['fallback_rank'], 'candidate': config['fallback_candidate'],
                               'source_rhs_closeout': str(source_campaign(config) / 'rhs_closeout.json'),
                               'source_rhs_closeout_sha256': config['source_rhs_closeout_sha256']},
        'r141_preparation_sha256': config['source_preparation_sha256'],
        'r144_release': receipt,
    }
    engine.immutable(prep_path, prep)
    immutable_json(destination / 'prerequisite_import.json', {
        'status': 'R144_CERTIFIED_TRAIN_ONLY_PREREQUISITES_IMPORTED',
        'source': report['frozen_r141_source'], 'fallback': config['fallback_candidate'],
        'imports': imported, 'test_opened': False, 'hard_links_used': True,
    })
    engine.valid()
    return {'status': 'R144_PREPARED', 'source': identity,
            'imported_prerequisites': len(imported), 'fallback_rank': config['fallback_rank']}


def complete(config):
    root = campaign(config); terminal = root / 'terminal.json'
    evidence = root / 'closeout/completed_evidence.json'
    if not terminal.is_file() or not evidence.is_file():
        return False
    value = read(terminal)
    return (value.get('status') == 'R144_CZ_FALLBACK_COMPLETE_NOT_PROMOTED'
            and value.get('source') == source_identity())


def controller(config):
    if complete(config):
        return read(campaign(config) / 'terminal.json')
    fallback_audit(config, require_idle=True)
    prep = prepare(config); del prep
    engine = load_engine(config); prepared = read(preparation_root(config) / 'preparation.json')
    engine.setup(Path(prepared['dependency'])); prepared = engine.valid()
    output = campaign(config); output.mkdir(parents=True, exist_ok=True)
    with (output / 'controller.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        cpus = engine.declared_cpus(','.join(map(str, config['cpus'])), config['maximum_workers'])
        try:
            rhs = [read(output / 'tasks' / (name + '.json'))
                   for name, value in config['prerequisites'].items() if value['kind'] == 'rhs']
            quantile = engine.quantile_tasks(prepared, rhs)
            selected = read(output / 'rhs_closeout.json')['CZ']['finalists']
            if (len(selected) != 1
                    or selected[0]['candidate_id'] != config['fallback_candidate']['candidate_id']
                    or not np.isclose(selected[0]['tau0'], config['fallback_candidate']['tau0'],
                                      rtol=1e-14, atol=0)):
                raise RuntimeError('R144 quantile confirmation did not retain the frozen fallback')
            engine.batch(quantile, cpus, prepared, 'fallback_training_only_seven_quantile_AL_confirmation')
            choices = engine.frozen_choices(prepared, quantile)
            choice = choices['CZ']
            if (choice['candidate_id'] != config['fallback_candidate']['candidate_id']
                    or not np.isclose(choice['tau0'], config['fallback_candidate']['tau0'], rtol=1e-14, atol=0)):
                raise RuntimeError('R144 fallback changed after train-only quantile confirmation')
            full = engine.full_tasks(prepared, choices)
            engine.batch(full, cpus, prepared, 'fallback_full_folds_nested_AL_and_forecast')
            engine.valid(); engine.verify_hashes(prepared['input_sha256'])
            for task in [*quantile, *full]:
                engine.verified(output / 'tasks_done' / task['name'])
            immutable_json(output / 'fallback_provenance.json', {
                'status': 'R144_PREDETERMINED_TRAINING_ONLY_FALLBACK_COMPLETED',
                'fallback_rank': config['fallback_rank'], 'fallback_candidate': config['fallback_candidate'],
                'source_r141_head': config['source_head'], 'source_rhs_closeout_sha256':
                    config['source_rhs_closeout_sha256'],
                'test_used_for_selection': False, 'posterior_target_changed': False,
                'certificate_limits_changed': False, 'source': source_identity(),
            })
            engine.closeout(prepared, full)
            terminal = {
                'status': 'R144_CZ_FALLBACK_COMPLETE_NOT_PROMOTED', 'region': 'CZ',
                'fallback_rank': config['fallback_rank'], 'fallback_candidate': config['fallback_candidate'],
                'source': source_identity(), 'source_r141_head': config['source_head'],
                'test_used_for_selection': False, 'authority_mutated': False,
                'article_mutated': False, 'promotion_decided': False,
                'full_fits': 24, 'official_origin_region_pairs':
                    sum(prepared['official_protocol']['test_origin_counts']),
            }
            atomic_json(output / 'terminal.json', terminal)
            return terminal
        except Exception as error:
            atomic_json(output / 'blocked.json', {
                'status': 'R144_BLOCKED_WITH_EVIDENCE_PRESERVED', 'error': str(error),
                'source': source_identity(), 'no_automatic_budget_change': True,
                'no_certificate_relaxation': True, 'epoch': time.time(),
            })
            raise


def worker(config, name, cpu):
    engine = load_engine(config)
    prepared = read(preparation_root(config) / 'preparation.json')
    engine.setup(Path(prepared['dependency']))
    engine.worker(name, cpu)


def run(config, poll_seconds=None):
    poll = poll_seconds or config['wait_poll_seconds']
    runtime = preparation_root(config) / 'jerez'; runtime.mkdir(parents=True, exist_ok=True)
    with (runtime / 'supervisor.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        release(config)
        while True:
            predecessor = predecessor_state(config)
            if predecessor['ready']:
                break
            state = {'status': 'R144_WAITING_FOR_R143_SLOT_B', 'predecessor': predecessor,
                     'health': host_health(config), 'source': source_identity(), 'epoch': time.time()}
            atomic_json(runtime / 'progress.json', state)
            if not state['health']['healthy']:
                raise RuntimeError('resource reserve crossed while waiting for R143')
            time.sleep(poll)
        conflicts = slot_b_idle(config)
        while conflicts:
            atomic_json(runtime / 'progress.json', {
                'status': 'R144_WAITING_FOR_SLOT_B_PROCESS_EXIT', 'conflicts': conflicts,
                'health': host_health(config), 'source': source_identity(), 'epoch': time.time()})
            time.sleep(poll); conflicts = slot_b_idle(config)
        atomic_json(runtime / 'progress.json', {
            'status': 'R144_STARTING_CZ_FALLBACK', 'predecessor': predecessor,
            'health': host_health(config), 'source': source_identity(), 'epoch': time.time()})
        result = controller(config)
        atomic_json(runtime / 'terminal.json', result)
        return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('audit', 'release', 'prepare', 'controller', 'worker', 'run', 'status'))
    parser.add_argument('--region', choices=('CZ',)); parser.add_argument('--name'); parser.add_argument('--cpu', type=int)
    parser.add_argument('--poll-seconds', type=int)
    arguments = parser.parse_args(); configuration = read(CONFIG)
    if arguments.action == 'audit':
        value = fallback_audit(configuration, require_idle=False)
    elif arguments.action == 'release':
        value = release(configuration)
    elif arguments.action == 'prepare':
        value = prepare(configuration)
    elif arguments.action == 'controller':
        value = controller(configuration)
    elif arguments.action == 'worker':
        if arguments.region != configuration['region']:
            raise RuntimeError('worker region differs from the frozen R144 region')
        worker(configuration, arguments.name, arguments.cpu); value = {'status': 'worker_complete'}
    elif arguments.action == 'run':
        value = run(configuration, arguments.poll_seconds)
    else:
        path = preparation_root(configuration) / 'jerez/progress.json'
        value = read(path) if path.is_file() else {'status': 'R144_NOT_STARTED'}
    print(json.dumps(value, indent=2, sort_keys=True), flush=True)
