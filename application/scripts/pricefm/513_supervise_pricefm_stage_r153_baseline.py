#!/usr/bin/env python3
"""Explicit additional baseline control, preserving the spent R152 chain.

This resource controller composes immutable R152 dispatch/packet helpers and
R141 numerical workers. It does not patch their globals, normalize observations,
signal numerical processes, repair a fit, or reopen cached development.
"""
from __future__ import annotations

import argparse
import contextlib
import copy
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
OLD_ROOT = ROOT.parent / 'pricefm_r152_parallel_20261024'
ADAPTER_ROOT = ROOT.parent / 'pricefm_r152_parent_recovery_20261024'
OLD_ENTRY = OLD_ROOT / 'application/scripts/pricefm/504_supervise_pricefm_stage_r152_baseline.py'
ADAPTER_ENTRY = ADAPTER_ROOT / 'application/scripts/pricefm/511_recover_pricefm_stage_r152_baseline_owner.py'
_MODULES = {}
NORMAL = '442_fit_pricefm_stage_r123_certified_normal.R'
AL = '470_fit_pricefm_stage_r137_certified_al_300.R'
TERMINAL = {'complete', 'blocked', 'control_expired', 'control_budget_exhausted'}


def module(name, path):
    if name not in _MODULES:
        spec = importlib.util.spec_from_file_location(name, path)
        value = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(value)
        _MODULES[name] = value
    return _MODULES[name]


def core():
    return module('r153_immutable_resource_helpers', OLD_ENTRY)


def adapter():
    return module('r153_immutable_process_reader', ADAPTER_ENTRY)


def read(path):
    return json.loads(Path(path).read_text())


def digest(path):
    return core().sha(path)


def canonical(path, within=None):
    """Reject aliases and substitution rather than silently resolving them."""
    path = Path(path)
    if not path.is_absolute() or not path.exists() or path.is_symlink() or path.resolve() != path:
        raise RuntimeError('noncanonical or missing identity path: ' + str(path))
    if within is not None and not path.is_relative_to(Path(within)):
        raise RuntimeError('identity path is outside its declared root: ' + str(path))
    return path


def service_groups(process):
    prefix = '/user.slice/user-' + str(os.getuid()) + '.slice/user@' + str(os.getuid()) + '.service/'
    return sorted(set(value for value in process.get('cgroups', []) if value.startswith(prefix)))


class System(adapter().RecoverySystem):
    """Truthful process snapshots with stable UID and parent metadata."""
    def process(self, pid):
        for attempt in range(3):
            value = super().process(pid)
            if value is None:
                return None
            before = self.stat_sample(pid)
            if self.terminal_or_gone(before):
                return None
            try:
                status = dict(line.split(':', 1) for line in (Path('/proc') / str(pid) / 'status').read_text().splitlines() if ':' in line)
                uids = tuple(map(int, status['Uid'].split()))
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                after = self.stat_sample(pid)
                if self.terminal_or_gone(after):
                    return None
                if not self.same_stat(before, after):
                    raise RuntimeError('PID lifetime changed during protected UID read')
                if attempt < 2:
                    time.sleep(.02)
                    continue
                raise
            after = self.stat_sample(pid)
            if self.terminal_or_gone(after):
                return None
            if (self.same_stat(before, after) and value['start_ticks'] == after['start_ticks']
                    and before['ppid'] == after['ppid'] and before['session_id'] == after['session_id']
                    and value['session_id'] == after['session_id']):
                return dict(value, uid=uids[0], uids=list(uids), ppid=after['ppid'],
                            process_group=after['process_group'],
                            age_seconds=time.clock_gettime(time.CLOCK_BOOTTIME) - after['start_ticks'] / os.sysconf('SC_CLK_TCK'))
            if not self.same_stat(before, after):
                raise RuntimeError('PID lifetime changed during parent/UID observation')
            if attempt < 2:
                time.sleep(.02)
        raise RuntimeError('process parent/session metadata did not stabilize')

    def cpu_seconds(self, pid, start_ticks):
        raw = (Path('/proc') / str(pid) / 'stat').read_text()
        fields = raw[raw.rfind(')') + 2:].split()
        if int(fields[19]) != start_ticks:
            raise RuntimeError('control CPU accounting lifetime changed')
        return (int(fields[11]) + int(fields[12])) / os.sysconf('SC_CLK_TCK')

    def unit(self, name):
        properties = core().PROPERTIES + ['CPUAccounting', 'MemoryAccounting', 'RuntimeMaxUSec']
        result = subprocess.run(['systemctl', '--user', 'show', name,
                                 '--property=' + ','.join(properties)], text=True,
                                capture_output=True, timeout=30)
        value = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
        if result.returncode and value.get('LoadState') != 'not-found':
            raise RuntimeError('cannot inspect explicit control unit: ' + result.stderr.strip())
        return value

    def members(self, cgroup):
        if not cgroup:
            return []
        if not hasattr(self, '_membership_reader'):
            release = module('r153_immutable_membership_reader',
                             ADAPTER_ROOT / 'application/scripts/pricefm/512_release_pricefm_stage_r152_baseline_owner.py')
            self._membership_reader = release.System()
        return self._membership_reader.members(cgroup)


