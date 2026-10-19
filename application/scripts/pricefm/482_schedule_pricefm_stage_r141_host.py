#!/usr/bin/env python3
"""Run two resumable, failure-isolated 15-core R141 regional queues."""
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

for name in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS',
             'BLIS_NUM_THREADS', 'NUMEXPR_NUM_THREADS', 'R_DATATABLE_NUM_THREADS'):
    os.environ[name] = '1'
os.environ['PYTHONDONTWRITEBYTECODE'] = '1'

ROOT = Path(__file__).resolve().parents[3]
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
CONFIG = ROOT / 'application/config/pricefm_stage_r141_recovery_rollout_20261019.json'
CONTROLLER = Path(__file__).resolve().parent / '480_run_pricefm_stage_r141_region.py'
RSCRIPT = Path('/data/jaguir26/local/opt/R/4.6.0/bin/Rscript')


def read(path):
    return json.loads(Path(path).read_text())


def atomic_json(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f'.tmp.{os.getpid()}')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    os.replace(temporary, path)


def sha256(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def git(*args, root=ROOT):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()


def host_name(value=None):
    name = (value or socket.gethostname()).split('.')[0].lower()
    for expected in ('muscat', 'jerez'):
        if name.startswith(expected):
            return expected
    raise RuntimeError('R141 scheduler is restricted to muscat or jerez, observed ' + name)


def physical_topology():
    topology = {}
    output = subprocess.check_output(['lscpu', '-p=CPU,CORE,SOCKET'], text=True)
    for line in output.splitlines():
        if line.startswith('#') or not line.strip():
            continue
        cpu, core, sock = map(int, line.split(','))
        topology[cpu] = (sock, core)
    return topology


def health(config, host):
    memory = {line.split(':')[0]: int(line.split()[1])
              for line in Path('/proc/meminfo').read_text().splitlines()}
    stat = os.statvfs(DATA)
    free_disk = stat.f_bavail * stat.f_frsize / 2**30
    available_memory = memory['MemAvailable'] / 2**20
    return {
        'healthy': (free_disk >= config['host_minimum_free_disk_GiB'][host]
                    and available_memory >= config['host_minimum_free_memory_GiB']),
        'free_disk_GiB': free_disk,
        'available_memory_GiB': available_memory,
        'disk_floor_GiB': config['host_minimum_free_disk_GiB'][host],
        'memory_floor_GiB': config['host_minimum_free_memory_GiB'],
    }


def validate(config, host, dependency, release):
    if config['tag'] != 'pricefm_stage_r141_recovery_rollout_20261019':
        raise ValueError('unexpected R141 tag')
    queued = [region for values in config['host_queues'].values()
              for queue in values.values() for region in queue]
    expected = set(config['regions']) - set(config['reuse_regions'])
    if len(queued) != len(set(queued)) or set(queued) != expected or len(queued) != 34:
        raise ValueError('host queues do not partition the 34 unfinished regions')
    if set(config['host_queues']) != {'muscat', 'jerez'}:
        raise ValueError('the two audited hosts are required')
    if any(len(config['host_queues'][name]['slot_a']) not in (8, 9)
           or len(config['host_queues'][name]['slot_b']) not in (8, 9)
           for name in ('muscat', 'jerez')):
        raise ValueError('each server must receive balanced two-slot queues')
    cpus = config['host_cpu_sets']; topology = physical_topology()
    flattened = [cpu for slot in ('slot_a', 'slot_b') for cpu in cpus[slot]]
    if (len(cpus['slot_a']) != 15 or len(cpus['slot_b']) != 15
            or len(flattened) != len(set(flattened))
            or any(cpu not in os.sched_getaffinity(0) for cpu in flattened)
            or len({topology[cpu] for cpu in flattened}) != 30):
        raise ValueError('declared allocation is not 30 distinct allowed physical cores')
    if git('rev-parse', 'HEAD', root=dependency) != config['dependency_head']:
        raise RuntimeError('frozen dependency HEAD differs')
    if git('status', '--porcelain', root=dependency):
        raise RuntimeError('frozen dependency worktree is dirty')
    source = {'branch': git('branch', '--show-current'), 'head': git('rev-parse', 'HEAD')}
    if not source['branch'].startswith('work/pricefm-r141-') or git('status', '--porcelain'):
        raise RuntimeError('clean committed dedicated R141 source required')
    receipt = read(release)
    if not receipt.get('passed') or receipt.get('source') != source:
        raise RuntimeError('source-matched R141 release receipt required')
    if '4.6.0' not in subprocess.check_output(
            [str(RSCRIPT), '--version'], text=True, stderr=subprocess.STDOUT):
        raise RuntimeError('project R 4.6.0 is unavailable')
    official = read(dependency / 'application/config/pricefm_stage_r126_matched_comparison_protocol_20261007.json')
    raw = DATA / 'raw/FINAL.csv'
    if sha256(raw) != official['raw_sha256']:
        raise RuntimeError('raw PriceFM source differs')
    state = health(config, host)
    if not state['healthy']:
        raise RuntimeError('host health reserve is already crossed: ' + str(state))
    return {'host': host, 'source': source, 'dependency': str(dependency),
            'release': str(release), 'raw_sha256': official['raw_sha256'],
            'cpu_sets': cpus, 'health': state}


def campaign(config, region):
    return DATA / 'campaigns' / (config['tag'] + '__' + region)


def complete(config, region, source_head):
    terminal = campaign(config, region) / 'terminal.json'
    evidence = campaign(config, region) / 'closeout/completed_evidence.json'
    if not terminal.is_file() or not evidence.is_file():
        return False
    value = read(terminal); sealed = read(evidence)
    return (value.get('status') == 'R141_REGION_COMPLETE_NOT_PROMOTED'
            and value.get('source', {}).get('head') == source_head
            and sealed.get('metadata', {}).get('source', {}).get('head') == source_head)


def pid_live(pid):
    try:
        command = Path(f'/proc/{pid}/cmdline').read_bytes()
    except OSError:
        return False
    return str(CONTROLLER).encode() in command and b'controller' in command


def adopted_pid(config, region):
    identity = campaign(config, region) / 'controller_identity.json'
    if not identity.is_file():
        return None
    pid = int(read(identity).get('pid', -1))
    return pid if pid_live(pid) else None


def prepare_region(config, region, dependency, release, reference, log_dir):
    env = dict(os.environ, PRICEFM_R141_REGION=region)
    command = [sys.executable, '-B', str(CONTROLLER), 'prepare',
               '--dependency', str(dependency), '--release', str(release)]
    if reference:
        command += ['--reference', str(reference)]
    log = log_dir / f'{region}.prepare.log'
    with log.open('a') as stream:
        subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT, check=True)


