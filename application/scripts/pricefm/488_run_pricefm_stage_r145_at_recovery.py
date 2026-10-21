#!/usr/bin/env python3
"""Recover AT and drain the idle Muscat R141 slot-A queue without target changes."""
from __future__ import annotations

import argparse
import concurrent.futures
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import time
import zipfile

for variable in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS',
                 'BLIS_NUM_THREADS', 'NUMEXPR_NUM_THREADS', 'R_DATATABLE_NUM_THREADS'):
    os.environ[variable] = '1'
os.environ['PYTHONDONTWRITEBYTECODE'] = '1'

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
CONFIG = ROOT / 'application/config/pricefm_stage_r145_at_recovery_muscat_utilization_20261021.json'
R142_PATH = HERE / '484_run_pricefm_stage_r142_certified_al_rescue.py'


def load_r142():
    specification = importlib.util.spec_from_file_location('pricefm_r145_r142', R142_PATH)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


R142 = load_r142()


def read(path):
    return json.loads(Path(path).read_text())


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f'.tmp.{os.getpid()}')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    os.replace(temporary, path)


def git(root, *arguments):
    return subprocess.check_output(['git', *arguments], cwd=root, text=True).strip()


def hostname():
    return socket.gethostname().split('.')[0].lower()


def source_identity():
    identity = {'branch': git(ROOT, 'branch', '--show-current'),
                'head': git(ROOT, 'rev-parse', 'HEAD')}
    if not identity['branch'].startswith('work/pricefm-r145-at-recovery-muscat-utilization-'):
        raise RuntimeError('dedicated R145 source branch required')
    if git(ROOT, 'status', '--porcelain'):
        raise RuntimeError('clean committed R145 source worktree required')
    return identity


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
        'healthy': (free_disk >= config['minimum_free_disk_GiB'] and
                    available_memory >= config['minimum_available_memory_GiB']),
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


def scheduler_pids(config):
    entry = 'application/scripts/pricefm/482_schedule_pricefm_stage_r141_host.py'
    matches = []
    for pid, command in command_lines():
        if entry not in command or ' run ' not in f' {command} ' or '--host muscat' not in command:
            continue
        try:
            working_directory = Path(f'/proc/{pid}/cwd').resolve()
        except OSError:
            continue
        if working_directory == Path(config['source_worktree']).resolve():
            matches.append(pid)
    return matches


def controller_pid(config, region):
    entry = str(source_controller(config))
    marker = f'controller --region {region}'
    matches = [pid for pid, command in command_lines() if entry in command and marker in command]
    if len(matches) > 1:
        raise RuntimeError(f'multiple R141 controllers found for {region}: {matches}')
    return matches[0] if matches else None


def source_campaign(config, region):
    return DATA / 'campaigns' / f"{config['source_tag']}__{region}"


def region_complete(config, region):
    campaign = source_campaign(config, region)
    terminal = campaign / 'terminal.json'
    evidence = campaign / 'closeout/completed_evidence.json'
    if not terminal.is_file() or not evidence.is_file():
        return False
    return (read(terminal).get('status') == 'R141_REGION_COMPLETE_NOT_PROMOTED'
            and read(terminal).get('source', {}).get('head') == config['source_head']
            and read(evidence).get('metadata', {}).get('source', {}).get('head') == config['source_head'])


def validate_static(config):
    forbidden = ('posterior_target_changes_authorized', 'certificate_limit_changes_authorized',
                 'test_based_rescue_authorized', 'test_data_access_authorized',
                 'registry_mutation_authorized', 'article_mutation_authorized',
                 'promotion_authorized')
    if config['tag'] != 'pricefm_stage_r145_at_recovery_muscat_utilization_20261021':
        raise ValueError('unexpected R145 tag')
    if config['host'] != 'muscat' or config['blocked_region'] != 'AT':
        raise ValueError('R145 is restricted to the audited Muscat AT recovery')
    if (config['fit_max_iter_per_attempt'] != 300
            or config['source_iteration_cap'] != 300
            or config['maximum_rescue_attempts'] != 2
            or config['maximum_controller_cycles'] != 8):
        raise ValueError('R145 bounded same-target recovery contract differs')
    if config['warm_start_components'] != ['beta_mean', 'likelihood_scale']:
        raise ValueError('R145 warm-start surface differs')
    if any(config[key] is not False for key in forbidden):
        raise ValueError('R145 may not change targets, use tests, or mutate authority')
    at_cpus = config['at_cpus']; queue_cpus = config['continuation_cpus']
    if (len(at_cpus) != 8 or len(queue_cpus) != 7
            or len(set(at_cpus + queue_cpus)) != 15
            or set(at_cpus).intersection(queue_cpus)
            or set(at_cpus + queue_cpus) != set(range(15))):
        raise ValueError('R145 must partition Muscat cores 0-14 as 8 + 7')
    regions = config['continuation_regions']
    if (len(regions) != len(set(regions)) or config['blocked_region'] in regions
            or regions != ['DE_LU', 'FI', 'IT_CALA', 'IT_SICI', 'NL', 'NO_4', 'RO', 'SE_4']):
        raise ValueError('R145 continuation queue differs from the frozen R141 slot-A tail')
    return True