class ContractPolicy:
    """The only broadened identity state is a pinned Normal package cwd.

    Every new numerical child is classified before it is retained. Previously
    observed lifetimes receive the same check; metadata is never rewritten.
    Source/contract reads use fresh bytes. Bulk source verification is explicit
    and scheduled separately from fresh process checks.
    """
    def __init__(self, config, system, private_namespace=None):
        self.config = copy.deepcopy(config)
        self.system = system
        self.private_namespace = Path(private_namespace) if private_namespace else None
        if self.private_namespace is not None:
            namespace = canonical(self.private_namespace)
            if (namespace.parent != Path('/tmp') or not namespace.name.startswith('pricefm-r153-owner-probe-')
                    or namespace.stat().st_uid != os.getuid() or namespace.stat().st_mode & 0o077):
                raise RuntimeError('private fixture policy needs its exclusive owned namespace')
            for key in ('data', 'dependency_worktree', 'source_worktree'):
                canonical(config[key], namespace)
        self.preparations = {}
        self._preparation_values = {}
        self._observation_preparations = None
        self.source_pins = dict(config.get('source_sha256', {}))
        for name, expected in config.get('evidence_sha256', {}).items():
            if name in self.source_pins and self.source_pins[name] != expected:
                raise RuntimeError('source/evidence authority pins conflict')
            self.source_pins[name] = expected
        self.events = []
        self.contract_pins = {}

    def preparation_path(self, region):
        return Path(self.config['data']) / 'launch_prep' / (self.config['source_tag'] + '__' + region) / 'preparation.json'

    def campaign(self, region):
        return Path(self.config['data']) / 'campaigns' / (self.config['source_tag'] + '__' + region)

    def preparation(self, region):
        if self._observation_preparations is not None and region in self._observation_preparations:
            return self._observation_preparations[region]
        path = canonical(self.preparation_path(region), Path(self.config['data']))
        raw = path.read_bytes()
        pin = hashlib.sha256(raw).hexdigest()
        previous = self.preparations.get(region)
        if previous:
            if previous['sha256'] != pin:
                raise RuntimeError('registered scientific preparation changed')
            value = self._preparation_values[region]
            if self._observation_preparations is not None:
                self._observation_preparations[region] = value
            return value
        value = json.loads(raw)
        expected = {'head': self.config['source_head'], 'branch': self.config['source_branch']}
        if value.get('source') != expected or value.get('dependency') != self.config['dependency_worktree']:
            raise RuntimeError('scientific preparation source/dependency differs')
        protocol = value.get('protocol', {})
        if protocol.get('normal_max_iter') != 2000 or protocol.get('al_max_iter') != 300:
            raise RuntimeError('preparation changed the original Normal2000/AL300 caps')
        if self.private_namespace is None:
            protocol_path = canonical(Path(self.config['source_worktree']) / 'application/config' / (self.config['source_tag'] + '.json'))
            if self.source_pins.get(str(protocol_path)) != digest(protocol_path):
                raise RuntimeError('global scientific protocol is not authority-pinned')
            declared = read(protocol_path)
            declared.update(regions=[region], tag=self.config['source_tag'] + '__' + region,
                            maximum_workers=declared['maximum_workers_per_region'])
            if protocol != declared:
                raise RuntimeError('regional preparation differs from the exact frozen global protocol')
        sources = value.get('source_sha256', {})
        if not sources or any(not isinstance(v, str) or len(v) != 64 for v in sources.values()):
            raise RuntimeError('scientific preparation lacks exact source pins')
        for name, expected_sha in sources.items():
            if name in self.source_pins and self.source_pins[name] != expected_sha:
                raise RuntimeError('scientific source pin conflicts with existing authority')
            self.source_pins[name] = expected_sha
        if not previous:
            for name, expected_sha in sources.items():
                if digest(canonical(name)) != expected_sha:
                    raise RuntimeError('scientific source bytes changed: ' + name)
        self.preparations[region] = dict(path=str(path), sha256=pin)
        self._preparation_values[region] = value
        if self._observation_preparations is not None:
            self._observation_preparations[region] = value
        return value

    @contextlib.contextmanager
    def observation(self):
        """One immutable-preparation SHA per observation, never a PID cache."""
        prior = self._observation_preparations
        if prior is None:
            self._observation_preparations = {}
        try:
            yield
        finally:
            self._observation_preparations = prior

    def prerequisite_terminal(self, region, task_name, relative):
        folder = canonical(self.campaign(region) / 'tasks_done' / task_name, self.campaign(region))
        terminal = canonical(folder / relative, folder)
        seal = read(canonical(folder / 'completed_evidence.json', folder))
        task_path = canonical(self.campaign(region) / 'tasks' / (task_name + '.json'), self.campaign(region))
        expected = digest(terminal)
        if (seal.get('metadata', {}).get('source_head') != self.config['source_head']
                or seal.get('metadata', {}).get('certified') is not True
                or seal.get('metadata', {}).get('task_sha256') != digest(task_path)
                or seal.get('artifacts', {}).get(relative) != expected):
            raise RuntimeError('scientific prerequisite terminal/seal/task differs')
        return expected

    @staticmethod
    def producer_seed(*parts):
        # Exact stdlib-only rule in frozen pricefm_recursive_normal.py:32–37,
        # imported by r120 and r123. No numerical runtime is imported here.
        payload = json.dumps(parts, sort_keys=True, separators=(',', ':'), default=str)
        return int.from_bytes(hashlib.sha256(payload.encode()).digest()[:8], 'little') % (2**63 - 1)

    def expected_contract(self, prep, task, job):
        """Reconstruct the immutable producer dictionary without executing a fit."""
        folder = self.campaign(job['region'])
        name = task['name']
        output = folder / 'tasks_done' / name / 'fit'
        dep = Path(self.config['dependency_worktree'])
        if task['kind'] in {'rhs', 'normal_full'}:
            stats_name = task['stats_name'] if task['kind'] == 'rhs' else task['design_name']
            stats = folder / 'tasks_done' / stats_name / 'stats'
            stats_sha = self.prerequisite_terminal(job['region'], stats_name, 'stats/terminal.json')
            helper = dep / 'application/R/pricefm_recursive_normal_fit.R'
            script = dep / 'application/scripts/pricefm' / NORMAL
            package = Path(prep['control']['normal_runtime'])
            paths = [helper, script, package / 'R/priors_beta.R', package / 'R/qdesn_rhs_ns_prior.R']
            hashes = {}
            for path in paths:
                canonical(path)
                expected = self.source_pins.get(str(path))
                if expected is None or digest(path) != expected:
                    raise RuntimeError('Normal producer source is outside frozen pins')
                hashes[str(path)] = expected
            return dict(prep['template'], tag=self.config['source_tag'] + '__' + job['region'],
                        fit_id=name, candidate_id=task['candidate_id'], split=task.get('split', task.get('fold')),
                        output_dir=str(output), stats_dir=str(stats), tau0=task['tau0'], helper_path=str(helper),
                        initial_fit_path=None, initial_fit_sha256=None,
                        max_iter=prep['protocol']['normal_max_iter'], min_iter=prep['protocol']['normal_min_iter'],
                        source_sha256=hashes, stats_terminal_sha256=stats_sha,
                        posterior_target_sha256=stats_sha + ':tau0=' + format(task['tau0'], '.17g'))
        if task['kind'] not in {'al', 'internal_al'}:
            raise RuntimeError('contract task is not an approved numerical producer')
        design = folder / 'tasks_done' / task['design_name'] / 'design'
        parent = folder / 'tasks_done' / task['parent_name'] / 'fit'
        design_sha = self.prerequisite_terminal(job['region'], task['design_name'], 'design/terminal.json')
        parent_sha = self.prerequisite_terminal(job['region'], task['parent_name'], 'fit/terminal.json')
        adapter_path = dep / 'application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R'
        fixed = Path(self.config['source_worktree']) / 'application/R/pricefm_r129_al_fixedpoint_certificate.R'
        manifest = Path(prep['control']['cran_manifest'])
        for path in (adapter_path, fixed, manifest):
            canonical(path)
            if self.source_pins.get(str(path)) != digest(path):
                raise RuntimeError('AL producer helper/manifest differs from frozen pins')
        p = prep['protocol']; index = task.get('fold', task.get('split'))
        return dict(stage='R137', model_stage='R137', tag=self.config['source_tag'] + '__' + job['region'],
                    family='al', fold=index, tau=task['tau'], tau0=task['tau0'],
                    output_dir=str(output), design_dir=str(design), parent_dir=str(parent), parent_type=task['parent_type'],
                    parent_terminal_sha256=parent_sha, cran_library=prep['control']['cran_library'],
                    cran_manifest=str(manifest), cran_manifest_sha256=digest(manifest),
                    cran_adapter=str(adapter_path), cran_adapter_sha256=digest(adapter_path),
                    fixedpoint_helper=str(fixed), fixedpoint_helper_sha256=digest(fixed),
                    certificate_limits=p['certificate_limits'], max_rhs_iter=p['max_rhs_iter'],
                    design_terminal_sha256=design_sha, max_iter=p['al_max_iter'], tol=p['al_tol'],
                    n_samp=p['al_n_samp'], n_samp_xi=p['al_n_samp'],
                    seed=self.producer_seed(p['forecast_seed'], task['region'], index, task['tau'], task['candidate_id']) % (2**31 - 1),
                    test_opened=False, prior_center_from_initializer=False,
                    posterior_target_sha256=design_sha + ':tau=' + str(task['tau']) + ':tau0=' + format(task['tau0'], '.17g'))

    def verify_sources(self):
        for name, expected in self.source_pins.items():
            if digest(canonical(name)) != expected:
                raise RuntimeError('registered scientific source changed: ' + name)
        for record in self.preparations.values():
            if digest(record['path']) != record['sha256']:
                raise RuntimeError('registered preparation changed')

    def task(self, region, name):
        if not re.fullmatch(r'[A-Za-z0-9_.-]{1,240}', name):
            raise RuntimeError('unsafe scientific task name')
        folder = canonical(self.campaign(region), Path(self.config['data']))
        path = canonical(folder / 'tasks' / (name + '.json'), folder)
        task = read(path)
        if task.get('name') != name or task.get('region') != region:
            raise RuntimeError('scientific task name/region differs')
        return task

    @staticmethod
    def flag(argv, flag):
        if argv.count(flag) != 1:
            raise RuntimeError('missing or duplicate identity flag: ' + flag)
        index = argv.index(flag)
        if index + 1 >= len(argv):
            raise RuntimeError('identity flag lacks a value: ' + flag)
        return argv[index + 1]

    def worker(self, process, job):
        argv = process.get('argv', [])
        name = self.flag(argv, '--name')
        cpu_text = self.flag(argv, '--cpu')
        if not cpu_text.isdecimal():
            raise RuntimeError('worker CPU is not an exact nonnegative integer')
        cpu = int(cpu_text)
        expected = [self.config['python_runtime'], '-B', self.config['source_controller'],
                    'worker', '--region', job['region'], '--name', name, '--cpu', str(cpu)]
        bootstrap = (process.get('cpus') == job['cpus']
                     and 0 <= process.get('age_seconds', float('inf')) <= 120)
        if argv != expected or cpu not in job['cpus'] or (process.get('cpus') != [cpu] and not bootstrap):
            raise RuntimeError('scientific worker argv/declared CPU differs')
        if process.get('cwd') != job['process']['cwd']:
            raise RuntimeError('Python scientific worker changed working directory')
        self.preparation(job['region'])
        self.task(job['region'], name)
        return dict(kind='worker', task=name, cpu=cpu, bootstrap=process.get('cpus') != [cpu])

    def r_role(self, process, job):
        """Validate the exact task/contract/source/cwd; never changes argv/cwd."""
        argv = process.get('argv', [])
        scripts = [a.split('=', 1)[1] if a.startswith('--file=') else a
                   for a in argv if a.endswith('/' + NORMAL) or a.endswith('/' + AL)]
        if len(scripts) != 1 or sum(a in {'--contract', '--config'} for a in argv) != 1:
            raise RuntimeError('R process lacks one exact approved script/contract role')
        script = canonical(scripts[0])
        normal = script.name == NORMAL
        expected_script = (Path(self.config['dependency_worktree']) / 'application/scripts/pricefm' / NORMAL
                           if normal else Path(self.config['source_worktree']) / 'application/scripts/pricefm' / AL)
        if script != expected_script:
            raise RuntimeError('R script path differs from frozen scientific role')
        contract_path = canonical(self.flag(argv, '--contract' if normal else '--config'), self.campaign(job['region']) / 'contracts')
        name = contract_path.stem
        task = self.task(job['region'], name)
        if task.get('kind') not in ({'rhs', 'normal_full'} if normal else {'al', 'internal_al'}):
            raise RuntimeError('R role does not match its scientific task kind')
        prep = self.preparation(job['region'])
        source_sha = prep['source_sha256'].get(str(script))
        if source_sha is None or digest(script) != source_sha:
            raise RuntimeError('R script is not pinned by its preparation')
        rscript = Path(prep['control']['rscript'])
        native = [rscript.parent.parent / name / 'R/bin/exec/R' for name in ('lib64', 'lib')]
        allowed_native = {str(path) for path in native if path.is_file()}
        native_form = ([argv[0], '--no-echo', '--no-restore', '--file=' + str(script),
                        '--args', '--contract' if normal else '--config', str(contract_path)]
                       if argv else [])
        script_form = [str(rscript), str(script), '--contract' if normal else '--config', str(contract_path)]
        if not ((argv == script_form) or (argv and argv[0] in allowed_native and argv == native_form)):
            raise RuntimeError('R executable is outside the pinned runtime')
        contract = read(contract_path)
        contract_sha = digest(contract_path)
        old_pin = self.contract_pins.get(str(contract_path))
        if old_pin and old_pin != contract_sha:
            raise RuntimeError('registered scientific contract changed')
        if self.private_namespace is None and contract != self.expected_contract(prep, task, job):
            raise RuntimeError('scientific contract differs from the exact frozen producer dictionary')
        output = self.campaign(job['region']) / 'tasks_done' / name / 'fit'
        if contract.get('output_dir') != str(output) or contract.get('tag') != self.config['source_tag'] + '__' + job['region']:
            raise RuntimeError('scientific contract output/tag differs from exact task')
        if (not isinstance(task.get('tau0'), (int, float)) or isinstance(task.get('tau0'), bool)
                or not math.isfinite(task['tau0']) or task['tau0'] <= 0
                or contract.get('tau0') != task['tau0']):
            raise RuntimeError('scientific contract shrinkage parameter differs from its task')
        if not normal and (contract.get('tau') != task.get('tau')
                           or contract.get('fold') != task.get('fold', task.get('split'))):
            raise RuntimeError('AL contract quantile/fold differs from its exact task')
        allowed_cwds = {job['process']['cwd']}
        if normal:
            package = canonical(contract.get('package_path', ''))
            if (str(package) != prep['template']['package_path']
                    or str(package) != prep['control']['normal_runtime']
                    or contract.get('max_iter') != 2000):
                raise RuntimeError('Normal contract package/cap differs from preparation')
            pins = contract.get('source_sha256', {})
            if str(script) not in pins or not any(str(Path(p)).startswith(str(package) + '/') for p in pins):
                raise RuntimeError('Normal contract lacks exact package/script source pins')
            for path, expected in pins.items():
                if prep['source_sha256'].get(path) != expected or digest(canonical(path)) != expected:
                    raise RuntimeError('Normal contract source hash differs')
            allowed_cwds.add(str(package))
            package_path = str(package)
        else:
            if (contract.get('max_iter') != 300 or prep['protocol']['al_max_iter'] != 300
                    or contract.get('family') != 'al' or contract.get('stage') != 'R137'
                    or contract.get('test_opened') is not False
                    or contract.get('cran_library') != prep['control']['cran_library']
                    or contract.get('cran_manifest') != prep['control']['cran_manifest']):
                raise RuntimeError('AL contract/cap/library differs from frozen preparation')
            for key in ('cran_adapter', 'fixedpoint_helper', 'cran_manifest'):
                path = canonical(contract[key])
                expected = contract[key + '_sha256']
                if self.source_pins.get(str(path)) != expected or digest(path) != expected:
                    raise RuntimeError('AL helper/manifest source hash differs')
            package_path = None
        if process.get('cwd') not in allowed_cwds:
            raise RuntimeError('R working directory is outside its exact contract policy')
        self.contract_pins[str(contract_path)] = contract_sha
        return dict(kind='normal_R' if normal else 'AL_R', task=name,
                    script=str(script), script_sha256=source_sha,
                    contract=str(contract_path), contract_sha256=contract_sha,
                    package_path=package_path, actual_cwd=process['cwd'],
                    allowed_cwds=sorted(allowed_cwds))

    def common(self, process, job):
        root = job.get('process')
        if not root:
            raise RuntimeError('cannot classify an unrecorded scientific session root')
        if (process.get('uid') != os.getuid() or process.get('uids') != [os.getuid()] * 4
                or process.get('session_id') != job['session_id']
                or process['start_ticks'] < root['start_ticks']
                or not set(process.get('cpus', [])).issubset(job['cpus'])
                or not service_groups(root) or service_groups(process) != service_groups(root)):
            raise RuntimeError('owned scientific child UID/session/lifetime/cgroup/CPU differs')

    def classify(self, process, job, peers, previously_recorded=False):
        self.common(process, job)
        root = job['process']
        if process['pid'] == root['pid']:
            if not core().same_process(process, root):
                raise RuntimeError('scientific controller lifetime/argv/cwd changed')
            return dict(kind='controller')
        argv = process.get('argv', [])
        if self.config['source_controller'] in argv and 'worker' in argv:
            role = self.worker(process, job)
            parent = peers.get(process.get('ppid'))
            if parent is None or not core().same_process(parent, root):
                if not previously_recorded or self.system.process(root['pid']) is not None:
                    raise RuntimeError('scientific worker lacks its recorded controller parent')
            return role
        if any(a.endswith('/' + NORMAL) or a.endswith('/' + AL) for a in argv):
            role = self.r_role(process, job)
            parent = peers.get(process.get('ppid'))
            if parent is None:
                raise RuntimeError('scientific R child lacks a freshly verified worker parent')
            parent_role = self.worker(parent, job)
            if parent_role['task'] != role['task']:
                raise RuntimeError('R child contract differs from its worker task')
            if parent_role['bootstrap']:
                raise RuntimeError('R child was launched before its worker CPU pin')
            if parent.get('ppid') != root['pid'] or not core().same_process(peers.get(root['pid']), root):
                if not previously_recorded or self.system.process(root['pid']) is not None:
                    raise RuntimeError('R child worker lineage differs from recorded controller')
            if process.get('cpus') != [parent_role['cpu']]:
                raise RuntimeError('R child escaped its exact worker CPU')
            return role
        # Frozen R141 validates sources using these three read-only git commands.
        # They are explicit administrative children, never a generic session waiver.
        if argv and Path(argv[0]).name == 'git' and argv[1:] in [
                ['rev-parse', 'HEAD'], ['branch', '--show-current'], ['status', '--porcelain']]:
            parent = peers.get(process.get('ppid'))
            if parent is None or (parent['pid'] != root['pid'] and self.config['source_controller'] not in parent.get('argv', [])):
                raise RuntimeError('source-check git child lacks scientific Python ancestry')
            if process.get('cwd') not in {self.config['source_worktree'], self.config['dependency_worktree']}:
                raise RuntimeError('source-check git cwd is outside pinned repositories')
            return dict(kind='source_check_git')
        if argv in [['lscpu', '-p=CPU,CORE,SOCKET'], ['/usr/bin/lscpu', '-p=CPU,CORE,SOCKET']]:
            if process.get('ppid') != root['pid'] or process.get('cwd') != root['cwd']:
                raise RuntimeError('CPU-topology helper has an unapproved parent/cwd')
            return dict(kind='source_check_lscpu')
        raise RuntimeError('unclassified live child in scientific session: ' + str(process['pid']))

    def same_owned_child(self, current, prior, job, peers=None):
        if not current or any(current.get(k) != prior.get(k) for k in ('pid', 'start_ticks', 'boot_id')):
            return False
        peers = peers or {p['pid']: p for p in self.system.processes()}
        role = self.classify(current, job, peers, previously_recorded=True)
        if role['kind'] in {'normal_R', 'AL_R'}:
            old_role = self.r_role(prior, job)
            if any(role[k] != old_role[k] for k in ('kind', 'task', 'script', 'script_sha256', 'contract', 'contract_sha256')):
                return False
            if current['cwd'] != prior['cwd'] or current['cmdline_sha256'] != prior['cmdline_sha256']:
                self.events.append(dict(kind='APPROVED_R_IDENTITY_TRANSITION', pid=current['pid'],
                                        start_ticks=current['start_ticks'], old_cwd=prior['cwd'],
                                        actual_cwd=current['cwd'], old_argv=prior['argv'], actual_argv=current['argv'],
                                        role=role, epoch=time.time()))
            return True
        if role['kind'] == 'worker' and role['bootstrap'] and prior.get('cpus') == [role['cpu']]:
            return False
        return core().same_process(current, prior)


