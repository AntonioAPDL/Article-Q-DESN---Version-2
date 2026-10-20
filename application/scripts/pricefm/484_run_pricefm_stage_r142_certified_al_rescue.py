#!/usr/bin/env python3
"""Repair finite R141 AL iteration-cap fits and drain Jerez slot B."""
from __future__ import annotations

import argparse
import concurrent.futures
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time

for variable in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS',
                 'BLIS_NUM_THREADS', 'NUMEXPR_NUM_THREADS', 'R_DATATABLE_NUM_THREADS'):
    os.environ[variable] = '1'
os.environ['PYTHONDONTWRITEBYTECODE'] = '1'

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
CONFIG = ROOT / 'application/config/pricefm_stage_r142_certified_al_rescue_20261020.json'
FITTER = HERE / '483_fit_pricefm_stage_r142_same_target_al_rescue.R'
RSCRIPT = Path('/data/jaguir26/local/opt/R/4.6.0/bin/Rscript')
R_LIBRARY_DIR = Path('/data/jaguir26/local/opt/R/4.6.0/lib64/R/lib')


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


def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()


def source_identity(root=ROOT):
    identity = {'branch': git(root, 'branch', '--show-current'),
                'head': git(root, 'rev-parse', 'HEAD')}
    if not identity['branch'].startswith('work/pricefm-r142-certified-al-rescue-'):
        raise RuntimeError('dedicated R142 source branch required')
    if git(root, 'status', '--porcelain'):
        raise RuntimeError('clean committed R142 source worktree required')
    return identity


def artifacts(folder):
    folder = Path(folder)
    return {str(path.relative_to(folder)): sha256(path)
            for path in sorted(folder.rglob('*'))
            if path.is_file() and path.name != 'completed_evidence.json'}


def seal(folder, metadata):
    immutable_json(Path(folder) / 'completed_evidence.json',
                   {'artifacts': artifacts(folder), 'metadata': metadata})


def verified(folder):
    folder = Path(folder); evidence = read(folder / 'completed_evidence.json')
    observed = artifacts(folder)
    if observed != evidence['artifacts']:
        raise RuntimeError('sealed artifacts differ: ' + str(folder))
    return evidence['metadata']


def hardlink_tree(source, destination):
    source, destination = Path(source), Path(destination)
    if destination.exists():
        raise RuntimeError('hard-link destination exists: ' + str(destination))
    destination.mkdir(parents=True)
    for path in sorted(source.rglob('*')):
        relative = path.relative_to(source); target = destination / relative
        if path.is_symlink():
            raise RuntimeError('symbolic links are not allowed in evidence: ' + str(path))
        if path.is_dir():
            target.mkdir(exist_ok=True)
        elif path.is_file():
            target.parent.mkdir(parents=True, exist_ok=True)
            os.link(path, target)


def host_health(config):
    mem = {line.split(':')[0]: int(line.split()[1])
           for line in Path('/proc/meminfo').read_text().splitlines()}
    stat = os.statvfs(DATA)
    state = {'available_memory_GiB': mem['MemAvailable'] / 2**20,
             'free_disk_GiB': stat.f_bavail * stat.f_frsize / 2**30}
    state['healthy'] = (state['available_memory_GiB'] >= config['minimum_available_memory_GiB']
                        and state['free_disk_GiB'] >= config['minimum_free_disk_GiB'])
    return state


def source_campaign(config, region):
    return DATA / 'campaigns' / f"{config['source_tag']}__{region}"


def rescue_root(config):
    return DATA / 'campaigns' / config['tag']