def initial_at_evidence(config):
    campaign = source_campaign(config, config['blocked_region'])
    states = {}
    for name, expected in config['expected_initial_uncertified_tasks'].items():
        task = campaign / 'tasks' / (name + '.json')
        canonical = campaign / 'tasks_done' / name
        backup = campaign / 'uncertified_attempts' / (name + '.r141_original')
        if not task.is_file() or sha256(task) != expected['task_sha256']:
            raise RuntimeError('AT source task identity differs: ' + name)
        original = backup if backup.is_dir() else canonical
        checks = {
            'completed_evidence.json': expected['completed_evidence_sha256'],
            'fit/terminal.json': expected['terminal_sha256'],
            'fit/fixedpoint_certificate.json': expected['fixedpoint_certificate_sha256'],
        }
        if any(not (original / relative).is_file() or sha256(original / relative) != digest
               for relative, digest in checks.items()):
            raise RuntimeError('AT original uncertified evidence differs: ' + name)
        if backup.is_dir():
            if not (canonical / 'rescue_provenance.json').is_file():
                raise RuntimeError('AT backup exists without a canonical rescued replacement: ' + name)
            R142.verified(canonical)
            states[name] = 'certified_replacement_bridged'
        else:
            metadata = R142.verified(canonical)
            if metadata.get('certified') is not False:
                raise RuntimeError('AT initial evidence is not the expected uncertified fit: ' + name)
            states[name] = 'original_uncertified_evidence'
    return states


def scheduler_failure(config):
    progress = DATA / 'launch_prep' / config['source_tag'] / 'host_scheduler/muscat/progress.json'
    value = read(progress)
    failures = [item for item in value.get('failures', [])
                if item.get('slot') == 'slot_a' and item.get('region') == config['blocked_region']]
    if not failures:
        raise RuntimeError('original R141 scheduler does not record the AT slot-A failure')
    return failures