def session_members(job, system, policy, census=None):
    """Fresh direct known-lifetime reads plus classified session census."""
    with policy.observation():
        return _session_members(job, system, policy, census)


def _session_members(job, system, policy, census=None):
    root = job.get('process')
    current_root = system.process(root['pid']) if root else None
    if current_root and not core().same_process(current_root, root):
        raise RuntimeError('recorded scientific root PID reused or identity changed')
    census = system.processes() if census is None else census
    peers = {p['pid']: p for p in census}
    replacements = {}
    absent = set()
    if root:
        if current_root is None:
            absent.add(root['pid'])
        else:
            peers[current_root['pid']] = current_root
            replacements[current_root['pid']] = current_root
    known = {}
    for prior in job.get('observed_children', []):
        current = system.process(prior['pid'])
        if current is None:
            absent.add(prior['pid'])
            continue
        peers[current['pid']] = current
        replacements[current['pid']] = current
        if any(current.get(k) != prior.get(k) for k in ('pid', 'start_ticks', 'boot_id')):
            continue
        if not policy.same_owned_child(current, prior, job, peers):
            raise RuntimeError('recorded scientific child identity changed outside contract policy')
        known[current['pid']] = current
    members = {p['pid']: p for p in census if p.get('session_id') == job['session_id']}
    for pid in absent:
        members.pop(pid, None)
        peers.pop(pid, None)
    for pid, row in replacements.items():
        if row.get('session_id') == job['session_id']:
            members[pid] = row
        else:
            members.pop(pid, None)
    members.update(known)
    if members and not root:
        raise RuntimeError('unrecorded scientific root cannot be adopted')
    observed = {p['pid']: p for p in job.get('observed_children', [])}
    for process in members.values():
        if current_root is None and process['pid'] not in observed:
            raise RuntimeError('unobserved orphan child cannot be adopted')
        if process['pid'] not in known:
            policy.classify(process, job, peers, previously_recorded=process['pid'] in observed)
    if root and current_root is not None:
        job['observed_children'] = [p for p in members.values() if p['pid'] != root['pid']]
    return list(members.values())


