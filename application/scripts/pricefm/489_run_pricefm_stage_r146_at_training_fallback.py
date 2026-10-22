#!/usr/bin/env python3
"""Complete AT with a rank-locked train-only fallback after the failed R145 lane drains."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
import re
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
CONFIG = ROOT / 'application/config/pricefm_stage_r146_at_training_fallback_20261022.json'


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
    if not identity['branch'].startswith('work/pricefm-r146-at-training-fallback-'):
        raise RuntimeError('dedicated R146 source branch required')
    if git(root, 'status', '--porcelain'):
        raise RuntimeError('clean committed R146 source worktree required')
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
    return DATA / 'launch_prep' / config['predecessor_tag'] / 'muscat/at.terminal.json'

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
    if (config['tag'] != 'pricefm_stage_r146_at_training_fallback_20261022'
            or config['region'] != 'AT' or config['fallback_rank'] != 4
            or fallback['candidate_id'] != 'r134_7a422c0c3473f81f'
            or not np.isclose(fallback['tau0'], 0.0016320908467640013, rtol=1e-14, atol=0)
            or config['maximum_workers'] != 8 or config['al_max_iter'] != 300
            or config['cpus'] != list(range(8)) or len(config['prerequisites']) != 6
            or 1 + sum(fallback['spec']['units']) != 577
            or any(config[key] is not False for key in forbidden)):
        raise ValueError('R146 bounded fallback contract differs')
    if require_host and socket.gethostname().split('.')[0].lower() != config['host']:
        raise RuntimeError('R146 numerical work is restricted to Muscat')
    topology = physical_topology()
    cpus = config['cpus']
    if (len(cpus) != 8 or len(cpus) != len(set(cpus))
            or any(cpu not in os.sched_getaffinity(0) for cpu in cpus)
            or len({topology[cpu] for cpu in cpus}) != len(cpus)):
        raise RuntimeError('R146 requires 8 distinct allowed physical cores')
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
    for relative, expected in config['predecessor_frozen_sha256'].items():
        if sha256(Path(config['predecessor_worktree']) / relative) != expected:
            raise RuntimeError('frozen R145 source differs: ' + relative)
    if Path(sys.executable).resolve() != Path(config['python_runtime']).resolve():
        raise RuntimeError('R146 requires the pinned campaign Python runtime')
    state = host_health(config)
    if not state['healthy']:
        raise RuntimeError('Muscat resource reserve is crossed: ' + str(state))


def slot_a_conflicts(config):
    """Identify overlapping PriceFM numerical workers or explicitly owned controllers."""
    target = set(config['cpus']); conflicts = []
    for pid, command in command_lines():
        if pid == os.getpid() or 'pricefm' not in command.lower():
            continue
        cpu_match = re.search(r'--cpus(?:=| +)([0-9,]+)', command)
        if ' controller ' in command and cpu_match:
            owned = {int(value) for value in cpu_match.group(1).split(',')}
        elif (' worker ' in command or ' --file=' in command or 'Rscript ' in command):
            try:
                owned = set(os.sched_getaffinity(pid))
            except ProcessLookupError:
                continue
            except PermissionError as error:
                raise RuntimeError('cannot establish numerical process CPU ownership') from error
        elif ' controller ' in command and '--region AT' in command:
            owned = target
        else:
            continue
        if owned & target:
            conflicts.append({'pid': pid, 'cpus': sorted(owned & target), 'command': command})
    return conflicts

def predecessor_state(config):
    runtime = DATA / 'launch_prep' / config['predecessor_tag'] / 'muscat'
    terminal = predecessor_terminal(config); quarantine = runtime / 'quarantine/AT.json'
    if not terminal.is_file() or not quarantine.is_file():
        return {'ready': False, 'status': 'R145_AT_LANE_STILL_DRAINING',
                'lane_terminal_present': terminal.is_file(),
                'quarantine_present': quarantine.is_file()}
    value = read(terminal); failure = read(quarantine)
    if (value.get('status') != config['predecessor_terminal_status']
            or value.get('lane') != 'at' or value.get('completed')
            or not any(item.get('region') == 'AT' for item in value.get('failures', []))
            or failure.get('region') != 'AT' or failure.get('lane') != 'at'
            or failure.get('error_type') != 'RuntimeError'
            or not failure.get('reason', '').startswith('bounded rescue exhausted without certification: ')
            or failure.get('test_opened') is not False
            or failure.get('posterior_target_changed') is not False):
        raise RuntimeError('R145 AT lane did not close with the expected bounded rescue quarantine')
    audit = runtime / 'audit.json'; identity = read(audit).get('source')
    if identity != {'branch': config['predecessor_branch'], 'head': config['predecessor_head']}:
        raise RuntimeError('R145 AT predecessor audit source differs')
    return {'ready': True, 'status': value['status'],
            'terminal_sha256': sha256(terminal), 'quarantine_sha256': sha256(quarantine),
            'audit_sha256': sha256(audit)}

def verified_packet(folder):
    folder = Path(folder)
    seal = read(folder / 'completed_evidence.json')
    if not isinstance(seal.get('artifacts'), dict) or not seal['artifacts']:
        raise RuntimeError('missing packet artifact ledger: ' + str(folder))
    for relative, expected in seal['artifacts'].items():
        path = Path(relative)
        if path.is_absolute() or '..' in path.parts:
            raise RuntimeError('unsafe packet artifact path')
        source = folder / path
        if source.is_symlink() or not source.is_file() or sha256(source) != expected:
            raise RuntimeError('packet artifact hash differs: ' + str(source))
    return seal['metadata']


def exhausted_evidence(config):
    if len(config['exhausted_rescues']) != 4:
        raise RuntimeError('four immutable exhausted AT tasks required')
    evidence = []
    for name, expected in config['exhausted_rescues'].items():
        directory = Path(expected['attempt_dir'])
        if (sha256(directory / 'completed_evidence.json') != expected['completed_evidence_sha256']
                or sha256(directory / 'fit/terminal.json') != expected['terminal_sha256']):
            raise RuntimeError('exhausted AT rescue evidence differs: ' + name)
        metadata = verified_packet(directory); terminal = read(directory / 'fit/terminal.json')
        if (metadata.get('certified') is not False or metadata.get('task_name') != name
                or metadata.get('attempt') != 2 or terminal.get('iterations') != 300
                or terminal.get('rescue_attempt_index') != 2
                or terminal.get('cumulative_iteration_budget') != 900
                or terminal.get('computationally_certified') is not False
                or terminal.get('finite_core') is not True
                or terminal.get('termination') != 'iteration_cap_uncertified'
                or any(terminal.get(key) is not False for key in
                       ('test_opened', 'posterior_target_changed', 'prior_center_from_initializer',
                        'certificate_limits_changed'))):
            raise RuntimeError('AT prerequisite is not an exhausted unchanged-target rescue: ' + name)
        evidence.append({'task': name, **expected})
    return evidence


def selected_training_bank(source_prep, candidate):
    matches = [Path(path) for path in source_prep['bank_sha256']
               if Path(path).name == candidate['spec']['feature_policy'] + '.npz']
    if len(matches) != 1:
        raise RuntimeError('fallback requires exactly one frozen matching training bank')
    path = matches[0]; expected = source_prep['bank_sha256'][str(path)]
    if path.is_symlink() or sha256(path) != expected:
        raise RuntimeError('frozen source training bank differs')
    return path, expected


def owned_source_paths():
    return [CONFIG, ENTRY,
        ROOT / 'application/scripts/pricefm/490_closeout_pricefm_stage_r146_all_region.py',
        ROOT / 'application/scripts/pricefm/491_supervise_pricefm_stage_r146_resource_handoff.py',
        ROOT / 'application/config/pricefm_stage_r146_resource_handoff_20261022.json',
        ROOT / 'application/tests/test_pricefm_stage_r146_at_training_fallback.py',
        ROOT / 'application/tests/test_pricefm_stage_r146_all_region_closeout.py',
        ROOT / 'application/tests/test_pricefm_stage_r146_resource_handoff.py',
        ROOT / 'docs/implementation_notes/pricefm_stage_r146_at_training_fallback_20261022.md']


def fallback_audit(config, require_idle=False, require_clean_source=True):
    assert_contract(config)
    identity = source_identity() if require_clean_source else {
        'branch': git(ROOT, 'branch', '--show-current'), 'head': git(ROOT, 'rev-parse', 'HEAD')}
    prep_path = source_preparation(config); rhs_path = source_campaign(config) / 'rhs_closeout.json'
    if sha256(prep_path) != config['source_preparation_sha256']:
        raise RuntimeError('frozen R141 AT preparation differs')
    if sha256(rhs_path) != config['source_rhs_closeout_sha256']:
        raise RuntimeError('frozen R141 AT RHS ranking differs')
    source_prep = read(prep_path); ranking = read(rhs_path)['AT']['ranking']
    import_path = source_campaign(config) / 'recovery_import.json'
    if sha256(import_path) != config['source_recovery_import_sha256']:
        raise RuntimeError('R141 R140 import provenance differs')
    recovery = read(import_path)
    if (recovery.get('status') != 'R141_R140_PREREQUISITES_IMPORTED'
            or recovery.get('region') != 'AT'
            or recovery.get('source_head') != source_prep['protocol']['recovery_source']['head']):
        raise RuntimeError('AT import source is not the frozen R140 predecessor')
    exhausted = exhausted_evidence(config)
    row = ranking[config['fallback_rank'] - 1]; expected = config['fallback_candidate']
    attempted = {item['candidate_id'] for item in read(rhs_path)['AT']['finalists']}
    first_distinct = next((index + 1 for index, item in enumerate(ranking)
                           if item['candidate_id'] not in attempted), None)
    if first_distinct != config['fallback_rank'] or expected['candidate_id'] in attempted:
        raise RuntimeError('fallback is not the first untried distinct training-ranked DESN')
    for key in ('candidate_id', 'mean_AQL'):
        if row[key] != expected[key]:
            raise RuntimeError('frozen fallback ranking row differs: ' + key)
    if not np.isclose(row['tau0'], expected['tau0'], rtol=1e-14, atol=0):
        raise RuntimeError('frozen fallback tau0 differs')
    if row['split_AQL'] != expected['split_AQL']:
        raise RuntimeError('frozen fallback split scores differ')
    candidate = next((value for value in source_prep['regional']['AT']['candidates']
                      if value['candidate_id'] == expected['candidate_id']), None)
    if candidate is None or candidate['specification_sha256'] != expected['specification_sha256']:
        raise RuntimeError('frozen fallback candidate identity differs')
    if candidate['spec'] != expected['spec']:
        raise RuntimeError('frozen fallback candidate specification differs')
    selected_training_bank(source_prep, candidate)
    for ledger in ('input_sha256', 'source_sha256'):
        for path, expected_hash in source_prep.get(ledger, {}).items():
            if sha256(path) != expected_hash:
                raise RuntimeError('frozen source preparation ledger differs: ' + path)
    source = source_campaign(config); prerequisites = []
    for name, expected_task in config['prerequisites'].items():
        task_path = source / 'tasks' / (name + '.json')
        done = source / 'tasks_done' / name
        if (sha256(task_path) != expected_task['task_sha256']
                or sha256(done / 'completed_evidence.json') != expected_task['completed_evidence_sha256']):
            raise RuntimeError('frozen prerequisite hash differs: ' + name)
        task = read(task_path); result = read(done / 'result.json')
        metadata = verified_packet(done)
        provenance = recovery.get('imported', {}).get(name)
        if (provenance is None or provenance['kind'] != expected_task['kind']
                or provenance['task_sha256'] != expected_task['task_sha256']
                or provenance['completed_evidence_sha256'] != expected_task['completed_evidence_sha256']
                or metadata.get('source_head') != expected_task['source_head']
                or metadata.get('source_head') != recovery['source_head']
                or metadata.get('task_sha256') != expected_task['task_sha256']
                or metadata.get('certified') is not True
                or task.get('region') != 'AT' or task.get('split') != expected_task['split']
                or task.get('kind') not in ('stats', 'rhs')):
            raise RuntimeError('original R140 prerequisite provenance differs: ' + name)
        if task['kind'] == 'rhs':
            terminal = read(done / 'fit/terminal.json')
            if (terminal.get('full_variational_certified') is not True
                    or terminal.get('test_opened') is not False
                    or terminal.get('prior_center_from_initializer') is not False
                    or terminal.get('p') != 577):
                raise RuntimeError('fallback RHS is not fully certified and prior-clean: ' + name)
        if task['kind'] != expected_task['kind'] or result.get('certified') is not True:
            raise RuntimeError('fallback prerequisite is not certified: ' + name)
        if task['candidate_id'] != expected['candidate_id']:
            raise RuntimeError('fallback prerequisite candidate differs: ' + name)
        if task['kind'] == 'stats' and result.get('train_only') is not True:
            raise RuntimeError('fallback statistics are not train-only: ' + name)
        if task['kind'] == 'rhs' and not np.isclose(task['tau0'], expected['tau0'], rtol=1e-14, atol=0):
            raise RuntimeError('fallback RHS tau0 differs: ' + name)
        prerequisites.append({'task': name, 'original_source_head': metadata['source_head'],
                              'r141_import_record': provenance, 'task_sha256': sha256(task_path),
                              'completed_evidence_sha256': sha256(done / 'completed_evidence.json')})
    predecessor = predecessor_state(config)
    if require_idle and not predecessor['ready']:
        raise RuntimeError('R145 AT lane has not finished draining')
    conflicts = slot_a_conflicts(config) if require_idle else []
    if conflicts:
        raise RuntimeError('Muscat AT slot is still occupied: ' + str(conflicts))
    return {
        'status': 'R146_AUDIT_PASS', 'passed': True, 'source': identity,
        'frozen_r141_source': {'branch': config['source_branch'], 'head': config['source_head']},
        'predecessor': predecessor, 'exhausted_rescues': exhausted,
        'fallback_rank': config['fallback_rank'], 'fallback_candidate': expected,
        'prerequisites': prerequisites, 'health': host_health(config),
        'test_used_for_selection': False, 'posterior_target_changes': 0,
        'posterior_target_change_scope': 'within_each_fit', 'model_choice_changed': True,
        'same_target_resumption': False,
        'fallback_changes_posterior_target_relative_to_failed_model': True,
        'certificate_limit_changes': 0, 'official_test_opened': False,
    }


def release(config):
    path = preparation_root(config) / 'release/muscat/validation.json'
    if path.is_file():
        value = read(path)
        if (not value.get('passed') or value.get('source') != source_identity()
                or value.get('regression_validation', {}).get('passed') is not True):
            raise RuntimeError('existing R146 release receipt differs')
        return value
    report = fallback_audit(config, require_idle=False)
    report['tests_required_before_launch'] = [
        'application/tests/test_pricefm_stage_r146_at_training_fallback.py',
        'application/tests/test_pricefm_stage_r146_all_region_closeout.py',
        'application/tests/test_pricefm_stage_r146_resource_handoff.py',
        'application/tests/test_pricefm_stage_r141_recovery_rollout.py',
        'application/tests/test_pricefm_stage_r145_at_recovery_muscat_utilization.py',
    ]
    command = [config['python_runtime'], '-B', '-m', 'pytest', '-q', '-p', 'no:cacheprovider',
               *report['tests_required_before_launch']]
    validation_env = dict(os.environ, PRICEFM_R141_DEPENDENCY=
                          read(source_preparation(config))['dependency'])
    validation = subprocess.run(command, cwd=ROOT, env=validation_env,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if validation.returncode:
        raise RuntimeError('R146 release regression suite failed: ' + validation.stdout[-8000:])
    report['regression_validation'] = {
        'passed': True, 'command': command, 'returncode': validation.returncode,
        'output_sha256': hashlib.sha256(validation.stdout.encode()).hexdigest(),
        'test_sha256': {relative: sha256(ROOT / relative)
                        for relative in report['tests_required_before_launch']},
    }
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
        return {'status': 'R146_ALREADY_PREPARED', 'source': prep['source'],
                'imported_prerequisites': len(config['prerequisites'])}
    candidate = next(value for value in source_prep['regional']['AT']['candidates']
                     if value['candidate_id'] == config['fallback_candidate']['candidate_id'])
    protocol = dict(source_prep['protocol'])
    protocol.update(tag=config['tag'], regions=['AT'], maximum_workers=config['maximum_workers'],
                    maximum_workers_per_region=config['maximum_workers'], quantile_finalists=1,
                    al_max_iter=config['al_max_iter'],
                    minimum_free_disk_GiB=config['minimum_free_disk_GiB'])
    source_bank, expected_bank_sha256 = selected_training_bank(source_prep, candidate)
    target_bank = destination / 'training_banks/AT' / source_bank.name
    target_bank.parent.mkdir(parents=True, exist_ok=True)
    if target_bank.exists():
        if sha256(target_bank) != expected_bank_sha256:
            raise RuntimeError('existing R146 training bank differs')
    else:
        os.link(source_bank, target_bank)
    if sha256(target_bank) != expected_bank_sha256:
        raise RuntimeError('hard-linked training bank differs from frozen source hash')
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
                         'original_metadata': verified_packet(source_done),
                         'r141_import_record': read(source_campaign(config) / 'recovery_import.json')['imported'][name],
                         'destination': str(target_done)})
    identity = source_identity()
    source_paths = owned_source_paths()
    sources = dict(source_prep['source_sha256'])
    sources.update({str(path): sha256(path) for path in source_paths})
    release_path = preparation_root(config) / 'release/muscat/validation.json'
    prep = {
        'source': identity, 'dependency': source_prep['dependency'],
        'dependency_head': source_prep['dependency_head'], 'protocol': protocol,
        'official_protocol': source_prep['official_protocol'], 'template': source_prep['template'],
        'control': source_prep['control'],
        'regional': {'AT': {'candidates': [candidate],
                            'protected_candidates': [candidate['candidate_id']],
                            'protected_tau0': config['fallback_candidate']['tau0']}},
        'tasks': [], 'references': source_prep['references'],
        'design_audit': {'AT': {'retained': 1, 'selection': 'predetermined_training_only_RHS_rank_4'}},
        'source_sha256': sources, 'input_sha256': source_prep['input_sha256'],
        'bank_sha256': {str(target_bank): expected_bank_sha256},
        'release_path': str(release_path), 'release_sha256': sha256(release_path),
        'historical_fits_used_for_selection': 0, 'training_only_prerequisite_fits_reused': 6,
        'test_used_for_selection': False, 'official_development_test_seen_previously': True,
        'raw_identity': source_prep['raw_identity'],
        'fallback_selection': {'rank': config['fallback_rank'], 'candidate': config['fallback_candidate'],
                               'source_rhs_closeout': str(source_campaign(config) / 'rhs_closeout.json'),
                               'source_rhs_closeout_sha256': config['source_rhs_closeout_sha256']},
        'r141_preparation_sha256': config['source_preparation_sha256'],
        'r141_recovery_import_sha256': config['source_recovery_import_sha256'],
        'r146_release': receipt,
        'model_choice_changed': True, 'same_target_resumption': False,
        'fallback_changes_posterior_target_relative_to_failed_model': True,
    }
    engine.immutable(prep_path, prep)
    immutable_json(destination / 'prerequisite_import.json', {
        'status': 'R146_CERTIFIED_TRAIN_ONLY_PREREQUISITES_IMPORTED',
        'source': report['frozen_r141_source'], 'fallback': config['fallback_candidate'],
        'r141_recovery_import_sha256': config['source_recovery_import_sha256'],
        'source_labels_preserved': True, 'al_fit_import_count': 0,
        'imports': imported, 'test_opened': False, 'hard_links_used': True,
    })
    engine.valid()
    return {'status': 'R146_PREPARED', 'source': identity,
            'imported_prerequisites': len(imported), 'fallback_rank': config['fallback_rank']}


def complete(config):
    root = campaign(config); terminal = root / 'terminal.json'
    evidence = root / 'closeout/completed_evidence.json'
    if not terminal.is_file() or not evidence.is_file():
        return False
    value = read(terminal)
    metadata = verified_packet(root / 'closeout')
    if metadata.get('source') != value.get('source'):
        raise RuntimeError('R146 regional closeout source differs')
    return (value.get('status') == 'R146_AT_FALLBACK_COMPLETE_NOT_PROMOTED'
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
            selected = read(output / 'rhs_closeout.json')['AT']['finalists']
            if (len(selected) != 1
                    or selected[0]['candidate_id'] != config['fallback_candidate']['candidate_id']
                    or not np.isclose(selected[0]['tau0'], config['fallback_candidate']['tau0'],
                                      rtol=1e-14, atol=0)):
                raise RuntimeError('R146 quantile confirmation did not retain the frozen fallback')
            engine.batch(quantile, cpus, prepared, 'fallback_training_only_seven_quantile_AL_confirmation')
            choices = engine.frozen_choices(prepared, quantile)
            choice = choices['AT']
            if (choice['candidate_id'] != config['fallback_candidate']['candidate_id']
                    or not np.isclose(choice['tau0'], config['fallback_candidate']['tau0'], rtol=1e-14, atol=0)):
                raise RuntimeError('R146 fallback changed after train-only quantile confirmation')
            full = engine.full_tasks(prepared, choices)
            engine.batch(full, cpus, prepared, 'fallback_full_folds_nested_AL_and_forecast')
            engine.valid(); engine.verify_hashes(prepared['input_sha256'])
            for task in [*quantile, *full]:
                engine.verified(output / 'tasks_done' / task['name'])
            immutable_json(output / 'fallback_provenance.json', {
                'status': 'R146_PREDETERMINED_TRAINING_ONLY_FALLBACK_COMPLETED',
                'fallback_rank': config['fallback_rank'], 'fallback_candidate': config['fallback_candidate'],
                'source_r141_head': config['source_head'], 'source_rhs_closeout_sha256':
                    config['source_rhs_closeout_sha256'],
                'test_used_for_selection': False, 'posterior_target_changed': False,
                'posterior_target_change_scope': 'within_each_fit',
                'model_choice_changed': True, 'same_target_resumption': False,
                'fallback_changes_posterior_target_relative_to_failed_model': True,
                'certificate_limits_changed': False, 'source': source_identity(),
            })
            engine.closeout(prepared, full)
            terminal = {
                'status': 'R146_AT_FALLBACK_COMPLETE_NOT_PROMOTED', 'region': 'AT',
                'fallback_rank': config['fallback_rank'], 'fallback_candidate': config['fallback_candidate'],
                'source': source_identity(), 'source_r141_head': config['source_head'],
                'test_used_for_selection': False, 'authority_mutated': False,
                'model_choice_changed': True, 'same_target_resumption': False,
                'fallback_changes_posterior_target_relative_to_failed_model': True,
                'posterior_target_changed': False,
                'posterior_target_change_scope': 'within_each_fit',
                'article_mutated': False, 'promotion_decided': False,
                'full_fits': 24, 'official_origin_region_pairs':
                    sum(prepared['official_protocol']['test_origin_counts']),
            }
            atomic_json(output / 'terminal.json', terminal)
            return terminal
        except Exception as error:
            atomic_json(output / 'blocked.json', {
                'status': 'R146_BLOCKED_WITH_EVIDENCE_PRESERVED', 'error': str(error),
                'source': source_identity(), 'no_automatic_budget_change': True,
                'no_certificate_relaxation': True, 'epoch': time.time(),
            })
            raise


def worker(config, name, cpu):
    if cpu not in config['cpus'] or not name:
        raise RuntimeError('R146 worker must use an owned AT CPU and a named task')
    engine = load_engine(config)
    prepared = read(preparation_root(config) / 'preparation.json')
    engine.setup(Path(prepared['dependency']))
    engine.worker(name, cpu)


def run(config, poll_seconds=None):
    poll = config['wait_poll_seconds'] if poll_seconds is None else poll_seconds
    if poll <= 0:
        raise ValueError('positive waiting poll interval required')
    runtime = preparation_root(config) / 'muscat'; runtime.mkdir(parents=True, exist_ok=True)
    with (runtime / 'supervisor.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        identity = source_identity()
        terminal_path = runtime / 'terminal.json'
        if terminal_path.is_file():
            terminal = read(terminal_path)
            if terminal.get('source') != identity:
                raise RuntimeError('existing R146 runtime terminal belongs to another source')
            if terminal.get('status') == 'R146_AT_FALLBACK_COMPLETE_NOT_PROMOTED':
                if not complete(config):
                    raise RuntimeError('R146 runtime success has no matching regional evidence')
                return terminal
            raise RuntimeError('R146 is terminally quarantined; automatic retries are forbidden')
        try:
            release(config)
            while True:
                predecessor = predecessor_state(config)
                conflicts = slot_a_conflicts(config)
                state = {'predecessor': predecessor, 'conflicts': conflicts,
                         'health': host_health(config), 'source': identity, 'epoch': time.time()}
                if not state['health']['healthy']:
                    raise RuntimeError('resource reserve crossed while waiting for R145')
                if not predecessor['ready']:
                    state['status'] = 'R146_WAITING_FOR_R145_AT_LANE_DRAIN'
                elif conflicts:
                    state['status'] = 'R146_WAITING_FOR_AT_SLOT_PROCESS_EXIT'
                else:
                    break
                atomic_json(runtime / 'progress.json', state)
                time.sleep(poll)
            atomic_json(runtime / 'progress.json', {
                'status': 'R146_STARTING_AT_FALLBACK', 'predecessor': predecessor,
                'health': host_health(config), 'source': identity, 'epoch': time.time()})
            result = controller(config)
            atomic_json(terminal_path, result)
            return result
        except Exception as error:
            terminal = {
                'status': 'R146_AT_FALLBACK_QUARANTINED_NOT_PROMOTED', 'region': 'AT',
                'reason': str(error), 'error_type': type(error).__name__,
                'source': identity, 'epoch': time.time(),
                'test_used_for_selection': False, 'authority_mutated': False,
                'article_mutated': False, 'promotion_decided': False,
                'model_choice_changed': True, 'same_target_resumption': False,
                'no_automatic_retry': True, 'no_certificate_relaxation': True,
            }
            atomic_json(terminal_path, terminal)
            atomic_json(runtime / 'progress.json', terminal)
            raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('audit', 'release', 'prepare', 'controller', 'worker', 'run', 'status'))
    parser.add_argument('--region', choices=('AT',)); parser.add_argument('--name'); parser.add_argument('--cpu', type=int)
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
            raise RuntimeError('worker region differs from the frozen R146 region')
        worker(configuration, arguments.name, arguments.cpu); value = {'status': 'worker_complete'}
    elif arguments.action == 'run':
        value = run(configuration, arguments.poll_seconds)
    else:
        path = preparation_root(configuration) / 'muscat/progress.json'
        value = read(path) if path.is_file() else {'status': 'R146_NOT_STARTED'}
    print(json.dumps(value, indent=2, sort_keys=True), flush=True)
