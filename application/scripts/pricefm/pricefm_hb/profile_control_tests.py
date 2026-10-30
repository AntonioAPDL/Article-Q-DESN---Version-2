"""Private lifecycle/accounting fixtures; no SSH, Slurm or numerical execution."""
import copy
import hashlib
import json
import os
import shutil
import shlex
from pathlib import Path
import tempfile
import subprocess
import sys
import time
import unittest
from unittest.mock import patch

from . import profile_control as c
from . import registry as r
from .execution_profile_tests import fixture_pair


def inner_command(argv):
    text = argv[-1]; tokens = shlex.split(text)
    if len(tokens) >= 8 and tokens[0] in ('python3','/usr/bin/python3') and tokens[1:4] == ['-I', '-B', '-c'] and '--passthrough' in tokens and '--' in tokens:
        return shlex.join(tokens[tokens.index('--') + 1:])
    return text


class Fixture:
    def __init__(self, base, scope='r164-profile-' + 'a' * 32):
        self.base = base; self.scope = scope
        self.remote = '/home/jaguir26/pricefm_hb_r164/' + scope
        self.files = []
        self.workers = {'__init__.py': hashlib.sha256(b'# empty\n').hexdigest()}
        self.controllers = dict(self.workers, **{'profile_control.py': hashlib.sha256(b'# controller\n').hexdigest()})
        for name, raw in [('__init__.py', b'# empty\n'), ('profile_control.py', b'# controller\n')]:
            path = base / ('source_' + name); path.write_bytes(raw)
            self.files.append(dict(local=str(path), relative='code/pricefm_hb/' + name,
                                   sha256=hashlib.sha256(raw).hexdigest(), bytes=len(raw)))
        self.policy = self.metadata('policy', {'purpose': 'distinct'})
        cost=self.metadata('cost_plan',{'input_allowlist':{}})
        compiler=self.metadata('compiler_output',{})
        self.profile=self.metadata('profile_plan',{'profile_delivery_binding':dict(schema=c.e.DELIVERY_SCHEMA,
            source_files=self.workers,compiler_output=compiler,contract_source=dict(path=c.e.p.CONTRACT_PATH,
                sha256=c.e.p.CONTRACT_SHA,bytes=c.e.SUPPORT_BYTES),authority=False)})
        support_path=base/'profile_contract.py';support_path.write_bytes(c.e.bounded_read(c.e.p.CONTRACT_PATH))
        self.support=dict(schema=c.e.SUPPORT_SCHEMA,role=c.e.SUPPORT_ROLE,logical_path=c.e.p.CONTRACT_PATH,
            path=self.remote+'/'+c.e.SUPPORT_RELATIVE,sha256=c.e.p.CONTRACT_SHA,bytes=c.e.SUPPORT_BYTES)
        self.files.append(dict(local=str(support_path),relative=c.e.SUPPORT_RELATIVE,
                               sha256=c.e.p.CONTRACT_SHA,bytes=c.e.SUPPORT_BYTES))
        self.request_value = {'policy': self.policy,'cost_plan':cost,'profile_plan':self.profile,
            'profile_support':self.support,'stage_root':'/owned/retained/stage','task_sha256':'3'*64}
        self.request = self.metadata('request', self.request_value)
        self.reservation = self.metadata('reservation', dict(schema='r164_profile_reservation_v1',
            status='CPU_RESERVED_BEFORE_SUBMISSION', scope_id=scope, phase='QUALIFICATION_PAIR',
            request_sha256=self.request['sha256'], source_files=self.workers, reserved_CPU_seconds=600,
            cumulative_reserved_CPU_seconds=600, created_epoch=time.time() - 1))
        key = base / 'test_private_key'; key.write_text('dummy-fixture-only')
        hosts = base / 'test_known_hosts'; hosts.write_text('dummy-fixture-only')
        site = dict(host='hb.ucsc.edu', user='jaguir26', account='128x24', partition='128x24', qos='normal',
            known_hosts_file=str(hosts), ssh_identity_file=str(key), remote_root='/home/jaguir26/pricefm_hb_r164')
        path = base / 'site.json'; r.write(path, site); self.site = c.pin(path)
        self.limits = dict(aggregate_cpu_seconds=500, wall_seconds=900, memory_MiB=2048)
        self.whole = dict(c.PHASE_LIMITS['QUALIFICATION_PAIR'], memory_MiB=2048)
        self.controls = dict(max_operations=32, operation_wall_seconds=20, operation_CPU_seconds=2,
            max_output_bytes=1024**2, transport_CPU_seconds=40, transport_wall_seconds=120,
            proof_CPU_seconds=5, proof_wall_seconds=30, validation_CPU_seconds=40, validation_wall_seconds=180,
            local_administrative_CPU_reserve_seconds=5, max_status_polls=3,
            ready_CPU_seconds=5, ready_wall_seconds=120, ready_wait_seconds=100,
            max_transfer_bytes=1024**3, aggregate_reserved_CPU_seconds=400, aggregate_reserved_wall_seconds=1800)
        self.publication = self.metadata('publication', dict(status='VERIFIED_FEATURE_PUBLICATION',
            source_files=self.controllers, fresh_remote_hash_verified=True))
        review = dict(status='PASS_REVIEWED_NEW_PROFILE_LIFECYCLE', scope_id=scope, request=self.request,
            worker_sources=self.workers, controller_sources=self.controllers, allocation_limits=self.whole,
            worker_limits=self.limits, controller_limits=self.controls, no_old_grants_reused=True)
        self.review = self.metadata('prelaunch_review', review)
        self.spec = dict(schema=c.SCHEMA, scope_id=scope, phase='QUALIFICATION_PAIR', created_epoch=time.time() - 5,
            expires_epoch=time.time() + 20000, controller_expires_epoch=time.time() + 21000,
            request=self.request, remote_root=self.remote,
            output_root=self.remote + '/outputs/ACTUAL_COMPONENT_PROFILE/' + scope,
            runtime_python='/home/jaguir26/accepted/runtime/venv/bin/python', environment_bundle='/home/jaguir26/accepted/env',
            node='node-13', worker_limits=self.limits, allocation_limits=self.whole, worker_sources=self.workers,
            controller_sources=self.controllers, files=self.files, funding_reservation=self.reservation,
            prelaunch_review=self.review, feature_publication=self.publication, qualification=None,
            site=self.site, controller_limits=self.controls, environment_provenance={})
        review['spec_contract_sha256'] = c.spec_contract(self.spec)
        review_path = base / 'prelaunch_review.json'; review_path.write_text(json.dumps(review))
        item = next(item for item in self.files if item['relative'] == 'metadata/prelaunch_review.json')
        item.update(sha256=r.digest(review_path), bytes=review_path.stat().st_size)
        self.review['sha256'] = item['sha256']
        self.spec_path = base / 'spec.json'; self.save()
        self.calls = []; self.lost_sbatch = False
    def metadata(self, name, value):
        path = self.base / (name + '.json'); r.write(path, value)
        self.files.append(dict(local=str(path), relative='metadata/' + name + '.json',
                               sha256=r.digest(path), bytes=path.stat().st_size))
        return dict(path=self.remote + '/metadata/' + name + '.json', sha256=r.digest(path))
    def save(self):
        self.spec_path.write_text(json.dumps(self.spec))
    def runner(self, argv, **kw):
        self.calls.append(argv)
        text = inner_command(argv)
        if '--task' in argv and any(value.endswith('profile_stream.py') for value in argv): return ''
        if text.startswith('squeue'): return ''
        if text.startswith('sha256sum'):
            return r.digest(c.CENTRAL / self.scope / 'release/release_manifest.json') + ' file\n'
        if 'os.execvpe' in text and 'sbatch' in text:
            records = c.Journal.__new__(c.Journal); records.root = c.CENTRAL / self.scope
            self.asserted_intent = any(x['state'] == 'SUBMISSION_INTENT' for x in records.records())
            if self.lost_sbatch: raise TimeoutError('lost reply fixture')
            return '123;hummingbird\n'
        if text.startswith('scontrol show job'):
            return 'JobId=123 JobName=' + self.scope + ' WorkDir=' + self.remote + (
                ' JobState=PENDING UserId=jaguir26(123) NumCPUs=1 NumTasks=1 NumNodes=1-1 CPUs/Task=1 Requeue=0'
                ' Reason=JobHeldUser RunTime=00:00:00 StartTime=Unknown AllocTRES=(null)'
                ' Account=128x24 Partition=128x24 QOS=normal TimeLimit=00:20:00 MinMemoryNode=2048M'
                ' Command=' + self.remote + '/job.sh ReqNodeList=node-13 TresPerTask=cpu=1')
        if 'every' not in text and 'VERIFIED ' in text:
            return 'VERIFIED ' + r.digest(c.CENTRAL / self.scope / 'release/release_manifest.json')
        if text.startswith(('mkdir', 'scontrol release', 'test ')): return ''
        raise AssertionError('unmocked network command: ' + repr(argv))


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.base = Path(self.tmp.name)
        self.f = Fixture(self.base)
        self.patches = [patch.object(c, 'CENTRAL', self.base / 'canonical'), patch.object(c, 'owner'),
                        patch.object(c.e, 'source_closure', return_value=self.f.workers),
                        patch.object(c, 'controller_sources', return_value=self.f.controllers),
                        patch.object(c.a, 'validate_policy'),
                        patch.object(c, 'runtime_provenance', return_value={'status': 'verified'})]
        for item in self.patches: item.start()
    def tearDown(self):
        for item in reversed(self.patches): item.stop()
        self.tmp.cleanup()
    def prepare(self): return c.prepare_run(self.f.spec_path)
    def submit(self):
        self.prepare(); c.stage_run(self.f.scope, self.f.runner)
        return c.submit_run(self.f.scope, self.f.runner)
    def last(self):
        j = c.Journal(self.f.scope)
        try: return j.last()
        finally: j.close()

    def test_preparation_copies_only_explicit_pinned_source_and_metadata(self):
        self.assertEqual(self.prepare()['state'], 'PREPARED')
        root = c.CENTRAL / self.f.scope / 'release'
        self.assertTrue((root / 'code/pricefm_hb/profile_control.py').is_file())
        self.assertNotIn('test_private_key', {p.name for p in root.rglob('*')})
        script = (root / 'job.sh').read_text()
        self.assertIn('--cpu-bind=cores', script); self.assertIn('--compute-session', script)
        self.assertIn('export PATH=/usr/bin:/bin SLURM_EXPORT_ENV=ALL\n', script)
        self.assertIn('exec /usr/bin/srun ', script)
        self.assertFalse(self.f.calls)

    def test_changed_input_keeps_preparation_intent_and_prevents_rerun(self):
        Path(self.f.files[0]['local']).write_text('changed')
        with self.assertRaisesRegex(ValueError, 'changed'): self.prepare()
        self.assertEqual(self.last()['state'], 'PREPARATION_INTENT')
        with self.assertRaisesRegex(ValueError, 'create-only'): self.prepare()

    def test_held_submission_has_durable_precharged_intent_and_no_retry(self):
        value = self.submit()
        self.assertEqual(value['state'], 'HELD'); self.assertTrue(self.f.asserted_intent)
        command = next(argv[-1] for argv in self.f.calls if 'os.execvpe' in argv[-1] and 'sbatch' in argv[-1])
        self.assertIn('--hold', command); self.assertIn('--no-requeue', command)
        self.assertIn('--time=00:20:00', command)
        with self.assertRaises(ValueError): c.submit_run(self.f.scope, self.f.runner)

    def test_lost_submit_reply_stays_spent_ambiguous_and_blocks_next_scope(self):
        self.f.lost_sbatch = True
        self.prepare(); c.stage_run(self.f.scope, self.f.runner)
        with self.assertRaises(TimeoutError): c.submit_run(self.f.scope, self.f.runner)
        self.assertEqual(self.last()['state'], 'AMBIGUOUS_SPENT')
        with self.assertRaisesRegex(ValueError, 'another new profile'):
            c.single_active('r164-profile-' + 'b' * 32)
        before = len(self.f.calls)
        with self.assertRaises(ValueError): c.submit_run(self.f.scope, self.f.runner)
        self.assertEqual(before, len(self.f.calls))

    def test_owned_held_release_admits_startup_only(self):
        self.submit(); value = c.release_startup(self.f.scope, self.f.runner)
        self.assertEqual(value['state'], 'STARTUP_READY_PENDING')
        self.assertTrue(any(inner_command(argv) == 'scontrol release 123' for argv in self.f.calls))
        self.assertFalse(any('worker_authority' in argv[-1] for argv in self.f.calls))

    def test_foreign_held_job_cannot_be_released(self):
        self.submit(); original = self.f.runner
        def wrong(argv, **kw):
            result = original(argv, **kw)
            return result.replace('UserId=jaguir26', 'UserId=other')
        with self.assertRaisesRegex(ValueError, 'exact owned'):
            c.release_startup(self.f.scope, wrong)
        self.assertFalse(any(inner_command(argv) == 'scontrol release 123' for argv in self.f.calls))

    def test_global_lock_prevents_two_scope_owners(self):
        first = c.Journal(self.f.scope)
        try:
            with self.assertRaises(BlockingIOError): c.Journal('r164-profile-' + 'b' * 32)
        finally: first.close()

    def test_missing_changed_or_duplicate_stage_payload_rejects(self):
        for change in ('duplicate', 'traversal', 'binary', 'shadow'):
            value = copy.deepcopy(self.f.spec)
            if change == 'duplicate': value['files'].append(value['files'][0])
            elif change == 'traversal': value['files'][0]['relative'] = '../source.py'
            elif change == 'binary': value['files'][0]['relative'] = 'models/fit.rds'
            else: value['files'].append(dict(value['files'][0], relative='json.py'))
            with self.subTest(change=change), self.assertRaises(ValueError): c.validate_spec(value)

    def test_old_whole_envelope_or_boolean_budget_cannot_pass(self):
        value = copy.deepcopy(self.f.spec); value['allocation_limits']['aggregate_cpu_seconds'] = 500
        with self.assertRaises(ValueError): c.validate_spec(value)
        value = copy.deepcopy(self.f.spec); value['controller_limits']['operation_CPU_seconds'] = True
        with self.assertRaises(ValueError): c.validate_spec(value)

    def test_expired_work_cannot_launch_but_historical_collection_validation_survives(self):
        now = self.f.spec['expires_epoch'] + 1
        with self.assertRaises(ValueError): c.validate_spec(self.f.spec, now=now)
        c.validate_spec(self.f.spec, now=now, admit_new_work=False)
        with self.assertRaisesRegex(ValueError, 'controller/accounting tail'):
            c.validate_spec(self.f.spec, now=self.f.spec['controller_expires_epoch'] + 1, admit_new_work=False)

    def test_remote_pin_local_resolution_checks_exact_hash(self):
        self.assertEqual(c.spec_read(self.f.spec, self.f.request), self.f.request_value)
        bad = dict(self.f.request, sha256='0' * 64)
        with self.assertRaises(ValueError): c.spec_read(self.f.spec, bad)

    def test_measurement_without_actual_qualification_rejects(self):
        value = copy.deepcopy(self.f.spec); value['phase'] = 'MEASUREMENT_PAIR'
        value['worker_limits'].update(aggregate_cpu_seconds=1500, wall_seconds=3600)
        value['allocation_limits'] = dict(c.PHASE_LIMITS['MEASUREMENT_PAIR'], memory_MiB=2048)
        with self.assertRaises(ValueError): c.validate_spec(value)

    def test_controller_failed_operation_reservation_is_never_refunded(self):
        self.prepare(); j = c.Journal(self.f.scope)
        try:
            controls = copy.deepcopy(self.f.spec); controls['controller_limits']['aggregate_reserved_CPU_seconds'] = 7
            c.operation(j, controls, 'one', ['dummy'], lambda *args, **kw: '')
            with self.assertRaisesRegex(ValueError, 'aggregate controller'):
                c.operation(j, controls, 'two', ['dummy'], lambda *args, **kw: '')
        finally: j.close()

    def test_precharge_cumulative_cannot_be_reset_after_completed_claim(self):
        self.prepare(); j = c.Journal(self.f.scope)
        try: j.put('ACCEPTED')
        finally: j.close()
        value = copy.deepcopy(self.f.spec); value['scope_id'] = 'r164-profile-' + 'b' * 32
        with self.assertRaisesRegex(ValueError, 'phase already consumed|cumulative'):
            c.funding_history(value)

    def test_compute_session_rejects_before_opening_any_fixture_on_admin(self):
        with patch.object(c, 'require_compute', side_effect=RuntimeError('compute only')):
            with self.assertRaisesRegex(RuntimeError, 'compute only'):
                c.compute_session('/absent')

    def test_all_runtime_site_window_fields_are_bound_by_full_spec_review(self):
        for key, value in [('runtime_python', '/home/jaguir26/other/python'), ('environment_bundle', '/home/jaguir26/other/env'),
                           ('node', 'node-14'), ('expires_epoch', self.f.spec['expires_epoch'] + 60)]:
            bad = copy.deepcopy(self.f.spec); bad[key] = value
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'independently reviewed'):
                c.validate_spec(bad)

    def test_one_bounded_ready_notification_checks_actual_owned_fixture(self):
        root = self.base / 'ready_fixture'; root.mkdir()
        ready = dict(status='COMPUTE_READY', scope_id=self.f.scope, allocation={'job_id': '123'},
                     request_sha256=self.f.request['sha256'])
        r.write(root / 'ready.json', ready)
        good = [sys.executable, '-I', '-B', '-c', c.READY_WAITER, str(root), self.f.scope, '123', self.f.request['sha256'], '1']
        result = subprocess.run(good, text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0); self.assertEqual(json.loads(result.stdout), ready)
        bad = good.copy(); bad[-3] = '999'
        self.assertNotEqual(subprocess.run(bad, capture_output=True, timeout=5).returncode, 0)

    def test_readiness_timeout_is_finite_and_retained(self):
        root = self.base / 'no_ready'; root.mkdir()
        command = [sys.executable, '-I', '-B', '-c', c.READY_WAITER, str(root), self.f.scope, '123', self.f.request['sha256'], '1']
        started = time.monotonic(); result = subprocess.run(command, capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0); self.assertLess(time.monotonic() - started, 4)

    def test_self_consistent_returned_parity_universe_cannot_replace_canonical_inputs(self):
        self.prepare()
        root = self.base / 'returned'; pair = root / 'outputs' / 'ACTUAL_COMPONENT_PROFILE' / self.f.scope
        shutil.copytree(c.CENTRAL / self.f.scope / 'release', root)
        pair.mkdir(parents=True); binding = fixture_pair(pair)
        r.write(pair / 'execution_identity.json', binding)
        r.write(pair / 'completed_evidence.json', dict(status='COMPLETE_PAIRED_PROFILE_NOT_SCREENING_ADMISSION',
            exact_whole_component_parity=True, artifacts={}))
        ready = self.base / 'actual_ready.json'
        r.write(ready, dict(allocation=binding['allocation'], runtime={'native_library_sha256': binding['native_library_sha256']}))
        proof = root / 'proof_fixture.json'; r.write(proof, {'fixture': True})
        claim = dict(authority={'sha256': binding['authority_sha256']}, attestation=c.pin(ready), job_id='123',
                     staged_files=[dict(relative='proof_fixture.json', sha256=r.digest(proof))])
        binding['attestation_sha256'] = claim['attestation']['sha256']
        (pair / 'execution_identity.json').write_text(json.dumps(binding))
        spec = copy.deepcopy(self.f.spec); spec['request']['sha256'] = binding['request_sha256']; spec['worker_sources'] = binding['executed_sources']
        trusted = {k: copy.deepcopy(binding[k]) for k in ('expected_packets', 'expected_chunk_identities', 'expected_result')}
        trusted['expected_packets']['checkpoints/clock24_part000/predictions.npz'] = {'truth': {'dtype': '<f8', 'shape': [2]}}
        # Isolate the existing canonical-universe negative boundary. Exact raw
        # READY/readiness counterparts have their own real metadata test.
        request=dict(self.f.request_value,task_sha256=binding['task_sha256'])
        profile=c.spec_read(self.f.spec,self.f.profile)
        readiness=dict(path=self.f.remote+'/input_readiness.json',sha256='4'*64)
        actual_ready=c.read(c.pin(ready));actual_ready['input_readiness']={'expected_component_sha256':r.identity(trusted)}
        binding.update(profile_support=self.f.support,
            profile_delivery_binding_sha256=r.identity(profile['profile_delivery_binding']),input_readiness=readiness)
        (pair/'execution_identity.json').write_text(json.dumps(binding))
        with patch.object(c, 'spec_read', side_effect=lambda _,ref:profile if ref==self.f.profile else request), \
             patch.object(c, 'verify_returned_readiness', return_value=(actual_ready,readiness)), \
             patch.object(c, 'canonical_return_expectation', return_value=trusted):
            with self.assertRaisesRegex(ValueError, 'independently pinned canonical'):
                c.verify_return(root, spec, claim)

    def test_exact_owned_pending_cancellation_preserves_full_failed_reservation(self):
        self.submit(); count = 0; original = self.f.runner
        def cancelling(argv, **kw):
            nonlocal count
            command = inner_command(argv)
            if command.startswith('scontrol show job'):
                count += 1
                value = original(argv, **kw)
                return (value if count == 1 else value.replace('JobState=PENDING', 'JobState=CANCELLED')
                        .replace('NumNodes=1-1', 'NumNodes=1'))
            if command == 'scancel 123': return ''
            if command.startswith('sacct'):
                return '123|CANCELLED|0:15|0|0|00:00:00||None assigned\n'
            return original(argv, **kw)
        result = c.cancel_exact_owned_job(self.f.scope, cancelling)
        self.assertEqual(result['state'], 'FAILED_RECONCILED')
        self.assertEqual(result['charged_CPU_seconds'], 600)
        self.assertFalse(result['retry_or_refund_authorized'])

    def test_cancellation_refuses_foreign_job_before_sending_any_signal(self):
        self.submit(); original = self.f.runner; sent = []
        def foreign(argv, **kw):
            sent.append(inner_command(argv)); value = original(argv, **kw)
            return value.replace('JobName=' + self.f.scope, 'JobName=baseline')
        with self.assertRaisesRegex(ValueError, 'exact owned new job'):
            c.cancel_exact_owned_job(self.f.scope, foreign)
        self.assertNotIn('scancel 123', sent)

    def test_all_SBATCH_environment_defaults_are_scrubbed_before_exec(self):
        code = 'import json,os,sys;print(json.dumps({"keys":[k for k in os.environ if k.startswith("SBATCH_")],"argv":sys.argv[1:]}))'
        env = dict(os.environ, SBATCH_ARRAY_INX='0-999', SBATCH_GRES='gpu:8', SBATCH_MAIL_TYPE='ALL')
        result = subprocess.run([sys.executable, '-I', '-B', '-c', c.SBATCH_ENV_WRAPPER,
            sys.executable, '-I', '-B', '-c', code, '--mail-type=NONE', 'literal$(no_shell)'],
            env=env, capture_output=True, text=True, timeout=10, check=True)
        value = json.loads(result.stdout)
        self.assertEqual(value['keys'], [])
        self.assertEqual(value['argv'], ['--mail-type=NONE', 'literal$(no_shell)'])

    def test_hidden_array_or_GPU_request_is_never_released(self):
        for fields in ({'ArrayJobId': '123', 'ArrayTaskId': '0'}, {'Gres': 'gpu:1'},
                       {'ReqTRES': 'cpu=1,mem=2G,node=1,gres/gpu=1'}):
            with self.subTest(fields=fields), self.assertRaises(ValueError): c._no_hidden_resources(fields)
        c._no_hidden_resources({'ReqTRES': 'cpu=1,mem=2G,node=1,billing=1', 'Gres': '(null)'})

    def test_actual_slurm_single_cpu_held_range_and_cancelled_count(self):
        # Observed on HB job873277: held NumNodes=1-1,TresPerTask=cpu=1;
        # after cancellation NumNodes=1. This fixture retains those exact
        # spellings while substituting the private fixture identity/resources.
        held = self.f.runner(['dummy', 'scontrol show job -o 123'])
        fields = c._owned_fields(held, self.f.spec, '123')
        self.assertEqual(fields['NumNodes'], '1-1')
        self.assertEqual(fields['TresPerTask'], 'cpu=1')
        cancelled = held.replace('JobState=PENDING', 'JobState=CANCELLED').replace('NumNodes=1-1', 'NumNodes=1')
        self.assertEqual(c._owned_fields(cancelled, self.f.spec, '123')['JobState'], 'CANCELLED')
        running = cancelled.replace('JobState=CANCELLED', 'JobState=RUNNING')
        self.assertEqual(c._owned_fields(running, self.f.spec, '123')['NumNodes'], '1')
        with self.assertRaises(ValueError):
            c._owned_fields(running.replace('NumNodes=1 ', 'NumNodes=1-1 '), self.f.spec, '123')

    def test_per_task_cpu_compatibility_rejects_extra_or_ambiguous_resources(self):
        c._no_hidden_resources({'TresPerTask': 'cpu=1'})
        for value in ('cpu=2', 'cpu=0', 'cpu=01', 'cpu:1', 'cpu=1,cpu=1',
                      'cpu=1,gres/gpu=1', 'cpu=1,mem=8G', 'gpu=1', 'unknown=1', 'cpu=', '1'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                c._no_hidden_resources({'TresPerTask': value})
        for name in ('Gres', 'GresDetail', 'TresPerNode', 'TresPerSocket', 'TresPerJob'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                c._no_hidden_resources({'TresPerTask': 'cpu=1', name: 'cpu=1'})

    def test_single_node_range_and_explicit_cpu_task_remain_exact(self):
        text = self.f.runner(['dummy', 'scontrol show job -o 123'])
        for value in ('1-2', '0-1', '01', '1-01', '2', ''):
            with self.subTest(nodes=value), self.assertRaises(ValueError):
                c._owned_fields(text.replace('NumNodes=1-1', 'NumNodes='+value), self.f.spec, '123')
        for value in ('0', '2', '01', ''):
            with self.subTest(cpu_task=value), self.assertRaises(ValueError):
                c._owned_fields(text.replace('CPUs/Task=1', 'CPUs/Task='+value), self.f.spec, '123')
        with self.assertRaises(ValueError):
            c._owned_fields(text.replace(' CPUs/Task=1', ''), self.f.spec, '123')
        for before, after in (('RunTime=00:00:00', 'RunTime=00:00:01'),
                              ('AllocTRES=(null)', 'AllocTRES=cpu=1,mem=2G,node=1')):
            with self.subTest(replacement=after), self.assertRaises(ValueError):
                c._owned_fields(text.replace(before, after), self.f.spec, '123')
        for before, after in (('Reason=JobHeldUser', 'Reason=Resources'),
                              ('StartTime=Unknown', 'StartTime=2026-10-29T14:20:00')):
            fields = dict(c.re.findall(r'(\S+?)=(\S*)', text.replace(before, after)))
            self.assertFalse(c._exact_single_node(fields))
            self.assertTrue(c._exact_single_node(fields, held_only=False))

    def test_command_or_requested_node_mismatch_cannot_cross_owned_job_guard(self):
        text = self.f.runner(['dummy', 'scontrol show job -o 123'])
        for changed in (text.replace('/job.sh', '/baseline.sh'), text.replace('ReqNodeList=node-13', 'ReqNodeList=node-14')):
            with self.assertRaisesRegex(ValueError, 'exact owned new job'):
                c._owned_fields(changed, self.f.spec, '123')

    def test_remote_release_verifier_checks_launcher_bytes_not_only_manifest(self):
        self.prepare(); root = c.CENTRAL / self.f.scope / 'release'
        digest = r.digest(root / 'release_manifest.json')
        command = [sys.executable, '-I', '-B', '-c', c.VERIFY_REMOTE_RELEASE, str(root), digest]
        result = subprocess.run(command, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0); self.assertEqual(result.stdout.strip(), 'VERIFIED ' + digest)
        with (root / 'job.sh').open('a') as out: out.write('\n# tampered private fixture\n')
        self.assertNotEqual(subprocess.run(command, capture_output=True, timeout=10).returncode, 0)

    def test_combined_remote_metadata_and_stream_caps_are_reserved(self):
        self.prepare(); j = c.Journal(self.f.scope)
        try:
            site = {'host':'hb.ucsc.edu','user':'jaguir26','known_hosts_file':'/fixture','ssh_identity_file':'/fixture'}
            c.remote(j, self.f.spec, site, 'private_metadata_probe', ['echo', 'private'], lambda *args, **kw: 'private')
            intent = next(item for item in j.records() if item['state'] == 'OPERATION_INTENT')
            self.assertEqual((intent['local_CPU_limit'], intent['remote_CPU_reservation'], intent['CPU_limit']), (2, 2, 4))
            args = []
            c.transfer(j, self.f.spec, {'host':'hb.ucsc.edu','user':'jaguir26','known_hosts_file':'/fixture','ssh_identity_file':'/fixture'},
                'private_proof_transfer', '/owned/a', 'owned:b', lambda argv, **kw: args.append(argv) or '', proof=True)
            self.assertTrue(any(value.endswith('profile_stream.py') for value in args[0]))
            task = json.loads(Path(args[0][-1]).read_text())
            self.assertIn('PR_SET_CHILD_SUBREAPER', task['remote_helper_source'])
            self.assertEqual(task['cpu'], 5)
            intent = [item for item in j.records() if item['state'] == 'OPERATION_INTENT'][-1]
            self.assertEqual(intent['CPU_limit'], 10)
        finally: j.close()

    def test_remote_exec_applies_real_private_CPU_and_wall_backstops(self):
        # Positive acceptance proves the wrapper under a separately funded fixture cap;
        # production2CPU availability is not the assertion of this test.
        output = c.bounded([sys.executable, '-I', '-B', '-c', 'print("aggregate owned command")'], wall=5, cpu=4, cap=4096)
        self.assertEqual(output, 'aggregate owned command\n')

    def test_same_policy_nested_pins_resolve_from_accepted_prior_canonical_release(self):
        self.prepare(); j = c.Journal(self.f.scope)
        try:
            accepted = j.root / 'accepted.json'
            r.write(accepted, dict(status='ACCEPTED_COMPLETE_PAIRED_COMPONENT_QUALIFICATION',
                scope_id=self.f.scope, source_files=self.f.workers))
            j.put('ACCEPTED', acceptance=c.pin(accepted))
        finally: j.close()
        later = copy.deepcopy(self.f.spec); later['scope_id'] = 'r164-profile-' + 'b' * 32
        later['phase'] = 'MEASUREMENT_PAIR'; later['remote_root'] = '/home/jaguir26/pricefm_hb_r164/' + later['scope_id']
        self.assertEqual(c.spec_read(later, self.f.policy), {'purpose': 'distinct'})
        bad = dict(self.f.policy, sha256='0' * 64)
        with self.assertRaisesRegex(ValueError, 'prior immutable metadata pin'):
            c.spec_read(later, bad)


class OriginalMetadataTests(unittest.TestCase):
    def test_actual_pinned_DK2_remote_metadata_maps_to_original_canonical_full_surface(self):
        path = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_r163_profile_preparation_20261028/PROFILE_PLAN_ROOT_03.json')
        if not path.is_file(): self.skipTest('original local R163 integration metadata is unavailable in this clone')
        profile = json.loads(c.e.bounded_read(path)); cost = profile['input_pins']['studies']['DK2']['cost_plan']
        task = next(t for t in profile['studies']['DK2']['tasks'] if t['name'] == 'DK_2_C0_s1_D_seed0')
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp); root = '/home/jaguir26/pricefm_r164_fixture/r164-profile-' + 'c' * 32
            request = dict(study='DK2', task=task['name'], task_sha256=task['task_sha256'],
                           stage_root='/nonexistent/HB/staged/payload', cost_plan=cost)
            p = base / 'request.json'; r.write(p, request)
            spec = dict(scope_id='r164-profile-' + 'c' * 32, remote_root=root,
                request=dict(path=root + '/metadata/request.json', sha256=r.digest(p)),
                files=[dict(local=str(p), relative='metadata/request.json', sha256=r.digest(p), bytes=p.stat().st_size)])
            result = c.canonical_return_expectation(spec)
            self.assertEqual(result['expected_result']['name'], 'DK_2_C0_s1_D_seed0')
            self.assertEqual(result['expected_result']['origin_clock_windows'], task['origin_clock_windows'])
            self.assertEqual({key.split('/')[1].split('_')[0] for key in result['expected_chunk_identities']},
                             {'clock00', 'clock24', 'clock48', 'clock72'})
            self.assertEqual(len(result['expected_packets']['predictions.npz']), 9)
            self.assertFalse({'numpy', 'scipy', 'pandas'} & set(sys.modules))


class AuthorityMarkerTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='pricefm_marker_test_',dir='/dev/shm')
        self.root=Path(self.tmp.name);self.part=self.root/'private-part'
        self.marker=self.root/'worker_authority.json';self.part.write_text('{"dummy":"not authority"}\n')
        self.cpu=patch.object(c.e.b,'aggregate_cpu_seconds',return_value=0);self.cpu.start()
    def tearDown(self):
        self.cpu.stop();self.tmp.cleanup()
    def test_two_link_marker_waits_until_cleanup_without_hash_or_spawn(self):
        os.link(self.part,self.marker);sleeps=[]
        def clean(_):
            sleeps.append(self.marker.stat().st_nlink);self.assertEqual(sleeps[-1],2);self.part.unlink()
        with patch.object(c.time,'sleep',side_effect=clean),patch.object(c,'pin',side_effect=AssertionError('no hash in wait')),patch.object(c.subprocess,'Popen') as spawn:
            expected=c.wait_for_authority_marker(self.marker,time.monotonic()+1,1)
        self.assertEqual(sleeps,[2]);self.assertEqual(self.marker.stat().st_nlink,1);spawn.assert_not_called()
        c.require_authority_marker_snapshot(self.marker,expected)
    def test_crashed_two_link_publication_exhausts_original_wait_and_never_spawns(self):
        os.link(self.part,self.marker)
        with patch.object(c.subprocess,'Popen') as spawn,self.assertRaisesRegex(ValueError,'bounded READY wait exhausted'):
            c.wait_for_authority_marker(self.marker,time.monotonic()+.02,1)
        spawn.assert_not_called();self.assertEqual(self.marker.stat().st_nlink,2)
    def test_complete_single_link_is_only_eligibility_not_worker_admission(self):
        os.link(self.part,self.marker);self.part.unlink()
        with patch.object(c.subprocess,'Popen') as spawn,patch.object(c,'read') as reader:
            expected=c.wait_for_authority_marker(self.marker,time.monotonic()+1,1)
        self.assertEqual(expected,c.e.fingerprint(self.marker.stat()));reader.assert_not_called();spawn.assert_not_called()
    def test_unexpected_third_link_is_rejected_without_wait_or_spawn(self):
        os.link(self.part,self.marker);os.link(self.part,self.root/'unexpected')
        with patch.object(c.time,'sleep') as sleep,patch.object(c.subprocess,'Popen') as spawn,self.assertRaisesRegex(ValueError,'one or two links'):
            c.wait_for_authority_marker(self.marker,time.monotonic()+1,1)
        sleep.assert_not_called();spawn.assert_not_called()
    def test_symlink_and_fifo_markers_are_rejected_before_open(self):
        self.marker.symlink_to(self.part)
        with self.assertRaisesRegex(ValueError,'symlink'):
            c.wait_for_authority_marker(self.marker,time.monotonic()+1,1)
        self.marker.unlink();os.mkfifo(self.marker,0o600)
        with self.assertRaisesRegex(ValueError,'owned bounded regular'):
            c.wait_for_authority_marker(self.marker,time.monotonic()+1,1)
    def test_marker_replacement_or_new_hardlink_after_wait_is_rejected(self):
        os.link(self.part,self.marker);self.part.unlink()
        expected=c.wait_for_authority_marker(self.marker,time.monotonic()+1,1)
        os.link(self.marker,self.part)
        with self.assertRaisesRegex(ValueError,'single-link'):
            c.require_authority_marker_snapshot(self.marker,expected)
        self.part.unlink();self.marker.unlink();self.marker.write_text('{"replacement":true}\n')
        with self.assertRaisesRegex(ValueError,'identity changed'):
            c.require_authority_marker_snapshot(self.marker,expected)
    def test_expired_wait_does_not_admit_an_existing_single_link_marker(self):
        os.link(self.part,self.marker);self.part.unlink()
        with self.assertRaisesRegex(ValueError,'bounded READY wait exhausted'):
            c.wait_for_authority_marker(self.marker,time.monotonic()-.01,1)
    def compute_fixture(self):
        from . import environment
        (self.root/'release_manifest.json').write_text('{"files":{}}\n')
        spec=dict(remote_root=str(self.root),node='dummy-node',expires_epoch=time.time()+2,
            allocation_limits=dict(wall_seconds=.1,wrapper_cpu_seconds=100,aggregate_cpu_seconds=600,
                                   exit_reserve_seconds=.01,ready_reserve_seconds=.015),
            worker_limits=dict(wall_seconds=.01),environment_bundle='/dummy/not-loaded',scope_id='dummy-only',
            request=dict(sha256='0'*64),worker_sources={},controller_sources={},controller_limits=dict(ready_wait_seconds=.005))
        def read(value):
            name=Path(value['path']).name
            if name=='spec.json':return spec
            if name=='release_manifest.json':return {'files':{}}
            if name=='worker_authority.json':return {'dummy':'not authority'}
            raise AssertionError('unexpected fixture metadata '+name)
        return [patch.object(c,'require_compute',return_value={'node':'dummy-node','job_id':'dummy-only'}),
                patch.object(c,'pin',side_effect=lambda p:{'path':str(p),'sha256':'0'*64}),patch.object(c,'read',side_effect=read),
                patch.object(c,'validate_spec'),patch.object(c.Path,'cwd',return_value=self.root),
                patch.object(c.signal,'signal'),patch.object(c.signal,'setitimer'),patch.object(c.resource,'setrlimit'),
                patch.object(environment,'verify_runtime',return_value={'status':'dummy-not-executed'}),
                patch.object(c.a,'scheduler_evidence',return_value={'end_epoch':time.time()+2}),patch.object(c.e,'write_new'),
                patch.object(c,'allocated_input_readiness',return_value={'dummy':'input readiness mocked for marker-only test'})]
    def test_actual_compute_flow_two_link_crash_never_reads_authority_or_spawns(self):
        os.link(self.part,self.marker);patches=self.compute_fixture()
        for item in patches:item.start()
        try:
            with patch.object(c.subprocess,'Popen') as spawn,self.assertRaisesRegex(ValueError,'bounded READY wait exhausted'):
                c.compute_session(self.root/'spec.json')
            spawn.assert_not_called()
            self.assertEqual([Path(row.args[0]['path']).name for row in c.read.call_args_list],['spec.json','release_manifest.json'])
        finally:
            for item in reversed(patches):item.stop()

    def test_ready_is_not_published_without_full_worker_exit_and_review_allowance(self):
        patches=self.compute_fixture()
        for item in patches:item.start()
        try:
            with patch.object(c.a,'scheduler_evidence',return_value={'end_epoch':time.time()+.01}), \
                 patch.object(c.subprocess,'Popen') as spawn,self.assertRaisesRegex(ValueError,'readiness leaves no original worker'):
                c.compute_session(self.root/'spec.json')
            spawn.assert_not_called();c.e.write_new.assert_not_called()
        finally:
            for item in reversed(patches):item.stop()
    def test_actual_compute_flow_single_link_still_requires_original_authority_gate(self):
        os.link(self.part,self.marker);self.part.unlink();patches=self.compute_fixture()
        for item in patches:item.start()
        try:
            with patch.object(c.subprocess,'Popen') as spawn,self.assertRaisesRegex(ValueError,'exact newly published paired worker envelope'):
                c.compute_session(self.root/'spec.json')
            spawn.assert_not_called()
            self.assertEqual(Path(c.read.call_args_list[-1].args[0]['path']).name,'worker_authority.json')
        finally:
            for item in reversed(patches):item.stop()