def make_policy(authority, config, system):
    validate_authority_shape(authority)
    return ContractPolicy(config, system)


def inspect_sessions(authority, system=None):
    """Read-only preflight; the input authority may be an in-memory draft."""
    validate_authority_shape(authority)
    system = system or System()
    config = core().read_config(authority['legacy_config_path'])
    if digest(authority['legacy_config_path']) != authority['legacy_config_sha256']:
        raise RuntimeError('original numerical/resource configuration bytes changed')
    state = read(authority['legacy_state_archive_path'])
    if digest(authority['legacy_state_archive_path']) != authority['legacy_state_archive_sha256']:
        raise RuntimeError('archived predecessor state changed')
    policy = make_policy(authority, config, system)
    result = {}
    for lane, job in state['active'].items():
        snapshot = copy.deepcopy(job)
        rows = session_members(snapshot, system, policy)
        result[lane] = dict(region=job['region'], cpus=job['cpus'], session_id=job['session_id'],
                            original_root=job.get('process'), live_members=rows,
                            refreshed_observed_children=snapshot.get('observed_children', []))
    policy.verify_sources()
    return dict(sessions=result, numerical_worker_signals=0, runtime_writes=0,
                source_pins=policy.source_pins, preparation_pins=policy.preparations,
                approved_identity_events=policy.events)


