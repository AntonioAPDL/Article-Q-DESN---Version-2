#!/usr/bin/env python3
"""Explicit, single-activation resource boundary for unchanged R144 CZ science.

The historical R143 quarantined terminal is never rewritten as clean. An
append-only authority allows only its pinned NO_3 quarantine and changes only
R144's required predecessor status parameter. Numerical workers and source
identity remain the original R144 implementation. This entry's actual control
source, service and invocation are attested separately.
"""
from __future__ import annotations
import argparse
import contextlib
import csv
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import resource
import socket
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
RUNTIME = DATA / 'launch_prep/pricefm_stage_r153_control_lifecycle_20261025/cz'
R144_ROOT = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_r144_cz_fallback_20261020')
R144_ENTRY = R144_ROOT / 'application/scripts/pricefm/486_run_pricefm_stage_r144_cz_training_fallback.py'
R144_CONFIG = R144_ROOT / 'application/config/pricefm_stage_r144_cz_training_fallback_20261020.json'
R143_ROOT = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_r143_queue_recovery_20261020')
R143_ENTRY = R143_ROOT / 'application/scripts/pricefm/485_run_pricefm_stage_r143_cz_quarantine_queue.py'
R143_CONFIG = R143_ROOT / 'application/config/pricefm_stage_r143_cz_quarantine_queue_recovery_20261020.json'
ADAPTER = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r152_parent_recovery_20261024/application/scripts/pricefm/511_recover_pricefm_stage_r152_baseline_owner.py')
PYTHON = DATA / 'runtime_envs/r137_py311/bin/python'
DEGRADED = 'R143_QUEUE_DRAINED_WITH_QUARANTINED_FAILURES'
CLEAN = 'R143_QUEUE_COMPLETE_NOT_PROMOTED'
R143_UNIT = 'pricefm-r143-jerez-slot-b.service'
OLD_WAITER_UNIT = 'pricefm-r144-jerez-cz-fallback.service'
QUEUE = ['ES', 'HR', 'IT_SARD', 'LV', 'NO_3', 'PT', 'SE_3']
APPROVED_NO3_TASKS = [
    'iq_NO_3_r134_283a8c333135aae3_t2.291521491921e-03_s1_al0.75',
    'iq_NO_3_r134_283a8c333135aae3_t2.291521491921e-05_s1_al0.75',
]
APPROVED_NO3_REVIEWED_SHA = {'iq_NO_3_r134_283a8c333135aae3_t2.291521491921e-03_s1_al0.75': {'task': '5d1f5ba257833341e0d0c2d444285b1eb229c42228b808e37ccd688af00d7283', 'seal': 'c136e0b3fde52c9407488035076d002e2fb125ca677aa8acfb9728bbd5436077', 'certificate': 'd5b22a44864d3a82f3e448a5c11a688fe77f21e5fc2882e8fa415a75967d0680'}, 'iq_NO_3_r134_283a8c333135aae3_t2.291521491921e-05_s1_al0.75': {'task': 'cad23cc34eab770c5f1e44012aabd6d21e322c3ecebd4f7c5de6d4a9d89bb7d9', 'seal': '1f544ac45419dc5894c204605c101acdd9ac77e1102a341831557f4abee85735', 'certificate': '4a657cc5d9e1bdc735c1d72c2af8d983afea47e2d7f17b0bfcbfba270822d841'}}
THREADS = ('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS',
           'BLIS_NUM_THREADS', 'NUMEXPR_NUM_THREADS', 'R_DATATABLE_NUM_THREADS')


def read(path): return json.loads(Path(path).read_text())
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def now(): return time.time()
def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value

