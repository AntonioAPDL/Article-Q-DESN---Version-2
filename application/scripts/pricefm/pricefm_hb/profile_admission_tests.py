"""Private metadata admission tests; no arrays, compute or network calls."""
import copy
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from . import profile_admission as a
from . import execution_profile as e
from . import execution_profile_plan as planning
from .environment import REFERENCE_NUMERICAL_ENV


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pricefm-r164-gate-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.now = 2000000000.0
        self.sources = e.source_closure()
        self.allocation = {'job_id': '123456', 'node': 'node-13', 'affinity': [7], 'cpus_per_task': 1,
                           'allocation_nodes': ['node-13']}
        self.actual = {'job_id': '123456', 'cpus': 1, 'tasks': 1, 'nodes': 1, 'requeue': False,
                       'memory_MiB': 4096, 'wall_seconds': 1200, 'cgroup_memory_limit_bytes': 4096*1024**2,
                       'end_epoch': self.now+1100}
        disabled = REFERENCE_NUMERICAL_ENV['NPY_DISABLE_CPU_FEATURES'].split(',')
        native = {'enabled': True, 'environment': REFERENCE_NUMERICAL_ENV,
                  'numpy_cpu_features': {k: False for k in disabled},
                  'numpy_dispatch_targets': disabled, 'openblas_architectures': ['Sandybridge']}
        self.runtime = {'status': 'verified', 'allocation': self.allocation,
                        'python_version': '3.11.0', 'executable': '/owned/python', 'versions': {'numpy': 'test'},
                        'threadpoolctl': [{'num_threads': 1}], 'reference_numerical_profile': native,
                        'native_library_sha256': {'/owned/one.so': '1'*64, '/owned/two.so': '2'*64}}
        self.limits = {'aggregate_cpu_seconds': 500, 'wall_seconds': 900, 'memory_MiB': 4096}
        self.whole = {'aggregate_cpu_seconds': 600, 'wall_seconds': 1200, 'memory_MiB': 4096,
                      'wrapper_cpu_seconds': 100, 'ready_reserve_seconds': 270, 'exit_reserve_seconds': 30}
        self.scope = 'r164-profile-' + 'a'*32
        history = self.put('history', {'old_scope_renewed': False, 'old_charges_refunded': False,
                                      'retained_evidence': [self.put('old', {'status': 'EXPIRED_RETAINED'})]})
        policy = {'schema': a.POLICY_SCHEMA, 'status': 'ROOT_ADMITTED_NEW_PROFILE_WINDOW',
                  'purpose': a.PURPOSE, 'controller': a.OWNER, 'created_epoch': self.now-100,
                  'expires_epoch': self.now+7200, 'max_workers': 1, 'cpus_per_task': 1,
                  'numerical_threads': 1, 'HB_total_CPU_ceiling': 72, 'Jerez_extra_workers': 0,
                  'Muscat_new_numerical_workers': 0, 'legacy_scope_renewed': False,
                  'old_charges_refunded': False, 'baseline_allocations_changed': False,
                  'scientific_rules_changed': False, 'profile_only': True,
                  'new_profile_CPU_budget': 2000, 'prior_history': history}
        auth = {'status': 'ROOT_REVIEWED_R164_NEW_PROFILE_POLICY', 'user_requested_implementation': True,
                'policy_scientific_identity_sha256': a.identity(policy)}
        policy['authorization'] = self.put('policy_auth', auth)
        self.policy_pin = self.put('policy', policy)
        # Private synthetic metadata make this test suite portable. The actual
        # R163 contract/cost/native pins are exercised separately by integration
        # packets; the override exists only inside this owned unittest fixture.
        cost_pin = self.put('canonical_cost', {'study': 'DK2'})
        canonical = patch.dict(planning.CANONICAL, {'DK2': {'cost_plan': cost_pin['sha256']}})
        canonical.start(); self.addCleanup(canonical.stop)
        profile = {'schema': 'r163_execution_profile_plan_v1',
                   'purpose': 'PROSPECTIVE_ACTUAL_COMPONENT_PROFILE_PREPARATION',
                   'numerical_execution_authorized': False, 'full_screening_admitted': False,
                   'input_pins': {'studies': {'DK2': {'cost_plan': cost_pin}}},
                   'studies': {'DK2': {'tasks': [{'name': 'DK_2_C0_s1_D_seed0', 'task_sha256': '3'*64,
                                               'imported': False}],
                                       'numerical_environment_evidence': dict(native, native_library_sha256=self.runtime['native_library_sha256'])}}}
        original = Path(self.put('profile', profile)['path'])
        self.request = {'schema': a.REQUEST_SCHEMA, 'purpose': a.PURPOSE,
                        'profile_plan': {'path': str(original), 'sha256': a.digest(original)},
                        'cost_plan': cost_pin, 'policy': self.policy_pin, 'study': 'DK2',
                        'task': 'DK_2_C0_s1_D_seed0', 'task_sha256': profile['studies']['DK2']['tasks'][0]['task_sha256'],
                        'stage_root': str(self.root), 'execution_order': ['reference', 'instrumented'],
                        'storage_mode': 'DIRECT_RETAINED_SOURCE'}
        self.request_pin = self.put('request', self.request)
        self.attestation = {'schema': 'r164_profile_job_attestation_v1', 'status': 'COMPUTE_READY',
                            'scope_id': self.scope, 'allocation': self.allocation,
                            'observed_epoch': self.now-10, 'runtime': self.runtime, 'scheduler_resources': self.actual}
        self.attestation_pin = self.put('attestation', self.attestation)
        self.review = {'schema': 'r164_profile_source_review_v1', 'status': 'PASS',
                       'request_sha256': self.request_pin['sha256'], 'policy': self.policy_pin,
                       'source_files': self.sources, 'phase': 'QUALIFICATION_PAIR', 'limits': self.limits,
                       'allocation_limits': self.whole,
                       'whole_component_reference_is_frozen': True, 'fixed_reference_then_instrumented': True,
                       'all_old_scopes_and_charges_preserved': True}
        funding = {'schema': 'r164_profile_funding_v1', 'scope_id': self.scope,
                   'phase': 'QUALIFICATION_PAIR', 'status': 'RESERVED_BEFORE_SUBMISSION',
                   'reserved_CPU_seconds': 600, 'cumulative_reserved_CPU_seconds': 600,
                   'old_claims_reused': False, 'failed_charges_refunded': False}
        reservation = {'schema': 'r164_profile_reservation_v1', 'status': 'CPU_RESERVED_BEFORE_SUBMISSION',
                       'scope_id': self.scope, 'request_sha256': self.request_pin['sha256'],
                       'phase': 'QUALIFICATION_PAIR', 'reserved_CPU_seconds': 600,
                       'cumulative_reserved_CPU_seconds': 600, 'source_files': self.sources,
                       'created_epoch': self.now-90}
        reserve_pin = self.put('reservation', reservation)
        submitted = {'status': 'HELD_SUBMISSION_JOB_IDENTIFIED', 'scope_id': self.scope,
                     'job_id': self.allocation['job_id'], 'reservation': reserve_pin, 'created_epoch': self.now-80}
        funding.update(reservation=reserve_pin, submission=self.put('submission', submitted),
                       job_id=self.allocation['job_id'], request_sha256=self.request_pin['sha256'],
                       source_files=self.sources)
        self.authority = {'schema': a.AUTHORITY_SCHEMA, 'status': 'ROOT_ADMITTED_COMPONENT_PROFILE_PAIR',
                          'purpose': a.PURPOSE, 'controller': a.OWNER, 'phase': 'QUALIFICATION_PAIR',
                          'request_sha256': self.request_pin['sha256'], 'policy': self.policy_pin,
                          'scope_id': self.scope, 'created_epoch': self.now-20, 'expires_epoch': self.now+2000,
                          'limits': self.limits, 'allocation_limits': self.whole, 'new_model_fits': 0, 'official_origins': 0,
                          'selection_authorized': False, 'repricing_authorized': False,
                          'automatic_retry': False, 'promotion_authorized': False,
                          'job_id': '123456', 'node': 'node-13', 'source_files': self.sources,
                          'review': self.put('review', self.review), 'attestation_sha256': self.attestation_pin['sha256'],
                          'output_root': str(self.root/'ACTUAL_COMPONENT_PROFILE'/self.scope),
                          'parity_runtime': self.runtime, 'funding': self.put('funding', funding)}
        self.review['authority_contract_sha256'] = a.identity({k: v for k, v in self.authority.items() if k != 'review'})
        self.authority['review'] = self.put('review', self.review)
        self.mock_scheduler = patch.object(a, 'scheduler_evidence', return_value=self.actual)
        self.mock_scheduler.start()
        self.addCleanup(self.mock_scheduler.stop)

    def put(self, name, value):
        path = self.root/(name+'.json')
        path.write_text(json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False))
        return {'path': str(path), 'sha256': a.digest(path)}

    def run_gate(self, **changes):
        values = dict(request=self.request, request_sha256=self.request_pin['sha256'],
                      authority=self.authority, authority_sha256='f'*64,
                      attestation=self.attestation, attestation_sha256=self.attestation_pin['sha256'],
                      allocation=self.allocation, executed_sources=self.sources, now=self.now)
        values.update(changes)
        return a.validate_worker(**values)

    def test_complete_positive_metadata_fixture(self):
        self.assertEqual(self.run_gate()['scope_id'], self.scope)

    def test_no_legacy_purpose_or_replay(self):
        for key, value in [('purpose', 'COST'), ('automatic_retry', True), ('new_model_fits', 1),
                           ('selection_authorized', True), ('official_origins', 1)]:
            with self.subTest(key=key), self.assertRaises(a.AdmissionError):
                changed = dict(self.authority, **{key: value})
                self.run_gate(authority=changed)

    def test_source_omission_and_rebinding_rejected(self):
        changed = dict(self.sources); changed.pop('prefix.py')
        with self.assertRaises(a.AdmissionError):
            self.run_gate(executed_sources=changed)

    def test_wrong_job_or_affinity_type_rejected(self):
        for change in ({'job_id': '999'}, {'cpus_per_task': True}, {'affinity': [True]}, {'affinity': [7, 8]}):
            with self.subTest(change=change), self.assertRaises(a.AdmissionError):
                self.run_gate(allocation=dict(self.allocation, **change))

    def test_whole_pair_absolute_window(self):
        with self.assertRaises(a.AdmissionError):
            self.run_gate(authority=dict(self.authority, expires_epoch=self.now+899))

    def test_stale_ready_no_controller(self):
        with self.assertRaises(a.AdmissionError):
            self.run_gate(attestation=dict(self.attestation, observed_epoch=self.now-301))

    def test_child_needs_live_controller_claim(self):
        with self.assertRaises((a.AdmissionError, FileNotFoundError)):
            self.run_gate(role='instrumented')

    def test_scheduler_memory_is_actual_not_flag(self):
        with patch.object(a, 'scheduler_evidence', return_value=dict(self.actual, cgroup_memory_limit_bytes=8192*1024**2)):
            with self.assertRaises(a.AdmissionError): self.run_gate()

    def test_scheduler_wall_cannot_expand(self):
        with patch.object(a, 'scheduler_evidence', return_value=dict(self.actual, wall_seconds=9000)):
            with self.assertRaises(a.AdmissionError): self.run_gate()

    def test_float_bool_and_nonfinite_caps(self):
        for value in (True, float('inf'), -1, 0):
            with self.subTest(value=value), self.assertRaises(a.AdmissionError):
                a.validate_limits(dict(self.limits, aggregate_cpu_seconds=value))

    def test_overflow_duplicate_and_symlink_metadata(self):
        for raw in ('{"x":1e999}', '{"x":1,"x":2}', '{"x":NaN}'):
            path=self.root/'invalid.json';path.write_text(raw)
            with self.assertRaises(a.AdmissionError):
                a.read_pin({'path':str(path),'sha256':a.digest(path)})
        link=self.root/'linked.json';link.symlink_to(self.root/'policy.json')
        with self.assertRaises(a.AdmissionError):a.read_pin({'path':str(link),'sha256':'a'*64})

    def test_new_measurement_needs_real_qualification(self):
        authority=dict(self.authority, phase='MEASUREMENT_PAIR')
        review=dict(self.review, phase='MEASUREMENT_PAIR')
        authority['review']=self.put('measurement_review', review)
        with self.assertRaises((a.AdmissionError, KeyError)):
            self.run_gate(authority=authority)


if __name__ == '__main__':
    unittest.main()
