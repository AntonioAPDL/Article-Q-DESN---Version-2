"""Adversarial saved-metadata checks; no numerical source imports."""
import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from . import dispatch_diagnosis as d


def sample(*, permitted=False, complete=False):
    return {'schema': d.OBSERVER_SCHEMA, 'epoch': 100., 'host_context': {'host': 'muscat.be.ucsc.edu'},
            'execution_source': {'head': d.SOURCE_HEAD, 'branch': d.SOURCE_BRANCH,
                                 'runtime_sha256': {'application/scripts/pricefm/' + n: s for n, s in d.SOURCE_HASHES.items()}},
            'healthy_control': True, 'dispatch_currently_permitted': permitted,
            'recorded_phase': 'running' if permitted else 'deferred_census_visibility',
            'status': 'CONTROL_RUNNING' if permitted else 'CONTROL_HEALTHY_DISPATCH_DEFERRED',
            'numerical_worker_signals': 0, 'runtime_writes': 0,
            'census': {'host': 'muscat.be.ucsc.edu', 'complete': complete, 'full_host_view_verified': True,
                       'unresolved': [] if complete else [{'pid': 7, 'boot_id': 'boot', 'stat': {'start_ticks': 50},
                          'comm': 'sshd', 'error': 'PermissionError', 'unavailable_fields': ['cwd', 'executable']}]}}


class DiagnosisTests(unittest.TestCase):
    def test_persistent_exact_lifetime_is_blocked_without_classification(self):
        old, new = sample(), sample(); new['epoch'] = 101
        r = d.diagnose(new, old, now_epoch=102)
        self.assertEqual(r['status'], 'BLOCKED_PROVENANCE_VISIBILITY')
        self.assertTrue(r['unresolved'][0]['same_recorded_lifetime_as_prior'])
        self.assertFalse(r['unresolved'][0]['role_classified'])
        self.assertFalse(r['dispatch_authorized_by_this_diagnostic'])
        self.assertTrue(r['not_a_Jerez_R143_dispatch_observation'])

    def test_pid_reuse_or_boot_change_is_not_same_lifetime(self):
        old = sample()
        for field, value in [('boot_id', 'other'), ('stat', {'start_ticks': 51})]:
            new = sample(); new['census']['unresolved'][0][field] = value
            self.assertFalse(d.diagnose(new, old, now_epoch=101)['unresolved'][0]['same_recorded_lifetime_as_prior'])

    def test_complete_scan_does_not_replace_owner_reconciliation(self):
        r = d.diagnose(sample(complete=True), now_epoch=101)
        self.assertEqual(r['status'], 'AWAIT_SOURCE_OWNER_RECONCILIATION')
        self.assertFalse(r['dispatch_authorized_by_this_diagnostic'])

    def test_source_permitted_snapshot_still_is_not_new_authority(self):
        r = d.diagnose(sample(permitted=True, complete=True), now_epoch=200)
        self.assertTrue(r['historical_snapshot_only'])
        self.assertTrue(r['source_snapshot_dispatch_permitted'])
        self.assertFalse(r['dispatch_authorized_by_this_diagnostic'])

    def test_inconsistent_complete_or_permitted_census_rejected(self):
        for v in [sample(permitted=True), sample()]:
            if not v['dispatch_currently_permitted']:
                v['census']['complete'] = True
            with self.assertRaises(ValueError):
                d.diagnose(v, now_epoch=101)

    def test_wrong_host_runtime_or_mutation_rejected(self):
        for field, value in [('host_context', {'host': 'jerez.be.ucsc.edu'}),
                             ('runtime_writes', 1), ('numerical_worker_signals', 1),
                             ('healthy_control', 1), ('runtime_writes', False)]:
            v = sample(); v[field] = value
            with self.assertRaises(ValueError): d.diagnose(v, now_epoch=101)
        v = sample(); v['execution_source']['runtime_sha256'].pop(next(iter(v['execution_source']['runtime_sha256'])))
        with self.assertRaises(ValueError): d.diagnose(v, now_epoch=101)

    def test_future_and_reversed_history_rejected(self):
        with self.assertRaises(ValueError): d.diagnose(sample(), now_epoch=90)
        old = sample(); old['epoch'] = 102
        with self.assertRaises(ValueError): d.diagnose(sample(), old, now_epoch=103)

    def test_metadata_pin_change_symlink_and_nonfinite_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory) / 'observation.json'; p.write_text(json.dumps(sample()))
            ref = {'path': str(p), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
            self.assertEqual(d.pinned_json(ref)['epoch'], 100)
            link = Path(directory) / 'link.json'; link.symlink_to(p)
            with self.assertRaises(ValueError): d.pinned_json(dict(ref, path=str(link)))
            p.write_text('{}')
            with self.assertRaises(ValueError): d.pinned_json(ref)
            p.write_text('{"x":NaN}')
            with self.assertRaises(ValueError): d.pinned_json({'path': str(p), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()})
            for raw in ['{"x":1e309}', '{"role":1,"role":2}']:
                p.write_text(raw)
                with self.assertRaises(ValueError): d.pinned_json({'path': str(p), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()})

    def test_request_cannot_add_authority(self):
        with self.assertRaises(ValueError):
            d.compile_request({'schema': 'r163_dispatch_request_v1', 'current': {}, 'prior': None,
                               'dispatch_authorized': True})


if __name__ == '__main__':
    unittest.main()
