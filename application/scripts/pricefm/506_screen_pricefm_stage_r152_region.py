#!/usr/bin/env python3
"""Explicit FI/DK2 cached-study adapter for the finite R152 shared pool.

The numerical kernel and regional prediction API remain immutable. This module
parameterizes the prior regional orchestration by an explicit Study instance;
it never patches a producer global or rewrites an existing preparation.
Only metadata imports occur until the owned worker's policy guard passes.
"""
from __future__ import annotations
import argparse
import ast
import datetime as dt
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import resource
import subprocess
import sys
import time
import uuid
import zipfile
ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
CONFIG = ROOT / 'application/config/pricefm_stage_r152_fi_20261024.json'

def read(path):
    return json.loads(Path(path).read_text())

def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            h.update(block)
    return h.hexdigest()

def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()

def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    temporary.write_text(json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + '\n')
    os.replace(temporary, path)

def immutable(path, value):
    if Path(path).exists():
        if read(path) != value:
            raise RuntimeError('immutable regional record differs: ' + str(path))
    else:
        write(path, value)

def verify_hashes(ledger):
    for path, expected in ledger.items():
        if digest(path) != expected:
            raise RuntimeError('pinned regional artifact changed: ' + path)

def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()

def bank_anchors(path):
    """Read only the pinned Unicode NPY anchor member, without NumPy."""
    with zipfile.ZipFile(path) as packet:
        with packet.open('anchors.npy') as stream:
            lead = stream.read(8)
            if lead[:6] != b'\x93NUMPY' or lead[6:8] not in (b'\x01\x00', b'\x02\x00'):
                raise ValueError('unsupported bank anchor NPY')
            width = 2 if lead[6] == 1 else 4
            size = int.from_bytes(stream.read(width), 'little')
            if size > 65536:
                raise ValueError('oversized bank anchor header')
            head = ast.literal_eval(stream.read(size).decode('latin1').strip())
            dtype = head['descr']
            if not dtype.startswith('<U') or head['fortran_order'] is not False or len(head['shape']) != 1:
                raise ValueError('one-dimensional little-endian Unicode anchors required')
            chars = int(dtype[2:])
            count = head['shape'][0]
            payload = stream.read()
            if len(payload) != count * chars * 4:
                raise ValueError('truncated/padded anchor member')
            values = [payload[i * chars * 4:(i + 1) * chars * 4].decode('utf-32-le').rstrip('\x00') for i in range(count)]
    parsed = [dt.datetime.fromisoformat(s) for s in values]
    if not parsed or any((v.utcoffset() != dt.timedelta(0) for v in parsed)):
        raise ValueError('exact aware UTC training bank anchors required')
    if any((b - a != dt.timedelta(days=1) for a, b in zip(parsed, parsed[1:]))):
        raise ValueError('common bank anchors must be consecutive UTC days')
    return values

def split_boundaries(path, n):
    """Extract the exact pinned inherited split declaration, then replay in worker."""
    tree = ast.parse(Path(path).read_text())
    function = next((v for v in tree.body if isinstance(v, ast.FunctionDef) and v.name == 'internal_splits'))
    bounds = next((ast.literal_eval(v.value) for v in function.body if isinstance(v, ast.Assign) and any((isinstance(t, ast.Name) and t.id == 'boundaries' for t in v.targets))))
    requirements = [v for v in ast.walk(function) if isinstance(v, ast.Compare) and any((isinstance(a, ast.Constant) and a.value == n for a in v.comparators))]
    if not requirements or len(bounds) != 3 or bounds[-1][1] != n:
        raise ValueError('bank support does not match pinned original split helper')
    if any((not 0 < a < b <= n for a, b in bounds)):
        raise ValueError('invalid inherited split support')
    return bounds

def cohort(anchors, boundaries, split, offsets):
    train_stop, validation_stop = boundaries[split - 1]
    validation = list(range(train_stop, validation_stop))
    daily = validation[:-1]
    stamps = {str(o): [(dt.datetime.fromisoformat(anchors[p]) + dt.timedelta(minutes=15 * o)).isoformat() for p in daily] for o in offsets}
    return dict(train_origin_positions=list(range(train_stop)), validation_origin_positions=validation, daily_origin_positions=daily, origin_timestamps=stamps)

def validate_worker_process(process):
    own_stat = Path('/proc/self/stat').read_text().rsplit(')', 1)[1].split()
    if process.get('pid') != os.getpid() or process.get('start_ticks') != int(own_stat[19]) or process.get('boot_id') != Path('/proc/sys/kernel/random/boot_id').read_text().strip():
        raise RuntimeError('regional policy proof process lifetime differs after exec')

def validate_fi_config(c):
    scope = dict(
        region='FI',
        required_branch='work/pricefm-r152-parallel-recovery-20261024',
        tag='pricefm_stage_r152_fi_20261024',
        new_model_fits=0,
        new_geometries=0,
        paths=100,
        horizon_steps=96,
        quantiles=[0.1, 0.25, 0.45, 0.5, 0.55, 0.75, 0.9],
        clock_offsets_steps=[0, 24, 48, 72],
        chunk_origins=8,
        extra_seeds=[2026102301, 2026102302],
        primary_aggregation='equal_three_inner_split_macro',
        practical_margin={'absolute': 0.1, 'relative': 0.01},
        seed0_trigger_fraction=0.5,
        audit_key='pricefm_parallel_continuation_20261024|regional|FI|v1',
        benchmark_max_seconds=1200,
        cost_headroom=1.5,
        benchmark_D_repeats=3,
        benchmark_S_repeats=1,
        max_new_D_components=60,
        max_new_S_components=27,
        max_numerical_waves=3,
        max_projected_cpu_seconds=32400,
        wave_lease_seconds=7200,
        wave_dispatch_seconds=5400,
        maximum_replacement_reserve=1,
        forecast_seed=2026101502,
        expected_bank_origins=940,
        expected_daily_counts=[124, 134, 173],
        benchmark_preflight_included=True,
        benchmark_CPU_seconds=1200,
        assessment_CPU_seconds=1800,
    )
    if any((c.get(k) != v for k, v in scope.items())):
        raise ValueError('frozen FI scope or finite allocation differs')
    if any((c.get(k) is not False for k in ('official_evaluation_authorized', 'AL_authorized', 'promotion_authorized', 'test_used_for_selection'))):
        raise ValueError('new fitting, official evaluation or promotion is not admitted')
    packages = c.get('packages', [])
    ids = [p['package_id'] for p in packages]
    if len(packages) != 20 or len(set(ids)) != 20 or len({p['candidate_id'] for p in packages}) != 19:
        raise ValueError('exact20 packages/19 FI geometries required')
    if len({(p['candidate_id'], p['tau0']) for p in packages}) != 20:
        raise ValueError('duplicate exact FI geometry/scale')
    if any((p['spec']['region'] != 'FI' or p['p'] != 1 + sum(p['spec']['units']) for p in packages)):
        raise ValueError('FI readout/region identity differs')
    by = {p['package_id']: p for p in packages}
    if (
        c.get('control') != 'C0'
        or by['C0']['candidate_id'] != 'r134_d9293ed1d2540e6d'
        or by['C0']['tau0'] != 2.4929739307713866e-05
        or by['C0_alt']['candidate_id'] != by['C0']['candidate_id']
        or by['C0_alt']['tau0'] != 0.00024929739307713865
    ):
        raise ValueError('actual FI controls differ')
    wanted = ['C0', 'r134_75c4492b5ef11634', 'r134_819baf69f92b36e7', 'r134_8f8f3beb4b5a3c42']
    if c.get('benchmark_D_packages') != wanted or c.get('benchmark_S_packages') != wanted:
        raise ValueError('full fixed FI benchmark panel required')
    if max((by[p]['p'] for p in wanted)) != 961 or max((p['p'] for p in packages)) != 961:
        raise ValueError('FI worst-readout cost class differs')
    return c