def validate(config, require_idle=True):
    validate_static(config)
    if not hostname().startswith(config['host']):
        raise RuntimeError('R145 must execute on Muscat')
    topology = physical_topology(); cpus = config['at_cpus'] + config['continuation_cpus']
    if (any(cpu not in os.sched_getaffinity(0) for cpu in cpus)
            or any(cpu not in topology for cpu in cpus)
            or len({topology[cpu] for cpu in cpus}) != 15):
        raise RuntimeError('R145 allocation is not 15 distinct allowed physical cores')
    source = Path(config['source_worktree'])
    python_runtime = Path(config['python_runtime'])
    if (not python_runtime.is_file() or 'Python 3.11.' not in subprocess.check_output(
            [str(python_runtime), '--version'], text=True, stderr=subprocess.STDOUT)):
        raise RuntimeError('frozen R141 Python 3.11 runtime is unavailable')
    if (git(source, 'branch', '--show-current') != config['source_branch']
            or git(source, 'rev-parse', 'HEAD') != config['source_head']
            or git(source, 'status', '--porcelain')):
        raise RuntimeError('frozen R141 source worktree identity or cleanliness differs')
    for relative, expected in config['frozen_source_sha256'].items():
        if sha256(source / relative) != expected:
            raise RuntimeError('frozen R141 source file differs: ' + relative)
    for relative, expected in config['frozen_recovery_sha256'].items():
        if sha256(ROOT / relative) != expected:
            raise RuntimeError('frozen R142 rescue file differs: ' + relative)
    source_protocol = read(source / 'application/config/pricefm_stage_r141_recovery_rollout_20261019.json')
    dependency = Path(config['dependency_worktree'])
    if (git(dependency, 'rev-parse', 'HEAD') != source_protocol['dependency_head']
            or git(dependency, 'status', '--porcelain')):
        raise RuntimeError('frozen R141 dependency worktree differs')
    receipt = read(config['release_receipt'])
    if not receipt.get('passed') or receipt.get('source') != {
            'branch': config['source_branch'], 'head': config['source_head']}:
        raise RuntimeError('source-matched Muscat R141 release receipt differs')
    preparation = Path(config['source_preparation'])
    blocked = source_campaign(config, config['blocked_region']) / 'blocked.json'
    if (sha256(preparation) != config['source_preparation_sha256']
            or sha256(blocked) != config['source_blocked_sha256']):
        raise RuntimeError('AT preparation or blocked evidence differs')
    original_scheduler = scheduler_pids(config)
    if len(original_scheduler) != 1:
        raise RuntimeError('exactly one original Muscat R141 scheduler must remain live')
    failures = scheduler_failure(config)
    regions = [config['blocked_region'], *config['continuation_regions']]
    live = {region: controller_pid(config, region) for region in regions}
    active = {region: pid for region, pid in live.items() if pid is not None}
    at_active = [region for region in active if region == config['blocked_region']]
    queue_active = [region for region in active if region in config['continuation_regions']]
    if len(at_active) > 1 or len(queue_active) > 1:
        raise RuntimeError('R145 found multiple controllers in one recovery lane: ' + str(active))
    if require_idle and active:
        raise RuntimeError('R145 target cores are not idle: ' + str(active))
    state = health(config)
    if not state['healthy']:
        raise RuntimeError('Muscat resource reserve is crossed: ' + str(state))
    at_evidence = initial_at_evidence(config)
    observed_eligible = {item['name'] for item in R142.eligible_tasks(config, config['blocked_region'])}
    expected_eligible = {name for name, state in at_evidence.items()
                         if state == 'original_uncertified_evidence'}
    if observed_eligible != expected_eligible:
        raise RuntimeError('AT eligible rescue set differs from the frozen evidence contract: '
                           f'expected={sorted(expected_eligible)}, observed={sorted(observed_eligible)}')
    return {
        'status': 'R145_PREFLIGHT_PASS',
        'source': source_identity(),
        'source_r141': {'branch': config['source_branch'], 'head': config['source_head']},
        'scheduler_pid': original_scheduler[0],
        'scheduler_failure': failures,
        'at_evidence': at_evidence,
        'eligible_at_tasks': sorted(observed_eligible),
        'active_adoptable_controllers': active,
        'resource_partition': {'at': config['at_cpus'], 'continuation': config['continuation_cpus']},
        'health': state,
        'test_opened': False,
        'posterior_target_changes': 0,
    }


def assert_scheduler_unchanged(config, pid):
    if scheduler_pids(config) != [pid]:
        raise RuntimeError('original Muscat scheduler identity changed during R145')
    scheduler_failure(config)


def preserve_corrupt_preparation_banks(config, region):
    preparation = DATA / 'launch_prep' / f"{config['source_tag']}__{region}" / 'preparation.json'
    if preparation.is_file():
        return []
    campaign = source_campaign(config, region)
    bank_root = campaign / 'training_banks' / region
    preserved = []
    for bank in sorted(bank_root.glob('*.npz')):
        error = None
        try:
            with zipfile.ZipFile(bank) as archive:
                bad_member = archive.testzip()
            if bad_member is not None:
                error = 'bad_zip_member:' + bad_member
        except (OSError, zipfile.BadZipFile) as caught:
            error = type(caught).__name__ + ':' + str(caught)
        if error is None:
            continue
        destination_root = campaign / 'interrupted_preparation_banks' / region
        destination_root.mkdir(parents=True, exist_ok=True)
        destination = destination_root / f'{bank.name}.{time.time_ns()}'
        record = {'status': 'R145_INTERRUPTED_PREPARATION_BANK_PRESERVED',
                  'region': region, 'source_path': str(bank), 'destination': str(destination),
                  'bytes': bank.stat().st_size, 'sha256': sha256(bank), 'validation_error': error,
                  'test_opened': False, 'posterior_target_changed': False, 'epoch': time.time()}
        os.replace(bank, destination)
        atomic_json(destination.with_name(destination.name + '.receipt.json'), record)
        preserved.append(record)
    return preserved


def reopen_interrupted_preparation_failures(config, runtime):
    reopened = []
    for region in config['continuation_regions']:
        quarantine = runtime / 'quarantine' / f'{region}.json'
        if not quarantine.is_file():
            continue
        preparation = DATA / 'launch_prep' / f"{config['source_tag']}__{region}" / 'preparation.json'
        if preparation.is_file():
            continue
        preserved = preserve_corrupt_preparation_banks(config, region)
        if not preserved:
            continue
        destination = runtime / 'interrupted_preparation_failures' / f'{region}.{time.time_ns()}.json'
        destination.parent.mkdir(parents=True, exist_ok=True)
        os.replace(quarantine, destination)
        reopened.append({'region': region, 'prior_quarantine': str(destination),
                         'preserved_banks': preserved})
    return reopened