def private_probe_policy(namespace, sourceproof=None, system=None):
    """A separate private fixture policy cannot authorize production runtime."""
    namespace = canonical(namespace)
    if (namespace.parent != Path('/tmp') or not namespace.name.startswith('pricefm-r153-owner-probe-')
            or namespace.stat().st_uid != os.getuid() or namespace.stat().st_mode & 0o077):
        raise RuntimeError('private identity probe needs its exclusive owned 0700 namespace')
    spec = read(namespace / 'policy.json')
    system = system or System()
    proof = spec.get('execution_source')
    if (spec.get('schema_version') != 1 or spec.get('namespace') != str(namespace)
            or sourceproof is not None and proof != sourceproof):
        raise RuntimeError('private policy source/namespace differs')
    if not core().same_process(system.process(spec['owner']['pid']), spec['owner']):
        raise RuntimeError('private policy owner disappeared or changed')
    if not proof or proof.get('root') != str(ROOT):
        raise RuntimeError('private policy is not bound to the execution checkout')
    for relative, expected in proof.get('runtime_sha256', {}).items():
        path = canonical(ROOT / relative, ROOT)
        if digest(path) != expected:
            raise RuntimeError('private probe execution source changed')
    if not proof.get('runtime_sha256'):
        raise RuntimeError('private source proof lacks file hashes')
    config = spec['config']
    for key in ('data', 'source_worktree', 'dependency_worktree'):
        canonical(config[key], namespace)
    return ContractPolicy(config, system, private_namespace=namespace)


def validate_authority_shape(authority):
    activation = authority.get('activation', {})
    grant = authority.get('grant', {})
    if (authority.get('schema_version') != 1
            or not re.fullmatch(r'[a-f0-9]{32}', authority.get('authority_id', ''))
            or activation != dict(legacy_generations_spent=3, explicit_additional_activation=1,
                                   activation_limit=1, cumulative_owner_count=4)
            or grant.get('wall_seconds') != 604800 or grant.get('control_CPU_seconds') != 28800
            or grant.get('expires_epoch', 0) - grant.get('starts_epoch', 0) != 604800
            or grant.get('prior_control_CPU_seconds', -1) < 0
            or authority.get('poll_seconds') != 20 or authority.get('source_verify_seconds') != 60
            or authority.get('guardian_lease_seconds') != 180):
        raise RuntimeError('R153 authority exceeds the explicit additional single-activation contract')
    if Path(authority['runtime']).resolve() == Path(authority['legacy_baseline_runtime']).resolve():
        raise RuntimeError('explicit successor must not reuse or overwrite the exhausted old runtime')
    if not authority.get('frozen_cached_sha256') or not authority.get('frozen_legacy_sha256'):
        raise RuntimeError('explicit successor lacks immutable predecessor/cached manifests')
    return authority


def check_pins(pins):
    for name, expected in pins.items():
        if digest(name) != expected:
            raise RuntimeError('immutable predecessor/source changed: ' + name)


def frozen_context(authority, authority_path=None):
    """Fresh closed-scope byte and exact-inventory checks; no mutation."""
    build_guard = module('r153_normal_build_guard', ENTRY.with_name('514_release_pricefm_stage_r153_control_repair.py'))
    build_guard.verify_normal_build_context(authority['normal_build_context'], metadata_only=True)
    check_pins(authority['frozen_legacy_sha256'])
    check_pins(authority['frozen_cached_sha256'])
    legacy = Path(authority['legacy_shared_runtime'])
    pointer = legacy / 'baseline/explicit_successor.json'
    expected = set(authority['frozen_legacy_sha256'])
    actual = {str(p) for p in legacy.rglob('*.json')}
    if pointer.exists():
        actual.discard(str(pointer))
        value = read(pointer)
        if (value.get('runtime') != authority['runtime']
                or value.get('source') != authority['execution_source']
                or value.get('cumulative_owner_count') != 4
                or value.get('cached_restart_authorized') is not False
                or authority_path is not None and value.get('authority_sha256') != digest(authority_path)):
            raise RuntimeError('explicit successor registry differs from its authority')
    if actual != expected:
        raise RuntimeError('legacy runtime JSON inventory changed beyond explicit successor registry')
    cached = {str(p) for p in (legacy / 'development').rglob('*.json')} | {str(legacy / 'development_closed.json')}
    if cached != set(authority['frozen_cached_sha256']):
        raise RuntimeError('closed cached JSON inventory changed')
    master = read(authority['legacy_master']['path'])
    if (digest(authority['legacy_master']['path']) != authority['legacy_master']['sha256']
            or master['scope_id'] != authority['legacy_master']['scope_id']
            or master['start_epoch'] != authority['legacy_master']['start_epoch']
            or master['expires_epoch'] != authority['legacy_master']['expires_epoch']):
        raise RuntimeError('original expired master changed')
    return master


def runtime_seconds(text):
    if isinstance(text, (int, float)):
        return float(text)
    text = str(text).strip()
    if text.isdecimal():
        # systemd's machine-readable raw microsecond value.
        return int(text) / 1e6
    units = {'us': 1e-6, 'ms': 1e-3, 's': 1, 'min': 60, 'h': 3600, 'd': 86400, 'w': 604800}
    matches = re.findall(r'([0-9]+(?:\.[0-9]+)?)\s*(us|ms|min|s|h|d|w)', text)
    if not matches or re.sub(r'([0-9]+(?:\.[0-9]+)?)\s*(us|ms|min|s|h|d|w)', '', text).strip():
        raise RuntimeError('unbounded or unreadable control unit runtime')
    return sum(float(number) * units[unit] for number, unit in matches)


def control_capsule(authority, attestation, mode, system):
    label = 'owner' if mode == 'run' else 'guardian'
    key = 'control_intent' if mode == 'run' else 'guardian_intent'
    expected = authority[key]
    capsule = attestation[label]
    current = system.process(capsule['process']['pid'])
    props = system.unit(expected['unit'])
    if (capsule.get('intent') != expected or not core().same_process(current, capsule['process'])
            or current.get('argv') != expected['argv'] or current.get('cwd') != str(ROOT)
            or current.get('uid') != os.getuid() or current.get('uids') != [os.getuid()] * 4
            or current.get('cpus') != list(range(30))
            or int(props.get('MainPID', 0)) != current['pid'] or props.get('ActiveState') != 'active'
            or props.get('InvocationID') != capsule['unit_properties'].get('InvocationID')
            or props.get('Restart') != 'no' or props.get('KillMode') != 'process'
            or props.get('WorkingDirectory') != str(ROOT) or str(ENTRY) not in props.get('ExecStart', '')
            or runtime_seconds(props.get('RuntimeMaxUSec', '')) != 604800):
        raise RuntimeError('actual explicit control lifetime/unit policy differs: ' + label)
    return current, props


def wait_attestation(authority, authority_path, mode, unit, system):
    expected_unit = authority['new_unit'] if mode == 'run' else authority['guardian_unit']
    if unit != expected_unit:
        raise RuntimeError('entry unit differs from declared explicit authority')
    deadline = time.monotonic() + 30
    path = Path(authority['launch_attestation_path'])
    while not path.is_file():
        if time.monotonic() >= deadline:
            raise RuntimeError('bounded explicit launch attestation wait expired')
        system.sleep(.025)
    attestation = read(path)
    if (attestation.get('authority_sha256') != digest(authority_path)
            or attestation.get('source') != authority['execution_source']):
        raise RuntimeError('launch attestation source/authority differs')
    owner, _ = control_capsule(authority, attestation, 'run', system)
    guardian, _ = control_capsule(authority, attestation, 'guard', system)
    current = owner if mode == 'run' else guardian
    if current['pid'] != os.getpid():
        raise RuntimeError('entry is not its own attested control process')
    return attestation, current


