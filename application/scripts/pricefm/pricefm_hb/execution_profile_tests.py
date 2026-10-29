"""Private scalar/byte-only PROFILE boundary tests; no scientific numerical calls."""
import copy
import io
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

from . import execution_profile as e
from . import registry as r


class Clock:
    def __init__(self):
        self.value = 0
    def advance(self, value):
        self.value += value
    def __call__(self):
        return {**{key: self.value for key in e.ADDITIVE}, 'epoch': self.value,
                'self_peak_RSS_KiB': 10, 'waited_child_peak_RSS_KiB': 20,
                'self_current_RSS_KiB': 5}


def npy(values=(1., 2.), dtype='<f8', shape=None, fortran=False):
    shape = (len(values),) if shape is None else shape
    header = repr(dict(descr=dtype, fortran_order=fortran, shape=shape)).encode('latin1')
    header += b' ' * ((64 - (10 + len(header) + 1) % 64) % 64) + b'\n'
    return b'\x93NUMPY\x01\x00' + len(header).to_bytes(2, 'little') + header + struct.pack('<' + 'd' * len(values), *values)


def packet(path, values=(1., 2.), date=(2020, 1, 1, 0, 0, 0), **kw):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as out:
        info = zipfile.ZipInfo('truth.npy', date)
        info.compress_type = zipfile.ZIP_DEFLATED
        out.writestr(info, npy(values, **kw))


def fixture_pair(base):
    binding = dict(request_sha256='1' * 64, authority_sha256='2' * 64,
        attestation_sha256='3' * 64, executed_sources={'frozen.py': '4' * 64},
        allocation={'job_id': '123', 'node': 'compute1'}, scope_id='test-profile', task_sha256='5' * 64,
        native_library_sha256={'native.so': '6' * 64})
    binding['expected_packets'] = {name: {'truth': dict(dtype='<f8', shape=[2])} for name in
        ('predictions.npz', 'checkpoints/clock00_part000/predictions.npz')}
    binding['expected_chunk_identities'] = {'checkpoints/clock00_part000/predictions.npz': {'descriptor': 'fixed'}}
    binding['expected_result'] = dict(name='canonical_task', task_sha256=binding['task_sha256'],
                                     origin_clock_windows=2, chunk_count=1)
    for role in e.ORDER:
        root = base / role; chunk = root / 'checkpoints' / 'clock00_part000'
        chunk.mkdir(parents=True)
        date = (2020, 1, 1 if role == 'reference' else 2, 0, 0, 0)
        packet(root / 'predictions.npz', date=date); packet(chunk / 'predictions.npz', date=date)
        execution = {key: binding[key] for key in ('request_sha256', 'authority_sha256', 'attestation_sha256',
                     'executed_sources', 'allocation', 'scope_id', 'task_sha256')}
        execution.update(role=role, runtime={'native_library_sha256': binding['native_library_sha256']})
        r.write(root / 'execution_identity.json', execution)
        r.write(chunk / 'chunk.json', dict(identity={'descriptor': 'fixed'}, sampler_audit={'seed': 123}))
        r.write(chunk / 'completed_evidence.json', dict(certified=True,
            artifacts={name: r.digest(chunk / name) for name in ('chunk.json', 'predictions.npz')}))
        result = dict(chunk_count=1, certified=True, new_model_fits=0, posterior_updated=False,
                      test_opened=False, promotion_authorized=False, metrics={'AQL': 1.},
                      name='canonical_task', task_sha256=binding['task_sha256'], origin_clock_windows=2)
        r.write(root / 'result.json', result)
        r.write(root / 'component_complete.json', dict(status='COMPLETE_PROFILE_COMPONENT_NOT_SCREENING',
            execution=execution, result_sha256=r.digest(root / 'result.json'),
            artifacts={str(q.relative_to(root)): r.digest(q) for q in root.rglob('*') if q.is_file()}))
    return binding


def reseal(root):
    value = json.loads((root / 'component_complete.json').read_text())
    value['result_sha256'] = r.digest(root / 'result.json')
    value['artifacts'] = {name: r.digest(root / name) for name in value['artifacts']}
    (root / 'component_complete.json').write_text(json.dumps(value))


