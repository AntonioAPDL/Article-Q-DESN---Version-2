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


class ProfileSupportTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='pricefm_profile_support_',dir='/dev/shm');self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)/('r164-profile-'+'b'*32);self.root.mkdir()
        self.path=self.root/e.SUPPORT_RELATIVE;self.path.parent.mkdir(parents=True)
        self.raw=e.bounded_read(e.p.CONTRACT_PATH);self.path.write_bytes(self.raw)
        self.request=dict(cost_plan=dict(path=str(self.root/'metadata/cost_plan.json'),sha256='1'*64),
            profile_support=dict(schema=e.SUPPORT_SCHEMA,role=e.SUPPORT_ROLE,logical_path=e.p.CONTRACT_PATH,
                path=str(self.path),bytes=e.SUPPORT_BYTES,sha256=e.p.CONTRACT_SHA))

    def test_only_contract_is_overlaid_original_paths_and_directories_are_identical(self):
        stage=self.root/'old_stage';f=stage/'files/fixed/value.json';f.parent.mkdir(parents=True);f.write_bytes(b'{}')
        original=e.b.Resolver(stage,dict(assets={'/fixed/value.json':dict(path='files/fixed/value.json',bytes=2,sha256=r.digest(f))}))
        wrapped=e.profile_resolver(original,self.request)
        self.assertIs(wrapped.assets,original.assets)
        self.assertEqual(wrapped.path('/fixed/value.json'),original.path('/fixed/value.json'))
        self.assertEqual(wrapped.directory('/fixed'),original.directory('/fixed'))
        self.assertEqual(wrapped.path(e.p.CONTRACT_PATH,verify=False),self.path)
        with self.assertRaises(KeyError):wrapped.path('/unlisted_contract.py')

    def test_wrong_missing_extra_role_path_hash_size_and_old_release_are_rejected(self):
        cases=[dict(self.request,profile_support=None)]
        for key,value in [('role','OTHER'),('logical_path','/other.py'),('path',str(self.root/'other.py')),
                          ('sha256','0'*64),('bytes',13278.),('extra',True)]:
            q=copy.deepcopy(self.request);q['profile_support'][key]=value;cases.append(q)
        q=copy.deepcopy(self.request);q['cost_plan']['path']='/owned/r157-old/metadata/cost_plan.json';cases.append(q)
        for q in cases:
            with self.subTest(q=q),self.assertRaises(ValueError):e.validate_profile_support(q)

    def test_tampered_missing_symlink_and_hardlink_support_fail_closed(self):
        self.path.write_bytes(b'x'+self.raw[1:])
        with self.assertRaises(ValueError):e.validate_profile_support(self.request)
        self.path.unlink()
        with self.assertRaises(FileNotFoundError):e.validate_profile_support(self.request)
        self.path.symlink_to(e.p.CONTRACT_PATH)
        with self.assertRaises(ValueError):e.validate_profile_support(self.request)
        self.path.unlink();self.path.write_bytes(self.raw);alias=self.root/'alias.py';os.link(self.path,alias)
        with self.assertRaises(ValueError):e.validate_profile_support(self.request)

    def test_delivery_retains_exact_compiler_bytes_and_binds_current_sources(self):
        original={'schema':'private original compiler fixture','typed_integer':1};compiler=self.root/'compiler.json';compiler.write_text(json.dumps(original))
        profile=dict(original,profile_delivery_binding=dict(schema=e.DELIVERY_SCHEMA,source_files=e.source_closure(),
            compiler_output=dict(path=str(compiler),sha256=r.digest(compiler)),
            contract_source=dict(path=e.p.CONTRACT_PATH,sha256=e.p.CONTRACT_SHA,bytes=e.SUPPORT_BYTES),authority=False))
        e.validate_delivery_binding(profile)
        for changed in [dict(profile,changed=True),dict(profile,typed_integer=True),dict(profile,typed_integer=1.),
                        dict(profile,profile_delivery_binding=dict(profile['profile_delivery_binding'],source_files={}))]:
            with self.assertRaises(ValueError):e.validate_delivery_binding(changed)

    def test_controller_rejects_readiness_expectation_divergence_before_children(self):
        request=dict(self.request,task_sha256='1'*64,storage_mode='DIRECT_RETAINED_SOURCE')
        profile={'profile_delivery_binding':{'private':'delivery'}}
        output=self.root/'ACTUAL_COMPONENT_PROFILE'/'private'
        admission=dict(limits={},expires_epoch=1,output_root=str(output),scope_id='private',
                       parity_runtime={'native_library_sha256':{}})
        paths=[]
        for name,value in [('request',request),('authority',{}),('attestation',dict(input_readiness_pin={},
                input_readiness={'expected_component_sha256':'0'*64}))]:
            path=self.root/(name+'.json');path.write_text(json.dumps(value));paths.append(path)
        with patch.object(e,'gate',return_value=(request,profile,{}, {},admission,{})),patch.object(e,'ProfileBudget'), \
             patch.object(e,'expected_component',return_value={'private':'canonical shape metadata'}), \
             patch.object(e.subprocess,'Popen') as spawn:
            with self.assertRaisesRegex(ValueError,'metadata differs from allocated input readiness'):
                e.run_profile(*paths,output)
            spawn.assert_not_called()

    def test_both_child_roles_attach_support_only_after_original_load_staged(self):
        for role in e.ORDER:
            with self.subTest(role=role):
                output_root=self.root/'ACTUAL_COMPONENT_PROFILE'/role;output=output_root/role
                admission=dict(limits={},expires_epoch=1,output_root=str(output_root),parity_runtime={'native_library_sha256':{}})
                order=[];cost={'fixed':'old inventory'};original=SimpleNamespace(root=self.root,manifest={},assets={})
                req=dict(self.request,stage_root='/original/unchanged/stage',task='fixed',task_sha256=r.identity({'name':'fixed','reuse':None,'scientific_identity_sha256':'x'}))
                task=dict(name='fixed',reuse=None,scientific_identity_sha256='x')
                def load(c,root):order.append('original_verify');self.assertIs(c,cost);self.assertEqual(root,req['stage_root']);return {'tasks':[task]}, {}, original
                def attach(base,request):order.append('attach_support');self.assertIs(base,original);return base
                with patch.object(e,'gate',return_value=(req,{},cost,{},admission,{})),patch.object(e,'ProfileBudget'), \
                     patch.object(e.b,'load_staged',side_effect=load),patch.object(e,'profile_resolver',side_effect=attach), \
                     patch.object(e.p,'original',return_value=lambda t:'private identity'),patch.object(e.r,'identity',return_value='x'), \
                     patch.object(e.b,'frozen_adapter',side_effect=RuntimeError('stop before numerical imports')):
                    req['task_sha256']='x'
                    with self.assertRaisesRegex(RuntimeError,'stop before numerical imports'):
                        e.execute_component('/unused','/unused','/unused',output,role,1,1)
                self.assertEqual(order,['original_verify','attach_support'])


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


