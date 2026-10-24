"""Focused FI/DK2 adapter protocol tests; no retained-data forecast or fit."""
import copy
import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT/'application/scripts/pricefm/506_screen_pricefm_stage_r152_region.py'
spec = importlib.util.spec_from_file_location('r152_region_tests', ENTRY)
M = importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)


class ScopeAndCohortTests(unittest.TestCase):
    def setUp(self):
        self.study = M.open_study('FI')
        self.config = copy.deepcopy(self.study.config())

    def test_import_and_adapter_construction_are_metadata_only(self):
        source = (
            'import importlib.util,sys;'
            f's=importlib.util.spec_from_file_location("adapter",{str(ENTRY)!r});'
            'm=importlib.util.module_from_spec(s);s.loader.exec_module(m);'
            'a=m.open_study("FI");b=m.open_study("DK2");'
            'assert a.study_id=="FI" and b.study_id=="DK2";'
            'assert not set(("numpy","scipy","pandas"))&set(sys.modules)'
        )
        subprocess.run([sys.executable, '-B', '-c', source], check=True, capture_output=True)

    def test_exact_package_counts_and_p961_cost_class(self):
        self.assertEqual(len(self.config['packages']), 20)
        self.assertEqual(len({p['candidate_id'] for p in self.config['packages']}), 19)
        self.assertEqual(max(p['p'] for p in self.config['packages']), 961)
        self.assertEqual(self.config['benchmark_D_packages'], self.config['benchmark_S_packages'])

    def test_scope_mutations_fail(self):
        changes = {'region':'EE', 'paths':500, 'new_model_fits':1, 'new_geometries':1,
                   'forecast_seed':1, 'benchmark_max_seconds':1201, 'max_numerical_waves':4,
                   'max_new_D_components':59, 'max_new_S_components':24,
                   'max_projected_cpu_seconds':64800, 'benchmark_preflight_included':False,
                   'official_evaluation_authorized':True, 'test_used_for_selection':True}
        for key,value in changes.items():
            with self.subTest(key=key):
                changed = copy.deepcopy(self.config); changed[key] = value
                with self.assertRaises(ValueError): M.validate_fi_config(changed)

    def test_control_scale_and_panel_cannot_be_removed(self):
        for change in ('control', 'alternate', 'panel'):
            changed = copy.deepcopy(self.config)
            if change == 'control': changed['packages'][0]['tau0'] *= 10
            elif change == 'alternate':
                next(p for p in changed['packages'] if p['package_id']=='C0_alt')['tau0'] *= 10
            else: changed['benchmark_S_packages'] = ['C0']
            with self.subTest(change=change), self.assertRaises(ValueError): M.validate_fi_config(changed)

    def test_fi_and_dk2_instances_do_not_mutate_frozen_globals(self):
        dk2 = M.open_study('DK2')
        reference = dk2.legacy_reference()
        old = (reference.TAG, reference.PREP, reference.OUT, reference.CONFIG)
        self.assertEqual(self.study.name_for('C0',1,'S',2), 'FI_C0_s1_S_seed2')
        self.assertEqual(dk2.name_for('C0',1,'S',2), 'DK_2_C0_s1_S_seed2')
        self.assertEqual((reference.TAG, reference.PREP, reference.OUT, reference.CONFIG), old)
        self.assertNotEqual(self.study.PREP, dk2.PREP)

    def test_own_940_origin_cohorts_exclude_last_day(self):
        start = dt.datetime(2022,2,4,tzinfo=dt.timezone.utc)
        anchors = [(start+dt.timedelta(days=i)).isoformat() for i in range(940)]
        boundaries = M.split_boundaries(self.config['split_helper'],940)
        self.assertEqual(tuple(boundaries), ((506,631),(631,766),(766,940)))
        for split,count in enumerate((124,134,173),1):
            cohort = M.cohort(anchors,boundaries,split,[0,24,48,72])
            self.assertEqual(len(cohort['daily_origin_positions']),count)
            self.assertLess(max(cohort['train_origin_positions']), min(cohort['validation_origin_positions']))
            self.assertEqual(max(cohort['daily_origin_positions'])+1,max(cohort['validation_origin_positions']))
            self.assertEqual(sum(map(len,cohort['origin_timestamps'].values())),4*count)
            first = dt.datetime.fromisoformat(cohort['origin_timestamps']['0'][0])
            for offset in (24,48,72):
                self.assertEqual(dt.datetime.fromisoformat(cohort['origin_timestamps'][str(offset)][0])-first,
                                 dt.timedelta(minutes=15*offset))

    def test_unicode_anchor_reader_rejects_duplicate_or_naive_days(self):
        def packet(values,path):
            width=max(map(len,values));header=repr({'descr':f'<U{width}','fortran_order':False,'shape':(len(values),)})
            header = header+' '*((16-(10+len(header)+1)%16)%16)+'\n'
            raw=b'\x93NUMPY\x01\x00'+struct.pack('<H',len(header))+header.encode()+b''.join(v.ljust(width,'\0').encode('utf-32-le') for v in values)
            with zipfile.ZipFile(path,'w') as z:z.writestr('anchors.npy',raw)
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'bank.npz'
            packet(['2023-03-12T00:00:00+00:00','2023-03-13T00:00:00+00:00'],path)
            self.assertEqual(len(M.bank_anchors(path)),2)
            for values in (['2023-03-12T00:00:00','2023-03-13T00:00:00'],
                           ['2023-03-12T00:00:00+00:00']*2):
                packet(values,path)
                with self.assertRaises(ValueError): M.bank_anchors(path)


