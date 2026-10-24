"""Scope, source and pre-attestation faults in the finite release boundary."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ENTRY=Path(__file__).resolve().parents[1]/'scripts/pricefm/507_orchestrate_pricefm_stage_r152_parallel.py'
spec=importlib.util.spec_from_file_location('r152_orchestration_test',ENTRY)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class ReleaseBoundary(unittest.TestCase):
    def test_config_rejects_renewal_or_foreign_runtime(self):
        c=m.read_config()
        for key,value in [('automatic_renewal',True),('master_seconds',86400),
                ('LT_AT_repair_fits',1),('runtime','/tmp/pricefm_stage_r152_parallel_20261024'),
                ('FI_config','../foreign.json')]:
            with self.subTest(key=key),tempfile.TemporaryDirectory() as tmp:
                changed=dict(c,**{key:value});path=Path(tmp)/'config.json';path.write_text(json.dumps(changed))
                with self.assertRaises(RuntimeError):m.read_config(path)

    def test_precommit_is_not_a_started_loan(self):
        c=m.read_config()
        owner=dict(unit='owned.service',invocation_id='inv',process={'pid':1},
            startup_epoch=100.,precommit_expires_epoch=400.)
        result=m.pending_contract(c,{'source':{'head':'head'}},owner,'release','probe')
        self.assertEqual(result['precommit_expires_epoch'],400.)
        self.assertEqual(result['master_seconds'],43200)
        self.assertNotIn('start_epoch',result)
        self.assertNotIn('expires_epoch',result)
        self.assertEqual(result['orchestrator'],owner)

    def test_precommit_cannot_extend_the_parent_bound(self):
        c=m.read_config()
        for expiry in (401,float('inf'),99):
            with self.subTest(expiry=expiry):
                owner=dict(unit='owned.service',invocation_id='inv',process={'pid':1},
                    startup_epoch=100.,precommit_expires_epoch=expiry)
                with self.assertRaises(RuntimeError):m.pending_contract(c,{'source':{'head':'h'}},owner,'r','p')

    def test_immutable_records_cannot_be_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'attempt.json';m.immutable(path,{'old':'receipt'})
            with self.assertRaises(FileExistsError):m.immutable(path,{'new':'receipt'})
            self.assertEqual(m.read(path),{'old':'receipt'})

    def test_immutable_publication_exposes_only_complete_json(self):
        real_link=m.os.link
        def observe(temporary,destination):
            self.assertFalse(Path(destination).exists())
            self.assertEqual(m.read(temporary),{'complete':['record',17]})
            real_link(temporary,destination)
            self.assertEqual(m.read(destination),{'complete':['record',17]})
        with tempfile.TemporaryDirectory() as tmp,patch.object(m.os,'link',side_effect=observe):
            path=Path(tmp)/'master.json';m.immutable(path,{'complete':['record',17]})
            self.assertEqual(list(Path(tmp).iterdir()),[path])

    def test_start_checks_intent_before_capturing_actual_as_expected(self):
        calls=[]
        class Legacy:
            def verify_owned(self,saved,current):
                calls.append('attested' in saved)
                if not calls[-1]:raise RuntimeError('wrong argv caught before attestation')
            def stop_and_drain(self,system,saved,timeout):
                calls.append('cleanup');return {'cleanup_verified':False}
        class System:
            def start(self,*args,**kwargs):pass
            def unit(self,name):return {'MainPID':'1','InvocationID':'i','ControlGroup':'/owned'}
        class Pool:
            def System(self):return System()
            def legacy(self):return Legacy()
        with tempfile.TemporaryDirectory() as tmp,patch.object(m,'git',return_value='new-head'):
            unit='pricefm-r150-r152-master-test.service'
            argv=[m.read_config()['python_runtime'],'-B',str(ENTRY),'coordinate','--unit',unit]
            with self.assertRaisesRegex(RuntimeError,'wrong argv'):
                m.start_control(Pool(),tmp,argv,m.read_config())
            self.assertEqual(calls,[False,'cleanup'])
            self.assertFalse((Path(tmp)/'attestation.json').exists())
            self.assertIn('cleanup',m.read(Path(tmp)/'startup_failure.json'))

    def test_status_does_not_create_or_start_runtime(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'not-created'
            self.assertEqual(m.status(path),{})
            self.assertFalse(path.exists())

    def test_parent_context_forwards_complete_capsule_to_pool(self):
        with tempfile.TemporaryDirectory() as tmp:
            shared=Path(tmp);dev=shared/'development';dev.mkdir()
            props=dict(Id='pricefm-r150-r152-master-test.service',MainPID='123',InvocationID='inv',ControlGroup='/owned')
            capsule=dict(unit=props['Id'],argv=['python','script'],description='owned',runtime_seconds=43560,attested=props)
            path=shared/'attestation.json';path.write_text(json.dumps(capsule))
            context=m.orchestrator_context(capsule,props,{'pid':123},'head',100,400,path)
            m.atomic(shared/'orchestrator.json',context)
            pool=m.module('r152_orchestration_pool_contract_test',ENTRY.with_name('505_run_pricefm_stage_r152_shared_pool.py'))
            self.assertIn(capsule,pool.control_capsules(dev))
            with self.assertRaises(RuntimeError):m.orchestrator_context(capsule,props,{'pid':124},'head',100,400,path)

if __name__=='__main__':unittest.main()