class PostvalidationProofTests(unittest.TestCase):
    def setUp(self):
        LifecycleTests.setUp(self)
        self.guard_text = patch.object(c, 'supervisor_source', return_value='# private inert guardian fixture')
        self.guard_text.start()
    def tearDown(self):
        self.guard_text.stop()
        LifecycleTests.tearDown(self)
    prepare = LifecycleTests.prepare
    submit = LifecycleTests.submit
    last = LifecycleTests.last

    def terminal(self):
        self.prepare(); root = c.CENTRAL / self.f.scope
        account = root / 'accounting_0000.json'
        r.write(account, dict(status='ACCEPTED_COMPLETE_JOB_ACCOUNTING', terminal=True,
            complete=True, job_id='123', job_still_queued=False, canonical_primary_CPU_seconds=3,
            canonical_primary_wall_seconds=5, rows=[], step_and_child_CPU_added_as_another_charge=False))
        ready = root / 'attestation.json'; r.write(ready, dict(runtime={'fixture': True}))
        j = c.Journal(self.f.scope)
        try:
            j.put('TERMINAL_OBSERVED', job_id='123', accounting=c.pin(account), attestation=c.pin(ready),
                  authority={'sha256': 'a'*64}, submitted={'sha256': 'b'*64}, staged_files=[])
        finally: j.close()
        return root, account

    def runner(self, root, account, valid=True, bad_hash=False):
        trace = []
        def run(argv, **kw):
            if '--task' in argv and any(x.endswith('profile_stream.py') for x in argv):
                task = json.loads(Path(argv[-1]).read_text()); trace.append(('transfer', task['source']))
                if task['source'].endswith('/accepted_job_accounting.json'):
                    self.assertTrue((root/'return_validation.json').is_file())
                    self.assertTrue(json.loads(Path(task['source']).read_text())['all_raw_outputs_returned_and_verified'])
                return ''
            if '--validate-return' in argv:
                trace.append(('validate',))
                pair = root/'returned_raw/outputs/ACTUAL_COMPONENT_PROFILE'/self.f.scope/'profile_result.json'
                pair.parent.mkdir(parents=True); r.write(pair, {'fixture': True})
                manifest = root/'returned_raw_manifest.json'
                r.write(manifest, dict(root=str(root/'returned_raw'), scope_id=self.f.scope, job_id='123',
                    members={str(pair.relative_to(root/'returned_raw')):dict(sha256=r.digest(pair), bytes=pair.stat().st_size)}))
                r.write(Path(argv[argv.index('--receipt')+1]), dict(
                    status='PASS_FULL_RAW_RETURN_VALIDATION' if valid else 'REJECTED_FIXTURE',
                    scope_id=self.f.scope, job_id='123', exact_whole_component_parity=valid,
                    full_raw_manifest=c.pin(manifest), component_pair_result=c.pin(pair)))
                return ''
            text = inner_command(argv); trace.append(('metadata', text))
            if text.startswith('test '): return ''
            if text.startswith('du '): return '0 fixture\n'
            if text.startswith('sha256sum '):
                value = root/'accepted_job_accounting.json' if text.endswith('/accepted_job_accounting.json') else account
                return ('0'*64 if bad_hash and value.name=='accepted_job_accounting.json' else r.digest(value))+' file\n'
            raise AssertionError('unmocked fixture operation: '+repr(argv))
        return run, trace

    def test_new_accounting_is_source_bound_postvalidation_and_preserves_raw_receipt(self):
        root, account = self.terminal(); original = account.read_bytes()
        runner, trace = self.runner(root, account); self.assertEqual(c.collect_run(self.f.scope, runner)['state'], 'ACCEPTED')
        self.assertEqual(account.read_bytes(), original); self.assertNotIn('source_files', json.loads(original))
        acceptance = json.loads((root/'accepted.json').read_text()); proof = c.read(acceptance['local_whole_accounting'])
        self.assertEqual(proof['status'], 'ACCEPTED_COMPLETE_JOB_ACCOUNTING')
        self.assertEqual(proof['source_files'], self.f.workers); self.assertTrue(proof['all_raw_outputs_returned_and_verified'])
        self.assertEqual(proof['original_accounting_sha256'], r.digest(account))
        self.assertEqual(acceptance['whole_accounting']['path'], self.f.remote+'/accepted_job_accounting.json')
        self.assertEqual(acceptance['whole_accounting']['sha256'], acceptance['local_whole_accounting']['sha256'])
        published = next(i for i,x in enumerate(trace) if x[0]=='transfer' and x[1].endswith('/accepted_job_accounting.json'))
        self.assertLess(trace.index(('validate',)), published)

    def test_failed_raw_validation_can_reconcile_completed_job_without_acceptance(self):
        root, account = self.terminal(); original = account.read_bytes(); runner, _ = self.runner(root, account, valid=False)
        with self.assertRaisesRegex(ValueError, 'raw return validation'): c.collect_run(self.f.scope, runner)
        self.assertFalse((root/'accepted_job_accounting.json').exists()); self.assertFalse((root/'accepted.json').exists())
        result = c.reconcile_failure(self.f.scope)
        self.assertEqual(result['state'], 'FAILED_RECONCILED'); self.assertEqual(result['charged_CPU_seconds'], 600)
        self.assertFalse(result['raw_outputs_accepted']); self.assertFalse(result['retry_or_refund_authorized'])
        self.assertEqual(account.read_bytes(), original)
        with self.assertRaises(ValueError): c.collect_run(self.f.scope, runner)

    def test_bad_published_proof_hash_never_accepts_or_refunds(self):
        root, account = self.terminal(); runner, _ = self.runner(root, account, bad_hash=True)
        with self.assertRaisesRegex(ValueError, 'postvalidation accounting changed'): c.collect_run(self.f.scope, runner)
        self.assertFalse((root/'accepted.json').exists())
        result = c.reconcile_failure(self.f.scope); self.assertFalse(result['raw_outputs_accepted'])
        self.assertEqual(result['charged_CPU_seconds'], 600)

    def test_completed_job_cannot_be_abandoned_before_collection(self):
        self.terminal()
        with self.assertRaisesRegex(ValueError, 'unaccepted collection'): c.reconcile_failure(self.f.scope)

    def test_measurement_resolves_only_canonical_accepted_dynamic_proof_roles(self):
        root, account = self.terminal(); runner, _ = self.runner(root, account)
        c.collect_run(self.f.scope, runner)
        accepted = json.loads((root/'accepted.json').read_text())
        later = copy.deepcopy(self.f.spec); later['scope_id'] = 'r164-profile-'+'b'*32
        later['remote_root'] = self.f.remote.rsplit('/', 1)[0]+'/'+later['scope_id']
        proof = c.spec_read(later, accepted['whole_accounting'])
        self.assertEqual(proof['source_files'], self.f.workers)
        self.assertTrue(proof['all_raw_outputs_returned_and_verified'])
        self.assertEqual(c.spec_read(later, accepted['component_pair_result']), {'fixture': True})
        with self.assertRaisesRegex(ValueError, 'exact remote pin'):
            c.spec_read(later, dict(accepted['whole_accounting'], sha256='0'*64))
        bad = copy.deepcopy(accepted); outside = self.base/'outside_accounting.json'
        outside.write_bytes((root/'accepted_job_accounting.json').read_bytes())
        bad['local_whole_accounting'] = c.pin(outside)
        with self.assertRaisesRegex(ValueError, 'path or hash'):
            c.accepted_dependency_read(root, self.f.spec, self.last(), bad, accepted['whole_accounting'])

    def test_already_terminal_owned_job_is_not_cancelled_again(self):
        self.submit(); original = self.f.runner; calls = []
        def runner(argv, **kw):
            text = inner_command(argv); calls.append(text)
            if text.startswith('scontrol show job'):
                return original(argv, **kw).replace('JobState=PENDING','JobState=COMPLETED').replace('NumNodes=1-1','NumNodes=1')
            if text.startswith('squeue'): return ''
            if text.startswith('sacct'):
                return '\n'.join('|'.join([name,'COMPLETED','0:0','5','1','00:00:03','10K','node-13']) for name in ('123','123.batch','123.0'))
            raise AssertionError(text)
        result = c.cancel_exact_owned_job(self.f.scope, runner)
        self.assertEqual(result['state'],'FAILED_RECONCILED'); self.assertFalse(result['raw_outputs_accepted'])
        self.assertFalse(any(x.startswith('scancel') for x in calls))

    def test_released_but_unallocated_exact_single_node_job_can_be_cancelled(self):
        self.submit(); original = self.f.runner; shows = 0
        def runner(argv, **kw):
            nonlocal shows
            text = inner_command(argv)
            if text.startswith('scontrol show job'):
                shows += 1
                value = original(argv, **kw).replace('Reason=JobHeldUser', 'Reason=Resources')
                value = value.replace('StartTime=Unknown', 'StartTime=2099-01-01T00:00:00')
                return value if shows == 1 else value.replace('JobState=PENDING', 'JobState=CANCELLED').replace('NumNodes=1-1', 'NumNodes=1')
            if text == 'scancel 123' or text.startswith('squeue'): return ''
            if text.startswith('sacct'): return '123|CANCELLED|0:15|0|0|00:00:00||None assigned\n'
            raise AssertionError(text)
        self.assertEqual(c.cancel_exact_owned_job(self.f.scope, runner)['state'], 'FAILED_RECONCILED')
        self.assertFalse(c._exact_single_node({'NumNodes':'1-1','JobState':'PENDING','RunTime':'00:00:00',
                        'Reason':'Resources','StartTime':'2099-01-01T00:00:00','AllocTRES':'(null)'}))

    def test_cancel_followups_are_throttled_and_survive_live_job_retention_loss(self):
        self.submit(); original = self.f.runner; shows = 0; reads = 0; calls = []
        def runner(argv, **kw):
            nonlocal shows, reads
            text = inner_command(argv); calls.append(text)
            if text.startswith('scontrol show job'):
                shows += 1; self.assertLessEqual(shows,2)
                value = original(argv, **kw)
                return value if shows==1 else value.replace('JobState=PENDING','JobState=CANCELLED').replace('NumNodes=1-1','NumNodes=1')
            if text=='scancel 123' or text.startswith('squeue'): return ''
            if text.startswith('sacct'):
                reads += 1; return '' if reads<3 else '123|CANCELLED|0:15|0|0|00:00:00||None assigned\n'
            raise AssertionError(text)
        first = c.cancel_exact_owned_job(self.f.scope, runner); count = len(calls)
        self.assertEqual(first['state'],'CANCELLATION_REQUESTED_UNRECONCILED')
        with self.assertRaisesRegex(ValueError,'throttled'): c.cancel_exact_owned_job(self.f.scope, runner)
        self.assertEqual(len(calls),count)
        with patch.object(c.time,'time',return_value=first['created_epoch']+301):
            self.assertEqual(c.cancel_exact_owned_job(self.f.scope,runner)['state'],'CANCELLATION_REQUESTED_UNRECONCILED')
        with patch.object(c.time,'time',return_value=first['created_epoch']+602):
            result = c.cancel_exact_owned_job(self.f.scope,runner)
        self.assertEqual(result['state'],'FAILED_RECONCILED'); self.assertEqual(result['charged_CPU_seconds'],600)
        self.assertEqual(shows,2); self.assertEqual(calls.count('scancel 123'),1)

    def test_lost_cancel_ack_uses_known_ownership_and_never_resends_cancel(self):
        self.submit(); original = self.f.runner; calls = []
        def runner(argv, **kw):
            text = inner_command(argv); calls.append(text)
            if text.startswith('scontrol show job'):
                self.assertEqual(sum(x.startswith('scontrol show job') for x in calls), 1)
                return original(argv, **kw)
            if text == 'scancel 123': raise TimeoutError('private lost acknowledgement')
            if text.startswith('squeue'): return ''
            if text.startswith('sacct'): return '123|CANCELLED|0:15|0|0|00:00:00||None assigned\n'
            raise AssertionError(text)
        with self.assertRaises(TimeoutError): c.cancel_exact_owned_job(self.f.scope, runner)
        failed = self.last(); self.assertEqual(failed['state'], 'AMBIGUOUS_SPENT')
        with patch.object(c.time, 'time', return_value=failed['created_epoch'] + 301):
            result = c.cancel_exact_owned_job(self.f.scope, runner)
        self.assertEqual(result['state'], 'FAILED_RECONCILED')
        self.assertEqual(result['charged_CPU_seconds'], 600)
        self.assertEqual(calls.count('scancel 123'), 1)

    def test_cancel_followup_count_is_finite_when_accounting_stays_pending(self):
        self.submit(); original = self.f.runner; shows = 0
        def runner(argv, **kw):
            nonlocal shows
            text = inner_command(argv)
            if text.startswith('scontrol show job'):
                shows += 1; self.assertLessEqual(shows, 2)
                value = original(argv, **kw)
                return value if shows == 1 else value.replace('JobState=PENDING', 'JobState=CANCELLED').replace('NumNodes=1-1', 'NumNodes=1')
            if text == 'scancel 123' or text.startswith(('squeue', 'sacct')): return ''
            raise AssertionError(text)
        first = c.cancel_exact_owned_job(self.f.scope, runner)
        for seconds in (301, 602):
            with patch.object(c.time, 'time', return_value=first['created_epoch'] + seconds):
                self.assertEqual(c.cancel_exact_owned_job(self.f.scope, runner)['state'], 'CANCELLATION_REQUESTED_UNRECONCILED')
        with patch.object(c.time, 'time', return_value=first['created_epoch'] + 903):
            with self.assertRaisesRegex(ValueError, 'follow-ups exhausted'):
                c.cancel_exact_owned_job(self.f.scope, runner)


