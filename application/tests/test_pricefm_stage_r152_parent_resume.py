"""Recovery authority, finite-parent, accounting and loop tests; no host action."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from contextlib import ExitStack
from unittest.mock import Mock,patch

ROOT=Path(__file__).resolve().parents[2]
ENTRY=ROOT/'application/scripts/pricefm/509_resume_pricefm_stage_r152_cached_pool.py'
spec=importlib.util.spec_from_file_location('r152_parent_resume_tests',ENTRY)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


class ParentResumeTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.shared=Path(self.temp.name);self.runtime=self.shared/'development';self.runtime.mkdir()
        original=m.original_api()
        self.api=types.SimpleNamespace(**{name:getattr(original,name) for name in dir(original) if not name.startswith('__')})
        self.c=self.api.read_config();self.now=1001.
        self.master=dict(schema_version=1,stage='R152',scope_id='scope',start_epoch=1000.,started_epoch=1000.,expires_epoch=44200.,boot_id='boot',
            source=dict(root=str(m.OLD_ROOT),head=m.OLD_HEAD,branch='work/pricefm-r152-parallel-recovery-20261024',runtime_sha256={}),
            partition=dict(baseline_A=list(range(15)),baseline_B=list(range(15,24)),development_base=list(range(24,30)),optional=[22,23]),probe_sha256='original-probe')
        self.api.immutable(self.shared/'master.json',self.master)
        self.authority=dict(schema_version=1,stage='R152',kind='ORIGINAL_SCOPE_PARENT_RECOVERY',attempt_id='attempt',
            original_master=dict(path=str(self.shared/'master.json'),sha256=self.api.digest(self.shared/'master.json'),scope_id='scope',
                start_epoch=1000.,started_epoch=1000.,expires_epoch=44200.,source=self.master['source']),
            execution_source=dict(root=str(ROOT),head='new',branch='work/pricefm-r152-parent-recovery-20261024',runtime_sha256={}),
            failed_parent=dict(capsule=dict(unit='old-parent')),
            effective_parent_expires_epoch=44195.,prior_control_debit=dict(CPU_seconds=25.,original_limit_CPU_seconds=1800),
            attestation_path=str(self.runtime/'recovery/attempt/controller_attestation.json'))
        self.capsule=dict(unit='pricefm-r150-r152-recovery-test.service',attested=dict(InvocationID='new-inv'),
            actual_kernel_expires_epoch=44199.,process=dict(pid=123,start_ticks=456,boot_id='boot'))
        self.authority_path=self.runtime/'recovery/attempt/authority.json'
        self.api.immutable(self.authority_path,self.authority)
        self.authority.update(_authority_path=str(self.authority_path),_authority_sha256=self.api.digest(self.authority_path))

    def test_import_and_actual_CLI_help_are_metadata_only(self):
        result=subprocess.run([sys.executable,'-B',str(ENTRY),'--help'],text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr);self.assertIn('--authority',result.stdout)
        self.assertFalse({'numpy','scipy','pandas'}&set(sys.modules))

    def test_original_api_is_separate_unchanged_cba_module(self):
        api=m.original_api()
        self.assertEqual(api.ROOT,m.OLD_ROOT)
        self.assertEqual(api.git(api.ROOT,'rev-parse','HEAD'),m.OLD_HEAD)
        self.assertEqual(api.git(api.ROOT,'status','--porcelain'),'')
        self.assertNotEqual(api.ROOT,ROOT)

    def test_planning_copy_preserves_original_clock_and_reserves_cleanup(self):
        prior=copy.deepcopy(self.master)
        planning=m.planning_master(self.master,self.authority,self.capsule)
        self.assertEqual(planning['expires_epoch'],44105.)
        self.assertEqual(self.master,prior)
        self.assertEqual(self.api.read(self.shared/'master.json'),prior)
        self.assertEqual(planning['start_epoch'],1000.)

    def test_actual_kernel_deadline_cannot_extend_master(self):
        with self.assertRaisesRegex(RuntimeError,'kernel deadline'):
            m.control_deadline(self.authority,dict(self.capsule,actual_kernel_expires_epoch=44201.))

    def test_window_that_fits_master_but_crosses_cleanup_horizon_is_rejected(self):
        self.api.claim_admission=Mock()
        with self.assertRaisesRegex(RuntimeError,'actual recovery parent'):
            m.claim_admission(self.api,self.runtime,self.master,'EE','numerical','science','prep','unit',
                authority=self.authority,controller=self.capsule,projection=dict(fits=True),now=44195-7200-20)
        self.api.claim_admission.assert_not_called()

    def test_accepted_claim_passes_original_master_and_binds_authority(self):
        self.api.claim_admission=Mock(return_value=('lease',{}))
        m.claim_admission(self.api,self.runtime,self.master,'EE','numerical','science','prep','unit',
            authority=self.authority,controller=self.capsule,projection=dict(fits=True),now=self.now)
        args=self.api.claim_admission.call_args
        self.assertIs(args.args[1],self.master)
        self.assertEqual(args.kwargs['projection']['recovery_authority_sha256'],self.authority['_authority_sha256'])
        self.assertEqual(args.kwargs['projection']['recovery_admission_deadline'],44105.)

    def test_projection_and_admin_receive_only_shorter_planning_clock(self):
        self.api.projection=Mock(return_value=dict(fits=True));self.api.admin_projection=Mock(return_value=dict(fits=True))
        m.projection(self.api,self.runtime,self.master,self.c,{},set(),{},self.authority,self.capsule)
        m.admin_projection(self.api,self.runtime,self.master,self.c,{},set(),'FI','benchmark',24,{},self.authority,self.capsule)
        self.assertEqual(self.api.projection.call_args.args[1]['expires_epoch'],44105.)
        self.assertEqual(self.api.admin_projection.call_args.args[1]['expires_epoch'],44105.)
        self.assertEqual(self.master['expires_epoch'],44200.)

    def _armed_baseline(self,phase='armed',expiry=None):
        state=dict(phase=phase,scope_id='scope',source=self.master['source'])
        epoch=dict(state,expires_epoch=expiry,heartbeat=self.now)
        self.api.immutable(self.shared/'baseline/state.json',state)
        self.api.immutable(self.shared/'baseline/resource_ownership_epoch.json',epoch)

    def test_first_master_heartbeat_publication_race_is_bounded_and_retried(self):
        self._armed_baseline();owner=Mock(side_effect=[RuntimeError('baseline ownership epoch/master/heartbeat differs'),dict(healthy=True)])
        self.api.baseline=lambda:types.SimpleNamespace(baseline_ownership=owner)
        with patch.object(m.time,'time',return_value=self.now),patch.object(m.time,'sleep'):
            self.assertEqual(m.await_baseline_ownership(self.api,self.shared,self.master),dict(healthy=True))
        self.assertEqual(owner.call_count,2)

    def test_running_owner_mismatch_is_not_retried_as_publication(self):
        self._armed_baseline(phase='running',expiry=44200.)
        owner=Mock(side_effect=RuntimeError('baseline ownership epoch/master/heartbeat differs'))
        self.api.baseline=lambda:types.SimpleNamespace(baseline_ownership=owner)
        with patch.object(m.time,'time',return_value=self.now),self.assertRaises(RuntimeError):
            m.await_baseline_ownership(self.api,self.shared,self.master)
        self.assertEqual(owner.call_count,1)

    def test_full_validation_once_per_poll_but_authority_hash_every_guard(self):
        original={key:value for key,value in self.authority.items() if not key.startswith('_')}
        validator=Mock(return_value=original);cache={}
        self.api.git=lambda root,*argv:self.api.EE_HEAD if argv==('rev-parse','HEAD') else ''
        with patch.object(m.time,'monotonic',side_effect=[1.,2.,5.9,6.]):
            for _ in range(4):m.validate_live_authority(self.api,None,self.c,self.master,self.authority,validator,cache)
        self.assertEqual(validator.call_count,2)
        self.api.atomic(self.authority_path,dict(original,changed=True))
        with self.assertRaisesRegex(RuntimeError,'bytes changed'):
            m.validate_live_authority(self.api,None,self.c,self.master,self.authority,validator,cache)

    def test_validation_cache_cannot_cross_scope_or_regress_clock(self):
        self.api.git=lambda root,*argv:self.api.EE_HEAD if argv==('rev-parse','HEAD') else ''
        validator=Mock(return_value={k:v for k,v in self.authority.items() if not k.startswith('_')});cache={}
        with patch.object(m.time,'monotonic',return_value=10.):m.validate_live_authority(self.api,None,self.c,self.master,self.authority,validator,cache)
        with patch.object(m.time,'monotonic',return_value=9.),self.assertRaisesRegex(RuntimeError,'regressed'):
            m.validate_live_authority(self.api,None,self.c,self.master,self.authority,validator,cache)
        with self.assertRaisesRegex(RuntimeError,'source/scope'):
            m.validate_live_authority(self.api,None,self.c,dict(self.master,scope_id='other'),self.authority,validator,cache)

    def test_control_accounting_includes_waited_children_and_maxes_cgroup(self):
        fields=['0']*20;fields[19]='456'
        for index,value in zip((11,12,13,14),(7,3,50,10)):fields[index]=str(value)
        self.api.unit_observation=lambda system,capsule:dict(live_pids=[123],cpu_seconds=.1)
        self.api.legacy=lambda:types.SimpleNamespace(process=lambda pid:dict(start_ticks=456))
        with patch.object(m.Path,'read_text',return_value='123 (python) '+' '.join(fields)),patch.object(m.os,'sysconf',return_value=100):
            self.assertEqual(m.control_CPU_with_children(self.api,None,self.capsule),.7)
        self.api.unit_observation=lambda system,capsule:dict(live_pids=[],cpu_seconds=2.)
        self.assertEqual(m.control_CPU_with_children(self.api,None,self.capsule),2.)

    def test_control_high_water_never_refunds_and_prior_debit_counts_once(self):
        with patch.object(m,'control_CPU_with_children',side_effect=[2.,1.]):
            first=m.control_CPU_total(self.api,None,self.runtime,self.master,[self.capsule],self.authority)
            second=m.control_CPU_total(self.api,None,self.runtime,self.master,[self.capsule],self.authority)
        self.assertEqual(first,27.);self.assertEqual(second,27.)
        changed=copy.deepcopy(self.capsule);changed['attested']['InvocationID']='replacement'
        with self.assertRaisesRegex(RuntimeError,'invocation history'):
            m.control_CPU_total(self.api,None,self.runtime,self.master,[changed],self.authority)

    def _guard_api(self):
        self.api.boot=lambda:'boot'
        self.api.git=lambda root,*argv:self.api.EE_HEAD if argv==('rev-parse','HEAD') else ''
        self.owner=Mock(return_value=dict(healthy=True))
        self.api.baseline=lambda:types.SimpleNamespace(baseline_ownership=self.owner)
        self.api.unit_observation=Mock(return_value=dict(active=False,members=[]))
        self.api.old_lifetime_absent=lambda saved:True
        self.api.verify_control_capsule=Mock()
        self.api.observe_union=Mock(return_value=dict(science_charges={},admin_charges={},active=[],control_CPU_seconds=0))
        self.api.study_limit=lambda study,c:0.
        self.validator=Mock(return_value={key:value for key,value in self.authority.items() if not key.startswith('_')})
        return {name:object() for name in ('EE','FI','DK2')}

    def test_every_guard_fences_units_master_and_baseline_while_sources_cache(self):
        studies=self._guard_api();cache={}
        with patch.object(m.time,'time',return_value=self.now),patch.object(m.time,'monotonic',return_value=10.),\
                patch.object(m,'control_CPU_total',return_value=75.):
            for _ in range(3):
                value=m.live_guard(self.api,None,self.c,self.shared,self.master,self.capsule,studies,{'EE'},self.authority,self.validator,cache)
        self.assertEqual(self.validator.call_count,1)
        self.assertEqual(self.owner.call_count,3)
        self.assertEqual(self.api.verify_control_capsule.call_count,3)
        self.assertEqual(self.api.unit_observation.call_count,3)
        self.assertEqual(value['control_CPU_seconds'],75.)
        self.assertEqual(value['recovery_prior_control_CPU_seconds'],25.)
        self.assertAlmostEqual(value['global_charged_CPU_seconds'],self.c['EE_historical_reservation_CPU_seconds']+75.)

    def test_prior_control_debit_cannot_be_spent_again(self):
        studies=self._guard_api()
        with patch.object(m.time,'time',return_value=self.now),patch.object(m,'control_CPU_total',return_value=1621.),\
                self.assertRaisesRegex(RuntimeError,'control CPU allowance'):
            m.live_guard(self.api,None,self.c,self.shared,self.master,self.capsule,studies,{'EE'},self.authority,self.validator,{})

    def test_failed_original_parent_reactivation_blocks_dispatch(self):
        studies=self._guard_api();self.api.unit_observation.return_value=dict(active=True,members=[777])
        with patch.object(m.time,'time',return_value=self.now),self.assertRaisesRegex(RuntimeError,'original parent lifetime'):
            m.live_guard(self.api,None,self.c,self.shared,self.master,self.capsule,studies,{'EE'},self.authority,self.validator,{})

    def test_master_byte_change_is_rejected_even_with_equal_parsed_JSON(self):
        studies=self._guard_api()
        (self.shared/'master.json').write_text(json.dumps(self.master,separators=(',',':')))
        self.assertEqual(self.api.read(self.shared/'master.json'),self.master)
        with patch.object(m.time,'time',return_value=self.now),self.assertRaisesRegex(RuntimeError,'master bytes'):
            m.live_guard(self.api,None,self.c,self.shared,self.master,self.capsule,studies,{'EE'},self.authority,self.validator,{})

    def test_exact_509_attestation_handshake_uses_new_source_and_actual_lifetime(self):
        argv=['python','-B',str(ENTRY),'--authority',str(self.authority_path),'--unit',self.capsule['unit']]
        intent=dict(unit=self.capsule['unit'],argv=argv,description='recovery',source_head='new',source_entry_path=str(ENTRY),
            source_entry_sha256=self.api.digest(ENTRY),runtime_seconds=30000,parent=None)
        self.authority['control_intent']=intent
        capsule=dict(self.capsule,**{key:value for key,value in intent.items() if key!='unit'})
        self.api.immutable(self.authority['attestation_path'],capsule)
        props=dict(MainPID='123',InvocationID='new-inv')
        self.api.legacy=lambda:types.SimpleNamespace(exec_arguments=lambda properties:' '.join(argv))
        self.api.verify_control_capsule=Mock()
        with patch.object(m.os,'getpid',return_value=123):
            result=m.await_controller(self.api,types.SimpleNamespace(unit=lambda unit:props),self.c,self.authority,self.authority_path,self.capsule['unit'])
        self.assertEqual(result,capsule);self.api.verify_control_capsule.assert_called_once()

    def _final_api(self):
        self.api.drain_scope=Mock(return_value=dict(cleanup_verified=True,cleanup_errors=[],cleanup=[],owned_pids=[],owned_units=[]))
        self.api.all_attempts=lambda runtime:[]
        self.api.drain_exact=Mock(return_value=dict(unit='guardian',drained=True,members=[],pids=[],expected_cgroup='/user.slice/guardian'))
        self.guardian=dict(unit='guardian',attested=dict(InvocationID='guardian-inv'))

    def test_final_drain_preserves_original_source_and_fences_publisher(self):
        self._final_api()
        with patch.object(m,'control_CPU_total',return_value=50.):
            result=m.finalize(self.api,None,self.c,self.shared,self.master,self.capsule,{},self.guardian,self.authority,'DONE',None)
        self.assertTrue(result['cleanup_verified']);self.assertEqual(result['control_charged_CPU_seconds'],230.)
        final=self.api.read(self.runtime/'final_drained.json')
        self.assertEqual(final['source_head'],m.OLD_HEAD);self.assertTrue(final['publisher_pending_drain'])
        self.assertEqual(final['publisher_capsule'],self.capsule)
        self.assertNotIn(self.capsule['unit'],final['owned_units'])
        self.assertEqual(final['owned_units'],['guardian'])
        self.assertTrue((self.shared/'development_closed.json').exists())
        self.assertEqual(self.api.read(self.shared/'master.json'),self.master)

    def test_CPU_read_error_still_attempts_guardian_drain_and_prevents_closure(self):
        self._final_api()
        with patch.object(m,'control_CPU_total',side_effect=PermissionError('CPU denied')):
            result=m.finalize(self.api,None,self.c,self.shared,self.master,self.capsule,{},self.guardian,self.authority,'DONE',None)
        self.api.drain_exact.assert_called_once()
        self.assertFalse(result['cleanup_verified']);self.assertFalse((self.shared/'development_closed.json').exists())
        self.assertGreater(result['control_charged_CPU_seconds'],1800.)

    def test_guardian_drain_failure_never_publishes_final_closure(self):
        self._final_api();self.api.drain_exact.side_effect=RuntimeError('still live')
        with patch.object(m,'control_CPU_total',return_value=50.):
            result=m.finalize(self.api,None,self.c,self.shared,self.master,self.capsule,{},self.guardian,self.authority,'DONE',None)
        self.assertFalse(result['cleanup_verified']);self.assertFalse((self.runtime/'final_drained.json').exists())

    def test_partial_guardian_start_intent_is_drained(self):
        self._final_api();self.api.immutable(self.runtime/'guardian_intent.json',dict(unit='guardian',argv=['expected']))
        system=types.SimpleNamespace(unit=lambda unit:dict(InvocationID='partial',MainPID='777'))
        ownership=Mock();self.api.legacy=lambda:types.SimpleNamespace(verify_owned=ownership,process=lambda pid:dict(pid=pid,start_ticks=1,boot_id='boot'))
        with patch.object(m,'control_CPU_total',return_value=50.):
            result=m.finalize(self.api,system,self.c,self.shared,self.master,self.capsule,{},None,self.authority,'STOP',None)
        ownership.assert_called_once();self.assertTrue(result['cleanup_verified'])
        self.assertEqual(self.api.drain_exact.call_args.args[1]['attested']['InvocationID'],'partial')

    def test_synthetic_dispatch_keeps_EE_science_and_defers_unpriced_FI(self):
        records=[];clock=self.now
        class Study:
            def __init__(self,name):self.study_id=name;self.done=False;self.bench=False
            def queue_state(self):
                if self.study_id=='EE':return dict(phase='READY_FOR_ASSESSMENT' if self.done else 'NOMINEE_SEED0',terminal=self.done,
                    ready=[] if self.done else [dict(name='EE_task_S_seed0')],complete=['EE_task_S_seed0'] if self.done else [],
                    pending=[] if self.done else ['EE_task_S_seed0'],unfunded_pending=[])
                return dict(phase='DEFERRED_UNFUNDED_PREFIX' if self.bench else 'BENCHMARK',ready=[],complete=[],pending=[],terminal=self.bench)
            def advance(self,**kwargs):return self.queue_state()
            def task_complete(self,name):return self.done
            def complete_prefix(self):return self.done
            def pricing(self):return dict(prefix_admitted=False,task_estimates=dict(dummy=dict(estimated_cpu_seconds=1,estimated_wall_seconds=1)))
        studies={name:Study(name) for name in ('EE','FI','DK2')}
        self.api.study_prepared=lambda study:True
        self.api.study_limit=lambda study,c:21786
        self.api.study_cpu_charge=lambda *args,**kwargs:(1085,[])
        self.api.study_source_and_prep=lambda study:(dict(head='science'),'prep')
        self.api.free_slot=lambda *args:24
        self.api.all_attempts=lambda runtime:list(records)
        def observe(*args,**kwargs):return dict(active=[],observations={row['unit']:dict(active=False,properties=dict(ExecMainStatus='0')) for _,row in records})
        def project(*args,**kwargs):return dict(fits=True,worst=dict(packing=dict(allocation=[dict(study='EE',name='EE_task_S_seed0',window_id='EE-C1',start=clock,cpu=24,active=False)])))
        def start(system,c,shared,runtime,master,capsule,study,name,cpu,lease_path,lease,kind,probe):
            folder=runtime/'attempts'/study.study_id/str(len(records));folder.mkdir(parents=True)
            row=dict(unit='worker-'+str(len(records)),study=study.study_id,kind=kind,task=name,cpu=cpu,admission_path=str(lease_path),started_epoch=clock-100)
            path=folder/'ownership.json';self.api.immutable(path,row);records.append((path,row))
            if kind=='numerical':study.done=True
            if kind=='benchmark':study.bench=True
            if kind=='assessment':self.api.immutable(runtime/'assessments/EE/assessment.json',dict(status='SCIENTIFIC_COMPLETE',scientific_complete=True))
        def finish(system,c,runtime,path,saved,study):
            self.api.immutable(path.parent/'finished.json',dict(cleanup=dict(drained=True)))
            return dict(charge=dict(live_or_unit_CPU_lower_bound=100),observation=dict(properties=dict(ExecMainStatus='0')))
        self.api.start_study_task=start;self.api.finish_worker=finish
        self.api.ee_gate=lambda runtime:dict(proceed=False)
        self.api.EE_CANONICAL=self.shared/'old-fences'
        final=Mock(side_effect=lambda *args:dict(status=args[-2],error=args[-1]))
        with patch.object(m,'live_guard',side_effect=observe),patch.object(m,'projection',side_effect=project),\
                patch.object(m,'admin_projection',return_value=dict(fits=True)),patch.object(m,'finalize',final),\
                patch.object(m.time,'time',return_value=clock),patch.object(m.time,'sleep'):
            result=m.dispatch(self.api,None,self.c,self.shared,self.master,self.capsule,studies,None,self.authority,Mock())
        self.assertEqual(result['status'],'R152_FINITE_TRANCHE_DISPOSITION_SEALED',result['error'])
        self.assertEqual(self.api.study_terminal(self.runtime,'EE')['status'],'SCIENTIFIC_COMPLETE')
        self.assertEqual(self.api.study_terminal(self.runtime,'FI')['status'],'DEFERRED_PREFIX_UNFUNDED')
        self.assertEqual(len(self.api.admission_files(self.runtime,'FI','numerical')),0)
        self.assertEqual(len(self.api.admission_files(self.runtime,'EE','numerical')),1)
        self.assertEqual(len(self.api.admission_files(self.runtime,'EE','assessment')),1)


if __name__=='__main__':unittest.main()