class Study:

    def producer(self):
        c = self.config()
        verify_hashes({c['producer_entry']: c['producer_sha256']})
        if self._PRODUCER is None:
            spec = importlib.util.spec_from_file_location('r152_immutable_numerical_ADD497', c['producer_entry'])
            self._PRODUCER = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self._PRODUCER)
        return self._PRODUCER

    def validate_config(self, c):
        if self.legacy:
            return self.legacy_reference().validate_config(c)
        return validate_fi_config(c)

    def source_identity(self):
        if self.legacy:
            return self.legacy_reference().source_identity()
        return self.execution_identity()

    def name_for(self, package, split, mode, seed_index):
        return self.region + '_' + package + '_s' + str(split) + '_' + mode + '_seed' + str(seed_index)

    def names_for(self, packages, mode, seeds):
        return [self.name_for(p, split, mode, seed) for p in packages for seed in seeds for split in (1, 2, 3)]

    def choose_nominees(self, packages, losses, control, key):
        p = self.producer()
        by_id = {v['package_id']: v for v in packages}
        if set(losses) != set(by_id) or any((not math.isfinite(v) for v in losses.values())):
            raise ValueError('complete finite deterministic regional pool required')
        a = p.strongest(losses, [control])
        order = p.audit_permutation(packages, key)
        excluded = {by_id[control]['candidate_id'], by_id[a]['candidate_id']}
        eligible = [i for i in order if by_id[i]['candidate_id'] not in excluded]
        if not eligible:
            raise ValueError('geometry-distinct regional audit nominee unavailable')
        return dict(
            A=a,
            B=eligible[0],
            audit_key=key,
            audit_order=order,
            eligible_audit_order=eligible,
            audit_rule='SHA256(key|canonical_package_id), then ID; exclude C0 and A geometries',
        )

    def verify_evidence_lineage(self, record, directory, ledger, summary, contract_path):
        """The pre-score external audit binds moments, not only a self-consistent seal."""
        directory = Path(directory)
        expected = {str(directory / 'completed_evidence.json'): record['completed_evidence_sha256'], str(directory / 'fit/beta_mean.bin'): record['beta_mean_sha256'], str(directory / 'fit/beta_cov.bin'): record['beta_cov_sha256'], str(contract_path): record['contract_sha256']}
        if (
            str(directory) != record['directory']
            or any((not h or ledger.get(p) != h for p, h in expected.items()))
            or any((summary.get(k) != record[k] for k in ('p', 'n', 'omega_shape', 'omega_rate', 'posterior_target_sha256')))
            or summary.get('full_variational_certified') is not True
        ):
            raise RuntimeError('cached parent differs from prospectively pinned regional moments/target/contract')

    def build_preparation(self, identity):
        if self.legacy:
            raise RuntimeError('existing DK2 preparation is immutable; use its execution bridge')
        c = self.config()
        p = self.producer()
        pins = {c[k]: c[k + '_sha256'] for k in ('regional_evidence', 'parent_preparation', 'split_helper', 'proposal')}
        verify_hashes(pins)
        evidence = read(c['regional_evidence'])
        proposal = read(c['proposal'])
        old = read(c['parent_preparation'])
        if evidence['region'] != self.region or evidence['failures'] or old['source'] != c['parent_source'] or (evidence['source'] != c['parent_source']):
            raise RuntimeError('audited original FI source/evidence differs')
        if fingerprint(c['packages']) != fingerprint(proposal['packages']) or proposal['region'] != 'FI':
            raise RuntimeError('FI package proposal was changed')
        verify_hashes(old['source_sha256'])
        verify_hashes(old['bank_sha256'])
        verify_hashes({path: value['sha256'] if isinstance(value, dict) else value for path, value in evidence['input_sha256'].items()})
        sources = dict(old['source_sha256'])
        sources[c['producer_entry']] = c['producer_sha256']
        sources[c['legacy_reference_entry']] = c['legacy_reference_sha256']
        for pattern in ('application/scripts/pricefm/*r152*.py', 'application/config/*r152*.json', 'application/tests/*r152*.py', 'docs/implementation_notes/*r152*.md'):
            sources.update({str(v): digest(v) for v in ROOT.glob(pattern)})
        inputs = dict(pins)
        inputs.update(old['bank_sha256'])
        banks = {Path(path).stem: dict(path=path, sha256=h) for path, h in old['bank_sha256'].items()}
        anchors = None
        for bank in banks.values():
            found = bank_anchors(bank['path'])
            if anchors is not None and found != anchors:
                raise RuntimeError('regional feature banks have different anchors')
            anchors = found
        if len(anchors) != 940 or anchors[0] != '2022-02-04T00:00:00+00:00' or anchors[-1] != '2024-08-31T00:00:00+00:00':
            raise RuntimeError('own FI training anchor support differs')
        boundaries = split_boundaries(c['split_helper'], len(anchors))
        cohorts = {s: cohort(anchors, boundaries, s, c['clock_offsets_steps']) for s in (1, 2, 3)}
        if [len(cohorts[s]['daily_origin_positions']) for s in (1, 2, 3)] != [124, 134, 173]:
            raise RuntimeError('own FI safe origin counts differ')
        cache = Path(evidence['campaign'])
        tasks = []
        for package in c['packages']:
            if not any((v['candidate_id'] == package['candidate_id'] and v['tau0'] == package['tau0'] and (v['spec'] == package['spec']) for v in evidence['packages'])):
                raise RuntimeError('FI package not in archived training-only union')
            for split in (1, 2, 3):
                parent = f"rhs_{self.region}_{package['candidate_id']}_s{split}_t{package['tau0']:.12e}"
                audited = next((v for v in evidence['fits'] if v['name'] == parent))
                descriptor, result, ledger = p.kernel().verify_cached_packet(cache, parent, old['source']['head'], heavy=True)
                directory = cache / 'tasks_done' / parent
                terminal = read(directory / 'fit/terminal.json')
                summary = read(directory / 'fit/fit_summary.json')
                contract_path = cache / 'contracts' / (parent + '.json')
                contract = read(contract_path)
                required = {str(directory / 'completed_evidence.json'): audited['completed_evidence_sha256'], str(directory / 'fit/beta_mean.bin'): audited['beta_mean_sha256'], str(directory / 'fit/beta_cov.bin'): audited['beta_cov_sha256'], str(contract_path): audited['contract_sha256']}
                ledger.update({str(contract_path): digest(contract_path)})
                if any((ledger.get(path) != h for path, h in required.items())):
                    raise RuntimeError('pinned FI moment/contract bytes differ')
                if (
                    descriptor['spec'] != package['spec']
                    or descriptor['tau0'] != package['tau0']
                    or descriptor['region'] != self.region
                    or descriptor['split'] != split
                    or result['certified'] is not True
                    or terminal['full_variational_certified'] is not True
                    or terminal['test_opened'] is not False
                    or terminal['tau0'] != package['tau0']
                    or summary['p'] != package['p']
                    or summary['contract_sha256'] != digest(contract_path)
                    or contract['tau0'] != package['tau0']
                    or any((summary.get(k) != audited[k] for k in ('p', 'n', 'posterior_target_sha256')))
                ):
                    raise RuntimeError('exact training-only FI posterior scope differs')
                stats, stats_result, stats_ledger = p.kernel().verify_cached_packet(cache, descriptor['stats_name'], old['source']['head'], heavy=False)
                scaler = cache / 'tasks_done' / descriptor['stats_name'] / 'scaler.json'
                if (
                    stats['candidate_id'] != package['candidate_id']
                    or stats['split'] != split
                    or stats_result['certified'] is not True
                    or str(scaler) != audited['scaler_path']
                    or digest(scaler) != audited['scaler_sha256']
                ):
                    raise RuntimeError('exact FI scaler lineage differs')
                inputs.update(ledger)
                inputs.update(stats_ledger)
                for mode, seeds in (('D', (0,)), ('S', (0, 1, 2))):
                    for seed_index in seeds:
                        task = dict(
                            name=self.name_for(package['package_id'], split, mode, seed_index),
                            kind='cached_' + mode + '_full_origin',
                            region=self.region,
                            package_id=package['package_id'],
                            candidate_id=package['candidate_id'],
                            tau0=package['tau0'],
                            spec=package['spec'],
                            p=package['p'],
                            split=split,
                            mode=mode,
                            seed_index=seed_index,
                            forecast_seed=([old['protocol']['forecast_seed']] + c['extra_seeds'])[seed_index],
                            paths=100,
                            parent_task=parent,
                            parent_source=old['source'],
                            parent_fit=str(directory / 'fit'),
                            parent_seal_sha256=digest(directory / 'completed_evidence.json'),
                            parent_input_sha256=ledger,
                            scaler_path=str(scaler),
                            scaler_sha256=digest(scaler),
                            bank=banks[package['spec']['feature_policy']],
                            clock_offsets_steps=c['clock_offsets_steps'],
                            horizon_steps=96,
                            quantiles=c['quantiles'],
                            new_model_fits=0,
                            posterior_updated=False,
                            test_opened=False,
                            **cohorts[split],
                        )
                        task['scientific_identity_sha256'] = fingerprint(p.task_identity(task))
                        task['reuse'] = None
                        tasks.append(task)
        if old['protocol']['forecast_seed'] != 2026101502 or len(tasks) != 240:
            raise RuntimeError('FI seed0/descriptor count differs')
        verify_hashes(sources)
        return dict(
            status=self.status('PREPARED_NO_NUMERICAL_ADMISSION'),
            source=identity,
            config_sha256=digest(self.CONFIG),
            source_sha256=sources,
            input_sha256=inputs,
            dependency=old['dependency'],
            dependency_head=old['dependency_head'],
            region=self.region,
            packages=c['packages'],
            control='C0',
            tasks=tasks,
            banks=banks,
            original_regional_source=old['source'],
            potential_task_count=len(tasks),
            imported_components=0,
            new_model_fits=0,
            frozen_audit_permutation=p.audit_permutation(c['packages'], c['audit_key']),
            cohort_audit=dict(
            bank_origins=len(anchors),
            split_boundaries=boundaries,
            daily_counts={str(s): len(v['daily_origin_positions']) for s, v in cohorts.items()},
            policy='own pinned FI anchors and original split helper; last validation day excluded',
        ),
            official_outcomes_exposed_development_only=True,
            test_opened=False,
            posterior_updated=False,
        )

    def prepare(self):
        if self.legacy:
            prep = self.read_preparation()
            execution = self.execution_identity()
            if self.source_identity() != prep['source']:
                raise RuntimeError('original DK2 scientific source changed')
            verify_hashes(prep['source_sha256'])
            verify_hashes(prep['input_sha256'])
            bridge = self.execution_bridge_path()
            immutable(bridge, dict(
                status='R152_EXACT_DK2_EXECUTION_BRIDGE_NO_SCIENCE_CHANGE',
                study='DK2',
                scientific_source=prep['source'],
                execution_source=execution,
                preparation_path=str(self.PREP / 'preparation.json'),
                preparation_sha256=digest(self.PREP / 'preparation.json'),
                descriptor_count=len(prep['tasks']),
                task_identity_sha256=fingerprint(prep['tasks']),
                input_sha256=prep['input_sha256'],
                original_output=str(self.OUT),
                existing_EE_gate_preserved=True,
                new_model_fits=0,
            ))
            return dict(status='R152_DK2_BRIDGED_EXISTING_PREPARATION', scientific_source=prep['source'], execution_source=execution)
        value = self.build_preparation(self.source_identity())
        immutable(self.PREP / 'preparation.json', value)
        immutable(self.PREP / 'prepared.json', dict(source=value['source'], sha256=digest(self.PREP / 'preparation.json')))
        for task in value['tasks']:
            immutable(self.OUT / 'tasks' / (task['name'] + '.json'), task)
        return dict(
            status=value['status'],
            potential_components=len(value['tasks']),
            D_components=60,
            S_max=27,
            new_model_fits=0,
            cohort_audit=value['cohort_audit'],
        )

    def read_preparation(self):
        key = digest(self.PREP / 'preparation.json')
        if key not in self._PREPARATION:
            value = read(self.PREP / 'preparation.json')
            if read(self.PREP / 'prepared.json') != dict(source=value['source'], sha256=key) or value['config_sha256'] != digest(self.CONFIG):
                raise RuntimeError('regional preparation seal or config differs')
            self._PREPARATION.clear()
            self._PREPARATION[key] = value
        return self._PREPARATION[key]

    def task_by_name(self, name, prep=None):
        task = next((v for v in (prep or self.read_preparation())['tasks'] if v['name'] == name), None)
        if task is None:
            raise ValueError('unknown regional component: ' + name)
        if task['scientific_identity_sha256'] != fingerprint(self.producer().task_identity(task)):
            raise RuntimeError('regional scientific task identity differs')
        return task

    def task_complete(self, name):
        p = self.producer()
        prep = self.read_preparation()
        if name == '__finalize__':
            if not (self.OUT / 'assessment_seal.json').exists():
                return False
            if read(self.OUT / 'assessment_seal.json') != dict(sha256=digest(self.OUT / 'assessment.json'), source=prep['source']):
                raise RuntimeError('regional final assessment seal differs')
            if read(self.OUT / 'assessment.json').get('source') != prep['source']:
                raise RuntimeError('regional assessment producer differs')
            return True
        if name == '__benchmark__':
            folder = self.OUT / 'benchmark'
            if not (folder / 'completed_evidence.json').exists():
                return False
            timing = read(folder / 'timings.json')
            panels = {v['retained_prediction_packet'] for v in timing['rows']}
            if any((Path(v).name != v or not v.endswith('.npz') for v in panels)):
                raise RuntimeError('regional benchmark retained panel path escapes packet')
            seal = p.verify_packet(folder, {'timings.json', 'branch.json'} | panels)
            if seal.get('context') != dict(source=prep['source'], preparation_sha256=digest(self.PREP / 'preparation.json')):
                raise RuntimeError('regional benchmark context differs')
            return True
        task = self.task_by_name(name, prep)
        if read(self.OUT / 'tasks' / (name + '.json')) != task:
            raise RuntimeError('regional immutable descriptor differs')
        folder = self.OUT / 'tasks_done' / name
        if not folder.exists():
            return False
        files = [folder / v for v in ('completed_evidence.json', 'predictions.npz', 'result.json')]
        files += [Path(task['scaler_path']), Path(task['bank']['path'])] + [Path(v) for v in task['parent_input_sha256']]
        signature = (fingerprint(task), tuple(((str(v), v.stat().st_mtime_ns, v.stat().st_ctime_ns, v.stat().st_size) for v in files)))
        if self._COMPLETE.get(name) == signature:
            return True
        seal = p.verify_packet(folder, {'predictions.npz', 'result.json'})
        result = read(folder / 'result.json')
        if (
            seal.get('context') != p.context_identity(task, prep)
            or seal.get('certified') is not True
            or result.get('scientific_identity_sha256') != task['scientific_identity_sha256']
            or result.get('source') != prep['source']
            or result.get('units') != 'EUR/MWh'
            or result.get('mode') != task['mode']
            or result.get('new_model_fits') != 0
            or result.get('posterior_updated') is not False
            or result.get('test_opened') is not False
            or result.get('origin_clock_windows') != 4 * len(task['daily_origin_positions'])
            or not result.get('numerical_threadpools')
            or any((v['num_threads'] != 1 for v in result['numerical_threadpools']))
            or not math.isfinite(result['metrics']['AQL'])
            or result['metrics']['AQL'] < 0
        ):
            raise RuntimeError('regional final packet scope, source or policy differs')
        verify_hashes(task['parent_input_sha256'])
        verify_hashes({task['bank']['path']: task['bank']['sha256'], task['scaler_path']: task['scaler_sha256']})
        p.validate_arrays(task, p.read_npz(folder / 'predictions.npz', headers_only=True), read(task['scaler_path']), semantic=False)
        self._COMPLETE[name] = signature
        return True

    def component_loss(self, package, mode, seed=0):
        names = self.names_for([package], mode, [seed])
        if not all((self.task_complete(n) for n in names)):
            raise RuntimeError('complete three-split regional component required')
        return sum((read(self.OUT / 'tasks_done' / n / 'result.json')['metrics']['AQL'] for n in names)) / 3

    def write_decision(self, name, value):
        immutable(self.OUT / 'decisions' / (name + '.json'), value)
        immutable(self.OUT / 'decisions' / (name + '.seal.json'), dict(sha256=digest(self.OUT / 'decisions' / (name + '.json')), source=self.read_preparation()['source'], preparation_sha256=digest(self.PREP / 'preparation.json')))

    def read_decision(self, name):
        path = self.OUT / 'decisions' / (name + '.json')
        if read(path.with_name(name + '.seal.json')) != dict(sha256=digest(path), source=self.read_preparation()['source'], preparation_sha256=digest(self.PREP / 'preparation.json')):
            raise RuntimeError('regional decision seal differs')
        return read(path)

    def pricing(self):
        if not self.task_complete('__benchmark__'):
            raise RuntimeError('regional cost-only benchmark not complete')
        return read(self.OUT / 'benchmark/branch.json')

    def manifest_state(self):
        prep = self.read_preparation()
        if not self.task_complete('__benchmark__'):
            return ('BENCHMARK', ['__benchmark__'], [], False)
        price = self.pricing()
        if not price['prefix_admitted']:
            return ('DEFERRED_UNFUNDED_PREFIX', [], [], True)
        names = self.names_for([v['package_id'] for v in prep['packages']], 'D', [0])
        if not all((self.task_complete(n) for n in names)):
            return ('DETERMINISTIC_POOL', names, [], False)
        if not (self.OUT / 'decisions/nominees.seal.json').exists():
            return ('NOMINATION_REQUIRED', names, [], False)
        nominees = self.read_decision('nominees')['nominees']
        if len(nominees) != 2 or len(set(nominees)) != 2:
            raise RuntimeError('regional nominee set changed')
        names += self.names_for([prep['control']] + nominees, 'S', [0])
        if not all((self.task_complete(n) for n in names)):
            return ('NOMINEE_SEED0', names, [], False)
        if not (self.OUT / 'decisions/extra_seeds.seal.json').exists():
            return ('EXTRA_SEED_DECISION_REQUIRED', names, [], False)
        extra = self.read_decision('extra_seeds')
        names += extra['required_extra_components']
        if any((v not in nominees for v in extra['qualified'])):
            raise RuntimeError('regional qualifier set changed')
        if extra['unfunded_pending']:
            return ('MATCHED_MC_UNFUNDED_PENDING', names, extra['unfunded_pending'], False)
        if not all((self.task_complete(n) for n in names)):
            return ('MATCHED_FULL_MC', names, [], False)
        return ('READY_FOR_ASSESSMENT', names, [], True)

    def estimate_task(self, name):
        if name == '__finalize__':
            return dict(
                name=name,
                kind='independent_semantic_finalization',
                estimated_cpu_seconds=1800.0,
                estimated_wall_seconds=1800.0,
                estimated_max_chunk_wall_seconds=1800.0,
            )
        if name == '__benchmark__':
            return dict(name=name, kind='cost_only_benchmark', estimated_cpu_seconds=1200.0, estimated_wall_seconds=1200.0, estimated_max_chunk_wall_seconds=1200.0)
        value = self.pricing()['task_estimates'][name]
        return dict(name=name, kind=self.task_by_name(name)['kind'], **{k: value[k] for k in ('estimated_cpu_seconds', 'estimated_wall_seconds', 'estimated_max_chunk_wall_seconds')})

    def queue_state(self):
        phase, names, unfunded, terminal = self.manifest_state()
        complete = [n for n in names if self.task_complete(n)]
        pending = [n for n in names if n not in complete]
        assessment = read(self.OUT / 'assessment.json') if self.task_complete('__finalize__') else {}
        if assessment.get('resource_extra_seed_disposition') is not None:
            disposition = self.validate_resource_budget_disposition(assessment['resource_extra_seed_disposition'])
            phase = 'MATCHED_MC_UNFUNDED_PENDING'
            unfunded = list(disposition['components'])
        scientific_complete = (
            phase == 'READY_FOR_ASSESSMENT'
            and not pending
            and not unfunded
            and assessment.get('status') == self.status('SCIENTIFICALLY_COMPLETE_NOT_PROMOTED')
            and assessment.get('scientific_complete') is True
            and assessment.get('required_components') == assessment.get('verified_components') == len(names)
        )
        assessment_ready = phase in ('READY_FOR_ASSESSMENT', 'DEFERRED_UNFUNDED_PREFIX', 'MATCHED_MC_UNFUNDED_PENDING')
        return dict(
            assessment_ready=assessment_ready,
            execution_terminal=self.task_complete('__finalize__'),
            phase=phase,
            ready=[self.estimate_task(n) for n in pending if n not in unfunded],
            pending=pending,
            complete=complete,
            total=len(names),
            terminal=terminal,
            unfunded_pending=unfunded,
            new_model_fits=0,
            scientific_complete=scientific_complete,
            promotion_authorized=False,
            resource_projection=self.pricing()['resource_projection'] if phase != 'BENCHMARK' else {},
        )

    def extra_admission(self, prefix, qualifiers, control, price, remaining_CPU_seconds, completed_charges, budget_view=None):
        if remaining_CPU_seconds is None or not math.isfinite(remaining_CPU_seconds) or remaining_CPU_seconds < 0:
            raise ValueError('fresh finite remaining-window CPU allowance required for atomic MC admission')
        extras = self.names_for([control] + list(qualifiers), 'S', [1, 2]) if qualifiers else []
        prefix_cpu = sum((completed_charges[n]['charged_CPU_seconds'] for n in prefix))
        cpu = sum((price['task_estimates'][n]['estimated_cpu_seconds'] for n in extras))
        remaining = max(0.0, min(remaining_CPU_seconds, price['benchmark_adjusted_available_CPU_seconds'] - prefix_cpu - price['replacement_reserve_CPU_seconds']))
        fits = cpu <= remaining
        return dict(
            qualified=list(qualifiers),
            required_extra_components=extras,
            admitted_extra_components=extras if fits else [],
            unfunded_pending=[] if fits else extras,
            atomic_qualified_set_admitted=fits,
            prefix_charged_CPU_seconds=prefix_cpu,
            extra_projected_CPU_seconds=cpu,
            remaining_CPU_seconds=remaining,
            explicit_remaining_window_CPU_seconds=remaining_CPU_seconds,
            completed_prefix_CPU_charges=completed_charges,
            resource_budget_view=budget_view,
            status='ADMITTED_MATCHED_EXTRAS' if fits else 'DEFERRED_UNFUNDED_MATCHED_EXTRAS',
            rule='entire qualified set and one shared control; no cost-based nominee or seed replacement',
        )

    def advance(self, remaining_CPU_seconds=None, budget_view=None):
        prep = self.read_preparation()
        p = self.producer()
        phase, names, _, _ = self.manifest_state()
        if phase == 'NOMINATION_REQUIRED':
            losses = {v['package_id']: self.component_loss(v['package_id'], 'D') for v in prep['packages']}
            rule = self.choose_nominees(prep['packages'], losses, prep['control'], read(self.CONFIG)['audit_key'])
            if rule['audit_order'] != prep['frozen_audit_permutation']:
                raise RuntimeError('frozen regional audit order differs')
            self.write_decision('nominees', dict(nominees=[rule['A'], rule['B']], rule=rule, nomination_losses=losses, source=prep['source']))
        elif phase == 'EXTRA_SEED_DECISION_REQUIRED':
            nominees = self.read_decision('nominees')['nominees']
            control = self.component_loss(prep['control'], 'S')
            gains = {n: control - self.component_loss(n, 'S') for n in nominees}
            trigger = 0.5 * p.practical_margin(control)
            qualified = [n for n in nominees if gains[n] >= trigger]
            decision = self.extra_admission(names, qualified, prep['control'], self.pricing(), remaining_CPU_seconds, {n: self.completed_CPU_charge(n, prep) for n in names}, budget_view)
            decision.update(seed0_gains=gains, seed0_control_AQL=control, exploration_trigger=trigger, source=prep['source'])
            self.write_decision('extra_seeds', decision)
        return self.queue_state()

    def prefix_contract(self, prep, estimates, available):
        c = read(self.CONFIG)
        packages = prep['packages']
        control = prep['control']
        ids = [v['package_id'] for v in packages]
        scenarios = []
        d = sum((estimates[n]['estimated_cpu_seconds'] for n in self.names_for(ids, 'D', [0])))
        for a in ids:
            if a == control:
                continue
            losses = {i: 2.0 for i in ids}
            losses[a] = 1.0
            b = self.choose_nominees(packages, losses, control, c['audit_key'])['B']
            initial = self.names_for([control, a, b], 'S', [0])
            scenarios.append(dict(A=a, B=b, seed0_CPU_seconds=sum((estimates[n]['estimated_cpu_seconds'] for n in initial))))
        worst = max(scenarios, key=lambda v: (v['seed0_CPU_seconds'], v['A']))
        replacement = max((v['estimated_cpu_seconds'] for v in estimates.values()))
        total = d + worst['seed0_CPU_seconds'] + replacement
        return dict(
            D_CPU_seconds=d,
            worst_seed0_nomination=worst,
            all_prospective_seed0_scenarios=scenarios,
            replacement_reserve_CPU_seconds=replacement,
            maximum_replacements=1,
            worst_prefix_CPU_seconds=total,
            benchmark_adjusted_available_CPU_seconds=available,
            prefix_admitted=total <= available,
            no_losses_used=True,
            extras_conditioned_on_remaining_budget=True,
        )

    def validate_worker_lease(self, receipt, prep, name, now=None):
        now = time.time() if now is None else now
        lease_path = Path(receipt['admission_path'])
        master_path = Path(receipt['master_path'])
        verify_hashes({str(lease_path): receipt['admission_sha256'], str(master_path): receipt['master_sha256']})
        lease = read(lease_path)
        master = read(master_path)
        expiry = lease.get('expires_epoch', -float('inf'))
        start = lease.get('started_epoch', float('inf'))
        master_id = master.get('scope_id', master.get('master_scope_id'))
        master_start = master.get('start_epoch', float('inf'))
        master_expiry = master.get('expires_epoch', -float('inf'))
        if (
            not master_id
            or not receipt.get('lease_id')
            or not receipt.get('controller_unit')
            or not master_start <= start
            or not math.isclose(master_expiry - master_start, 43200.0, abs_tol=1e-06)
        ):
            raise RuntimeError('one committed twelve-hour master must contain the admission')
        if (
            lease.get('schema_version', 1) != 1
            or lease.get('study') != self.study_id
            or lease.get('lease_id') != receipt.get('lease_id')
            or lease.get('study_source_head') != prep['source']['head']
            or lease.get('source_head') != receipt.get('resource_source_head')
            or lease.get('prep_sha256') != digest(self.PREP / 'preparation.json')
            or lease.get('master_sha256') != receipt['master_sha256']
            or lease.get('master_scope_id') != master_id
            or lease.get('controller_unit') != receipt.get('controller_unit')
            or expiry != receipt.get('lease_expires_epoch')
            or not start <= now < expiry
            or expiry > master.get('expires_epoch', -float('inf'))
            or not math.isclose(expiry - start, lease.get('seconds', -1), abs_tol=1e-06, rel_tol=0.0)
        ):
            raise RuntimeError('regional finite admission/master/source/preparation differs')
        identifier = lease.get('admission_id', '')
        kind = lease.get('kind')
        if name == '__benchmark__':
            if identifier != self.study_id + '-B0' or not 0 < lease['seconds'] <= 1200:
                raise RuntimeError('benchmark must use its single20-minute admission')
        elif name == '__finalize__':
            if identifier != self.study_id + '-A0' or not 0 < lease['seconds'] <= 1800:
                raise RuntimeError('assessment must use own bounded reserved admission')
            parent_path = Path(lease['parent_admission_path'])
            closed_path = Path(lease['compute_closed_path'])
            verify_hashes({str(parent_path): lease['parent_admission_sha256'], str(closed_path): lease['compute_closed_sha256']})
            parent, closed = (read(parent_path), read(closed_path))
            if (
                parent.get('study') != self.study_id
                or parent.get('lease_id') != lease.get('parent_lease_id')
                or parent.get('master_scope_id') != master_id
                or parent.get('master_sha256') != receipt['master_sha256']
                or parent.get('prep_sha256') != lease['prep_sha256']
                or not parent.get('started_epoch', float('inf')) <= start < expiry <= parent.get('expires_epoch', -float('inf'))
                or closed.get('lease_id') != parent['lease_id']
                or closed.get('study') != self.study_id
                or closed.get('active_workers') != []
                or closed.get('numerical_dispatch_closed') is not True
                or not parent['started_epoch'] <= closed.get('closed_epoch', float('inf')) <= start
            ):
                raise RuntimeError('assessment must be contained in its drained closed-compute numerical window')
        elif identifier not in [self.study_id + '-C' + str(i) for i in (1, 2, 3)] or lease['seconds'] != 7200:
            raise RuntimeError('D/S requires a numerical admission')
        if kind in ('closed', 'terminal') or lease.get('nonrenewing', True) is not True:
            raise RuntimeError('terminal or renewable admission refused')
        return lease

    def guard(self, cpu, receipt_path, name):
        receipt = read(receipt_path)
        prep = self.read_preparation()
        if (
            receipt.get('schema_version') != 1
            or receipt.get('stage') != 'R152'
            or receipt.get('task') != name
            or receipt.get('source_head') != prep['source']['head']
            or receipt.get('cpu') != cpu
            or receipt.get('lease_expires_epoch', 0) <= time.time()
            or receipt.get('expected_affinity') != [cpu]
            or receipt.get('expected_scheduler') != 5
            or receipt.get('numerical_threads') != 1
            or receipt.get('io_class') != 3
            or not receipt.get('worker_invocation_id')
            or not receipt.get('worker_cgroup')
            or not receipt.get('actual_probe')
            or not receipt.get('global_slot_path')
        ):
            raise RuntimeError('R152 regional worker policy receipt differs')
        if cpu not in range(15, 30) or os.sched_getaffinity(0) != {cpu} or os.sched_getscheduler(0) != os.SCHED_IDLE:
            raise RuntimeError('one physical CPU15–29 and SCHED_IDLE required')
        if not subprocess.check_output(['ionice', '-p', str(os.getpid())], text=True).startswith('idle'):
            raise RuntimeError('idle I/O required')
        paths = {line.split(':', 2)[2] for line in Path('/proc/self/cgroup').read_text().splitlines()}
        if receipt['worker_cgroup'] not in paths or receipt['worker_invocation_id'] != os.environ.get('INVOCATION_ID'):
            raise RuntimeError('actual regional worker cgroup/invocation differs')
        proof = receipt['actual_probe']
        props = proof.get('properties', {})
        process = proof.get('process', {})
        if (
            props.get('Id') != receipt.get('unit')
            or props.get('InvocationID') != receipt['worker_invocation_id']
            or props.get('ControlGroup') != receipt['worker_cgroup']
            or process.get('scheduler') != 5
            or process.get('affinity') != [cpu]
            or props.get('IOSchedulingClass') != '3'
        ):
            raise RuntimeError('actual regional unit policy proof differs')
        validate_worker_process(process)
        for key in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS', 'BLIS_NUM_THREADS', 'NUMEXPR_NUM_THREADS', 'VECLIB_MAXIMUM_THREADS'):
            if os.environ.get(key) != '1':
                raise RuntimeError('one numerical thread environment required')
        self.validate_worker_lease(receipt, prep, name)
        if receipt.get('global_slot_path'):
            slotpath = Path(receipt['global_slot_path'])
            expected = receipt.get('global_slot_sha256', receipt.get('global_slot_claim_sha256', receipt.get('claim_sha')))
            if not expected:
                raise RuntimeError('global slot claim hash missing')
            verify_hashes({str(slotpath): expected})
            slot = read(slotpath)
            if slot.get('task') != name or slot.get('cpu') != cpu or slot.get('lease_id') != receipt['lease_id']:
                raise RuntimeError('global physical-slot claim differs')
        if time.monotonic() - self._last_source_check >= 30:
            execution = self.execution_identity()
            if receipt.get('resource_source_head') != execution['head']:
                raise RuntimeError('execution resource source differs')
            if self.source_identity() != prep['source']:
                raise RuntimeError('scientific source identity differs')
            if self.legacy:
                bridge = read(self.execution_bridge_path())
                if (
                    bridge.get('scientific_source') != prep['source']
                    or bridge.get('execution_source') != execution
                    or bridge.get('preparation_sha256') != digest(self.PREP / 'preparation.json')
                    or bridge.get('task_identity_sha256') != fingerprint(prep['tasks'])
                    or bridge.get('existing_EE_gate_preserved') is not True
                ):
                    raise RuntimeError('DK2 execution bridge differs from its unchanged scientific preparation')
            verify_hashes(prep['source_sha256'])
            self._last_source_check = time.monotonic()
        return receipt

    def predict(self, context, task, descriptor, beat):
        return self.legacy_reference().predict(context, task, descriptor, beat)

    def legacy_control_replay(self, context, task, descriptor, prediction, truth):
        """Compare wiring with the actual original regional producer's call chain.

    This is a no-loss benchmark check, not an additional screening component.
    No equivalent retained full-cohort control array has been established.
    """
        import numpy as np
        from pricefm_r127_contract import shifted_windows
        c = read(self.CONFIG)
        parent = read(c['parent_preparation'])
        actual = next((p for p in c['packages'] if p['package_id'] == 'C0'))
        if (
            task['package_id'] != 'C0'
            or task['seed_index'] != 0
            or task['candidate_id'] != actual['candidate_id']
            or task['tau0'] != actual['tau0']
            or task['forecast_seed'] != parent['protocol']['forecast_seed']
        ):
            raise RuntimeError('legacy control replay requires exact actual C0 and original seed')
        runtime = context['runtime']
        offset = descriptor['clock_offset_steps']
        positions = np.asarray(descriptor['origin_positions'], dtype=int)
        arrays = shifted_windows(context['scaled'], positions, offset, np.asarray(task['validation_origin_positions'], dtype=int))
        if task['mode'] == 'D':
            reference = self.producer().kernel().deterministic_predictions(runtime, arrays, task['spec'], context['fit'])
            okay = np.allclose(reference, prediction, atol=1e-12, rtol=1e-10)
            rule = 'same_original_analytic_kernel_call_chain_consistency_atol1e-12_rtol1e-10_not_independent_D_implementation'
        else:
            original_seed = runtime.BASE.deterministic_seed(parent['protocol']['forecast_seed'], c['region'], task['split'])
            reference, _ = context['core'].normal_predictions(runtime, arrays, task['spec'], context['fit'], positions * 96 + offset, runtime.BASE.deterministic_seed(original_seed, 'clock', offset), paths=100)
            okay = np.array_equal(reference, prediction)
            rule = 'bitwise_original_R141_regional_absolute_clock_RNG_call_chain'
        if not okay or not np.array_equal(arrays.response, truth):
            raise RuntimeError('regional C0 differs from original producer mathematical replay')
        return dict(
            status='PASS_ACTUAL_C0_ORIGINAL_MATH_REPLAY',
            rule=rule,
            mode=task['mode'],
            original_regional_source=parent['source'],
            seed=parent['protocol']['forecast_seed'],
            region=c['region'],
            paths=100 if task['mode'] == 'S' else 0,
            no_candidate_AQL_computed=True,
            reference_prediction_bytes_sha256=hashlib.sha256(np.ascontiguousarray(reference, dtype='<f8').tobytes()).hexdigest(),
            retained_original_full_cohort_packet_reuse=False,
        )

    def start_CPU_attempt(self, task, prep, receipt, policy_path):
        folder = self.OUT / 'cpu_accounting' / task['name'] / receipt['worker_invocation_id']
        value = dict(
            source=prep['source'],
            task=task['name'],
            scientific_identity_sha256=task['scientific_identity_sha256'],
            policy_invocation_id=receipt['worker_invocation_id'],
            policy_receipt_path=str(policy_path),
            policy_receipt_sha256=digest(policy_path),
            prior_started_invocations=sorted((v.parent.name for v in folder.parent.glob('*/started.json'))),
            preexisting_checkpoint_count=len(list((self.OUT / 'checkpoints' / task['name']).glob('*/completed_evidence.json'))),
        )
        immutable(folder / 'started.json', value)
        return (folder, value)

    def finish_CPU_attempt(self, folder, started, completed):
        child = resource.getrusage(resource.RUSAGE_CHILDREN)
        process = time.process_time()
        children = child.ru_utime + child.ru_stime
        value = dict(
            started,
            completed_component=completed,
            observed_process_CPU_seconds=process,
            observed_terminated_children_CPU_seconds=children,
            observed_total_CPU_seconds=process + children,
            task_final_seal_sha256=digest(self.OUT / 'tasks_done' / started['task'] / 'completed_evidence.json') if completed else None,
            post_observation_exit_allowance_CPU_seconds=5.0,
            hard_CPU_quota=False,
            exact_exit_CPU_measurement=False,
        )
        immutable(folder / 'observed.json', value)
        immutable(folder / 'observed.seal.json', dict(sha256=digest(folder / 'observed.json'), source=started['source']))

    def completed_CPU_charge(self, name, prep=None):
        prep = prep or self.read_preparation()
        task = self.task_by_name(name, prep)
        if not self.task_complete(name):
            raise RuntimeError('CPU credit requires strict final component')
        estimate = self.pricing()['task_estimates'][name]['estimated_cpu_seconds']
        starts = list((self.OUT / 'cpu_accounting' / name).glob('*/started.json'))
        totals = []
        errors = []
        final = 0
        prior = set()
        present = {v.parent.name for v in starts}
        for path in starts:
            try:
                started = read(path)
                observed = read(path.parent / 'observed.json')
                previous = started.get('prior_started_invocations')
                if not isinstance(previous, list) or any((not isinstance(v, str) or not v or '/' in v or (v in ('.', '..')) for v in previous)):
                    raise ValueError('invalid CPU attempt lineage')
                prior.update(previous)
                if (
                    started.get('source') != prep['source']
                    or started.get('task') != name
                    or started.get('scientific_identity_sha256') != task['scientific_identity_sha256']
                    or started.get('policy_invocation_id') != path.parent.name
                    or any((observed.get(k) != v for k, v in started.items()))
                    or read(path.parent / 'observed.seal.json') != dict(sha256=digest(path.parent / 'observed.json'), source=prep['source'])
                    or observed.get('post_observation_exit_allowance_CPU_seconds') != 5.0
                    or observed.get('hard_CPU_quota') is not False
                    or observed.get('exact_exit_CPU_measurement') is not False
                    or type(observed.get('completed_component')) is not bool
                    or started.get('preexisting_checkpoint_count', 0) and (not previous)
                ):
                    raise ValueError('CPU attempt source/task/seal differs')
                verify_hashes({started['policy_receipt_path']: started['policy_receipt_sha256']})
                policy = read(started['policy_receipt_path'])
                if policy.get('task') != name or policy.get('source_head') != prep['source']['head'] or policy.get('worker_invocation_id') != path.parent.name:
                    raise ValueError('CPU receipt policy differs')
                values = [observed[k] for k in ('observed_process_CPU_seconds', 'observed_terminated_children_CPU_seconds', 'observed_total_CPU_seconds')]
                if any((isinstance(v, bool) or not isinstance(v, (int, float)) or (not math.isfinite(v)) or (v < 0) for v in values)):
                    raise ValueError('invalid observed CPU')
                if not math.isclose(values[0] + values[1], values[2], rel_tol=1e-12, abs_tol=1e-10):
                    raise ValueError('CPU sum differs')
                if observed['completed_component']:
                    if observed['task_final_seal_sha256'] != digest(self.OUT / 'tasks_done' / name / 'completed_evidence.json'):
                        raise ValueError('CPU credit final scientific seal differs')
                    final += 1
                totals.append(values[2])
            except Exception as error:
                errors.append(dict(attempt=str(path), error=repr(error)))
        missing_prior = sorted(prior - present)
        missing = len(errors) + len(missing_prior)
        if not final:
            missing = max(1, missing)
        charge = sum((v + 5.0 for v in totals)) + missing * estimate
        return dict(
            charged_CPU_seconds=charge,
            observed_CPU_seconds=sum(totals),
            observed_attempts=len(totals),
            unknown_or_malformed_attempts=missing,
            missing_prior_invocations=missing_prior,
            verified_final_CPU_receipts=final,
            receipt_errors=errors,
            credit_eligible=bool(totals) and (not missing) and bool(final),
            frozen_component_CPU_seconds=estimate,
            hard_CPU_quota=False,
            exact_exit_CPU_measurement=False,
            charge_rule='all observed attempts process+terminated-child CPU +5s each; full estimate per unknown attempt',
        )

    def attempt_charge(self, saved):
        """Charge one owned invocation; never sum or credit other attempts here.

        The shared ledger reconciles prior invocation IDs once against its
        canonical owned intents. Missing or malformed evidence receives the
        full frozen component estimate, even if another attempt later finished.
        """
        name = saved['task']
        prep = self.read_preparation()
        task = self.task_by_name(name, prep)
        estimate = self.pricing()['task_estimates'][name]['estimated_cpu_seconds']
        invocation = (saved.get('attested') or {}).get('InvocationID')
        prior = []
        observed_cpu = None
        try:
            if not isinstance(invocation, str) or not invocation:
                raise ValueError('owned invocation identity absent')
            folder = self.OUT/'cpu_accounting'/name/invocation
            started = read(folder/'started.json')
            prior = started.get('prior_started_invocations')
            if (not isinstance(prior, list) or len(prior) != len(set(prior))
                    or any(not isinstance(item, str) or not item or '/' in item
                           or item in ('.', '..', invocation) for item in prior)):
                raise ValueError('CPU attempt lineage malformed')
            policy_path = Path(saved['policy_receipt'])
            if (started.get('source') != prep['source'] or started.get('task') != name
                    or started.get('scientific_identity_sha256') != task['scientific_identity_sha256']
                    or started.get('policy_invocation_id') != invocation
                    or started.get('policy_receipt_path') != str(policy_path)
                    or started.get('policy_receipt_sha256') != digest(policy_path)
                    or saved.get('study') != self.study_id
                    or saved.get('study_source_head') != prep['source']['head']
                    or started.get('preexisting_checkpoint_count', 0) and not prior):
                raise ValueError('CPU started record differs from exact owned scientific attempt')
            policy = read(policy_path)
            if (policy.get('stage') != 'R152' or policy.get('task') != name
                    or policy.get('source_head') != prep['source']['head']
                    or policy.get('resource_source_head') != saved.get('source_head')
                    or policy.get('worker_invocation_id') != invocation
                    or policy.get('unit') != saved.get('unit')
                    or policy.get('lease_id') != saved.get('lease_id')
                    or policy.get('cpu') != saved.get('cpu')
                    or policy.get('worker_cgroup') != saved['attested'].get('ControlGroup')):
                raise ValueError('CPU policy receipt differs from owned unit/invocation/lease')
            observed = read(folder/'observed.json')
            if (read(folder/'observed.seal.json') != dict(sha256=digest(folder/'observed.json'), source=prep['source'])
                    or any(observed.get(key) != value for key, value in started.items())
                    or observed.get('post_observation_exit_allowance_CPU_seconds') != 5.
                    or observed.get('hard_CPU_quota') is not False
                    or observed.get('exact_exit_CPU_measurement') is not False
                    or type(observed.get('completed_component')) is not bool):
                raise ValueError('CPU observation seal or started backlink differs')
            values = [observed.get(key) for key in (
                'observed_process_CPU_seconds', 'observed_terminated_children_CPU_seconds',
                'observed_total_CPU_seconds')]
            if (any(isinstance(value, bool) or not isinstance(value, (int,float))
                    or not math.isfinite(value) or value < 0 for value in values)
                    or not math.isclose(values[0]+values[1], values[2], rel_tol=1e-12, abs_tol=1e-10)):
                raise ValueError('CPU observation total malformed')
            observed_cpu = values[2]
            complete = observed['completed_component'] and self.task_complete(name)
            if complete and observed.get('task_final_seal_sha256') != digest(self.OUT/'tasks_done'/name/'completed_evidence.json'):
                raise ValueError('CPU credit final scientific seal differs')
            amount = observed_cpu+5. if complete else max(estimate, observed_cpu+5.)
            return dict(charged_CPU_seconds=amount, observed_CPU_seconds=observed_cpu,
                verified_final_observation=bool(complete), conservative_full_reservation=not complete,
                invocation_id=invocation, task=name, prior_started_invocations=prior,
                missing_prior_invocations=[item for item in prior if not (folder.parent/item/'started.json').is_file()],
                scope='ONE_OWNED_INVOCATION_ONLY', no_cross_attempt_credit=True,
                error=None, post_observation_exit_allowance_CPU_seconds=5.)
        except Exception as error:
            # A self-consistent observed JSON alone never earns a discount.
            amount = max(estimate, observed_cpu+5.) if observed_cpu is not None else estimate
            return dict(charged_CPU_seconds=amount, observed_CPU_seconds=observed_cpu,
                verified_final_observation=False, conservative_full_reservation=True,
                invocation_id=invocation, task=name,
                prior_started_invocations=prior if isinstance(prior,list) else [],
                missing_prior_invocations=[], scope='ONE_OWNED_INVOCATION_ONLY',
                no_cross_attempt_credit=True, error=repr(error),
                post_observation_exit_allowance_CPU_seconds=5.)

    def checkpoint(self, prep, task, descriptor, context, beat):
        import numpy as np
        p = self.producer()
        folder = self.OUT / 'checkpoints' / task['name'] / descriptor['name']
        identity = dict(context=p.context_identity(task, prep), descriptor=descriptor)
        if folder.exists():
            seal = p.verify_packet(folder, {'chunk.json', 'predictions.npz'})
            if seal.get('identity') != identity or seal.get('certified') is not True:
                raise RuntimeError('regional checkpoint context differs')
            p.validate_arrays(task, p.read_npz(folder / 'predictions.npz'), context['scaler'], descriptor)
            with np.load(folder / 'predictions.npz', allow_pickle=False) as packet:
                return {k: packet[k] for k in packet.files}
        wall = time.monotonic()
        cpu = time.process_time()
        beat(dict(status='chunk_running', chunk=descriptor['name']))
        prediction, truth, audit = self.predict(context, task, descriptor, beat)
        arrays = p.retained_arrays(context, task, descriptor, prediction, truth)
        p.validate_arrays(task, p.light(arrays), context['scaler'], descriptor)
        attempt = self.OUT / 'attempts' / task['name'] / (descriptor['name'] + '.' + uuid.uuid4().hex)
        attempt.mkdir(parents=True)
        np.savez_compressed(attempt / 'predictions.npz', **arrays)
        write(attempt / 'chunk.json', dict(
            identity=identity,
            sampler_audit=audit,
            numerical_threadpools=p.kernel().numerical_threadpools(),
            elapsed_seconds=time.monotonic() - wall,
            cpu_seconds=time.process_time() - cpu,
            new_model_fits=0,
            posterior_updated=False,
        ))
        write(attempt / 'completed_evidence.json', dict(identity=identity, certified=True, artifacts={v: digest(attempt / v) for v in ('chunk.json', 'predictions.npz')}))
        folder.parent.mkdir(parents=True, exist_ok=True)
        os.rename(attempt, folder)
        beat(dict(status='chunk_sealed', chunk=descriptor['name']))
        return arrays

    def worker(self, name, cpu, policy_receipt):
        receipt = self.guard(cpu, policy_receipt, name)
        prep = self.read_preparation()
        p = self.producer()
        if name == '__finalize__':
            return self.finalize(self.resource_budget_disposition(receipt),
                                 guard=lambda: self.guard(cpu, policy_receipt, name))
        if name == '__benchmark__':
            return self.benchmark(prep, cpu, policy_receipt, time.process_time())
        task = self.task_by_name(name, prep)
        if name not in [v['name'] for v in self.queue_state()['ready']] and (not self.task_complete(name)):
            raise RuntimeError('regional task not funded or admitted')
        locks = self.OUT / 'locks'
        locks.mkdir(parents=True, exist_ok=True)
        with (locks / (name + '.lock')).open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if self.task_complete(name):
                return dict(status='already_complete', name=name)
            folder, started = self.start_CPU_attempt(task, prep, receipt, policy_receipt)
            import numpy as np

            def beat(event):
                self.guard(cpu, policy_receipt, name)
                write(self.OUT / 'heartbeats' / (name + '.json'), dict(event, epoch=time.time(), task=name, cpu=cpu, pid=os.getpid()))
            beat(dict(status='context_loading'))
            context = p.numerical_context(prep, task)
            parts = []
            for descriptor in p.chunks(task):
                if time.time() >= receipt['lease_expires_epoch'] or self.stop_requested(receipt, policy_receipt, name):
                    beat(dict(status='cooperative_checkpoint_stop'))
                    self.finish_CPU_attempt(folder, started, False)
                    return dict(status='deferred_at_checkpoint', name=name)
                parts.append(self.checkpoint(prep, task, descriptor, context, beat))
            arrays = {k: np.ascontiguousarray(np.concatenate([v[k] for v in parts]), dtype='<i8' if k in p.INT_KEYS else '<f8') for k in p.array_shapes(1)}
            p.validate_arrays(task, p.light(arrays), context['scaler'])
            verify_hashes(task['parent_input_sha256'])
            result = dict(
                name=name,
                source=prep['source'],
                certified=True,
                mode=task['mode'],
                scientific_identity_sha256=task['scientific_identity_sha256'],
                units='EUR/MWh',
                metrics=p.metrics(p.light(arrays)),
                origin_clock_windows=len(arrays['origin_positions']),
                numerical_threadpools=p.kernel().numerical_threadpools(),
                new_model_fits=0,
                posterior_updated=False,
                test_opened=False,
                promotion_authorized=False,
            )
            attempt = self.OUT / 'attempts' / name / ('final.' + uuid.uuid4().hex)
            attempt.mkdir(parents=True)
            np.savez_compressed(attempt / 'predictions.npz', **arrays)
            write(attempt / 'result.json', result)
            write(attempt / 'completed_evidence.json', dict(context=p.context_identity(task, prep), certified=True, artifacts={v: digest(attempt / v) for v in ('result.json', 'predictions.npz')}))
            target = self.OUT / 'tasks_done' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                raise RuntimeError('unverified existing regional packet requires review')
            self.guard(cpu, policy_receipt, name)
            os.rename(attempt, target)
            if not self.task_complete(name):
                raise RuntimeError('sealed regional packet failed strict completion')
            self.finish_CPU_attempt(folder, started, True)
            beat(dict(status='completed'))
            return result

    def benchmark(self, prep, cpu, policy_receipt, startup_cpu=0.0):
        """Fixed timing panel; compute no candidate loss or scientific selection."""
        import numpy as np
        c = read(self.CONFIG)
        p = self.producer()
        receipt = read(policy_receipt)
        begin = time.monotonic()
        cpu_begin = 0.0
        deadline = begin + receipt['lease_expires_epoch'] - time.time()
        rows = []
        attempt = self.OUT / 'attempts/__benchmark__' / uuid.uuid4().hex
        attempt.mkdir(parents=True)

        def beat(event):
            self.guard(cpu, policy_receipt, '__benchmark__')
            write(self.OUT / 'heartbeats/__benchmark__.json', dict(event, epoch=time.time(), task='__benchmark__', cpu=cpu, pid=os.getpid()))
        preflight = self.numeric_preflight(prep, receipt, beat)
        for mode in ('D', 'S'):
            for package in c['benchmark_' + mode + '_packages']:
                task = self.task_by_name(self.name_for(package, 3, mode, 0), prep)
                if time.monotonic() >= deadline:
                    raise RuntimeError('regional benchmark lease exhausted')
                wall0 = time.monotonic()
                cpu0 = time.process_time()
                beat(dict(status='context_loading', package_id=package, mode=mode))
                context = p.numerical_context(prep, task)
                cold = time.monotonic() - wall0
                cold_cpu = time.process_time() - cpu0
                descriptor = p.chunks(task)[0]
                previous = None
                for repetition in range(c['benchmark_' + mode + '_repeats']):
                    if time.monotonic() >= deadline or (Path(policy_receipt).parent / 'stop_requests/__benchmark__.json').exists():
                        raise RuntimeError('regional benchmark cap/stop reached; no prefix admitted')
                    wall0 = time.monotonic()
                    cpu0 = time.process_time()
                    prediction, truth, audit = self.predict(context, task, descriptor, beat)
                    arithmetic = time.monotonic() - wall0
                    arithmetic_cpu = time.process_time() - cpu0
                    replay = self.legacy_control_replay(context, task, descriptor, prediction, truth) if package == 'C0' and repetition == 0 else None
                    if previous is not None and (not np.array_equal(prediction, previous)):
                        raise RuntimeError('warm regional arithmetic repeat changed')
                    previous = prediction.copy()
                    wall0 = time.monotonic()
                    cpu0 = time.process_time()
                    path = attempt / (mode + '_' + package + '_' + str(repetition) + '.npz')
                    np.savez_compressed(path, **p.retained_arrays(context, task, descriptor, prediction, truth, compute_loss=False))
                    packet_hash = digest(path)
                    packet_bytes = path.stat().st_size
                    rows.append(dict(
                        mode=mode,
                        package_id=package,
                        p=task['p'],
                        spec=task['spec'],
                        split=3,
                        clock_offset_steps=0,
                        origin_count=len(descriptor['origin_positions']),
                        repetition=repetition,
                        cold_context_wall_seconds=cold if repetition == 0 else 0.0,
                        cold_context_cpu_seconds=cold_cpu if repetition == 0 else 0.0,
                        arithmetic_wall_seconds=arithmetic,
                        arithmetic_cpu_seconds=arithmetic_cpu,
                        serialization_wall_seconds=time.monotonic() - wall0,
                        serialization_cpu_seconds=time.process_time() - cpu0,
                        retained_prediction_packet=path.name,
                        retained_prediction_sha256=packet_hash,
                        compressed_bytes=packet_bytes,
                        numerical_threadpools=p.kernel().numerical_threadpools(),
                        sampler_audit=audit,
                        original_control_replay=replay,
                    ))
                del context
        wall = time.time() - self.validate_worker_lease(receipt, prep, '__benchmark__')['started_epoch']
        cpu_time = time.process_time() - cpu_begin
        expected = len(c['benchmark_D_packages']) * 3 + len(c['benchmark_S_packages'])
        if len(rows) != expected or time.monotonic() >= deadline or time.process_time() >= 1200:
            raise RuntimeError('regional benchmark incomplete or over cap')
        share = min(1.0, 0.75 * cpu_time / wall)
        estimates = p.prospective_costs(prep['packages'], prep['tasks'], rows, prep['control'], prep['control'], c['audit_key'], startup_cpu, share, 1.5)['task_estimates']
        price = self.prefix_contract(prep, estimates, c['max_projected_cpu_seconds'] * share)
        price.update(task_estimates=estimates, source=prep['source'], preparation_sha256=digest(self.PREP / 'preparation.json'), status='ADMITTED_COMPLETE_D_AND_WORST_S0_PREFIX' if price['prefix_admitted'] else 'DEFERRED_UNFUNDED_COMPLETE_PREFIX', finite_three_wave_CPU_ceiling=c['max_projected_cpu_seconds'], contingency_factor=1.5, resource_projection=dict(
            effective_cpu_share=cpu_time / wall,
            conservative_idle_share=share,
            max_chunk_wall_seconds=max((v['estimated_max_chunk_wall_seconds'] for v in estimates.values())),
            max_observed_chunk_wall_seconds=max((v['arithmetic_wall_seconds'] + v['serialization_wall_seconds'] for v in rows)),
        ), no_new_candidate_AQL_inspected=True, no_automatic_budget_expansion=True, independent_regional_benchmark=True)
        replay_calls = sum((row['original_control_replay'] is not None for row in rows))
        write(attempt / 'timings.json', dict(
            status='R151_FIXED_TIMINGS_COMPLETE_NO_SELECTION_LOSS',
            rows=rows,
            arithmetic_calls=expected + replay_calls,
            timed_prediction_calls=expected,
            untimed_control_replay_prediction_calls=replay_calls,
            elapsed_seconds=wall,
            process_CPU_seconds=cpu_time,
            numerical_preflight=preflight,
            delivered_effective_cores=cpu_time / wall,
            new_model_fits=0,
            no_new_candidate_AQL_computed=True,
            forecast_paths=100,
            source=prep['source'],
            serialization_schema='retained standardized/EUR/identity NPZ with explicit zero origin_AQL; no loss computed',
        ))
        write(attempt / 'branch.json', price)
        write(attempt / 'completed_evidence.json', dict(context=dict(source=prep['source'], preparation_sha256=digest(self.PREP / 'preparation.json')), artifacts={v: digest(attempt / v) for v in ['timings.json', 'branch.json'] + [row['retained_prediction_packet'] for row in rows]}))
        if (self.OUT / 'benchmark').exists():
            raise RuntimeError('existing regional benchmark requires strict review')
        os.rename(attempt, self.OUT / 'benchmark')
        beat(dict(status='completed', timed_prediction_calls=expected, arithmetic_calls=expected + replay_calls))
        return price

    def validate_resource_budget_disposition(self, value):
        """Preserve the scientific gate while deferring its entire extra set.

        An independently pinned resource decision can close a fully verified
        D/S0 prefix only when no member of the qualified extra set was started.
        A partial extra set remains incomplete, even if its packets were lost.
        """
        prep = self.read_preparation()
        extra = self.read_decision('extra_seeds')
        expected = extra['required_extra_components']
        if (not isinstance(value, dict) or not expected
                or extra.get('atomic_qualified_set_admitted') is not True
                or extra.get('unfunded_pending')
                or extra.get('admitted_extra_components') != expected
                or value.get('study') != self.study_id
                or value.get('source') != prep['source']
                or value.get('components') != expected
                or value.get('admitted') is not False):
            raise RuntimeError('resource disposition must defer exact scientifically admitted extra set')
        for name in expected:
            evidence = (
                self.OUT / 'tasks_done' / name,
                self.OUT / 'cpu_accounting' / name,
                self.OUT / 'checkpoints' / name,
                self.OUT / 'attempts' / name,
                self.OUT / 'heartbeats' / (name + '.json'),
            )
            if self.task_complete(name) or any(path.exists() for path in evidence):
                raise RuntimeError('resource-unfunded extra set already has numerical attempt evidence')
        return value

    def resource_budget_disposition(self, receipt):
        """Read only the canonical request pinned into the assessment lease."""
        verify_hashes({receipt['admission_path']: receipt['admission_sha256'],
                       receipt['master_path']: receipt['master_sha256']})
        lease = read(receipt['admission_path'])
        runtime = Path(receipt['master_path']).parent / 'development'
        request_path = runtime / 'studies' / self.study_id / 'assessment_request.json'
        if (lease.get('assessment_request_path') != str(request_path)
                or lease.get('assessment_request_sha256') != digest(request_path)):
            raise RuntimeError('assessment request is not pinned to the owned admission')
        request = read(request_path)
        if request.get('active_workers') != [] or request.get('cleanup_preassessment_verified') is not True:
            raise RuntimeError('regional assessment request lacks a drained prefix')
        if not request.get('resource_disposition_path'):
            return None
        path = runtime / 'studies' / self.study_id / 'extras_resource_admission.json'
        if (request.get('resource_disposition_path') != str(path)
                or request.get('resource_disposition_sha256') != digest(path)):
            raise RuntimeError('resource disposition path or hash differs')
        resource = read(path)
        if resource.get('admitted') is True:
            return None
        expected = self.read_decision('extra_seeds')['required_extra_components']
        if (request.get('entire_extra_set_unfunded_pending') is not True
                or request.get('unfunded_components') != expected
                or resource.get('components') != expected
                or resource.get('admitted') is not False):
            raise RuntimeError('assessment request does not preserve the whole qualified extra set')
        value = dict(resource, study=self.study_id, source=self.read_preparation()['source'],
                     resource_disposition_path=str(path), resource_disposition_sha256=digest(path),
                     assessment_request_path=str(request_path), assessment_request_sha256=digest(request_path))
        for ownership in (runtime / 'attempts' / self.study_id).glob('*/ownership.json'):
            if read(ownership)['task'] in expected:
                raise RuntimeError('resource-unfunded extra set has a canonical owned numerical attempt')
        return self.validate_resource_budget_disposition(value)

    def finalize(self, budget_disposition=None, guard=None):
        prep = self.read_preparation()
        p = self.producer()
        phase, names, unfunded, terminal = self.manifest_state()
        resource_pending = budget_disposition is not None
        if resource_pending:
            self.validate_resource_budget_disposition(budget_disposition)
            if phase != 'MATCHED_FULL_MC':
                raise RuntimeError('resource-only extra deferral requires completed D and matched S0')
            unfunded = list(budget_disposition['components'])
        if phase == 'DEFERRED_UNFUNDED_PREFIX':
            result = dict(
                status=self.status('DEFERRED_UNFUNDED_COMPLETE_PREFIX'),
                source=prep['source'],
                region=self.region,
                pricing=self.pricing(),
                scientific_complete=False,
                new_model_fits=0,
                promotion_authorized=False,
                automatic_followon_admitted=False,
            )
        else:
            pending_extra = phase == 'MATCHED_MC_UNFUNDED_PENDING' or resource_pending
            if not terminal and (not pending_extra) or (unfunded and (not pending_extra)):
                raise RuntimeError('regional science incomplete: ' + phase)
            verify_hashes(prep['source_sha256'])
            verify_hashes(prep['input_sha256'])
            verification = []
            verify_names = [name for name in names if name not in unfunded]
            if pending_extra:
                expected = self.names_for([v['package_id'] for v in prep['packages']], 'D', [0])
                expected += self.names_for([prep['control']] + self.read_decision('nominees')['nominees'], 'S', [0])
                if set(verify_names) != set(expected):
                    raise RuntimeError('clean budget disposition requires full D and matched S0')
            for name in verify_names:
                if guard is not None:
                    guard()
                if not self.task_complete(name):
                    raise RuntimeError('required regional component missing')
                task = self.task_by_name(name, prep)
                arrays = p.read_npz(self.OUT / 'tasks_done' / name / 'predictions.npz')
                p.validate_arrays(task, arrays, read(task['scaler_path']))
                measured = p.metrics(arrays)
                recorded = read(self.OUT / 'tasks_done' / name / 'result.json')['metrics']
                if any((not math.isclose(measured[k], recorded[k], rel_tol=1e-11, abs_tol=1e-10) for k in measured)):
                    raise RuntimeError('independent regional metric replay differs')
                verification.append(dict(name=name, metrics=measured))
            extra = self.read_decision('extra_seeds')
            confirmed = {}
            proposal = None
            lead = None
            if not pending_extra:
                control = [self.component_loss(prep['control'], 'S', seed) for seed in (0, 1, 2)] if extra['qualified'] else []
                for nominee in extra['qualified']:
                    candidate = [self.component_loss(nominee, 'S', seed) for seed in (0, 1, 2)]
                    confirmed[nominee] = dict(p.confirm_gains(control, candidate), control_AQL_by_seed=control, candidate_AQL_by_seed=candidate)
                eligible = {name: -row['mean_gain'] for name, row in confirmed.items() if row['eligible_for_AL_proposal']}
                lead = p.strongest(eligible) if eligible else None
                if lead:
                    package = next((v for v in prep['packages'] if v['package_id'] == lead))
                    actual = next((v for v in prep['packages'] if v['package_id'] == prep['control']))
                    proposal = dict(
                        package_id=lead,
                        cached_candidate_AL_fits_to_verify=42 if package['candidate_id'] == actual['candidate_id'] else 0,
                        new_candidate_fits_if_exact_identity_reused=0 if package['candidate_id'] == actual['candidate_id'] else 21,
                        forecast_components=18,
                        paths=500,
                        default_iterations=300,
                        operator='cdf_pool_clipped',
                        same_package_Normal_driver_and_AL_receiver=True,
                        launched=False,
                        separate_budget_required=True,
                    )
            result = dict(
                status=self.status('FINITE_BUDGET_DEFERRED_MATCHED_EXTRAS') if pending_extra else self.status('SCIENTIFICALLY_COMPLETE_NOT_PROMOTED'),
                source=prep['source'],
                region=prep['region'],
                scientific_complete=not pending_extra,
                all_D_and_matched_S0_complete=True,
                entire_extra_set_unfunded_pending=pending_extra,
                required_components=len(names),
                verified_components=len(verification),
                verification=verification,
                nominations=self.read_decision('nominees'),
                extra_seed_decision=extra,
                resource_extra_seed_disposition=budget_disposition,
                matched_three_seed_results=confirmed,
                conditional_AL_proposal=proposal,
                new_model_fits=0,
                official_test_opened=False,
                independent_confirmation=False,
                automatic_followon_admitted=False,
                promotion_authorized=False,
                disposition='CLEAN_FINITE_BUDGET_DEFERRAL_NO_STABLE_LEAD_CLAIM' if pending_extra else 'ONE_CONDITIONAL_AL_PROPOSAL_NOT_ADMITTED' if lead else 'STOP_NO_STABLE_PRACTICAL_LEAD',
            )
        result['execution_resource_source'] = self.execution_identity()
        if guard is not None:
            guard()
        immutable(self.OUT / 'assessment.json', result)
        immutable(self.OUT / 'assessment_seal.json', dict(sha256=digest(self.OUT / 'assessment.json'), source=prep['source']))
        return result

    def metadata_audit(self):
        value = self.build_preparation(dict(head='METADATA_AUDIT_NO_RELEASE', branch=read(self.CONFIG)['required_branch']))
        return dict(
            status='PASS_REGIONAL_METADATA_NO_FORECAST_OR_DATA_WRITES',
            packages=len(value['packages']),
            potential_components=len(value['tasks']),
            source_pins=len(value['source_sha256']),
            input_pins=len(value['input_sha256']),
            cohort_audit=value['cohort_audit'],
            new_model_fits=0,
            numerical_imports=[n for n in ('numpy', 'pandas', 'scipy') if n in sys.modules],
        )

    def __init__(self, config_path=None, prep_dir=None, out_dir=None):
        self.CONFIG = Path(config_path or CONFIG)
        self.c = read(self.CONFIG)
        self.region = self.c['region']
        self.legacy = self.region == 'DK_2'
        self.TAG = self.c['tag']
        self.PREP = Path(prep_dir) if prep_dir else DATA / 'launch_prep' / self.TAG
        self.OUT = Path(out_dir) if out_dir else DATA / 'campaigns' / self.TAG
        self._PRODUCER = None
        self._PREPARATION = {}
        self._COMPLETE = {}
        self._REFERENCE = None
        self._last_source_check = -float('inf')
        self.validate_config(self.c)

    @property
    def study_id(self):
        return 'DK2' if self.legacy else self.region

    def status(self, suffix):
        return ('R151_REGION_' if self.legacy else 'R152_REGION_') + suffix

    def config(self):
        current = read(self.CONFIG)
        if current != self.c:
            raise RuntimeError('study configuration changed after adapter construction')
        return self.validate_config(current)

    def legacy_reference(self):
        if self._REFERENCE is None:
            if self.legacy:
                path = Path(self.CONFIG).parents[2] / 'application/scripts/pricefm/502_screen_pricefm_stage_r151_region.py'
                expected = read(CONFIG)['legacy_reference_sha256']
            else:
                path = Path(self.c['legacy_reference_entry'])
                expected = self.c['legacy_reference_sha256']
            verify_hashes({str(path): expected})
            spec = importlib.util.spec_from_file_location('r152_immutable_regional_reference_' + fingerprint(str(path))[:12], path)
            self._REFERENCE = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self._REFERENCE)
        return self._REFERENCE

    def execution_identity(self):
        required = 'work/pricefm-r152-parallel-recovery-20261024'
        if git(ROOT, 'branch', '--show-current') != required or git(ROOT, 'status', '--porcelain'):
            raise RuntimeError('clean committed dedicated R152 execution source required')
        return dict(head=git(ROOT, 'rev-parse', 'HEAD'), branch=required)

    def numeric_preflight(self, prep, receipt, beat):
        import numpy as np
        records = []
        for package in prep['packages']:
            for split in (1, 2, 3):
                if time.time() >= receipt['lease_expires_epoch'] or time.process_time() >= 1200:
                    raise RuntimeError('combined numerical preflight/benchmark allowance exhausted')
                task = self.task_by_name(self.name_for(package['package_id'], split, 'D', 0), prep)
                beat(dict(status='numerical_preflight', package_id=package['package_id'], split=split))
                context = self.producer().numerical_context(prep, task)
                fit = context['fit']
                p = task['p']
                mean = np.asarray(fit['beta_mean'])
                cov = np.asarray(fit['beta_cov'])
                if mean.shape != (p,) or cov.shape != (p, p) or (not np.isfinite(mean).all()) or (not np.isfinite(cov).all()):
                    raise RuntimeError('cached posterior moments malformed/nonfinite')
                scale = max(1.0, float(np.max(np.abs(cov))))
                if not np.allclose(cov, cov.T, rtol=1e-10, atol=1e-12 * scale):
                    raise RuntimeError('cached covariance asymmetric')
                smallest = float(np.linalg.eigvalsh((cov + cov.T) * 0.5)[0])
                if smallest < -1e-10 * scale or np.any(np.diag(cov) < 0):
                    raise RuntimeError('cached covariance not positive semidefinite')
                for key in ('omega_shape', 'omega_rate'):
                    if key in fit and (not math.isfinite(float(fit[key])) or fit[key] <= 0):
                        raise RuntimeError('invalid cached omega moments')
                records.append(dict(name=task['parent_task'], p=p, minimum_covariance_eigenvalue=smallest, scaler_sha256=task['scaler_sha256'], posterior_moments_unchanged=True))
                del context
        return dict(status='PASS_ALL_CACHED_MOMENTS_UNDER_BENCHMARK_LEASE', parents=len(records), records=records, new_model_fits=0, no_candidate_AQL_computed=True)

    def worker_command(self, name, cpu, policy_receipt, python=None):
        return [str(python or sys.executable), '-B', str(ENTRY), 'worker', '--study', self.study_id, '--config', str(self.CONFIG), '--prep', str(self.PREP), '--out', str(self.OUT), '--name', name, '--cpu', str(cpu), '--policy-receipt', str(policy_receipt)]

    def execution_bridge_path(self):
        return DATA / 'launch_prep/pricefm_stage_r152_parallel_20261024/development/science_bridges/DK2.json'

    def stop_requested(self, receipt, policy_path, name):
        return bool(receipt.get('stop_request_path') and Path(receipt['stop_request_path']).exists()) or (Path(policy_path).parent / 'stop_requests' / (name + '.json')).exists()