class AccountingTests(unittest.TestCase):
    def spec(self):
        return dict(allocation_limits=dict(aggregate_cpu_seconds=600, wall_seconds=1200, memory_MiB=2048), node='node-13')
    def rows(self, cpu='00:02:00', state='COMPLETED'):
        return '\n'.join('|'.join([name, state, '0:0', '300', '1', cpu, '100K', 'node-13'])
                         for name in ('123', '123.batch', '123.0'))
    def test_charge_primary_once_and_use_steps_only_as_attribution(self):
        result = c.parse_accounting(self.rows(), '123', self.spec())
        self.assertTrue(result['complete']); self.assertEqual(result['canonical_primary_CPU_seconds'], 120)
        self.assertFalse(result['step_and_child_CPU_added_as_another_charge'])
    def test_duplicate_primary_foreign_or_overfunded_job_rejects(self):
        for value in (self.rows() + '\n' + self.rows().splitlines()[0], self.rows().replace('123.0', '999.0'),
                      self.rows(cpu='00:10:01'), self.rows().replace('node-13', 'node-14')):
            with self.subTest(value=value), self.assertRaises(ValueError): c.parse_accounting(value, '123', self.spec())
    def test_incomplete_step_or_failed_job_does_not_qualify(self):
        value = '\n'.join(self.rows().splitlines()[:-1])
        self.assertFalse(c.parse_accounting(value, '123', self.spec())['complete'])
        self.assertFalse(c.parse_accounting(self.rows(state='FAILED'), '123', self.spec())['complete'])
    def test_delayed_empty_accounting_retains_full_reservation_and_allows_status(self):
        result = c.parse_accounting('', '123', self.spec())
        self.assertFalse(result['complete']); self.assertFalse(result['terminal'])
        self.assertIsNone(result['canonical_primary_CPU_seconds'])
        self.assertEqual(result['unresolved_full_reservation_CPU_seconds'], 600)