def prepare_region(config, region, runtime):
    preserve_corrupt_preparation_banks(config, region)
    environment = dict(os.environ, PRICEFM_R141_REGION=region)
    command = [config['python_runtime'], '-B', str(source_controller(config)), 'prepare',
               '--dependency', config['dependency_worktree'], '--release', config['release_receipt']]
    with (runtime / f'{region}.prepare.log').open('a') as stream:
        subprocess.run(command, env=environment, stdout=stream, stderr=subprocess.STDOUT, check=True)


def launch_controller(config, region, cpus, runtime):
    environment = dict(os.environ, PRICEFM_R141_REGION=region)
    command = [config['python_runtime'], '-B', str(source_controller(config)), 'controller', '--region', region,
               '--workers', str(len(cpus)), '--cpus', ','.join(map(str, cpus))]
    stream = (runtime / f'{region}.controller.log').open('a')
    process = subprocess.Popen(command, env=environment, stdout=stream, stderr=subprocess.STDOUT,
                               start_new_session=True)
    return process, stream


def rescue_cycle_config(config, region, cpus, cycle):
    result = dict(config)
    result['cpus'] = cpus
    result['tag'] = f"{config['tag']}__{region}__cycle_{cycle:02d}"
    return result


def next_rescue_cycle(config, region, pending):
    prefix = f"{config['tag']}__{region}__cycle_"
    roots = sorted((DATA / 'campaigns').glob(prefix + '*'))
    maximum = 0
    names = {item['name'] for item in pending}
    for root in roots:
        try:
            cycle = int(root.name.rsplit('_', 1)[1])
        except ValueError:
            continue
        maximum = max(maximum, cycle)
        task_root = root / region / 'tasks'
        if not (root / region / 'bridge_receipt.json').exists() and any(
                (task_root / name).exists() for name in names):
            return cycle
    return maximum + 1


def preserve_interrupted_attempts(rescue_config, region, pending):
    root = DATA / 'campaigns' / rescue_config['tag'] / region / 'tasks'
    preserved = []
    for item in pending:
        task_root = root / item['name']
        for attempt in sorted(task_root.glob('attempt_*')):
            if not attempt.is_dir() or (attempt / 'completed_evidence.json').is_file():
                continue
            destination_root = task_root / 'interrupted_attempts'
            destination_root.mkdir(parents=True, exist_ok=True)
            destination = destination_root / f'{attempt.name}.{time.time_ns()}'
            os.replace(attempt, destination)
            atomic_json(destination / 'r145_interruption.json', {
                'status': 'R145_INTERRUPTED_ATTEMPT_PRESERVED',
                'reason': 'supervisor stopped before the attempt evidence was sealed',
                'task': item['name'],
                'posterior_target_changed': False,
                'test_opened': False,
                'epoch': time.time(),
            })
            preserved.append(str(destination))
    return preserved


def lane_progress(config, lane, region, completed, failures, scheduler_pid, cycles=0):
    queue = ([config['blocked_region']] if lane == 'at' else config['continuation_regions'])
    return {
        'status': 'degraded' if failures else 'running',
        'lane': lane,
        'active_region': region,
        'completed': completed,
        'completed_count': len(completed),
        'assigned_count': len(queue),
        'remaining_count': len(queue) - len(completed),
        'pending': [value for value in queue if value not in completed
                    and value not in {failure['region'] for failure in failures}
                    and value != region],
        'failures': failures,
        'controller_cycles': cycles,
        'scheduler_pid': scheduler_pid,
        'health': health(config),
        'epoch': time.time(),
    }


