#!/usr/bin/env python3
"""Drain the frozen R141 Jerez slot-B queue while CZ remains quarantined."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time

for variable in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS',
                 'BLIS_NUM_THREADS', 'NUMEXPR_NUM_THREADS', 'R_DATATABLE_NUM_THREADS'):
    os.environ[variable] = '1'
os.environ['PYTHONDONTWRITEBYTECODE'] = '1'

ROOT = Path(__file__).resolve().parents[3]
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
CONFIG = ROOT / 'application/config/pricefm_stage_r143_cz_quarantine_queue_recovery_20261020.json'


def read(path):
    return json.loads(Path(path).read_text())


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def atomic_json(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f'.tmp.{os.getpid()}')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    os.replace(temporary, path)


def git(root, *arguments):
    return subprocess.check_output(['git', *arguments], cwd=root, text=True).strip()


def hostname():
    return socket.gethostname().split('.')[0].lower()


def physical_topology():
    topology = {}
    for line in subprocess.check_output(['lscpu', '-p=CPU,CORE,SOCKET'], text=True).splitlines():
        if line.startswith('#') or not line.strip():
            continue
        cpu, core, package = map(int, line.split(','))
        topology[cpu] = (package, core)
    return topology


def health(config):
    memory = {line.split(':')[0]: int(line.split()[1])
              for line in Path('/proc/meminfo').read_text().splitlines()}
    stat = os.statvfs(DATA)
    free_disk = stat.f_bavail * stat.f_frsize / 2**30
    available_memory = memory['MemAvailable'] / 2**20
    return {
        'healthy': free_disk >= config['minimum_free_disk_GiB'] and
                   available_memory >= config['minimum_available_memory_GiB'],
        'free_disk_GiB': free_disk,
        'available_memory_GiB': available_memory,
        'disk_floor_GiB': config['minimum_free_disk_GiB'],
        'memory_floor_GiB': config['minimum_available_memory_GiB'],
    }


def command_lines():
    values = []
    for path in Path('/proc').glob('[0-9]*/cmdline'):
        try:
            command = path.read_bytes().replace(b'\0', b' ').decode(errors='replace')
        except OSError:
            continue
        values.append((int(path.parent.name), command))
    return values


def source_controller(config):
    return Path(config['source_worktree']) / 'application/scripts/pricefm/480_run_pricefm_stage_r141_region.py'


def source_campaign(config, region):
    return DATA / 'campaigns' / f"{config['source_tag']}__{region}"


def complete(config, region):
    campaign = source_campaign(config, region)
    terminal = campaign / 'terminal.json'; evidence = campaign / 'closeout/completed_evidence.json'
    if not terminal.is_file() or not evidence.is_file():
        return False
    return (read(terminal).get('status') == 'R141_REGION_COMPLETE_NOT_PROMOTED'
            and read(terminal).get('source', {}).get('head') == config['source_head']
            and read(evidence).get('metadata', {}).get('source', {}).get('head') == config['source_head'])


def controller_pid(config, region):
    entry = str(source_controller(config))
    marker = f'controller --region {region}'
    matches = [pid for pid, command in command_lines() if entry in command and marker in command]
    if len(matches) > 1:
        raise RuntimeError(f'multiple R141 controllers found for {region}: {matches}')
    return matches[0] if matches else None


def cz_diagnosis(config):
    root = DATA / 'campaigns' / config['cz_rescue_tag'] / 'CZ/tasks'
    records = []
    for name in config['cz_expected_failed_tasks']:
        path = root / name / 'attempt_02/fit/fixedpoint_certificate.json'
        if not path.is_file():
            raise RuntimeError('missing expected CZ attempt-2 certificate: ' + str(path))
        value = read(path); measures = value['measures']; limits = value['limits']
        solve = value['mean_solve_relative_residual']
        beta = measures['beta_posterior_sd_rms']; covariance = measures['covariance_whitened_rms']
        records.append({
            'task': name,
            'certificate_sha256': sha256(path),
            'certified': value['certified'],
            'beta_posterior_sd_rms': beta,
            'beta_limit': limits['beta_posterior_sd_rms'],
            'beta_limit_ratio': beta / limits['beta_posterior_sd_rms'],
            'covariance_whitened_rms': covariance,
            'covariance_limit': limits['covariance_whitened_rms'],
            'mean_solve_relative_residual': solve,
            'precision_condition': value['precision_condition'],
            'accurate_linear_solve': solve <= 1e-10,
            'coefficient_block_stationary': beta <= limits['beta_posterior_sd_rms'],
        })
    certified = []
    for name in config['cz_expected_certified_tasks']:
        path = root / name / 'promoted_task/fit/terminal.json'
        if not path.is_file() or not read(path).get('computationally_certified'):
            raise RuntimeError('missing expected certified CZ split-3 rescue: ' + str(path))
        certified.append({'task': name, 'terminal_sha256': sha256(path)})
    if (root.parent / 'bridge_receipt.json').exists():
        raise RuntimeError('CZ was unexpectedly bridged despite incomplete all-or-nothing rescue')
    all_solved = all(item['accurate_linear_solve'] for item in records)
    all_nonstationary = all(not item['coefficient_block_stationary'] for item in records)
    rhs_closeout_path = source_campaign(config, 'CZ') / 'rhs_closeout.json'
    rhs_closeout = read(rhs_closeout_path)['CZ']
    active_candidate = config['cz_expected_failed_tasks'][0].split('iq_CZ_', 1)[1].split('_t', 1)[0]
    fallback = next((item for item in rhs_closeout['ranking']
                     if item['candidate_id'] != active_candidate), None)
    if fallback is None:
        raise RuntimeError('CZ has no alternative completed training-only RHS finalist')
    return {
        'status': 'CZ_QUARANTINED_AFTER_BOUNDED_SAME_TARGET_RESCUE',
        'classification': ('coefficient_block_nonstationarity_not_linear_solve_failure'
                           if all_solved and all_nonstationary else 'unresolved'),
        'failed_attempt_2': records,
        'certified_split_3_rescues_unbridged': certified,
        'all_or_nothing_bridge_performed': False,
        'more_blind_iterations_authorized': False,
        'certificate_relaxation_authorized': False,
        'training_only_fallback_candidate': fallback,
        'training_only_fallback_source_sha256': sha256(rhs_closeout_path),
        'training_only_fallback_launched': False,
        'test_opened': False,
    }


def validate(config, require_idle=True):
    if config['tag'] != 'pricefm_stage_r143_cz_quarantine_queue_recovery_20261020':
        raise ValueError('unexpected R143 tag')
    if not hostname().startswith(config['host']):
        raise RuntimeError('R143 continuation must execute on Jerez')
    if config['quarantined_region'] != 'CZ' or 'CZ' in config['continuation_regions']:
        raise ValueError('CZ must remain outside the continuation queue')
    if len(config['continuation_regions']) != len(set(config['continuation_regions'])):
        raise ValueError('continuation queue contains duplicate regions')
    for key in ('test_data_access_authorized', 'posterior_target_changes_authorized',
                'certificate_limit_changes_authorized', 'registry_mutation_authorized',
                'article_mutation_authorized', 'promotion_authorized'):
        if config[key] is not False:
            raise ValueError('forbidden R143 authority or target expansion: ' + key)
    cpus = config['cpus']; topology = physical_topology()
    if (len(cpus) != 15 or len(cpus) != len(set(cpus))
            or any(cpu not in os.sched_getaffinity(0) for cpu in cpus)
            or len({topology[cpu] for cpu in cpus}) != len(cpus)):
        raise RuntimeError('R143 requires 15 distinct allowed physical cores')
    source = Path(config['source_worktree'])
    if (git(source, 'branch', '--show-current') != config['source_branch']
            or git(source, 'rev-parse', 'HEAD') != config['source_head']
            or git(source, 'status', '--porcelain')):
        raise RuntimeError('frozen R141 source worktree identity or cleanliness differs')
    for relative, expected in config['frozen_source_sha256'].items():
        if sha256(source / relative) != expected:
            raise RuntimeError('frozen R141 source file differs: ' + relative)
    receipt = read(config['release_receipt'])
    if not receipt.get('passed') or receipt.get('source') != {
            'branch': config['source_branch'], 'head': config['source_head']}:
        raise RuntimeError('R141 source-matched Jerez release receipt differs')
    scheduler = DATA / 'launch_prep' / config['source_tag'] / 'host_scheduler/jerez/progress.json'
    state = read(scheduler)
    cz_failures = [item for item in state.get('failures', [])
                   if item.get('region') == 'CZ' and item.get('slot') == 'slot_b']
    if not cz_failures:
        raise RuntimeError('original scheduler does not record the quarantined CZ slot-B failure')
    live = command_lines(); source_entry = str(source_controller(config))
    slot_b_live = [(pid, command) for pid, command in live if source_entry in command and
                   'controller --region' in command and any(
                       f'--region {region}' in command for region in [config['quarantined_region'],
                                                                     *config['continuation_regions']])]
    rescue_live = [(pid, command) for pid, command in live
                   if '484_run_pricefm_stage_r142_certified_al_rescue.py run' in command]
    cz_live = [(pid, command) for pid, command in slot_b_live if '--region CZ' in command]
    continuation_live = [(pid, command) for pid, command in slot_b_live if '--region CZ' not in command]
    if rescue_live or cz_live or len(continuation_live) > 1:
        raise RuntimeError(f'conflicting Jerez slot-B work: controllers={slot_b_live}, rescue={rescue_live}')
    if require_idle and continuation_live:
        raise RuntimeError(f'Jerez slot B is not idle: controllers={slot_b_live}, rescue={rescue_live}')
    host_state = health(config)
    if not host_state['healthy']:
        raise RuntimeError('Jerez resource reserve is crossed: ' + str(host_state))
    return {
        'status': 'R143_PREFLIGHT_PASS',
        'source': {'branch': config['source_branch'], 'head': config['source_head']},
        'queue': config['continuation_regions'],
        'quarantined_region': 'CZ',
        'cz_diagnosis': cz_diagnosis(config),
        'health': host_state,
        'original_scheduler_failure': cz_failures,
        'test_opened': False,
        'posterior_target_changes': 0,
    }


def prepare(config, region, runtime):
    environment = dict(os.environ, PRICEFM_R141_REGION=region)
    command = [sys.executable, '-B', str(source_controller(config)), 'prepare',
               '--dependency', config['dependency_worktree'], '--release', config['release_receipt']]
    with (runtime / f'{region}.prepare.log').open('a') as stream:
        subprocess.run(command, env=environment, stdout=stream, stderr=subprocess.STDOUT, check=True)


def launch(config, region, runtime):
    environment = dict(os.environ, PRICEFM_R141_REGION=region)
    command = [sys.executable, '-B', str(source_controller(config)), 'controller', '--region', region,
               '--workers', str(len(config['cpus'])), '--cpus', ','.join(map(str, config['cpus']))]
    stream = (runtime / f'{region}.controller.log').open('a')
    process = subprocess.Popen(command, env=environment, stdout=stream, stderr=subprocess.STDOUT,
                               start_new_session=True)
    return process, stream


def progress(config, audit, active, failures):
    completed = [region for region in config['continuation_regions'] if complete(config, region)]
    failed = {item['region'] for item in failures}
    pending = [region for region in config['continuation_regions']
               if region not in completed and region not in failed and region != active]
    return {
        'status': 'degraded' if failures else 'running',
        'completed': completed,
        'completed_count': len(completed),
        'assigned_count': len(config['continuation_regions']),
        'remaining_count': len(config['continuation_regions']) - len(completed),
        'pending': pending,
        'active_region': active,
        'failures': failures,
        'quarantined_region': config['quarantined_region'],
        'health': health(config),
        'source': audit['source'],
        'epoch': time.time(),
    }


def run(config, poll_seconds=15):
    audit = validate(config, require_idle=False)
    runtime = DATA / 'launch_prep' / config['tag'] / 'jerez'
    runtime.mkdir(parents=True, exist_ok=True)
    with (runtime / 'supervisor.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        atomic_json(runtime / 'audit.json', audit)
        previous = read(runtime / 'progress.json') if (runtime / 'progress.json').is_file() else {}
        failures = previous.get('failures', [])
        failed_regions = {item['region'] for item in failures}
        for region in config['continuation_regions']:
            if complete(config, region) or region in failed_regions:
                continue
            if not health(config)['healthy']:
                raise RuntimeError('resource reserve crossed before ' + region)
            adopted = controller_pid(config, region)
            process = None; stream = None
            if adopted is None:
                prepare(config, region, runtime)
                process, stream = launch(config, region, runtime)
                adopted = process.pid
            atomic_json(runtime / 'progress.json', progress(config, audit, region, failures))
            while controller_pid(config, region) is not None:
                atomic_json(runtime / 'progress.json', progress(config, audit, region, failures))
                time.sleep(poll_seconds)
            if stream is not None:
                stream.close()
            returncode = process.poll() if process is not None else None
            if not complete(config, region):
                failures.append({'region': region, 'returncode': returncode,
                                 'reason': 'R141 controller exited without certified region closeout'})
                failed_regions.add(region)
            atomic_json(runtime / 'progress.json', progress(config, audit, None, failures))
        result = progress(config, audit, None, failures)
        result['status'] = ('R143_QUEUE_COMPLETE_NOT_PROMOTED' if not failures
                            else 'R143_QUEUE_DRAINED_WITH_QUARANTINED_FAILURES')
        atomic_json(runtime / 'terminal.json', result)
        if failures:
            raise RuntimeError('R143 drained healthy work but retained regional failures: ' + str(failures))
        return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('audit', 'diagnose-cz', 'run'))
    parser.add_argument('--poll-seconds', type=int, default=15)
    arguments = parser.parse_args(); configuration = read(CONFIG)
    if arguments.action == 'audit':
        value = validate(configuration)
    elif arguments.action == 'diagnose-cz':
        value = cz_diagnosis(configuration)
    else:
        value = run(configuration, arguments.poll_seconds)
    print(json.dumps(value, indent=2, sort_keys=True), flush=True)
