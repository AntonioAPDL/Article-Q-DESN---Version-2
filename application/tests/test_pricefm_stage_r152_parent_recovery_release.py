"""Original-clock recovery faults; temporary files and fake managers only."""
import copy
import importlib.util
import math
import os
from pathlib import Path
import tempfile
import time
import types
import unittest
from unittest.mock import patch

ENTRY=Path(__file__).resolve().parents[1]/'scripts/pricefm/510_release_pricefm_stage_r152_parent_recovery.py'
spec=importlib.util.spec_from_file_location('r152_recovery_release_test',ENTRY)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class ReleaseRecovery(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.home=Path(self.temp.name);self.shared=self.home/'canonical';self.shared.mkdir()
        broker=self.home/'509_test_broker.py';broker.write_text('pass\n')
        self.patchers=[patch.object(m,'SHARED',self.shared),patch.object(m,'MASTER',self.shared/'master.json'),patch.object(m,'BROKER',broker)]
        for patcher in self.patchers:patcher.start();self.addCleanup(patcher.stop)
        self.props=dict(ActiveState='failed',MainPID='0',ControlGroup='',CPUUsageNSec='[not set]')
        self.groups={};self.proc=None
        self.system=types.SimpleNamespace(unit=lambda unit:dict(self.props),members=lambda group:self.groups.get(group,[]))
        self.legacy=types.SimpleNamespace(verify_owned=lambda saved,props:'owned',process=lambda pid:self.proc,
            parse_duration=lambda value:float(value.rstrip('s')),idle_command=lambda argv:['/usr/bin/chrt','--idle','0']+list(argv))
        self.pool=types.SimpleNamespace(validate_master=lambda *args,**kwargs:None,verify_source=lambda source:None,
            boot=lambda:'boot',legacy=lambda:self.legacy,hardening=lambda:types.SimpleNamespace(same_process_identity=lambda a,b:a==b),
            baseline=lambda:types.SimpleNamespace(baseline_ownership=lambda *args:dict(healthy=True)),System=lambda:self.system)
        api_patch=patch.object(m,'api',return_value=self.pool);api_patch.start();self.addCleanup(api_patch.stop)
        verify_patch=patch.object(m,'verify_source',return_value=None);verify_patch.start();self.addCleanup(verify_patch.stop)
        adapter_patch=patch.object(m,'adapter',return_value=types.SimpleNamespace(verify_baseline=lambda *args:dict(healthy=True)))
        adapter_patch.start();self.addCleanup(adapter_patch.stop)
        now=time.time();self.now=now
        self.source=dict(root=str(m.ROOT),head='recovery-head',branch=m.BRANCH,runtime_sha256={})
        oldsource=dict(root=str(m.OLD_ROOT),head='old-head',branch='old-branch',runtime_sha256={})
        self.saved=dict(unit='pricefm-r150-r152-master-failed.service',source_head='old-head',created_epoch=now-20,
            process=dict(pid=11,start_ticks=100,boot_id='boot'),expected_cgroup='/user.slice/old.service',
            attested=dict(InvocationID='failed-invocation',ControlGroup='/user.slice/old.service'))
        self.context=dict(capsule=self.saved)
        self.master=dict(scope_id='original-scope',start_epoch=now-30,started_epoch=now-30,expires_epoch=now-30+43200,
            source=oldsource,orchestrator=self.context)
        self.write(self.shared/'master.json',self.master);self.write(self.shared/'orchestrator.json',self.context)
        self.write(self.shared/'terminal.json',dict(status='R152_ORCHESTRATION_OPERATIONAL_STOP_BASELINE_PRESERVED',
            baseline_worker_signals=0,source_head='old-head',error='baseline ownership epoch/master/heartbeat differs',finished_epoch=now-18))
        self.write(self.shared/'blocked.json',dict(preserved=True))
        _,self.original=m.original_master()
        self.failed=m.failed_parent(self.system)
        self.probe=self.home/'probe.json';self.probe_value=dict(status='PASS_R152_PARENT_RECOVERY_DISPOSABLE_PROBE',
            original_master_sha256=m.digest(m.MASTER),scope_id=self.master['scope_id'],boot_id='boot',started_epoch=now-10,
            cleanup_verified=True,cleanup_errors=[],probe_driver_CPU_seconds=5.,unit_CPU_charges=[dict(CPU_seconds=20.)],
            charged_control_CPU_seconds=30.,execution_source=self.source,scientific_runs=0,production_admissions=0,
            parent_death_binding_verified=True)
        self.probe_value.update(private_adoption_CPU_bound_seconds=5.,private_baseline_adoption_probe=dict(
            status='PASS_R152_PRIVATE_BASELINE_ADOPTION_PROBE',execution_source=self.source,original_master_sha256=m.digest(m.MASTER),
            generation=2,exact_cleanup=True,scientific_runs=0,orphan_CPU_bound_seconds=5.))
        self.write(self.probe,self.probe_value)
        self.release=self.home/'release.json';self.write(self.release,dict(schema_version=1,status='R152_PARENT_RECOVERY_RELEASE',
            execution_source=self.source,original_master=self.original,failed_parent={key:self.failed[key] for key in
                ('capsule_path','capsule_sha256','terminal_path','terminal_sha256','blocked_path','blocked_sha256')}))
        attempt='a'*32;self.path=self.shared/'development/recovery'/attempt/'authority.json';unit='pricefm-r150-r152-recovery-'+attempt+'.service'
        intent=dict(unit=unit,argv=[m.PYTHON,'-B',str(m.BROKER),'--authority',str(self.path),'--unit',unit],
            description='test',runtime_seconds=math.floor(self.master['expires_epoch']-5-now),source_head=self.source['head'],
            source_entry_path=str(m.BROKER),source_entry_sha256=m.digest(m.BROKER),working_directory=str(m.EE_ROOT),parent=None,created_epoch=now)
        prior=m.failed_parent_charge(self.failed);probes=m.validate_probe_receipts([self.probe],self.source,self.master)
        self.authority=dict(schema_version=1,stage='R152',kind='ORIGINAL_SCOPE_PARENT_RECOVERY',attempt_id=attempt,
            original_master=self.original,execution_source=self.source,failed_parent=self.failed,zero_admission_inventory=m.inventory(),
            effective_parent_expires_epoch=self.master['expires_epoch']-5,release_path=str(self.release),release_sha256=m.digest(self.release),
            prior_control_debit=dict(CPU_seconds=prior['CPU_seconds']+30,failed_parent=prior,probe_receipts=probes,original_limit_CPU_seconds=1800),
            control_intent=intent,attestation_path=str(self.path.parent/'controller_attestation.json'))
        self.write(self.path,self.authority)
    def write(self,path,value):
        path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(__import__('json').dumps(value));return path
    def test_valid_authority_preserves_all_original_bytes(self):
        before={path:path.read_bytes() for path in (m.MASTER,self.shared/'orchestrator.json',self.shared/'terminal.json',self.shared/'blocked.json')}
        result=m.validate_authority(self.path,self.system)
        self.assertEqual(result['original_master'],self.original)
        self.assertEqual(before,{path:path.read_bytes() for path in before})
    def test_clock_reset_or_changed_master_is_rejected(self):
        value=copy.deepcopy(self.master);value['expires_epoch']+=1;self.write(m.MASTER,value)
        with self.assertRaisesRegex(RuntimeError,'original immutable master'):m.validate_authority(self.path,self.system)
    def test_live_failed_predecessor_blocks_recovery(self):
        self.props.update(ActiveState='active',MainPID='11')
        with self.assertRaisesRegex(RuntimeError,'not independently drained'):m.validate_authority(self.path,self.system)
    def test_failed_parent_surviving_cgroup_blocks_recovery(self):
        self.groups['/user.slice/old.service']=[12]
        with self.assertRaisesRegex(RuntimeError,'not independently drained'):m.validate_authority(self.path,self.system)
    def test_failed_parent_original_PID_still_alive_blocks_recovery(self):
        self.proc=copy.deepcopy(self.saved['process'])
        with self.assertRaisesRegex(RuntimeError,'not independently drained'):m.validate_authority(self.path,self.system)
    def test_replaced_predecessor_capsule_is_not_master_identity(self):
        changed=copy.deepcopy(self.context);changed['capsule']['unit']='other'
        self.write(self.shared/'orchestrator.json',changed)
        with self.assertRaisesRegex(RuntimeError,'exact ownership-publication race'):m.validate_authority(self.path,self.system)
    def test_existing_partial_claim_blocks_initial_adoption(self):
        self.write(self.shared/'development/admissions/EE/C1/funding.json',dict(partial=True))
        with self.assertRaisesRegex(RuntimeError,'claims appeared'):m.validate_authority(self.path,self.system)
        self.assertEqual(m.validate_authority(self.path,self.system,require_empty=False)['attempt_id'],'a'*32)
    def test_existing_controller_blocks_initial_adoption(self):
        self.write(self.shared/'development/controller.json',dict(unit='unexpected'))
        with self.assertRaisesRegex(RuntimeError,'claims appeared'):m.validate_authority(self.path,self.system)
    def test_false_initial_zero_claim_receipt_is_rejected(self):
        self.authority['zero_admission_inventory']['admissions']=['oldclaim'];self.write(self.path,self.authority)
        with self.assertRaisesRegex(RuntimeError,'initial zero-claim'):m.validate_authority(self.path,self.system)
    def test_shorter_effective_deadline_cannot_be_extended(self):
        self.authority['effective_parent_expires_epoch']+=5;self.write(self.path,self.authority)
        with self.assertRaisesRegex(RuntimeError,'recovery clock'):m.validate_authority(self.path,self.system)
    def test_kernel_duration_extension_is_rejected(self):
        self.authority['control_intent']['runtime_seconds']+=100;self.write(self.path,self.authority)
        with self.assertRaisesRegex(RuntimeError,'kernel duration'):m.validate_authority(self.path,self.system)
    def test_other_executable_cannot_reuse_authority(self):
        self.authority['control_intent']['argv'][2]='/tmp/other.py';self.write(self.path,self.authority)
        with self.assertRaisesRegex(RuntimeError,'control intent'):m.validate_authority(self.path,self.system)
    def test_original_control_budget_is_not_replenished(self):
        self.authority['prior_control_debit']['CPU_seconds']-=1;self.write(self.path,self.authority)
        with self.assertRaisesRegex(RuntimeError,'shared-control debit'):m.validate_authority(self.path,self.system)
    def test_probe_charge_cannot_hide_unit_or_driver_CPU(self):
        self.probe_value['charged_control_CPU_seconds']=1;self.write(self.probe,self.probe_value)
        with self.assertRaisesRegex(RuntimeError,'probe debit'):m.validate_authority(self.path,self.system)
    def test_duplicate_probe_receipt_cannot_hide_prior_attempt(self):
        with self.assertRaisesRegex(RuntimeError,'duplicated'):m.validate_probe_receipts([self.probe,self.probe],self.source,self.master)
    def test_failed_probe_remains_charged_before_success(self):
        earlier=self.home/'earlier.json';value=dict(self.probe_value,status='FAIL_R152_PARENT_RECOVERY_DISPOSABLE_PROBE')
        self.write(earlier,value)
        rows=m.validate_probe_receipts([earlier,self.probe],self.source,self.master)
        self.assertEqual(sum(row['charged_CPU_seconds'] for row in rows),60)
    def test_incomplete_probe_cleanup_cannot_release_recovery(self):
        self.probe_value['cleanup_verified']=False;self.write(self.probe,self.probe_value)
        with self.assertRaisesRegex(RuntimeError,'cleanup identity'):m.validate_probe_receipts([self.probe],self.source,self.master)
    def test_probe_success_requires_actual_parent_death_binding(self):
        self.probe_value['parent_death_binding_verified']=False;self.write(self.probe,self.probe_value)
        with self.assertRaisesRegex(RuntimeError,'lifecycle probe'):m.validate_probe_receipts([self.probe],self.source,self.master)
    def test_u64_unknown_CPU_uses_failed_parent_wall_bound(self):
        failed=copy.deepcopy(self.failed);failed['drain_proof']['properties']['CPUUsageNSec']=str(2**64-1)
        value=m.failed_parent_charge(failed)
        self.assertEqual(value['CPU_seconds'],35.)
        self.assertIn('WALL_TIMES_FIFTEEN',value['basis'])
    def test_actual_failed_parent_CPU_always_adds_five(self):
        failed=copy.deepcopy(self.failed);failed['drain_proof']['properties']['CPUUsageNSec']='2000000000'
        self.assertEqual(m.failed_parent_charge(failed)['CPU_seconds'],7.)
    def test_probe_u64_unknown_CPU_uses_real_lifetime_bound(self):
        self.props['CPUUsageNSec']=str(2**64-1)
        saved=dict(unit='unit',created_epoch=100.,cpus=[24])
        with patch.object(m.time,'time',return_value=110.):value=m.probe_charge(saved,self.system)
        self.assertEqual(value['CPU_seconds'],15.)
    def test_CPU_counter_bounds_reject_sentinels_and_negatives(self):
        for value in ('[not set]',str(2**64-1),str(2**63),'-1',None):
            with self.subTest(value=value):self.assertIsNone(m.unit_cpu_seconds(value))
        self.assertEqual(m.unit_cpu_seconds('1000000000'),1.)
    def test_immutable_publication_is_complete_create_once(self):
        target=self.home/'complete.json';real_link=os.link
        def publish(temporary,destination):
            self.assertFalse(Path(destination).exists());self.assertEqual(m.read(temporary),dict(complete=True));real_link(temporary,destination)
        with patch.object(m.os,'link',side_effect=publish):m.immutable(target,dict(complete=True))
        with self.assertRaises(FileExistsError):m.immutable(target,dict(replaced=True))
        self.assertEqual(m.read(target),dict(complete=True));self.assertEqual(list(self.home.glob('.complete.json.*.tmp')),[])
    def test_kernel_anchor_is_actual_monotonic_unit_start(self):
        with patch.object(m.subprocess,'check_output',return_value='80000000\n'),\
                patch.object(m.time,'time',return_value=1000.),patch.object(m.time,'monotonic',return_value=100.):
            self.assertEqual(m.kernel_deadline(self.system,'unit',10),990.)
    def test_unavailable_kernel_anchor_blocks_release(self):
        with patch.object(m.subprocess,'check_output',return_value='0\n'):
            with self.assertRaisesRegex(RuntimeError,'anchor invalid'):m.kernel_deadline(self.system,'unit',10)
    def test_existing_recovery_scope_cannot_launch_again(self):
        self.write(self.shared/'development/recovery/scope_claim.json',dict(consumed=True))
        with self.assertRaisesRegex(RuntimeError,'already claimed'):m.launch(self.release,[self.probe])
    def test_failed_new_control_attestation_drains_only_its_owned_unit(self):
        starts=[];cleaned=[]
        self.path.unlink()
        self.system.start=lambda unit,*args,**kwargs:starts.append(unit)
        self.pool.drain_exact=lambda system,saved:cleaned.append(saved['unit']) or dict(drained=True)
        before=m.MASTER.read_bytes()
        with patch.object(m,'attest_control',side_effect=RuntimeError('delayed kernel start')):
            with self.assertRaisesRegex(RuntimeError,'delayed kernel'):m.launch(self.release,[self.probe])
        self.assertEqual(starts,cleaned);self.assertEqual(len(starts),1)
        self.assertRegex(starts[0],r'^pricefm-r150-r152-recovery-[a-f0-9]{32}\.service$')
        self.assertNotEqual(starts[0],self.saved['unit']);self.assertEqual(m.MASTER.read_bytes(),before)
    def _probe_manager(self,policy_live):
        props={};started=[];cleaned=[]
        def start(unit,description,argv,**kwargs):
            started.append((unit,argv))
            props[unit]=dict(ActiveState='active',MainPID=str(len(started)),BindsTo=kwargs.get('controller') or '',After=kwargs.get('controller') or '')
        system=types.SimpleNamespace(start=start,unit=lambda unit:dict(props[unit]))
        self.pool.System=lambda:system
        self.pool.hardening=lambda:types.SimpleNamespace(strict_worker_policy=lambda *args:policy_live)
        self.pool.drain_exact=lambda system,saved:cleaned.append(saved['unit']) or dict(unit=saved['unit'],drained=True)
        def attest(system,intent,*args,**kwargs):
            return dict(intent,attested=dict(InvocationID='inv'),process=dict(pid=len(started),affinity=intent['cpus']),
                expected_cgroup='/user.slice/'+intent['unit'],actual_kernel_expires_epoch=self.master['expires_epoch']-10)
        def kill(argv,**kwargs):
            if argv[0]==m.PYTHON:
                self.assertEqual(argv[2],str(m.ADAPTER));self.assertEqual(argv[3],'probe')
                report=Path(argv[argv.index('--output')+1]);self.write(report,dict(status='PASS_R152_PRIVATE_BASELINE_ADOPTION_PROBE',
                    execution_source=self.source,original_master_sha256=m.digest(m.MASTER),scope_id=self.master['scope_id'],
                    generation=2,exact_cleanup=True,scientific_runs=0,orphan_CPU_bound_seconds=10.))
                return types.SimpleNamespace(returncode=0,stdout='',stderr='')
            self.assertEqual(argv[:5],['systemctl','--user','kill','--kill-who=main','--signal=KILL'])
            self.assertIn('-probe-parent-',argv[-1])
            for value in props.values():value['ActiveState']='failed';value['MainPID']='0'
            return types.SimpleNamespace(returncode=0)
        return started,cleaned,attest,kill
    def test_disposable_probe_requires_live_policy_and_finally_cleans_both_units(self):
        started,cleaned,attest,kill=self._probe_manager(False);output=self.home/'new_failed_probe.json'
        observation=dict(threads=1,thread_environment={key:'1' for key in m.THREADS})
        with patch.object(m,'source_identity',return_value=self.source),patch.object(m,'attest_control',side_effect=attest),\
                patch.object(m,'wait_file',return_value=observation),patch.object(m,'probe_charge',side_effect=lambda saved,system:dict(CPU_seconds=20.)),\
                patch.object(m.subprocess,'run',side_effect=kill) as signal:
            with self.assertRaisesRegex(RuntimeError,'receipt preserved'):m.capability_probe(output)
            self.assertEqual(signal.call_count,1);self.assertEqual(signal.call_args.args[0][0],m.PYTHON)
        receipt=m.read(output);self.assertTrue(receipt['cleanup_verified']);self.assertEqual(len(cleaned),2)
        self.assertIn('policy proof was not live',receipt['error'])
        self.assertGreaterEqual(receipt['charged_control_CPU_seconds'],45.)
        self.assertTrue(all('hold' in argv and str(m.ENTRY) in argv for _,argv in started))
    def test_disposable_probe_proves_parent_death_and_charges_driver_and_units(self):
        started,cleaned,attest,kill=self._probe_manager(True);output=self.home/'new_good_probe.json'
        observation=dict(threads=1,thread_environment={key:'1' for key in m.THREADS})
        with patch.object(m,'source_identity',return_value=self.source),patch.object(m,'attest_control',side_effect=attest),\
                patch.object(m,'wait_file',return_value=observation),patch.object(m,'probe_charge',side_effect=lambda saved,system:dict(CPU_seconds=20.)),\
                patch.object(m.subprocess,'run',side_effect=kill):
            result=m.capability_probe(output)
        self.assertEqual(result['status'],'PASS_R152_PARENT_RECOVERY_DISPOSABLE_PROBE')
        self.assertTrue(result['parent_death_binding_verified']);self.assertTrue(result['cleanup_verified'])
        self.assertEqual(len(cleaned),2);self.assertEqual(result['original_master_sha256'],m.digest(m.MASTER))
        self.assertEqual(started[1][1][:3],['/usr/bin/chrt','--idle','0'])
        self.assertEqual(started[1][1][3:6],[m.PYTHON,'-B',str(m.ENTRY)])
    def _idle_attestation(self):
        self.props.update(ActiveState='active',MainPID='12',InvocationID='idle-invocation',RuntimeMaxUSec='55s',
            IOSchedulingClass='3',CPUAccounting='yes',ControlGroup='/user.slice/idle.service')
        intent=dict(unit='unit',runtime_seconds=55,expected_cgroup='/user.slice/idle.service')
        process=dict(pid=12,start_ticks=100,boot_id='boot',affinity=[24],scheduler=0)
        return intent,process
    def test_idle_first_exec_wait_is_bounded_and_keeps_exact_lifetime(self):
        intent,initial=self._idle_attestation();ready=dict(initial,scheduler=5)
        with patch.object(m,'describe_process',side_effect=[initial,ready]),patch.object(m.time,'sleep'),\
                patch.object(m,'kernel_deadline',return_value=self.master['expires_epoch']-10):
            result=m.attest_control(self.system,intent,self.master['expires_epoch'],idle=True,cpu=24)
        self.assertEqual(result['process'],ready)
    def test_idle_first_exec_wait_rejects_process_reuse(self):
        intent,initial=self._idle_attestation();reused=dict(initial,start_ticks=101,scheduler=5)
        with patch.object(m,'describe_process',side_effect=[initial,reused]),patch.object(m.time,'sleep'):
            with self.assertRaisesRegex(RuntimeError,'changed process lifetime'):
                m.attest_control(self.system,intent,self.master['expires_epoch'],idle=True,cpu=24)
    def test_idle_first_exec_wait_rejects_unit_invocation_change(self):
        intent,initial=self._idle_attestation();changed=dict(self.props,InvocationID='other')
        with patch.object(self.system,'unit',side_effect=[dict(self.props),changed]),\
                patch.object(m,'describe_process',return_value=initial),patch.object(m.time,'sleep'):
            with self.assertRaisesRegex(RuntimeError,'changed unit invocation'):
                m.attest_control(self.system,intent,self.master['expires_epoch'],idle=True,cpu=24)
    def test_idle_first_exec_timeout_retains_actual_policy_diagnostics(self):
        intent,initial=self._idle_attestation()
        with patch.object(m,'describe_process',return_value=initial),patch.object(m.time,'sleep'),\
                patch.object(m.time,'monotonic',side_effect=[0.,0.,4.]):
            with self.assertRaisesRegex(RuntimeError,'live recovery control policy differs') as failure:
                m.attest_control(self.system,intent,self.master['expires_epoch'],idle=True,cpu=24)
        self.assertIn('"expected_scheduler": 5',str(failure.exception))
        self.assertIn('"scheduler": 0',str(failure.exception))
        self.assertIn('idle-invocation',str(failure.exception))

if __name__=='__main__':unittest.main()