def assert_config(config):
    forbidden = ('posterior_target_changes_authorized', 'certificate_limit_changes_authorized',
                 'test_based_rescue_authorized', 'registry_mutation_authorized',
                 'article_mutation_authorized', 'promotion_authorized')
    if (config['tag'] != 'pricefm_stage_r142_certified_al_rescue_20261020'
            or config['host'] != 'jerez' or config['slot'] != 'slot_b'
            or config['fit_max_iter_per_attempt'] != 300
            or config['maximum_rescue_attempts'] != 2
            or config['source_iteration_cap'] != 300
            or len(config['cpus']) != 15 or len(set(config['cpus'])) != 15
            or any(config[key] is not False for key in forbidden)):
        raise ValueError('R142 bounded rescue contract differs')
    if socket.gethostname().split('.')[0].lower() != config['host']:
        raise RuntimeError('R142 is restricted to the audited Jerez slot')
    topology = {}
    for line in subprocess.check_output(['lscpu', '-p=CPU,CORE,SOCKET'], text=True).splitlines():
        if line.startswith('#') or not line.strip():
            continue
        cpu, core, package = map(int, line.split(',')); topology[cpu] = (package, core)
    if (any(cpu not in os.sched_getaffinity(0) for cpu in config['cpus'])
            or len({topology[cpu] for cpu in config['cpus']}) != len(config['cpus'])):
        raise RuntimeError('R142 CPUs are not distinct allowed physical cores')
    source = Path(config['source_worktree'])
    if (git(source, 'branch', '--show-current') != config['source_branch']
            or git(source, 'rev-parse', 'HEAD') != config['source_head']
            or git(source, 'status', '--porcelain')):
        raise RuntimeError('frozen R141 source worktree differs')
    if not RSCRIPT.is_file() or not R_LIBRARY_DIR.is_dir():
        raise RuntimeError('project R 4.6 runtime is unavailable')
    if not host_health(config)['healthy']:
        raise RuntimeError('Jerez health reserve is crossed')


def assert_slot_idle(config):
    regions = set(config['regions'])
    controller = str(Path(config['source_worktree']) /
                     'application/scripts/pricefm/480_run_pricefm_stage_r141_region.py').encode()
    for path in Path('/proc').glob('[0-9]*/cmdline'):
        try:
            command = path.read_bytes().split(b'\0')
        except OSError:
            continue
        if controller in command and b'controller' in command:
            for region in regions:
                if region.encode() in command:
                    raise RuntimeError('live R141 slot-B controller detected for ' + region)


def region_complete(config, region):
    campaign = source_campaign(config, region)
    terminal = campaign / 'terminal.json'; evidence = campaign / 'closeout/completed_evidence.json'
    if not terminal.is_file() or not evidence.is_file():
        return False
    value = read(terminal); verified(campaign / 'closeout')
    return (value.get('status') == 'R141_REGION_COMPLETE_NOT_PROMOTED'
            and value.get('source', {}).get('head') == config['source_head'])


def eligible_tasks(config, region):
    campaign = source_campaign(config, region); values = []
    if not (campaign / 'tasks_done').is_dir():
        return values
    required = config['required_source_state']
    for folder in sorted((campaign / 'tasks_done').iterdir()):
        task_path = campaign / 'tasks' / (folder.name + '.json')
        if not task_path.is_file() or not (folder / 'fit/terminal.json').is_file():
            continue
        task = read(task_path); result = read(folder / 'result.json')
        if task.get('kind') not in config['eligible_task_kinds'] or result.get('certified') is not False:
            continue
        metadata = verified(folder); terminal = read(folder / 'fit/terminal.json')
        if metadata.get('certified') is not False:
            raise RuntimeError('uncertified result has a certified outer seal: ' + folder.name)
        for key, expected in required.items():
            if terminal.get(key) != expected:
                raise RuntimeError(f'ineligible AL failure {folder.name}: {key} differs')
        if (terminal.get('iterations') != config['source_iteration_cap']
                or terminal.get('termination') != 'iteration_cap_uncertified'
                or terminal.get('package', {}).get('version') != config['expected_package']['version']
                or terminal.get('package', {}).get('repository') != config['expected_package']['repository']):
            raise RuntimeError('AL failure is not the bounded R141 iteration-cap case: ' + folder.name)
        contract = read(campaign / 'contracts' / (folder.name + '.json'))
        if (contract['posterior_target_sha256'] != terminal['posterior_target_sha256']
                or contract['test_opened'] is not False
                or contract['prior_center_from_initializer'] is not False):
            raise RuntimeError('source target contract differs: ' + folder.name)
        values.append({'name': folder.name, 'task': task, 'contract': contract,
                       'folder': folder, 'task_path': task_path})
    return values