class AccountingTests(unittest.TestCase):
    def test_nested_disjoint_phases_and_explicit_residual(self):
        clock = Clock(); meter = e.Meter(clock)
        clock.advance(1)
        with meter.phase('component_orchestration'):
            clock.advance(1)
            with meter.phase('arithmetic'):
                clock.advance(2)
            clock.advance(3)
        clock.advance(4)
        report = meter.report()
        self.assertEqual(report['interval_total']['wall'], 11)
        self.assertEqual(report['disjoint_attributed']['wall'], 6)
        self.assertEqual(report['unattributed_residual']['wall'], 5)
        self.assertEqual([v['exclusive']['wall'] for v in report['events']], [2, 4])

    def test_failure_records_and_exits_stack(self):
        clock = Clock(); meter = e.Meter(clock)
        with self.assertRaisesRegex(OSError, 'retained'):
            with meter.phase('arithmetic'):
                clock.advance(3)
                raise OSError('retained')
        self.assertTrue(meter.report()['events'][0]['failed'])
        self.assertEqual(meter.stack, [])

    def test_nonmonotonic_accounting_rejects(self):
        clock = Clock(); meter = e.Meter(clock)
        clock.advance(-1)
        with self.assertRaisesRegex(ValueError, 'nonmonotonic'):
            meter.report()

    def test_adapter_instrumentation_preserves_values_and_keywords(self):
        clock = Clock(); meter = e.Meter(clock)
        calls = []
        def function(*args, **kw):
            calls.append((args, kw)); clock.advance(2); return {'same': args}
        adapter = type('Adapter', (), {})()
        for name in ('context', 'predict', 'retained_arrays', 'cleanup', 'pools'):
            setattr(adapter, name, function)
        wrapped = e.instrument_adapter(adapter, meter)
        self.assertEqual(wrapped.retained_arrays(1, compute_loss=True), {'same': (1,)})
        self.assertEqual(calls, [((1,), {'compute_loss': True})])
        self.assertIs(wrapped.pools, adapter.pools)
        self.assertEqual(meter.events[0]['phase'], 'retained_array_conversion')

    def test_unknown_phase_rejects(self):
        with self.assertRaisesRegex(ValueError, 'unknown'):
            with e.Meter(Clock()).phase('cheap_subset'): pass


