"""Whole-component reference/instrumented replay under distinct PROFILE authority.

Import is standard-library only. Numerical execution requires a reviewed new
authority, compute-node attestation and two fresh interpreters. Frozen scientific
functions and their arithmetic are never edited or monkeypatched.
"""
from __future__ import annotations

import argparse
import ast
import builtins
from contextlib import contextmanager
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import signal
import stat
import subprocess
import sys
import symtable
import time
from types import SimpleNamespace
import zipfile

from . import execution_profile_plan as planning
from . import prefix as p, benchmark as b, registry as r
from .environment import THREAD_ENV, REFERENCE_NUMERICAL_ENV, require_compute
from .science import _assert_frozen_imports

SCHEMA = 'r164_actual_component_profile_request_v1'
PURPOSE = 'ACTUAL_COMPONENT_PROFILE'
ORDER = ['reference', 'instrumented']
REQUEST_KEYS = {'schema', 'purpose', 'profile_plan', 'cost_plan', 'policy', 'study',
                'task', 'task_sha256', 'stage_root', 'execution_order', 'storage_mode'}
MAX_METADATA = 16 * 1024**2
COMPONENT_LOOP_AST = '9b466b16f5d39890892a629c02ddf9069024a8c16ca22274e628a751231e234a'
COMPONENT_LOOP_GLOBALS = {'Path', 'PrefixError', 'RESULT_SCHEMA', 'finite', 'len', 'r', 'seal_directory', 'time'}
PHASES = ('startup_and_authority', 'input_verification', 'runtime_and_adapter_setup',
          'parent_context_load', 'arithmetic', 'retained_array_conversion',
          'chunk_validation', 'chunk_serialization',
          'concatenation_full_validation_metrics', 'full_serialization',
          'sealing_and_final_accounting', 'cleanup', 'component_orchestration',
          'reference_component', 'pair_orchestration', 'parity_verification')
ADDITIVE = ('self_CPU', 'waited_children_CPU', 'wall', 'read_bytes', 'write_bytes',
            'read_characters', 'write_characters', 'minor_faults', 'major_faults',
            'voluntary_context_switches', 'involuntary_context_switches')


def require(ok, message):
    if not ok:
        raise ValueError(message)


def finite(value, positive=False):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0 and (not positive or value > 0)