def rescue_contract(config, item, source_fit, output_fit, attempt):
    original = item['contract']; source_terminal = read(source_fit / 'terminal.json')
    prior = int(source_terminal.get('cumulative_iteration_budget', source_terminal['iterations']))
    fixedpoint = ROOT / 'application/R/pricefm_r129_al_fixedpoint_certificate.R'
    adapter = Path(original['cran_adapter']); manifest = Path(original['cran_manifest'])
    return {
        'stage': 'R142', 'tag': config['tag'], 'family': 'al', 'task_name': item['name'],
        'fold': original['fold'], 'tau': original['tau'], 'tau0': original['tau0'],
        'output_dir': str(output_fit), 'design_dir': original['design_dir'],
        'source_fit_dir': str(source_fit), 'source_terminal_sha256': sha256(source_fit / 'terminal.json'),
        'source_beta_mean_sha256': sha256(source_fit / 'beta_mean.bin'),
        'design_terminal_sha256': original['design_terminal_sha256'],
        'cran_library': original['cran_library'], 'cran_manifest': str(manifest),
        'cran_manifest_sha256': sha256(manifest), 'cran_adapter': str(adapter),
        'cran_adapter_sha256': sha256(adapter), 'fixedpoint_helper': str(fixedpoint),
        'fixedpoint_helper_sha256': sha256(fixedpoint),
        'certificate_limits': original['certificate_limits'], 'max_rhs_iter': original['max_rhs_iter'],
        'max_iter': config['fit_max_iter_per_attempt'], 'tol': original['tol'],
        'n_samp': original['n_samp'], 'n_samp_xi': original['n_samp_xi'], 'seed': original['seed'],
        'attempt_index': attempt, 'maximum_rescue_attempts': config['maximum_rescue_attempts'],
        'prior_attempt_iterations': prior, 'posterior_target_sha256': original['posterior_target_sha256'],
        'test_opened': False, 'prior_center_from_initializer': False,
        'posterior_target_changed': False, 'certificate_limits_changed': False,
        'exact_optimizer_resumption': False,
        'original_contract_path': str(Path(original['contract_path']) if 'contract_path' in original
                                      else item['folder'].parents[1] / 'contracts' / (item['name'] + '.json')),
        'original_contract_sha256': sha256(item['folder'].parents[1] / 'contracts' / (item['name'] + '.json')),
    }