def native_record(path='/fixture/native_a.so', prefix='libopenblas'):
    return dict(architecture='Sandybridge',filepath=path,internal_api='openblas',num_threads=1,
                prefix=prefix,threading_layer='pthreads',user_api='blas',version='0.3.27')


class NativeInventoryComparisonTests(unittest.TestCase):
    def values(self):
        records=[native_record(),native_record('/fixture/native_b.so','libscipy_openblas')]
        return dict(metrics={'AQL':1.},ordered=['first','second'],numerical_threadpools=records)

    def test_only_complete_native_record_order_is_ignored(self):
        left=self.values();right=copy.deepcopy(left);right['numerical_threadpools'].reverse()
        result=e.result_metadata_comparison(left,right)
        self.assertTrue(result['canonical_result_and_metrics_equal']);self.assertFalse(result['exact_result_and_metrics_equal'])
        self.assertTrue(result['scientific_fields_and_metrics_equal']);self.assertTrue(result['native_inventory_equal_under_policy'])
        self.assertEqual(result['native_inventory_comparison_policy'],e.NATIVE_INVENTORY_POLICY)
        self.assertEqual(left['numerical_threadpools'][0]['filepath'],'/fixture/native_a.so')

    def test_fields_extra_fields_and_multiplicity_are_preserved(self):
        left=self.values();left['numerical_threadpools'][0]['extra']={'ordered':['x','y'],'typed':1}
        right=copy.deepcopy(left);right['numerical_threadpools'].reverse()
        self.assertTrue(e.result_metadata_comparison(left,right)['canonical_result_and_metrics_equal'])
        changed=copy.deepcopy(right);changed['numerical_threadpools'][1]['extra']['ordered'].reverse()
        self.assertFalse(e.result_metadata_comparison(left,changed)['canonical_result_and_metrics_equal'])
        for key in native_record():
            changed=copy.deepcopy(right)
            if key=='num_threads':changed['numerical_threadpools'][0][key]=2
            else:changed['numerical_threadpools'][0][key]+='_different'
            if key=='num_threads':
                with self.assertRaises(ValueError):e.result_metadata_comparison(left,changed)
            else:self.assertFalse(e.result_metadata_comparison(left,changed)['canonical_result_and_metrics_equal'])
        duplicate=copy.deepcopy(left);duplicate['numerical_threadpools'].append(copy.deepcopy(left['numerical_threadpools'][0]))
        reversed_duplicate=copy.deepcopy(duplicate);reversed_duplicate['numerical_threadpools'].reverse()
        self.assertTrue(e.result_metadata_comparison(duplicate,reversed_duplicate)['canonical_result_and_metrics_equal'])
        self.assertFalse(e.result_metadata_comparison(duplicate,right)['canonical_result_and_metrics_equal'])

    def test_missing_records_fields_and_wrong_types_are_rejected(self):
        for value in (None,[],{},(native_record(),),[[]]):
            with self.subTest(value=value),self.assertRaises(ValueError):e.canonical_native_inventory(value)
        for key in native_record():
            value=native_record();value.pop(key)
            with self.subTest(missing=key),self.assertRaises(ValueError):e.canonical_native_inventory([value])
        for value in (True,1.,0,2,'1',None):
            record=native_record();record['num_threads']=value
            with self.subTest(threads=value),self.assertRaises(ValueError):e.canonical_native_inventory([record])
        for value in (None,False,1,1.,[],{}):
            record=native_record();record['version']=value
            with self.subTest(version=value),self.assertRaises(ValueError):e.canonical_native_inventory([record])
        for value in (float('nan'),float('inf'),('tuple',),{1:'non-string key'}):
            record=native_record();record['extra']=value
            with self.subTest(extra=value),self.assertRaises(ValueError):e.canonical_native_inventory([record])
        record=native_record();record['extra']=1
        changed=copy.deepcopy(record);changed['extra']=True
        self.assertNotEqual(e.canonical_native_inventory([record]),e.canonical_native_inventory([changed]))

    def test_every_other_list_metric_and_json_type_remains_exact(self):
        left=self.values()
        cases=[]
        for value in (1.001,True,1):
            changed=copy.deepcopy(left);changed['metrics']['AQL']=value;cases.append(changed)
        changed=copy.deepcopy(left);changed['ordered'].reverse();cases.append(changed)
        changed=copy.deepcopy(left);changed['other']={'numerical_threadpools':[1,2]};different=copy.deepcopy(changed)
        different['other']['numerical_threadpools'].reverse()
        self.assertFalse(e.result_metadata_comparison(changed,different)['scientific_fields_and_metrics_equal'])
        for changed in cases:
            result=e.result_metadata_comparison(left,changed)
            self.assertFalse(result['scientific_fields_and_metrics_equal']);self.assertFalse(result['canonical_result_and_metrics_equal'])