class ByteParityTests(unittest.TestCase):
    def test_different_zip_container_metadata_keeps_exact_array_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp); a = base / 'a.npz'; b = base / 'b.npz'
            packet(a); packet(b, date=(2020, 2, 1, 0, 0, 0))
            aa, bb = e.array_packet_identity(a), e.array_packet_identity(b)
            self.assertEqual(aa['canonical_arrays'], bb['canonical_arrays'])
            self.assertNotEqual(aa['raw_packet_sha256'], bb['raw_packet_sha256'])

    def test_signed_zero_ordered_bytes_are_not_numerically_coalesced(self):
        with tempfile.TemporaryDirectory() as tmp:
            a, b = Path(tmp) / 'a.npz', Path(tmp) / 'b.npz'
            packet(a, (0.,)); packet(b, (-0.,))
            self.assertNotEqual(e.array_packet_identity(a)['canonical_arrays'], e.array_packet_identity(b)['canonical_arrays'])

    def test_wrong_dtype_fortran_truncation_and_traversal_reject(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'x.npz'
            for kw in ({'dtype': '>f8'}, {'fortran': True}, {'shape': (3,)}):
                packet(p, **kw)
                with self.assertRaises(ValueError): e.array_packet_identity(p)
            with zipfile.ZipFile(p, 'w') as out: out.writestr('../truth.npy', npy())
            with self.assertRaises(ValueError): e.array_packet_identity(p)

    def test_symbolic_packet_rejects(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp); packet(base / 'x.npz'); (base / 'alias.npz').symlink_to('x.npz')
            with self.assertRaises(ValueError): e.array_packet_identity(base / 'alias.npz')

    def test_full_pair_reports_container_difference_and_exact_science(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp); binding = fixture_pair(base)
            report = e.verify_pair(base / 'reference', base / 'instrumented', binding)
            self.assertTrue(report['all_ordered_array_bytes_equal'])
            self.assertFalse(report['all_raw_packets_identical'])
            self.assertEqual(len(report['packets']), 2)

    def test_pair_without_reviewed_expected_binding_rejects(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp); fixture_pair(base)
            with self.assertRaisesRegex(ValueError, 'binding'):
                e.verify_pair(base / 'reference', base / 'instrumented', {})

    def test_matching_but_wrong_role_request_source_or_task_cannot_pass(self):
        for key, bad in (('role', 'reference'), ('task_sha256', '9' * 64), ('executed_sources', {}),
                         ('request_sha256', '0' * 64), ('allocation', {'node': 'other'})):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as tmp:
                base = Path(tmp); binding = fixture_pair(base); root = base / 'instrumented'
                execution = json.loads((root / 'execution_identity.json').read_text()); execution[key] = bad
                (root / 'execution_identity.json').write_text(json.dumps(execution))
                seal = json.loads((root / 'component_complete.json').read_text()); seal['execution'] = execution
                (root / 'component_complete.json').write_text(json.dumps(seal)); reseal(root)
                with self.assertRaisesRegex(ValueError, 'binding'):
                    e.verify_pair(base / 'reference', root, binding)

    def test_resealed_metrics_or_sampler_difference_fails_exact_parity(self):
        for change in ('metrics', 'sampler'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as tmp:
                base = Path(tmp); binding = fixture_pair(base); root = base / 'instrumented'
                if change == 'metrics':
                    result = json.loads((root / 'result.json').read_text()); result['metrics']['AQL'] += 1e-14
                    (root / 'result.json').write_text(json.dumps(result))
                else:
                    chunk = root / 'checkpoints' / 'clock00_part000'
                    value = json.loads((chunk / 'chunk.json').read_text()); value['sampler_audit']['seed'] += 1
                    (chunk / 'chunk.json').write_text(json.dumps(value))
                    value = json.loads((chunk / 'completed_evidence.json').read_text())
                    value['artifacts']['chunk.json'] = r.digest(chunk / 'chunk.json')
                    (chunk / 'completed_evidence.json').write_text(json.dumps(value))
                reseal(root)
                with self.assertRaisesRegex(ValueError, 'parity'):
                    e.verify_pair(base / 'reference', root, binding)

    def test_changed_raw_array_or_missing_chunk_seal_rejects(self):
        for change in ('array', 'seal'):
            with tempfile.TemporaryDirectory() as tmp:
                base = Path(tmp); binding = fixture_pair(base); root = base / 'instrumented'
                if change == 'array': packet(root / 'predictions.npz', (9., 2.))
                else: (root / 'checkpoints' / 'clock00_part000' / 'completed_evidence.json').unlink()
                with self.assertRaises((ValueError, FileNotFoundError)):
                    e.verify_pair(base / 'reference', root, binding)

    def test_both_matching_wrong_task_or_omitted_chunk_still_fail(self):
        for change in ('task', 'chunk'):
            with tempfile.TemporaryDirectory() as tmp:
                base = Path(tmp); binding = fixture_pair(base)
                for role in e.ORDER:
                    root = base / role
                    value = json.loads((root / 'result.json').read_text())
                    if change == 'task': value['name'] = 'other_task'
                    else:
                        (root / 'checkpoints' / 'clock00_part000' / 'predictions.npz').unlink()
                        value['chunk_count'] = 0
                    (root / 'result.json').write_text(json.dumps(value))
                    if change == 'task': reseal(root)
                with self.assertRaises(ValueError):
                    e.verify_pair(base / 'reference', base / 'instrumented', binding)


class AdmissionAndSourceTests(unittest.TestCase):
    def test_import_and_test_suite_have_no_numerical_imports(self):
        self.assertFalse({'numpy', 'scipy', 'pandas'} & set(sys.modules))

    def test_compute_gate_fails_before_reading_missing_payloads(self):
        with patch.object(e, 'require_compute', side_effect=RuntimeError('not compute')):
            with self.assertRaisesRegex(RuntimeError, 'not compute'):
                e.run_profile('/absent', '/absent', '/absent', '/absent')

    def test_budget_rejects_boolean_nonfinite_unbounded_and_expanded_fields(self):
        good = dict(aggregate_cpu_seconds=500, wall_seconds=900, memory_MiB=2048)
        cases = [dict(good, aggregate_cpu_seconds=True), dict(good, aggregate_cpu_seconds=float('nan')),
                 dict(good, wall_seconds=900.), dict(good, memory_MiB=True), dict(good, cpus=True),
                 dict(good, cpus=1.), dict(good, aggregate_cpu_seconds=2001)]
        for value in cases:
            with self.subTest(value=value), self.assertRaises(ValueError):
                e.ProfileBudget(value, e.time.time() + 2000)

    def test_child_cannot_expand_pair_remaining_allowance(self):
        good = dict(aggregate_cpu_seconds=500, wall_seconds=900, memory_MiB=2048)
        for kw in (dict(remaining_CPU=501), dict(remaining_wall=901), dict(remaining_CPU=True)):
            with self.assertRaises(ValueError): e.ProfileBudget(good, e.time.time() + 2000, **kw)

    def test_expired_budget_is_failed_without_clock_renewal(self):
        good = dict(aggregate_cpu_seconds=500, wall_seconds=900, memory_MiB=2048)
        budget = e.ProfileBudget(good, e.time.time() - 1)
        with self.assertRaises(TimeoutError): budget.check()

    def test_parent_self_hard_limit_subtracts_waited_children_and_floors(self):
        good = dict(aggregate_cpu_seconds=500, wall_seconds=900, memory_MiB=2048)
        budget = e.ProfileBudget(good, e.time.time() + 2000)
        children = SimpleNamespace(ru_utime=100.3, ru_stime=10.2)
        with patch.object(e.resource, 'getrusage', return_value=children), \
             patch.object(e.resource, 'getrlimit', return_value=(500, 500)), \
             patch.object(e.resource, 'setrlimit') as install, \
             patch.object(e.time, 'process_time', return_value=20):
            budget.install_cpu_backstop()
        install.assert_called_once_with(e.resource.RLIMIT_CPU, (389, 389))

    def test_unfinished_phase_cannot_publish_accounting(self):
        meter = e.Meter(Clock())
        with meter.phase('arithmetic'):
            with self.assertRaisesRegex(ValueError, 'unfinished'): meter.report()

    def test_private_component_function_is_AST_identical_and_not_monkeypatch(self):
        original = e.p.component_loop
        fn = e.instrumented_component_loop(e.Meter(Clock()))
        self.assertIs(e.p.component_loop, original)
        self.assertEqual(fn.__code__.co_argcount, original.__code__.co_argcount)
        self.assertEqual(fn.__code__.co_varnames, original.__code__.co_varnames)
        self.assertEqual(fn.__code__.co_names, original.__code__.co_names)
        self.assertIsNot(fn.__globals__, original.__globals__)
        self.assertEqual(set(fn.__globals__) - {'__builtins__', 'component_loop'}, e.COMPONENT_LOOP_GLOBALS)

    def test_source_tamper_is_rejected_before_private_function_creation(self):
        source = e.bounded_read(Path(e.p.__file__)).replace(b'def component_loop(', b'def component_loop_BAD(')
        with patch.object(e, 'bounded_read', return_value=source):
            with self.assertRaisesRegex(ValueError, 'source changed'):
                e.instrumented_component_loop(e.Meter(Clock()))

    def test_exact_private_loop_executes_four_clocks_and_seals_without_global_mutation(self):
        with tempfile.TemporaryDirectory() as tmp:
            original_seal = e.p.seal_directory
            meter = e.Meter(Clock()); cleanup = []; calls = []
            task = dict(name='fixed_task', mode='D', scientific_identity_sha256='1' * 64,
                        daily_origin_positions=[0])
            prep = {'source': {'head': 'fixed'}}
            chunks = [dict(name='clock' + str(c), clock_offset_steps=c) for c in (0, 24, 48, 72)]
            def predict(context, task, descriptor, beat):
                calls.append(descriptor['clock_offset_steps'])
                return descriptor, None, {'fixed_rng': 1}
            adapter = SimpleNamespace(context=lambda task: {'scaler': {}}, predict=predict,
                retained_arrays=lambda *args, **kw: {'chunk': args[2], 'compute_loss': kw['compute_loss']},
                pools=lambda: [], cleanup=lambda context: cleanup.append(context))
            def serializer(path, arrays):
                Path(path).write_text(json.dumps(arrays))
            result = e.instrumented_component_loop(meter)(prep, task,
                e.instrument_adapter(adapter, meter), SimpleNamespace(check=lambda: None), tmp,
                serializer=serializer, concatenate=lambda parts: parts, validator=lambda *args: None,
                metric=lambda arrays: {'AQL': 1.}, chunks=lambda task: chunks,
                context_identity=lambda task, prep: {'fixed': 'context'})
            self.assertEqual(calls, [0, 24, 48, 72])
            self.assertEqual(result['chunk_count'], 4)
            self.assertEqual(len(cleanup), 1)
            self.assertEqual(len(list(Path(tmp).glob('checkpoints/*/completed_evidence.json'))), 4)
            self.assertEqual(sum(v['phase'] == 'sealing_and_final_accounting' for v in meter.events), 9)
            self.assertIs(e.p.seal_directory, original_seal)


if __name__ == '__main__':
    unittest.main()