def verify_execution_source(authority):
    source = authority['execution_source']
    if source.get('root') != str(ROOT):
        raise RuntimeError('execution source root differs')
    for relative, expected in source['runtime_sha256'].items():
        path = canonical(ROOT / relative, ROOT)
        if digest(path) != expected:
            raise RuntimeError('explicit control execution source changed')
    # The release implements the exact committed branch/clean-worktree guard.
    # Its bounded administrative charge is reserved independently of model CPU.
    release = module('r153_explicit_release_source_guard', ENTRY.with_name('514_release_pricefm_stage_r153_control_repair.py'))
    release.verify_source(source)
    release.verify_normal_build_context(authority['normal_build_context'])


def choose_cpus(config, lane, runtime, legacy_shared, master, system):
    if lane == 'A':
        return config['partition']['baseline_A']
    if not core().cached_drained(legacy_shared, master, system):
        raise RuntimeError('closed cached scope unexpectedly contains a live lifetime')
    # The old allowance is expired and closed. Record the verified return in
    # the new runtime, never in or by editing the exhausted R152 chain.
    core().record_loan_return(runtime, legacy_shared, master)
    return list(range(15, 30))


def failed_certificates(config, region, diagnostics=None):
    """Typed original-cap exclusions, without treating RHS screens as AL stops.

    The historical 504 collector assumes every false packet is an AL failure.
    R141 intentionally retains false RHS screening packets. This explicitly
    versioned resource classifier preserves those packets and quarantines only
    finite required-fit blockers; it never recomputes a certificate.
    """
    folder = core().campaign(config, region)
    blockers = []
    screened = []
    policy = ContractPolicy(config, None)
    prep = None
    for path in sorted((folder / 'tasks_done').glob('*')):
        seal_path = path / 'completed_evidence.json'
        if not seal_path.is_file() or read(seal_path).get('metadata', {}).get('certified') is not False:
            continue
        seal = core().verify_packet(path)
        task_path = folder / 'tasks' / (path.name + '.json')
        task = read(task_path)
        terminal_path = path / 'fit/terminal.json'
        if (seal.get('metadata', {}).get('source_head') != config['source_head']
                or seal.get('metadata', {}).get('task_sha256') != digest(task_path)
                or not terminal_path.is_file() or task.get('region') != region
                or task.get('name') != path.name):
            raise RuntimeError('unclassified failed scientific packet/source/task')
        terminal = read(terminal_path)
        contract_path = folder / 'contracts' / (path.name + '.json')
        if (terminal.get('contract_path') != str(contract_path)
                or terminal.get('contract_sha256') != digest(contract_path)):
            raise RuntimeError('failed scientific packet contract differs')
        if prep is None:
            prep = policy.preparation(region)
        if read(contract_path) != policy.expected_contract(prep, task, {'region':region}):
            raise RuntimeError('failed fit is outside its exact frozen producer contract')
        record = dict(task=path.name, kind=task['kind'], completed_evidence_sha256=digest(seal_path),
                      terminal_sha256=digest(terminal_path), task_sha256=digest(task_path),
                      contract_sha256=digest(contract_path))
        if task['kind'] in {'rhs', 'normal_full'}:
            if (terminal.get('status') != 'R123_SUCCESSOR_UNCERTIFIED'
                    or terminal.get('iterations') != 2000 or terminal.get('termination_reason') != 'iteration_cap'
                    or terminal.get('full_variational_certified') is not False
                    or terminal.get('test_opened') is not False
                    or terminal.get('official_validation_opened') is not False
                    or terminal.get('initialization_only') is not True):
                raise RuntimeError('Normal exclusion is not finite original-cap evidence')
            if task['kind'] == 'rhs':
                screened.append(record)
            else:
                blockers.append(record)
        elif task['kind'] in {'al', 'internal_al'}:
            if (terminal.get('finite_core') is not True or terminal.get('iterations') != 300
                    or terminal.get('computationally_certified') is not False
                    or terminal.get('termination') != 'iteration_cap_uncertified'
                    or terminal.get('test_opened') is not False):
                raise RuntimeError('AL blocker is not finite original-cap evidence')
            blockers.append(record)
        else:
            raise RuntimeError('unknown false scientific task kind cannot be waived')
    if diagnostics is not None:
        diagnostics['preserved_RHS_screening_exclusions'] = screened
    return blockers


def step_lanes(config, runtime, legacy_shared, state, master, system, policy):
    """Original nine-region scientific sequence, explicit identity dependency."""
    census = system.processes()
    for lane, queue in config['queues'].items():
        job = state['active'].get(lane)
        if job:
            if session_members(job, system, policy, census=census):
                continue
            region = job['region']
            if job['phase'] == 'prepare':
                prep = policy.preparation_path(region)
                if not prep.is_file() or read(prep).get('source', {}).get('head') != config['source_head']:
                    raise RuntimeError('preparation exited without exact immutable science preparation')
                state['active'][lane] = core().launch_region(config, runtime, lane, region, 'controller', job['cpus'], system)
            elif core().complete_region(config, region):
                state['completed'][lane].append(region)
                del state['active'][lane]
                core().immutable(Path(runtime) / 'regions' / (region + '.complete.json'), dict(
                    region=region, status='R153_BASELINE_NUMERICAL_SOURCE_PRESERVED',
                    source_head=config['source_head'], terminal_sha256=digest(core().campaign(config, region) / 'terminal.json'),
                    epoch=time.time()))
            else:
                diagnostics = {}
                failures = failed_certificates(config, region, diagnostics)
                if not failures:
                    raise RuntimeError('controller drained without a closeout or original-cap certificate exclusion')
                core().immutable(Path(runtime) / 'quarantine' / (region + '.json'), dict(
                    region=region, lane=lane, status='R153_ORIGINAL_CAP_CERTIFICATE_QUARANTINE',
                    failed=failures, source_head=config['source_head'], fit_retry_admitted=False,
                    certificate_limits_changed=False, **diagnostics, epoch=time.time()))
                state['quarantined'][lane].append(region)
                del state['active'][lane]
            continue
        pending = [region for region in queue if region not in state['completed'][lane]
                   and region not in state['quarantined'][lane]]
        if not pending:
            continue
        region = pending[0]
        if core().complete_region(config, region):
            state['completed'][lane].append(region)
            continue
        prep = policy.preparation_path(region)
        phase = 'controller' if prep.is_file() else 'prepare'
        cpus = choose_cpus(config, lane, runtime, legacy_shared, master, system)
        state['active'][lane] = core().launch_region(config, runtime, lane, region, phase, cpus, system)
    return state


def budget(authority, state, system, now=None):
    """Control-only debit: never cgroup CPU or numerical-child rusage."""
    now = time.time() if now is None else now
    guardian_path = Path(authority['runtime']) / 'guardian_heartbeat.json'
    guardian = read(guardian_path) if guardian_path.is_file() else None
    owner = state['owner']
    owner_cpu = system.cpu_seconds(owner['pid'], owner['start_ticks'])
    guardian_cpu = guardian.get('control_CPU_seconds', 0.) if guardian else 0.
    reservation = authority['grant'].get('administrative_source_check_CPU_reservation', .5)
    administrative = state.get('heavy_source_checks', 0) * reservation
    prior = authority['grant']['prior_control_CPU_seconds']
    # Reserve the final control-only publication/exit tail; no refund implied.
    final_tail = 5.
    charged = prior + owner_cpu + guardian_cpu + administrative + final_tail
    return dict(owner_actual_CPU_seconds=owner_cpu, guardian_actual_CPU_seconds=guardian_cpu,
                administrative_reserved_CPU_seconds=administrative,
                prior_private_probe_CPU_seconds=prior, final_tail_reserved_CPU_seconds=final_tail,
                cumulative_control_charged_CPU_seconds=charged,
                control_ceiling_CPU_seconds=authority['grant']['control_CPU_seconds'],
                control_expires_epoch=authority['grant']['expires_epoch'],
                within_CPU=charged < authority['grant']['control_CPU_seconds'],
                within_wall=now < authority['grant']['expires_epoch'],
                numerical_CPU_included=False, cgroup_CPU_used=False)