def run_one_rescue(config, identity, item, cpu):
    root = rescue_root(config) / item['task']['region'] / 'tasks' / item['name']
    source_fit = item['folder'] / 'fit'; final_fit = None
    for attempt in range(1, config['maximum_rescue_attempts'] + 1):
        attempt_dir = root / f'attempt_{attempt:02d}'; output_fit = attempt_dir / 'fit'
        contract_path = attempt_dir / 'contract.json'
        if output_fit.is_dir():
            verified(attempt_dir)
            terminal = read(output_fit / 'terminal.json')
        else:
            attempt_dir.mkdir(parents=True, exist_ok=True)
            contract = rescue_contract(config, item, source_fit, output_fit, attempt)
            immutable_json(contract_path, contract)
            log = (attempt_dir / 'fit.log').open('x')
            env = dict(os.environ)
            env['LD_LIBRARY_PATH'] = str(R_LIBRARY_DIR) + ':' + env.get('LD_LIBRARY_PATH', '')
            env['PATH'] = str(RSCRIPT.parent) + ':' + env['PATH']
            started = time.time()
            try:
                subprocess.run(['taskset', '-c', str(cpu), str(RSCRIPT), str(FITTER),
                                '--config', str(contract_path)], env=env, stdout=log,
                               stderr=subprocess.STDOUT, check=True)
            finally:
                log.close()
            terminal = read(output_fit / 'terminal.json')
            seal(attempt_dir, {'source': identity, 'task_name': item['name'], 'attempt': attempt,
                               'cpu': cpu, 'elapsed_seconds': time.time() - started,
                               'certified': terminal['computationally_certified'],
                               'posterior_target_sha256': terminal['posterior_target_sha256']})
        if terminal['posterior_target_sha256'] != item['contract']['posterior_target_sha256']:
            raise RuntimeError('rescue changed posterior target: ' + item['name'])
        if terminal['computationally_certified']:
            final_fit = output_fit; break
        source_fit = output_fit
    if final_fit is None:
        raise RuntimeError('bounded rescue exhausted without certification: ' + item['name'])

    promoted = root / 'promoted_task'
    if not promoted.exists():
        temporary = root / f'promoted_task.tmp.{os.getpid()}'
        hardlink_tree(final_fit, temporary / 'fit')
        result = {'certified': True, 'tau': item['task']['tau']}
        result['fold' if 'fold' in item['task'] else 'split'] = item['task'].get('fold', item['task'].get('split'))
        atomic_json(temporary / 'result.json', result)
        terminal = read(final_fit / 'terminal.json')
        atomic_json(temporary / 'rescue_provenance.json', {
            'stage': 'R142', 'source_task': str(item['folder']),
            'source_completed_evidence_sha256': sha256(item['folder'] / 'completed_evidence.json'),
            'rescue_fit': str(final_fit), 'rescue_terminal_sha256': sha256(final_fit / 'terminal.json'),
            'posterior_target_sha256': terminal['posterior_target_sha256'],
            'posterior_target_changed': False, 'prior_center_from_initializer': False,
            'test_opened': False, 'exact_optimizer_resumption': False,
            'warm_start_components': config['warm_start_components'], 'source': identity,
        })
        seal(temporary, {'certified': True, 'source_head': identity['head'],
                         'source_r141_head': config['source_head'],
                         'task_sha256': sha256(item['task_path']), 'rescue_stage': 'R142'})
        os.replace(temporary, promoted)
    verified(promoted)
    return {'name': item['name'], 'promoted': str(promoted),
            'terminal': read(promoted / 'fit/terminal.json')}


def bridge_region(config, identity, region, items):
    campaign = source_campaign(config, region); root = rescue_root(config) / region
    receipt_path = root / 'bridge_receipt.json'
    if receipt_path.is_file():
        receipt = read(receipt_path)
        for item in items:
            canonical = campaign / 'tasks_done' / item['name']
            if not (canonical / 'rescue_provenance.json').is_file() or not verified(canonical).get('certified'):
                raise RuntimeError('existing bridge receipt has an incomplete canonical replacement')
        return receipt
    promoted = {item['name']: root / 'tasks' / item['name'] / 'promoted_task' for item in items}
    for path in promoted.values():
        if not path.is_dir() or not verified(path).get('certified'):
            raise RuntimeError('bridge withheld until every rescue certifies')
    receipts = {}
    for item in items:
        name = item['name']; canonical = campaign / 'tasks_done' / name
        if (canonical / 'rescue_provenance.json').is_file():
            verified(canonical); receipts[name] = 'already_bridged'; continue
        original_metadata = verified(canonical)
        if original_metadata.get('certified') is not False:
            raise RuntimeError('bridge source is not the original uncertified task: ' + name)
        backup = campaign / 'uncertified_attempts' / (name + '.r141_original')
        backup.parent.mkdir(parents=True, exist_ok=True)
        if backup.exists():
            raise RuntimeError('ambiguous pre-existing R141 backup: ' + str(backup))
        os.replace(canonical, backup)
        temporary = canonical.with_name(canonical.name + f'.r142_bridge.{os.getpid()}')
        try:
            hardlink_tree(promoted[name], temporary)
            verified(temporary)
            os.replace(temporary, canonical)
        finally:
            if temporary.exists(): shutil.rmtree(temporary)
        receipts[name] = {'original': str(backup), 'original_evidence_sha256': sha256(backup / 'completed_evidence.json'),
                          'replacement': str(canonical),
                          'replacement_evidence_sha256': sha256(canonical / 'completed_evidence.json')}
    receipt = {'status': 'R142_CERTIFIED_RESCUES_BRIDGED', 'region': region, 'source': identity,
               'source_r141_head': config['source_head'], 'tasks': receipts,
               'posterior_target_changed': False, 'test_opened': False, 'epoch': time.time()}
    immutable_json(receipt_path, receipt)
    return receipt


