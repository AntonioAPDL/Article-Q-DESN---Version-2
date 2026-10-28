"""Private AUTHORIZED/PENDING bridge fixtures; no canonical or scheduler I/O."""
import copy
import json
import os
from pathlib import Path
import resource
import signal
import sys
import tempfile
import time
import types
import unittest

HERE = Path(__file__).resolve().parent
QUALIFIED = HERE.parent / 'hb/FI_COST_PIPELINE_02/release/code'
sys.path.insert(0, str(QUALIFIED))
from pricefm_hb import admission as stock
from authorized_admission_bridge import make_refresh_bridge


class AuthorizedBridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.number = 0

    def fixture(self, study):
        self.number += 1
        root = self.root / (study + '-' + str(self.number))
        release_root = root / 'release'
        release_root.mkdir(parents=True)
        module = types.SimpleNamespace(**vars(stock))
        module.CENTRAL = root / 'never-used-canonical'
        module.policy = types.SimpleNamespace(**vars(stock.policy))
        module.policy.hb_concurrency = lambda packet: 1
        policy_pin = dict(path='/private/future-policy.json', sha256='d' * 64)
        resources = dict(cpus=1, memory_MiB=4096, cpu_seconds=1200, wall_seconds=1200)
        key = ('a' if study == 'FI' else 'b') * 64
        release = dict(purpose='COST_ONLY', study=study, task_key=key,
            plan_sha256='e' * 64, scientific_exclusion_key=study + '|private-new-intent',
            resources=resources, remote_root='/private-future/' + study,
            policy_pin=policy_pin, node='node-13', scope_id='private-future-' + study,
            source_hashes={'admission.py': stock.r.digest(stock.__file__)})
        stock.r.write(release_root / 'release.json', release)
        claim = dict(task_key=key, state='AUTHORIZED', job_id='123',
            task=dict(purpose='COST_ONLY', study=study, plan_sha256=release['plan_sha256'],
                scientific_exclusion_key=release['scientific_exclusion_key']),
            release_path=str(release_root), release_sha256=stock.r.digest(release_root / 'release.json'),
            remote_root=release['remote_root'], resources=resources, policy_pin=policy_pin,
            legacy_cost_key='c' * 64, scope_id=release['scope_id'], config_sha256='f' * 64,
            authority_sha256='7' * 64)
        legacy = dict(task_key=claim['legacy_cost_key'], state='AUTHORIZED', job_id='123',
            task=dict(study=study, plan_sha256=release['plan_sha256'],
                scientific_exclusion_key=release['scientific_exclusion_key']),
            release_path=claim['release_path'], release_sha256=claim['release_sha256'],
            remote_root=release['remote_root'], scope_id=claim['scope_id'],
            config_sha256=claim['config_sha256'], reserved_CPU_seconds=1200, wall_seconds=1200,
            authority_sha256=claim['authority_sha256'])
        state = dict(schema=stock.LIFECYCLE_SCHEMA, owner=stock.policy.OWNER,
            claims={key: copy.deepcopy(claim), 'old-terminal': dict(task_key='old-terminal',
                state='FAILED_RECONCILED')})
        legacy_state = dict(schema=stock.cost.SCHEMA, owner=stock.policy.OWNER,
            claims={legacy['task_key']: copy.deepcopy(legacy), 'old-paid-terminal':
                dict(task_key='old-paid-terminal', state='FAILED_RECONCILED',
                     reserved_CPU_seconds=1200, wall_seconds=1200)},
            spent_regions={study: legacy['task_key']})
        module._state_snapshot = lambda: copy.deepcopy(state)
        legacy_snapshot = lambda: copy.deepcopy(legacy_state)
        snapshot = {'slurm': {
            'partition': 'PartitionName=128x24 State=UP MaxTime=1-00:00:00',
            'self_job': 'JobId=123 JobState=PENDING Reason=JobHeldUser NumCPUs=1 ReqNodeList=node-13 ReqTRES=cpu=1,mem=4G,node=1 MinMemoryNode=4G',
            'nodes': 'NodeName=node-13 Partitions=128x24 State=MIXED CPUEfctv=4 CPUTot=4 CPUAlloc=2 FreeMem=8192 RealMemory=16384 AllocMem=8192\n'
                     'NodeName=node-14 Partitions=128x24 State=IDLE CPUEfctv=40 CPUTot=40 CPUAlloc=0 FreeMem=65536 RealMemory=65536 AllocMem=0'}}
        return types.SimpleNamespace(module=module, study=study, release=release, claim=claim,
            legacy=legacy, state=state, legacy_state=legacy_state, legacy_snapshot=legacy_snapshot,
            snapshot=snapshot)

    def bridge(self, fixture, **changes):
        values = dict(expected_claim=fixture.claim, expected_release=fixture.release,
                      expected_legacy_claim=fixture.legacy,
                      legacy_snapshot=fixture.legacy_snapshot)
        values.update(changes)
        return make_refresh_bridge(fixture.module, **values)

    def canonical(self, fixture, bridge=None, claim=None):
        bridge = self.bridge(fixture) if bridge is None else bridge
        return bridge.__globals__['canonical_claims']({'scope_id': 'private-policy'},
            fixture.release['plan_sha256'], fixture.release['scientific_exclusion_key'],
            fixture.claim if claim is None else claim)

    def test_FI_and_DK2_authorized_pair_accept_without_mutating_old_paid_history(self):
        for study in ('FI', 'DK2'):
            with self.subTest(study=study):
                f = self.fixture(study)
                before = copy.deepcopy((f.state, f.legacy_state))
                _, own, peers = self.canonical(f)
                self.assertEqual(own, f.claim)
                self.assertEqual(peers, [])
                self.assertEqual((f.state, f.legacy_state), before)
                self.assertFalse(f.module.CENTRAL.exists())

    def test_only_two_named_globals_are_isolated_and_stock_is_never_monkeypatched(self):
        for study in ('FI', 'DK2'):
            with self.subTest(study=study):
                f = self.fixture(study)
                old = dict(stock.refresh_request.__globals__)
                bridge = self.bridge(f)
                self.assertIsNot(bridge, stock.refresh_request)
                self.assertIsNot(bridge.__globals__, stock.refresh_request.__globals__)
                self.assertEqual(bridge.authorized_bridge_binding['overridden_globals'],
                                 ['canonical_claims', 'select_node'])
                self.assertEqual(bridge.authorized_bridge_binding['study'], study)
                self.assertIs(bridge.authorized_bridge_binding['no_allocation_added_back'], True)
                for name, value in old.items():
                    self.assertIs(stock.refresh_request.__globals__[name], value)
                    if name not in ('refresh_request', 'canonical_claims', 'select_node'):
                        self.assertIs(bridge.__globals__[name], value)
                self.assertIsNot(bridge.__globals__['canonical_claims'], stock.canonical_claims)
                self.assertIsNot(bridge.__globals__['select_node'], stock.select_node)

    def test_wrong_state_scope_job_study_source_and_original_paid_shape_reject(self):
        for study in ('FI', 'DK2'):
            for target, change in (
                ('claim', {'state': 'HELD'}), ('claim', {'state': 'SUBMITTED'}),
                ('claim', {'job_id': '0'}), ('claim', {'scope_id': 'other-scope'}),
                ('claim', {'task': dict(purpose='COST_ONLY', study='TEST')}),
                ('release', {'study': 'TEST'}), ('release', {'scope_id': 'other-scope'}),
                ('release', {'source_hashes': {'admission.py': '0' * 64}}),
                ('legacy', {'state': 'HELD'}), ('legacy', {'job_id': '456'}),
                ('legacy', {'scope_id': 'other-scope'}), ('legacy', {'config_sha256': '0' * 64}),
                ('legacy', {'reserved_CPU_seconds': 1199}), ('legacy', {'wall_seconds': 1201}),
                ('legacy', {'task': dict(study='TEST')}),
                ('legacy', {'release_sha256': '0' * 64})):
                with self.subTest(study=study, target=target, change=change):
                    f = self.fixture(study)
                    argument = {'claim': 'expected_claim', 'release': 'expected_release',
                                'legacy': 'expected_legacy_claim'}[target]
                    with self.assertRaises(stock.AdmissionError):
                        self.bridge(f, **{argument: dict(getattr(f, target), **change)})

    def test_changed_live_claim_or_legacy_callback_and_unrelated_active_claims_reject(self):
        for study in ('FI', 'DK2'):
            for change in ('operational-job', 'legacy-state', 'spent-key',
                           'operational-peer', 'legacy-peer'):
                with self.subTest(study=study, change=change):
                    f = self.fixture(study)
                    bridge = self.bridge(f)
                    if change == 'operational-job':
                        f.state['claims'][f.claim['task_key']]['job_id'] = '456'
                    elif change == 'legacy-state':
                        f.legacy_state['claims'][f.legacy['task_key']]['state'] = 'HELD'
                    elif change == 'spent-key':
                        f.legacy_state['spent_regions'][study] = 'old-paid-terminal'
                    elif change == 'operational-peer':
                        f.state['claims']['other'] = dict(task_key='other', state='AUTHORIZED')
                    else:
                        f.legacy_state['claims']['other'] = dict(task_key='other', state='RESERVED')
                    with self.assertRaises(stock.AdmissionError):
                        self.canonical(f, bridge)

    def test_authority_SHA_is_present_well_formed_and_identical_in_both_authorized_claims(self):
        for study in ('FI', 'DK2'):
            for target, change in (('claim', 'missing'), ('legacy', 'missing'),
                                   ('claim', ''), ('legacy', ''),
                                   ('claim', 'g' * 64), ('legacy', '8' * 64)):
                with self.subTest(study=study, target=target, change=change):
                    f = self.fixture(study)
                    value = copy.deepcopy(getattr(f, target))
                    if change == 'missing':
                        value.pop('authority_sha256')
                    else:
                        value['authority_sha256'] = change
                    argument = {'claim': 'expected_claim',
                                'legacy': 'expected_legacy_claim'}[target]
                    with self.assertRaises(stock.AdmissionError):
                        self.bridge(f, **{argument: value})

    def test_actual_pending_selector_keeps_bound_node_and_has_no_allocation_addback(self):
        for study in ('FI', 'DK2'):
            with self.subTest(study=study):
                f = self.fixture(study)
                selector = self.bridge(f).__globals__['select_node']
                result = selector(f.snapshot, 4096, 1200, f.claim,
                                  ['node-13', 'node-14'], 'node-14')
                self.assertEqual(result['node'], 'node-13')
                self.assertEqual(result['available_cpus'], 2)
                self.assertEqual(result['available_memory_mib'], 8192)
                self.assertIs(result['self_allocation_added_back'], False)
                no_cpu = copy.deepcopy(f.snapshot)
                no_cpu['slurm']['nodes'] = no_cpu['slurm']['nodes'].replace('CPUAlloc=2', 'CPUAlloc=4')
                with self.assertRaises(stock.AdmissionError):
                    selector(no_cpu, 4096, 1200, f.claim)
                low_memory = copy.deepcopy(f.snapshot)
                low_memory['slurm']['nodes'] = low_memory['slurm']['nodes'].replace('FreeMem=8192', 'FreeMem=2048')
                with self.assertRaises(stock.AdmissionError):
                    selector(low_memory, 4096, 1200, f.claim)

    def test_scheduler_job_hold_node_CPU_and_both_memory_fields_are_exact(self):
        for study in ('FI', 'DK2'):
            f = self.fixture(study)
            selector = self.bridge(f).__globals__['select_node']
            for before, after in (('JobId=123', 'JobId=456'), ('PENDING', 'RUNNING'),
                    ('JobHeldUser', 'Resources'), ('NumCPUs=1', 'NumCPUs=2'),
                    ('ReqNodeList=node-13', 'ReqNodeList=node-14'), ('cpu=1,', 'cpu=2,'),
                    ('mem=4G', 'mem=8G'), ('MinMemoryNode=4G', 'MinMemoryNode=8G')):
                with self.subTest(study=study, before=before, after=after):
                    changed = copy.deepcopy(f.snapshot)
                    changed['slurm']['self_job'] = changed['slurm']['self_job'].replace(before, after)
                    with self.assertRaises(stock.AdmissionError):
                        selector(changed, 4096, 1200, f.claim)
            with self.assertRaises(stock.AdmissionError):
                selector(f.snapshot, 4096, 1200, f.claim, ['node-14'])
            with self.assertRaises(stock.AdmissionError):
                selector(f.snapshot, 8192, 1200, f.claim)
            with self.assertRaises(stock.AdmissionError):
                selector(f.snapshot, 4096, 1199, f.claim)


if __name__ == '__main__':
    assert os.sched_getaffinity(0) == {31}
    resource.setrlimit(resource.RLIMIT_CPU, (5, 5))
    signal.alarm(30)
    began = time.monotonic()
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(AuthorizedBridgeTests))
    own = resource.getrusage(resource.RUSAGE_SELF)
    children = resource.getrusage(resource.RUSAGE_CHILDREN)
    print(json.dumps(dict(tests=result.testsRun, failures=len(result.failures), errors=len(result.errors),
        successful=result.wasSuccessful(), CPU_seconds=own.ru_utime + own.ru_stime + children.ru_utime + children.ru_stime,
        wall_seconds=time.monotonic() - began, numerical_modules=[name for name in ('numpy', 'pandas', 'scipy') if name in sys.modules],
        SSH_calls=0, canonical_reads_or_writes=0, array_reads=0), sort_keys=True))
    raise SystemExit(0 if result.wasSuccessful() else 1)