def _heartbeat(runtime, state, authority_path, authority, system):
    state['epoch'] = time.time()
    state['control_budget'] = budget(authority, state, system)
    core().atomic(Path(runtime) / 'state.json', state)
    core().atomic(Path(runtime) / 'resource_ownership_epoch.json', dict(
        schema_version=1, authority_path=str(authority_path), authority_sha256=digest(authority_path),
        legacy_scope_id=authority['legacy_master']['scope_id'],
        legacy_master_sha256=authority['legacy_master']['sha256'],
        activation=authority['activation'], owner=state['owner'], guardian_unit=authority['guardian_unit'],
        phase=state['phase'], heartbeat=state['epoch'], execution_source=authority['execution_source'],
        control_budget=state['control_budget']))


def _guardian_live(authority, attestation, system, now=None):
    now = time.time() if now is None else now
    current, _ = control_capsule(authority, attestation, 'guard', system)
    heartbeat = read(Path(authority['runtime']) / 'guardian_heartbeat.json')
    if (not core().same_process(current, heartbeat.get('process'))
            or heartbeat.get('authority_id') != authority['authority_id']
            or now - heartbeat.get('heartbeat', 0) > authority['guardian_lease_seconds']
            or heartbeat.get('status') != 'running'):
        raise RuntimeError('independent explicit guardian heartbeat differs or is stale')
    if (Path(authority['runtime']) / 'guardian_blocked.json').exists():
        raise RuntimeError('independent explicit guardian blocked dependent dispatch')
    return current


def _validate(path, validator=None):
    if validator is None:
        validator = module('r153_explicit_authority_validator', ENTRY.with_name('514_release_pricefm_stage_r153_control_repair.py')).validate_authority
    authority = validator(path)
    validate_authority_shape(authority)
    return authority


def run(authority_path, unit, system=None, validator=None):
    system = system or System()
    authority_path = Path(authority_path).resolve()
    authority = _validate(authority_path, validator)
    runtime = Path(authority['runtime'])
    config = core().read_config(authority['legacy_config_path'])
    attestation, current = wait_attestation(authority, authority_path, 'run', unit, system)
    master = frozen_context(authority, authority_path)
    claim = read(runtime / 'activation_claim.json')
    if claim.get('authority_sha256') != digest(authority_path) or claim.get('activation') != authority['activation']:
        raise RuntimeError('single explicit activation claim differs')
    # The create-once start receipt makes manual repetition fail even though
    # the service already declares Restart=no. Old epochs are not consumed.
    core().immutable(runtime / 'owner_start.json', dict(
        authority_sha256=digest(authority_path), activation=authority['activation'],
        owner=current, InvocationID=attestation['owner']['unit_properties']['InvocationID'], epoch=time.time()))
    state = copy.deepcopy(read(authority['legacy_state_archive_path']))
    state.pop('error', None)
    state.update(schema_version=1, phase='adopted_ready', authority_id=authority['authority_id'],
                 authority_path=str(authority_path), authority_sha256=digest(authority_path),
                 legacy_resource_source=state['source'], source=authority['execution_source'],
                 legacy_max_owner_generations=3, activation=authority['activation'],
                 new_unit=unit, owner=current, guardian_unit=authority['guardian_unit'],
                 heavy_source_checks=0, numerical_worker_signals=0)
    state.pop('max_owner_generations', None)
    policy = make_policy(authority, config, system)
    # Reuse exactly the legacy dispatch locks, plus a new owner-specific lock.
    # The lease is never a substitute for an exclusive kernel lock.
    with core().fences(runtime, config):
        try:
            for job in state['active'].values():
                session_members(job, system, policy)
            verify_execution_source(authority)
            policy.verify_sources()
            state['heavy_source_checks'] += 1
            _heartbeat(runtime, state, authority_path, authority, system)
            deadline = time.monotonic() + 30
            while not (runtime / 'guardian_heartbeat.json').is_file():
                if time.monotonic() >= deadline:
                    raise RuntimeError('bounded initial guardian readiness wait expired')
                system.sleep(.025)
            _guardian_live(authority, attestation, system)
            core().immutable(runtime / 'ready.json', dict(
                authority_sha256=digest(authority_path), owner=current, activation=authority['activation'],
                original_sessions_preserved=True, cached_scope_stays_closed=True,
                numerical_worker_signals=0, epoch=time.time()))
            # The release observes readiness and publishes this single explicit
            # registry. New dispatch cannot precede that reviewed publication.
            pointer = Path(authority['legacy_baseline_runtime']) / 'explicit_successor.json'
            deadline = time.monotonic() + 60
            while not pointer.is_file():
                if time.monotonic() >= deadline:
                    raise RuntimeError('bounded explicit successor publication wait expired')
                _guardian_live(authority, attestation, system)
                _heartbeat(runtime, state, authority_path, authority, system)
                system.sleep(.2)
            frozen_context(authority, authority_path)
            state['phase'] = 'running'
            last_heavy = time.monotonic()
            while True:
                frozen_context(authority, authority_path)
                _guardian_live(authority, attestation, system)
                charge = budget(authority, state, system)
                if not charge['within_wall'] or not charge['within_CPU']:
                    state['phase'] = 'control_expired' if not charge['within_wall'] else 'control_budget_exhausted'
                    _heartbeat(runtime, state, authority_path, authority, system)
                    core().immutable(runtime / 'control_terminal.json', dict(
                        status=state['phase'], activation_spent=True, control_budget=state['control_budget'],
                        numerical_worker_signals=0, epoch=time.time()))
                    return state
                now = time.monotonic()
                if now - last_heavy >= authority['source_verify_seconds']:
                    verify_execution_source(authority)
                    policy.verify_sources()
                    core().verify_pins(config['source_sha256'])
                    core().verify_pins(config['evidence_sha256'])
                    state['heavy_source_checks'] += 1
                    last_heavy = now
                health = core().host_health(config)
                if not health['healthy']:
                    raise RuntimeError('baseline host resource floor crossed')
                state = step_lanes(config, runtime, authority['legacy_shared_runtime'], state,
                                   master, system, policy)
                state['health'] = health
                done = all(len(state['completed'][lane]) + len(state['quarantined'][lane]) == len(queue)
                           for lane, queue in config['queues'].items())
                if done:
                    state['phase'] = 'complete'
                state['approved_identity_events'] = policy.events[-128:]
                _heartbeat(runtime, state, authority_path, authority, system)
                core().atomic(runtime / 'progress.json', state)
                if done:
                    core().immutable(runtime / 'terminal.json', dict(
                        status='R153_NINE_ORIGINAL_TAILS_DRAINED_NOT_GLOBAL_PROMOTION',
                        completed=state['completed'], quarantined=state['quarantined'],
                        activation=authority['activation'], numerical_source_head=config['source_head'],
                        control_budget=state['control_budget'], numerical_worker_signals=0, epoch=time.time()))
                    return state
                system.sleep(authority['poll_seconds'])
        except BaseException as error:
            state.update(phase='blocked', error=repr(error), approved_identity_events=policy.events[-128:])
            _heartbeat(runtime, state, authority_path, authority, system)
            core().immutable(runtime / 'blocked.json', dict(
                authority_sha256=digest(authority_path), error=repr(error),
                activation_spent=True, numerical_worker_signals=0, cached_restart_authorized=False,
                approved_identity_events=policy.events[-128:], epoch=time.time()))
            raise


