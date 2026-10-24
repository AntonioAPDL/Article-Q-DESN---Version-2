"""Fault boundaries for independently attested resource/scientific sources."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ENTRY=Path(__file__).resolve().parents[1]/'scripts/pricefm/508_bootstrap_pricefm_stage_r152_payload.py'
spec=importlib.util.spec_from_file_location('r152_bootstrap_test',ENTRY)
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class BootstrapContracts(unittest.TestCase):
    def fixture(self):
        spec=dict(schema_version=1,stage='R150',task='EE_task',cpu=24,expires_epoch=200,
            lease_id='ee-c1-id',unit='pricefm-r150-r152-worker-abc.service',
            controller_unit='pricefm-r150-r152-controller-abc.service',
            resource_source_head='new-resource',scientific_source_head='old-science',
            resource_entry_path=str(ENTRY.with_name('505_run_pricefm_stage_r152_shared_pool.py')),
            resource_entry_sha256='a'*64,bootstrap_path=str(ENTRY),bootstrap_sha256='b'*64,
            scientific_source_root=str(module.ROOT),scientific_source_sha256={str(ENTRY):'c'*64},
            master_path='/tmp/master',master_sha256='d'*64,master_scope_id='scope',
            admission_path='/tmp/admission',admission_sha256='e'*64,
            global_slot_path='/tmp/slot',global_slot_sha256='f'*64,policy_receipt_path='/tmp/receipt',
            target_argv=[module.PYTHON,'-B',str(ENTRY),'probe-payload'])
        master=dict(scope_id='scope',expires_epoch=300)
        admission=dict(lease_id='ee-c1-id',expires_epoch=200)
        slot={key:spec[key] for key in ('cpu','task','unit','lease_id')}
        slot['master_scope_id']='scope'
        receipt=dict(schema_version=1,stage='R150',task='EE_task',cpu=24,expected_affinity=[24],
            expected_scheduler=5,numerical_threads=1,io_class=3,unit=spec['unit'],
            controller_unit=spec['controller_unit'],source_head='old-science',
            resource_source_head='new-resource',lease_id=spec['lease_id'],lease_expires_epoch=200,
            probe_id='probe',worker_invocation_id='inv',worker_cgroup='/owned',
            actual_probe=dict(properties=dict(Id=spec['unit'],InvocationID='inv',ControlGroup='/owned',
                IOSchedulingClass='3'),process=dict(affinity=[24],scheduler=5)))
        return spec,master,admission,slot,receipt

    def test_distinct_scientific_and_resource_heads_are_valid(self):
        s,m,a,c,r=self.fixture()
        module.validate_spec(s,now=100,verify_files=False)
        self.assertTrue(module.validate_contracts(s,m,a,c,now=100))
        self.assertTrue(module.validate_receipt(s,r,now=100))

    def test_resource_head_cannot_replace_scientific_head(self):
        s,m,a,c,r=self.fixture();r['source_head']=s['resource_source_head']
        with self.assertRaisesRegex(RuntimeError,'source_head'):
            module.validate_receipt(s,r,now=100)

    def test_each_identity_and_policy_field_is_binding(self):
        for key,value in [('stage','R152'),('cpu',25),('task','other'),('lease_id','old'),
            ('controller_unit','foreign'),('expected_affinity',[24,56]),('numerical_threads',2),
            ('resource_source_head','foreign'),('lease_expires_epoch',201)]:
            with self.subTest(key=key):
                s,m,a,c,r=self.fixture();r[key]=value
                with self.assertRaises(RuntimeError):module.validate_receipt(s,r,now=100)

    def test_slot_and_master_cannot_be_reused_for_other_task(self):
        for key,value in [('cpu',25),('task','other'),('unit','other'),('lease_id','other'),('master_scope_id','other')]:
            with self.subTest(key=key):
                s,m,a,c,r=self.fixture();c[key]=value
                with self.assertRaises(RuntimeError):module.validate_contracts(s,m,a,c,now=100)

    def test_nonfinite_expired_or_excess_expiry_rejected(self):
        for expiry in (float('nan'),float('inf'),True,99):
            s,m,a,c,r=self.fixture();s['expires_epoch']=expiry
            with self.assertRaises(RuntimeError):module.validate_spec(s,now=100,verify_files=False)
        s,m,a,c,r=self.fixture();m['expires_epoch']=199
        with self.assertRaises(RuntimeError):module.validate_contracts(s,m,a,c,now=100)
        s,m,a,c,r=self.fixture();a['expires_epoch']=199
        with self.assertRaises(RuntimeError):module.validate_contracts(s,m,a,c,now=100)

    def test_no_shell_or_foreign_executable(self):
        for argv in (['bash','-c','echo unsafe'],[module.PYTHON,'-B','/tmp/unowned.py']):
            s,m,a,c,r=self.fixture();s['target_argv']=argv
            with self.assertRaises(RuntimeError):module.validate_spec(s,now=100,verify_files=False)

    def test_first_exec_never_moves_work_to_other_cpus(self):
        for cpu in (14,30,56,True):
            with self.assertRaises(RuntimeError):module.first_exec_policy(cpu)

    def test_admin_failure_keeps_exact_exit_charge_and_namespace(self):
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory);script=folder/'admin.py'
            script.write_text('raise RuntimeError("deliberate admin failure")\n')
            s,m,a,c,r=self.fixture()
            s.update(accounting_path=str(folder/'accounting'),target_argv=[module.PYTHON,'-B',str(script)])
            path=folder/'spec.json';path.write_text(json.dumps(s))
            with self.assertRaisesRegex(RuntimeError,'deliberate admin failure'):
                module.run_instrumented_admin(s,path)
            result=json.loads((folder/'accounting/observed.json').read_text())
            self.assertFalse(result['completed'])
            self.assertGreaterEqual(result['observed_total_CPU_seconds'],result['observed_process_CPU_seconds'])
            self.assertEqual(result['post_observation_exit_allowance_CPU_seconds'],5)
            seal=json.loads((folder/'accounting/observed.seal.json').read_text())
            self.assertEqual(seal['sha256'],module.digest(folder/'accounting/observed.json'))

    def test_admin_accounting_path_cannot_escape_worker_directory(self):
        s,m,a,c,r=self.fixture();s.update(instrumented_admin=True,accounting_path='/unowned/admin')
        with self.assertRaisesRegex(RuntimeError,'accounting escaped'):
            module.validate_spec(s,now=100,verify_files=False)

if __name__=='__main__':unittest.main()
