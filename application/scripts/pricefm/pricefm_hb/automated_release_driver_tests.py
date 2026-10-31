"""Synthetic causal/failure metadata tests. No native jobs or guards execute."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from . import automated_release_driver as m


class Clock:
    def __init__(self):self.value=0
    def __call__(self):return self.value
    def sleep(self,n):self.value+=n


class FixtureCore:
    def prepare_release(self,config,bundle):
        bundle.mkdir(mode=0o700)
        for name in ['install_spec.json','owner_spec.json','namespace_spec.json']:m.write_new(bundle/name,dict(synthetic_unissued_metadata=True))
        for prefix,status in [('install','ROOT_ADMITTED_NEW_SCIENTIFIC_CODE_NAMESPACE_ONLY'),('owner','ROOT_ADMITTED_R179_SCIENTIFIC_METADATA_ONLY')]:
            m.write_new(bundle/(prefix+'_authority_TEMPLATE.json'),dict(status='PROPOSED_UNISSUED',required_status=status,expires_epoch=time.time()+3600))


class FixtureDriver(m.Driver):
    def __init__(self,*args,failure=None,late=False,bad_peer=False,**kwargs):
        super().__init__(*args,**kwargs);self.actions=[];self.failure=failure;self.late=late;self.bad_peer=bad_peer
    def guarded(self,action,previous_guard,*,bundle=None):
        self.check();self.actions.append(action);self.record(action.upper()+'_INTENT')
        if self.failure==action:raise m.DriverError('synthetic failed H '+action)
        if action=='submit':m.write_new(self.x['root']/'JOB.json',dict(job_id='999'))
        if action=='ready':m.write_new(self.x['root']/'READY.json',dict(synthetic_metadata=True))
        if action=='release':
            assert (bundle/'RELEASE.json').exists()
            assert 'peer_passed' in self.actions
        path=self.x['output']/(action+'.guard.json');m.write_new(path,dict(synthetic_metadata_only=True))
        return path,dict(status=action.upper())
    def peer(self,bundle,submit_guard,ready_guard):
        self.check();self.actions.append('peer')
        if self.failure=='peer':raise m.DriverError('synthetic independent reviewer failure')
        x=self.x;p=x['packet'];folder=p['remote_root']+'/release'
        remote=lambda n:dict(path=folder+'/'+n,sha256=m.pin(bundle/n)['sha256'])
        for prefix,status in [('install','PASS_REVIEWED_SCIENTIFIC_CODE_INSTALL_SOURCE_AND_SPEC'),('owner','PASS_REVIEWED_R179_SCIENTIFIC_METADATA_OWNER_AND_SPEC')]:
            m.write_new(bundle/(prefix+'_review.json'),dict(status=status,spec=remote(prefix+'_spec.json'),authority=remote(prefix+'_authority.json'),actual_peer_scope=x['settings']['peer_scope'],config=x['config_pin']))
        stages=dict(install_spec=remote('install_spec.json'),install_authority=remote('install_authority.json'),install_review=remote('install_review.json'),namespace_spec=remote('namespace_spec.json'),owner_spec=remote('owner_spec.json'),owner_authority=remote('owner_authority.json'),owner_review=remote('owner_review.json'))
        peer=dict(status='FAIL' if self.bad_peer else 'PASS_REVIEWED_STARTUP_BATCH_RELEASE',purpose='SCIENTIFIC_METADATA_ONLY',role=x['config']['role'],scope_id=p['scope_id'],job_id='999',node=x['config']['node'],ready_sha256=m.pin(x['root']/'READY.json')['sha256'],spec_sha256=p['spec_sha256'],sources=p['sources'],stage_pins=stages,review_source=x['settings']['reviewer'],actual_peer_scope=x['settings']['peer_scope'],config=x['config_pin'],expires_epoch=time.time()+3600)
        m.write_new(bundle/'PEER_RELEASE.json',peer)
        m.write_new(x['output']/'peer.stdout',dict(status='ACTUAL_NAMESPACE_INSTALL_OWNER_AND_OUTER_RELEASE_REVIEWED',independent_review=remote('PEER_RELEASE.json'),stage_pins=stages))
        self.actions.append('peer_passed')
        if self.late:self.clock.value=81


class DriverTests(unittest.TestCase):
    def context(self,tmp):
        p=Path(tmp);root=p/'role';root.mkdir();out=p/'driver'
        src=p/'source.py';src.write_text('synthetic metadata source, never executed')
        scope=p/'scope.json';m.write_new(scope,dict(synthetic_metadata_only=True))
        stage=p/'stage.guard.json';m.write_new(stage,{})
        packet_peer=p/'packet_peer.json';m.write_new(packet_peer,{})
        config=p/'config.json';m.write_new(config,dict(synthetic_metadata_only=True))
        d=dict(local_python=dict(path=sys.executable,sha256=m.pin(Path(sys.executable).resolve())['sha256']),source=m.pin(src),reviewer=m.pin(src),peer_scope=m.pin(scope),invocation_scope=m.pin(scope),settle_seconds=8,supervisor=m.pin(src))
        return dict(output=out,root=root,config=dict(role='SCIENTIFIC_NAMESPACE_NO_OPTIMIZER',node='node-13',scope=m.pin(scope),source_dir=str(p)),config_pin=m.pin(config),config_path=str(config),settings=d,
            scope=dict(expires_epoch=time.time()+3600),invocation_scope=dict(expires_epoch=time.time()+3600),packet=dict(scope_id='synthetic-unit-only',remote_root='/private/synthetic',spec_sha256='a'*64,sources={}),stage_guard=str(stage),packet_review=str(packet_peer),core=FixtureCore(),fixed_pins=[m.pin(src)])
    def driver(self,x,**kw):
        clock=Clock();return FixtureDriver(x,clock=clock,sleeper=clock.sleep,**kw)

    def test_single_invocation_orders_submit_READY_independent_PASS_before_release(self):
        with tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
            x=self.context(tmp);d=self.driver(x);result=d.execute()
            self.assertEqual(d.actions,['submit','ready','peer','peer_passed','release'])
            self.assertIn('NOT_RUNTIME_PROOF',result['status'])
            release=m.read(x['output']/'bundle/RELEASE.json');self.assertEqual(len(release['files']),8)
            self.assertFalse(result['namespace_ABI_TSYNC_or_numerical_acceptance'])

    def test_failed_submit_READY_or_peer_stops_without_RELEASE(self):
        for phase in ['submit','ready','peer']:
            with self.subTest(phase=phase),tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
                x=self.context(tmp);d=self.driver(x,failure=phase)
                with self.assertRaises(m.DriverError):d.execute()
                self.assertFalse((x['output']/'bundle/RELEASE.json').exists())
                self.assertNotIn('release',d.actions)
                self.assertFalse(m.read(x['output']/'FAILED.json')['remote_payload_may_have_started'])

    def test_guard_process_failure_is_not_a_PASS_or_retry(self):
        with tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
            x=self.context(tmp);d=m.Driver(x)
            with patch.object(d,'subprocess',return_value=125) as child,self.assertRaises(m.DriverError):d.execute()
            self.assertEqual(child.call_count,1);self.assertFalse((x['output']/'bundle/RELEASE.json').exists())

    def test_nonpassing_independent_record_cannot_create_RELEASE(self):
        with tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
            x=self.context(tmp);d=self.driver(x,bad_peer=True)
            with self.assertRaises(m.DriverError):d.execute()
            self.assertFalse((x['output']/'bundle/RELEASE.json').exists());self.assertNotIn('release',d.actions)

    def test_late_peer_completion_never_extends_the_compute_window(self):
        with tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
            x=self.context(tmp);d=self.driver(x,late=True)
            with self.assertRaises(m.DriverError):d.execute()
            self.assertFalse((x['output']/'bundle/RELEASE.json').exists());self.assertNotIn('release',d.actions)

    def test_duplicate_invocation_JOB_and_failed_role_are_rejected(self):
        for name in ['JOB.json','RECONCILED_JOB.json','ROLE_FAILED_SPENT.json','submit.intent.json','READY.json']:
            with self.subTest(name=name),tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
                x=self.context(tmp);m.write_new(x['root']/name,{})
                with self.assertRaises(m.DriverError):m.fresh_unsubmitted(x['root'],x['output'])
        with tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
            x=self.context(tmp);x['output'].mkdir()
            with self.assertRaises(m.DriverError):m.fresh_unsubmitted(x['root'],x['output'])

    def test_source_or_reviewer_bytes_drift_prevents_any_submission(self):
        with tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
            x=self.context(tmp);Path(x['settings']['source']['path']).write_text('changed bytes');d=self.driver(x)
            with self.assertRaises(m.DriverError):d.execute()
            self.assertEqual(d.actions,[]);self.assertFalse(x['output'].exists())

    def test_failed_release_guard_conservatively_records_possible_remote_start(self):
        with tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
            x=self.context(tmp);d=self.driver(x,failure='release')
            with self.assertRaises(m.DriverError):d.execute()
            self.assertTrue(m.read(x['output']/'FAILED.json')['remote_payload_may_have_started'])
            self.assertTrue((x['output']/'bundle/RELEASE.json').exists())

    def test_real_CLI_uses_direct_driver_file_without_caching_W184_core_package(self):
        value=subprocess.run([sys.executable,'-I','-B',str(Path(m.__file__).absolute()),'--help'],capture_output=True,text=True,check=False)
        self.assertEqual(value.returncode,0);self.assertIn('--stage-guard',value.stdout);self.assertIn('--packet-review',value.stdout)

    def test_readonly_child_identity_records_birth_boot_and_UID_without_signaling(self):
        row=m.process_identity(os.getpid());self.assertEqual(row['pid'],os.getpid());self.assertEqual(row['uid'],os.getuid())
        self.assertGreater(row['start_ticks'],0);self.assertEqual(len(row['boot_id']),36)


if __name__=='__main__':unittest.main()
