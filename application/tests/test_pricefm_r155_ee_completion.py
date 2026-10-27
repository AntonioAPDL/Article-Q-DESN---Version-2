"""Metadata and disposable-kernel tests; never load a fitted model or campaign helper."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
HERE=Path(__file__).resolve().parents[1]/'scripts/pricefm'
sys.path.insert(0,str(HERE));sys.dont_write_bytecode=True
import pricefm_r155_completion_contract as c
import pricefm_r155_completion_inventory as inv
for name in c.THREAD_ENV:os.environ[name]='1'


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


base=module('r155_inherited_test_contract',Path(__file__).with_name('test_pricefm_r154_predictions.py'))
base.c=c
runner=module('r155_runner_test',HERE/'524_run_pricefm_stage_r155_ee_completion.py')
conditional=module('r155_conditional_test',HERE/'525_run_pricefm_stage_r155_ee_conditional.py')


class TestCompletionAuthority(base.TestAuthority):
    def setUp(self):
        super().setUp()
        self.prep.update(remaining_component_names=['missing2','missing3'],previous_paid_scope={'paid':10961.212634},
            global_contract=self.a['global_contract'],original_global_lock_identity={'device':2304,'inode':59124844},
            LV_completed_gate={'synthetic_gate':True})
        self.pp.write_text(json.dumps(self.prep))
        self.evidence.write_text(json.dumps(dict(status='PASS',LV_complete=True,
            exact_lifetimes_gone=True,same_global_flock_free=True)))
        for key in ('peer_census','pricing_evidence','process_classifier_proof','source_review','admin_rules'):
            self.a[key]=c.pin(self.evidence)
        self.a.update(schema='r155_ee_completion_authority_v1',max_new_tasks=2,
            output_dir=str(self.root/'pricefm_stage_r155_ee_completion_fresh'),preparation=c.pin(self.pp),
            previous_paid_scope=self.prep['previous_paid_scope'],requires_completed_LV_drain=True,
            LV_completed_drain_proof=c.pin(self.evidence),original_global_lock_identity={'device':2304,'inode':59124844})

    def validate(self,a=None):
        with patch.object(c,'validate_LV_completion'):
            return c.validate_authority(a or self.a,self.prep,self.pp,self.identity,1100,'muscat')

    def test_rejects_task_expansion_old_charge_credit_lock_replacement_and_no_LV_gate(self):
        for key,value in (('max_new_tasks',3),('previous_paid_scope',{}),
                ('original_global_lock_identity',{'device':2304,'inode':99}),('requires_completed_LV_drain',False)):
            a=dict(self.a);a[key]=value
            with self.subTest(key=key),self.assertRaises(RuntimeError):self.validate(a)


class TestPeers(base.TestPeerAndLifetime):
    # Replace the inherited old privacy assertion with the specifically
    # authorized contemporaneous observable-context receipt contract.
    test_foreign_argv_not_retained_in_conflict=None
    def test_observable_argv_cwd_and_all_thread_masks_are_retained(self):
        row=self.row(executable='/python',cwd='/work',threads=[{'tid':123,'cpus':[62]}])
        conflict=c.peer_conflicts(30,{'allowed_intersecting_processes':[]},set(),[row])[0]
        for key in ('argv','executable','cwd','threads','pid','start_ticks','boot_id'):
            self.assertEqual(conflict[key],row[key])
        self.assertEqual(conflict['unavailable_fields'],[])
        self.assertIn('unreviewed_numerical',conflict['classifier_reason'])

    def test_peer_receipt_precedes_failure_and_missing_fields_are_explicit(self):
        with tempfile.TemporaryDirectory() as d:
            lease=c.Lease.__new__(c.Lease);lease.out=Path(d);lease.a={'physical_sibling_cpus':[30,62]}
            conflict=c.peer_conflicts(30,{'allowed_intersecting_processes':[]},set(),[self.row()])[0]
            with self.assertRaises(RuntimeError):lease.reject_peers([conflict],'test')
            records=list((Path(d)/'peer_rejections').glob('*.json'))
            self.assertEqual(len(records),1)
            record=c.read(records[0]);self.assertIn('cwd',record['conflicts'][0]['unavailable_fields'])
            self.assertFalse(record['exemptions_added'])

    def test_unreadable_observation_is_persisted_before_raise(self):
        with tempfile.TemporaryDirectory() as d:
            lease=c.Lease.__new__(c.Lease);lease.out=Path(d);lease.a={'physical_sibling_cpus':[30,62]}
            with patch.object(c,'all_processes',side_effect=c.PeerObservationError(456,'PermissionError')):
                with self.assertRaises(c.PeerObservationError):lease.scan_peers('test',{1})
            record=c.read(next((Path(d)/'peer_rejections').glob('*.json')))
            self.assertEqual(record['conflicts'][0]['pid'],456)
            self.assertIn('argv',record['conflicts'][0]['unavailable_fields'])


class TestHeldChildGuardian(base.TestDisposableGuardianPrivate):
    def script(self,root,mode):
        return super().script(root,mode).replace('import pricefm_r154_prediction_contract as c',
            'import pricefm_r155_completion_contract as c')


class TestInventoryBoundaries(unittest.TestCase):
    def task(self):
        return dict(name='example',scientific_identity_sha256='id',mode='S',forecast_seed=1,
            parent_seal_sha256='parent',scaler_sha256='scale',bank={'path':'bank','sha256':'b'},
            daily_origin_positions=list(range(12)),clock_offsets_steps=[0,24],
            origin_timestamps={'0':list(map(str,range(12))),'24':list(map(str,range(12)))})

    def test_exact_chunk_batch_clock_and_stable_rng_identity(self):
        descriptors=inv.chunks(self.task())
        self.assertEqual([d['name'] for d in descriptors],['clock00_part000','clock00_part001','clock24_part000','clock24_part001'])
        self.assertEqual(descriptors[-1]['stable_rng_origin_keys'],[p*96+24 for p in range(8,12)])
        self.assertEqual(inv.MISSING,['EE_r134_984fd326bd5fd13e_s2_S_seed0','EE_r134_984fd326bd5fd13e_s3_S_seed0'])

    def test_R150_context_cannot_be_relabelled_as_R154_execution(self):
        task=self.task();original={'source':{'head':'original'}};science=inv.science(task,original)
        with tempfile.TemporaryDirectory() as d:
            folder=Path(d);payload=folder/'result.json';payload.write_text('{}')
            seal={'certified':True,'artifacts':{'result.json':c.digest(payload)},'context':science}
            (folder/'completed_evidence.json').write_text(json.dumps(seal))
            self.assertEqual(inv.packet_row(folder,task,science)['kind'],'R150_component')
            with self.assertRaises(RuntimeError):inv.packet_row(folder,task,science,{'source':'new'})
            seal.pop('context');seal.update(schema='r154_prediction_packet_v1',scientific_context=science,execution={'source':'oldR154'})
            (folder/'completed_evidence.json').write_text(json.dumps(seal))
            self.assertEqual(inv.packet_row(folder,task,science,{'source':'oldR154'})['kind'],'R154_component')
            with self.assertRaises(RuntimeError):inv.packet_row(folder,task,science,{'source':'forged'})
            with self.assertRaises(RuntimeError):inv.packet_row(folder,task,dict(science,seed=2),{'source':'oldR154'})

    def test_metric_reconstruction_rejects_drift(self):
        runner.compare_metrics({'AQL':1.0},{'AQL':1.0},'same')
        with self.assertRaises(RuntimeError):runner.compare_metrics({'AQL':1.0},{'AQL':1.01},'drift')

    def test_guardian_source_callgraph_is_the_frozen_held_child_implementation(self):
        import ast
        old=ast.parse((HERE/'pricefm_r154_prediction_contract.py').read_text())
        new=ast.parse((HERE/'pricefm_r155_completion_contract.py').read_text())
        def functions(tree):return {n.name:ast.dump(n,include_attributes=False) for n in ast.walk(tree) if isinstance(n,ast.FunctionDef)}
        a,b=functions(old),functions(new)
        for name in ('_start_guardian','signal_unreaped_direct_child','funded_payload_CPU_limit','cpu_seconds','process_identity'):
            self.assertEqual(a[name],b[name],name)

    def test_imports_do_not_load_numerics_before_authority(self):
        import subprocess
        script="import sys;sys.path.insert(0,sys.argv[1]);import pricefm_r155_completion_contract,pricefm_r155_completion_inventory;assert 'numpy' not in sys.modules"
        subprocess.run([sys.executable,'-B','-c',script,str(HERE)],check=True)


class TestLVCompletionAndConditional(unittest.TestCase):
    def fixture(self,root):
        source={'branch':'frozenLV','head':'cd113800'}
        authority={'source':source,'scope_id':'LVscope','output_dir':str(root)}
        original=root/'original_authority.json';c.immutable(original,authority)
        c.immutable(root/'authority.json',authority)
        execution={'source':source,'scope_id':'LVscope','authority':c.pin(root/'authority.json')}
        c.immutable(root/'assessment.json',{'status':'COMPLETE_TRAINING_DIAGNOSTIC_EXPOSED_NOT_PROMOTED','calls':12,'execution':execution})
        c.immutable(root/'assessment_seal.json',{'assessment':c.pin(root/'assessment.json')})
        c.immutable(root/'exit_receipt.json',{'status':'COMPLETE_DIAGNOSTIC'})
        dead={'pid':987654,'start_ticks':1,'boot_id':'synthetic'}
        c.immutable(root/'claim.json',{'authority':c.pin(original),'process':dead})
        c.immutable(root/'supervisor_exit_receipt.json',{'child_exit_code':0,'parent':dead,'payload':dead})
        return {'authority':c.pin(original),'output_dir':str(root)},dead

    def test_actual_complete_packet_and_negative_status_source_seal_lifetime_paths(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);gate,dead=self.fixture(root)
            with patch.object(c,'process_identity',return_value=None):c.validate_LV_completion(gate)
            for filename,key,value in [('assessment.json','calls',11),('assessment.json','status','INCOMPLETE'),
                    ('exit_receipt.json','status','INCOMPLETE'),('supervisor_exit_receipt.json','child_exit_code',1)]:
                path=root/filename;before=path.read_text();record=json.loads(before);record[key]=value;path.write_text(json.dumps(record))
                with self.subTest(filename=filename,key=key),self.assertRaises(RuntimeError):c.validate_LV_completion(gate)
                path.write_text(before)
            assessment=root/'assessment.json';before=assessment.read_text();record=json.loads(before)
            record['execution']['source']={'head':'forged'};assessment.write_text(json.dumps(record))
            c.read(root/'assessment_seal.json')
            (root/'assessment_seal.json').write_text(json.dumps({'assessment':c.pin(assessment)}))
            with self.assertRaises(RuntimeError):c.validate_LV_completion(gate)
            assessment.write_text(before)
            (root/'assessment_seal.json').write_text(json.dumps({'assessment':c.pin(assessment)}))
            with patch.object(c,'process_identity',return_value=dead),self.assertRaises(RuntimeError):c.validate_LV_completion(gate)

    def test_conditional_derivation_changes_only_future_proof_pin(self):
        template={'LV_completed_drain_proof':None,'source':'actual','start_epoch':10,'expires_epoch':20,'max_new_tasks':2,'full_prefix_CPU':5500}
        proof={'path':'future','sha256':'a'*64}
        value=conditional.derive_child(template,proof)
        self.assertEqual(value,dict(template,LV_completed_drain_proof=proof))
        self.assertIsNone(template['LV_completed_drain_proof'])
        with self.assertRaises(RuntimeError):conditional.derive_child(value,proof)

    def test_entire_control_budget_and_fixed_expiry_must_fit(self):
        template={'full_prefix_CPU':5500,'replacement_CPU':1200,'admin_drain_CPU':1200,
            'min_delivered_share':.5,'drain_seconds':900,'maximum_atomic_wall_seconds':120,
            'expires_epoch':20000,'max_execution_wall_seconds':18000}
        self.assertEqual(conditional.whole_calendar(template,1000),16820)
        with self.assertRaises(RuntimeError):conditional.whole_calendar(template,4000)
        with self.assertRaises(RuntimeError):conditional.whole_calendar(dict(template,max_execution_wall_seconds=14400),1000)

    def test_conditional_live_failed_and_wrong_unit_LV_cannot_dispatch(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);dead={'pid':987654,'start_ticks':1,'boot_id':'fixture'}
            authority={'path':'lvadminauthority','sha256':'a'*64};original={'path':'originalLV','sha256':'b'*64}
            admin={'output_dir':str(root),'source':{'head':'LVadmin'},'unit':'lvunit'}
            prep={'LV_completed_gate':{'authority':original}}
            claim={'authority':authority,'source':admin['source'],'original_LV_authority':original,
                'process':dead,'unit':{'InvocationID':'invocation'}}
            c.immutable(root/'claim.json',claim)
            with patch.object(c,'process_identity',return_value=dead):
                self.assertIsNone(conditional.LV_ready(admin,prep,authority))
            with patch.object(c,'process_identity',return_value=None),self.assertRaises(RuntimeError):
                conditional.LV_ready(admin,prep,authority)
            receipt={'status':'COMPLETE_LV_TRAINING_DIAGNOSTIC_NOT_PROMOTED','source':admin['source'],
                'original_LV_authority':original,'LV':{'physical_drain':True}}
            c.immutable(root/'exit_receipt.json',receipt)
            with patch.object(c,'process_identity',return_value=dead),patch.object(conditional,'systemd') as unit:
                self.assertIsNone(conditional.LV_ready(admin,prep,authority));unit.assert_not_called()
            unit={'InvocationID':'invocation','Id':'lvunit','MainPID':'0','ActiveState':'inactive',
                'Restart':'no','NRestarts':'0','KillMode':'process','Result':'success','ExecMainStatus':'0'}
            with patch.object(c,'process_identity',return_value=None),patch.object(conditional,'systemd',return_value=unit),patch.object(c,'validate_LV_completion') as validate:
                self.assertIsNotNone(conditional.LV_ready(admin,prep,authority));validate.assert_called_once()
            for change in ({'InvocationID':'restarted'},{'MainPID':'1'},{'Result':'exit-code'},{'ExecMainStatus':'1'}):
                with patch.object(c,'process_identity',return_value=None),patch.object(conditional,'systemd',return_value=dict(unit,**change)),self.assertRaises(RuntimeError):
                    conditional.LV_ready(admin,prep,authority)
            (root/'exit_receipt.json').write_text(json.dumps(dict(receipt,status='STOPPED_NO_RETRY')))
            with self.assertRaises(RuntimeError):conditional.LV_ready(admin,prep,authority)

    def test_private_controller_soft_cap_preserves_child_hard_ceiling_and_held_cleanup(self):
        import subprocess
        script=r'''
import sys,os,subprocess,resource,time,signal
sys.path.insert(0,sys.argv[1])
import importlib.util
spec=importlib.util.spec_from_file_location('conditional',sys.argv[1]+'/525_run_pricefm_stage_r155_ee_conditional.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
cpu0=m.c.cpu_seconds()
limit=m.apply_limits({'administrative_live_CPU_cap':5},{'total_CPU_cap':10,'prior_CPU_charged_seconds':0},cpu0)
assert resource.getrlimit(resource.RLIMIT_CPU)[0]<=5 and resource.getrlimit(resource.RLIMIT_CPU)[1]>=10
parent=m.c.process_identity(os.getpid())
p=subprocess.Popen([sys.executable,'-B','-c','import resource,time;assert resource.getrlimit(resource.RLIMIT_CPU)==(10,10);time.sleep(30)'],preexec_fn=lambda:m.arm(parent,limit))
identity=m.c.process_identity(p.pid)
time.sleep(.1)
m.stop_held(p,identity)
_,status,usage=os.wait4(p.pid,0);p.returncode=os.waitstatus_to_exitcode(status)
assert p.returncode==-signal.SIGKILL
assert usage.ru_utime+usage.ru_stime>=0
'''
        subprocess.run([sys.executable,'-B','-c',script,str(HERE)],check=True,timeout=5)


if __name__=='__main__':unittest.main()