def launch_region(config, region, slot, log_dir):
    cpus = config['host_cpu_sets'][slot]
    env = dict(os.environ, PRICEFM_R141_REGION=region)
    command = [sys.executable, '-B', str(CONTROLLER), 'controller', '--region', region,
               '--workers', str(len(cpus)), '--cpus', ','.join(map(str, cpus))]
    log = (log_dir / f'{region}.controller.log').open('a')
    proc = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                            start_new_session=True)
    return {'pid': proc.pid, 'process': proc, 'stream': log, 'region': region,
            'slot': slot, 'cpus': cpus, 'adopted': False, 'started_epoch': time.time()}


def progress_payload(config, host, source, queues, active, state, failures):
    completed = [region for slot in queues for region in queues[slot]
                 if complete(config, region, source['head'])]
    return {
        'status': 'degraded' if failures else 'running',
        'host': host,
        'source': source,
        'completed': completed,
        'completed_count': len(completed),
        'assigned_count': sum(map(len, queues.values())),
        'remaining_count': sum(map(len, queues.values())) - len(completed),
        'active': {slot: {k: v for k, v in item.items()
                          if k not in ('process', 'stream')} for slot, item in active.items()},
        'health': state,
        'failures': failures,
        'epoch': time.time(),
    }


def run(host, dependency, release, reference=None, poll_seconds=30):
    config = read(CONFIG); audit = validate(config, host, dependency, release)
    runtime = DATA / 'launch_prep' / config['tag'] / 'host_scheduler' / host
    runtime.mkdir(parents=True, exist_ok=True)
    lock_path = runtime / 'scheduler.lock'
    with lock_path.open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        atomic_json(runtime / 'audit.json', audit)
        queues = config['host_queues'][host]
        active = {}; failures = []
        for slot, regions in queues.items():
            for region in regions:
                pid = adopted_pid(config, region)
                if pid and not complete(config, region, audit['source']['head']):
                    if slot in active:
                        raise RuntimeError('more than one live controller assigned to ' + slot)
                    active[slot] = {'pid': pid, 'process': None, 'stream': None, 'region': region,
                                    'slot': slot, 'cpus': config['host_cpu_sets'][slot],
                                    'adopted': True, 'started_epoch': None}
        while True:
            for slot, item in list(active.items()):
                process = item['process']
                running = process.poll() is None if process is not None else pid_live(item['pid'])
                if running:
                    continue
                if item['stream'] is not None:
                    item['stream'].close()
                returncode = process.returncode if process is not None else None
                region = item['region']; del active[slot]
                if not complete(config, region, audit['source']['head']):
                    failures.append({'region': region, 'slot': slot, 'returncode': returncode,
                                     'reason': 'controller exited without certified region closeout'})
            state = health(config, host)
            for slot, regions in queues.items():
                if slot in active or slot in {failure['slot'] for failure in failures} or not state['healthy']:
                    continue
                next_region = next((region for region in regions
                                    if not complete(config, region, audit['source']['head'])), None)
                if next_region is None:
                    continue
                prepare_region(config, next_region, dependency, release, reference, runtime)
                active[slot] = launch_region(config, next_region, slot, runtime)
            payload = progress_payload(config, host, audit['source'], queues, active, state, failures)
            atomic_json(runtime / 'progress.json', payload)
            if failures:
                atomic_json(runtime / 'blocked.json', payload)
                blocked_slots = {failure['slot'] for failure in failures}
                healthy_remaining = any(
                    not complete(config, region, audit['source']['head'])
                    for slot, regions in queues.items() if slot not in blocked_slots
                    for region in regions)
                if not active and not healthy_remaining:
                    payload['status'] = 'blocked'
                    atomic_json(runtime / 'progress.json', payload)
                    atomic_json(runtime / 'blocked.json', payload)
                    raise RuntimeError(
                        'R141 host queue blocked after healthy slots drained: ' + str(failures))
            if payload['remaining_count'] == 0 and not active:
                payload['status'] = 'R141_HOST_COMPLETE_NOT_PROMOTED'
                atomic_json(runtime / 'terminal.json', payload)
                return payload
            time.sleep(poll_seconds)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('audit', 'run'))
    parser.add_argument('--host', choices=('muscat', 'jerez'))
    parser.add_argument('--dependency', type=Path, required=True)
    parser.add_argument('--release', type=Path, required=True)
    parser.add_argument('--reference', type=Path)
    parser.add_argument('--poll-seconds', type=int, default=30)
    args = parser.parse_args(); observed = host_name(args.host)
    if args.host and host_name() != args.host:
        raise RuntimeError('declared host does not match the executing server')
    if args.action == 'audit':
        print(json.dumps(validate(read(CONFIG), observed, args.dependency, args.release), indent=2))
    else:
        print(json.dumps(run(observed, args.dependency, args.release, args.reference,
                             args.poll_seconds), indent=2))
