"""Resource/accounting/funding regressions; no scientific forecast or service."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import types
import unittest
from contextlib import ExitStack
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
ENTRY=ROOT/'scripts/pricefm/505_run_pricefm_stage_r152_shared_pool.py'
spec=importlib.util.spec_from_file_location('r152_pool_tests',ENTRY)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


class PoolTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.shared=Path(self.temp.name);self.runtime=self.shared/'development';self.runtime.mkdir()
        self.c=m.read_config();self.now=1000.
        self.master=dict(schema_version=1,stage='R152',scope_id='scope',start_epoch=self.now,started_epoch=self.now,
            expires_epoch=self.now+43200,boot_id='boot',source=dict(root=str(m.ROOT),head='new',branch='work/test',runtime_sha256={}),
            partition=dict(baseline_A=list(range(15)),baseline_B=list(range(15,24)),development_base=list(range(24,30)),optional=[22,23]))
        m.immutable(self.shared/'master.json',self.master)
    def admission(self,study='EE',kind='numerical',now=None):
        return m.claim_admission(self.runtime,self.master,study,kind,'science','prep','controller',
            now=self.now+1 if now is None else now,projection=dict(fits=True))
    def test_config_contract_fixed(self):
        self.assertEqual(self.c['base_cpus'],list(range(24,30)))
        self.assertEqual(m.stop_tail_reserve(self.c,8),420)
        self.assertAlmostEqual(m.nominal_global_limit(self.c,dict(FI=32400,DK2=32400)),96186.14193483983)
    def test_immutable_publication_exposes_only_complete_JSON(self):
        target=self.shared/'publication.json';original=m.os.link;observed=[]
        value=dict(scope_id='scope',payload=list(range(1000)))
        def publish(source,destination):
            self.assertFalse(Path(destination).exists())
            observed.append(json.loads(Path(source).read_text()))
            return original(source,destination)
        with patch.object(m.os,'link',side_effect=publish):m.immutable(target,value)
        self.assertEqual(observed,[value]);self.assertEqual(m.read(target),value)
        with self.assertRaises(FileExistsError):m.immutable(target,dict(different=True))
        self.assertEqual(m.read(target),value)
        self.assertEqual(list(self.shared.glob('.publication.json.*.tmp')),[])
    def test_invalid_config_scope_rejected(self):
        for key,value in [('base_cpus',list(range(6))),('max_workers',30),('automatic_renewal',True)]:
            c=dict(self.c);c[key]=value;p=self.shared/(key+'.json');m.immutable(p,c)
            with self.subTest(key=key),self.assertRaises(RuntimeError):m.read_config(p)
    def test_invalid_regional_ceiling(self):
        for value in (True,-1,float('inf'),32401):
            with self.subTest(value=value),self.assertRaises(RuntimeError):m.nominal_global_limit(self.c,dict(FI=value))
    def test_single_master_clock(self):
        m.validate_master(self.master,self.c,now=self.now+1)
        for key,value in [('expires_epoch',self.now+999999),('started_epoch',self.now+1),('stage','R151')]:
            master=copy.deepcopy(self.master);master[key]=value
            with self.subTest(key=key),self.assertRaises(RuntimeError):m.validate_master(master,self.c,now=self.now+1)
    def test_expired_master_rejected(self):
        with self.assertRaises(RuntimeError):m.validate_master(self.master,self.c,now=self.master['expires_epoch'])
    def test_bad_partition_rejected(self):
        master=copy.deepcopy(self.master);master['partition']['development_base']=[22,23,24,25,26,27]
        with self.assertRaises(RuntimeError):m.validate_master(master,self.c,now=self.now+1)
    def test_two_new_EE_admissions_only(self):
        first,lease=self.admission();self.assertEqual(lease['admission_id'],'EE-C1')
        m.close_admission(first,'DEFERRED',cleanup_verified=True)
        second,lease=self.admission(now=self.now+7202);self.assertEqual(lease['admission_id'],'EE-C2')
        m.close_admission(second,'DEFERRED',cleanup_verified=True)
        with self.assertRaises(RuntimeError):self.admission(now=self.now+14403)
        self.assertFalse((self.shared/'wave_3').exists())
    def test_duplicate_live_lease_not_joined(self):
        self.admission()
        with self.assertRaises(RuntimeError):self.admission()
    def test_no_new_EE_benchmark(self):
        with self.assertRaises(RuntimeError):self.admission(kind='benchmark')
    def test_no_claim_without_full_joint_proof(self):
        for value in (None,dict(fits=False)):
            with self.subTest(value=value),self.assertRaises(RuntimeError):
                m.claim_admission(self.runtime,self.master,'FI','numerical','s','p','u',now=self.now+1,projection=value)
    def test_full_new_window_containment(self):
        with self.assertRaises(RuntimeError):self.admission(now=self.master['expires_epoch']-7200)
        self.assertEqual(len(m.admission_files(self.runtime,'EE')),0)
    def test_assessment_requires_closed_compute(self):
        path,parent=self.admission()
        with self.assertRaises(RuntimeError):self.admission(kind='assessment',now=self.now+100)
        m.immutable(path.parent/'compute_closed.json',dict(lease_id=parent['lease_id'],active_workers=[],numerical_dispatch_closed=True,closed_epoch=self.now+90))
        apath,assessment=self.admission(kind='assessment',now=self.now+100)
        self.assertEqual(assessment['parent_admission_path'],str(path))
        self.assertEqual(assessment['parent_lease_id'],parent['lease_id'])
        self.assertLessEqual(assessment['expires_epoch'],parent['expires_epoch'])
        self.assertEqual(assessment['seconds'],1800)
        self.assertFalse((path.parent/'terminal.json').exists())
    def test_late_assessment_cannot_reset_window(self):
        path,parent=self.admission()
        m.immutable(path.parent/'compute_closed.json',dict(active_workers=[],numerical_dispatch_closed=True))
        with self.assertRaises(RuntimeError):self.admission(kind='assessment',now=parent['expires_epoch']-20)
    def test_atomic_slot_and_task_duplicate(self):
        path,lease=self.admission()
        first,row=m.claim_slot(self.runtime,self.master,path,'task',24,'pricefm-r150-r152-1.service',now=self.now+2)
        for task,cpu in [('other',24),('task',25)]:
            with self.subTest(task=task,cpu=cpu),self.assertRaises(RuntimeError):
                m.claim_slot(self.runtime,self.master,path,task,cpu,'pricefm-r150-r152-2.service',now=self.now+2)
        with self.assertRaises(RuntimeError):m.release_slot(first,dict(unit=row['unit'],drained=False,members=[]))
        m.release_slot(first,dict(unit=row['unit'],drained=True,members=[]))
        m.claim_slot(self.runtime,self.master,path,'other',24,'pricefm-r150-r152-3.service',now=self.now+2)
    def test_optional_cpu_cannot_fund_base_claim(self):
        path,lease=self.admission()
        with self.assertRaises(RuntimeError):m.claim_slot(self.runtime,self.master,path,'task',22,'u',now=self.now+2)
    def test_phase_barrier_and_no_slot_overlap(self):
        jobs=[dict(study='EE',name='D1',phase=0,estimated_wall_seconds=10,estimated_cpu_seconds=5),
            dict(study='EE',name='D2',phase=0,estimated_wall_seconds=20,estimated_cpu_seconds=10),
            dict(study='EE',name='S1',phase=1,estimated_wall_seconds=5,estimated_cpu_seconds=2)]
        result=m.pack_joint(jobs,dict(EE=[dict(id='EE-C1',start=0,end=100)]),now=0)
        self.assertTrue(result['fits']);rows=result['allocation']
        end=max(row['end'] for row in rows if row['phase']==0)
        self.assertGreaterEqual(next(row['start'] for row in rows if row['name']=='S1'),end)
        for cpu in range(24,30):
            intervals=sorted((row['start'],row['end']) for row in rows if row['cpu']==cpu)
            self.assertTrue(all(right<=next_left for (left,right),(next_left,next_right) in zip(intervals,intervals[1:])))
    def test_active_D_barrier_not_overwritten_by_short_pending_D(self):
        jobs=[dict(study='EE',name='shortD',phase=0,estimated_wall_seconds=10,estimated_cpu_seconds=5),
            dict(study='EE',name='S',phase=1,estimated_wall_seconds=5,estimated_cpu_seconds=2)]
        active=[dict(study='EE',name='longD',phase=0,cpu=24,projected_end_epoch=80)]
        result=m.pack_joint(jobs,dict(EE=[dict(id='EE-C1',start=0,end=100)]),active=active,now=0)
        self.assertTrue(result['fits']);self.assertGreaterEqual(next(row['start'] for row in result['allocation'] if row['name']=='S'),80)
    def test_independent_study_can_use_early_free_slot(self):
        jobs=[dict(study='EE',name='longD',phase=0,estimated_wall_seconds=80,estimated_cpu_seconds=5),
            dict(study='FI',name='D',phase=0,estimated_wall_seconds=10,estimated_cpu_seconds=5),
            dict(study='FI',name='S',phase=1,estimated_wall_seconds=10,estimated_cpu_seconds=5)]
        windows={s:[dict(id=s+'-C1',start=0,end=100)] for s in ('EE','FI')}
        result=m.pack_joint(jobs,windows,now=0,study_cpus=dict(EE=[24,25,26,27],FI=[28,29]))
        self.assertTrue(result['fits']);self.assertEqual(next(row['start'] for row in result['allocation'] if row['name']=='S'),10)
    def test_unplaced_task_not_dispatched(self):
        result=m.pack_joint([dict(study='EE',name='too-long',phase=0,estimated_wall_seconds=101,estimated_cpu_seconds=1)],dict(EE=[dict(id='EE-C1',start=0,end=100)]),now=0)
        self.assertFalse(result['fits']);self.assertIn('NO_EXHIBITED',result['proof'])
    def test_optional_calendar_rejected(self):
        with self.assertRaises(RuntimeError):m.pack_joint([],{},cpus=list(range(22,30)),now=0)
    def test_unsealed_elapsed_wall_receives_no_credit(self):
        class Study:
            def estimate_task(self,name):return dict(estimated_wall_seconds=100,estimated_cpu_seconds=50)
        value=m.verified_remaining_wall(Study(),'unsealed',self.c)
        self.assertEqual(value['estimated_remaining_wall_seconds'],100)
        self.assertEqual(value['elapsed_wall_credit'],0)
    def test_unknown_prefix_price_rejected(self):
        with self.assertRaises(RuntimeError):m.regional_prefix_priced({})
        self.assertFalse(m.regional_prefix_priced(dict(prefix_admitted=False)))
        self.assertTrue(m.regional_prefix_priced(dict(prefix_admitted=True)))
    def _admin_case(self):
        directory=self.runtime/'attempts/FI/attempt';directory.mkdir(parents=True)
        target=directory/'target.py';target.write_text('pass\n')
        proc=dict(pid=123,start_ticks=456,boot_id='boot')
        saved=dict(estimated_cpu_seconds=1200,kind='benchmark',unit='pricefm-r150-r152-x.service',task='__benchmark__',study='FI',
            lease_id='lease',attested=dict(InvocationID='inv'),source_head='resource',study_source_head='science',process=proc,
            policy_receipt=str(directory/'policy.json'),accounting_path=str(directory/'admin_accounting'))
        m.immutable(directory/'ownership.json',saved)
        m.immutable(Path(saved['policy_receipt']),dict(worker_invocation_id='inv',task='__benchmark__',source_head='science'))
        spec=dict(target_argv=['python','-B',str(target)],policy_receipt_path=saved['policy_receipt'])
        m.immutable(directory/'bootstrap_spec.json',spec)
        identity=dict(task='__benchmark__',unit=saved['unit'],lease_id='lease',invocation_id='inv',resource_source_head='resource',
            scientific_source_head='science',target_argv=spec['target_argv'],target_sha256=m.digest(target),bootstrap_spec_sha256=m.digest(directory/'bootstrap_spec.json'),
            process=proc,started_epoch=1)
        folder=Path(saved['accounting_path']);m.immutable(folder/'started.json',identity)
        observed=dict(identity,completed=True,observed_process_CPU_seconds=7,observed_terminated_children_CPU_seconds=3,
            observed_total_CPU_seconds=10,post_observation_exit_allowance_CPU_seconds=5.)
        return directory,saved,folder,observed
    def _publish_admin(self,saved,folder,observed):
        m.immutable(folder/'observed.json',observed)
        m.immutable(folder/'observed.seal.json',dict(sha256=m.digest(folder/'observed.json'),resource_source_head=saved['source_head'],unit=saved['unit'],invocation_id='inv'))
    def test_admin_raw_CPU_always_adds_five_second_tail(self):
        directory,saved,folder,value=self._admin_case();self._publish_admin(saved,folder,value)
        result=m.freeze_attempt_charge(directory/'ownership.json',saved,dict(cpu_seconds=0))
        self.assertEqual(result['charged_CPU_seconds'],15)
        self.assertTrue(result['verified_final_observation'])
    def test_copied_cross_attempt_admin_receipt_gets_no_credit(self):
        directory,saved,folder,value=self._admin_case();value['lease_id']='other';self._publish_admin(saved,folder,value)
        result=m.freeze_attempt_charge(directory/'ownership.json',saved,dict(cpu_seconds=0))
        self.assertEqual(result['charged_CPU_seconds'],1200)
        self.assertFalse(result['verified_final_observation'])
    def test_admin_wrong_process_lifetime_gets_no_credit(self):
        directory,saved,folder,value=self._admin_case();value['process']=dict(pid=124,start_ticks=1,boot_id='boot');self._publish_admin(saved,folder,value)
        result=m.freeze_attempt_charge(directory/'ownership.json',saved,dict(cpu_seconds=0))
        self.assertEqual(result['charged_CPU_seconds'],1200)
    def test_missing_attempt_cpu_retains_full_price(self):
        directory,saved,folder,value=self._admin_case()
        result=m.freeze_attempt_charge(directory/'ownership.json',saved,dict(cpu_seconds=2))
        self.assertEqual(result['charged_CPU_seconds'],1200)
    def test_admin_cpu_overrun_not_erased(self):
        directory,saved,folder,value=self._admin_case();self._publish_admin(saved,folder,value)
        result=m.freeze_attempt_charge(directory/'ownership.json',saved,dict(cpu_seconds=1300))
        self.assertEqual(result['charged_CPU_seconds'],1305)
    def test_partial_regional_receipt_does_not_earn_completed_packet_credit(self):
        directory,saved,folder,value=self._admin_case();saved['kind']='numerical';m.atomic(directory/'ownership.json',saved)
        class Study:
            def attempt_charge(self,saved):return dict(charged_CPU_seconds=9,verified_final_observation=False,prior_started_invocations=[],missing_prior_invocations=[])
            def task_complete(self,name):return True
        result=m.freeze_attempt_charge(directory/'ownership.json',saved,dict(cpu_seconds=0),Study())
        self.assertEqual(result['charged_CPU_seconds'],1200)
        self.assertFalse(result['verified_final_observation'])
    def test_control_duration_uses_stable_launch_bound_after_fractional_crossing(self):
        path=self.runtime/'control/intent.json'
        m.immutable(path,dict(unit='pricefm-r150-r152-test.service',source_head='new',runtime_seconds=10.9))
        class System:
            def unit(self,name):return dict(ActiveState='active',RuntimeMaxUSec='10s')
        with patch.object(m,'legacy',return_value=types.SimpleNamespace(verify_owned=lambda saved,props:None)),patch.object(m.time,'time',return_value=self.master['expires_epoch']-9.8):
            self.assertEqual(m.launch_duration(System(),path,'pricefm-r150-r152-test.service',self.master),10.9)
    def test_real_EE_worker_cli_uses_task_argument(self):
        study=m.EEStudy.__new__(m.EEStudy);study.c=self.c
        argv=study.command('task',24,'receipt')
        self.assertIn('--task',argv);self.assertNotIn('--name',argv)
        help_result=subprocess.run(argv[:4]+['--help'],capture_output=True,text=True)
        self.assertEqual(help_result.returncode,0,help_result.stderr)
        self.assertIn('--task',help_result.stdout)
    def test_real_bootstrap_entry_and_subcommand_exist(self):
        path=m.ROOT/'application/scripts/pricefm/508_bootstrap_pricefm_stage_r152_payload.py'
        self.assertTrue(path.is_file())
        result=subprocess.run([self.c['python_runtime'],'-B',str(path),'bootstrap','--help'],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr);self.assertIn('--spec',result.stdout)
        text=ENTRY.read_text()
        self.assertIn("str(bootstrap),'bootstrap','--spec'",text)
    def test_emitted_bootstrap_command_parses_actual_entry(self):
        path,lease=self.admission(study='FI')
        lease['expires_epoch']=m.time.time()+60;lease['started_epoch']=m.time.time()
        m.atomic(path,lease)
        captured=[]
        class Capture:
            def start(self,unit,description,argv,**kwargs):
                captured.append(argv);raise RuntimeError('test stops before any service operation')
            def unit(self,unit):return dict(Id=unit,LoadState='not-found',ActiveState='inactive',MainPID='0')
            def members(self,cgroup):return []
        controller=dict(unit='pricefm-r150-r152-control-test.service',attested=dict(InvocationID='parent',ControlGroup='/user.slice/user-test/control.service'))
        target=[self.c['python_runtime'],'-B',str(m.ROOT/'application/scripts/pricefm/508_bootstrap_pricefm_stage_r152_payload.py'),'probe-payload']
        with self.assertRaisesRegex(RuntimeError,'payload startup failed'):
            m.start_payload(Capture(),self.c,self.runtime/'attempts/FI',dict(name='__probe__',estimated_cpu_seconds=1),24,
                lease,controller,target,dict(root=str(m.ROOT),head='resource',sha256={}),
                'probe',master_path=self.shared/'master.json',admission_path=path,study='FI')
        self.assertEqual(len(captured),1)
        argv=captured[0];script=argv.index(str(m.ROOT/'application/scripts/pricefm/508_bootstrap_pricefm_stage_r152_payload.py'))
        self.assertEqual(argv[script+1:script+3],['bootstrap','--spec'])
        parsed=subprocess.run([self.c['python_runtime'],'-B',argv[script],argv[script+1],'--help'],capture_output=True,text=True)
        self.assertEqual(parsed.returncode,0,parsed.stderr)
    def test_commit_accepts_real_baseline_fields_without_duplicate_keyword(self):
        shared=self.shared/'fresh';shared.mkdir()
        owner=dict(pid=os.getpid(),start_ticks=1,boot_id='boot')
        fields=dict(baseline_owner=owner,baseline_runtime=str(shared/'baseline'),baseline_guardian_unit='guardian',
            host='test',boot_id='boot',partition=self.master['partition'])
        pending=dict(source=self.master['source'],scope_id='scope')
        with patch.object(m,'verify_source'),patch.object(m,'legacy',return_value=types.SimpleNamespace(process=lambda pid:owner)),patch.object(m,'boot',return_value='boot'):
            value=m.commit_master(pending,shared,fields,now=self.now)
            self.assertEqual(value['partition'],fields['partition'])
            self.assertEqual(value['expires_epoch'],self.now+43200)
            with self.assertRaises(RuntimeError):m.commit_master(pending,shared,fields,now=self.now+1)
    def test_joint_schedule_reserves_assessment_outside_compute_segment(self):
        jobs=[dict(study='EE',name='D',phase=0,estimated_cpu_seconds=10,estimated_wall_seconds=10),
            dict(study='EE',name='assessment',phase=2,kind='assessment_reserve',estimated_cpu_seconds=30,estimated_wall_seconds=30)]
        result=m.pack_joint(jobs,dict(EE=[dict(id='EE-C1',start=0,end=20,lease_end=60)]),now=0)
        self.assertTrue(result['fits'])
        self.assertEqual(next(row['end'] for row in result['allocation'] if row['name']=='assessment'),40)
    def test_numerical_task_event_accepts_estimate_with_name(self):
        class Study:
            study_id='FI'
            def estimate_task(self,name):return dict(name=name,estimated_cpu_seconds=1,estimated_wall_seconds=1)
            def worker_command(self,*args):return ['python','-B','target.py']
        path,lease=self.admission(study='FI')
        with patch.object(m,'start_payload',return_value=dict(unit='worker')),patch.object(m,'event') as logged:
            m.start_study_task(None,self.c,self.shared,self.runtime,self.master,{},Study(),'task',24,path,lease,'numerical','probe')
        self.assertEqual(logged.call_args.kwargs['payload_kind'],'numerical')
    def test_synthetic_daemon_FI_unfunded_benchmark_does_not_block_EE(self):
        clock=1001.;records=[];ticks=[0]
        class Study:
            def __init__(self,name):
                self.study_id=name;self.done=False;self.bench=False
                self.PREP=self_shared/'prep'/name;self.PREP.mkdir(parents=True)
                m.immutable(self.PREP/'preparation.json',dict(source=dict(head='science')))
            def queue_state(self):
                if self.study_id=='EE':
                    return dict(phase='READY_FOR_ASSESSMENT' if self.done else 'NOMINEE_SEED0',terminal=self.done,
                        ready=[] if self.done else [dict(name='EE_task_S_seed0',estimated_cpu_seconds=10,estimated_wall_seconds=10)],
                        complete=['EE_task_S_seed0'] if self.done else [],pending=[] if self.done else ['EE_task_S_seed0'],unfunded_pending=[])
                return dict(phase='DEFERRED_UNFUNDED_PREFIX' if self.bench else 'BENCHMARK',ready=[],complete=[],pending=[],terminal=self.bench)
            def advance(self,**kwargs):return self.queue_state()
            def complete_prefix(self):return self.done
            def task_complete(self,name):return self.done
            def pricing(self):return dict(prefix_admitted=False,task_estimates=dict(dummy=dict(estimated_cpu_seconds=1,estimated_wall_seconds=1)))
        self_shared=self.shared
        studies={name:Study(name) for name in ('EE','FI','DK2')}
        m.immutable(self.runtime/'prepared.json',dict(source=self.master['source']))
        m.immutable(self.shared/'orchestrator.json',dict(unit='pricefm-r150-r152-master-test.service'))
        class FakeSystem:
            def unit(self,name):return dict(LoadState='not-found',ActiveState='inactive',MainPID='0',Id=name)
            def members(self,group):return []
        def observe(*args,**kwargs):
            ticks[0]+=1
            if ticks[0]>100:raise RuntimeError('synthetic daemon failed to make its expected finite transitions')
            return dict(active=[],observations={row['unit']:dict(active=False,properties=dict(ExecMainStatus='0')) for _,row in records},global_charged_CPU_seconds=0,global_limit_CPU_seconds=100000)
        def projected(*args,**kwargs):
            return dict(fits=True,worst=dict(packing=dict(allocation=[dict(study='EE',name='EE_task_S_seed0',window_id='EE-C1',start=clock,cpu=24,active=False)])))
        def start(system,c,shared,runtime,master,controller,study,name,cpu,lease_path,lease,kind,probe):
            directory=runtime/'attempts'/study.study_id/str(len(records));directory.mkdir(parents=True)
            row=dict(unit='pricefm-r150-r152-test-'+str(len(records))+'.service',study=study.study_id,kind=kind,task=name,
                cpu=cpu,admission_path=str(lease_path),started_epoch=clock-100)
            path=directory/'ownership.json';m.immutable(path,row);records.append((path,row))
            if kind=='numerical':study.done=True
            if kind=='benchmark':study.bench=True
            if kind=='assessment':
                out=runtime/'assessments/EE';m.immutable(out/'assessment.json',dict(status='SCIENTIFIC_COMPLETE',scientific_complete=True))
            return row
        def finish(system,c,runtime,path,saved,study):
            m.immutable(path.parent/'finished.json',dict(cleanup=dict(drained=True)))
            return dict(charge=dict(live_or_unit_CPU_lower_bound=100),observation=dict(properties=dict(ExecMainStatus='0')))
        capsule=dict(unit='pricefm-r150-r152-broker-test.service')
        patches=[patch.object(m,'System',FakeSystem),patch.object(m,'EE_CANONICAL',self.shared/'old-canonical'),
            patch.object(m,'verify_source'),patch.object(m,'historical_bridge'),
            patch.object(m,'attest_self',return_value=capsule),patch.object(m,'launch_duration',return_value=43200),patch.object(m,'start_guardian',return_value=dict(unit='pricefm-r150-r152-guardian-test.service')),
            patch.object(m,'open_studies',return_value=studies),patch.object(m,'all_attempts',side_effect=lambda runtime:list(records)),
            patch.object(m,'live_guard',side_effect=observe),patch.object(m,'finish_worker',side_effect=finish),
            patch.object(m,'projection',side_effect=projected),patch.object(m,'study_source_and_prep',return_value=(dict(head='science'),'prep')),
            patch.object(m,'study_limit',return_value=21786),patch.object(m,'study_cpu_charge',return_value=(1085,[])),
            patch.object(m,'start_study_task',side_effect=start),patch.object(m,'free_slot',return_value=24),
            patch.object(m,'ee_gate',return_value=dict(proceed=False)),
            patch.object(m,'drain_scope',return_value=dict(cleanup_verified=True,cleanup_errors=[],cleanup=[],owned_pids=[],owned_units=[])),
            patch.object(m.time,'time',return_value=clock),patch.object(m.time,'sleep')]
        master=m.read(self.shared/'master.json');master['probe_sha256']='probe';m.atomic(self.shared/'master.json',master)
        with ExitStack() as stack:
            for item in patches:stack.enter_context(item)
            terminal=m.run(self.shared,unit=capsule['unit'])
        self.assertEqual(terminal['status'],'R152_FINITE_TRANCHE_DISPOSITION_SEALED',terminal.get('original_stop_reason'))
        self.assertEqual(m.study_terminal(self.runtime,'EE')['status'],'SCIENTIFIC_COMPLETE')
        self.assertEqual(m.study_terminal(self.runtime,'FI')['status'],'DEFERRED_PREFIX_UNFUNDED')
        self.assertEqual(m.admission_files(self.runtime,'FI','numerical'),[])
    def test_prepare_and_status_do_not_create_admissions(self):
        value=m.status(self.shared)
        self.assertEqual(value['stage'],'R152')
        self.assertFalse((self.runtime/'admissions').exists())


if __name__=='__main__':unittest.main()
