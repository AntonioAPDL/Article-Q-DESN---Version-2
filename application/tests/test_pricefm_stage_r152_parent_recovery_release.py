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
    def _incomplete_private_cleanup(self,unit=False):
        broker_patch=patch.object(m,'BROKER',m.ENTRY.with_name('509_resume_pricefm_stage_r152_cached_pool.py'))
        broker_patch.start();self.addCleanup(broker_patch.stop)
        earlier=self.home/'incomplete.json';folder=self.home/('incomplete.'+'d'*32+'.runtime');folder.mkdir()
        private=tempfile.TemporaryDirectory(prefix='pricefm-r152-baseline-probe-');self.addCleanup(private.cleanup);namespace=Path(private.name)
        core=m.OLD_ROOT/'application/scripts/pricefm/504_supervise_pricefm_stage_r152_baseline.py'
        driver=dict(pid=101,start_ticks=1010,boot_id='boot',argv=[m.PYTHON,'-B',str(m.ADAPTER),'probe','--output',str(folder/'private_baseline_adoption.json')])
        publisher=dict(pid=102,start_ticks=1020,boot_id='boot',session_id=102,
            argv=[m.PYTHON,'-B',str(core),'probe-orphan','--probe-runtime',str(namespace)])
        child=dict(pid=103,start_ticks=1030,boot_id='boot',session_id=102,argv=[m.PYTHON,'-B','-c','import time; time.sleep(20)'])
        self.write(namespace/'authority.json',dict(disposable=True,owner=driver,source=self.master['source']))
        self.write(namespace/'orphan_job.json',dict(disposable=True,process=publisher,child=child,observed_children=[child],session_id=102))
        self.write(namespace/'cleanup.json',dict(cleanup_verified=True,owned_pids=[],original_lifetimes=[publisher,child],signals=[],unrelated_process_signals=0))
        adoption=dict(self.probe_value['private_baseline_adoption_probe'],status='FAIL_R152_PRIVATE_BASELINE_ADOPTION_PROBE',exact_cleanup=False,
            exact_orphan_adoption=False,probe_namespace=str(namespace),scope_id=self.master['scope_id'],production_units=0,
            delegated_core_path=str(core),delegated_core_sha256=m.digest(core))
        self.write(folder/'private_baseline_adoption.json',adoption)
        value=dict(self.probe_value,status='FAIL_R152_PARENT_RECOVERY_DISPOSABLE_PROBE',cleanup_verified=False,
            cleanup_errors=[],cleanup=[],unit_CPU_charges=[],charged_control_CPU_seconds=10.,probe_runtime=str(folder),
            private_baseline_adoption_probe=adoption,private_baseline_adoption_probe_sha256=m.digest(folder/'private_baseline_adoption.json'))
        if unit:
            name='pricefm-r150-r152-recovery-probe-parent-'+'e'*32+'.service';group='/user.slice/'+name
            intent=dict(unit=name,argv=['python','hold'],expected_cgroup=group)
            proc=dict(pid=104,start_ticks=1040,boot_id='boot')
            self.write(folder/'parent_intent.json',intent)
            self.write(folder/'parent_attestation.json',dict(intent,process=proc,attested=dict(InvocationID='old-probe',ControlGroup=group)))
            self.write(folder/'parent.json',dict(process=proc))
            value['unit_CPU_charges']=[dict(unit=name,CPU_seconds=5.)];value['charged_control_CPU_seconds']=15.
        self.write(earlier,value)
        resolution_source=dict(root=str(m.ROOT),head='c'*40,branch=m.BRANCH,
            runtime_sha256={str(path.relative_to(m.ROOT)):m.digest(path) for path in (m.ENTRY,m.BROKER,m.ADAPTER,m.BASELINE_RELEASE)})
        return earlier,value,folder,namespace,resolution_source
    def _resolve_private(self,earlier,resolution_source,process_snapshot=None):
        with patch.object(m,'source_identity',return_value=resolution_source),patch.object(m.time,'process_time',return_value=2.),\
                patch.object(m.os,'times',return_value=types.SimpleNamespace(children_user=1.,children_system=.5)):
            return m.resolve_probe_cleanup(earlier,system=self.system,process_snapshot=process_snapshot or (lambda pid:None))
    def test_failed_cleanup_resolution_preserves_failed_bytes_and_adds_actual_CPU_plus_five(self):
        earlier,value,folder,namespace,source=self._incomplete_private_cleanup();before=earlier.read_bytes()
        resolution=self._resolve_private(earlier,source)
        self.assertEqual(earlier.read_bytes(),before);self.assertEqual(resolution['charged_control_CPU_seconds'],8.5)
        self.assertEqual(resolution['signals_sent'],0);self.assertEqual(len(resolution['inventory']['processes']),3)
        with patch.object(m,'process_lifetime_snapshot',return_value=None):rows=m.validate_probe_receipts([earlier,self.probe],self.source,self.master)
        self.assertEqual(rows[0]['status'],'FAIL_R152_PARENT_RECOVERY_DISPOSABLE_PROBE')
        self.assertEqual(rows[0]['charged_CPU_seconds'],18.5);self.assertEqual(sum(row['charged_CPU_seconds'] for row in rows),48.5)
        self.assertEqual(rows[0]['resolution_sha256'],m.digest(m.cleanup_resolution_path(earlier)))
    def test_cleanup_resolution_never_qualifies_latest_failed_probe(self):
        earlier,value,folder,namespace,source=self._incomplete_private_cleanup();self._resolve_private(earlier,source)
        with self.assertRaisesRegex(RuntimeError,'cleanup identity'):m.validate_probe_receipts([earlier],self.source,self.master)
    def test_live_recorded_private_child_blocks_resolution_without_signals(self):
        earlier,value,folder,namespace,source=self._incomplete_private_cleanup()
        live=lambda pid:dict(pid=103,start_ticks=1030,boot_id='boot',state='S') if pid==103 else None
        with self.assertRaisesRegex(RuntimeError,'still live'):self._resolve_private(earlier,source,live)
        self.assertFalse(m.cleanup_resolution_path(earlier).exists())
    def test_readonly_resolution_never_signals_reused_PID(self):
        earlier,value,folder,namespace,source=self._incomplete_private_cleanup()
        reused=lambda pid:dict(pid=103,start_ticks=9999,boot_id='boot',state='S') if pid==103 else None
        result=self._resolve_private(earlier,source,reused)
        proof=next(row for row in result['proof']['processes'] if row['pid']==103)
        self.assertEqual(proof['disposition'],'PID_REUSED_NO_SIGNAL');self.assertEqual(result['signals_sent'],0)
    def test_resolution_rechecks_lifetimes_instead_of_only_trusting_seal(self):
        earlier,value,folder,namespace,source=self._incomplete_private_cleanup();self._resolve_private(earlier,source)
        with patch.object(m,'process_lifetime_snapshot',return_value=dict(pid=103,start_ticks=1030,boot_id='boot',state='S')):
            with self.assertRaisesRegex(RuntimeError,'still live'):m.validate_probe_receipts([earlier,self.probe],self.source,self.master)
    def test_live_disposable_unit_or_cgroup_blocks_resolution(self):
        earlier,value,folder,namespace,source=self._incomplete_private_cleanup(unit=True)
        name=value['unit_CPU_charges'][0]['unit'];self.groups['/user.slice/'+name]=[104]
        with self.assertRaisesRegex(RuntimeError,'not drained'):self._resolve_private(earlier,source)
        self.groups.clear();self.props.update(ActiveState='active',MainPID='104')
        with self.assertRaisesRegex(RuntimeError,'not drained'):self._resolve_private(earlier,source)
    def test_unrecorded_charged_unit_cannot_get_cleanup_resolution(self):
        earlier,value,folder,namespace,source=self._incomplete_private_cleanup()
        value['unit_CPU_charges']=[dict(unit='unknown-unit',CPU_seconds=1.)];value['charged_control_CPU_seconds']+=1.;self.write(earlier,value)
        with self.assertRaisesRegex(RuntimeError,'ownership records are incomplete'):self._resolve_private(earlier,source)
    def test_private_cleanup_missing_root_or_child_cannot_be_reconciled(self):
        earlier,value,folder,namespace,source=self._incomplete_private_cleanup();cleanup=m.read(namespace/'cleanup.json')
        cleanup['original_lifetimes']=cleanup['original_lifetimes'][:1];self.write(namespace/'cleanup.json',cleanup)
        with self.assertRaisesRegex(RuntimeError,'omitted a recorded root or child'):self._resolve_private(earlier,source)
    def test_unknown_recorded_owned_PID_cannot_get_cleanup_resolution(self):
        earlier,value,folder,namespace,source=self._incomplete_private_cleanup();cleanup=m.read(namespace/'cleanup.json')
        cleanup['owned_pids']=[999];self.write(namespace/'cleanup.json',cleanup)
        with self.assertRaisesRegex(RuntimeError,'without a complete lifetime'):self._resolve_private(earlier,source)
    def test_wrong_private_probe_output_binding_is_rejected(self):
        earlier,value,folder,namespace,source=self._incomplete_private_cleanup();authority=m.read(namespace/'authority.json')
        authority['owner']['argv'][-1]='other-probe.json';self.write(namespace/'authority.json',authority)
        with self.assertRaisesRegex(RuntimeError,'does not bind this failed probe'):self._resolve_private(earlier,source)
    def test_resolution_is_create_once_and_keeps_prior_failure_unchanged(self):
        earlier,value,folder,namespace,source=self._incomplete_private_cleanup();self._resolve_private(earlier,source)
        before=m.cleanup_resolution_path(earlier).read_bytes()
        with self.assertRaises(FileExistsError):self._resolve_private(earlier,source)
        self.assertEqual(m.cleanup_resolution_path(earlier).read_bytes(),before);self.assertFalse(m.read(earlier)['cleanup_verified'])
    def test_changed_original_probe_or_copied_resolution_fails_identity(self):
        earlier,value,folder,namespace,source=self._incomplete_private_cleanup();self._resolve_private(earlier,source)
        value['error']='changed bytes';self.write(earlier,value)
        with self.assertRaisesRegex(RuntimeError,'resolution identity'):m.validate_probe_receipts([earlier,self.probe],self.source,self.master)
    def test_resolution_cannot_refund_exit_allowance_or_omit_execution_pin(self):
        earlier,value,folder,namespace,source=self._incomplete_private_cleanup();resolution=self._resolve_private(earlier,source)
        resolution['charged_control_CPU_seconds']=resolution['observed_resolution_CPU_seconds'];self.write(m.cleanup_resolution_path(earlier),resolution)
        with self.assertRaisesRegex(RuntimeError,'resolution identity'):m.validate_probe_receipts([earlier,self.probe],self.source,self.master)
    def test_private_inputs_changed_after_resolution_fail_closed(self):
        earlier,value,folder,namespace,source=self._incomplete_private_cleanup();self._resolve_private(earlier,source)
        cleanup=m.read(namespace/'cleanup.json');cleanup['epoch']=123.;self.write(namespace/'cleanup.json',cleanup)
        with self.assertRaisesRegex(RuntimeError,'resolution inventory differs'):m.validate_probe_receipts([earlier,self.probe],self.source,self.master)
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