class AllocatedInputReadinessTests(unittest.TestCase):
    def test_returned_ready_and_readiness_are_exact_local_counterparts(self):
        with tempfile.TemporaryDirectory(prefix='pricefm_readiness_return_',dir='/dev/shm') as tmp:
            root=Path(tmp);raw=root/'returned_raw';raw.mkdir();receipt={'fixed':'allocated metadata'}
            c.e.write_new(raw/'input_readiness.json',receipt)
            ref=dict(path='/home/jaguir26/exact-new-release/input_readiness.json',sha256=r.digest(raw/'input_readiness.json'))
            ready=dict(observed_epoch=123.,input_readiness=receipt,input_readiness_pin=ref)
            c.e.write_new(root/'canonical_ready.json',ready);c.e.write_new(raw/'ready.json',ready)
            claim=dict(attestation=c.pin(root/'canonical_ready.json'))
            with patch.object(c,'ready_input_binding',return_value=ref) as binding:
                self.assertEqual(c.verify_returned_readiness(raw,{},claim),(ready,ref))
                binding.assert_called_once_with({},ready,now=123.)
                (raw/'input_readiness.json').write_text('{}')
                with self.assertRaisesRegex(ValueError,'returned exact allocated input readiness'):
                    c.verify_returned_readiness(raw,{},claim)
                (raw/'ready.json').write_text('{}')
                with self.assertRaisesRegex(ValueError,'returned exact allocated READY'):
                    c.verify_returned_readiness(raw,{},claim)

    def test_original_verification_support_and_actual_metadata_expectation_precede_receipt(self):
        allocation={'job_id':'private','node':'private'};order=[]
        request=dict(cost_plan={'path':'/private/cost.json','sha256':'1'*64},stage_root='/old/unchanged/stage',
                     profile_support={'fixed':'contract'},task_sha256='2'*64)
        profile={'profile_delivery_binding':{'fixed':'new delivery'}};cost={'input_allowlist':{'old':{'bytes':7}}}
        spec=dict(request={'path':'/private/request.json','sha256':'3'*64},remote_root='/private/new',scope_id='private')
        def old(cst,root):order.append('original_all_input_verification');self.assertIs(cst,cost);self.assertEqual(root,request['stage_root']);return {},{},'original resolver'
        def support(base,req):order.append('support');self.assertEqual(base,'original resolver');self.assertIs(req,request)
        def expected(cst,req):order.append('actual_expected_component');return {'metadata':'shape only'}
        with patch.object(c,'require_compute',return_value=allocation),patch.object(c,'read',return_value=request), \
             patch.object(c.e,'validate_request',return_value=(profile,cost,{})),patch.object(c.e.b,'load_staged',side_effect=old), \
             patch.object(c.e,'profile_resolver',side_effect=support),patch.object(c.e,'expected_component',side_effect=expected), \
             patch.object(c.e,'source_closure',return_value={'fixed':'sources'}),patch.object(c.e,'write_new') as write:
            receipt=c.allocated_input_readiness(spec,allocation)
        self.assertEqual(order,['original_all_input_verification','support','actual_expected_component'])
        self.assertEqual(receipt['verified_original_input_count'],1);self.assertEqual(receipt['verified_original_input_bytes'],7)
        self.assertFalse(receipt['predictions_executed']);self.assertFalse(receipt['array_payloads_evaluated'])
        self.assertEqual(write.call_args.args[0],Path('/private/new/input_readiness.json'))

    def test_unallocated_or_failed_expectation_cannot_publish_readiness(self):
        with patch.object(c,'require_compute',side_effect=RuntimeError('no allocation')), \
             patch.object(c.e.b,'load_staged') as loader,patch.object(c.e,'write_new') as write:
            with self.assertRaisesRegex(RuntimeError,'no allocation'):c.allocated_input_readiness({}, {})
            loader.assert_not_called();write.assert_not_called()
        request=dict(stage_root='/unchanged');profile={};cost={};spec=dict(request={})
        with patch.object(c,'require_compute',return_value={}),patch.object(c,'read',return_value=request), \
             patch.object(c.e,'validate_request',return_value=(profile,cost,{})), \
             patch.object(c.e.b,'load_staged',return_value=({}, {}, 'original')),patch.object(c.e,'profile_resolver'), \
             patch.object(c.e,'expected_component',side_effect=KeyError('missing dependency')),patch.object(c.e,'write_new') as write:
            with self.assertRaisesRegex(KeyError,'missing dependency'):c.allocated_input_readiness(spec,{})
            write.assert_not_called()


if __name__ == '__main__': unittest.main()
