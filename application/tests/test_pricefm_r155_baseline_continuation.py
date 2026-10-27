"""Synthetic metadata/private lifecycle boundaries; no target arrays or models."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import sys
import types
import unittest
import tempfile
import time
from unittest.mock import patch
HERE=Path(__file__).resolve().parents[1]/'scripts/pricefm'
sys.path.insert(0,str(HERE));sys.dont_write_bytecode=True
import pricefm_r155_baseline_contract as c
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,HERE/path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
runner=module('private_r155_baseline_runner','530_supervise_pricefm_stage_r155_baseline_continuation.py')
observer=module('private_r155_baseline_observer','533_inspect_pricefm_stage_r155_baseline_continuation.py')
activator=module('private_r155_baseline_activator','532_activate_pricefm_stage_r155_baseline_continuation.py')


class CensusBoundaries(unittest.TestCase):
    def system(self,protected=None):
        def one(path):
            if path.name==protected:raise PermissionError('protected fixture')
            return dict(pid=int(path.name),start_ticks=100,boot_id='fixture')
        return types.SimpleNamespace(boot_id='fixture',expected_pid_namespace='pid:[fixture]',
            census_process=one,stat_sample=lambda pid:dict(pid=pid,start_ticks=100,state='S'))

    def test_private_three_process_view_never_claims_host_health(self):
        with patch.object(c.os,'readlink',return_value='pid:[fixture]'):
            rows,proof=c.collect_census(self.system(),[Path('/private')/str(i) for i in range(3)])
        self.assertEqual(len(rows),3);self.assertFalse(proof['complete'])
        self.assertFalse(proof['full_host_view_verified']);self.assertEqual(proof['action'],'DEFER_ALL_NEW_DISPATCH')

    def test_unreadable_peer_is_retained_and_defers_every_dispatch(self):
        unresolved=dict(pid=17,unavailable_fields=[dict(field='cwd',error='PermissionError')],ownership_assumed=False)
        with patch.object(c.os,'readlink',return_value='pid:[fixture]'),patch.object(c,'partial_identity',return_value=unresolved):
            rows,proof=c.collect_census(self.system('17'),[Path('/private')/str(i) for i in range(101)])
        self.assertEqual(len(rows),100);self.assertFalse(proof['complete']);self.assertEqual(proof['unresolved'],[unresolved])
        self.assertFalse(proof['unknown_or_unreadable_processes_ignored'])

    def test_later_complete_census_reconciles_without_role_whitelist(self):
        with patch.object(c.os,'readlink',return_value='pid:[fixture]'):
            rows,proof=c.collect_census(self.system(),[Path('/private')/str(i) for i in range(101)])
        self.assertEqual(len(rows),101);self.assertTrue(proof['complete']);self.assertEqual(proof['unresolved'],[])

    def test_system_does_not_return_partial_rows_to_dispatcher(self):
        system=c.System.__new__(c.System);system.last_census=None
        proof=dict(complete=False,action='DEFER_ALL_NEW_DISPATCH')
        with patch.object(c,'collect_census',return_value=([dict(pid=1)],proof)):
            with self.assertRaises(c.CensusDeferred) as raised:system.processes()
        self.assertIs(raised.exception.observation,proof)

    def test_direct_protected_known_lifetime_is_typed_defer(self):
        system=c.System.__new__(c.System);system.boot_id='fixture';system.last_census=None
        anchor=dict(pid=17,start_ticks=100,state='S');system.stat_sample=lambda pid:anchor
        with (patch.object(c.old.System,'process',side_effect=PermissionError('fixture')),
              patch.object(c,'partial_identity',return_value=dict(pid=17,ownership_assumed=False))):
            with self.assertRaises(c.CensusDeferred) as raised:system.process(17)
        self.assertEqual(raised.exception.observation['action'],'DEFER_ALL_NEW_DISPATCH')

    def test_protection_after_complete_census_defers_without_policy_waiver(self):
        system=c.System.__new__(c.System);system.boot_id='fixture';system.last_census=None
        system.stat_sample=lambda pid:dict(pid=pid,start_ticks=100,state='S')
        system.processes=lambda:[dict(pid=17,start_ticks=100,boot_id='fixture')]
        state=dict(active={'A':dict(region='NL')})
        with (patch.object(c.old.System,'process',side_effect=PermissionError('after complete scan')),
              patch.object(c,'partial_identity',return_value=dict(pid=17,ownership_assumed=False)),
              patch.object(c.old,'session_members',side_effect=lambda job,sys,policy,census:sys.process(17))):
            with self.assertRaises(c.CensusDeferred):runner.reconcile_sessions(state,system,None)
        with (patch.object(c.old.System,'process',side_effect=RuntimeError('lifetime policy mismatch')),
              patch.object(c.old,'session_members',side_effect=lambda job,sys,policy,census:sys.process(17))):
            with self.assertRaises(RuntimeError) as raised:runner.reconcile_sessions(state,system,None)
        self.assertNotIsInstance(raised.exception,c.CensusDeferred)

    def test_census_wall_budget_never_returns_a_dispatchable_partial_view(self):
        with patch.object(c.time,'monotonic',side_effect=[0.,6.,6.]):
            with patch.object(c.os,'readlink',return_value='pid:[fixture]'):
                rows,proof=c.collect_census(self.system(),[Path('/private')/str(i) for i in range(101)])
        self.assertEqual(rows,[]);self.assertFalse(proof['complete'])
        self.assertEqual(proof['unresolved'][0]['error'],'BOUNDED_CENSUS_OBSERVATION_LIMIT_REACHED')

    def test_dispatch_function_is_never_reached_after_census_defer(self):
        deferred=c.CensusDeferred(dict(complete=False,unresolved=[]))
        with patch.object(runner,'reconcile_sessions',side_effect=deferred),patch.object(c.core(),'launch_region') as launch:
            with self.assertRaises(c.CensusDeferred):runner.step_lanes(dict(queues={'A':['NL']}),Path('/private'),None,dict(active={},completed={'A':[]},quarantined={'A':[]}),None,None,None)
        launch.assert_not_called()


class RHSBoundaries(unittest.TestCase):
    def fixture(self):
        return dict(kind='rhs'),dict(status='R123_SUCCESSOR_UNCERTIFIED',iterations=2000,
            termination_reason='gaussian_conditional_accuracy_rejected',full_variational_certified=False,
            initialization_only=True,test_opened=False,official_validation_opened=False,
            precision_accuracy=dict(accepted=False,maximum_inverse_residual=3.328388265799731e-5,jitter=0,tolerance=1e-5))

    def test_finite_false_screening_exclusion_keeps_packet_false_unchanged(self):
        task,terminal=self.fixture();before=copy.deepcopy(terminal)
        self.assertTrue(c.precision_rhs_exclusion(task,terminal));self.assertEqual(terminal,before)
        self.assertIs(terminal['full_variational_certified'],False)

    def test_required_normal_full_AL_or_unknown_reason_never_waived(self):
        task,terminal=self.fixture()
        for kind in ('normal_full','al','internal_al','unknown'):
            self.assertFalse(c.precision_rhs_exclusion(dict(kind=kind),terminal))
        terminal['termination_reason']='unknown';self.assertFalse(c.precision_rhs_exclusion(task,terminal))

    def test_original_threshold_cap_finiteness_and_no_test_opening_enforced(self):
        mutations=[lambda t:t.update(iterations=1999),lambda t:t.update(full_variational_certified=True),
            lambda t:t.update(test_opened=True),lambda t:t.update(official_validation_opened=True),
            lambda t:t['precision_accuracy'].update(accepted=True),lambda t:t['precision_accuracy'].update(jitter=False),
            lambda t:t['precision_accuracy'].update(jitter=1e-9),lambda t:t['precision_accuracy'].update(tolerance=1.000001e-5),
            lambda t:t['precision_accuracy'].update(maximum_inverse_residual=1e-5),
            lambda t:t['precision_accuracy'].update(maximum_inverse_residual=float('nan'))]
        for i,mutate in enumerate(mutations):
            with self.subTest(case=i):
                task,terminal=self.fixture();mutate(terminal)
                with self.assertRaises(RuntimeError):c.precision_rhs_exclusion(task,terminal)

    def test_metadata_imports_do_not_import_numerical_libraries(self):
        self.assertFalse(any(key in sys.modules for key in ('numpy','scipy','pandas')))


class AuthorityAndLifecycle(unittest.TestCase):
    def fixture(self,path):
        scope='1'*32;source=dict(root=str(c.ROOT),branch=c.BRANCH,head='2'*40,runtime_sha256={})
        prep_pin=dict(path='/private/preparation.json',sha256='3'*64);review_pin=dict(path='/private/review.json',sha256='4'*64)
        pin=dict(path='/private/old.json',sha256='5'*64);epoch=time.time()-1
        a=dict(schema='r155_baseline_control_authority_v1',status='ADMITTED',authority_id=scope,
            activation=copy.deepcopy(c.ACTIVATION),automatic_retry=False,cached_restart_authorized=False,numerical_parameters_changed=False,
            runtime=str(c.DATA/'launch_prep'/('pricefm_stage_r155_baseline_continuation_'+scope)),
            new_unit='pricefm-r155-baseline-owner-'+scope+'.service',guardian_unit='pricefm-r155-baseline-guardian-'+scope+'.service',
            execution_source=source,preparation=prep_pin,source_review=review_pin,
            predecessor_authority=pin,predecessor_state=pin,predecessor_state_original=pin,predecessor_attestation=pin,original_dispatch_locks=[],
            predecessor_control_CPU_retained=c.PRIOR_CONTROL_CPU,predecessor_unobserved_tail_CPU_reserve=60,
            preparation_CPU_debit=600,activation_wrapper_CPU_reserve=30,guardian_CPU_reserve=600,
            grant=dict(starts_epoch=c.ORIGINAL_START,expires_epoch=c.ORIGINAL_EXPIRY,wall_seconds=604800,
                control_CPU_seconds=c.ORIGINAL_CPU,prior_control_CPU_seconds=c.PRIOR_CONTROL_CPU+60+600+30,
                administrative_source_check_CPU_reservation=.5,administrative_poll_CPU_reservation=.1),
            activation_epoch=epoch,unit_runtime_max_seconds=int(c.ORIGINAL_EXPIRY-epoch-300),administrative_cpu=31,
            expected_host_pid_namespace='pid:[4026531836]',expected_boot_id='37b80e3b-9596-4c75-85e1-aca85af8fa7f',
            poll_seconds=20,source_verify_seconds=60,guardian_lease_seconds=180)
        a.update(control_intent=c.intent(a['new_unit'],'run',path),guardian_intent=c.intent(a['guardian_unit'],'guard',path))
        prep={key:a[key] for key in ('execution_source','predecessor_authority','predecessor_state','predecessor_state_original','predecessor_attestation','original_dispatch_locks')}
        prep.update(dependency_sha256={},predecessor_runtime_sha256={})
        review=dict(status='PASS_RUNTIME_SOURCE',administrative_runtime_review=True,execution_source=source)
        return a,prep,review

    def validate(self,path,a,prep,review):
        def verify(value):
            if value==a['preparation']:return prep
            if value==a['source_review']:return review
            raise AssertionError('unexpected private proof request')
        with patch.object(c,'read',return_value=a),patch.object(c,'verify_pin',side_effect=verify),patch.object(c,'verify_source'),patch.object(c,'check_pins'):
            return c.validate_authority(path)

    def test_complete_shape_keeps_original_clock_and_cumulative_debits(self):
        path=Path('/private/authority.json');a,prep,review=self.fixture(path)
        self.assertIs(self.validate(path,a,prep,review),a)
        self.assertEqual(a['grant']['starts_epoch'],c.ORIGINAL_START)
        self.assertGreater(a['grant']['prior_control_CPU_seconds'],c.PRIOR_CONTROL_CPU+600)
        self.assertEqual(a['control_intent']['nice'],0);self.assertEqual(a['control_intent']['CPU_hard_limit'],'infinity')

    def test_clock_budget_activation_ancestry_and_runtime_review_boundaries(self):
        changes=[lambda a,r:a['grant'].update(starts_epoch=time.time()),
            lambda a,r:a['grant'].update(expires_epoch=c.ORIGINAL_EXPIRY+1),
            lambda a,r:a['grant'].update(control_CPU_seconds=57600),
            lambda a,r:a['grant'].update(prior_control_CPU_seconds=0),
            lambda a,r:a.update(predecessor_unobserved_tail_CPU_reserve=0),
            lambda a,r:a.update(preparation_CPU_debit=0),lambda a,r:a.update(automatic_retry=True),
            lambda a,r:a['activation'].update(cumulative_owner_count=4),
            lambda a,r:a.update(administrative_cpu=0),lambda a,r:a['control_intent'].update(nice=10),
            lambda a,r:a['control_intent'].update(CPU_hard_limit=600),
            lambda a,r:a.update(unit_runtime_max_seconds=int(c.ORIGINAL_EXPIRY-a['activation_epoch'])),
            lambda a,r:r.update(status='PASS_CONDITIONAL_ONLY',administrative_runtime_review=False)]
        for i,change in enumerate(changes):
            with self.subTest(case=i):
                path=Path('/private/authority.json');a,prep,review=self.fixture(path);change(a,review)
                with self.assertRaises(RuntimeError):self.validate(path,a,prep,review)

    def test_late_unit_start_is_rejected_without_starting_any_service(self):
        a=dict(unit_runtime_max_seconds=100)
        with patch.object(activator.time,'time',return_value=c.ORIGINAL_EXPIRY-120),patch.object(activator.subprocess,'run') as launch:
            with self.assertRaises(RuntimeError):activator.start_control({},a,Path('/private/log'))
        launch.assert_not_called()

    def test_running_original_session_is_never_restarted_or_resized(self):
        job=dict(region='NL',phase='controller',cpus=list(range(15)),process=dict(pid=17),session_id=17)
        state=dict(active={'A':copy.deepcopy(job)},completed={'A':[]},quarantined={'A':[]});before=copy.deepcopy(state)
        with patch.object(runner,'reconcile_sessions',return_value=[]),patch.object(c.old,'session_members',return_value=[dict(pid=17)]),patch.object(c.core(),'launch_region') as launch:
            result=runner.step_lanes(dict(queues={'A':['NL']}),Path('/private'),None,state,None,None,None)
        self.assertEqual(result,before);launch.assert_not_called()

    def test_private_observer_never_reports_host_owner_dead_or_healthy(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'authority.json';a,prep,review=self.fixture(path);path.write_text(json.dumps(a))
            with patch.object(observer,'host_context',return_value=dict(full_host_view_verified=False,visible_processes=3)):
                result=observer.inspect(path,c.digest(path))
            self.assertEqual(result['status'],'UNVERIFIED_OBSERVER_NAMESPACE');self.assertIsNone(result['healthy_control'])
            self.assertFalse(result['dispatch_currently_permitted']);self.assertEqual(result['runtime_writes'],0)

    def test_guardian_first_state_epoch_publication_gap_is_bounded(self):
        for age,wanted in ((1,'wait'),(60,'blocked')):
            with self.subTest(age=age),tempfile.TemporaryDirectory() as directory:
                runtime=Path(directory);path=runtime/'authority.json';path.write_text('{}');now=time.time()
                owner=dict(pid=17,start_ticks=1,boot_id='fixture',cmdline_sha256='owner',cwd='/private')
                guardian=dict(pid=os.getpid(),start_ticks=2,boot_id='fixture',cmdline_sha256='guardian',cwd='/private')
                a=dict(runtime=str(runtime),guardian_unit='private.service',authority_id='1'*32,execution_source=dict(head='fixture'))
                state=dict(authority=c.pin(path),activation=c.ACTIVATION,source=a['execution_source'],phase='adopted_ready',owner=owner)
                (runtime/'state.json').write_text(json.dumps(state));attestation=dict(epoch=now-age)
                system=types.SimpleNamespace(cpu_seconds=lambda pid,start:0.)
                def capsule(a,attest,mode,system):return (guardian if mode=='guard' else owner),{}
                with patch.object(runner,'control_capsule',side_effect=capsule):
                    self.assertEqual(runner.guard_once(path,'private.service',system,a,attestation,now),wanted)
                self.assertEqual((runtime/'guardian_blocked.json').exists(),wanted=='blocked')

    def test_pin_replacement_cannot_satisfy_old_proof(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'proof.json';path.write_text('{}');pin=c.pin(path);path.write_text('{"changed":true}')
            with self.assertRaises(RuntimeError):c.verify_pin(pin)


class PublicationAndKernel(unittest.TestCase):
    def test_private_kernel_flock_busy_and_replaced_inode(self):
        import fcntl
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'original.lock';path.touch();stat=path.stat()
            a=dict(original_dispatch_locks=[dict(path=str(path),device=stat.st_dev,inode=stat.st_ino)])
            c.verify_original_locks(a,require_free=True)
            with path.open('r+') as held:
                fcntl.flock(held,fcntl.LOCK_EX|fcntl.LOCK_NB)
                with self.assertRaises(BlockingIOError):c.verify_original_locks(a,require_free=True)
                path.unlink();path.touch()
                with self.assertRaises(RuntimeError):c.verify_original_locks(a)

    def test_partial_JSON_and_hash_instability_are_bounded_metadata_retries(self):
        with patch.object(Path,'read_bytes',side_effect=[b'{',b'{"v":2}',b'{"v":2}']),patch.object(c.time,'sleep'):
            self.assertEqual(c.read_published('/private/publication.json'),{'v':2})
        with patch.object(Path,'read_bytes',side_effect=[b'{"v":1}',b'{"v":2}',b'{"v":2}',b'{"v":2}']),patch.object(c.time,'sleep'):
            self.assertEqual(c.read_published('/private/publication.json'),{'v':2})

    def test_missing_metadata_has_bounded_pending_receipt(self):
        with patch.object(Path,'read_bytes',side_effect=FileNotFoundError('fixture')):
            with self.assertRaises(c.PublicationPending) as raised:c.read_published('/private/missing.json',max_wait_seconds=0)
        self.assertEqual(raised.exception.observation['status'],'BOUNDED_METADATA_PUBLICATION_INCOMPLETE')
        self.assertTrue(raised.exception.observation['attempts'])

    def test_stable_semantic_mismatch_is_not_suppressed(self):
        with patch.object(Path,'read_bytes',return_value=b'{"authority":"wrong"}') as reader:
            value=c.read_published('/private/wrong.json')
            with self.assertRaises(RuntimeError):c.require(value['authority']=='expected','semantic authority mismatch')
        self.assertEqual(reader.call_count,2)

    def test_health_publication_pending_does_not_claim_control_failure(self):
        pending=c.PublicationPending('/private/new.json',[dict(error='JSONDecodeError')])
        with patch.object(observer,'_inspect',side_effect=pending):result=observer.inspect('/private/grant','1'*64)
        self.assertEqual(result['status'],'METADATA_PUBLICATION_PENDING');self.assertIsNone(result['healthy_control'])
        self.assertEqual(result['runtime_writes'],0)
        with patch.object(observer,'_inspect',side_effect=RuntimeError('source mismatch')):
            with self.assertRaises(RuntimeError):observer.inspect('/private/grant','1'*64)

    def test_activation_budget_counts_whole_startup_and_reaped_CPU(self):
        usage=dict(own_CPU_seconds=10.,reaped_subprocess_CPU_seconds=3.,whole_invocation_own_plus_reaped_CPU=13.)
        with patch.object(activator,'wrapper_usage',return_value=usage),patch.object(activator.resource,'getrlimit',return_value=(-1,-1)),patch.object(activator.resource,'setrlimit') as limit:
            self.assertEqual(activator.wrapper_budget(dict(activation_wrapper_CPU_reserve=30)),usage)
        self.assertIn(unittest.mock.call(activator.resource.RLIMIT_CPU,(27,27)),limit.call_args_list)
        usage=dict(own_CPU_seconds=25.,reaped_subprocess_CPU_seconds=4.,whole_invocation_own_plus_reaped_CPU=29.)
        with patch.object(activator,'wrapper_usage',return_value=usage):
            with self.assertRaises(RuntimeError):activator.wrapper_budget(dict(activation_wrapper_CPU_reserve=30))

    def test_immediate_pending_or_blocked_proof_never_gets_healthy_activation_status(self):
        self.assertEqual(activator.activation_disposition(dict(healthy_control=None)),'ONE_FIFTH_CONTROL_ACTIVATION_METADATA_PENDING_NO_RETRY')
        self.assertEqual(activator.activation_disposition(dict(healthy_control=False)),'ONE_FIFTH_CONTROL_ACTIVATION_BLOCKED_AFTER_REGISTRATION_NO_RETRY')
        self.assertEqual(activator.activation_disposition(dict(healthy_control=True,dispatch_currently_permitted=False)),
            'ONE_FIFTH_CONTROL_ACTIVATION_HEALTHY_NO_RETRY')


class TerminalTransition(unittest.TestCase):
    def fixture(self,runtime,alive,bad=None):
        path=runtime/'authority.json';path.write_text('{}');source=dict(head='fixture')
        a=dict(runtime=str(runtime),execution_source=source,new_unit='owner.service',guardian_unit='guardian.service',
            predecessor_authority=dict(path='/private/prior.json',sha256='1'*64))
        completed=dict(A=['NL'],B=[]);quarantined=dict(A=[],B=[])
        state=dict(completed=completed,quarantined=quarantined,active={})
        terminal=dict(status='R155_ORIGINAL_NINE_TAIL_DISPOSITIONS_NOT_GLOBAL_PROMOTION',authority=c.pin(path),
            activation=c.ACTIVATION,execution_source=source,completed=completed,quarantined=quarantined,numerical_source_head='science')
        (runtime/'terminal.json').write_text(json.dumps(terminal));processes={};attestation={};units={}
        for index,label in enumerate(('owner','guardian')):
            name=a['new_unit' if label=='owner' else 'guardian_unit'];pid=101+index
            life=dict(pid=pid,start_ticks=100+index,boot_id='fixture',cmdline_sha256=label,cwd=str(c.ROOT))
            attestation[label]=dict(process=life,unit_properties=dict(InvocationID=label))
            if label in alive:processes[pid]=life
            units[name]=dict(Id=name,LoadState='loaded',ActiveState='active',SubState='running' if label in alive else 'exited',
                MainPID=str(pid) if label in alive else '0',RemainAfterExit='yes',Result='success',ExecMainStatus='0',
                InvocationID=label,Restart='no',NRestarts='0',KillMode='process',ExecMainPID=str(pid))
        if bad=='missing':units['guardian.service'].update(LoadState='not-found',ActiveState='inactive',InvocationID='')
        if bad=='failed':units['guardian.service'].update(ActiveState='failed',SubState='failed',Result='exit-code',ExecMainStatus='1')
        if bad=='restart':units['guardian.service']['NRestarts']='1'
        system=types.SimpleNamespace(unit=lambda name:units[name],process=lambda pid:processes.get(pid))
        prior=dict(legacy_config_path='/private/config.json',runtime='/private/old')
        config=dict(source_head='science',queues=dict(A=['NL'],B=[]))
        return a,path,state,attestation,system,prior,config

    def test_exit_pending_complete_and_unverified_failures_are_distinct(self):
        cases=[({'owner','guardian'},None,'COMPLETE_PACKET_AWAITING_RETAINED_UNIT_EXIT',True,False),
            ({'guardian'},None,'COMPLETE_PACKET_AWAITING_RETAINED_UNIT_EXIT',True,False),
            (set(),None,'COMPLETED_RETAINED_UNITS',True,True),
            (set(),'missing','COMPLETE_PACKET_CONTROL_EXIT_UNVERIFIED',False,False),
            (set(),'failed','COMPLETE_PACKET_CONTROL_EXIT_UNVERIFIED',False,False),
            (set(),'restart','COMPLETE_PACKET_CONTROL_EXIT_UNVERIFIED',False,False)]
        for alive,bad,status,healthy,closed in cases:
            with self.subTest(alive=alive,bad=bad),tempfile.TemporaryDirectory() as directory:
                a,path,state,attest,system,prior,config=self.fixture(Path(directory),alive,bad)
                with patch.object(c,'verify_pin',return_value=prior),patch.object(c.core(),'read_config',return_value=config),patch.object(c.core(),'complete_region',return_value=True):
                    result=observer.terminal_proof(a,path,state,attest,system)
                self.assertEqual(result['status'],status);self.assertEqual(result['healthy_control'],healthy)
                self.assertEqual(result['retained_unit_closure_verified'],closed)


if __name__=='__main__':unittest.main()
