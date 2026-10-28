"""Private READY/failure stream tests; scheduler boundaries stay mocked."""
import json
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest import mock

from . import activation as a, admission, lifecycle as l, metered_io, registry as r

PY = '/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python'


class StartupStreamTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.key = 'test03-key'
        self.ledger = mock.Mock()
        self.budget = mock.Mock()
        self.release = dict(source_hashes={'lifecycle.py': 'a' * 64}, purpose='CONTROL_TEST')
        release_path = self.root / 'release'
        (release_path / 'authorization').mkdir(parents=True)
        now = time.time()
        self.authority = dict(issued_epoch=now - 1, max_queue_seconds=120,
            calendar_expires_epoch=now + 300)
        authority_path = release_path / 'authorization/authority.json'
        r.write(authority_path, self.authority)
        self.claim = dict(state='SUBMITTED', task_key=self.key, job_id='869999',
            release_sha256='b' * 64, authority_sha256=r.digest(authority_path),
            release_path=str(release_path), remote_root=str(self.root / 'remote'))
        self.config = {'_r157_control_budget': self.budget}
        self.failure = dict(schema=l.SCHEMA, task_key=self.key, job_id=self.claim['job_id'],
            release_sha256=self.claim['release_sha256'], source_hashes=self.release['source_hashes'],
            authority_sha256=self.claim['authority_sha256'], application_passed=False,
            error={'type': 'ActivationError', 'message': 'private pre-READY failure'})
        bound = mock.patch.object(l, '_bound_claim', return_value=(self.ledger, self.claim, self.release, self.config))
        bound.start()
        self.addCleanup(bound.stop)

    def test_verified_failure_stops_before_refresh_or_activation_and_never_sets_ready_pin(self):
        destination = self.root / 'activation'
        event = dict(event='FAILED', evidence=self.failure)
        with mock.patch.object(l, 'release_job') as released, \
                mock.patch.object(metered_io, 'watch', return_value=json.dumps(event)) as watched, \
                mock.patch.object(admission, 'refresh_request') as refresh, \
                mock.patch.object(l, 'activate') as activate:
            with self.assertRaises(a.ActivationError):
                l.release_and_activate(self.key, 'site', 'operator', 'plan', destination)
        released.assert_called_once_with(self.key, 'site')
        watched.assert_called_once()
        refresh.assert_not_called()
        activate.assert_not_called()
        self.budget.start_operation.assert_not_called()
        self.ledger.update.assert_called_once_with(self.key, startup_event_claimed=True)
        self.assertFalse((destination / 'ready.json').exists())
        self.assertEqual(r.read(destination / 'worker-failure-event.json'), event)

    def test_wrong_negative_identity_source_authority_or_pass_flag_is_rejected(self):
        changes = ({'job_id': '1'}, {'release_sha256': 'c' * 64}, {'task_key': 'other'},
            {'source_hashes': {'wrong': 'd' * 64}}, {'authority_sha256': 'e' * 64},
            {'schema': 'wrong'}, {'application_passed': True}, {'error': None})
        for index, change in enumerate(changes):
            with self.subTest(change=change):
                event = dict(event='FAILED', evidence=dict(self.failure, **change))
                destination = self.root / str(index) / 'ready.json'
                with mock.patch.object(metered_io, 'watch', return_value=json.dumps(event)):
                    with self.assertRaises(a.ActivationError):
                        l.watch_ready(self.key, 'site', destination)
                self.assertFalse(destination.exists())
                self.assertFalse(destination.with_name('worker-failure-event.json').exists())
        self.assertTrue(all('ready_pin' not in call.kwargs for call in self.ledger.update.call_args_list))

    def test_positive_READY_retains_existing_pin_behavior_and_single_exact_bounded_stream(self):
        ready = dict(schema=a.READY_SCHEMA, job_id=self.claim['job_id'],
            release_sha256=self.claim['release_sha256'])
        destination = self.root / 'ready.json'
        before = time.time()
        with mock.patch.object(metered_io, 'watch', return_value=json.dumps(dict(event='READY', evidence=ready))) as watched:
            self.assertEqual(l.watch_ready(self.key, 'site', destination), ready)
        self.assertEqual(r.read(destination), ready)
        self.assertEqual(self.ledger.update.call_args_list[-1], mock.call(self.key, ready_pin=l.pin(destination)))
        args, kwargs = watched.call_args
        self.assertEqual(args[0], self.config)
        self.assertIs(args[2], self.budget)
        self.assertEqual(args[3], self.key)
        script = args[1]
        self.assertEqual(script.count('pathlib.Path('), 2)
        self.assertIn(repr(self.claim['remote_root'] + '/outputs/ready.json'), script)
        self.assertIn(repr(self.claim['remote_root'] + '/outputs/worker_evidence.json'), script)
        self.assertIn('resource.setrlimit(resource.RLIMIT_CPU,(10,10))', script)
        end = min(self.authority['issued_epoch'] + 120, self.authority['calendar_expires_epoch'])
        self.assertIn('deadline=' + repr(end), script)
        self.assertGreater(kwargs['timeout'], 1)
        self.assertLessEqual(kwargs['timeout'], end - before + 5)
        for command in ('scontrol', 'squeue', 'sacct'):
            self.assertNotIn(command, script)

    def test_captured_private_stream_wakes_immediately_for_existing_failure_file(self):
        event = dict(event='FAILED', evidence=self.failure)
        with mock.patch.object(metered_io, 'watch', return_value=json.dumps(event)) as watched:
            with self.assertRaises(a.ActivationError):
                l.watch_ready(self.key, 'site', self.root / 'ready.json')
        remote_outputs = Path(self.claim['remote_root']) / 'outputs'
        remote_outputs.mkdir(parents=True)
        r.write(remote_outputs / 'worker_evidence.json', self.failure)
        started = time.monotonic()
        result = subprocess.run([PY, '-B', '-c', watched.call_args.args[1]],
            text=True, capture_output=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), event)
        self.assertLess(time.monotonic() - started, 3)


if __name__ == '__main__':
    unittest.main()