class DecisionAndBudgetTests(unittest.TestCase):
    def setUp(self):
        self.study=M.open_study('FI');self.config=self.study.config()
        self.packages=self.config['packages'];self.ids=[p['package_id'] for p in self.packages]

    def test_nomination_requires_complete_finite_pool(self):
        losses={name:2. for name in self.ids}
        for invalid in (dict(list(losses.items())[:-1]),dict(losses, C0=float('nan'))):
            with self.assertRaises(ValueError):self.study.choose_nominees(self.packages,invalid,'C0',self.config['audit_key'])

    def test_alternate_control_can_be_A_B_excludes_whole_geometry(self):
        losses={name:2. for name in self.ids};losses['C0_alt']=1.
        decision=self.study.choose_nominees(self.packages,losses,'C0',self.config['audit_key'])
        self.assertEqual(decision['A'],'C0_alt')
        by={p['package_id']:p for p in self.packages}
        self.assertNotEqual(by[decision['B']]['candidate_id'],by['C0']['candidate_id'])
        shuffled=dict(reversed(list(losses.items())))
        self.assertEqual(decision,self.study.choose_nominees(self.packages,shuffled,'C0',self.config['audit_key']))

    def test_audit_nominee_order_is_keyed_not_loss_rank(self):
        noncontrol=[i for i in self.ids if i not in ('C0','C0_alt')]
        losses={name:3. for name in self.ids};losses[noncontrol[0]]=1.
        first=self.study.choose_nominees(self.packages,losses,'C0',self.config['audit_key'])
        losses[first['B']]=10000.
        second=self.study.choose_nominees(self.packages,losses,'C0',self.config['audit_key'])
        self.assertEqual(first['A'],second['A']);self.assertEqual(first['B'],second['B'])

    def test_prefix_prices_full_D_all_nominee_scenarios_and_reserve(self):
        tasks=self.study.names_for(self.ids,'D',[0])+self.study.names_for(self.ids,'S',[0,1,2])
        estimates={name:dict(estimated_cpu_seconds=1.) for name in tasks}
        prep=dict(packages=self.packages,control='C0')
        price=self.study.prefix_contract(prep,estimates,70.)
        self.assertEqual(price['D_CPU_seconds'],60.)
        self.assertEqual(price['worst_prefix_CPU_seconds'],70.)
        self.assertEqual(len(price['all_prospective_seed0_scenarios']),19)
        self.assertTrue(price['prefix_admitted'])
        self.assertFalse(self.study.prefix_contract(prep,estimates,69.999)['prefix_admitted'])

    def test_extra_seeds_are_atomic_for_zero_one_two_qualifiers(self):
        names=self.study.names_for(self.ids,'S',[1,2])
        price=dict(task_estimates={n:dict(estimated_cpu_seconds=1.) for n in names},
                   benchmark_adjusted_available_CPU_seconds=100.,replacement_reserve_CPU_seconds=1.)
        for qualifiers,count in (([],0),([self.ids[2]],12),([self.ids[2],self.ids[3]],18)):
            decision=self.study.extra_admission([],qualifiers,'C0',price,float(count),{})
            self.assertEqual(len(decision['required_extra_components']),count)
            self.assertEqual(len(decision['admitted_extra_components']),count)
            self.assertFalse(decision['unfunded_pending'])
            if count:
                denied=self.study.extra_admission([],qualifiers,'C0',price,count-.01,{})
                self.assertEqual(denied['admitted_extra_components'],[])
                self.assertEqual(len(denied['unfunded_pending']),count)

    def test_unknown_or_nonfinite_remaining_budget_rejected(self):
        for amount in (None,float('nan'),float('inf'),-1.):
            with self.subTest(amount=amount), self.assertRaises(ValueError):
                self.study.extra_admission([],[],'C0',{},amount,{})

    def test_all_charged_prefix_attempts_reduce_extra_budget(self):
        names=self.study.names_for(['C0',self.ids[2]],'S',[1,2])
        price=dict(task_estimates={n:dict(estimated_cpu_seconds=1.) for n in names},
                   benchmark_adjusted_available_CPU_seconds=25.,replacement_reserve_CPU_seconds=1.)
        d=self.study.extra_admission(['prefix'],[self.ids[2]],'C0',price,100.,{'prefix':dict(charged_CPU_seconds=13.)})
        self.assertEqual(d['remaining_CPU_seconds'],11.)
        self.assertEqual(len(d['unfunded_pending']),12)

    def test_final_practical_margin_uses_three_seed_control_mean(self):
        # Seed0's threshold would be0.10; three-seed control mean makes it0.30.
        result=self.study.producer().confirm_gains([10.,40.,40.],[9.8,39.8,39.8])
        self.assertAlmostEqual(result['practical_margin'],.3)
        self.assertFalse(result['eligible_for_AL_proposal'])
        stable=self.study.producer().confirm_gains([10.,10.,10.],[9.8,9.8,9.8])
        self.assertTrue(stable['eligible_for_AL_proposal'])
        unstable=self.study.producer().confirm_gains([10.,10.,10.],[9.,10.1,10.1])
        self.assertFalse(unstable['eligible_for_AL_proposal'])

    def test_nomination_barrier_does_not_open_from_partial_D(self):
        fakeprep=dict(packages=self.packages,control='C0')
        with mock.patch.object(self.study,'read_preparation',return_value=fakeprep), \
             mock.patch.object(self.study,'task_complete',side_effect=lambda n:n=='__benchmark__'), \
             mock.patch.object(self.study,'pricing',return_value={'prefix_admitted':True}):
            phase,names,unfunded,terminal=self.study.manifest_state()
        self.assertEqual(phase,'DETERMINISTIC_POOL');self.assertEqual(len(names),60)
        self.assertFalse(terminal);self.assertFalse(unfunded)


class AdmissionAndAssessmentTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.directory=Path(self.tmp.name);self.study=M.open_study('FI',prep_dir=self.directory/'prep',out_dir=self.directory/'out')
        self.prep=dict(source={'head':'science'})
        M.write(self.study.PREP/'preparation.json',self.prep)
        self.master_path=self.directory/'master.json'
        M.write(self.master_path,dict(scope_id='scope',start_epoch=100.,expires_epoch=43300.))
        self.lease_path=self.directory/'admission.json'

    def admission(self,identifier='FI-C1',seconds=7200.,start=200.):
        lease=dict(schema_version=1,study='FI',admission_id=identifier,lease_id='lease',
            started_epoch=start,expires_epoch=start+seconds,seconds=seconds,master_scope_id='scope',
            master_sha256=M.digest(self.master_path),source_head='execution',study_source_head='science',
            prep_sha256=M.digest(self.study.PREP/'preparation.json'),controller_unit='controller.service',nonrenewing=True)
        M.write(self.lease_path,lease)
        receipt=dict(admission_path=str(self.lease_path),admission_sha256=M.digest(self.lease_path),
            master_path=str(self.master_path),master_sha256=M.digest(self.master_path),lease_id='lease',
            resource_source_head='execution',controller_unit='controller.service',lease_expires_epoch=start+seconds)
        return lease,receipt

    def test_explicit_new_numerical_lease_bound_to_master(self):
        lease,receipt=self.admission()
        self.assertEqual(self.study.validate_worker_lease(receipt,self.prep,'FI_C0_s1_D_seed0',300.),lease)

    def test_expired_renewed_wrong_source_and_preparation_rejected(self):
        for key,value in (('study','DK2'),('study_source_head','other'),('prep_sha256','bad'),
                          ('master_scope_id','different'),('nonrenewing',False),('seconds',7201.)):
            lease,receipt=self.admission();lease[key]=value;M.write(self.lease_path,lease)
            receipt['admission_sha256']=M.digest(self.lease_path)
            with self.subTest(key=key),self.assertRaises(RuntimeError):
                self.study.validate_worker_lease(receipt,self.prep,'FI_C0_s1_D_seed0',300.)
        _,receipt=self.admission()
        with self.assertRaises(RuntimeError):self.study.validate_worker_lease(receipt,self.prep,'FI_C0_s1_D_seed0',7400.)

    def test_master_and_admission_cannot_start_independent_clocks(self):
        _,receipt=self.admission()
        M.write(self.master_path,dict(scope_id='scope',start_epoch=250.,expires_epoch=43450.))
        receipt['master_sha256']=M.digest(self.master_path)
        with self.assertRaises(RuntimeError):self.study.validate_worker_lease(receipt,self.prep,'FI_C0_s1_D_seed0',300.)

    def test_benchmark_cannot_release_scientific_component(self):
        _,receipt=self.admission('FI-B0',1200.)
        self.study.validate_worker_lease(receipt,self.prep,'__benchmark__',300.)
        with self.assertRaises(RuntimeError):self.study.validate_worker_lease(receipt,self.prep,'FI_C0_s1_D_seed0',300.)

    def test_assessment_requires_drained_parent_compute_and_containment(self):
        parent_path=self.directory/'parent.json'
        parent,receipt=self.admission();M.write(parent_path,parent)
        closed_path=self.directory/'compute_closed.json'
        closed=dict(lease_id='lease',study='FI',active_workers=[],closed_epoch=400.,numerical_dispatch_closed=True)
        M.write(closed_path,closed)
        lease,receipt=self.admission('FI-A0',1800.,start=500.)
        lease.update(parent_admission_path=str(parent_path),parent_admission_sha256=M.digest(parent_path),
            parent_lease_id='lease',compute_closed_path=str(closed_path),compute_closed_sha256=M.digest(closed_path))
        M.write(self.lease_path,lease);receipt['admission_sha256']=M.digest(self.lease_path)
        self.study.validate_worker_lease(receipt,self.prep,'__finalize__',600.)
        closed['active_workers']=['still-running'];M.write(closed_path,closed)
        lease['compute_closed_sha256']=M.digest(closed_path);M.write(self.lease_path,lease)
        receipt['admission_sha256']=M.digest(self.lease_path)
        with self.assertRaises(RuntimeError):self.study.validate_worker_lease(receipt,self.prep,'__finalize__',600.)

    def prefix_fixture(self, phase='MATCHED_MC_UNFUNDED_PENDING'):
        packages=self.study.config()['packages'];nominees=[packages[2]['package_id'],packages[3]['package_id']]
        prefix=self.study.names_for([p['package_id'] for p in packages],'D',[0])+self.study.names_for(['C0']+nominees,'S',[0])
        extras=self.study.names_for(['C0']+nominees,'S',[1,2])
        prep=dict(source={'head':'s'},region='FI',packages=packages,control='C0',source_sha256={},input_sha256={})
        class P:
            def read_npz(self,path):return {}
            def validate_arrays(self,*args):pass
            def metrics(self,arrays):return {'AQL':1.}
        self.study.read_preparation=lambda:prep;self.study.producer=lambda:P()
        self.study.manifest_state=lambda:(phase,prefix+extras,extras if phase=='MATCHED_MC_UNFUNDED_PENDING' else [],False)
        self.study.task_complete=lambda name:name in prefix
        self.study.task_by_name=lambda name,prep:dict(scaler_path=str(self.directory/'scaler.json'))
        decision=dict(qualified=nominees,required_extra_components=extras,
            unfunded_pending=extras if phase=='MATCHED_MC_UNFUNDED_PENDING' else [],
            admitted_extra_components=[] if phase=='MATCHED_MC_UNFUNDED_PENDING' else extras,
            atomic_qualified_set_admitted=phase!='MATCHED_MC_UNFUNDED_PENDING')
        self.study.read_decision=lambda name:dict(nominees=nominees) if name=='nominees' else decision
        self.study.execution_identity=lambda:dict(head='execution',branch='task')
        M.write(self.directory/'scaler.json',{})
        for name in prefix:M.write(self.study.OUT/'tasks_done'/name/'result.json',dict(metrics={'AQL':1.}))
        return prefix,extras,decision

    def test_clean_unfunded_extras_assessment_verifies_only_complete_prefix(self):
        self.prefix_fixture()
        result=self.study.finalize()
        self.assertFalse(result['scientific_complete'])
        self.assertTrue(result['all_D_and_matched_S0_complete'])
        self.assertTrue(result['entire_extra_set_unfunded_pending'])
        self.assertEqual(result['verified_components'],69)
        self.assertIsNone(result['conditional_AL_proposal'])

    def resource_fixture(self):
        prefix,extras,decision=self.prefix_fixture('MATCHED_FULL_MC')
        _,receipt=self.admission('FI-A0',1800.,start=500.)
        runtime=self.master_path.parent/'development'
        resource=runtime/'studies/FI/extras_resource_admission.json'
        M.write(resource,dict(admitted=False,components=extras,epoch=450.,projection_sha256='projection'))
        request=runtime/'studies/FI/assessment_request.json'
        M.write(request,dict(active_workers=[],cleanup_preassessment_verified=True,
            entire_extra_set_unfunded_pending=True,unfunded_components=extras,
            resource_disposition_path=str(resource),resource_disposition_sha256=M.digest(resource)))
        lease=M.read(self.lease_path)
        lease.update(assessment_request_path=str(request),assessment_request_sha256=M.digest(request))
        M.write(self.lease_path,lease);receipt['admission_sha256']=M.digest(self.lease_path)
        return receipt,resource,request,extras,decision

    def test_resource_only_deferral_preserves_scientific_extra_decision(self):
        receipt,_,_,extras,decision=self.resource_fixture()
        disposition=self.study.resource_budget_disposition(receipt)
        guard=mock.Mock()
        result=self.study.finalize(disposition,guard=guard)
        self.assertFalse(result['scientific_complete'])
        self.assertEqual(result['verified_components'],69)
        self.assertTrue(result['entire_extra_set_unfunded_pending'])
        self.assertIsNone(result['conditional_AL_proposal'])
        self.assertEqual(result['extra_seed_decision'],decision)
        self.assertTrue(result['extra_seed_decision']['atomic_qualified_set_admitted'])
        self.assertEqual(result['resource_extra_seed_disposition']['components'],extras)
        self.assertEqual(guard.call_count,70)

    def test_resource_deferral_rejects_partial_set_or_attempt_evidence(self):
        receipt,resource,request,extras,_=self.resource_fixture()
        original=M.read(resource);r=M.read(request)
        M.write(resource,dict(original,components=extras[:-1]))
        M.write(request,dict(r,resource_disposition_sha256=M.digest(resource)))
        lease=M.read(self.lease_path);lease['assessment_request_sha256']=M.digest(request);M.write(self.lease_path,lease)
        receipt['admission_sha256']=M.digest(self.lease_path)
        with self.assertRaises(RuntimeError):self.study.resource_budget_disposition(receipt)
        M.write(resource,original);M.write(request,r)
        lease['assessment_request_sha256']=M.digest(request);M.write(self.lease_path,lease)
        receipt['admission_sha256']=M.digest(self.lease_path)
        started=self.study.OUT/'cpu_accounting'/extras[0]/'invocation'/'started.json'
        M.write(started,{})
        with self.assertRaises(RuntimeError):self.study.resource_budget_disposition(receipt)
        started.unlink();started.parent.rmdir();started.parent.parent.rmdir()
        owned=self.master_path.parent/'development/attempts/FI/intent/ownership.json'
        M.write(owned,dict(task=extras[0]))
        with self.assertRaises(RuntimeError):self.study.resource_budget_disposition(receipt)

    def test_resource_assessment_request_requires_owned_pin_and_cleanup(self):
        receipt,_,request,_,_=self.resource_fixture()
        value=M.read(request);M.write(request,dict(value,cleanup_preassessment_verified=False))
        with self.assertRaises(RuntimeError):self.study.resource_budget_disposition(receipt)
        lease=M.read(self.lease_path);lease['assessment_request_sha256']=M.digest(request);M.write(self.lease_path,lease)
        receipt['admission_sha256']=M.digest(self.lease_path)
        with self.assertRaises(RuntimeError):self.study.resource_budget_disposition(receipt)
        M.write(request,value);lease['assessment_request_path']=str(request.with_name('other.json'))
        lease['assessment_request_sha256']=M.digest(request);M.write(self.lease_path,lease)
        receipt['admission_sha256']=M.digest(self.lease_path)
        with self.assertRaises(RuntimeError):self.study.resource_budget_disposition(receipt)

    def test_partial_D_or_S0_cannot_be_called_clean_budget_disposition(self):
        self.study.read_preparation=lambda:dict(source={},source_sha256={},input_sha256={},packages=self.study.config()['packages'],control='C0')
        self.study.manifest_state=lambda:('MATCHED_MC_UNFUNDED_PENDING',['partial'],['missing-extra'],False)
        self.study.producer=lambda:object();self.study.read_decision=lambda name:dict(nominees=['a','b'])
        with self.assertRaises(RuntimeError):self.study.finalize()


