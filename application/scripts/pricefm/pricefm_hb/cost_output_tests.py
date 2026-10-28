"""Strict COST_ONLY publication contract with opaque fake protocol files.

No retained numerical packet is deserialized and no model or scheduler is used.
Tampering tests reseal changed JSON deliberately, to exercise scientific
protocol predicates independently from the outer transport hashes.
"""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

from . import lifecycle as l, registry as r, cost_control

ORIGINAL_PLAN=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_hb_scientific_preparation_20261027/benchmark_plans/FI_COST_PANEL_NOT_ADMITTED.json')


class CostOutputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.original_plan=r.read(ORIGINAL_PLAN)

    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.release_root=self.root/'release';self.release_root.mkdir()
        self.outputs=self.root/'outputs';self.outputs.mkdir();self.plan=copy.deepcopy(self.original_plan)
        r.write(self.release_root/'plan.json',self.plan)
        self.release={'schema':l.RELEASE_SCHEMA,'purpose':'COST_ONLY','study':'FI','scope_id':'r157-fi-test',
            'plan_sha256':r.digest(self.release_root/'plan.json'),'task_key':'operational-key'}
        r.write(self.release_root/'release.json',self.release)
        self.claim={'task_key':'legacy-key','operational_task_key':'operational-key','job_id':'123',
            'authority_sha256':'b'*64,'scope_id':self.release['scope_id'],'release_path':str(self.release_root)}
        relative=Path('BENCHMARK_TEST/FI')/self.plan['canonical_preparation']['sha256'][:16]/self.release['scope_id']
        self.panel=self.outputs/relative;self.panel.mkdir(parents=True)
        execution={'plan_sha256':self.release['plan_sha256'],'authority_sha256':self.claim['authority_sha256'],
            'scope_id':self.claim['scope_id'],'namespace':'BENCHMARK_TEST','full_prefix_admitted':False,
            'scientific_exclusion_key':self.plan['claim']['scientific_exclusion_key'],
            'allocation':{'job_id':'123','node':'node-12','cpus_per_task':1,'affinity':[2]}}
        rows=[]
        for call in self.plan['schedule']:
            if call['kind']!='timed_prediction':continue
            name=call['serialization']['retained_packet'];path=self.panel/name
            path.write_bytes(b'OPAQUE TEST FILE; NO NUMERICAL ARRAY\n')
            rows.append({**{k:call[k] for k in ('mode','package_id','repetition','p')},'split':3,'clock_offset_steps':0,
                'origin_count':8,'retained_prediction_packet':name,'retained_prediction_sha256':r.digest(path),
                'compressed_bytes':path.stat().st_size,'numerical_threadpools':[{'num_threads':1}],
                'cold_context_cpu_seconds':.1,'arithmetic_cpu_seconds':.1,'serialization_cpu_seconds':.1})
        self.result={'status':'COMPLETE_COST_ONLY_18_CALL_PANEL_NO_SELECTION_NO_ADMISSION','execution':execution,
            'arithmetic_calls':18,'timed_prediction_calls':16,'untimed_control_replay_prediction_calls':2,'rows':rows,
            'calls':[{k:v[k] for k in ('sequence','kind','task')} for v in self.plan['schedule']],
            'no_new_candidate_AQL_computed':True,'no_scientific_selection':True,'full_prefix_admitted':False,
            'prefix_pricing_performed':False,'automatic_retry':False,'new_model_fits':0,'official_origins':0,
            'process_CPU_seconds':10.,'aggregate_CPU_seconds':10.5,'elapsed_seconds':11.,'startup_cpu_seconds':1.,
            'numerical_preflight':{'parents':60}}
        self.outer_extra={};self.flush()

    def flush(self,*,sync_identity=True):
        r.write(self.panel/'timings.json',self.result)
        if sync_identity:r.write(self.panel/'execution_identity.json',self.result['execution'])
        artifacts={str(q.relative_to(self.panel)):r.digest(q) for q in self.panel.rglob('*')
            if q.is_file() and q!=self.panel/'completed_evidence.json'}
        r.write(self.panel/'completed_evidence.json',{'status':'COMPLETE_COST_PANEL_ONLY_NO_SCIENCE_ADMISSION',
            'execution':self.result['execution'],'artifacts':artifacts})
        files={str(q.relative_to(self.outputs)):r.digest(q) for q in self.outputs.rglob('*')
            if q.is_file() and q!=self.outputs/'worker_evidence.json'}
        r.write(self.outputs/'worker_evidence.json',{'schema':l.SCHEMA,'task_key':'operational-key',
            'release_sha256':r.digest(self.release_root/'release.json'),'job_id':'123',
            'authority_sha256':self.claim['authority_sha256'],'new_model_fits':0,'official_origins':0,
            'application_passed':True,'full_prefix_admitted':False,'files':files,**self.outer_extra})

    def rejects(self):
        with self.assertRaises((ValueError,OSError)):l.validate_cost_outputs(self.outputs,self.claim,self.release)

    def test_real_original18_call_metadata_and_all_opaque_packets_accept(self):
        self.assertTrue(l.validate_cost_outputs(self.outputs,self.claim,self.release))
        self.assertTrue(cost_control.validate_results(self.outputs,self.claim,self.release))
        self.assertNotIn('numpy',sys.modules);self.assertNotIn('scipy',sys.modules)

    def test_failed_application_is_not_accepted(self):
        self.outer_extra['application_passed']=False;self.flush()
        self.assertFalse(l.validate_cost_outputs(self.outputs,self.claim,self.release))

    def test_other_purpose_does_not_use_cost_acceptance(self):
        self.release['purpose']='CONTROL_TEST';self.rejects()

    def test_outer_seal_cannot_admit_prefix(self):
        self.outer_extra['full_prefix_admitted']=True;self.flush();self.rejects()

    def test_outer_identity_cannot_be_changed_even_if_all_files_reseal(self):
        self.outer_extra['task_key']='other';self.flush();self.rejects()

    def test_execution_scope_predicates_survive_resealing(self):
        base=copy.deepcopy(self.result)
        for key,value in [('namespace','PREFIX_TRAINING'),('full_prefix_admitted',True),
                ('scientific_exclusion_key','other'),('plan_sha256','c'*64),('scope_id','other'),('authority_sha256','c'*64)]:
            with self.subTest(key=key):
                self.result=copy.deepcopy(base);self.result['execution'][key]=value;self.flush();self.rejects()

    def test_one_actual_cpu_and_single_affinity_are_required(self):
        base=copy.deepcopy(self.result)
        for field,value in [('job_id','other'),('cpus_per_task',2),('affinity',[]),('affinity',[1,2])]:
            with self.subTest(field=field,value=value):
                self.result=copy.deepcopy(base);self.result['execution']['allocation'][field]=value;self.flush();self.rejects()

    def test_result_cannot_claim_selection_pricing_retry_fit_or_official_work(self):
        base=copy.deepcopy(self.result)
        for field,value in [('no_new_candidate_AQL_computed',False),('no_scientific_selection',False),
                ('prefix_pricing_performed',True),('automatic_retry',True),('full_prefix_admitted',True),
                ('new_model_fits',1),('official_origins',1)]:
            with self.subTest(field=field):
                self.result=copy.deepcopy(base);self.result[field]=value;self.flush();self.rejects()

    def test_all_finite_panel_cpu_and_wall_limits_are_required(self):
        base=copy.deepcopy(self.result)
        for field in ('process_CPU_seconds','aggregate_CPU_seconds','elapsed_seconds','startup_cpu_seconds'):
            for value in (-.1,1200.1,True,'10'):
                with self.subTest(field=field,value=value):
                    self.result=copy.deepcopy(base);self.result[field]=value;self.flush();self.rejects()

    def test_nonfinite_json_cannot_be_a_cost_result(self):
        self.result['elapsed_seconds']=float('nan')
        (self.panel/'timings.json').write_text(json.dumps(self.result))
        # Transport sealing may hash arbitrary bytes; JSON acceptance rejects it.
        files={str(q.relative_to(self.outputs)):r.digest(q) for q in self.outputs.rglob('*')
            if q.is_file() and q!=self.outputs/'worker_evidence.json'}
        outer=r.read(self.outputs/'worker_evidence.json');outer['files']=files;r.write(self.outputs/'worker_evidence.json',outer)
        self.rejects()

    def test_exact_startup_measurement_is_mandatory_and_consistent(self):
        base=copy.deepcopy(self.result)
        for change in ('missing','after_process','process_after_aggregate'):
            with self.subTest(change=change):
                self.result=copy.deepcopy(base)
                if change=='missing':del self.result['startup_cpu_seconds']
                elif change=='after_process':self.result['startup_cpu_seconds']=10.1
                else:self.result['process_CPU_seconds']=11.
                self.flush();self.rejects()

    def test_all18_exact_calls_include_both_immediate_control_replays(self):
        self.result['calls'].pop(1);self.flush();self.rejects()

    def test_call_order_cannot_be_changed(self):
        self.result['calls'][0],self.result['calls'][1]=self.result['calls'][1],self.result['calls'][0]
        self.flush();self.rejects()

    def test_entire16_row_panel_is_required(self):
        self.result['rows'].pop();self.flush();self.rejects()

    def test_timed_row_package_mode_repetition_and_quantile_are_exact(self):
        base=copy.deepcopy(self.result)
        for field,value in [('mode','other'),('package_id','other'),('repetition',99),('p',.99)]:
            with self.subTest(field=field):
                self.result=copy.deepcopy(base);self.result['rows'][0][field]=value;self.flush();self.rejects()

    def test_original_first_eight_midnight_split3_cohort_is_required(self):
        base=copy.deepcopy(self.result)
        for field,value in [('split',2),('clock_offset_steps',24),('origin_count',7)]:
            with self.subTest(field=field):
                self.result=copy.deepcopy(base);self.result['rows'][0][field]=value;self.flush();self.rejects()

    def test_own_region_all_parent_preflight_is_required(self):
        self.result['numerical_preflight']['parents']=63;self.flush();self.rejects()

    def test_standalone_execution_record_must_equal_result_execution(self):
        other=dict(self.result['execution'],namespace='other');r.write(self.panel/'execution_identity.json',other)
        self.flush(sync_identity=False);self.rejects()

    def test_resealed_extra_packet_cannot_expand_inner_membership(self):
        (self.panel/'extra.npz').write_bytes(b'opaque');self.flush();self.rejects()

    def test_missing_retained_packet_is_not_complete(self):
        (self.panel/self.result['rows'][0]['retained_prediction_packet']).unlink();self.flush();self.rejects()

    def test_wrong_retained_packet_row_name_is_rejected(self):
        self.result['rows'][0]['retained_prediction_packet']='other.npz';self.flush();self.rejects()

    def test_retained_row_hash_must_equal_both_sealed_and_actual_packet(self):
        self.result['rows'][0]['retained_prediction_sha256']='c'*64;self.flush();self.rejects()

    def test_compressed_bytes_are_positive_exact_integer(self):
        base=copy.deepcopy(self.result)
        for value in (0,-1,True,float(base['rows'][0]['compressed_bytes']),base['rows'][0]['compressed_bytes']+1):
            with self.subTest(value=value):
                self.result=copy.deepcopy(base);self.result['rows'][0]['compressed_bytes']=value;self.flush();self.rejects()

    def test_actual_numerical_pools_must_be_present_and_single_thread(self):
        base=copy.deepcopy(self.result)
        for value in ([],[{'num_threads':2}],[{'num_threads':True}],[{}]):
            with self.subTest(value=value):
                self.result=copy.deepcopy(base);self.result['rows'][0]['numerical_threadpools']=value;self.flush();self.rejects()

    def test_complete_task_pricing_cpu_measurements_are_finite_nonnegative(self):
        base=copy.deepcopy(self.result)
        for field in ('cold_context_cpu_seconds','arithmetic_cpu_seconds','serialization_cpu_seconds'):
            with self.subTest(field=field):
                self.result=copy.deepcopy(base);self.result['rows'][0][field]=-.1;self.flush();self.rejects()

    def test_plan_requires16_unique_basename_npz_packets(self):
        timed=[v for v in self.plan['schedule'] if v['kind']=='timed_prediction']
        timed[1]['serialization']['retained_packet']=timed[0]['serialization']['retained_packet']
        r.write(self.release_root/'plan.json',self.plan);self.rejects()

    def test_plan_cannot_turn_on_loss_computation(self):
        next(v for v in self.plan['schedule'] if v['kind']=='timed_prediction')['serialization']['compute_loss']=True
        r.write(self.release_root/'plan.json',self.plan);self.rejects()

    def test_plan_replay_must_immediately_follow_its_first_C0_call(self):
        next(v for v in self.plan['schedule'] if v['kind']=='control_replay')['reference_to_prediction_sequence']=99
        r.write(self.release_root/'plan.json',self.plan);self.rejects()


if __name__=='__main__':unittest.main()
