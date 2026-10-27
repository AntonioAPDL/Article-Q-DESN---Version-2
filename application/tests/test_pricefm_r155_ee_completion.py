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
    def test_foreign_argv_not_retained_in_conflict(self):
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


if __name__=='__main__':unittest.main()
