"""Private metadata/kernel tests. No fitted parent, model import or forecast."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parents[1]/'scripts/pricefm'
sys.path.insert(0,str(HERE));sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location('r155_lv_handoff',HERE/'526_run_pricefm_stage_r155_lv_handoff.py')
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)


class TestPermitAndDrain(unittest.TestCase):
    def test_same_existing_lock_inode_and_busy_lock(self):
        import fcntl
        with tempfile.TemporaryDirectory() as d:
            glob={'lock_dir':d};path=Path(d)/'permit.lock';path.touch()
            self.assertEqual(h.permit_free(glob,'permit')['inode'],path.stat().st_ino)
            with path.open('r+') as stream:
                fcntl.flock(stream,fcntl.LOCK_EX|fcntl.LOCK_NB)
                self.assertIsNone(h.permit_free(glob,'permit'))
            self.assertTrue(h.permit_free(glob,'permit')['free'])
            expected=dict(path=str(path),device=path.stat().st_dev,inode=path.stat().st_ino)
            self.assertTrue(h.permit_free(glob,'permit',expected)['free'])
            # Hold the old inode open so the filesystem cannot immediately
            # recycle it for the replacement file in this negative proof.
            with path.open('r+'):
                path.unlink();path.touch()
                with self.assertRaisesRegex(RuntimeError,'device/inode replaced'):h.permit_free(glob,'permit',expected)
            with self.assertRaises(FileNotFoundError):h.permit_free(glob,'new')

    def fixtures(self,d):
        root=Path(d);stage={'study':'LV','authority':{'path':'lv','sha256':'a'*64},'preparation':{'path':'prep','sha256':'b'*64}}
        identity={'branch':'old','head':'c'*40};life={'pid':1,'start_ticks':2,'boot_id':'b'}
        def save(name,value):
            p=root/name;p.write_text(json.dumps(value));return h.pin(p)
        queue=save('grant',{'source':identity,'stages':[{'study':'EE'},stage]})
        old={'queue_authority':queue,'queue_claim':save('claim',{'authority':queue,'source':identity,'stages':[{'study':'EE'},stage],'process':life}),
            'queue_exit':save('exit',{'status':'STOPPED_NO_RETRY','claim_consumed':True,'source':identity}),
            'EE_wait':save('wait',{'exit_code':1}),
            'EE_supervisor_exit':save('receipt',{'child_exit_code':1,'all_inclusive_charged_CPU_seconds':42,'parent':life,'payload':life}),
            'retained_EE_CPU_charge':42,'unit':'old.service','invocation_id':'exact'}
        unit=dict(Id='old.service',InvocationID='exact',MainPID='0',ActiveState='failed',Restart='no',NRestarts='0',KillMode='process')
        return {'stage':stage,'predecessor':old},unit,life

    def test_drained_old_stopped_queue_keeps_charge_and_stage(self):
        with tempfile.TemporaryDirectory() as d:
            a,unit,life=self.fixtures(d)
            with patch.object(h,'systemd',return_value=unit),patch.object(h,'process_identity',return_value=None):
                result=h.predecessor_drain(a)
                self.assertEqual(result['retained_EE_CPU_charge'],42)
                self.assertFalse(result['unused_credit_reusable'])
                bad=copy.deepcopy(a);bad['stage']['authority']['sha256']='d'*64
                with self.assertRaisesRegex(RuntimeError,'originally queued'):h.predecessor_drain(bad)

    def test_live_old_lifetime_or_wrong_invocation_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            a,unit,life=self.fixtures(d)
            with patch.object(h,'systemd',return_value=unit),patch.object(h,'process_identity',return_value=life):
                with self.assertRaisesRegex(RuntimeError,'still lives'):h.predecessor_drain(a)
            for change in ({'MainPID':'55'},{'InvocationID':'replaced'},{'NRestarts':'1'},{'KillMode':'control-group'}):
                with patch.object(h,'systemd',return_value=dict(unit,**change)),patch.object(h,'process_identity',return_value=None):
                    with self.assertRaisesRegex(RuntimeError,'exact queue unit'):h.predecessor_drain(a)


class TestLifecycle(unittest.TestCase):
    def test_truthful_child_argv_uses_original_source_and_grant(self):
        a={'python':'PINNED','scientific_entry':'/original/521.py','stage':{'preparation':{'path':'prep'},'authority':{'path':'originalgrant','sha256':'a'*64}}}
        self.assertEqual(h.scientific_argv(a),['PINNED','-B','/original/521.py','--preparation','prep','--authority','originalgrant','--authority-sha256','a'*64])

    def test_low_admin_soft_preserves_separately_funded_child_hard(self):
        usage=type('Usage',(),dict(ru_utime=.2,ru_stime=.3))()
        with patch.object(h.resource,'getrusage',return_value=usage),patch.object(h.resource,'getrlimit',return_value=(-1,-1)),patch.object(h.resource,'setrlimit') as limits,patch.object(h.signal,'signal'):
            result=h.apply_limits(120,{'total_CPU_cap':7000,'prior_CPU_charged_seconds':100})
            self.assertEqual(result['administrative_soft_CPU_limit'],120)
            self.assertEqual(result['inherited_child_hard_CPU_ceiling'],6900)
            self.assertIn((resource.RLIMIT_CPU,(120,6900)),[v.args for v in limits.call_args_list])

    def test_child_unfunded_hard_limit_rejected(self):
        with patch.object(h.resource,'getrlimit',return_value=(120,120)):
            with self.assertRaisesRegex(RuntimeError,'hard ceiling'):h.apply_limits(120,{'total_CPU_cap':7000,'prior_CPU_charged_seconds':100})

    def test_held_unreaped_private_child_only(self):
        parent=os.getpid()
        child=subprocess.Popen([sys.executable,'-B','-c','import time;time.sleep(20)'],preexec_fn=lambda:h.arm(parent,10))
        identity=h.process_identity(child.pid)
        try:
            self.assertIsNone(h.held_state(child))
            bad=dict(identity,ppid=identity['ppid']+1)
            with self.assertRaisesRegex(RuntimeError,'held direct child'):h.stop_held(child,bad)
            self.assertEqual(h.stop_held(child,identity),-signal.SIGKILL)
            with self.assertRaises(ChildProcessError):h.held_state(child)
        finally:
            if child.poll() is None:child.kill();child.wait()

    def test_exited_child_remains_unreaped_until_sole_wait(self):
        child=subprocess.Popen([sys.executable,'-B','-c','pass'])
        for _ in range(100):
            if h.held_state(child) is not None:break
            time.sleep(.01)
        self.assertIsNotNone(h.held_state(child))
        self.assertEqual(h.process_identity(child.pid)['state'],'Z')
        self.assertEqual(child.wait(),0)

    def test_child_actual_pdeath_and_hard_limits(self):
        parent=os.getpid()
        code='import ctypes,json,resource,os;v=ctypes.c_int();ctypes.CDLL(None).prctl(2,ctypes.byref(v),0,0,0);print(json.dumps(dict(pdeath=v.value,cpu=resource.getrlimit(resource.RLIMIT_CPU),parent=os.getppid(),mask=sorted(os.sched_getaffinity(0)))))'
        worker=subprocess.Popen([sys.executable,'-B','-c',code],stdout=subprocess.PIPE,text=True,preexec_fn=lambda:h.arm(parent,6900))
        value=json.loads(worker.communicate(timeout=10)[0])
        self.assertEqual(worker.returncode,0);self.assertEqual(value['pdeath'],signal.SIGKILL)
        self.assertEqual(value['cpu'],[6900,6900]);self.assertEqual(value['parent'],parent);self.assertEqual(value['mask'],[31])

    def test_actual_parent_death_kills_only_private_descendant(self):
        code=('import importlib.util,json,os,subprocess,sys,time;'
              'sys.path.insert(0,'+repr(str(HERE))+');'
              's=importlib.util.spec_from_file_location("private_h",'+repr(str(HERE/'526_run_pricefm_stage_r155_lv_handoff.py'))+');'
              'h=importlib.util.module_from_spec(s);s.loader.exec_module(h);p=os.getpid();'
              'c=subprocess.Popen([sys.executable,"-B","-c","import time;time.sleep(30)"],preexec_fn=lambda:h.arm(p,5));'
              'print(json.dumps(h.process_identity(c.pid)),flush=True);time.sleep(30)')
        parent=subprocess.Popen([sys.executable,'-B','-c',code],stdout=subprocess.PIPE,text=True)
        identity=h.process_identity(parent.pid)
        try:
            grandchild=json.loads(parent.stdout.readline())
            self.assertEqual(grandchild['ppid'],parent.pid)
            self.assertEqual(h.stop_held(parent,identity),-signal.SIGKILL)
            for _ in range(200):
                current=h.process_identity(grandchild['pid'])
                if not h.same_lifetime(current,grandchild) or current['state']=='Z':break
                time.sleep(.01)
            current=h.process_identity(grandchild['pid'])
            self.assertTrue(not h.same_lifetime(current,grandchild) or current['state']=='Z')
        finally:
            if parent.poll() is None:parent.kill();parent.wait()
            parent.stdout.close()

    def test_preflight_failure_does_not_make_claim_or_dispatch(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'authority';path.write_text('{}')
            with patch.object(h,'own_source',return_value={}),patch.object(h,'preflight',side_effect=RuntimeError('pins differ')),patch.object(h.subprocess,'Popen') as popen:
                with self.assertRaisesRegex(RuntimeError,'pins differ'):h.execute(path,h.digest(path))
                popen.assert_not_called()
            self.assertEqual(sorted(v.name for v in Path(d).iterdir()),['authority'])

    def test_peer_failure_retains_unknown_departed_PID_without_exemption(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'stderr';path.write_text('RuntimeError: new unreviewed numerical peer intersects allocation: [2487026]\n')
            with patch.object(h,'all_processes',return_value=[]),patch.object(h,'observe',return_value={'conflicts':[]}):
                result=h.failure_incident({},path)
            self.assertEqual(result['reported_peers'][0]['reported_PID'],2487026)
            self.assertIsNone(result['reported_peers'][0]['current_identity'])
            self.assertTrue(result['reported_peers'][0]['no_PID_based_exemption'])
            self.assertTrue(result['prior_reported_PID_lifetime_cannot_be_reconstructed'])


class TestAuthorityGates(unittest.TestCase):
    def fixture(self):
        a=json.loads((HERE.parents[1]/'config/pricefm_stage_r155_lv_handoff_authority_template.json').read_text())
        a.update(source={'branch':'work/pricefm-r155-lv-handoff-test','head':'1'*40},scope_id='new',
            unit='pricefm-r155-lv-handoff-new.service',output_dir=str(h.AUDIT/'runs/pricefm_stage_r155_lv_handoff_new'),
            start_epoch=1000,expires_epoch=22600,original_LV_start_epoch=10,original_LV_expires_epoch=50000,
            python=sys.executable,python_sha256='0'*64,
            source_sha256={str(h.ENTRY):'0'*64,str(h.ENTRY.with_name('pricefm_r154_prediction_contract.py')):'0'*64})
        grant=dict(study='LV',source=a['scientific_source'],global_contract=a['global_contract'],start_epoch=10,expires_epoch=50000,
            output_dir='/nonexistent/private_test_LV_output',full_prefix_CPU=6300,replacement_CPU=100,
            min_delivered_share=.5,drain_seconds=600,maximum_atomic_wall_seconds=1200)
        amendment=dict(schema='r155_loss_blind_order_amendment_v1',status='PROPOSED',transition='EE_STOPPED_TO_LV_FIRST',
            loss_blind=True,LV_scientifically_independent_of_EE=True,scientific_scope_changed=False,
            unchanged_LV_authority=a['stage']['authority'],predecessor_queue_authority=a['predecessor']['queue_authority'])
        def verify(value):
            if value==a['global_contract']:return dict(created_epoch=0,expires_epoch=50000,lock_dir=str(Path(a['permit_identity']['path']).parent))
            if value==a['order_amendment']:return amendment
            if value==a['stage']['authority']:return grant
            if value==a['stage']['preparation']:return dict(study='LV')
            if value==a['pricing_evidence']:return dict(prior_administrative_CPU_charged_seconds=20)
            raise AssertionError('unrecognised private pin')
        return a,amendment,grant,verify

    def checked(self,a,verify):
        with patch.object(h,'verify_pin',side_effect=verify),patch.object(h,'verify_hashes'),patch.object(h,'digest',return_value='0'*64),patch.object(h,'source_identity',return_value=a['scientific_source']),patch.object(h,'validate_authority'):
            return h.validate(a,{'branch':'work/pricefm-r155-lv-handoff-test','head':'1'*40},1000,'muscat',False)

    def test_proposed_loss_blind_unchanged_LV_contract(self):
        a,amendment,grant,verify=self.fixture();self.checked(a,verify)

    def test_reject_scope_clock_source_budget_and_order_changes(self):
        for key,value in [('source',{}),('max_CPU_seconds',121),('expires_epoch',50001),('original_LV_start_epoch',11),
                          ('max_wall_seconds',10000),('automatic_retry',True),('max_dispatches',2),('new_forecasts',1),
                          ('max_incident_observations',61),
                          ('prior_administrative_CPU_charged_seconds',21),('administrative_total_CPU_cap',139)]:
            a,amendment,grant,verify=self.fixture();a[key]=value
            with self.subTest(key=key),self.assertRaises(RuntimeError):self.checked(a,verify)
        for key,value in [('loss_blind',False),('LV_scientifically_independent_of_EE',False),('scientific_scope_changed',True),('transition','RETRY_EE')]:
            a,amendment,grant,verify=self.fixture();amendment[key]=value
            with self.subTest(amendment=key),self.assertRaises(RuntimeError):self.checked(a,verify)


if __name__=='__main__':unittest.main()