def run_region(config, identity, audit, region, cpus, runtime, lane, poll_seconds):
    cycles = 0
    adopted = controller_pid(config, region)
    if adopted is None:
        prepare_region(config, region, runtime)
    while not region_complete(config, region):
        assert_scheduler_unchanged(config, audit['scheduler_pid'])
        state = health(config)
        if not state['healthy']:
            raise RuntimeError('resource reserve crossed before ' + region)
        adopted = controller_pid(config, region)
        if adopted is None:
            pending = R142.eligible_tasks(config, region)
            if pending:
                cycle = next_rescue_cycle(config, region, pending)
                cycles = max(cycles, cycle)
                if cycle > config['maximum_controller_cycles']:
                    raise RuntimeError('bounded recovery cycles exhausted: ' + region)
                rescue = rescue_cycle_config(config, region, cpus, cycle)
                preserve_interrupted_attempts(rescue, region, pending)
                R142.rescue_region(rescue, identity, region, pending)
            process, stream = launch_controller(config, region, cpus, runtime)
            adopted = process.pid
        else:
            process = None; stream = None
        atomic_json(runtime / f'{lane}.progress.json',
                    lane_progress(config, lane, region, [], [], audit['scheduler_pid'], cycles))
        while controller_pid(config, region) is not None:
            assert_scheduler_unchanged(config, audit['scheduler_pid'])
            if not health(config)['healthy']:
                raise RuntimeError('resource reserve crossed while monitoring ' + region)
            time.sleep(poll_seconds)
        if stream is not None:
            stream.close()
        if region_complete(config, region):
            return {'region': region, 'controller_cycles': cycles, 'status': 'complete'}
        pending = R142.eligible_tasks(config, region)
        if not pending:
            returncode = process.poll() if process is not None else None
            raise RuntimeError(f'{region} controller exited ({returncode}) without an eligible AL failure')
        if cycles >= config['maximum_controller_cycles']:
            raise RuntimeError('bounded recovery cycles exhausted: ' + region)
    return {'region': region, 'controller_cycles': cycles, 'status': 'complete'}


def drain_lane(config, identity, audit, lane, queue, cpus, runtime, poll_seconds):
    completed = [region for region in queue if region_complete(config, region)]
    failures = []
    quarantine = runtime / 'quarantine'
    for region in queue:
        quarantine_path = quarantine / f'{region}.json'
        if region in completed or quarantine_path.is_file():
            if quarantine_path.is_file():
                failures.append(read(quarantine_path))
            continue
        try:
            result = run_region(config, identity, audit, region, cpus, runtime, lane, poll_seconds)
            completed.append(region)
            atomic_json(runtime / f'{region}.completed.json', result)
        except Exception as error:
            failure = {'region': region, 'lane': lane, 'error_type': type(error).__name__,
                       'reason': str(error), 'test_opened': False,
                       'posterior_target_changed': False, 'epoch': time.time()}
            atomic_json(quarantine_path, failure)
            failures.append(failure)
        atomic_json(runtime / f'{lane}.progress.json',
                    lane_progress(config, lane, None, completed, failures,
                                  audit['scheduler_pid']))
    result = lane_progress(config, lane, None, completed, failures, audit['scheduler_pid'])
    result['status'] = ('R145_LANE_COMPLETE_NOT_PROMOTED' if not failures
                        else 'R145_LANE_DRAINED_WITH_QUARANTINED_FAILURES')
    atomic_json(runtime / f'{lane}.terminal.json', result)
    return result


def run(config, poll_seconds=15):
    audit = validate(config, require_idle=False)
    identity = audit['source']
    runtime = DATA / 'launch_prep' / config['tag'] / 'muscat'
    runtime.mkdir(parents=True, exist_ok=True)
    with (runtime / 'supervisor.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        atomic_json(runtime / 'audit.json', audit)
        reopened = reopen_interrupted_preparation_failures(config, runtime)
        if reopened:
            atomic_json(runtime / 'reopened_interrupted_preparations.json', {
                'status': 'R145_INTERRUPTED_PREPARATIONS_REOPENED',
                'regions': reopened,
                'test_opened': False,
                'posterior_target_changes': 0,
                'epoch': time.time(),
            })
        jobs = {
            'at': ([config['blocked_region']], config['at_cpus']),
            'continuation': (config['continuation_regions'], config['continuation_cpus']),
        }
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures = {
                lane: pool.submit(drain_lane, config, identity, audit, lane, queue, cpus,
                                  runtime, poll_seconds)
                for lane, (queue, cpus) in jobs.items()
            }
            results = {lane: future.result() for lane, future in futures.items()}
        failures = [failure for result in results.values() for failure in result['failures']]
        terminal = {
            'status': ('R145_MUSCAT_SLOT_A_COMPLETE_NOT_PROMOTED' if not failures else
                       'R145_MUSCAT_SLOT_A_DRAINED_WITH_QUARANTINED_FAILURES'),
            'lanes': results,
            'source': identity,
            'source_r141': audit['source_r141'],
            'health': health(config),
            'test_opened': False,
            'posterior_target_changes': 0,
            'epoch': time.time(),
        }
        atomic_json(runtime / 'terminal.json', terminal)
        if failures:
            raise RuntimeError('R145 drained healthy work but retained quarantined failures')
        return terminal


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('audit', 'run'))
    parser.add_argument('--poll-seconds', type=int, default=15)
    arguments = parser.parse_args()
    configuration = read(CONFIG)
    value = (validate(configuration) if arguments.action == 'audit'
             else run(configuration, arguments.poll_seconds))
    print(json.dumps(value, indent=2, sort_keys=True), flush=True)
