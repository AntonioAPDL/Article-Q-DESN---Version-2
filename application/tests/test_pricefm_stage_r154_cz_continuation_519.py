"""Finite CZ continuation faults and real lock order; zero model/service calls."""
import copy
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[2]
HERE=ROOT/'application/scripts/pricefm'
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
G=load('r154_test_gate',HERE/'519_resolve_pricefm_stage_r154_cz_continuation.py')
R=load('r154_test_release',HERE/'519_release_pricefm_stage_r154_cz_continuation.py')
B=load('r154_frozen_fixture_helpers',ROOT/'application/tests/test_pricefm_stage_r153_cz_gate.py')
B.GATE=G


class ContinuationTests(unittest.TestCase):
    def setUp(self):
        method=next(n for n in dir(B.CZGateTests) if n.startswith('test_'))
        self.base=B.CZGateTests(method);self.base.setUp()
        self.root=self.base.root;self.data=self.base.data;self.a=self.base.authority
        self.system=self.base.system;self.path=self.base.path;self.runtime=self.base.runtime
        self.previous=G.RUNTIME.parent/'previous';self.previous_source=self.root/'previous_source'
        self.extra=mock.patch.multiple(G,PREVIOUS_RUNTIME=self.previous,PREVIOUS_CONTROL_ROOT=self.previous_source)
        self.extra.start();self.release_patch=mock.patch.object(R,'api',return_value=G);self.release_patch.start()
        self.a.update(kind='R154_CZ_CONTROL_CONTINUATION',poll_seconds=60,additional_control_activations=1,
            historical_debits_credited=False,historical_claims_or_clocks_reset=False,
            proof_CPU_charged_seconds=240.,proof_CPU_actual_charged_seconds=20.,
            administrative_release_CPU_reservation_seconds=120.,prior_control_CPU_charged_seconds=360.,
            pricing=dict(CPU_seconds_per_hour_upper=14.,worst_check_wall_seconds=20.,publication_wall_margin_seconds=5.))
        self.a['waiter_unit']='pricefm-r154-cz-gate-'+self.a['id']+'.service'
        self.a['science_unit']='pricefm-r154-cz-science-'+self.a['id']+'.service'
        self.a['control_CPU_allowance_seconds']=3600.
        old=copy.deepcopy(self.a);old.update(kind='R153_CZ_RESOURCE_RESOLUTION',id='2'*32)
        old['waiter_unit']='pricefm-r153-cz-gate-'+old['id']+'.service'
        old['execution_source']=dict(root=str(self.previous_source),branch='frozen-old',head='17bd756aacb0f4ce458978f10af45c75200b9a65')
        self.system.sources[str(self.previous_source)]=old['execution_source']
        oldroot=self.previous/old['id'];oldpath=oldroot/'authority.json';B.put(oldpath,old)
        self.a.update(previous_authority_path=str(oldpath),previous_authority_sha256=G.sha(oldpath),
            previous_waiter=dict(unit=old['waiter_unit'],process=B.process(66),cgroup='/old/r153',invocation_id='old'))
        B.put(self.previous/'single_activation_claim.json',dict(id=old['id'],authority_path=str(oldpath),authority_sha256=G.sha(oldpath)))
        names=['activation.json','launch_claim.json','launch_receipt.json','old_waiter_fence.json','effective_config.json','original_waiter_progress.json']
        for name in names:B.put(oldroot/name,{})
        self.a['previous_immutable_sha256']={str(p):G.sha(p) for p in [oldpath,self.previous/'single_activation_claim.json']+[oldroot/n for n in names]}
        self.save()
    def tearDown(self):
        self.release_patch.stop();self.extra.stop();self.base.tearDown()
    def save(self):B.put(self.path,self.a)
    def valid(self):return G.validate_authority(self.path,system=self.system)
    def launch_fixture(self):
        B.put(G.RUNTIME/'single_activation_claim.json',dict(id=self.a['id'],authority_sha256=G.sha(self.path)))
        B.put(self.runtime/'old_waiter_fence.json',dict(authority_sha256=G.sha(self.path)))
    def test_valid_finite_scope_and_original_science(self):self.assertEqual(self.valid()['effective_config'],self.base.config)
    def test_polling_plus_worst_check_and_margin_must_fit90(self):
        self.a['pricing']['worst_check_wall_seconds']=26.;self.save()
        with self.assertRaisesRegex(RuntimeError,'freshness'):self.valid()
    def test_finite_price_covers_actual_reserves(self):
        self.a['pricing']['CPU_seconds_per_hour_upper']=15.;self.a['proof_CPU_charged_seconds']=241.
        self.a['prior_control_CPU_charged_seconds']=361.;self.save()
        with self.assertRaisesRegex(RuntimeError,'price exceeds'):self.valid()
    def test3600_requires_measured_rate_no_more15(self):
        self.a['proof_CPU_charged_seconds']=1.;self.a['prior_control_CPU_charged_seconds']=121.
        self.a['pricing']['CPU_seconds_per_hour_upper']=15.01;self.save()
        with self.assertRaisesRegex(RuntimeError,'at most15'):self.valid()
    def test_allowance_cannot_exceed6400(self):
        self.a['control_CPU_allowance_seconds']=6401.;self.save()
        with self.assertRaisesRegex(RuntimeError,'allowance differs'):self.valid()
    def test_old_clock_and_debit_reset_denied(self):
        for field in ['historical_debits_credited','historical_claims_or_clocks_reset']:
            self.a[field]=True;self.save()
            with self.assertRaisesRegex(RuntimeError,'policy differs'):self.valid()
            self.a[field]=False
    def test_old_immutable_ledger_change_blocks(self):
        oldroot=Path(self.a['previous_authority_path']).parent;B.put(oldroot/'activation.json',dict(changed=True))
        with self.assertRaisesRegex(RuntimeError,'pinned source/evidence differs'):self.valid()
    def test_old_ledger_inventory_cannot_be_omitted(self):
        self.a['previous_immutable_sha256'].pop(next(iter(self.a['previous_immutable_sha256'])));self.save()
        with self.assertRaisesRegex(RuntimeError,'inventory differs'):self.valid()
    def test_unregistered_old_authority_denied(self):
        B.put(self.previous/'single_activation_claim.json',dict(id='wrong'))
        with self.assertRaisesRegex(RuntimeError,'registered R153'):self.valid()
    def test_new_source_does_not_accept_private_profile_as_production(self):
        self.a['kind']='R154_CZ_PRIVATE_PROFILE';self.save()
        with self.assertRaisesRegex(RuntimeError,'scope differs'):self.valid()
    def test_new_PT_failure_is_not_quarantined(self):
        B.put(self.base.predecessor/'progress.json',dict(failures=self.a['approved_predecessor_failures']+[dict(region='PT')]))
        with self.assertRaisesRegex(RuntimeError,'unapproved/new'):G.boundary_state(self.a,self.system)
    def test_each_old_science_record_and_preparation_denies_continuation(self):
        for path in G.prior_science_paths(self.a):
            B.put(path,{})
            with self.assertRaisesRegex(RuntimeError,'prior CZ science'):G.assert_no_prior_science(self.a)
            path.unlink()
    def test_old_task_registration_denies_even_without_claim(self):
        path=self.data/'campaigns'/self.a['effective_config']['tag']/'tasks/new.json';B.put(path,{})
        with self.assertRaisesRegex(RuntimeError,'prior CZ science'):G.assert_no_prior_science(self.a)
    def test_owned_preparation_exception_never_waives_old_science_claim(self):
        path=Path(self.a['previous_authority_path']).parent/'science_claim.json';B.put(path,{})
        with self.assertRaisesRegex(RuntimeError,'prior CZ science'):G.assert_no_prior_science(self.a,allow_own_preparation=True)
    def test_previous_live_waiter_blocks_new_run(self):
        self.launch_fixture();old=self.a['previous_waiter'];self.system.procs[66]=old['process']
        with mock.patch.object(G,'self_attestation',return_value={}):
            with self.assertRaisesRegex(RuntimeError,'physically drained'):G.run(self.path,self.a['waiter_unit'],system=self.system)
        self.assertFalse((self.runtime/'science_claim.json').exists())
    def test_ready_science_claim_is_global_create_once_and_freshly_rechecked(self):
        self.launch_fixture();before=Path(self.a['previous_authority_path']).read_bytes()
        with mock.patch.object(G,'self_attestation',return_value={}),mock.patch.object(G,'cpu_guard',return_value=360.),mock.patch.object(G,'publish_waiter_budget',return_value=dict(charged_CPU_seconds=361.)),mock.patch.object(G,'boundary_state',return_value=dict(ready=True)) as boundary:
            G.run(self.path,self.a['waiter_unit'],system=self.system)
        self.assertGreaterEqual(boundary.call_count,2)
        self.assertEqual(len(self.system.dispatches),1)
        self.assertEqual(G.read(G.RUNTIME/'science_dispatch_claim.json'),G.read(self.runtime/'science_claim.json'))
        self.assertEqual(Path(self.a['previous_authority_path']).read_bytes(),before)
        with self.assertRaises(FileExistsError):
            G.immutable(G.RUNTIME/'science_dispatch_claim.json',{})
    def test_old_claim_created_at_ready_recheck_prevents_dispatch(self):
        self.launch_fixture();calls=[]
        def state(*args):
            calls.append(1);B.put(Path(self.a['previous_authority_path']).parent/'science_claim.json',{})
            return dict(ready=True)
        with mock.patch.object(G,'self_attestation',return_value={}),mock.patch.object(G,'cpu_guard',return_value=360.),mock.patch.object(G,'boundary_state',side_effect=state):
            with self.assertRaisesRegex(RuntimeError,'prior CZ science'):G.run(self.path,self.a['waiter_unit'],system=self.system)
        self.assertFalse(self.system.dispatches)
    def test_fence_precedes_original_supervisor_and_supervisor_released_at_launch(self):
        events=[];original=self.data/'launch_prep'/self.a['effective_config']['tag']/'jerez/supervisor.lock'
        def fenced(*args):
            events.append('fence');self.assertFalse(original.exists())
        def started(*args):
            events.append('launch')
            with original.open('a') as stream:
                fcntl.flock(stream,fcntl.LOCK_EX|fcntl.LOCK_NB)
                fcntl.flock(stream,fcntl.LOCK_UN)
            return dict(started=True)
        with mock.patch.object(R,'fence_previous',side_effect=fenced),mock.patch.object(R,'start_waiter',side_effect=started):
            R.handoff_and_launch(self.path,system=self.system)
        self.assertEqual(events,['fence','launch'])
        self.assertTrue((G.RUNTIME/'single_activation_claim.json').exists())
    def test_inflight_old_science_after_fence_aborts_and_preserves_claim(self):
        claim=Path(self.a['previous_authority_path']).parent/'science_claim.json'
        def fenced(*args):B.put(claim,dict(claim=1))
        with mock.patch.object(R,'fence_previous',side_effect=fenced),mock.patch.object(R,'start_waiter') as start:
            with self.assertRaisesRegex(RuntimeError,'prior CZ science'):R.handoff_and_launch(self.path,system=self.system)
            start.assert_not_called()
        self.assertEqual(G.read(claim),dict(claim=1));self.assertFalse((G.RUNTIME/'single_activation_claim.json').exists())
    def test_spent_activation_does_not_signal_old_again(self):
        self.launch_fixture()
        with mock.patch.object(R,'fence_previous') as fence:
            with self.assertRaisesRegex(RuntimeError,'already spent'):R.handoff_and_launch(self.path,system=self.system)
            fence.assert_not_called()
    def test_unclassified_child_or_wrong_invocation_prevents_exact_fence(self):
        old=self.a['previous_waiter'];self.system.procs[66]=old['process']
        self.system.units[old['unit']]=dict(MainPID='66',InvocationID='old',ControlGroup=old['cgroup'],Restart='no',KillMode='process')
        self.system.groups[old['cgroup']]=[66,999]
        with mock.patch.object(R,'exact_pidfd_term') as term:
            with self.assertRaisesRegex(RuntimeError,'sole administrative'):R.fence_previous(self.a,self.path,self.system)
            term.assert_not_called()
    def test_pid_reuse_never_falls_back_to_pid_signal(self):
        expected=B.process(66);self.system.procs[66]=dict(expected,start_ticks=9999)
        with mock.patch.object(R,'pidfd_open',return_value=111),mock.patch.object(R.os,'close'),mock.patch.object(R,'pidfd_send') as send:
            with self.assertRaisesRegex(RuntimeError,'lifetime changed'):R.exact_pidfd_term(self.system,expected)
            send.assert_not_called()
    def test_missing_pidfd_support_blocks_without_plain_kill(self):
        with mock.patch.object(R,'pidfd_open',side_effect=RuntimeError('pidfd unavailable')),mock.patch.object(R.os,'kill') as kill:
            # A missing or noncallable pidfd API must fail before any signal.
            with self.assertRaises((RuntimeError,TypeError)):R.exact_pidfd_term(self.system,B.process(66))
            kill.assert_not_called()


if __name__=='__main__':unittest.main()