def fixture_pair(base):
    binding = dict(request_sha256='1' * 64, authority_sha256='2' * 64,
        attestation_sha256='3' * 64, executed_sources={'frozen.py': '4' * 64},
        allocation={'job_id': '123', 'node': 'compute1'}, scope_id='test-profile', task_sha256='5' * 64,
        native_library_sha256={'/fixture/native_a.so': '6' * 64,'/fixture/native_b.so':'7'*64})
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
                      name='canonical_task', task_sha256=binding['task_sha256'], origin_clock_windows=2,
                      numerical_threadpools=[native_record(),native_record('/fixture/native_b.so','libscipy_openblas')])
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

    def test_native_order_only_pair_keeps_raw_seals_and_reports_literal_difference(self):
        with tempfile.TemporaryDirectory(prefix='pricefm_native_order_',dir='/dev/shm') as tmp:
            base=Path(tmp);binding=fixture_pair(base);right=base/'instrumented'
            path=right/'result.json';value=json.loads(path.read_text());value['numerical_threadpools'].reverse()
            r.write(path,value);reseal(right)
            before={role:r.digest(base/role/'result.json') for role in e.ORDER}
            result=e.verify_pair(base/'reference',right,binding)
            self.assertFalse(result['exact_result_and_metrics_equal']);self.assertFalse(result['raw_result_JSON_bytes_equal'])
            self.assertTrue(result['canonical_result_and_metrics_equal']);self.assertTrue(result['scientific_fields_and_metrics_equal'])
            self.assertTrue(result['all_ordered_array_bytes_equal']);self.assertTrue(result['native_inventory_equal_under_policy'])
            self.assertEqual(before,{role:r.digest(base/role/'result.json') for role in e.ORDER})

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