def bounded_read(path, maximum=MAX_METADATA):
    path = planning.physical(path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        require(stat.S_ISREG(before.st_mode) and before.st_uid == os.getuid()
                and 0 <= before.st_size <= maximum, 'owned bounded regular file required')
        data = bytearray()
        while len(data) <= maximum:
            block = os.read(fd, min(1024**2, maximum + 1 - len(data)))
            if not block:
                break
            data.extend(block)
        require(len(data) == before.st_size and fingerprint(os.fstat(fd)) == fingerprint(before), 'file changed during read')
        require(fingerprint(path.stat()) == fingerprint(before), 'file changed after read')
        planning.physical(path)
        return bytes(data)
    finally:
        os.close(fd)


def fingerprint(value):
    return (value.st_dev, value.st_ino, value.st_mode, value.st_uid,
            value.st_size, value.st_mtime_ns, value.st_ctime_ns)


def read_pin(pin):
    require(type(pin) is dict and set(pin) == {'path', 'sha256'}, 'exact metadata pin required')
    require(type(pin['sha256']) is str and len(pin['sha256']) == 64
            and set(pin['sha256']) <= set('0123456789abcdef'), 'SHA256 required')
    require(Path(pin['path']).suffix == '.json', 'JSON metadata pin required')
    data = bounded_read(pin['path'])
    require(hashlib.sha256(data).hexdigest() == pin['sha256'], 'changed pinned metadata')
    return planning.decode_json(data)


def write_new(path, value):
    planning.write_new(Path(path), value)


def source_closure():
    result = p.executed_sources()
    for name in ('execution_profile.py', 'execution_profile_plan.py', 'profile_admission.py'):
        path = Path(__file__).with_name(name)
        result[name] = hashlib.sha256(bounded_read(path)).hexdigest()
    return result


def validate_request(request):
    require(type(request) is dict and set(request) == REQUEST_KEYS, 'exact actual-profile request required')
    require(request['schema'] == SCHEMA and request['purpose'] == PURPOSE,
            'distinct actual-component PROFILE purpose required')
    require(request['study'] in ('FI', 'DK2') and type(request['task']) is str
            and request['execution_order'] == ORDER
            and request['storage_mode'] == 'DIRECT_RETAINED_SOURCE',
            'fixed paired full-component order/direct retained source required')
    planning.physical(request['stage_root'])
    profile = read_pin(request['profile_plan'])
    require(profile.get('schema') == planning.SCHEMA and profile.get('status') == 'PREPARED_NOT_ADMITTED'
            and profile.get('full_screening_admitted') is False
            and profile.get('numerical_execution_authorized') is False,
            'original non-admitting R163 profile contract required')
    cost = read_pin(request['cost_plan'])
    require(request['cost_plan']['sha256'] == profile['input_pins']['studies'][request['study']]['cost_plan']['sha256'],
            'original cost-plan pin differs from full R163 universe')
    require(request['cost_plan']['sha256'] == planning.CANONICAL[request['study']]['cost_plan']
            and {role: ref['sha256'] for role, ref in profile['source_pins'].items()} == planning.SOURCE_HASHES,
            'accepted original source/cost closure changed')
    require(cost.get('study') == request['study'], 'profile study/cost mismatch')
    entries = [t for t in profile['studies'][request['study']]['tasks'] if t['name'] == request['task']]
    require(len(entries) == 1 and entries[0]['task_sha256'] == request['task_sha256']
            and entries[0]['imported'] is False, 'exact non-imported complete canonical task required')
    read_pin(request['policy'])
    return profile, cost, entries[0]


def read_proc(path, maximum=65536):
    with open(path, 'rb', buffering=0) as handle:
        value = handle.read(maximum + 1)
    require(len(value) <= maximum, 'bounded process evidence required')
    return value.decode()


def snapshot():
    own = resource.getrusage(resource.RUSAGE_SELF)
    children = resource.getrusage(resource.RUSAGE_CHILDREN)
    io = dict(line.split(':', 1) for line in read_proc('/proc/self/io').splitlines())
    status = dict(line.split(':', 1) for line in read_proc('/proc/self/status').splitlines() if ':' in line)
    return dict(self_CPU=own.ru_utime + own.ru_stime,
        waited_children_CPU=children.ru_utime + children.ru_stime, wall=time.monotonic(),
        read_bytes=int(io['read_bytes']), write_bytes=int(io['write_bytes']),
        read_characters=int(io['rchar']), write_characters=int(io['wchar']),
        minor_faults=own.ru_minflt + children.ru_minflt,
        major_faults=own.ru_majflt + children.ru_majflt,
        voluntary_context_switches=own.ru_nvcsw + children.ru_nvcsw,
        involuntary_context_switches=own.ru_nivcsw + children.ru_nivcsw,
        self_peak_RSS_KiB=own.ru_maxrss, waited_child_peak_RSS_KiB=children.ru_maxrss,
        self_current_RSS_KiB=int(status['VmRSS'].strip().split()[0]),
        epoch=time.time())


def process_start_wall():
    # Linux starttime is field22; executable names may contain spaces or ')'.
    fields = read_proc('/proc/self/stat').rsplit(')', 1)[1].split()
    ticks = int(fields[19]) / os.sysconf('SC_CLK_TCK')
    elapsed = time.clock_gettime(time.CLOCK_BOOTTIME) - ticks
    require(finite(elapsed), 'process start clock invalid')
    return time.monotonic() - elapsed


def delta(before, after):
    result = {key: after[key] - before[key] for key in ADDITIVE}
    require(all(finite(v) for v in result.values()), 'nonmonotonic accounting counter')
    return result


class Meter:
    """Nested exclusive counters. RSS is a high-water observation, never summed."""
    def __init__(self, clock=snapshot, sink=None):
        self.clock, self.sink = clock, sink
        self.start = clock(); self.stack = []; self.events = []

    @contextmanager
    def phase(self, name):
        require(name in PHASES, 'unknown lifecycle phase')
        frame = {'phase': name, 'before': self.clock(), 'children': {k: 0 for k in ADDITIVE}}
        self.stack.append(frame)
        failed = True
        try:
            yield
            failed = False
        finally:
            after = self.clock(); inclusive = delta(frame['before'], after)
            require(self.stack.pop() is frame, 'phase stack corrupted')
            exclusive = {k: inclusive[k] - frame['children'][k] for k in ADDITIVE}
            require(all(v >= -1e-8 for v in exclusive.values()), 'overlapping phase attribution')
            exclusive = {k: max(0, v) for k, v in exclusive.items()}
            if self.stack:
                for k in ADDITIVE:
                    self.stack[-1]['children'][k] += inclusive[k]
            event = dict(phase=name, failed=failed, before=frame['before'], after=after,
                         inclusive=inclusive, exclusive=exclusive)
            require(len(self.events) < 10000, 'bounded phase event limit')
            self.events.append(event)
            if self.sink:
                self.sink(event)

    def wrap(self, name, function):
        def measured(*args, **kwargs):
            with self.phase(name):
                return function(*args, **kwargs)
        return measured

    def report(self):
        require(not self.stack, 'unfinished phase cannot complete')
        end = self.clock(); total = delta(self.start, end)
        attributed = {k: sum(e['exclusive'][k] for e in self.events) for k in ADDITIVE}
        residual = {k: total[k] - attributed[k] for k in ADDITIVE}
        require(all(v >= -1e-7 for v in residual.values()), 'phase attribution exceeds whole process')
        return dict(start=self.start, end=end, interval_total=total, disjoint_attributed=attributed,
            unattributed_residual={k: max(0, v) for k, v in residual.items()}, events=self.events,
            pre_meter_CPU_including_interpreter_imports=self.start['self_CPU'] + self.start['waited_children_CPU'],
            lifetime_CPU_at_snapshot=end['self_CPU'] + end['waited_children_CPU'],
            final_receipt_publication_tail_in_canonical_Slurm_charge=True,
            RSS_policy='before/after current and process high-water; not additive; aggregate peak needs Slurm/cgroup evidence',
            phase_counter_scope='self and waited children only; live workers are separately bounded; no assumed CPU discount')


class ProfileBudget:
    def __init__(self, limits, expires_epoch, *, remaining_CPU=None, remaining_wall=None):
        require(type(limits) is dict and set(limits) == {'aggregate_cpu_seconds', 'wall_seconds', 'memory_MiB'},
                'exact distinct paired limit fields required')
        for key in ('aggregate_cpu_seconds', 'wall_seconds', 'memory_MiB'):
            require(finite(limits.get(key), True), 'finite PROFILE-specific resource limits required')
        require(type(limits['memory_MiB']) is int and 1024 <= limits['memory_MiB'] <= 8192
                and type(limits['wall_seconds']) is int and limits['wall_seconds'] <= 5400
                and limits['aggregate_cpu_seconds'] <= 2000,
                'one physical worker and finite memory required')
        self.cpu_cap = limits['aggregate_cpu_seconds']
        if remaining_CPU is not None:
            require(finite(remaining_CPU, True) and remaining_CPU <= self.cpu_cap,
                    'child cannot expand remaining pair CPU')
            self.cpu_cap = remaining_CPU
        whole_deadline = process_start_wall() + limits['wall_seconds']
        if remaining_wall is not None:
            require(finite(remaining_wall, True) and remaining_wall <= limits['wall_seconds'],
                    'child cannot expand remaining pair wall')
            whole_deadline = min(whole_deadline, time.monotonic() + remaining_wall)
        self.deadline = min(whole_deadline, time.monotonic() + expires_epoch - time.time())
        self.memory_MiB = limits['memory_MiB']

    def used_CPU(self):
        return b.aggregate_cpu_seconds()

    def check(self):
        if self.used_CPU() >= self.cpu_cap or time.monotonic() >= self.deadline:
            raise TimeoutError('whole PROFILE pair allowance exhausted; retain failure; no automatic retry')

    def install(self):
        self.check()
        self.install_cpu_backstop()
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        def expired(*_):
            raise TimeoutError('hard prospective PROFILE CPU/wall boundary')
        signal.signal(signal.SIGALRM, expired); signal.signal(signal.SIGXCPU, expired)
        signal.setitimer(signal.ITIMER_REAL, self.deadline - time.monotonic())

    def install_cpu_backstop(self):
        # RLIMIT_CPU applies to SELF, not the cumulative job. After each waited
        # child, reduce the parent's SELF hard limit by that child's exact CPU.
        # Floor conservatively: a fractional remaining grant never rounds up.
        children = resource.getrusage(resource.RUSAGE_CHILDREN)
        cap = math.floor(self.cpu_cap - children.ru_utime - children.ru_stime)
        require(cap > time.process_time(), 'insufficient whole-pair CPU for conservative hard backstop')
        old = resource.getrlimit(resource.RLIMIT_CPU)
        if old[1] != resource.RLIM_INFINITY:
            cap = min(cap, old[1])
        resource.setrlimit(resource.RLIMIT_CPU, (cap, cap))


def context_evidence():
    return dict(affinity=sorted(os.sched_getaffinity(0)), cgroup=read_proc('/proc/self/cgroup'),
                process_status=read_proc('/proc/self/status'), pid=os.getpid(), ppid=os.getppid(),
                process_start_ticks=int(read_proc('/proc/self/stat').rsplit(')', 1)[1].split()[19]),
                proc_self_uid=os.getuid(),
                process_start_monotonic=process_start_wall(), interpreter=sys.executable,
                thread_environment={k: os.environ.get(k) for k in {**THREAD_ENV, **REFERENCE_NUMERICAL_ENV}})


def gate(request_path, authority_path, attestation_path, role):
    allocation = require_compute()
    require(sys.dont_write_bytecode, 'fresh -B compute interpreter required')
    require(all(os.environ.get(k) == v for k, v in {**THREAD_ENV, **REFERENCE_NUMERICAL_ENV}.items()),
            'qualified original one-thread native profile required')
    request_bytes = bounded_read(request_path); request = planning.decode_json(request_bytes)
    profile, cost, entry = validate_request(request)
    authority_bytes = bounded_read(authority_path); attestation_bytes = bounded_read(attestation_path)
    from . import profile_admission
    sources = source_closure()
    require(all(sources[name + '.py'] == digest for name, digest in planning.SOURCE_HASHES.items()),
            'actual frozen scientific wrappers differ from R163 source contract')
    reviewed = profile_admission.validate_worker(request=request,
        request_sha256=hashlib.sha256(request_bytes).hexdigest(),
        authority=planning.decode_json(authority_bytes), authority_sha256=hashlib.sha256(authority_bytes).hexdigest(),
        attestation=planning.decode_json(attestation_bytes), attestation_sha256=hashlib.sha256(attestation_bytes).hexdigest(),
        allocation=allocation, executed_sources=sources, role=role, now=time.time())
    require(type(reviewed) is dict and set(('limits', 'expires_epoch', 'scope_id', 'parity_runtime', 'output_root')) <= set(reviewed),
            'complete reviewed PROFILE gate result required')
    require(finite(reviewed['expires_epoch'], True) and reviewed['expires_epoch'] > time.time()
            and type(reviewed['scope_id']) is str and bool(reviewed['scope_id']), 'finite active distinct scope required')
    b.validate_actual_runtime(reviewed['parity_runtime'])
    return request, profile, cost, entry, reviewed, allocation


def event_sink(path):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    handle = os.fdopen(fd, 'wb')
    def append(event):
        handle.write((json.dumps(event, sort_keys=True, allow_nan=False) + '\n').encode())
        handle.flush(); os.fsync(handle.fileno())
    return append, handle


def instrument_adapter(adapter, meter):
    return SimpleNamespace(context=meter.wrap('parent_context_load', adapter.context),
        predict=meter.wrap('arithmetic', adapter.predict),
        retained_arrays=meter.wrap('retained_array_conversion', adapter.retained_arrays),
        cleanup=meter.wrap('cleanup', adapter.cleanup), pools=adapter.pools)


def instrumented_component_loop(meter):
    """Execute the unchanged AST with one explicit, timed seal dependency.

    No module/global/code object is patched. This is the same private-namespace
    extraction pattern as the accepted frozen scientific function adapters.
    """
    source = bounded_read(Path(p.__file__)).decode()
    require(hashlib.sha256(source.encode()).hexdigest() == planning.SOURCE_HASHES['prefix'],
            'frozen prefix source changed')
    nodes = [n for n in ast.parse(source).body if isinstance(n, ast.FunctionDef) and n.name == 'component_loop']
    require(len(nodes) == 1 and not nodes[0].decorator_list, 'one frozen component function required')
    node = nodes[0]
    require(hashlib.sha256(ast.dump(node, include_attributes=False).encode()).hexdigest() == COMPONENT_LOOP_AST,
            'frozen whole-component AST changed')
    table = symtable.symtable(ast.get_source_segment(source, node), p.__file__, 'exec').get_children()[0]
    from .science import _referenced_globals
    require(_referenced_globals(table) == COMPONENT_LOOP_GLOBALS, 'frozen whole-component global surface changed')
    bindings = dict(Path=Path, PrefixError=p.PrefixError, RESULT_SCHEMA=p.RESULT_SCHEMA, finite=p.finite,
        len=builtins.len, r=r, time=time, seal_directory=meter.wrap('sealing_and_final_accounting', p.seal_directory))
    namespace = dict(bindings, __builtins__={'len': len})
    exec(compile(ast.Module(body=[node], type_ignores=[]), p.__file__, 'exec'), namespace)
    return namespace['component_loop']


def expected_component(cost, request):
    """Bind parity to the canonical metadata, not two self-consistent outputs."""
    assets = {path: dict(entry, path=entry['staged_relative_path']) for path, entry in cost['input_allowlist'].items()}
    resolver = b.Resolver(request['stage_root'], dict(assets=assets))
    pin = cost['canonical_preparation']
    prep = read_pin(dict(path=str(planning.physical(resolver.path(pin['path']))), sha256=pin['sha256']))
    tasks = [t for t in prep['tasks'] if t['name'] == request['task']]
    require(len(tasks) == 1 and r.identity(tasks[0]) == request['task_sha256'], 'canonical expected task changed')
    task = tasks[0]
    contract = p.load_contract(resolver)
    descriptors = p.original('chunks', resolver=resolver)(task)
    context = p.original('context_identity', resolver=resolver)(task, prep)
    def shapes(n):
        return {key: dict(dtype='<i8' if key in b.RETAINED_INT_KEYS else '<f8', shape=list(value))
                for key, value in contract.array_shapes(n).items()}
    packets = {'predictions.npz': shapes(4 * len(task['daily_origin_positions']))}
    identities = {}
    for descriptor in descriptors:
        path = 'checkpoints/' + descriptor['name'] + '/predictions.npz'
        packets[path] = shapes(len(descriptor['origin_positions']))
        identities[path] = dict(context=context, descriptor=descriptor)
    return dict(expected_packets=packets, expected_chunk_identities=identities,
        expected_result=dict(schema=p.RESULT_SCHEMA, name=task['name'], source=prep['source'], mode=task['mode'],
            scientific_identity_sha256=task['scientific_identity_sha256'], task_sha256=r.identity(task),
            origin_clock_windows=4 * len(task['daily_origin_positions']), chunk_count=len(descriptors),
            certified=True, new_model_fits=0, posterior_updated=False, test_opened=False,
            promotion_authorized=False, equal_origin_clock_weights=True, units='EUR/MWh'))


def execute_component(request_path, authority_path, attestation_path, output, role, remaining_CPU, remaining_wall):
    require(role in ORDER, 'fixed pair child role required')
    meter = Meter()
    with meter.phase('startup_and_authority'):
        request, profile, cost, entry, admission, allocation = gate(request_path, authority_path, attestation_path, role)
        budget = ProfileBudget(admission['limits'], admission['expires_epoch'],
                               remaining_CPU=remaining_CPU, remaining_wall=remaining_wall)
        budget.install()
        output = planning.physical(output)
        require(output == Path(admission['output_root']) / role, 'exact authorized pair child output required')
        require('ACTUAL_COMPONENT_PROFILE' in output.parts, 'separate owned PROFILE namespace required')
        output.mkdir(parents=True, exist_ok=False)
        sink, journal = event_sink(output / 'phase_events.jsonl'); meter.sink = sink
    try:
        with meter.phase('input_verification'):
            prep, config, resolver = b.load_staged(cost, request['stage_root'])
            tasks = [t for t in prep['tasks'] if t['name'] == request['task']]
            require(len(tasks) == 1 and r.identity(tasks[0]) == request['task_sha256'], 'complete staged task changed')
            task = tasks[0]
            require(task['reuse'] is None and task['scientific_identity_sha256']
                    == r.identity(p.original('task_identity', resolver=resolver)(task)), 'task scientific identity changed')
        with meter.phase('runtime_and_adapter_setup'):
            adapter = b.frozen_adapter(cost, prep, config, resolver, budget,
                                      admission['parity_runtime']['native_library_sha256'])
            contract = p.load_contract(resolver)
            import numpy as np
            def light(arrays):
                return {k: (tuple(v.shape), v.ravel().tolist()) for k, v in arrays.items()}
            def validate(t, arrays, scaler, descriptor):
                contract.validate_arrays(t, light(arrays), scaler, descriptor)
            def concatenate(parts):
                return {k: np.ascontiguousarray(np.concatenate([v[k] for v in parts]),
                        dtype='<i8' if k in b.RETAINED_INT_KEYS else '<f8') for k in contract.array_shapes(1)}
            def serializer(path, arrays):
                np.savez_compressed(path, **arrays)
            metric = lambda arrays: contract.metrics(light(arrays))
            chunks = p.original('chunks', resolver=resolver)
            context_identity = p.original('context_identity', resolver=resolver)
            executed = dict(role=role, task=task['name'], task_sha256=r.identity(task),
                source=prep['source'], executed_sources=source_closure(),
                authority_sha256=r.digest(authority_path), attestation_sha256=r.digest(attestation_path),
                request_sha256=r.digest(request_path), scope_id=admission['scope_id'], allocation=allocation,
                runtime=adapter.reference_numerical_profile, process=context_evidence(),
                all_parent_preflight_executed=False, original_prices_revised=False,
                promotion_authorized=False, official_origins=0, new_model_fits=0)
            write_new(output / 'execution_identity.json', executed)
        if role == 'instrumented':
            adapter = instrument_adapter(adapter, meter)
            def measured_serialize(path, arrays):
                name = 'full_serialization' if path.parent == output else 'chunk_serialization'
                with meter.phase(name):
                    serializer(path, arrays)
            def measured_validate(t, arrays, scaler, descriptor):
                name = 'chunk_validation' if descriptor is not None else 'concatenation_full_validation_metrics'
                with meter.phase(name):
                    validate(t, arrays, scaler, descriptor)
            kwargs = dict(serializer=measured_serialize, validator=measured_validate,
                concatenate=meter.wrap('concatenation_full_validation_metrics', concatenate),
                metric=meter.wrap('concatenation_full_validation_metrics', metric))
            loop = instrumented_component_loop(meter)
        else:
            kwargs = dict(serializer=serializer, validator=validate, concatenate=concatenate, metric=metric)
            loop = p.component_loop
        with meter.phase('component_orchestration' if role == 'instrumented' else 'reference_component'):
            result = loop(prep, task, adapter, budget, output, **kwargs,
                          chunks=chunks, context_identity=context_identity)
        with meter.phase('sealing_and_final_accounting'):
            _assert_frozen_imports(resolver); budget.check()
            write_new(output / 'component_complete.json', dict(status='COMPLETE_PROFILE_COMPONENT_NOT_SCREENING',
                execution=executed, task_sha256=r.identity(task), result_sha256=r.digest(output / 'result.json'),
                process_lifetime_CPU=b.aggregate_cpu_seconds(), process_lifetime_wall=time.monotonic() - process_start_wall(),
                lifetime_counter_is_pre_seal_snapshot=True,
                peak_RSS_KiB=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
                artifacts={str(q.relative_to(output)): r.digest(q) for q in sorted(output.rglob('*'))
                           if q.is_file() and q.name != 'phase_events.jsonl'}))
        write_new(output / 'phase_accounting.json', meter.report())
        budget.check()
        return result
    except BaseException as exc:
        if not (output / 'failure.json').exists():
            write_new(output / 'failure.json', dict(status='FAILED_PROFILE_COMPONENT_NO_RETRY', role=role,
                error_type=type(exc).__name__, error=str(exc), phase_accounting=meter.report(),
                observed_CPU=b.aggregate_cpu_seconds(), observed_wall=time.monotonic() - process_start_wall()))
        raise
    finally:
        journal.close()


def array_packet_identity(path, budget=None):
    """Stream canonical NPY element bytes; no numerical imports or list materialization."""
    path = planning.physical(path); before = path.stat()
    require(stat.S_ISREG(before.st_mode) and before.st_uid == os.getuid(), 'owned regular raw packet required')
    result = {}
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as raw:
        require(fingerprint(os.fstat(raw.fileno())) == fingerprint(before), 'packet changed at open')
        packet_hash = hashlib.sha256()
        for block in iter(lambda: raw.read(1024**2), b''):
            if budget: budget.check()
            packet_hash.update(block)
        raw.seek(0)
        with zipfile.ZipFile(raw) as packet:
            names = packet.namelist()
            require(len(names) == len(set(names)) and 0 < len(names) <= 64,
                    'complete unique bounded NPZ members required')
            for name in names:
                require('/' not in name and '\\' not in name and name.endswith('.npy'), 'safe canonical NPY member required')
                with packet.open(name) as stream:
                    lead = stream.read(8)
                    require(lead[:6] == b'\x93NUMPY' and lead[6:] in (b'\x01\x00', b'\x02\x00'), 'supported NPY header required')
                    width = 2 if lead[6] == 1 else 4
                    encoded = stream.read(width)
                    require(len(encoded) == width, 'truncated NPY header length')
                    length = int.from_bytes(encoded, 'little')
                    require(0 < length <= 65536, 'bounded NPY header required')
                    header = ast.literal_eval(stream.read(length).decode('latin1').strip())
                    require(type(header) is dict and set(header) == {'descr', 'shape', 'fortran_order'}
                            and header['descr'] in ('<i8', '<f8') and header['fortran_order'] is False
                            and type(header['shape']) is tuple and len(header['shape']) <= 4
                            and all(type(n) is int and n >= 0 for n in header['shape']),
                            'exact canonical little-endian dtype/C-order/shape required')
                    expected = 8 * math.prod(header['shape'])
                    require(expected <= 8 * 1024**3 and packet.getinfo(name).file_size == 8 + width + length + expected,
                            'bounded complete NPY array bytes required')
                    digest = hashlib.sha256(); count = 0
                    while True:
                        if budget: budget.check()
                        block = stream.read(min(1024**2, expected - count + 1))
                        if not block: break
                        digest.update(block); count += len(block)
                        require(count <= expected, 'array payload exceeds declared geometry')
                    require(count == expected, 'truncated canonical array payload')
                    result[name[:-4]] = dict(dtype=header['descr'], shape=list(header['shape']),
                        fortran_order=False, element_bytes=count, ordered_element_sha256=digest.hexdigest())
        require(fingerprint(os.fstat(raw.fileno())) == fingerprint(before), 'raw packet changed while hashing')
    require(fingerprint(path.stat()) == fingerprint(before), 'raw packet changed after hashing')
    planning.physical(path)
    return dict(canonical_arrays=result, raw_packet_sha256=packet_hash.hexdigest(), raw_packet_bytes=before.st_size)


def verify_pair(reference, instrumented, binding, budget=None):
    require(type(binding) is dict and all(k in binding for k in
        ('request_sha256', 'authority_sha256', 'attestation_sha256', 'executed_sources',
         'allocation', 'scope_id', 'task_sha256', 'native_library_sha256',
         'expected_packets', 'expected_chunk_identities', 'expected_result')), 'reviewed expected pair binding required')
    reference = planning.physical(reference); instrumented = planning.physical(instrumented)
    left = sorted(str(q.relative_to(reference)) for q in reference.rglob('predictions.npz'))
    right = sorted(str(q.relative_to(instrumented)) for q in instrumented.rglob('predictions.npz'))
    require(left == right == sorted(binding['expected_packets']) and 'predictions.npz' in left and len(left) > 1,
            'whole canonical component and every expected chunk packet required')
    for root, role in ((reference, 'reference'), (instrumented, 'instrumented')):
        require((root / 'component_complete.json').is_file() and not (root / 'failure.json').exists(),
                'both full components must finish before parity')
        completed = planning.decode_json(bounded_read(root / 'component_complete.json'))
        execution = planning.decode_json(bounded_read(root / 'execution_identity.json'))
        require(completed.get('execution') == execution and execution.get('role') == role
                and all(execution.get(k) == binding[k] for k in
                    ('request_sha256', 'authority_sha256', 'attestation_sha256', 'executed_sources',
                     'allocation', 'scope_id', 'task_sha256')),
                'actual paired role/source/request/allocation/task binding changed')
        require(execution.get('runtime', {}).get('native_library_sha256') == binding['native_library_sha256'],
                'actual paired native runtime binding changed')
        require(completed['status'] == 'COMPLETE_PROFILE_COMPONENT_NOT_SCREENING'
                and r.digest(root / 'result.json') == completed['result_sha256'], 'component result seal changed')
        for name, digest in completed['artifacts'].items():
            require(type(name) is str and not Path(name).is_absolute() and '..' not in Path(name).parts,
                    'safe retained artifact name required')
            require(r.digest(planning.physical(root / name)) == digest, 'complete original component artifact seal changed')
    rows = []
    for name in left:
        a = array_packet_identity(reference / name, budget)
        b_ = array_packet_identity(instrumented / name, budget)
        require(a['canonical_arrays'] == b_['canonical_arrays'], 'ordered full-array bytes/dtype/shape parity failed: ' + name)
        observed_shapes = {key: dict(dtype=value['dtype'], shape=value['shape']) for key, value in a['canonical_arrays'].items()}
        require(observed_shapes == binding['expected_packets'][name], 'canonical original array-key/dtype/shape coverage differs')
        rows.append(dict(path=name, reference=a, instrumented=b_, canonical_array_bytes_equal=True,
                         raw_packet_bytes_equal=a['raw_packet_sha256'] == b_['raw_packet_sha256']))
        if name != 'predictions.npz':
            chunk = str(Path(name).with_name('chunk.json'))
            l = planning.decode_json(bounded_read(reference / chunk))
            rr = planning.decode_json(bounded_read(instrumented / chunk))
            require(l['identity'] == rr['identity'] == binding['expected_chunk_identities'][name]
                    and l['sampler_audit'] == rr['sampler_audit'],
                    'exact sampler/RNG/chunk identity parity failed')
            for root in (reference, instrumented):
                seal = planning.decode_json(bounded_read(root / Path(name).with_name('completed_evidence.json')))
                require(seal.get('certified') is True
                        and seal['artifacts'] == {key: r.digest(root / Path(name).with_name(key))
                                                  for key in ('chunk.json', 'predictions.npz')},
                        'chunk original artifact seal changed')
    l = planning.decode_json(bounded_read(reference / 'result.json'))
    rr = planning.decode_json(bounded_read(instrumented / 'result.json'))
    require(l == rr, 'complete original result/scalars/metrics/order parity failed')
    require(all(l.get(key) == value for key, value in binding['expected_result'].items()),
            'canonical original task/source/origin-clock result identity differs')
    require(l['chunk_count'] == len(left) - 1 and l['certified'] is True
            and l['new_model_fits'] == 0 and l['posterior_updated'] is False
            and l['test_opened'] is False and l['promotion_authorized'] is False,
            'complete original component scope/count required')
    return dict(status='PASS_EXACT_WHOLE_COMPONENT_ARRAY_AND_SAMPLER_PARITY', packets=rows,
        all_ordered_array_bytes_equal=True, exact_result_and_metrics_equal=True,
        all_raw_packets_identical=all(row['raw_packet_bytes_equal'] for row in rows),
        serialization_policy='NPZ container hashes retained; canonical dtype/shape/C-order/element bytes exact; no tolerance added',
        screening_admitted=False, prices_revised=False, official_evaluation_authorized=False)


def run_profile(request_path, authority_path, attestation_path, output):
    meter = Meter()
    with meter.phase('startup_and_authority'):
        request, profile, cost, entry, admission, allocation = gate(request_path, authority_path, attestation_path, 'controller')
        budget = ProfileBudget(admission['limits'], admission['expires_epoch']); budget.install()
        output = planning.physical(output)
        require(output == Path(admission['output_root']), 'exact authorized profile output required')
        require('ACTUAL_COMPONENT_PROFILE' in output.parts, 'separate PROFILE namespace required')
        output.mkdir(parents=True, exist_ok=False)
        binding = dict(request_sha256=r.digest(request_path), authority_sha256=r.digest(authority_path),
            attestation_sha256=r.digest(attestation_path), executed_sources=source_closure(),
            allocation=allocation, scope_id=admission['scope_id'], task_sha256=request['task_sha256'],
            native_library_sha256=admission['parity_runtime']['native_library_sha256'],
            execution_order=ORDER, storage_mode=request['storage_mode'], process=context_evidence())
        with meter.phase('input_verification'):
            binding.update(expected_component(cost, request))
        write_new(output / 'execution_identity.json', binding)
    try:
        for role in ORDER:
            with meter.phase('pair_orchestration'):
                budget.check()
                remaining_cpu = budget.cpu_cap - budget.used_CPU()
                remaining_wall = budget.deadline - time.monotonic()
                command = [sys.executable, '-B', '-m', 'pricefm_hb.execution_profile',
                    '--request', str(request_path), '--authority', str(authority_path),
                    '--attestation', str(attestation_path), '--output', str(output / role),
                    '--component-child', role, '--remaining-cpu', str(remaining_cpu),
                    '--remaining-wall', str(remaining_wall)]
                with (output / (role + '.stdout')).open('xb') as stdout, (output / (role + '.stderr')).open('xb') as stderr:
                    try:
                        result = subprocess.run(command, stdout=stdout, stderr=stderr, timeout=remaining_wall, check=False)
                    finally:
                        budget.install_cpu_backstop()
                write_new(output / (role + '_process.json'), dict(returncode=result.returncode,
                    remaining_CPU_at_launch=remaining_cpu, remaining_wall_at_launch=remaining_wall,
                    command=command, cumulative_parent_and_waited_children_CPU=budget.used_CPU()))
                require(result.returncode == 0, role + ' full component failed; no automatic retry')
                budget.check()
        with meter.phase('parity_verification'):
            parity = verify_pair(output / 'reference', output / 'instrumented', binding, budget)
            write_new(output / 'parity.json', parity)
        with meter.phase('sealing_and_final_accounting'):
            budget.check()
            write_new(output / 'profile_result.json', dict(status='COMPLETE_PAIRED_PROFILE_NOT_SCREENING_ADMISSION',
                execution=binding, parity_status=parity['status'], all_parent_preflight_executed=False,
                whole_process_lifetime_CPU=budget.used_CPU(),
                whole_process_lifetime_wall=time.monotonic() - process_start_wall(),
                lifetime_counter_is_pre_final_seal_snapshot=True,
                original_scientific_budgets_and_prices_unchanged=True, automatic_followon=False,
                Slurm_charge_policy='Primary allocation canonical TotalCPU once at collection; self/children/step counters attribute and never add another charge; retain failed/uncertain/reserved charges',
                child_phase_files=['reference/phase_accounting.json', 'instrumented/phase_accounting.json'],
                child_IO_not_added_to_parent_IO='Separate per-process counters; no claim parent IO includes child IO',
                aggregate_peak_memory='Requires collected Slurm/cgroup peak evidence; phase RSS alone cannot establish concurrency'))
        write_new(output / 'pair_accounting.json', meter.report())
        with meter.phase('sealing_and_final_accounting'):
            write_new(output / 'completed_evidence.json', dict(status='COMPLETE_PAIRED_PROFILE_NOT_SCREENING_ADMISSION',
                execution=binding, artifacts={str(q.relative_to(output)): r.digest(q)
                    for q in sorted(output.rglob('*')) if q.is_file()}, exact_whole_component_parity=True))
        write_new(output / 'post_seal_accounting.json', dict(status='POST_SEAL_ACCOUNTING_SNAPSHOT',
            execution=binding, completed_evidence_sha256=r.digest(output / 'completed_evidence.json'),
            accounting=meter.report(), process_lifetime_wall=time.monotonic() - process_start_wall(),
            publication_and_interpreter_exit_tail_captured_by_canonical_Slurm=True,
            no_aggregate_charge_is_derived_by_adding_attribution_counters=True))
        budget.check()
        return parity
    except BaseException as exc:
        if not (output / 'failure.json').exists():
            write_new(output / 'failure.json', dict(status='FAILED_PAIRED_PROFILE_NO_AUTOMATIC_RETRY',
                error_type=type(exc).__name__, error=str(exc), execution=binding,
                observed_CPU=budget.used_CPU(), phase_accounting=meter.report()))
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('request', 'authority', 'attestation', 'output'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--component-child', choices=ORDER)
    parser.add_argument('--remaining-cpu', type=float); parser.add_argument('--remaining-wall', type=float)
    args = parser.parse_args(argv)
    if args.component_child:
        require(args.remaining_cpu is not None and args.remaining_wall is not None, 'paired parent remaining limits required')
        result = execute_component(args.request, args.authority, args.attestation, args.output,
                                   args.component_child, args.remaining_cpu, args.remaining_wall)
        print(json.dumps({'status': 'COMPLETE_PROFILE_COMPONENT', 'name': result['name']}))
    else:
        require(args.remaining_cpu is None and args.remaining_wall is None, 'parent cannot override authority caps')
        result = run_profile(args.request, args.authority, args.attestation, args.output)
        print(json.dumps({'status': result['status']}))


if __name__ == '__main__':
    main()