def rescue_region(config, identity, region, items):
    cpus = config['cpus']
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(cpus)) as pool:
        futures = [pool.submit(run_one_rescue, config, identity, item, cpus[index % len(cpus)])
                   for index, item in enumerate(items)]
        results = [future.result() for future in futures]
    bridge_region(config, identity, region, items)
    return results


def original_entry(config):
    return Path(config['source_worktree']) / 'application/scripts/pricefm/480_run_pricefm_stage_r141_region.py'


def prepare_region(config, region, runtime):
    env = dict(os.environ, PRICEFM_R141_REGION=region)
    command = [sys.executable, '-B', str(original_entry(config)), 'prepare',
               '--dependency', config['dependency_worktree'], '--release', config['release_receipt']]
    with (runtime / f'{region}.prepare.log').open('a') as stream:
        subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT, check=True)


def run_controller(config, region, runtime):
    env = dict(os.environ, PRICEFM_R141_REGION=region)
    command = [sys.executable, '-B', str(original_entry(config)), 'controller', '--region', region,
               '--workers', str(len(config['cpus'])), '--cpus', ','.join(map(str, config['cpus']))]
    with (runtime / f'{region}.controller.log').open('a') as stream:
        return subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT).returncode


def audit(config):
    assert_config(config); assert_slot_idle(config)
    identity = source_identity(); state = host_health(config)
    eligible = {region: [item['name'] for item in eligible_tasks(config, region)]
                for region in config['regions'] if source_campaign(config, region).is_dir()}
    return {'status': 'R142_AUDIT_PASS', 'source': identity, 'health': state,
            'queue': config['regions'], 'eligible': eligible,
            'active_model_target_changes': 0, 'test_opened': False}


def run(config):
    report = audit(config); identity = report['source']; runtime = rescue_root(config) / 'runtime'
    runtime.mkdir(parents=True, exist_ok=True)
    with (runtime / 'supervisor.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        immutable_json(runtime / 'audit.json', report)
        for region in config['regions']:
            if region_complete(config, region):
                continue
            prepare_region(config, region, runtime)
            cycles = 0
            while not region_complete(config, region):
                pending = eligible_tasks(config, region)
                if pending:
                    rescue_region(config, identity, region, pending)
                if not host_health(config)['healthy']:
                    raise RuntimeError('health reserve crossed before region controller: ' + region)
                returncode = run_controller(config, region, runtime); cycles += 1
                atomic_json(runtime / 'progress.json', {'status': 'running', 'region': region,
                    'controller_cycles': cycles, 'returncode': returncode,
                    'complete_regions': [value for value in config['regions'] if region_complete(config, value)],
                    'health': host_health(config), 'source': identity, 'epoch': time.time()})
                if region_complete(config, region):
                    break
                pending = eligible_tasks(config, region)
                if not pending:
                    raise RuntimeError(f'{region} controller failed without an eligible finite AL cap failure')
                if cycles >= 8:
                    raise RuntimeError('bounded controller recovery cycles exhausted: ' + region)
        result = {'status': 'R142_JEREZ_SLOT_B_COMPLETE', 'regions': config['regions'],
                  'source': identity, 'test_used_for_rescue': False,
                  'posterior_target_changes': 0, 'epoch': time.time()}
        atomic_json(runtime / 'terminal.json', result)
        return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('audit', 'run'))
    args = parser.parse_args(); configuration = read(CONFIG)
    value = audit(configuration) if args.action == 'audit' else run(configuration)
    print(json.dumps(value, indent=2, sort_keys=True), flush=True)
