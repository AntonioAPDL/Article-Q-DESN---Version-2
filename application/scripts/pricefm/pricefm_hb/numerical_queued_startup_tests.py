"""Source/metadata fixtures only: no process, scheduler, R or target execution."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from . import numerical_batch as batch
from . import numerical_critical_driver as driver
from . import numerical_independent_peer as peer


class Clock:
    def __init__(self):self.now=0.
    def monotonic(self):return self.now
    def sleep(self,seconds):self.now+=seconds


class WaitingTests(unittest.TestCase):
    def exercise(self,sequence,duration=1):
        clock=Clock();calls=[]
        def probe(index):
            calls.append(index);clock.now+=duration
            status=sequence[min(index,len(sequence)-1)]
            return dict(result=dict(status=status,probe_index=index,production_admission=False,
                                    ready=dict(path='/UNIT/READY.json',sha256='a'*64)))
        with patch.object(driver.time,'monotonic',side_effect=clock.monotonic),patch.object(driver.time,'sleep',side_effect=clock.sleep):
            try:return driver.wait_for_startup_ready(probe,batch.STARTUP_WATCH_PROFILE),calls,clock.now
            except ValueError as error:return str(error),calls,clock.now
    def test_delayed_allocation_then_ready(self):
        result,calls,seconds=self.exercise(['STARTUP_WAITING_READY_ABSENT_NO_RELEASE']*2+['STARTUP_READY_PRESENT_MATCHED_NO_RELEASE'])
        self.assertEqual(calls,[0,1,2]);self.assertEqual(seconds,43)
        self.assertEqual(result['status'],'STARTUP_READY_OBSERVED_AWAIT_ONE_SHOT_READY')
    def test_all_absent_has_finite_ten_probes(self):
        result,calls,seconds=self.exercise(['STARTUP_WAITING_READY_ABSENT_NO_RELEASE'])
        self.assertEqual(calls,list(range(10)));self.assertEqual(seconds,190);self.assertIn('exhausted',result)
    def test_never_starts_guard_without_complete_remaining_envelope(self):
        result,calls,seconds=self.exercise(['STARTUP_WAITING_READY_ABSENT_NO_RELEASE'],duration=44)
        self.assertEqual(calls,[0,1,2,3,4]);self.assertLess(seconds,300);self.assertIn('complete original guardian',result)
    def test_invalid_probe_state_cannot_wait(self):
        result,calls,_=self.exercise(['TRANSPORT_ERROR']);self.assertIsInstance(result,str);self.assertEqual(calls,[0])
    def test_profile_cannot_be_expanded(self):
        changed=dict(batch.STARTUP_WATCH_PROFILE,maximum_probes=11)
        with self.assertRaises(ValueError):driver.wait_for_startup_ready(lambda _:None,changed)


class ProbeTests(unittest.TestCase):
    def fixture(self,folder):
        root=folder/'registry/ZERO_UPDATE_BRIDGE';root.mkdir(parents=True)
        startup=folder/'critical_driver/startup';startup.mkdir(parents=True)
        packet=dict(role='ZERO_UPDATE_BRIDGE',scope_id='UNIT_ONLY_NONAUTHORITY',remote_root='/UNIT_REMOTE/NONAUTHORITY',
                    spec_sha256='a'*64,sources={'numerical_batch.py':dict(path='/UNIT_SOURCE',sha256=batch.digest(batch.__file__))})
        batch.h.write_new(root/'PACKET.json',packet)
        batch.h.write_new(root/'JOB.json',dict(job_id='123',scope_id=packet['scope_id']))
        batch.append(root,'PREPARED',packet=batch.h.pin(root/'PACKET.json'))
        batch.append(root,'SUBMITTED')
        scope=dict(issued_epoch=0,expires_epoch=2000000000,allowed_metadata_output_root=str(folder),
                   administrative_allocations={'startup_watch60':60},new_separate_administrative_CPU_reservation=234)
        budget=folder/'BUDGET.json';batch.h.write_new(budget,dict(status='PROSPECTIVE_FRESH_NUMERICAL_STARTUP_WATCH_BUDGET',
            scope=dict(path='/UNIT_SCOPE',sha256='b'*64),profile=batch.STARTUP_WATCH_PROFILE,expires_epoch=scope['expires_epoch']))
        config=dict(role=packet['role'],registry=str(root.parent),scope=dict(path='/UNIT_SCOPE',sha256='b'*64),
                    critical_driver=batch.h.pin(driver.__file__),startup_watch_budget=batch.h.pin(budget))
        cp=folder/'CONFIG.json';batch.h.write_new(cp,config)
        authority=dict(status='ROOT_AUTHORIZED_FROZEN525_NUMERICAL_CRITICAL_LIFECYCLE',
            config=batch.h.pin(cp),scope=config['scope'],driver_source=config['critical_driver'],
            startup_watch_profile=batch.STARTUP_WATCH_PROFILE,startup_watch_budget=config['startup_watch_budget'],
            issued_epoch=0,expires_epoch=scope['expires_epoch'],driver_maximum_wall_seconds=1200)
        ap=folder/'AUTHORITY.json';batch.h.write_new(ap,authority)
        ready=dict(status='READY_SOURCE_BOUND_COMPUTE_METADATA',scope_id=packet['scope_id'],job_id='123',
            role=config['role'],spec_sha256=packet['spec_sha256'],sources=packet['sources'],node='node-13',
            affinity=[0],cpus_per_task=1,models=0,physical_snapshot_value=dict(observed_epoch=1000000000.))
        return root,startup,packet,scope,config,cp,authority,ap,ready
    def test_complete_startup_budget_and_scope_binding_are_required(self):
        with tempfile.TemporaryDirectory() as td:
            root,startup,packet,scope,config,cp,authority,ap,ready=self.fixture(Path(td))
            self.assertEqual(batch.validate_startup_watch_budget(config,scope)['profile'],batch.STARTUP_WATCH_PROFILE)
            with self.assertRaises(ValueError):batch.validate_startup_watch_budget(config,dict(scope,new_separate_administrative_CPU_reservation=233))
            changed=batch.h.read(config['startup_watch_budget']);changed['profile']['probe_remote_unknown_fee']=0
            altered=Path(td)/'ALTERED_BUDGET.json';batch.h.write_new(altered,changed)
            with self.assertRaises(ValueError):batch.validate_startup_watch_budget(dict(config,startup_watch_budget=batch.h.pin(altered)),scope)
    def run_probe(self,folder,rc=0,mutation=None):
        root,startup,packet,scope,config,cp,authority,ap,ready=self.fixture(folder)
        if mutation:mutation(ready)
        raw=dict(argv=['test','-f',packet['remote_root']+'/READY.json'],returncode=rc,stdout='',stderr='')
        def transfer(site,commands,path):
            path.write_text('\n'.join(commands)+'\n')
            batch.h.write_new(startup/'probe_00.READY.json',ready)
            return dict(returncode=0,stdout='',stderr='')
        with patch.object(batch,'load_config',return_value=(config,scope,{},{})),\
             patch.object(batch,'require_outer_context'),patch.object(batch.resource,'getrlimit',return_value=(3,3)),\
             patch.object(batch.resource,'setrlimit'),patch.object(batch.time,'time',return_value=1000000001.),\
             patch.object(batch,'run_native',return_value=raw),patch.object(batch,'run_sftp',side_effect=transfer):
            value=batch.startup_probe(str(cp),batch.h.pin(ap),0)
        return value,(root,startup,packet,scope,config,cp,authority,ap,ready)
    def test_actual_probe_absence_is_waiting_not_ready_action(self):
        with tempfile.TemporaryDirectory() as td:
            result,context=self.run_probe(Path(td),rc=1);root=context[0]
            self.assertEqual(result['status'],'STARTUP_WAITING_READY_ABSENT_NO_RELEASE')
            self.assertFalse((root/'ready.intent.json').exists());self.assertFalse((root/'READY.json').exists())
    def test_actual_probe_present_validates_exact_ready(self):
        with tempfile.TemporaryDirectory() as td:
            result,_=self.run_probe(Path(td));self.assertEqual(result['status'],'STARTUP_READY_PRESENT_MATCHED_NO_RELEASE')
            self.assertEqual(result['ready']['sha256'],batch.h.pin(result['ready']['path'])['sha256'])
    def test_transport_failure_is_fatal_and_raw_preserved(self):
        with tempfile.TemporaryDirectory() as td:
            folder=Path(td)
            with self.assertRaisesRegex(ValueError,'transport'):self.run_probe(folder,rc=255)
            self.assertTrue((folder/'critical_driver/startup/probe_00.native.json').is_file())
    def test_foreign_nonce_is_fatal_before_one_shot_ready(self):
        with tempfile.TemporaryDirectory() as td:
            with self.assertRaisesRegex(ValueError,'stale/foreign'):self.run_probe(Path(td),mutation=lambda x:x.update(scope_id='FOREIGN'))
    def test_stale_snapshot_is_fatal(self):
        with tempfile.TemporaryDirectory() as td:
            with self.assertRaisesRegex(ValueError,'stale or future'):self.run_probe(Path(td),mutation=lambda x:x['physical_snapshot_value'].update(observed_epoch=999999000.))
    def test_real_peer_reconciles_guard_and_ready_metadata(self):
        from .numerical_independent_startup_peer_tests import StartupFixture
        with tempfile.TemporaryDirectory() as td:
            fixture=StartupFixture(Path(td),absent=0)
            self.assertEqual(fixture.review(),fixture.watch)
            fixture.change_guard(0,lambda value:value.update(session_id=1))
            with self.assertRaisesRegex(ValueError,'actual paid H3'):
                fixture.review()


def row(state='CANCELLED by 269188',alloc='0',cpu='00:00:00',elapsed='0',job='123',name='UNIT'):
    return '|'.join([job,state,'0:0',cpu,elapsed,alloc,name,'128x24','128x24','8Gn',''])+'\n'


class AccountingTests(unittest.TestCase):
    def test_unallocated_pending_and_cancelled_never_complete_or_admit(self):
        for state in ['PENDING','CONFIGURING','CANCELLED by 269188']:
            value=batch.parse_accounting(row(state=state),'123','UNIT')
            self.assertFalse(value['complete']);self.assertFalse(value['numerical_admission'])
            self.assertEqual(value['terminal'],state.startswith('CANCELLED'));self.assertEqual(value['allocated_CPUs'],0)
    def test_unallocated_completed_cpu_elapsed_steps_or_foreign_are_rejected(self):
        for raw in [row(state='COMPLETED'),row(cpu='00:00:01'),row(elapsed='1'),
                    row()+row(job='123.batch'),row(name='FOREIGN')]:
            with self.subTest(raw=raw):
                with self.assertRaises(ValueError):batch.parse_accounting(raw,'123','UNIT')
    def test_success_still_requires_original_allocated_steps(self):
        primary=row(state='COMPLETED',alloc='1',cpu='00:00:01',elapsed='2')
        self.assertFalse(batch.parse_accounting(primary,'123','UNIT')['complete'])
        complete=primary+row(state='COMPLETED',alloc='1',cpu='00:00:01',elapsed='2',job='123.batch',name='batch')
        self.assertTrue(batch.parse_accounting(complete,'123','UNIT')['complete'])
    def test_raw_accounting_preserved_before_parse_error_and_poll_intent_spent(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);batch.h.write_new(root/'PACKET.json',dict(scope_id='UNIT'))
            batch.h.write_new(root/'JOB.json',dict(job_id='123'))
            batch.append(root,'PREPARED',packet=batch.h.pin(root/'PACKET.json'))
            raw=dict(returncode=0,stdout='malformed native reply',stderr='')
            with patch.object(batch,'run_native',return_value=raw):
                with self.assertRaises(ValueError):batch.observe({},root)
            self.assertEqual(batch.h.read(batch.h.pin(root/'accounting_raw_0000.json')),raw)
            self.assertTrue((root/'observe_00.intent.json').exists())
    def test_actual_unallocated_retirement_requires_three_native_absences(self):
        with tempfile.TemporaryDirectory() as td:
            folder=Path(td);root=folder/'registry/ZERO_UPDATE_BRIDGE';root.mkdir(parents=True)
            batch.h.write_new(root/'PACKET.json',dict(scope_id='UNIT',remote_root='/UNIT/remote'))
            batch.h.write_new(root/'JOB.json',dict(job_id='123'))
            batch.append(root,'PREPARED',packet=batch.h.pin(root/'PACKET.json'))
            account=folder/'ACCOUNT.json';batch.h.write_new(account,batch.parse_accounting(row(),'123','UNIT'))
            batch.append(root,'OBSERVED',accounting=batch.h.pin(account))
            review=folder/'REVIEW.json';batch.h.write_new(review,dict(status='PASS_REVIEWED_FROZEN525_FAILED_ROLE_RETIREMENT',
                job_id='123',accounting=batch.h.pin(account)))
            calls=[]
            def native(site,argv):
                calls.append(argv)
                return dict(argv=argv,returncode=1 if argv[:2]==['test','-e'] else 0,stdout='',stderr='')
            with patch.object(batch,'run_native',side_effect=native):
                result=batch.retire_failed(dict(registry=str(root.parent),remote_namespace='/UNIT'),dict(user='UNIT'),root,str(review))
            self.assertEqual(result['status'],'FAILED_RETIRED_NO_RETRY')
            self.assertEqual([x[2] for x in calls if x[:2]==['test','-e']],
                ['/UNIT/remote/READY.json','/UNIT/remote/release/RELEASE.json','/UNIT/remote/result/RETURN_MANIFEST.json'])


if __name__=='__main__':unittest.main()