def open_study(study='FI', config_path=None, prep_dir=None, out_dir=None):
    if study not in ('FI', 'DK2', 'DK_2'):
        raise ValueError('only FI and prepared DK2 are admitted')
    if config_path is None:
        config_path = CONFIG if study == 'FI' else read(CONFIG)['legacy_DK2_config']
    value = Study(config_path, prep_dir, out_dir)
    if value.study_id != ('DK2' if study == 'DK_2' else study):
        raise ValueError('study/config region mismatch')
    return value

def read_config(study='FI', config_path=None):
    return open_study(study, config_path).config()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'status', 'advance', 'worker', 'finalize', 'metadata-audit'])
    parser.add_argument('--study', choices=['FI', 'DK2'], default='FI')
    parser.add_argument('--config', type=Path)
    parser.add_argument('--prep', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--name')
    parser.add_argument('--cpu', type=int)
    parser.add_argument('--policy-receipt', type=Path)
    parser.add_argument('--remaining-CPU-seconds', type=float)
    args = parser.parse_args()
    study = open_study(args.study, args.config, args.prep, args.out)
    if args.action == 'prepare':
        value = study.prepare()
    elif args.action == 'status':
        value = study.queue_state()
    elif args.action == 'advance':
        value = study.advance(args.remaining_CPU_seconds)
    elif args.action in ('worker', 'finalize'):
        name = '__finalize__' if args.action == 'finalize' else args.name
        if name is None or args.cpu is None or args.policy_receipt is None:
            parser.error('owned worker requires name/cpu/policy receipt')
        value = study.worker(name, args.cpu, args.policy_receipt)
    else:
        value = study.metadata_audit()
    print(json.dumps(value, sort_keys=True, allow_nan=False), flush=True)
if __name__ == '__main__':
    main()
