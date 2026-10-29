"""Private metadata-only coverage and preparation-boundary tests."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from . import execution_profile_plan as p


def fixture(study='FI'):
    n, geometries, _ = p.COUNTS[study]
    region = p.CANONICAL[study]['region']
    spec = dict(m_y=2, m_x=2, depth=2, input_fan_in=2, recurrent_sparsity=.2, feature_policy='target_only')
    packages = [dict(package_id='C0' if i == 0 else 'P' + str(i), candidate_id='G' + str(i % geometries), p=2, spec=dict(spec)) for i in range(n)]
    tasks = []
    for package in packages:
        for split in (1, 2, 3):
            for mode, seed in [('D', 0), ('S', 0), ('S', 1), ('S', 2)]:
                task = dict(region=region, name=package['package_id'] + '_' + str(split) + '_' + mode + str(seed),
                    package_id=package['package_id'], candidate_id=package['candidate_id'], p=2, spec=dict(spec), split=split,
                    mode=mode, seed_index=seed, clock_offsets_steps=list(p.CLOCKS), horizon_steps=96, paths=100,
                    quantiles=list(p.QUANTILES), forecast_seed=42 + seed, test_opened=False, posterior_updated=False,
                    new_model_fits=0, daily_origin_positions=[10, 11], origin_timestamps={str(c): ['A', 'B'] for c in p.CLOCKS},
                    scientific_identity_sha256='a' * 64, parent_fit='/retained/parent', parent_seal_sha256='b' * 64,
                    parent_input_sha256={'/retained/input.bin': 'c' * 64}, scaler_path='/retained/scaler.json',
                    scaler_sha256='d' * 64, bank={'path': '/retained/bank.npz', 'sha256': 'e' * 64}, reuse=None)
                tasks.append(task)
    prep = dict(packages=packages, region=region, control='C0', source={'head': p.CANONICAL[study]['head']},
        new_model_fits=0, posterior_updated=False, test_opened=False, tasks=tasks,
        source_sha256={'/source.py': 'f' * 64}, input_sha256={'/retained/input.bin': 'c' * 64})
    config = dict(region=region, control='C0', clock_offsets_steps=list(p.CLOCKS), horizon_steps=96, paths=100,
        quantiles=list(p.QUANTILES), AL_authorized=False, official_evaluation_authorized=False, promotion_authorized=False,
        test_used_for_selection=False)
    rows = [dict(mode='D' if i < 12 else 'S', p=1, spec={**spec, 'm_y': 1}, clock_offset_steps=0) for i in range(16)]
    timing = dict(status='COMPLETE_COST_ONLY_18_CALL_PANEL_NO_SELECTION_NO_ADMISSION', arithmetic_calls=18, rows=rows,
        full_prefix_admitted=False, no_scientific_selection=True,
        actual_reference_numerical_profile={'enabled': True, 'native_library_sha256': {'/native.so': 'a' * 64}, 'environment': {}})
    prices = {'task_estimates': {t['name']: {'reserved_CPU': 10, 'reserved_wall': 20, 'imported': None} for t in tasks}}
    return prep, config, timing, prices


class GridTests(unittest.TestCase):
    def test_complete_both_original_universes_and_fallbacks(self):
        for study, count in [('FI', 240), ('DK2', 252)]:
            result = p.build_study(study, *fixture(study))
            self.assertEqual(result['task_count'], count)
            self.assertEqual(result['joint_geometry_coverage']['uncovered_count'], count)
            self.assertEqual(len(result['joint_geometry_coverage']['old_panel_missing_clock_coverage_tasks']), count)
            self.assertEqual(result['tasks'][0]['clocks'], [0, 24, 48, 72])
            self.assertFalse(result['original_prices_revised'])
            self.assertFalse(result['input_payloads_rehashed'])

    def reject(self, edit):
        values = fixture(); edit(*values)
        with self.assertRaises((ValueError, KeyError)):
            p.build_study('FI', *values)

    def test_task_omission_rejected(self):
        self.reject(lambda prep, *_: prep['tasks'].pop())

    def test_duplicate_and_wrong_seed_rejected(self):
        self.reject(lambda prep, *_: prep['tasks'][0].update(seed_index=1))

    def test_missing_clock_rejected(self):
        self.reject(lambda prep, *_: prep['tasks'][0].update(clock_offsets_steps=[0, 24, 48]))

    def test_missing_clock_timestamp_rejected(self):
        self.reject(lambda prep, *_: prep['tasks'][0]['origin_timestamps'].pop('72'))

    def test_changed_geometry_rejected(self):
        self.reject(lambda prep, *_: prep['tasks'][0]['spec'].update(m_y=20))

    def test_non_joint_maximum_does_not_cover(self):
        prep, cfg, timing, prices = fixture()
        timing['rows'][0].update(p=99, spec={**timing['rows'][0]['spec'], 'm_y': 1, 'm_x': 99})
        result = p.build_study('FI', prep, cfg, timing, prices)
        self.assertEqual(result['joint_geometry_coverage']['uncovered_count'], 240)

    def test_dominance_respects_mode_and_policy(self):
        prep, cfg, timing, prices = fixture()
        timing['rows'][0].update(p=2, spec=copy.deepcopy(prep['packages'][0]['spec']))
        result = p.build_study('FI', prep, cfg, timing, prices)
        self.assertEqual(result['joint_geometry_coverage']['uncovered_count'], 180)
        timing['rows'][0]['spec']['feature_policy'] = 'another_policy'
        self.assertEqual(p.build_study('FI', prep, cfg, timing, prices)['joint_geometry_coverage']['uncovered_count'], 240)

    def test_boolean_dimensions_and_reservations_rejected(self):
        self.reject(lambda prep, *_: prep['tasks'][0].update(p=True))
        self.reject(lambda prep, cfg, timing, prices: next(iter(prices['task_estimates'].values())).update(reserved_CPU=True))

    def test_mode_omission_rejected(self):
        self.reject(lambda prep, cfg, timing, prices: timing.update(rows=[{**r, 'mode': 'D'} for r in timing['rows']]))

    def test_expansion_roles_rejected(self):
        self.reject(lambda prep, cfg, *_: cfg.update(AL_authorized=True))
        self.reject(lambda prep, *_: prep.update(test_opened=True))

    def test_imported_reuse_has_no_new_reservation(self):
        prep, cfg, timing, prices = fixture(); task = prep['tasks'][0]
        task['reuse'] = {'retained': 'prior accepted component'}
        price = prices['task_estimates'][task['name']]; price.update(imported=copy.deepcopy(task['reuse']))
        with self.assertRaises(ValueError):
            p.build_study('FI', prep, cfg, timing, prices)
        price.update(reserved_CPU=0, reserved_wall=0)
        result = p.build_study('FI', prep, cfg, timing, prices)
        self.assertEqual(result['imported_reference_count'], 1)
        self.assertEqual(result['tasks'][0]['measurement_role'], 'REFERENCE_ONLY_RETAINED_REUSE')

    def test_native_profile_required(self):
        self.reject(lambda prep, cfg, timing, prices: timing['actual_reference_numerical_profile'].update(enabled=False))

    def test_null_import_is_preserved_and_boolean_substitution_rejected(self):
        prep, cfg, timing, prices = fixture()
        self.assertIsNone(prices['task_estimates'][prep['tasks'][0]['name']]['imported'])
        p.build_study('FI', prep, cfg, timing, prices)
        prices['task_estimates'][prep['tasks'][0]['name']]['imported'] = False
        with self.assertRaises(ValueError):
            p.build_study('FI', prep, cfg, timing, prices)

    def test_boolean_seed_and_path_float_rejected(self):
        self.reject(lambda prep, *_: prep['tasks'][0].update(seed_index=False))
        self.reject(lambda prep, *_: prep['tasks'][0].update(paths=100.0))


class BoundaryTests(unittest.TestCase):
    def test_numerical_authority_forgery_rejected(self):
        request = dict(schema=p.REQUEST_SCHEMA, purpose='METADATA_ONLY_PROSPECTIVE_EXECUTION_PROFILE',
            numerical_execution_authorized=True, full_screening_admitted=False, studies={}, accepted_prices={}, source_pins={})
        with self.assertRaises(ValueError):
            p.compile_request(request)

    def test_unknown_role_rejected(self):
        request = dict(schema=p.REQUEST_SCHEMA, purpose='COST_ONLY', numerical_execution_authorized=False,
            full_screening_admitted=False, studies={}, accepted_prices={}, source_pins={})
        with self.assertRaises(ValueError):
            p.compile_request(request)

    def test_extra_gate_override_rejected(self):
        with self.assertRaises(ValueError):
            p.compile_request({'numerical_execution_authorized': False, 'all_gates_passed': True})

    def test_changed_metadata_pin_and_array_extension_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / 'input.json'; f.write_text('{}')
            with self.assertRaises(ValueError):
                p.read_pin({'path': str(f), 'sha256': 'a' * 64})
            with self.assertRaises(ValueError):
                p.read_pin({'path': str(f.with_suffix('.npz')), 'sha256': 'a' * 64})

    def test_symlink_metadata_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / 'input.json'; f.write_text('{}'); s = Path(tmp) / 'link.json'; s.symlink_to(f)
            with self.assertRaises(ValueError):
                p.read_pin({'path': str(s), 'sha256': hashlib.sha256(b'{}').hexdigest()})

    def test_duplicate_json_keys_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / 'input.json'; f.write_text('{"x":1,"x":2}')
            with self.assertRaises(ValueError):
                p.read_pin({'path': str(f), 'sha256': hashlib.sha256(f.read_bytes()).hexdigest()})

    def test_nonfinite_and_relative_metadata_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / 'input.json'; f.write_text('{"value":NaN}')
            with self.assertRaises(ValueError):
                p.read_pin({'path': str(f), 'sha256': hashlib.sha256(f.read_bytes()).hexdigest()})
        with self.assertRaises(ValueError):
            p.read_pin({'path': 'relative.json', 'sha256': 'a' * 64})

    def test_nested_numeric_overflow_rejected_before_contract_use(self):
        for raw in ['{"nested":[{"v":1e309}]}', '{"nested":[-1e309]}']:
            with self.assertRaisesRegex(ValueError, 'nonfinite JSON'):
                p.decode_json(raw)

    def test_changed_file_between_stat_and_open_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / 'input.json'; f.write_text('{}')
            real_open = p.os.open
            def replace_before_open(path, flags):
                f.write_text('{"changed":true}')
                return real_open(path, flags)
            with mock.patch.object(p.os, 'open', side_effect=replace_before_open):
                with self.assertRaisesRegex(ValueError, 'changed before open'):
                    p.bounded_bytes(f)

    def test_altered_accepted_price_hash_rejected(self):
        folder = Path(p.__file__).parent
        request = dict(schema=p.REQUEST_SCHEMA, purpose='METADATA_ONLY_PROSPECTIVE_EXECUTION_PROFILE',
            numerical_execution_authorized=False, full_screening_admitted=False,
            studies={'FI': {}, 'DK2': {}}, accepted_prices={'path': '/forged.json', 'sha256': 'a' * 64},
            source_pins={role: {'path': str(folder / (role + '.py')), 'sha256': digest} for role, digest in p.SOURCE_HASHES.items()})
        with self.assertRaisesRegex(ValueError, 'price certificate changed'):
            p.compile_request(request)

    def test_output_create_only_atomic(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / 'out.json'; p.write_new(f, {'status': 'PREPARED_NOT_ADMITTED'})
            old = f.read_bytes()
            with self.assertRaises(FileExistsError):
                p.write_new(f, {'status': 'changed'})
            self.assertEqual(f.read_bytes(), old)
            self.assertEqual([q.name for q in Path(tmp).iterdir()], ['out.json'])

    def test_original_lifecycle_source_anchors(self):
        folder = Path(p.__file__).parent
        refs = {role: {'path': str(folder / (role + '.py')), 'sha256': digest} for role, digest in p.SOURCE_HASHES.items()}
        sources = {role: p.read_pin(ref, source=True) for role, ref in refs.items()}
        mapping = p.instrumentation(sources, refs)
        self.assertEqual(len(mapping), 13)
        self.assertEqual([r['phase'] for r in mapping if not r['in_actual_component']], ['all_parent_preflight_comparison'])
        self.assertEqual(set(p.environment_from_source(sources['environment']).values()) - {'1'},
                         {'Sandybridge', 'AVX2,FMA3,F16C,AVX512F,AVX512CD,AVX512_KNL,AVX512_KNM,AVX512_SKX,AVX512_CLX,AVX512_CNL,AVX512_ICL'})


if __name__ == '__main__':
    unittest.main()