class OwnedBenchmarkTests(unittest.TestCase):
    """Synthetic moment/prediction fixtures only; never retained-data forecasts."""
    def test_moment_preflight_rejects_invalid_covariance_before_ranking(self):
        import numpy as np
        study=M.open_study('FI')
        prep=dict(packages=[{'package_id':'fixture'}])
        study.task_by_name=lambda name,prep:dict(p=2,parent_task=name,scaler_sha256='fixture')
        receipt={'lease_expires_epoch':M.time.time()+1000}
        class Producer:
            def numerical_context(self,prep,task):return {'fit':self.fit}
        producer=Producer();study.producer=lambda:producer
        producer.fit=dict(beta_mean=np.zeros(2),beta_cov=np.eye(2),omega_shape=2.,omega_rate=1.)
        result=study.numeric_preflight(prep,receipt,lambda event:None)
        self.assertEqual(result['parents'],3)
        for covariance in (np.diag([1.,-1.]),np.array([[1.,2.],[0.,1.]]),np.array([[1.,0.],[0.,float('nan')]])):
            producer.fit['beta_cov']=covariance
            with self.assertRaises(RuntimeError):study.numeric_preflight(prep,receipt,lambda event:None)

    def test_benchmark_runs_one_preflight_and_18_prediction_calls_without_loss(self):
        import numpy as np
        with tempfile.TemporaryDirectory() as folder:
            study=M.open_study('FI',prep_dir=Path(folder)/'prep',out_dir=Path(folder)/'out')
            prep=dict(source={'head':'fixture'},packages=study.config()['packages'],control='C0',tasks=[])
            M.write(study.PREP/'preparation.json',prep)
            receipt_path=Path(folder)/'policy.json';M.write(receipt_path,dict(lease_expires_epoch=M.time.time()+1000))
            events=[];prediction_calls=[];replay_calls=[];loss_flags=[]
            study.guard=lambda *args:None
            study.numeric_preflight=lambda *args:events.append('preflight') or {'parents':60}
            packages={p['package_id']:p for p in study.config()['packages']}
            def task(name,prep):
                package=next(p for pid,p in packages.items() if name==study.name_for(pid,3,'D',0) or name==study.name_for(pid,3,'S',0))
                return dict(package_id=package['package_id'],p=package['p'],spec=package['spec'],mode='_S_' in name and 'S' or 'D')
            study.task_by_name=task
            def predict(context,task,descriptor,beat):
                self.assertEqual(events[0],'preflight')
                prediction_calls.append((task['package_id'],task['mode']))
                return np.ones((1,96,7)),np.ones((1,96)),{'fixture':True}
            study.predict=predict
            study.legacy_control_replay=lambda *args:replay_calls.append(1) or {'fixture_replay':True}
            study.validate_worker_lease=lambda *args:{'started_epoch':M.time.time()-1}
            study.prefix_contract=lambda prep,estimates,available:dict(prefix_admitted=True,replacement_reserve_CPU_seconds=1.)
            class Producer:
                def numerical_context(self,*args):return {}
                def chunks(self,task):return [{'origin_positions':[0],'clock_offset_steps':0}]
                def retained_arrays(self,context,task,descriptor,prediction,truth,compute_loss=True):
                    loss_flags.append(compute_loss)
                    return {'prediction':prediction,'truth':truth,'origin_AQL':np.zeros(1)}
                def numerical_threadpools(self):return [{'num_threads':1}]
                def kernel(self):return self
                def prospective_costs(self,*args):
                    return {'task_estimates':{'fixture':dict(estimated_max_chunk_wall_seconds=1.)}}
                def metrics(self,*args):raise AssertionError('benchmark may not compute a candidate loss')
            study.producer=lambda:Producer()
            result=study.benchmark(prep,29,receipt_path,0.)
            self.assertEqual(events,['preflight'])
            self.assertEqual(len(prediction_calls),16)
            self.assertEqual(len(replay_calls),2)
            self.assertEqual(loss_flags,[False]*16)
            timings=M.read(study.OUT/'benchmark/timings.json')
            self.assertEqual(timings['arithmetic_calls'],18)
            self.assertEqual(timings['timed_prediction_calls'],16)
            self.assertEqual(timings['numerical_preflight']['parents'],60)
            self.assertTrue(result['no_new_candidate_AQL_inspected'])


class PerInvocationCPUAccountingTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.folder=Path(self.tmp.name)
        self.study=M.open_study('FI',prep_dir=self.folder/'prep',out_dir=self.folder/'out')
        self.name='FI_C0_s1_D_seed0';self.invocation='a'*32
        self.prep=dict(source={'head':'science'})
        self.study.read_preparation=lambda:self.prep
        self.study.task_by_name=lambda name,prep:dict(scientific_identity_sha256='scientific-identity')
        self.study.pricing=lambda:dict(task_estimates={self.name:dict(estimated_cpu_seconds=100.)})
        self.study.task_complete=lambda name:True
        self.policy_path=self.folder/'policy.json'
        self.policy=dict(stage='R152',task=self.name,source_head='science',resource_source_head='execution',
            worker_invocation_id=self.invocation,unit='owned.service',lease_id='lease',cpu=29,worker_cgroup='/owned')
        M.write(self.policy_path,self.policy)
        self.saved=dict(task=self.name,study='FI',study_source_head='science',source_head='execution',
            unit='owned.service',cpu=29,lease_id='lease',policy_receipt=str(self.policy_path),
            attested=dict(InvocationID=self.invocation,ControlGroup='/owned'))
        self.cpu=self.study.OUT/'cpu_accounting'/self.name/self.invocation
        self.started=dict(source=self.prep['source'],task=self.name,
            scientific_identity_sha256='scientific-identity',policy_invocation_id=self.invocation,
            policy_receipt_path=str(self.policy_path),policy_receipt_sha256=M.digest(self.policy_path),
            prior_started_invocations=[],preexisting_checkpoint_count=0)
        M.write(self.study.OUT/'tasks_done'/self.name/'completed_evidence.json',{'final':'seal'})
        self.observed=dict(self.started,completed_component=True,observed_process_CPU_seconds=2.,
            observed_terminated_children_CPU_seconds=1.,observed_total_CPU_seconds=3.,
            post_observation_exit_allowance_CPU_seconds=5.,hard_CPU_quota=False,exact_exit_CPU_measurement=False,
            task_final_seal_sha256=M.digest(self.study.OUT/'tasks_done'/self.name/'completed_evidence.json'))
        self.save()

    def save(self):
        M.write(self.cpu/'started.json',self.started)
        M.write(self.cpu/'observed.json',self.observed)
        M.write(self.cpu/'observed.seal.json',dict(sha256=M.digest(self.cpu/'observed.json'),source=self.prep['source']))

    def test_exact_final_attempt_earns_only_its_own_observed_CPU_plus_exit_tail(self):
        result=self.study.attempt_charge(self.saved)
        self.assertEqual(result['charged_CPU_seconds'],8.)
        self.assertTrue(result['verified_final_observation'])
        self.assertEqual(result['scope'],'ONE_OWNED_INVOCATION_ONLY')

    def test_past_attempts_are_exposed_for_reconciliation_not_added_again(self):
        prior='b'*32;self.started['prior_started_invocations']=[prior]
        self.observed.update(self.started);self.save()
        result=self.study.attempt_charge(self.saved)
        self.assertEqual(result['charged_CPU_seconds'],8.)
        self.assertEqual(result['prior_started_invocations'],[prior])
        self.assertEqual(result['missing_prior_invocations'],[prior])
        M.write(self.cpu.parent/prior/'started.json',{'old':True})
        self.assertEqual(self.study.attempt_charge(self.saved)['missing_prior_invocations'],[])

    def test_partial_or_missing_receipt_keeps_full_frozen_price(self):
        self.observed['completed_component']=False;self.save()
        result=self.study.attempt_charge(self.saved)
        self.assertEqual(result['charged_CPU_seconds'],100.)
        self.assertFalse(result['verified_final_observation'])
        (self.cpu/'observed.json').unlink()
        self.assertEqual(self.study.attempt_charge(self.saved)['charged_CPU_seconds'],100.)

    def test_self_consistent_tampered_invocation_or_source_cannot_earn_credit(self):
        for key,value in (('worker_invocation_id','c'*32),('unit','other.service'),
                          ('source_head','other-science'),('lease_id','other-lease')):
            with self.subTest(key=key):
                policy=dict(self.policy);policy[key]=value;M.write(self.policy_path,policy)
                self.started['policy_receipt_sha256']=M.digest(self.policy_path)
                self.observed.update(self.started);self.save()
                result=self.study.attempt_charge(self.saved)
                self.assertEqual(result['charged_CPU_seconds'],100.)
                self.assertFalse(result['verified_final_observation'])

    def test_invalid_total_final_seal_or_attempt_backlink_cannot_earn_credit(self):
        original=copy.deepcopy(self.observed)
        for key,value in (('observed_total_CPU_seconds',.5),('task_final_seal_sha256','wrong'),
                          ('scientific_identity_sha256','other-target')):
            with self.subTest(key=key):
                self.observed=copy.deepcopy(original);self.observed[key]=value;self.save()
                result=self.study.attempt_charge(self.saved)
                self.assertEqual(result['charged_CPU_seconds'],100.)
                self.assertFalse(result['verified_final_observation'])


if __name__=='__main__':unittest.main()