def guard_once(authority_path, unit, system=None, now=None, authority=None, attestation=None):
    system = system or System()
    authority = authority or _validate(authority_path)
    now = time.time() if now is None else now
    if attestation is None:
        attestation = read(authority['launch_attestation_path'])
    current, _ = control_capsule(authority, attestation, 'guard', system)
    if current['pid'] != os.getpid() or unit != authority['guardian_unit']:
        raise RuntimeError('guardian is not its attested process')
    runtime = Path(authority['runtime'])
    core().atomic(runtime / 'guardian_heartbeat.json', dict(
        schema_version=1, authority_id=authority['authority_id'], process=current,
        heartbeat=now, control_CPU_seconds=system.cpu_seconds(current['pid'], current['start_ticks']),
        status='running', numerical_worker_signals=0))
    state_path = runtime / 'state.json'
    if not state_path.is_file():
        if now - attestation['epoch'] < 30:
            return 'wait'
        reason = 'owner_never_published_initial_state'
    else:
        state = read(state_path)
        if state.get('phase') in TERMINAL:
            return 'complete'
        try:
            owner, _ = control_capsule(authority, attestation, 'run', system)
            try:
                epoch = read(runtime / 'resource_ownership_epoch.json')
            except FileNotFoundError:
                # Only the initial state→first-epoch publication gap is a
                # bounded wait, and only with fresh positive owner proof.
                # No new dispatch occurs before the release publishes the
                # registry after observing both complete readiness records.
                if (now - attestation['epoch'] < 30 and state.get('phase') == 'adopted_ready'
                        and state.get('authority_sha256') == digest(authority_path)
                        and state.get('activation') == authority['activation']
                        and core().same_process(state.get('owner'), owner)):
                    return 'wait'
                raise
            if (not core().same_process(owner, epoch.get('owner'))
                    or epoch.get('authority_sha256') != digest(authority_path)
                    or now - epoch.get('heartbeat', 0) > authority['guardian_lease_seconds']):
                reason = 'owner_lease_or_lifetime_differs'
            elif now >= authority['grant']['expires_epoch']:
                reason = 'explicit_control_grant_expired'
            elif not epoch.get('control_budget', {}).get('within_CPU', False):
                reason = 'explicit_control_CPU_exhausted'
            else:
                return 'wait'
        except (RuntimeError, FileNotFoundError, ProcessLookupError) as error:
            reason = repr(error)
    core().immutable(runtime / 'guardian_blocked.json', dict(
        reason=reason, authority_sha256=digest(authority_path), numerical_worker_signals=0,
        owner_restart_attempts=0, epoch=now))
    return 'blocked'


def guard(authority_path, unit, system=None, validator=None):
    system = system or System()
    authority_path = Path(authority_path).resolve()
    authority = _validate(authority_path, validator)
    attestation, _ = wait_attestation(authority, authority_path, 'guard', unit, system)
    while guard_once(authority_path, unit, system, authority=authority, attestation=attestation) == 'wait':
        system.sleep(authority['poll_seconds'])


def inspect_owner(authority_path, system=None, now=None):
    """Fresh observer API; ready state is valid before pointer publication."""
    system = system or System()
    authority_path = Path(authority_path).resolve()
    authority = _validate(authority_path)
    runtime = Path(authority['runtime'])
    state = read(runtime / 'state.json')
    if state.get('phase') == 'complete' and (runtime / 'terminal.json').is_file():
        terminal = read(runtime / 'terminal.json')
        config = core().read_config(authority['legacy_config_path'])
        if (terminal.get('status') != 'R153_NINE_ORIGINAL_TAILS_DRAINED_NOT_GLOBAL_PROMOTION'
                or terminal.get('activation') != authority['activation']
                or terminal.get('numerical_source_head') != config['source_head']
                or terminal.get('completed') != state.get('completed')
                or terminal.get('quarantined') != state.get('quarantined') or state.get('active')):
            raise RuntimeError('explicit baseline terminal differs from completed state')
        for lane, queue in config['queues'].items():
            completed = state['completed'][lane]
            quarantined = state['quarantined'][lane]
            if len(set(completed + quarantined)) != len(queue) or set(completed + quarantined) != set(queue):
                raise RuntimeError('completed explicit owner lost or duplicated a regional disposition')
            for region in completed:
                if not core().complete_region(config, region):
                    raise RuntimeError('completed region no longer has its strict original closeout')
            for region in quarantined:
                receipt = read(runtime / 'quarantine' / (region + '.json'))
                if receipt.get('failed') != failed_certificates(config, region):
                    raise RuntimeError('quarantined region lost its exact original-cap blocker evidence')
        frozen_context(authority, authority_path)
        owner_props = system.unit(authority['new_unit'])
        return dict(healthy=True, phase='complete', tail_finished=True,
                    owner_live=owner_props.get('ActiveState') == 'active' and bool(int(owner_props.get('MainPID', 0))),
                    activation=authority['activation'], completed=state['completed'], quarantined=state['quarantined'],
                    sessions={}, execution_source=authority['execution_source'], cached_scope_closed=True,
                    terminal_sha256=digest(runtime / 'terminal.json'), numerical_worker_signals=0, runtime_writes=0)
    attestation = read(authority['launch_attestation_path'])
    if attestation.get('authority_sha256') != digest(authority_path) or attestation.get('source') != authority['execution_source']:
        raise RuntimeError('observer launch attestation differs')
    owner, props = control_capsule(authority, attestation, 'run', system)
    guardian = _guardian_live(authority, attestation, system, now)
    frozen_context(authority, authority_path)
    epoch = read(runtime / 'resource_ownership_epoch.json')
    now = time.time() if now is None else now
    if (state.get('phase') not in {'adopted_ready', 'running', 'complete'}
            or state.get('authority_sha256') != digest(authority_path)
            or not core().same_process(state.get('owner'), owner)
            or not core().same_process(epoch.get('owner'), owner)
            or epoch.get('activation') != authority['activation']
            or now - epoch.get('heartbeat', 0) > authority['guardian_lease_seconds']
            or now >= authority['grant']['expires_epoch']
            or not epoch.get('control_budget', {}).get('within_CPU', False)):
        raise RuntimeError('explicit owner state/epoch/lease/grant differs')
    config = core().read_config(authority['legacy_config_path'])
    policy = make_policy(authority, config, system)
    sessions = {}
    for lane, job in state['active'].items():
        sessions[lane] = dict(region=job['region'], cpus=job['cpus'],
                              live_members=session_members(copy.deepcopy(job), system, policy))
    return dict(healthy=True, phase=state['phase'], authority_id=authority['authority_id'],
                activation=authority['activation'], owner=owner, guardian=guardian,
                heartbeat=epoch['heartbeat'], heartbeat_age_seconds=now - epoch['heartbeat'],
                unit=props.get('Id'), sessions=sessions, execution_source=authority['execution_source'],
                legacy_scope_id=authority['legacy_master']['scope_id'],
                cached_scope_closed=True, numerical_worker_signals=0, runtime_writes=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest='action', required=True)
    for name in ('run', 'guard'):
        command = actions.add_parser(name)
        command.add_argument('--authority', required=True)
        command.add_argument('--unit', required=True)
    command = actions.add_parser('inspect')
    command.add_argument('--authority', required=True)
    args = parser.parse_args()
    if args.action == 'run':
        value = run(args.authority, args.unit)
    elif args.action == 'guard':
        value = guard(args.authority, args.unit)
    else:
        value = inspect_owner(args.authority)
    if value is not None:
        print(json.dumps(value, indent=2, sort_keys=True, allow_nan=False))


if __name__ == '__main__':
    main()