def immutable(path, value):
    """Create once with fsync+link; an existing record is never overwritten."""
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name('.' + path.name + '.' + uuid.uuid4().hex)
    try:
        with temporary.open('x') as stream:
            stream.write(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n')
            stream.flush(); os.fsync(stream.fileno())
        os.link(temporary, path)
    finally: temporary.unlink(missing_ok=True)
    descriptor = os.open(path.parent, os.O_RDONLY)
    try: os.fsync(descriptor)
    finally: os.close(descriptor)
    return value

def atomic(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name('.' + path.name + '.' + uuid.uuid4().hex)
    try:
        with temporary.open('x') as stream:
            stream.write(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n')
            stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally: temporary.unlink(missing_ok=True)

@contextlib.contextmanager
def locked(path):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try: yield
        finally: fcntl.flock(stream, fcntl.LOCK_UN)


def source_identity(root=ROOT):
    root = Path(root)
    def git(*args): return subprocess.check_output(['git', '-C', str(root), *args], text=True,timeout=30).strip()
    if git('status', '--porcelain'): raise RuntimeError('source worktree is not clean: ' + str(root))
    return dict(root=str(root), branch=git('branch', '--show-current'), head=git('rev-parse', 'HEAD'))


def source_files():
    return [ENTRY, ENTRY.with_name('516_release_pricefm_stage_r153_cz_gate.py')]


def verify_files(records):
    for filename, expected in records.items():
        path = Path(filename)
        if path.is_symlink() or not path.is_file() or sha(path) != expected:
            raise RuntimeError('pinned source/evidence differs: ' + str(path))


def effective_config(original):
    value = json.loads(json.dumps(original))
    if original.get('predecessor_terminal_status') != CLEAN:
        raise RuntimeError('original R144 predecessor contract is not the pinned clean policy')
    value['predecessor_terminal_status'] = DEGRADED
    return value


def check_effective_config(authority):
    original = read(authority['science_config_path'])
    if sha(authority['science_config_path']) != authority['science_config_sha256']:
        raise RuntimeError('original scientific configuration changed')
    value = effective_config(original)
    digest = hashlib.sha256((json.dumps(value, indent=2, sort_keys=True) + '\n').encode()).hexdigest()
    effective_path=Path(authority['runtime'])/'effective_config.json'
    if (value != authority['effective_config'] or digest != authority['effective_config_sha256']
            or sha(effective_path)!=digest or read(effective_path)!=value):
        raise RuntimeError('effective configuration/resource delta differs')
    changed = {key for key in set(original) | set(value) if original.get(key) != value.get(key)}
    if changed != {'predecessor_terminal_status'}:
        raise RuntimeError('scientific configuration was changed by resource resolution')
    return value


def validate_authority(path, *, system=None, require_host=True, allow_expired=False):
    path = Path(path).resolve(); authority = read(path); system = system or System()
    if (authority.get('schema_version') != 1 or authority.get('kind') != 'R153_CZ_RESOURCE_RESOLUTION'
            or authority.get('activation_limit') != 1 or authority.get('scientific_dispatch_limit') != 1
            or authority.get('approved_quarantined_regions') != ['NO_3']
            or authority.get('predecessor_queue') != QUEUE
            or authority.get('resource_only') is not True or authority.get('cached_restart_authorized') is not False
            or authority.get('fit_cap_changes') != 0 or authority.get('certificate_limit_changes') != 0
            or authority.get('scientific_source_changes') != 0
            or authority.get('waiter_control_cpu')!=29
            or authority.get('budget_heartbeat_max_age_seconds')!=90
            or authority.get('final_publication_CPU_reserve_seconds')!=90):
        raise RuntimeError('CZ resource authority scope differs')
    if require_host and system.host() != 'jerez': raise RuntimeError('CZ dispatch is restricted to Jerez')
    if not 0 < authority['expires_epoch'] - authority['created_epoch'] <= 7 * 86400:
        raise RuntimeError('CZ waiter lifetime is not finite within seven days')
    if not 0 < authority['control_CPU_allowance_seconds'] <= 1800:
        raise RuntimeError('CZ waiter control allowance differs')
    if not allow_expired and system.now() >= authority['expires_epoch']:
        raise RuntimeError('CZ gate authority expired; no automatic renewal')
    if (Path(authority['runtime']).resolve() != (RUNTIME / authority['id']).resolve()
            or path != Path(authority['runtime']) / 'authority.json'):
        raise RuntimeError('authority is outside its exact canonical runtime')
    if not re.fullmatch(r'[a-f0-9]{32}', authority['id']): raise RuntimeError('invalid authority identity')
    if authority['waiter_unit'] != 'pricefm-r153-cz-gate-' + authority['id'] + '.service':
        raise RuntimeError('waiter unit identity differs')
    if authority['science_unit'] != 'pricefm-r153-cz-science-' + authority['id'] + '.service':
        raise RuntimeError('scientific unit identity differs')
    verify_files(authority['frozen_sha256']); verify_files(authority['approved_NO3_evidence_sha256'])
    for key in ('execution_source', 'science_source', 'predecessor_source', 'process_adapter_source', 'resource_core_source'):
        if system.source(authority[key]['root']) != authority[key]:
            raise RuntimeError('source identity differs: ' + key)
    archive=authority.get('archived_original_waiter_progress')
    if archive and (Path(archive['archive'])!=Path(authority['runtime'])/'original_waiter_progress.json'
                    or sha(archive['archive'])!=archive['sha256']):
        raise RuntimeError('archived original CZ waiter progress differs')
    value = check_effective_config(authority)
    if (value['region'] != 'CZ' or value['fallback_rank'] != 3 or value['al_max_iter'] != 300
            or value['cpus'] != list(range(15, 30)) or value['maximum_workers'] != 15
            or authority['old_waiter']['unit'] != OLD_WAITER_UNIT
            or authority['predecessor']['unit'] != R143_UNIT):
        raise RuntimeError('CZ numerical scope or predecessor identity changed')
    registry=RUNTIME/'single_activation_claim.json'
    if registry.is_file():
        record=read(registry)
        if record.get('authority_sha256')!=sha(path) or record.get('id')!=authority['id']:
            raise RuntimeError('finite CZ activation already belongs to another authority')
    no3 = DATA / 'campaigns' / (value['source_tag'] + '__NO_3')
    for name in APPROVED_NO3_TASKS:
        done = no3 / 'tasks_done' / name
        expected=APPROVED_NO3_REVIEWED_SHA[name]
        reviewed={str(no3/'tasks'/(name+'.json')):expected['task'],
                  str(done/'completed_evidence.json'):expected['seal'],
                  str(done/'fit/fixedpoint_certificate.json'):expected['certificate']}
        if any(authority['approved_NO3_evidence_sha256'].get(filename)!=digest
               for filename,digest in reviewed.items()):
            raise RuntimeError('NO3 evidence differs from the exact reviewed failure targets')
        if read(done / 'completed_evidence.json').get('metadata', {}).get('certified') is not False:
            raise RuntimeError('approved NO3 failure was replaced or recertified')
        cert = read(done / 'fit/fixedpoint_certificate.json')
        if cert.get('certified') is not False:
            raise RuntimeError('approved NO3 certificate status differs')
    return authority


class System:
    """Actual-host process/cgroup reads; lifecycle helpers are explicit."""
    def __init__(self):
        self.admin_invocations=0
        self.adapter = module('r153_cz_frozen_process_adapter', ADAPTER).RecoverySystem()
    def now(self): return time.time()
    def host(self): return socket.gethostname().split('.')[0].lower()
    def source(self, root):
        self.admin_invocations+=3
        return source_identity(root)
    def process(self, pid): return self.adapter.process(pid)
    def recorded(self, expected):
        sample=self.adapter.stat_sample(expected['pid'])
        if self.adapter.terminal_or_gone(sample):return None
        if (sample['start_ticks']!=expected['start_ticks']
                or self.adapter.boot_id!=expected['boot_id']):return None
        return self.process(expected['pid'])
    def processes(self): return self.adapter.processes()
    def members(self, cgroup): return self.adapter.members(cgroup)
    def unit(self, name):
        self.admin_invocations+=1
        names = ['Id', 'LoadState', 'ActiveState', 'SubState', 'MainPID', 'ControlGroup', 'InvocationID',
                 'CPUUsageNSec', 'CPUAccounting', 'KillMode', 'Restart', 'WorkingDirectory', 'NRestarts',
                 'RuntimeMaxUSec', 'ExecStart', 'Result']
        result = subprocess.run(['systemctl', '--user', 'show', name, '--property=' + ','.join(names)],
                                text=True, capture_output=True, timeout=30)
        props = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
        if result.returncode and props.get('LoadState') != 'not-found':
            raise RuntimeError('unit inspection failed: ' + name + ': ' + result.stderr.strip())
        return props
    def start_science(self, authority, authority_path):
        self.admin_invocations+=1
        command = [str(PYTHON), '-B', str(ENTRY), 'delegate', '--authority', str(authority_path),
                   '--delegated-entry', str(R144_ENTRY), '--unit', authority['science_unit']]
        subprocess.run(['systemd-run', '--user', '--quiet', '--unit=' + authority['science_unit'],
                        '--property=Restart=no', '--property=KillMode=process', '--property=CPUAccounting=yes',
                        '--property=WorkingDirectory=' + str(ROOT),
                        *['--setenv=' + name + '=1' for name in THREADS], *command],
                       check=True, timeout=30)
        return command
    def proc_cpu_snapshot(self,expected):
        raw=(Path('/proc')/str(expected['pid'])/'stat').read_text()
        fields=raw[raw.rfind(')')+2:].split();ticks=os.sysconf('SC_CLK_TCK')
        if (int(fields[19])!=expected['start_ticks'] or self.adapter.boot_id!=expected['boot_id']
                or fields[0] in {'Z','X','x'}):
            raise RuntimeError('recorded control CPU lifetime is not live')
        return dict(self_CPU_seconds=(int(fields[11])+int(fields[12]))/ticks,
                    reaped_child_CPU_seconds=(int(fields[13])+int(fields[14]))/ticks,
                    tick_seconds=1./ticks)
    def own_admin_cpu(self):
        process=self.process(os.getpid())
        if process is None:raise RuntimeError('current control CPU process is unreadable')
        usage=resource.getrusage(resource.RUSAGE_CHILDREN)
        own=resource.getrusage(resource.RUSAGE_SELF)
        child_cpu=usage.ru_utime+usage.ru_stime
        measured=max(time.process_time(),own.ru_utime+own.ru_stime)
        proc=self.proc_cpu_snapshot(process)
        if measured+2*proc['tick_seconds']<proc['self_CPU_seconds'] or child_cpu+2*proc['tick_seconds']<proc['reaped_child_CPU_seconds']:
            raise RuntimeError('process/resource control CPU measurements disagree')
        return dict(process=process,self_CPU_seconds=measured,reaped_admin_CPU_seconds=child_cpu,
                    admin_measurement_reserve_seconds=.002+.001*self.admin_invocations,
                    administrative_invocations=self.admin_invocations,proc_CPU=proc)
    def sleep(self, seconds): time.sleep(seconds)


def recorded_process(system, expected):
    return system.recorded(expected) if hasattr(system,'recorded') else system.process(expected['pid'])


def same_lifetime(current, expected):
    return bool(current) and all(current.get(k) == expected.get(k) for k in ('pid', 'start_ticks', 'boot_id'))


def exact_process(current, expected):
    return same_lifetime(current, expected) and all(current.get(k) == expected.get(k)
                                                    for k in ('cmdline_sha256', 'cwd'))


def old_waiter_drained(authority, system):
    record = authority['old_waiter']; props = system.unit(record['unit'])
    expected = record['process']; current = recorded_process(system,expected)
    members = sorted(set(system.members(record['cgroup'])) | set(system.members(props.get('ControlGroup', ''))))
    if (props.get('ActiveState') in {'active', 'activating', 'deactivating'}
            or int(props.get('MainPID', 0)) or members or same_lifetime(current, expected)):
        return dict(drained=False, unit=props, members=members)
    return dict(drained=True, unit=props, members=[])


def complete_region(config, region):
    folder = DATA / 'campaigns' / (config['source_tag'] + '__' + region)
    terminal_path = folder / 'terminal.json'; seal_path = folder / 'closeout/completed_evidence.json'
    if not terminal_path.is_file() or not seal_path.is_file(): return False
    terminal = read(terminal_path); seal = read(seal_path)
    expected = dict(branch=config['source_branch'], head=config['source_head'])
    if (terminal.get('status') != 'R141_REGION_COMPLETE_NOT_PROMOTED' or terminal.get('source') != expected
            or seal.get('metadata', {}).get('source') != expected):
        raise RuntimeError('R143 completed regional source/terminal differs: ' + region)
    closeout = folder / 'closeout'
    for relative, digest in seal['artifacts'].items():
        target = (closeout / relative).resolve()
        if not target.is_relative_to(closeout.resolve()) or sha(target) != digest:
            raise RuntimeError('R143 regional closeout payload differs: ' + region)
    with (closeout / 'fold_comparison.csv').open() as stream: rows = list(csv.DictReader(stream))
    if (len(rows) != 12 or {(int(row['fold']), row['operator']) for row in rows} !=
            {(fold, operator) for fold in (1, 2, 3)
             for operator in ('cdf_pool_clipped', 'mean_feature', 'path_specific', 'normal_driver')}
            or any(row['region'] != region or not math.isfinite(float(row['AQL'])) or float(row['AQL']) < 0
                   for row in rows)):
        raise RuntimeError('R143 regional closeout surface differs: ' + region)
    return dict(terminal_sha256=sha(terminal_path), closeout_sha256=sha(seal_path))


def numerical_conflicts(authority, processes):
    """No predecessor or known numerical role may occupy the declared slot."""
    config = authority['effective_config']; cpus = set(config['cpus']); conflicts = []
    regions = set(QUEUE + ['CZ']); source_entry = str(Path(config['source_worktree']) /
                                  'application/scripts/pricefm/480_run_pricefm_stage_r141_region.py')
    for process in processes:
        argv = process.get('argv', [])
        if not argv: raise RuntimeError('live process has empty metadata in CZ boundary census')
        args = set(argv); names = {Path(arg).name for arg in argv if len(arg) < 4096}
        r_process = bool(names.intersection({'R', 'Rscript'}))
        worker = 'worker' in args or 'payload' in args or 'bootstrap' in args
        region = None
        if '--region' in argv:
            index = argv.index('--region'); region = argv[index + 1] if index + 1 < len(argv) else None
        queue_controller = source_entry in args and 'controller' in args and region in regions
        queue_worker = source_entry in args and worker and region in regions
        r144_worker = str(R144_ENTRY) in args and bool(args.intersection({'prepare', 'worker', 'controller'}))
        if queue_controller or queue_worker or r144_worker or ((r_process or worker) and cpus.intersection(process.get('cpus', []))):
            conflicts.append(process)
    return conflicts


def quarantine_matches(authority, value):
    failures = value.get('failures', [])
    if failures != authority['approved_predecessor_failures']:
        raise RuntimeError('unapproved/new R143 quarantine or failure replacement')


def boundary_state(authority, system, *, complete=complete_region):
    """Read only. A truthful terminal plus actual unit/model drain is required."""
    config = authority['effective_config']
    runtime = DATA / 'launch_prep' / config['predecessor_tag'] / 'jerez'
    progress_path = runtime / 'progress.json'
    if progress_path.is_file(): quarantine_matches(authority, read(progress_path))
    terminal_path = runtime / 'terminal.json'
    if not terminal_path.is_file():
        return dict(ready=False, status='R153_CZ_WAITING_FOR_COMPLETE_R143_QUEUE',
                    predecessor_unit=system.unit(authority['predecessor']['unit']))
    terminal_sha = sha(terminal_path)
    terminal = read(terminal_path); quarantine_matches(authority, terminal)
    expected = dict(branch=config['source_branch'], head=config['source_head'])
    if (terminal.get('status') != DEGRADED or terminal.get('source') != expected
            or terminal.get('assigned_count') != len(QUEUE) or terminal.get('active_region') is not None
            or terminal.get('pending') != [] or terminal.get('quarantined_region') != 'CZ'
            or set(terminal.get('completed', [])) != set(QUEUE) - {'NO_3'}):
        raise RuntimeError('R143 failure-retaining final disposition differs')
    closeouts = {region: complete(config, region) for region in QUEUE if region != 'NO_3'}
    if not all(closeouts.values()): raise RuntimeError('R143 final terminal lacks a required completed region')
    props = system.unit(authority['predecessor']['unit']); recorded = authority['predecessor']
    live = recorded_process(system,recorded['process'])
    members = sorted(set(system.members(recorded['cgroup'])) | set(system.members(props.get('ControlGroup', ''))))
    if (props.get('ActiveState') in {'active', 'activating', 'deactivating'}
            or int(props.get('MainPID', 0)) or same_lifetime(live, recorded['process']) or members):
        return dict(ready=False, status='R153_CZ_WAITING_FOR_R143_PROCESS_AND_CGROUP_DRAIN',
                    terminal_sha256=sha(terminal_path), predecessor_unit=props, members=members)
    conflicts = numerical_conflicts(authority, system.processes())
    if conflicts:
        return dict(ready=False, status='R153_CZ_WAITING_FOR_SLOT_B_NUMERICAL_DRAIN',
                    terminal_sha256=sha(terminal_path), conflicts=conflicts)
    # A live restart, changing terminal or reappearing orphan defeats proof.
    again = system.unit(recorded['unit'])
    if sha(terminal_path) != terminal_sha:
        raise RuntimeError('R143 terminal changed during boundary proof')
    if (again.get('ActiveState') in {'active', 'activating', 'deactivating'}
            or int(again.get('MainPID', 0)) or system.members(recorded['cgroup'])
            or system.members(again.get('ControlGroup', ''))
            or same_lifetime(recorded_process(system,recorded['process']), recorded['process'])):
        return dict(ready=False, status='R153_CZ_WAITING_FOR_R143_STABLE_DRAIN')
    return dict(ready=True, status='R153_CZ_TRUTHFUL_QUARANTINE_BOUNDARY_READY',
                terminal_path=str(terminal_path), terminal_sha256=sha(terminal_path),
                predecessor_status=DEGRADED, preserved_failures=terminal['failures'],
                completed_closeouts=closeouts, predecessor_unit=again, numerical_conflicts=[])


def sha_bytes(value): return hashlib.sha256(value.encode()).hexdigest()


def systemd_seconds(value):
    if not value or value == 'infinity': raise RuntimeError('finite systemd timeout unavailable')
    if value.isdigit(): return int(value) / 1e6
    parts=re.findall(r'([0-9]+(?:\.[0-9]+)?)\s*(us|µs|ms|min|s|h|d|w)',value)
    leftover=re.sub(r'([0-9]+(?:\.[0-9]+)?)\s*(us|µs|ms|min|s|h|d|w)','',value).strip()
    if not parts or leftover: raise RuntimeError('unrecognized systemd finite timeout: '+value)
    scales={'us':1e-6,'µs':1e-6,'ms':.001,'s':1,'min':60,'h':3600,'d':86400,'w':604800}
    return sum(float(number)*scales[unit] for number,unit in parts)


def self_attestation(authority, path, system, *, role):
    unit = authority['waiter_unit'] if role == 'waiter' else authority['science_unit']
    props = system.unit(unit); process = system.process(os.getpid())
    argv = [str(PYTHON), '-B', str(ENTRY), 'run' if role == 'waiter' else 'delegate',
            '--authority', str(Path(path).resolve())]
    if role != 'waiter': argv += ['--delegated-entry', str(R144_ENTRY)]
    argv += ['--unit', unit]
    if (not process or process['argv'] != argv or process['cwd'] != str(ROOT)
            or int(props.get('MainPID', 0)) != os.getpid() or props.get('Id') != unit
            or not props.get('InvocationID') or props.get('Restart') != 'no'
            or props.get('KillMode') != 'process' or props.get('CPUAccounting') != 'yes'
            or props.get('WorkingDirectory') != str(ROOT)
            or not props.get('ControlGroup') or props['ControlGroup'] not in process.get('cgroups', [])):
        raise RuntimeError('truthful CZ resource/science unit self-attestation differs')
    if role == 'waiter':
        if process.get('cpus')!=[authority['waiter_control_cpu']]:
            raise RuntimeError('CZ waiter/admin CPU mask differs from its finite control grant')
        seconds=systemd_seconds(props.get('RuntimeMaxUSec',''))
        launch_claim=read(Path(authority['runtime'])/'launch_claim.json')
        if (seconds<=0 or seconds>7*86400 or seconds!=launch_claim.get('expected_RuntimeMaxSec')
                or launch_claim.get('authority_sha256')!=sha(path)
                or launch_claim.get('expected_argv')!=argv):
            raise RuntimeError('CZ waiter independent systemd expiry/launch contract differs')
    return dict(unit=unit, properties=props, process=process, epoch=system.now(),
                actual_entry=str(ENTRY), delegated_entry=str(R144_ENTRY) if role != 'waiter' else None,
                execution_source=authority['execution_source'], scientific_source=authority['science_source'])


def native_cpu_seconds(props):
    raw=props.get('CPUUsageNSec')
    if raw in (None,'','[not set]','18446744073709551615'):return None
    try:value=int(raw)/1e9
    except (ValueError,TypeError):raise RuntimeError('native control CPU counter is malformed')
    if not math.isfinite(value) or value<0:raise RuntimeError('native control CPU counter is invalid')
    return value


def finite_cpu(value,label):
    if isinstance(value,bool) or not isinstance(value,(int,float)) or not math.isfinite(value) or value<0:
        raise RuntimeError('invalid measured control CPU field: '+label)
    return float(value)


def waiter_cpu_snapshot(authority,system):
    """Only the actual waiter may publish its own+reaped-admin measurements.

    Its trusted children are synchronous Git/systemctl/systemd-run helpers.
    The numerical R144 unit is launched by systemd and is not its child. All
    waiter/admin work is confined to one CPU; it cannot fund a model slot.
    """
    props=system.unit(authority['waiter_unit'])
    if int(props.get('MainPID',0))!=os.getpid() or props.get('ActiveState')!='active':
        raise RuntimeError('only the actual attested waiter may publish its measured CPU')
    if not hasattr(system,'own_admin_cpu'):raise RuntimeError('measured waiter/admin CPU is unavailable')
    own=system.own_admin_cpu();process=own['process']
    if process.get('pid')!=os.getpid() or process.get('cpus')!=[authority['waiter_control_cpu']]:
        raise RuntimeError('measured waiter CPU identity or single-CPU bound differs')
    self_cpu=finite_cpu(own['self_CPU_seconds'],'self')
    child_cpu=finite_cpu(own['reaped_admin_CPU_seconds'],'reaped administrative children')
    reserve=finite_cpu(own['admin_measurement_reserve_seconds'],'measurement reserve')
    native=native_cpu_seconds(props)
    waiter=max(self_cpu+child_cpu+reserve,native or 0.)
    prior=finite_cpu(authority['prior_control_CPU_charged_seconds'],'prior carry')
    path=Path(authority['runtime'])/'authority.json'
    result=dict(schema_version=1,authority_sha256=sha(path),execution_source=authority['execution_source'],
        unit=authority['waiter_unit'],InvocationID=props['InvocationID'],
        process={key:process[key] for key in ('pid','start_ticks','boot_id','cmdline_sha256','cwd')},
        heartbeat_epoch=system.now(),mode='self_plus_reaped_administrative_children',
        control_cpu=authority['waiter_control_cpu'],self_CPU_seconds=self_cpu,
        reaped_admin_CPU_seconds=child_cpu,admin_measurement_reserve_seconds=reserve,
        administrative_invocations=own.get('administrative_invocations',0),
        native_cgroup_CPU_seconds=native,waiter_CPU_seconds=waiter,
        prior_control_CPU_seconds=prior,charged_CPU_seconds=prior+waiter,
        allowance_CPU_seconds=authority['control_CPU_allowance_seconds'],expires_epoch=authority['expires_epoch'],
        numerical_CPU_included=False,in_flight_publication_CPU_reserve_seconds=authority['final_publication_CPU_reserve_seconds'])
    previous=Path(authority['runtime'])/'control_budget_heartbeat.json'
    if previous.is_file():
        old=read(previous)
        if (old.get('authority_sha256')!=result['authority_sha256'] or old.get('process')!=result['process']
                or old.get('InvocationID')!=result['InvocationID']
                or self_cpu+.001<old.get('self_CPU_seconds',0)
                or child_cpu+.001<old.get('reaped_admin_CPU_seconds',0)
                or result['charged_CPU_seconds']+.001<old.get('charged_CPU_seconds',0)):
            raise RuntimeError('measured control CPU heartbeat was reset or refunded')
    return result


def publish_waiter_budget(authority,system):
    value=waiter_cpu_snapshot(authority,system)
    value['within_CPU']=value['charged_CPU_seconds']+authority['final_publication_CPU_reserve_seconds']<value['allowance_CPU_seconds']
    value['within_wall']=value['heartbeat_epoch']<value['expires_epoch']
    atomic(Path(authority['runtime'])/'control_budget_heartbeat.json',value)
    return value


def cpu_guard(authority,system):
    value=publish_waiter_budget(authority,system)
    if not value['within_CPU']:raise RuntimeError('CZ waiter exhausted its finite measured control CPU allowance')
    if not value['within_wall']:raise RuntimeError('CZ waiter expired before its scientific claim')
    return value['charged_CPU_seconds']


def observe_waiter_cpu(authority,authority_path,system,capsule):
    """Pure external verifier: never charges the observer's CPU as the owner.

    Read fresh owner stat plus its last measured reaped-child heartbeat. Since
    the complete trusted waiter/admin unit is confined to one CPU, elapsed wall
    time is a conservative upper bound for any child CPU since that sample.
    """
    path=Path(authority_path).resolve();unit=authority['waiter_unit'];props=system.unit(unit)
    recorded=capsule['process'];current=recorded_process(system,recorded)
    expected_argv=[str(PYTHON),'-B',str(ENTRY),'run','--authority',str(path),'--unit',unit]
    if (not exact_process(current,recorded) or current.get('argv')!=expected_argv
            or current.get('cpus')!=[authority['waiter_control_cpu']]
            or props.get('ActiveState')!='active' or int(props.get('MainPID',0))!=recorded['pid']
            or props.get('InvocationID')!=capsule['properties']['InvocationID']
            or props.get('Restart')!='no' or props.get('KillMode')!='process'
            or props.get('CPUAccounting')!='yes' or props.get('ControlGroup')!=capsule['properties']['ControlGroup']
            or capsule.get('execution_source')!=authority['execution_source']):
        raise RuntimeError('external waiter CPU proof lacks its exact live owner/unit/source')
    value=read(Path(authority['runtime'])/'control_budget_heartbeat.json')
    identity={key:recorded[key] for key in ('pid','start_ticks','boot_id','cmdline_sha256','cwd')}
    epoch=finite_cpu(value.get('heartbeat_epoch'),'heartbeat epoch');age=system.now()-epoch
    if (value.get('schema_version')!=1 or value.get('authority_sha256')!=sha(path)
            or value.get('execution_source')!=authority['execution_source'] or value.get('unit')!=unit
            or value.get('InvocationID')!=props['InvocationID'] or value.get('process')!=identity
            or value.get('mode')!='self_plus_reaped_administrative_children'
            or value.get('control_cpu')!=authority['waiter_control_cpu']
            or value.get('numerical_CPU_included') is not False
            or age<0 or age>authority['budget_heartbeat_max_age_seconds']):
        raise RuntimeError('measured waiter CPU heartbeat is missing, stale, unbound or reset')
    fields={key:finite_cpu(value.get(key),key) for key in ('self_CPU_seconds','reaped_admin_CPU_seconds',
        'admin_measurement_reserve_seconds','waiter_CPU_seconds','prior_control_CPU_seconds',
        'charged_CPU_seconds','allowance_CPU_seconds','expires_epoch')}
    if (fields['prior_control_CPU_seconds']!=authority['prior_control_CPU_charged_seconds']
            or fields['allowance_CPU_seconds']!=authority['control_CPU_allowance_seconds']
            or fields['expires_epoch']!=authority['expires_epoch']
            or abs(fields['charged_CPU_seconds']-fields['prior_control_CPU_seconds']-fields['waiter_CPU_seconds'])>1e-6
            or fields['waiter_CPU_seconds']+1e-6<fields['self_CPU_seconds']+fields['reaped_admin_CPU_seconds']+fields['admin_measurement_reserve_seconds']):
        raise RuntimeError('reported measured control CPU contains a refund or changed finite allowance')
    # Do not infer containment from the dispatcher's original mask: inspect
    # every currently visible member of this specific new administrative unit.
    for pid in system.members(props['ControlGroup']):
        process=system.process(pid)
        if process is not None and process.get('cpus')!=[authority['waiter_control_cpu']]:
            raise RuntimeError('waiter administrative child escaped its single-CPU accounting bound')
    proc=system.proc_cpu_snapshot(recorded)
    fresh_self=finite_cpu(proc['self_CPU_seconds'],'fresh owner proc CPU')
    fresh_children=finite_cpu(proc['reaped_child_CPU_seconds'],'fresh owner proc reaped CPU')
    tick=finite_cpu(proc['tick_seconds'],'kernel accounting tick')
    if tick<=0 or fresh_self+2*tick<fields['self_CPU_seconds'] or fresh_children+2*tick<fields['reaped_admin_CPU_seconds']:
        raise RuntimeError('fresh owner CPU contradicts its measured heartbeat; possible rollback')
    native=native_cpu_seconds(props)
    old_native=value.get('native_cgroup_CPU_seconds')
    if old_native is not None:
        old_native=finite_cpu(old_native,'last native CPU')
        if native is not None and native+2*tick<old_native:
            raise RuntimeError('native control counter rolled back within its exact invocation')
    upper=max(fields['waiter_CPU_seconds'],native or 0.,
        fresh_self+max(fresh_children,fields['reaped_admin_CPU_seconds'])+age+2*tick+fields['admin_measurement_reserve_seconds'])
    charged=fields['prior_control_CPU_seconds']+upper
    return dict(status='VERIFIED_EXTERNAL_MEASURED_WAITER_CPU',basis='fresh_owner_proc_plus_measured_reaped_admin_children_and_single_CPU_elapsed_bound',
        heartbeat_age_seconds=age,control_cpu=authority['waiter_control_cpu'],
        measured_charged_CPU_seconds=fields['charged_CPU_seconds'],charged_CPU_upper_bound_seconds=charged,
        allowance_CPU_seconds=fields['allowance_CPU_seconds'],expires_epoch=fields['expires_epoch'],
        final_publication_CPU_reserve_seconds=authority['final_publication_CPU_reserve_seconds'],
        within_CPU=charged+authority['final_publication_CPU_reserve_seconds']<fields['allowance_CPU_seconds'],
        within_wall=system.now()<fields['expires_epoch'],
        numerical_CPU_included=False,observer_CPU_used=False)


def mirror_progress(authority, value):
    root = Path(authority['runtime']); atomic(root / 'progress.json', value)
    # Explicitly bridge the mutable current R144 resource pointer. Prior bytes
    # are archived by release, while scientific campaign/source remains R144.
    original = DATA / 'launch_prep' / authority['effective_config']['tag'] / 'jerez/progress.json'
    atomic(original, dict(value, source={k:authority['science_source'][k] for k in ('branch', 'head')},
                          execution_control_source=authority['execution_source'], authority_path=str(root / 'authority.json')))


def run(path, unit, *, system=None, poll_seconds=30):
    system = system or System(); path = Path(path).resolve()
    authority = validate_authority(path, system=system); root = Path(authority['runtime'])
    if unit != authority['waiter_unit']: raise RuntimeError('CZ waiter unit differs')
    old_runtime = DATA / 'launch_prep' / authority['effective_config']['tag'] / 'jerez'
    with locked(root / 'owner.lock'), locked(old_runtime / 'supervisor.lock'):
        grant=read(RUNTIME/'single_activation_claim.json')
        if grant.get('id')!=authority['id'] or grant.get('authority_sha256')!=sha(path):
            raise RuntimeError('CZ waiter lacks its sole global activation grant')
        if (not (root/'old_waiter_fence.json').is_file()
                or read(root/'old_waiter_fence.json').get('authority_sha256')!=sha(path)):
            raise RuntimeError('CZ waiter lacks an exact prior control-fence receipt')
        capsule = self_attestation(authority, path, system, role='waiter')
        if not old_waiter_drained(authority, system)['drained']:
            raise RuntimeError('old R144 waiter is not exactly drained')
        immutable(root / 'activation.json', dict(activation=1, authority_sha256=sha(path), capsule=capsule))
        try:
            while True:
                validate_authority(path, system=system)
                charged = cpu_guard(authority, system)
                state = boundary_state(authority, system)
                mirror_progress(authority, dict(state, epoch=system.now(), control_CPU_seconds=charged,
                                                scientific_dispatches=0, authority_sha256=sha(path)))
                if state['ready']:
                    # Full guard once more immediately before the one claim.
                    if not old_waiter_drained(authority, system)['drained']:
                        raise RuntimeError('old R144 waiter reappeared')
                    state = boundary_state(authority, system)
                    if not state['ready']: continue
                    cpu_guard(authority, system)
                    immutable(root / 'science_claim.json', dict(claim=1, authority_sha256=sha(path),
                        claimed_epoch=system.now(), boundary=state, unit=authority['science_unit']))
                    argv = system.start_science(authority, path)
                    immutable(root / 'science_launch.json', dict(argv=argv, unit=authority['science_unit'],
                        started_epoch=system.now(), scientific_source=authority['science_source'],
                        effective_config_sha256=authority['effective_config_sha256']))
                    final_budget=publish_waiter_budget(authority,system)
                    result = dict(status='R153_CZ_FROZEN_SCIENCE_DISPATCHED_WAITER_EXITING',
                                  epoch=system.now(), scientific_dispatches=1, unit=authority['science_unit'],
                                  control_CPU_seconds=final_budget['charged_CPU_seconds'],authority_sha256=sha(path))
                    mirror_progress(authority, result); immutable(root / 'waiter_terminal.json', result)
                    return result
                system.sleep(min(max(1, poll_seconds), 30))
        except BaseException as error:
            record = dict(status='R153_CZ_GATE_BLOCKED_NO_AUTOMATIC_RETRY', error=repr(error),
                          epoch=system.now(), scientific_dispatches=int((root / 'science_claim.json').exists()),
                          source=authority['execution_source'], models_signalled=False)
            immutable(root / 'waiter_blocked.json', record); mirror_progress(authority, record)
            raise


def delegate(path, unit, delegated_entry, *, system=None):
    system = system or System(); path = Path(path).resolve()
    authority = validate_authority(path, system=system); root = Path(authority['runtime'])
    if unit != authority['science_unit'] or Path(delegated_entry).resolve() != R144_ENTRY:
        raise RuntimeError('explicit original R144 delegation differs')
    # The waiter can still be finishing its bounded publication; the old
    # supervisor lock below must drain before any model work begins.
    claim = read(root / 'science_claim.json')
    if claim.get('claim') != 1 or claim.get('authority_sha256') != sha(path):
        raise RuntimeError('CZ scientific unit lacks exact create-once claim')
    old_runtime = DATA / 'launch_prep' / authority['effective_config']['tag'] / 'jerez'
    deadline = time.monotonic() + 30
    while True:
        try:
            lock = (old_runtime / 'supervisor.lock').open('a'); fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except BlockingIOError:
            lock.close()
            if time.monotonic() >= deadline: raise RuntimeError('CZ waiter did not release predecessor supervisor lock')
            system.sleep(.05)
    try:
        authority=validate_authority(path,system=system)
        capsule = self_attestation(authority, path, system, role='science')
        if not old_waiter_drained(authority, system)['drained'] or not boundary_state(authority, system)['ready']:
            raise RuntimeError('CZ scientific handoff lacks fresh predecessor/slot drain')
        immutable(root / 'scientific_activation.json', dict(activation=1, authority_sha256=sha(path), capsule=capsule,
                    effective_config_sha256=authority['effective_config_sha256']))
        original = module('r153_explicit_frozen_r144_science', R144_ENTRY)
        config = check_effective_config(authority)
        # This is the unchanged public controller API with a separately recorded
        # one-field resource parameter. Its own frozen source identity, worker
        # argv, numerical configuration, preparation and closeout remain R144.
        result = original.controller(config)
        immutable(root / 'science_terminal.json', dict(result=result, actual_control_capsule=capsule,
                    authority_sha256=sha(path), epoch=system.now()))
        original.atomic_json(old_runtime / 'terminal.json', result)
        mirror_progress(authority, dict(status='R153_CZ_FROZEN_SCIENCE_FINISHED', result=result, epoch=system.now()))
        return result
    except BaseException as error:
        failure=dict(status='R153_CZ_FROZEN_SCIENCE_BLOCKED',error=repr(error),epoch=system.now(),
                    original_science_preserved=True,automatic_retry=False,models_signalled=False)
        immutable(root/'science_blocked.json',failure);mirror_progress(authority,failure)
        raise
    finally:
        fcntl.flock(lock, fcntl.LOCK_UN); lock.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('inspect', 'run', 'delegate'))
    parser.add_argument('--authority', type=Path, required=True)
    parser.add_argument('--unit'); parser.add_argument('--delegated-entry', type=Path)
    args = parser.parse_args(); system = System()
    if args.action == 'inspect':
        authority = validate_authority(args.authority, system=system)
        value = dict(authority_sha256=sha(args.authority), old_waiter=old_waiter_drained(authority, system),
                     boundary=boundary_state(authority, system), source_runtime_changes=0, model_dispatches=0)
    elif args.action == 'run': value = run(args.authority, args.unit, system=system)
    else: value = delegate(args.authority, args.unit, args.delegated_entry, system=system)
    print(json.dumps(value, indent=2, sort_keys=True), flush=True)

if __name__ == '__main__': main()
